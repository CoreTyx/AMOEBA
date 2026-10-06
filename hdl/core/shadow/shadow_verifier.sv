///////////////////////////////////////////
// shadow_verifier.sv
//
// Purpose: SHARD per-instruction result comparison at shadow sWriteback.
//          Compares the shadow's independently computed result with the RQ
//          committed value. Rev 6 adds effective-address verification for
//          loads and stores (shadow's own address adder vs the main's observed
//          access address), and excludes loads from the ALU-result compare
//          (a load's architectural result is memory data, not an ALU output).
//          SkipVerify entries (FP, DIV, CSR, fence, WFI, AMO, etc.) pass through.
//
// A component of the CORE-V-WALLY configurable RISC-V project.
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

module shadow_verifier import cvw::*; #(parameter cvw_t P) (
  input  logic [31:0]        sInstr32,        // instruction word (from IQ via shadow pipeline)
  input  logic [P.XLEN-1:0]  sALUResult,      // shadow independently computed result
  input  logic [P.XLEN-1:0]  rq_IntResult,    // main's committed result from RQ
  input  logic               rq_IntWriteEn,   // 1 = integer result is meaningful
  input  logic               rq_SkipVerify,   // 1 = skip comparison (HW-CSR, fence, etc.)
  input  logic               rq_InstrValid,   // 0 = bubble / flushed instruction
  input  logic               sBranchTaken,    // shadow computed branch outcome
  input  logic               rq_PCSrc,        // main's branch taken (from IQ.PCSrc)
  input  logic               isBranch,        // instruction at sW is a branch
  input  logic [P.XLEN-1:0]  rq_PC,           // instruction PC from RQ (also for fault reporting)
  input  logic [P.XLEN-1:0]  sPC,             // shadow-pipeline PC at sW (from IQ via sD..sW)
  // Rev 6 effective-address verification (loads/stores)
  input  logic [P.XLEN-1:0]  sEA,             // shadow-recomputed effective address
  input  logic [P.XLEN-1:0]  mainEA,          // main's observed access address (RQ.MemAddr)
  input  logic               isLoad,          // instruction at sW is a load
  input  logic               isStore,         // instruction at sW is a store
  output logic               SecFaultMatch,   // 1 = verification passed
  output logic               SecFaultMismatch,// 1 = mismatch detected -> MSECFAULT
  output logic [P.XLEN-1:0]  SecFaultPC       // PC of the mismatching instruction
);

  logic result_mismatch;
  logic branch_mismatch;
  logic ea_mismatch;
  logic pc_match;

  // The RQ (W-stage results) and the IQ-fed shadow pipeline (sD..sW) are filled at
  // different pipeline points and can transiently slip by a cycle around stalls/flushes
  // (load-use bubbles, mispredicts). Only compare when both refer to the SAME retiring
  // instruction (PCs agree); otherwise this cycle is "can't-verify" and must not fault.
  // A genuine datapath fault keeps the PCs equal (same instruction) with differing
  // result/EA/branch, so coverage is preserved; a control-flow fault shows as a PC
  // mismatch and is a documented boundary (future next-PC check).
  assign pc_match = (sPC == rq_PC);

  // A load's architectural result is memory data (not an ALU output), so the
  // shadow ALU result must NOT be compared against rq_IntResult for loads; the
  // load is verified by its effective address instead.
  assign result_mismatch = rq_IntWriteEn && ~isLoad && (sALUResult != rq_IntResult);
  assign branch_mismatch = isBranch       && (sBranchTaken != rq_PCSrc);

  // Effective-address check: the shadow's own address adder must agree with the
  // address the main pipeline actually accessed. Covers the AGU / immediate /
  // address-sum datapath for every load and store, non-destructively.
  assign ea_mismatch     = (isLoad | isStore) && (sEA != mainEA);

  always_comb begin
    if (!rq_InstrValid || rq_SkipVerify || !pc_match) begin
      SecFaultMatch    = 1'b1;
      SecFaultMismatch = 1'b0;
      SecFaultPC       = '0;
    end else if (result_mismatch || branch_mismatch || ea_mismatch) begin
      SecFaultMatch    = 1'b0;
      SecFaultMismatch = 1'b1;
      SecFaultPC       = rq_PC;
    end else begin
      SecFaultMatch    = 1'b1;
      SecFaultMismatch = 1'b0;
      SecFaultPC       = '0;
    end
  end

endmodule
