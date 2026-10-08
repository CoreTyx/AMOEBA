///////////////////////////////////////////
// shadow_iq.sv
//
// Purpose: SHARD Instruction Queue.  One entry per instruction that leaves the
//          main Memory stage without being flushed, i.e. per instruction that is
//          certain to retire.  The head feeds shadow sD.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_iq import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic                       clk, reset,
  input  logic                       Flush,        // recovery: discard every entry
  // Push: main M-stage exit
  input  logic                       Push,
  input  logic [P.XLEN-1:0]          PCM,
  input  logic [31:0]                InstrM,
  input  logic                       CompressedM,
  // Pop: shadow sD -> sE advance
  input  logic                       Pop,
  // Head (shadow sD)
  output logic                       sValid,
  output logic [P.XLEN-1:0]          sPC,
  output logic [31:0]                sInstr,
  output logic                       sCompressed
);

  localparam int ENTRY_W = P.XLEN + 32 + 1;

  logic [ENTRY_W-1:0]         entry [DEPTH];
  logic [$clog2(DEPTH+1)-1:0] count;

  shadow_fifo #(.W(ENTRY_W), .DEPTH(DEPTH)) fifo(.clk, .reset, .flush(Flush), .keep('0),
    .push(Push), .din({PCM, InstrM, CompressedM}), .pop(Pop), .entry, .count);

  assign sValid = (count != '0);
  assign {sPC, sInstr, sCompressed} = entry[0];

endmodule
