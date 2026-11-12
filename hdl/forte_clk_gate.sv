///////////////////////////////////////////////////////////////////////////////
// forte_clk_gate.sv
//
// Latch-based integrated clock gate: gclk = clk while (en | te), held low
// otherwise.  The enable is captured while clk is low, so gclk never glitches
// and a change of en takes effect from the next rising edge.
//
//   en   functional enable
//   te   test enable; ORed in so scan can force the clock on
//
// Used for the two root gates of the DFT hold (hdl/forte_chip.sv, "DFT HOLD"),
// which have to exist in the RTL rather than be inferred: they separate the
// scan-selected registers from everything else, and that split is a design
// decision, not something synthesis could find on its own.
//
// SYNTHESIS.  The model below is the textbook latch + AND.  DC does not turn
// that into the library's integrated clock-gating cell on its own (it maps a
// latch and an AND, with no clock-gating check), so a synthesis run defines
// FORTE_ICG_TECH and supplies forte_icg_tech: a one-cell wrapper around the
// library ICG, kept with the library like the pad wrappers in io_drivers/,
// because cell and pin names differ between libraries (FreePDK45
// CLKGATETST_X1 CK/E/SE/GCK; on TSMC, list them with
// get_lib_cells */* -filter "defined(clock_gating_integrated_cell)").
// synth/synthesis.tcl and synth/DFT_FLOW.md on the dft branch.
///////////////////////////////////////////////////////////////////////////////

module forte_clk_gate (
  input  logic clk,
  input  logic en,
  input  logic te,
  output logic gclk
);

`ifdef FORTE_ICG_TECH
  forte_icg_tech icg(.clk, .en, .te, .gclk);
`else
  logic en_l;

  // Transparent while clk is low, closed while it is high.
  always_latch
    if (!clk) en_l = en | te;

  assign gclk = clk & en_l;
`endif

endmodule
