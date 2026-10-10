///////////////////////////////////////////
// cache_integration_tb.sv
//
// Purpose: Integration-level verification of the wired-up SECDED cache (cache.sv/cacheway.sv/
//          cachefsm.sv/cachescrubber.sv together, not just the standalone cacheeccenc/dec modules
//          -- see hvl/cache/cache_ecc_unit_tb.sv for that). Instantiates a real `cache` module with
//          a small test-sized geometry, drives it like a simple LSU against a behavioral memory
//          model on the bus side, and injects bit flips directly into the internal SRAM arrays via
//          hierarchical access (USE_SRAM=0 in this config, so the arrays are plain behavioral
//          `bit` arrays, not opaque vendor macros).
//
// Run: make -C sim cache_integration_test
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

`include "config.vh"

module cache_integration_tb;
  import cvw::*;
  `include "parameter-defs.vh"

  localparam PA_BITS = 16;
  localparam LINELEN = 128;
  localparam NUMSETS = 8;
  localparam NUMWAYS = 2;
  localparam WORDLEN = 64;
  localparam MUXINTERVAL = 64;
  localparam LOGBWPL = 2;

  localparam OFFSETLEN = $clog2(LINELEN/8);
  localparam SETLEN = $clog2(NUMSETS);
  localparam TAGLEN = PA_BITS - SETLEN - OFFSETLEN;

  logic clk, reset;
  logic Stall, FlushStage, InvalidateFlushStage;
  logic [1:0] CacheRW;
  logic FlushCache, InvalidateCache;
  logic [3:0] CMOpM;
  logic [11:0] NextSet;
  logic [PA_BITS-1:0] PAdr;
  logic [(WORDLEN-1)/8:0] ByteMask;
  logic [WORDLEN-1:0] WriteData;
  logic CacheCommitted, CacheStall;
  logic [WORDLEN-1:0] ReadDataWord;
  logic CacheMiss, CacheAccess;
  logic [31:0] SecCount;
  logic SelHPTW;
  logic CacheBusAck, SelBusBeat;
  logic [LOGBWPL-1:0] BeatCount;
  logic [LINELEN-1:0] FetchBuffer;
  logic [1:0] CacheBusRW;
  logic [PA_BITS-1:0] CacheBusAdr;
  logic EccDedDirtyFault;
  logic [PA_BITS-1:0] EccDedDirtyFaultAdr;

  int errors;
  int checks;

  cache #(.P(P), .PA_BITS(PA_BITS), .LINELEN(LINELEN), .NUMSETS(NUMSETS), .NUMWAYS(NUMWAYS),
          .LOGBWPL(LOGBWPL), .WORDLEN(WORDLEN), .MUXINTERVAL(MUXINTERVAL), .READ_ONLY_CACHE(0),
          .SCRUBBER_ENABLED(1'b1), .SCRUB_INTERVAL_CYCLES(0)) dut (
    .clk, .reset, .Stall, .FlushStage, .InvalidateFlushStage,
    .CacheRW, .FlushCache, .InvalidateCache, .CMOpM, .NextSet, .PAdr, .ByteMask, .WriteData,
    .CacheCommitted, .CacheStall, .ReadDataWord, .CacheMiss, .CacheAccess, .SelHPTW,
    .CacheBusAck, .SelBusBeat, .BeatCount, .FetchBuffer, .CacheBusRW, .CacheBusAdr, .SecCount,
    .EccDedDirtyFault, .EccDedDirtyFaultAdr
  );

  // ── Clock ──────────────────────────────────────────────────────────────────────────────────
  always #5 clk = ~clk;

  // ── Behavioral "memory": one line per distinct line address ever fetched ─────────────────────
  logic [LINELEN-1:0] mem [logic [PA_BITS-1:0]];

  function automatic logic [LINELEN-1:0] mem_read(input logic [PA_BITS-1:0] lineadr);
    if (mem.exists(lineadr)) return mem[lineadr];
    else return {NUMWAYS{64'hBAD0BAD0BAD0BAD0}}; // distinctive "uninitialized" pattern
  endfunction

  // ── Minimal bus responder: acks a fetch with FetchBuffer = mem[line], acks a writeback without
  // needing to capture correct data (none of these tests depend on writeback content). ──────────
  always @(posedge clk) begin
    if (reset) begin
      CacheBusAck <= 1'b0;
      FetchBuffer <= '0;
    end else begin
      CacheBusAck <= 1'b0;
      if (CacheBusRW[1] & ~CacheBusAck) begin
        // present the line 2 cycles after a fetch request, matching a small fixed bus latency
        FetchBuffer <= mem_read({CacheBusAdr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}});
        CacheBusAck <= 1'b1;
      end else if (CacheBusRW[0] & ~CacheBusAck) begin
        CacheBusAck <= 1'b1;
      end
    end
  end
  assign SelBusBeat = 1'b0;
  assign BeatCount = '0;

  // ── Drive-side helper tasks ───────────────────────────────────────────────────────────────────
  task automatic waitclocks(input int n);
    repeat (n) @(posedge clk);
  endtask

  task automatic waitidle;
    int timeout;
    timeout = 0;
    while (CacheStall) begin
      @(posedge clk);
      timeout++;
      if (timeout > 500) begin
        $display("FAIL: timeout waiting for CacheStall to clear (CurrState=%0d ScrubBusy=%b ScrubGrant=%b ScrubReq=%b CacheRW=%b)",
                  dut.cachefsm.CurrState, dut.ScrubBusy, dut.ScrubGrant, dut.ScrubReq, CacheRW);
        errors++;
        break;
      end
    end
  endtask

  task automatic doload(input logic [PA_BITS-1:0] adr, output logic [WORDLEN-1:0] result);
    CacheRW = 2'b10;
    PAdr = adr;
    NextSet = adr[11:0];
    @(posedge clk);
    waitidle();
    result = ReadDataWord;
    CacheRW = 2'b00;
    @(posedge clk);
  endtask

  task automatic dostore(input logic [PA_BITS-1:0] adr, input logic [WORDLEN-1:0] data);
    CacheRW = 2'b01;
    PAdr = adr;
    NextSet = adr[11:0];
    WriteData = data;
    ByteMask = '1;
    @(posedge clk);
    waitidle();
    CacheRW = 2'b00;
    @(posedge clk);
  endtask

  task automatic check(input string what, input bit ok);
    checks++;
    if (!ok) begin
      $display("FAIL: %s", what);
      errors++;
    end else $display("PASS: %s", what);
  endtask

  // Hierarchical peek/poke into way `w`'s internal arrays for set `s`. USE_SRAM=0 in this config,
  // so these are plain behavioral `bit` arrays (see ram1p1rwe.sv's `ram` fallback block), reachable
  // directly -- no vendor macro stands in the way. Widths computed independently (same ladder as
  // cacheway.sv/cache.sv) rather than pulled hierarchically from the DUT, since Verilator doesn't
  // support a hierarchical parameter reference as a type width outside the instance's own scope.
  function automatic int tbrequiredr(input int dw);
    return (dw <=    1) ?  2 :
           (dw <=    4) ?  3 :
           (dw <=   11) ?  4 :
           (dw <=   26) ?  5 :
           (dw <=   57) ?  6 :
           (dw <=  120) ?  7 :
           (dw <=  247) ?  8 :
           (dw <=  502) ?  9 :
           (dw <= 1013) ? 10 : 11;
  endfunction
  localparam int TB_LINECHECKWIDTH = tbrequiredr(LINELEN) + 1;
  localparam int TB_TAGCHECKWIDTH = tbrequiredr(TAGLEN) + 1;

  function automatic logic [TB_LINECHECKWIDTH-1:0] peekdatacheck(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].wordram.CacheDataCheckMem.ram.RAM[s];
      default: return dut.CacheWays[1].wordram.CacheDataCheckMem.ram.RAM[s];
    endcase
  endfunction

  function automatic logic [LINELEN-1:0] peekdata(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].wordram.CacheDataMem.ram.RAM[s];
      default: return dut.CacheWays[1].wordram.CacheDataMem.ram.RAM[s];
    endcase
  endfunction

  task automatic flipdatacheckbits(input int w, input int s, input int bit0, input int bit1 = -1);
    logic [TB_LINECHECKWIDTH-1:0] v;
    v = peekdatacheck(w, s);
    v[bit0] = ~v[bit0];
    if (bit1 >= 0) v[bit1] = ~v[bit1];
    case (w)
      0: dut.CacheWays[0].wordram.CacheDataCheckMem.ram.RAM[s] = v;
      default: dut.CacheWays[1].wordram.CacheDataCheckMem.ram.RAM[s] = v;
    endcase
  endtask

  function automatic logic [TB_TAGCHECKWIDTH-1:0] peektagcheck(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].tag_ecc.CacheTagCheckMem.ram.RAM[s];
      default: return dut.CacheWays[1].tag_ecc.CacheTagCheckMem.ram.RAM[s];
    endcase
  endfunction

  task automatic fliptagcheckbits(input int w, input int s, input int bit0, input int bit1 = -1);
    logic [TB_TAGCHECKWIDTH-1:0] v;
    v = peektagcheck(w, s);
    v[bit0] = ~v[bit0];
    if (bit1 >= 0) v[bit1] = ~v[bit1];
    case (w)
      0: dut.CacheWays[0].tag_ecc.CacheTagCheckMem.ram.RAM[s] = v;
      default: dut.CacheWays[1].tag_ecc.CacheTagCheckMem.ram.RAM[s] = v;
    endcase
  endtask

  function automatic logic peekvalid(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].ValidBits[s] & dut.CacheWays[0].ValidBitsRedundant[s];
      default: return dut.CacheWays[1].ValidBits[s] & dut.CacheWays[1].ValidBitsRedundant[s];
    endcase
  endfunction

  function automatic logic peekdirty(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].DirtyBits[s];
      default: return dut.CacheWays[1].DirtyBits[s];
    endcase
  endfunction

  // Which way an address landed in: scan both ways' tags for this set (LRU picks the victim, we
  // don't control it directly, so tests discover it after the fact).
  function automatic int findway(input logic [PA_BITS-1:0] adr);
    int s;
    s = adr[SETLEN+OFFSETLEN-1:OFFSETLEN];
    if (peekvalid(0, s) && dut.CacheWays[0].CacheTagMem.ram.RAM[s] == adr[PA_BITS-1:SETLEN+OFFSETLEN]) return 0;
    if (peekvalid(1, s) && dut.CacheWays[1].CacheTagMem.ram.RAM[s] == adr[PA_BITS-1:SETLEN+OFFSETLEN]) return 1;
    return -1;
  endfunction

  logic [WORDLEN-1:0] result;
  logic [PA_BITS-1:0] testadr, dirtyadr, scrubadr, tagsecadr, tagdedadr;
  logic [PA_BITS-1:0] scrubcleanadr, scrubdirtyadr, scrubverifyadr;
  logic [PA_BITS-1:0] evictadrA, evictadrB, evictadrC;
  int way, s;

  initial begin
    clk = 0; reset = 1; errors = 0; checks = 0;
    Stall = 0; FlushStage = 0; InvalidateFlushStage = 0;
    CacheRW = 0; FlushCache = 0; InvalidateCache = 0; CMOpM = 0;
    NextSet = 0; PAdr = 0; ByteMask = 0; WriteData = 0; SelHPTW = 0;
    waitclocks(5);
    reset = 0;
    waitclocks(3);
    check("SEC counter resets to zero", SecCount == 0);

    // ── 1. Fetch (compulsory miss) + read-back correctness ──
    testadr = 16'h1000;
    mem[{testadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'hCAFEF00DDEADBEEF}};
    doload(testadr, result);
    check("fetch: correct data on compulsory miss", result === 64'hCAFEF00DDEADBEEF);

    way = findway(testadr);
    s = testadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
    check("fetch: line landed in a valid way", way >= 0);

    // ── 2. Re-read: should hit, same data, no new bus activity expected ──
    doload(testadr, result);
    check("hit: correct data on re-read", result === 64'hCAFEF00DDEADBEEF);

    // ── 3. Single-bit inject into data check bits, then re-read: SEC should correct transparently
    //       and persist the fix (writeback), confirmed by the stored check bits changing. ──
    begin
      logic [TB_LINECHECKWIDTH-1:0] checkbefore, checkafter;
      checkbefore = peekdatacheck(way, s);
      flipdatacheckbits(way, s, 0);
      doload(testadr, result);
      check("SEC: data still correct after single-bit inject", result === 64'hCAFEF00DDEADBEEF);
      checkafter = peekdatacheck(way, s);
      check("SEC: correction was written back (check bits no longer match the injected error)", checkafter !== (checkbefore ^ (1 << 0)));
      check("SEC counter increments once for demand correction", SecCount == 1);
    end

    // ── 4. Double-bit inject on a CLEAN line: should invalidate + refetch, recovering correct data
    //       via the bus model rather than "correcting" incorrectly. ──
    begin
      bit sawmiss;
      flipdatacheckbits(way, s, 1, 3);
      sawmiss = 0;
      fork
        begin : watch
          while (!sawmiss) begin
            @(posedge clk);
            if (CacheBusRW[1]) sawmiss = 1;
          end
        end
        begin : drive
          doload(testadr, result);
        end
      join
      check("DED clean: triggered a refetch (CacheBusRW asserted read)", sawmiss);
      check("DED clean: correct data recovered via refetch", result === 64'hCAFEF00DDEADBEEF);
    end

    // ── 5. Store to set dirty, confirm dirty bit set ──
    dirtyadr = 16'h2040; // distinct set from testadr where practical
    mem[{dirtyadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'h1111222233334444}};
    doload(dirtyadr, result); // fetch it in first
    dostore(dirtyadr, 64'h9999888877776666);
    way = findway(dirtyadr);
    s = dirtyadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
    check("store hit sets dirty", way >= 0 && peekdirty(way, s));

    // ── 6. Double-bit inject on the now-DIRTY line: must trap, NOT invalidate (would silently drop
    //       the only copy of the modified data), and must not touch valid/dirty state. ──
    begin
      bit sawfault, sawmiss;
      flipdatacheckbits(way, s, 2, 5);
      sawfault = 0; sawmiss = 0;
      fork
        begin : watchfault
          while (!sawfault && !sawmiss) begin
            @(posedge clk);
            if (EccDedDirtyFault) sawfault = 1;
            if (CacheBusRW[1]) sawmiss = 1;
          end
        end
        begin : driveload
          doload(dirtyadr, result);
        end
      join
      check("DED dirty: escalated as a fault pulse, not silently refetched", sawfault && !sawmiss);
      check("DED dirty: line remains valid and dirty afterward", peekvalid(way, s) && peekdirty(way, s));
      flipdatacheckbits(way, s, 2, 5); // restore the line before testing background scrub behavior
    end

    // ── 7. Scrubber: correct a tag SEC on an otherwise idle line and persist the correction. ──
    begin
      logic [TB_TAGCHECKWIDTH-1:0] checkbefore, checkafter;
      int tagway, tagset;
      bit found;
      tagsecadr = 16'h50A0;
      mem[{tagsecadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'h5151515151515151}};
      doload(tagsecadr, result);
      tagway = findway(tagsecadr);
      tagset = tagsecadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
      checkbefore = peektagcheck(tagway, tagset);
      fliptagcheckbits(tagway, tagset, 1);
      found = 0;
      for (int i = 0; i < 20000 && !found; i++) begin
        @(posedge clk);
        checkafter = peektagcheck(tagway, tagset);
        if (checkafter !== (checkbefore ^ (1 << 1))) found = 1;
      end
      waitclocks(2);
      check("scrubber: found and corrected a tag SEC", found);
      check("scrubber: tag SEC correction increments SEC counter", SecCount == 2);
      doload(tagsecadr, result);
      check("scrubber: corrected tag remains accessible", result === 64'h5151515151515151);
    end

    // ── 8. Scrubber: an uncorrectable tag on a clean line must invalidate, then demand refetch. ──
    begin
      int tagway, tagset;
      bit invalidated;
      tagdedadr = 16'h60C0;
      mem[{tagdedadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'h6262626262626262}};
      doload(tagdedadr, result);
      tagway = findway(tagdedadr);
      tagset = tagdedadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
      fliptagcheckbits(tagway, tagset, 0, 2);
      CacheRW = 0;
      invalidated = 0;
      for (int i = 0; i < 20000 && !invalidated; i++) begin
        @(posedge clk);
        invalidated = !peekvalid(tagway, tagset);
      end
      check("scrubber: tag DED invalidates the clean line", invalidated);
      doload(tagdedadr, result);
      check("scrubber: invalidated tag DED line is fetched correctly", result === 64'h6262626262626262);
    end

    // ── 9. Scrubber: a data DED on a clean line invalidates it and a later load refetches it. ──
    begin
      int cleanway, cleanset;
      bit invalidated;
      scrubcleanadr = 16'h70E0;
      mem[{scrubcleanadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'h7070707070707070}};
      doload(scrubcleanadr, result);
      cleanway = findway(scrubcleanadr);
      cleanset = scrubcleanadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
      flipdatacheckbits(cleanway, cleanset, 0, 2);
      CacheRW = 0;
      invalidated = 0;
      for (int i = 0; i < 20000 && !invalidated; i++) begin
        @(posedge clk);
        invalidated = !peekvalid(cleanway, cleanset);
      end
      check("scrubber: data DED invalidates a clean line", invalidated);
      doload(scrubcleanadr, result);
      check("scrubber: invalidated data DED line is fetched correctly", result === 64'h7070707070707070);
    end

    // ── 10. If an error disappears between discovery and verification, the scrubber must not
    //        commit a stale correction. ──
    begin
      int verifyway, verifyset;
      bit sawverify;
      logic [31:0] countbefore;
      scrubverifyadr = 16'h90F0;
      mem[{scrubverifyadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'h9090909090909090}};
      doload(scrubverifyadr, result);
      verifyway = findway(scrubverifyadr);
      verifyset = scrubverifyadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
      countbefore = SecCount;
      flipdatacheckbits(verifyway, verifyset, 1);
      CacheRW = 0;
      sawverify = 0;
      for (int i = 0; i < 20000 && !sawverify; i++) begin
        @(negedge clk);
        sawverify = dut.scrubber.VerifyPass;
      end
      check("scrubber: a detected error enters the verify pass", sawverify);
      if (sawverify) flipdatacheckbits(verifyway, verifyset, 1);
      waitclocks(100);
      check("scrubber: a vanished error does not cause a stale correction",
            peekvalid(verifyway, verifyset) && SecCount == countbefore);
    end

    // ── 11. Scrubber: a data DED on a dirty line must fault without invalidating it. ──
    begin
      int dirtyway, dirtyset;
      bit sawfault, sawrefetch;
      scrubdirtyadr = 16'h80A0;
      mem[{scrubdirtyadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'h8080808080808080}};
      doload(scrubdirtyadr, result);
      dostore(scrubdirtyadr, 64'h88889999AAAABBBB);
      dirtyway = findway(scrubdirtyadr);
      dirtyset = scrubdirtyadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
      flipdatacheckbits(dirtyway, dirtyset, 3, 6);
      CacheRW = 0;
      sawfault = 0; sawrefetch = 0;
      for (int i = 0; i < 20000 && !sawfault; i++) begin
        @(posedge clk);
        sawfault = EccDedDirtyFault;
        sawrefetch |= CacheBusRW[1];
        if (sawfault)
          check("scrubber: dirty data DED reports the scrubbed line address",
                EccDedDirtyFaultAdr == {scrubdirtyadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}});
      end
      check("scrubber: dirty data DED raises a fault", sawfault);
      check("scrubber: dirty data DED does not refetch and drop modified data", !sawrefetch);
      check("scrubber: dirty data DED retains valid and dirty state",
            peekvalid(dirtyway, dirtyset) && peekdirty(dirtyway, dirtyset));
    end

    // ── 12. Scrubber: inject into a line NEVER touched by any demand access, then go idle and
    //        confirm it gets found and fixed without any demand access. ──
    begin
      logic [TB_LINECHECKWIDTH-1:0] checkbefore, checkafter;
      int scrubway, scrubset;
      bit found;
      scrubadr = 16'h4080;
      mem[{scrubadr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] = {NUMWAYS{64'hABCD1234ABCD1234}};
      doload(scrubadr, result); // get a real, valid, ECC-consistent line into the cache first
      scrubway = findway(scrubadr);
      scrubset = scrubadr[SETLEN+OFFSETLEN-1:OFFSETLEN];
      CacheRW = 0; // go idle -- no further demand accesses to this line from here on
      checkbefore = peekdatacheck(scrubway, scrubset);
      flipdatacheckbits(scrubway, scrubset, 4);
      found = 0;
      for (int i = 0; i < 20000 && !found; i++) begin
        @(posedge clk);
        checkafter = peekdatacheck(scrubway, scrubset);
        if (checkafter !== (checkbefore ^ (1 << 4))) found = 1;
      end
      check("scrubber: found and corrected an error on an untouched line", found);
      check("SEC counter includes scrubber data correction", SecCount == 3);
    end

    // ── 13. Dirty miss: select and write back the victim data before the bus's first beat, then
    //        preserve the fetched line when the miss itself is a store. ──
    begin
      logic [LINELEN-1:0] expectedvictimline;
      int victimway, evictset;
      bit writebackseen;

      evictadrA = 16'h10F0;
      evictadrB = 16'h18F0;
      evictadrC = 16'h20F0; // all three addresses map to the same set
      mem[{evictadrA[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] =
        128'hA1A1A1A1A1A1A1A1_A0A0A0A0A0A0A0A0;
      mem[{evictadrB[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] =
        128'hB1B1B1B1B1B1B1B1_B0B0B0B0B0B0B0B0;
      mem[{evictadrC[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}] =
        128'hC1C1C1C1C1C1C1C1_C0C0C0C0C0C0C0C0;

      doload(evictadrA, result);
      dostore(evictadrA + 8, 64'hA2A2A2A2A2A2A2A2);
      doload(evictadrB, result);
      dostore(evictadrB, 64'hB2B2B2B2B2B2B2B2);

      evictset = evictadrA[SETLEN+OFFSETLEN-1:OFFSETLEN];
      victimway = dut.VictimWay[0] ? 0 : 1;
      expectedvictimline = peekdata(victimway, evictset);
      writebackseen = 0;
      fork
        begin : observe_dirty_writeback
          for (int i = 0; i < 50 && !writebackseen; i++) begin
            @(negedge clk);
            if (CacheBusRW[0]) begin
              writebackseen = 1;
              check("dirty eviction: victim data way selected before first writeback beat",
                    dut.SelectedWayDataQ === (2'b01 << victimway));
              check("dirty eviction: first writeback line matches the dirty victim",
                    dut.ReadDataLineCache === expectedvictimline);
            end
          end
        end
        begin : issue_store_miss
          dostore(evictadrC + 8, 64'hC2C2C2C2C2C2C2C2);
        end
      join
      check("dirty eviction: writeback request was observed", writebackseen);
      doload(evictadrC, result);
      check("store miss: untouched word came from the fetched line",
            result === 64'hC0C0C0C0C0C0C0C0);
      doload(evictadrC + 8, result);
      check("store miss: requested word was stored", result === 64'hC2C2C2C2C2C2C2C2);
    end

    // ── 14. Flush: every dirty line must use its flush-way selection for the whole writeback. ──
    begin
      int flushwrites;

      flushwrites = 0;
      fork
        begin : observe_flush_writebacks
          bit previouswrite;
          wait (FlushCache);
          previouswrite = 0;
          for (int i = 0; i < 20000 && (FlushCache || CacheStall); i++) begin
            int flushway, flushset;
            @(negedge clk);
            if (CacheBusRW[0] && !previouswrite) begin
              flushway = dut.FlushWay[0] ? 0 : 1;
              flushset = dut.FlushAdr;
              flushwrites++;
              check("flush: selected data way matches flush-way counter",
                    dut.SelectedWayDataQ === dut.FlushWay);
              check("flush: writeback line matches selected dirty cache line",
                    dut.ReadDataLineCache === peekdata(flushway, flushset));
            end
            previouswrite = CacheBusRW[0];
          end
        end
        begin : issue_flush
          FlushCache = 1;
          @(negedge clk);
          $display("DBG flush start: state=%0d stall=%b dirty=%b", dut.cachefsm.CurrState,
                   CacheStall, dut.LineDirty);
          waitidle();
          $display("DBG flush end: state=%0d stall=%b dirty=%b", dut.cachefsm.CurrState,
                   CacheStall, dut.LineDirty);
          FlushCache = 0;
          @(posedge clk);
        end
      join
      check("flush: at least one dirty line was written back", flushwrites > 0);
    end

    $display("cache_integration_tb: %0d/%0d checks passed", checks - errors, checks);
    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d FAILURES", errors);
    $finish;
  end

endmodule
