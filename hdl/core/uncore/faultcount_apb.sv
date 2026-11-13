// Fault counters: read-only, 16-bit, saturating.  APB slave at ECC_COUNTER_BASE; counter i is
// the 32-bit word at offset 4*i, reading {16'b0, count}.  Only reset clears them.
//   0 register-file SEC     1 register-file DED     2 pipeline-register SEC   3 pipeline-register DED
//   4 I$ SEC                5 I$ DED                6 D$ SEC                  7 D$ DED
//   8 ALU mismatch          9 ALU unresolved       10 CMP mismatch           11 CMP unresolved
//  12 MUL residue mismatch 13 MUL unresolved       14 DIV residue mismatch   15 DIV unresolved
//  16 priv-mode TMR corrected                      17 priv-mode TMR uncorrectable
// Every detected error counts: two read ports corrected in one cycle count two.  The events
// arrive registered from the core, so the counting adds nothing to any core path.
module faultcount_apb import cvw::*; #(
  parameter int XLEN = 64
) (
  input  logic            PCLK, PRESETn,
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
    else          {FTUnresolvedQ, ResidueUnresolvedQ, TmrCorrectedQ, TmrUncorrectableQ} <=
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
  end

  // Saturating: a count that would pass 0xFFFF stays there
  logic [FAULT_COUNTERS-1:0][W-1:0] Count;
  for (genvar i = 0; i < FAULT_COUNTERS; i++) begin : counter
    logic [W:0] Sum;
    assign Sum = {1'b0, Count[i]} + (W+1)'(Inc[i]);
    always_ff @(posedge PCLK)
      if (!PRESETn) Count[i] <= '0;
      else          Count[i] <= Sum[W] ? '1 : Sum[W-1:0];
  end

  logic [31:0] ReadWord;
  assign ReadWord = (int'(PADDR) < FAULT_COUNTERS) ? {16'b0, Count[PADDR]} : '0;
  assign PRDATA   = {(XLEN/32){ReadWord}};
  assign PREADY   = 1'b1;
endmodule
