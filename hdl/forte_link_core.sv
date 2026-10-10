///////////////////////////////////////////////////////////////////////////////
// forte_link_core.sv
//
// The core domain: AHB-Lite slave on the SoC's external port -> flits.  This is
// the half of hdl/forte_link_master.sv that has to stay next to the core,
// because it is the half that can see HTRANS.
//
//   LC_IDLE    HREADYOUT=1.  An address phase that completes here is latched
//              and its command flit pushed.
//   LC_WFIRST  one idle cycle -- see "WHY LC_WFIRST" below
//   LC_WDATA   push BEATS data flits, pulsing HREADYOUT to pull each next beat
//   LC_RDATA   pop BEATS beats, presenting each on HRDATA with an HREADYOUT pulse
//
// This is simpler than the logic it replaces, because the crossing deals in
// whole 64-bit beats: there is no 16-bit word accounting here and no beat
// assembly register.  HRDATA is the inbound FIFO's read data directly.
//
// THE ABORT RULE lives here, unchanged in substance from forte_link_master.
// buscachefsm drops to ADR_PHASE on FlushD in the same cycle, so an I-fetch
// line fill can lose its master mid-burst.  Once a command flit has been pushed
// the phy is committed to finishing it on the wire, so this module must still
// account for all BEATS beats -- what it must NOT do is complete an AHB beat for a
// master that has moved on.  A NONSEQ at a beat boundary is the master's *next*
// request, and pulsing HREADY then would accept it while the old transaction is
// still draining.  So at a non-final beat boundary HREADYOUT pulses only if
// HTRANS was SEQ a cycle ago; otherwise the beat is pushed or popped and
// discarded, and the master -- which only issues a new NONSEQ while HREADY=1 --
// waits.
//
// HTRANS is looked at through a register: Wally's HTRANS mux depends on HREADY,
// so a combinational look would loop.  The master holds SEQ for the whole beat,
// and a flush in the pulse cycle itself cannot raise NONSEQ (~Flush gates it),
// so the one-cycle-old value is exact.
//
// WHY LC_WFIRST.  htrans_q lags by a cycle, and in the cycle right after an
// accept it still holds the NONSEQ that was accepted -- the master only raises
// SEQ for beat 1 in that same cycle.  A write would otherwise push beat 0 while
// htrans_q reads NONSEQ, beat_ok would be false, `aborted` would latch on beat 0
// of EVERY write, and HREADYOUT would never pulse again: an instant hang.
// forte_link_master was accidentally immune because its first pulse came four
// words into the burst, by which time SEQ had been showing for three cycles.
// One idle cycle lets htrans_q catch up.  It costs nothing on the wire -- the
// phy does not start until the whole transaction is buffered anyway.
//
// The tempting alternative, exempting beat 0 from the check, is WRONG: on a READ
// beat 0 is popped ~18 cycles after the accept, so the master really can have
// flushed by then, and exempting it would complete a beat for a master that has
// gone.  The lag is a write-path problem only, so it is fixed on the write path
// only.
//
// Writes are never aborted in practice (the D-cache's buscachefsm has Flush
// tied low); the write path accounts for them the same way for symmetry, and
// asserts if it ever happens.
///////////////////////////////////////////////////////////////////////////////

