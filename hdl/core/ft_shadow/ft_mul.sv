///////////////////////////////////////////
// ft_mul.sv
//
// Written: Siddharth Rau (sidrau2@illinois.edu)
//
// Purpose: Fault-tolerant wrapper for Wally's registered integer multiplier.
//
// Usage:
// Instantiated by the MDU. Preserves the multiplier's E-input/M-output
// boundary and returns the half of the product the instruction asks for, with
// recovery status.
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
  // Preserve Wally's E-input/M-output boundary while adding replay control.
  input  logic                clk, reset,
  input  logic                StallM, FlushM,
  input  logic                HoldE,                  // Execute's operands cannot be used this cycle (ECC stall)
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
  // saved_* is the architectural transaction; mul_* selects current E inputs
  // or that saved transaction during an M-stage replay.
  logic [P.XLEN-1:0] saved_a, saved_b, mul_a, mul_b;
  logic [2:0] saved_funct3, mul_funct3;
  logic mul_active_m, mismatch, replay_load;
  logic [P.XLEN*2-1:0] prod_raw, prod;
  logic [P.XLEN*2-1:0] prod_q;                       // the product as captured in SUM
  logic internal_stall_m;
  // One evaluation of the product in Memory.  As in ft_alu, nothing crosses from
  // the adder to the rest of the core inside one cycle:
  //   SUM      the multiplier adds its partial products; the product is captured.
  //   COMPARE  the captured product is checked and the controller acts.
  //   REPLAY   after a failed check: the multiplier is given the saved operands
  //   LOAD     ... and the partial-product registers reload; then SUM again.
  //   DONE     the captured product is presented and the stall released.
  typedef enum logic [2:0] {SUM, COMPARE, REPLAY, LOAD, DONE} phase_t;
  phase_t phase;
  logic check, retry, replay_sel;
  logic [P.XLEN-1:0] e_a_q, e_b_q;                   // Execute's operands and multiply type, registered
  logic [2:0]        e_funct3_q;
  logic [1:0]        e_cnt;                          // full cycles the multiplier has had on this instruction (saturates at 2)

  // Save the transaction that produced the current partial product. A retry
  // must replay these exact operands while the architectural stages are held.
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
    if (reset | ~StallM) phase <= SUM;
    else case (phase)
      SUM:     phase <= COMPARE;
      COMPARE: phase <= retry ? REPLAY : DONE;
      REPLAY:  phase <= LOAD;
      LOAD:    phase <= SUM;
      DONE:    phase <= DONE;
      default: phase <= SUM;
    endcase

  // After a failed check, load the saved transaction into the internal PP registers
  // even though the architectural pipeline is globally held.  The multiplier
  // takes two cycles (mul.sv), so the saved operands are presented for two and
  // the registers load in the second.
  assign replay_sel  = (phase == REPLAY) | (phase == LOAD);
  assign replay_load = (phase == LOAD);
  assign internal_stall_m = StallM & ~replay_load;
  // A multiply arriving in Execute takes three cycles to reach the
  // partial-product registers: its operands are registered here (so the
  // multiplier starts at a register and not behind the forwarding muxes), the
  // half products are registered in mul.sv, and their sum loads when the
  // pipeline advances.  e_cnt counts the cycles the chain has had since the
  // instruction arrived; an ECC stall dirties the operand register and starts
  // the count again, and a replay borrows the multiplier, costing one cycle.
  always_ff @(posedge clk) begin
    e_a_q      <= ForwardedSrcAE;
    e_b_q      <= ForwardedSrcBE;
    e_funct3_q <= Funct3E;
  end
  assign mul_a = replay_sel ? saved_a : e_a_q;
  assign mul_b = replay_sel ? saved_b : e_b_q;
  assign mul_funct3 = replay_sel ? saved_funct3 : e_funct3_q;
  always_ff @(posedge clk)
    if (reset | ~StallM | HoldE) e_cnt <= 2'd0;
    else if (replay_sel)         e_cnt <= 2'd1;
    else if (e_cnt != 2'd2)      e_cnt <= e_cnt + 2'd1;
  // Permit the internal PP registers to load the saved retry transaction even
  // when the architectural hazard unit is asserting StallM.
  mul #(P.XLEN) primary(.clk, .reset, .StallM(internal_stall_m), .FlushM(FlushM & ~StallM),
    .ForwardedSrcAE(mul_a), .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .ProdM(prod_raw));
  // Fault-injection endpoint: corrupt the completed product before the check
  // and the architectural product output.
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
  logic [3:0] res_a_bits, res_b_bits, res_a, res_b, res_ab, res_ab_q, res_prod, res_expected;

  assign signed_a = (saved_funct3 == 3'b001) | (saved_funct3 == 3'b010);
  assign signed_b = (saved_funct3 == 3'b001);
  residue15 #(P.XLEN) ares(saved_a, res_a_bits);
  residue15 #(P.XLEN) bres(saved_b, res_b_bits);
  residue15 #(5) aval(5'(res_a_bits) + ((signed_a & saved_a[P.XLEN-1]) ? 5'd14 : 5'd0), res_a);
  residue15 #(5) bval(5'(res_b_bits) + ((signed_b & saved_b[P.XLEN-1]) ? 5'd14 : 5'd0), res_b);
  residue15 #(8) abres(8'(res_a) * 8'(res_b), res_ab);

  // No reset: nothing reads these before SUM has written them.
  always_ff @(posedge clk)
    if (phase == SUM) begin
      prod_q   <= prod;
      res_ab_q <= res_ab;
    end
  residue15 #(P.XLEN*2) prodres(prod_q, res_prod);
  residue15 #(5) expres(5'(res_ab_q) + {4'b0, signed_a & prod_q[P.XLEN*2-1]}, res_expected);
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

  // The pipeline waits for a multiply's evaluation in Memory to finish, and for
  // the multiplier to have had its cycles with a multiply in Execute.
  assign stall_req = (mul_active_m & (phase != DONE)) | (MulActiveE & (e_cnt != 2'd2));
  // The product reads as zero until the evaluation is DONE, and stays zero if it
  // ended unresolved.  Both conditions, the half select, and the product are registers.
  assign ProdM = ((phase != DONE) | unresolved) ? '0 :
                 (saved_funct3[1:0] == 2'b00) ? prod_q[P.XLEN-1:0] : prod_q[P.XLEN*2-1:P.XLEN];
endmodule
