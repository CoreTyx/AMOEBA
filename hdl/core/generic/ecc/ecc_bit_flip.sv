///////////////////////////////////////////
// ecc_bit_flip.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 4 September 2026
// Modified:
//
// Purpose: Parameterizable single-bit error injector for ECC testing.
//          Uses a 16-bit Galois LFSR to select a pseudo-random codeword bit
//          index; a period counter triggers an injection every 2^INJECT_PERIOD
//          clock cycles.  Injection is gated by inject_en so the module is a
//          pure combinational pass-through (codeword_o = codeword_i) when
//          inject_en = 0.  This keeps the normal-operation critical path clean
//          and makes the design DFT-friendly: a test controller can assert
//          inject_en to exercise ECC correction without a separate build.
//
//          Only a single bit is ever flipped per injection event, guaranteeing
//          that the SECDED decoder can always correct the error.  DED (double
//          error) injection is not supported here by design.
//
//          Synthesis path: LFSR + period counter are ordinary flip-flops.
//          When inject_en is tied to 0 (production), synthesis constant-
//          propagation can eliminate the XOR flip path entirely.
//
//          REG_MASK: where codeword_i is itself a register output (the ECC
//          pipeline registers), decoding the LFSR into a bit position takes
//          far longer than the data takes to arrive, and that decode ends up
//          at the head of every path out of the register.  With REG_MASK = 1
//          the one-hot flip mask is computed a cycle ahead into a register, so
//          the codeword passes one XOR.  The same bit is flipped in the same
//          cycle; the one difference is that inject_en is sampled the cycle
//          before the flip.  Leave it 0 where codeword_i arrives late anyway
//          (the register file read), which saves the mask register.
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

module ecc_bit_flip #(
  parameter int CW_WIDTH      = 72,   // codeword width (DATA_WIDTH + R + 1)
  parameter int LFSR_POLY     = 16'hB400, // Galois LFSR: x^16+x^14+x^13+x^11+1
  parameter int INJECT_PERIOD = 9,    // inject every 2^INJECT_PERIOD cycles
  parameter bit REG_MASK      = 1'b0  // 1 = flip mask from a register (see header)
) (
  input  logic                 clk,
  input  logic                 reset,
  input  logic                 inject_en,          // 1 = inject; 0 = pass-through
  input  logic [CW_WIDTH-1:0]  codeword_i,
  output logic [CW_WIDTH-1:0]  codeword_o
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

  // ── Injection ────────────────────────────────────────────────────────────────
  // Flip exactly one bit when inject_en is asserted and the counter fires.
  if (REG_MASK) begin : reg_mask
    // Next cycle's flip, decided now: the counter fires next cycle when it is one
    // short of all ones, and the bit comes from the LFSR's next state.
    logic [CW_WIDTH-1:0] mask, mask_next;

    always_comb begin
      mask_next = '0;
      if (inject_en & (cnt == {{(INJECT_PERIOD-1){1'b1}}, 1'b0}))
        mask_next[bit_index(lfsr_next)] = 1'b1;
    end

    always_ff @(posedge clk)
      if (reset) mask <= '0;
      else       mask <= mask_next;

    assign codeword_o = codeword_i ^ mask;
  end else begin : comb_mask
    // When inject_en=0 this is a direct wire assignment (no XOR in critical path).
    logic [LOG_CW-1:0] bit_sel;
    assign bit_sel = bit_index(lfsr);

    always_comb begin
      codeword_o = codeword_i;
      if (inject_en & (&cnt))
        codeword_o[bit_sel] = ~codeword_i[bit_sel];
    end
  end

endmodule
