///////////////////////////////////////////
// cacheway
//
// Written: Rose Thompson rose@rosethompson.net
// Created: 7 July 2021
// Modified: 20 January 2023
// Modified: SECDED ECC hardening + scrub support, 2026
//
// Purpose: Per-way state of a cache: valid, dirty, and the way's share of the lookup.
//          The tags and lines themselves are in cachearray.sv, where every way shares one tag macro
//          and one data macro; the ways are looked up one after another.  This module keeps, for its
//          way, what the lookup found when the way's row came out of the arrays (hit, tag SEC/DED),
//          and decides whether this way is the one an access reads or writes (SelectedWay).
//          Valid and dirty bits are protected by simple 2-copy
//          redundancy: cheap, and sufficient to catch the one dangerous flip direction for each
//          (0->1 for valid, 1->0 for dirty) without requiring a Hamming read-modify-write on every
//          dirty-setting store the way folding dirty into the tag codeword would have.
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

module cacheway #(parameter NUMSETS=512, READ_ONLY_CACHE = 0) (
  input  logic                        clk,
  input  logic                        reset,
  input  logic                        FlushStage,     // Pipeline flush of second stage (prevent writes and bus operations)
  input  logic                        InvalidateFlushStage,     // Pipeline flush of second stage (prevent writes and bus operations)
  input  logic                        CacheEn,        // Enable the cache memory arrays.  Disable hold read data constant
  input  logic [$clog2(NUMSETS)-1:0]  CacheSetData,   // Set written: the output of the data address select mux
  input  logic [$clog2(NUMSETS)-1:0]  CacheSetTag,    // Set read: the output of the tag address select mux
  input  logic                        SetValid,       // Set the valid bit in the selected way and set
  input  logic                        ClearValid,     // Clear the valid bit in the selected way and set
  input  logic                        ScrubInvalidate, // Invalidate the scrubber's selected way and set
  input  logic                        SetDirty,       // Set the dirty bit in the selected way and set
  input  logic                        SelVictim,      // Overrides HitWay Tag matching.  Selects selects the victim tag/data regardless of hit
  input  logic                        ClearDirty,     // Clear the dirty bit in the selected way and set
  input  logic                        FlushCache,     // Flush in progress: FlushWay selects
  input  logic                        VictimWay,      // LRU selected this way as victim to evict
  input  logic                        FlushWay,       // This way is selected for flush and possible writeback if dirty
  input  logic                        InvalidateCache,// Clear all valid bits

  // Scrubber interface: SelScrub overrides HitWay/FlushWay/VictimWay selection the same way they
  // override each other, picking an arbitrary way independent of any tag match.
  input  logic                        SelScrub,       // Scrubber is driving CacheSetTag/CacheSetData this cycle
  input  logic                        ScrubWay,       // This way is the scrubber's current target (one-hot across ways)

  // The lookup (see cachearray.sv).  The arrays return one way's row per cycle; ArriveWay says it
  // is this way's.  What the row's tag decoded to is then kept here, per way, until the next scan
  // starts: so HitWay, TagSecErr and TagDedErr describe the access through all its later states.
  input  logic                        ArriveWay,      // The arrays are returning this way's row (a read)
  input  logic                        TagMatchLive,   // The arriving tag matches the access
  input  logic                        TagSecErrLive,  // The arriving tag had a correctable error
  input  logic                        TagDedErrLive,  // The arriving tag had an uncorrectable error
  input  logic                        ScanStart,      // cachefsm: a lookup starts; forget the last one

  output logic                        SelectedWay,    // This way is the one being read and written
  output logic                        HitWay,         // This way hits (tag matches AND tag is not uncorrectable); registered
  output logic                        HitWayLive,     // The same in the cycle the tag is read
  output logic                        ValidWay,       // This way is valid (redundancy-checked)
  output logic                        ValidMismatch,  // This way's two valid-bit copies disagree (single-bit flip caught)
  output logic                        HitDirtyWay,    // The hit way is dirty
  output logic                        DirtyWay   ,    // The selected way is dirty
  output logic                        DirtyWayLive,   // The same in the cycle the tag is read
  output logic                        DirtyMismatch,  // The selected way's two dirty-bit copies disagree
  output logic                        TagSecErr,      // This way's tag codeword has a correctable error; registered
  output logic                        TagDedErr,       // This way's tag codeword has an uncorrectable error; registered
  // A valid, dirty line whose tag is uncorrectable cannot be written back (its address is lost).
  // It is excluded from DirtyWay so no eviction or flush ever writes it to a wrong address, flagged
  // here, and dropped when cachefsm pulses DropTagDedDirty (which also raises the dirty-data fault).
  output logic                        TagDedDirtyWay,  // This way holds a valid, dirty line with an uncorrectable tag
  input  logic                        DropTagDedDirty); // cachefsm: invalidate this way if TagDedDirtyWay (gated to FlushWay during a flush)

  logic [NUMSETS-1:0]                ValidBits, ValidBitsRedundant;
  logic [NUMSETS-1:0]                DirtyBits, DirtyBitsRedundant;
  logic                               Dirty, DirtyRedundant;
  logic                               SelecteDirty;
  logic                               SetValidEN, ClearValidEN, ScrubInvalidateWay;
  logic                               SetValidWay;
  logic                               ClearValidWay;
  logic                               SetDirtyWay;
  logic                               ClearDirtyWay;
  logic                               TagDedErrWayLive;
  logic [1:0]                         SelectedWaySel;
  logic                               InvalidateCacheDelay;
  logic                               DirtyEff;        // effective dirty: either copy set (safe direction)
  logic                               TagDedDropWay;
  logic                               HitWayQ;

  if (!READ_ONLY_CACHE) begin : flushlogic
    mux2 #(1) seltagmux(VictimWay, FlushWay, FlushCache, SelecteDirty);
    assign SelectedWaySel = SelScrub ? 2'b11 :
                            SelVictim ? 2'b10 :
                            FlushCache ? 2'b01 : 2'b00;
    mux4 #(1) selectedmux(HitWay, FlushWay, VictimWay, ScrubWay, SelectedWaySel, SelectedWay);
    // Widened from the original mux3 to a mux4 with SelScrub as the new top-priority leg. Scrub
    // grants only ever occur when no demand access -- and hence no SelVictim/FlushCache -- is in
    // flight (see cache.sv's ScrubGrant definition), so priority among the other three legs is
    // unchanged from before.
  end else begin : flushlogic // no flush operation for read-only caches.
    assign SelecteDirty = VictimWay;
    mux3 #(1) selectedwaymux(HitWay, SelecteDirty, ScrubWay, {SelScrub, SelVictim}, SelectedWay);
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Write Enable demux.  The array writes themselves are made in cachearray.sv, at this way's row
  // when SelectedWay is set (cache.sv); only the valid and dirty bits are written here.
  /////////////////////////////////////////////////////////////////////////////////////////////

  assign SetValidWay = SetValid & SelectedWay;
  assign ClearValidWay = ClearValid & SelectedWay;                             // exclusion-tag: icache ClearValidWay
  assign ScrubInvalidateWay = ScrubInvalidate & SelectedWay;
  assign SetDirtyWay = SetDirty & SelectedWay;                                 // exclusion-tag: icache SetDirtyWay
  assign ClearDirtyWay = ClearDirty & SelectedWay;
  assign SetValidEN = SetValidWay & ~FlushStage;                           // exclusion-tag: cache SetValidEN
  assign ClearValidEN = ClearValidWay & ~FlushStage;                       // exclusion-tag: cache ClearValidEN

  /////////////////////////////////////////////////////////////////////////////////////////////
  // This way's share of the lookup
  /////////////////////////////////////////////////////////////////////////////////////////////

  // The hit and the tag's error flags, from the row as it arrives, and kept until the next scan
  // starts.  A scan that stops early never reads the later ways; with nothing kept from an older
  // access, they count as not hit and not in error.
  assign TagDedErrWayLive = ArriveWay & TagDedErrLive;
  assign HitWayLive = ArriveWay & ValidWay & TagMatchLive & ~InvalidateCacheDelay & ~TagDedErrLive; // exclusion-tag: dcache HitWay
  always_ff @(posedge clk)
    if (reset | ScanStart) {HitWayQ, TagSecErr, TagDedErr} <= '0;
    else if (ArriveWay)    {HitWayQ, TagSecErr, TagDedErr} <= {HitWayLive, TagSecErrLive, TagDedErrLive};
  // An invalidate must not be outlived by a registered hit.
  assign HitWay = HitWayQ & ~InvalidateCacheDelay;
  flopenrc #(1) InvalidateCacheReg(clk, 1'b0, InvalidateFlushStage, 1'b1, InvalidateCache, InvalidateCacheDelay);

  assign HitDirtyWay = DirtyEff & ValidWay;
  // The lost-tag check and the flush walk act in the cycle the tag is read.
  assign TagDedDirtyWay = HitDirtyWay & TagDedErrWayLive;
  assign DirtyWayLive = (SelScrub ? ScrubWay : SelecteDirty) & HitDirtyWay & ~TagDedErrWayLive;
  assign DirtyWay = (SelScrub ? ScrubWay : SelecteDirty) & HitDirtyWay & ~TagDedErr;        // exclusion-tag: icache DirtyWay
  assign TagDedDropWay = DropTagDedDirty & TagDedDirtyWay & (~FlushCache | FlushWay);

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Valid Bits -- 2-copy redundancy. A mismatch on a CLEAN line resolves to invalid, since a 0->1
  // flip (garbage line looking like a hit) is the dangerous one and a spurious miss is harmless.
  // A mismatch on a DIRTY line resolves to valid: dirty implies valid, and treating it as invalid
  // would silently replace the only copy of modified data with stale memory contents. That rule
  // relies on the invariant "dirty => valid", which the dirty block below maintains by clearing a
  // way's dirty copies whenever its valid bit is cleared.
  /////////////////////////////////////////////////////////////////////////////////////////////

  logic ValidRaw, ValidRedundantRaw;

  always_ff @(posedge clk) begin // Valid bit array,
    // The read registers are cleared with the arrays, and nothing below runs during reset.
    // Otherwise their power-up value makes ValidMismatch fire in reset, and the resync write
    // below lands after the clear in the same cycle and overrides it for one entry. In 4-state
    // simulation that entry then holds X forever (X ^ X = X keeps the mismatch alive).
    if (reset) begin
      ValidBits <= '0;
      ValidBitsRedundant <= '0;
      ValidRaw <= 1'b0;
      ValidRedundantRaw <= 1'b0;
    end else if (CacheEn) begin
      ValidRaw          <= ValidBits[CacheSetTag];
      ValidRedundantRaw <= ValidBitsRedundant[CacheSetTag];
      if(InvalidateCache & ~InvalidateFlushStage) begin
        ValidBits <= '0; // exclusion-tag: dcache invalidateway
        ValidBitsRedundant <= '0;
      end else if (SetValidEN) begin
        ValidBits[CacheSetData] <= SetValidWay;
        ValidBitsRedundant[CacheSetData] <= SetValidWay;
      end else if (ClearValidEN | ScrubInvalidateWay | TagDedDropWay) begin
        ValidBits[CacheSetData] <= '0; // exclusion-tag: icache ClearValidBits
        ValidBitsRedundant[CacheSetData] <= '0;
      end else if (ValidMismatch & SelectedWay) begin
        // Resync both copies to the resolved value (see ValidWay) on a detected mismatch.
        ValidBits[CacheSetData] <= ValidWay;
        ValidBitsRedundant[CacheSetData] <= ValidWay;
      end
    end
  end

  assign ValidMismatch = ValidRaw ^ ValidRedundantRaw;
  assign ValidWay = (ValidRaw & ValidRedundantRaw) | (ValidMismatch & DirtyEff);

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Dirty Bits -- same 2-copy redundancy, mismatch resolves to the safe direction (dirty), since
  // a 1->0 flip (silently dropping the only copy of modified data on eviction) is the dangerous
  // one here; 0->1 is just a spurious writeback.
  /////////////////////////////////////////////////////////////////////////////////////////////

  if (!READ_ONLY_CACHE) begin : dirty
    logic ClearDirtyOnInvalidate;
    assign ClearDirtyOnInvalidate = ClearValidEN | ScrubInvalidateWay | TagDedDropWay;
    always_ff @(posedge clk) begin
      if (reset) begin
        DirtyBits <= '0;
        DirtyBitsRedundant <= '0;
        // Cleared for the same reason as ValidRaw above: an unreset read register makes
        // DirtyMismatch fire on the first cycle after reset and resync-write the array.
        Dirty <= 1'b0;
        DirtyRedundant <= 1'b0;
      end else if (CacheEn) begin
        Dirty          <= DirtyBits[CacheSetTag];
        DirtyRedundant <= DirtyBitsRedundant[CacheSetTag];
        if (InvalidateCache & ~InvalidateFlushStage) begin
          DirtyBits <= '0;
          DirtyBitsRedundant <= '0;
        end else if (ClearDirtyOnInvalidate) begin
          // Keep "dirty => valid": a way losing its valid bit loses its dirty bit with it.
          DirtyBits[CacheSetData] <= 1'b0;
          DirtyBitsRedundant[CacheSetData] <= 1'b0;
          if (CacheSetData == CacheSetTag) begin
            Dirty <= 1'b0;
            DirtyRedundant <= 1'b0;
          end
        end else if ((SetDirtyWay | ClearDirtyWay) & ~FlushStage) begin
          DirtyBits[CacheSetData] <= SetDirtyWay; // exclusion-tag: cache UpdateDirty
          DirtyBitsRedundant[CacheSetData] <= SetDirtyWay;
          if (CacheSetData == CacheSetTag) begin
            Dirty <= SetDirtyWay;
            DirtyRedundant <= SetDirtyWay;
          end else begin
            Dirty <= DirtyBits[CacheSetTag];
            DirtyRedundant <= DirtyBitsRedundant[CacheSetTag];
          end
        end else if (DirtyMismatch & SelectedWay) begin
          // Resync both copies to the safe (dirty) value on a detected mismatch.
          DirtyBits[CacheSetData] <= 1'b1;
          DirtyBitsRedundant[CacheSetData] <= 1'b1;
          Dirty <= 1'b1;
          DirtyRedundant <= 1'b1;
        end
      end
    end
    assign DirtyMismatch = Dirty ^ DirtyRedundant;
    assign DirtyEff = Dirty | DirtyRedundant;
  end else begin
    assign Dirty = 1'b0;
    assign DirtyRedundant = 1'b0;
    assign DirtyMismatch = 1'b0;
    assign DirtyEff = 1'b0;
  end
endmodule
