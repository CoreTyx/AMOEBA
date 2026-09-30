///////////////////////////////////////////
// shadow_hzu.sv
//
// Purpose: SHARD shadow forwarding unit — 2-tier bypass within the shadow pipeline.
//          Detects RAW hazards between shadow sD/sE instructions and generates
//          forward select signals: 00 = OQ base, 01 = sM bypass, 10 = sE bypass.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_hzu #(parameter int XLEN = 64) (
  // Shadow pipeline Rd and write-enable for E and M stages
  input  logic [4:0]       sRdE,
  input  logic [4:0]       sRdM,
  input  logic             sRegWriteE,
  input  logic             sRegWriteM,
  // Source register indices for the instruction entering shadow sE (from IQ)
  input  logic [4:0]       sRs1,
  input  logic [4:0]       sRs2,
  // Forward select outputs (same encoding as main pipeline)
  // 00 = use OQ value, 01 = sM bypass, 10 = sE bypass
  output logic [1:0]       sForwardAE,
  output logic [1:0]       sForwardBE
);

  always_comb begin
    // sE bypass has higher priority than sM bypass
    if (sRegWriteE && (sRdE != 5'b0) && (sRdE == sRs1))
      sForwardAE = 2'b10;
    else if (sRegWriteM && (sRdM != 5'b0) && (sRdM == sRs1))
      sForwardAE = 2'b01;
    else
      sForwardAE = 2'b00;

    if (sRegWriteE && (sRdE != 5'b0) && (sRdE == sRs2))
      sForwardBE = 2'b10;
    else if (sRegWriteM && (sRdM != 5'b0) && (sRdM == sRs2))
      sForwardBE = 2'b01;
    else
      sForwardBE = 2'b00;
  end

endmodule
