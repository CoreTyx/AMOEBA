///////////////////////////////////////////
// shadow_oq.sv
//
// Purpose: SHARD Operand Queue.  Pushed together with the IQ when an instruction
//          leaves the main Memory stage.  Carries what the main pipeline used and
//          observed for that instruction: the forwarded register operands, the
//          ALU sum (effective address / branch target), the raw load word, and
//          the decoded datapath controls.  The head feeds shadow sE, which checks
//          the operands against its own and re-executes the instruction.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_oq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic              clk, reset,
  input  logic              Flush,           // recovery: discard every entry
  input  logic              Push,            // main M-stage exit
  input  logic              Pop,             // shadow sE -> sM advance
  // Main M-stage values
  input  logic [P.XLEN-1:0] ForwardedSrcAM,  // rs1 value the main pipeline used
  input  logic [P.XLEN-1:0] ForwardedSrcBM,  // rs2 value the main pipeline used
  input  logic [P.XLEN-1:0] IEUAdrM,         // ALU sum: effective address or branch/jump target
  input  logic [P.XLEN-1:0] RawLoadWordM,    // aligned read word (after store-queue merge) before subword extract
  input  logic              ALUSrcAM, ALUSrcBM,
  input  logic [2:0]        ImmSrcM,
  input  logic              W64M, UW64M, SubArithM,
  input  logic [2:0]        ALUSelectM,
  input  logic [3:0]        BSelectM, ZBBSelectM,
  input  logic [2:0]        BALUControlM,
  input  logic              BMUActiveM,
  input  logic [1:0]        CZeroM,
  input  logic              ALUResultSrcM, JumpM, BranchM,
  input  logic              PCSrcM,          // main took the branch/jump
  input  logic              RegWriteM,
  input  logic [2:0]        ResultSrcM,
  input  logic              FWriteIntM,
  input  logic              ViaSQM,          // this instruction pushed a store-queue entry
  input  logic              AMOM,            // atomic memory operation (store data is the AMO result)
  input  logic              LoadChkM,        // integer load/LR/AMO read whose data the shadow re-derives
  // Head (shadow sE)
  output logic [P.XLEN-1:0] s_ForwardedSrcA,
  output logic [P.XLEN-1:0] s_ForwardedSrcB,
  output logic [P.XLEN-1:0] s_IEUAdr,
  output logic [P.XLEN-1:0] s_RawLoadWord,
  output logic              s_ALUSrcA, s_ALUSrcB,
  output logic [2:0]        s_ImmSrc,
  output logic              s_W64, s_UW64, s_SubArith,
  output logic [2:0]        s_ALUSelect,
  output logic [3:0]        s_BSelect, s_ZBBSelect,
  output logic [2:0]        s_BALUControl,
  output logic              s_BMUActive,
  output logic [1:0]        s_CZero,
  output logic              s_ALUResultSrc, s_Jump, s_Branch,
  output logic              s_PCSrc,
  output logic              s_RegWrite,
  output logic [2:0]        s_ResultSrc,
  output logic              s_FWriteInt,
  output logic              s_ViaSQ,
  output logic              s_AMO,
  output logic              s_LoadChk
);

  localparam int CTL_W   = 37;
  localparam int ENTRY_W = 4*P.XLEN + CTL_W;

  logic [ENTRY_W-1:0]         entry [DEPTH];
  logic [$clog2(DEPTH+1)-1:0] count;

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep('0),
    .push(Push),
    .din({ForwardedSrcAM, ForwardedSrcBM, IEUAdrM, RawLoadWordM,
          ALUSrcAM, ALUSrcBM, ImmSrcM, W64M, UW64M, SubArithM,
          ALUSelectM, BSelectM, ZBBSelectM, BALUControlM, BMUActiveM, CZeroM,
          ALUResultSrcM, JumpM, BranchM, PCSrcM, RegWriteM, ResultSrcM, FWriteIntM,
          ViaSQM, AMOM, LoadChkM}),
    .pop(Pop), .entry, .count);

  assign {s_ForwardedSrcA, s_ForwardedSrcB, s_IEUAdr, s_RawLoadWord,
          s_ALUSrcA, s_ALUSrcB, s_ImmSrc, s_W64, s_UW64, s_SubArith,
          s_ALUSelect, s_BSelect, s_ZBBSelect, s_BALUControl, s_BMUActive, s_CZero,
          s_ALUResultSrc, s_Jump, s_Branch, s_PCSrc, s_RegWrite, s_ResultSrc, s_FWriteInt,
          s_ViaSQ, s_AMO, s_LoadChk} = entry[0];

endmodule
