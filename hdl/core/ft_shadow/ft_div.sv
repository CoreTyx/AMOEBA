// Fault-tolerant wrapper for Wally's iterative integer divider.
//
// Unlike MUL, division keeps its transaction in E while div.sv iterates.  A
// result mismatch is therefore handled by resetting both divider FSMs and
// restarting the still-held E-stage instruction.  The wrapper protects both
// quotient and remainder because either may be selected by Funct3M.
module ft_div import cvw::*; #(
  parameter cvw_t P,
  parameter int TE_THRESHOLD = 3 // must be >= 1
) (
  input  logic              clk, reset,
  input  logic              StallM, FlushE, FlushM,
  input  logic              IntDivE, DivSignedE, W64E,
  input  logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE,
  // Shared runtime enable; bit and kind are selected inside each injector.
  input  logic fi_enable,
  output logic              DivBusyE,
  output logic [P.XLEN-1:0] QuotM, RemM,
  output logic              stall_req, unresolved, pe_primary, pe_shadow
);

  localparam int COUNT_W = (TE_THRESHOLD == 1) ? 1 : $clog2(TE_THRESHOLD);
  localparam logic [COUNT_W-1:0] RETRY_LIMIT = COUNT_W'(TE_THRESHOLD-1);
  typedef enum logic [1:0] {NORMAL, RETRY, UNRESOLVED} state_t;

  state_t state;
  logic [COUNT_W-1:0] mismatch_count;
  logic primary_busy, shadow_busy, primary_done, shadow_done;
  logic result_valid, mismatch;
  logic retry_reset, retry_again, internal_stall_m;
  logic saved_valid, saved_signed, saved_w64;
  logic [P.XLEN-1:0] saved_a, saved_b, operand_a, operand_b;
  logic operand_signed, operand_w64;
  logic [P.XLEN-1:0] primary_quot_raw, primary_rem_raw;
  logic [P.XLEN-1:0] shadow_quot_raw, shadow_rem_raw;
  logic [P.XLEN-1:0] primary_quot, primary_rem, shadow_quot, shadow_rem;

  // A retry owns both divider FSMs while the architectural pipeline remains
  // frozen.  Remove the external M-stage stall only for these private FSMs so
  // the held E-stage divide can relaunch and make forward progress.
  // Hold DONE on the final retry edge. Otherwise returning to NORMAL would
  // relaunch the same divide instead of releasing its completed result.
  assign internal_stall_m = (state == RETRY) ?
      (result_valid & (~mismatch | (mismatch_count >= RETRY_LIMIT))) : StallM;

  // Forwarding sources can disappear while division holds E and older stages
  // drain. Capture the launch transaction, including its arithmetic controls,
  // and use it for every private restart.
  assign operand_a = saved_valid ? saved_a : ForwardedSrcAE;
  assign operand_b = saved_valid ? saved_b : ForwardedSrcBE;
  assign operand_signed = saved_valid ? saved_signed : DivSignedE;
  assign operand_w64 = saved_valid ? saved_w64 : W64E;
  always_ff @(posedge clk) begin
    if (reset | FlushE) begin
      saved_valid <= 1'b0;
      saved_a <= '0;
      saved_b <= '0;
      saved_signed <= 1'b0;
      saved_w64 <= 1'b0;
    end else if (!saved_valid & IntDivE & ~StallM) begin
      saved_valid <= 1'b1;
      saved_a <= ForwardedSrcAE;
      saved_b <= ForwardedSrcBE;
      saved_signed <= DivSignedE;
      saved_w64 <= W64E;
    end else if (result_valid & ~stall_req & ~StallM) begin
      saved_valid <= 1'b0;
    end
  end

  // Reset is asserted for the edge that records a failed completed attempt.
  // The next cycle sees both FSMs idle and reissues the unchanged IntDivE.
  assign retry_again = (state == RETRY) & result_valid & mismatch &
                       (mismatch_count < RETRY_LIMIT);
  assign retry_reset = ((state == NORMAL) & mismatch & (TE_THRESHOLD != 1)) |
                       retry_again;

  div #(P) primary(
    .clk, .reset, .StallM(internal_stall_m), .FlushE(FlushE | retry_reset),
    .IntDivE, .DivSignedE(operand_signed), .W64E(operand_w64),
    .ForwardedSrcAE(operand_a), .ForwardedSrcBE(operand_b),
    .DivBusyE(primary_busy), .DivDoneE(primary_done),
    .QuotM(primary_quot_raw), .RemM(primary_rem_raw));
  div #(P) shadow(
    .clk, .reset, .StallM(internal_stall_m), .FlushE(FlushE | retry_reset),
    .IntDivE, .DivSignedE(operand_signed), .W64E(operand_w64),
    .ForwardedSrcAE(operand_a), .ForwardedSrcBE(operand_b),
    .DivBusyE(shadow_busy), .DivDoneE(shadow_done),
    .QuotM(shadow_quot_raw), .RemM(shadow_rem_raw));

  // Faults are placed after independent replicas; shared operands, controls,
  // progress state, and the common divider algorithm remain out of scope.
  ft_fault_inject #(.WIDTH(P.XLEN), .SEED(16'hA0A1)) primary_quot_fi(
    .clk, .reset, .fi_enable, .data_i(primary_quot_raw), .data_o(primary_quot));
  ft_fault_inject #(.WIDTH(P.XLEN), .SEED(16'hA0B1)) shadow_quot_fi(
    .clk, .reset, .fi_enable, .data_i(shadow_quot_raw), .data_o(shadow_quot));
  ft_fault_inject #(.WIDTH(P.XLEN), .SEED(16'hA0C1)) primary_rem_fi(
    .clk, .reset, .fi_enable, .data_i(primary_rem_raw), .data_o(primary_rem));
  ft_fault_inject #(.WIDTH(P.XLEN), .SEED(16'hA0D1)) shadow_rem_fi(
    .clk, .reset, .fi_enable, .data_i(shadow_rem_raw), .data_o(shadow_rem));

  // Compare only after both divider FSMs have completed this held instruction;
  // IDLE is also not busy, but does not contain a valid result.
  assign result_valid = IntDivE & primary_done & shadow_done;
  assign mismatch = result_valid & ((primary_quot != shadow_quot) |
                                    (primary_rem  != shadow_rem));
  assign DivBusyE = primary_busy | shadow_busy;

  // Initial and retry mismatches hold the full pipeline.  A final failed
  // attempt holds an E-stage fault until E can advance; the MDU registers it
  // alongside the instruction. No guessed replica result
  // is allowed to enter the normal MDU result mux.
  assign stall_req = ((state == NORMAL) & mismatch) | (state == RETRY);
  assign unresolved = (state == UNRESOLVED);
  assign pe_primary = 1'b0;
  assign pe_shadow = 1'b0;

  always_ff @(posedge clk) begin
    if (reset | FlushE) begin
      state          <= NORMAL;
      mismatch_count <= '0;
    end else begin
      case (state)
        NORMAL: begin
          mismatch_count <= '0;
          if (mismatch) begin
            if (TE_THRESHOLD == 1) state <= UNRESOLVED;
            else begin
              state          <= RETRY;
              mismatch_count <= COUNT_W'(1);
            end
          end
        end
        RETRY: begin
          if (result_valid) begin
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
        UNRESOLVED: if (!StallM) state <= NORMAL;
        default:    state <= NORMAL;
      endcase
    end
  end

  // The checker validates E-stage results. Capture that exact pair when the
  // instruction advances into M; live injectors may change on the next cycle,
  // when IntDivE no longer enables the checker. Holding these registers also
  // protects an older M-stage divide while a younger divide retries in E.
  flopenrc #(P.XLEN) quotreg(clk, reset, FlushM, ~StallM,
    (result_valid & ~stall_req & ~unresolved) ? primary_quot : '0, QuotM);
  flopenrc #(P.XLEN) remreg(clk, reset, FlushM, ~StallM,
    (result_valid & ~stall_req & ~unresolved) ? primary_rem : '0, RemM);
endmodule
