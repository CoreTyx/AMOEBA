///////////////////////////////////////////////////////////////////////////////
// pin_tb.sv
//
// Pin-only testbench for forte_top: the bring-up FPGA in simulation.  The DUT
// is touched through its pads and nothing else, so the same bench runs the RTL
// (`forte_top` from hdl/) and the synthesized or placed-and-routed netlist,
// selected purely by the file list.  There is no RVFI, no Spike and no
// hierarchical probes in gate runs. RTL hold tests add internal freeze checks;
// correctness of the program itself is established
// by the RTL flow in sim/ (Spike co-sim); this bench establishes that the chip
// does the same thing at its pins.
//
// Agents (the FPGA's jobs, one module each):
//   pin_link_agent   link protocol + external memory, tohost, pin checks
//   pin_uart_agent   console on uart_tx / input on uart_rx, fixed divisor
//   (this file)      clock, rst_n, irq[1:0], fault_inject, test_mode/scan_en,
//                    status monitor, command script, verdict
//
// 4-STATE.  Everything earlier ran 2-state (Verilator).  Here nothing is
// initialised that the board would not initialise: the DUT's flops start X,
// unwritten memory can read back X (mem_policy x), io_in can carry X between
// read words (+FPGA_IO_IDLE=x), and every pin the agents sample is
// checked with $isunknown.  Under Verilator all of this collapses to 2-state,
// so a Verilator pass proves the bench and the flow, not X-cleanliness.
//
// COMMAND SCRIPT (+CMD=<file>), one command per line, '#' comments:
//   mem_policy x|zero|rand          unwritten memory reads as X / 0 / hash
//   load_lst   <path>               bin/generate_memory_file.py -8 image
//   load_bin   <path> <hexaddr>     raw binary at a byte address
//   reset      <cycles>             hold rst_n low, then release
//   run        <cycles>
//   run_until_tohost <timeout>      tohost write seen on the link
//   run_until_uart   <timeout> <text...>
//   expect_tohost <code>            exit code (tohost >> 1) must equal <code>
//   uart_div   <n>                  16*(n<<UART_PRESCALE) core clocks per bit
//   uart_send  <text...>            \n and \r are expanded
//   uart_send_ferr <hex>            one byte with a framing error (stop bit 0)
//   uart_gap   <bits>               idle bit times between sent bytes
//   uart_fail  <text...>            fail the test if the console prints this
//   irq        <0|1> <0|1>          drive irq[i]
//   fault_inject <0|1>              the master enable pin
//   dump_mem   <hexaddr> <nbytes> <path>
//   dft_hold   <cycles>             a DFT hold session of <cycles> frozen
//                                   cycles (see "DFT hold" below); the
//                                   program must then finish as if untouched
//   dft_locked <cycles>             the same pin sequence on a part whose DFT
//                                   lock is cleared: it must be ignored
//   dft ...                         STUB: scan shifting is tested at gate
//                                   level (synth/scripts/full_tb on dft)
//   finish
// Without +CMD the bench runs: load_lst +MEMLST, reset 16,
// run_until_tohost +TIMEOUT, expect_tohost 0.
//
// VERDICT: one line, `PIN_TB_RESULT: PASS` or `PIN_TB_RESULT: FAIL <why>`.
// Scripts grep for it; a run that ends without it is a FAIL.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module pin_tb;
  import forte_link_pkg::*;

  // One burst length per build: DCACHE_LINELENINBITS / AHBW in pkg/config.vh
  // (128 / 64).  A netlist carries no parameters to read it from; under the
  // RTL the check below compares it with forte_chip's own.
  localparam int BEATS = 2;

  // ---- clock: 100 MHz unless +CLK_PS ----------------------------------------
  real  half_ns = 5.0;
  logic core_clk = 1'b0;
  initial begin
    int v;
    if ($value$plusargs("CLK_PS=%d", v)) half_ns = v / 2000.0;
    forever #(half_ns) core_clk = ~core_clk;
  end

  // ---- pins -----------------------------------------------------------------
  wire  [LINK_W-1:0] io_in, io_out;
  wire               req, wr, clk_out, uart_tx, status;
  wire               ready, rvalid;
  logic              link_ready, link_rvalid, uart_rx;
  // dft_hold pauses the link the way the tester must: ready first (no new
  // transaction), then rvalid once the agent is idle.  The agent is not reset.
  bit                link_hold_ready = 0, link_hold_rvalid = 0;
  assign ready  = link_hold_ready  ? 1'b0 : link_ready;
  assign rvalid = link_hold_rvalid ? 1'b0 : link_rvalid;
  // rst_n starts X and FALLS to 0 at 0.5 ns, before the first clock edge.  A
  // declaration initialiser (`= 1'b0`) is applied before any process starts
  // (IEEE 1800 6.8), so it produces no negedge: every asynchronous reset in the
  // chip would stay X until the first clock edge, which silicon -- where rst_n
  // is simply held low at power-up -- never does.  Under 2-state simulation
  // the difference is invisible.
  logic              rst_n;
  initial begin rst_n = 1'bx; #0.5 rst_n = 1'b0; end
  logic [1:0]        irq = 2'b00;
  logic              test_mode = 1'b0, scan_en = 1'b0, fault_inject = 1'b0;

  forte_top dut (
    .core_clk, .rst_n, .io_in, .io_out, .req, .clk_out, .wr, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx, .test_mode, .scan_en, .fault_inject, .status);

  pin_link_agent #(.BEATS(BEATS)) link (
    .core_clk, .clk_out, .rst_n, .io_out, .io_in, .req, .wr, .ready(link_ready), .rvalid(link_rvalid));

  pin_uart_agent uart (.core_clk, .rst_n, .uart_tx, .uart_rx);

