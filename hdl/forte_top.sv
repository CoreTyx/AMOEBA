///////////////////////////////////////////////////////////////////////////////
// forte_top.sv
//
// The ASIC: forte_chip plus pads.  DESIGN_TOP for synthesis and lint.
//
// Pad list (docs/top_level_plan.md s3): core_clk, rst_n, io[15:0] bidir, dir, req,
// wr, burst, ready, rvalid, irq[1:0], uart_tx, uart_rx, test_mode, scan_en,
// status.  Power and ground are the pad library's business.
//
// FORTE_PADLIB selects the 65 nm IO cells; without it the bidirectional
// pads are behavioural tristates, which is what simulation and the FPGA
// rehearsal use.  Either way the sixteen bidirectional pads have an output
// enable EACH, because test mode drives the two halves of the bus in opposite
// directions -- see the behavioural model below and
// docs/impl_plan_link_clocking.md s11.
///////////////////////////////////////////////////////////////////////////////

module forte_top import forte_link_pkg::*; #(
  parameter logic PERIPH_ONCHIP = 1'b1
)(
  input  wire              core_clk,
  input  wire              rst_n,
  inout  wire [LINK_W-1:0] io,
  output wire              dir,
  output wire              req,
  output wire              wr,
  output wire              burst,
  input  wire              ready,
  input  wire              rvalid,
  input  wire [1:0]        irq,
  output wire              uart_tx,
  input  wire              uart_rx,
  input  wire              test_mode,
  input  wire              scan_en,
  // ECC inject enable, for the register-file ECC test path on
  // Making_HDL_Synthesizable.  NOT in the s3 pad table: it is a test input and
  // the team has to decide whether it earns a pad, shares the DFT encoding, or
  // is tied off in silicon.  Carried as a port so the testbench can drive it.
  input  wire              ecc_inject_en,
  output wire              status
);

  logic [LINK_W-1:0] io_o, io_oe, io_i;

  // link_clk is tied to the core_clk pad: one clock off the board, two clock
  // trees on the die (docs/impl_plan_link_clocking.md s4).  The separate port on
  // forte_chip is what lets a testbench drive the two domains independently and
  // actually exercise the FIFOs' pointer crossings; a single port would give
  // simulation zero skew and no coverage.  Splitting the frequencies later is a
  // one-line change here plus a pad.
  forte_chip #(.PERIPH_ONCHIP(PERIPH_ONCHIP)) chip(
    .core_clk, .link_clk(core_clk), .rst_n, .io_o, .io_oe, .io_i, .dir, .req, .wr, .burst, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx, .test_mode, .scan_en, .ecc_inject_en, .status);

`ifdef FORTE_PADLIB
  // TODO: instantiate the PDK's IO cells here: bidirectional with per-pad OE
  // on io, inputs with pull-down on test_mode/scan_en and pull-up on uart_rx.
  `error "FORTE_PADLIB: pad library not yet wired"
`else
  // Behavioural pads, one enable PER PAD.  A single bus-wide enable happens to
  // be exact in functional mode, where every io_oe bit equals dir -- but it
  // makes test mode unsimulatable.  forte_chip drives io_oe = {8'hFF, 8'h00}
  // for scan (io[7:0] in, io[15:8] out), and the low half of that is 0, so an
  // enable taken from io_oe[0] tristated all sixteen pads and the eight
  // scan-out chains could not be observed even in simulation.  The PDK cells
  // have an OE per pad, so this is also the more faithful model.
  for (genvar i = 0; i < LINK_W; i++) begin : g_iopad
    assign io[i] = io_oe[i] ? io_o[i] : 1'bz;
  end
  assign io_i = io;
`endif

endmodule
