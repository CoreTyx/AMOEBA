///////////////////////////////////////////
// dummymask.sv
//
// Purpose: Operand obfuscation for inserted dummy instructions
//
// AMOEBA addition; not part of upstream CORE-V Wally.
//
// Random instruction insertion replays a previously captured encoding verbatim,
// so a dummy reads the same architectural registers -- and therefore the same
// live data -- as the instruction it was captured from.  Left alone that is a
// side-channel liability rather than a defence: the dummy re-runs an ALU
// operation on secret operands, contributing a second power sample correlated
// with the real one.  Insertion is meant to decorrelate *when* an operation
// happens; this module decorrelates *what* the dummies touch.
//
// On an injection cycle each register read port is XORed with an independent
// pseudo-random 64-bit mask, so a dummy's operand, ALU switching activity and
// shadow-register write are all uncorrelated with the real register contents.
// Real instructions are untouched: the mask is gated by InjectD.
//
// This is obfuscation, not cryptographic masking.  It does not reduce the
// leakage of the real instruction stream; it only stops the inserted dummies
// from adding correlated signal to it.
//
// Two independent generators are used, because a single shared mask would
// cancel in A-B and would preserve the Hamming distance between the two
// operands either way.  Both characteristic polynomials were verified
// primitive over GF(2) (order of x is exactly 2**64-1), and they are not
// reciprocals of one another:
//   LFSR A: x^64 + x^63 + x^61 + x^60 + 1
//   LFSR B: x^64 + x^63 + x^62 + x^53 + 1
// Neither generator shares state with the dummygen LFSR, whose bits already
// gate the injection decision and the shadow register select; reusing that
// state would correlate mask value with insertion timing.
///////////////////////////////////////////

module dummymask #(parameter WIDTH = 64) (
  input  logic             clk, reset,
  input  logic             InjectD,                  // decode stage holds an injected dummy this cycle
  input  logic [WIDTH-1:0] Rd1D, Rd2D,               // register file read data, after ECC correction
  output logic [WIDTH-1:0] Rd1MaskedD, Rd2MaskedD    // operands as seen by the rest of the pipeline
);

  // Free-running so that the mask sequence does not correlate with when
  // insertion was enabled.  Seeds are non-zero, as an all-zero LFSR state is
  // the fixed point of the recurrence.
  logic [63:0] LfsrA, LfsrB;

  always_ff @(posedge clk)
    if (reset) LfsrA <= 64'h0123_4567_89AB_CDEF;
    else       LfsrA <= {LfsrA[62:0], LfsrA[63] ^ LfsrA[3] ^ LfsrA[2] ^ LfsrA[0]};

  always_ff @(posedge clk)
    if (reset) LfsrB <= 64'hFEDC_BA98_7654_3210;
    else       LfsrB <= {LfsrB[62:0], LfsrB[63] ^ LfsrB[10] ^ LfsrB[1] ^ LfsrB[0]};

  // The mask comes straight out of a flop, so this adds a single XOR level to
  // the decode-stage read path and nothing to the execute-stage ALU path.
  assign Rd1MaskedD = InjectD ? (Rd1D ^ LfsrA[WIDTH-1:0]) : Rd1D;
  assign Rd2MaskedD = InjectD ? (Rd2D ^ LfsrB[WIDTH-1:0]) : Rd2D;

`ifdef ECE411_DUMMY_TRACE
  // Debug-only: show the operands a dummy would have read against what it
  // actually sees.  InjectD is a single-cycle pulse, so this cannot double-report.
  always_ff @(posedge clk)
    if (~reset & InjectD) begin
      $display("[dmask] %0t  rs1 %016h -> %016h   (mask %016h)",
               $time, Rd1D, Rd1MaskedD, LfsrA[WIDTH-1:0]);
      $display("[dmask] %0t  rs2 %016h -> %016h   (mask %016h)",
               $time, Rd2D, Rd2MaskedD, LfsrB[WIDTH-1:0]);
    end
`endif

endmodule
