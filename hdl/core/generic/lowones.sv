///////////////////////////////////////////
// lowones.sv
//
// Written: 11 October 2026
//
// Purpose: For each bit position, whether every lower bit of the input is one:
//          y[i] = &a[i-1:0], with y[0] = 1.  This is (a + 1) ^ a -- the mask of
//          the trailing ones and the zero above them -- without the carry chain.
//          An incrementer written as a + 1 is built as a ripple of half adders,
//          one gate per bit; this is a parallel prefix (Sklansky) AND with
//          log2(WIDTH) levels.
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

module lowones #(parameter int WIDTH = 8) (
  input  logic [WIDTH-1:0] a,
  output logic [WIDTH-1:0] y
);

  localparam int LEVELS = $clog2(WIDTH);

  // After level l, p[i] is the AND of a[i] down to the bottom of i's block of
  // 2**(l+1) bits: each level joins the upper half of a block to the completed
  // lower half.  After the last level p[i] = &a[i:0].
  always_comb begin
    logic [WIDTH-1:0] p, q;
    p = a;
    for (int l = 0; l < LEVELS; l++) begin
      q = p;
      for (int i = 0; i < WIDTH; i++)
        if (((i >> l) % 2) == 1) q[i] = p[i] & p[((i >> l) << l) - 1];
      p = q;
    end
    y = {p[WIDTH-2:0], 1'b1};
  end

endmodule
