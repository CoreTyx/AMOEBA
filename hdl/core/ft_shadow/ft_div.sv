///////////////////////////////////////////
// ft_div.sv
//
// Written: Siddharth Rau (sidrau2@illinois.edu)
//
// Purpose: Fault-tolerant wrapper for Wally's iterative integer divider.
//
// Usage:
// Instantiated by the MDU when integer division uses the dedicated divider.
// Accepts an E-stage division transaction and registers the checked result
// (quotient or remainder, as the instruction asks) at E-to-M acceptance.
//
// Functionality:
// One divider, checked with residues modulo 15 (residue15.sv).  On the
// magnitudes the divider iterates on, |X| = |Q|*|D| + |R| must hold mod 15
// and |R| < |D| must hold outright; the residue identity alone would accept a
// wrong quotient bit, which moves a multiple of |D| between Q and R.  The
// signed result is then checked against the magnitude it was made from.
// Saves launch operands and controls, restarts the divider on a failed check,
// and holds the architectural pipeline during retry. Persistent failures
// report an unresolved E-stage fault for the MDU to register into M.
///////////////////////////////////////////

module ft_div import cvw::*; #(
  parameter cvw_t P,
  parameter int TE_THRESHOLD = 3 // must be >= 1
) (
  input  logic              clk, reset,
  input  logic              StallM, FlushE, FlushM,
  input  logic              IntDivE, DivSignedE, RemE, W64E,
  input  logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE,
  // Shared runtime enable and generator; bit and kind are selected inside the injector.
  input  logic              fi_enable,
  input  logic [15:0]       fi_lfsr,
  input  logic [FI_COUNT_BITS-1:0] fi_count,
  output logic              DivBusyE,
  output logic [P.XLEN-1:0] DivResultM,
  output logic              stall_req, unresolved,
  output logic              fault_detect              // a check found the result wrong
);

  localparam int COUNT_W = (TE_THRESHOLD == 1) ? 1 : $clog2(TE_THRESHOLD);
  localparam logic [COUNT_W-1:0] RETRY_LIMIT = COUNT_W'(TE_THRESHOLD-1);
  typedef enum logic [1:0] {NORMAL, RETRY, UNRESOLVED} state_t;

  state_t state;
  logic [COUNT_W-1:0] mismatch_count;
  logic div_done, div_first;
  logic result_valid, mismatch;
  logic retry_reset, retry_again, internal_stall_m;
  logic saved_valid, saved_signed, saved_rem, saved_w64;
  logic [P.XLEN-1:0] saved_a, saved_b, operand_a, operand_b;
  logic operand_signed, operand_rem, operand_w64;
  logic [P.XLEN-1:0] result_raw, result;
  logic [P.XLEN-1:0] div_xq, div_w, div_dabsb, div_mag;
  logic div0, div_neg, div_rem;
  // The completed result and what the check needs from the divider, captured.
  // As in ft_alu and ft_mul, the check works on these registers and the stall
  // and the outputs come from registers, so nothing crosses from the divider
  // to the rest of the core inside one cycle:
  //   WAIT     the divider is running (or idle).  The cycle it is done, its
  //            result is captured.
  //   COMPARE  the captured result is checked and the retry controller acts.
  //   DONE     the captured result is presented and the pipeline released.
  logic [P.XLEN-1:0] result_q;
  typedef enum logic [1:0] {WAIT, COMPARE, DONE} phase_t;
  phase_t phase;
  logic check;

  // A retry owns the divider FSM while the architectural pipeline remains
  // frozen.  Remove the external M-stage stall only for this private FSM so
  // the held E-stage divide can relaunch and make forward progress.
  // Hold DONE on the final retry edge. Otherwise returning to NORMAL would
  // relaunch the same divide instead of releasing its completed result.
  // Threshold one bypasses RETRY; its zero retry limit is intentional.
  /* verilator lint_off UNSIGNED */
  // In RETRY the divider runs free of the pipeline's stall until it is done,
  // then holds its result for the check; a failed check restarts it through
  // retry_reset.
  assign internal_stall_m = (state == RETRY) ? result_valid : StallM;
  /* verilator lint_on UNSIGNED */

  // Forwarding sources can disappear while division holds E and older stages
  // drain. Capture the launch transaction, including its arithmetic controls,
  // and use it for every private restart.  The operands need no reset: they
  // are read only while saved_valid is set.
  assign operand_a = saved_valid ? saved_a : ForwardedSrcAE;
  assign operand_b = saved_valid ? saved_b : ForwardedSrcBE;
  assign operand_signed = saved_valid ? saved_signed : DivSignedE;
  assign operand_rem = saved_valid ? saved_rem : RemE;
  assign operand_w64 = saved_valid ? saved_w64 : W64E;
  always_ff @(posedge clk)
    if (reset | FlushE)                         saved_valid <= 1'b0;
    else if (!saved_valid & IntDivE & ~StallM)  saved_valid <= 1'b1;
    else if ((phase == DONE) & ~StallM)         saved_valid <= 1'b0;
  always_ff @(posedge clk)
    if (!saved_valid & IntDivE & ~StallM) begin
      saved_a <= ForwardedSrcAE;
      saved_b <= ForwardedSrcBE;
      saved_signed <= DivSignedE;
      saved_rem <= RemE;
      saved_w64 <= W64E;
    end

  // Reset is asserted for the edge that records a failed completed attempt.
  // The next cycle sees the FSM idle and reissues the unchanged IntDivE.
  // Threshold one bypasses RETRY; its zero retry limit is intentional.
  /* verilator lint_off UNSIGNED */
  assign retry_again = (state == RETRY) & check & mismatch &
                       (mismatch_count < RETRY_LIMIT);
  assign retry_reset = ((state == NORMAL) & check & mismatch & (TE_THRESHOLD != 1)) |
                       retry_again;
  /* verilator lint_on UNSIGNED */

  div #(P) primary(
    .clk, .reset, .StallM(internal_stall_m), .FlushE(FlushE | retry_reset),
    .IntDivE, .DivSignedE(operand_signed), .RemE(operand_rem), .W64E(operand_w64),
    .ForwardedSrcAE(operand_a), .ForwardedSrcBE(operand_b),
    .DivBusyE, .DivDoneE(div_done), .ResultM(result_raw),
    .DivFirstE(div_first), .XQ0(div_xq), .W0(div_w), .DAbsBOut(div_dabsb), .MagM(div_mag),
    .Div0M(div0), .NegM(div_neg), .RemM(div_rem));

  // The fault is placed on the result ahead of its capture, where the check
  // sees it; operands, controls and progress state are out of scope.
  ft_fault_inject #(.WIDTH(P.XLEN), .PHASE(9'h15E)) result_fi(
    .reset, .lfsr(fi_lfsr), .count(fi_count), .fi_enable, .data_i(result_raw), .data_o(result));

  // Check only after the divider FSM has completed this held instruction;
  // IDLE is also not busy, but does not contain a valid result.
  assign result_valid = IntDivE & div_done;
  assign check = (phase == COMPARE);
  always_ff @(posedge clk)
    if (reset | FlushE) phase <= WAIT;
    else case (phase)
      WAIT:    if (result_valid) phase <= COMPARE;
      COMPARE: phase <= retry_reset ? WAIT : DONE;   // a retry restarts the divider
      DONE:    if (~StallM) phase <= WAIT;           // the instruction leaves Execute
      default: phase <= WAIT;
    endcase

  /////////////////////////////////////////////////////////////////////////////////////////////
  // Residue check (mod 15)
  //
  // Two residue trees, each read at three points of a divide.  On the first iteration cycle
  // they give |X| (XQ) and -|D| (DAbsB, constant from then on); the cycle the divide is done,
  // |Q| (XQ) and |R| (W); in COMPARE, tree A gives the captured result.  2^64 is congruent to
  // 1 (mod 15), so the stored -|D| (2^64 - |D|) has residue 1 - |D|, and so has a negated
  // nonzero result 1 - its magnitude's.  A W-type divide starts from X shifted left 32 bits,
  // which leaves its residue unchanged, so the same identity holds.
  /////////////////////////////////////////////////////////////////////////////////////////////
  logic [3:0] res_a, res_b;                        // tree outputs
  logic [3:0] res_x_q, res_nd_q, res_q_q, res_r_q; // |X|, -|D|, |Q|, |R|
  logic       in_range, in_range_q;                // |R| < |D|
  logic       mag_zero_q;                          // the magnitude the result was made from is 0
  logic [3:0] res_d, res_id, res_mag, res_mag_neg, res_expected;
  logic [P.XLEN:0] r_minus_d;

  residue15 #(P.XLEN) treea((phase == COMPARE) ? result_q : div_xq, res_a);
  residue15 #(P.XLEN) treeb(div_done ? div_w : div_dabsb, res_b);
  // W + (2^64 - |D|) carries out of bit 63 exactly when W >= |D|, as in divstep
  assign r_minus_d = {1'b0, div_w} + {1'b0, div_dabsb};
  assign in_range  = ~r_minus_d[P.XLEN];

  // No reset: nothing reads these before a divide has written them.
  always_ff @(posedge clk)
    if (div_first) begin
      res_x_q  <= res_a;
      res_nd_q <= res_b;
    end
  always_ff @(posedge clk)
    if ((phase == WAIT) & result_valid) begin
      result_q   <= result;
      res_q_q    <= res_a;
      res_r_q    <= res_b;
      in_range_q <= in_range;
      mag_zero_q <= (div_mag == '0);
    end

  // |X| = |Q|*|D| + |R|, with |D| = 1 - (-|D|) and 16 = 1 (mod 15); skipped on a divide by
  // zero, which does not iterate
  residue15 #(5) dres(5'd16 - 5'(res_nd_q), res_d);
  residue15 #(8) idres(8'(res_q_q) * 8'(res_d) + 8'(res_r_q), res_id);
  // The result: the magnitude, its negation, or for a divide by zero all 1s (residue 0) or X
  assign res_mag = div_rem ? res_r_q : res_q_q;
  residue15 #(5) negres(5'd16 - 5'(res_mag), res_mag_neg);
  always_comb
    if (div0)                       res_expected = div_rem ? res_q_q : 4'd0;
    else if (div_neg & ~mag_zero_q) res_expected = res_mag_neg;
    else                            res_expected = res_mag;
  assign mismatch = (res_a != res_expected) | (~div0 & (~in_range_q | (res_id != res_x_q)));
  assign fault_detect = check & mismatch;

  // A completed divide holds the full pipeline until its check is DONE, and a
  // retry holds it while the divider runs again.  A final failed
  // attempt holds an E-stage fault until E can advance; the MDU registers it
  // alongside the instruction. No unchecked result
  // is allowed to enter the normal MDU result mux.
  assign stall_req = (result_valid & (phase != DONE)) | (state == RETRY);
  assign unresolved = (state == UNRESOLVED);

  always_ff @(posedge clk) begin
    if (reset | FlushE) begin
      state          <= NORMAL;
      mismatch_count <= '0;
    end else begin
      case (state)
        NORMAL: if (check) begin
          mismatch_count <= '0;
          if (mismatch) begin
            if (TE_THRESHOLD == 1) state <= UNRESOLVED;
            else begin
              state          <= RETRY;
              mismatch_count <= COUNT_W'(1);
            end
          end
        end
        // Threshold one bypasses RETRY; its zero retry limit is intentional.
        /* verilator lint_off UNSIGNED */
        RETRY: begin
          if (check) begin
            if (!mismatch) begin
              state          <= NORMAL;
              mismatch_count <= '0;
            end else if (mismatch_count >= RETRY_LIMIT) begin
              state <= UNRESOLVED;
            end else begin
              mismatch_count <= mismatch_count + COUNT_W'(1);
            end
          end
        end
        /* verilator lint_on UNSIGNED */
        UNRESOLVED: if (!StallM) state <= NORMAL;
        default:    state <= NORMAL;
      endcase
    end
  end

  // The checker validated the captured E-stage result. Pass that exact value on
  // when the instruction advances into M; the live injector may change at any time
  // after the capture. Holding this register also
  // protects an older M-stage divide while a younger divide retries in E.
  flopenrc #(P.XLEN) resultreg(clk, reset, FlushM, ~StallM,
    ((phase == DONE) & ~unresolved) ? result_q : '0, DivResultM);
endmodule
