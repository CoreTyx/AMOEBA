///////////////////////////////////////////////////////////////////////////////
// pin_selftest_tb.sv -- the harness tested without the chip.
//
// pin_link_agent and pin_uart_agent are the FPGA side of every post-synthesis
// result, so they are tested against independent models before anything they
// say about the netlist is believed.
//
//   link   asic_bfm below plays the chip's side of hdl/forte_link_pkg.sv the
//          way forte_link_phy does (idle: dir=1, io=0; read: dir falls after
//          the header, TA, words on rvalid, TA, dir rises), issues random
//          line reads and writes, and checks every read against a shadow
//          memory.  Also: .lst loading, mem_policy rand stability.
//   uart   reference serialiser/deserialiser written independently of the
//          agent, random bytes both ways at several divisors.
//   negative (+VIOLATE=<n>): the models break one rule on purpose, and the
//          run passes only if the agent reports it with the expected message.
//          A checker that cannot fail is not a checker.
//
// Verdict: `SELFTEST_RESULT: PASS|FAIL <why>`, same convention as pin_tb.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module pin_selftest_tb;
  import forte_link_pkg::*;

  localparam int BEATS = 2;
  localparam int WORDS = 4 * BEATS;
  localparam int LINE  = 8 * BEATS;

  logic clk = 0;
  always #5 clk = ~clk;

  logic rst_n = 0;
  wire  [LINK_W-1:0] io;
  logic dir = 1, req = 0, wr = 0;
  wire  ready, rvalid;
  logic [LINK_W-1:0] bfm_io = '0;
  logic bfm_oe = 1;
  assign io = bfm_oe ? bfm_io : 'z;

  pin_link_agent #(.BEATS(BEATS)) link (
    .core_clk(clk), .clk_out(clk), .rst_n, .io, .dir, .req, .wr, .ready, .rvalid);

  wire  u_tx;           // reference TX -> agent RX (the chip's uart_tx)
  logic u_tx_drv = 1;
  assign u_tx = u_tx_drv;
  wire  u_rx;           // agent TX -> reference RX (the chip's uart_rx)
  pin_uart_agent uart (.core_clk(clk), .rst_n, .uart_tx(u_tx), .uart_rx(u_rx));

  int violate = 0;
  int fails   = 0;
  int n_checks = 0;

  function automatic void fail(input string m);
    fails++;
    $display("[SELFTEST] FAIL: %s", m);
  endfunction

  // ---- chip-side link model -------------------------------------------------
  // Drives on the posedge (as the phy's registers do), samples the agent's
  // outputs at the negedge (as the phy's inbound capture does).
  logic s_ready, s_rvalid;
  logic [LINK_W-1:0] s_io;
  always @(negedge clk) begin s_ready = ready; s_rvalid = rvalid; s_io = io; end

  task automatic tick(); @(posedge clk); #0.1; endtask

  task automatic idle();
    dir = 1; bfm_oe = 1; bfm_io = '0; req = 0; wr = 0;
  endtask

  task automatic header(input logic [31:0] a, input logic w, input bit short_req = 0);
    int waited = 0;
    if (violate == 7) begin
      // req long after ready fell: hold ready low, then start anyway.
      link.gap_pct = 100;
      repeat (8) tick();
    end else
      while (s_ready !== 1'b1) begin tick(); waited++; if (waited > 1000) begin fail("ready never rose"); return; end end
    req = 1; wr = w; bfm_io = a[31:16]; tick();
    if (violate == 7) link.gap_pct = 0;               // let the transaction finish
    if (!short_req) begin bfm_io = a[15:0]; tick(); end
  endtask

  task automatic line_write(input logic [31:0] a, input logic [63:0] d[BEATS]);
    header(a, 1);
    req = 0;
    for (int i = 0; i < WORDS; i++) begin
      bfm_io = d[i / 4][16 * (i % 4) +: 16];
      if (violate == 6 && i == 3) bfm_io = 'x;        // X on the bus mid-write (4-state only)
      tick();
    end
    idle();
  endtask

  task automatic line_read(input logic [31:0] a, output logic [63:0] d[BEATS]);
    int got = 0, guard = 0;
    header(a, 0);
    req = 0; wr = 0; dir = 0; bfm_oe = 0; bfm_io = '0;
    while (got < WORDS) begin
      tick();
      if (violate == 8 && got == 2) begin dir = 1; bfm_oe = 1; end   // grab the bus mid-read
      if (s_rvalid === 1'b1) begin d[got / 4][16 * (got % 4) +: 16] = s_io; got++; end
      if (++guard > 2000) begin fail($sformatf("read %08h: only %0d words arrived", a, got)); break; end
    end
    if (violate == 3) begin idle(); tick(); end      // take the bus back before TA
    else begin repeat (TA) tick(); idle(); end
    tick();
  endtask

  // ---- link test -------------------------------------------------------------
  logic [63:0] shadow [longint unsigned];

  task automatic link_random(input int n, input int unsigned seed);
    logic [63:0] d[BEATS], q[BEATS];
    logic [31:0] a;
    int unsigned s = seed;
    for (int t = 0; t < n; t++) begin
      s = s * 1664525 + 1013904223;
      // 64 lines in one region plus the far end of EXT_MEM, so lines are revisited
      a = (s[20]) ? 32'h8FFF_FC00 + 32'((s >> 8) % 64) * LINE : 32'h8010_0000 + 32'((s >> 8) % 64) * LINE;
      if (s[5]) begin
        for (int b = 0; b < BEATS; b++) begin s = s * 1664525 + 1013904223; d[b] = {s, ~s ^ 32'(t)}; shadow[(a >> 3) + b] = d[b]; end
        line_write(a, d);
      end else begin
        line_read(a, q);
        for (int b = 0; b < BEATS; b++) begin
          logic [63:0] e = shadow.exists((a >> 3) + b) ? shadow[(a >> 3) + b] : '0;
          n_checks++;
          if (q[b] !== e) fail($sformatf("read %08h beat %0d: got %h, expected %h", a, b, q[b], e));
        end
      end
    end
  endtask

  // ---- reference UART (independent of pin_uart_agent) ----------------------
  int ubit;     // core clocks per bit
  task automatic ref_send(input byte c, input bit bad_stop = 0, input bit x_bit = 0);
    @(posedge clk);
    for (int b = 0; b < 10; b++) begin
      u_tx_drv = (b == 0) ? 1'b0 : (b == 9) ? ~bad_stop : c[b - 1];
      if (x_bit && b == 4) u_tx_drv = 1'bx;
      repeat (ubit) @(posedge clk);
    end
  endtask

  byte ref_got[$];
  initial begin : ref_rx
    byte c;
    forever begin
      @(negedge u_rx);
      repeat (ubit / 2) @(posedge clk);
      if (u_rx !== 1'b0) continue;
      for (int b = 0; b < 8; b++) begin repeat (ubit) @(posedge clk); c[b] = u_rx; end
      repeat (ubit) @(posedge clk);
      if (u_rx !== 1'b1) fail("agent TX: stop bit not 1");
      ref_got.push_back(c);
    end
  end

  task automatic uart_test(input int div);
    string hello = "Hello, FPGA!\n";
    byte sent[$];
    int  n0 = uart.n_rx;
    string want = "";
    uart.div = div; ubit = 16 * (div << uart.prescale);
    // reference -> agent
    for (int i = 0; i < 24; i++) begin
      byte c = byte'((i * 37 + div) & 8'hFF);
      if (c == 8'h0A || c == 8'h0D) c = 8'h41;
      sent.push_back(c); ref_send(c);
    end
    repeat (ubit) @(posedge clk);
    if (uart.n_rx - n0 != 24) fail($sformatf("div %0d: agent received %0d of 24 bytes", div, uart.n_rx - n0));
    for (int i = 0; i < 24; i++) want = {want, $sformatf("%c", sent[i])};
    n_checks++;
    if (uart.tail.substr(uart.tail.len() - 24, uart.tail.len() - 1) != want) fail($sformatf("div %0d: agent decoded wrong bytes", div));
    // agent -> reference
    ref_got.delete();
    uart.send(hello);
    repeat (14 * 11 * ubit) @(posedge clk);
    n_checks++;
    if (ref_got.size() != 13) fail($sformatf("div %0d: reference received %0d of 13 bytes", div, ref_got.size()));
    else foreach (ref_got[i]) if (ref_got[i] != hello.getc(i)) fail($sformatf("div %0d: byte %0d is %h", div, i, ref_got[i]));
  endtask

  // ---- negative runs -------------------------------------------------------------
  // Each violation names the substring its error message must contain.
  function automatic string expect_msg(input int v);
    case (v)
      1:  return "req while dir=0";
      2:  return "req dropped after one header word";
      3:  return "dir rose";
      4:  return "outside EXT_MEM";
      5:  return "not line-aligned";
      6:  return "X/Z on io in write word";
      7:  return "after ready fell";
      8:  return "contention";
      9:  return "first transaction";
      10: return "framing error";
      11: return "uart_tx is";
      12: return "X/Z on dir/req/wr";
      13: return "watchdog";
      default: return "";
    endcase
  endfunction

  task automatic negative(input int v);
    logic [63:0] d[BEATS], q[BEATS];
    d[0] = 64'h1; d[1] = 64'h2;
    case (v)
      1: begin header(32'h8000_0000, 0); end          // see below: dir dropped first
      2: begin header(32'h8000_0000, 0, 1); req = 0; repeat (4) tick(); end
      3, 8: line_read(32'h8000_0000, q);
      4: begin line_read(32'h8000_0000, q); line_write(32'h9000_0000, d); end
      5: begin line_read(32'h8000_0000, q); line_write(32'h8000_0008, d); end
      6: begin line_read(32'h8000_0000, q); line_write(32'h8000_0010, d); end
      7: line_read(32'h8000_0000, q);
      9: line_write(32'h8000_0000, d);
      10: begin uart.div = 1; ubit = 16 * (1 << uart.prescale); ref_send(8'h55, 1); repeat (2 * ubit) @(posedge clk); end
      11: begin uart.div = 1; ubit = 16 * (1 << uart.prescale); ref_send(8'h55, 0, 1); repeat (2 * ubit) @(posedge clk); end
      12: begin tick(); wr = 1'bx; tick(); tick(); wr = 0; end
      13: begin header(32'h8000_0000, 0); req = 0; repeat (1100) tick(); end   // read, bus never released
    endcase
    repeat (4) tick();
  endtask

  // ---- sequence ---------------------------------------------------------------------
  initial begin
    int fd;
    string why;
    void'($value$plusargs("VIOLATE=%d", violate));
    link.mem_policy = "zero";
    uart.echo = 0;
    // 4-state-only checks cannot fire under a 2-state simulator.
`ifdef VERILATOR
    if (violate == 6 || violate == 11 || violate == 12) begin
      $display("SELFTEST_RESULT: PASS (violation %0d needs a 4-state simulator: skipped)", violate);
      $finish;
    end
`endif
    if (violate == 1) dir = 0;
    repeat (4) @(posedge clk);
    #2 rst_n = 1;
    repeat (4) @(posedge clk);

    if (violate) begin
      negative(violate);
      n_checks++;
      if (link.errors + uart.errors == 0)
        fail($sformatf("violation %0d (%s) was not reported", violate, expect_msg(violate)));
      // The FIRST error must be the violation itself; later ones are fallout.
      else if (!has(link.first_err, expect_msg(violate)) && !has(uart.first_err, expect_msg(violate)))
        fail($sformatf("violation %0d first reported as '%s%s', expected '%s'", violate, link.first_err, uart.first_err, expect_msg(violate)));
    end else begin
      // First transaction must be the reset-vector fetch, as the chip's is.
      begin logic [63:0] q[BEATS]; line_read(32'h8000_0000, q); end
      link_random(400, 1);
      link.gap_pct = 30; link.rd_latency = 5;
      link_random(400, 2);
      link.gap_pct = 0; link.rd_latency = 0;

      // .lst loading: write a file, load it, read it back over the link.
      fd = $fopen("selftest.lst", "w");
      $fdisplay(fd, "@%h", (64'h8020_0000 >> 3));
      for (int i = 0; i < 2 * BEATS; i++) $fdisplay(fd, "%016h", 64'hC0DE_0000_0000_0000 | 64'(i));
      $fclose(fd);
      n_checks++;
      if (link.load_lst("selftest.lst") != 2 * BEATS) fail("load_lst word count");
      for (int l = 0; l < 2; l++) begin
        logic [63:0] q[BEATS];
        line_read(32'h8020_0000 + 32'(l * LINE), q);
        for (int b = 0; b < BEATS; b++) begin
          n_checks++;
          if (q[b] !== (64'hC0DE_0000_0000_0000 | 64'(l * BEATS + b))) fail($sformatf("lst word %0d: %h", l * BEATS + b, q[b]));
        end
      end

      // mem_policy rand: stable per address, different across addresses.
      link.mem_policy = "rand";
      begin
        logic [63:0] a[BEATS], b[BEATS], c[BEATS];
        line_read(32'h8030_0000, a); line_read(32'h8030_0000, b); line_read(32'h8030_0040, c);
        n_checks++;
        if (a[0] !== b[0] || a[1] !== b[1]) fail("mem_policy rand: unstable");
        if (a[0] === c[0] || a[0] === a[1]) fail("mem_policy rand: not address-dependent");
      end

      uart_test(1);
      uart_test(3);

      if (link.errors + uart.errors) fail($sformatf("%0d agent errors on legal traffic", link.errors + uart.errors));
    end

    $display("[SELFTEST] violate=%0d checks=%0d reads=%0d writes=%0d fails=%0d", violate, n_checks, link.n_rd, link.n_wr, fails);
    if (fails == 0) $display("SELFTEST_RESULT: PASS");
    else            $display("SELFTEST_RESULT: FAIL %0d failures", fails);
    $finish;
  end

  function automatic bit has(input string s, input string p);
    if (p.len() == 0) return 1;
    for (int i = 0; i + p.len() <= s.len(); i++) if (s.substr(i, i + p.len() - 1) == p) return 1;
    return 0;
  endfunction

  initial begin #50ms; $display("SELFTEST_RESULT: FAIL watchdog"); $finish; end

endmodule
