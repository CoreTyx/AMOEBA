///////////////////////////////////////////
// shadow_hzu.sv
//
// Purpose: SHARD shadow forwarding unit.  The shadow sources its operands from
//          verified state only: the committed register file, bypassed by the
//          results of the older instructions still in shadow sM and sW.  This
//          select is computed from the shadow's own decode of the instruction
//          word and is independent of the main pipeline's ForwardAE/BE logic.
//
//          Select encoding (same as the main pipeline):
//            00 = register file, 01 = sW bypass, 10 = sM bypass
//
//          The shadow never needs a load-use stall: every result, including
//          load data, is already available when its producer is in sM.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_hzu (
  input  logic [4:0] sRs1E, sRs2E,       // source registers of the instruction in shadow sE
  input  logic [4:0] sRdM, sRdW,         // destination registers in shadow sM and sW
  input  logic       sRegWriteM,         // sM holds a valid instruction that writes sRdM
  input  logic       sRegWriteW,         // sW holds a valid instruction that writes sRdW
  output logic [1:0] sForwardAE,
  output logic [1:0] sForwardBE
);

  always_comb begin
    sForwardAE = 2'b00;
    sForwardBE = 2'b00;
    if (sRs1E != 5'b0)
      if      (sRegWriteM & (sRdM == sRs1E)) sForwardAE = 2'b10;
      else if (sRegWriteW & (sRdW == sRs1E)) sForwardAE = 2'b01;

    if (sRs2E != 5'b0)
      if      (sRegWriteM & (sRdM == sRs2E)) sForwardBE = 2'b10;
      else if (sRegWriteW & (sRdW == sRs2E)) sForwardBE = 2'b01;
  end

endmodule
