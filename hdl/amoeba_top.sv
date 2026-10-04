///////////////////////////////////////////////////////////////////////////////
// amoeba_top.sv
//
// The ASIC: amoeba_chip plus pads.  DESIGN_TOP for synthesis and lint.
//
// Pad list (docs/top_level_plan.md s3): core_clk, rst_n, io[15:0] bidir, dir, req,
// wr, burst, ready, rvalid, irq[1:0], uart_tx, uart_rx, test_mode, scan_en,
// status.  Power and ground are the pad library's business.
//
// AMOEBA_PADLIB selects the 65 nm IO cells; without it the bidirectional
// pads are behavioural tristates, which is what simulation and the FPGA
// rehearsal use.
///////////////////////////////////////////////////////////////////////////////

module amoeba_top import amoeba_link_pkg::*; #(
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
  output wire              status
);

  logic [LINK_W-1:0] io_o, io_oe, io_i;

  // link_clk is tied to the core_clk pad: one clock off the board, two clock
  // trees on the die (docs/impl_plan_link_clocking.md s4).  The separate port on
  // amoeba_chip is what lets a testbench drive the two domains independently and
  // actually exercise the FIFOs' pointer crossings; a single port would give
  // simulation zero skew and no coverage.  Splitting the frequencies later is a
  // one-line change here plus a pad.
  amoeba_chip #(.PERIPH_ONCHIP(PERIPH_ONCHIP)) chip(
    .core_clk, .link_clk(core_clk), .rst_n, .io_o, .io_oe, .io_i, .dir, .req, .wr, .burst, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx, .test_mode, .scan_en, .status);

`ifdef AMOEBA_PADLIB
  // TODO: instantiate the PDK's IO cells here: bidirectional with per-pad OE
  // on io, inputs with pull-down on test_mode/scan_en and pull-up on uart_rx.
  `error "AMOEBA_PADLIB: pad library not yet wired"
`else
  // Behavioural pads.  One enable for the whole bus is exact in functional
  // mode (every io_oe bit equals dir); scan mode is not simulated here.
  assign io   = io_oe[0] ? io_o : {LINK_W{1'bz}};
  assign io_i = io;
`endif

endmodule
