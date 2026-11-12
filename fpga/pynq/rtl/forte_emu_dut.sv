///////////////////////////////////////////////////////////////////////////////
// forte_emu_dut.sv -- the frozen forte_top in the fabric, behind its pins.
//
// forte_top is instantiated unmodified (with emu/emu_pads.sv and
// emu/emu_srams.sv standing in for the PDK cells it names under `SYNTHESIS).
// This module's ports are the FPGA's side of the 31 signal pins: whatever
// drives them is in the position of the bring-up FPGA, and it sees nothing of
// the chip but those pins.  The link is two one-way buses, io_in (FPGA to
// chip) and io_out (chip to FPGA), so no pin is shared or tristated.
//
// P0: the FPGA side is this module's ports, so out-of-context synthesis sees
// the whole chip with every pin observable.  P1 instantiates fbu_top here.
///////////////////////////////////////////////////////////////////////////////

module forte_emu_dut import forte_link_pkg::*; (
  input  logic              core_clk,
  input  logic              rst_n,
  // link
  input  logic [LINK_W-1:0] io_in,
  output logic [LINK_W-1:0] io_out,
  // chip outputs
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
  forte_top chip (
    .core_clk, .rst_n, .io_in, .io_out,
    .req, .clk_out, .wr, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx,
    .test_mode, .scan_en, .fault_inject, .status);
endmodule
