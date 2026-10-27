///////////////////////////////////////////
// cachefi.sv
//
// Purpose: Runtime fault injection into a cache's tag and data arrays.
//
// Usage:
// Instantiated by cache.sv, which XORs TagFlip and LineFlip into the words it
// writes to every way.  Driven by the core's shared generator (ft_fault_gen) and
// two unit enables: correctable (SEC) and uncorrectable (DED) events.
//
// Functionality:
// On the cycle the shared counter reaches PHASE, an event is armed for the tag
// array and for the data array.  Each applies to the next word written to its
// array (a fill, a store, or a correction write-back) and is then spent, so the
// flip is stored in the array like a real upset and is found by a later read or
// by the scrubber.  The flips use four fixed data positions whose Hamming
// syndromes together set every check bit (cacheeccbits.sv: the syndrome of a
// data bit is its codeword position): one of them makes a correctable error, two
// an uncorrectable one.  The masks come from registers, so the write data passes
// one XOR and nothing else.
///////////////////////////////////////////

module cachefi import cvw::*; #(
  parameter int TAGLEN, TAGR, LINELEN, LINER,       // data widths and Hamming check-bit counts
  parameter logic [FI_COUNT_BITS-1:0] PHASE
) (
  input  logic                     clk, reset,
  input  logic                     FaultInjectSec, FaultInjectDed,
  input  logic [15:0]              FaultLfsr,        // shared generator
  input  logic [FI_COUNT_BITS-1:0] FaultCount,
  input  logic                     TagWrite, LineWrite, // a word is written to that array this cycle
  output logic [TAGLEN-1:0]        TagFlip,
  output logic [LINELEN-1:0]       LineFlip
);
  // Data index of the data bit at 1-indexed codeword position p (cacheeccbits.sv)
  function automatic int databit(input int p);
    return p - $clog2(p + 1) - 1;
  endfunction
  // Positions 3, 2^(R-1)-1, 2^(R-1)+1 and the last data position: their syndromes OR to all ones
  function automatic int position(input int r, input int width, input int i);
    int last;
    last = width + r;
    if ((last & (last - 1)) == 0) last = last - 1;
    case (i)
      0:       return 3;
      1:       return (1 << (r - 1)) - 1;
      2:       return (1 << (r - 1)) + 1;
      default: return last;
    endcase
  endfunction

  logic       Event, TagPend, LinePend, Ded;
  logic [1:0] Sel;
  logic [3:0] Flips;                                // which of the four positions flip

  assign Event = (FaultInjectSec | FaultInjectDed) & (FaultCount == PHASE);
  always_ff @(posedge clk)
    if (reset) begin
      TagPend  <= 1'b0;
      LinePend <= 1'b0;
    end else begin
      TagPend  <= Event | (TagPend & ~TagWrite);
      LinePend <= Event | (LinePend & ~LineWrite);
    end
  // With both enabled, a quarter of the events are uncorrectable. No reset: read only while pending.
  always_ff @(posedge clk)
    if (Event) begin
      Sel <= FaultLfsr[1:0];
      Ded <= FaultInjectDed & (~FaultInjectSec | (FaultLfsr[15:14] == 2'b11));
    end

  assign Flips = (4'b1 << Sel) | (Ded ? (4'b1 << (Sel + 2'd1)) : 4'b0);
  always_comb begin
    TagFlip  = '0;
    LineFlip = '0;
    for (int i = 0; i < 4; i++) begin
      TagFlip[databit(position(TAGR, TAGLEN, i))]    = TagPend & Flips[i];
      LineFlip[databit(position(LINER, LINELEN, i))] = LinePend & Flips[i];
    end
  end
endmodule
