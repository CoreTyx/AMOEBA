///////////////////////////////////////////////////////////////////////////////
// pad_behav.sv -- LOCAL STAND-INS for the three PDK pad wrappers, never for
// sign-off.  Under `SYNTHESIS forte_top instantiates io_in / io_out / io_tri;
// on the VM the PDK's own models are compiled instead (hvl/pin/vm_paths.sh:
// PAD_MODELS).  Port convention from forte_top.sv: `chipout` is the pin,
// `chipin` the die side; io_tri's t is ACTIVE-HIGH TRISTATE (t=1 releases).
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module io_in  (input  wire chipout, output wire chipin);  assign chipin  = chipout; endmodule
module io_out (output wire chipout, input  wire chipin);  assign chipout = chipin;  endmodule
module io_tri (inout  wire chipout, output logic i, input logic o, input logic t);
  assign chipout = t ? 1'bz : o;
  assign i       = chipout;
endmodule
