///////////////////////////////////////////
// shadow_pipeline.sv
//
// Purpose: SHARD shadow pipeline sD -> sE -> sM -> sW.
//          The shadow re-executes every instruction the main pipeline retired, in
//          order, from verified state only, and is the sole writer of the register
//          file.  It is decoupled from the main pipeline's stalls: an instruction
//          enters sE as soon as its IQ entry and its RQ entry exist, and then moves
//          one stage per cycle.
//
//            sD  IQ head.  Decode source registers.
//            sE  Operands from the register file with sM/sW bypass (shadow_hzu),
//                checked against the operands the main pipeline used (OQ).  ALU,
//                branch comparator, immediate and link address recomputed.
//                Next-PC continuity checked.
//            sM  shadow_verifier compares against the OQ, RQ and SQ records.
//            sW  Commit: write the register file, release the RQ entry and mark
//                the store-queue entry verified -- or, on any fault, commit
//                nothing and raise Fault so the core can flush and replay.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_pipeline import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       StreamBreak,     // main took a trap: the next retired PC is not sequential
  // IQ head (sD)
  input  logic                       iqValid,
  input  logic [P.XLEN-1:0]          iqPC,
  input  logic [31:0]                iqInstr,
  input  logic                       iqCompressed,
  output logic                       iqPop,
  // OQ head (sE)
  input  logic [P.XLEN-1:0]          oqForwardedSrcA, oqForwardedSrcB,
  input  logic [P.XLEN-1:0]          oqIEUAdr, oqRawLoadWord,
  input  logic                       oqALUSrcA, oqALUSrcB,
  input  logic [2:0]                 oqImmSrc,
  input  logic                       oqW64, oqUW64, oqSubArith,
  input  logic [2:0]                 oqALUSelect,
  input  logic [3:0]                 oqBSelect, oqZBBSelect,
  input  logic [2:0]                 oqBALUControl,
  input  logic                       oqBMUActive,
  input  logic [1:0]                 oqCZero,
  input  logic                       oqALUResultSrc, oqJump, oqBranch,
  input  logic                       oqPCSrc,
  input  logic                       oqRegWrite,
  input  logic [2:0]                 oqResultSrc,
  input  logic                       oqFWriteInt,
  input  logic                       oqViaSQ, oqAMO, oqLoadChk,
  output logic                       oqPop,
  // RQ: two oldest entries, occupancy, and this cycle's push
  input  logic [4:0]                 rqRd [2],
  input  logic                       rqRegWrite [2],
  input  logic [P.XLEN-1:0]          rqResult [2],
  input  logic [$clog2(DEPTH+1)-1:0] rqCount,
  input  logic                       rqPush,
  // SQ contents
  input  logic [P.PA_BITS-1:0]       sqPA [DEPTH],
  input  logic [1:0]                 sqSize [DEPTH],
  input  logic [P.XLEN-1:0]          sqData [DEPTH],
  input  logic [$clog2(DEPTH+1)-1:0] sqCount, sqNVerified,
  // Register file: shadow read ports and the only write port
  output logic [4:0]                 sRs1E, sRs2E,
  input  logic [P.XLEN-1:0]          sRD1E, sRD2E,
  output logic                       shadow_we3,
  output logic [4:0]                 shadow_a3,
  output logic [P.XLEN-1:0]          shadow_wd3,
  // Commit / fault
  output logic                       Commit,          // sW instruction verified and committed (pops the RQ)
  output logic                       CommitStore,     // ... and it owns the oldest unverified SQ entry
  output logic                       Fault,           // sW instruction failed verification
  output logic [P.XLEN-1:0]          FaultPC,         // where to resume: the PC that instruction should have had
  output logic [7:0]                 FaultClass
);

  localparam int CW = $clog2(DEPTH+1);

  // Stage occupancy
  logic              sValidE, sValidM, sValidW;
  logic              AdvanceDE;

  // sE
  logic [P.XLEN-1:0] sPCE, sPCLinkE, sImmExtE;
  logic [31:0]       sInstrE;
  logic              sCompressedE;
  logic [1:0]        sForwardAE, sForwardBE;
  logic [P.XLEN-1:0] sForwardedSrcAE, sForwardedSrcBE, sSrcAE, sSrcBE;
  logic [P.XLEN-1:0] sALUResultE, sSumE, sAltResultE, sIEUResultE;
  logic [1:0]        sFlagsE;
  logic              sBranchSignedE, sTakenE;
  logic              sOpFaultE, sNPCFaultE;
  logic              sRetE;
  logic              NPCValid;
  logic [P.XLEN-1:0] NPCExpected, sRestartPCE;

  // sM
  logic [P.XLEN-1:0] sRestartPCM, sIEUResultM, sSumM, sSrcBM, sIEUAdrM, sRawLoadWordM, sValM;
  logic [31:0]       sInstrM;
  logic              sTakenM, sOpFaultM, sNPCFaultM;
  logic              sPCSrcM, sRegWriteM, sALUClassM, sLoadChkM, sViaSQM, sAMOM;
  logic [7:0]        sFaultM;
  logic              rqSelM;
  logic [CW-1:0]     sqIdxM;

  // sW
  logic [P.XLEN-1:0] sRestartPCW, sValW;
  logic [4:0]        sRdW;
  logic              sRegWriteW, sViaSQW;
  logic [7:0]        sFaultW;

  ///////////////////////////////////////////
  // sD: an instruction leaves the IQ once its RQ entry is certain to be present
  // when it reaches sM (every instruction in sE, sM, sW owns one RQ entry, in order).
  ///////////////////////////////////////////

  assign AdvanceDE = iqValid & ~Fault &
    ((rqCount + {{(CW-1){1'b0}}, rqPush}) >
     ({{(CW-1){1'b0}}, sValidE} + {{(CW-1){1'b0}}, sValidM} + {{(CW-1){1'b0}}, sValidW}));
  assign iqPop = AdvanceDE;

  always_ff @(posedge clk)
    if (reset | Fault) sValidE <= 1'b0;
    else               sValidE <= AdvanceDE;

  always_ff @(posedge clk)
    if (AdvanceDE) begin
      sPCE         <= iqPC;
      sInstrE      <= iqInstr;
      sCompressedE <= iqCompressed;
    end

  ///////////////////////////////////////////
  // sE: operand sourcing, operand check, re-execution, next-PC continuity
  ///////////////////////////////////////////

  assign sRs1E = sInstrE[19:15];
  assign sRs2E = sInstrE[24:20];

  shadow_hzu hzu(.sRs1E, .sRs2E, .sRdM(sInstrM[11:7]), .sRdW,
    .sRegWriteM(sValidM & sRegWriteM), .sRegWriteW(sValidW & sRegWriteW),
    .sForwardAE, .sForwardBE);

  mux3 #(P.XLEN) sfaemux(sRD1E, sValW, sValM, sForwardAE, sForwardedSrcAE);
  mux3 #(P.XLEN) sfbemux(sRD2E, sValW, sValM, sForwardBE, sForwardedSrcBE);

  // The main pipeline must have used exactly the operands the shadow derives from
  // verified state.  This covers the forwarding selects, RQ forwarding and regfile read.
  assign sOpFaultE = (sForwardedSrcAE != oqForwardedSrcA) | (sForwardedSrcBE != oqForwardedSrcB);

  extend #(P) sext(.InstrD(sInstrE[31:7]), .ImmSrcD(oqImmSrc), .ImmExtD(sImmExtE));
  assign sPCLinkE = sPCE + (sCompressedE ? 'd2 : 'd4);

  mux2 #(P.XLEN) ssrcamux(sForwardedSrcAE, sPCE, oqALUSrcA, sSrcAE);
  mux2 #(P.XLEN) ssrcbmux(sForwardedSrcBE, sImmExtE, oqALUSrcB, sSrcBE);

  alu #(P) salu(sSrcAE, sSrcBE, oqW64, oqUW64, oqSubArith, oqALUSelect, oqBSelect, oqZBBSelect,
    sInstrE[14:12], sInstrE[31:25], sInstrE[24:20], oqBALUControl, oqBMUActive, oqCZero,
    sALUResultE, sSumE);

  assign sBranchSignedE = ~(sInstrE[14:13] == 2'b11) & oqBranch;
  comparator #(P.XLEN) scomp(sForwardedSrcAE, sForwardedSrcBE, sBranchSignedE, sFlagsE);
  assign sTakenE = oqJump | (oqBranch & ((sInstrE[14] ? sFlagsE[0] : sFlagsE[1]) ^ sInstrE[12]));

  mux2 #(P.XLEN) saltresultmux(sImmExtE, sPCLinkE, oqJump, sAltResultE);
  mux2 #(P.XLEN) sieuresultmux(sALUResultE, sAltResultE, oqALUResultSrc, sIEUResultE);

  // Next-PC continuity: each retired instruction must sit where its predecessor leads
  // (fall-through, or the shadow's own branch/jump target).  A trap and an xRET break
  // the chain; the first instruction after one is not checked.  When the chain is
  // intact the expected PC, not the PC the main pipeline actually fetched, is where a
  // replay must resume -- for a next-PC fault the two differ.
  assign sNPCFaultE  = NPCValid & (sPCE != NPCExpected);
  assign sRestartPCE = NPCValid ? NPCExpected : sPCE;
  assign sRetE = (sInstrE[6:0] == 7'b1110011) & (sInstrE[19:7] == 13'b0) &
                 ((sInstrE[31:20] == 12'b000100000010) | (sInstrE[31:20] == 12'b001100000010));

  always_ff @(posedge clk)
    if (reset | StreamBreak) NPCValid <= 1'b0;
    else if (Fault)          NPCValid <= 1'b1;     // the replay must start at FaultPC
    else if (sValidE)        NPCValid <= ~sRetE;

  always_ff @(posedge clk)
    if (Fault)        NPCExpected <= FaultPC;
    else if (sValidE) NPCExpected <= sTakenE ? {sSumE[P.XLEN-1:1], 1'b0} : sPCLinkE;

  assign oqPop = sValidE & ~Fault;

  ///////////////////////////////////////////
  // sE -> sM
  ///////////////////////////////////////////

  always_ff @(posedge clk)
    if (reset | Fault) sValidM <= 1'b0;
    else               sValidM <= sValidE;

  always_ff @(posedge clk)
    if (sValidE) begin
      sRestartPCM   <= sRestartPCE;
      sInstrM       <= sInstrE;
      sIEUResultM   <= sIEUResultE;
      sSumM         <= sSumE;
      sTakenM       <= sTakenE;
      sSrcBM        <= sForwardedSrcBE;
      sOpFaultM     <= sOpFaultE;
      sNPCFaultM    <= sNPCFaultE;
      sIEUAdrM      <= oqIEUAdr;
      sRawLoadWordM <= oqRawLoadWord;
      sPCSrcM       <= oqPCSrc;
      sRegWriteM    <= oqRegWrite;
      sALUClassM    <= (oqResultSrc == 3'b000) & ~oqFWriteInt;
      sLoadChkM     <= oqLoadChk;
      sViaSQM       <= oqViaSQ;
      sAMOM         <= oqAMO;
    end

  ///////////////////////////////////////////
  // sM: verification against the RQ and SQ records
  ///////////////////////////////////////////

  // sW owns RQ entry 0 when occupied, so sM's entry is right behind it.  Likewise the
  // store in sM owns the oldest unverified SQ entry unless sW holds an older store.
  assign rqSelM = sValidW;
  assign sqIdxM = sqNVerified + {{(CW-1){1'b0}}, sValidW & sViaSQW};

  shadow_verifier #(P) verifier(
    .sOpFault(sOpFaultM), .sNPCFault(sNPCFaultM),
    .sInstr(sInstrM), .sIEUResult(sIEUResultM), .sSum(sSumM), .sTaken(sTakenM), .sSrcB(sSrcBM),
    .mIEUAdr(sIEUAdrM), .mRawLoadWord(sRawLoadWordM), .mPCSrc(sPCSrcM), .mRegWrite(sRegWriteM),
    .mALUClass(sALUClassM), .mLoadChk(sLoadChkM), .mViaSQ(sViaSQM), .mAMO(sAMOM),
    .rqRd(rqRd[rqSelM]), .rqRegWrite(rqRegWrite[rqSelM]), .rqResult(rqResult[rqSelM]),
    .sqValid(sqIdxM < sqCount), .sqPA(sqPA[sqIdxM[$clog2(DEPTH)-1:0]]),
    .sqSize(sqSize[sqIdxM[$clog2(DEPTH)-1:0]]), .sqData(sqData[sqIdxM[$clog2(DEPTH)-1:0]]),
    .Fault(sFaultM));

  // Value this instruction leaves in its destination register: the shadow's own result
  // where it can recompute it, otherwise the main pipeline's result record.
  assign sValM = sALUClassM ? sIEUResultM : rqResult[rqSelM];

  ///////////////////////////////////////////
  // sM -> sW
  ///////////////////////////////////////////

  always_ff @(posedge clk)
    if (reset | Fault) sValidW <= 1'b0;
    else               sValidW <= sValidM;

  always_ff @(posedge clk)
    if (sValidM) begin
      sRestartPCW <= sRestartPCM;
      sRdW       <= sInstrM[11:7];
      sRegWriteW <= sRegWriteM;
      sViaSQW    <= sViaSQM;
      sValW      <= sValM;
      sFaultW    <= sFaultM;
    end

  ///////////////////////////////////////////
  // sW: commit or fault
  ///////////////////////////////////////////

  assign Fault       = sValidW & (|sFaultW);
  assign FaultPC     = sRestartPCW;
  assign FaultClass  = sFaultW;
  assign Commit      = sValidW & ~(|sFaultW);
  assign CommitStore = Commit & sViaSQW;

  assign shadow_we3 = Commit & sRegWriteW;
  assign shadow_a3  = sRdW;
  assign shadow_wd3 = sValW;

endmodule
