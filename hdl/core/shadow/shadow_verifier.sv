///////////////////////////////////////////
// shadow_verifier.sv
//
// Purpose: SHARD per-instruction result comparison at shadow sWriteback.
//          Compares shadow's independently computed result with the RQ committed value.
//          SkipVerify entries (FP, DIV, CSR, fence, WFI, etc.) pass through silently.
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
  input  logic               sBranchTaken,    // shadow computed branch outcome (FlagsE[0] or equiv)
  input  logic               rq_PCSrc,        // main's branch taken (from IQ.PCSrc)
  input  logic               isBranch,        // instruction at sW is a branch
  input  logic [P.XLEN-1:0]  rq_PC,           // instruction PC (for fault reporting)
  output logic               SecFaultMatch,   // 1 = verification passed
  output logic               SecFaultMismatch,// 1 = mismatch detected → MSECFAULT
  output logic [P.XLEN-1:0]  SecFaultPC       // PC of the mismatching instruction
);

  logic result_mismatch;
  logic branch_mismatch;

  assign result_mismatch = rq_IntWriteEn && (sALUResult != rq_IntResult);
  assign branch_mismatch = isBranch       && (sBranchTaken != rq_PCSrc);

  always_comb begin
    if (!rq_InstrValid || rq_SkipVerify) begin
      SecFaultMatch    = 1'b1;
      SecFaultMismatch = 1'b0;
      SecFaultPC       = '0;
    end else if (result_mismatch || branch_mismatch) begin
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
