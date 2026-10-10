///////////////////////////////////////////
// cache_edge_tb.sv
//
// Purpose: Demand-path edge cases for the SECDED D$, with the background scrubber DISABLED
//          (SCRUBBER_ENABLED=0, matching how lsu.sv instantiates the real D$). Complements
//          cache_integration_tb.sv, which runs with the scrubber on.
//
//          Unlike cache_integration_tb, the bus model here records every writeback (address and
//          line) into the behavioral memory, so tests can check what actually reaches memory on an
//          eviction or flush -- not just what the cache returns to the core.
//
//          Each numbered section states the property it checks. Sections 5-9 cover design gaps
//          that were found with this testbench and then fixed:
//            - valid-bit 1->0 flip on a dirty line silently dropped modified data
//            - uncorrectable tag on a dirty line lost the data / wrote back to a wrong address
//            - dirty eviction / flush wrote back uncorrected (raw) data
//
//          The final section is a seeded random load/store run checked against a reference
//          memory, first without and then with injected single-bit data errors.
//
// Run: make -C sim cache_edge_test [SEED=n]
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

`include "config.vh"

module cache_edge_tb;
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
  int dedfaults;

  cache #(.P(P), .PA_BITS(PA_BITS), .LINELEN(LINELEN), .NUMSETS(NUMSETS), .NUMWAYS(NUMWAYS),
          .LOGBWPL(LOGBWPL), .WORDLEN(WORDLEN), .MUXINTERVAL(MUXINTERVAL), .READ_ONLY_CACHE(0),
          .SCRUBBER_ENABLED(1'b0), .SCRUB_INTERVAL_CYCLES(0)) dut (
    .clk, .reset, .Stall, .FlushStage, .InvalidateFlushStage,
    .CacheRW, .FlushCache, .InvalidateCache, .CMOpM, .NextSet, .PAdr, .ByteMask, .WriteData,
    .CacheCommitted, .CacheStall, .ReadDataWord, .CacheMiss, .CacheAccess, .SelHPTW,
    .CacheBusAck, .SelBusBeat, .BeatCount, .FetchBuffer, .CacheBusRW, .CacheBusAdr, .SecCount,
    .EccDedDirtyFault, .EccDedDirtyFaultAdr
  );

  // ── Clock ──────────────────────────────────────────────────────────────────────────────────
  always #5 clk = ~clk;

  // ── Behavioral memory (what the bus side holds) and reference model (what it should hold) ──
  logic [LINELEN-1:0] mem    [logic [PA_BITS-1:0]];
  // Reference model as a fixed array indexed by line number (+ a "has entry" bit) rather than an
  // associative array: Verilator can insert default entries on associative reads.
  localparam int NUMLINES = 1 << (PA_BITS - OFFSETLEN);
  logic [LINELEN-1:0] refline [NUMLINES];
  bit                 refhas  [NUMLINES];
  bit                 everfetched [logic [PA_BITS-1:0]]; // line addresses the cache has ever filled

  function automatic int lineidx(input logic [PA_BITS-1:0] adr);
    return int'(adr[PA_BITS-1:OFFSETLEN]);
  endfunction

  function automatic logic [LINELEN-1:0] refget(input logic [PA_BITS-1:0] adr);
    if (refhas[lineidx(adr)]) return refline[lineidx(adr)];
    else return mem_read({adr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}});
  endfunction

  task automatic refset(input logic [PA_BITS-1:0] adr, input logic [LINELEN-1:0] v);
    refline[lineidx(adr)] = v;
    refhas[lineidx(adr)] = 1'b1;
  endtask

  function automatic logic [PA_BITS-1:0] lineof(input logic [PA_BITS-1:0] adr);
    return {adr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}};
  endfunction

  function automatic int setof(input logic [PA_BITS-1:0] adr);
    return int'(adr[SETLEN+OFFSETLEN-1:OFFSETLEN]);
  endfunction

  function automatic logic [LINELEN-1:0] mem_read(input logic [PA_BITS-1:0] lineadr);
    if (mem.exists(lineadr)) return mem[lineadr];
    else return {NUMWAYS{64'hBAD0BAD0BAD0BAD0}};
  endfunction

  // Seed one line identically in memory and the reference model.
  task automatic setline(input logic [PA_BITS-1:0] adr, input logic [LINELEN-1:0] v);
    mem[lineof(adr)] = v;
    refset(adr, v);
  endtask

  // ── Bus responder: fetch returns mem[line]; writeback records the full line into mem ──
  // The writeback line is sampled from dut.ReadDataLine (the line the cache presents to the bus,
  // after the early-return mux) on the request cycle, before the ack.
  int wbcount;
  logic [PA_BITS-1:0] lastwbadr;

  always @(posedge clk) begin
    if (reset) begin
      CacheBusAck <= 1'b0;
      FetchBuffer <= '0;
    end else begin
      CacheBusAck <= 1'b0;
      if (CacheBusRW[1] & ~CacheBusAck) begin
        FetchBuffer <= mem_read(lineof(CacheBusAdr));
        everfetched[lineof(CacheBusAdr)] = 1'b1;
        CacheBusAck <= 1'b1;
      end else if (CacheBusRW[0] & ~CacheBusAck) begin
        CacheBusAck <= 1'b1;
      end
    end
  end

  always @(negedge clk) begin
    if (!reset && CacheBusRW[0] && !CacheBusAck) begin
      mem[lineof(CacheBusAdr)] = dut.ReadDataLine;
      lastwbadr = lineof(CacheBusAdr);
      wbcount++;
    end
  end

  logic [PA_BITS-1:0] lastfaultadr;
  always @(posedge clk) if (!reset && EccDedDirtyFault) begin
    dedfaults++;
    lastfaultadr = {EccDedDirtyFaultAdr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}};
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
        $display("FAIL: timeout waiting for CacheStall to clear (CurrState=%0d CacheRW=%b)",
                  dut.cachefsm.CurrState, CacheRW);
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

  // Store a full word, and mirror it into the reference model.
  task automatic dostore(input logic [PA_BITS-1:0] adr, input logic [WORDLEN-1:0] data);
    logic [LINELEN-1:0] l;
    CacheRW = 2'b01;
    PAdr = adr;
    NextSet = adr[11:0];
    WriteData = data;
    ByteMask = '1;
    @(posedge clk);
    waitidle();
    CacheRW = 2'b00;
    @(posedge clk);
    l = refget(adr);
    l[int'(adr[OFFSETLEN-1:3])*64 +: 64] = data;
    refset(adr, l);
  endtask

  task automatic doflush;
    FlushCache = 1;
    @(negedge clk);
    waitidle();
    FlushCache = 0;
    @(posedge clk);
  endtask

  // Clear all valid state between tests so each starts from an empty cache. Only call when no
  // dirty data still matters (memory contents are kept).
  task automatic doreset;
    reset = 1;
    waitclocks(3);
    reset = 0;
    waitclocks(3);
  endtask

  function automatic logic [WORDLEN-1:0] refword(input logic [PA_BITS-1:0] adr);
    logic [LINELEN-1:0] l;
    l = refget(adr);
    return l[int'(adr[OFFSETLEN-1:3])*64 +: 64];
  endfunction

  task automatic check(input string what, input bit ok);
    checks++;
    if (!ok) begin
      $display("FAIL: %s", what);
      errors++;
    end else $display("PASS: %s", what);
    $fflush();
  endtask

  // ── Hierarchical peek/poke into the behavioral arrays (USE_SRAM=0) ──
  function automatic logic [LINELEN-1:0] peekdata(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].wordram.CacheDataMem.ram.RAM[s];
      default: return dut.CacheWays[1].wordram.CacheDataMem.ram.RAM[s];
    endcase
  endfunction

  task automatic flipdatabit(input int w, input int s, input int b);
    case (w)
      0: dut.CacheWays[0].wordram.CacheDataMem.ram.RAM[s][b] = ~dut.CacheWays[0].wordram.CacheDataMem.ram.RAM[s][b];
      default: dut.CacheWays[1].wordram.CacheDataMem.ram.RAM[s][b] = ~dut.CacheWays[1].wordram.CacheDataMem.ram.RAM[s][b];
    endcase
  endtask

  task automatic fliptagbit(input int w, input int s, input int b);
    case (w)
      0: dut.CacheWays[0].CacheTagMem.ram.RAM[s][b] = ~dut.CacheWays[0].CacheTagMem.ram.RAM[s][b];
      default: dut.CacheWays[1].CacheTagMem.ram.RAM[s][b] = ~dut.CacheWays[1].CacheTagMem.ram.RAM[s][b];
    endcase
  endtask

  task automatic clearvalidredundant(input int w, input int s);
    case (w)
      0: dut.CacheWays[0].ValidBitsRedundant[s] = 1'b0;
      default: dut.CacheWays[1].ValidBitsRedundant[s] = 1'b0;
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

  function automatic logic [TAGLEN-1:0] peektag(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].CacheTagMem.ram.RAM[s];
      default: return dut.CacheWays[1].CacheTagMem.ram.RAM[s];
    endcase
  endfunction

  function automatic int findway(input logic [PA_BITS-1:0] adr);
    int s;
    s = setof(adr);
    for (int w = 0; w < NUMWAYS; w++)
      if (peekvalid(w, s) && peektag(w, s) == adr[PA_BITS-1:SETLEN+OFFSETLEN]) return w;
    return -1;
  endfunction

  // Three distinct line addresses that share `adr`'s set, used to force evictions.
  function automatic logic [PA_BITS-1:0] alias_of(input logic [PA_BITS-1:0] adr, input int k);
    return adr + PA_BITS'((k + 1) * (NUMSETS << OFFSETLEN));
  endfunction

  // ── Probe decoder: lets the random test ask "does this stored line already hold an error?" ──
  function automatic int tbrequiredr(input int dw);
    return (dw <=    1) ?  2 : (dw <=    4) ?  3 : (dw <=   11) ?  4 : (dw <=   26) ?  5 :
           (dw <=   57) ?  6 : (dw <=  120) ?  7 : (dw <=  247) ?  8 : (dw <=  502) ?  9 :
           (dw <= 1013) ? 10 : 11;
  endfunction
  localparam int TB_LINECHECKR = tbrequiredr(LINELEN);

  logic [LINELEN+TB_LINECHECKR:0] probecw;
  logic [LINELEN-1:0]             probedata;
  logic                           probesec, probeded;
  cacheeccdec #(.DATA_WIDTH(LINELEN), .R(TB_LINECHECKR)) probe (
    .codeword_i(probecw), .data_o(probedata), .sec_err_o(probesec), .ded_err_o(probeded));

  function automatic logic [TB_LINECHECKR:0] peekdatacheck(input int w, input int s);
    case (w)
      0: return dut.CacheWays[0].wordram.CacheDataCheckMem.ram.RAM[s];
      default: return dut.CacheWays[1].wordram.CacheDataCheckMem.ram.RAM[s];
    endcase
  endfunction

  task automatic lineclean(input int w, input int s, output bit clean);
    probecw = {peekdata(w, s), peekdatacheck(w, s)};
    // Let the probe decoder settle by waiting for the next falling edge, like the rest of this
    // bench samples. (A bare #1 here aborted Verilator's --timing scheduler: "Missed a time slot?")
    @(negedge clk);
    clean = !probesec && !probeded;
  endtask

  // ── Random run: one phase of NOPS random loads/stores over 4 tags x NUMSETS lines ──
  task automatic randomphase(input string name, input int nops, input bit inject);
    int loadfails, memfails, injected, faultsbefore;
    logic [PA_BITS-1:0] adr;
    logic [WORDLEN-1:0] r, d;
    loadfails = 0; memfails = 0; injected = 0; faultsbefore = dedfaults;
    foreach (refhas[i]) refhas[i] = 0; // judge only this phase's lines (earlier directed tests leave known mismatches)
    for (int i = 0; i < nops; i++) begin
      adr = PA_BITS'(16'h4000 + (($urandom % 4) << 7) + (($urandom % NUMSETS) << OFFSETLEN) + (($urandom % 2) << 3));
      if ($urandom % 2) begin
        doload(adr, r);
        if (r !== refword(adr)) begin
          if (loadfails < 5) $display("  [%s] op %0d load %h: got %h expected %h", name, i, adr, r, refword(adr));
          loadfails++;
        end
      end else begin
        d = {$urandom, $urandom};
        dostore(adr, d);
      end
      // Occasionally plant a single-bit DATA error in a random valid line that is currently
      // error-free (so errors never accumulate into an uncorrectable double).
      if (inject && ($urandom % 8 == 0)) begin
        int w, s;
        bit clean;
        w = $urandom % NUMWAYS;
        s = $urandom % NUMSETS;
        lineclean(w, s, clean);
        if (peekvalid(w, s) && clean) begin
          flipdatabit(w, s, $urandom % LINELEN);
          injected++;
        end
      end
    end
    doflush();
    for (int i = 0; i < NUMLINES; i++)
      if (refhas[i]) begin
        logic [PA_BITS-1:0] la;
        la = PA_BITS'(i << OFFSETLEN);
        if (mem_read(la) !== refline[i]) begin
          if (memfails < 5) $display("  [%s] memory line %h after flush: got %h expected %h", name, la, mem_read(la), refline[i]);
          memfails++;
        end
      end
    $display("  [%s] %0d ops, %0d errors injected, %0d bad loads, %0d bad memory lines, EccDedDirtyFaults seen: %0d",
             name, nops, injected, loadfails, memfails, dedfaults - faultsbefore);
    check({"random ", name, ": every load returned the reference value"}, loadfails == 0);
    check({"random ", name, ": memory matches the reference after flush"}, memfails == 0);
  endtask

  // ── 9b. Uncorrectable (2-bit) DATA error on a DIRTY line that is evicted without being read.
  //        The cache must report the loss (fault) and must not write the corrupted line to memory
  //        as if it were good data. (Separate task: keeps the main initial block's coroutine frame
  //        small -- Verilator --timing crashed at startup when these were inlined.) ──
  task automatic test_ded_dirty_evict;
    logic [PA_BITS-1:0] adr;
    logic [WORDLEN-1:0] r;
    logic [LINELEN-1:0] memold;
    int way, set, faultsbefore;
    adr = 16'h1090;
    setline(adr, 128'h5656565656565656_7878787878787878);
    setline(alias_of(adr, 0), 128'h0);
    setline(alias_of(adr, 1), 128'h0);
    doload(adr, r);
    dostore(adr, 64'h1357135713571357);
    way = findway(adr); set = setof(adr);
    faultsbefore = dedfaults;
    memold = mem_read(adr);
    flipdatabit(way, set, 10);
    flipdatabit(way, set, 90);
    doload(alias_of(adr, 0), r);
    doload(alias_of(adr, 1), r);            // evicts adr
    check("data DED, dirty victim: eviction raises a fault", dedfaults != faultsbefore);
    check("data DED, dirty victim: corrupted line not written to memory", mem_read(adr) === memold);
    check("data DED, dirty victim: fault address is the lost line",
          dedfaults != faultsbefore && lastfaultadr == lineof(adr));
    doreset();
  endtask

  // ── 9c. Same, but the dirty line is written out by a full-cache flush. Run with the bad line
  //        in way 0 and in the last way: the last-way case is when the flush counters move on to
  //        the next set, so a clean, valid neighbour in the next set must survive untouched. ──
  task automatic test_ded_dirty_flush(input bit lastway);
    logic [PA_BITS-1:0] adr, other, neighbour;
    logic [WORDLEN-1:0] r;
    logic [LINELEN-1:0] memold;
    int way, set, faultsbefore;
    string tag;
    tag = lastway ? " (last way)" : " (way 0)";
    adr = 16'h10A0;
    other = alias_of(adr, 0);
    neighbour = adr + PA_BITS'(1 << OFFSETLEN);     // next set
    setline(adr, 128'h9A9A9A9A9A9A9A9A_BCBCBCBCBCBCBCBC);
    setline(other, 128'h0F0F0F0F0F0F0F0F_F0F0F0F0F0F0F0F0);
    setline(neighbour, 128'h3C3C3C3C3C3C3C3C_C3C3C3C3C3C3C3C3);
    doload(neighbour, r);
    doload(neighbour + PA_BITS'(NUMSETS << OFFSETLEN), r); // fill the neighbour set's other way too
    if (lastway) doload(other, r);          // occupy way 0 first so adr lands in the last way
    doload(adr, r);
    dostore(adr + 8, 64'h2468246824682468);
    way = findway(adr); set = setof(adr);
    check({"data DED flush", tag, ": bad line is in the intended way"}, way == (lastway ? NUMWAYS - 1 : 0));
    faultsbefore = dedfaults;
    memold = mem_read(adr);
    flipdatabit(way, set, 1);
    flipdatabit(way, set, 77);
    doflush();
    check({"data DED, dirty line", tag, ": flush raises a fault"}, dedfaults != faultsbefore);
    check({"data DED, dirty line", tag, ": flush does not write the corrupted line"}, mem_read(adr) === memold);
    check({"data DED, dirty line", tag, ": line is not left valid after the flush"}, findway(adr) < 0);
    check({"data DED, dirty line", tag, ": fault address is the lost line"},
          dedfaults != faultsbefore && lastfaultadr == lineof(adr));
    check({"data DED, dirty line", tag, ": next set's line survives the flush"}, findway(neighbour) >= 0);
    doreset();
  endtask

  // ── 9d. Uncorrectable TAG error on a dirty line in the last way, found by a flush (never accessed
  //        first). Must fault, must not write back to a wrong address, and the next set's line must
  //        survive (same flush-counter look-ahead hazard as 9c). ──
  task automatic test_tagded_dirty_flush;
    logic [PA_BITS-1:0] adr, other, neighbour;
    logic [WORDLEN-1:0] r;
    int way, set, faultsbefore, wbbefore;
    adr = 16'h10C0;
    other = alias_of(adr, 0);
    neighbour = adr + PA_BITS'(1 << OFFSETLEN);
    setline(adr, 128'h1111222233334444_5555666677778888);
    setline(other, 128'h0);
    setline(neighbour, 128'hABABABABABABABAB_CDCDCDCDCDCDCDCD);
    doload(neighbour, r);
    doload(neighbour + PA_BITS'(NUMSETS << OFFSETLEN), r);
    doload(other, r);
    doload(adr, r);
    dostore(adr, 64'h0BADF00D0BADF00D);
    way = findway(adr); set = setof(adr);
    check("tag DED flush: bad line is in the last way", way == NUMWAYS - 1);
    faultsbefore = dedfaults;
    wbbefore = wbcount;
    fliptagbit(way, set, 4);
    fliptagbit(way, set, 5);
    doflush();
    check("tag DED flush: flush raises a fault", dedfaults != faultsbefore);
    check("tag DED flush: no writeback was issued for it", wbcount == wbbefore);
    check("tag DED flush: bad line is invalidated", !peekvalid(way, set));
    check("tag DED flush: next set's line survives the flush", findway(neighbour) >= 0);
    doreset();
  endtask

  logic [WORDLEN-1:0] result;
  logic [PA_BITS-1:0] a;
  int w, s, seed;

  initial begin
    if (!$value$plusargs("SEED=%d", seed)) seed = 1;
    void'($urandom(seed));
    clk = 0; reset = 1; errors = 0; checks = 0; wbcount = 0; dedfaults = 0;
    Stall = 0; FlushStage = 0; InvalidateFlushStage = 0;
    CacheRW = 0; FlushCache = 0; InvalidateCache = 0; CMOpM = 0;
    NextSet = 0; PAdr = 0; ByteMask = 0; WriteData = 0; SelHPTW = 0;
    waitclocks(5);
    reset = 0;
    waitclocks(3);
    $display("cache_edge_tb: seed %0d, scrubber disabled", seed);

    // ── 1. Baseline (no faults): dirty eviction writes the right line to the right address.
    //       Validates the writeback-capturing bus model the later tests depend on. ──
    a = 16'h1000;
    setline(a, 128'hA1A1A1A1A1A1A1A1_A0A0A0A0A0A0A0A0);
    setline(alias_of(a, 0), 128'hB1B1B1B1B1B1B1B1_B0B0B0B0B0B0B0B0);
    setline(alias_of(a, 1), 128'hC1C1C1C1C1C1C1C1_C0C0C0C0C0C0C0C0);
    doload(a, result);
    dostore(a + 8, 64'hA2A2A2A2A2A2A2A2);
    doload(alias_of(a, 0), result);
    doload(alias_of(a, 1), result); // evicts a (LRU)
    check("baseline: dirty eviction wrote back the stored line", mem_read(a) === refget(a));
    check("baseline: evicted line is no longer resident", findway(a) < 0);
    doload(a + 8, result);
    check("baseline: re-fetched line returns the stored word", result === 64'hA2A2A2A2A2A2A2A2);
    doflush(); doreset();

    // ── 2. Load from a line with a single-bit DATA error (in the word being read). The core must
    //       get the corrected value on that same access, not only on a later re-read. ──
    a = 16'h1010;
    setline(a, 128'h2222222222222222_1111111111111111);
    doload(a, result);
    w = findway(a); s = setof(a);
    flipdatabit(w, s, 5);
    doload(a, result);
    check("SEC data: load returns corrected word on the faulting access", result === 64'h1111111111111111);
    doload(a, result);
    check("SEC data: subsequent load also correct", result === 64'h1111111111111111);
    doreset();

    // ── 3. Single-bit TAG error and single-bit DATA error at once (both correctable). ──
    a = 16'h1020;
    setline(a, 128'h4444444444444444_3333333333333333);
    doload(a, result);
    w = findway(a); s = setof(a);
    begin
      logic [31:0] seccountbefore;
      seccountbefore = SecCount;
      fliptagbit(w, s, 2);
      flipdatabit(w, s, 70);
      doload(a + 8, result);
      check("SEC tag+data: load hits and returns corrected word", result === 64'h4444444444444444);
      check("SEC tag+data: no refetch (still the same way)", findway(a) == w);
      check("SEC tag+data: SEC counter counted both corrections", SecCount == seccountbefore + 2);
    end
    doreset();

    // ── 4. Store hit to a line that holds a single-bit error in ANOTHER word. Both the new store
    //       and the corrected neighbour must survive. ──
    a = 16'h1030;
    setline(a, 128'h6666666666666666_5555555555555555);
    doload(a, result);
    w = findway(a); s = setof(a);
    flipdatabit(w, s, 64 + 9);              // error in word 1
    dostore(a, 64'h0123456789ABCDEF);       // store to word 0
    doload(a, result);
    check("SEC + store hit: stored word is intact", result === 64'h0123456789ABCDEF);
    doload(a + 8, result);
    check("SEC + store hit: neighbouring word was corrected", result === 64'h6666666666666666);
    doflush();
    check("SEC + store hit: flushed line matches reference", mem_read(a) === refget(a));
    doreset();

    // ── 5. [suspected flaw] Dirty victim holding a latent single-bit error is evicted without
    //       being read first. Memory must receive the CORRECTED line. ──
    a = 16'h1040;
    setline(a, 128'h8888888888888888_7777777777777777);
    setline(alias_of(a, 0), 128'h0);
    setline(alias_of(a, 1), 128'h0);
    doload(a, result);
    dostore(a, 64'hDEADBEEFDEADBEEF);
    w = findway(a); s = setof(a);
    flipdatabit(w, s, 100);                 // latent error in the dirty line's word 1
    doload(alias_of(a, 0), result);
    doload(alias_of(a, 1), result);         // evicts a
    check("SEC on dirty victim: eviction writes corrected data to memory", mem_read(a) === refget(a));
    doreset();

    // ── 6. [suspected flaw] Same as 5, but via a full-cache flush instead of eviction. ──
    a = 16'h1050;
    setline(a, 128'hAAAAAAAAAAAAAAAA_9999999999999999);
    doload(a, result);
    dostore(a + 8, 64'hFEEDFACEFEEDFACE);
    w = findway(a); s = setof(a);
    flipdatabit(w, s, 3);                   // latent error in word 0
    doflush();
    check("SEC on dirty line: flush writes corrected data to memory", mem_read(a) === refget(a));
    doreset();

    // ── 7. Valid-bit redundancy, CLEAN line: one copy flips 1->0. A spurious miss is fine here
    //       because memory still holds the data. ──
    a = 16'h1060;
    setline(a, 128'hCCCCCCCCCCCCCCCC_BBBBBBBBBBBBBBBB);
    doload(a, result);
    w = findway(a); s = setof(a);
    clearvalidredundant(w, s);
    doload(a, result);
    check("valid flip, clean line: load still returns correct data", result === 64'hBBBBBBBBBBBBBBBB);
    doreset();

    // ── 8. [suspected flaw] Valid-bit redundancy, DIRTY line: one copy flips 1->0. The modified
    //       data must not be silently replaced by the stale memory copy. Either the right data
    //       comes back, or the cache raises a fault -- silent stale data is the failure. ──
    a = 16'h1070;
    setline(a, 128'hEEEEEEEEEEEEEEEE_DDDDDDDDDDDDDDDD);
    doload(a, result);
    dostore(a, 64'h5A5A5A5A5A5A5A5A);
    w = findway(a); s = setof(a);
    begin
      int faultsbefore;
      faultsbefore = dedfaults;
      clearvalidredundant(w, s);
      doload(a, result);
      check("valid flip, dirty line: modified data not silently lost",
            result === 64'h5A5A5A5A5A5A5A5A || dedfaults != faultsbefore);
    end
    doflush();
    check("valid flip, dirty line: memory ends up with the modified data", mem_read(a) === refget(a));
    doreset();

    // ── 9. [suspected flaw] Uncorrectable (2-bit) TAG error on a DIRTY line. The line can no
    //       longer be matched, so the core sees a miss. Required: the modified data is not
    //       silently lost, and nothing is ever written back to an address the cache never held. ──
    a = 16'h1080;
    setline(a, 128'h1212121212121212_3434343434343434);
    setline(alias_of(a, 0), 128'h0);
    setline(alias_of(a, 1), 128'h0);
    setline(alias_of(a, 2), 128'h0);
    doload(a, result);
    dostore(a, 64'h7777777777777777);
    w = findway(a); s = setof(a);
    begin
      int faultsbefore, wbbefore;
      bit strayadr;
      faultsbefore = dedfaults;
      wbbefore = wbcount;
      fliptagbit(w, s, 4);                 // address bits 11 and 12: the corrupted tag names 0x0880,
      fliptagbit(w, s, 5);                 // a line no test ever touches
      doload(a, result);
      check("tag DED, dirty line: load returns modified data or raises a fault",
            result === 64'h7777777777777777 || dedfaults != faultsbefore);
      // Push the corrupted way out of the set and watch where its writeback goes.
      strayadr = 0;
      for (int k = 0; k < 3; k++) begin
        doload(alias_of(a, k), result);
        if (wbcount != wbbefore && !everfetched.exists(lastwbadr)) strayadr = 1;
        wbbefore = wbcount;
      end
      if (strayadr) $display("  stray writeback to never-cached line %h", lastwbadr);
      check("tag DED, dirty line: no writeback to an address the cache never held", !strayadr);
    end
    doflush();
    // With the tag unrecoverable the data cannot reach its real address; the requirement is that
    // the loss is reported (fault), not that memory is somehow repaired.
    check("tag DED, dirty line: data reaches memory, or the loss was reported",
          mem_read(a) === refget(a) || dedfaults != 0);
    doreset();

    // ── 9b / 9c. Uncorrectable DATA error on a dirty line leaving via eviction / flush. ──
    test_ded_dirty_evict();
    test_ded_dirty_flush(0);
    test_ded_dirty_flush(1);
    test_tagded_dirty_flush();

    // ── 10. Random load/store run against the reference model, no faults injected. ──
    randomphase("no-inject", 1500, 0);
    doreset();

    // ── 11. Same, with single-bit data errors planted in resident lines. All are correctable,
    //        so loads AND final memory contents must still match the reference. ──
    randomphase("inject", 1500, 1);

    $display("cache_edge_tb: %0d/%0d checks passed", checks - errors, checks);
    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d FAILURES", errors);
    $finish;
  end

endmodule
