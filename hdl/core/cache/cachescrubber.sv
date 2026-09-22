///////////////////////////////////////////
// cachescrubber.sv
//
// Purpose: Background SECDED scrubber for the L1 cache. Free-running (set, way) round-robin
//          walker: reads and decodes every set/way on a parameterizable interval, regardless of
//          whether the core ever accesses it, and corrects/invalidates/traps on what it finds.
//          Replaces the branch's previous access-driven "refresh" mechanism (RefreshCount /
//          REFRESH_THRESHOLD), which only ever re-fetched lines the core actually touched and so
//          could never catch an error in a line nobody reads again.
//
//          Always yields to demand traffic: ScrubReq is level-held (never edge-triggered, so a
//          request is only ever delayed, never dropped), and cache.sv's ScrubGrant is defined to
//          require no demand access, CMO, flush, or invalidate in flight that cycle.
//
//          Read and write/action grants are separate events that can be arbitrarily far apart in
//          time (a demand access can and will interleave). Rather than holding the array's address
//          bus continuously across a multi-cycle operation -- which would either stall demand
//          traffic or require yanking the address out from under an in-flight scrub sequence -- this
//          module re-reads and re-decodes before ever committing a write: a discovery pass finds a
//          candidate error and remembers only "this (set,way) looked wrong"; a second, independent
//          verify pass re-reads the same (set,way) fresh and only commits the action if the same
//          condition still holds. If the line changed underneath the scrubber in the meantime (a
//          demand miss/fill on the same line), the verify pass simply won't reproduce the original
//          finding, and the scrubber quietly moves on -- no stale or incorrect write can land.
//
// A component of the AMOEBA RISC-V project.
////////////////////////////////////////////////////////////////////////////////////////////////