`ifdef PIN_TB_RTL
  // Only the RTL has a forte_chip to ask.
  initial if (dut.chip.LINK_BEATS != BEATS)
    $fatal(1, "pin_tb: BEATS=%0d but forte_chip LINK_BEATS=%0d", BEATS, dut.chip.LINK_BEATS);
`endif

  // ---- knobs ----------------------------------------------------------------
  real    tco_ns     = 2.0;
  int     max_errors = 1;            // +MAX_ERRORS: stop at the first by default
  bit     x_in_reset = 0;
  longint cyc        = 0;            // core cycles since time 0
  int     errors     = 0;
  int     status_edges = 0;

  function automatic int total_errors();
    return errors + link.errors + uart.errors;
  endfunction

  function automatic void err(input string m);
    errors++;
    $display("[PIN_TB] ERROR @%0t cyc %0d: %s", $realtime, cyc, m);
  endfunction

  initial begin
    int v;
    if ($value$plusargs("FPGA_TCO_PS=%d", v)) tco_ns = v / 1000.0;
    if ($value$plusargs("MAX_ERRORS=%d", v))  max_errors = v;
    if ($test$plusargs("FPGA_X_IN_RESET"))    x_in_reset = 1;
    if (x_in_reset) begin irq = 'x; fault_inject = 1'bx; end
  end

  always @(posedge core_clk) cyc++;

`ifdef PIN_WAVES
  // Waveforms for chasing an X to its source (build with WAVES=1).  +PIN_FSDB
  // (VCS, below) writes wave.fsdb for Verdi; +PIN_VCD
  // dumps the DUT to pin.vcd from time 0 for +PIN_VCD_CYCLES core cycles
  // (default 400): a whole-chip VCD grows fast, and the first X is usually
  // early.  +PIN_VCD_CYCLES=0 dumps the whole run.
  initial if ($test$plusargs("PIN_VCD")) begin
    int n = 400;
    void'($value$plusargs("PIN_VCD_CYCLES=%d", n));
    $dumpfile("pin.vcd");
    $dumpvars(0, pin_tb);
    if (n > 0) begin repeat (n) @(posedge core_clk); $dumpoff; $dumpflush; end
  end
  // VCD output is buffered, and the run that needs a waveform usually ends in
  // a $fatal (the bench's or the design's) right where the X appears: flush
  // every 1000 cycles and at the end, or the interesting part is lost.
  initial if ($test$plusargs("PIN_VCD")) forever begin repeat (1000) @(posedge core_clk); $dumpflush; end
  final if ($test$plusargs("PIN_VCD")) $dumpflush;
`ifdef VCS
  // FSDB for Verdi: +PIN_FSDB dumps the whole bench, every cycle, to wave.fsdb
  // in the run directory (compact enough to keep the full run).  Open with
  // `verdi -ssf wave.fsdb`.  VCS links the dumper itself in a -kdb build.
  initial if ($test$plusargs("PIN_FSDB")) begin
    $fsdbDumpfile("wave.fsdb");
    $fsdbDumpvars(0, pin_tb);
  end
