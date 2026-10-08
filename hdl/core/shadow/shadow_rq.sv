///////////////////////////////////////////
// shadow_rq.sv
//
// Purpose: SHARD Result Queue.  Holds the result of every instruction that has
//          retired from the main pipeline but has not yet been verified and
//          committed to the register file by the shadow.  Pushed once per
//          instruction on its first cycle in main W; popped by the shadow commit.
//
//          Because the register file only holds verified state, the main Execute
//          stage reads through this queue: an associative lookup over all valid
//          entries, newest match wins.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_rq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       Flush,        // recovery: discard every entry
  // Push: main W stage
  input  logic                       Push,
  input  logic [4:0]                 RdW,
  input  logic                       RegWriteW,
  input  logic [P.XLEN-1:0]          ResultW,
  // Pop: shadow commit
  input  logic                       Pop,
  // Forwarding to the main Execute stage
  input  logic [4:0]                 Rs1E, Rs2E,
  output logic                       RQ_HitA, RQ_HitB,
  output logic [P.XLEN-1:0]          RQ_ValA, RQ_ValB,
  // The two oldest entries: shadow sW owns entry 0 when it is occupied, and shadow
  // sM owns the entry behind it
  output logic [4:0]                 sRd [2],
  output logic                       sRegWrite [2],
  output logic [P.XLEN-1:0]          sResult [2],
  output logic [$clog2(DEPTH+1)-1:0] Count
);

  localparam int ENTRY_W = 5 + 1 + P.XLEN;

  logic [ENTRY_W-1:0] entry [DEPTH];

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep('0),
    .push(Push), .din({RdW, RegWriteW, ResultW}), .pop(Pop), .entry, .count(Count));

  assign {sRd[0], sRegWrite[0], sResult[0]} = entry[0];
  assign {sRd[1], sRegWrite[1], sResult[1]} = entry[1];

  // Newest matching entry wins: scan oldest to newest so later matches override
  always_comb begin
    RQ_HitA = 1'b0; RQ_ValA = '0;
    RQ_HitB = 1'b0; RQ_ValB = '0;
    for (int j = 0; j < DEPTH; j++) begin
      logic [4:0] Rd;
      logic       RegWrite;
      logic [P.XLEN-1:0] Result;
      {Rd, RegWrite, Result} = entry[j];
      if ((j < Count) & RegWrite & (Rd != 5'b0)) begin
        if (Rd == Rs1E) begin RQ_HitA = 1'b1; RQ_ValA = Result; end
        if (Rd == Rs2E) begin RQ_HitB = 1'b1; RQ_ValB = Result; end
      end
    end
  end

endmodule
