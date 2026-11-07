///////////////////////////////////////////////////////////////////////////////
// pad_behav.sv -- LOCAL STAND-INS for the PDK pad wrappers, never for
// sign-off.  Under `SYNTHESIS forte_top instantiates io_in / io_out;
// on the VM the PDK's own models are compiled instead (hvl/pin/vm_paths.sh:
// PAD_MODELS).  Port convention from forte_top.sv: `chipout` is the pin,
// `chipin` the die side.  The PDK's io_tri is not modelled: since the link
// split into one-way io_in[7:0] / io_out[7:0] buses no pad on the chip uses it.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module io_in  (input  wire chipout, output wire chipin);  assign chipin  = chipout; endmodule
module io_out (output wire chipout, input  wire chipin);  assign chipout = chipin;  endmodule
