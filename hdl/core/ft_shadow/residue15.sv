///////////////////////////////////////////
// residue15.sv
//
// Purpose: Residue of an unsigned value modulo 15, for arithmetic self-checks.
//
// Usage:
// Instantiated by ft_mul and ft_div to check their single multiplier and
// divider (see those files), and by them again on the small sums and products
// of residues that the checks compare.  WIDTH is at most 136 bits.
//
// Functionality:
// 16 is congruent to 1 (mod 15), so a value is congruent to the sum of its
// 4-bit digits.  The digits are summed (synthesis builds a carry-save tree),
// the sum is folded the same way twice, and the result is brought into
// 0..14, so that equal residues compare equal bit for bit.
///////////////////////////////////////////

module residue15 #(
  parameter int WIDTH = 64
) (
  input  logic [WIDTH-1:0] a,
  output logic [3:0]       r          // a mod 15, in 0..14
);
  localparam int DIGITS = (WIDTH + 3) / 4;
  localparam int SUMW   = $clog2(DIGITS * 15 + 1);  // at most 9 bits for WIDTH <= 136

  logic [4*DIGITS-1:0] digits;
  logic [SUMW-1:0]     sum;
  logic [8:0]          sumx;           // sum, zero-extended to the widest it can be
  logic [5:0]          fold1;          // <= 15 + 30
  logic [4:0]          fold2;          // <= 15 + 2

  assign digits = (4*DIGITS)'(a);
  always_comb begin
    sum = '0;
    for (int i = 0; i < DIGITS; i++) sum = sum + SUMW'(digits[4*i +: 4]);
  end

  assign sumx  = 9'(sum);
  assign fold1 = 6'(sumx[3:0]) + 6'(sumx[8:4]);
  assign fold2 = 5'(fold1[3:0]) + 5'(fold1[5:4]);
  assign r     = (fold2 >= 5'd15) ? 4'(fold2 - 5'd15) : fold2[3:0];
endmodule
