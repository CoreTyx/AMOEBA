///////////////////////////////////////////
// flopenrc_cw.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 4 September 2026 (as part of flopenrc_ecc)
// Modified: 11 October 2026: split out of flopenrc_ecc
//
// Purpose: The storage half of flopenrc_ecc: a register with enable, synchronous
//          reset and enabled clear that holds a SECDED codeword, with the error
//          injection XOR, the decoder and the self-repair behind it.  The flip
//          mask comes from outside (ecc_flip_mask), so one generator can serve
//          every register in a group.
//
//          flopenrc_ecc is an encoder in front of this module.  Use this one
//          directly when the value to store is already a codeword -- a register
//          file read, for instance -- so that it is not decoded and encoded
//          again on the way in.  An error already present in cw is stored as it
//          is and handled like any other: q is corrected, q_raw is not, and
//          sec_err_o / ded_err_o report it.  See flopenrc_ecc.sv for the q / q_raw
//          contract and the self-repair.
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

module flopenrc_cw #(
  parameter int WIDTH = 64,
  // Number of Hamming check bits for this data width
  parameter int R = (WIDTH <=   1) ? 2 :
                    (WIDTH <=   4) ? 3 :
                    (WIDTH <=  11) ? 4 :
                    (WIDTH <=  26) ? 5 :
                    (WIDTH <=  57) ? 6 :
                    (WIDTH <= 120) ? 7 : 8
) (
  input  logic             clk, reset, clear, en,
  input  logic [WIDTH+R:0] flip_mask,  // one-hot on an injection cycle, else zero (ecc_flip_mask)
  input  logic [WIDTH+R:0] cw,         // codeword to store: {data, overall parity, R Hamming bits}
  output logic [WIDTH-1:0] q,          // corrected data
  output logic             sec_err_o,
  output logic             ded_err_o,
  output logic [WIDTH-1:0] q_raw       // data as stored: one decode earlier than q, wrong while an error flag is high
);

  localparam int CW_WIDTH = WIDTH + R + 1;  // data + R Hamming bits + 1 overall parity

  // ── Storage FF (holds CW_WIDTH bits) ─────────────────────────────────────────
  // All-zeros is the valid codeword for data=0 (Hamming bits and parity all 0).
  logic [CW_WIDTH-1:0] cw_stored, cw_repair;

  always_ff @(posedge clk)
    if (reset)          cw_stored <= '0;
    else if (en)
      if (clear)        cw_stored <= '0;
      else              cw_stored <= cw;
    else if (sec_err_o) cw_stored <= cw_repair;

  // ── Error injection ──────────────────────────────────────────────────────────
  // The flip mask comes from a register (ecc_flip_mask): cw_stored is a register
  // output, and q_raw has nothing but this XOR between it and the pipeline.
  logic [CW_WIDTH-1:0] cw_inj;
  assign cw_inj = cw_stored ^ flip_mask;

  // Data bits sit above the R Hamming bits and the overall parity bit.
  assign q_raw = cw_inj[CW_WIDTH-1 : R+1];

  // ── Decode ────────────────────────────────────────────────────────────────────
  ecc_secded_dec #(.DATA_WIDTH(WIDTH)) dec (
    .codeword_i(cw_inj),
    .data_o    (q),
    .sec_err_o,
    .ded_err_o
  );

  // ── Repair ────────────────────────────────────────────────────────────────────
  // The corrected data re-encoded, which also repairs an error in a check bit.
  ecc_secded_enc #(.DATA_WIDTH(WIDTH)) repair_enc (.data_i(q), .codeword_o(cw_repair));

endmodule
