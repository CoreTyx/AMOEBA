///////////////////////////////////////////
// lessthan.sv
//
// Written: 12 October 2026
//
// Purpose: Unsigned a < b as a balanced tree.  Each node joins two adjacent
//          fields, the upper one deciding unless it is equal:
//             lt = lt_hi | (eq_hi & lt_lo),   eq = eq_hi & eq_lo
//          which gives log2(WIDTH) levels.  The < operator is built as a
//          borrow chain along the whole width, one gate per bit or two.
//
// A component of the AMOEBA RISC-V project.
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
//
// Licensed under the Solderpad Hardware License v 2.1 (the "License"); you may not use this file
// except in compliance with the License, or, at your option, the Apache License version 2.0. You
// may obtain a copy of the License at
//
// https://solderpad.org/licenses/SHL-2.1/
//
// Unless required by applicable law or agreed to in writing, any work distributed under the
// License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions
// and limitations under the License.
////////////////////////////////////////////////////////////////////////////////////////////////

module lessthan #(parameter int WIDTH = 8) (
  input  logic [WIDTH-1:0] a, b,
  output logic             y      // a < b, unsigned
);

  localparam int LEVELS = $clog2(WIDTH);
  localparam int LEAVES = 2**LEVELS;

  // lt[i], eq[i] describe field i.  The fields start as single bits (the
  // positions above WIDTH compare equal) and are joined in pairs at each level,
  // so after level l there are LEAVES >> (l+1) of them and at the end one.
  always_comb begin
    logic [LEAVES-1:0] lt, eq, ltn, eqn;
    lt = '0;
    eq = '1;
    lt[WIDTH-1:0] = ~a & b;
    eq[WIDTH-1:0] = a ~^ b;
    for (int l = 0; l < LEVELS; l++) begin
      ltn = '0;
      eqn = '1;
      for (int i = 0; i < (LEAVES >> (l+1)); i++) begin
        ltn[i] = lt[2*i+1] | (eq[2*i+1] & lt[2*i]);
        eqn[i] = eq[2*i+1] & eq[2*i];
      end
      lt = ltn;
      eq = eqn;
    end
    y = lt[0];
  end

endmodule
