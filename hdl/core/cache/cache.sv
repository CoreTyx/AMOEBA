///////////////////////////////////////////
// cache.sv
//
// Written: Rose Thompson rose@rosethompson.net
// Created: 7 July 2021
// Modified: 20 January 2023
// Modified: SECDED ECC hardening + scrub support, 2026
//
// Purpose: Implements the I$ and D$. Interfaces with requests from IEU and HPTW and ahbcacheinterface
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

module cache import cvw::*; #(parameter cvw_t P,
                              parameter PA_BITS, LINELEN,  NUMSETS,  NUMWAYS, LOGBWPL, WORDLEN, MUXINTERVAL, READ_ONLY_CACHE,
                              parameter SCRUBBER_ENABLED = 1'b0,
                              parameter SCRUB_INTERVAL_CYCLES = 0,
                              parameter logic [FI_COUNT_BITS-1:0] FI_PHASE = '0) (  // this cache's event phase on the shared generator
  input  logic                   clk,
  input  logic                   reset,
  // Runtime fault injection (cachefi.sv): unit enables and the core's shared generator
  input  logic                   FaultInjectSec, FaultInjectDed,
  input  logic [15:0]            FaultLfsr,
  input  logic [FI_COUNT_BITS-1:0] FaultCount,
  input  logic                   Stall,             // Stall the cache, preventing new accesses. In-flight access finished but does not return to READY
  input  logic                   FlushStage,        // Pipeline flush of second stage (prevent writes and bus operations)
  input  logic                   InvalidateFlushStage, // Pipeline flush of second stage (prevent writes and bus operations)
  // cpu side
  input  logic [1:0]             CacheRW,           // [1] Read, [0] Write
  input  logic                   FlushCache,        // Flush all dirty lines back to memory
  input  logic                   InvalidateCache,   // Clear all valid bits
  input  logic [3:0]             CMOpM,              // 1: cbo.inval; 2: cbo.flush; 4: cbo.clean; 8: cbo.zero
  input  logic [11:0]            NextSet,           // Virtual address, but we only use the lower 12 bits.
  input  logic [PA_BITS-1:0]     PAdr,              // Physical address
  input  logic [(WORDLEN-1)/8:0] ByteMask,          // Which bytes to write (D$ only)
  input  logic [WORDLEN-1:0]     WriteData,    // Data to write to cache (D$ only)
  output logic                   CacheCommitted,    // Cache has started bus operation that shouldn't be interrupted
  output logic                   CacheStall,        // Cache stalls pipeline during multicycle operation
  output logic                   CacheBusy,         // CacheStall without the cycle a request is first seen (see cachefsm.sv)
  output logic [WORDLEN-1:0]     ReadDataWord,      // Word read from cache (goes to CPU and bus)
  output logic [WORDLEN-1:0]     AmoWord,           // The word an AMO operates on, from a register: the hit word, or the fetched one on a miss
  input  logic [$clog2(LINELEN/8)-1:0] AmoOffset,   // Where in the line that word is: PAdr's offset bits, from the instruction's own address register
  // to performance counters to cpu
  output logic                   CacheMiss,         // Cache miss
  output logic                   CacheAccess,       // Cache access
  output logic [2:0]             SecErr,            // Pulses: tag, line, and store-repaired line corrected this cycle
  output logic                   DedErr,            // Pulse: an uncorrectable line or tag was dropped or reported
  // lsu control
  input  logic                   SelHPTW,           // Use PAdr from Hardware Page Table Walker rather than NextSet
  // Bus fsm interface
  input  logic                   CacheBusAck,       // Bus operation completed
  input  logic                   SelBusBeat,        // Word in cache line comes from BeatCount
  input  logic [LOGBWPL-1:0]     BeatCount,         // Beat in burst
  input  logic [LINELEN-1:0]     FetchBuffer,       // Buffer long enough to hold entire cache line arriving from bus
  output logic [1:0]             CacheBusRW,        // [1] Read (cache line fetch) or [0] write bus (cache line writeback)
  output logic [PA_BITS-1:0]     CacheBusAdr,       // Address for bus access

  // Hardware-error escalation (D$ only): an uncorrectable data error was found on a dirty line, so
  // the only surviving copy of modified data can't simply be dropped. See cachefsm.sv/wallypipelinedcore.sv
  // for the trap path this feeds (its own cause, independent of the IEU regfile's ECC DED / cause 19).
  output logic                   EccDedDirtyFault,
  output logic [PA_BITS-1:0]     EccDedDirtyFaultAdr
);

  // Cache parameters
  localparam                     LINEBYTELEN = LINELEN/8;            // Line length in bytes
  localparam                     OFFSETLEN = $clog2(LINEBYTELEN);    // Number of bits in offset field
  localparam                     SETLEN = $clog2(NUMSETS);          // Number of set bits
  localparam                     SETTOP = SETLEN+OFFSETLEN;          // Number of set plus offset bits
  localparam                     TAGLEN = PA_BITS - SETTOP;          // Number of tag bits
  localparam                     LOGWAYS = $clog2(NUMWAYS);          // Number of bits in a way index (0 when direct mapped)
  localparam                     WAYBITS = (NUMWAYS > 1) ? LOGWAYS : 1; // ... as a signal width
