///////////////////////////////////////////////////////////////////////////////
// amoeba_top.sv
//
// The ASIC: amoeba_chip plus pads.  DESIGN_TOP for synthesis and lint.
//
// Pad list (docs/top_level_plan.md s3): clk, rst_n, io[15:0] bidir, dir, req,
// wr, burst, ready, rvalid, irq[1:0], uart_tx, uart_rx, test_mode, scan_en,
// status.  Power and ground are the pad library's business.
//
// AMOEBA_PADLIB selects the 65 nm IO cells; without it the bidirectional
// pads are behavioural tristates, which is what simulation and the FPGA
// rehearsal use.
///////////////////////////////////////////////////////////////////////////////

module amoeba_top import amoeba_link_pkg::*; #(
  parameter TRAIN_LEN     = TRAIN_LEN_DEFAULT,
  parameter logic PERIPH_ONCHIP = 1'b1
)(
  input  wire              clk,
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

  amoeba_chip #(.TRAIN_LEN(TRAIN_LEN), .PERIPH_ONCHIP(PERIPH_ONCHIP)) chip(
    .clk, .rst_n, .io_o, .io_oe, .io_i, .dir, .req, .wr, .burst, .ready, .rvalid,
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
