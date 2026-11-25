// Fault counters and last-error records.  APB slave at ECC_COUNTER_BASE, 32-bit words.
// Counters: 16-bit, saturating; counter i is the word at offset 4*i, reading {16'b0, count}.
// Software clears one by writing (any value) to its word, or all of them by writing word 31;
// reset clears them too.  An event in the cycle of the clear still counts.
//   0 register-file SEC     1 register-file DED     2 pipeline-register SEC   3 pipeline-register DED
//   4 I$ SEC                5 I$ DED                6 D$ SEC                  7 D$ DED
//   8 ALU mismatch          9 ALU unresolved       10 CMP mismatch           11 CMP unresolved
//  12 MUL residue mismatch 13 MUL unresolved       14 DIV residue mismatch   15 DIV unresolved
//  16 priv-mode TMR corrected                      17 priv-mode TMR uncorrectable
// Breakdown of the cache counters above (4-7 keep their totals, so tag and data can be told apart):
//  18 I$ tag SEC           19 I$ tag DED           20 D$ tag SEC             21 D$ tag DED
//  22 D$ modified data lost: each report of a dirty line that could not be kept (trap cause 20/21);
//     5/7 minus the tag DEDs and this are uncorrectable lines that were dropped and refetched, harmlessly
// Last uncorrectable error of each cache (the *CacheDed events: what counters 5/7 count):
//  24 D$ record   25 D$ line address   26 I$ record   27 I$ line address
//  record: [0] VALID  [1] MULTIPLE (another error came after the first since the record was
//          cleared; the record holds the newest)  [2] TAG (the tag was uncorrectable: the line
//          address is unknown, word 25/27 is meaningless)  [3] LOST (D$: dirty data lost, trap
//          cause 20/21)  [5:4] SOURCE (0 lookup, 1 eviction, 2 flush, 3 scrubber)
//          [11:8] WAYS (the way(s) dropped, one bit each)  [27:16] SET
//  line address: physical address [31:0] of the line, when TAG is 0
// Writing (any value) to a record word clears that cache's record; an error in the same cycle
// wins.  Reads of words 23, 28-31 return 0.
// Every detected error counts: two read ports corrected in one cycle count two.  The events
// arrive registered from the core, so the counting adds nothing to any core path.
module faultcount_apb import cvw::*; #(
  parameter int XLEN = 64
) (
  input  logic            PCLK, PRESETn,
  input  logic            DFTHold,      // DFT hold: no counting (forte_chip.sv)
  input  logic            PSEL, PENABLE, PWRITE,
  input  logic [6:2]      PADDR,
  output logic [XLEN-1:0] PRDATA,
  output logic            PREADY,
  input  fault_events_t   FaultEvents
);
  localparam int W = 16;

  function automatic logic [2:0] ones(input logic [4:0] flags);
    ones = '0;
    for (int i = 0; i < 5; i++) ones = ones + 3'(flags[i]);
  endfunction

  // Levels are counted once per occurrence, on their rising edge
  logic [1:0] FTUnresolvedQ, ResidueUnresolvedQ;
  logic       TmrCorrectedQ, TmrUncorrectableQ;
  always_ff @(posedge PCLK)
    if (!PRESETn) {FTUnresolvedQ, ResidueUnresolvedQ, TmrCorrectedQ, TmrUncorrectableQ} <= '0;
    else if (~DFTHold) {FTUnresolvedQ, ResidueUnresolvedQ, TmrCorrectedQ, TmrUncorrectableQ} <=
                  {FaultEvents.FTUnresolved, FaultEvents.ResidueUnresolved, FaultEvents.TmrCorrected, FaultEvents.TmrUncorrectable};

  logic [FAULT_COUNTERS-1:0][2:0] Inc;
  always_comb begin
    Inc[0]  = ones(5'(FaultEvents.RegfileSec));
    Inc[1]  = ones(5'(FaultEvents.RegfileDed));
    Inc[2]  = ones(FaultEvents.PipeSec);
    Inc[3]  = ones(FaultEvents.PipeDed);
    Inc[4]  = ones(5'(FaultEvents.ICacheSec));
    Inc[5]  = 3'(FaultEvents.ICacheDed);
    Inc[6]  = ones(5'(FaultEvents.DCacheSec));
    Inc[7]  = 3'(FaultEvents.DCacheDed);
    Inc[8]  = 3'(FaultEvents.FTDetect[0]);
    Inc[9]  = 3'(FaultEvents.FTUnresolved[0] & ~FTUnresolvedQ[0]);
    Inc[10] = 3'(FaultEvents.FTDetect[1]);
    Inc[11] = 3'(FaultEvents.FTUnresolved[1] & ~FTUnresolvedQ[1]);
    Inc[12] = 3'(FaultEvents.ResidueDetect[0]);
    Inc[13] = 3'(FaultEvents.ResidueUnresolved[0] & ~ResidueUnresolvedQ[0]);
    Inc[14] = 3'(FaultEvents.ResidueDetect[1]);
    Inc[15] = 3'(FaultEvents.ResidueUnresolved[1] & ~ResidueUnresolvedQ[1]);
    Inc[16] = 3'(FaultEvents.TmrCorrected & ~TmrCorrectedQ);
    Inc[17] = 3'(FaultEvents.TmrUncorrectable & ~TmrUncorrectableQ);
    Inc[18] = 3'(FaultEvents.ICacheSec[0]);
    Inc[19] = 3'(FaultEvents.ICacheTagDed);
    Inc[20] = 3'(FaultEvents.DCacheSec[0]);
    Inc[21] = 3'(FaultEvents.DCacheTagDed);
    Inc[22] = 3'(FaultEvents.DCacheDataLost);
  end

  // Software writes: the word written says what to clear; the data is ignored
  localparam logic [4:0] W_DREC = 5'd24, W_DADR = 5'd25, W_IREC = 5'd26, W_IADR = 5'd27, W_CLEARALL = 5'd31;
  logic Wr;
  assign Wr = PSEL & PENABLE & PWRITE & ~DFTHold;

  // Saturating: a count that would pass 0xFFFF stays there
  logic [FAULT_COUNTERS-1:0][W-1:0] Count;
  for (genvar i = 0; i < FAULT_COUNTERS; i++) begin : counter
    logic [W:0] Sum;
    logic       Clear;
    assign Sum   = {1'b0, (Clear ? W'(0) : Count[i])} + (W+1)'(Inc[i]);
    assign Clear = Wr & ((PADDR == 5'(i)) | (PADDR == W_CLEARALL));
    always_ff @(posedge PCLK)
      if (!PRESETn) Count[i] <= '0;
      else if (~DFTHold) Count[i] <= Sum[W] ? '1 : Sum[W-1:0];
  end

  // Last-error records
  typedef struct packed {
    logic            Valid, Multiple, Tag, Lost;
    cache_ded_info_t Info;
  } ded_record_t;
  ded_record_t DRec, IRec;

  function automatic ded_record_t next_record(input ded_record_t Rec, input logic Ded, TagDed, Lost,
                                              input cache_ded_info_t Info, input logic Clear);
    if (Ded)        next_record = '{Valid: 1'b1, Multiple: Rec.Valid & ~Clear, Tag: TagDed, Lost: Lost, Info: Info};
    else if (Clear) next_record = '0;
    else            next_record = Rec;
  endfunction

  always_ff @(posedge PCLK)
    if (!PRESETn) {DRec, IRec} <= '0;
    else if (~DFTHold) begin
      DRec <= next_record(DRec, FaultEvents.DCacheDed, FaultEvents.DCacheTagDed, FaultEvents.DCacheDataLost,
                          FaultEvents.DCacheDedInfo, Wr & ((PADDR == W_DREC) | (PADDR == W_DADR)));
      IRec <= next_record(IRec, FaultEvents.ICacheDed, FaultEvents.ICacheTagDed, 1'b0,
                          FaultEvents.ICacheDedInfo, Wr & ((PADDR == W_IREC) | (PADDR == W_IADR)));
    end

  function automatic logic [31:0] record_word(input ded_record_t Rec);
    record_word = {4'b0, Rec.Info.Set, 4'b0, Rec.Info.Ways, 2'b0, Rec.Info.Source,
                   Rec.Lost, Rec.Tag, Rec.Multiple, Rec.Valid};
  endfunction

  logic [31:0] ReadWord;
  always_comb
    if (int'(PADDR) < FAULT_COUNTERS) ReadWord = {16'b0, Count[PADDR]};
    else case (PADDR)
      W_DREC:  ReadWord = record_word(DRec);
      W_DADR:  ReadWord = DRec.Info.LineAdr;
      W_IREC:  ReadWord = record_word(IRec);
      W_IADR:  ReadWord = IRec.Info.LineAdr;
      default: ReadWord = '0;
    endcase
  assign PRDATA   = {(XLEN/32){ReadWord}};
  assign PREADY   = 1'b1;
endmodule
