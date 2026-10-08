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
  logic                          FlushD, FlushE, FlushM, FlushW;
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

  // SHARD
  localparam int SHARD_DEPTH = 8;                            // IQ/OQ/RQ/SQ depth
  localparam int SHARD_CW    = $clog2(SHARD_DEPTH+1);
  // main pipeline values recorded for the shadow
  logic [4:0]          Rs1E, Rs2E;
  logic [P.XLEN-1:0]   SrcAE, SrcBE;
  logic [P.XLEN-1:0]   ForwardedSrcAM;
  logic [27:0]         ShardCtlM;
  logic                PCSrcM, RegWriteM, FWriteIntM;
  logic [2:0]          ResultSrcM;
  logic [P.XLEN-1:0]   ResultW_s;
  logic                RegWriteW_s;
  logic                CompressedE, CompressedM;
  logic                InstrValidW;
  logic [P.XLEN-1:0]   RawReadDataWordM;
  // retirement into the queues
  logic                MExitM;                               // instruction leaves Memory unflushed: it will retire
  logic                ShardPushOK;                          // no recovery in progress
  logic                QPushM;                               // IQ/OQ (and SQ) push
  logic                RQPushW, WPushed;                     // RQ push, once per Writeback-stage instruction
  logic [SHARD_CW:0]   InFlight;                             // retired instructions not yet committed by the shadow
  logic                ShadowIdleM;
  logic                ShardBackpressureW;
  logic [4:0]          RegA4, RegA5;                         // regfile read ports 4/5: the shadow's, or the Memory-stage check's
  // IQ / OQ heads
  logic                iqValid, iqPop, oqPop;
  logic [P.XLEN-1:0]   iqPC;
  logic [31:0]         iqInstr;
  logic                iqCompressed;
  logic [P.XLEN-1:0]   oqForwardedSrcA, oqForwardedSrcB, oqIEUAdr, oqRawLoadWord;
  logic                oqALUSrcA, oqALUSrcB;
  logic [2:0]          oqImmSrc;
  logic                oqW64, oqUW64, oqSubArith;
  logic [2:0]          oqALUSelect;
  logic [3:0]          oqBSelect, oqZBBSelect;
  logic [2:0]          oqBALUControl;
  logic                oqBMUActive;
  logic [1:0]          oqCZero;
  logic                oqALUResultSrc, oqJump, oqBranch, oqPCSrc, oqRegWrite;
  logic [2:0]          oqResultSrc;
  logic                oqFWriteInt, oqViaSQ, oqAMO, oqLoadChk;
  // RQ
  logic                RQ_HitA, RQ_HitB;
  logic [P.XLEN-1:0]   RQ_ValA, RQ_ValB;
  logic [4:0]          rqRd [2];
  logic                rqRegWrite [2];
  logic [P.XLEN-1:0]   rqResult [2];
  logic [SHARD_CW-1:0] rqCount;
  // SQ
  logic [P.PA_BITS-1:0] sqPA [SHARD_DEPTH];
  logic [1:0]          sqSize [SHARD_DEPTH];
  logic [P.XLEN-1:0]   sqData [SHARD_DEPTH];
  logic [SHARD_CW-1:0] sqCount, sqNVerified;
  logic                sqPop, SQStoreM;
  logic [P.PA_BITS-1:0] SQPAdrM;
  logic [P.XLEN-1:0]   SQWriteDataM;
  // shadow pipeline
  logic                shadow_we3;
  logic [4:0]          shadow_a3;
  logic [P.XLEN-1:0]   shadow_wd3;
  logic [4:0]          sRs1E, sRs2E;
  logic [P.XLEN-1:0]   sRD1E, sRD2E;
  logic                sCommit, sCommitStore, sFault;
  logic [P.XLEN-1:0]   sFaultPC;
  logic [7:0]          sFaultClass;
  // serialization, recovery
  logic                NonMemSerialM;                        // M-stage instruction changes state the shadow cannot defer
  logic                ShadowQuiescentM;
  logic                TrapPendingM;
  logic                RecPending;                           // shadow fault seen; pipeline not yet redirected
  logic [P.XLEN-1:0]   RecPC;
  logic                ShardRedirectM;
  logic [P.XLEN-1:0]   ShardRedirectPCM;
  // Memory-stage checks and fault response
  localparam logic [1:0] SHARD_RETRY_LIMIT = 2'd3;           // consecutive faults before a replay becomes a trap
  logic                EAFaultM, OperandFaultM, AMOFaultM, LoadFwdFaultM, CSRFaultM;
  logic [P.XLEN-1:0]   ShadowEAM;                            // effective address from the second AGU adder
  logic                MULFaultM, FMAFaultM;
  logic                CSRStateFaultM, CSRMirrorResyncM, EscalateStateM;
  logic                ShardPreFaultM, ShardLocalFaultM;
  logic                RedirectRecM, RedirectLocalM, EscalateLocalM, EscalateRecM;
  logic [1:0]          RetryCount;
  logic                ShadowFaultTrapM, ShadowFaultTrapTakenM;
  logic [P.XLEN-1:0]   ShadowFaultEPCM, ShadowFaultMtvalM;
  logic                ShadowFaultW;
  logic                          EccDedFaultM, EccDedTrapTakenM; // registered DED trap record and acknowledgement
  logic [P.XLEN-1:0]             EccDedFaultEPCM, EccDedFaultMtvalM;
  logic                          RegEccDedErrSticky;              // latched DED fault — cleared only by reset
  logic                          PrivModeUncorrectableFaultW_priv; // from privileged unit before ECC OR

  // instruction fetch unit: PC, branch prediction, instruction cache
  ifu #(P) ifu(.clk, .reset,
    .StallF, .StallD, .StallE, .StallM, .StallW, .FlushD, .FlushE, .FlushM, .FlushW,
    .CompressedE,
    .InstrValidE, .InstrValidD,
    .BranchD, .BranchE, .JumpD, .JumpE, .ICacheStallF, .InjectD,
    // Fetch
    .HRDATA, .PCSpillF, .IFUHADDR,
    .IFUStallF, .IFUHBURST, .IFUHTRANS, .IFUHSIZE, .IFUHREADY, .IFUHWRITE,
    .ICacheAccess, .ICacheMiss,
    // Execute
    .PCLinkE, .PCSrcE, .IEUAdrE, .IEUAdrM, .PCE, .BPWrongE,  .BPWrongM,
    // Mem
    .CommittedF, .EPCM, .TrapVectorM, .RetM, .TrapM, .ShardRedirectM, .ShardRedirectPCM, .InvalidateICacheM, .CSRWriteFenceM,
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
     // SHARD
     .shadow_we3, .shadow_a3, .shadow_wd3, .sRs1E(RegA4), .sRs2E(RegA5), .sRD1E, .sRD2E,
     .Rs1E, .Rs2E, .RQ_HitA, .RQ_ValA, .RQ_HitB, .RQ_ValB,
     .SrcAE, .SrcBE, .ForwardedSrcAM, .ShardCtlM, .PCSrcM, .RegWriteM, .ResultSrcM, .FWriteIntM,
     .RegWriteW(RegWriteW_s), .ResultW(ResultW_s));

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

  lsu #(.P(P), .SQ_DEPTH(SHARD_DEPTH)) lsu(
    .clk, .reset, .StallM, .FlushM, .StallW, .FlushW,
    // CPU interface
    .MemRWE, .MemRWM, .Funct3M, .Funct7M(InstrM[31:25]), .AtomicM,
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
    // SHARD store buffer
    .ShadowIdleM, .NonMemSerialM, .ShardPreFaultM, .ShardRedirectM,
    .sqPA, .sqSize, .sqData, .sqCount, .sqNVerified, .sqPop,
    .SQStoreM, .SQPAdrM, .SQWriteDataM, .ShadowQuiescentM,
    .RawReadDataWordM, .AMOFaultM, .LoadFwdFaultM);

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

  // global stall and flush control
  hazard hzu(
    .BPWrongE, .CSRWriteFenceM, .RetM, .TrapM,
    .StructuralStallD,
    .LSUStallM, .IFUStallF,
    .FPUStallD, .ExternalStall,
    .DivBusyE, .FDivBusyE,
    .ShardRedirectM, .ShardStallW(ShardBackpressureW | ShardLocalFaultM),
    .wfiM, .IntPendingM, .InjectD,
    // Stall & flush outputs
    .StallF, .StallD, .StallE, .StallM, .StallW,
    .FlushD, .FlushE, .FlushM, .FlushW);

  // privileged unit
  if (P.ZICSR_SUPPORTED) begin : priv
    privileged #(P) priv(
      .clk, .reset,
      .FlushD, .FlushE, .FlushM, .FlushW, .StallD, .StallE, .StallM, .StallW,
      .CSRReadM, .CSRWriteM, .SrcAM, .ForwardedSrcAM, .PCM, .PCSpillM,
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
      .CSRFaultM, .CSRStateFaultM, .CSRMirrorResyncM, .ShadowQuiescentM, .ShardRedirectM, .TrapPendingM,
      .ShadowFaultTrapM, .ShadowFaultEPCM, .ShadowFaultMtvalM, .ShadowFaultTrapTakenM,
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
            sfencevmaM, BigEndianM, wfiM, IntPendingM, EccDedTrapTakenM, PrivModeUncorrectableFaultW_priv,
            TrapPendingM, ShadowFaultTrapTakenM} = '0;
    // Without a CSR to program it, dummy instruction insertion stays disabled.
    assign RAND_INSTR_INSERT_FREQ_REGW = '0;
    assign CSRFaultM = 1'b0;
    assign CSRStateFaultM = 1'b0;
  end

  // W-stage PC: used as MEPC when the DED error comes from the W-stage pipeline register
  flopenrc #(P.XLEN) PCWReg(clk, reset, FlushW, ~StallW, PCM, PCW);

  ///////////////////////////////////////////////////////////////////////////
  // SHARD — Shadow Hardware Audit Redundancy Design
  //
  // The main pipeline proposes; the shadow verifies and commits.  Nothing the main
  // pipeline computes reaches architectural state unverified:
  //  - register results wait in the RQ until the shadow commits them to the regfile;
  //  - stores wait in the SQ until the shadow verifies them, then drain to memory;
  //  - anything else with an irreversible effect (CSR write, trap, xRET, FP state,
  //    device access, ...) is held in the Memory stage until the shadow has verified
  //    every older instruction (NonMemSerialM here, SerialMemM in the LSU).
  // On a mismatch the shadow commits nothing, the queues are flushed, and the main
  // pipeline is redirected to replay from the faulting instruction.
  ///////////////////////////////////////////////////////////////////////////

  // An instruction that leaves the Memory stage unflushed is certain to retire.  That is
  // where it enters the IQ/OQ (and SQ); its result follows into the RQ from Writeback.
  assign MExitM = InstrValidM & ~StallW & ~FlushW;
  flopenrc #(1) InstrValidWReg(clk, reset, FlushW, ~StallW, InstrValidM, InstrValidW);
  flopenrc #(1) CompressedMReg(clk, reset, FlushM, ~StallM, CompressedE, CompressedM);

  // From a shadow fault until the redirect, the main pipeline holds wrong-path
  // instructions: nothing they produce may enter the queues.
  assign ShardPushOK = ~RecPending & ~sFault;
  assign QPushM      = MExitM & ShardPushOK;

  // The Writeback-stage result is stable for as long as the instruction sits there, so
  // push it on the first cycle rather than waiting for StallW to clear.  The shadow can
  // then finish verifying an instruction that the rest of the pipeline is waiting on.
  assign RQPushW = InstrValidW & ~WPushed & ShardPushOK;
  always_ff @(posedge clk)
    if (reset) WPushed <= 1'b0;
    else       WPushed <= StallW & (WPushed | RQPushW);

  always_ff @(posedge clk)
    if (reset | sFault) InFlight <= '0;
    else                InFlight <= InFlight + {{SHARD_CW{1'b0}}, QPushM} - {{SHARD_CW{1'b0}}, sCommit};

  assign ShadowIdleM = (InFlight == '0) & ~RecPending;

  // Freeze the main pipeline one short of a full RQ: the instruction already in
  // Writeback still has room, and every IQ/OQ entry belongs to an instruction that is
  // in the RQ or in Writeback, so no queue can overflow.
  assign ShardBackpressureW = (rqCount >= SHARD_CW'(SHARD_DEPTH-1));

  // Instructions whose effect cannot be deferred or undone wait in Memory until the
  // shadow is quiescent.  A pending trap waits the same way.
  assign NonMemSerialM = (InstrValidM & (CSRWriteFenceM | PrivilegedM | InvalidateICacheM | FlushDCacheM |
                                         FRegWriteM | FpLoadStoreM | FWriteIntM)) | TrapPendingM;

  // Memory-stage checks.  These cover what the trailing shadow cannot re-derive, and
  // what must be right before an instruction with a direct, irreversible effect runs.
  //  EA       second AGU adder and second address register on every memory access
  //  Operand  once the shadow is idle the register file is architecturally current, so
  //           the operands of the instruction in Memory must equal it (read through
  //           the shadow's ports, which are free then).  This verifies in place every
  //           instruction that waits for quiescence before acting.
  //  AMO, LoadFwd, CSR   duplicated datapaths in the LSU and CSR file
  //  MUL, FMA mod-3 residue checks of the two multipliers, which the shadow shares
  flopenrc #(P.XLEN) ShadowEAMReg(clk, reset, FlushM, ~StallM, SrcAE + SrcBE, ShadowEAM);
  assign EAFaultM = (|MemRWM) & (ShadowEAM != IEUAdrM);

  assign RegA4 = ShadowIdleM ? InstrM[19:15] : sRs1E;
  assign RegA5 = ShadowIdleM ? InstrM[24:20] : sRs2E;
  assign OperandFaultM = ShadowIdleM & ((ForwardedSrcAM != sRD1E) | (WriteDataM != sRD2E));

  assign ShardPreFaultM   = InstrValidM & (EAFaultM | OperandFaultM | CSRFaultM | MULFaultM | FMAFaultM);
  assign ShardLocalFaultM = ShardPreFaultM | (InstrValidM & (AMOFaultM | LoadFwdFaultM));

  // Fault response.
  //  Shadow fault (sFault): the queues are flushed at once; the main pipeline is
  //   redirected to the faulting instruction as soon as no bus operation is in flight
  //   (the condition an interrupt waits for).
  //  Memory-stage fault: the instruction is held, then flushed and refetched.
  // Either way nothing was committed, so the replay is exact.  A fault that repeats
  // SHARD_RETRY_LIMIT times with no instruction committing in between is not transient:
  // it becomes a precise cause-16 trap at the faulting instruction instead.
  // A CSR mirror state fault cannot be replayed away at all (one of the two copies is
  // already wrong), so it traps at once; the mirror is reloaded after the trap is taken
  // so that the fault is reported once.
  always_ff @(posedge clk)
    if (reset)             RecPending <= 1'b0;
    else if (sFault)       RecPending <= 1'b1;
    else if (RedirectRecM) RecPending <= 1'b0;
  flopen #(P.XLEN) RecPCReg(clk, sFault, sFaultPC, RecPC);

  assign RedirectRecM   = RecPending & ~CommittedM & ~CommittedF;
  assign EscalateRecM   = sFault & (RetryCount == SHARD_RETRY_LIMIT - 2'd1);
  assign EscalateLocalM = ShardLocalFaultM & ~RecPending & ~CommittedF & ~ShadowFaultTrapM &
                          (RetryCount == SHARD_RETRY_LIMIT - 2'd1);
  assign RedirectLocalM = ShardLocalFaultM & ~RecPending & ~CommittedF & ~ShadowFaultTrapM &
                          (RetryCount != SHARD_RETRY_LIMIT - 2'd1);

  assign ShardRedirectM   = RedirectRecM | RedirectLocalM;
  assign ShardRedirectPCM = RecPending ? RecPC : PCM;

  assign EscalateStateM = CSRStateFaultM & ~ShadowFaultTrapM & ~CSRMirrorResyncM;
  flopr #(1) CSRMirrorResyncReg(clk, reset, ShadowFaultTrapTakenM & CSRStateFaultM, CSRMirrorResyncM);

  always_ff @(posedge clk)
    if (reset | EscalateRecM | EscalateLocalM) RetryCount <= '0;
    else if (sFault | RedirectLocalM)          RetryCount <= sCommit ? 2'd1 : RetryCount + 2'd1;
    else if (sCommit)                          RetryCount <= '0;

  always_ff @(posedge clk)
    if (reset | ShadowFaultTrapTakenM)         ShadowFaultTrapM <= 1'b0;
    else if (EscalateRecM | EscalateLocalM | EscalateStateM) ShadowFaultTrapM <= 1'b1;
  flopen #(P.XLEN) ShadowFaultEPCReg(clk, EscalateRecM | EscalateLocalM | EscalateStateM, sFault ? sFaultPC : PCM, ShadowFaultEPCM);
  flopen #(P.XLEN) ShadowFaultMtvalReg(clk, EscalateRecM | EscalateLocalM | EscalateStateM,
    {{(P.XLEN-16){1'b0}}, CSRStateFaultM, FMAFaultM, MULFaultM, LoadFwdFaultM, AMOFaultM, CSRFaultM, OperandFaultM, EAFaultM,
     sFault ? sFaultClass : 8'b0}, ShadowFaultMtvalM);

  // MSECFAULT[6] logs every detection, recovered or not
  assign ShadowFaultW = sFault | RedirectLocalM | EscalateLocalM | EscalateStateM;

  shadow_iq #(.P(P), .DEPTH(SHARD_DEPTH)) siq(.clk, .reset, .Flush(sFault),
    .Push(QPushM), .PCM, .InstrM, .CompressedM, .Pop(iqPop),
    .sValid(iqValid), .sPC(iqPC), .sInstr(iqInstr), .sCompressed(iqCompressed));

  shadow_oq #(.P(P), .DEPTH(SHARD_DEPTH)) soq(.clk, .reset, .Flush(sFault),
    .Push(QPushM), .Pop(oqPop),
    .ForwardedSrcAM, .ForwardedSrcBM(WriteDataM), .IEUAdrM, .RawLoadWordM(RawReadDataWordM),
    .ALUSrcAM(ShardCtlM[27]), .ALUSrcBM(ShardCtlM[26]), .ImmSrcM(ShardCtlM[25:23]),
    .W64M(ShardCtlM[22]), .UW64M(ShardCtlM[21]), .SubArithM(ShardCtlM[20]),
    .ALUSelectM(ShardCtlM[19:17]), .BSelectM(ShardCtlM[16:13]), .ZBBSelectM(ShardCtlM[12:9]),
    .BALUControlM(ShardCtlM[8:6]), .BMUActiveM(ShardCtlM[5]), .CZeroM(ShardCtlM[4:3]),
    .ALUResultSrcM(ShardCtlM[2]), .JumpM(ShardCtlM[1]), .BranchM(ShardCtlM[0]),
    .PCSrcM, .RegWriteM, .ResultSrcM, .FWriteIntM,
    .ViaSQM(SQStoreM), .AMOM(AtomicM[1]), .LoadChkM(MemRWM[1] & ~FpLoadStoreM & ~BigEndianM),
    .s_ForwardedSrcA(oqForwardedSrcA), .s_ForwardedSrcB(oqForwardedSrcB),
    .s_IEUAdr(oqIEUAdr), .s_RawLoadWord(oqRawLoadWord),
    .s_ALUSrcA(oqALUSrcA), .s_ALUSrcB(oqALUSrcB), .s_ImmSrc(oqImmSrc),
    .s_W64(oqW64), .s_UW64(oqUW64), .s_SubArith(oqSubArith),
    .s_ALUSelect(oqALUSelect), .s_BSelect(oqBSelect), .s_ZBBSelect(oqZBBSelect),
    .s_BALUControl(oqBALUControl), .s_BMUActive(oqBMUActive), .s_CZero(oqCZero),
    .s_ALUResultSrc(oqALUResultSrc), .s_Jump(oqJump), .s_Branch(oqBranch),
    .s_PCSrc(oqPCSrc), .s_RegWrite(oqRegWrite), .s_ResultSrc(oqResultSrc), .s_FWriteInt(oqFWriteInt),
    .s_ViaSQ(oqViaSQ), .s_AMO(oqAMO), .s_LoadChk(oqLoadChk));

  shadow_rq #(.P(P), .DEPTH(SHARD_DEPTH)) srq(.clk, .reset, .Flush(sFault),
    .Push(RQPushW), .RdW, .RegWriteW(RegWriteW_s), .ResultW(ResultW_s), .Pop(sCommit),
    .Rs1E, .Rs2E, .RQ_HitA, .RQ_HitB, .RQ_ValA, .RQ_ValB,
    .sRd(rqRd), .sRegWrite(rqRegWrite), .sResult(rqResult), .Count(rqCount));

  shadow_sq #(.P(P), .DEPTH(SHARD_DEPTH)) ssq(.clk, .reset, .Flush(sFault),
    .Push(QPushM & SQStoreM), .PAdrM(SQPAdrM), .SizeM(Funct3M[1:0]), .WriteDataM(SQWriteDataM),
    .Verify(sCommitStore), .Pop(sqPop),
    .sqPA, .sqSize, .sqData, .Count(sqCount), .NVerified(sqNVerified));

  shadow_pipeline #(.P(P), .DEPTH(SHARD_DEPTH)) spipe(.clk, .reset, .StreamBreak(TrapM),
    .iqValid, .iqPC, .iqInstr, .iqCompressed, .iqPop,
    .oqForwardedSrcA, .oqForwardedSrcB, .oqIEUAdr, .oqRawLoadWord,
    .oqALUSrcA, .oqALUSrcB, .oqImmSrc, .oqW64, .oqUW64, .oqSubArith,
    .oqALUSelect, .oqBSelect, .oqZBBSelect, .oqBALUControl, .oqBMUActive, .oqCZero,
    .oqALUResultSrc, .oqJump, .oqBranch, .oqPCSrc, .oqRegWrite, .oqResultSrc, .oqFWriteInt,
    .oqViaSQ, .oqAMO, .oqLoadChk, .oqPop,
    .rqRd, .rqRegWrite, .rqResult, .rqCount, .rqPush(RQPushW),
    .sqPA, .sqSize, .sqData, .sqCount, .sqNVerified,
    .sRs1E, .sRs2E, .sRD1E, .sRD2E,
    .shadow_we3, .shadow_a3, .shadow_wd3,
    .Commit(sCommit), .CommitStore(sCommitStore),
    .Fault(sFault), .FaultPC(sFaultPC), .FaultClass(sFaultClass));

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
      .MDUResultW, .DivBusyE, .MULFaultM);
  end else begin // no M instructions supported
    assign MDUResultW = '0;
    assign DivBusyE   = 1'b0;
    assign MULFaultM  = 1'b0;
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
      .FIntDivResultW, .FMAFaultM);
  end else begin                           // no F_SUPPORTED or D_SUPPORTED; tie outputs low
    assign {FPUStallD, FWriteIntE, FCvtIntE, FIntResM, FCvtIntW, FRegWriteM,
            IllegalFPUInstrD, SetFflagsM, FpLoadStoreM, FMAFaultM,
            FWriteDataM, FCvtIntResW, FIntDivResultW, FDivBusyE} = '0;
  end

endmodule
