///////////////////////////////////////////////////////////////////////////////
// forte_link_pkg.sv
//
// The off-chip link, in one place.  The ASIC-side bridge (hdl/forte_link_master),
// the testbench slave model (hvl/common/forte_link_model) and the FPGA slave
// all elaborate against these, so a protocol change is one edit.
//
// The link is a 16-bit bidirectional bus that carries only addresses,
// attributes and data.  Transaction type is on dedicated pins, held for the
// whole transaction, so nothing on the bus is decoded by either side:
//
//   req=1, cycle 0   io = HADDR[31:16]   the full address; no bits are stolen
//   req=1, cycle 1   io = HADDR[15:0]
//   otherwise        io = data word      64-bit beat as 4 words, LSW first
//
// ONE BURST LENGTH PER BUILD.  Every transfer is BEATS aligned 64-bit beats
// with all eight lanes live, so the link carries no size and no byte strobes.
// BEATS is not a constant here: it is
//
//     BEATS = DCACHE_LINELENINBITS / AHBW
//
// evaluated in hdl/forte_chip.sv, which is the only module that sees both the
// core config and the link, and threaded as a parameter to forte_link_core,
// forte_link_phy and the testbench slave.  It is NOT a package localparam
// because the package cannot include config.vh without dropping the whole Wally
// parameter set into forte_link_pkg::* and colliding with cvw::*.
//
// The link used to hardcode INCR8, which was true at a 512-bit line and became
// silently false when the line shrank to 128 bits for area: at AHBW=64 that is
// two beats, so buscachefsm emits HBURST=3'b001 (INCR, undefined length) rather
// than INCR8, and the core and the link disagreed about how many beats a
// transaction has.  Nothing asserted -- the DUT just hung on the second
// transaction.  hburst_for() below is the mirror of buscachefsm's LocalBurstType
// so that disagreement is now an elaboration-time or first-transaction failure.
//
// Measured at a 512-bit line: across the whole ISA regression, 4032
// transactions, zero singles -- with PERIPH_ONCHIP=1 the only off-chip region is
// EXT_MEM, which the PMA marks cacheable, so every access is a line fill or a
// writeback.  That is a property of the PMA, not of the line length, so it
// survives the resize.  A single transfer would cost a third header word
// carrying {HWSTRB, HSIZE}; that path existed for a configuration nothing
// exercises, and untested logic does not go to silicon.  BEATS >= 2 is checked:
// a one-beat line would make a line fill indistinguishable on the wire from an
// uncached single, which is the case that needs the header word.  `burst` is
// consequently always 1 -- the pin is kept so a future single path needs no pad,
// not because it carries information today.
//   wr, burst        held from req until the last word
//   ready            see "the ready guard band" below
//   rvalid           read data word on io this cycle; gaps allowed
//   dir              1 = ASIC drives io, 0 = ASIC has released it; the single
//                    source of truth for bus ownership.  TA idle cycles are
//                    guaranteed by the ASIC on every change.
//
// NO LINK TRAINING.  The ASIC used to drive an LFSR pattern and check an echo
// before releasing the core (docs/impl_plan_link_clocking.md s7).  It does not
// any more: the first fetch is fully determined (RESET_VECTOR = 0x8000_0000, so
// the first read's header words are 0x8000, 0x0000 with wr=0, burst=1) and `rst_n` is
// an FPGA output, so the FPGA releases the core, checks that header, and
// re-asserts reset within microseconds if it is wrong.  The gate moved to the
// side with a CPU, Python and an ILA instead of a one-bit status pin.
//
// THE READY GUARD BAND.  `ready` means "I have room for a whole transaction,
// and one more in reserve".  It is advisory, not a handshake: the ASIC samples
// it through two input registers and asserts req a cycle later, so a req may
// legally arrive up to GUARD cycles after the slave dropped ready.  A slave
// must therefore deassert ready while it still has room for one more
// transaction -- never when it is actually full.  Sizing for two outstanding
// lines instead of one removes the race entirely, which is what the testbench
// model does and what the FPGA slave must do.
//
// See docs/top_level_plan.md s4.
///////////////////////////////////////////////////////////////////////////////
package forte_link_pkg;

  localparam int LINK_W          = 16;      // io[LINK_W-1:0]
  localparam int ADDR_WORDS      = 2;       // 32-bit address on a 16-bit bus
  localparam int WORDS_PER_BEAT  = 64 / LINK_W;              // 4
  // Beats per transaction is a per-build PARAMETER, not a constant -- see "ONE
  // BURST LENGTH PER BUILD" above.  MAX_BEATS only bounds the widths that have
  // to be fixed at package scope.
  localparam int MAX_BEATS       = 16;      // INCR16, the largest AHB burst
  localparam int TA              = 2;       // turnaround idle cycles per dir change

  // Cycles after a slave deasserts ready in which it must still accept a req:
  // the ASIC's two inbound capture registers plus the START -> HDR0 edge.
  localparam int GUARD = 3;

  // The two FSMs' state encodings live here, not inside their modules, so the
  // testbench can NAME a state instead of numbering it.  hvl/common/
  // forte_dut_wrap.sv used to compare `st` against literal integers; adding a
  // state silently repointed every one of them at its neighbour, and the abort
  // injection stopped firing with no error anywhere.
  // forte_link_phy, the link domain.
  typedef enum logic [3:0] {
    LM_IDLE, LM_START, LM_HDR0, LM_HDR1,
    LM_WDATA, LM_RD_TA, LM_RD_DATA, LM_RD_TA2
  } link_st_t;

  // forte_link_core, the core domain.
  typedef enum logic [1:0] { LC_IDLE, LC_WFIRST, LC_WDATA, LC_RDATA } link_core_st_t;

  // The flit crossing between them.  Width is set by the DATA flits -- one
  // 64-bit AHB beat -- so the command rides free in a slot that exists anyway;
  // its 31 reserved bits cost nothing.
  //
  //   command flit  [64] is_cmd=1 | [63] wr | [62:32] reserved | [31:0] addr
  //   data flit     [64] is_cmd=0 | [63:0] one 64-bit beat
  //
  // The crossing deals in transactions and beats, never in 16-bit link words:
  // serialization is a link-domain implementation detail.
  localparam int FLIT_W   = 65;

  // The outbound FIFO must hold a whole transaction -- 1 command + BEATS data
  // flits -- because the phy may not start one until all of it is buffered
  // (hdl/forte_link_phy.sv, THE BUFFERING INVARIANT).  One slot beyond that
  // keeps the NEXT command pushable while the current transaction drains, so the
  // AHB side never stalls on a full FIFO.  prim_fifo_async requires a power of
  // two.  At a 128-bit line this is 4 deep, not 16: the old constant was sized
  // for 512-bit lines and was pure area at any smaller one.
  function automatic int fifo_depth(input int beats);
    int d;
    d = 4;
    while (d < beats + 2) d = d * 2;
    return d;
  endfunction

  // prim_fifo_async's own DepthW.  Occupancy runs 0..Depth inclusive, so this is
  // $clog2(Depth+1) and NOT $clog2(Depth).
  function automatic int fifo_depth_w(input int depth);
    return $clog2(depth + 1);
  endfunction

  // Width every module uses for an occupancy it compares against BEATS+1,
  // regardless of the FIFO it came from: one width means forte_chip can pad a
  // narrow rdepth_o once instead of every consumer tracking the FIFO's size.
  localparam int DEPTH_W = 6;      // fifo_depth_w(fifo_depth(MAX_BEATS)) = 6

  function automatic logic [FLIT_W-1:0] cmd_flit(input logic wr, input logic [31:0] addr);
    return {1'b1, wr, 31'b0, addr};
  endfunction

  function automatic logic [FLIT_W-1:0] dat_flit(input logic [63:0] beat);
    return {1'b0, beat};
  endfunction

  typedef enum logic [3:0] {
    LS_IDLE, LS_HDR1, LS_WDATA, LS_RD_TA, LS_RD
  } link_slave_st_t;

  // The HBURST encoding a BEATS-beat cache transaction arrives with.  This is a
  // copy of LocalBurstType in hdl/core/ebu/buscachefsm.sv, which selects on
  // BeatCountThreshold = BEATS-1; any beat count that is not 1, 4, 8 or 16 falls
  // through to INCR-without-end.  Kept as a function rather than a constant
  // because it is the one place the two sides' idea of burst length is compared,
  // and a constant could only ever be right for one line length.
  function automatic logic [2:0] hburst_for(input int beats);
    case (beats)
      1:       return 3'b000;      // SINGLE
      4:       return 3'b011;      // INCR4
      8:       return 3'b101;      // INCR8
      16:      return 3'b111;      // INCR16
      default: return 3'b001;      // INCR, undefined length
    endcase
  endfunction

endpackage
