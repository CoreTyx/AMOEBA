///////////////////////////////////////////
// ecc_flip_mask.sv
//
// Written: 2026, split out of ecc_bit_flip (REG_MASK)
//
// Purpose: Registered one-hot flip mask for injecting single-bit errors into
//          codeword registers.  The register XORs the mask into its stored
//          codeword (flopenrc_cw), so the codeword passes one XOR.
//
//          One mask drives all seven ECC pipeline registers: the same bit of
//          every register flips in the same cycle.  The LFSR and counter are the
//          core's shared fault generator (ft_fault_gen); this module keeps only
//          the mask register.
//
//          Timing: the bit is chosen a cycle ahead from the LFSR's next state and
//          registered, and inject_en is sampled the cycle before the flip.
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

module ecc_flip_mask import cvw::*; #(
  parameter int CW_WIDTH = 72,                      // codeword width (DATA_WIDTH + R + 1)
  parameter logic [FI_COUNT_BITS-1:0] PHASE = '1    // shared-counter value at which the mask is applied
) (
  input  logic                     clk,
  input  logic                     reset,
  input  logic                     inject_en,       // 1 = inject; 0 = mask stays zero
  input  logic [15:0]              lfsr,            // shared generator
  input  logic [FI_COUNT_BITS-1:0] count,
  output logic [CW_WIDTH-1:0]      mask             // one-hot on an injection cycle, else zero
);

  localparam int LOG_CW = $clog2(CW_WIDTH);

  // Clamp indices >= CW_WIDTH to 0 (simple comparator, no divider hardware).
  function automatic logic [LOG_CW-1:0] bit_index(input logic [15:0] state);
    return (state[LOG_CW-1:0] < LOG_CW'(CW_WIDTH)) ? state[LOG_CW-1:0] : '0;
  endfunction

  // Next cycle's flip, decided now: the counter reaches PHASE next cycle when it
  // is one short of it, and the bit comes from the LFSR's next state.
  logic [CW_WIDTH-1:0] mask_next;

  always_comb begin
    mask_next = '0;
    if (inject_en & (count == PHASE - FI_COUNT_BITS'(1)))
      mask_next[bit_index(fi_lfsr_next(lfsr))] = 1'b1;
  end

  always_ff @(posedge clk)
    if (reset) mask <= '0;
    else       mask <= mask_next;

endmodule
