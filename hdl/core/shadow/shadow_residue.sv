///////////////////////////////////////////
// shadow_residue.sv
//
// Purpose: SHARD mod-3 residue generator, used to check the shared multipliers.
//          2^2 = 1 (mod 3), so the residue of an unsigned number is the sum of its
//          2-bit digits mod 3.  A multiplier that returns a wrong product violates
//          res(a) * res(b) = res(a*b) (mod 3) unless the error is itself a multiple
//          of 3; in particular every single-bit error (+-2^k) is caught.
//
//          Unlike a duplicated datapath, the check is arithmetically different from
//          the multiplier, so a permanent fault or a trojan in the array cannot
//          corrupt both in the same way.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_residue #(parameter int WIDTH = 64) (
  input  logic [WIDTH-1:0] a,
  output logic [1:0]       residue   // a mod 3
);

  localparam int DIGITS = (WIDTH + 1) / 2;

  logic [2*DIGITS-1:0] Padded;

  assign Padded = {{(2*DIGITS-WIDTH){1'b0}}, a};

  always_comb begin
    residue = 2'd0;
    for (int i = 0; i < DIGITS; i++) begin
      logic [2:0] Sum;
      Sum = {1'b0, residue} + {1'b0, Padded[2*i +: 2]};   // at most 2 + 3
      residue = (Sum >= 3'd3) ? 2'(Sum - 3'd3) : Sum[1:0];
    end
  end

endmodule
