///////////////////////////////////////////////////////////////////////////////
// emu_pads.sv -- FPGA stand-ins for the three PDK pad wrappers.  Vivado
// defines `SYNTHESIS, so the frozen forte_top instantiates io_in / io_out /
// io_tri by name; these definitions satisfy it in the fabric.
//
// The module bodies are those of hvl/pin/models/pad_behav.sv, line for line,
// so the FPGA and the pin bench model the pads identically.
// fpga/scripts/check_frozen.sh diffs the two and fails on any difference.
//
// io_tri's chipout is an internal tristate net in the fabric: forte_emu_dut
// drives the same net from the FPGA side, and Vivado converts the pair of
// tristate drivers into a mux (proven on feature/top_level, stages A/B).
///////////////////////////////////////////////////////////////////////////////

module io_in  (input  wire chipout, output wire chipin);  assign chipin  = chipout; endmodule
module io_out (output wire chipout, input  wire chipin);  assign chipout = chipin;  endmodule
module io_tri (inout  wire chipout, output logic i, input logic o, input logic t);
  assign chipout = t ? 1'bz : o;
  assign i       = chipout;
endmodule