module cachescrubber #(
  parameter NUMSETS, NUMWAYS, SETLEN,
  parameter READ_ONLY_CACHE,
  parameter SCRUB_INTERVAL_CYCLES  // cycles to wait between round-robin steps; left untuned by design
) (
  input  logic clk, reset,

  // Arbitration with cache.sv
  output logic                ScrubReq,       // level-held: "grant me the address bus this cycle"
  input  logic                ScrubGrant,     // cache.sv: granted this cycle
  output logic [SETLEN-1:0]   ScrubSet,
  output logic [NUMWAYS-1:0]  ScrubWay,       // one-hot target of this sweep step

  // Decode status for whichever way ScrubWay currently selects (via the same SelectedWay/AND-OR
  // mux machinery the demand path uses), valid on the same 2-cycle-after-grant schedule as the
  // demand path (tag info one cycle after grant, data info the cycle after that).
  input  logic                ValidWay,
  input  logic                DirtyWay,        // D$ only; tied 0 for I$
  input  logic                TagSecErr,
  input  logic                TagDedErr,
  input  logic                DataSecErr,
  input  logic                DataDedErr,

  // Action requests -- one-cycle pulses; cache.sv performs the actual write/invalidate/trap when
  // it sees one of these asserted during a granted cycle.
  output logic                ScrubCorrectTag,
  output logic                ScrubCorrectData,
  output logic                ScrubInvalidate,   // clean line (or I$, which has no dirty state): cheap invalidate-and-refetch
  output logic                ScrubTrap,         // D$ only: dirty line, uncorrectable -- escalate, do not invalidate

  // Mirrors cachefsm's TagDecodeCaptureEn for the scrub path: pulses during SCRUB_TAG_WAIT (the
  // cycle tag info for ScrubWay is valid) so cacheway.sv's SelectedWayDataQ register captures the
  // scrubber's target way, not whatever way the last demand access left it pointing at. Without
  // this, the shared data decoder in cache.sv would silently decode the wrong way's data whenever
  // a scrub read follows a demand access.
  output logic                ScrubTagDecodeCaptureEn,

  // True from the granted read cycle through commit: the scrubber is actively using ScrubWay-based
  // way-selection (SelectedWay in cacheway.sv, and this module's own TagSecErr/TagDedErr/etc
  // inputs, which cache.sv aggregates using the SAME ScrubWay signal -- see cache.sv). A demand
  // access starting mid-sequence would contend for that same shared way-selection state and corrupt
  // either side's view of it, so cachefsm holds off entering its own decode sequence while this is
  // asserted. Not asserted during SCRUB_WAIT/SCRUB_REQUEST, since standard grant arbitration
  // (ScrubGrant requires no demand access) already keeps those from ever conflicting with a demand
  // access -- only once granted does the scrubber start actually touching shared way-selection state.
  output logic                ScrubBusy
);

  localparam int WAYLOG2 = (NUMWAYS > 1) ? $clog2(NUMWAYS) : 1;

  typedef enum logic [2:0] {
    SCRUB_WAIT,        // between sweep steps, counting down the scrub interval
    SCRUB_REQUEST,     // ScrubReq asserted, waiting for ScrubGrant
    SCRUB_TAG_WAIT,    // granted last cycle; tag decode valid this cycle
    SCRUB_DATA_WAIT,   // data decode valid this cycle; decide
    SCRUB_COMMIT       // second (verify) pass reproduced the finding; commit this cycle
  } scrubstatetype;

  scrubstatetype CurrState, NextState;

  logic [$clog2(SCRUB_INTERVAL_CYCLES == 0 ? 1 : SCRUB_INTERVAL_CYCLES)-1:0] IntervalCount;
  logic IntervalExpired;
  logic [SETLEN-1:0]  SetCount;
  logic [WAYLOG2-1:0] WayCount;
  logic               VerifyPass;   // 0 = discovery pass, 1 = re-verifying a prior finding

  // Latched finding from the discovery pass, compared against the verify pass's fresh result.
  logic PendingTagSec, PendingTagDed, PendingDataSec, PendingDataDed, PendingValid, PendingDirty;

  assign ScrubSet = SetCount;
  assign ScrubWay = NUMWAYS'(1'b1) << WayCount;

  // ---------------------------------------------------------------------------------------------
  // Interval counter: paces round-robin steps. SCRUB_INTERVAL_CYCLES==0 disables the counter (steps
  // as fast as grants allow) -- useful for simulation; a real interval is expected to be set in
  // pkg/config.vh once tuned.
  // ---------------------------------------------------------------------------------------------
  always_ff @(posedge clk)
    if (reset) IntervalCount <= '0;
    else if (CurrState == SCRUB_WAIT) begin
      if (IntervalExpired) IntervalCount <= '0;
      else IntervalCount <= IntervalCount + 1'b1;
    end
  assign IntervalExpired = (SCRUB_INTERVAL_CYCLES == 0) || (IntervalCount == SCRUB_INTERVAL_CYCLES - 1);

  // ---------------------------------------------------------------------------------------------
  // Round-robin (set, way) counter: advances once per completed sweep step (whether or not any
  // action was taken), only out of SCRUB_DATA_WAIT (discovery, nothing wrong or nothing worth a
  // verify pass) or SCRUB_COMMIT (verify pass concluded, acted or not).
  // ---------------------------------------------------------------------------------------------
  logic AdvanceRoundRobin;
  always_ff @(posedge clk)
    if (reset) begin
      SetCount <= '0;
      WayCount <= '0;
    end else if (AdvanceRoundRobin) begin
      if (WayCount == WAYLOG2'(NUMWAYS - 1)) begin
        WayCount <= '0;
        SetCount <= (SetCount == SETLEN'(NUMSETS - 1)) ? '0 : SetCount + 1'b1;
      end else begin
        WayCount <= WayCount + 1'b1;
      end
    end

  always_ff @(posedge clk)
    if (reset) VerifyPass <= 1'b0;
    else if (CurrState == SCRUB_DATA_WAIT && NextState == SCRUB_REQUEST) VerifyPass <= 1'b1; // discovery found something, looping back to verify
    else if (AdvanceRoundRobin) VerifyPass <= 1'b0;

  // ---------------------------------------------------------------------------------------------
  // Sequencer
  // ---------------------------------------------------------------------------------------------
  always_ff @(posedge clk)
    if (reset) CurrState <= SCRUB_WAIT;
    else CurrState <= NextState;

  logic FoundSomething;
  assign FoundSomething = ValidWay & (TagDedErr | TagSecErr | DataDedErr | DataSecErr);
  // DirtyWay alone is never itself a fault -- it only affects how SCRUB_COMMIT routes a DataDedErr.

  assign ScrubTagDecodeCaptureEn = (CurrState == SCRUB_TAG_WAIT);
  assign ScrubBusy = (CurrState == SCRUB_TAG_WAIT) || (CurrState == SCRUB_DATA_WAIT) || (CurrState == SCRUB_COMMIT);

  always_comb begin
    NextState = CurrState;
    AdvanceRoundRobin = 1'b0;
    ScrubReq = 1'b0;
    ScrubCorrectTag = 1'b0;
    ScrubCorrectData = 1'b0;
    ScrubInvalidate = 1'b0;
    ScrubTrap = 1'b0;
    case (CurrState)
      SCRUB_WAIT: if (IntervalExpired) NextState = SCRUB_REQUEST;
      SCRUB_REQUEST: begin
        ScrubReq = 1'b1;
        if (ScrubGrant) NextState = SCRUB_TAG_WAIT;
      end
      SCRUB_TAG_WAIT: NextState = SCRUB_DATA_WAIT; // tag decode (for ScrubWay) valid this cycle; nothing to act on yet, data still pending
      SCRUB_DATA_WAIT: begin
        // Data decode valid this cycle. On a fresh (discovery) pass, remember the finding and loop
        // back to re-verify. On a verify pass, the finding must reproduce exactly (down to which
        // error class) before it's trusted.
        if (!VerifyPass) begin
          if (FoundSomething) NextState = SCRUB_REQUEST; // discovery: re-request immediately for the verify pass
          else begin
            NextState = SCRUB_WAIT;
            AdvanceRoundRobin = 1'b1;
          end
        end else begin
          if (FoundSomething
              && (TagDedErr == PendingTagDed) && (TagSecErr == PendingTagSec)
              && (DataDedErr == PendingDataDed) && (DataSecErr == PendingDataSec)
              && (ValidWay == PendingValid) && (DirtyWay == PendingDirty))
            NextState = SCRUB_COMMIT;
          else begin
            NextState = SCRUB_WAIT; // didn't reproduce -- someone else already touched this line; move on
            AdvanceRoundRobin = 1'b1;
          end
        end
      end
      SCRUB_COMMIT: begin
        // Route by error class, same priority as the demand path: uncorrectable-and-dirty (D$
        // only) traps without touching valid/dirty; uncorrectable-and-clean (or I$) invalidates;
        // correctable commits a re-encoded writeback for whichever of tag/data needed it.
        if (TagDedErr | (DataDedErr & ~(DirtyWay & !READ_ONLY_CACHE))) begin
          ScrubInvalidate = 1'b1;
        end else if (DataDedErr & DirtyWay & !READ_ONLY_CACHE) begin
          ScrubTrap = 1'b1; // leave valid+dirty set; privileged unit escalates
        end else begin
          if (TagSecErr) ScrubCorrectTag = 1'b1;
          if (DataSecErr) ScrubCorrectData = 1'b1;
        end
        NextState = SCRUB_WAIT;
        AdvanceRoundRobin = 1'b1;
      end
      default: NextState = SCRUB_WAIT;
    endcase
  end

  always_ff @(posedge clk) begin
    if (CurrState == SCRUB_DATA_WAIT && !VerifyPass && FoundSomething) begin
      PendingTagSec  <= TagSecErr;
      PendingTagDed  <= TagDedErr;
      PendingDataSec <= DataSecErr;
      PendingDataDed <= DataDedErr;
      PendingValid   <= ValidWay;
      PendingDirty   <= DirtyWay;
    end
  end

endmodule
