///////////////////////////////////////////
// shadow_iq.sv
//
// Purpose: SHARD Instruction Queue — N-deep shift register between main D and shadow sD.
//          Stores PC, Instr32, PCSrc, FRM_snap, IsHWCSR, IsDummy, DummySel, InstrValid.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_iq import cvw::*; #(parameter cvw_t P, parameter int N = 3) (
  input  logic              clk, reset,
  input  logic              StallD, FlushD,
  // Main D-stage push
  input  logic [P.XLEN-1:0] PCF,
  input  logic [31:0]       InstrD,
  input  logic              PCSrcD,
  input  logic [2:0]        FRM_D,
  input  logic              IsHWCSR_D,
  input  logic              IsDummyD,
  input  logic              DummySelD,
  input  logic              InstrValidD,
  // Shadow head output (entry[N-1])
  output logic [P.XLEN-1:0] sPC,
  output logic [31:0]       sInstr32,
  output logic              sPCSrc,
  output logic [2:0]        sFRM_snap,
  output logic              sIsHWCSR,
  output logic              sIsDummy,
  output logic              sDummySel,
  output logic              sInstrValid
);

  // Entry structure packed into a single vector for array handling
  // [XLEN+31+1+3+1+1+1+1-1 : 0] = [XLEN+38 : 0]
  localparam int ENTRY_W = P.XLEN + 32 + 1 + 3 + 1 + 1 + 1 + 1; // 104 for RV64

  logic [ENTRY_W-1:0] entry [N];

  // Field packing helper
  function automatic [ENTRY_W-1:0] pack_entry(
    input logic [P.XLEN-1:0] pc,
    input logic [31:0]        instr,
    input logic               pcsrc,
    input logic [2:0]         frm,
    input logic               is_hw_csr,
    input logic               is_dummy,
    input logic               dummy_sel,
    input logic               valid
  );
    pack_entry = {pc, instr, pcsrc, frm, is_hw_csr, is_dummy, dummy_sel, valid};
  endfunction

  // Unpack head
  assign {sPC, sInstr32, sPCSrc, sFRM_snap, sIsHWCSR, sIsDummy, sDummySel, sInstrValid} = entry[N-1];

  integer i;
  always_ff @(negedge clk) begin
    if (reset) begin
      for (i = 0; i < N; i++) entry[i] <= '0;
    end else if (FlushD) begin
      // Invalidate all entries on flush; preserve data (useful for debug)
      for (i = 0; i < N; i++) entry[i][0] <= 1'b0; // InstrValid is bit 0
    end else if (~StallD) begin
      // Shift: entry[N-1] ← entry[N-2] ← ... ← entry[0] ← new
      for (i = N-1; i > 0; i--) entry[i] <= entry[i-1];
      entry[0] <= pack_entry(PCF, InstrD, PCSrcD, FRM_D, IsHWCSR_D, IsDummyD, DummySelD, InstrValidD);
    end
  end

endmodule
