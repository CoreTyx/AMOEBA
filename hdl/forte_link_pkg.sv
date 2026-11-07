///////////////////////////////////////////////////////////////////////////////
// forte_link_pkg.sv
//
// The off-chip link, in one place.  The ASIC-side bridge (hdl/forte_link_master),
// the testbench slave model (hvl/common/forte_link_model) and the FPGA slave
// all elaborate against these, so a protocol change is one edit.
//
// The link is two dedicated 8-bit buses, one each way, that carry only
// addresses, attributes and data.  Neither ever changes direction, so there is
// no bus ownership to arbitrate: no dir pin, no tristate enables and no
// turnaround cycles.  Transaction type is on dedicated pins, held for the whole
// transaction, so nothing on either bus is decoded by either side:
//
//   io_out  ASIC -> FPGA
//     req=1, cycles 0..3   io_out = HADDR[31:24], [23:16], [15:8], [7:0]
//     write data           io_out = data byte, a 64-bit beat as 8 bytes, LSB first
//   io_in   FPGA -> ASIC
//     read data            io_in  = data byte when rvalid=1, same packing
//
// The two buses used to be one 16-bit bidirectional bus on io_tri pads, each
// with its own tristate enable, plus a dir pin and two TA idle cycles on every
// change of direction.  Splitting it costs half the bandwidth each way and buys
// back all of that control logic, one pad, and the 2*TA idle cycles every read
// used to pay.
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
// survives the resize.  A single transfer would cost an extra header word
// carrying {HWSTRB, HSIZE}; that path existed for a configuration nothing
// exercises, and untested logic does not go to silicon.  BEATS >= 2 is checked:
// a one-beat line would make a line fill indistinguishable on the wire from an
// uncached single, which is the case that needs the header word.  There is no
// `burst` pin: it would have been tied to 1 for the life of the part, so it cost
// a pad to carry no information, and that pad went to clk_out instead.
//   wr               held from req until the last word
//   ready            see "the ready guard band" below
//   rvalid           read data byte on io_in this cycle; gaps allowed.  The
//                    first may come as soon as the slave has seen the last
//                    header byte: there is no turnaround to wait out.
//
// NO LINK TRAINING.  The ASIC used to drive an LFSR pattern and check an echo
// before releasing the core (docs/impl_plan_link_clocking.md s7).  It does not
// any more: the first fetch is fully determined (RESET_VECTOR = 0x8000_0000, so
// the first read's header bytes are 80 00 00 00 with wr=0) and `rst_n` is
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

  localparam LINK_W          = 8;       // io_in[LINK_W-1:0], io_out[LINK_W-1:0]
  localparam ADDR_WORDS      = 32 / LINK_W;              // 4 header bytes on io_out
  localparam WORDS_PER_BEAT  = 64 / LINK_W;              // 8
  // Beats per transaction is a per-build PARAMETER, not a constant -- see "ONE
  // BURST LENGTH PER BUILD" above.  MAX_BEATS only bounds the widths that have
  // to be fixed at package scope.
  localparam MAX_BEATS       = 16;      // INCR16, the largest AHB burst

  // Cycles after a slave deasserts ready in which it must still accept a req:
  // the ASIC's two inbound capture registers plus the START -> HDR edge.
  localparam GUARD = 3;

  // The two FSMs' state encodings live here, not inside their modules, so the
  // testbench can NAME a state instead of numbering it.  hvl/common/
  // forte_dut_wrap.sv used to compare `st` against literal integers; adding a
  // state silently repointed every one of them at its neighbour, and the abort
  // injection stopped firing with no error anywhere.
  // forte_link_phy, the link domain.
  typedef enum logic [2:0] {
    LM_IDLE, LM_START, LM_HDR, LM_WDATA, LM_RD_DATA
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
  // The crossing deals in transactions and beats, never in 8-bit link words:
  // serialization is a link-domain implementation detail.
  localparam FLIT_W   = 65;

  // The outbound FIFO must hold a whole transaction -- 1 command + BEATS data
  // flits -- because the phy may not start one until all of it is buffered
  // (hdl/forte_link_phy.sv, THE BUFFERING INVARIANT).  One slot beyond that
  // keeps the NEXT command pushable while the current transaction drains, so the
  // AHB side never stalls on a full FIFO.  prim_fifo_async requires a power of
  // two.  At a 128-bit line this is 4 deep, not 16: the old constant was sized
  // for 512-bit lines and was pure area at any smaller one.
  function automatic integer fifo_depth(input integer beats);
    integer d;
    d = 4;
    while (d < beats + 2) d = d * 2;
    return d;
  endfunction

  // prim_fifo_async's own DepthW.  Occupancy runs 0..Depth inclusive, so this is
  // $clog2(Depth+1) and NOT $clog2(Depth).
  function automatic integer fifo_depth_w(input integer depth);
    return $clog2(depth + 1);
  endfunction

  // Width every module uses for an occupancy it compares against BEATS+1,
  // regardless of the FIFO it came from: one width means forte_chip can pad a
  // narrow rdepth_o once instead of every consumer tracking the FIFO's size.
  localparam DEPTH_W = 6;      // fifo_depth_w(fifo_depth(MAX_BEATS)) = 6

  function automatic logic [FLIT_W-1:0] cmd_flit(input logic wr, input logic [31:0] addr);
    return {1'b1, wr, 31'b0, addr};
  endfunction

  function automatic logic [FLIT_W-1:0] dat_flit(input logic [63:0] beat);
    return {1'b0, beat};
  endfunction

  typedef enum logic [1:0] {
    LS_IDLE, LS_HDR, LS_WDATA, LS_RD
  } link_slave_st_t;

  // The HBURST encoding a BEATS-beat cache transaction arrives with.  This is a
  // copy of LocalBurstType in hdl/core/ebu/buscachefsm.sv, which selects on
  // BeatCountThreshold = BEATS-1; any beat count that is not 1, 4, 8 or 16 falls
  // through to INCR-without-end.  Kept as a function rather than a constant
  // because it is the one place the two sides' idea of burst length is compared,
  // and a constant could only ever be right for one line length.
  function automatic logic [2:0] hburst_for(input integer beats);
    case (beats)
      1:       return 3'b000;      // SINGLE
      4:       return 3'b011;      // INCR4
      8:       return 3'b101;      // INCR8
      16:      return 3'b111;      // INCR16
      default: return 3'b001;      // INCR, undefined length
    endcase
  endfunction

endpackage
