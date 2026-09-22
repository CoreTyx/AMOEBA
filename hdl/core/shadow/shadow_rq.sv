///////////////////////////////////////////
// shadow_rq.sv
//
// Purpose: SHARD Result Queue — N-deep shift register pushed at main W-stage.
//          Shadow pops at sW. Also provides N-entry associative forwarding for
//          main D-stage to cover the N-cycle stale-regfile window.
//
//          Forwarding priority: newest matching entry wins (entry[0] newest).
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_rq import cvw::*; #(parameter cvw_t P, parameter int N = 3) (
  input  logic              clk, reset,
  input  logic              StallW, FlushW,
  // Push from main W-stage
  input  logic [4:0]        RdW,
  input  logic [P.XLEN-1:0] ResultW,
  input  logic              RegWriteW,
  input  logic [P.XLEN-1:0] PCW,          // W-stage PC
  input  logic [1:0]        MemRWW,
  input  logic              HasStoreW,
  input  logic              SkipVerifyW,
  input  logic              IsFaultedInstrW,
  input  logic              DummyW,
  input  logic              DummySelW,
  input  logic              InstrValidW,
  // Shadow sW consumed head (pop = advance = no stall/flush)
  input  logic              sW_pop,
  // N-entry associative forwarding for main D-stage (rs1, rs2)
  input  logic [4:0]        Rs1D, Rs2D,
  output logic [P.XLEN-1:0] RQ_ValA, RQ_ValB,
  output logic              RQ_HitA, RQ_HitB,
  // RQ head (oldest valid entry) exposed to shadow sW
  output logic [4:0]        sRQ_Rd,
  output logic [P.XLEN-1:0] sRQ_IntResult,
  output logic              sRQ_IntWriteEn,
  output logic [P.XLEN-1:0] sRQ_MemAddr,
  output logic [1:0]        sRQ_MemRW,
  output logic              sRQ_HasStore,
  output logic [P.XLEN-1:0] sRQ_PC,
  output logic              sRQ_SkipVerify,
  output logic              sRQ_IsFaultedInstr,
  output logic              sRQ_DummyW,
  output logic              sRQ_DummySelW,
  output logic              sRQ_InstrValid
);

  // Entry width: 5 + XLEN + 1 + XLEN + 2 + 1 + XLEN + 1 + 1 + 1 + 1 + 1
  localparam int ENTRY_W = 5 + P.XLEN + 1 + P.XLEN + 2 + 1 + P.XLEN + 1 + 1 + 1 + 1 + 1;

  logic [ENTRY_W-1:0] entry [N];

  // Field layout (MSB→LSB):
  //   [ENTRY_W-1 : ENTRY_W-5]    Rd[4:0]
  //   [ENTRY_W-6 : ENTRY_W-5-XLEN] IntResult
  //   IntWriteEn (1)
  //   MemAddr (XLEN)
  //   MemRW (2)
  //   HasStore (1)
  //   PC (XLEN)
  //   SkipVerify (1)
  //   IsFaultedInstr (1)
  //   DummyW (1)
  //   DummySelW (1)
  //   InstrValid (1)

  function automatic [ENTRY_W-1:0] pack_rq(
    input logic [4:0]        rd,
    input logic [P.XLEN-1:0] result,
    input logic              int_we,
    input logic [P.XLEN-1:0] mem_addr,
    input logic [1:0]        mem_rw,
    input logic              has_store,
    input logic [P.XLEN-1:0] pc,
    input logic              skip,
    input logic              faulted,
    input logic              dummy,
    input logic              dummy_sel,
    input logic              valid
  );
    pack_rq = {rd, result, int_we, mem_addr, mem_rw, has_store, pc, skip, faulted, dummy, dummy_sel, valid};
  endfunction

  // Unpack head (entry[N-1] = oldest = consumed by shadow sW)
  assign {sRQ_Rd, sRQ_IntResult, sRQ_IntWriteEn, sRQ_MemAddr, sRQ_MemRW, sRQ_HasStore,
          sRQ_PC, sRQ_SkipVerify, sRQ_IsFaultedInstr, sRQ_DummyW, sRQ_DummySelW, sRQ_InstrValid}
    = entry[N-1];

  // Push data for W-stage
  wire [ENTRY_W-1:0] push_data = pack_rq(
    RdW, ResultW, RegWriteW,
    '0,          // MemAddr: not threaded in V1 (address check skipped)
    MemRWW, HasStoreW, PCW,
    SkipVerifyW, IsFaultedInstrW, DummyW, DummySelW, InstrValidW
  );

  // The old StallW_prev forwarding guard is removed.  The hazard: at the first
  // negedge after a stall exits (StallW just deasserted), the RQ would shift
  // (evict entry[2]) while the E-stage instruction hasn't advanced to M yet
  // (E→M happens at the next posedge).  The 1-cycle negedge bypass in
  // wallypipelinedcore.sv now covers this one-posedge stale-R1E window.
  //
  // Removing StallW_prev is also necessary for correctness: with a long stall
  // (e.g., 42-cycle I-cache miss), an instruction (e.g., addi) can sit in M
  // while the stall holds.  At the stall-exit posedge, W advances and captures
  // addi from M.  Without StallW_prev, the very next negedge pushes addi
  // (push_data now reflects W = addi).  With StallW_prev, that negedge was held,
  // so addi retired from W before the push — permanently skipped in the RQ.

  integer i;
  always_ff @(negedge clk) begin
    if (reset) begin
      for (i = 0; i < N; i++) entry[i] <= '0;
    end else if (StallW) begin
      // Hold all entries while stall active
    end else if (FlushW) begin
      for (i = N-1; i > 0; i--) entry[i] <= entry[i-1];
      entry[0] <= '0;
    end else begin
      for (i = N-1; i > 0; i--) entry[i] <= entry[i-1];
      entry[0] <= push_data;
    end
  end

  // ---------------------------------------------------------------------------
  // N-entry associative forwarding for main D-stage
  // Scan all entries; newest matching entry wins (priority encoder from entry[0])
  // ---------------------------------------------------------------------------
  // Inline unpack: Rd is ENTRY_W-1 downto ENTRY_W-5, IntWriteEn is at bit (1+XLEN+2+1+XLEN+1+1+1+1+1)
  // Simpler: unpack relevant fields per entry
  logic [4:0]        rq_rd    [N];
  logic [P.XLEN-1:0] rq_val   [N];
  logic              rq_we    [N];
  logic              rq_valid [N];

  genvar g;
  generate
    for (g = 0; g < N; g++) begin : unpack
      // Rd is top 5 bits
      assign rq_rd[g]    = entry[g][ENTRY_W-1 : ENTRY_W-5];
      // IntResult is next XLEN bits
      assign rq_val[g]   = entry[g][ENTRY_W-6 : ENTRY_W-5-P.XLEN];
      // IntWriteEn is next 1 bit
      assign rq_we[g]    = entry[g][ENTRY_W-6-P.XLEN];
      // InstrValid is bit 0
      assign rq_valid[g] = entry[g][0];
    end
  endgenerate

  // Priority: entry[0] is newest (highest priority)
  always_comb begin
    RQ_HitA = 1'b0; RQ_ValA = '0;
    RQ_HitB = 1'b0; RQ_ValB = '0;
    for (int j = N-1; j >= 0; j--) begin
      if (rq_valid[j] && rq_we[j] && rq_rd[j] != 5'b0) begin
        if (rq_rd[j] == Rs1D) begin RQ_HitA = 1'b1; RQ_ValA = rq_val[j]; end
        if (rq_rd[j] == Rs2D) begin RQ_HitB = 1'b1; RQ_ValB = rq_val[j]; end
      end
    end
  end

endmodule
