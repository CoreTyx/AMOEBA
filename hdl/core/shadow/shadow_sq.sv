///////////////////////////////////////////
// shadow_sq.sv
//
// Purpose: SHARD Store Queue — N-deep FIFO, pushed at main M-stage for stores.
//          Shadow pops at sM. Conflict detection moved to M-stage in wallypipelinedcore
//          using PAdrM (physical address) instead of E-stage virtual address.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_sq import cvw::*; #(parameter cvw_t P, parameter int N = 3) (
  input  logic                   clk, reset,
  input  logic                   StallM, FlushM,
  // Push: main M-stage store (PA required — use PAdrM from lsu, not IEUAdrM which is VA)
  input  logic [P.PA_BITS-1:0]   PAdrM,
  input  logic [P.XLEN-1:0]      WriteDataM,
  input  logic [P.XLEN/8-1:0]    ByteMaskM,
  input  logic                   StoreM,
  // Pop: shadow sM consumed head
  input  logic                   sM_pop,
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
  wire [ENTRY_W-1:0] push_store = {PAdrM, WriteDataM, ByteMaskM, 1'b1};
  wire [ENTRY_W-1:0] push_null  = '0;

  integer i;
  always_ff @(posedge clk) begin
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

endmodule
