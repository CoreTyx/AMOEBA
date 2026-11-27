///////////////////////////////////////////////////////////////////////////////
// pin_uart_agent.sv
//
// The FPGA's serial transceiver on the chip's uart_tx / uart_rx pins: 8N1 at a
// FIXED divisor, matching the on-chip uartPC16550D's bit time of
// 16 * (divisor << UART_PRESCALE) core clocks.  UART_PRESCALE is 1 in
// pkg/config.vh, so one bit is 32 core clocks at divisor 1.  The agent cannot see the divisor register (pins only), so the
// software and the command script must agree on it: FreeRTOS and the ISA tests
// never program it (reset DLL=1, so div 1); the soft-float Linux image pins it
// with current-speed in the DTS so OpenSBI and the kernel never change it.
// A wrong divisor shows up at once as a framing error, which is an ERROR, and
// the report names the shortest low run seen -- which is the actual bit time.
//
// RX samples the pin at the core_clk NEGEDGE (mid-cycle, race-free in RTL and
// netlist alike), or +UART_SAMPLE_PS after the posedge when given (postpnr/run.sh:
// T - output_delay(max) of uart_tx, from the SDC).  TX launches TCO after the
// posedge, like every FPGA output.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module pin_uart_agent (
  input  logic core_clk,
  input  logic rst_n,
  input  wire  uart_tx,          // chip -> agent
  output logic uart_rx           // agent -> chip
);

  int     div        = 1;        // +UART_DIV
  int     prescale   = 1;        // +UART_PRESCALE; pkg/config.vh UART_PRESCALE
  int     tx_gap     = 0;        // +UART_TX_GAP: idle bit times between sent bytes
  real    tco_ns     = 2.0;
  real    smp_ns     = -1.0;     // +UART_SAMPLE_PS; < 0: sample at the negedge
  string  log_path   = "uart.log";
  bit     echo       = 1;        // copy the console to stdout

  int     errors     = 0;
  string  last_err   = "";
  string  first_err  = "";
  int     n_rx = 0, n_tx = 0;
  int     log_fd     = 0;
  string  line       = "";       // current console line, for stdout
  string  want       = "";       // pattern run_until_uart is waiting for
  bit     want_hit   = 0;
  string  fail_pat[$];           // patterns that fail the test on sight
  int     min_low    = 0;        // shortest low run seen, in core cycles
  int     txq[$];               // bits 7:0 the byte; bit 8 = send it with a bad (0) stop bit
  longint cyc        = 0;
  longint idle_cyc   = 0;        // uart_tx samples high since the last frame ended
  string  tail       = "";       // last chars, for pattern matching

  function automatic int bit_cyc(); return 16 * (div << prescale); endfunction
  function automatic int frame_cyc(); return 10 * bit_cyc(); endfunction

  function automatic void err(input string m);
    errors++;
    if (errors == 1) first_err = m;
    last_err = m;
    $display("[FPGA-UART] ERROR @%0t: %s", $realtime, m);
  endfunction

  function automatic bit ends_with(input string s, input string p);
    if (p.len() == 0 || s.len() < p.len()) return 0;
    return s.substr(s.len() - p.len(), s.len() - 1) == p;
  endfunction

  function automatic void got(input byte c);
    n_rx++;
    if (log_fd) begin $fwrite(log_fd, "%c", c); $fflush(log_fd); end
    tail = {tail, $sformatf("%c", c)};
    if (tail.len() > 256) tail = tail.substr(tail.len() - 256, tail.len() - 1);
    if (want.len() && ends_with(tail, want)) want_hit = 1;
    foreach (fail_pat[i]) if (ends_with(tail, fail_pat[i])) err($sformatf("console printed fail pattern \"%s\"", fail_pat[i]));
    if (c == 8'h0A) begin
      if (echo) $display("[UART] %s", line);
      line = "";
    end else if (c != 8'h0D) line = {line, $sformatf("%c", c)};
  endfunction

  // One byte with a framing error: stop bit driven 0 for one bit time.
  function automatic void send_ferr(input byte c);
    txq.push_back((int'(c) & 'hFF) | 'h100);
  endfunction

  function automatic void send(input string s);
    for (int i = 0; i < s.len(); i++) txq.push_back(int'(s.getc(i)) & 'hFF);
  endfunction

  initial begin
    int v;
    if ($value$plusargs("UART_DIV=%d", v)) div = v;
    if ($value$plusargs("UART_PRESCALE=%d", v)) prescale = v;
    if ($value$plusargs("UART_TX_GAP=%d", v)) tx_gap = v;
    if ($value$plusargs("FPGA_TCO_PS=%d", v)) tco_ns = v / 1000.0;
    if ($value$plusargs("UART_SAMPLE_PS=%d", v)) smp_ns = v / 1000.0;
    if ($value$plusargs("UART_LOG=%s", log_path)) ;
    if ($test$plusargs("UART_QUIET")) echo = 0;
    log_fd = $fopen(log_path, "w");
    uart_rx = 1'b1;
  end

  // ---- RX: chip -> agent ----------------------------------------------------
  task automatic rx_sample_point();
    if (smp_ns < 0.0) @(negedge core_clk);
    else begin @(posedge core_clk); #(smp_ns); end
  endtask

  initial begin : rx
    longint t_fall, low_run;
    logic   s, prev;
    byte    c;
    int     k, b;
    // No initialised declarations in here: this is a static block, so an
    // initialiser runs once at time 0, not per iteration (IEEE 1800 6.21).
    // VCS honours that and Verilator does not, which hid exactly that bug.
    prev = 1'b1;
    forever begin
      rx_sample_point();
      s = uart_tx;
      if (rst_n !== 1'b1) begin prev = 1'b1; idle_cyc = 0; continue; end   // X (power-up) counts as in reset
      cyc++;
      if ($isunknown(s)) begin err($sformatf("uart_tx is %b", s)); prev = 1'b1; idle_cyc = 0; continue; end
      if (s == 1'b1) idle_cyc++;
      else idle_cyc = 0;
      if (prev == 1'b1 && s == 1'b0) begin
        // Start bit.  Sample the middle of every bit from here, cycle by cycle.
        t_fall = cyc; low_run = 0; c = 0;
        for (k = 0; k <= 9 * bit_cyc() + bit_cyc() / 2; k++) begin
          // k counts cycles since the falling edge; bit b's middle is at
          // (b + 0.5) * bit_cyc.  b = 0 is the start bit, 1..8 data, 9 stop.
          if (k > 0) begin rx_sample_point(); s = uart_tx; cyc++; end
          if (s == 1'b0) low_run++;
          else if (low_run) begin
            if (min_low == 0 || low_run < min_low) min_low = int'(low_run);
            low_run = 0;
          end
          if (k % bit_cyc() == bit_cyc() / 2) begin
            b = k / bit_cyc();
            if ($isunknown(s)) err($sformatf("uart_tx is %b in bit %0d", s, b));
            if (b == 0 && s != 1'b0) begin err("start bit glitch"); break; end
            if (b >= 1 && b <= 8) c[b - 1] = s;
          end
        end
        // stop bit
        if (s !== 1'b1) err($sformatf("framing error at div %0d (shortest low run %0d cycles = div %0d?)",
                                      div, min_low, min_low / (16 << prescale)));
        else got(c);
        prev = s;
        idle_cyc = 0;
      end else prev = s;
    end
  end

  // ---- TX: agent -> chip ----------------------------------------------------
  initial begin : tx
    byte c;
    int  e;
    forever begin
      // The queue is looked at mid-cycle, not at the posedge: uart_send
      // queues bytes right after a posedge, and whether this process or the
      // script runs first at that edge is the simulator's choice -- an RTL
      // and a netlist build chose differently and sent a cycle apart.
      @(negedge core_clk);
      if (rst_n !== 1'b1 || txq.size() == 0) continue;
      e = txq.pop_front();
      c = e[7:0];
      n_tx++;
      @(posedge core_clk);
      for (int b = 0; b < 10; b++) begin
        #(tco_ns);
        uart_rx = (b == 0) ? 1'b0 : (b == 9) ? ~e[8] : c[b - 1];
        repeat (bit_cyc()) @(posedge core_clk);
      end
      // Back to idle-high: after a bad (0) stop bit the line would otherwise
      // stay low, which the receiver rightly reads as a break.
      if (e[8]) begin #(tco_ns); uart_rx = 1'b1; end
      repeat (tx_gap * bit_cyc()) @(posedge core_clk);
    end
  end

  final begin
    if (line.len() && echo) $display("[UART] %s", line);
    if (log_fd) $fclose(log_fd);
  end

endmodule
