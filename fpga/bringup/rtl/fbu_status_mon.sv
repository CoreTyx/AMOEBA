///////////////////////////////////////////////////////////////////////////////
// fbu_status_mon.sv -- the status and clk_out pins, measured
// (docs/impl_plan_fpga_rtl_freeze.md s5.7, STAT-01..07).
//
// status is a square wave off a free-running link counter whose half-period
// is exactly 2^23 (stalled), 2^25 (active) or 2^27 (quiet) link cycles while
// the condition holds (forte_chip.sv).  Every half-period is measured in clk
// cycles from the first edge after a clear; the class is that of the last
// two equal half-periods, and a half-period of none of the three lengths (the
// one a transition leaves, or one cut by a chip reset) counts as a glitch.
// The rates are parameters, as in forte_chip.sv, so a testbench can shrink
// them.
//
// clk_out's rising edges are counted in its own domain and carried over in
// Gray code; CLKOUT_EDGES is the count over the last complete window of
// CLKOUT_WINDOW clk cycles.
///////////////////////////////////////////////////////////////////////////////
module fbu_status_mon #(
  parameter int STALLED_LOG2       = 23,
  parameter int ACTIVE_LOG2        = 25,
  parameter int QUIET_LOG2         = 27,
  parameter int CLKOUT_WINDOW_LOG2 = 20
)(
  input  logic        clk,
  input  logic        arst_n,

  input  logic        status,
  input  logic        clk_out,
  input  logic        clear,

  output logic [31:0] last,
  output logic [31:0] min,
  output logic [31:0] max,
  output logic [31:0] edges,
  output logic [1:0]  status_class,
  output logic        level,
  output logic [31:0] glitches,
  output logic [31:0] clkout_edges
);

  localparam logic [1:0] CLASS_NONE    = 2'd0;
  localparam logic [1:0] CLASS_STALLED = 2'd1;
  localparam logic [1:0] CLASS_ACTIVE  = 2'd2;
  localparam logic [1:0] CLASS_QUIET   = 2'd3;

  function automatic logic [1:0] class_of(input logic [31:0] half_period);
    case (half_period)
      32'd1 << STALLED_LOG2: return CLASS_STALLED;
      32'd1 << ACTIVE_LOG2:  return CLASS_ACTIVE;
      32'd1 << QUIET_LOG2:   return CLASS_QUIET;
      default:     return CLASS_NONE;
    endcase
  endfunction

  // ---- status ----
  // started: an edge has been seen since the clear, so since_edge measures a
  // whole half-period; have_last: last holds one to compare with.
  logic [2:0]  status_sync;
  logic        status_edge;
  logic [31:0] since_edge;
  logic        started;
  logic        have_last;

  assign level       = status_sync[2];
  assign status_edge = status_sync[2] != status_sync[1];

  always_ff @(posedge clk or negedge arst_n)
    if (!arst_n) status_sync <= '0;
    else         status_sync <= {status_sync[1:0], status};

  always_ff @(posedge clk or negedge arst_n)
    if (!arst_n) begin
      since_edge   <= '0;
      started      <= 1'b0;
      have_last    <= 1'b0;
      last         <= '0;
      min          <= '1;
      max          <= '0;
      edges        <= '0;
      status_class <= CLASS_NONE;
      glitches     <= '0;
    end else if (clear) begin
      since_edge   <= '0;
      started      <= 1'b0;
      have_last    <= 1'b0;
      last         <= '0;
      min          <= '1;
      max          <= '0;
      edges        <= '0;
      status_class <= CLASS_NONE;
      glitches     <= '0;
    end else if (status_edge) begin
      since_edge <= 32'd1;
      started    <= 1'b1;
      edges      <= edges + 1'b1;
      if (started) begin
        have_last <= 1'b1;
        last      <= since_edge;
        if (since_edge < min)
          min <= since_edge;
        if (since_edge > max)
          max <= since_edge;
        if (class_of(since_edge) == CLASS_NONE)
          glitches <= glitches + 1'b1;
      end
      if (have_last && since_edge == last)
        status_class <= class_of(since_edge);
    end else if (since_edge != '1) begin
      since_edge <= since_edge + 1'b1;
    end

  // ---- clk_out ----
  logic [31:0] clkout_count;
  logic [31:0] clkout_gray;
  logic [31:0] clkout_gray_sync [2];
  logic [31:0] clkout_seen;
  logic [31:0] clkout_at_window;
  logic [CLKOUT_WINDOW_LOG2-1:0] window;

  function automatic logic [31:0] gray_to_binary(input logic [31:0] g);
    logic [31:0] b;
    b[31] = g[31];
    for (int i = 30; i >= 0; i--)
      b[i] = b[i + 1] ^ g[i];
    return b;
  endfunction

  always_ff @(posedge clk_out or negedge arst_n)
    if (!arst_n) begin
      clkout_count <= '0;
      clkout_gray  <= '0;
    end else begin
      clkout_count <= clkout_count + 1'b1;
      clkout_gray  <= (clkout_count + 1'b1) ^ ((clkout_count + 1'b1) >> 1);
    end

  assign clkout_seen = gray_to_binary(clkout_gray_sync[1]);

  always_ff @(posedge clk or negedge arst_n)
    if (!arst_n) begin
      clkout_gray_sync[0] <= '0;
      clkout_gray_sync[1] <= '0;
      window              <= '0;
      clkout_at_window    <= '0;
      clkout_edges        <= '0;
    end else begin
      clkout_gray_sync[0] <= clkout_gray;
      clkout_gray_sync[1] <= clkout_gray_sync[0];
      window              <= window + 1'b1;
      if (window == '1) begin
        clkout_at_window <= clkout_seen;
        clkout_edges     <= clkout_seen - clkout_at_window;
      end
    end

endmodule
