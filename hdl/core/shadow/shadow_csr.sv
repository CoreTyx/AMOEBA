///////////////////////////////////////////
// shadow_csr.sv
//
// Purpose: SHARD CSR state mirror.  An independent second copy of the trap-handling
//          and translation state of the CSR file:
//
//            privilege mode, mstatus (and its sstatus view), medeleg, mideleg,
//            mtvec, mscratch, mepc, mcause, mtval,
//            stvec, sscratch, sepc, scause, stval, satp
//
//          The mirror keeps its own storage and applies its own decode, its own
//          WARL legalization and its own trap-entry / trap-return updates, from the
//          same committed events that update the main CSR file (a retiring CSR
//          instruction, a trap, an xRET).  CSR writes and traps only happen once the
//          shadow pipeline is quiescent, so the events arrive in architectural order
//          and the write operand has already been checked against the register file.
//
//          It provides three checks:
//           - read:  the value a CSR instruction reads must equal the mirror's;
//           - write: the value a CSR instruction is about to write must equal the
//                    one the mirror computes from its own old value (both are
//                    checked in csr.sv before the instruction commits);
//           - state: every mirrored register must equal the main one in every
//                    cycle.  This catches a wrong legalization, a wrong trap or
//                    return side effect, a missed or spurious write, and an upset in
//                    either copy's storage.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_csr import cvw::*; #(parameter cvw_t P) (
  input  logic              clk, reset,
  input  logic              StallW,
  // Committed events
  input  logic              CSRWriteCommitM,     // a CSR instruction writes its CSR this cycle
  input  logic [11:0]       CSRAdrM,
  input  logic [1:0]        CSROpM,              // 01 write, 10 set, 11 clear
  input  logic [P.XLEN-1:0] CSRSrcM,             // rs1 value or zero-extended immediate
  input  logic              TrapM, InterruptM,
  input  logic [4:0]        CauseM,
  input  logic              mretM, sretM,
  input  logic [P.XLEN-1:0] PCM,
  input  logic [P.XLEN-1:0] EccDedFaultEPCM, ShadowFaultEPCM,
  input  logic [P.XLEN-1:0] NextFaultMtvalM,
  input  logic              FSDirtyM,            // floating-point state written
  input  logic              Resync,              // reload the mirror from the main CSR file
  // Main CSR state
  input  logic [1:0]        PrivilegeModeW,
  input  logic [P.XLEN-1:0] MSTATUS_REGW, MSTATUSH_REGW,
  input  logic [15:0]       MEDELEG_REGW,
  input  logic [11:0]       MIDELEG_REGW,
  input  logic [P.XLEN-1:0] MTVEC_REGW, MSCRATCH_REGW, MEPC_REGW, MCAUSE_REGW, MTVAL_REGW,
  input  logic [P.XLEN-1:0] STVEC_REGW, SSCRATCH_REGW, SEPC_REGW, SCAUSE_REGW, STVAL_REGW, SATP_REGW,
  // Checks
  output logic              MirrorHitM,          // CSRAdrM is a mirrored CSR
  output logic [P.XLEN-1:0] MirrorReadValM,      // its value as a CSR instruction reads it
  output logic              StateFault           // some mirrored register differs from the main one
);

  localparam MSTATUS  = 12'h300;
  localparam MEDELEG  = 12'h302;
  localparam MIDELEG  = 12'h303;
  localparam MTVEC    = 12'h305;
  localparam MSTATUSH = 12'h310;
  localparam MSCRATCH = 12'h340;
  localparam MEPC     = 12'h341;
  localparam MCAUSE   = 12'h342;
  localparam MTVAL    = 12'h343;
  localparam SSTATUS  = 12'h100;
  localparam STVEC    = 12'h105;
  localparam SSCRATCH = 12'h140;
  localparam SEPC     = 12'h141;
  localparam SCAUSE   = 12'h142;
  localparam STVAL    = 12'h143;
  localparam SATP     = 12'h180;

  localparam MEDELEG_MASK = P.ZCA_SUPPORTED ? 16'hB3FE : 16'hB3FF;
  localparam MIDELEG_MASK = 12'h222;

  // Mirror storage
  logic [1:0]        mPriv;
  logic              mTSR, mTW, mTVM, mMXR, mSUM, mMPRV;
  logic [1:0]        mFS, mMPP;
  logic              mSPP, mMPIE, mSPIE, mMIE, mSIE, mMBE, mSBE, mUBE;
  logic [15:0]       mMEDELEG;
  logic [11:0]       mMIDELEG;
  logic [P.XLEN-1:0] mMTVEC, mMSCRATCH, mMEPC, mMCAUSE, mMTVAL;
  logic [P.XLEN-1:0] mSTVEC, mSSCRATCH, mSEPC, mSCAUSE, mSTVAL, mSATP;

  // Status views
  logic              vTSR, vTW, vTVM, vMXR, vSUM, vMPRV, vSD;
  logic [1:0]        vFS, vSXL, vUXL;
  logic [P.XLEN-1:0] mMSTATUS, mSSTATUS, mMSTATUSH;

  logic [P.XLEN-1:0] WriteVal, TVECWriteVal, TrapEPC, NextEPC;
  logic              WrM, WrS;
  logic              Delegate, MTrap, STrap;
  logic [1:0]        TrapPriv, NextPriv, MPPNext;
  logic              LegalSatpMode;

  ///////////////////////////////////////////
  // Read views (what a CSR instruction would read)
  ///////////////////////////////////////////

  assign vTSR  = P.S_SUPPORTED & mTSR;
  assign vTW   = P.U_SUPPORTED & mTW;
  assign vTVM  = P.S_SUPPORTED & mTVM;
  assign vMXR  = P.S_SUPPORTED & mMXR;
  assign vSUM  = P.S_SUPPORTED & P.VIRTMEM_SUPPORTED & mSUM;
  assign vMPRV = P.U_SUPPORTED & mMPRV;
  assign vFS   = P.F_SUPPORTED ? mFS : 2'b00;
  assign vSD   = (vFS == 2'b11);
  assign vSXL  = P.S_SUPPORTED ? 2'b10 : 2'b00;
  assign vUXL  = P.U_SUPPORTED ? 2'b10 : 2'b00;

  if (P.XLEN == 64) begin : status64
    assign mMSTATUS  = {vSD, 25'b0, mMBE, mSBE, vSXL, vUXL, 9'b0,
                        vTSR, vTW, vTVM, vMXR, vSUM, vMPRV,
                        2'b00, vFS, mMPP, 2'b0,
                        mSPP, mMPIE, mUBE, mSPIE, 1'b0,
                        mMIE, 1'b0, mSIE, 1'b0};
    assign mSSTATUS  = {vSD, 29'b0, vUXL, 12'b0,
                        vMXR, vSUM, 1'b0,
                        2'b00, vFS, 4'b0,
                        mSPP, 1'b0, mUBE, mSPIE,
                        3'b0, mSIE, 1'b0};
    assign mMSTATUSH = '0;
  end else begin : status32
    assign mMSTATUS  = {vSD, 8'b0,
                        vTSR, vTW, vTVM, vMXR, vSUM, vMPRV,
                        2'b00, vFS, mMPP, 2'b0,
                        mSPP, mMPIE, mUBE, mSPIE, 1'b0, mMIE, 1'b0, mSIE, 1'b0};
    assign mMSTATUSH = {26'b0, mMBE, mSBE, 4'b0};
    assign mSSTATUS  = {vSD, 11'b0,
                        vMXR, vSUM, 1'b0,
                        2'b00, vFS, 4'b0,
                        mSPP, 1'b0, mUBE, mSPIE,
                        3'b0, mSIE, 1'b0};
  end

  always_comb begin
    MirrorHitM     = 1'b1;
    MirrorReadValM = '0;
    case (CSRAdrM)
      MSTATUS:  MirrorReadValM = mMSTATUS;
      MSTATUSH: if (P.XLEN == 32) MirrorReadValM = mMSTATUSH;
                else              MirrorHitM = 1'b0;
      MEDELEG:  if (P.S_SUPPORTED) MirrorReadValM = {{(P.XLEN-16){1'b0}}, mMEDELEG};
                else               MirrorHitM = 1'b0;
      MIDELEG:  if (P.S_SUPPORTED) MirrorReadValM = {{(P.XLEN-12){1'b0}}, mMIDELEG};
                else               MirrorHitM = 1'b0;
      MTVEC:    MirrorReadValM = mMTVEC;
      MSCRATCH: MirrorReadValM = mMSCRATCH;
      MEPC:     MirrorReadValM = mMEPC;
      MCAUSE:   MirrorReadValM = mMCAUSE;
      MTVAL:    MirrorReadValM = mMTVAL;
      SSTATUS:  if (P.S_SUPPORTED) MirrorReadValM = mSSTATUS;
                else               MirrorHitM = 1'b0;
      STVEC:    if (P.S_SUPPORTED) MirrorReadValM = mSTVEC;
                else               MirrorHitM = 1'b0;
      SSCRATCH: if (P.S_SUPPORTED) MirrorReadValM = mSSCRATCH;
                else               MirrorHitM = 1'b0;
      SEPC:     if (P.S_SUPPORTED) MirrorReadValM = mSEPC;
                else               MirrorHitM = 1'b0;
      SCAUSE:   if (P.S_SUPPORTED) MirrorReadValM = mSCAUSE;
                else               MirrorHitM = 1'b0;
      STVAL:    if (P.S_SUPPORTED) MirrorReadValM = mSTVAL;
                else               MirrorHitM = 1'b0;
      SATP:     if (P.S_SUPPORTED) MirrorReadValM = mSATP;
                else               MirrorHitM = 1'b0;
      default:  MirrorHitM = 1'b0;
    endcase
  end

  ///////////////////////////////////////////
  // Next-state inputs
  ///////////////////////////////////////////

  // Value written by the CSR instruction, from the mirror's own old value
  always_comb
    case (CSROpM)
      2'b01:   WriteVal = CSRSrcM;
      2'b10:   WriteVal = MirrorReadValM | CSRSrcM;
      2'b11:   WriteVal = MirrorReadValM & ~CSRSrcM;
      default: WriteVal = MirrorReadValM;
    endcase

  assign WrM = CSRWriteCommitM & (mPriv == P.M_MODE);
  assign WrS = CSRWriteCommitM & (|mPriv) & P.S_SUPPORTED;

  // Trap target privilege, from the mirror's own delegation registers
  assign Delegate = P.S_SUPPORTED & ~CauseM[4] &
                    (InterruptM ? mMIDELEG[CauseM[3:0]] : mMEDELEG[CauseM[3:0]]) &
                    (mPriv == P.U_MODE | mPriv == P.S_MODE);
  assign TrapPriv = Delegate ? P.S_MODE : P.M_MODE;
  assign MTrap    = TrapM & (TrapPriv == P.M_MODE);
  assign STrap    = TrapM & (TrapPriv == P.S_MODE) & P.S_SUPPORTED;

  always_comb
    if      (TrapM) NextPriv = TrapPriv;
    else if (mretM) NextPriv = (mMPP == 2'b10) ? P.M_MODE : mMPP;
    else if (sretM) NextPriv = {1'b0, mSPP};
    else            NextPriv = mPriv;

  always_comb
    if      (WriteVal[12:11] == P.U_MODE & P.U_SUPPORTED) MPPNext = P.U_MODE;
    else if (WriteVal[12:11] == P.S_MODE & P.S_SUPPORTED) MPPNext = P.S_MODE;
    else if (WriteVal[12:11] == P.M_MODE)                 MPPNext = P.M_MODE;
    else                                                  MPPNext = mMPP;

  assign TVECWriteVal = WriteVal[0] ? {WriteVal[P.XLEN-1:6], 6'b000001} : {WriteVal[P.XLEN-1:2], 2'b00};

  // Hardware-error (19) and SHARD (16) traps report a captured PC
  assign TrapEPC = (CauseM == 5'd19) ? EccDedFaultEPCM : (CauseM == 5'd16) ? ShadowFaultEPCM : PCM;
  always_comb begin
    NextEPC = TrapM ? TrapEPC : WriteVal;
    NextEPC[0] = 1'b0;
    if (!P.ZCA_SUPPORTED) NextEPC[1] = 1'b0;
  end

  if (P.XLEN == 64) begin : satp64
    assign LegalSatpMode = P.SV39_SUPPORTED &
                           ((WriteVal[63:60] == 4'b0) | (WriteVal[63:60] == P.SV39) |
                            (P.SV48_SUPPORTED & WriteVal[63:60] == P.SV48) |
                            (P.SV57_SUPPORTED & WriteVal[63:60] == P.SV57));
  end else begin : satp32
    assign LegalSatpMode = P.SV32_SUPPORTED;
  end

  ///////////////////////////////////////////
  // State update
  ///////////////////////////////////////////

  always_ff @(posedge clk)
    if (reset)             mPriv <= P.M_MODE;
    else if (Resync)       mPriv <= PrivilegeModeW;
    else if (~StallW)      mPriv <= P.U_SUPPORTED ? NextPriv : P.M_MODE;

  always_ff @(posedge clk)
    if (reset) begin
      {mTSR, mTW, mTVM, mMXR, mSUM, mMPRV} <= '0;
      mFS <= 2'b00; mMPP <= 2'b00;
      {mSPP, mMPIE, mSPIE, mMIE, mSIE, mMBE, mSBE, mUBE} <= '0;
    end else if (Resync) begin
      {mTSR, mTW, mTVM, mMXR, mSUM, mMPRV} <= MSTATUS_REGW[22:17];
      mFS   <= MSTATUS_REGW[14:13];
      mMPP  <= MSTATUS_REGW[12:11];
      mSPP  <= MSTATUS_REGW[8];
      mMPIE <= MSTATUS_REGW[7];
      mUBE  <= MSTATUS_REGW[6];
      mSPIE <= MSTATUS_REGW[5];
      mMIE  <= MSTATUS_REGW[3];
      mSIE  <= MSTATUS_REGW[1];
      mMBE  <= (P.XLEN == 64) ? MSTATUS_REGW[P.XLEN-27] : MSTATUSH_REGW[5];
      mSBE  <= (P.XLEN == 64) ? MSTATUS_REGW[P.XLEN-28] : MSTATUSH_REGW[4];
    end else if (~StallW) begin
      if (TrapM) begin
        if (TrapPriv == P.M_MODE) begin
          mMPIE <= mMIE;
          mMIE  <= 1'b0;
          mMPP  <= mPriv;
        end else if (P.S_SUPPORTED) begin
          mSPIE <= mSIE;
          mSIE  <= 1'b0;
          mSPP  <= mPriv[0];
        end
      end else if (mretM) begin
        mMIE  <= mMPIE;
        mMPIE <= 1'b1;
        mMPP  <= P.U_SUPPORTED ? P.U_MODE : P.M_MODE;
        mMPRV <= mMPRV & (mMPP == P.M_MODE);
      end else if (sretM & P.S_SUPPORTED) begin
        mSIE  <= mSPIE;
        mSPIE <= P.S_SUPPORTED;
        mSPP  <= 1'b0;
        mMPRV <= 1'b0;
      end else if (WrM & (CSRAdrM == MSTATUS)) begin
        mTSR  <= P.S_SUPPORTED & WriteVal[22];
        mTW   <= P.U_SUPPORTED & WriteVal[21];
        mTVM  <= P.S_SUPPORTED & WriteVal[20];
        mMXR  <= P.S_SUPPORTED & WriteVal[19];
        mSUM  <= P.VIRTMEM_SUPPORTED & WriteVal[18];
        mMPRV <= P.U_SUPPORTED & WriteVal[17];
        mFS   <= WriteVal[14:13];
        mMPP  <= MPPNext;
        mSPP  <= P.S_SUPPORTED & WriteVal[8];
        mMPIE <= WriteVal[7];
        mSPIE <= P.S_SUPPORTED & WriteVal[5];
        mMIE  <= WriteVal[3];
        mSIE  <= P.S_SUPPORTED & WriteVal[1];
        mUBE  <= P.U_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[6];
        if (P.XLEN == 64) begin
          mMBE <= P.BIGENDIAN_SUPPORTED & WriteVal[P.XLEN-27];
          mSBE <= P.S_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[P.XLEN-28];
        end
      end else if ((P.XLEN == 32) & WrM & (CSRAdrM == MSTATUSH)) begin
        mMBE  <= P.BIGENDIAN_SUPPORTED & WriteVal[5];
        mSBE  <= P.S_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[4];
      end else if (WrS & (CSRAdrM == SSTATUS)) begin
        mMXR  <= P.S_SUPPORTED & WriteVal[19];
        mSUM  <= P.VIRTMEM_SUPPORTED & WriteVal[18];
        mFS   <= WriteVal[14:13];
        mSPP  <= P.S_SUPPORTED & WriteVal[8];
        mSPIE <= P.S_SUPPORTED & WriteVal[5];
        mSIE  <= P.S_SUPPORTED & WriteVal[1];
        mUBE  <= P.U_SUPPORTED & P.BIGENDIAN_SUPPORTED & WriteVal[6];
      end else if (FSDirtyM) mFS <= 2'b11;
    end

  always_ff @(posedge clk)
    if (reset) begin
      mMEDELEG <= '0; mMIDELEG <= '0;
      mMTVEC <= '0; mMSCRATCH <= '0; mMEPC <= '0; mMCAUSE <= '0; mMTVAL <= '0;
      mSTVEC <= '0; mSSCRATCH <= '0; mSEPC <= '0; mSCAUSE <= '0; mSTVAL <= '0; mSATP <= '0;
    end else if (Resync) begin
      mMEDELEG <= MEDELEG_REGW; mMIDELEG <= MIDELEG_REGW;
      mMTVEC <= MTVEC_REGW; mMSCRATCH <= MSCRATCH_REGW; mMEPC <= MEPC_REGW;
      mMCAUSE <= MCAUSE_REGW; mMTVAL <= MTVAL_REGW;
      mSTVEC <= STVEC_REGW; mSSCRATCH <= SSCRATCH_REGW; mSEPC <= SEPC_REGW;
      mSCAUSE <= SCAUSE_REGW; mSTVAL <= STVAL_REGW; mSATP <= SATP_REGW;
    end else begin
      if (WrM & (CSRAdrM == MEDELEG) & P.S_SUPPORTED) mMEDELEG <= WriteVal[15:0] & MEDELEG_MASK;
      if (WrM & (CSRAdrM == MIDELEG) & P.S_SUPPORTED) mMIDELEG <= WriteVal[11:0] & MIDELEG_MASK;
      if (WrM & (CSRAdrM == MTVEC))                   mMTVEC <= TVECWriteVal;
      if (WrM & (CSRAdrM == MSCRATCH))                mMSCRATCH <= WriteVal;
      if (MTrap | (WrM & (CSRAdrM == MEPC)))          mMEPC <= NextEPC;
      if (MTrap | (WrM & (CSRAdrM == MCAUSE)))        mMCAUSE <= TrapM ? {InterruptM, {(P.XLEN-6){1'b0}}, CauseM}
                                                                      : {WriteVal[P.XLEN-1], {(P.XLEN-6){1'b0}}, WriteVal[4:0]};
      if (MTrap | (WrM & (CSRAdrM == MTVAL)))         mMTVAL <= TrapM ? NextFaultMtvalM : WriteVal;
      if (WrS & (CSRAdrM == STVEC))                   mSTVEC <= TVECWriteVal;
      if (WrS & (CSRAdrM == SSCRATCH))                mSSCRATCH <= WriteVal;
      if (STrap | (WrS & (CSRAdrM == SEPC)))          mSEPC <= NextEPC;
      if (STrap | (WrS & (CSRAdrM == SCAUSE)))        mSCAUSE <= TrapM ? {InterruptM, {(P.XLEN-6){1'b0}}, CauseM}
                                                                      : {WriteVal[P.XLEN-1], {(P.XLEN-6){1'b0}}, WriteVal[4:0]};
      if (STrap | (WrS & (CSRAdrM == STVAL)))         mSTVAL <= TrapM ? NextFaultMtvalM : WriteVal;
      if (WrS & (CSRAdrM == SATP) & P.VIRTMEM_SUPPORTED &
          (mPriv == P.M_MODE | ~vTVM) & LegalSatpMode) mSATP <= WriteVal;
    end

  ///////////////////////////////////////////
  // State check
  ///////////////////////////////////////////

  assign StateFault = (mPriv != PrivilegeModeW) | (mMSTATUS != MSTATUS_REGW) | (mMSTATUSH != MSTATUSH_REGW) |
                      (mMEDELEG != MEDELEG_REGW) | (mMIDELEG != MIDELEG_REGW) |
                      (mMTVEC != MTVEC_REGW) | (mMSCRATCH != MSCRATCH_REGW) | (mMEPC != MEPC_REGW) |
                      (mMCAUSE != MCAUSE_REGW) | (mMTVAL != MTVAL_REGW) |
                      (mSTVEC != STVEC_REGW) | (mSSCRATCH != SSCRATCH_REGW) | (mSEPC != SEPC_REGW) |
                      (mSCAUSE != SCAUSE_REGW) | (mSTVAL != STVAL_REGW) | (mSATP != SATP_REGW);

endmodule
