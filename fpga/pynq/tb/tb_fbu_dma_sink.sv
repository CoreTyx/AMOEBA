///////////////////////////////////////////////////////////////////////////////
// tb_fbu_dma_sink.sv -- fbu_dma_sink against an AXI3 write slave and a PS that
// reads both rings slowly (make test-dma-sink).
//
// The rings are small (16 trace slots, 32 console entries) and the reader
// lags, so they wrap and fill: every entry the PS reads must be the next one
// pushed, which also proves nothing unread was overwritten.  The slave checks
// each burst's shape, that it stays inside its ring and never crosses 4 KB,
// and the console strobes.  Then a clear restarts both rings at 0, and a bad
// BRESP must be sticky while the pointers still advance.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module tb_fbu_dma_sink;
  import fbu_pkg::*;

  localparam logic [31:0] TRACE_BASE   = 32'h0C40_0000;
  localparam logic [31:0] CONSOLE_BASE = 32'h0C80_0010;
  localparam int          TRACE_LOG2   = 4;
  localparam int          CONSOLE_LOG2 = 5;
  localparam int          N_TRACE      = 3000;
  localparam int          N_CONSOLE    = 4000;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic arst_n = 1'b0;

  sink_cfg_t    cfg;
  sink_stat_t   stat;
  logic [319:0] trace_head;
  logic         trace_valid;
  logic         trace_pop;
  logic [8:0]   console_head;
  logic         console_valid;
  logic         console_pop;

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
  logic        awready;
  logic [5:0]  wid;
  logic [63:0] wdata;
  logic [7:0]  wstrb;
  logic        wlast;
  logic        wvalid;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready;

  fbu_dma_sink dut (
    .clk, .arst_n, .cfg, .stat,
    .trace_head, .trace_valid, .trace_pop, .console_head, .console_valid, .console_pop,
    .m_axi_awid(awid), .m_axi_awaddr(awaddr), .m_axi_awlen(awlen), .m_axi_awsize(awsize),
    .m_axi_awburst(awburst), .m_axi_awlock(awlock), .m_axi_awcache(awcache), .m_axi_awprot(awprot),
    .m_axi_awqos(awqos), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
    .m_axi_wid(wid), .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wlast(wlast),
    .m_axi_wvalid(wvalid), .m_axi_wready(wready),
    .m_axi_bid(6'd0), .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready));

  int errors = 0;

  function automatic void fail(input string what);
    errors++;
    if (errors <= 10)
      $display("[SINK_TB] %0t: %s", $time, what);
  endfunction

  // ---- sources: the trace and console FIFOs ----
  logic [319:0] trace_q [$];
  logic [8:0]   console_q [$];
  logic [319:0] trace_sent [$];
  logic [8:0]   console_sent [$];
  bit           sources_on = 1'b1;
  int           trace_pushed = 0;
  int           console_pushed = 0;

  // The FIFO heads, set where the queues are settled: Verilator does not
  // re-evaluate an assign on a queue's size.
  always @(negedge clk) begin
    trace_valid   = trace_q.size() != 0;
    trace_head    = trace_valid ? trace_q[0] : '0;
    console_valid = console_q.size() != 0;
    console_head  = console_valid ? console_q[0] : '0;
  end

  always @(posedge clk) begin
    if (trace_pop) begin
      if (!trace_valid)
        fail("trace pop with the FIFO empty");
      else
        trace_sent.push_back(trace_q.pop_front());
    end
    if (console_pop) begin
      if (!console_valid)
        fail("console pop with the FIFO empty");
      else
        console_sent.push_back(console_q.pop_front());
    end
    if (sources_on && trace_pushed < N_TRACE && $urandom_range(99) < 40) begin
      logic [319:0] r;
      for (int w = 0; w < 10; w++)
        r[32 * w +: 32] = $urandom;
      trace_q.push_back(r);
      trace_pushed++;
    end
    if (sources_on && console_pushed < N_CONSOLE && $urandom_range(99) < 50) begin
      console_q.push_back(9'($urandom));
      console_pushed++;
    end
  end

  // ---- the AXI3 write slave ----
  // W may lead AW (AXI allows it), so the beats queue until both the address
  // and WLAST are in; then the burst is checked and written, and B follows.
  logic [7:0]  mem [logic [31:0]];
  logic [63:0] w_data [$];
  logic [7:0]  w_strb [$];
  bit          w_last [$];
  bit          aw_taken;
  logic [31:0] burst_addr;
  int          burst_beats;
  bit          bad_next = 1'b0;
  bit          b_due;
  bit          b_bad;
  int          b_wait;

  always @(negedge clk) begin
    awready <= $urandom_range(99) < 60 && !aw_taken;
    wready  <= $urandom_range(99) < 60;
  end

  function automatic bit in_ring(input logic [31:0] a, input logic [31:0] base, input int bytes);
    return a >= base && a < base + 32'(bytes);
  endfunction

  task automatic check_aw(input logic [31:0] a, input int beats);
    if (awsize != 3'd3 || awburst != 2'b01 || awprot != 3'b000 || awid != '0)
      fail($sformatf("AW fields: size %0d burst %0d prot %0d id %0d", awsize, awburst, awprot, awid));
    if ((a & 32'hFFF) + 32'(8 * beats) > 32'h1000)
      fail($sformatf("burst at %08h crosses 4 KB", a));
    if (!(beats == 5 && in_ring(a, TRACE_BASE, 64 << TRACE_LOG2) && a[5:0] == 0) &&
        !(beats == 1 && in_ring(a, CONSOLE_BASE & ~32'h7, (2 << CONSOLE_LOG2) + 8)))
      fail($sformatf("AW %08h, %0d beats, outside both rings", a, beats));
  endtask

  always @(posedge clk) begin
    if (!arst_n) begin
      aw_taken = 1'b0;
      b_due    = 1'b0;
      bvalid  <= 1'b0;
      bresp   <= 2'b00;
    end else begin
      if (bvalid && bready)
        bvalid <= 1'b0;
      if (awvalid && awready) begin
        aw_taken    = 1'b1;
        burst_addr  = awaddr;
        burst_beats = int'(awlen) + 1;
        check_aw(awaddr, burst_beats);
      end
      if (wvalid && wready) begin
        w_data.push_back(wdata);
        w_strb.push_back(wstrb);
        w_last.push_back(wlast);
      end
      if (aw_taken && !b_due && w_last.size() >= burst_beats) begin
        for (int i = 0; i < burst_beats; i++) begin
          logic [63:0] d;
          logic [7:0]  st;
          bit          l;
          d  = w_data.pop_front();
          st = w_strb.pop_front();
          l  = w_last.pop_front();
          if (l != (i == burst_beats - 1))
            fail($sformatf("WLAST %0d on beat %0d of %0d", l, i, burst_beats));
          if (burst_beats == 1 && !(st inside {8'h03, 8'h0C, 8'h30, 8'hC0}))
            fail($sformatf("console strobe %02h", st));
          if (burst_beats == 5 && st != 8'hFF)
            fail($sformatf("trace strobe %02h", st));
          for (int b = 0; b < 8; b++)
            if (st[b] && !bad_next)
              mem[burst_addr + 32'(8 * i + b)] = d[8 * b +: 8];
        end
        b_due  = 1'b1;
        b_bad  = bad_next;
        b_wait = $urandom_range(12);
      end
      if (b_due && !bvalid) begin
        if (b_wait == 0) begin
          bvalid  <= 1'b1;
          bresp   <= b_bad ? 2'b10 : 2'b00;
          b_due    = 1'b0;
          aw_taken = 1'b0;
          if (b_bad)
            bad_next = 1'b0;
        end else begin
          b_wait--;
        end
      end
    end
  end

  // ---- the PS: read what WR passed, slowly ----
  int trace_read = 0;
  int console_read = 0;

  function automatic logic [319:0] trace_slot(input int n);
    logic [319:0] r;
    logic [31:0]  a;
    a = TRACE_BASE + 32'((n % (1 << TRACE_LOG2)) * 64);
    for (int b = 0; b < 40; b++)
      r[8 * b +: 8] = mem.exists(a + 32'(b)) ? mem[a + 32'(b)] : 8'hxx;
    return r;
  endfunction

  function automatic logic [8:0] console_slot(input int n);
    logic [31:0] a;
    a = CONSOLE_BASE + 32'((n % (1 << CONSOLE_LOG2)) * 2);
    return {mem[a + 32'd1][0], mem[a]};
  endfunction

  task automatic ps_drain(input int lag_pct);
    while (trace_read < int'(stat.trace_wr) && $urandom_range(99) >= lag_pct) begin
      logic [319:0] want;
      if (trace_sent.size() == 0) begin
        fail("trace WR ahead of the pops");
        break;
      end
      want = trace_sent.pop_front();
      if (trace_slot(trace_read) !== want)
        fail($sformatf("trace record %0d: ring %h, pushed %h", trace_read, trace_slot(trace_read), want));
      trace_read++;
    end
    while (console_read < int'(stat.console_wr) && $urandom_range(99) >= lag_pct) begin
      logic [8:0] want;
      if (console_sent.size() == 0) begin
        fail("console WR ahead of the pops");
        break;
      end
      want = console_sent.pop_front();
      if (console_slot(console_read) !== want)
        fail($sformatf("console entry %0d: ring %h, pushed %h", console_read, console_slot(console_read), want));
      console_read++;
    end
    cfg.trace_rd   = 32'(trace_read);
    cfg.console_rd = 32'(console_read);
  endtask

  // The reader alternates: eager windows read an entry the cycle WR passes it
  // (an early WR shows up as stale data), slow ones let both rings fill.
  task automatic run_until_drained();
    int idle = 0;
    int cyc = 0;
    while (idle < 200) begin
      @(posedge clk);
      cyc++;
      ps_drain((cyc / 5000) % 2 == 0 ? 0 : 99);
      if (trace_q.size() == 0 && console_q.size() == 0 && !stat.busy &&
          trace_read == int'(stat.trace_wr) && console_read == int'(stat.console_wr) &&
          (!sources_on || (trace_pushed == N_TRACE && console_pushed == N_CONSOLE)))
        idle++;
      else
        idle = 0;
    end
  endtask

  int max_trace_unread = 0;
  always @(posedge clk)
    if (int'(stat.trace_wr) - trace_read > max_trace_unread)
      max_trace_unread = int'(stat.trace_wr) - trace_read;

  initial begin
    cfg = '{trace_en: 1'b0, console_en: 1'b0, clear: 1'b0,
            trace_base: TRACE_BASE, trace_log2: 5'(TRACE_LOG2), trace_rd: '0,
            console_base: CONSOLE_BASE, console_log2: 5'(CONSOLE_LOG2), console_rd: '0};
    repeat (4) @(posedge clk);
    arst_n = 1'b1;
    @(negedge clk);
    cfg.trace_en   = 1'b1;
    cfg.console_en = 1'b1;

    // 1: both rings, a reader that keeps them full.
    run_until_drained();
    if (trace_read != N_TRACE || console_read != N_CONSOLE)
      fail($sformatf("read %0d/%0d trace, %0d/%0d console", trace_read, N_TRACE, console_read, N_CONSOLE));
    if (max_trace_unread != (1 << TRACE_LOG2))
      fail($sformatf("trace ring never filled: at most %0d unread", max_trace_unread));
    if (stat.err)
      fail("err set without a bad response");

    // 2: rings off, clear: both pointers back to 0.
    @(negedge clk);
    cfg.trace_en   = 1'b0;
    cfg.console_en = 1'b0;
    cfg.clear      = 1'b1;
    @(negedge clk);
    cfg.clear      = 1'b0;
    repeat (4) @(negedge clk);
    if (stat.trace_wr != 0 || stat.console_wr != 0)
      fail($sformatf("after clear WR %0d/%0d", stat.trace_wr, stat.console_wr));
    trace_read   = 0;
    console_read = 0;
    cfg.trace_rd   = '0;
    cfg.console_rd = '0;

    // 3: console only, one SLVERR: sticky, and the entry still counts.
    console_q.push_back(9'h041);
    console_q.push_back(9'h142);
    console_q.push_back(9'h043);
    cfg.console_en = 1'b1;
    wait (stat.console_wr == 1);
    @(negedge clk);
    bad_next = 1'b1;
    wait (stat.console_wr == 3);
    repeat (4) @(negedge clk);
    if (!stat.err || stat.err_resp != 2'b10)
      fail($sformatf("bad BRESP not kept: err %0d resp %0d", stat.err, stat.err_resp));
    if (console_slot(0) !== 9'h041 || console_slot(2) !== 9'h043)
      fail("entries around the bad write lost");
    void'(console_sent.pop_front());
    void'(console_sent.pop_front());
    void'(console_sent.pop_front());

    $display("[SINK_TB] %0d trace records, %0d console entries through rings of %0d and %0d; at most %0d records unread",
             N_TRACE, N_CONSOLE, 1 << TRACE_LOG2, 1 << CONSOLE_LOG2, max_trace_unread);
    if (errors == 0)
      $display("tb_fbu_dma_sink PASS");
    else
      $display("tb_fbu_dma_sink FAIL %0d", errors);
    $finish;
  end

  initial begin
    #20ms;
    $display("tb_fbu_dma_sink FAIL timeout (trace %0d read, console %0d read)", trace_read, console_read);
    $finish;
  end

endmodule
