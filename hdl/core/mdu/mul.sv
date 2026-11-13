///////////////////////////////////////////
// mul.sv
//
// Written: David_Harris@hmc.edu 16 February 2021
// Modified: 2026-11 -- sequential shift-add, one multiplier bit per cycle
//
// Purpose: Integer multiplication
//
// Documentation: RISC-V System on Chip Design
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the “License”); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an “AS IS” BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

// SEQUENTIAL SHIFT-ADD MULTIPLIER, ONE MULTIPLIER BIT PER CYCLE.
//
// Multiplies and divides are a small share of the dynamic instruction mix, so
// this trades latency for area: one adder, used again every cycle, in place of
// the four 32x32 array multipliers and 512 partial-product flops it replaces.
// A multiply takes XLEN+1 cycles (65): a load, then XLEN steps.  The product is
// held until the next Start.
//
//   Acc  XLEN+1 bits   the running high half.  Its top bit is the carry out
//                      of each step's add -- the sign of the partial sum.
//   MQ   XLEN bits     the multiplier, shifted out at the bottom one bit per
//                      cycle while the product's low half shifts in at the top.
//
// Step k (k = 0..XLEN-1) adds A to Acc when multiplier bit k is set, then
// shifts {sum, MQ} right by one.  After XLEN steps {Acc[XLEN-1:0], MQ} is the
// 2*XLEN-bit product.  Per bit of the adder that is one sum and one carry
// function of three inputs -- the two LUT3s -- and the row is used once per
// cycle for XLEN cycles.
//
// Signedness costs no extra cycles.  A signed multiplicand (mulh, mulhsu) is
// sign-extended to XLEN+1 bits, so the partial sums stay right in two's
// complement; the arithmetic shift keeps them so.  A signed multiplier (mulh)
// has bit XLEN-1 of weight -2^(XLEN-1), so the last step subtracts instead of
// adding.  mul's low half is the same whatever the signedness and is formed
// unsigned; mulw's is the low 32 bits of the same product, truncated in mdu.
//
// TIMING.  A step is one XLEN+2-bit add whose only late input is MQ[0], a
// register, selecting A or 0 per bit.  Everything else in front of the adder
// comes from registers that are steady for the whole multiply: A, the
// signedness, and Last -- the last step, registered a step ahead rather than
// decoded from the count -- so A's subtract-or-add form settles early.  The load
// cycle is what keeps a "first step reads B" mux off this path.
//
// A, B and Funct3 must be held from the Start edge until Done: ft_mul feeds
// them from its saved-transaction registers.
//
// Load overwrites the product register with PIn.  ft_mul uses it, once the
// product is complete, to place an injected fault where the residue check sees
// it, so the product register doubles as the captured result.

module mul #(parameter XLEN) (
  input  logic                clk, reset,
  input  logic                DFTHold,                       // DFT hold: freeze (forte_chip.sv)
  input  logic                Start,                         // load next cycle, then XLEN steps
  input  logic [XLEN-1:0]     A, B,                          // multiplicand, multiplier; held until Done
  input  logic [2:0]          Funct3,                        // type of multiply; held until Done
  input  logic                Load,                          // replace the product with PIn (only when Done)
  input  logic [XLEN*2-1:0]   PIn,
  output logic                Done,                          // Prod is the product
  output logic [XLEN*2-1:0]   Prod
);

  localparam CNTW = $clog2(XLEN);

  logic [XLEN:0]   Acc;                                      // running high half, with its sign
  logic [XLEN-1:0] MQ;                                       // multiplier out, product low half in
  logic [CNTW-1:0] Cnt;                                      // step number
  logic            Loading, Busy, Last;
  logic            SignedA, SignedB, Sub;
  logic [XLEN:0]   AExt, AOp, Addend;
  logic [XLEN+1:0] Sum;

  // flavour of multiply: mulh is signed x signed, mulhsu signed x unsigned
  assign SignedA = (Funct3 == 3'b001) | (Funct3 == 3'b010);
  assign SignedB = (Funct3 == 3'b001);

  // The signed multiplier's top bit is worth -2^(XLEN-1): the last step subtracts.
  assign Sub    = SignedB & Last;
  assign AExt   = {SignedA & A[XLEN-1], A};
  assign AOp    = AExt ^ {(XLEN+1){Sub}};                    // A or ~A, settled before the step
  assign Addend = MQ[0] ? AOp : '0;
  assign Sum    = {Acc[XLEN], Acc} + {Addend[XLEN], Addend} + (XLEN+2)'(Sub & MQ[0]);

  always_ff @(posedge clk)
    if (reset) begin
      Loading <= 1'b0;
      Busy    <= 1'b0;
    end else if (DFTHold) begin
    end else if (Start) begin
      Loading <= 1'b1;
      Busy    <= 1'b0;
    end else if (Loading) begin
      Loading <= 1'b0;
      Busy    <= 1'b1;
      Cnt     <= '0;
      Last    <= 1'b0;
    end else if (Busy) begin
      Cnt     <= Cnt + 1'b1;
      Last    <= (Cnt == CNTW'(XLEN-2));
      if (Last) Busy <= 1'b0;
    end

  // The datapath registers need no reset: nothing reads them before a multiply has written them.
  always_ff @(posedge clk)
    if (DFTHold) ;
    else if (Loading) begin
      Acc <= '0;
      MQ  <= B;
    end else if (Busy) begin
      Acc <= Sum[XLEN+1:1];
      MQ  <= {Sum[0], MQ[XLEN-1:1]};
    end else if (Load) begin
      {Acc, MQ} <= {PIn[XLEN*2-1], PIn};
    end

  assign Done = ~Loading & ~Busy;
  assign Prod = {Acc[XLEN-1:0], MQ};
endmodule
