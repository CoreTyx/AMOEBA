///////////////////////////////////////////
// cacheeccenc.sv
//
// Purpose: SECDED encoder for the L1 cache. Packs DATA_WIDTH data bits into
//          a systematic codeword {data_i, parity, hamming[R-1:0]}: the data
//          bits pass through unmodified, so a check-bit-only side array can
//          hold the new information without reshaping the cache's existing
//          raw tag/data storage. Runs on every write into a way (line fill,
//          store hit, or a correction writeback).
//
//          Cache-specific: independent of hdl/core/generic/ecc/, which is
//          used only by the register file.
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

module cacheeccenc #(
  parameter int DATA_WIDTH,
  parameter int R
) (
  input  logic [DATA_WIDTH-1:0] data_i,
  output logic [DATA_WIDTH+R:0] codeword_o   // {data_i, parity, hamming[R-1:0]}
);

  logic [R-1:0] hamming;
  logic         parity;

  cacheeccbits #(.DATA_WIDTH(DATA_WIDTH), .R(R)) checkbits (
    .data_i    (data_i),
    .hamming_o (hamming)
  );

  // Overall parity covers every other codeword bit, so a clean codeword's
  // full XOR (data + hamming + parity) is always 0.
  assign parity = ^data_i ^ ^hamming;

  assign codeword_o = {data_i, parity, hamming};

endmodule
