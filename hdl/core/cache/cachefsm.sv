///////////////////////////////////////////
// cachefsm.sv
//
// Written: Rose Thompson rose@rosethompson.net
// Created: 25 August 2021
// Modified: 20 January 2023
// Modified: SECDED ECC hardening (decode-wait states, correction/trap branching), 2026
//
// Purpose: Controller for the cache fsm
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

module cachefsm #(parameter logic READ_ONLY_CACHE = 1'b0) (
  input  logic       clk,
  input  logic       reset,
  // hazard and privilege unit
  input  logic       Stall,             // Stall the cache, preventing new accesses. In-flight access finished but does not return to READY
  input  logic       FlushStage,        // Pipeline flush of second stage (prevent writes and bus operations)
  input  logic       InvalidateFlushStage, // Pipeline flush of second stage (prevent writes and bus operations)
  output logic       CacheCommitted,    // Cache has started bus operation that shouldn't be interrupted
  output logic       CacheBusy,         // CacheStall without the cycle the request is first seen (see below)
  output logic       CacheStall,        // Cache stalls pipeline during multicycle operation
  // inputs from IEU
  input  logic [1:0] CacheRW,           // [1] Read, [0] Write
  input  logic       FlushCache,        // Flush all dirty lines back to memory
  input  logic       InvalidateCache,   // Clear all valid bits
  input  logic [3:0] CMOpM,             // 0001: cbo.inval; 0010: cbo.flush; 0100: cbo.clean; 1000: cbo.zero
  // Bus controls
  input  logic       CacheBusAck,       // Bus operation completed
  output logic [1:0] CacheBusRW,        // [1] Read (cache line fetch) or [0] write bus (cache line writeback)
  // performance counter outputs
  output logic       CacheMiss,         // Cache miss
  output logic       CacheAccess,       // Cache access

  // cache internals
  input  logic       Hit,          // Exactly 1 way hits
  input  logic       LineDirty,         // The selected line and way is dirty
  input  logic       HitLineDirty,   // The cache hit way is dirty
  input  logic       FlushFlag,         // On the last line (set and way) of a cache flush
  output logic       SelAdrData,            // [0] SRAM reads from NextAdr, [1] SRAM reads from PAdr
  output logic       SelAdrTag,            // [0] SRAM reads from NextAdr, [1] SRAM reads from PAdr
  output logic       SetValid,          // Set the valid bit in the selected way and set
  output logic       ClearValid,        // Clear the valid bit in the selected way and set
  output logic       SetDirty,          // Set the dirty bit in the selected way and set
  output logic       ClearDirty,        // Clear the dirty bit in the selected way and set
  output logic       SelWriteback,      // Overrides cached tag check to select a specific way and set for writeback
  output logic       LRUWriteEn,        // Update the LRU state
  output logic       SelVictim,         // Overrides HitWay Tag matching.  Selects selects the victim tag/data regardless of hit
  output logic       FlushCntEn,        // Advance the flush counter to the next line
  output logic       FlushCntRst,       // Reset the flush counter
  output logic       SelFetchBuffer,    // Bypass the SRAM for a load hit by directly using the read data from the ahbcacheinterface's FetchBuffer
  output logic       CacheEn,           // Enable the cache memory arrays.  Disable hold read data constant

  // SECDED ECC
  input  logic       TagSecErr,         // Selected way's tag codeword has a correctable error
  input  logic       TagDedErr,         // Selected way's tag codeword has an uncorrectable error (never true when Hit -- see cacheway.sv HitWay)
  input  logic       DataSecErr,        // Selected way's data codeword has a correctable error
  input  logic       DataDedErr,        // Selected way's data codeword has an uncorrectable error
  input  logic       HitDirty,          // Hit way is dirty (D$ only; tied 0 for I$)
  // Hit, LineDirty and the four error flags above are registered decode results, valid from the
  // cycle after the arrays present them.  These two are the same quantities in the cycle the tags
  // are read, for the two places that act in that cycle: ending the scan on a hit, and the flush
  // walk.
  input  logic       HitLive,
  input  logic       LineDirtyLive,
  // The lookup reads one way per cycle (cachearray.sv).  ScanLast: the way arriving is the last.
  input  logic       ScanLast,
  output logic       ScanStart,         // A lookup starts: issue way 0 and forget the last lookup's results
  output logic       ScanIssue,         // Read the way after the one arriving
  output logic       ScanArrive,        // A way of the lookup is arriving: keep its row
  output logic       RowIdle,           // No access in flight: read way 0, where a lookup starts
  output logic       StoreRepairsData,  // This cycle's store-hit write also repairs a correctable error in the line: write all of it
  input  logic       TagDedDirty,       // A valid+dirty way in the set being read (the flush way, during a flush) has an uncorrectable tag
  output logic       DropTagDedDirty,   // Pulse: invalidate that way -- its data can't be written back without an address
  output logic       EccDedLostLine,    // Pulse: a dirty line leaving the cache (eviction or flush) had uncorrectable data; it was dropped, not written back
  output logic       EccDedCleanDrop,   // Pulse: an access found an uncorrectable error in a clean line (or its tag) and dropped it
  output logic       LatchHitWord,      // Capture the word the core will read, before a store/AMO hit's write lands
  output logic       SelHitWord,        // Return that captured word (ADDRESS_SETUP after a hit) instead of re-reading the array
  input  logic       ScrubOwnsWaySelect, // The scrubber has an operation in flight (or is being granted this cycle) that needs way-selection state a new demand sequence would otherwise contend for -- hold off starting one until it clears (see cache.sv)
  output logic       SelCorrectTag,     // Pulse: commit a re-encoded tag correction into the hit way
  output logic       SelCorrectData,    // Pulse: commit a re-encoded data correction into the hit way
  output logic       EccDedDirtyFault   // Pulse: D$ only, uncorrectable data error on a dirty line -- escalate, do not invalidate
);

  logic              resetDelay;
  logic              AnyUpdateHit, AnyHit;
  logic              AnyMiss;
  logic              CMOWriteback;
  logic              CMOZeroNoEviction;
  logic              StallConditions;
  logic              FillBufferReturn;
  logic              HitReturn;         // this ADDRESS_SETUP completes a hit (directly or via ECC_WRITEBACK)
  logic              VictimDed;         // DATA_DECODE: the dirty victim of this miss has uncorrectable data
  logic              EvictDirty;        // dirty victim that must actually be written back (LineDirty minus VictimDed)
  logic              FlushDedHit;       // FLUSH_WRITEBACK, first cycle: the flushed line has uncorrectable data -- report and invalidate it, no bus write
  logic              FlushSkipQ;        // the cycle after FlushDedHit: finish the skipped writeback (advance the flush counters)
  logic              FlushWbDone;       // flush writeback finished: bus ack, or skipped

  typedef enum logic [3:0]{STATE_ACCESS, // hit states
                           STATE_TAG_SCAN,      // one way's tag and line arrive per cycle; ends on a hit or after the last way
                           STATE_VICTIM_READ,   // miss: the victim's row, read as the scan ended, arrives
                           STATE_DATA_DECODE,   // ECC: data decode result available this cycle; branch point
                           STATE_AMO_WRITE,     // an AMO hit writes its result here, the cycle after its operand was captured
                           STATE_ECC_WRITEBACK, // ECC: commit a correctable-error fix before completing
                           STATE_DED_TRAP,       // ECC: D$ dirty line, uncorrectable -- pulse the fault, hold state
                           // miss states
                           STATE_FETCH,
                           STATE_WRITEBACK,
                           STATE_WRITE_LINE,
                           STATE_ADDRESS_SETUP,  // required for back to back reads. structural hazard on writing SRAM
                           // flush cache
                           STATE_FLUSH,
                           STATE_FLUSH_WRITEBACK
                           } statetype;

  statetype CurrState, NextState;

  // The request as it stood when the access left STATE_ACCESS.  It does not change while the
  // access is in flight, and it arrives late (whether an address is cacheable comes out of the
  // MMU), so every state after ACCESS uses this copy.  ACCESS itself has to use the live one.
  logic [1:0] CacheRWQ;
  flopen #(2) cacherwreg(clk, CurrState == STATE_ACCESS, CacheRW, CacheRWQ);

  // AnyMiss/AnyUpdateHit/AnyHit/CMOWriteback/CMOZeroNoEviction are evaluated once the array read
  // that STATE_ACCESS issued has been decoded (during STATE_DATA_DECODE), using the corrected
  // Hit/LineDirty/HitLineDirty that already reflect ECC-corrected values by construction (the
  // decoders sit unconditionally in front of these signals in cache.sv, not gated by "is this an
  // ordinary load/store" -- so CMO/flush writebacks also see corrected data for free).
  assign AnyMiss = (CacheRWQ[0] | CacheRWQ[1]) & ~Hit & ~InvalidateCache; // exclusion-tag: cache AnyMiss
  assign AnyUpdateHit = (CacheRWQ[0]) & Hit;        // exclusion-tag: icache storeAMO1
  assign AnyHit = AnyUpdateHit | (CacheRWQ[1] & Hit); // exclusion-tag: icache AnyUpdateHit
  // cbo.zero zeros a hit line where it is.  A miss takes the victim's place, writing the victim
  // back first if it is dirty.  (A hit used to be treated like a miss whenever the victim was
  // dirty: the victim was written back and refilled with zeros, leaving the line in two ways.)
  assign CMOZeroNoEviction = CMOpM[3] & (Hit | ~LineDirty);   // store zeros now
  assign CMOWriteback = ((CMOpM[1] | CMOpM[2]) & Hit & HitLineDirty) | CMOpM[3] & ~Hit & LineDirty;

  logic UpdateHitWrite, WroteLineQ, AmoHit;
  // The line write a store, AMO or cbo.zero hit makes in DATA_DECODE.  It writes the corrected
  // line with the new data merged in, so if that line had a correctable error the write is also
  // the repair; ECC_WRITEBACK must then not write the pre-store line back over it.
  // An AMO reads and writes: CacheRW is 2'b11.  Its write data is computed from the word it
  // read, so the write waits one state for that word to be in a register (HitWordQ); done in
  // DATA_DECODE, the word went from the line register through the AMO ALU, the merge and the
  // encoder into the arrays in a single cycle.
  assign AmoHit = AnyUpdateHit & CacheRWQ[1];
  assign UpdateHitWrite = ((CurrState == STATE_DATA_DECODE) & ((AnyUpdateHit & ~CacheRWQ[1]) | CMOZeroNoEviction) & ~TagDedErr & ~(DataDedErr & Hit)) |
                          (CurrState == STATE_AMO_WRITE);
  assign StoreRepairsData = UpdateHitWrite & DataSecErr & Hit;
  always_ff @(posedge clk)
    if (reset | FlushStage) WroteLineQ <= 1'b0;
    else if ((CurrState == STATE_DATA_DECODE) | (CurrState == STATE_AMO_WRITE)) WroteLineQ <= UpdateHitWrite;

  // outputs for the performance counters. CacheAccess/CacheMiss now fire out of STATE_DATA_DECODE
  // (where the hit/miss decision is actually made) instead of STATE_ACCESS. STATE_ACCESS only ever
  // advances to STATE_TAG_SCAN on a real request (see the state-transition case below), so
  // reaching STATE_DATA_DECODE at all already implies a real, non-flushed access is in flight.
  assign CacheAccess = (|CacheRWQ) & ((CurrState == STATE_DATA_DECODE) | (CurrState == STATE_ADDRESS_SETUP & ~Stall & ~FlushStage)); // exclusion-tag: icache CacheW
  assign CacheMiss = CurrState == STATE_ADDRESS_SETUP & ~Stall & ~FlushStage;

  // special case on reset. When the fsm first exists reset twayhe
  // PCNextF will no longer be pointing to the correct address.
  // But PCF will be the reset vector.
  flop #(1) resetDelayReg(.clk, .d(reset), .q(resetDelay));

  always_ff @(posedge clk)
    if (reset | FlushStage)    CurrState <= STATE_ACCESS;
    else CurrState <= NextState;

  always_ff @(posedge clk)
    if (reset | FlushStage) FillBufferReturn <= 1'b0;
    else if (CurrState == STATE_WRITE_LINE) FillBufferReturn <= 1'b1;
    else if (CurrState == STATE_ADDRESS_SETUP & ~Stall) FillBufferReturn <= 1'b0;

  // A hit's read data must be the line as it was BEFORE that access's own write. The write (store,
  // AMO) lands at the end of DATA_DECODE, but the core only samples read data in ADDRESS_SETUP, by
  // which point the array already returns the new contents -- so an AMO would hand back its own
  // result instead of the old value. The word is latched in DATA_DECODE and returned from there.
  always_ff @(posedge clk)
    if (reset | FlushStage) HitReturn <= 1'b0;
    else if (CurrState == STATE_DATA_DECODE)
      HitReturn <= AnyHit & ((NextState == STATE_ADDRESS_SETUP) | (NextState == STATE_ECC_WRITEBACK) | (NextState == STATE_AMO_WRITE));
    else if (CurrState == STATE_ECC_WRITEBACK) HitReturn <= HitReturn;
    else if (CurrState == STATE_AMO_WRITE) HitReturn <= HitReturn;
    else if (CurrState == STATE_ADDRESS_SETUP & Stall) HitReturn <= HitReturn;
    else HitReturn <= 1'b0;
  assign LatchHitWord = (CurrState == STATE_DATA_DECODE);
  assign SelHitWord   = (CurrState == STATE_ADDRESS_SETUP) & HitReturn;

  always_comb begin
    NextState = STATE_ACCESS;
    case (CurrState)                                                                                        // exclusion-tag: icache state-case
      STATE_ACCESS:          if(InvalidateCache & ~InvalidateFlushStage)                        NextState = STATE_ACCESS;     // exclusion-tag: dcache InvalidateCheck
                             else if(FlushCache & ~READ_ONLY_CACHE & ~ScrubOwnsWaySelect) NextState = STATE_FLUSH;     // exclusion-tag: icache FLUSHStatement
                             else if((CacheRW[0] | CacheRW[1] | (|CMOpM)) & ~InvalidateCache & ~ScrubOwnsWaySelect) NextState = STATE_TAG_SCAN; // any real request: look it up (held off while the scrubber owns way-selection state, see cache.sv)
                             else                                              NextState = STATE_ACCESS;
      STATE_TAG_SCAN:        if(TagDedDirty & ~READ_ONLY_CACHE)               NextState = STATE_DED_TRAP;    // a dirty line in this set lost its tag: report and drop it, then retry the access
                             else if(HitLive)                                  NextState = STATE_DATA_DECODE; // this way hits; its line arrived with its tag
                             else if(ScanLast)                                 NextState = STATE_VICTIM_READ; // miss: the victim's row was read this cycle
                             else                                              NextState = STATE_TAG_SCAN;
      STATE_VICTIM_READ:                                                       NextState = STATE_DATA_DECODE;
      STATE_DATA_DECODE:      if(TagDedErr | (DataDedErr & Hit & ~(HitDirty & ~READ_ONLY_CACHE)))
                                                                                NextState = STATE_FETCH;      // uncorrectable, but safe to discard: refetch. (TagDedErr never coincides with Hit -- see cacheway.sv -- so this always proceeds as a normal compulsory miss.)
                             else if(DataDedErr & Hit & HitDirty & ~READ_ONLY_CACHE)
                                                                                NextState = STATE_DED_TRAP;   // uncorrectable AND the only copy of modified data -- cannot discard
                             else if(AmoHit)                                   NextState = STATE_AMO_WRITE;     // the word just read is the AMO's operand; it is in HitWordQ next cycle
                             else if((TagSecErr | DataSecErr) & Hit)           NextState = STATE_ECC_WRITEBACK; // correctable: fix durably before completing
                             else if(AnyMiss & (READ_ONLY_CACHE | ~EvictDirty)) NextState = STATE_FETCH;    // exclusion-tag: icache FETCHStatement (an uncorrectable dirty victim is dropped, not written back)
                             else if((AnyMiss | CMOWriteback) & ~READ_ONLY_CACHE) NextState = STATE_WRITEBACK; // exclusion-tag: icache WRITEBACKStatement
                             else if((|CMOpM) & ~CMOWriteback)               NextState = STATE_ADDRESS_SETUP; // any CMO without dirty writeback: stall and re-read SRAM next cycle
                             else                                              NextState = STATE_ADDRESS_SETUP; // ordinary hit: release CacheStall for one cycle (like every other completion path) before re-checking CacheRWQ in STATE_ACCESS, so a caller holding CacheRWQ constant until it sees CacheStall drop doesn't get misread as a brand-new request
      STATE_AMO_WRITE:       if((TagSecErr | DataSecErr) & Hit)                NextState = STATE_ECC_WRITEBACK; // as from DATA_DECODE
                             else                                              NextState = STATE_ADDRESS_SETUP;
      STATE_ECC_WRITEBACK:                                                    NextState = STATE_ADDRESS_SETUP; // structural hazard on the SRAM write, same as STATE_WRITE_LINE
      STATE_DED_TRAP:                                                         NextState = STATE_ADDRESS_SETUP; // one-cycle pulse, then resume (re-reads SRAM; the fault is latched externally)
      STATE_FETCH:           if(CacheBusAck)                                   NextState = STATE_WRITE_LINE;
                             else                                              NextState = STATE_FETCH;
      STATE_WRITE_LINE:                                                        NextState = STATE_ADDRESS_SETUP;
      STATE_ADDRESS_SETUP:       if(Stall)                                         NextState = STATE_ADDRESS_SETUP;
                             else                                              NextState = STATE_ACCESS;
      // exclusion-tag-start: icache case
      STATE_WRITEBACK:       if(CacheBusAck & ~(|CMOpM[3:1]))                  NextState = STATE_FETCH;
                             else if(CacheBusAck)                              NextState = STATE_ADDRESS_SETUP; // Read_hold lowers CacheStall
                             else                                              NextState = STATE_WRITEBACK;
      // eviction needs a delay as the bus fsm does not correctly handle sending the write command at the same time as getting back the bus ack.
      STATE_FLUSH:           if(TagDedDirty)                                   NextState = STATE_FLUSH;     // drop the tagless dirty line this cycle; counters hold (see below)
                             else if(LineDirtyLive)                            NextState = STATE_FLUSH_WRITEBACK;
                             else if (FlushFlag)                               NextState = STATE_ADDRESS_SETUP;
                             else                                              NextState = STATE_FLUSH;
      STATE_FLUSH_WRITEBACK: if(FlushWbDone & ~FlushFlag)                      NextState = STATE_FLUSH;
                             else if(FlushWbDone)                              NextState = STATE_ADDRESS_SETUP;
                             else                                              NextState = STATE_FLUSH_WRITEBACK;
      // exclusion-tag-end: icache case
      default:                                                                 NextState = STATE_ACCESS;
    endcase
  end

  // com back to CPU
  assign CacheCommitted = (CurrState != STATE_ACCESS) & ~(READ_ONLY_CACHE & (CurrState == STATE_ADDRESS_SETUP));
  assign StallConditions =  FlushCache | AnyMiss | (|CMOpM);                            // exclusion-tag: icache FlushCache
  // CacheBusy: in the middle of an access.  CacheStall adds the cycle a request is first seen in
  // ACCESS, which depends on the live request; a client that already holds the pipeline for that
  // cycle by other means can use CacheBusy and stay off that path.
  assign CacheBusy = (CurrState == STATE_TAG_SCAN) |
                      (CurrState == STATE_VICTIM_READ) |
                      (CurrState == STATE_DATA_DECODE) |
                      (CurrState == STATE_AMO_WRITE) |
                      (CurrState == STATE_ECC_WRITEBACK) |
                      (CurrState == STATE_DED_TRAP) |
                      (CurrState == STATE_FETCH) |
                      (CurrState == STATE_WRITEBACK) |
                      (CurrState == STATE_WRITE_LINE) |  // this cycle writes the sram, must keep stalling so the next cycle can read the next hit/miss unless its a write.
                      (CurrState == STATE_FLUSH) |
                      (CurrState == STATE_FLUSH_WRITEBACK);
  assign CacheStall = (CurrState == STATE_ACCESS & (CacheRW[0] | CacheRW[1] | (|CMOpM) | (FlushCache & ~READ_ONLY_CACHE))) | CacheBusy;
  // write enables internal to cache
  assign SetValid = CurrState == STATE_WRITE_LINE |
                    (CurrState == STATE_DATA_DECODE & CMOZeroNoEviction) |
                    (CurrState == STATE_WRITEBACK & CacheBusAck & CMOpM[3]);
  assign ClearValid = (CurrState == STATE_DATA_DECODE & ((CMOpM[0] | (CMOpM[2] & ~HitLineDirty)) | TagDedErr | (DataDedErr & Hit & ~(HitDirty & ~READ_ONLY_CACHE)))) |
                      (CurrState == STATE_WRITEBACK & CMOpM[2] & CacheBusAck) |
                      FlushDedHit; // drop the uncorrectable flushed line rather than leave it valid
  assign LRUWriteEn = (((CurrState == STATE_DATA_DECODE & (AnyHit | CMOZeroNoEviction) & ~TagSecErr & ~DataSecErr & ~TagDedErr & ~DataDedErr) |
                       (CurrState == STATE_ECC_WRITEBACK) |
                       (CurrState == STATE_WRITE_LINE)) & ~FlushStage) |
                      (CurrState == STATE_WRITEBACK & CMOpM[3] & CacheBusAck);
  // exclusion-tag-start: icache flushdirtycontrols
  assign SetDirty = UpdateHitWrite |         // exclusion-tag: icache SetDirty
                    (CurrState == STATE_WRITE_LINE & (CacheRWQ[0])) |
                    (CurrState == STATE_WRITEBACK & (CMOpM[3] & CacheBusAck));
  assign ClearDirty = (CurrState == STATE_WRITE_LINE & ~(CacheRWQ[0])) |   // exclusion-tag: icache ClearDirty
                      (CurrState == STATE_FLUSH & LineDirtyLive) | // This is wrong in a multicore snoop cache protocol.  Dirty must be cleared concurrently and atomically with writeback.  For single core cannot clear after writeback on bus ack and change flushadr.  Clears the wrong set.
  // Flush and eviction controls
                      CurrState == STATE_WRITEBACK & (CMOpM[1] | CMOpM[2]) & CacheBusAck;
  assign SelVictim =
                  (CurrState == STATE_WRITEBACK & ((~CacheBusAck & ~(CMOpM[1] | CMOpM[2])) | (CacheBusAck & CMOpM[3]))) |
                  (CurrState == STATE_DATA_DECODE & ((AnyMiss & LineDirty) | (CMOZeroNoEviction & ~Hit))) |
                  (CurrState == STATE_WRITE_LINE);
  assign SelWriteback = (CurrState == STATE_WRITEBACK & (CMOpM[1] | CMOpM[2] | ~CacheBusAck)) |
                        (CurrState == STATE_DATA_DECODE & AnyMiss & EvictDirty);
  // The flush counter walks every line, way by way within a set.  The arrays read it look-ahead
  // (cache.sv reads the next line in the same cycle FlushCntEn is set), so a cycle that invalidates
  // the current flush line must not also advance the counter, or the write would land on the next
  // line. Hence ~TagDedDirty here and FlushSkipQ (one cycle late) for data DED.
  assign FlushCntEn = (CurrState == STATE_FLUSH & ~LineDirtyLive & ~TagDedDirty) |
             (CurrState == STATE_FLUSH_WRITEBACK & FlushWbDone);
  assign FlushCntRst = (CurrState == STATE_FLUSH & FlushFlag & ~LineDirtyLive & ~TagDedDirty) |
              (CurrState == STATE_FLUSH_WRITEBACK & FlushFlag & FlushWbDone);
  // exclusion-tag-end: icache flushdirtycontrols
  // Bus interface controls
  assign CacheBusRW[1] = (CurrState == STATE_DATA_DECODE & AnyMiss & ~EvictDirty) | // exclusion-tag: icache CacheBusRCauses
                         (CurrState == STATE_FETCH & ~CacheBusAck) |
                         (CurrState == STATE_WRITEBACK & CacheBusAck & ~(|CMOpM));

  logic LoadMiss;
  assign LoadMiss = (CacheRWQ[1]) & ~Hit & ~InvalidateCache; // exclusion-tag: cache AnyMiss

  assign CacheBusRW[0] = (CurrState == STATE_DATA_DECODE & LoadMiss & EvictDirty) | // exclusion-tag: icache CacheBusW
                         (CurrState == STATE_WRITEBACK & ~CacheBusAck) |
                         (CurrState == STATE_FLUSH_WRITEBACK & ~CacheBusAck & ~FlushDedHit & ~FlushSkipQ) |
                         (CurrState == STATE_WRITEBACK & (CMOpM[1] | CMOpM[2]) & ~CacheBusAck);

  assign SelAdrData = (CurrState == STATE_ACCESS & (CacheRW[0] | CacheRW[1] | (|CMOpM))) | // exclusion-tag: icache SelAdrCauses // changes if store delay hazard removed
                  (CurrState == STATE_TAG_SCAN) |
                  (CurrState == STATE_VICTIM_READ) |
                  (CurrState == STATE_DATA_DECODE) |
                  (CurrState == STATE_AMO_WRITE) |
                  (CurrState == STATE_ECC_WRITEBACK) |
                  (CurrState == STATE_DED_TRAP) |
                  (CurrState == STATE_FETCH) |
                  (CurrState == STATE_WRITEBACK) |
                  (CurrState == STATE_WRITE_LINE) |
                  (CurrState == STATE_ADDRESS_SETUP & Stall & ~FillBufferReturn) |
                  resetDelay;
  assign SelAdrTag = (CurrState == STATE_ACCESS & (CacheRW[0] | CacheRW[1] | (|CMOpM))) | // exclusion-tag: icache SelAdrTag // changes if store delay hazard removed
                  (CurrState == STATE_TAG_SCAN) |
                  (CurrState == STATE_VICTIM_READ) |
                  (CurrState == STATE_DATA_DECODE) |
                  (CurrState == STATE_AMO_WRITE) |
                  (CurrState == STATE_ECC_WRITEBACK) |
                  (CurrState == STATE_DED_TRAP) |
                  (CurrState == STATE_FETCH) |
                  (CurrState == STATE_WRITEBACK) |
                  (CurrState == STATE_WRITE_LINE) |
                  resetDelay;
  assign SelFetchBuffer = CurrState == STATE_WRITE_LINE |
                          (CurrState == STATE_ADDRESS_SETUP & FillBufferReturn);
  assign CacheEn = (~Stall | StallConditions) | (CurrState != STATE_ACCESS) | reset | InvalidateCache; // exclusion-tag: dcache CacheEn

  // The lookup.  It starts at way 0, which is also what the arrays read while no access is in
  // flight (RowIdle): if the arrays are not enabled in ACCESS, the row they hold is still way 0 of
  // the access's set, read with NextSet the cycle before.
  assign ScanStart  = (CurrState == STATE_ACCESS) & (NextState == STATE_TAG_SCAN);
  assign ScanArrive = (CurrState == STATE_TAG_SCAN);
  assign ScanIssue  = (CurrState == STATE_TAG_SCAN) & ~ScanLast;
  assign RowIdle    = (CurrState == STATE_ACCESS) | (CurrState == STATE_ADDRESS_SETUP);

  // ECC-specific controls
  assign SelCorrectTag = (CurrState == STATE_ECC_WRITEBACK) & TagSecErr;
  assign SelCorrectData = (CurrState == STATE_ECC_WRITEBACK) & DataSecErr & ~WroteLineQ;
  // Uncorrectable data on a dirty line that is leaving the cache. The decoder already shows that
  // line: the victim during DATA_DECODE (re-read in VICTIM_READ), the flushed line on
  // FLUSH_WRITEBACK's first cycle. Writing it back would put garbage in memory
  // as if it were good data, so the line is dropped and the loss is reported instead.
  assign VictimDed = AnyMiss & LineDirty & DataDedErr & ~READ_ONLY_CACHE;
  assign EvictDirty = LineDirty & ~VictimDed;
  assign FlushDedHit = (CurrState == STATE_FLUSH_WRITEBACK) & DataDedErr & ~FlushSkipQ & ~READ_ONLY_CACHE;
  always_ff @(posedge clk)
    if (reset | FlushStage) FlushSkipQ <= 1'b0;
    else FlushSkipQ <= FlushDedHit;
  assign FlushWbDone = CacheBusAck | FlushSkipQ;
  assign EccDedLostLine = ((CurrState == STATE_DATA_DECODE) & VictimDed) | FlushDedHit;

  assign DropTagDedDirty = ((CurrState == STATE_TAG_SCAN) | (CurrState == STATE_FLUSH)) & TagDedDirty & ~READ_ONLY_CACHE;
  assign EccDedCleanDrop = (CurrState == STATE_DATA_DECODE) & (TagDedErr | (DataDedErr & Hit & ~(HitDirty & ~READ_ONLY_CACHE)));
  assign EccDedDirtyFault = ((CurrState == STATE_DATA_DECODE) & DataDedErr & Hit & HitDirty & ~READ_ONLY_CACHE) |
                            DropTagDedDirty | // modified data lost with its tag: reported, never silently dropped
                            EccDedLostLine;   // dirty line with uncorrectable data dropped on eviction/flush

endmodule // cachefsm
