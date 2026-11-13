///////////////////////////////////////////
// ft_mul.sv
//
// Written: Siddharth Rau (sidrau2@illinois.edu)
//
// Purpose: Fault-tolerant wrapper for the sequential integer multiplier.
//
// Usage:
// Instantiated by the MDU. Takes a multiply's operands as it leaves Execute,
// runs the multiplier while holding the pipeline with the multiply in Memory,
// and returns the half of the product the instruction asks for, with recovery
// status.
//
// Functionality:
// One multiplier, checked with residues modulo 15 (residue15.sv): the
// completed M-stage product must be congruent to the product of its operands'
// residues.  Saves operands and signedness controls for replay while the
// pipeline is held.  Transient failures retry; persistent failures report an
// unresolved fault and mask the product.
///////////////////////////////////////////

module ft_mul import cvw::*; #(
  parameter cvw_t P,
  parameter int TE_THRESHOLD = 3
) (
  input  logic                clk, reset,
  input  logic                StallM, FlushM,
  input  logic [P.XLEN-1:0]   ForwardedSrcAE, ForwardedSrcBE,
  input  logic [2:0]          Funct3E,
  input  logic                MulActiveE,
  // Shared runtime enable and generator; bit and kind are selected inside the injector.
  input  logic                fi_enable,
  input  logic [15:0]         fi_lfsr,
  input  logic [FI_COUNT_BITS-1:0] fi_count,
  output logic [P.XLEN-1:0]   ProdM,                  // low half for mul, high half for mulh/mulhsu/mulhu
  output logic                stall_req, unresolved,
  output logic                fault_detect            // a check found the product wrong
);
  // saved_* is the architectural transaction: loaded as the multiply leaves
  // Execute and held, while the pipeline waits, for the multiplier and for
  // every replay.
  logic [P.XLEN-1:0]   saved_a, saved_b;
  logic [2:0]          saved_funct3;
  logic                mul_active_m, mismatch;
  logic                mul_start, mul_done, capture;
  logic [P.XLEN*2-1:0] prod_raw, prod;               // the multiplier's product register; with the fault applied
  // One evaluation of the product in Memory.  Nothing crosses from the adder to
  // the rest of the core inside one cycle:
  //   RUN      the multiplier loads and steps (XLEN+1 cycles).  The cycle after its last
  //            step, the product register is rewritten through the fault
  //            injector -- the product as captured -- and the expected residue
  //            is registered.
  //   COMPARE  the captured product is checked and the controller acts.  A
  //            failed check restarts the multiplier on the saved operands and
  //            goes back to RUN.
  //   DONE     the captured product is presented and the stall released.
  typedef enum logic [1:0] {RUN, COMPARE, DONE} phase_t;
  phase_t phase;
  logic check, retry;

  // The operands need no reset: they are read only for a multiply in Memory.
  always_ff @(posedge clk)
    if (reset | (FlushM & ~StallM)) saved_funct3 <= '0;
    else if (MulActiveE & ~StallM)  saved_funct3 <= Funct3E;
  always_ff @(posedge clk)
    if (MulActiveE & ~StallM) begin
      saved_a <= ForwardedSrcAE;
      saved_b <= ForwardedSrcBE;
    end
  flopenrc #(1) MulActiveMReg(clk, reset, FlushM, ~StallM, MulActiveE, mul_active_m);

  // Memory takes its next instruction when it is not stalled, and that starts a
  // new evaluation.  (A flush that Memory accepts is such an edge too.)
  assign check = (phase == COMPARE);
  always_ff @(posedge clk)
    if (reset | ~StallM) phase <= RUN;
    else case (phase)
      RUN:     if (mul_done) phase <= COMPARE;
      COMPARE: phase <= retry ? RUN : DONE;
      DONE:    phase <= DONE;
      default: phase <= RUN;
    endcase

  // The multiplier starts on the edge a multiply enters Memory, which is the
  // edge saved_* load, and again on the edge a failed check sends it back.
  assign mul_start = (MulActiveE & ~StallM) | (check & retry);
  assign capture   = (phase == RUN) & mul_done;
  mul #(P.XLEN) primary(.clk, .reset, .Start(mul_start), .A(saved_a), .B(saved_b), .Funct3(saved_funct3),
    .Load(capture), .PIn(prod), .Done(mul_done), .Prod(prod_raw));
  // Fault-injection endpoint: the completed product passes through it once, into
  // the product register, before the check reads it.
  ft_fault_inject #(.WIDTH(P.XLEN*2), .PHASE(9'h17E)) result_fi(
    .reset, .lfsr(fi_lfsr), .count(fi_count), .fi_enable, .data_i(prod_raw), .data_o(prod));

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Residue check (mod 15)
  //
  // The expected residue comes from the saved operands, which are the ones the multiplier was
  // given, so a fault in the operand registers in front of it is caught too.  2^64 and 2^128
  // are congruent to 1 (mod 15): a signed operand's value is its bits' residue minus its sign
  // bit, and a negative double-width product reads its value plus 1.  mulh takes both
  // operands as signed, mulhsu only A; mul's low half is the same whatever the signedness, and
  // mul.sv forms it unsigned.
  /////////////////////////////////////////////////////////////////////////////////////////////
  logic       signed_a, signed_b;
  logic [3:0] res_a_bits, res_b_bits, res_a, res_b, res_a_q, res_b_q, res_ab, res_ab_q, res_prod, res_expected;

  assign signed_a = (saved_funct3 == 3'b001) | (saved_funct3 == 3'b010);
  assign signed_b = (saved_funct3 == 3'b001);
  residue15 #(P.XLEN) ares(saved_a, res_a_bits);
  residue15 #(P.XLEN) bres(saved_b, res_b_bits);
  residue15 #(5) aval(5'(res_a_bits) + ((signed_a & saved_a[P.XLEN-1]) ? 5'd14 : 5'd0), res_a);
  residue15 #(5) bval(5'(res_b_bits) + ((signed_b & saved_b[P.XLEN-1]) ? 5'd14 : 5'd0), res_b);
  // The operands are steady for the whole multiply (XLEN+1 cycles), so the
  // expected residue is pipelined: the operand residues are registered every
  // cycle, and their product is captured with the result.
  // No reset: nothing reads these before the capture has written res_ab_q.
  always_ff @(posedge clk) begin
    res_a_q <= res_a;
    res_b_q <= res_b;
  end
  residue15 #(8) abres(8'(res_a_q) * 8'(res_b_q), res_ab);
  always_ff @(posedge clk)
    if (capture) res_ab_q <= res_ab;
  residue15 #(P.XLEN*2) prodres(prod_raw, res_prod);
  residue15 #(5) expres(5'(res_ab_q) + {4'b0, signed_a & prod_raw[P.XLEN*2-1]}, res_expected);
  assign mismatch = mul_active_m & (res_prod != res_expected);
  assign fault_detect = check & mismatch;

  // MUL uses retry only in this implementation; with one multiplier there is no
  // replica to isolate.  A persistent failure is unresolved.
  // A trap may request FlushM while unrelated backpressure holds M. Accept
  // that flush only when the architectural M-stage register accepts it too.
  /* verilator lint_off PINCONNECTEMPTY */
  ft_shadow_ctrl #(.TE_THRESHOLD(TE_THRESHOLD)) ctrl(
    .clk, .reset, .flush(FlushM & ~StallM), .valid(mul_active_m), .check,
    .advance(~StallM & (phase == DONE)), .mismatch,
    .recompute_supported(1'b0), .recompute_primary_ok(1'b0), .recompute_shadow_ok(1'b0),
    .recompute_mode(), .capture_normal(), .stall_req(retry), .unresolved, .isolated(), .use_shadow(),
    .pe_primary(), .pe_shadow());
  /* verilator lint_on PINCONNECTEMPTY */

  // The pipeline waits for a multiply's evaluation in Memory to finish.
  assign stall_req = mul_active_m & (phase != DONE);
  // The product reads as zero until the evaluation is DONE, and stays zero if it
  // ended unresolved.  Both conditions, the half select, and the product are registers.
  assign ProdM = ((phase != DONE) | unresolved) ? '0 :
                 (saved_funct3[1:0] == 2'b00) ? prod_raw[P.XLEN-1:0] : prod_raw[P.XLEN*2-1:P.XLEN];
endmodule
