///////////////////////////////////////////////////////////////////////////////
// forte_emu_dut.sv -- the frozen forte_top in the fabric, behind its pins.
//
// forte_top is instantiated unmodified (with emu/emu_pads.sv and
// emu/emu_srams.sv standing in for the PDK cells it names under `SYNTHESIS).
// This module's ports are the FPGA's side of the 32 signal pins: whatever
// drives them is in the position of the bring-up FPGA, and it sees nothing of
// the chip but those pins.
//
// io is one tristate net shared by the chip's io_tri cells and the FPGA's
// drivers, as on a board.  The FPGA drives a lane only where fpga_io_oe is set;
// when both sides drive, the fabric resolves it silently (Vivado turns the
// tristates into a mux), so the protocol checker in fpga/bringup enforces the
// turnaround rule at the pins instead.
//
// P0: the FPGA side is this module's ports, so out-of-context synthesis sees
// the whole chip with every pin observable.  P1 instantiates fbu_top here.
///////////////////////////////////////////////////////////////////////////////

module forte_emu_dut import forte_link_pkg::*; (
  input  logic              core_clk,
  input  logic              rst_n,
  // io lanes, FPGA side
  input  logic [LINK_W-1:0] fpga_io_o,
  input  logic [LINK_W-1:0] fpga_io_oe,
  output logic [LINK_W-1:0] fpga_io_i,
  // chip outputs
  output logic              dir,
  output logic              req,
  output logic              wr,
  output logic              clk_out,
  output logic              uart_tx,
  output logic              status,
  // chip inputs
  input  logic              ready,
  input  logic              rvalid,
  input  logic [1:0]        irq,
  input  logic              uart_rx,
  input  logic              test_mode,
  input  logic              scan_en,
  input  logic              fault_inject
);
  wire [LINK_W-1:0] io;

  for (genvar i = 0; i < LINK_W; i++) begin : g_fpga_io
    assign io[i] = fpga_io_oe[i] ? fpga_io_o[i] : 1'bz;
  end
  assign fpga_io_i = io;

  forte_top chip (
    .core_clk, .rst_n, .io,
    .dir, .req, .clk_out, .wr, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx,
    .test_mode, .scan_en, .fault_inject, .status);
endmodule
