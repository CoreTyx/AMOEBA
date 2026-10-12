///////////////////////////////////////////
// ft_mul.sv
//
// Written: Siddharth Rau (sidrau2@illinois.edu)
//
// Purpose: Fault-tolerant wrapper for Wally's registered integer multiplier.
//
// Usage:
// Instantiated by the MDU. Preserves the multiplier's E-input/M-output
// boundary and returns the full double-width product with recovery status.
//
// Functionality:
// Duplicates the multiplier, compares completed M-stage products, and saves
// operands and signedness controls for replay while the pipeline is held.
// Transient mismatches retry; persistent mismatches report an unresolved
// fault and mask the product. This wrapper does not isolate a replica.
///////////////////////////////////////////

module ft_mul import cvw::*; #(
  parameter cvw_t P,
  parameter int TE_THRESHOLD = 3
) (
  // Preserve Wally's E-input/M-output boundary while adding replay control.
  input  logic                clk, reset,
  input  logic                StallM, FlushM,
  input  logic [P.XLEN-1:0]   ForwardedSrcAE, ForwardedSrcBE,
  input  logic [2:0]          Funct3E,
  input  logic                MulActiveE,
  // Shared runtime enable; bit and kind are selected inside each injector.
  input  logic                fi_enable,
  output logic [P.XLEN*2-1:0] ProdM,
  output logic                stall_req, unresolved, pe_primary, pe_shadow
);
  // saved_* is the architectural transaction; mul_* selects current E inputs
  // or that saved transaction during an M-stage replay.
  logic [P.XLEN-1:0] saved_a, saved_b, mul_a, mul_b;
  logic [2:0] saved_funct3, mul_funct3;
  logic mul_active_m, mismatch, replay_load;
  logic isolated, use_shadow;
  logic [P.XLEN*2-1:0] primary_prod_raw, shadow_prod_raw;
  logic [P.XLEN*2-1:0] primary_prod, shadow_prod;
  logic [P.XLEN*2-1:0] primary_q, shadow_q;          // the products as captured in SUM
  logic internal_stall_m;
  // One evaluation of the product in Memory.  As in ft_alu, nothing crosses from
  // the adder to the rest of the core inside one cycle:
  //   SUM      both replicas add their partial products; the products are captured.
  //   COMPARE  the captured products are compared and the controller acts.
  //   REPLAY   after a mismatch: the partial-product registers reload from the
  //            saved operands, then SUM again.
  //   DONE     the captured product is presented and the stall released.
  typedef enum logic [1:0] {SUM, COMPARE, REPLAY, DONE} phase_t;
  phase_t phase;
  logic check, retry;

  // Save the transaction that produced the current partial product. A retry
  // must replay these exact operands while the architectural stages are held.
  always_ff @(posedge clk) begin
    if (reset | (FlushM & ~StallM)) begin
      saved_a <= '0;
      saved_b <= '0;
      saved_funct3 <= '0;
    end else if (MulActiveE & ~StallM) begin
      saved_a <= ForwardedSrcAE;
      saved_b <= ForwardedSrcBE;
      saved_funct3 <= Funct3E;
    end
  end
  flopenrc #(1) MulActiveMReg(clk, reset, FlushM, ~StallM, MulActiveE, mul_active_m);

  // Memory takes its next instruction when it is not stalled, and that starts a
  // new evaluation.  (A flush that Memory accepts is such an edge too.)
  assign check = (phase == COMPARE);
  always_ff @(posedge clk)
    if (reset | ~StallM) phase <= SUM;
    else case (phase)
      SUM:     phase <= COMPARE;
      COMPARE: phase <= retry ? REPLAY : DONE;
      REPLAY:  phase <= SUM;
      DONE:    phase <= DONE;
    endcase

  // The original multiplier is registered; the completed products are captured
  // and compared in M.  No reset: nothing reads them before SUM has written them.
  always_ff @(posedge clk)
    if (phase == SUM) begin
      primary_q <= primary_prod;
      shadow_q  <= shadow_prod;
    end
  assign mismatch = mul_active_m & ~isolated & (primary_q != shadow_q);
  // After a mismatch, load the saved transaction into the internal PP registers
  // even though the architectural pipeline is globally held.
  assign replay_load = (phase == REPLAY);
  assign internal_stall_m = StallM & ~replay_load;
  assign mul_a = replay_load ? saved_a : ForwardedSrcAE;
  assign mul_b = replay_load ? saved_b : ForwardedSrcBE;
  assign mul_funct3 = replay_load ? saved_funct3 : Funct3E;
  // Permit the internal PP registers to load the saved retry transaction even
  // when the architectural hazard unit is asserting StallM.
  mul #(P.XLEN) primary(.clk, .reset, .StallM(internal_stall_m), .FlushM(FlushM & ~StallM),
    .ForwardedSrcAE(mul_a), .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .ProdM(primary_prod_raw));
  mul #(P.XLEN) shadow(.clk, .reset, .StallM(internal_stall_m), .FlushM(FlushM & ~StallM),
    .ForwardedSrcAE(mul_a), .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .ProdM(shadow_prod_raw));
  // Fault-injection endpoints: corrupt completed replica products before
  // the mismatch checker and the selected architectural product output.
  ft_fault_inject #(.WIDTH(P.XLEN*2), .SEED(16'hA081)) primary_fi(
    .clk, .reset, .fi_enable, .data_i(primary_prod_raw), .data_o(primary_prod));
  ft_fault_inject #(.WIDTH(P.XLEN*2), .SEED(16'hA091)) shadow_fi(
    .clk, .reset, .fi_enable, .data_i(shadow_prod_raw), .data_o(shadow_prod));

  // MUL uses DMR/retry only in this implementation.  A persistent mismatch
  // is unresolved; do not apply an invalid signedness-agnostic recompute rule.
  // A trap may request FlushM while unrelated backpressure holds M. Accept
  // that flush only when the architectural M-stage register accepts it too.
  // MUL retries without recomputation or first-mismatch diagnostic snapshots.
  /* verilator lint_off PINCONNECTEMPTY */
  ft_shadow_ctrl #(.TE_THRESHOLD(TE_THRESHOLD)) ctrl(
    .clk, .reset, .flush(FlushM & ~StallM), .valid(mul_active_m), .check,
    .advance(~StallM & (phase == DONE)), .mismatch,
    .recompute_supported(1'b0), .recompute_primary_ok(1'b0), .recompute_shadow_ok(1'b0),
    .recompute_mode(), .capture_normal(), .stall_req(retry), .unresolved, .isolated, .use_shadow,
    .pe_primary, .pe_shadow);
  /* verilator lint_on PINCONNECTEMPTY */

  // The pipeline waits for a multiply's evaluation to finish.
  assign stall_req = mul_active_m & (phase != DONE);
  // The product reads as zero until the evaluation is DONE, and stays zero if it
  // ended unresolved.  Both conditions, and the product itself, are registers.
  assign ProdM = ((phase != DONE) | unresolved) ? '0 : (use_shadow ? shadow_q : primary_q);
endmodule
