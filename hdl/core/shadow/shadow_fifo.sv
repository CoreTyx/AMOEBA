///////////////////////////////////////////
// shadow_fifo.sv
//
// Purpose: SHARD collapsing FIFO shared by the IQ, OQ, RQ and SQ.
//          entry[0] is always the oldest element, so a consumer that trails the
//          head by k elements reads entry[k] directly.  Entries at index >= count
//          hold stale data and must be qualified by the reader.
//
//          pop   removes entry[0] and shifts every other element down.
//          push  appends at the tail (after any simultaneous pop).
//          flush keeps only the `keep` oldest elements (a simultaneous pop removes
//                one of them) and discards any simultaneous push.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_fifo #(parameter int W = 8, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       flush,
  input  logic [$clog2(DEPTH+1)-1:0] keep,
  input  logic                       push,
  input  logic [W-1:0]               din,
  input  logic                       pop,
  output logic [W-1:0]               entry [DEPTH],
  output logic [$clog2(DEPTH+1)-1:0] count
);

  localparam int CW = $clog2(DEPTH+1);

  logic [CW-1:0] CountAfterPop;

  assign CountAfterPop = count - {{(CW-1){1'b0}}, pop};

  always_ff @(posedge clk) begin
    if (reset) count <= '0;
    else if (flush) count <= keep - {{(CW-1){1'b0}}, pop};
    else count <= CountAfterPop + {{(CW-1){1'b0}}, push};
  end

  always_ff @(posedge clk) begin
    for (int i = 0; i < DEPTH; i++) begin
      if (push & ~flush & (CountAfterPop == CW'(i))) entry[i] <= din;
      else if (pop & (i < DEPTH-1))                  entry[i] <= entry[(i+1) % DEPTH];
    end
  end

endmodule
