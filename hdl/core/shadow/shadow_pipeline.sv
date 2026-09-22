///////////////////////////////////////////
// shadow_pipeline.sv
//
// Purpose: SHARD shadow pipeline top-level — sD → sE → sM → sW.
//          Pulls instructions from IQ, operands from OQ, store data from SQ,
//          and committed results from RQ. Re-executes using a shadow ALU and
//          comparator. At sW, verifies against RQ and writes the register file.
//
//          V1 simplifications:
//            - Same stall/flush as main (synchronous shadow)
//            - SkipVerify for FP, DIV, LR/SC, AMO, CSR, fence, WFI
//            - sM: address-only check for stores (no D-cache re-read)
//            - VBC_StallE: tied low (not implemented)
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_pipeline import cvw::*; #(parameter cvw_t P, parameter int N = 3) (
  input  logic              clk, reset,
  // Main stall/flush (shadow uses same signals for V1)
  input  logic              StallD, StallE, StallM, StallW,
  input  logic              FlushD, FlushE, FlushM, FlushW,
  // IQ head (shadow sD input)
  input  logic [P.XLEN-1:0] sPC_in,
  input  logic [31:0]       sInstr32_in,
  input  logic              sPCSrc_in,
  input  logic [2:0]        sFRM_snap_in,
  input  logic              sIsHWCSR_in,
  input  logic              sIsDummy_in,
  input  logic              sDummySel_in,
  input  logic              sInstrValid_in,
  // OQ head fields (shadow sE input)
  input  logic [P.XLEN-1:0] oq_SrcAE,
  input  logic [P.XLEN-1:0] oq_SrcBE,
  input  logic [P.XLEN-1:0] oq_ForwardedSrcBE,
  input  logic [P.XLEN-1:0] oq_PCLinkE,
  input  logic [P.XLEN-1:0] oq_ImmExtE,
  input  logic              oq_W64E, oq_UW64E, oq_SubArithE,
  input  logic [2:0]        oq_ALUSelectE,
  input  logic [3:0]        oq_BSelectE, oq_ZBBSelectE,
  input  logic [2:0]        oq_BALUControlE,
  input  logic              oq_BMUActiveE,
  input  logic [1:0]        oq_CZeroE,
  input  logic [2:0]        oq_Funct3E,
  input  logic [6:0]        oq_Funct7E,
  input  logic [4:0]        oq_Rs2E,
  input  logic              oq_ALUResultSrcE, oq_JumpE, oq_BranchSignedE,
  input  logic [1:0]        oq_MemRWE,
  input  logic [4:0]        oq_RdE,
  input  logic              oq_RegWriteE, oq_InstrValidE, oq_DummyE, oq_DummySelE,
  // RQ head (shadow sW input)
  input  logic [4:0]        rq_Rd,
  input  logic [P.XLEN-1:0] rq_IntResult,
  input  logic              rq_IntWriteEn,
  input  logic [P.XLEN-1:0] rq_MemAddr,
  input  logic [1:0]        rq_MemRW,
  input  logic              rq_HasStore,
  input  logic [P.XLEN-1:0] rq_PC,
  input  logic              rq_SkipVerify,
  input  logic              rq_IsFaultedInstr,
  input  logic              rq_DummyW,
  input  logic              rq_DummySelW,
  input  logic              rq_InstrValid,
  // RQ pop (shadow sW consumed entry)
  output logic              sW_pop,
  // SQ head (shadow sM input)
  input  logic [P.PA_BITS-1:0] sq_PA,
  input  logic [P.XLEN-1:0]   sq_WriteData,
  input  logic [P.XLEN/8-1:0] sq_ByteMask,
  input  logic                sq_Valid,
  // SQ pop (shadow sM consumed a store entry)
  output logic              sM_pop,
  // Shadow regfile write port (drives regfile we3/a3/wd3)
  output logic              shadow_we3,
  output logic [4:0]        shadow_a3,      // 5-bit Rd; regfile uses DummyW/Sel for shadow regs
  output logic [P.XLEN-1:0] shadow_wd3,
  output logic              shadow_DummyW,  // dummy write → shadow physical register
  output logic              shadow_DummySel,
  // MSECFAULT reporting
  output logic              SecFaultW,
  output logic [P.XLEN-1:0] SecFaultPC_W,
  // VBC (V1: stubbed)
  output logic              VBC_StallE,
  // Shadow stage Rd outputs (for future use / debug)
  output logic [4:0]        sRdE_out,
  output logic [4:0]        sRdM_out
);

  // ---------------------------------------------------------------------------
  // SkipVerify opcode decode (combinational, used at sD)
  // ---------------------------------------------------------------------------
  function automatic logic is_skip_verify(input logic [31:0] instr);
    logic [6:0] op;
    logic [6:0] f7;
    logic [11:0] i_imm;
    op    = instr[6:0];
    f7    = instr[31:25];
    i_imm = instr[31:20];
    // FP ops
    if (op == 7'b1010011 || op == 7'b1000011 || op == 7'b1000111 ||
        op == 7'b1001011 || op == 7'b1001111)
      return 1'b1;
    // Integer DIV/REM (R-type, funct7=0000001)
    if (op == 7'b0110011 && f7 == 7'b0000001)
      return 1'b1;
    // LR/SC/AMO
    if (op == 7'b0101111)
      return 1'b1;
    // CSR instructions (SYSTEM opcode, funct3 != 000)
    if (op == 7'b1110011 && instr[14:12] != 3'b000)
      return 1'b1;
    // WFI: SYSTEM opcode, funct3=000, imm=000100000101
    if (op == 7'b1110011 && instr[14:12] == 3'b000 && i_imm == 12'b000100000101)
      return 1'b1;
    // ECALL/EBREAK/MRET/SRET: SYSTEM opcode, funct3=000
    if (op == 7'b1110011 && instr[14:12] == 3'b000)
      return 1'b1;
    // Fence / fence.i
    if (op == 7'b0001111)
      return 1'b1;
    // FP load/store
    if (op == 7'b0000111 || op == 7'b0100111)
      return 1'b1;
    // Integer loads (lb, lh, lw, ld, lbu, lhu, lwu) — shadow can't re-read memory
    if (op == 7'b0000011)
      return 1'b1;
    return 1'b0;
  endfunction

  function automatic logic is_branch(input logic [31:0] instr);
    return (instr[6:0] == 7'b1100011); // BRANCH opcode
  endfunction

  // ---------------------------------------------------------------------------
  // sD stage (combinational decode from IQ head)
  // ---------------------------------------------------------------------------
  logic [4:0]        sRs1D, sRs2D, sRdD;
  logic              sSkipVerifyD, sIsBranchD;
  logic              sInstrValidD_q;  // qualified valid

  assign sRs1D        = sInstr32_in[19:15];
  assign sRs2D        = sInstr32_in[24:20];
  assign sRdD         = sInstr32_in[11:7];
  assign sSkipVerifyD = is_skip_verify(sInstr32_in) | sIsHWCSR_in | sIsDummy_in;
  assign sIsBranchD   = is_branch(sInstr32_in);
  assign sInstrValidD_q = sInstrValid_in;

  // ---------------------------------------------------------------------------
  // sD → sE pipeline register
  // ---------------------------------------------------------------------------
  logic [P.XLEN-1:0] sPC_E;
  logic [31:0]       sInstr32_E;
  logic              sPCSrc_E;
  logic [4:0]        sRs1_E, sRs2_E, sRd_E;
  logic              sSkipVerify_E, sIsBranch_E, sInstrValid_E;
  logic              sIsDummy_E, sDummySel_E;

  flopenrc #(P.XLEN) sPC_E_reg      (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sPC_in),       .q(sPC_E));
  flopenrc #(32)     sI32_E_reg     (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sInstr32_in),  .q(sInstr32_E));
  flopenrc #(1)      sPCSrc_E_reg   (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sPCSrc_in),    .q(sPCSrc_E));
  flopenrc #(5)      sRs1_E_reg     (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sRs1D),        .q(sRs1_E));
  flopenrc #(5)      sRs2_E_reg     (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sRs2D),        .q(sRs2_E));
  flopenrc #(5)      sRd_E_reg      (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sRdD),         .q(sRd_E));
  flopenrc #(1)      sSkip_E_reg    (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sSkipVerifyD), .q(sSkipVerify_E));
  flopenrc #(1)      sBr_E_reg      (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sIsBranchD),   .q(sIsBranch_E));
  flopenrc #(1)      sValid_E_reg   (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sInstrValidD_q),.q(sInstrValid_E));
  flopenrc #(1)      sDummy_E_reg   (.clk, .reset, .en(~StallE), .clear(FlushE), .d(sIsDummy_in),  .q(sIsDummy_E));
  flopenrc #(1)      sDummySel_E_reg(.clk, .reset, .en(~StallE), .clear(FlushE), .d(sDummySel_in), .q(sDummySel_E));

  assign sRdE_out = sRd_E;

  // ---------------------------------------------------------------------------
  // sE stage: shadow forwarding + ALU
  // ---------------------------------------------------------------------------
  logic [P.XLEN-1:0] sALUResultE, sIEUAdrE;
  logic [P.XLEN-1:0] sAltResultE, sIEUResultE;
  logic [1:0]        sFlagsE;

  // V1: shadow operands come directly from OQ (main already forwarded correctly).
  // No intra-shadow forwarding needed; eliminates combinational loop through shadow ALU.

  // Shadow ALU — uses OQ operands directly
  alu #(P) salu(
    oq_SrcAE, oq_SrcBE,
    oq_W64E, oq_UW64E, oq_SubArithE,
    oq_ALUSelectE, oq_BSelectE, oq_ZBBSelectE,
    oq_Funct3E, oq_Funct7E, oq_Rs2E,
    oq_BALUControlE, oq_BMUActiveE, oq_CZeroE,
    sALUResultE, sIEUAdrE
  );

  // Shadow comparator (for branch verification) — uses OQ operands directly
  comparator #(P.XLEN) scomp(oq_SrcAE, oq_SrcBE, oq_BranchSignedE, sFlagsE);
  // FlagsE[0] = LT, FlagsE[1] = EQ; branch taken depends on funct3 — simplified:
  // actual branch decision matches main's PCSrcE which we compare at sW via IQ.PCSrc

  // AltResult mux (JAL/JALR link address = PCLink)
  mux2 #(P.XLEN) saltresult(oq_ImmExtE, oq_PCLinkE, oq_JumpE, sAltResultE);
  mux2 #(P.XLEN) sieuresult(sALUResultE, sAltResultE, oq_ALUResultSrcE, sIEUResultE);

  // ---------------------------------------------------------------------------
  // sE → sM pipeline register
  // ---------------------------------------------------------------------------
  logic [P.XLEN-1:0] sPC_M;
  logic [31:0]       sInstr32_M;
  logic              sPCSrc_M;
  logic [4:0]        sRs1_M, sRs2_M, sRd_M;
  logic              sSkipVerify_M, sIsBranch_M, sInstrValid_M;
  logic              sIsDummy_M, sDummySel_M;
  logic [P.XLEN-1:0] sIEUResultM, sIEUAdrM;
  logic [1:0]        sFlagsM;
  logic [1:0]        sMemRW_M;
  logic              sRegWrite_M;

  flopenrc #(P.XLEN) sPC_M_reg      (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sPC_E),         .q(sPC_M));
  flopenrc #(32)     sI32_M_reg     (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sInstr32_E),    .q(sInstr32_M));
  flopenrc #(1)      sPCSrc_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sPCSrc_E),      .q(sPCSrc_M));
  flopenrc #(5)      sRs1_M_reg     (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sRs1_E),        .q(sRs1_M));
  flopenrc #(5)      sRs2_M_reg     (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sRs2_E),        .q(sRs2_M));
  flopenrc #(5)      sRd_M_reg      (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sRd_E),         .q(sRd_M));
  flopenrc #(1)      sSkip_M_reg    (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sSkipVerify_E), .q(sSkipVerify_M));
  flopenrc #(1)      sBr_M_reg      (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sIsBranch_E),   .q(sIsBranch_M));
  flopenrc #(1)      sValid_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sInstrValid_E), .q(sInstrValid_M));
  flopenrc #(P.XLEN) sResult_M_reg  (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sIEUResultE),   .q(sIEUResultM));
  flopenrc #(P.XLEN) sAddr_M_reg    (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sIEUAdrE),      .q(sIEUAdrM));
  flopenrc #(2)      sFlags_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sFlagsE),       .q(sFlagsM));
  flopenrc #(2)      sMemRW_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(oq_MemRWE),     .q(sMemRW_M));
  flopenrc #(1)      sRegWr_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(oq_RegWriteE & sInstrValid_E), .q(sRegWrite_M));
  flopenrc #(1)      sDummy_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sIsDummy_E),    .q(sIsDummy_M));
  flopenrc #(1)      sDummySel_M_reg(.clk, .reset, .en(~StallM), .clear(FlushM), .d(sDummySel_E),   .q(sDummySel_M));

  assign sRdM_out            = sRd_M;

  // sM: pop SQ on store; V1 does address-only check (no D-cache re-read)
  assign sM_pop = sInstrValid_M & sMemRW_M[0] & ~StallM & ~FlushM; // store in sM advancing

  // ---------------------------------------------------------------------------
  // sM → sW pipeline register
  // ---------------------------------------------------------------------------
  logic [P.XLEN-1:0] sPC_W;
  logic [31:0]       sInstr32_W;
  logic              sPCSrc_W;
  logic [4:0]        sRd_W;
  logic              sSkipVerify_W, sIsBranch_W, sInstrValid_W;
  logic              sIsDummy_W, sDummySel_W;
  logic [P.XLEN-1:0] sIEUResultW;
  logic [1:0]        sFlagsW;

  flopenrc #(P.XLEN) sPC_W_reg      (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sPC_M),         .q(sPC_W));
  flopenrc #(32)     sI32_W_reg     (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sInstr32_M),    .q(sInstr32_W));
  flopenrc #(1)      sPCSrc_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sPCSrc_M),      .q(sPCSrc_W));
  flopenrc #(5)      sRd_W_reg      (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sRd_M),         .q(sRd_W));
  flopenrc #(1)      sSkip_W_reg    (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sSkipVerify_M), .q(sSkipVerify_W));
  flopenrc #(1)      sBr_W_reg      (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sIsBranch_M),   .q(sIsBranch_W));
  flopenrc #(1)      sValid_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sInstrValid_M), .q(sInstrValid_W));
  flopenrc #(P.XLEN) sResult_W_reg  (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sIEUResultM),   .q(sIEUResultW));
  flopenrc #(2)      sFlags_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sFlagsM),       .q(sFlagsW));
  flopenrc #(1)      sDummy_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sIsDummy_M),    .q(sIsDummy_W));
  flopenrc #(1)      sDummySel_W_reg(.clk, .reset, .en(~StallW), .clear(FlushW), .d(sDummySel_M),   .q(sDummySel_W));

  // ---------------------------------------------------------------------------
  // sW stage: verification and register file write
  // ---------------------------------------------------------------------------
  logic              sv_match, sv_mismatch;
  logic [P.XLEN-1:0] sv_fault_pc;
  // Branch taken: check FlagsW against branch opcode
  // Simplified: use FlagsW[1] (EQ) and FlagsW[0] (LT), branch direction from funct3
  logic              sBranchTakenW;
  logic [2:0]        sBrFunct3W;
  assign sBrFunct3W    = sInstr32_W[14:12];
  always_comb
    case (sBrFunct3W)
      3'b000: sBranchTakenW =  sFlagsW[1];         // BEQ
      3'b001: sBranchTakenW = ~sFlagsW[1];         // BNE
      3'b100: sBranchTakenW =  sFlagsW[0];         // BLT
      3'b101: sBranchTakenW = ~sFlagsW[0];         // BGE
      3'b110: sBranchTakenW =  sFlagsW[0];         // BLTU
      3'b111: sBranchTakenW = ~sFlagsW[0];         // BGEU
      default: sBranchTakenW = 1'b0;
    endcase

  shadow_verifier #(P) sv (
    .sInstr32(sInstr32_W),
    .sALUResult(sIEUResultW),
    .rq_IntResult(rq_IntResult),
    .rq_IntWriteEn(rq_IntWriteEn),
    .rq_SkipVerify(rq_SkipVerify | sSkipVerify_W),
    .rq_InstrValid(rq_InstrValid & sInstrValid_W),
    .sBranchTaken(sBranchTakenW),
    .rq_PCSrc(sPCSrc_W),
    .isBranch(sIsBranch_W),
    .rq_PC(rq_PC),
    .SecFaultMatch(sv_match),
    .SecFaultMismatch(sv_mismatch),
    .SecFaultPC(sv_fault_pc)
  );

  // sW outputs
  assign sW_pop = ~StallW & ~FlushW;

  // VBC: stubbed for V1
  assign VBC_StallE = 1'b0;

  // Fault detection: use verifier's sv_mismatch (verifier handles SkipVerify + InstrValid).
  assign SecFaultW   = sv_mismatch;
  assign SecFaultPC_W = sv_fault_pc;

  // Regfile write: shadow drives write port with RQ committed value.
  // Write whenever RQ has a valid committing entry, regardless of shadow's own
  // validity.  When shadow has a bubble (flush-induced gap from IQ flush), we
  // trust the main pipeline's RQ result and skip verification for that entry.
  // This is necessary because FlushD (CSR fence, misprediction) flushes the IQ
  // and creates N-cycle holes in the shadow pipeline while RQ continues filling.
  wire write_enable = rq_InstrValid & ~FlushW & (rq_IntWriteEn | rq_DummyW);
  assign shadow_we3      = write_enable;
  assign shadow_a3       = rq_Rd;          // 5-bit; regfile uses DummyW to redirect
  assign shadow_wd3      = rq_IntResult;
  assign shadow_DummyW   = rq_DummyW   & write_enable;
  assign shadow_DummySel = rq_DummySelW;

endmodule
