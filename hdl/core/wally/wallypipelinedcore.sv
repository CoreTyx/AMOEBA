///////////////////////////////////////////
// wallypipelinedcore.sv
//
// Written: David_Harris@hmc.edu 9 January 2021
// Modified:
//
// Purpose: Pipelined RISC-V Processor
//
// Documentation: RISC-V System on Chip Design
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

module wallypipelinedcore import cvw::*; #(parameter cvw_t P) (
   input  logic                  clk, reset,
   // ECC inject enable (from top-level, for DFT)
   input  logic                  ecc_inject_en,
   // Privileged
   input  logic                  MTimerInt, MExtInt, SExtInt, MSwInt,
   input  logic [63:0]           MTIME_CLINT,
   // Bus Interface
   input  logic [P.AHBW-1:0]     HRDATA,
   input  logic                  HREADY, HRESP,
   output logic                  HCLK, HRESETn,
   output logic [P.PA_BITS-1:0]  HADDR,
   output logic [P.AHBW-1:0]     HWDATA,
   output logic [P.XLEN/8-1:0]   HWSTRB,
   output logic                  HWRITE,
   output logic [2:0]            HSIZE,
   output logic [2:0]            HBURST,
   output logic [3:0]            HPROT,
   output logic [1:0]            HTRANS,
   output logic                  HMASTLOCK,
   input  logic                  ExternalStall,
   output logic                  PrivModeUncorrectableFaultW  // TMR uncorrectable privilege mode fault — wire to reset/NMI
);

  logic                          StallF, StallD, StallE, StallM, StallW;
  logic                          FlushD, FlushE, FlushM, FlushW, FlushWCause;
  logic                          TrapM, RetM;

  //  signals that must connect through DP
  logic                          IntDivE, W64E;
  logic                          CSRReadM, CSRWriteM, PrivilegedM;
  logic [1:0]                    AtomicM;
  logic [P.XLEN-1:0]             ForwardedSrcAE, ForwardedSrcBE;
  logic [P.XLEN-1:0]             SrcAM;
  logic [2:0]                    Funct3E;
  logic [31:0]                   InstrD;
  logic [31:0]                   InstrM, InstrOrigM;
  logic [P.XLEN-1:0]             PCSpillF, PCE, PCLinkE;
  logic [P.XLEN-1:0]             PCM, PCSpillM;
  logic [P.XLEN-1:0]             CSRReadValW, MDUResultW;
  logic [P.XLEN-1:0]             EPCM, TrapVectorM;
  logic [1:0]                    MemRWE;
  logic [1:0]                    MemRWM;
  logic                          InstrValidD, InstrValidE, InstrValidM;
  logic                          InstrMisalignedFaultM;
  logic                          IllegalBaseInstrD, IllegalFPUInstrD, IllegalIEUFPUInstrD;
  logic                          InstrPageFaultF, LoadPageFaultM, StoreAmoPageFaultM;
  logic                          LoadMisalignedFaultM, LoadAccessFaultM;
  logic                          StoreAmoMisalignedFaultM, StoreAmoAccessFaultM;
  logic                          InvalidateICacheM, FlushDCacheM;
  logic                          PCSrcE;
  logic                          CSRWriteFenceM;
  logic                          DivBusyE;
  logic                          StructuralStallD;
  logic                          LoadStallD;
  logic                          StoreStallD;
  logic                          SquashSCW;
  logic                          MDUActiveE;                      // Mul/Div instruction being executed
  logic                          ENVCFG_ADUE;                     // HPTW A/D Update enable
  logic                          ENVCFG_PBMTE;                    // Page-based memory type enable
  logic [3:0]                    ENVCFG_CBE;                      // Cache Block operation enables
  logic [3:0]                    CMOpM;                           // 1: cbo.inval; 2: cbo.flush; 4: cbo.clean; 8: cbo.zero
  logic                          IFUPrefetchE, LSUPrefetchM;      // instruction / data prefetch hints
  // AMOEBA random instruction insertion
  logic [31:0]                   RAND_INSTR_INSERT_FREQ_REGW;     // rand_instr_insert_freq CSR
  logic [31:0]                   DummyInstrD;                     // dummy instruction to inject
  logic                          InjectD;                         // inject a dummy this cycle
  logic                          DummySelD;                       // shadow register the dummy writes
  logic                          DummyW;                          // Writeback holds a dummy instruction
  logic                          InsertOkD;                       // pipeline permits an insertion

  // floating point unit signals
  logic [2:0]                    FRM_REGW;
  logic [4:0]                    RdE, RdM, RdW;
  logic                          FPUStallD;
  logic                          FWriteIntE;
  logic [P.FLEN-1:0]             FWriteDataM;
  logic [P.XLEN-1:0]             FIntResM;
  logic [P.XLEN-1:0]             FCvtIntResW;
  logic                          FCvtIntW;
  logic                          FDivBusyE;
  logic                          FRegWriteM;
  logic                          FpLoadStoreM;
  logic [4:0]                    SetFflagsM;
  logic [P.XLEN-1:0]             FIntDivResultW;

  // memory management unit signals
  logic                          ITLBWriteF;
  logic                          ITLBMissOrUpdateAF;
  logic [P.XLEN-1:0]             SATP_REGW;
  logic                          STATUS_MXR, STATUS_SUM, STATUS_MPRV;
  logic [1:0]                    STATUS_MPP, STATUS_FS;
  logic [1:0]                    PrivilegeModeW;
  logic [P.XLEN-1:0]             PTE;
  logic [2:0]                    PageType;
  logic                          sfencevmaM;
  logic                          SelHPTW;

  // PMA checker signals
  /* verilator lint_off UNDRIVEN */ // these signals are undriven in configurations without a privileged unit
  var logic [P.PA_BITS-3:0]      PMPADDR_ARRAY_REGW[P.PMP_ENTRIES-1:0];
  var logic [7:0]                PMPCFG_ARRAY_REGW[P.PMP_ENTRIES-1:0];
  /* verilator lint_on UNDRIVEN */

  // IMem stalls
  logic                          IFUStallF;
  logic                          LSUStallM;

  // cpu lsu interface
  logic [2:0]                    Funct3M;
  logic [P.XLEN-1:0]             IEUAdrE;
  logic [P.XLEN-1:0]             WriteDataM;
  logic [P.XLEN-1:0]             IEUAdrM;
  logic [P.XLEN-1:0]             IEUAdrxTvalM;
  logic [P.LLEN-1:0]             ReadDataW;
  logic                          CommittedM;

  // AHB ifu interface
  logic [P.PA_BITS-1:0]          IFUHADDR;
  logic [2:0]                    IFUHBURST;
  logic [1:0]                    IFUHTRANS;
  logic [2:0]                    IFUHSIZE;
  logic                          IFUHWRITE;
  logic                          IFUHREADY;

  // AHB LSU interface
  logic [P.PA_BITS-1:0]          LSUHADDR;
  logic [P.XLEN-1:0]             LSUHWDATA;
  logic [P.XLEN/8-1:0]           LSUHWSTRB;
  logic                          LSUHWRITE;
  logic                          LSUHREADY;

  logic                          BPWrongE, BPWrongM;
  logic                          BPDirWrongM;
  logic                          BTAWrongM;
  logic                          RASPredPCWrongM;
  logic                          IClassWrongM;
  logic [3:0]                    IClassM;
  logic                          InstrAccessFaultF, HPTWInstrAccessFaultF, HPTWInstrPageFaultF;
  logic [2:0]                    LSUHSIZE;
  logic [2:0]                    LSUHBURST;
  logic [1:0]                    LSUHTRANS;

  logic                          DCacheMiss;
  logic                          DCacheAccess;
  logic                          ICacheMiss;
  logic                          ICacheAccess;
  logic                          BigEndianM;
  logic                          FCvtIntE;
  logic                          CommittedF;
  logic                          BranchD, BranchE, JumpD, JumpE;
  logic                          DCacheStallM, ICacheStallF;
  logic                          wfiM, IntPendingM;
  logic                          RegEccSecErrW, RegEccDedErrW;  // ECC error aggregates from IEU
  logic                          RegEccDedErrPipeW;               // DED from W-stage pipeline reg only
  logic [P.XLEN-1:0]             PCW;                             // W-stage PC (PCM registered)

  // SHARD shadow pipeline signals
  logic              shadow_we3;
  logic [4:0]        shadow_a3;
  logic [P.XLEN-1:0] shadow_wd3;
  logic              shadow_DummyW_sp, shadow_DummySel_sp;
  logic              RQ_HitA, RQ_HitB;
  logic [P.XLEN-1:0] RQ_ValA, RQ_ValB;
  logic [P.XLEN-1:0] SrcAE_s, SrcBE_s, ImmExtE_s;
  logic              SecFaultW_s;
  logic [P.XLEN-1:0] SecFaultPC_W_s;
  logic              VBC_StallE_s;
  // IQ head outputs
  logic [P.XLEN-1:0] iq_sPC;
  logic [31:0]       iq_sInstr32;
  logic              iq_sPCSrc;
  logic [2:0]        iq_sFRM;
  logic              iq_sIsHWCSR, iq_sIsDummy, iq_sDummySel, iq_sInstrValid;
  // OQ head outputs (shadow sE inputs)
  logic [P.XLEN-1:0] oq_SrcAE, oq_SrcBE, oq_FwdBE, oq_PCLinkE, oq_ImmExtE;
  logic              oq_W64E, oq_UW64E, oq_SubArithE;
  logic [2:0]        oq_ALUSelectE;
  logic [3:0]        oq_BSelectE, oq_ZBBSelectE;
  logic [2:0]        oq_BALUControlE;
  logic              oq_BMUActiveE;
  logic [1:0]        oq_CZeroE;
  logic [2:0]        oq_Funct3E;
  logic [6:0]        oq_Funct7E;
  logic [4:0]        oq_Rs2E;
  logic              oq_ALUResultSrcE, oq_JumpE, oq_BranchSignedE;
  logic [1:0]        oq_MemRWE;
  logic [4:0]        oq_RdE;
  logic              oq_RegWriteE, oq_InstrValidE, oq_DummyE, oq_DummySelE;
  logic              CompressedE_s;  // Rev 7: next-PC check (CompressedE from IFU)
  // RQ head outputs (shadow sW inputs)
  logic [4:0]        rq_Rd;
  logic [P.XLEN-1:0] rq_IntResult;
  logic              rq_IntWriteEn;
  logic [P.XLEN-1:0] rq_MemAddr;
  logic [1:0]        rq_MemRW;
  logic              rq_HasStore;
  logic [P.XLEN-1:0] rq_PC;
  logic              rq_SkipVerify, rq_IsFaultedInstr;
  logic              rq_DummyW_rq, rq_DummySelW_rq, rq_InstrValid;
  logic [P.XLEN-1:0] rq_RawLoadWord;
  logic [2:0]        rq_Funct3;
  logic              rq_Compressed, rq_IsCtrlFlow;
  logic              sW_pop;
  // SQ signals
  logic              sM_pop;
  logic [P.PA_BITS-1:0] sSQ_PA;
  logic [P.XLEN-1:0]   sSQ_WriteData;
  logic [P.XLEN/8-1:0] sSQ_ByteMask;
  logic                 sSQ_Valid;
  // Signals exported from ieu for SHARD queues
  logic [P.XLEN-1:0]   ResultW_s;
  logic                RegWriteW_s, DummySelW_s;
  logic                UW64E_s, SubArithE_s;
  logic [2:0]          ALUSelectE_s;
  logic [3:0]          BSelectE_s, ZBBSelectE_s;
  logic [2:0]          BALUControlE_s;
  logic                BMUActiveE_s;
  logic [1:0]          CZeroE_s;
  logic [6:0]          Funct7E_s;
  logic [4:0]          Rs2E_s;
  logic                ALUResultSrcE_s, BranchSignedE_s;
  logic                RegWriteE_s;
  logic [4:0]          Rs1D_s, Rs2D_s;
  logic [4:0]          Rs1E_rq;     // Rs1D_s piped one stage: correct timing for RQ E-stage scan
  // SHARD: D-cache re-read interface
  logic              shadow_dcache_req_s;
  logic [P.PA_BITS-1:0] shadow_dcache_pa_s;
  logic [P.XLEN-1:0]  shadow_dcache_data_s;
  logic              shadow_dcache_stall_s;
  logic              ShadowDCacheStallM_s;
  logic [P.PA_BITS-1:0] PAdrM_s;
  logic              ShadowVerifyConflictStallM_s;
  // Signals computed in wallypipelinedcore for SHARD push
  logic [1:0]          MemRWW;
  logic                InstrValidW;
  logic                DummyE_s, DummySelE_s;
  // SHARD fault signal threaded to privileged/csr
  logic                ShadowFaultW;
  logic                          EccDedFaultM, EccDedTrapTakenM; // registered DED trap record and acknowledgement
  logic [P.XLEN-1:0]             EccDedFaultEPCM, EccDedFaultMtvalM;
  logic                          RegEccDedErrSticky;              // latched DED fault — cleared only by reset
  logic                          PrivModeUncorrectableFaultW_priv; // from privileged unit before ECC OR

  // instruction fetch unit: PC, branch prediction, instruction cache
  ifu #(P) ifu(.clk, .reset,
    .StallF, .StallD, .StallE, .StallM, .StallW, .FlushD, .FlushE, .FlushM, .FlushW,
    .CompressedE(CompressedE_s),
    .InstrValidE, .InstrValidD,
    .BranchD, .BranchE, .JumpD, .JumpE, .ICacheStallF, .InjectD,
    // Fetch
    .HRDATA, .PCSpillF, .IFUHADDR,
    .IFUStallF, .IFUHBURST, .IFUHTRANS, .IFUHSIZE, .IFUHREADY, .IFUHWRITE,
    .ICacheAccess, .ICacheMiss,
    // Execute
    .PCLinkE, .PCSrcE, .IEUAdrE, .IEUAdrM, .PCE, .BPWrongE,  .BPWrongM,
    // Mem
    .CommittedF, .EPCM, .TrapVectorM, .RetM, .TrapM, .InvalidateICacheM, .CSRWriteFenceM,
    .InstrD, .InstrM, .InstrOrigM, .PCM, .PCSpillM, .IClassM, .BPDirWrongM,
    .BTAWrongM, .RASPredPCWrongM, .IClassWrongM,
    // Faults out
    .IllegalBaseInstrD, .IllegalFPUInstrD, .InstrPageFaultF, .IllegalIEUFPUInstrD, .InstrMisalignedFaultM,
    // mmu management
    .PrivilegeModeW, .PTE, .PageType, .SATP_REGW, .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV,
    .STATUS_MPP, .ENVCFG_PBMTE, .ENVCFG_ADUE, .ITLBWriteF, .sfencevmaM, .ITLBMissOrUpdateAF,
    // pmp/pma (inside mmu) signals.
    .PMPCFG_ARRAY_REGW,  .PMPADDR_ARRAY_REGW, .InstrAccessFaultF);

  // integer execution unit: integer register file, datapath and controller
  ieu #(P) ieu(.clk, .reset,
     .ecc_inject_en, .RegEccSecErrW, .RegEccDedErrW, .RegEccDedErrPipeW,
     // Decode Stage interface
     .InstrD, .STATUS_FS, .ENVCFG_CBE, .IllegalIEUFPUInstrD, .IllegalBaseInstrD,
     // Execute Stage interface
     .PCE, .PCLinkE, .FWriteIntE, .FCvtIntE, .IEUAdrE, .IntDivE, .W64E,
     .Funct3E, .ForwardedSrcAE, .ForwardedSrcBE, .MDUActiveE, .CMOpM, .IFUPrefetchE, .LSUPrefetchM,
     // Memory stage interface
     .SquashSCW,  // from LSU
     .MemRWE,     // read/write control goes to LSU
     .MemRWM,     // read/write control goes to LSU
     .AtomicM,    // atomic control goes to LSU
     .WriteDataM, // Write data to LSU
     .Funct3M,    // size and signedness to LSU
     .SrcAM,      // to privilege and fpu
     .RdE, .RdM, .FIntResM, .FlushDCacheM,
     .BranchD, .BranchE, .JumpD, .JumpE,
     // Writeback stage
     .CSRReadValW, .MDUResultW, .FIntDivResultW, .RdW, .ReadDataW(ReadDataW[P.XLEN-1:0]),
     .InstrValidM, .InstrValidE, .InstrValidD, .FCvtIntResW, .FCvtIntW,
     // hazards
     .StallD, .StallE, .StallM, .StallW, .FlushD, .FlushE, .FlushM, .FlushW,
     .StructuralStallD, .LoadStallD, .StoreStallD, .PCSrcE,
     .CSRReadM, .CSRWriteM, .PrivilegedM, .CSRWriteFenceM, .InvalidateICacheM,
     // random instruction insertion
     .InjectD, .DummyInstrD, .DummySelD, .DummyW,
     // SHARD: shadow write port inputs (from shadow_pipeline)
     .shadow_we3, .shadow_a3, .shadow_wd3,
     .shadow_DummyW(shadow_DummyW_sp), .shadow_DummySel(shadow_DummySel_sp),
     // SHARD: RQ associative forwarding inputs (with conflict-stall hold applied)
     .RQ_HitA(final_hitA), .RQ_ValA(final_valA), .RQ_HitB(final_hitB), .RQ_ValB(final_valB),
     // SHARD: OQ push operands
     .SrcAE_out(SrcAE_s), .SrcBE_out(SrcBE_s), .ImmExtE_out(ImmExtE_s),
     .UW64E_out(UW64E_s), .SubArithE_out(SubArithE_s), .ALUSelectE_out(ALUSelectE_s),
     .BSelectE_out(BSelectE_s), .ZBBSelectE_out(ZBBSelectE_s), .BALUControlE_out(BALUControlE_s),
     .BMUActiveE_out(BMUActiveE_s), .CZeroE_out(CZeroE_s), .Funct7E_out(Funct7E_s),
     .Rs2E_out(Rs2E_s), .ALUResultSrcE_out(ALUResultSrcE_s), .BranchSignedE_out(BranchSignedE_s),
     .RegWriteE_out(RegWriteE_s),
     // SHARD: RQ push signals
     .RegWriteW_out(RegWriteW_s), .DummySelW_out(DummySelW_s), .ResultW_out(ResultW_s),
     // SHARD: RQ forwarding scan D-stage source registers
     .Rs1D_out(Rs1D_s), .Rs2D_out(Rs2D_s));

  ///////////////////////////////////////////
  // AMOEBA: random instruction insertion
  ///////////////////////////////////////////
  // An insertion is blocked whenever Execute cannot accept a new instruction this cycle
  // (a divide occupying Execute, or a stall originating in Memory/Writeback) or the
  // pipeline is about to be flushed anyway.  All of these are Memory/Execute stage
  // signals that do not depend on the decode-stage instruction, so qualifying the
  // strobe with them cannot form a combinational loop through the injection mux.
  // Structural stalls in Decode are deliberately *not* excluded: injecting into a
  // bubble that would have been inserted anyway costs no performance.
  assign InsertOkD = ~DivBusyE & ~FDivBusyE & ~StallM & ~RetM & ~CSRWriteFenceM;

  dummygen dummygen(.clk, .reset,
    .FreqW(RAND_INSTR_INSERT_FREQ_REGW),
    .InstrD, .InstrValidD, .InsertOkD,
    .InjectD, .DummyInstrD, .DummySelD);

  lsu #(P) lsu(
    .clk, .reset, .StallM, .FlushM, .StallW, .FlushW,
    // CPU interface
    .MemRWE, .MemRWM(MemRWM_lsu), .Funct3M, .Funct7M(InstrM[31:25]), .AtomicM,
    .CommittedM, .DCacheMiss, .DCacheAccess, .SquashSCW,
    .FpLoadStoreM, .FWriteDataM, .IEUAdrE, .IEUAdrM, .WriteDataM,
    .ReadDataW, .FlushDCacheM, .CMOpM, .LSUPrefetchM,
    // connected to ahb (all stay the same)
    .LSUHADDR,  .HRDATA, .LSUHWDATA, .LSUHWSTRB, .LSUHSIZE,
    .LSUHBURST, .LSUHTRANS, .LSUHWRITE, .LSUHREADY,
    // connect to csr or privilege and stay the same.
    .PrivilegeModeW, .BigEndianM, // connects to csr
    .PMPCFG_ARRAY_REGW,           // connects to csr
    .PMPADDR_ARRAY_REGW,          // connects to csr
    // hptw keep i/o
    .SATP_REGW,                   // from csr
    .STATUS_MXR,                  // from csr
    .STATUS_SUM,                  // from csr
    .STATUS_MPRV,                 // from csr
    .STATUS_MPP,                  // from csr
    .ENVCFG_PBMTE,                // from csr
    .ENVCFG_ADUE,                 // from csr
    .sfencevmaM,                  // connects to privilege
    .DCacheStallM,                // connects to privilege
    .IEUAdrxTvalM,                // connects to privilege
    .LoadPageFaultM,              // connects to privilege
    .StoreAmoPageFaultM,          // connects to privilege
    .LoadMisalignedFaultM,        // connects to privilege
    .LoadAccessFaultM,            // connects to privilege
    .HPTWInstrAccessFaultF,       // connects to privilege
    .HPTWInstrPageFaultF,         // connects to privilege
    .StoreAmoMisalignedFaultM,    // connects to privilege
    .StoreAmoAccessFaultM,        // connects to privilege
    .PCSpillF, .ITLBMissOrUpdateAF, .PTE, .PageType, .ITLBWriteF, .SelHPTW,
    .LSUStallM,
    // SHARD shadow D-cache re-read interface
    .PAdrM_out(PAdrM_s),
    .RawReadDataWordM(RawReadDataWordM_s),
    .AMOFaultM(AMOFaultM_s),
    .shadow_dcache_req(shadow_dcache_req_s),
    .shadow_dcache_pa(shadow_dcache_pa_s),
    .shadow_dcache_data(shadow_dcache_data_s),
    .shadow_dcache_stall(shadow_dcache_stall_s));

  if (P.BUS_SUPPORTED) begin : ebu
    ebu #(P) ebu(// IFU connections
      .clk, .reset,
      // IFU interface
      .IFUHADDR, .IFUHBURST, .IFUHTRANS, .IFUHREADY, .IFUHSIZE,
      // LSU interface
      .LSUHADDR, .LSUHWDATA, .LSUHWSTRB, .LSUHSIZE, .LSUHBURST,
      .LSUHTRANS, .LSUHWRITE, .LSUHREADY,
      // BUS interface
      .HREADY, .HRESP, .HCLK, .HRESETn,
      .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HBURST,
      .HPROT, .HTRANS, .HMASTLOCK);
  end else begin
    assign {IFUHREADY, LSUHREADY, HCLK, HRESETn, HADDR, HWDATA,
            HWSTRB, HWRITE, HSIZE, HBURST, HPROT, HTRANS, HMASTLOCK} = '0;
  end

  // ShadowVerifyConflictStallM: stall main at M when shadow needs D-cache read and
  // main simultaneously has a store to the same 8-byte word (would dirty the line).
  assign ShadowVerifyConflictStallM_s = ShadowDCacheStallM_s
    & MemRWM[0]
    & (PAdrM_s[P.PA_BITS-1:3] == shadow_dcache_pa_s[P.PA_BITS-1:3]);

  // global stall and flush control
  hazard hzu(
    .BPWrongE, .CSRWriteFenceM, .RetM, .TrapM,
    .StructuralStallD,
    .LSUStallM, .IFUStallF,
    .FPUStallD, .ExternalStall,
    .DivBusyE, .FDivBusyE,
    .ShadowDCacheStallM(ShadowDCacheStallM_s),
    .ShadowVerifyConflictStallM(ShadowVerifyConflictStallM_s),
    .wfiM, .IntPendingM, .InjectD,
    // Stall & flush outputs
    .StallF, .StallD, .StallE, .StallM, .StallW,
    .FlushD, .FlushE, .FlushM, .FlushW, .FlushWCause);

  // privileged unit
  if (P.ZICSR_SUPPORTED) begin : priv
    privileged #(P) priv(
      .clk, .reset,
      .FlushD, .FlushE, .FlushM, .FlushW, .StallD, .StallE, .StallM, .StallW,
      .CSRReadM, .CSRWriteM, .SrcAM, .PCM, .PCSpillM,
      .InstrM, .InstrOrigM, .CSRReadValW, .EPCM, .TrapVectorM,
      .RetM, .TrapM, .sfencevmaM, .InvalidateICacheM, .DCacheStallM, .ICacheStallF,
      .InstrValidM, .CommittedM, .CommittedF,
      .FRegWriteM, .LoadStallD, .StoreStallD,
      .BPDirWrongM, .BTAWrongM, .BPWrongM,
      .RASPredPCWrongM, .IClassWrongM, .DivBusyE, .FDivBusyE,
      .IClassM, .DCacheMiss, .DCacheAccess, .ICacheMiss, .ICacheAccess, .PrivilegedM,
      .InstrPageFaultF, .LoadPageFaultM, .StoreAmoPageFaultM,
      .InstrMisalignedFaultM, .IllegalIEUFPUInstrD,
      .LoadMisalignedFaultM, .StoreAmoMisalignedFaultM,
      .MTimerInt, .MExtInt, .SExtInt, .MSwInt,
      .MTIME_CLINT, .IEUAdrxTvalM, .SetFflagsM,
      .InstrAccessFaultF, .HPTWInstrAccessFaultF, .HPTWInstrPageFaultF, .LoadAccessFaultM, .StoreAmoAccessFaultM, .SelHPTW,
      .PrivilegeModeW, .SATP_REGW,
      .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP, .STATUS_FS,
      .PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW,
      .FRM_REGW, .ENVCFG_CBE, .ENVCFG_PBMTE, .ENVCFG_ADUE, .wfiM, .IntPendingM, .BigEndianM,
      .CSRFaultM(CSRFaultM_s),
      .RAND_INSTR_INSERT_FREQ_REGW,
      .RegEccSecErrW, .RegEccDedErrW, .ShadowFaultW,
      .EccDedFaultM, .EccDedFaultEPCM, .EccDedFaultMtvalM, .EccDedTrapTakenM,
      .PrivModeUncorrectableFaultW(PrivModeUncorrectableFaultW_priv));
  end else begin
    assign {CSRReadValW, PrivilegeModeW,
            SATP_REGW, STATUS_MXR, STATUS_SUM, STATUS_MPRV, STATUS_MPP, STATUS_FS, FRM_REGW,
            // PMPCFG_ARRAY_REGW, PMPADDR_ARRAY_REGW,
            ENVCFG_CBE, ENVCFG_PBMTE, ENVCFG_ADUE,
            EPCM, TrapVectorM, RetM, TrapM,
            sfencevmaM, BigEndianM, wfiM, IntPendingM, EccDedTrapTakenM, PrivModeUncorrectableFaultW_priv} = '0;
    // Without a CSR to program it, dummy instruction insertion stays disabled.
    assign RAND_INSTR_INSERT_FREQ_REGW = '0;
    assign CSRFaultM_s = 1'b0;
  end

  // W-stage PC: used as MEPC when the DED error comes from the W-stage pipeline register
  flopenrc #(P.XLEN) PCWReg(clk, reset, FlushW, ~StallW, PCM, PCW);

  // SHARD: W-stage pipeline registers for RQ push
  flopenrc #(2) MemRWWReg      (clk, reset, FlushW, ~StallW, MemRWM, MemRWW);
  flopenrc #(1) InstrValidWReg (clk, reset, FlushW, ~StallW, InstrValidM, InstrValidW);
  // Rev 6: pipe the effective address to W for shadow EA verification of loads/stores
  logic [P.XLEN-1:0] IEUAdrW;
  flopenrc #(P.XLEN) IEUAdrWReg (clk, reset, FlushW, ~StallW, IEUAdrM, IEUAdrW);
  // Rev 6: pipe the raw load word and funct3 to W for shadow load-data re-derivation
  logic [P.XLEN-1:0] RawReadDataWordM_s, RawLoadWordW;
  logic [2:0]        Funct3W;
  flopenrc #(P.XLEN) RawLoadWordWReg (clk, reset, FlushW, ~StallW, RawReadDataWordM_s, RawLoadWordW);
  flopenrc #(3)      Funct3WReg      (clk, reset, FlushW, ~StallW, Funct3M, Funct3W);
  // Rev 7: pipe AMO verification fault (computed at M in the LSU) to W
  logic AMOFaultM_s, AMOFaultW;
  flopenrc #(1)      AMOFaultWReg    (clk, reset, FlushW, ~StallW, AMOFaultM_s, AMOFaultW);
  // Rev 7: pipe CSR verification fault (computed at M in csr.sv, already gated to a
  // committing CSR write) to W
  logic CSRFaultM_s, CSRFaultW;
  flopenrc #(1)      CSRFaultWReg    (clk, reset, FlushW, ~StallW, CSRFaultM_s, CSRFaultW);
  // Rev 7: carry the compressed flag and a control-flow class bit to W for the RQ-based
  // next-PC continuity check.  CompressedE (from IFU) is piped E->M->W; the control-flow
  // class is decoded from the M-stage opcode and piped to W.
  logic CompressedM_s, CompressedW;
  logic IsCtrlFlowM, IsCtrlFlowW;
  flopenrc #(1) CompressedMReg (clk, reset, FlushM, ~StallM, CompressedE_s, CompressedM_s);
  flopenrc #(1) CompressedWReg (clk, reset, FlushW, ~StallW, CompressedM_s, CompressedW);
  assign IsCtrlFlowM = (InstrM[6:0] == 7'b1100011)   // branch
                     | (InstrM[6:0] == 7'b1101111)   // jal
                     | (InstrM[6:0] == 7'b1100111)   // jalr
                     | (InstrM[6:0] == 7'b1110011)   // system (ecall/ebreak/csr/mret/wfi)
                     | (InstrM[6:0] == 7'b0001111);  // fence / fence.i
  flopenrc #(1) IsCtrlFlowWReg (clk, reset, FlushW, ~StallW, IsCtrlFlowM, IsCtrlFlowW);

  // Rev 7: gated / deferred store commit (prevention).  An independent adder recomputes
  // the store effective address (SrcAE+SrcBE, the AGU sum) at Execute and it is checked
  // against the main AGU output IEUAdrE at the commit point.  On a mismatch (a transient
  // fault in one adder) a fault is raised into MSECFAULT, and — when GATE_STORE_ON_SECFAULT
  // is enabled — the store's write bit into the LSU is cleared so a mis-addressed store
  // cannot corrupt memory.  In fault-free operation the two adders always agree, so this
  // never false-fires and the default behavior is byte-identical (regressions unchanged).
  // This is the microarchitecture-appropriate realization of the review's "deferred store
  // commit" (verify-before-commit) without a full DIVA store buffer / shadow decoupling.
  localparam logic GATE_STORE_ON_SECFAULT = 1'b0;   // 0 = detect+log (safe default); 1 = prevent (suppress write)
  logic              StoreEAFaultE, StoreEAFaultM, StoreEAFaultW;
  logic [P.XLEN-1:0] IndepStoreEA_E;
  logic [1:0]        MemRWM_lsu;
  assign IndepStoreEA_E = SrcAE_s + SrcBE_s;        // independent copy of the AGU adder
  assign StoreEAFaultE  = MemRWE[0] & InstrValidE & (IndepStoreEA_E != IEUAdrE);
  flopenrc #(1) StoreEAFaultMReg (clk, reset, FlushM, ~StallM, StoreEAFaultE, StoreEAFaultM);
  flopenrc #(1) StoreEAFaultWReg (clk, reset, FlushW, ~StallW, StoreEAFaultM, StoreEAFaultW);
  assign MemRWM_lsu = (GATE_STORE_ON_SECFAULT & StoreEAFaultM) ? {MemRWM[1], 1'b0} : MemRWM;

  // SHARD: E-stage dummy flags and Rs1 for RQ scan (pipelined from D-stage)
  flopenrc #(1) DummyEReg      (clk, reset, FlushE, ~StallE, InjectD, DummyE_s);
  flopenrc #(1) DummySelEReg   (clk, reset, FlushE, ~StallE, DummySelD, DummySelE_s);
  flopenrc #(5) Rs1E_rq_reg    (clk, reset, FlushE, ~StallE, Rs1D_s, Rs1E_rq);

  // Assign shadow fault signal for privileged/csr threading
  // Rev 7: fold the AMO verification fault (gated by W-stage validity) into the shadow
  // MSECFAULT alongside the sW verifier output.
  assign ShadowFaultW = SecFaultW_s | (AMOFaultW & InstrValidW) | CSRFaultW
                      | (StoreEAFaultW & InstrValidW);

  ///////////////////////////////////////////////////////////////////////////
  // SHARD — Shadow Hardware Audit Redundancy Design
  ///////////////////////////////////////////////////////////////////////////

  // IQ: N-deep shift register pushed at D-stage
  shadow_iq #(.P(P), .N(3)) siq(
    .clk, .reset,
    .StallD, .FlushD,
    .PCF(PCSpillF),
    .InstrD,
    .PCSrcD(PCSrcE),
    .FRM_D(FRM_REGW[2:0]),
    .IsHWCSR_D(1'b0),
    .IsDummyD(InjectD),
    .DummySelD,
    .InstrValidD,
    .sPC(iq_sPC), .sInstr32(iq_sInstr32), .sPCSrc(iq_sPCSrc),
    .sFRM_snap(iq_sFRM), .sIsHWCSR(iq_sIsHWCSR),
    .sIsDummy(iq_sIsDummy), .sDummySel(iq_sDummySel), .sInstrValid(iq_sInstrValid));

  // OQ: N-deep shift register pushed at E→M boundary
  shadow_oq #(.P(P), .N(3)) soq(
    .clk, .reset,
    .StallM, .FlushE, .FlushM,
    .SrcAE(SrcAE_s), .SrcBE(SrcBE_s), .ForwardedSrcBE, .PCLinkE, .ImmExtE(ImmExtE_s),
    .W64E, .UW64E(UW64E_s), .SubArithE(SubArithE_s),
    .ALUSelectE(ALUSelectE_s), .BSelectE(BSelectE_s), .ZBBSelectE(ZBBSelectE_s),
    .BALUControlE(BALUControlE_s), .BMUActiveE(BMUActiveE_s), .CZeroE(CZeroE_s),
    .Funct3E, .Funct7E(Funct7E_s), .Rs2E(Rs2E_s),
    .ALUResultSrcE(ALUResultSrcE_s), .JumpE, .BranchSignedE(BranchSignedE_s),
    .MemRWE, .RdE,
    .RegWriteE(RegWriteE_s), .InstrValidE, .DummyE(DummyE_s), .DummySelE(DummySelE_s),
    .s_SrcAE(oq_SrcAE), .s_SrcBE(oq_SrcBE), .s_ForwardedSrcBE(oq_FwdBE),
    .s_PCLinkE(oq_PCLinkE), .s_ImmExtE(oq_ImmExtE),
    .s_W64E(oq_W64E), .s_UW64E(oq_UW64E), .s_SubArithE(oq_SubArithE),
    .s_ALUSelectE(oq_ALUSelectE), .s_BSelectE(oq_BSelectE), .s_ZBBSelectE(oq_ZBBSelectE),
    .s_BALUControlE(oq_BALUControlE), .s_BMUActiveE(oq_BMUActiveE), .s_CZeroE(oq_CZeroE),
    .s_Funct3E(oq_Funct3E), .s_Funct7E(oq_Funct7E), .s_Rs2E(oq_Rs2E),
    .s_ALUResultSrcE(oq_ALUResultSrcE), .s_JumpE(oq_JumpE), .s_BranchSignedE(oq_BranchSignedE),
    .s_MemRWE(oq_MemRWE), .s_RdE(oq_RdE),
    .s_RegWriteE(oq_RegWriteE), .s_InstrValidE(oq_InstrValidE),
    .s_DummyE(oq_DummyE), .s_DummySelE(oq_DummySelE));

  // RQ: N-deep shift register pushed at W-stage; provides associative forwarding to main D-stage
  shadow_rq #(.P(P), .N(3)) srq(
    .clk, .reset,
    .StallW, .FlushW, .FlushWCause,
    .RdW, .ResultW(ResultW_s), .RegWriteW(RegWriteW_s), .PCW,
    .MemRWW, .MemAddrW(IEUAdrW), .HasStoreW(1'b0), .SkipVerifyW(1'b0), .IsFaultedInstrW(1'b0),
    .DummyW, .DummySelW(DummySelW_s), .RawLoadWordW(RawLoadWordW), .Funct3W(Funct3W),
    .CompressedW(CompressedW), .IsCtrlFlowW(IsCtrlFlowW), .InstrValidW,
    .sW_pop,
    .Rs1D(Rs1E_rq), .Rs2D(Rs2E_s),   // E-stage regs: Rs1 piped from D, Rs2 exported from ieu
    .RQ_ValA, .RQ_ValB, .RQ_HitA, .RQ_HitB,
    .sRQ_Rd(rq_Rd), .sRQ_IntResult(rq_IntResult), .sRQ_IntWriteEn(rq_IntWriteEn),
    .sRQ_MemAddr(rq_MemAddr), .sRQ_MemRW(rq_MemRW), .sRQ_HasStore(rq_HasStore),
    .sRQ_PC(rq_PC), .sRQ_SkipVerify(rq_SkipVerify), .sRQ_IsFaultedInstr(rq_IsFaultedInstr),
    .sRQ_DummyW(rq_DummyW_rq), .sRQ_DummySelW(rq_DummySelW_rq),
    .sRQ_RawLoadWord(rq_RawLoadWord), .sRQ_Funct3(rq_Funct3),
    .sRQ_Compressed(rq_Compressed), .sRQ_IsCtrlFlow(rq_IsCtrlFlow), .sRQ_InstrValid(rq_InstrValid));

  // Conflict-stall forwarding hold: when StallE fires with StallW=0, the
  // RQ keeps shifting (evicting the entry the stalled E-stage needs for forwarding).
  // Capture the RQ hit/value on the first stall posedge, hold through all stall cycles,
  // and persist one extra cycle so WriteDataM captures the correct value as E→M advances.
  logic       cstall_hitA, cstall_hitB;
  logic [P.XLEN-1:0] cstall_valA, cstall_valB;
  logic       cstall_valid;
  logic       StallE_r;
  wire        cstall_trigger = StallE & ~StallW;

  always_ff @(posedge clk) begin
    StallE_r <= StallE;
    if (reset | ~StallE) begin
      cstall_valid <= 1'b0;
    end else if (StallE & ~StallW & ~cstall_valid) begin
      cstall_hitA  <= RQ_HitA;
      cstall_hitB  <= RQ_HitB;
      cstall_valA  <= RQ_ValA;
      cstall_valB  <= RQ_ValB;
      cstall_valid <= 1'b1;
    end
  end

  // Apply held forwarding: during the active stall OR for one extra cycle after it ends
  wire cstall_active = cstall_valid & (cstall_trigger | (StallE_r & ~StallE));
  wire final_hitA = cstall_active ? cstall_hitA : RQ_HitA;
  wire [P.XLEN-1:0] final_valA = (cstall_active & cstall_hitA) ? cstall_valA : RQ_ValA;
  wire final_hitB = cstall_active ? cstall_hitB : RQ_HitB;
  wire [P.XLEN-1:0] final_valB = (cstall_active & cstall_hitB) ? cstall_valB : RQ_ValB;

  // SQ: N-deep FIFO pushed at M-stage for stores
  shadow_sq #(.P(P), .N(3)) ssq(
    .clk, .reset,
    .StallM, .FlushM,
    .PAdrM(PAdrM_s),
    .WriteDataM, .ByteMaskM({(P.XLEN/8){1'b1}}),
    .StoreM(MemRWM[0]),
    .sM_pop,
    .sSQ_PA, .sSQ_WriteData, .sSQ_ByteMask, .sSQ_Valid);

  // Shadow pipeline: sD→sE→sM→sW
  shadow_pipeline #(.P(P), .N(3)) spipe(
    .clk, .reset,
    .StallD, .StallE, .StallM, .StallW,
    .FlushD, .FlushE, .FlushM, .FlushW,
    // IQ head → sD
    .sPC_in(iq_sPC), .sInstr32_in(iq_sInstr32), .sPCSrc_in(iq_sPCSrc),
    .sFRM_snap_in(iq_sFRM), .sIsHWCSR_in(iq_sIsHWCSR),
    .sIsDummy_in(iq_sIsDummy), .sDummySel_in(iq_sDummySel), .sInstrValid_in(iq_sInstrValid),
    // OQ head → sE
    .oq_SrcAE, .oq_SrcBE, .oq_ForwardedSrcBE(oq_FwdBE), .oq_PCLinkE, .oq_ImmExtE,
    .oq_W64E, .oq_UW64E, .oq_SubArithE,
    .oq_ALUSelectE, .oq_BSelectE, .oq_ZBBSelectE, .oq_BALUControlE,
    .oq_BMUActiveE, .oq_CZeroE, .oq_Funct3E, .oq_Funct7E, .oq_Rs2E,
    .oq_ALUResultSrcE, .oq_JumpE, .oq_BranchSignedE,
    .oq_MemRWE, .oq_RdE, .oq_RegWriteE, .oq_InstrValidE, .oq_DummyE, .oq_DummySelE,
    // RQ head → sW
    .rq_Rd, .rq_IntResult, .rq_IntWriteEn, .rq_MemAddr, .rq_MemRW, .rq_HasStore,
    .rq_PC, .rq_SkipVerify, .rq_IsFaultedInstr,
    .rq_DummyW(rq_DummyW_rq), .rq_DummySelW(rq_DummySelW_rq), .rq_InstrValid,
    .rq_RawLoadWord(rq_RawLoadWord), .rq_Funct3(rq_Funct3),
    .rq_Compressed(rq_Compressed), .rq_IsCtrlFlow(rq_IsCtrlFlow),
    // RQ pop
    .sW_pop,
    // SQ head → sM
    .sq_PA(sSQ_PA), .sq_WriteData(sSQ_WriteData), .sq_ByteMask(sSQ_ByteMask), .sq_Valid(sSQ_Valid),
    // SQ pop
    .sM_pop,
    // SHARD D-cache re-read interface
    .shadow_dcache_req(shadow_dcache_req_s),
    .shadow_dcache_pa(shadow_dcache_pa_s),
    .shadow_dcache_data(shadow_dcache_data_s),
    .shadow_dcache_stall(shadow_dcache_stall_s),
    .ShadowDCacheStallM(ShadowDCacheStallM_s),
    // Shadow regfile write port
    .shadow_we3, .shadow_a3, .shadow_wd3, .shadow_DummyW(shadow_DummyW_sp), .shadow_DummySel(shadow_DummySel_sp),
    // Fault reporting
    .SecFaultW(SecFaultW_s), .SecFaultPC_W(SecFaultPC_W_s),
    // VBC (stubbed)
    .VBC_StallE(VBC_StallE_s),
    // Debug outputs
    .sRdE_out(), .sRdM_out());

  // Capture an uncorrectable ECC error before presenting it to trap logic.  This
  // breaks the combinational DED -> TrapM -> flush/bus -> DED feedback path.
  // The existing PC attribution rule is preserved: an IFResultW error uses PCW;
  // all other aggregated errors use the current memory-stage PC.
  always_ff @(posedge clk) begin
    if (reset) begin
      EccDedFaultM      <= 1'b0;
      EccDedFaultEPCM   <= '0;
      EccDedFaultMtvalM <= '0;
    end else if (EccDedTrapTakenM) begin
      EccDedFaultM <= 1'b0;
    end else if (!EccDedFaultM && RegEccDedErrW) begin
      EccDedFaultM      <= 1'b1;
      EccDedFaultEPCM   <= RegEccDedErrPipeW ? PCW : PCM;
      EccDedFaultMtvalM <= (|MemRWM) ? IEUAdrxTvalM : '0;
    end
  end

  // DED fault is sticky: once a double-bit error is seen it holds until reset
  always_ff @(posedge clk)
    if (reset) RegEccDedErrSticky <= 1'b0;
    else       RegEccDedErrSticky <= RegEccDedErrSticky | RegEccDedErrW;

  // Combine privilege-mode TMR fault with sticky IEU ECC uncorrectable (DED) fault
  assign PrivModeUncorrectableFaultW = PrivModeUncorrectableFaultW_priv | RegEccDedErrSticky;

  // multiply/divide unit
  if (P.ZMMUL_SUPPORTED) begin : mdu
    mdu #(P) mdu(.clk, .reset, .StallM, .StallW, .FlushE, .FlushM, .FlushW,
      .ForwardedSrcAE, .ForwardedSrcBE,
      .Funct3E, .Funct3M, .IntDivE, .W64E, .MDUActiveE,
      .MDUResultW, .DivBusyE);
  end else begin // no M instructions supported
    assign MDUResultW = '0;
    assign DivBusyE   = 1'b0;
  end

  // floating point unit
  if (P.F_SUPPORTED) begin : fpu
    fpu #(P) fpu(
      .clk, .reset,
      .FRM_REGW,                           // Rounding mode from CSR
      .InstrD,                             // instruction from IFU
      .ReadDataW(ReadDataW[P.FLEN-1:0]),   // Read data from memory
      .ForwardedSrcAE,                     // Integer input being processed (from IEU)
      .StallE, .StallM, .StallW,           // stall signals from HZU
      .FlushE, .FlushM, .FlushW,           // flush signals from HZU
      .RdE, .RdM, .RdW,                    // which FP register to write to (from IEU)
      .STATUS_FS,                          // is floating-point enabled?
      .FRegWriteM,                         // FP register write enable
      .FpLoadStoreM,
      .ForwardedSrcBE,                     // Integer input for intdiv
      .Funct3E, .Funct3M, .IntDivE, .W64E, // Integer flags and functions
      .FPUStallD,                          // Stall the decode stage
      .FWriteIntE, .FCvtIntE,              // integer register write enable, conversion operation
      .FWriteDataM,                        // Data to be written to memory
      .FIntResM,                           // data to be written to integer register
      .FCvtIntResW,                        // fp -> int conversion result to be stored in int register
      .FCvtIntW,                           // fpu result selection
      .FDivBusyE,                          // Is the divide/sqrt unit busy (stall execute stage)
      .IllegalFPUInstrD,                   // Is the instruction an illegal fpu instruction
      .SetFflagsM,                         // FPU flags (to privileged unit)
      .FIntDivResultW);
  end else begin                           // no F_SUPPORTED or D_SUPPORTED; tie outputs low
    assign {FPUStallD, FWriteIntE, FCvtIntE, FIntResM, FCvtIntW, FRegWriteM,
            IllegalFPUInstrD, SetFflagsM, FpLoadStoreM,
            FWriteDataM, FCvtIntResW, FIntDivResultW, FDivBusyE} = '0;
  end

endmodule
