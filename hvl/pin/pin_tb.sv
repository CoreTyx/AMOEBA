///////////////////////////////////////////////////////////////////////////////
// pin_tb.sv
//
// Pin-only testbench for forte_top: the bring-up FPGA in simulation.  The DUT
// is touched through its pads and nothing else, so the same bench runs the RTL
// (`forte_top` from hdl/) and the synthesized or placed-and-routed netlist,
// selected purely by the file list.  There is no RVFI, no Spike and no
// hierarchical probe here -- correctness of the program itself is established
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
// unwritten memory can read back X (mem_policy x), the bus floats Z whenever
// the protocol says nobody drives it, and every pin the agents sample is
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
//   uart_gap   <bits>               idle bit times between sent bytes
//   uart_fail  <text...>            fail the test if the console prints this
//   irq        <0|1> <0|1>          drive irq[i]
//   fault_inject <0|1>              the master enable pin
//   dump_mem   <hexaddr> <nbytes> <path>
//   dft ...                         STUB: DFT/scan is not yet testable
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
  wire  [LINK_W-1:0] io;
  wire               dir, req, wr, clk_out, uart_tx, status;
  logic              ready, rvalid, uart_rx;
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
    .core_clk, .rst_n, .io, .dir, .req, .clk_out, .wr, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx, .test_mode, .scan_en, .fault_inject, .status);

  pin_link_agent #(.BEATS(BEATS)) link (
    .core_clk, .clk_out, .rst_n, .io, .dir, .req, .wr, .ready, .rvalid);

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

  // ---- the command interpreter ----------------------------------------------------
  int  exit_code = -1;

  task automatic exec(input string raw, input int lineno);
    string  ln, cmd, a1, a2, a3;
    int     n, rc;
    longint t, v;
    logic [63:0] addr;
    ln = chomp(raw);
    n = $sscanf(ln, "%s %s %s %s", cmd, a1, a2, a3);
    if (n < 1 || cmd.getc(0) == "#") return;
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
      "dft":    err("dft: DFT/scan testing is a stub until the DFT flow lands");
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
    verdict(1, "");
  end

endmodule
