///////////////////////////////////////////////////////////////////////////////
// emu_pads.sv -- FPGA stand-ins for the PDK pad wrappers.  Vivado defines
// `SYNTHESIS, so the frozen forte_top instantiates io_in / io_out by name;
// these definitions satisfy it in the fabric.
//
// The module bodies are those of hvl/pin/models/pad_behav.sv, line for line,
// so the FPGA and the pin bench model the pads identically.
// fpga/scripts/check_frozen.sh diffs the two and fails on any difference.
///////////////////////////////////////////////////////////////////////////////

module io_in  (input  wire chipout, output wire chipin);  assign chipin  = chipout; endmodule
module io_out (output wire chipout, input  wire chipin);  assign chipout = chipin;  endmodule
