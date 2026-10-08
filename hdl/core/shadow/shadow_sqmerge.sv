///////////////////////////////////////////
// shadow_sqmerge.sv
//
// Purpose: SHARD store-to-load forwarding.  Every store buffered in the store queue
//          is older than the instruction in the main Memory stage, whether or not the
//          shadow has verified it yet.  Merge their bytes over the word read from the
//          cache, oldest first so that the newest store to a byte wins.
//
//          The match is on the full physical word address, so it is exact; entries
//          are naturally aligned and never cross a word.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_sqmerge import cvw::*; #(parameter cvw_t P, parameter int DEPTH = 8) (
  input  logic [P.LLEN-1:0]          ReadDataWordM,    // word read from the cache
  input  logic [P.PA_BITS-1:0]       PAdrM,            // physical address of the access
  input  var logic [P.PA_BITS-1:0]   sqPA [DEPTH],
  input  var logic [1:0]             sqSize [DEPTH],
  input  var logic [P.XLEN-1:0]      sqData [DEPTH],
  input  logic [$clog2(DEPTH+1)-1:0] sqCount,
  output logic [P.LLEN-1:0]          ReadDataWordFwdM  // word with the buffered stores merged in
);

  localparam LLENBYTES   = P.LLEN/8;
  localparam LLENADRBITS = $clog2(LLENBYTES);

  always_comb begin
    ReadDataWordFwdM = ReadDataWordM;
    for (int i = 0; i < DEPTH; i++) begin
      logic [LLENBYTES-1:0] Mask;
      logic [P.LLEN-1:0]    Data;
      Mask = (('d2**('d2**sqSize[i]))-'d1) << sqPA[i][LLENADRBITS-1:0];
      case (sqSize[i])
        2'b00:   Data = {LLENBYTES{sqData[i][7:0]}};
        2'b01:   Data = {(LLENBYTES/2){sqData[i][15:0]}};
        2'b10:   Data = {(LLENBYTES/4){sqData[i][31:0]}};
        default: Data = {(P.LLEN/P.XLEN){sqData[i]}};
      endcase
      if ((i < sqCount) & (sqPA[i][P.PA_BITS-1:LLENADRBITS] == PAdrM[P.PA_BITS-1:LLENADRBITS]))
        for (int b = 0; b < LLENBYTES; b++)
          if (Mask[b]) ReadDataWordFwdM[8*b +: 8] = Data[8*b +: 8];
    end
  end

endmodule
