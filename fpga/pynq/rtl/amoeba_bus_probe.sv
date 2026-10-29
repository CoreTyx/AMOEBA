///////////////////////////////////////////////////////////////////////////////
// amoeba_bus_probe.sv
//
// Observability for the EXTERNAL AHB -- the one link in this design that the
// control block could not see, and therefore the one place a failure had no
// signature beyond "0 retired, 0 traps".
//
// The gap this fills.  cycles/retired/traps describe the CORE.  When the core
// stalls on a bus that never answers, all three are consistent with half a
// dozen unrelated faults: a bad image, a dead clock, a reset that never
// released, a mistranslated address, a slave that was never connected.  The
// counters below separate them, because they say whether the core ASKED, and
// whether anything ANSWERED.
//
// Everything here is observation only.  Nothing drives the bus, nothing
// gates it, and the module is a no-op for the design's behaviour -- which
// matters, because a probe that can perturb the thing it measures is worse
// than no probe when you are chasing an intermittent.
//
// Reading it while the core is HUNG is the intended use.  A stalled AHB is
// static, so a single read of `state` is a photograph of the deadlock: who is
// selected, what phase is on the bus, and which side is refusing to move.
///////////////////////////////////////////////////////////////////////////////

module amoeba_bus_probe #(
    parameter int PA_BITS = 56
)(
    input  logic               clk,
    input  logic               rstn,          // PL reset; NOT the core's
    input  logic               clear,         // one-cycle pulse, from CTRL

    // The external AHB, exactly as the core drives it
    input  logic               HSEL,
    input  logic [1:0]         HTRANS,
    input  logic               HWRITE,
    input  logic [2:0]         HBURST,
    input  logic [2:0]         HSIZE,
    input  logic [PA_BITS-1:0] HADDR,
    input  logic               HREADY,        // from the slave (HREADYEXT)
    input  logic               HRESP,
    input  logic [63:0]        HRDATA,        // what the slave returns
    input  logic               core_reset,

    // The address that actually leaves the module, after translation.  Kept
    // separate from HADDR on purpose: comparing the two on hardware is the
    // only direct check that the rebase is doing what the RTL says it does.
    input  logic [31:0]        xaddr,

    output logic [31:0]        state,
    output logic [31:0]        xact_count,    // NONSEQ address phases accepted
    output logic [31:0]        beat_count,    // data phases that returned OKAY
    output logic [31:0]        err_count,     // data phases that returned ERROR
    output logic [31:0]        stall_count,   // data-phase cycles with HREADY low
    output logic [31:0]        max_wait,      // longest single data-phase wait
    output logic [31:0]        err_wait,      // wait cycles before the FIRST error
    output logic [31:0]        err_xact,      // which transfer number that was
    output logic [31:0]        pre_state,     // bus state BEFORE the 1st select

    // Capture buffer: CAP_DEPTH consecutive cycles from the first select.
    input  logic [5:0]         cap_sel,
    output logic [31:0]        cap_dat,
    output logic [31:0]        cap_rdat,      // HRDATA[31:0] for the same cycle
    output logic [31:0]        cap_stat,      // {done, ptr}: did it capture?
    output logic [31:0]        rst_xact,      // transfers accepted DURING reset

    output logic [31:0]        first_addr,    // core address of the 1st access
    output logic [31:0]        first_xaddr    // translated address of the 1st
);

    localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

    // WHY THE DATA PHASE IS TRACKED SEPARATELY.
    //
    // AHB is pipelined: a transfer's address phase and its data phase are one
    // cycle apart, and HREADY and HRESP belong to the DATA phase.  The first
    // version of this probe gated every counter on HSEL -- an ADDRESS-phase
    // signal -- which made it blind to exactly what it was built for.  While a
    // slave extends a data phase the master has nothing new to present, so it
    // drives HTRANS=IDLE and drops HSEL; a 256-cycle bridge timeout therefore
    // read out as "0 stall cycles", and the error count degenerated into a
    // count of cycles HSEL happened to be high.  Both numbers looked like
    // measurements and were not.
    //
    // So: latch whether a data phase is in flight, and attribute HREADY and
    // HRESP to that, not to whatever the address bus is doing meanwhile.
    logic addr_accepted, xact_start, dphase;

    assign addr_accepted = HSEL && HREADY && HTRANS[1];       // NONSEQ or SEQ
    assign xact_start    = HSEL && HREADY && (HTRANS == HTRANS_NONSEQ);

    logic beat_ok, beat_err, waiting;
    assign waiting  = dphase && !HREADY;
    assign beat_ok  = dphase &&  HREADY && !HRESP;
    assign beat_err = dphase &&  HREADY &&  HRESP;

    logic seen_first;
    logic [31:0] wait_run;      // length of the wait currently in progress

    // WHY THE FIRST ERROR IS LATCHED SEPARATELY.
    //
    // ahblite_axi_bridge's HRESP is a sticky flag, not a per-transfer
    // response: its HRESP register holds its value and is only cleared on a
    // path where a transfer SUCCEEDS.  So once anything fails and nothing
    // afterwards succeeds, HRESP stays asserted for good, every later data
    // phase reads as an error, and no beat can ever be counted OK again.  The
    // aggregate counters are therefore telling you about the flag, not about
    // the transfers.  Only the first error is a real event, so capture the
    // circumstances of exactly that one:  how long the bridge had been
    // waiting (256 means its AXI timeout fired; 0 means it refused the
    // transfer outright) and how many transfers had already gone out.
    logic err_seen;

    // DID ANYTHING DRIVE THIS BUS WHILE THE CORE WAS HELD?
    //
    // It should not be possible, and a previous capture suggests it happens: a
    // full INCR8 read was seen with core_reset asserted.  It matters because
    // ahblite_axi_bridge would take that transfer, issue AXI for it, and still
    // be waiting when the core is finally released -- which would explain an
    // HREADY already low before the core's own first select, and an error that
    // appears to arrive with no wait because the waiting happened earlier.
    // Counted rather than argued about.

    // WAS HRESP ALREADY ASSERTED BEFORE WE EVER ASKED?
    //
    // HRESP is meaningful only during a data phase, so a slave sitting with it
    // high while nothing is selected is not answering anything -- it is in an
    // error state it entered on its own.  Distinguishing that from "our first
    // transfer was rejected" cannot be done from counters, because the sticky
    // flag makes both look identical afterwards.  Sample the bus once, on the
    // last cycle before the first select, and keep it.
    logic [31:0] pre_state_q, state_q;
    logic        pre_captured, armed;

    // The core drives the bus only once it is out of reset; anything before
    // that belongs to the PS-side load, not to the fetch we are chasing.
    assign armed = !core_reset;
    assign pre_state = pre_state_q;

    // ---- capture buffer ----------------------------------------------------
    // The counters say a transfer failed; they cannot say what was on the wire
    // when it did.  CAP_DEPTH cycles from the first select is enough to hold
    // the reset-vector fetch and the bridge's response to it, which is the
    // only transaction that matters -- everything after it is downstream of a
    // latched error.
    localparam int CAP_DEPTH = 64;

    logic [31:0] cap_mem  [CAP_DEPTH];

    // THE DATA, NOT JUST THE HANDSHAKE.  A burst can complete with correct
    // addresses, correct beat count and no error, and still hand the core the
    // wrong bytes -- a swapped lane or a stale line looks identical on the
    // control signals.  Nothing above could tell that from a healthy fetch,
    // which is the difference between "the bus works" and "the core can boot".
    logic [31:0] cap_rmem [CAP_DEPTH];
    logic [5:0]  cap_ptr;
    logic        cap_run, cap_done;
    logic [31:0] cap_word;

    // BIT 31 IS A VALIDITY MARKER, AND IT IS NOT DECORATION.  cap_mem has no
    // reset, so an entry that was never written reads back as all zeros -- and
    // all zeros decodes to "HSEL=0, HTRANS=IDLE, HREADY=0", a perfectly
    // plausible idle bus.  Without this bit an empty buffer is indistinguish-
    // able from a captured quiet one, which is exactly the ambiguity that made
    // the first capture run worthless.
    // BIT 30 IS core_reset, AND IT SETTLES THE ONLY QUESTION THAT MATTERED.
    // Without it a captured burst cannot be placed in time: "the core fetched
    // this after release" and "the core was still held and this leaked" look
    // identical on the wires, and the counters that were supposed to tell them
    // apart count in different units (xact_count counts NONSEQ starts,
    // rst_xact counts address phases).  Now every captured cycle says for
    // itself whether the core was running.
    assign cap_word = { 1'b1, core_reset, 6'h0, 12'(HADDR), HRESP, HREADY,
                        HSEL, HWRITE, HTRANS, HSIZE, HBURST };
    assign cap_dat  = cap_mem[cap_sel];
    assign cap_rdat = cap_rmem[cap_sel];

    // So the reader can tell "never armed" from "armed and the bus was quiet"
    // even before looking at an entry.
    assign cap_stat = { 24'h0, cap_done, 1'b0, cap_ptr };

    // Start capturing ON the select cycle, not the one after it.  The address
    // phase is the most interesting cycle in the whole window and the first
    // version threw it away.
    logic cap_start;
    assign cap_start = !cap_run && !cap_done && armed && HSEL;

    always_ff @(posedge clk) begin
        if (!rstn || clear) begin
            xact_count  <= '0;
            beat_count  <= '0;
            err_count   <= '0;
            stall_count <= '0;
            max_wait    <= '0;
            wait_run    <= '0;
            first_addr  <= '0;
            first_xaddr <= '0;
            seen_first  <= 1'b0;
            dphase      <= 1'b0;
            // EVERY piece of state in this module resets here.  An earlier
            // version reset only the counters above, so err_wait/err_xact,
            // pre_state and the capture buffer's control all survived both
            // MON_CLEAR and PL reset -- they accumulated from the moment the
            // bitstream configured, and a reading taken after a run described
            // some other window entirely.  A probe whose numbers cannot be
            // attributed to a time span is not a measurement.
            err_wait     <= '0;
            err_xact     <= '0;
            err_seen     <= 1'b0;
            rst_xact     <= '0;
            pre_state_q  <= '0;
            state_q      <= '0;
            pre_captured <= 1'b0;
            cap_ptr      <= '0;
            cap_run      <= 1'b0;
            cap_done     <= 1'b0;
        end else begin
            if (HREADY) dphase <= addr_accepted;

            // One cycle of history, so "before the first select" really is
            // the cycle before it and not the select cycle itself.
            state_q <= state;

            // Freeze the pre-transfer picture at the first select the running
            // core makes.
            if (!pre_captured && armed) begin
                pre_state_q <= state_q;
                if (HSEL) pre_captured <= 1'b1;
            end

            if (cap_start) cap_run <= 1'b1;
            if (cap_run || cap_start) begin
                cap_mem[cap_ptr]  <= cap_word;
                cap_rmem[cap_ptr] <= HRDATA[31:0];
                if (cap_ptr == 6'(CAP_DEPTH - 1)) begin
                    cap_run  <= 1'b0;
                    cap_done <= 1'b1;
                end else begin
                    cap_ptr <= cap_ptr + 1'b1;
                end
            end

            if (xact_start) xact_count <= xact_count + 1'b1;
            if (HSEL && HREADY && HTRANS[1] && core_reset)
                rst_xact <= rst_xact + 1'b1;
            if (beat_ok)    beat_count <= beat_count + 1'b1;
            if (beat_err)   err_count  <= err_count  + 1'b1;

            if (beat_err && !err_seen) begin
                err_seen <= 1'b1;
                err_wait <= wait_run;
                err_xact <= xact_count;
            end

            // The peak matters more than the total.  A total says the bus was
            // slow; the peak says whether any single transfer sat there for
            // the bridge's whole 256-cycle timeout, which is the difference
            // between "the AXI side never answered" and "the bridge refused
            // the transfer on the spot".
            if (waiting) begin
                stall_count <= stall_count + 1'b1;
                wait_run    <= wait_run + 1'b1;
                if (wait_run + 1'b1 > max_wait) max_wait <= wait_run + 1'b1;
            end else begin
                wait_run <= '0;
            end

            // FIRST, not last.  The interesting access is the reset-vector
            // fetch: if that one never completes nothing else ever happens, so
            // the last address would just be the same one forever and tell you
            // nothing you did not already know.
            if (xact_start && !seen_first) begin
                seen_first  <= 1'b1;
                first_addr  <= 32'(HADDR);
                first_xaddr <= xaddr;
            end
        end
    end

    // Live, unregistered: this is meant to be read while the bus is frozen.
    assign state = {
        16'h0,
        core_reset,     // [15]
        seen_first,     // [14]
        HRESP,          // [13]
        HREADY,         // [12]
        HSIZE,          // [11:9]
        HBURST,         // [8:6]
        HWRITE,         // [5]
        HTRANS,         // [4:3]
        HSEL,           // [2]
        2'b00           // [1:0]
    };

endmodule