module forte_link_core import forte_link_pkg::*; #(
  parameter HADDR_W = 56,
  // Beats per transaction.  Set by hdl/forte_chip.sv from the core config as
  // DCACHE_LINELENINBITS / AHBW; see "ONE BURST LENGTH PER BUILD" in
  // hdl/forte_link_pkg.sv.  The default matches a 512-bit line and is here only
  // because SystemVerilog requires one -- forte_chip always overrides it.
  parameter BEATS   = 8
)(
  input  logic                HCLK, HRESETn,

  // AHB-Lite slave (external port of forte_soc)
  input  logic                HSEL,
  input  logic [HADDR_W-1:0]  HADDR,
  input  logic [1:0]          HTRANS,      // 00 IDLE 01 BUSY 10 NONSEQ 11 SEQ
  input  logic                HWRITE,
  input  logic [2:0]          HSIZE,
  input  logic [2:0]          HBURST,
  input  logic [63:0]         HWDATA,
  input  logic                HREADY,      // the uncore's mux: address phase completes on this
  output logic [63:0]         HRDATA,
  output logic                HREADYOUT,
  output logic                HRESP,

  // outbound flits, write side of the core->link FIFO
  output logic                ocmd_valid,
  input  logic                ocmd_ready,
  output logic [FLIT_W-1:0]   ocmd_data,

  // inbound beats, read side of the link->core FIFO
  input  logic                ibeat_valid,
  output logic                ibeat_ready,
  input  logic [63:0]         ibeat_data
);

  localparam logic [1:0] HTRANS_NONSEQ = 2'b10, HTRANS_SEQ = 2'b11;

  // HSIZE and HBURST feed assertions only -- INCR8 is implicit on the wire.
  // Sink them so the synthesis flow does not warn about unread inputs.
  logic unused_attrs;
  assign unused_attrs = ^{HSIZE, HBURST};

  link_core_st_t st;                   // states in hdl/forte_link_pkg.sv

  // No addr_r/wr_r: the command flit is pushed in the cycle the address phase
  // is accepted, so the address never needs holding, and after that LC_WDATA vs
  // LC_RDATA is the direction.
  logic [31:0] nxt_addr;
  logic        nxt_wr, pending;
  // Beat index runs 0..BEATS-1.  BEATS >= 2 is checked below, so $clog2 is
  // never asked for the width of a one-element range.
  localparam BCNT_W = $clog2(BEATS);
  logic [BCNT_W-1:0] bcnt;             // beat within the transaction
  logic        aborted;
  logic [1:0]  htrans_q;
  always_ff @(posedge HCLK) htrans_q <= HTRANS;

  logic last_beat, beat_ok, accept, wpush, rpop;

  assign last_beat = (bcnt == BCNT_W'(BEATS - 1));
  assign beat_ok   = ~aborted & ~pending & (last_beat | (htrans_q == HTRANS_SEQ));

  // Address phase of a transfer to us completes on the mux'd HREADY.  SEQ beats
  // belong to the burst already in flight.
  //
  // GATED ON HRESETn, and that gate is load-bearing.  ocmd_valid is a
  // COMBINATIONAL output feeding the outbound FIFO, whose write port is reset by
  // rst_n_s -- released about two cycles after rst_n.  HRESETn comes from the
  // core's reset synchroniser and releases later still.  In that window the FIFO
  // is live while this module is still held in reset, and HADDR/HSEL/HREADY read
  // as a plausible accept at the reset vector, so four garbage command flits got
  // pushed before the core had issued anything.  The phy then executed them as
  // four extra reads, and the surplus beats were misattributed to later
  // transactions -- a deadlock on the second one.
  //
  // forte_link_master never had this exposure: `accept` only ever had effect
  // inside the reset-guarded always_ff, and nothing combinational left the
  // module.  Any combinational signal crossing into a different reset domain
  // needs this gate.
  assign accept = HRESETn & HSEL & (HTRANS == HTRANS_NONSEQ) & HREADY;

  // ---- flit traffic ---------------------------------------------------------
  // A write beat is pushed whenever the FIFO can take it.  All BEATS go in whether
  // or not the master is still interested: the phy is committed to the word
  // count, so a short push would underrun the wire.
  assign rpop  = (st == LC_RDATA) & ibeat_valid;
  assign ibeat_ready = (st == LC_RDATA);

  // The command flit is pushed in the cycle the address phase is accepted, or
  // in the cycle a pending one is started.
  logic cmd_push;
  assign cmd_push   = (st == LC_IDLE) & (pending | accept);

  // valid must NOT depend on ready -- that is a valid/ready protocol violation
  // even where it happens to work (prim_fifo_async's wready does not depend on
  // wvalid, so there is no actual loop).  wpush is the derived "a push was
  // taken this cycle".
  assign ocmd_valid = cmd_push | (st == LC_WDATA);
  assign wpush      = (st == LC_WDATA) & ocmd_ready;
  assign ocmd_data  = cmd_push ? cmd_flit(pending ? nxt_wr   : HWRITE,
                                          pending ? nxt_addr : HADDR[31:0])
                               : dat_flit(HWDATA);

  // ---- AHB response ---------------------------------------------------------
  // Stalling on ~ocmd_ready in LC_IDLE cannot deadlock: the FIFO is sized to
  // BEATS+2 (hdl/forte_link_pkg.sv fifo_depth), one transaction plus the next
  // command, and only one transaction is ever in flight.  It is gated anyway
  // rather than assumed -- the margin is now one slot, not seven.
  assign HREADYOUT = ((st == LC_IDLE) & ~pending & ocmd_ready)
                   | (wpush & beat_ok)
                   | (rpop  & beat_ok);
  assign HRDATA    = ibeat_data;
  assign HRESP     = 1'b0;              // no error path (BRINGUP.md s2)

  always_ff @(posedge HCLK) begin
    if (!HRESETn) begin
      st <= LC_IDLE;
      nxt_addr <= '0; nxt_wr <= 1'b0; pending <= 1'b0;
      bcnt <= '0; aborted <= 1'b0;
    end else begin
      case (st)
        LC_IDLE: begin
          aborted <= 1'b0;
          bcnt    <= '0;
          if (pending & ocmd_ready) begin
            pending <= 1'b0;
            st <= nxt_wr ? LC_WFIRST : LC_RDATA;
          end
        end

        LC_WFIRST: st <= LC_WDATA;    // let htrans_q catch up; see the header

        LC_WDATA: begin
          if (wpush) begin
            if (~beat_ok) aborted <= 1'b1;
            if (last_beat) st <= LC_IDLE;
            else           bcnt <= bcnt + BCNT_W'(1);
          end
        end

        LC_RDATA: begin
          if (rpop) begin
            if (~beat_ok) aborted <= 1'b1;
            if (last_beat) st <= LC_IDLE;
            else           bcnt <= bcnt + BCNT_W'(1);
          end
        end

        default: st <= LC_IDLE;
      endcase

      // Accept, wherever the address phase completes.  Straight into the
      // working registers from LC_IDLE, otherwise into the single pending slot,
      // whose data phase then stalls on HREADYOUT=0 until we get to it -- so a
      // second one cannot arrive.
      if (accept) begin
        if (st == LC_IDLE & ~pending & ocmd_ready) begin
          st <= HWRITE ? LC_WFIRST : LC_RDATA;
        end else begin
          nxt_addr <= HADDR[31:0]; nxt_wr <= HWRITE; pending <= 1'b1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  logic was_idle;
  always_ff @(posedge HCLK) was_idle <= (st == LC_IDLE);
  always @(posedge HCLK) if (HRESETn & st == LC_RDATA & was_idle & ibeat_valid)
    $fatal(1, "link core: stale beat in the inbound FIFO at the start of a read -- the two halves disagree about the beat count");

  // The pending slot is single: a second accept while one is pending would mean
  // the pending one's data phase did not stall, which the uncore's HREADY mux
  // makes impossible.
  always_ff @(posedge HCLK) if (HRESETn & accept & pending & st != LC_IDLE)
    $fatal(1, "link core: second pipelined accept");
  // The address goes over whole, so 32 bits is the only constraint left.
  always_ff @(posedge HCLK) if (HRESETn & accept) begin
    assert (HADDR[HADDR_W-1:32] == '0) else $fatal(1, "link core: HADDR above 4 GB: %h", HADDR);
    // The two sides' idea of the burst length, compared.  A line resize that
    // nobody propagated here lands on this line instead of hanging the DUT.
    assert (HBURST == hburst_for(BEATS))
      else $fatal(1, "link core: HBURST %b but BEATS=%0d expects %b -- the link and the cache disagree about the burst length",
                  HBURST, BEATS, hburst_for(BEATS));
    assert (HSIZE == 3'b011 & HADDR[2:0] == 3'b000)
      else $fatal(1, "link core: HSIZE %b at %h is not a full aligned eight-lane beat", HSIZE, HADDR);
  end
  // Writes are never aborted (the D-cache's Flush is tied low); if that changes,
  // junk goes to memory and this is the first thing to fire.
  always_ff @(posedge HCLK) if (HRESETn & wpush & ~beat_ok)
    $fatal(1, "link core: write burst abandoned by the master at beat %0d", bcnt);

  // BEATS=1 would be a one-beat "burst", which on the wire is indistinguishable
  // from an uncached single -- and a single is the one case that needs the
  // {HWSTRB, HSIZE} header word the link does not carry.  Caught at elaboration
  // rather than left to the HBURST assertion, which would also fire but only
  // after the first transaction.
  initial if (BEATS < 2)
    $fatal(1, "link core: BEATS=%0d; the link carries no size and no lane strobes, so it cannot express a single transfer", BEATS);
  // The upper bound is what keeps forte_chip's widening of the FIFO occupancy to
  // DEPTH_W a zero-extend rather than a silent truncation: DEPTH_W is sized for
  // fifo_depth(MAX_BEATS).  MAX_BEATS is also AHB's largest burst, so a build
  // above it could not have a legal HBURST encoding either.
  initial if (BEATS > MAX_BEATS)
    $fatal(1, "link core: BEATS=%0d exceeds MAX_BEATS=%0d; AHB has no burst that long and the occupancy counters are sized for it", BEATS, MAX_BEATS);
`endif

endmodule
