///////////////////////////////////////////
// icache_ecc_flush_tb.sv
//
// Purpose: An I$ ECC repair must not land in another set when the access is flushed.
//
//          A hit with a correctable tag or line error goes to STATE_ECC_WRITEBACK, which writes
//          the corrected tag and line back into the hit way.  For the I$ (READ_ONLY_CACHE=1) a
//          FlushStage moves the array address to NextSet, the new PC's set.  If the flush comes in
//          the repair cycle, the repair must not be written there: that would put line A, under
//          A's tag, into another set, where a later fetch with the same tag hits it and runs A's
//          code (found by the FPGA always-on injection test, docs/impl_plan_fpga_rtl_freeze.md
//          s12.1 F1 on branch fpga/rtl_freeze).
//
//          Same small geometry and array access as cache_integration_tb.sv; the cache is an I$
//          with the scrubber off, as instantiated in ifu.sv.  For a line error and then a tag
//          error: a repair with no flush writes A's own row (so the test reaches the state), and
//          a repair with a flush to set 3 leaves set 3's rows exactly as they were and A still
//          readable.
//
// Run: make -C sim icache_ecc_flush_test
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

`include "config.vh"

module icache_ecc_flush_tb;
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

  // cachefsm.sv's statetype: STATE_ACCESS, STATE_TAG_SCAN, STATE_VICTIM_READ, STATE_DATA_DECODE,
  // STATE_AMO_WRITE, STATE_ECC_WRITEBACK, ...
  localparam int STATE_ECC_WRITEBACK = 5;

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
  logic [2:0]  SecErr;
  logic        DedErr;
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
          .LOGBWPL(LOGBWPL), .WORDLEN(WORDLEN), .MUXINTERVAL(MUXINTERVAL), .READ_ONLY_CACHE(1),
          .SCRUBBER_ENABLED(1'b0)) dut (
    .clk, .reset, .Stall, .FlushStage, .InvalidateFlushStage,
    .FaultInjectSec(1'b0), .FaultInjectDed(1'b0), .FaultLfsr('0), .FaultCount('0),
    .CacheRW, .FlushCache, .InvalidateCache, .CMOpM, .NextSet, .PAdr, .ByteMask, .WriteData,
    .CacheCommitted, .CacheStall, .CacheBusy(), .ReadDataWord, .AmoWord(), .AmoOffset('0), .CacheMiss, .CacheAccess, .SelHPTW,
    .CacheBusAck, .SelBusBeat, .BeatCount, .FetchBuffer, .CacheBusRW, .CacheBusAdr, .SecErr, .DedErr,
    .EccDedDirtyFault, .EccDedDirtyFaultAdr
  );

  always #5 clk = ~clk;

  // Memory: one line per line address; the bus acks a fetch the cycle after the request.
  logic [LINELEN-1:0] mem [logic [PA_BITS-1:0]];

  always @(posedge clk) begin
    if (reset) begin
      CacheBusAck <= 1'b0;
      FetchBuffer <= '0;
    end else begin
      CacheBusAck <= 1'b0;
      if (CacheBusRW[1] & ~CacheBusAck) begin
        FetchBuffer <= mem[{CacheBusAdr[PA_BITS-1:OFFSETLEN], {OFFSETLEN{1'b0}}}];
        CacheBusAck <= 1'b1;
      end
    end
  end
  assign SelBusBeat = 1'b0;
  assign BeatCount = '0;

  task automatic waitidle;
    int timeout;
    timeout = 0;
    while (CacheStall && timeout < 500) begin
      @(posedge clk);
      timeout++;
    end
    if (timeout >= 500) begin
      $display("FAIL: timeout waiting for CacheStall to clear (CurrState=%0d)", dut.cachefsm.CurrState);
      errors++;
    end
  endtask

  task automatic fetch(input logic [PA_BITS-1:0] adr, output logic [WORDLEN-1:0] result);
    CacheRW = 2'b10;
    PAdr = adr;
    NextSet = adr[11:0];
    @(posedge clk);
    waitidle();
    result = ReadDataWord;
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
  localparam int TB_LINEROW = LINELEN + TB_LINECHECKWIDTH;
  localparam int TB_TAGROW = TAGLEN + TB_TAGCHECKWIDTH;

  // Way w of set s is row w*NUMSETS+s of each array (cachearray.sv).
  function automatic logic [TB_LINEROW-1:0] dataraw(input int w, input int s);
    return dut.CacheArray.CacheDataMem.ram.RAM[w*NUMSETS+s][TB_LINEROW-1:0];
  endfunction

  function automatic logic [TB_TAGROW-1:0] tagraw(input int w, input int s);
    return dut.CacheArray.CacheTagMem.ram.RAM[w*NUMSETS+s][TB_TAGROW-1:0];
  endfunction

  task automatic flipdata(input int w, input int s, input int b);
    dut.CacheArray.CacheDataMem.ram.RAM[w*NUMSETS+s][TB_LINECHECKWIDTH + b] =
      ~dut.CacheArray.CacheDataMem.ram.RAM[w*NUMSETS+s][TB_LINECHECKWIDTH + b];
  endtask

  task automatic fliptag(input int w, input int s, input int b);
    dut.CacheArray.CacheTagMem.ram.RAM[w*NUMSETS+s][TB_TAGCHECKWIDTH + b] =
      ~dut.CacheArray.CacheTagMem.ram.RAM[w*NUMSETS+s][TB_TAGCHECKWIDTH + b];
  endtask

  function automatic int findway(input logic [PA_BITS-1:0] adr);
    int s;
    s = adr[SETLEN+OFFSETLEN-1:OFFSETLEN];
    for (int w = 0; w < NUMWAYS; w++)
      if (tagraw(w, s)[TB_TAGCHECKWIDTH +: TAGLEN] == adr[PA_BITS-1:SETLEN+OFFSETLEN]) return w;
    return -1;
  endfunction

  // Fetch adr, whose line holds an injected correctable error, and when the FSM reaches the repair
  // cycle optionally flush with NextSet pointing at flushadr.  Returns whether the repair cycle came.
  task automatic fetch_through_repair(input logic [PA_BITS-1:0] adr, input bit flush,
                                      input logic [PA_BITS-1:0] flushadr, output bit reached);
    int cycles;
    reached = 0;
    CacheRW = 2'b10;
    PAdr = adr;
    NextSet = adr[11:0];
    cycles = 0;
    while (!reached && cycles < 200) begin
      @(negedge clk);
      cycles++;
      if (int'(dut.cachefsm.CurrState) == STATE_ECC_WRITEBACK) begin
        reached = 1;
        if (flush) begin
          FlushStage = 1;
          NextSet = flushadr[11:0];
        end
      end
    end
    @(negedge clk);
    FlushStage = 0;
    CacheRW = 2'b00;
    NextSet = adr[11:0];
    repeat (4) @(posedge clk);
    waitidle();
  endtask

  // A in set 1, B in set 3 with a different tag; C, D refill set 3 with other tags after B.
  localparam logic [PA_BITS-1:0] ADR_A = 16'h0410;
  localparam logic [PA_BITS-1:0] ADR_B = 16'h0230;
  localparam logic [PA_BITS-1:0] ADR_C = 16'h0830;

  logic [WORDLEN-1:0]   result;
  logic [TB_LINEROW-1:0] set3_data [NUMWAYS];
  logic [TB_TAGROW-1:0]  set3_tag  [NUMWAYS];
  logic [TB_LINEROW-1:0] a_data_clean;
  logic [TB_TAGROW-1:0]  a_tag_clean;
  bit   reached;
  int   wa;
  bit   set3_same;

  task automatic snapshot_set3;
    for (int w = 0; w < NUMWAYS; w++) begin
      set3_data[w] = dataraw(w, 3);
      set3_tag[w]  = tagraw(w, 3);
    end
  endtask

  function automatic bit set3_unchanged;
    for (int w = 0; w < NUMWAYS; w++)
      if (dataraw(w, 3) !== set3_data[w] || tagraw(w, 3) !== set3_tag[w]) return 0;
    return 1;
  endfunction

  initial begin
    clk = 0; reset = 1; errors = 0; checks = 0;
    Stall = 0; FlushStage = 0; InvalidateFlushStage = 0;
    CacheRW = 0; FlushCache = 0; InvalidateCache = 0; CMOpM = 0;
    NextSet = 0; PAdr = 0; ByteMask = 0; WriteData = 0; SelHPTW = 0;
    mem[ADR_A & ~16'hF] = {64'h1111_2222_3333_4444, 64'hAAAA_BBBB_CCCC_DDDD};
    mem[ADR_B & ~16'hF] = {64'h5555_6666_7777_8888, 64'hEEEE_FFFF_0000_1234};
    mem[ADR_C & ~16'hF] = {64'h9999_0000_1111_2222, 64'h3333_4444_5555_6666};
    repeat (5) @(posedge clk);
    reset = 0;
    repeat (3) @(posedge clk);

    fetch(ADR_A, result);
    fetch(ADR_B, result);
    fetch(ADR_C, result);
    wa = findway(ADR_A);
    check("A is cached in set 1", wa >= 0);
    a_data_clean = dataraw(wa, 1);
    a_tag_clean  = tagraw(wa, 1);

    // ── Line error, no flush: the repair writes A's own row ──
    flipdata(wa, 1, 5);
    fetch_through_repair(ADR_A, 0, '0, reached);
    check("line error: the hit reaches STATE_ECC_WRITEBACK", reached);
    check("line error, no flush: A's row is repaired", dataraw(wa, 1) === a_data_clean);

    // ── Line error, flush to set 3 in the repair cycle: set 3 is untouched ──
    flipdata(wa, 1, 5);
    snapshot_set3();
    fetch_through_repair(ADR_A, 1, ADR_B, reached);
    check("line error + flush: the hit reaches STATE_ECC_WRITEBACK", reached);
    set3_same = set3_unchanged();
    check("line error + flush: set 3's rows are untouched", set3_same);
    fetch(ADR_B, result);
    check("line error + flush: B still reads its own data", result === 64'hEEEE_FFFF_0000_1234);
    fetch(ADR_A, result);
    check("line error + flush: A still reads its own data", result === 64'hAAAA_BBBB_CCCC_DDDD);

    // ── Tag error, flush to set 3 in the repair cycle: set 3 is untouched ──
    fliptag(wa, 1, 2);
    snapshot_set3();
    fetch_through_repair(ADR_A, 1, ADR_B, reached);
    check("tag error + flush: the hit reaches STATE_ECC_WRITEBACK", reached);
    set3_same = set3_unchanged();
    check("tag error + flush: set 3's rows are untouched", set3_same);
    fetch(ADR_B, result);
    check("tag error + flush: B still reads its own data", result === 64'hEEEE_FFFF_0000_1234);
    fetch(ADR_A, result);
    check("tag error + flush: A still reads its own data", result === 64'hAAAA_BBBB_CCCC_DDDD);
    check("tag error: A's row is repaired by the later unflushed read",
          tagraw(wa, 1) === a_tag_clean && dataraw(wa, 1) === a_data_clean);

    $display("icache_ecc_flush_tb: %0d/%0d checks passed", checks - errors, checks);
    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d FAILURES", errors);
    $finish;
  end

endmodule