`ifdef CACHE_TAG_ECC_DISABLED
  localparam                     TAG_ECC_SUPPORTED = 1'b0;
`else
  localparam                     TAG_ECC_SUPPORTED = 1'b1;
`endif

  // ECC sizing for the tag and line codewords: the smallest R such that 2^R >= dw+R+1, for the
  // encoders here and the decoders in cachearray.sv, which is given R.  (cacheeccbits/enc/dec take
  // R without a default on purpose: an R too small fails elaboration there instead of aliasing.)
  localparam int TAGCHECKR      = (TAGLEN <=    1) ?  2 :
                                   (TAGLEN <=    4) ?  3 :
                                   (TAGLEN <=   11) ?  4 :
                                   (TAGLEN <=   26) ?  5 :
                                   (TAGLEN <=   57) ?  6 :
                                   (TAGLEN <=  120) ?  7 :
                                   (TAGLEN <=  247) ?  8 :
                                   (TAGLEN <=  502) ?  9 :
                                   (TAGLEN <= 1013) ? 10 :
                                   (TAGLEN <= 2036) ? 11 :
                                   (TAGLEN <= 4083) ? 12 : 13;
  localparam int TAGCHECKWIDTH  = TAGCHECKR + 1;
  localparam int TAGSTOREWIDTH  = TAGLEN + (TAG_ECC_SUPPORTED ? TAGCHECKWIDTH : 0);
  localparam int LINECHECKR     = (LINELEN <=    1) ?  2 :
                                   (LINELEN <=    4) ?  3 :
                                   (LINELEN <=   11) ?  4 :
                                   (LINELEN <=   26) ?  5 :
                                   (LINELEN <=   57) ?  6 :
                                   (LINELEN <=  120) ?  7 :
                                   (LINELEN <=  247) ?  8 :
                                   (LINELEN <=  502) ?  9 :
                                   (LINELEN <= 1013) ? 10 :
                                   (LINELEN <= 2036) ? 11 :
                                   (LINELEN <= 4083) ? 12 : 13;
  localparam int LINECHECKWIDTH = LINECHECKR + 1;

  logic                          SelAdrData;
  logic                          SelAdrTag;
  logic [1:0]                    AdrSelMuxSelData;
  logic [1:0]                    AdrSelMuxSelTag;
  logic [SETLEN-1:0]             CacheSetDataDemand, CacheSetData;
  logic [SETLEN-1:0]             CacheSetTagDemand, CacheSetTag;
  logic [LINELEN-1:0]            LineWriteData;
  logic                          ClearDirty, SetDirty, SetValid, ClearValid;
  logic [NUMWAYS-1:0]            HitWayLive, DirtyWayLive;
  logic                          HitLive, LineDirtyLive;
  logic                          StoreRepairsData;
  logic                          CacheBusyFsm;
  logic [LINELEN-1:0]            LineEncodedData, LineCorrectionData, LineWriteMux, LineWriteFinal;
  logic [LINECHECKWIDTH-1:0]     LineEncodedCheck, LineCorrectionCheck, LineCheckWriteFinal;
  logic [NUMWAYS-1:0]            HitWay, ValidWay, ValidMismatchWay;
  logic                          Hit;
  logic [NUMWAYS-1:0]            VictimWay, DirtyWay, HitDirtyWay, DirtyMismatchWay;
  logic                          LineDirty, HitLineDirty;
  logic [TAGLEN-1:0]             Tag;
  logic [NUMWAYS-1:0]            TagSecErrWay, TagDedErrWay;
  logic [NUMWAYS-1:0]            TagDedDirtyWay;     // valid+dirty ways whose tag is uncorrectable
  logic                          TagDedDirty, DropTagDedDirty;
  logic                          EccDedLostLine;     // cachefsm: dirty line dropped on eviction/flush (uncorrectable data)
  logic                          EccDedCleanDrop;    // cachefsm: clean line dropped for an uncorrectable error
  logic                          LatchHitWord, SelHitWord;
  logic [WORDLEN-1:0]            ReadDataWordLine, HitWordQ;
  logic [SETLEN-1:0]             FlushAdr;
  logic [SETLEN-1:0]             FlushAdrCurr;      // the set being flushed (FlushAdr looks one ahead for the next read)
  logic                          FlushCntEn, FlushCntRst;
  logic                          FlushFlag;
  logic [NUMWAYS-1:0]            FlushWay;
  logic [WAYBITS-1:0]            FlushRowWay;       // way field of the flush line the arrays read (look-ahead, like FlushAdr)
  logic                          SelWriteback;
  logic                          LRUWriteEn;
  logic [LINELEN-1:0]            ReadDataLine;
  logic                          SelFetchBuffer;
  logic                          CacheEn;
  logic                          SelVictim;
  logic [$clog2(LINELEN/8) - $clog2(MUXINTERVAL/8) - 1:0] WordOffsetAddr;
  genvar                         index;

  // Scrubber / correction-writeback plumbing
  logic                          ScrubReq, ScrubGrant, ScrubBusy;
  logic                          ScrubOwnsWaySelect;
  logic [SETLEN-1:0]             ScrubSet;
  logic [NUMWAYS-1:0]            ScrubWay;
  logic [WAYBITS-1:0]            ScrubWayIdx;
  logic                          ScrubCorrectTag, ScrubCorrectData, ScrubInvalidate, ScrubTrap;
  logic                          TagSecErr, TagDedErr, DataSecErr, DataDedErr;
  logic                          SelCorrectTag, SelCorrectData;
  logic [TAGLEN-1:0]             CorrectedTagIn;
  logic [TAGSTOREWIDTH-1:0]      TagStoreWrite;
  logic [LINELEN-1:0]            CorrectedLine;
  logic                          DataSecErrQ, DataDedErrQ;

  // The arrays: every way in one tag macro and one data macro, read a way at a time
  logic [NUMWAYS-1:0]            SelectedWay;       // the way being read and written (one-hot, or none)
  logic [WAYBITS-1:0]            SelectedWayEnc, VictimWayEnc;
  logic [WAYBITS-1:0]            RowWay;            // the way the arrays access this cycle
  logic [WAYBITS-1:0]            ReadWayQ;          // the way whose row the arrays are returning
  logic                          TagReadQ;
  logic [NUMWAYS-1:0]            ArriveWay;         // one-hot ReadWayQ, when that row is a read
  logic                          TagMatchLive, TagSecErrLive, TagDedErrLive;
  logic                          TagWe, DataWe;
  logic                          ScanStart, ScanIssue, ScanArrive, ScanLast, RowIdle;

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Read Path
  /////////////////////////////////////////////////////////////////////////////////////////////

  // Choose read address (CacheSet).  Normally use NextSet, but use PAdr during stalls
  // and FlushAdr when handling D$ flushes
  // The icache must update to the newest PCNextF on flush as it is probably a trap.  Trap
  // sets PCNextF to XTVEC and the icache must start reading the instruction.
  assign AdrSelMuxSelData = {FlushCache, ((SelAdrData | SelHPTW) & ~((READ_ONLY_CACHE == 1) & FlushStage))};
  mux3 #(SETLEN) AdrSelMuxData(NextSet[SETTOP-1:OFFSETLEN], PAdr[SETTOP-1:OFFSETLEN], FlushAdr,
    AdrSelMuxSelData, CacheSetDataDemand);
  assign AdrSelMuxSelTag = {FlushCache, ((SelAdrTag | SelHPTW) & ~((READ_ONLY_CACHE == 1) & FlushStage))};
  mux3 #(SETLEN) AdrSelMuxTag(NextSet[SETTOP-1:OFFSETLEN], PAdr[SETTOP-1:OFFSETLEN], FlushAdr,
    AdrSelMuxSelTag, CacheSetTagDemand);

  // Scrubber takes the address bus on grant and retains it through decode, verification, and
  // commit; ScrubGrant never overlaps a real demand/flush/CMO/HPTW access.
  mux2 #(SETLEN) ScrubAdrMuxData(CacheSetDataDemand, ScrubSet, ScrubOwnsWaySelect, CacheSetData);
  mux2 #(SETLEN) ScrubAdrMuxTag(CacheSetTagDemand, ScrubSet, ScrubOwnsWaySelect, CacheSetTag);

  assign ScrubGrant = SCRUBBER_ENABLED & ScrubReq & ~(|CacheRW) & ~FlushCache & ~InvalidateCache & ~(|CMOpM) & ~SelHPTW & ~CacheStall;
  assign ScrubOwnsWaySelect = ScrubGrant | ScrubBusy;

  // The scrubber needs the array enabled throughout its operation, including cycles when cachefsm's
  // own CacheEn would be deasserted. LRU state, though, should only ever move for demand evictions.
  logic CacheEnArray;
  assign CacheEnArray = CacheEn | ScrubOwnsWaySelect;

  // Per-way state: valid, dirty, the way's lookup results, and way selection
  cacheway #(.NUMSETS(NUMSETS), .READ_ONLY_CACHE(READ_ONLY_CACHE)) CacheWays[NUMWAYS-1:0](
    .clk, .reset, .CacheEn(CacheEnArray), .CacheSetData, .CacheSetTag,
    .SetValid, .ClearValid, .ScrubInvalidate, .SetDirty, .ClearDirty, .VictimWay,
    .FlushWay, .FlushCache, .SelVictim,
    .SelScrub(ScrubOwnsWaySelect), .ScrubWay,
    .ArriveWay, .TagMatchLive, .TagSecErrLive, .TagDedErrLive, .ScanStart,
    .SelectedWay, .HitWay, .HitWayLive, .ValidWay, .ValidMismatch(ValidMismatchWay),
    .DirtyWay, .DirtyWayLive, .HitDirtyWay, .DirtyMismatch(DirtyMismatchWay),
    .TagSecErr(TagSecErrWay), .TagDedErr(TagDedErrWay),
    .TagDedDirtyWay, .DropTagDedDirty,
    .FlushStage, .InvalidateCache, .InvalidateFlushStage);

  // Select victim way for associative caches
  if (NUMWAYS > 1) begin : vict
    cacheLRU #(NUMWAYS, SETLEN, NUMSETS) cacheLRU(
      .clk, .reset, .CacheEn, .HitWay, .ValidWay, .VictimWay, .VictimWayEnc, .LRUWriteEn,
      .SetValid, .PAdr(PAdr[SETTOP-1:OFFSETLEN]), .InvalidateCache, .InvalidateFlushStage);
  end else begin : vict
    assign VictimWay = 1'b1; // one hot.
    assign VictimWayEnc = '0;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // The arrays (cachearray.sv).  Way w of set s is row w*NUMSETS + s of each macro.
  //
  // The way read: while no access is in flight, way 0, where a lookup starts.  During the lookup,
  // the way after the one arriving; after it, the selected way (hit, victim, flush or scrub way),
  // or with none selected -- a miss whose victim is not yet being written -- the victim, so that
  // the line about to be evicted is the one the arrays hold.  The way written is always the way
  // read: every array write is gated by a selected way.
  /////////////////////////////////////////////////////////////////////////////////////////////

  always_comb
    if (ScrubOwnsWaySelect)   RowWay = ScrubWayIdx;
    else if (FlushCache)      RowWay = FlushRowWay;
    else if (RowIdle)         RowWay = '0;
    else if (ScanIssue)       RowWay = ReadWayQ + 1'b1;
    else if (|SelectedWay)    RowWay = SelectedWayEnc;
    else                      RowWay = VictimWayEnc;

  if (NUMWAYS > 1) begin : wayindex
    logic [NUMWAYS-1:0] ReadWayOneHot;
    binencoder #(NUMWAYS) selwayenc(SelectedWay, SelectedWayEnc);
    decoder #(LOGWAYS) readwaydec(ReadWayQ, ReadWayOneHot);
    assign ArriveWay = ReadWayOneHot & {NUMWAYS{TagReadQ}};
  end else begin : wayindex
    assign SelectedWayEnc = '0;
    assign ArriveWay = TagReadQ;
  end
  assign ScanLast = (ReadWayQ == WAYBITS'(NUMWAYS-1));

  // A way's array writes are its valid/dirty writes (cacheway.sv) plus corrections, here for the
  // one selected way.
  assign TagWe  = (|SelectedWay) & ((SetValid & ~FlushStage) | (TAG_ECC_SUPPORTED & SelCorrectTag));
  assign DataWe = (|SelectedWay) & (((SetValid | SetDirty) & ~FlushStage) | SelCorrectData);

  cachearray #(.P(P), .NUMWAYS(NUMWAYS), .NUMSETS(NUMSETS), .TAGLEN(TAGLEN), .LINELEN(LINELEN),
               .TAGCHECKR(TAGCHECKR), .LINECHECKR(LINECHECKR), .TAG_ECC_SUPPORTED(TAG_ECC_SUPPORTED)) CacheArray(
    .clk, .reset, .CacheEn(CacheEnArray), .RowWay, .CacheSetTag, .CacheSetData, .TagWe, .DataWe,
    .TagStoreWrite, .LineWriteFinal, .LineCheckWriteFinal, .PAdrTag(PAdr[PA_BITS-1:SETTOP]), .ScanArrive,
    .ReadWayQ, .TagReadQ, .TagMatchLive, .TagSecErrLive, .TagDedErrLive,
    .Tag, .CorrectedLine, .DataSecErr(DataSecErrQ), .DataDedErr(DataDedErrQ));

  assign Hit = |HitWay;
  assign HitLineDirty = |HitDirtyWay;
  assign LineDirty = |DirtyWay;
  // For the decisions taken in the cycle the tags are read (see cacheway.sv).
  assign HitLive = |HitWayLive;
  assign LineDirtyLive = |DirtyWayLive;

  // Whichever way is currently selected -- the demand hit way, or (mutually exclusive in time,
  // never both meaningful at once) the scrubber's target way -- determines whose tag SEC/DED
  // status is live. Gated explicitly by ScrubOwnsWaySelect rather than OR'd blindly, since HitWay
  // can be nonzero for a stale/unrelated way while a scrub operation is active.
  logic [NUMWAYS-1:0] TagSelWay;
  assign TagSelWay = ScrubOwnsWaySelect ? ScrubWay : HitWay;
  assign TagSecErr = |(TagSecErrWay & TagSelWay);
  assign TagDedErr = |(TagDedErrWay & TagSelWay);
  logic ValidMismatch, DirtyMismatch;
  assign ValidMismatch = |(ValidMismatchWay & TagSelWay);
  assign DirtyMismatch = |(DirtyMismatchWay & TagSelWay);

  // The arrays return one way's row at a time, so CorrectedLine and Tag (cachearray.sv) are
  // already that way's.  A line's error flags count only while some way is selected: on a miss
  // with a clean victim no way is, and the arrays hold the victim's line although nothing will be
  // done with it.
  assign DataSecErr = DataSecErrQ & (|SelectedWay);
  assign DataDedErr = DataDedErrQ & (|SelectedWay);

  cachescrubber #(.NUMSETS(NUMSETS), .NUMWAYS(NUMWAYS), .SETLEN(SETLEN),
                  .READ_ONLY_CACHE(READ_ONLY_CACHE), .SCRUB_INTERVAL_CYCLES(SCRUB_INTERVAL_CYCLES)) scrubber (
    .clk, .reset, .ScrubReq, .ScrubGrant, .ScrubSet, .ScrubWay, .ScrubWayIdx,
    .ValidWay(|(ValidWay & ScrubWay)), .DirtyWay(|(DirtyWay & ScrubWay)),
    .TagSecErr, .TagDedErr, .DataSecErr, .DataDedErr,
    .ScrubCorrectTag, .ScrubCorrectData, .ScrubInvalidate, .ScrubTrap,
    .ScrubBusy);

  // The scrubber's ScrubBusy output only rises the cycle *after* it's granted (once CurrState
  // actually reaches its own decode states), but cachefsm decides whether to start a *new* demand
  // sequence using this same grant cycle's signals -- so a demand request arriving in the exact
  // cycle the scrubber is granted would race ScrubBusy's rising edge. ORing in the live ScrubGrant
  // pulse itself closes that gap: cachefsm treats "about to become busy" the same as "already busy."
  // Data cache needs to choose word offset from PAdr or BeatCount to writeback dirty lines
  if (!READ_ONLY_CACHE)
    mux2 #(LOGBWPL) WordAdrrMux(.d0(PAdr[$clog2(LINELEN/8) - 1 : $clog2(MUXINTERVAL/8)]),
      .d1(BeatCount), .s(SelBusBeat),
      .y(WordOffsetAddr));
  else
    assign WordOffsetAddr = PAdr[$clog2(LINELEN/8) - 1 : $clog2(MUXINTERVAL/8)];

  // Bypass cache array to save a cycle when finishing a load miss
  // Everything leaving the cache from the arrays -- load data to the core and eviction/flush
  // writeback data to the bus -- takes the ECC-corrected line, so a latent single-bit error is never
  // handed out or written to (unprotected) memory.
  mux2 #(LINELEN) EarlyReturnMux(CorrectedLine, FetchBuffer, SelFetchBuffer, ReadDataLine);

  // A dirty line with an uncorrectable tag can't be written back (its address is lost). A lookup
  // that reads it (the way arriving), or a flush reaching it, reports it and drops it; cacheway.sv
  // already keeps it out of DirtyWay so it is never written back to a wrong address.
  assign TagDedDirty = FlushCache ? |(TagDedDirtyWay & FlushWay) : |TagDedDirtyWay;

  // Select word from cache line
  subcachelineread #(LINELEN, WORDLEN, MUXINTERVAL) subcachelineread(
    .PAdr(WordOffsetAddr), .ReadDataLine, .ReadDataWord(ReadDataWordLine));

  // Hit read data is captured before that access's own write (see cachefsm.sv HitReturn): otherwise
  // a store/AMO hit would return the post-write word, and AMOs would hand back their own result.
  flopen #(WORDLEN) HitWordReg(clk, LatchHitWord, ReadDataWordLine, HitWordQ);
  mux2 #(WORDLEN) HitWordMux(ReadDataWordLine, HitWordQ, SelHitWord, ReadDataWord);

  // The AMO's operand.  An AMO hit writes in STATE_AMO_WRITE, when HitWordQ holds the word it
  // read; an AMO miss writes with the refill (STATE_WRITE_LINE), from the fetch buffer.  Either
  // way the operand starts at a register and does not come through ReadDataWord, so the AMO
  // ALU is not on a path from the arrays or from the bus-beat word select.
  // The word of the fetch buffer is picked with AmoOffset and not with PAdr: for an AMO they are
  // the same bits (the offset within a line is inside the page offset), but PAdr arrives through
  // the page walker's address mux and AmoOffset comes straight from a register.
  logic [WORDLEN-1:0] FetchBufferWord;
  subcachelineread #(LINELEN, WORDLEN, MUXINTERVAL) fetchbufferwordread(
    .PAdr(AmoOffset[$clog2(LINELEN/8) - 1 : $clog2(MUXINTERVAL/8)]), .ReadDataLine(FetchBuffer), .ReadDataWord(FetchBufferWord));
  mux2 #(WORDLEN) AmoWordMux(HitWordQ, FetchBufferWord, SelFetchBuffer, AmoWord);

  // Bus address for fetch, writeback, or flush writeback
  mux3 #(PA_BITS) CacheBusAdrMux(.d0({PAdr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}),
    .d1({Tag, PAdr[SETTOP-1:OFFSETLEN], {OFFSETLEN{1'b0}}}),
    .d2({Tag, FlushAdrCurr, {OFFSETLEN{1'b0}}}),
    .s({FlushCache, SelWriteback}), .y(CacheBusAdr));

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Write Path
  /////////////////////////////////////////////////////////////////////////////////////////////
  if (!READ_ONLY_CACHE) begin : WriteSelLogic
    logic [LINELEN/8-1:0]          DemuxedByteMask, FetchBufferByteSel;

    // Adjust byte mask from word to cache line
    logic [LINELEN/8-1:0]          BlankByteMask;
    assign BlankByteMask[WORDLEN/8-1:0] = ByteMask;
    assign BlankByteMask[LINELEN/8-1:WORDLEN/8] = 0;

    assign DemuxedByteMask = BlankByteMask << ((MUXINTERVAL/8) * WordOffsetAddr);

    assign FetchBufferByteSel = SetDirty ? ~DemuxedByteMask : '1;  // If load miss set all muxes to 1.

    // A store hit merges against the corrected resident line. During a miss refill, including a
    // store miss, the new line must instead be based on FetchBuffer rather than the victim line.
    for (index = 0; index < LINELEN/8; index++) begin
      mux2 #(8) WriteDataMux(.d0(WriteData[(8*index)%WORDLEN+7:(8*index)%WORDLEN]),
        .d1((SetDirty & ~SelFetchBuffer) ? CorrectedLine[8*index+7:8*index] : FetchBuffer[8*index+7:8*index]),
        .s(FetchBufferByteSel[index] & ~CMOpM[3]), .y(LineWriteData[8*index+7:8*index]));
    end
  end else begin : WriteSelLogic
    // No need for this mux if the cache does not handle writes.
    assign LineWriteData = FetchBuffer;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Line encode
  //
  // What is written to the data array is either new data (LineWriteData) or the corrected copy
  // of the line that was read (a correction writeback).  Both are the same for every way -- the
  // way is chosen by the write enable -- so they are encoded once here.  Each way used to carry
  // its own copy of both encoders.
  /////////////////////////////////////////////////////////////////////////////////////////////
  cacheeccenc #(.DATA_WIDTH(LINELEN), .R(LINECHECKR)) dataenc (
    .data_i     (LineWriteData),
    .codeword_o ({LineEncodedData, LineEncodedCheck})
  );
  cacheeccenc #(.DATA_WIDTH(LINELEN), .R(LINECHECKR)) datacorrectionenc (
    .data_i     (CorrectedLine),
    .codeword_o ({LineCorrectionData, LineCorrectionCheck})
  );
  mux2 #(LINELEN) linedinmux(LineEncodedData, LineCorrectionData, SelCorrectData, LineWriteMux);
  mux2 #(LINECHECKWIDTH) linecheckdinmux(LineEncodedCheck, LineCorrectionCheck, SelCorrectData, LineCheckWriteFinal);

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Fault injection: flips armed by cachefi land in the next tag and line written, after encode
  /////////////////////////////////////////////////////////////////////////////////////////////
  logic [TAGLEN-1:0]             TagFlip;
  logic [LINELEN-1:0]            LineFlip;
  cachefi #(.TAGLEN(TAGLEN), .TAGR(TAGCHECKR), .LINELEN(LINELEN), .LINER(LINECHECKR), .PHASE(FI_PHASE)) faultinject(
    .clk, .reset, .FaultInjectSec, .FaultInjectDed, .FaultLfsr, .FaultCount,
    .TagWrite((SetValid & ~FlushStage) | SelCorrectTag),
    .LineWrite(((SetValid | SetDirty) & ~FlushStage) | SelCorrectData),
    .TagFlip, .LineFlip);
  assign LineWriteFinal = LineWriteMux ^ LineFlip;

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Tag encode
  //
  // The same holds for the tag array: what is written is either the new line's tag (from PAdr)
  // or the corrected copy of the tag that was read (CorrectedTagIn), the same for every way, so
  // the word is built once here.  Each way used to carry its own copy of both encoders.
  /////////////////////////////////////////////////////////////////////////////////////////////
  if (TAG_ECC_SUPPORTED) begin : tagwrite
    logic [TAGLEN-1:0]        TagEncodedData, TagCorrectionData, TagWriteData;
    logic [TAGCHECKWIDTH-1:0] TagEncodedCheck, TagCorrectionCheck, TagCheckWriteData;

    cacheeccenc #(.DATA_WIDTH(TAGLEN), .R(TAGCHECKR)) tagenc (
      .data_i     (PAdr[PA_BITS-1:SETTOP]),
      .codeword_o ({TagEncodedData, TagEncodedCheck})
    );
    cacheeccenc #(.DATA_WIDTH(TAGLEN), .R(TAGCHECKR)) tagcorrectionenc (
      .data_i     (CorrectedTagIn),
      .codeword_o ({TagCorrectionData, TagCorrectionCheck})
    );
    mux2 #(TAGLEN) tagdinmux(TagEncodedData, TagCorrectionData, SelCorrectTag, TagWriteData);
    mux2 #(TAGCHECKWIDTH) tagcheckdinmux(TagEncodedCheck, TagCorrectionCheck, SelCorrectTag, TagCheckWriteData);
    assign TagStoreWrite = {TagWriteData ^ TagFlip, TagCheckWriteData};
  end else begin : tagwrite                      // no tag ECC: nothing to inject into
    assign TagStoreWrite = PAdr[PA_BITS-1:SETTOP];
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Flush logic
  /////////////////////////////////////////////////////////////////////////////////////////////

  if (!READ_ONLY_CACHE) begin : flushlogic // D$ can be flushed
    // One counter walks every line, {set, way}: through the ways of a set, then on to the next
    // set.  It is read look-ahead: the arrays read the next line in the cycle the counter is told
    // to advance, a decision that comes from the tags as they are read.  So the line being flushed
    // -- its way select and the set on the bus address -- comes from the counter itself.
    localparam int ROWBITS = SETLEN + LOGWAYS;
    logic [ROWBITS-1:0]            FlushRow, FlushRowP1, FlushRowRead;

    flopenr #(ROWBITS) FlushRowReg(clk, reset | FlushCntRst, FlushCntEn, FlushRowP1, FlushRow);
    assign FlushRowP1 = FlushRow + 1'b1;
    mux2    #(ROWBITS) FlushRowMux(FlushRow, FlushRowP1, FlushCntEn, FlushRowRead);
    assign FlushFlag = &FlushRow;                       // last way of the last set

    assign FlushAdr = FlushRowRead[ROWBITS-1 -: SETLEN];
    assign FlushAdrCurr = FlushRow[ROWBITS-1 -: SETLEN];
    if (NUMWAYS > 1) begin : flushway
      assign FlushRowWay = FlushRowRead[LOGWAYS-1:0];
      decoder #(LOGWAYS) flushwaydec(FlushRow[LOGWAYS-1:0], FlushWay);
    end else begin : flushway
      assign FlushRowWay = '0;
      assign FlushWay = 1'b1;
    end
  end // block: flushlogic
  else begin : flushlogic // I$ is never flushed because it is never dirty
    assign FlushWay = '0;
    assign FlushRowWay = '0;
    assign FlushFlag = 1'b0;
    assign FlushAdr = '0;
    assign FlushAdrCurr = '0;
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Correction writeback routing: whichever of the demand path (cachefsm, on the hit way) or the
  // scrubber (on ScrubWay) is asking, drive the same SelCorrectTag/SelCorrectData/CorrectedTagIn
  // into the way array. Mutually exclusive by construction (ScrubGrant never overlaps a demand
  // access in progress).
  /////////////////////////////////////////////////////////////////////////////////////////////

  logic SelCorrectTagDemand, SelCorrectDataDemand;
  logic                          EccDedDirtyFaultDemand;
  logic [PA_BITS-1:0]             ScrubFaultAdr;
  assign SelCorrectTag = SelCorrectTagDemand | ScrubCorrectTag;
  assign SelCorrectData = SelCorrectDataDemand | ScrubCorrectData;
  assign CorrectedTagIn = Tag; // the corrected tag of the row the arrays hold: the selected way's (demand hit way, or scrub target)

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Cache FSM
  /////////////////////////////////////////////////////////////////////////////////////////////

  cachefsm #(READ_ONLY_CACHE) cachefsm(.clk, .reset, .CacheBusRW, .CacheBusAck,
    .FlushStage, .InvalidateFlushStage, .CacheRW, .Stall,
    .Hit, .LineDirty, .HitLineDirty, .CacheStall, .CacheBusy(CacheBusyFsm), .CacheCommitted,
    .CacheMiss, .CacheAccess, .SelAdrData, .SelAdrTag, .SelVictim,
    .ClearDirty, .SetDirty, .SetValid, .ClearValid, .SelWriteback,
    .FlushCntEn, .FlushCntRst,
    .FlushFlag, .FlushCache, .SelFetchBuffer,
    .InvalidateCache, .CMOpM, .CacheEn, .LRUWriteEn,
    .TagSecErr, .TagDedErr, .DataSecErr, .DataDedErr, .HitDirty(HitLineDirty),
    .HitLive, .LineDirtyLive, .StoreRepairsData,
    .ScanLast, .ScanStart, .ScanIssue, .ScanArrive, .RowIdle,
    .ScrubOwnsWaySelect,
    .SelCorrectTag(SelCorrectTagDemand), .SelCorrectData(SelCorrectDataDemand),
    .TagDedDirty, .DropTagDedDirty, .EccDedLostLine, .EccDedCleanDrop, .LatchHitWord, .SelHitWord,
    .EccDedDirtyFault(EccDedDirtyFaultDemand));

  assign EccDedDirtyFault = EccDedDirtyFaultDemand | ScrubTrap;
  // While the scrubber has the arrays a demand request waits in ACCESS, so the cache is busy
  // then too.  (ScrubBusy is scrubber state; its grant cycle needs no cover, because a grant
  // requires that there be no request.)
  assign CacheBusy = CacheBusyFsm | ScrubBusy;
  assign ScrubFaultAdr = {Tag, ScrubSet, {OFFSETLEN{1'b0}}};
  // For a line dropped on eviction/flush, report that line's own address (the selected way's tag is
  // the victim's or flush way's), not the access that caused the eviction.
  logic [PA_BITS-1:0]            LostLineAdr;
  assign LostLineAdr = FlushCache ? {Tag, FlushAdrCurr, {OFFSETLEN{1'b0}}} : {Tag, PAdr[SETTOP-1:OFFSETLEN], {OFFSETLEN{1'b0}}};
  assign EccDedDirtyFaultAdr = ScrubTrap ? ScrubFaultAdr : EccDedLostLine ? LostLineAdr : PAdr;

  // Fault flags for the counters (faultcount_apb), demand and scrubber alike
  assign SecErr = {StoreRepairsData, SelCorrectData, SelCorrectTag};
  assign DedErr = EccDedCleanDrop | EccDedDirtyFault | ScrubInvalidate;

endmodule
