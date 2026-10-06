///////////////////////////////////////////
// shifter.sv
//
// Written: David_Harris@hmc.edu, Sarah.Harris@unlv.edu, Kevin Kim <kekim@hmc.edu>
// Created: 9 January 2021
// Modified: 6 February 2023
//
// Purpose: RISC-V 32/64 bit shifter
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

module shifter import cvw::*; #(parameter cvw_t P) (
  input  logic [P.XLEN-1:0] A,
  input  logic [P.LOG_XLEN-1:0] Amt,
  input  logic Right, Rotate, W64, SubArith,
  input  logic Recompute,
  output logic [P.XLEN-1:0] Y,
  // Private diagnostic result: consumed only within the enclosing ft_alu.
  output logic [P.XLEN+1:0] WideY
);
  logic [P.XLEN-1:0] normalized_a, rotate_a, rotate_y;
  logic [P.XLEN+1:0] shift_input;
  logic [P.LOG_XLEN-1:0] amount;
  logic arithmetic;

  // Normalize word operands before displacement. SLLI.UW's zero extension
  // already occurs in bitmanipalu's CondShiftA, upstream of this shifter.
  generate
    if (P.XLEN == 64) begin : word_input
      assign normalized_a = W64 ? (SubArith ? {{32{A[31]}}, A[31:0]} :
                                                        {32'b0, A[31:0]}) : A;
      assign rotate_a = W64 ? {A[31:0], A[31:0]} : A;
      assign amount = W64 ? {1'b0, Amt[4:0]} : Amt;
    end else begin : full_input
      assign normalized_a = A;
      assign rotate_a = A;
      assign amount = Amt;
    end
  endgenerate
  assign arithmetic = Right & SubArith;
  assign shift_input = Recompute ? {normalized_a, 2'b00} :
                      {{2{arithmetic & normalized_a[P.XLEN-1]}}, normalized_a};

  always_comb begin
    if (!Right)          WideY = shift_input << amount;
    else if (arithmetic) WideY = $signed(shift_input) >>> amount;
    else                 WideY = shift_input >> amount;
  end

  // Preserve the n-bit rotation ring (word rings are repeated twice). The
  // widened-shift relation is not valid for rotations, so they never diagnose.
  generate
    if (P.ZBB_SUPPORTED | P.ZBKB_SUPPORTED) begin : rotation
      always_comb begin
        if (amount == '0) rotate_y = rotate_a;
        else if (Right) rotate_y = (rotate_a >> amount) |
                                  (rotate_a << (P.XLEN - int'(amount)));
        else rotate_y = (rotate_a << amount) |
                        (rotate_a >> (P.XLEN - int'(amount)));
      end
    end else begin : no_rotation
      assign rotate_y = '0;
    end
  endgenerate

  assign Y = Rotate ? rotate_y : (Recompute ? WideY[P.XLEN+1:2] : WideY[P.XLEN-1:0]);
endmodule
