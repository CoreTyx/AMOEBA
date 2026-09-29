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
          .SCRUB_INTERVAL_CYCLES(0)) dut (
    .clk, .reset, .Stall, .FlushStage, .InvalidateFlushStage,
    .CacheRW, .FlushCache, .InvalidateCache, .CMOpM, .NextSet, .PAdr, .ByteMask, .WriteData,
    .CacheCommitted, .CacheStall, .ReadDataWord, .CacheMiss, .CacheAccess, .SelHPTW,
    .CacheBusAck, .SelBusBeat, .BeatCount, .FetchBuffer, .CacheBusRW, .CacheBusAdr,
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
  localparam int TB_TAGLEN = PA_BITS - SETLEN - OFFSETLEN;
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
  localparam int TB_TAGCHECKWIDTH  = tbrequiredr(TB_TAGLEN) + 1;
  localparam int TB_LINECHECKWIDTH = tbrequiredr(LINELEN) + 1;

  function automatic logic [TB_TAGCHECKWIDTH-1:0] peektagcheck(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].CacheTagCheckMem.ram.RAM[s];
      default: return dut.CacheWays[1].CacheTagCheckMem.ram.RAM[s];
    endcase
  endfunction

  function automatic logic [TB_LINECHECKWIDTH-1:0] peekdatacheck(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].wordram.CacheDataCheckMem.ram.RAM[s];
      default: return dut.CacheWays[1].wordram.CacheDataCheckMem.ram.RAM[s];
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
  logic [PA_BITS-1:0] testadr, dirtyadr, scrubadr;
  int way, s;

  initial begin
    clk = 0; reset = 1; errors = 0; checks = 0;
    Stall = 0; FlushStage = 0; InvalidateFlushStage = 0;
    CacheRW = 0; FlushCache = 0; InvalidateCache = 0; CMOpM = 0;
    NextSet = 0; PAdr = 0; ByteMask = 0; WriteData = 0; SelHPTW = 0;
    waitclocks(5);
    reset = 0;
    waitclocks(3);

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
    end

    // ── 7. Scrubber: inject into a line NEVER touched by any demand access, then go idle and
    //       confirm it gets found and fixed without any demand access. ──
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
    end

    $display("cache_integration_tb: %0d/%0d checks passed", checks - errors, checks);
    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d FAILURES", errors);
    $finish;
  end

endmodule
