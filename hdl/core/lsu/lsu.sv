/////////////////////////////////////////////////////////////////////////////////////////////////////////
// lsu.sv
//
// Written: David_Harris@hmc.edu, rose@rosethompson.net
// Created: 9 January 2021
// Modified: 11 January 2023
//
// Purpose: Load/Store Unit
//          HPTW, DMMU, data cache, interface to external bus
//          Atomic, Endian swap, and subword read/write logic
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
/////////////////////////////////////////////////////////////////////////////////////////////////////////

module lsu import cvw::*;  #(parameter cvw_t P, parameter int SQ_DEPTH = 8) (
  input  logic                    clk, reset,
  input  logic                    StallM, FlushM, StallW, FlushW,
  output logic                    LSUStallM,                            // LSU stalls pipeline during a multicycle operation
  // connected to cpu (controls)
  input  logic [1:0]              MemRWE,                               // Read/Write control
  input  logic [1:0]              MemRWM,                               // Read/Write control
  input  logic [2:0]              Funct3M,                              // Size of memory operation
  input  logic [6:0]              Funct7M,                              // Atomic memory operation function
  input  logic [1:0]              AtomicM,                              // Atomic memory operation
  input  logic                    FlushDCacheM,                         // Flush D cache to next level of memory
  input  logic [3:0]              CMOpM,                                // 1: cbo.inval; 2: cbo.flush; 4: cbo.clean; 8: cbo.zero
  input  logic                    LSUPrefetchM,                         // Prefetch; presently unused
  output logic                    CommittedM,                           // Delay interrupts while memory operation in flight
  output logic                    SquashSCW,                            // Store conditional failed disable write to GPR
  output logic                    DCacheMiss,                           // D cache miss for performance counters
  output logic                    DCacheAccess,                         // D cache memory access for performance counters
  // address and write data
  input  logic [P.XLEN-1:0]       IEUAdrE,                              // Execution stage memory address
  output logic [P.XLEN-1:0]       IEUAdrM,                              // Memory stage memory address
  input  logic [P.XLEN-1:0]       WriteDataM,                           // Write data from IEU
  output logic [P.LLEN-1:0]       ReadDataW,                            // Read data to IEU or FPU
  // cpu privilege
  input  logic [1:0]              PrivilegeModeW,                       // Current privilege mode
  input  logic                    BigEndianM,                           // Swap byte order to big endian
  input  logic                    sfencevmaM,                           // Virtual memory address fence, invalidate TLB entries
  output logic                    DCacheStallM,                         // D$ busy with multicycle operation
  output logic [P.XLEN-1:0]       IEUAdrxTvalM,                         // IEUAdrM, but could be spilled onto the next cacheline or virtual page.
  // fpu
  input  logic [P.FLEN-1:0]       FWriteDataM,                          // Write data from FPU
  input  logic                    FpLoadStoreM,                         // Selects FPU as store for write data
  // faults
  output logic                    LoadPageFaultM, StoreAmoPageFaultM,   // Page fault exceptions
  output logic                    LoadMisalignedFaultM,                 // Load address misaligned fault
  output logic                    LoadAccessFaultM,                     // Load access fault (PMA)
  output logic                    HPTWInstrAccessFaultF,                // HPTW generated access fault during instruction fetch
  output logic                    HPTWInstrPageFaultF,                  // HPTW generated access fault during instruction fetch
  // cpu hazard unit (trap)
  output logic                    StoreAmoMisalignedFaultM,             // Store or AMO address misaligned fault
  output logic                    StoreAmoAccessFaultM,                 // Store or AMO access fault
  // connect to ahb
  output logic [P.PA_BITS-1:0]    LSUHADDR,                             // Bus address from LSU to EBU
  input  logic [P.XLEN-1:0]       HRDATA,                               // Bus read data from LSU to EBU
  output logic [P.XLEN-1:0]       LSUHWDATA,                            // Bus write data from LSU to EBU
  input  logic                    LSUHREADY,                            // Bus ready from LSU to EBU
  output logic                    LSUHWRITE,                            // Bus write operation from LSU to EBU
  output logic [2:0]              LSUHSIZE,                             // Bus operation size from LSU to EBU
  output logic [2:0]              LSUHBURST,                            // Bus burst from LSU to EBU
  output logic [1:0]              LSUHTRANS,                            // Bus transaction type from LSU to EBU
  output logic [P.XLEN/8-1:0]     LSUHWSTRB,                            // Bus byte write enables from LSU to EBU
  // page table walker
  input  logic [P.XLEN-1:0]       SATP_REGW,                            // SATP (supervisor address translation and protection) CSR
  input  logic                    STATUS_MXR, STATUS_SUM, STATUS_MPRV,  // STATUS CSR bits: make executable readable, supervisor user memory, machine privilege
  input  logic [1:0]              STATUS_MPP,                           // Machine previous privilege mode
  input  logic                    ENVCFG_PBMTE,                         // Page-based memory types enabled
  input  logic                    ENVCFG_ADUE,                          // HPTW A/D Update enable
  input  logic [P.XLEN-1:0]       PCSpillF,                             // Fetch PC
  input  logic                    ITLBMissOrUpdateAF,                   // ITLB miss causes HPTW (hardware pagetable walker) walk or update access bit
  output logic [P.XLEN-1:0]       PTE,                                  // Page table entry write to ITLB
  output logic [2:0]              PageType,                             // Type of page table entry to write to ITLB
  output logic                    ITLBWriteF,                           // Write PTE to ITLB
  output logic                    SelHPTW,                              // During a HPTW walk the effective privilege mode becomes S_MODE
  input var logic [7:0]           PMPCFG_ARRAY_REGW[P.PMP_ENTRIES-1:0], // PMP configuration from privileged unit
  input var logic [P.PA_BITS-3:0] PMPADDR_ARRAY_REGW[P.PMP_ENTRIES-1:0], // PMP address from privileged unit
  // SHARD store buffer.  The main pipeline never writes memory with an ordinary store:
  // the store enters the store queue when it leaves the Memory stage, and this LSU's
  // drain engine writes it to the D-cache or bus once the shadow has verified it.
  input  logic                    ShadowIdleM,                            // every retired instruction has been verified and committed
  input  logic                    NonMemSerialM,                          // M-stage instruction has an irreversible effect outside memory, or a trap is pending
  input  logic                    ShardPreFaultM,                         // M-stage instruction failed a check outside the LSU: it must not access memory
  input  logic                    ShardRedirectM,                         // recovery or retry redirect: discard the LR reservation
  input  var logic [P.PA_BITS-1:0] sqPA [SQ_DEPTH],                       // store queue contents, oldest first
  input  var logic [1:0]          sqSize [SQ_DEPTH],
  input  var logic [P.XLEN-1:0]   sqData [SQ_DEPTH],
  input  logic [$clog2(SQ_DEPTH+1)-1:0] sqCount, sqNVerified,             // entries held, and how many of the oldest are verified
  output logic                    sqPop,                                  // drain engine wrote the head to memory
  output logic                    SQStoreM,                               // M-stage instruction enters the store queue when it leaves M
  output logic [P.PA_BITS-1:0]    SQPAdrM,                                // ... with this physical address
  output logic [P.XLEN-1:0]       SQWriteDataM,                           // ... and this data (store data, or the AMO result)
  output logic                    ShadowQuiescentM,                       // nothing retired is unverified and no store is buffered
  output logic [P.XLEN-1:0]       RawReadDataWordM,                       // aligned load word (after store-queue merge), before subword extract
  output logic                    AMOFaultM,                              // second AMO ALU disagrees with the first
  output logic                    LoadFwdFaultM                           // the two store-queue merges disagree
);
  localparam logic MISALIGN_SUPPORT = P.ZICCLSM_SUPPORTED & P.DCACHE_SUPPORTED;
  localparam MLEN = MISALIGN_SUPPORT ? 2*P.LLEN : P.LLEN; // widen buffer for misaligned accessess

  logic [P.XLEN+1:0]     IEUAdrExtM;                             // Memory stage address zero-extended to PA_BITS or XLEN whichever is longer
  logic [P.XLEN+1:0]     IEUAdrExtE;                             // Execution stage address zero-extended to PA_BITS or XLEN whichever is longer
  logic [P.PA_BITS-1:0]  PAdrM;                                  // Physical memory address
  logic [P.XLEN+1:0]     IHAdrM;                                 // Either IEU or HPTW memory address

  logic [1:0]            PreLSURWM;                              // IEU or HPTW Read/Write signal
  logic [1:0]            LSURWM;                                 // IEU or HPTW Read/Write signal gated by LR/SC
  logic [2:0]            LSUFunct3M;                             // IEU or HPTW memory operation size
  logic [6:0]            LSUFunct7M;                             // AMO function gated by HPTW
  logic [1:0]            LSUAtomicM;                             // AMO signal gated by HPTW
  logic [3:0]            LSUCMOpM;                               // CMOpM gated by HPTW

  logic                  GatedStallW;                            // Hazard unit StallW gated when SelHPTW = 1

  logic                  LSUBusStallM;                           // Bus interface busy with multicycle operation masked by HPTWFlushW
  logic                  HPTWStall;                              // HPTW busy with multicycle operation
  logic                  DCacheBusStallM;                        // Cache or bus stall
  logic                  CacheBusHPWTStall;                      // Cache, bus, or hptw is requesting a stall
  logic                  SelSpillE;                              // Align logic detected a spill and needs to stall

  logic                  CacheableM;                             // PMA indicates memory address is cacheable
  logic                  BusCommittedM;                          // Bus memory operation in flight, delay interrupts
  logic                  DCacheCommittedM;                       // D$ memory operation started, delay interrupts

  logic [P.LLEN-1:0]     DTIMReadDataWordM;                      // DTIM read data
  logic [MLEN-1:0]       DCacheReadDataWordM;                    // D$ read data
  logic [MLEN-1:0]       LSUWriteDataSpillM;                     // Final write data
  logic [MLEN/8-1:0]     ByteMaskSpillM;                         // Selects which bytes within a word to write
  logic [P.LLEN-1:0]     DCacheReadDataWordSpillM;               // D$ read data
  logic [P.LLEN-1:0]     ReadDataWordMuxM;                       // DTIM or D$ read data
  logic [P.LLEN-1:0]     LittleEndianReadDataWordM;              // Endian-swapped read data
  logic [P.LLEN-1:0]     ReadDataM;                              // Final read data

  logic [P.XLEN-1:0]     IHWriteDataM;                           // IEU or HPTW write data
  logic [P.XLEN-1:0]     IMAWriteDataM;                          // IEU, HPTW, or AMO write data
  logic [P.LLEN-1:0]     IMAFWriteDataM;                         // IEU, HPTW, AMO, or FPU write data
  logic [P.LLEN-1:0]     LittleEndianWriteDataM;                 // Ending-swapped write data
  logic [P.LLEN-1:0]     LSUWriteDataM;                          // Final write data
  logic [(P.LLEN-1)/8:0] ByteMaskM;                              // Selects which bytes within a word to write
  logic [(P.LLEN-1)/8:0] ByteMaskExtendedM;                      // Selects which bytes within a word to write
  logic [1:0]            MemRWSpillM;
  logic                  SpillStallM;

  logic                  DTLBMissM;                              // DTLB miss causes HPTW walk
  logic                  DTLBWriteM;                             // Writes PTE and PageType to DTLB
  logic                  LSULoadAccessFaultM;                    // Load access fault
  logic                  LSUStoreAmoAccessFaultM;                // Store access fault
  logic                  HPTWFlushW;                             // HPTW needs to flush operation
  logic                  LSUFlushW;                              // HPTW or hazard unit flushes operation
  logic                  SelDTIM;                                // Select DTIM rather than bus or D$
  logic [P.XLEN-1:0]     WriteDataZM;
  logic                  LSULoadPageFaultM, LSUStoreAmoPageFaultM;
  logic                  DTLBMissOrUpdateDAM;

  // SHARD store buffer
  typedef enum logic [1:0] {SQ_IDLE, SQ_ADR, SQ_WR, SQ_RESTORE} sqstatetype;
  sqstatetype            SQState, SQNextState;
  logic                  SQBusy;                                 // drain engine owns the LSU
  logic                  SQDrainSel;                             // LSU is addressing or writing the store queue head
  logic                  SQStart;                                // drain engine takes the LSU this cycle
  logic                  SQOwnsLSUM;                             // drain engine owns the LSU this cycle
  logic                  SQRestoreM;                             // M-stage instruction needs its cache set re-read after a drain
  logic                  SQEmpty, SQFull;
  logic                  WalkOK;                                 // HPTW may start a walk: nothing buffered that it could miss or overwrite
  logic                  AlignedM;                               // naturally aligned access
  logic                  SimpleMemOKM;                           // access the store queue / byte-merge can represent
  logic                  SerialMemM;                             // memory operation that must wait until the shadow is quiescent
  logic                  HoldM;                                  // M-stage instruction must wait this cycle
  logic                  ShardLSUStallM;                         // stall from a hold or the drain engine
  logic                  ShardMaskM;                             // hide the M-stage instruction from the cache and bus
  logic [1:0]            LSURWMaskedM;                           // read/write presented to the cache, bus and DTIM
  logic [1:0]            HPreLSURWM;                             // IEU or HPTW requests, before the drain engine's
  logic [1:0]            HLSUAtomicM;
  logic [2:0]            HLSUFunct3M;
  logic [6:0]            HLSUFunct7M;
  logic [3:0]            HLSUCMOpM;
  logic [P.XLEN+1:0]     HIHAdrM;
  logic [P.XLEN-1:0]     HIHWriteDataM;
  logic                  MMULoadAccessFaultM, MMUStoreAmoAccessFaultM;
  logic                  MMULoadPageFaultM, MMUStoreAmoPageFaultM;
  logic [P.LLEN-1:0]     ReadDataWordFwdM;                       // read word with buffered stores merged in
  logic [P.LLEN-1:0]     ReadDataWordFwdCheckM;                  // second copy of the merge

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Pipeline for IEUAdr E to M
  // Zero-extend address to 34 bits for XLEN=32
  /////////////////////////////////////////////////////////////////////////////////////////////

  flopenrc #(P.XLEN) AddressMReg(clk, reset, FlushM, ~StallM, IEUAdrE, IEUAdrM);
  if(MISALIGN_SUPPORT) begin : ziccslm_align
    logic [P.XLEN-1:0] IEUAdrSpillE;
    logic [P.XLEN-1:0] IEUAdrSpillM;
    align #(P) align(.clk, .reset, .StallM, .FlushM, .IEUAdrE, .IEUAdrM, .Funct3M, .FpLoadStoreM,
                     .MemRWM,
                     .DCacheReadDataWordM, .CacheBusHPWTStall, .SelHPTW(SelHPTW | SQOwnsLSUM),
                     .ByteMaskM, .ByteMaskExtendedM, .LSUWriteDataM, .ByteMaskSpillM, .LSUWriteDataSpillM,
                     .IEUAdrSpillE, .IEUAdrSpillM, .IEUAdrxTvalM, .SelSpillE, .DCacheReadDataWordSpillM, .SpillStallM);
    assign IEUAdrExtM = {2'b00, IEUAdrSpillM};
    assign IEUAdrExtE = {2'b00, IEUAdrSpillE};
  end else begin : no_ziccslm_align
    assign IEUAdrExtM = {2'b00, IEUAdrM};
    assign IEUAdrExtE = {2'b00, IEUAdrE};
    assign SelSpillE = 1'b0;
    assign DCacheReadDataWordSpillM = DCacheReadDataWordM;
    assign ByteMaskSpillM = ByteMaskM;
    assign LSUWriteDataSpillM = LSUWriteDataM;
    assign MemRWSpillM = MemRWM;
    assign {SpillStallM} = 1'b0;
    assign IEUAdrxTvalM = IEUAdrM;
  end

    if(P.ZICBOZ_SUPPORTED) begin : cboz
      assign WriteDataZM = LSUCMOpM[3] ? 0 : WriteDataM;
   end else begin : cboz
      assign WriteDataZM = WriteDataM;
    end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // HPTW (only needed if VM supported)
  // MMU include PMP and is needed if any privileged supported
  /////////////////////////////////////////////////////////////////////////////////////////////

  if(P.VIRTMEM_SUPPORTED) begin : hptw
    hptw #(P) hptw(.clk, .reset, .MemRWM, .AtomicM, .ITLBMissOrUpdateAF(ITLBMissOrUpdateAF & WalkOK), .ITLBWriteF,
      .DTLBMissOrUpdateDAM(DTLBMissOrUpdateDAM & WalkOK), .DTLBWriteM,
      .FlushW, .DCacheBusStallM, .SATP_REGW, .PCSpillF,
      .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP, .ENVCFG_ADUE, .PrivilegeModeW,
      .ReadDataM(ReadDataM[P.XLEN-1:0]), // ReadDataM is LLEN, but HPTW only needs XLEN
      .WriteDataM(WriteDataZM), .Funct3M, .LSUFunct3M(HLSUFunct3M), .Funct7M, .LSUFunct7M(HLSUFunct7M),
      .IEUAdrExtM, .PTE, .IHWriteDataM(HIHWriteDataM), .PageType, .PreLSURWM(HPreLSURWM), .LSUAtomicM(HLSUAtomicM),
      .IHAdrM(HIHAdrM), .CMOpM, .LSUCMOpM(HLSUCMOpM), .HPTWStall, .SelHPTW,
      .HPTWFlushW, .LSULoadAccessFaultM, .LSUStoreAmoAccessFaultM,
      .LoadAccessFaultM, .StoreAmoAccessFaultM, .HPTWInstrAccessFaultF,
      .LoadPageFaultM, .StoreAmoPageFaultM, .LSULoadPageFaultM, .LSUStoreAmoPageFaultM, .HPTWInstrPageFaultF
);
  end else begin // No HPTW, so signals are not multiplexed
    assign HPreLSURWM = MemRWM;
    assign HIHAdrM = IEUAdrExtM;
    assign HLSUFunct3M = Funct3M;
    assign HLSUFunct7M = Funct7M;
    assign HLSUAtomicM = AtomicM;
    assign HLSUCMOpM = CMOpM;
    assign HIHWriteDataM = WriteDataZM;
    assign LoadAccessFaultM = LSULoadAccessFaultM;
    assign StoreAmoAccessFaultM = LSUStoreAmoAccessFaultM;
    assign LoadPageFaultM = LSULoadPageFaultM;
    assign StoreAmoPageFaultM = LSUStoreAmoPageFaultM;
    assign {HPTWStall, SelHPTW, PTE, PageType, DTLBWriteM, ITLBWriteF, HPTWFlushW} = '0;
    assign {HPTWInstrAccessFaultF, HPTWInstrPageFaultF} = '0;
   end

  // CommittedM indicates the cache, bus, or HPTW are busy with a multiple cycle operation.
  // CommittedM is 1 after the first cycle and until the last cycle.  Partially completed memory
  // operations delay interrupts until the next instruction by suppressing pending interrupts in
  // the trap module.
  assign CommittedM = SelHPTW | DCacheCommittedM | BusCommittedM;
  assign GatedStallW = StallW & ~SelHPTW & ~SQOwnsLSUM;
  assign DCacheBusStallM = DCacheStallM | LSUBusStallM;
  assign CacheBusHPWTStall = DCacheBusStallM | HPTWStall | ShardLSUStallM;
  assign LSUStallM = CacheBusHPWTStall | SpillStallM;

  /////////////////////////////////////////////////////////////////////////////////////////////
  // MMU and misalignment fault logic required if privileged unit exists
  /////////////////////////////////////////////////////////////////////////////////////////////
  if(P.ZICSR_SUPPORTED == 1) begin : dmmu
    logic DisableTranslation;                             // During HPTW walk or D$ flush disable virtual memory address translation
    logic WriteAccessM;
    logic DataUpdateDAM;                                  // DTLB hit needs to update dirty or access bits

    assign DisableTranslation = SelHPTW | FlushDCacheM | SQDrainSel;
    assign WriteAccessM = PreLSURWM[0];
    mmu #(.P(P), .TLB_ENTRIES(P.DTLB_ENTRIES), .IMMU(0))
    dmmu(.clk, .reset, .SATP_REGW, .STATUS_MXR, .STATUS_SUM, .STATUS_MPRV, .STATUS_MPP, .ENVCFG_PBMTE, .ENVCFG_ADUE,
      .PrivilegeModeW, .DisableTranslation, .VAdr(IHAdrM), .Size(LSUFunct3M[1:0]),
      .PTE, .PageTypeWriteVal(PageType), .TLBWrite(DTLBWriteM), .TLBFlush(sfencevmaM),
      .PhysicalAddress(PAdrM), .TLBMiss(DTLBMissM), .Cacheable(CacheableM), .Idempotent(), .SelTIM(SelDTIM),
      .InstrAccessFaultF(), .LoadAccessFaultM(MMULoadAccessFaultM),
      .StoreAmoAccessFaultM(MMUStoreAmoAccessFaultM), .InstrPageFaultF(), .LoadPageFaultM(MMULoadPageFaultM),
      .StoreAmoPageFaultM(MMUStoreAmoPageFaultM),
      .LoadMisalignedFaultM, .StoreAmoMisalignedFaultM,
      .UpdateDA(DataUpdateDAM), .CMOpM(LSUCMOpM),
      .AtomicAccessM(|LSUAtomicM), .ExecuteAccessF(1'b0),
      .WriteAccessM, .ReadAccessM(PreLSURWM[1]),
      .PMPCFG_ARRAY_REGW, .PMPADDR_ARRAY_REGW);

    assign DTLBMissOrUpdateDAM = DTLBMissM | (P.SVADU_SUPPORTED & DataUpdateDAM);
  end else begin  // No MMU, so no PMA/page faults and no address translation
    assign DTLBMissOrUpdateDAM = '0;
    assign {DTLBMissM, MMULoadAccessFaultM, MMUStoreAmoAccessFaultM, LoadMisalignedFaultM, StoreAmoMisalignedFaultM} = '0;
    assign {MMULoadPageFaultM, MMUStoreAmoPageFaultM} = '0;
    assign PAdrM = IHAdrM[P.PA_BITS-1:0];
    assign CacheableM = 1'b1;
    assign SelDTIM = P.DTIM_SUPPORTED & ~P.BUS_SUPPORTED; // if no PMA then select dtim if there is a DTIM.  If there is
    // a bus then this is always 0. Cannot have both without PMA.
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Memory System (options)
  // 1. DTIM
  // 2. DTIM and bus
  // 3. Bus
  // 4. Cache and bus
  /////////////////////////////////////////////////////////////////////////////////////////////

  // Pause IEU memory request if TLB miss.  After TLB fill, replay request.
  // Discard memory request on pipeline flush
  // A pipeline flush must not abort the drain engine's write: that store has been
  // verified and is older than anything the flush discards.
  assign LSUFlushW = HPTWFlushW | (FlushW & ~SQBusy);

  if (P.DTIM_SUPPORTED) begin : dtim
    logic [P.PA_BITS-1:0] DTIMAdr;
    logic [1:0]           DTIMMemRWM;

    // The DTIM uses untranslated addresses, so it is not compatible with virtual memory.
    mux2 #(P.PA_BITS) DTIMAdrMux(IEUAdrExtE[P.PA_BITS-1:0], IEUAdrExtM[P.PA_BITS-1:0], MemRWM[0], DTIMAdr);
    assign DTIMMemRWM = SelDTIM ? LSURWMaskedM : 0;
    dtim #(P) dtim(.clk, .reset, .ce(~GatedStallW),
              .MemRWM(DTIMMemRWM),
              .DTIMAdr, .FlushW(LSUFlushW), .WriteDataM(LSUWriteDataM),
              .ReadDataWordM(DTIMReadDataWordM[P.LLEN-1:0]), .ByteMaskM(ByteMaskM));
  end else
    assign DTIMReadDataWordM = '0;
  if (P.BUS_SUPPORTED) begin : bus
    if(P.DCACHE_SUPPORTED) begin : dcache
      localparam   LLENWORDSPERLINE = P.DCACHE_LINELENINBITS/P.LLEN;             // Number of LLEN words in cacheline
      localparam   LLENLOGBWPL = $clog2(LLENWORDSPERLINE);                       // Log2 of ^
      localparam   BEATSPERLINE = P.DCACHE_LINELENINBITS/P.AHBW;                 // Number of AHBW words (beats) in cacheline
      localparam   AHBWLOGBWPL = $clog2(BEATSPERLINE);                           // Log2 of ^
      localparam   LINELEN = P.DCACHE_LINELENINBITS;                             // Number of bits in cacheline
      localparam   LLENPOVERAHBW = P.LLEN / P.AHBW;                              // Number of AHB beats in a LLEN word. AHBW cannot be larger than LLEN. (implementation limitation)
      localparam   CACHEWORDLEN = P.ZICCLSM_SUPPORTED ? 2*P.LLEN : P.LLEN;       // Width of the cache's input and output data buses.  Misaligned doubles width for fast access

      logic [LINELEN-1:0]      FetchBuffer;                                      // Temporary buffer to hold partially fetched cacheline
      logic [P.PA_BITS-1:0]    DCacheBusAdr;                                     // Cacheline address to fetch or writeback.
      logic [AHBWLOGBWPL-1:0]  BeatCount;                                        // Position within a cacheline.  ahbcacheinterface to cache
      logic                    DCacheBusAck;                                     // ahbcacheinterface completed fetch or writeback
      logic                    SelBusBeat;                                       // ahbcacheinterface selects position in cacheline with BeatCount
      logic [1:0]              CacheBusRW;                                       // Cache sends request to ahbcacheinterface
      logic [1:0]              BusRW;                                            // Uncached bus memory access
      logic                    CacheableOrFlushCacheM;                           // Memory address is cacheable or operation is a cache flush
      logic [1:0]              CacheRWM;                                         // Cache read (10), write (01), AMO (11)
      logic                    FlushDCache;                                      // Suppress d cache flush if there is an ITLB miss.
      logic                    BusCMOZero;
      logic [3:0]              CacheCMOpM;
      logic                    BusAtomic;

      if(P.ZICBOZ_SUPPORTED) begin
        assign BusCMOZero = LSUCMOpM[3] & ~CacheableM & ~ShardMaskM;
        assign CacheCMOpM = (CacheableM & ~SelHPTW & ~ShardMaskM) ? CMOpM : '0;
      end else begin
        assign BusCMOZero = 1'b0;
        assign CacheCMOpM = '0;
      end
      // SHARD: an AMO only reads here; its write goes through the store queue, so the
      // bus never sees a locked read-modify-write.
      assign BusAtomic = 1'b0;
      assign BusRW = (~CacheableM & ~SelDTIM )? LSURWMaskedM : '0;
      assign CacheableOrFlushCacheM = CacheableM | (FlushDCacheM & ~ShardMaskM);
      assign CacheRWM = (CacheableM & ~SelDTIM) ? LSURWMaskedM : '0;
      assign FlushDCache = FlushDCacheM & ~SelHPTW & ~ShardMaskM;            // exclusion-tag: lsu FlushDCacheSelHPTW

      cache #(.P(P), .PA_BITS(P.PA_BITS), .LINELEN(P.DCACHE_LINELENINBITS), .NUMSETS(P.DCACHE_WAYSIZEINBYTES*8/LINELEN),
              .NUMWAYS(P.DCACHE_NUMWAYS), .LOGBWPL(LLENLOGBWPL), .WORDLEN(CACHEWORDLEN), .MUXINTERVAL(P.LLEN), .READ_ONLY_CACHE(0)) dcache(
        .clk, .reset, .Stall(GatedStallW & ~SelSpillE), .SelBusBeat, .FlushStage(LSUFlushW),
        .CacheRW(CacheRWM),
        .FlushCache(FlushDCache), .NextSet(IEUAdrExtE[11:0]), .PAdr(PAdrM),
        .ByteMask(ByteMaskSpillM), .BeatCount(BeatCount[AHBWLOGBWPL-1:AHBWLOGBWPL-LLENLOGBWPL]),
        .WriteData(LSUWriteDataSpillM), .SelHPTW(SelHPTW | SQOwnsLSUM),
        .CacheStall(DCacheStallM), .CacheMiss(DCacheMiss), .CacheAccess(DCacheAccess),
        .CacheCommitted(DCacheCommittedM),
        .CacheBusAdr(DCacheBusAdr), .ReadDataWord(DCacheReadDataWordM),
        .FetchBuffer, .CacheBusRW(CacheBusRW),
        .CacheBusAck(DCacheBusAck), .InvalidateCache(1'b0), .InvalidateFlushStage(LSUFlushW), .CMOpM(CacheCMOpM));

      ahbcacheinterface #(.P(P), .BEATSPERLINE(BEATSPERLINE), .AHBWLOGBWPL(AHBWLOGBWPL), .LINELEN(LINELEN),  .LLENPOVERAHBW(LLENPOVERAHBW), .READ_ONLY_CACHE(0)) ahbcacheinterface(
        .HCLK(clk), .HRESETn(~reset), .Flush(LSUFlushW),
        .HRDATA, .HWDATA(LSUHWDATA), .HWSTRB(LSUHWSTRB),
        .HSIZE(LSUHSIZE), .HBURST(LSUHBURST), .HTRANS(LSUHTRANS), .HWRITE(LSUHWRITE), .HREADY(LSUHREADY),
        .BeatCount, .SelBusBeat, .CacheReadDataWordM(DCacheReadDataWordM[P.LLEN-1:0]), .WriteDataM(LSUWriteDataM),
        .Funct3(LSUFunct3M), .HADDR(LSUHADDR), .CacheBusAdr(DCacheBusAdr), .CacheBusRW, .BusAtomic, .BusCMOZero, .CacheableOrFlushCacheM,
        .CacheBusAck(DCacheBusAck), .FetchBuffer, .PAdr(PAdrM),
        .Cacheable(CacheableOrFlushCacheM), .BusRW, .Stall(GatedStallW),
        .BusStall(LSUBusStallM), .BusCommitted(BusCommittedM));

      mux3 #(P.LLEN) UnCachedDataMux(.d0(DCacheReadDataWordSpillM), .d1({LLENPOVERAHBW{FetchBuffer[P.XLEN-1:0]}}),
                                    .d2({{P.LLEN-P.XLEN{1'b0}}, DTIMReadDataWordM[P.XLEN-1:0]}),
                                    .s({SelDTIM, ~(CacheableOrFlushCacheM)}), .y(ReadDataWordMuxM));
    end else begin : passthrough
      // No Cache, use simple ahbinterface instead of ahbcacheinterface
      logic [1:0] BusRW;                    // Non-DTIM memory access, ignore cacheableM
      logic [P.XLEN-1:0] FetchBuffer;
      assign BusRW = ~SelDTIM ? LSURWMaskedM : 0;

      assign LSUHADDR = PAdrM;
      assign LSUHSIZE = LSUFunct3M;

      ahbinterface #(P.XLEN, 1'b1) ahbinterface(.HCLK(clk), .HRESETn(~reset), .Flush(LSUFlushW), .HREADY(LSUHREADY),
        .HRDATA(HRDATA), .HTRANS(LSUHTRANS), .HWRITE(LSUHWRITE), .HWDATA(LSUHWDATA),
        .HWSTRB(LSUHWSTRB), .BusRW, .BusAtomic(1'b0), .ByteMask(ByteMaskM[P.XLEN/8-1:0]), .WriteData(LSUWriteDataM[P.XLEN-1:0]),
        .Stall(GatedStallW), .BusStall(LSUBusStallM), .BusCommitted(BusCommittedM), .FetchBuffer(FetchBuffer));

    // Mux between the 2 sources of read data, 0: Bus, 1: DTIM
      if(P.DTIM_SUPPORTED) mux2 #(P.XLEN) ReadDataMux2(FetchBuffer, DTIMReadDataWordM[P.XLEN-1:0], SelDTIM, ReadDataWordMuxM[P.XLEN-1:0]);
      else assign ReadDataWordMuxM[P.XLEN-1:0] = FetchBuffer[P.XLEN-1:0];
      assign LSUHBURST = 3'b0;
      assign {DCacheStallM, DCacheCommittedM, DCacheMiss, DCacheAccess, DCacheReadDataWordM} = '0;
    end
  end else begin : nobus // block: bus, only DTIM
    assign {LSUHWDATA, LSUHADDR, LSUHWRITE, LSUHSIZE, LSUHBURST, LSUHTRANS, LSUHWSTRB} = '0;
    assign DCacheReadDataWordM = '0;
    assign ReadDataWordMuxM = DTIMReadDataWordM;
    assign {LSUBusStallM, BusCommittedM} = '0;
    assign {DCacheMiss, DCacheAccess} = '0;
    assign {DCacheStallM, DCacheCommittedM} = '0;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // SHARD store buffer
  /////////////////////////////////////////////////////////////////////////////////////////////

  // Classify the M-stage access.  A naturally aligned little-endian integer access maps
  // onto one store-queue entry / one merged read word.  Anything else (misaligned,
  // floating-point, big-endian, DTIM, cache-block operation, or a read of uncacheable
  // memory, which may have side effects) executes directly, on its own, once the shadow
  // has verified everything older and the store queue is empty.
  assign AlignedM = (Funct3M[1:0] == 2'b00) | ((Funct3M[1:0] == 2'b01) & ~IEUAdrM[0]) |
                    ((Funct3M[1:0] == 2'b10) & (IEUAdrM[1:0] == 2'b00)) |
                    ((Funct3M[1:0] == 2'b11) & (IEUAdrM[2:0] == 3'b000));
  assign SimpleMemOKM = AlignedM & ~FpLoadStoreM & ~BigEndianM & ~SelDTIM & ~(|CMOpM);
  assign SerialMemM = ((|MemRWM) & ~SimpleMemOKM) | (MemRWM[1] & ~CacheableM) | (|CMOpM);

  assign SQEmpty = (sqCount == '0);
  assign SQFull  = (sqCount == SQ_DEPTH[$clog2(SQ_DEPTH+1)-1:0]);
  assign ShadowQuiescentM = ShadowIdleM & SQEmpty & ~SQBusy;

  // A page table walk reads PTEs, and may write one, straight through the D-cache, so
  // it waits until no store is buffered.
  assign WalkOK = SQEmpty & ~SQBusy;

  // Hold the M-stage instruction (stall, and hide it from the cache and bus) while
  //  - it needs the shadow to be quiescent and it is not,
  //  - it is a store and the store queue is full, or
  //  - a page table walk is waiting for the store queue to empty, or
  //  - it failed a check and is about to be replayed.
  assign HoldM = ((NonMemSerialM | SerialMemM) & ~ShadowQuiescentM) | ShardPreFaultM |
                 (MemRWM[0] & SimpleMemOKM & SQFull) |
                 ((ITLBMissOrUpdateAF | DTLBMissOrUpdateDAM) & ~WalkOK);

  // Drain engine.  Modeled on the HPTW: it stalls the pipeline, takes over the LSU's
  // address/data/control inputs, and replays the head of the store queue as an ordinary
  // store (cache hit or miss, or an uncached bus write).
  //   IDLE     when the head is verified and no memory operation is in flight, hide the
  //            M-stage instruction and present the head's address so the cache reads
  //            its set (SQStart)
  //   WR       write; wait out a cache miss or the bus
  //   ADR      present the next head's address when several stores are drained in a row
  //   RESTORE  present the M-stage instruction's own address again so the cache holds
  //            the right set when that instruction resumes; skipped when it makes no
  //            cache access of its own
  assign SQStart = (SQState == SQ_IDLE) & (sqNVerified != '0) & ~CommittedM;
  assign SQRestoreM = MemRWM[1] | ((|MemRWM) & ~SimpleMemOKM) | (|CMOpM) | FlushDCacheM;
  always_comb
    case (SQState)
      SQ_IDLE:    SQNextState = SQStart ? SQ_WR : SQ_IDLE;
      SQ_ADR:     SQNextState = SQ_WR;
      SQ_WR:      if (DCacheBusStallM)      SQNextState = SQ_WR;
                  else if (sqNVerified > 1) SQNextState = SQ_ADR;
                  else if (SQRestoreM)      SQNextState = SQ_RESTORE;
                  else                      SQNextState = SQ_IDLE;
      default:    SQNextState = SQ_IDLE;
    endcase
  always_ff @(posedge clk)
    if (reset) SQState <= SQ_IDLE;
    else       SQState <= SQNextState;

  assign SQBusy     = (SQState != SQ_IDLE);
  assign SQOwnsLSUM = SQBusy | SQStart;
  assign SQDrainSel = SQStart | (SQState == SQ_ADR) | (SQState == SQ_WR);
  assign sqPop      = (SQState == SQ_WR) & ~DCacheBusStallM;

  assign ShardLSUStallM = HoldM | SQOwnsLSUM;
  assign ShardMaskM     = HoldM | SQOwnsLSUM;

  // Requests from the IEU or HPTW, overridden by the drain engine
  assign PreLSURWM    = SQDrainSel ? {1'b0, SQState == SQ_WR} : HPreLSURWM;
  assign LSUFunct3M   = SQDrainSel ? {1'b0, sqSize[0]} : HLSUFunct3M;
  assign LSUFunct7M   = SQDrainSel ? 7'b0 : HLSUFunct7M;
  assign LSUAtomicM   = SQDrainSel ? 2'b00 : HLSUAtomicM;
  assign LSUCMOpM     = SQDrainSel ? 4'b0 : HLSUCMOpM;
  assign IHAdrM       = SQDrainSel ? {{(P.XLEN+2-P.PA_BITS){1'b0}}, sqPA[0]} : HIHAdrM;
  assign IHWriteDataM = SQDrainSel ? sqData[0] : HIHWriteDataM;

  // The drained store passed its PMP/PMA checks when it executed
  assign LSULoadAccessFaultM     = MMULoadAccessFaultM & ~SQDrainSel;
  assign LSUStoreAmoAccessFaultM = MMUStoreAmoAccessFaultM & ~SQDrainSel;
  assign LSULoadPageFaultM       = MMULoadPageFaultM & ~SQDrainSel;
  assign LSUStoreAmoPageFaultM   = MMUStoreAmoPageFaultM & ~SQDrainSel;

  // The drain engine and the HPTW own the LSU while they are active.  Otherwise the
  // M-stage instruction is hidden from the cache and bus while it is held, and a queued
  // store, SC or AMO presents only its read half: just a direct (non-queued) access
  // writes memory from the Memory stage.
  always_comb
    if (SQDrainSel | SelHPTW) LSURWMaskedM = LSURWM;
    else if (ShardMaskM)      LSURWMaskedM = 2'b00;
    else                      LSURWMaskedM = {LSURWM[1], LSURWM[0] & ~SimpleMemOKM};

  // What the M-stage instruction pushes into the store queue when it leaves M (a failed
  // SC has LSURWM[0] low and pushes nothing)
  assign SQStoreM     = MemRWM[0] & SimpleMemOKM & LSURWM[0];
  assign SQPAdrM      = PAdrM;
  assign SQWriteDataM = IMAWriteDataM;

  // Store-to-load forwarding.  Accesses that cannot be merged only run with the queue
  // empty.  The merge sits in the main load path ahead of everything the shadow can
  // re-derive, so it is computed twice and the copies compared.
  shadow_sqmerge #(.P(P), .DEPTH(SQ_DEPTH)) sqmerge(.ReadDataWordM(ReadDataWordMuxM), .PAdrM,
    .sqPA, .sqSize, .sqData, .sqCount, .ReadDataWordFwdM);
  shadow_sqmerge #(.P(P), .DEPTH(SQ_DEPTH)) sqmergecheck(.ReadDataWordM(ReadDataWordMuxM), .PAdrM,
    .sqPA, .sqSize, .sqData, .sqCount, .ReadDataWordFwdM(ReadDataWordFwdCheckM));
  assign LoadFwdFaultM = MemRWM[1] & ~SQOwnsLSUM & (ReadDataWordFwdM != ReadDataWordFwdCheckM);

  // The shadow re-derives every integer load from this word with its own subword extract
  assign RawReadDataWordM = ReadDataWordFwdM[P.XLEN-1:0];

  // SHARD independent AMO verification.  A second, separate amoalu instance recomputes
  // the atomic result from the same operands the main amoalu used.  The shadow verifies
  // a queued AMO again from its own operands; this local check also covers an AMO that
  // writes memory directly, and stops a bad one before it leaves the Memory stage.
  if (P.ZAAMO_SUPPORTED) begin : shadow_amo
    logic [P.XLEN-1:0] ShadowAMOResultM;
    amoalu #(P) shadow_amoalu(.ReadDataM(ReadDataM[P.XLEN-1:0]), .IHWriteDataM,
                              .LSUFunct7M, .LSUFunct3M, .AMOResultM(ShadowAMOResultM));
    assign AMOFaultM = LSUAtomicM[1] & (ShadowAMOResultM != IMAWriteDataM);
  end else begin : no_shadow_amo
    assign AMOFaultM = 1'b0;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Atomic operations
  /////////////////////////////////////////////////////////////////////////////////////////////

  if (P.ZAAMO_SUPPORTED | P.ZALRSC_SUPPORTED) begin : atomic
    atomic #(P) atomic(.clk, .reset, .StallW, .ShardRedirectM, .ReadDataM(ReadDataM[P.XLEN-1:0]), .IHWriteDataM, .PAdrM,
      .LSUFunct7M, .LSUFunct3M, .LSUAtomicM, .PreLSURWM, .LSUFlushW,
      .IMAWriteDataM, .SquashSCW, .LSURWM);
  end else begin : lrsc
    assign SquashSCW = 1'b0;
    assign LSURWM = PreLSURWM;
    assign IMAWriteDataM = IHWriteDataM;
  end

  if (P.F_SUPPORTED)
    if (P.FLEN >= P.XLEN)
      mux2 #(P.LLEN) datamux({{{P.LLEN-P.XLEN}{1'b0}}, IMAWriteDataM}, FWriteDataM, FpLoadStoreM & ~SQDrainSel, IMAFWriteDataM);
    else
      mux2 #(P.LLEN) datamux(IMAWriteDataM, {{{P.XLEN-P.FLEN}{1'b0}}, FWriteDataM}, FpLoadStoreM & ~SQDrainSel, IMAFWriteDataM);

  else assign IMAFWriteDataM = IMAWriteDataM;

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Subword Accesses
  /////////////////////////////////////////////////////////////////////////////////////////////

  subwordread #(P) subwordread(.ReadDataWordMuxM(LittleEndianReadDataWordM), .PAdrM(PAdrM[3:0]), .BigEndianM,
    .FpLoadStoreM, .Funct3M(LSUFunct3M), .ReadDataM);
  subwordwrite #(P.LLEN) subwordwrite(.LSUFunct3M, .IMAFWriteDataM, .LittleEndianWriteDataM);

  // Compute byte masks
  swbytemask #(P.LLEN, P.ZICCLSM_SUPPORTED) swbytemask(.Size(LSUFunct3M), .Adr(PAdrM[$clog2(P.LLEN/8)-1:0]), .ByteMask(ByteMaskM), .ByteMaskExtended(ByteMaskExtendedM));

  /////////////////////////////////////////////////////////////////////////////////////////////
  // MW Pipeline Register
  /////////////////////////////////////////////////////////////////////////////////////////////

  flopen #(P.LLEN) ReadDataMWReg(clk, ~StallW, ReadDataM, ReadDataW);

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Big Endian Byte Swapper
  //  hart works little-endian internally
  //  swap the bytes when read from big-endian memory
  /////////////////////////////////////////////////////////////////////////////////////////////

  if (P.BIGENDIAN_SUPPORTED) begin : endian
    endianswap #(P.LLEN) storeswap(.BigEndianM, .a(LittleEndianWriteDataM), .y(LSUWriteDataM));
    endianswap #(P.LLEN) loadswap(.BigEndianM, .a(ReadDataWordFwdM), .y(LittleEndianReadDataWordM));
  end else begin
    assign LSUWriteDataM = LittleEndianWriteDataM;
    assign LittleEndianReadDataWordM = ReadDataWordFwdM;
  end
endmodule