`endif
`endif

  // ---- status and output pin monitor -----------------------------------------
  // status cannot be checked for RATE here -- its slowest tap is 2^28 cycles --
  // only that it is never unknown once the chip is out of reset.  clk_out must
  // be a clean clock: X there would freeze the link agent silently.
  logic   status_q;
  longint since_rst = 0;
  always @(negedge core_clk) begin
    if (rst_n !== 1'b1) since_rst = 0;   // X (power-up) counts as in reset
    else begin
      since_rst++;
      if (since_rst > 4) begin
        if ($isunknown(status))  err($sformatf("status is %b", status));
        if ($isunknown(clk_out)) err($sformatf("clk_out is %b", clk_out));
        if (status !== status_q) status_edges++;
      end
      status_q = status;
    end
  end

  // ---- verdict ----------------------------------------------------------------
  bit done = 0;
  task automatic verdict(input bit pass, input string why);
    if (done) return;
    if (pass && cyc == 0) begin
      pass = 0;
      why = "no clock cycles executed";
    end
    done = 1;
    $display("[PIN_TB] cycles=%0d link_rd=%0d link_wr=%0d uart_rx=%0d uart_tx=%0d status_edges=%0d errors=%0d",
             cyc, link.n_rd, link.n_wr, uart.n_rx, uart.n_tx, status_edges, total_errors());
    if (pass && total_errors() == 0) begin
      $display("PIN_TB_RESULT: PASS");
      $finish;
    end else begin
      $display("PIN_TB_RESULT: FAIL %s", (pass ? $sformatf("%0d checker errors", total_errors()) : why));
      $fatal(1, "pin_tb failed");
    end
  endtask

  // Error watchdog: stop as soon as the error budget is spent, whatever the
  // script is waiting on -- a gate-level run should not burn an hour after
  // the first protocol error.
  always @(posedge core_clk)
    if (!done && total_errors() >= max_errors) verdict(0, $sformatf("%0d checker errors", total_errors()));

  // ---- command helpers ----------------------------------------------------------
  // Words of a line, and the remainder after the first n words (for <text...>).
  function automatic string rest_after(input string s, input int n);
    int i = 0;
    for (int w = 0; w < n; w++) begin
      while (i < s.len() && (s.getc(i) == " " || s.getc(i) == "\t")) i++;
      while (i < s.len() && !(s.getc(i) == " " || s.getc(i) == "\t")) i++;
    end
    while (i < s.len() && (s.getc(i) == " " || s.getc(i) == "\t")) i++;
    return (i < s.len()) ? s.substr(i, s.len() - 1) : "";
  endfunction

  function automatic string chomp(input string s);
    while (s.len() && (s.getc(s.len() - 1) == "\n" || s.getc(s.len() - 1) == "\r")) s = s.substr(0, s.len() - 2);
    return s;
  endfunction

  function automatic string unescape(input string s);
    string o = "";
    for (int i = 0; i < s.len(); i++) begin
      if (s.getc(i) == "\\" && i + 1 < s.len()) begin
        i++;
        case (s.getc(i))
          "n":     o = {o, "\n"};
          "r":     o = {o, "\r"};
          default: o = {o, $sformatf("%c", s.getc(i))};
        endcase
      end else o = {o, $sformatf("%c", s.getc(i))};
    end
    return o;
  endfunction

  task automatic run_cycles(input longint n);
    repeat (n) @(posedge core_clk);
  endtask

  // ---- DFT hold ---------------------------------------------------------------------
  // A hold session as the tester runs it (hdl/forte_chip.sv, "DFT HOLD"), with
  // no shifting: the RTL has no scan chains (DFT insertion builds them), and a
  // scan_en=1 edge in a hold clocks the scan registers' FUNCTIONAL D here, where
  // silicon would shift.  Shifting and reload are tested at gate level by
  // full_tb's phase S on the dft branch.  What this checks is the freeze: with
  // core_clk running for <cycles>, nothing in the core-clock domain may move,
  // and after the hold the program finishes exactly as an uninterrupted run
  // (compare the pin traces with `pin.sh compare --no-cycles`).
  //   1. link quiet: hold ready low, wait for the agent and the pins to be idle
  //      for 8 cycles, then hold rvalid low too
  //   2. arm: scan_en=1 for 3 cycles (test_mode low: no effect)
  //   3. enter: test_mode=1, scan_en=0, 3 cycles (2 functional, then frozen)
  //   4. <cycles> frozen cycles; req/wr must stay low
  //   5. exit: test_mode=0, 3 cycles (2 frozen, then functional); release link
  // PIN_TB_RTL checks representative state on every frozen edge.
  int dft_holds = 0;
`ifdef PIN_TB_RTL
  // Representative state, sampled on EVERY frozen clock, not just at exit.
  // SRAM contents are checked indirectly by the resumed program and pin trace.
  function automatic logic [1023:0] hold_state(input int group_id);
    case (group_id)
      0: return {dut.chip.soc.core.ifu.PCF, dut.chip.soc.core.ifu.PCD,
                 dut.chip.soc.core.ifu.PCE, dut.chip.soc.core.ifu.PCM,
                 dut.chip.soc.core.ifu.InstrD, dut.chip.soc.core.ifu.InstrM};
      1: return dut.chip.soc.uncore.clint.MTIME;
      2: return {dut.chip.soc.core.ifu.bus.icache.icache.cachefsm.CurrState,
                 dut.chip.soc.core.lsu.bus.dcache.dcache.cachefsm.CurrState};
      3: return {dut.chip.soc.core.ebu.ebu.ebufsmarb.CurrState,
                 dut.chip.linkcore.st, dut.chip.linkcore.bcnt, dut.chip.linkcore.pending};
      4: return {dut.chip.soc.core.FaultLfsr, dut.chip.soc.core.FaultCount,
                 dut.chip.soc.core.FTStatusSticky, dut.chip.soc.core.EccDedFaultM,
                 dut.chip.soc.core.EccDedFaultEPCM, dut.chip.soc.core.EccDedFaultMtvalM};
      5: return {dut.chip.soc.core.priv.priv.csr.csrm.MSECFAULT_REGW,
                 dut.chip.soc.core.priv.priv.csr.csrm.MSCRATCH_REGW,
                 dut.chip.soc.core.priv.priv.csr.csrm.MTVEC_REGW,
                 dut.chip.soc.core.priv.priv.csr.csrm.RAND_INSTR_INSERT_FREQ_REGW};
      6: return {dut.chip.soc.core.mdu.mdu.ftmul.phase,
                 dut.chip.soc.core.mdu.mdu.ftmul.primary.Acc,
                 dut.chip.soc.core.mdu.mdu.ftmul.primary.MQ,
                 dut.chip.soc.core.mdu.mdu.ftmul.primary.Cnt,
                 dut.chip.soc.core.mdu.mdu.div.ftdiv.phase,
                 dut.chip.soc.core.mdu.mdu.div.ftdiv.primary.state};
      7: return {dut.chip.soc.core.lsu.hptw.hptw.WalkerState,
                 dut.chip.soc.core.lsu.hptw.hptw.PTE};
      8: return {dut.chip.soc.uncore.onchip.plic.intPending,
                 dut.chip.soc.uncore.onchip.plic.intInProgress,
                 dut.chip.soc.uncore.faultcount.Count};
      default: return 'x;
    endcase
  endfunction
`endif
  task automatic dft_hold(input longint n);
    int quiet = 0;
    int waited = 0;
    int quiet_timeout = 10000;
    int frozen_se = 0;
`ifdef PIN_TB_RTL
    logic [1023:0] state0 [0:8];
    logic [$bits(dut.chip.soc.core.ieu.dp.regf.rf[1])-1:0] rf0 [1:$size(dut.chip.soc.core.ieu.dp.regf.rf)];
    int  nrf = $size(dut.chip.soc.core.ieu.dp.regf.rf);
`endif
    if (n < 1) begin err("dft_hold: cycles must be positive"); return; end
    void'($value$plusargs("DFT_QUIET_TIMEOUT=%d", quiet_timeout));
    void'($value$plusargs("DFT_HOLD_SE=%d", frozen_se));
    if (!(frozen_se inside {0, 1})) begin err("dft_hold: DFT_HOLD_SE must be 0 or 1"); return; end
    if (quiet_timeout < 8) begin err("dft_hold: DFT_QUIET_TIMEOUT must be >= 8"); return; end
    @(posedge core_clk); #(tco_ns);
    link_hold_ready = 1;
    while (quiet < 8) begin
      @(posedge core_clk);
      quiet = (int'(link.st) === 0 && req === 1'b0 && link_rvalid === 1'b0) ? quiet + 1 : 0;
      waited++;
      if (quiet < 8 && waited >= quiet_timeout) begin
        err("dft_hold: timeout waiting for a quiet link"); return;
      end
    end
    #(tco_ns);
    link_hold_rvalid = 1;
    scan_en = 1'b1;
    run_cycles(3); #(tco_ns);
    test_mode = 1'b1; scan_en = 1'b0;
    run_cycles(3); #(tco_ns);
    scan_en = (frozen_se != 0);
`ifdef PIN_TB_RTL
    if (dut.chip.hold !== 1'b1) err("dft_hold: hold did not assert");
    $display("[PIN_TB] hold entry pc=%h icache=%0d dcache=%0d mul_busy=%b div_state=%0d walker=%0d se=%b",
             dut.chip.soc.core.ifu.PCF,
             dut.chip.soc.core.ifu.bus.icache.icache.cachefsm.CurrState,
             dut.chip.soc.core.lsu.bus.dcache.dcache.cachefsm.CurrState,
             dut.chip.soc.core.mdu.mdu.ftmul.primary.Busy,
             dut.chip.soc.core.mdu.mdu.div.ftdiv.primary.state,
             dut.chip.soc.core.lsu.hptw.hptw.WalkerState, scan_en);
    for (int g = 0; g < 9; g++) state0[g] = hold_state(g);
    for (int i = 1; i <= nrf; i++) rf0[i] = dut.chip.soc.core.ieu.dp.regf.rf[i];
`endif
    for (longint c = 0; c < n; c++) begin
      @(posedge core_clk); #(tco_ns);
      if (req !== 1'b0 || wr !== 1'b0) err($sformatf("dft_hold: req=%b wr=%b during the hold", req, wr));
`ifdef PIN_TB_RTL
      if (dut.chip.hold !== 1'b1) err("dft_hold: hold dropped early");
      for (int g = 0; g < 9; g++)
        if (hold_state(g) !== state0[g]) err($sformatf("dft_hold: state group %0d changed at frozen cycle %0d", g, c));
      for (int i = 1; i <= nrf; i++)
        if (dut.chip.soc.core.ieu.dp.regf.rf[i] !== rf0[i])
          err($sformatf("dft_hold: x%0d changed at frozen cycle %0d", i, c));
      if ({dut.chip.soc.core.StallF, dut.chip.soc.core.StallD, dut.chip.soc.core.StallE,
           dut.chip.soc.core.StallM, dut.chip.soc.core.StallW} !== 5'b11111 ||
          {dut.chip.soc.core.FlushD, dut.chip.soc.core.FlushE,
           dut.chip.soc.core.FlushM, dut.chip.soc.core.FlushW} !== 4'b0000)
        err("dft_hold: pipeline stall/flush controls do not preserve state");
      if (dut.chip.soc.uncore.PSELP !== '0 || dut.chip.ofifo.wvalid_i !== 1'b0 ||
          dut.chip.ififo.rready_i !== 1'b0 || dut.chip.soc.core.ieu.dp.regf.WriteEn !== 1'b0)
        err("dft_hold: APB/FIFO/register-file write enables active");
      if ((dut.chip.soc.core.ifu.bus.icache.icache.CacheEnArray &&
           (dut.chip.soc.core.ifu.bus.icache.icache.TagWe || dut.chip.soc.core.ifu.bus.icache.icache.DataWe)) ||
          (dut.chip.soc.core.lsu.bus.dcache.dcache.CacheEnArray &&
           (dut.chip.soc.core.lsu.bus.dcache.dcache.TagWe || dut.chip.soc.core.lsu.bus.dcache.dcache.DataWe)))
        err("dft_hold: cache array write enabled");
`endif
    end
    @(posedge core_clk); #(tco_ns);
    test_mode = 1'b0; scan_en = 1'b0;
    run_cycles(3); #(tco_ns);
`ifdef PIN_TB_RTL
    if (dut.chip.hold !== 1'b0) err("dft_hold: hold did not release");
`endif
    link_hold_ready = 0; link_hold_rvalid = 0;
    dft_holds++;
    $display("[PIN_TB] dft_hold %0d: %0d frozen cycles", dft_holds, n);
  endtask

  // dft_locked <cycles>: drive test_mode/scan_en exactly as a hold entry and a
  // scan shift would (scan_en toggling every cycle), on a part whose software
  // has cleared the DFT lock (hdl/forte_dft_lock.sv).  Nothing may happen: the
  // link is not paused, because a locked part must keep running.  RTL checks
  // the gated controls every cycle; on any build the script checks that the
  // program kept running (hvl/pin/tests/dft_lock.cmd).
  task automatic dft_locked(input longint n);
    if (n < 1) begin err("dft_locked: cycles must be positive"); return; end
    @(posedge core_clk); #(tco_ns);
    scan_en = 1'b1;
    run_cycles(3); #(tco_ns);
    test_mode = 1'b1; scan_en = 1'b0;
    for (longint c = 0; c < n; c++) begin
      @(posedge core_clk); #(tco_ns);
      scan_en = c[0];
`ifdef PIN_TB_RTL
      if (dut.chip.test_mode_dft !== 1'b0) err($sformatf("dft_locked: test_mode reached the chip at cycle %0d", c));
      if (dut.chip.scan_en_dft   !== 1'b0) err($sformatf("dft_locked: scan_en reached the chains at cycle %0d", c));
      if (dut.chip.hold          !== 1'b0) err($sformatf("dft_locked: the chip entered a DFT hold at cycle %0d", c));
`endif
    end
    test_mode = 1'b0; scan_en = 1'b0;
    run_cycles(3);
    $display("[PIN_TB] dft_locked: %0d cycles of test_mode/scan_en ignored", n);
  endtask

  // ---- the command interpreter ----------------------------------------------------
  int  exit_code = -1;
  int commands_executed = 0;

  task automatic exec(input string raw, input int lineno);
    string  ln, cmd, a1, a2, a3;
    int     rc;
    longint t, v;
    logic [63:0] addr;
    ln = chomp(raw);
    // Parse optional words separately: some simulator versions return EOF
    // for a multi-word scan with fewer inputs than conversions, even after
    // successfully reading the command. Never skip a valid short command.
    if ($sscanf(ln, "%s", cmd) != 1 || cmd.getc(0) == "#") return;
    void'($sscanf(rest_after(ln, 1), "%s", a1));
    void'($sscanf(rest_after(ln, 2), "%s", a2));
    void'($sscanf(rest_after(ln, 3), "%s", a3));
    commands_executed++;
    $display("[PIN_TB] cmd %0d: %s", lineno, ln);
    case (cmd)
      "mem_policy": link.mem_policy = a1;
      "load_lst": begin
        rc = link.load_lst(a1);
        if (rc <= 0) err($sformatf("load_lst %s: %s", a1, rc < 0 ? "cannot open" : "no words"));
        else $display("[PIN_TB] loaded %0d words from %s", rc, a1);
      end
      "load_bin": begin
        void'($sscanf(a2, "%h", addr));
        rc = link.load_bin(a1, addr);
        if (rc <= 0) err($sformatf("load_bin %s: %s", a1, rc < 0 ? "cannot open" : "empty"));
        else $display("[PIN_TB] loaded %0d bytes from %s at %h", rc, a1, addr);
      end
      "reset": begin
        void'($sscanf(a1, "%d", t));
        @(posedge core_clk); #(tco_ns);
        rst_n = 1'b0;
        link.tohost_seen = 0; link.tohost_val = '0; exit_code = -1;
        if (x_in_reset) begin irq = 'x; fault_inject = 1'bx; end
        run_cycles(t);
        // Inputs are defined from the cycle before release on.
        #(tco_ns);
        if (x_in_reset) begin irq = 2'b00; fault_inject = 1'b0; end
        @(posedge core_clk); #(tco_ns);
        rst_n = 1'b1;
      end
      "run": begin void'($sscanf(a1, "%d", t)); run_cycles(t); end
      "run_until_tohost": begin
        // tohost_seen is cleared by `reset` only, so a tohost that landed while
        // an earlier command was waiting (e.g. on the console) still counts.
        void'($sscanf(a1, "%d", t));
        for (v = 0; v < t && !link.tohost_seen; v++) @(posedge core_clk);
        if (!link.tohost_seen) verdict(0, $sformatf("timeout: no tohost write in %0d cycles", t));
        exit_code = int'(link.tohost_val >> 1);
        $display("[PIN_TB] tohost = %h (exit code %0d) after %0d cycles", link.tohost_val, exit_code, v);
        if (link.tohost_val[0] !== 1'b1) err($sformatf("tohost %h has bit 0 clear", link.tohost_val));
      end
      "run_until_uart": begin
        void'($sscanf(a1, "%d", t));
        uart.want = unescape(rest_after(ln, 2)); uart.want_hit = 0;
        for (v = 0; v < t && !uart.want_hit; v++) @(posedge core_clk);
        if (!uart.want_hit) verdict(0, $sformatf("timeout: console never printed \"%s\" in %0d cycles", uart.want, t));
        $display("[PIN_TB] console printed \"%s\" after %0d cycles", uart.want, v);
        uart.want = "";
      end
      "expect_tohost": begin
        void'($sscanf(a1, "%d", v));
        if (exit_code != int'(v)) err($sformatf("exit code %0d, expected %0d", exit_code, v));
      end
      "uart_div":  begin void'($sscanf(a1, "%d", v)); uart.div = int'(v); end
      "uart_send": uart.send(unescape(rest_after(ln, 1)));
      "uart_send_ferr": begin void'($sscanf(a1, "%h", v)); uart.send_ferr(byte'(v)); end
      "uart_gap":  begin void'($sscanf(a1, "%d", v)); uart.tx_gap = int'(v); end
      "uart_fail": uart.fail_pat.push_back(unescape(rest_after(ln, 1)));
      "irq": begin
        void'($sscanf(a1, "%d", v)); void'($sscanf(a2, "%d", t));
        @(posedge core_clk); #(tco_ns);
        irq[v] = t[0];
        if (link.trace_fd) $fdisplay(link.trace_fd, "I %0d %0d %0d", link.cyc, v, t[0]);
      end
      "fault_inject": begin
        void'($sscanf(a1, "%d", v));
        @(posedge core_clk); #(tco_ns);
        fault_inject = v[0];
      end
      "dump_mem": begin
        void'($sscanf(a1, "%h", addr)); void'($sscanf(a2, "%d", v));
        if (link.dump(addr, int'(v), a3) != 0) err($sformatf("dump_mem: cannot write %s", a3));
      end
      "dft_hold": begin void'($sscanf(a1, "%d", t)); dft_hold(t); end
      "dft_locked": begin void'($sscanf(a1, "%d", t)); dft_locked(t); end
      "dft":    err("dft: scan shifting is tested at gate level (synth/scripts/full_tb on the dft branch)");
      "finish": verdict(1, "");
      default:  err($sformatf("line %0d: unknown command '%s'", lineno, cmd));
    endcase
  endtask

  initial begin : script
    string path, line, s;
    int    fd, lineno = 0;
    longint to = 10_000_000;
    #1;    // let every agent read its plusargs first (rst_n is low meanwhile)
    if ($value$plusargs("CMD=%s", path)) begin
      fd = $fopen(path, "r");
      if (fd == 0) verdict(0, $sformatf("cannot open command script %s", path));
      while ($fgets(line, fd)) begin
        lineno++;
        exec(line, lineno);
        if (done) break;
      end
      $fclose(fd);
    end else begin
      if (!$value$plusargs("MEMLST=%s", s)) verdict(0, "neither +CMD nor +MEMLST given");
      void'($value$plusargs("TIMEOUT=%d", to));
      exec({"load_lst ", s}, 1);
      exec("reset 16", 2);
      exec($sformatf("run_until_tohost %0d", to), 3);
      exec("expect_tohost 0", 4);
    end
    if (commands_executed == 0 || cyc == 0) verdict(0, "no commands or clock cycles executed");
    verdict(1, "");
  end

endmodule
