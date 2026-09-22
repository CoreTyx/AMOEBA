///////////////////////////////////////////
// shadow_sq.sv
//
// Purpose: SHARD Store Queue — N-deep FIFO, pushed at main M-stage for stores.
//          Shadow pops at sM. Contains N-entry conflict detector: if any SQ entry
//          overlaps with a pending main store at E-stage, assert ShadowConflictStallE.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_sq import cvw::*; #(parameter cvw_t P, parameter int N = 3) (
  input  logic                   clk, reset,
  input  logic                   StallM, FlushM,
  // Push: main M-stage store
  input  logic [P.PA_BITS-1:0]   IEUAdrM,
  input  logic [P.XLEN-1:0]      WriteDataM,
  input  logic [P.XLEN/8-1:0]    ByteMaskM,
  input  logic                   StoreM,
  // Pop: shadow sM consumed head
  input  logic                   sM_pop,
  // Conflict detection: main E-stage incoming store
  input  logic [P.PA_BITS-1:0]   IEUAdrE_PA,
  input  logic [P.XLEN/8-1:0]    ByteMaskE,
  input  logic                   StoreE,
  output logic                   ShadowConflictStallE,
  // Shadow head for sM
  output logic [P.PA_BITS-1:0]   sSQ_PA,
  output logic [P.XLEN-1:0]      sSQ_WriteData,
  output logic [P.XLEN/8-1:0]    sSQ_ByteMask,
  output logic                   sSQ_Valid
);

  // Entry width: PA_BITS + XLEN + XLEN/8 + 1
  localparam int ENTRY_W = P.PA_BITS + P.XLEN + P.XLEN/8 + 1;

  logic [ENTRY_W-1:0] sq [N];

  // Unpack head
  assign {sSQ_PA, sSQ_WriteData, sSQ_ByteMask, sSQ_Valid} = sq[N-1];

  // Push data
  wire [ENTRY_W-1:0] push_store = {IEUAdrM, WriteDataM, ByteMaskM, 1'b1};
  wire [ENTRY_W-1:0] push_null  = '0;

  integer i;
  always_ff @(negedge clk) begin
    if (reset) begin
      for (i = 0; i < N; i++) sq[i] <= '0;
    end else if (StallM) begin
      // Hold all entries
    end else if (FlushM) begin
      for (i = N-1; i > 0; i--) sq[i] <= sq[i-1];
      sq[0] <= push_null;
    end else begin
      for (i = N-1; i > 0; i--) sq[i] <= sq[i-1];
      sq[0] <= StoreM ? push_store : push_null;
    end
  end

  // ---------------------------------------------------------------------------
  // Conflict detection: scan all N entries for PA overlap with incoming E-stage store
  // ---------------------------------------------------------------------------
  logic [N-1:0] conflict;
  genvar g;
  generate
    for (g = 0; g < N; g++) begin : conf
      logic                  entry_valid;
      logic [P.PA_BITS-1:0]  entry_pa;
      logic [P.XLEN/8-1:0]   entry_mask;
      assign entry_valid = sq[g][0];
      assign entry_pa    = sq[g][ENTRY_W-1 : P.XLEN + P.XLEN/8 + 1];
      assign entry_mask  = sq[g][P.XLEN/8 : 1];
      assign conflict[g] = entry_valid
                         & (entry_pa[P.PA_BITS-1:2] == IEUAdrE_PA[P.PA_BITS-1:2])
                         & ((entry_mask & ByteMaskE) != '0);
    end
  endgenerate

  assign ShadowConflictStallE = StoreE & (|conflict);

endmodule
