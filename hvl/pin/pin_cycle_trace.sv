///////////////////////////////////////////////////////////////////////////////
// pin_cycle_trace.sv
//
// Two jobs, both on the pins only, both off unless asked for:
//
// 1. PER-CYCLE PIN TRACE (+PIN_CYCLE_TRACE=<file>).  Every core cycle after
//    rst_n is released, the value of every forte_top port.  A line is written
//    only when something changed, so idle stretches cost nothing.  The trace is
//    what postpnr/run.sh compares, cycle-exact, between the golden RTL and the
//    post-PnR netlist:
//      # pin_cycle v1 ...                       header
//      R <n>                                    rst_n released (n-th time)
//      C <cyc> <io_in> <rdy><rv> <irq> <rx> <tm><se><fi> | <io_out> <req><wr> <tx> <st>
//    <cyc> counts core_clk posedges since that release, so the trace does not
//    depend on the clock period or the bench's absolute start time.
//    Sample points:
//      inputs   AT the core_clk posedge -- the value the bench launched in the
//               previous cycle.  Every bench output launches TCO after a
//               posedge (TCO < T), so this is race-free for any TCO.
//      outputs  +PIN_TRACE_SAMPLE_PS after the posedge (default 3/4 T).  In an
//               SDF run postpnr/run.sh puts it at T - min(output_delay -max),
//               the latest moment the SDC lets any output still be settling.
//    clk_out is a clock and is not traced by value (see 3).
//
// 2. PAD OUTPUT WINDOW CHECK (+OUT_MAX_LINK_PS/+OUT_MIN_LINK_PS for io_out, req,
//    wr; +OUT_MAX_SLOW_PS/+OUT_MIN_SLOW_PS for uart_tx, status).  The SDC's
//    set_output_delay -max/-min, relative to the core_clk posedge at the pin:
//    an output launched by edge E(k) must be settled by E(k+1) - out_max
//    (the board's setup) and must not change before E(k+1) - out_min (the
//    board's hold; out_min is usually negative, i.e. after the edge).  So any
//    transition whose distance to the next posedge lies in (out_min, out_max),
//    or (for a negative out_min) that comes less than -out_min after a posedge,
//    is an ERROR.  VCS's own timing checks only see the chip's internal flops;
//    this is the pad-side half.  Meaningful only with back-annotated delays:
//    in RTL or a zero-delay netlist every output moves exactly on the edge.
//
// 3. clk_out: its insertion delay after core_clk (min/max over the run) is
//    reported at the end, and it must keep toggling once out of reset.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module pin_cycle_trace #(parameter int LINK_W = 8) (
  input logic              core_clk,
  input logic              rst_n,
  input wire  [LINK_W-1:0] io_in,
  input wire               ready,
  input wire               rvalid,
  input wire  [1:0]        irq,
  input wire               uart_rx,
  input wire               test_mode,
  input wire               scan_en,
  input wire               fault_inject,
  input wire  [LINK_W-1:0] io_out,
  input wire               req,
  input wire               wr,
  input wire               uart_tx,
  input wire               status,
  input wire               clk_out
);

  real    per_ns     = 10.0;      // +CLK_PS, as pin_tb reads it
  real    smp_ns     = 7.5;       // +PIN_TRACE_SAMPLE_PS
  int     fd         = 0;
  int     errors     = 0;         // pad window errors (pin_tb counts them)
  longint n_rst      = 0;

  // window checks: enabled per group when its out_max plusarg is given
  bit     win_link = 0, win_slow = 0;
  real    omax_link, omin_link, omax_slow, omin_slow;
  int     win_quiet  = 4;         // cycles after rst_n release before checking

  function automatic void err(input string m);
    errors++;
    $display("[PIN_IO] ERROR @%0t: %s", $realtime, m);
  endfunction

  initial begin
    int v;
    string path;
    if ($value$plusargs("CLK_PS=%d", v)) per_ns = v / 1000.0;
    smp_ns = 0.75 * per_ns;
    if ($value$plusargs("PIN_TRACE_SAMPLE_PS=%d", v)) smp_ns = v / 1000.0;
    if ($value$plusargs("OUT_MAX_LINK_PS=%d", v)) begin win_link = 1; omax_link = v / 1000.0; omin_link = 0.0; end
    if ($value$plusargs("OUT_MIN_LINK_PS=%d", v)) omin_link = v / 1000.0;
    if ($value$plusargs("OUT_MAX_SLOW_PS=%d", v)) begin win_slow = 1; omax_slow = v / 1000.0; omin_slow = 0.0; end
    if ($value$plusargs("OUT_MIN_SLOW_PS=%d", v)) omin_slow = v / 1000.0;
    if (smp_ns <= 0.0 || smp_ns >= per_ns)
      $fatal(1, "pin_cycle_trace: PIN_TRACE_SAMPLE_PS=%0.0f outside (0, CLK_PS=%0.0f)", smp_ns * 1000, per_ns * 1000);
    if (win_link) $display("[PIN_IO] output window io_out/req/wr: settled %0.3f ns before, held %0.3f ns %s the core_clk edge",
                           omax_link, omin_link < 0 ? -omin_link : omin_link, omin_link < 0 ? "after" : "before");
    if (win_slow) $display("[PIN_IO] output window uart_tx/status: settled %0.3f ns before, held %0.3f ns %s the core_clk edge",
                           omax_slow, omin_slow < 0 ? -omin_slow : omin_slow, omin_slow < 0 ? "after" : "before");
    if ($value$plusargs("PIN_CYCLE_TRACE=%s", path)) begin
      fd = $fopen(path, "w");
      if (fd == 0) $display("[PIN_IO] WARNING: cannot open %s", path);
      else begin
        $fdisplay(fd, "# pin_cycle v1  clk_ps=%0d out_sample_ps=%0d", $rtoi(per_ns * 1000), $rtoi(smp_ns * 1000));
        $fdisplay(fd, "# C <cyc> <io_in> <ready><rvalid> <irq> <uart_rx> <test_mode><scan_en><fault_inject> | <io_out> <req><wr> <uart_tx> <status>");
      end
    end
  end

  // ---- 1. the trace ---------------------------------------------------------
  // since_rel: posedges since rst_n was seen released (0 = in reset).
  longint since_rel = 0;
  initial begin : tracer
    logic        s_rst;
    logic [LINK_W+7:0] s_in;      // io_in, ready, rvalid, irq[1:0], uart_rx, test_mode, scan_en, fault_inject
    logic [LINK_W+3:0] s_out;     // io_out, req, wr, uart_tx, status
    logic [2*LINK_W+11:0] cur, prev;
    forever begin
      @(posedge core_clk);
      s_rst = rst_n;
      s_in  = {io_in, ready, rvalid, irq, uart_rx, test_mode, scan_en, fault_inject};
      if (s_rst !== 1'b1) begin since_rel = 0; continue; end   // X (power-up) counts as in reset
      if (since_rel == 0) begin
        n_rst++;
        if (fd) $fdisplay(fd, "R %0d", n_rst);
        prev = 'x;
      end
      since_rel++;
      if (fd) begin
        #(smp_ns);
        s_out = {io_out, req, wr, uart_tx, status};
        cur   = {s_in, s_out};
        if (cur !== prev)
          $fdisplay(fd, "C %0d %h %b%b %b %b %b%b%b | %h %b%b %b %b", since_rel,
                    s_in[LINK_W+7:8], s_in[7], s_in[6], s_in[5:4], s_in[3], s_in[2], s_in[1], s_in[0],
                    s_out[LINK_W+3:4], s_out[3], s_out[2], s_out[1], s_out[0]);
        prev = cur;
      end
    end
  end

  // ---- 2. pad output windows -------------------------------------------------
  realtime last_pos = 0;
  always @(posedge core_clk) last_pos = $realtime;

  // phase: time since the last core_clk posedge.  The forbidden zone around
  // each capture edge E is (E - out_max, E - out_min): before E it is the
  // board's setup, after E (negative out_min) its hold.
  function automatic void win_check(input string pin, input real omax, input real omin);
    real ph, to_next;
    if (rst_n !== 1'b1 || since_rel <= win_quiet) return;
    ph      = $realtime - last_pos;
    to_next = per_ns - ph;
    if (to_next < omax && to_next > omin)
      err($sformatf("output window: %s changed %0.3f ns before the core_clk edge (must settle %0.3f ns before it)",
                    pin, to_next, omax));
    else if (omin < 0 && ph < -omin)
      err($sformatf("output window: %s changed %0.3f ns after the core_clk edge (must hold %0.3f ns after it)",
                    pin, ph, -omin));
  endfunction

  always @(io_out) if (win_link) win_check("io_out", omax_link, omin_link);
  always @(req)    if (win_link) win_check("req",    omax_link, omin_link);
  always @(wr)     if (win_link) win_check("wr",     omax_link, omin_link);
  always @(uart_tx) if (win_slow) win_check("uart_tx", omax_slow, omin_slow);
  always @(status)  if (win_slow) win_check("status",  omax_slow, omin_slow);

  // ---- 3. clk_out -------------------------------------------------------------
  // In RTL clk_out and core_clk rise in the same time step, in either order:
  // a delay of a whole period there is 0, and the stall check allows one
  // cycle without an edge (the two orders alternate at worst).
  real    ins_min = 1.0e9, ins_max = -1.0, ins_d;
  longint co_edges = 0, co_last = 0;
  int     co_stall = 0;
  always @(posedge clk_out) begin
    ins_d = $realtime - last_pos;
    if (ins_d >= 0.999 * per_ns) ins_d = ins_d - per_ns;
    co_edges++;
    if (since_rel > win_quiet) begin
      if (ins_d < ins_min) ins_min = ins_d;
      if (ins_d > ins_max) ins_max = ins_d;
    end
  end
  always @(posedge core_clk) begin
    co_stall = (co_edges == co_last) ? co_stall + 1 : 0;
    if (since_rel > win_quiet + 2 && co_stall == 2) err("clk_out stopped: no edge in two core cycles");
    co_last = co_edges;
  end

  final begin
    if (ins_max >= 0.0)
      $display("[PIN_IO] clk_out insertion after core_clk: min %0.3f ns, max %0.3f ns", ins_min, ins_max);
    $display("[PIN_IO] pad window errors: %0d%s", errors, (win_link || win_slow) ? "" : " (window checks off)");
    if (fd) $fclose(fd);
  end

endmodule
