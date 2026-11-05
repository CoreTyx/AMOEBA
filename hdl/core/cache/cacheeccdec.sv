///////////////////////////////////////////
// cacheeccdec.sv
//
// Purpose: SECDED decoder for the L1 cache. Recomputes the check bits from
//          the received data (via cacheeccbits, the same submodule the
//          encoder uses), forms the syndrome, and classifies the result:
//            syndrome == 0                        -> clean, forward as-is
//            syndrome != 0, overall parity odd     -> single-bit, correctable
//            syndrome != 0, overall parity even    -> double-bit, uncorrectable
//          A correctable error's exact bit position is the syndrome itself
//          (one-hot decode); an uncorrectable one is flagged without trusting
//          the syndrome's position. Correction is combinational only -- the
//          caller (cacheway.sv/cachefsm.sv) is responsible for writing the
//          corrected, re-encoded codeword back into the array so the fix is
//          durable rather than re-derived on every read.
//
//          Cache-specific: independent of hdl/core/generic/ecc/, which is
//          used only by the register file.
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

module cacheeccdec #(
  parameter int DATA_WIDTH,
  parameter int R
) (
  input  logic [DATA_WIDTH+R:0] codeword_i,   // {data, parity, hamming[R-1:0]}
  output logic [DATA_WIDTH-1:0] data_o,
  output logic                  sec_err_o,     // correctable (single-bit) error found
  output logic                  ded_err_o      // uncorrectable (double-bit) error found
);

  localparam int CHECKBITS = R + 1;   // R Hamming bits + 1 overall parity bit
  localparam int CWBITS    = DATA_WIDTH + CHECKBITS;

  logic [DATA_WIDTH-1:0] data_rx;
  logic [R-1:0]          hamming_rx;

  assign hamming_rx = codeword_i[R-1:0];
  assign data_rx    = codeword_i[CWBITS-1:CHECKBITS];

  logic [R-1:0] hamming_expected;
  cacheeccbits #(.DATA_WIDTH(DATA_WIDTH), .R(R)) checkbits (
    .data_i    (data_rx),
    .hamming_o (hamming_expected)
  );

  logic [R-1:0] syndrome;
  logic         total_parity;

  assign syndrome     = hamming_rx ^ hamming_expected;
  assign total_parity = ^codeword_i;   // 0 for an even (0 or 2-bit) flip count, 1 for odd (1-bit)

  // Under the SECDED fault model (at most 2 bits wrong), total_parity==1
  // always means exactly one bit flipped somewhere in the whole codeword --
  // including the case where the flipped bit is the overall parity bit
  // itself (syndrome==0, since neither the data nor the Hamming bits
  // changed). That case must still be flagged as sec_err_o: if it isn't,
  // the stale parity bit never gets a writeback-triggered re-encode, and a
  // later, unrelated single-bit flip elsewhere in the same codeword would
  // then look like two wrong bits total and be misreported as an
  // uncorrectable DED instead of a correctable SEC.
  assign sec_err_o = total_parity;
  assign ded_err_o = ~total_parity & (syndrome != '0);

  // Correction mask: the data bit at codeword position p is the flipped bit
  // exactly when syndrome == p. A syndrome of 0 (parity-bit-only flip) or a
  // syndrome pointing at a check-bit-only position (a power of two) means no
  // data bit needs correcting -- data_o is already right in both cases; the
  // stale check bits get fixed for free the next time this codeword is
  // re-encoded on writeback.
  logic [DATA_WIDTH-1:0] correction;

  for (genvar cwpos = 1; cwpos <= DATA_WIDTH + R; cwpos++) begin : gen_corr
    localparam bit IS_CHECK_POS = (cwpos & (cwpos - 1)) == 0;
    if (!IS_CHECK_POS) begin : data_pos
      localparam int DBIT = cwpos - $clog2(cwpos + 1) - 1;
      assign correction[DBIT] = (syndrome == R'(cwpos));
    end
  end

  assign data_o = sec_err_o ? (data_rx ^ correction) : data_rx;

endmodule
