///////////////////////////////////////////
// ecc_flip_mask.sv
//
// Written: 2026, split out of ecc_bit_flip (REG_MASK)
//
// Purpose: Registered one-hot flip mask for injecting single-bit errors into
//          codeword registers.  The register XORs the mask into its stored
//          codeword (flopenrc_cw), so the codeword passes one XOR.
//
//          The ECC pipeline registers used to carry one of these each, inside
//          ecc_bit_flip.  Every copy had the same LFSR, the same reset value, the
//          same period counter and the same inject_en, so every copy produced the
//          same mask in every cycle.  One generator now drives all of them: the
//          same bit of every register flips in the same cycle, exactly as before,
//          for one LFSR, one counter and one mask register.
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

module ecc_flip_mask #(
  parameter int CW_WIDTH      = 72,   // codeword width (DATA_WIDTH + R + 1)
  parameter int LFSR_POLY     = 16'hB400, // Galois LFSR: x^16+x^14+x^13+x^11+1
  parameter int INJECT_PERIOD = 9     // inject every 2^INJECT_PERIOD cycles
) (
  input  logic                 clk,
  input  logic                 reset,
  input  logic                 inject_en,          // 1 = inject; 0 = mask stays zero
  output logic [CW_WIDTH-1:0]  mask                // one-hot on an injection cycle, else zero
);

  localparam int LOG_CW = $clog2(CW_WIDTH);

  // ── Galois LFSR ──────────────────────────────────────────────────────────────
  // Feedback: shift right, XOR polynomial mask on LSB-out.
  // Initialised to all-ones (avoids the lock-up all-zeros state).
  logic [15:0] lfsr, lfsr_next;

  assign lfsr_next = {1'b0, lfsr[15:1]} ^ (lfsr[0] ? 16'(LFSR_POLY) : 16'h0);

  always_ff @(posedge clk)
    if (reset) lfsr <= 16'hFFFF;
    else       lfsr <= lfsr_next;

  // ── Period counter ───────────────────────────────────────────────────────────
  // Counts freely; injection fires on the single cycle where all bits are 1.
  logic [INJECT_PERIOD-1:0] cnt;

  always_ff @(posedge clk)
    if (reset) cnt <= '0;
    else       cnt <= cnt + 1'b1;

  // ── Bit-index selection ──────────────────────────────────────────────────────
  // Use the lower LOG_CW bits of the LFSR as the candidate index.
  // Clamp indices >= CW_WIDTH to 0 (simple comparator, no divider hardware).
  function automatic logic [LOG_CW-1:0] bit_index(input logic [15:0] state);
    return (state[LOG_CW-1:0] < LOG_CW'(CW_WIDTH)) ? state[LOG_CW-1:0] : '0;
  endfunction

  // ── Mask ─────────────────────────────────────────────────────────────────────
  // Next cycle's flip, decided now: the counter fires next cycle when it is one
  // short of all ones, and the bit comes from the LFSR's next state.
  logic [CW_WIDTH-1:0] mask_next;

  always_comb begin
    mask_next = '0;
    if (inject_en & (cnt == {{(INJECT_PERIOD-1){1'b1}}, 1'b0}))
      mask_next[bit_index(lfsr_next)] = 1'b1;
  end

  always_ff @(posedge clk)
    if (reset) mask <= '0;
    else       mask <= mask_next;

endmodule
