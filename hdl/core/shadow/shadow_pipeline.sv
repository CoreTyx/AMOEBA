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
  input  logic [P.XLEN-1:0] rq_RawLoadWord,   // Rev 6: raw aligned load word (self-contained data verify)
  input  logic [2:0]        rq_Funct3,        // Rev 6: load size/signedness
  input  logic              rq_Compressed,    // Rev 7: 2-byte instruction (next-PC check)
  input  logic              rq_IsCtrlFlow,    // Rev 7: branch/jal/jalr/system/fence
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
  // SHARD D-cache re-read interface (connected to lsu)
  output logic              shadow_dcache_req,
  output logic [P.PA_BITS-1:0] shadow_dcache_pa,
  input  logic [P.XLEN-1:0] shadow_dcache_data,
  input  logic              shadow_dcache_stall,
  // D-cache re-read stall to hazard (stalls main at M while shadow re-reads)
  output logic              ShadowDCacheStallM,
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
    // Integer loads (lb/lh/lw/ld/lbu/lhu/lwu): Rev 6 verifies the EFFECTIVE ADDRESS
    // (shadow recomputes rs1+imm and compares to the main's observed access address via
    // RQ.MemAddr) — a non-destructive, independent check of the address datapath.  The
    // loaded DATA is trusted (SECDED-covered SRAM).  Loads are therefore NOT SkipVerify.
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

  // Shadow operands come directly from OQ (main already forwarded correctly).
  // shadow_hzu is NOT instantiated: the shadow pipeline uses a coupled-stall model
  // (any shadow stall = main stall), so shadow and main are always in lockstep.
  // OQ provides post-forwarded operands, so no intra-shadow RAW hazards can occur.

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
  logic              sOQValid_M;   // OQ head validity (operand path) carried to sW

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
  flopenrc #(1)      sOQVld_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(oq_InstrValidE),                .q(sOQValid_M));
  flopenrc #(1)      sDummy_M_reg   (.clk, .reset, .en(~StallM), .clear(FlushM), .d(sIsDummy_E),    .q(sIsDummy_M));
  flopenrc #(1)      sDummySel_M_reg(.clk, .reset, .en(~StallM), .clear(FlushM), .d(sDummySel_E),   .q(sDummySel_M));

  assign sRdM_out            = sRd_M;

  // ---------------------------------------------------------------------------
  // sM stage: D-cache re-read for loads and stores
  // ---------------------------------------------------------------------------
  // Shadow re-reads the D-cache to verify load data (vs RQ.IntResult) and
  // store data (vs SQ.WriteData).  Main is stalled (ShadowDCacheStallM) while
  // the re-read is in flight.  sM_read_done_r latches completion so we don't
  // re-issue after a DCacheStall multi-cycle hit.
  logic shadow_is_load_M, shadow_is_store_M, shadow_needs_dcache_M;
  logic sM_read_done_r;
  logic [P.XLEN-1:0] sM_dcache_result_r;  // latched D-cache read result for sW

  assign shadow_is_load_M      = sMemRW_M[1] & sInstrValid_M & ~sSkipVerify_M;
  assign shadow_is_store_M     = sMemRW_M[0] & sInstrValid_M & ~sSkipVerify_M;

  // V1: the D-cache re-read is DISABLED because it is destructive — a forced read of a
  // just-stored dirty line misses and triggers a writeback+refill that overwrites the
  // dirty store data with stale memory (confirmed on test_fwd_depth, see
  // shadow_debug_progress.md).  The shadow therefore never drives the shared cache port.
  // Loads are SkipVerify (committed from RQ); stores are address-tracked via the SQ but
  // their data is not re-read.  A proper non-destructive scheme (dedicated read-only
  // snoop port, or compare shadow store-data vs SQ) is left for V2.
  assign shadow_needs_dcache_M = 1'b0;
  assign shadow_dcache_pa  = '0;
  assign shadow_dcache_req = 1'b0;
  assign ShadowDCacheStallM = 1'b0;

  // sM_read_done_r retained but inert (re-read disabled): keeps sW mem-result-valid low.
  always_ff @(posedge clk) begin
    if (reset | FlushM) begin
      sM_read_done_r    <= 1'b0;
      sM_dcache_result_r <= '0;
    end else if (~StallM) begin
      sM_read_done_r    <= 1'b0;
      sM_dcache_result_r <= '0;
    end
  end

  // SQ pop: one store consumed per store that passes sM (no re-read dependency).
  assign sM_pop = shadow_is_store_M & ~StallM & ~FlushM;

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
  logic [P.XLEN-1:0] sDCacheResult_W;   // D-cache re-read result from sM
  logic              sMemResultValid_W; // 1 = load/store re-read completed
  logic              sIsLoad_W, sIsStore_W;
  logic [P.XLEN/8-1:0] sSQByteM_W;      // SQ byte mask from sM
  logic [P.XLEN-1:0] sSQWriteData_W;    // SQ write data from sM (for store comparison)
  logic [P.XLEN-1:0] sIEUAdrW;          // Rev 6: shadow-recomputed effective address at sW
  logic              sOQValid_W;        // Rev 6: OQ (operand path) validity at sW

  flopenrc #(P.XLEN) sPC_W_reg      (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sPC_M),              .q(sPC_W));
  flopenrc #(32)     sI32_W_reg     (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sInstr32_M),         .q(sInstr32_W));
  flopenrc #(1)      sPCSrc_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sPCSrc_M),           .q(sPCSrc_W));
  flopenrc #(5)      sRd_W_reg      (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sRd_M),              .q(sRd_W));
  flopenrc #(1)      sSkip_W_reg    (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sSkipVerify_M),      .q(sSkipVerify_W));
  flopenrc #(1)      sBr_W_reg      (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sIsBranch_M),        .q(sIsBranch_W));
  flopenrc #(1)      sValid_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sInstrValid_M),      .q(sInstrValid_W));
  flopenrc #(P.XLEN) sResult_W_reg  (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sIEUResultM),        .q(sIEUResultW));
  flopenrc #(2)      sFlags_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sFlagsM),            .q(sFlagsW));
  flopenrc #(1)      sDummy_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sIsDummy_M),         .q(sIsDummy_W));
  flopenrc #(1)      sDummySel_W_reg(.clk, .reset, .en(~StallW), .clear(FlushW), .d(sDummySel_M),        .q(sDummySel_W));
  flopenrc #(P.XLEN) sDCR_W_reg     (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sM_dcache_result_r), .q(sDCacheResult_W));
  flopenrc #(1)      sMemRV_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sM_read_done_r),     .q(sMemResultValid_W));
  flopenrc #(1)      sIsLd_W_reg    (.clk, .reset, .en(~StallW), .clear(FlushW), .d(shadow_is_load_M),   .q(sIsLoad_W));
  flopenrc #(1)      sIsSt_W_reg    (.clk, .reset, .en(~StallW), .clear(FlushW), .d(shadow_is_store_M),  .q(sIsStore_W));
  flopenrc #(P.XLEN/8) sSQBM_W_reg  (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sq_ByteMask),        .q(sSQByteM_W));
  flopenrc #(P.XLEN) sSQWD_W_reg    (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sq_WriteData),       .q(sSQWriteData_W));
  flopenrc #(P.XLEN) sEA_W_reg      (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sIEUAdrM),           .q(sIEUAdrW));
  flopenrc #(1)      sOQVld_W_reg   (.clk, .reset, .en(~StallW), .clear(FlushW), .d(sOQValid_M),         .q(sOQValid_W));

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
    // Require the OQ (operand) path valid too: around load-use bubbles the IQ (PC) and
    // OQ (operands) transiently disagree; verifying then would compare a bubble operand
    // set against a real RQ result.  Gating on sOQValid_W makes verification sound.
    .rq_InstrValid(rq_InstrValid & sInstrValid_W & sOQValid_W),
    .sBranchTaken(sBranchTakenW),
    .rq_PCSrc(sPCSrc_W),
    .isBranch(sIsBranch_W),
    .rq_PC(rq_PC),
    .sPC(sPC_W),
    // Rev 6: effective-address verification for loads/stores (non-destructive).
    // The shadow's independent address adder (sIEUAdrW) is compared against the
    // main's observed access address carried in RQ.MemAddr.
    .sEA(sIEUAdrW),
    .mainEA(rq_MemAddr),
    .isLoad(sIsLoad_W),
    .isStore(sIsStore_W),
    .SecFaultMatch(sv_match),
    .SecFaultMismatch(sv_mismatch),
    .SecFaultPC(sv_fault_pc)
  );

  // sW outputs.
  // Pop must match the RQ shift condition exactly (RQ shifts on ~StallW).  FlushW must
  // NOT gate the pop: a W-stage flush (trap/ret, or WFI's LatestUnstalledW) squashes the
  // YOUNGEST slot (RQ entry[0], already bubbled by the RQ push logic), never the RQ head
  // (entry[N-1]), which is an older instruction that retired N cycles ago and must commit.
  assign sW_pop = ~StallW;

  // VBC: stubbed for V1
  assign VBC_StallE = 1'b0;

  // ---------------------------------------------------------------------------
  // Rev 6: self-contained load-DATA verification.
  // The raw aligned load word, the access address, the size/signedness (funct3) and the
  // committed result all live in the SAME RQ entry, so the shadow can re-derive the
  // loaded value with its OWN copy of subwordread and compare — no shadow-pipeline
  // alignment required (unlike the EA check, which uses the shadow's independent adder).
  // This catches faults in the subword-extract / sign-extend datapath.  The raw memory
  // word itself is SECDED-covered.  FP loads are excluded (rq_IntWriteEn=0 for them).
  // ---------------------------------------------------------------------------
  logic [P.LLEN-1:0] sExpectedLoadLLEN;
  logic              rq_is_int_load, load_data_mismatch;

  subwordread #(P) sswr (
    .ReadDataWordMuxM({{(P.LLEN-P.XLEN){1'b0}}, rq_RawLoadWord}),
    .PAdrM(rq_MemAddr[3:0]),
    .Funct3M(rq_Funct3),
    .FpLoadStoreM(1'b0),      // integer loads only; FP loads are SkipVerify / IntWriteEn=0
    .BigEndianM(1'b0),        // little-endian targets (bare-metal, Linux)
    .ReadDataM(sExpectedLoadLLEN)
  );

  // Pure integer load only: MemRW==2'b10 (read, not write) excludes stores AND AMOs
  // (AMO=2'b11), and rq_IntWriteEn excludes FP loads.  AMO/CSR verification is a
  // documented boundary (needs operand+written-value capture + a shadow AMO/CSR ALU).
  assign rq_is_int_load     = (rq_MemRW == 2'b10) & rq_IntWriteEn & rq_InstrValid;
  assign load_data_mismatch = rq_is_int_load & (sExpectedLoadLLEN[P.XLEN-1:0] != rq_IntResult);

  // ---------------------------------------------------------------------------
  // Rev 7: next-PC continuity check (RQ-self-contained).
  // Consecutive committed RQ entries are consecutive retired instructions (bubbles
  // have InstrValid=0 and are skipped).  A sequential (non-control-flow) instruction
  // must be followed by one at PC + ilen (2 if compressed, else 4), recomputed with
  // the shadow's own adder.  Legitimate discontinuities — control-flow
  // (branch/jal/jalr/system/fence, via rq_IsCtrlFlow) and any trap/redirect (FlushW
  // since the last commit) — are excluded, so the check is sound.  No shadow-pipeline
  // alignment needed; it runs on every sequential commit pair.  Catches IFU
  // sequential-PC (PC+ilen) datapath faults.
  // ---------------------------------------------------------------------------
  wire npc_rq_commit = ~StallW & rq_InstrValid;

  logic              npc_prev_valid, npc_prev_check, npc_flush_seen;
  logic [P.XLEN-1:0] npc_expected;
  logic              next_pc_mismatch;

  assign next_pc_mismatch = npc_rq_commit & npc_prev_valid & npc_prev_check
                          & ~npc_flush_seen & (rq_PC != npc_expected);

  always_ff @(posedge clk) begin
    if (reset) begin
      npc_prev_valid <= 1'b0; npc_prev_check <= 1'b0; npc_flush_seen <= 1'b0; npc_expected <= '0;
    end else begin
      if (FlushW) npc_flush_seen <= 1'b1;              // a trap/redirect broke the stream
      if (npc_rq_commit) begin
        npc_prev_valid <= 1'b1;
        npc_prev_check <= ~rq_IsCtrlFlow;              // only predict fall-through after sequential ops
        npc_expected   <= rq_PC + (rq_Compressed ? 'd2 : 'd4);
        npc_flush_seen <= FlushW;                      // open a fresh window
      end
    end
  end

  // Fault detection: verifier (ALU/branch/EA) OR load-data OR next-PC continuity.
  assign SecFaultW   = sv_mismatch | load_data_mismatch | next_pc_mismatch;
  assign SecFaultPC_W = sv_mismatch ? sv_fault_pc : (next_pc_mismatch ? sPC_W : rq_PC);



  // Regfile write: shadow drives write port with RQ committed value.
  // Write whenever RQ has a valid committing entry, regardless of shadow's own
  // validity.  When shadow has a bubble (flush-induced gap from IQ flush), we
  // trust the main pipeline's RQ result and skip verification for that entry.
  // This is necessary because FlushD (CSR fence, misprediction) flushes the IQ
  // and creates N-cycle holes in the shadow pipeline while RQ continues filling.
  // write_enable must NOT be gated by FlushW: the RQ head is an older instruction whose
  // result is final; a trap/ret/WFI flush of the W stage pertains to the youngest slot
  // (RQ entry[0], already bubbled on push), not the head.  Gating the head's commit on
  // FlushW silently drops the head's register write whenever the RQ shifts under FlushW
  // (every interrupt/trap), leaving the main regfile stale — observed as "stale rs read"
  // under FreeRTOS's frequent timer interrupts.
  wire write_enable = rq_InstrValid & (rq_IntWriteEn | rq_DummyW);
  assign shadow_we3      = write_enable;
  assign shadow_a3       = rq_Rd;          // 5-bit; regfile uses DummyW to redirect
  assign shadow_wd3      = rq_IntResult;
  assign shadow_DummyW   = rq_DummyW   & write_enable;
  assign shadow_DummySel = rq_DummySelW;

endmodule
