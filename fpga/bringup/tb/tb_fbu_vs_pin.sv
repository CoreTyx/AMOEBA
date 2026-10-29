///////////////////////////////////////////////////////////////////////////////
// tb_fbu_vs_pin.sv -- fbu_link_slave against the pin bench, trace for trace.
//
// The frozen forte_top (inside forte_emu_dut, so with the FPGA's pad and SRAM
// stand-ins and the in-fabric io net) driven by fbu_link_slave, with a
// behavioural line memory behind it.  It writes a pin_trace.log in the bench's
// format; fpga/bringup/tb/fbu_vs_pin.sh runs the pin bench on the same image
// with the same knobs and requires `pin.sh compare` to MATCH, cycle for cycle.
// That is the P1 gate: the gateware implements the bench's protocol, decisions
// and checks exactly.
//
// Plusargs mirror pin_link_agent's: +MEMLST +FPGA_SEED +FPGA_GAP_PCT
// +FPGA_RD_LAT +FPGA_MEM=rand|zero +FPGA_WDOG +FPGA_MUTATE +TOHOST +TIMEOUT
// +TRACE, plus the gateware's own: +NODET (natural mode) and +MEM_LAT (backend
// read latency in cycles, default 1).
//
// Only the link is modelled.  uart_rx idles high and nothing else is driven, so
// images that need console input are out of scope here (tb_forte_emu covers them).
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_fbu_vs_pin;
  import forte_link_pkg::*;
  import fbu_pkg::*;

  localparam int BEATS  = 2;
  localparam int LINE_W = 64 * BEATS;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---- knobs ------------------------------------------------------------------
  int unsigned seed = 1;
  int          gap_pct = 0, rd_lat = 0, wdog = 1000, mutate = 0, mem_lat = 1;
  longint      timeout = 10_000_000;
  logic [63:0] tohost_addr = 64'h8080_0000;
  string       mem_policy = "rand", memlst, trace_path = "pin_trace.log";
  bit          det = 1;

  // ---- the FPGA's side of the pins ------------------------------------------------
  logic              rst_n = 1'b0, arst_n = 1'b0;
  logic [LINK_W-1:0] io_o, io_i;
  logic              io_oe, ready, rvalid;
  logic              dir, req, wr, clk_out, uart_tx, status;

  forte_emu_dut dut (
    .core_clk(clk), .rst_n,
    .fpga_io_o(io_o), .fpga_io_oe({LINK_W{io_oe}}), .fpga_io_i(io_i),
    .dir, .req, .wr, .clk_out, .uart_tx, .status,
    .ready, .rvalid, .irq(2'b00), .uart_rx(1'b1),
    .test_mode(1'b0), .scan_en(1'b0), .fault_inject(1'b0));

  // ---- the slave ---------------------------------------------------------------------
  logic              m_req_valid, m_req_ready, m_req_wr, m_rsp_valid;
  logic [31:0]       m_req_addr;
  logic [LINE_W-1:0] m_req_data, m_rsp_data;
  logic [63:0]       cyc, tohost_val, first_err_cyc, rec_cyc, rec_tohost_cyc, rec_tohost_val;
  logic [31:0]       n_rd, n_wr, err_now, err_sticky, err_count, rec_addr;
  logic [4:0]        first_err;
  logic              tohost_seen, rec_valid, rec_wr, rec_tohost;
  logic [LINE_W-1:0] rec_line;
  logic              prng_load = 1'b0;
  logic [63:0]       prng_init_v = '0;

  fbu_link_slave #(.BEATS(BEATS)) slave (
    .clk, .arst_n,
    .cfg_det(det), .cfg_gap_pct(7'(gap_pct)), .cfg_rd_lat(16'(rd_lat)), .cfg_wdog(16'(wdog)),
    .cfg_mem_base(32'h8000_0000), .cfg_mem_limit(32'h8FFF_FFFF), .cfg_reset_vec(32'h8000_0000),
    .cfg_tohost_addr(tohost_addr[31:0]), .cfg_mutate(2'(mutate)),
    .prng_load, .prng_init(prng_init_v),
    .rst_n_pin(rst_n), .dir, .req, .wr, .io_i, .io_o, .io_oe, .ready, .rvalid,
    .m_req_valid, .m_req_ready, .m_req_wr, .m_req_addr, .m_req_data,
    .m_rsp_valid, .m_rsp_data, .m_rsp_err(1'b0),
    .cyc, .n_rd, .n_wr, .tohost_seen, .tohost_val,
    .err_now, .err_sticky, .err_count, .first_err, .first_err_cyc,
    .rec_valid, .rec_cyc, .rec_wr, .rec_addr, .rec_line,
    .rec_tohost, .rec_tohost_cyc, .rec_tohost_val);

  // ---- behavioural line memory: pin_link_agent's, word for word ---------------------------
  logic [63:0] mem [longint unsigned];

  function automatic logic [63:0] mix64(input logic [63:0] z);
    z = (z ^ (z >> 30)) * 64'hBF58_476D_1CE4_E5B9;
    z = (z ^ (z >> 27)) * 64'h94D0_49BB_1331_11EB;
    return z ^ (z >> 31);
  endfunction

  function automatic logic [63:0] mem_rd(input logic [63:0] a);
    longint unsigned k = a >> 3;
    if (mem.exists(k)) return mem[k];
    return (mem_policy == "zero") ? '0 : mix64(k ^ (64'(seed) << 40));
  endfunction

  function automatic int load_lst(input string path);
    int fd, n = 0;
    longint unsigned k = 0;
    string line;
    logic [63:0] w;
    fd = $fopen(path, "r");
    if (fd == 0) return -1;
    while ($fgets(line, fd)) begin
      if (line.len() == 0 || line.getc(0) == "\n" || line.getc(0) == "/" || line.getc(0) == "#") continue;
      if (line.getc(0) == "@") void'($sscanf(line.substr(1, line.len() - 1), "%h", k));
      else if ($sscanf(line, "%h", w) == 1) begin mem[k] = w; k++; n++; end
    end
    $fclose(fd);
    return n;
  endfunction

  // In order, one request per cycle; a read answers mem_lat cycles after it is taken.
  assign m_req_ready = 1'b1;
  logic [LINE_W-1:0] rsp_pipe [$];
  int                rsp_due  [$];
  int                now = 0;
  always @(posedge clk) begin
    now++;
    m_rsp_valid <= 1'b0;
    if (rsp_due.size() && rsp_due[0] <= now) begin
      m_rsp_valid <= 1'b1;
      m_rsp_data  <= rsp_pipe.pop_front();
      void'(rsp_due.pop_front());
    end
    if (m_req_valid && m_req_ready) begin
      if (m_req_wr) begin
        for (int b = 0; b < BEATS; b++) mem[(64'(m_req_addr) >> 3) + b] = m_req_data[64 * b +: 64];
      end else begin
        logic [LINE_W-1:0] l;
        for (int b = 0; b < BEATS; b++) l[64 * b +: 64] = mem_rd(64'(m_req_addr) + 64'(8 * b));
        rsp_pipe.push_back(l);
        rsp_due.push_back(now + mem_lat);
      end
    end
  end

  // ---- trace, in pin_trace.log's format -------------------------------------------------
  // The bench stops at its MAX_ERRORS-th error (default 1), in the cycle after
  // it, with that cycle's records written.  This writes nothing that finished
  // after the cycle of the first error either, so the traces stay comparable
  // when a run fails -- which is what the mutation self-tests do on purpose.
  // rec_tohost_cyc is the cycle the transaction finished, for every record.
  int     trace_fd;
  bit     finished = 0;
  int     max_errors = 1;
  longint stop_cyc = -1;                     // cycle of the max_errors-th error
  int     seen_errors = 0;
  always @(posedge clk) if (!finished) begin
    if (rec_valid && (stop_cyc < 0 || longint'(rec_tohost_cyc) <= stop_cyc)) begin
      string s = "";
      if (rec_tohost) $fdisplay(trace_fd, "T %0d %016h", rec_tohost_cyc, rec_tohost_val);
      for (int b = 0; b < BEATS; b++) s = {s, $sformatf(" %016h", rec_line[64 * b +: 64])};
      $fdisplay(trace_fd, "L %0d %s %08h%s", rec_cyc, rec_wr ? "W" : "R", rec_addr, s);
    end
    if (err_now != '0 && stop_cyc < 0) begin
      for (int i = 1; i < 32; i++) if (err_now[i]) begin
        link_err_t e = link_err_t'(i);
        $fdisplay(trace_fd, "E %0d %s", cyc + 1, e.name());
        seen_errors++;
      end
      if (seen_errors >= max_errors) stop_cyc = longint'(cyc) + 1;
    end
  end

  // ---- the run ----------------------------------------------------------------------------
  initial begin
    int v;
    string s;
    longint t;
    link_err_t fe;
    if ($value$plusargs("FPGA_SEED=%d", v))    seed = v;
    if ($value$plusargs("FPGA_GAP_PCT=%d", v)) gap_pct = v;
    if ($value$plusargs("FPGA_RD_LAT=%d", v))  rd_lat = v;
    if ($value$plusargs("FPGA_WDOG=%d", v))    wdog = v;
    if ($value$plusargs("FPGA_MUTATE=%d", v))  mutate = v;
    if ($value$plusargs("FPGA_MEM=%s", s))     mem_policy = s;
    if ($value$plusargs("MEM_LAT=%d", v))      mem_lat = v;
    if ($value$plusargs("TOHOST=%h", tohost_addr)) ;
    if ($value$plusargs("TIMEOUT=%d", timeout)) ;
    if ($value$plusargs("TRACE=%s", s))        trace_path = s;
    if ($test$plusargs("NODET"))               det = 0;
    if ($value$plusargs("MAX_ERRORS=%d", v))   max_errors = v;
    if (!$value$plusargs("MEMLST=%s", memlst)) $fatal(1, "tb_fbu_vs_pin: +MEMLST is required");
    if (mem_policy != "rand" && mem_policy != "zero") $fatal(1, "FPGA_MEM=%s: hardware has rand or zero only", mem_policy);
    trace_fd = $fopen(trace_path, "w");
    v = load_lst(memlst);
    if (v <= 0) $fatal(1, "load_lst %s failed", memlst);
    $display("[FBU_TB] loaded %0d words from %s; seed %0d gap %0d%% rd_lat %0d mem_lat %0d %s",
             v, memlst, seed, gap_pct, rd_lat, mem_lat, det ? "DET" : "natural");

    // FPGA configuration: the PS loads the generator, then releases the chip.
    prng_init_v = prng_seed_state(seed);
    repeat (2) @(posedge clk);
    arst_n <= 1'b1;
    @(posedge clk) prng_load <= 1'b1;
    @(posedge clk) prng_load <= 1'b0;
    repeat (16) @(posedge clk);
    rst_n <= 1'b1;

    for (t = 0; t < timeout && !tohost_seen && stop_cyc < 0; t++) @(posedge clk);
    repeat (2) @(posedge clk);
    finished = 1;
    $fclose(trace_fd);
    fe = link_err_t'(first_err);
    $display("[FBU_TB] cycles=%0d link_rd=%0d link_wr=%0d errors=%0d first=%s@%0d",
             cyc, n_rd, n_wr, err_count, fe.name(), first_err_cyc);
    if (stop_cyc >= 0)                   $display("PIN_TB_RESULT: FAIL %0d checker errors", seen_errors);
    else if (!tohost_seen)               $display("PIN_TB_RESULT: FAIL timeout: no tohost write in %0d cycles", timeout);
    else if (err_count != 0)             $display("PIN_TB_RESULT: FAIL %0d checker errors", err_count);
    else if (tohost_val[0] !== 1'b1)     $display("PIN_TB_RESULT: FAIL tohost %h has bit 0 clear", tohost_val);
    else if ((tohost_val >> 1) != 0)     $display("PIN_TB_RESULT: FAIL exit code %0d, expected 0", tohost_val >> 1);
    else                                 $display("PIN_TB_RESULT: PASS");
    $finish;
  end

endmodule
