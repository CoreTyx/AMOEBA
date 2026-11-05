///////////////////////////////////////////////////////////////////////////////
// tb_fbu_status_mon.sv -- fbu_status_mon against a status pin modelled as
// forte_chip.sv drives it, with the rates shrunk (2^5 stalled, 2^7 active,
// 2^9 quiet) so every class is seen in microseconds.  The pin is a tap on a
// free-running counter, so a change of class leaves one or two odd
// half-periods: the one the switch cuts short, and, if the pin flips at the
// switch, the one from there to the new tap's next edge.
// clk_out runs at clk's rate and then at 3/2 of it.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
module tb_fbu_status_mon;

  localparam int STALLED_LOG2 = 5;
  localparam int ACTIVE_LOG2  = 7;
  localparam int QUIET_LOG2   = 9;
  localparam int WINDOW_LOG2  = 10;

  logic        clk = 1'b0;
  logic        clk_out = 1'b0;
  logic        arst_n = 1'b0;
  logic        clear = 1'b0;
  logic [QUIET_LOG2:0] tick = '0;
  int          tap = ACTIVE_LOG2;
  logic        chip_in_reset = 1'b0;
  logic        status;
  real         clk_out_half = 5.0;
  int          errors = 0;

  logic [31:0] last;
  logic [31:0] min;
  logic [31:0] max;
  logic [31:0] edges;
  logic [1:0]  status_class;
  logic        level;
  logic [31:0] glitches;
  logic [31:0] clkout_edges;

  always #5 clk = ~clk;
  always #(clk_out_half) clk_out = ~clk_out;

  always @(posedge clk)
    if (chip_in_reset) tick <= '0;
    else               tick <= tick + 1'b1;

  assign status = tick[tap];

  fbu_status_mon #(.STALLED_LOG2(STALLED_LOG2), .ACTIVE_LOG2(ACTIVE_LOG2), .QUIET_LOG2(QUIET_LOG2),
                   .CLKOUT_WINDOW_LOG2(WINDOW_LOG2)) dut (
    .clk, .arst_n, .status, .clk_out, .clear,
    .last, .min, .max, .edges, .status_class, .level, .glitches, .clkout_edges);

  task automatic expect_eq(input string what, input longint got, input longint want);
    if (got != want) begin
      $display("FAIL %s: %0d, expected %0d", what, got, want);
      errors++;
    end
  endtask

  task automatic expect_within(input string what, input longint got, input longint lo, input longint hi);
    if (got < lo || got > hi) begin
      $display("FAIL %s: %0d, expected %0d..%0d", what, got, lo, hi);
      errors++;
    end
  endtask

  task automatic cycles(input int n);
    repeat (n) @(posedge clk);
  endtask

  task automatic clear_stats;
    @(negedge clk);
    clear = 1'b1;
    @(negedge clk);
    clear = 1'b0;
  endtask

  initial begin
    cycles(4);
    arst_n = 1'b1;

    // Steady active: every whole half-period is 2^7, no glitch.
    clear_stats();
    cycles(8 << ACTIVE_LOG2);
    expect_eq("active class", status_class, 2);
    expect_eq("active last", last, 1 << ACTIVE_LOG2);
    expect_eq("active min", min, 1 << ACTIVE_LOG2);
    expect_eq("active max", max, 1 << ACTIVE_LOG2);
    expect_eq("active glitches", glitches, 0);

    // To stalled, mid half-period: one or two odd half-periods, then stalled.
    cycles(37);
    tap = STALLED_LOG2;
    cycles(8 << STALLED_LOG2);
    expect_eq("stalled class", status_class, 1);
    expect_eq("stalled last", last, 1 << STALLED_LOG2);
    expect_within("stalled glitches", glitches, 1, 2);

    // To quiet: one or two more glitches, then quiet; max spans the run, and
    // min is the shortest odd piece.
    tap = QUIET_LOG2;
    cycles(8 << QUIET_LOG2);
    expect_eq("quiet class", status_class, 3);
    expect_eq("quiet last", last, 1 << QUIET_LOG2);
    expect_within("quiet min", min, 1, 1 << STALLED_LOG2);
    expect_eq("quiet max", max, 1 << QUIET_LOG2);
    expect_within("quiet glitches", glitches, 2, 4);

    // A clear forgets everything; the first edge only starts a measurement.
    clear_stats();
    expect_eq("cleared edges", edges, 0);
    expect_eq("cleared class", status_class, 0);
    expect_eq("cleared glitches", glitches, 0);
    cycles(3 << QUIET_LOG2);
    expect_eq("after clear class", status_class, 3);
    expect_eq("after clear glitches", glitches, 0);

    // A chip reset holds the pin low: one or two cut half-periods, and the
    // class comes back after release.
    tap = ACTIVE_LOG2;
    cycles(4 << ACTIVE_LOG2);
    clear_stats();
    cycles(3 << ACTIVE_LOG2);
    chip_in_reset = 1'b1;
    cycles(300);
    chip_in_reset = 1'b0;
    cycles(6 << ACTIVE_LOG2);
    expect_eq("reset class", status_class, 2);
    expect_within("reset glitches", glitches, 1, 2);

    // clk_out: as fast as clk, then 3/2 as fast (two windows each).
    cycles(2 << WINDOW_LOG2);
    expect_eq("clk_out edges at 1x", clkout_edges, 1 << WINDOW_LOG2);
    clk_out_half = 5.0 * 2.0 / 3.0;
    cycles(3 << WINDOW_LOG2);
    expect_within("clk_out edges at 1.5x", clkout_edges, (3 << WINDOW_LOG2) / 2 - 1, (3 << WINDOW_LOG2) / 2 + 1);

    if (errors == 0)
      $display("tb_fbu_status_mon PASS");
    else
      $display("tb_fbu_status_mon FAIL %0d", errors);
    $finish;
  end

endmodule
