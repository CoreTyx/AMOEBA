///////////////////////////////////////////
// shadow_sq.sv
//
// Purpose: SHARD Store Queue: the store buffer between the main pipeline and
//          memory.  A store (or the write half of an AMO / successful SC) enters
//          here when it leaves main M and is never written to the D-cache or bus
//          by the main pipeline.  The oldest NVerified entries have been verified
//          by the shadow and may be written to memory by the LSU drain engine;
//          the rest are still speculative and are discarded on recovery.
//          Main loads see every entry through the LSU's byte-merge.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_sq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       Flush,        // recovery: discard the unverified entries
  // Push: main M-stage exit of a store
  input  logic                       Push,
  input  logic [P.PA_BITS-1:0]       PAdrM,
  input  logic [1:0]                 SizeM,
  input  logic [P.XLEN-1:0]          WriteDataM,
  // Shadow commit of the oldest unverified store
  input  logic                       Verify,
  // LSU drain engine wrote the head to memory
  input  logic                       Pop,
  // Contents
  output logic [P.PA_BITS-1:0]       sqPA [DEPTH],
  output logic [1:0]                 sqSize [DEPTH],
  output logic [P.XLEN-1:0]          sqData [DEPTH],
  output logic [$clog2(DEPTH+1)-1:0] Count,
  output logic [$clog2(DEPTH+1)-1:0] NVerified
);

  localparam int CW      = $clog2(DEPTH+1);
  localparam int ENTRY_W = P.PA_BITS + 2 + P.XLEN;

  logic [ENTRY_W-1:0] entry [DEPTH];

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep(NVerified),
    .push(Push), .din({PAdrM, SizeM, WriteDataM}), .pop(Pop), .entry, .count(Count));

  // A fault at shadow sW raises Flush instead of Verify, so the two never coincide
  always_ff @(posedge clk)
    if (reset) NVerified <= '0;
    else       NVerified <= NVerified + {{(CW-1){1'b0}}, Verify} - {{(CW-1){1'b0}}, Pop};

  for (genvar i = 0; i < DEPTH; i++) begin : unpack
    assign {sqPA[i], sqSize[i], sqData[i]} = entry[i];
  end

endmodule
