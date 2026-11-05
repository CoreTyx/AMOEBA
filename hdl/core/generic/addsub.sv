///////////////////////////////////////////
// addsub.sv
//
// Written: Siddharth Rau
// Modified:
//
// Purpose: Extended add/subtract arithmetic with FT recomputation
//
// AMOEBA fault-tolerant extension to CORE-V-WALLY.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

// Arithmetic kernel shared by the independent ALU and branch-compare lanes.
// Extend operands before entry. Identities are modulo 2**WIDTH.
module addsub #(parameter int WIDTH = 65) (
  input  logic [WIDTH-1:0] a, b,
  input  logic             sub, recompute,
  output logic [WIDTH-1:0] result
);
  always_comb begin
    if (recompute) begin
      if (sub) result = ~a + b;              // ~(a - b)
      else     result = ~a + ~b + WIDTH'(1); // ~(a + b)
    end else result = a + (sub ? ~b : b) + WIDTH'(sub);
  end
endmodule
