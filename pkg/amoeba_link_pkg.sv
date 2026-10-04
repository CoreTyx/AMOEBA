///////////////////////////////////////////////////////////////////////////////
// amoeba_link_pkg.sv
//
// The off-chip link, in one place.  The ASIC-side bridge (hdl/amoeba_link_master),
// the testbench slave model (hvl/common/amoeba_link_model) and the FPGA slave
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
// INCR8 ONLY.  Every transfer is eight aligned 64-bit beats with all eight
// lanes live, so the link carries no size and no byte strobes.  Measured:
// across the whole ISA regression, 4032 transactions, zero singles -- with
// PERIPH_ONCHIP=1 the only off-chip region is EXT_MEM, which the PMA marks
// cacheable, so every access is a line fill or a writeback.  A single transfer
// used to cost a third header word carrying {HWSTRB, HSIZE}; that path existed
// for a configuration nothing exercises, and untested logic does not go to
// silicon.  `burst` is consequently always 1 -- the pin is kept so a future
// single path needs no pad, not because it carries information today.
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
// an INCR8 read with header words 0x8000, 0x0000, wr=0, burst=1) and `rst_n` is
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
package amoeba_link_pkg;

  localparam int LINK_W          = 16;      // io[LINK_W-1:0]
  localparam int ADDR_WORDS      = 2;       // 32-bit address on a 16-bit bus
  localparam int WORDS_PER_BEAT  = 64 / LINK_W;              // 4
  localparam int BEATS_PER_LINE  = 8;                        // INCR8, AHBW=64
  localparam int WORDS_PER_LINE  = WORDS_PER_BEAT * BEATS_PER_LINE;  // 32
  localparam int TA              = 2;       // turnaround idle cycles per dir change

  // Cycles after a slave deasserts ready in which it must still accept a req:
  // the ASIC's two inbound capture registers plus the START -> HDR0 edge.
  localparam int GUARD = 3;

  // The two FSMs' state encodings live here, not inside their modules, so the
  // testbench can NAME a state instead of numbering it.  hvl/common/
  // amoeba_dut_wrap.sv used to compare `st` against literal integers; adding a
  // state silently repointed every one of them at its neighbour, and the abort
  // injection stopped firing with no error anywhere.
  typedef enum logic [3:0] {
    LM_IDLE, LM_START, LM_HDR0, LM_HDR1,
    LM_WDATA, LM_RD_TA, LM_RD_DATA, LM_RD_TA2
  } link_st_t;

  typedef enum logic [3:0] {
    LS_IDLE, LS_HDR1, LS_WDATA, LS_RD_TA, LS_RD
  } link_slave_st_t;

  // The only HBURST encoding the link can express.
  localparam logic [2:0] HBURST_INCR8  = 3'b101;

endpackage
