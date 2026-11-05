///////////////////////////////////////////
// ecc_bit_flip.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 4 September 2026
// Modified:
//
// Purpose: Parameterizable single-bit error injector for ECC testing.
//          On the cycle the core's shared fault counter (ft_fault_gen) reaches
//          PHASE, the shared LFSR selects a pseudo-random codeword bit index and
//          that bit is flipped.  Injection is gated by inject_en so the module is a
//          pure combinational pass-through (codeword_o = codeword_i) when
//          inject_en = 0.  This keeps the normal-operation critical path clean
//          and makes the design DFT-friendly: a test controller can assert
//          inject_en to exercise ECC correction without a separate build.
//
//          Only a single bit is ever flipped per injection event, guaranteeing
//          that the SECDED decoder can always correct the error.  DED (double
//          error) injection is not supported here by design.
//
// A component of the AMOEBA RISC-V project.
//
// Copyright (C) 2026 Saipranavvk
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

module ecc_bit_flip import cvw::*; #(
  parameter int CW_WIDTH = 72,                      // codeword width (DATA_WIDTH + R + 1)
  parameter logic [FI_COUNT_BITS-1:0] PHASE = '1    // shared-counter value at which this site flips
) (
  input  logic                     inject_en,       // 1 = inject; 0 = pass-through
  input  logic [15:0]              lfsr,            // shared generator
  input  logic [FI_COUNT_BITS-1:0] count,
  input  logic [CW_WIDTH-1:0]      codeword_i,
  output logic [CW_WIDTH-1:0]      codeword_o
);

  localparam int LOG_CW = $clog2(CW_WIDTH);

  // Use the lower LOG_CW bits of the LFSR as the candidate index.
  // Clamp indices >= CW_WIDTH to 0 (simple comparator, no divider hardware).
  logic [LOG_CW-1:0] bit_sel;

  assign bit_sel = (lfsr[LOG_CW-1:0] < LOG_CW'(CW_WIDTH))
                    ? lfsr[LOG_CW-1:0]
                    : '0;

  always_comb begin
    codeword_o = codeword_i;
    if (inject_en & (count == PHASE))
      codeword_o[bit_sel] = ~codeword_i[bit_sel];
  end

endmodule
