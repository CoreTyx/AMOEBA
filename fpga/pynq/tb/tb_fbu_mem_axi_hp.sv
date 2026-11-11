///////////////////////////////////////////////////////////////////////////////
// tb_fbu_mem_axi_hp.sv -- fbu_mem_axi_hp against an AXI3 slave model with
// random ready and latency (make -C fpga/pynq test-mem-axi-hp).
//
// The model applies a write to its memory only when it sends B, after a
// random delay, so a read issued before the write's B reads stale data and
// the check fails.  Some lines answer SLVERR.  The driver behaves as the link
// slave does: writes back to back, a read waits for its line.  Checked:
// every read's data against program order, poison and rsp_err on bad lines
// and outside EXT_MEM, the AXI fields, no response for a read the chip reset
// interrupted, and the status counters.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module tb_fbu_mem_axi_hp;

  localparam int          BEATS        = 2;
  localparam int          LINE_W       = 64 * BEATS;
  localparam int          LINES        = 64;
  localparam int          TRANSACTIONS = 20000;
  localparam logic [31:0] CARVEOUT     = 32'h1000_0000;
  localparam logic [63:0] POISON       = 64'hBAAD_C0DE_DEAD_BEEF;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic arst_n = 1'b0;
  logic chip_in_reset = 1'b0;

  logic              req_valid = 1'b0;
  logic              req_ready;
  logic              req_wr = 1'b0;
  logic [31:0]       req_addr = '0;
  logic [LINE_W-1:0] req_data = '0;
  logic              rsp_valid;
  logic [LINE_W-1:0] rsp_data;
  logic              rsp_err;

  logic [5:0]  awid;
  logic [31:0] awaddr;
  logic [3:0]  awlen;
  logic [2:0]  awsize;
  logic [1:0]  awburst;
  logic [1:0]  awlock;
  logic [3:0]  awcache;
  logic [2:0]  awprot;
  logic [3:0]  awqos;
  logic        awvalid;
  logic        awready = 1'b0;
  logic [5:0]  wid;
  logic [63:0] wdata;
  logic [7:0]  wstrb;
  logic        wlast;
  logic        wvalid;
  logic        wready = 1'b0;
  logic [1:0]  bresp = '0;
  logic        bvalid = 1'b0;
  logic        bready;
  logic [5:0]  arid;
  logic [31:0] araddr;
  logic [3:0]  arlen;
  logic [2:0]  arsize;
  logic [1:0]  arburst;
  logic [1:0]  arlock;
  logic [3:0]  arcache;
  logic [2:0]  arprot;
  logic [3:0]  arqos;
  logic        arvalid;
  logic        arready = 1'b0;
  logic [63:0] rdata = '0;
  logic [1:0]  rresp = '0;
  logic        rlast = 1'b0;
  logic        rvalid = 1'b0;
  logic        rready;

  logic        mem_err;
  logic [31:0] first_err_addr;
  logic [1:0]  first_err_resp;
  logic [31:0] reads;
  logic [31:0] writes;
  logic [31:0] dropped_writes;
  logic [15:0] read_latency_max;
  logic [47:0] read_latency_sum;
  logic [7:0][31:0] read_latency_hist;

  fbu_mem_axi_hp #(.BEATS(BEATS), .DDR_CARVEOUT(CARVEOUT)) dut (
    .clk, .arst_n, .chip_in_reset,
    .req_valid, .req_ready, .req_wr, .req_addr, .req_data,
    .rsp_valid, .rsp_data, .rsp_err,
    .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache),
    .m_axi_awprot(awprot), .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
    .m_axi_wid(wid), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
    .m_axi_wvalid(wvalid), .m_axi_wready(wready),
    .m_axi_bid(6'd0), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
    .m_axi_arid(arid), .m_axi_araddr(araddr), .m_axi_arlen(arlen), .m_axi_arsize(arsize),
    .m_axi_arburst(arburst), .m_axi_arlock(arlock), .m_axi_arcache(arcache),
    .m_axi_arprot(arprot), .m_axi_arqos(arqos), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
    .m_axi_rid(6'd0), .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rlast(rlast),
    .m_axi_rvalid(rvalid), .m_axi_rready(rready),
    .mem_err, .first_err_addr, .first_err_resp, .reads, .writes, .dropped_writes,
    .read_latency_max, .read_latency_sum, .read_latency_hist);

  int errors = 0;

  task automatic fail(input string what);
    errors++;
    if (errors <= 20)
      $display("[MEM_AXI_TB] %0t: %s", $time, what);
  endtask

  // ---- the slave model ----
  logic [63:0] ddr [logic [31:0]];

  function automatic logic [63:0] unwritten(input logic [31:0] a);
    return {a, ~a};
  endfunction

  function automatic logic [63:0] ddr_word(input logic [31:0] a);
    return ddr.exists(a) ? ddr[a] : unwritten(a);
  endfunction

  function automatic bit bad_line(input logic [31:0] ddr_addr);
    return ddr_addr[9:4] == 6'd13;
  endfunction

  logic [31:0] aw_queue [$];
  logic [63:0] w_beats [$];
  typedef struct { logic [31:0] addr; logic [63:0] data [BEATS]; int due; } pending_write_t;
  pending_write_t b_queue [$];
  int now = 0;

  always @(posedge clk) now <= now + 1;

  always @(posedge clk) begin
    awready <= ($urandom % 4) != 0;
    wready  <= ($urandom % 4) != 0;
    arready <= ($urandom % 3) != 0;
  end

  always @(posedge clk) begin
    if (awvalid && awready) begin
      aw_queue.push_back(awaddr);
      if (awprot !== 3'b000 || awlen !== 4'(BEATS - 1) || awsize !== 3'd3 || awburst !== 2'b01 || awid !== '0)
        fail($sformatf("AW fields prot %b len %0d size %0d burst %b", awprot, awlen, awsize, awburst));
      if (awaddr[3:0] != 0)
        fail($sformatf("AW address %h not line-aligned", awaddr));
    end
    if (wvalid && wready) begin
      w_beats.push_back(wdata);
      if (wstrb !== 8'hFF)
        fail("WSTRB not all ones");
      if (wlast !== (w_beats.size() % BEATS == 0))
        fail("WLAST on the wrong beat");
    end
    if (aw_queue.size() > 0 && w_beats.size() >= BEATS) begin
      pending_write_t pw;
      pw.addr = aw_queue.pop_front();
      for (int i = 0; i < BEATS; i++)
        pw.data[i] = w_beats.pop_front();
      pw.due = now + 1 + int'($urandom % 24);
      b_queue.push_back(pw);
    end
  end

  // B, in AW order, each after its own delay; the write lands in memory as B goes out.
  initial begin
    pending_write_t pw;
    forever begin
      @(negedge clk);
      if (b_queue.size() == 0 || b_queue[0].due > now)
        continue;
      pw = b_queue.pop_front();
      if (!bad_line(pw.addr))
        for (int i = 0; i < BEATS; i++)
          ddr[pw.addr + 32'(8 * i)] = pw.data[i];
      bresp  = bad_line(pw.addr) ? 2'b10 : 2'b00;
      bvalid = 1'b1;
      do @(posedge clk); while (!bready);
      @(negedge clk);
      bvalid = 1'b0;
    end
  end

  // R, one burst at a time, after a random delay and with random gaps between beats.
  logic [31:0] ar_queue [$];

  always @(posedge clk)
    if (arvalid && arready) begin
      ar_queue.push_back(araddr);
      if (arprot !== 3'b000 || arlen !== 4'(BEATS - 1) || arsize !== 3'd3 || arburst !== 2'b01 || arid !== '0)
        fail($sformatf("AR fields prot %b len %0d size %0d burst %b", arprot, arlen, arsize, arburst));
      if (b_queue.size() > 0 || aw_queue.size() > 0 || bvalid)
        fail($sformatf("AR %h issued with a write still waiting for B", araddr));
    end

  initial begin
    logic [31:0] a;
    forever begin
      @(negedge clk);
      if (ar_queue.size() == 0)
        continue;
      a = ar_queue.pop_front();
      repeat ($urandom % 40) @(negedge clk);
      for (int beat = 0; beat < BEATS; beat++) begin
        repeat ($urandom % 3) @(negedge clk);
        rdata  = ddr_word(a + 32'(8 * beat));
        rresp  = bad_line(a) ? 2'b10 : 2'b00;
        rlast  = beat == BEATS - 1;
        rvalid = 1'b1;
        do @(posedge clk); while (!rready);
        @(negedge clk);
        rvalid = 1'b0;
        rlast  = 1'b0;
      end
    end
  end

  // ---- program-order reference and the driver ----
  logic [LINE_W-1:0] reference [logic [31:0]];
  int expected_reads = 0;
  int expected_writes = 0;
  int expected_dropped = 0;
  bit expect_mem_err = 0;
  bit response_expected = 0;

  function automatic logic [LINE_W-1:0] reference_line(input logic [31:0] a);
    logic [31:0]       d;
    logic [LINE_W-1:0] line;
    if (reference.exists(a))
      return reference[a];
    d = CARVEOUT | (a & 32'h0FFF_FFFF);
    for (int i = 0; i < BEATS; i++)
      line[64 * i +: 64] = unwritten(d + 32'(8 * i));
    return line;
  endfunction

  always @(posedge clk)
    if (rsp_valid && !response_expected)
      fail("a response nobody asked for");

  task automatic request(input bit wr, input logic [31:0] a, input logic [LINE_W-1:0] d);
    @(negedge clk);
    req_valid = 1'b1;
    req_wr    = wr;
    req_addr  = a;
    req_data  = d;
    do @(posedge clk); while (!req_ready);
    @(negedge clk);
    req_valid = 1'b0;
  endtask

  task automatic read_check(input logic [31:0] a);
    logic [LINE_W-1:0] want;
    bit                outside;
    bit                bad;
    outside = (a & 32'hF000_0000) != 32'h8000_0000;
    bad     = !outside && bad_line(CARVEOUT | (a & 32'h0FFF_FFFF));
    want    = (outside || bad) ? {BEATS{POISON}} : reference_line(a);
    response_expected = 1;
    request(0, a, '0);
    while (!rsp_valid) @(posedge clk);
    if (rsp_data !== want || rsp_err !== (outside || bad))
      fail($sformatf("read %h: data %h err %b, want %h err %b", a, rsp_data, rsp_err, want, outside || bad));
    @(negedge clk);
    response_expected = 0;
    if (!outside)
      expected_reads++;
    if (bad)
      expect_mem_err = 1;
  endtask

  task automatic write(input logic [31:0] a, input logic [LINE_W-1:0] d);
    bit outside;
    outside = (a & 32'hF000_0000) != 32'h8000_0000;
    request(1, a, d);
    if (outside) begin
      expected_dropped++;
    end else begin
      expected_writes++;
      if (bad_line(CARVEOUT | (a & 32'h0FFF_FFFF)))
        expect_mem_err = 1;
      else
        reference[a] = d;
    end
  endtask

  function automatic logic [31:0] random_line();
    case ($urandom % 16)
      0:       return 32'h9000_0000 | 32'(($urandom % LINES) << 4);
      1:       return 32'h8FFF_FFF0 - 32'(($urandom % 4) << 4);
      default: return 32'h8000_0000 | 32'(($urandom % LINES) << 4);
    endcase
  endfunction

  // A read the chip reset interrupts gets no response; the next read is right.
  task automatic reset_during_read(input bit reset_first);
    logic [31:0] a;
    a = 32'h8000_0000 | 32'(($urandom % LINES) << 4);
    if (bad_line(CARVEOUT | a))
      a = a + 32'h10;
    if (reset_first)
      chip_in_reset = 1'b1;
    request(0, a, '0);
    expected_reads++;
    repeat (2) @(posedge clk);
    chip_in_reset = 1'b1;
    repeat (3) @(posedge clk);
    chip_in_reset = 1'b0;
    repeat (80) @(posedge clk);
    read_check(a);
  endtask

  initial begin
    repeat (4) @(posedge clk);
    arst_n = 1'b1;
    repeat (4) @(posedge clk);
    for (int n = 0; n < TRANSACTIONS; n++) begin
      if ($urandom % 2)
        write(random_line(), {$urandom, $urandom, $urandom, $urandom});
      else
        read_check(random_line());
      if (n % 2000 == 1000)
        reset_during_read(n % 4000 == 1000);
    end
    repeat (100) @(posedge clk);
    if (reads != 32'(expected_reads))
      fail($sformatf("reads %0d, want %0d", reads, expected_reads));
    if (writes != 32'(expected_writes))
      fail($sformatf("writes %0d, want %0d", writes, expected_writes));
    if (dropped_writes != 32'(expected_dropped))
      fail($sformatf("dropped writes %0d, want %0d", dropped_writes, expected_dropped));
    if (mem_err !== expect_mem_err)
      fail($sformatf("mem_err %b, want %b", mem_err, expect_mem_err));
    if (mem_err && first_err_addr[9:4] != 6'd13)
      fail($sformatf("first_err_addr %h is not a bad line", first_err_addr));
    begin
      longint hist_total = 0;
      int     top_bin = -1;
      for (int b = 0; b < 8; b++) begin
        hist_total += read_latency_hist[b];
        if (read_latency_hist[b] != 0)
          top_bin = b;
      end
      if (hist_total != longint'(reads))
        fail($sformatf("latency histogram holds %0d reads, want %0d", hist_total, reads));
      if (top_bin != (read_latency_max >= 28 ? 7 : int'(read_latency_max) / 4))
        fail($sformatf("highest histogram bin %0d, but the maximum latency %0d", top_bin, read_latency_max));
    end
    $display("[MEM_AXI_TB] %0d reads, %0d writes, %0d dropped; read latency max %0d mean %0d",
             reads, writes, dropped_writes, read_latency_max,
             reads == 0 ? 0 : int'(read_latency_sum / 48'(reads)));
    if (errors == 0)
      $display("tb_fbu_mem_axi_hp PASS");
    else
      $display("tb_fbu_mem_axi_hp FAIL %0d", errors);
    $finish;
  end

  initial begin
    #100ms;
    $display("tb_fbu_mem_axi_hp FAIL timeout");
    $finish;
  end

endmodule
