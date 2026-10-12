///////////////////////////////////////////
// regfile.sv
//
// Written: David_Harris@hmc.edu, Sarah.Harris@unlv.edu
// Created: 9 January 2021
// Modified: Saipranavvk saipranavvk@gmail.com 4 September 2026
//           ECC hardening: register storage upgraded to full SECDED codewords.
//           Each entry stores XLEN + R + 1 bits so that a single-bit upset in
//           the array is corrected transparently on the next read.  Two
//           ecc_bit_flip instances (one per read port) inject pseudo-random
//           single-bit errors when inject_en is asserted, allowing the ECC
//           correction path to be exercised in simulation and DFT.
// Modified: 11 October 2026
//           Timing: the array is written on the rising edge and a read of the
//           register being written is bypassed from wd3.  The falling-edge
//           write gave the write (decode, mux, encode) and the read that
//           followed it (mux, decode, encode) half a cycle each.
//           Timing: the read ports return the stored codeword.  Decoding it
//           here only for the operand register to encode it again put two
//           XOR trees behind the read mux; the operand register (flopenrc_cw)
//           now stores the codeword as read and does the one decode.
//
// Purpose: 3-port register file of SECDED codewords
//
// Documentation: RISC-V System on Chip Design
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// https://github.com/openhwgroup/cvw
//
// Copyright (C) 2021-23 Harvey Mudd College & Oklahoma State University
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

module regfile #(
  parameter XLEN, E_SUPPORTED,
  // SECDED check-bit count and total codeword width
  parameter int R  = (XLEN <=   1) ? 2 :
                     (XLEN <=   4) ? 3 :
                     (XLEN <=  11) ? 4 :
                     (XLEN <=  26) ? 5 :
                     (XLEN <=  57) ? 6 :
                     (XLEN <= 120) ? 7 : 8,
  parameter int CW = XLEN + R + 1  // e.g. 64+7+1 = 72 for RV64
) (
  input  logic             clk, reset,
  input  logic             we3,
  input  logic [4:0]       a1, a2, a3,
  input  logic [XLEN-1:0]  wd3,
  input  logic             DummyW,
  input  logic             DummySelW,
  output logic [CW-1:0]    rd1, rd2,           // codewords as stored: not checked or corrected here
  input  logic             inject_en
);

  localparam ARCHREGS = E_SUPPORTED ? 16 : 32;
  localparam NUMREGS  = ARCHREGS + 2;
  localparam logic [5:0] SHADOW0 = 6'(ARCHREGS);

  // Storage array holds encoded codewords.
  // All-zeros is the valid SECDED codeword for data=0 (Hamming bits and
  // overall parity are all 0 when data is 0), so reset to '0 is correct.
  logic [CW-1:0] rf [NUMREGS-1:1];
  logic [5:0]    WriteIdx;
  integer i;

  // Dummy writes are redirected to shadow registers and cannot alter
  // architectural register state.
  assign WriteIdx = DummyW ? (SHADOW0 | {5'b0, DummySelW}) : {1'b0, a3};

  // ── Write path ────────────────────────────────────────────────────────────────
  // Encode wd3 combinationally, then store the codeword on the rising clock edge.
  logic [CW-1:0] cw_wr3;
  logic          WriteEn;
  ecc_secded_enc #(.DATA_WIDTH(XLEN)) enc_wr (.data_i(wd3), .codeword_o(cw_wr3));

  assign WriteEn = we3 & (WriteIdx != '0);

  always_ff @(posedge clk)
    if (reset) for (i = 1; i < NUMREGS; i++) rf[i] <= '0;
    else       if (WriteEn)                   rf[WriteIdx] <= cw_wr3;

  // ── Write-to-read bypass ──────────────────────────────────────────────────────
  // The array does not hold this cycle's write until the next edge, so a read of
  // the register being written takes the codeword on its way in instead.  The
  // index compare is on the array index, as the read is, so a dummy write to a
  // shadow register can never be bypassed into a read of an architectural one.
  logic Bypass1, Bypass2;
  assign Bypass1 = WriteEn & ({1'b0, a1} == WriteIdx);
  assign Bypass2 = WriteEn & ({1'b0, a2} == WriteIdx);

  // ── Read ports ────────────────────────────────────────────────────────────────
  // The injector sits on the array output only: a bypassed read never touched
  // the array.
  logic [CW-1:0] cw_rd1_raw, cw_rd1_inj;
  logic [CW-1:0] cw_rd2_raw, cw_rd2_inj;

  assign cw_rd1_raw = (a1 != '0) ? rf[a1] : '0;
  assign cw_rd2_raw = (a2 != '0) ? rf[a2] : '0;

  ecc_bit_flip  #(.CW_WIDTH(CW)) inj1 (
    .clk, .reset, .inject_en,
    .codeword_i(cw_rd1_raw),
    .codeword_o(cw_rd1_inj)
  );

  ecc_bit_flip  #(.CW_WIDTH(CW)) inj2 (
    .clk, .reset, .inject_en,
    .codeword_i(cw_rd2_raw),
    .codeword_o(cw_rd2_inj)
  );

  assign rd1 = Bypass1 ? cw_wr3 : cw_rd1_inj;
  assign rd2 = Bypass2 ? cw_wr3 : cw_rd2_inj;

endmodule
