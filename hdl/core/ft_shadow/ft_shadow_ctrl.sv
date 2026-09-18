// Fault-tolerant shadow controller shared by execute-unit wrappers.
// A mismatch retries the held transaction.  Recompute is optional and is used
// only by ft_alu for the supported ordinary-add relation.
module ft_shadow_ctrl #(
  // Number of consecutive mismatches before escalation.
  parameter int TE_THRESHOLD = 3
) (
  // Clock/reset/flush define the lifetime of the held transaction.
  input  logic clk, reset, flush,
  input  logic valid,                   // operation currently occupies the wrapper
  input  logic mismatch,                // primary and shadow outputs disagree
  input  logic recompute_supported,     // wrapper supplies a trusted alternate test
  input  logic recompute_primary_ok,    // primary passes the alternate test
  input  logic recompute_shadow_ok,     // shadow passes the alternate test
  output logic recompute_mode,          // alternate test is active
  output logic stall_req,               // hold all architectural stages
  output logic unresolved,               // no trustworthy result; take a trap
  output logic isolated,                // one copy has been diagnosed
  output logic use_shadow,              // select shadow after primary failure
  output logic pe_primary,
  output logic pe_shadow                 // diagnostic isolation indicators
);

  // Keep one counter bit for the threshold-one configuration.
  localparam int COUNT_W = (TE_THRESHOLD <= 1) ? 1 : $clog2(TE_THRESHOLD);
  // UNRESOLVED releases the instruction so Wally can report a precise
  // exception; all earlier states preserve the original transaction.
  typedef enum logic [2:0] {NORMAL, RETRY, RECOMPUTE, ISOLATED, UNRESOLVED} state_t;
  state_t state;
  logic [COUNT_W-1:0] mismatch_count;

  initial begin
    if (TE_THRESHOLD < 1) $error("TE_THRESHOLD must be positive");
  end

  assign recompute_mode = (state == RECOMPUTE);
  assign isolated       = (state == ISOLATED);
  assign unresolved     = (state == UNRESOLVED);
  // A mismatch/recompute holds every architectural stage.  UNRESOLVED is
  // deliberately not stalled so its instruction can enter M and take a
  // precise synchronous trap.
  assign stall_req      = (state == RECOMPUTE) |
                          (((state == NORMAL) | (state == RETRY)) & valid & mismatch);

  // State is synchronous; datapath results remain combinational for retries.
  always_ff @(posedge clk) begin
    if (reset | flush) begin
      state          <= NORMAL;
      mismatch_count <= '0;
      use_shadow     <= 1'b0;
      pe_primary     <= 1'b0;
      pe_shadow      <= 1'b0;
    end else begin
      case (state)
        // First disagreement starts the retry count; normal execution has
        // no added latency when both copies agree.
        NORMAL: begin
          mismatch_count <= '0;
          if (valid & mismatch) begin
            mismatch_count <= COUNT_W'(1);
            if (TE_THRESHOLD == 1) begin
              if (recompute_supported) state <= RECOMPUTE;
              else                     state <= UNRESOLVED;
            end else state <= RETRY;
          end
        end
        // The pipeline remains frozen while the same operation is observed
        // again. A matching retry returns directly to NORMAL.
        RETRY: begin
          if (!valid | !mismatch) begin
            state          <= NORMAL;
            mismatch_count <= '0;
          end else if (mismatch_count >= TE_THRESHOLD-1) begin
            if (recompute_supported) state <= RECOMPUTE;
            else                     state <= UNRESOLVED;
          end else begin
            mismatch_count <= mismatch_count + COUNT_W'(1);
          end
        end
        // Recompute is one diagnostic cycle. Exactly one passing relation is
        // required; agreement or disagreement by both copies is ambiguous.
        RECOMPUTE: begin
          // A copy is bad when its alternate result no longer has the known
          // relationship to its own saved normal result.
          if (recompute_primary_ok & ~recompute_shadow_ok) begin
            pe_shadow <= 1'b1;
            use_shadow <= 1'b0;
            state <= ISOLATED;
          end else if (~recompute_primary_ok & recompute_shadow_ok) begin
            pe_primary <= 1'b1;
            use_shadow <= 1'b1;
            state <= ISOLATED;
          end else begin
            state <= UNRESOLVED;
          end
        end
        // The diagnosed-good copy is used for subsequent operations until a
        // flush/reset; the bad copy is never trusted again in this instance.
        ISOLATED: state <= ISOLATED;
        // Release one instruction to M so the normal trap path can capture PC.
        UNRESOLVED: begin
          state          <= NORMAL;
          mismatch_count <= '0;
        end
        default: state <= NORMAL;
      endcase
    end
  end
endmodule
