///////////////////////////////////////////
// shadow_oq.sv
//
// Purpose: SHARD Operand Queue — N-deep shift register, pushed at main E→M transition.
//          Carries forwarded operands and pre-decoded ALU control signals to shadow sE.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

// oq_entry_t is used by both shadow_oq and shadow_pipeline; define in a shared header.
// For V1, shadow_pipeline imports it from this package by including this file.
// (In production, move to pkg/shadow_types.sv.)

module shadow_oq import cvw::*; #(parameter cvw_t P, parameter int N = 3) (
  input  logic              clk, reset,
  // Push enable: stall at M (no shift), flush at E (push invalid entry)
  input  logic              StallM, FlushE, FlushM,
  // Data from main E-stage (post-mux operands + pre-decoded controls)
  input  logic [P.XLEN-1:0] SrcAE,            // ALUSrcA mux output
  input  logic [P.XLEN-1:0] SrcBE,            // ALUSrcB mux output
  input  logic [P.XLEN-1:0] ForwardedSrcBE,   // raw forwarded B (store data)
  input  logic [P.XLEN-1:0] PCLinkE,          // PC+4
  input  logic [P.XLEN-1:0] ImmExtE,          // sign-extended immediate
  input  logic              W64E, UW64E, SubArithE,
  input  logic [2:0]        ALUSelectE,
  input  logic [3:0]        BSelectE, ZBBSelectE,
  input  logic [2:0]        BALUControlE,
  input  logic              BMUActiveE,
  input  logic [1:0]        CZeroE,
  input  logic [2:0]        Funct3E,
  input  logic [6:0]        Funct7E,
  input  logic [4:0]        Rs2E,
  input  logic              ALUResultSrcE, JumpE, BranchSignedE,
  input  logic [1:0]        MemRWE,
  input  logic [4:0]        RdE,
  input  logic              RegWriteE, InstrValidE, DummyE, DummySelE,
  // Shadow head output fields (consumed by shadow sE)
  output logic [P.XLEN-1:0] s_SrcAE,
  output logic [P.XLEN-1:0] s_SrcBE,
  output logic [P.XLEN-1:0] s_ForwardedSrcBE,
  output logic [P.XLEN-1:0] s_PCLinkE,
  output logic [P.XLEN-1:0] s_ImmExtE,
  output logic              s_W64E, s_UW64E, s_SubArithE,
  output logic [2:0]        s_ALUSelectE,
  output logic [3:0]        s_BSelectE, s_ZBBSelectE,
  output logic [2:0]        s_BALUControlE,
  output logic              s_BMUActiveE,
  output logic [1:0]        s_CZeroE,
  output logic [2:0]        s_Funct3E,
  output logic [6:0]        s_Funct7E,
  output logic [4:0]        s_Rs2E,
  output logic              s_ALUResultSrcE, s_JumpE, s_BranchSignedE,
  output logic [1:0]        s_MemRWE,
  output logic [4:0]        s_RdE,
  output logic              s_RegWriteE, s_InstrValidE, s_DummyE, s_DummySelE
);

  // Pack all fields into one wide vector per entry
  // Width: 5*XLEN + 3 + 3 + 3 + 4 + 4 + 3 + 1 + 2 + 3 + 7 + 5 + 1 + 1 + 1 + 2 + 5 + 1 + 1 + 1 + 1
  localparam int CTL_W = 3+3+3+4+4+3+1+2+3+7+5+1+1+1+2+5+1+1+1+1; // control bits
  localparam int ENTRY_W = 5*P.XLEN + CTL_W;

  logic [ENTRY_W-1:0] entry [N];

  // Pack/unpack macros via concatenation
  wire [ENTRY_W-1:0] push_data = {
    SrcAE, SrcBE, ForwardedSrcBE, PCLinkE, ImmExtE,
    W64E, UW64E, SubArithE,
    ALUSelectE, BSelectE, ZBBSelectE, BALUControlE,
    BMUActiveE, CZeroE, Funct3E, Funct7E, Rs2E,
    ALUResultSrcE, JumpE, BranchSignedE,
    MemRWE, RdE,
    RegWriteE, InstrValidE, DummyE, DummySelE
  };

  wire [ENTRY_W-1:0] null_entry = '0;

  assign {
    s_SrcAE, s_SrcBE, s_ForwardedSrcBE, s_PCLinkE, s_ImmExtE,
    s_W64E, s_UW64E, s_SubArithE,
    s_ALUSelectE, s_BSelectE, s_ZBBSelectE, s_BALUControlE,
    s_BMUActiveE, s_CZeroE, s_Funct3E, s_Funct7E, s_Rs2E,
    s_ALUResultSrcE, s_JumpE, s_BranchSignedE,
    s_MemRWE, s_RdE,
    s_RegWriteE, s_InstrValidE, s_DummyE, s_DummySelE
  } = entry[N-1];

  integer i;
  always_ff @(negedge clk) begin
    if (reset) begin
      for (i = 0; i < N; i++) entry[i] <= '0;
    end else if (StallM) begin
      // Hold all entries (instruction stuck at E, do not shift)
    end else if (FlushE || FlushM) begin
      // Inject invalid entry at position 0; shift everything else
      for (i = N-1; i > 0; i--) entry[i] <= entry[i-1];
      entry[0] <= null_entry; // InstrValidE is 0
    end else begin
      for (i = N-1; i > 0; i--) entry[i] <= entry[i-1];
      entry[0] <= push_data;
    end
  end

endmodule
