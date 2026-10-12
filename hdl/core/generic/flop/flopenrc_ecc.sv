///////////////////////////////////////////
// flopenrc_ecc.sv
//
// Written: Saipranavvk saipranavvk@gmail.com 4 September 2026
// Modified:
//
// Purpose: SECDED-protected D flip-flop with enable, synchronous reset, and
//          enabled clear.  Drop-in data-path replacement for flopenrc with
//          three additional output ports (sec_err_o, ded_err_o, q_raw) and one
//          additional input port (inject_en).
//
//          Internal pipeline (purely combinational except the storage FF):
//            d[WIDTH-1:0]
//            → ecc_secded_enc  (XOR tree, no FF)
//            → flopenrc_cw, which is everything from here down:
//            → always_ff       (stores CW_WIDTH bits: WIDTH + R + 1)
//            → ecc_bit_flip    (combinational, clocked LFSR inside)
//            → q_raw[WIDTH-1:0]                       (data bits as stored)
//            → ecc_secded_dec  (syndrome + correction, no FF)
//            → q[WIDTH-1:0], sec_err_o, ded_err_o
//
//          q is always correct for a single-bit error, but arrives a full
//          decode later than q_raw.  q_raw is correct only while sec_err_o and
//          ded_err_o are low.  A consumer may use q_raw if nothing it computes
//          is kept in a cycle where sec_err_o is high -- the pipeline does this
//          by stalling on sec_err_o.  Anything with an effect of its own
//          (a memory, CSR or register file write) must use q.
//
//          Self-repair: while the register is holding (en low) and reports a
//          single-bit error, it rewrites itself with the corrected codeword.
//          A consumer stalled on sec_err_o therefore waits one cycle.
//
//          When inject_en = 0 the ecc_bit_flip module is a wire, so the
//          decode path sees clean (uncorrupted) codewords.  In this case
//          sec_err_o and ded_err_o will always be 0.
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

module flopenrc_ecc #(parameter int WIDTH = 64) (
  input  logic             clk, reset, clear, en,
  input  logic             inject_en,
  input  logic [WIDTH-1:0] d,
  output logic [WIDTH-1:0] q,          // corrected data
  output logic             sec_err_o,
  output logic             ded_err_o,
  output logic [WIDTH-1:0] q_raw       // data as stored: one decode earlier than q, wrong while an error flag is high
);

  // Number of Hamming check bits for this data width
  localparam int R = (WIDTH <=   1) ? 2 :
                     (WIDTH <=   4) ? 3 :
                     (WIDTH <=  11) ? 4 :
                     (WIDTH <=  26) ? 5 :
                     (WIDTH <=  57) ? 6 :
                     (WIDTH <= 120) ? 7 : 8;

  // Encode here; storage, injection, decode and repair are flopenrc_cw's.
  logic [WIDTH+R:0] cw_enc;
  ecc_secded_enc #(.DATA_WIDTH(WIDTH)) enc (.data_i(d), .codeword_o(cw_enc));

  flopenrc_cw #(.WIDTH(WIDTH)) store (
    .clk, .reset, .clear, .en, .inject_en,
    .cw(cw_enc), .q, .sec_err_o, .ded_err_o, .q_raw
  );

endmodule
