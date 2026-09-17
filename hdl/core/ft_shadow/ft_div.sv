// Fault-tolerant wrapper for Wally's iterative integer divider.
//
// Unlike MUL, division keeps its transaction in E while div.sv iterates.  A
// result mismatch is therefore handled by resetting both divider FSMs and
// restarting the still-held E-stage instruction.  The wrapper protects both
// quotient and remainder because either may be selected by Funct3M.
module ft_div import cvw::*; #(
  parameter cvw_t P,
  parameter int TE_THRESHOLD = 3,
  parameter bit FAULT_INJECT = 1'b0
) (
  input  logic              clk, reset,
  input  logic              StallM, FlushE,
  input  logic              IntDivE, DivSignedE, W64E,
  input  logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE,
  // Test-only output injection; tied off by the production MDU.
  input  logic              fi_enable,
  input  logic [1:0]        fi_target,
  input  logic [1:0]        fi_kind,
  input  logic [$clog2(P.XLEN)-1:0] fi_bit,
  input  logic              fi_channel, // 0: quotient, 1: remainder
  output logic              DivBusyE,
  output logic [P.XLEN-1:0] QuotM, RemM,
  output logic              stall_req, unresolved, pe_primary, pe_shadow
);

  localparam int COUNT_W = (TE_THRESHOLD <= 1) ? 1 : $clog2(TE_THRESHOLD);
  localparam logic [COUNT_W-1:0] RETRY_LIMIT = COUNT_W'(TE_THRESHOLD-1);
  typedef enum logic [1:0] {NORMAL, RETRY, UNRESOLVED} state_t;

  state_t state;
  logic [COUNT_W-1:0] mismatch_count;
  logic primary_busy, shadow_busy, result_valid, mismatch;
  logic retry_reset, retry_again, internal_stall_m;
  logic [P.XLEN-1:0] primary_quot_raw, primary_rem_raw;
  logic [P.XLEN-1:0] shadow_quot_raw, shadow_rem_raw;
  logic [P.XLEN-1:0] primary_quot, primary_rem, shadow_quot, shadow_rem;

  initial begin
    if (TE_THRESHOLD < 1) $error("TE_THRESHOLD must be positive");
  end

  // A retry owns both divider FSMs while the architectural pipeline remains
  // frozen.  Remove the external M-stage stall only for these private FSMs so
  // the held E-stage divide can relaunch and make forward progress.
  assign internal_stall_m = (state == RETRY) ? 1'b0 : StallM;

  // Reset is asserted for the edge that records a failed completed attempt.
  // The next cycle sees both FSMs idle and reissues the unchanged IntDivE.
  assign retry_again = (state == RETRY) & result_valid & mismatch &
                       (mismatch_count < RETRY_LIMIT);
  assign retry_reset = ((state == NORMAL) & mismatch & (TE_THRESHOLD != 1)) |
                       retry_again;

  div #(P) primary(
    .clk, .reset, .StallM(internal_stall_m), .FlushE(FlushE | retry_reset),
    .IntDivE, .DivSignedE, .W64E, .ForwardedSrcAE, .ForwardedSrcBE,
    .DivBusyE(primary_busy), .QuotM(primary_quot_raw), .RemM(primary_rem_raw));
  div #(P) shadow(
    .clk, .reset, .StallM(internal_stall_m), .FlushE(FlushE | retry_reset),
    .IntDivE, .DivSignedE, .W64E, .ForwardedSrcAE, .ForwardedSrcBE,
    .DivBusyE(shadow_busy), .QuotM(shadow_quot_raw), .RemM(shadow_rem_raw));

  // Faults are placed after independent replicas; shared operands, controls,
  // progress state, and the common divider algorithm remain out of scope.
  ft_fault_inject #(.WIDTH(P.XLEN), .FAULT_INJECT(FAULT_INJECT)) primary_quot_fi(
    .data_i(primary_quot_raw), .fi_enable(fi_enable & ~fi_channel & fi_target[0]),
    .fi_kind, .fi_bit, .data_o(primary_quot));
  ft_fault_inject #(.WIDTH(P.XLEN), .FAULT_INJECT(FAULT_INJECT)) shadow_quot_fi(
    .data_i(shadow_quot_raw), .fi_enable(fi_enable & ~fi_channel & fi_target[1]),
    .fi_kind, .fi_bit, .data_o(shadow_quot));
  ft_fault_inject #(.WIDTH(P.XLEN), .FAULT_INJECT(FAULT_INJECT)) primary_rem_fi(
    .data_i(primary_rem_raw), .fi_enable(fi_enable & fi_channel & fi_target[0]),
    .fi_kind, .fi_bit, .data_o(primary_rem));
  ft_fault_inject #(.WIDTH(P.XLEN), .FAULT_INJECT(FAULT_INJECT)) shadow_rem_fi(
    .data_i(shadow_rem_raw), .fi_enable(fi_enable & fi_channel & fi_target[1]),
    .fi_kind, .fi_bit, .data_o(shadow_rem));

  // div.sv keeps DivBusyE asserted from launch through every iteration.  The
  // sole non-busy cycle for a held IntDivE is its DONE state, when its outputs
  // are valid for comparison.  Both busy outputs are retained defensively.
  assign result_valid = IntDivE & ~primary_busy & ~shadow_busy;
  assign mismatch = result_valid & ((primary_quot != shadow_quot) |
                                    (primary_rem  != shadow_rem));
  assign DivBusyE = primary_busy | shadow_busy;

  // Initial and retry mismatches hold the full pipeline.  A final failed
  // attempt exposes one M-aligned unresolved pulse; no guessed replica result
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
        // Trap/flush normally clears this state.  Self-clear also makes the
        // fault indication a single cycle if a standalone wrapper is used.
        UNRESOLVED: state <= NORMAL;
        default:    state <= NORMAL;
      endcase
    end
  end

  // Mask all untrusted outputs.  During normal iteration DivBusyE already
  // prevents M-stage consumption; retry/unresolved additionally protect the
  // held transaction from any accidental result-path use.
  assign QuotM = (stall_req | unresolved) ? '0 : primary_quot;
  assign RemM  = (stall_req | unresolved) ? '0 : primary_rem;
endmodule
