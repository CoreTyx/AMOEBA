///////////////////////////////////////////
// cacheway
//
// Written: Rose Thompson rose@rosethompson.net
// Created: 7 July 2021
// Modified: 20 January 2023
// Modified: SECDED ECC hardening + scrub support, 2026
//
// Purpose: Storage and read/write access to data cache data, tag valid, dirty, and replacement.
//          Tag array is SECDED-protected (extended Hamming, see cacheeccenc/cacheeccdec). Data
//          array storage lives here (raw, undecoded); decode is shared once per cache in cache.sv
//          rather than replicated per way, since -- unlike the tag, which must be decoded on every
//          way in parallel to determine which way hits -- only the selected way's data ever needs
//          decoding, and that selection is already resolved via the existing AND-OR mux structure
//          by the time data decode matters. Valid and dirty bits are protected by simple 2-copy
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

module cacheway import cvw::*; #(parameter cvw_t P,
                  parameter PA_BITS, NUMSETS=512, LINELEN = 256, TAGLEN = 26,
                  OFFSETLEN = 5, INDEXLEN = 9, READ_ONLY_CACHE = 0,
                  // ECC check-bit sizing, needed here (not just in the body) because
                  // LINECHECKWIDTH sizes the DataCheckWay port below. R has no default in
                  // cacheeccbits/enc/dec by design (see those files) -- an insufficient R fails
                  // elaboration there rather than silently aliasing -- so it must be computed
                  // correctly here. This ladder extends the smallest-R-such-that-2^R>=dw+R+1
                  // formula (the same one hdl/core/generic/ecc/ecc_secded_enc.sv uses) past its
                  // R=8/dw=247 ceiling, which is where that IP's version silently under-provisions
                  // for anything wider -- exactly the bug class this cache ECC is independent of.
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
                                                   (TAGLEN <= 4083) ? 12 : 13,
                  localparam int TAGCHECKWIDTH  = TAGCHECKR + 1,
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
                                                   (LINELEN <= 4083) ? 12 : 13,
                  localparam int LINECHECKWIDTH = LINECHECKR + 1) (
  input  logic                        clk,
  input  logic                        reset,
  input  logic                        FlushStage,     // Pipeline flush of second stage (prevent writes and bus operations)
  input  logic                        InvalidateFlushStage,     // Pipeline flush of second stage (prevent writes and bus operations)
  input  logic                        CacheEn,        // Enable the cache memory arrays.  Disable hold read data constant
  input  logic [$clog2(NUMSETS)-1:0]  CacheSetData,       // Cache address, the output of the address select mux, NextAdr, PAdr, or FlushAdr
  input  logic [$clog2(NUMSETS)-1:0]  CacheSetTag,       // Cache address, the output of the address select mux, NextAdr, PAdr, or FlushAdr
  input  logic [PA_BITS-1:0]          PAdr,           // Physical address
  input  logic [LINELEN-1:0]          LineWriteData,  // Final data written to cache (D$ only)
  input  logic                        SetValid,       // Set the valid bit in the selected way and set
  input  logic                        ClearValid,     // Clear the valid bit in the selected way and set
  input  logic                        SetDirty,       // Set the dirty bit in the selected way and set
  input  logic                        SelVictim,      // Overrides HitWay Tag matching.  Selects selects the victim tag/data regardless of hit
  input  logic                        ClearDirty,     // Clear the dirty bit in the selected way and set
  input  logic                        FlushCache,       // [0] Use SelAdr, [1] SRAM reads/writes from FlushAdr
  input  logic                        VictimWay,      // LRU selected this way as victim to evict
  input  logic                        FlushWay,       // This way is selected for flush and possible writeback if dirty
  input  logic                        InvalidateCache,// Clear all valid bits
  input  logic [LINELEN/8-1:0]        LineByteMask,   // Final byte enables to cache (D$ only)

  // Scrubber interface: SelScrub overrides HitWay/FlushWay/VictimWay selection the same way they
  // override each other, picking an arbitrary way independent of any tag match.
  input  logic                        SelScrub,       // Scrubber is driving CacheSetTag/CacheSetData this cycle
  input  logic                        ScrubWay,       // This way is the scrubber's current target (one-hot across ways)

  // Correction writeback: re-encode and commit a corrected line (tag or data) into the currently
  // selected way. Tag correction is self-contained per way (this way's own decode result); data
  // correction's re-encoded value is supplied by cache.sv, which owns the single shared data
  // encoder/decoder pair.
  input  logic                        SelCorrectTag,  // Commit CorrectedTagIn (re-encoded) into the tag array
  input  logic [TAGLEN-1:0]           CorrectedTagIn,         // Re-encoded tag input for a tag-codeword correction writeback
  input  logic                        SelCorrectData, // Commit CorrectedLineIn (re-encoded externally) into the data array
  input  logic [LINELEN-1:0]          CorrectedLineIn,         // Data payload for a data-codeword correction writeback (already the corrected value; this module re-encodes it)

  // A second, held-one-cycle-later copy of "which way is selected," used only to gate the data
  // array's AND-part-of-mux. This breaks the tag-decode -> data-decode combinational path into two
  // cycles (tag decode resolves HitWay; NEXT cycle, the now-registered HitWay gates which way's raw
  // data feeds the shared data decoder), per the locked "stall, tag first then data" decision.
  input  logic                        TagDecodeCaptureEn,      // cachefsm: capture SelectedWay for data-decode use now
  output logic                        SelectedWayDataQ,        // registered SelectedWay-for-data, one cycle delayed

  output logic [LINELEN-1:0]          ReadDataLineWay,// This way's raw read data if selected (AND part of AO mux; NOT decoded -- decode is shared, done once in cache.sv)
  output logic [LINECHECKWIDTH-1:0]   DataCheckWay,   // This way's raw data check bits if selected (AND part of AO mux)
  output logic                        HitWay,         // This way hits (tag matches AND tag is not uncorrectable)
  output logic                        ValidWay,       // This way is valid (redundancy-checked)
  output logic                        ValidMismatch,  // This way's two valid-bit copies disagree (single-bit flip caught)
  output logic                        HitDirtyWay,    // The hit way is dirty
  output logic                        DirtyWay   ,    // The selected way is dirty
  output logic                        DirtyMismatch,  // The selected way's two dirty-bit copies disagree
  output logic                        TagSecErr,      // This way's tag codeword has a correctable error
  output logic                        TagDedErr,       // This way's tag codeword has an uncorrectable error
  output logic [TAGLEN-1:0]           TagWay);        // This way's corrected tag if selected (AND part of AO mux)

  logic [NUMSETS-1:0]                ValidBits, ValidBitsRedundant;
  logic [NUMSETS-1:0]                DirtyBits, DirtyBitsRedundant;
  logic [LINELEN-1:0]                 ReadDataLine;
  logic [LINECHECKWIDTH-1:0]          ReadDataCheck;
  logic [TAGLEN-1:0]                  ReadTag;
  logic [TAGCHECKWIDTH-1:0]           ReadTagCheck;
  logic                               Dirty, DirtyRedundant;
  logic                               SelecteDirty;
  logic                               SelectedWriteWordEn;
  logic [LINELEN/8-1:0]               FinalByteMask;
  logic                               SetValidEN, ClearValidEN;
  logic                               SetValidWay;
  logic                               ClearValidWay;
  logic                               SetDirtyWay;
  logic                               ClearDirtyWay;
  logic                               SelectedWay;
  logic                               InvalidateCacheDelay;

  if (!READ_ONLY_CACHE) begin : flushlogic
    mux2 #(1) seltagmux(VictimWay, FlushWay, FlushCache, SelecteDirty);
    mux4 #(1) selectedmux(HitWay, FlushWay, VictimWay, ScrubWay, {SelScrub, (SelVictim | FlushCache)}, SelectedWay);
    // Widened from the original mux3 to a mux4 with SelScrub as the new top-priority leg. Scrub
    // grants only ever occur when no demand access -- and hence no SelVictim/FlushCache -- is in
    // flight (see cache.sv's ScrubGrant definition), so priority among the other three legs is
    // unchanged from before.
  end else begin : flushlogic // no flush operation for read-only caches.
    assign SelecteDirty = VictimWay;
    mux3 #(1) selectedwaymux(HitWay, SelecteDirty, ScrubWay, {SelScrub, SelVictim}, SelectedWay);
  end

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Write Enable demux
  /////////////////////////////////////////////////////////////////////////////////////////////

  assign SetValidWay = SetValid & SelectedWay;
  assign ClearValidWay = ClearValid & SelectedWay;                             // exclusion-tag: icache ClearValidWay
  assign SetDirtyWay = SetDirty & SelectedWay;                                 // exclusion-tag: icache SetDirtyWay
  assign ClearDirtyWay = ClearDirty & SelectedWay;
  assign SelectedWriteWordEn = (SetValidWay | SetDirtyWay) & ~FlushStage;  // exclusion-tag: icache SelectedWiteWordEn
  assign SetValidEN = SetValidWay & ~FlushStage;                           // exclusion-tag: cache SetValidEN
  assign ClearValidEN = ClearValidWay & ~FlushStage;                       // exclusion-tag: cache ClearValidEN

  // If writing the whole line set all write enables to 1, else only set the correct word.
  assign FinalByteMask = SetValidWay ? '1 : LineByteMask; // OR

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Tag Array (SECDED-protected: TAGLEN data bits + check-bit side array)
  /////////////////////////////////////////////////////////////////////////////////////////////

  logic [TAGLEN-1:0]       TagEncodedData;
  logic [TAGCHECKWIDTH-1:0] TagEncodedCheck;
  cacheeccenc #(.DATA_WIDTH(TAGLEN), .R(TAGCHECKR)) tagenc (
    .data_i     (PAdr[PA_BITS-1:OFFSETLEN+INDEXLEN]),
    .codeword_o ({TagEncodedData, TagEncodedCheck})
  );

  logic [TAGLEN-1:0]       TagCorrectionData;
  logic [TAGCHECKWIDTH-1:0] TagCorrectionCheck;
  cacheeccenc #(.DATA_WIDTH(TAGLEN), .R(TAGCHECKR)) tagcorrectionenc (
    .data_i     (CorrectedTagIn),
    .codeword_o ({TagCorrectionData, TagCorrectionCheck})
  );

  logic [TAGLEN-1:0]       TagWriteData;
  logic [TAGCHECKWIDTH-1:0] TagCheckWriteData;
  mux2 #(TAGLEN) tagdinmux(TagEncodedData, TagCorrectionData, SelCorrectTag, TagWriteData);
  mux2 #(TAGCHECKWIDTH) tagcheckdinmux(TagEncodedCheck, TagCorrectionCheck, SelCorrectTag, TagCheckWriteData);

  logic TagWe;
  assign TagWe = SetValidEN | (SelCorrectTag & SelectedWay);

  ram1p1rwe #(.USE_SRAM(P.USE_SRAM), .DEPTH(NUMSETS), .WIDTH(TAGLEN)) CacheTagMem(.clk, .ce(CacheEn),
    .addr(CacheSetTag), .dout(ReadTag),
    .din(TagWriteData), .we(TagWe));

  ram1p1rwe #(.USE_SRAM(P.USE_SRAM), .DEPTH(NUMSETS), .WIDTH(TAGCHECKWIDTH)) CacheTagCheckMem(.clk, .ce(CacheEn),
    .addr(CacheSetTag), .dout(ReadTagCheck),
    .din(TagCheckWriteData), .we(TagWe));

  logic [TAGLEN-1:0] CorrectedTag;
  cacheeccdec #(.DATA_WIDTH(TAGLEN), .R(TAGCHECKR)) tagdec (
    .codeword_i ({ReadTag, ReadTagCheck}),
    .data_o     (CorrectedTag),
    .sec_err_o  (TagSecErr),
    .ded_err_o  (TagDedErr)
  );

  // AND portion of distributed tag multiplexer
  assign TagWay = SelectedWay ? CorrectedTag : '0; // AND part of AOMux
  assign HitDirtyWay = Dirty & ValidWay;
  assign DirtyWay = SelecteDirty & HitDirtyWay;                               // exclusion-tag: icache DirtyWay
  assign HitWay = ValidWay & (CorrectedTag == PAdr[PA_BITS-1:OFFSETLEN+INDEXLEN]) & ~InvalidateCacheDelay & ~TagDedErr; // exclusion-tag: dcache HitWay

  flopenrc #(1) InvalidateCacheReg(clk, 1'b0, InvalidateFlushStage, 1'b1, InvalidateCache, InvalidateCacheDelay);

  // Registered, one-cycle-delayed SelectedWay used only to gate the data array's AND-part-of-mux.
  // Breaks the tag-decode -> data-decode combinational path into two cycles.
  flopenr #(1) selectedwaydatareg(clk, reset, TagDecodeCaptureEn, SelectedWay, SelectedWayDataQ);

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Data Array (SECDED-protected: one codeword per full line; decode is shared across ways in
  // cache.sv, since only the selected way's data ever needs decoding -- see module header)
  /////////////////////////////////////////////////////////////////////////////////////////////

  logic [LINELEN-1:0] LineEncodedData;
  logic [LINECHECKWIDTH-1:0] LineEncodedCheck;
  cacheeccenc #(.DATA_WIDTH(LINELEN), .R(LINECHECKR)) dataenc (
    .data_i     (LineWriteData),
    .codeword_o ({LineEncodedData, LineEncodedCheck})
  );

  logic [LINELEN-1:0] LineCorrectionData;
  logic [LINECHECKWIDTH-1:0] LineCorrectionCheck;
  cacheeccenc #(.DATA_WIDTH(LINELEN), .R(LINECHECKR)) datacorrectionenc (
    .data_i     (CorrectedLineIn),
    .codeword_o ({LineCorrectionData, LineCorrectionCheck})
  );

  logic [LINELEN-1:0] LineWriteFinal;
  logic [LINECHECKWIDTH-1:0] LineCheckWriteFinal;
  mux2 #(LINELEN) linedinmux(LineEncodedData, LineCorrectionData, SelCorrectData, LineWriteFinal);
  mux2 #(LINECHECKWIDTH) linecheckdinmux(LineEncodedCheck, LineCorrectionCheck, SelCorrectData, LineCheckWriteFinal);

  logic DataWe;
  assign DataWe = SelectedWriteWordEn | (SelCorrectData & SelectedWay);

  if (READ_ONLY_CACHE) begin : wordram // no byte-enable needed for i$.
    ram1p1rwe #(.USE_SRAM(P.USE_SRAM), .DEPTH(NUMSETS), .WIDTH(LINELEN)) CacheDataMem(.clk, .ce(CacheEn), .addr(CacheSetData),
      .dout(ReadDataLine), .din(LineWriteFinal), .we(DataWe));
    ram1p1rwe #(.USE_SRAM(P.USE_SRAM), .DEPTH(NUMSETS), .WIDTH(LINECHECKWIDTH)) CacheDataCheckMem(.clk, .ce(CacheEn), .addr(CacheSetData),
      .dout(ReadDataCheck), .din(LineCheckWriteFinal), .we(DataWe));
  end else begin : wordram // D$ needs byte enables
    ram1p1rwbe #(.USE_SRAM(P.USE_SRAM), .DEPTH(NUMSETS), .WIDTH(LINELEN)) CacheDataMem(.clk, .ce(CacheEn), .addr(CacheSetData),
      .dout(ReadDataLine), .din(LineWriteFinal), .we(DataWe), .bwe(FinalByteMask));
    // Check-bit array is always written in full -- per-line granularity means partial-line stores
    // are merged with the corrected line and re-encoded whole (see cache.sv WriteSelLogic), so
    // there is never a partial write to make here.
    ram1p1rwe #(.USE_SRAM(P.USE_SRAM), .DEPTH(NUMSETS), .WIDTH(LINECHECKWIDTH)) CacheDataCheckMem(.clk, .ce(CacheEn), .addr(CacheSetData),
      .dout(ReadDataCheck), .din(LineCheckWriteFinal), .we(DataWe));
  end

  // AND portion of distributed read multiplexers -- raw, undecoded. Decode happens once, shared,
  // in cache.sv, on the OR-aggregated value across all ways (see module header rationale).
  assign ReadDataLineWay = SelectedWayDataQ ? ReadDataLine : '0;
  assign DataCheckWay = SelectedWayDataQ ? ReadDataCheck : '0;

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Valid Bits -- 2-copy redundancy. Mismatch always resolves to the safe direction (invalid),
  // since a 0->1 flip (garbage line looking like a hit) is the dangerous one; 1->0 is just a
  // spurious miss.
  /////////////////////////////////////////////////////////////////////////////////////////////

  logic ValidRaw, ValidRedundantRaw;

  always_ff @(posedge clk) begin // Valid bit array,
    if (reset) begin
      ValidBits <= '0;
      ValidBitsRedundant <= '0;
    end
    if (CacheEn) begin
      ValidRaw          <= ValidBits[CacheSetTag];
      ValidRedundantRaw <= ValidBitsRedundant[CacheSetTag];
      if(InvalidateCache & ~InvalidateFlushStage) begin
        ValidBits <= '0; // exclusion-tag: dcache invalidateway
        ValidBitsRedundant <= '0;
      end else if (SetValidEN) begin
        ValidBits[CacheSetData] <= SetValidWay;
        ValidBitsRedundant[CacheSetData] <= SetValidWay;
      end else if (ClearValidEN) begin
        ValidBits[CacheSetData] <= '0; // exclusion-tag: icache ClearValidBits
        ValidBitsRedundant[CacheSetData] <= '0;
      end else if (ValidMismatch & SelectedWay) begin
        // Resync both copies to the safe (invalid) value on a detected mismatch.
        ValidBits[CacheSetData] <= 1'b0;
        ValidBitsRedundant[CacheSetData] <= 1'b0;
      end
    end
  end

  assign ValidMismatch = ValidRaw ^ ValidRedundantRaw;
  assign ValidWay = ValidRaw & ValidRedundantRaw; // safe direction: only a hit if BOTH copies agree it's valid

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Dirty Bits -- same 2-copy redundancy, mismatch resolves to the safe direction (dirty), since
  // a 1->0 flip (silently dropping the only copy of modified data on eviction) is the dangerous
  // one here; 0->1 is just a spurious writeback.
  /////////////////////////////////////////////////////////////////////////////////////////////

  if (!READ_ONLY_CACHE) begin : dirty
    always_ff @(posedge clk) begin
      if (CacheEn) begin
        Dirty          <= DirtyBits[CacheSetTag];
        DirtyRedundant <= DirtyBitsRedundant[CacheSetTag];
        if ((SetDirtyWay | ClearDirtyWay) & ~FlushStage) begin
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
  end else begin
    assign Dirty = 1'b0;
    assign DirtyRedundant = 1'b0;
    assign DirtyMismatch = 1'b0;
  end
endmodule
