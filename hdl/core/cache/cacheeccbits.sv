///////////////////////////////////////////
// cacheeccbits.sv
//
// Purpose: Shared extended-Hamming check-bit computation for the L1 cache's
//          SECDED protection. Given DATA_WIDTH data bits, computes the R
//          Hamming check bits (not the overall parity bit -- that is added
//          separately by the encoder). Instantiated once by cacheeccenc and
//          once by cacheeccdec so both sides run the exact same equations
//          instead of maintaining two independently-verified copies.
//
//          This is a cache-specific implementation, kept structurally
//          independent from hdl/core/generic/ecc/ (used only by the register
//          file) so a bug in one mechanism cannot compromise both.
//
// Codeword position convention (1-indexed): position p is a check-bit
// position iff p is a power of two; every other position holds a data bit,
// assigned in increasing order of position. Check bit k is the XOR of every
// data bit whose codeword position has bit k set.
//
// R has no default: it must be sized explicitly at every instantiation
// (2^R >= DATA_WIDTH + R + 1), and elaboration fails via $error below if it
// is not, rather than silently producing an aliased code.
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

module cacheeccbits #(
  parameter int DATA_WIDTH,
  parameter int R
) (
  input  logic [DATA_WIDTH-1:0] data_i,
  output logic [R-1:0]          hamming_o
);

  localparam int CWBITS = DATA_WIDTH + R;

  if (2**R < CWBITS + 1)
    $error("cacheeccbits: R=%0d is insufficient for DATA_WIDTH=%0d (need 2^R >= DATA_WIDTH+R+1=%0d)",
           R, DATA_WIDTH, CWBITS + 1);

  for (genvar bit_k = 0; bit_k < R; bit_k++) begin : gen_hamming
    logic [CWBITS-1:0] cov;
    for (genvar cwpos = 1; cwpos <= CWBITS; cwpos++) begin : gen_cov
      localparam bit IS_CHECK_POS = (cwpos & (cwpos - 1)) == 0;
      localparam bit COVERS_K     = ((cwpos >> bit_k) & 1) == 1;
      if (!IS_CHECK_POS && COVERS_K) begin : contributes
        localparam int DBIT = cwpos - $clog2(cwpos + 1) - 1;
        assign cov[cwpos-1] = data_i[DBIT];
      end else begin : blank
        assign cov[cwpos-1] = 1'b0;
      end
    end
    assign hamming_o[bit_k] = ^cov;
  end

endmodule
