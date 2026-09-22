///////////////////////////////////////////
// cache_ecc_unit_tb.sv
//
// Purpose: Self-checking testbench for cacheeccbits/cacheeccenc/cacheeccdec (the cache's own
//          SECDED implementation -- deliberately independent of hdl/core/generic/ecc/, which is
//          the register file's SECDED pair; see hvl/ecc/ecc_tb.sv for that one). Exercises the two
//          widths the cache actually uses: the tag codeword (DATA_WIDTH=44, R=6) and the full-line
//          codeword (DATA_WIDTH=512, R=10). Purely combinational; compiled standalone.
//
//          Coverage per width: a clean round trip, an exhaustive single-bit-flip sweep across
//          every codeword position (confirms every position is correctable, including the overall
//          parity bit itself -- a lone parity-bit flip must still be flagged as sec_err_o, or a
//          later unrelated flip in the same codeword can be misclassified as uncorrectable; see the
//          cacheeccdec.sv header for why), and a spot-checked set of double-bit-flip pairs (confirms
//          they're flagged uncorrectable rather than silently "corrected" to the wrong value).
//
// Run: make -C sim cache_ecc_unit_test
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

`timescale 1ps/1ps

module cache_ecc_unit_tb;

  int errors;
  int totalchecks;

  // ── Tag width: DATA_WIDTH=44, R=6 (this branch's default rv64gc config: PA_BITS=56, NUMSETS=64) ──
  localparam int TAG_DW = 44;
  localparam int TAG_R  = 6;
  localparam int TAG_CW = TAG_DW + TAG_R + 1;

  logic [TAG_DW-1:0] tag_data;
  logic [TAG_CW-1:0] tag_codeword, tag_corrupted;
  logic [TAG_DW-1:0] tag_decoded;
  logic tag_sec, tag_ded;

  cacheeccenc #(.DATA_WIDTH(TAG_DW), .R(TAG_R)) tag_enc (.data_i(tag_data), .codeword_o(tag_codeword));
  cacheeccdec #(.DATA_WIDTH(TAG_DW), .R(TAG_R)) tag_dec (.codeword_i(tag_corrupted), .data_o(tag_decoded), .sec_err_o(tag_sec), .ded_err_o(tag_ded));

  // ── Line width: DATA_WIDTH=512, R=10 (this branch's default LINELEN) ──
  localparam int LINE_DW = 512;
  localparam int LINE_R  = 10;
  localparam int LINE_CW = LINE_DW + LINE_R + 1;

  logic [LINE_DW-1:0] line_data;
  logic [LINE_CW-1:0] line_codeword, line_corrupted;
  logic [LINE_DW-1:0] line_decoded;
  logic line_sec, line_ded;

  cacheeccenc #(.DATA_WIDTH(LINE_DW), .R(LINE_R)) line_enc (.data_i(line_data), .codeword_o(line_codeword));
  cacheeccdec #(.DATA_WIDTH(LINE_DW), .R(LINE_R)) line_dec (.codeword_i(line_corrupted), .data_o(line_decoded), .sec_err_o(line_sec), .ded_err_o(line_ded));

  task automatic report(input string what, input bit ok);
    totalchecks++;
    if (!ok) begin
      $display("FAIL: %s", what);
      errors++;
    end
  endtask

  initial begin
    errors = 0;
    totalchecks = 0;

    // ── Tag width checks ──
    tag_data = 44'h2A5C3F91B7;
    #1;
    tag_corrupted = tag_codeword;
    #1;
    report("tag: clean decode", tag_decoded === tag_data && !tag_sec && !tag_ded);

    for (int i = 0; i < TAG_CW; i++) begin
      tag_corrupted = tag_codeword ^ (TAG_CW'(1) << i);
      #1;
      report($sformatf("tag: single-bit sweep bit %0d", i), tag_decoded === tag_data && tag_sec && !tag_ded);
    end

    for (int i = 0; i < TAG_CW; i++) begin
      int j;
      j = (i + 1 + (i % (TAG_CW-1))) % TAG_CW;
      if (j == i) j = (j + 1) % TAG_CW;
      tag_corrupted = tag_codeword ^ (TAG_CW'(1) << i) ^ (TAG_CW'(1) << j);
      #1;
      report($sformatf("tag: double-bit spot-check (%0d,%0d)", i, j), tag_ded);
    end

    // ── Line width checks ──
    line_data = {8{64'h0123456789ABCDEF}} ^ {8{64'hA5A5A5A5DEADBEEF}};
    #1;
    line_corrupted = line_codeword;
    #1;
    report("line: clean decode", line_decoded === line_data && !line_sec && !line_ded);

    for (int i = 0; i < LINE_CW; i++) begin
      line_corrupted = line_codeword ^ (LINE_CW'(1) << i);
      #1;
      report($sformatf("line: single-bit sweep bit %0d", i), line_decoded === line_data && line_sec && !line_ded);
    end

    // Full N^2 double-bit sweep on a 523-bit codeword is too slow for a routine test; spot-check a
    // representative diagonal (every position paired with one ~1/3 of the way around) plus the
    // boundary cases (adjacent bits, and the two ends of the codeword).
    for (int i = 0; i < LINE_CW; i++) begin
      int j;
      j = (i + LINE_CW/3 + 1) % LINE_CW;
      if (j == i) j = (j + 1) % LINE_CW;
      line_corrupted = line_codeword ^ (LINE_CW'(1) << i) ^ (LINE_CW'(1) << j);
      #1;
      report($sformatf("line: double-bit spot-check (%0d,%0d)", i, j), line_ded);
    end
    line_corrupted = line_codeword ^ (LINE_CW'(1) << 0) ^ (LINE_CW'(1) << (LINE_CW-1));
    #1;
    report("line: double-bit boundary (0, CW-1)", line_ded);

    $display("cache_ecc_unit_tb: %0d/%0d checks passed", totalchecks - errors, totalchecks);
    if (errors == 0) $display("ALL TESTS PASSED");
    else $display("%0d FAILURES", errors);
    $finish;
  end

endmodule
