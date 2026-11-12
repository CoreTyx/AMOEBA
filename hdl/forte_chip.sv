///////////////////////////////////////////////////////////////////////////////
// forte_chip.sv
//
// The die minus its pads: two reset synchronisers, the SoC, the link bridge
// across a clock-domain crossing, the scan mux.  This is the boundary DFT
// insertion and gate-level simulation see.  forte_top adds the pad cells.
//
// TWO CLOCK DOMAINS (docs/impl_plan_link_clocking.md s4).  core_clk runs the
// core and the AHB side of the bridge; link_clk runs the pin side.  The reason
// is not frequency -- they are the same frequency today -- it is that the
// packaging is non-standard, so pad and package parasitics and the uncertainty
// on them are uncharacterised, and a small capture domain next to the pads buys
// margin that does not depend on knowing those numbers.
//
// forte_top ties link_clk to the single core_clk pad.  The port exists at THIS
// level so a testbench can drive the two domains at a non-integer ratio: with
// one clock port, RTL simulation sees zero skew between the domains and the
// Gray-coded pointer logic in the FIFOs is never exercised at all.
//
// The link is two one-way buses, so there is no bus ownership to manage:
// forte_link_phy drives io_o and the FPGA drives io_i, always.  There is no
// training FSM either -- the core leaves reset as soon as rst_n is released,
// and it is the FPGA that decides when that happens (hdl/forte_link_pkg.sv).
//
// THE BURST LENGTH IS DECIDED HERE.  This is the only module that sees both the
// core config and the link, so it is where DCACHE_LINELENINBITS / AHBW becomes
// the link's beat count, and it threads that one expression to both halves of
// the bridge and to the FIFO sizing.  Nothing downstream hardcodes 8 any more:
// the link was INCR8-only, which was correct at a 512-bit line and became
// quietly wrong when the line shrank to 128 bits for area.  See "ONE BURST
// LENGTH PER BUILD" in hdl/forte_link_pkg.sv.
///////////////////////////////////////////////////////////////////////////////

`include "../pkg/config.vh"

module forte_chip import cvw::*; import forte_link_pkg::*; #(
  parameter logic PERIPH_ONCHIP = 1'b1,
  // status blink rates, as taps on a free-running link-domain counter.  status
  // is a square wave off tick[N], so its frequency is f_link / 2**(N+1).  At
  // 100 MHz: 23 -> 5.96 Hz, 25 -> 1.49 Hz, 27 -> 0.37 Hz.  Roughly 6 / 1.5 /
  // 0.4 Hz, spread about 4x apart so the three are told apart at a glance
  // rather than by timing them.  Parameters, not constants, because the real
  // frequency is not settled and because a testbench has to be able to shrink
  // them -- nothing can observe a 0.4 Hz blink in a simulation.
  parameter STATUS_FAST_BIT  = 23,      // stalled
  parameter STATUS_ACT_BIT   = 25,      // active
  parameter STATUS_SLOW_BIT  = 27,      // quiet; also sizes the counter
  // "nothing has completed recently" threshold: 2**N link cycles, 1.31 ms at
  // 100 MHz.  Long enough that an ordinary gap in traffic is not a stall.
  parameter STATUS_IDLE_BITS = 17
)(
  input  logic              core_clk,
  input  logic              link_clk,       // tied to the core_clk pad in forte_top
  input  logic              rst_n,
  // link: io_o drives the io_out pads, io_i comes from the io_in pads
  output logic [LINK_W-1:0] io_o,
  input  logic [LINK_W-1:0] io_i,
  output logic              req,
  output logic              wr,
  input  logic              ready,
  input  logic              rvalid,
  // Forwarded LINK clock, for the FPGA to capture inbound io with
  // (docs/impl_plan_link_clocking.md s6.1).  It must be the LINK clock and not
  // core_clk: the io output registers live in the link domain, so forwarding
  // core_clk would have the FPGA capturing link-domain data with a
  // core-domain clock, which cancels nothing.
  output logic              clk_out,
  // interrupts, console
  input  logic [1:0]        irq,            // PERIPH_ONCHIP=1: PLIC sources; =0: meip, seip
  output logic              uart_tx,
  input  logic              uart_rx,
  // test
  input  logic              test_mode,
  input  logic              scan_en,
  // Fault-injection master enable from the pad, synchronised below. The core
  // applies the per-unit software mask at MMIO 0x1007_000b and registers the
  // result before driving ECC and FT injectors.
  input  logic              fault_inject,
  // status
  output logic              status
);

  `include "../pkg/parameter-defs.vh"

  // ---- link geometry, from the core config ----------------------------------
  // A cache line is moved as LINK_BEATS AHBW-wide beats, which is exactly what
  // buscachefsm's BeatCountThreshold counts, so this is the burst length the
  // link sees.  The I-cache and D-cache must agree: the link commits to one
  // length for every transaction, and there is no field on the wire to say
  // otherwise.
  localparam LINK_BEATS  = P.DCACHE_LINELENINBITS / P.AHBW;
  localparam LINK_FIFO_D = fifo_depth(LINK_BEATS);
  localparam LINK_FIFO_W = fifo_depth_w(LINK_FIFO_D);

  // ---- reset ----------------------------------------------------------------
  // One pad, one synchroniser per domain: asserted asynchronously to both,
  // released synchronously in each.  Releasing a single synchronised reset
  // asynchronously into both sides of an async FIFO can leave its two pointers
  // mutually inconsistent, which is the classic failure of that structure
  // (third_party/opentitan/README.md).
  logic rst_n_s, link_rst_n_s;
  forte_rst_sync rstsync    (.clk(core_clk), .rst_n_in(rst_n), .rst_n_out(rst_n_s));
  forte_rst_sync linkrstsync(.clk(link_clk), .rst_n_in(rst_n), .rst_n_out(link_rst_n_s));

  // ---- DFT HOLD: test-mode control and the two root clock gates -------------
  // A DFT session can stop the chip anywhere in a running program, unload every
  // scan chain on io_out, load the same bits back on io_in, leave test mode and
  // let the program carry on as if nothing had happened.  For that, test mode
  // has to freeze EVERY piece of state that is not on a scan chain, and the
  // scan cells must move only when they shift.  A pipeline stall cannot do it:
  // traps, flushes, the regfile write port, the cache and bus FSMs, the
  // divider, the FT checkers, LFSRs, MTIME and the UART all keep running while
  // the pipeline is stalled, and synthesis adds clock gates whose test enable
  // forces their flops to clock on every shift cycle.  That is why
  // ExternalStall stays tied off below.  The hold is a CLOCK SPLIT instead:
  //
  //   core_clk -+- tmsync, sesync, hold_mode, the reset synchronisers
  //             |    (ungated; never on a chain)
  //             +- cg_ns   (en ~hold, te 0)           -> clk_ns
  //             |    everything else in the core-clock domain: forte_soc
  //             |    (core, caches and their SRAMs, regfile, CSRs, uncore),
  //             |    the AHB side of the link, the FIFOs' core-side ports,
  //             |    the irq/uart/fault_inject synchronisers
  //             +- cg_scan (en ~hold, te scan_en_dft) -> clk_scan
  //                  only the scan-selected registers (synth/dft_setup.tcl's
  //                  groups on the dft branch; that list and the clk_scan
  //                  wiring in hdl/core must match, and the DFT flow checks it)
  //
  // Outside a hold both gates pass every edge, so functional behaviour, and
  // legacy test mode, are exactly what they were.  Inside a hold, clk_ns has no
  // edges at all, so nothing that is not on a chain can change whatever the
  // chains hold, and clk_scan pulses only on scan_en=1 edges, so the scan cells
  // shift and otherwise hold (no capture, no ECC self-repair).  A scan_en=0
  // edge in a hold changes nothing on core_clk except the ungated flops above.
  //
  // HOLD MODE IS CHOSEN AT ENTRY, BY SCAN_EN.  Existing test-mode users (the
  // full_tb capture phases, ATPG) need a scan_en=0 edge to be a functional
  // capture, so a hold cannot simply be "test mode".  hold_mode samples the
  // synchronised scan_en on every edge while test_mode_s is 0 and freezes when
  // test_mode_s rises, so it holds what scan_en was on the edge before test_mode
  // rose.  The two synchronisers are the same depth, so for pins driven on the
  // same tester cycle the alignment is exact:
  //
  //   arm     scan_en=1, test_mode=0, >= 3 cycles  (no effect: scan_en_dft is
  //                                                 qualified by test mode)
  //   enter   test_mode=1, scan_en=0, 3 cycles     edges 1-2 are functional
  //                                                 (tmsync lag, as before);
  //                                                 frozen from edge 3 on
  //   unload/reload  scan_en=1 per shift
  //   exit    test_mode=0, 3 cycles                edges 1-2 still frozen;
  //                                                 edge 3 is functional again
  //
  // test_mode raised with scan_en low is legacy test mode, unchanged.  The full
  // tester protocol (padding, inversion) is in synth/scripts/HANDOFF.md on dft.
  //
  // THE LINK IS NOT FROZEN.  It is a separate clock domain and the tester only
  // enters a hold while the link is quiet (no transaction in flight, ready and
  // rvalid low).  As a guard, the phy treats ready and rvalid as low while
  // hold_link is set, so it cannot start a transaction or take io_in (which
  // carries scan data) and req/wr stay low; its status heartbeat keeps running
  // by design.  A hold that catches a transaction in flight breaks it.
  //
  // WHAT IS STRETCHED, NOT FROZEN.  Pins keep their last value: a UART byte in
  // flight on uart_tx is stretched (the receiver sees a framing error), and an
  // irq or uart_rx edge during the hold is seen when it ends.  MTIME stops, so
  // the session is invisible to software that reads time.
  //
  // DFT: tmsync, sesync, hold_mode and holdlinksync must stay OFF the chains,
  // and DRC is told hold_mode is 0 in test (legacy protocol), as test_mode_s and
  // dft_unlocked are told they are 1.  cg_ns/cg_scan keep their TE wiring.
  logic dft_unlocked;
  logic test_mode_s, scan_en_s;
  logic test_mode_dft, scan_en_dft;
  logic hold_mode, hold, hold_link;
  logic clk_ns, clk_scan;

  synchronizer tmsync(.clk(core_clk), .d(test_mode), .q(test_mode_s));
  synchronizer sesync(.clk(core_clk), .d(scan_en),   .q(scan_en_s));

  // test_mode is synchronised, scan_en is not (see the scan mux below), so
  // scan_en_dft follows the pin directly but only inside test mode: a stray
  // scan_en in functional mode must not shift the chains under a running core.
  assign test_mode_dft = test_mode_s & dft_unlocked;
  assign scan_en_dft   = scan_en & test_mode_dft;

  // No reset: it is rewritten on every edge outside test mode.
  always_ff @(posedge core_clk)
    if (!test_mode_s) hold_mode <= scan_en_s;

  assign hold = test_mode_dft & hold_mode;

  forte_clk_gate cg_ns  (.clk(core_clk), .en(~hold), .te(1'b0),        .gclk(clk_ns));
  forte_clk_gate cg_scan(.clk(core_clk), .en(~hold), .te(scan_en_dft), .gclk(clk_scan));

  prim_flop_2sync #(.Width(1)) holdlinksync(
    .clk_i(link_clk), .rst_ni(link_rst_n_s), .d_i(hold), .q_o(hold_link));

  logic [LINK_W-1:0] lm_io_o;

  // ---- SoC ------------------------------------------------------------------
  logic              reset_soc, reset_ext;
  logic [P.AHBW-1:0] HRDATAEXT;
  logic              HREADYEXT, HRESPEXT, HSELEXT, HCLK, HRESETn;
  logic [P.PA_BITS-1:0] HADDR;
  logic [P.AHBW-1:0] HWDATA;
  logic [P.XLEN/8-1:0] HWSTRB;
  logic              HWRITE, HMASTLOCK, HREADY;
  logic [2:0]        HSIZE, HBURST;
  logic [3:0]        HPROT;
  logic [1:0]        HTRANS;
  logic [1:0]        irq_s;
  logic              uart_rx_s;
  logic              fault_inject_s;

  assign reset_ext = ~rst_n_s;

  synchronizer irq0sync(.clk(clk_ns), .d(irq[0]),  .q(irq_s[0]));
  synchronizer irq1sync(.clk(clk_ns), .d(irq[1]),  .q(irq_s[1]));
  synchronizer rxsync  (.clk(clk_ns), .d(uart_rx), .q(uart_rx_s));
  // fault_inject is a board-level strap with no timing relationship to
  // core_clk, and it gates logic on every protected datapath in the core.
  synchronizer fisync  (.clk(clk_ns), .d(fault_inject), .q(fault_inject_s));

  // ExternalStall stays tied off: a stall is not a hold (see DFT HOLD above).
  forte_soc #(.P(P), .PERIPH_ONCHIP(PERIPH_ONCHIP)) soc(
    .core_clk(clk_ns), .clk_scan, .reset_ext, .reset(reset_soc), .ExternalStall(1'b0),
    .fault_inject(fault_inject_s),
    .dft_unlocked,
    .HRDATAEXT, .HREADYEXT, .HRESPEXT, .HSELEXT, .HCLK, .HRESETn,
    .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HBURST, .HPROT, .HTRANS, .HMASTLOCK, .HREADY,
    .UARTSin(uart_rx_s), .UARTSout(uart_tx),
    .ExtIrq(irq_s), .MExtIntIn(irq_s[0]), .SExtIntIn(irq_s[1]));

  // ---- link bridge, across the crossing -------------------------------------
  // core domain          |  link domain
  //   forte_link_core   |
  //     cmd + beats  --> | ofifo --> forte_link_phy --> pads
  //     read beats   <-- | ififo <--      (assembles beats from 8-bit words)
  //
  // The crossing carries transactions and 64-bit beats, never 8-bit link
  // words: serialization is a link-domain implementation detail.
  logic                oc_valid, oc_ready;     // core -> ofifo (write side)
  logic [FLIT_W-1:0]   oc_data;
  logic                op_valid, op_ready;     // ofifo -> phy  (read side)
  logic [FLIT_W-1:0]   op_data;
  logic [LINK_FIFO_W-1:0] op_depth;            // load-bearing: see the phy
  logic [LINK_FIFO_W-1:0] oc_depth_unused;

  logic                ip_valid, ip_ready;     // phy -> ififo  (write side)
  logic [63:0]         ip_data;
  logic                ic_valid, ic_ready;     // ififo -> core (read side)
  logic [63:0]         ic_data;
  logic [LINK_FIFO_W-1:0] ip_depth_unused, ic_depth_unused;

  // The phy takes one fixed occupancy width (DEPTH_W) whatever the FIFO's own
  // DepthW is, so the padding happens once, here, instead of the phy having to
  // know how deep the FIFO it is reading happens to be.
  logic [DEPTH_W-1:0]  op_depth_w;
  assign op_depth_w = DEPTH_W'(op_depth);

  forte_link_core #(.HADDR_W(P.PA_BITS), .BEATS(LINK_BEATS)) linkcore(
    .HCLK, .HRESETn,
    .HSEL(HSELEXT), .HADDR, .HTRANS, .HWRITE, .HSIZE, .HBURST, .HWDATA, .HREADY,
    .HRDATA(HRDATAEXT), .HREADYOUT(HREADYEXT), .HRESP(HRESPEXT),
    .ocmd_valid(oc_valid), .ocmd_ready(oc_ready), .ocmd_data(oc_data),
    .ibeat_valid(ic_valid), .ibeat_ready(ic_ready), .ibeat_data(ic_data));

  prim_fifo_async #(.Width(FLIT_W), .Depth(LINK_FIFO_D)) ofifo(
    .clk_wr_i(clk_ns), .rst_wr_ni(rst_n_s),
    .wvalid_i(oc_valid), .wready_o(oc_ready), .wdata_i(oc_data), .wdepth_o(oc_depth_unused),
    .clk_rd_i(link_clk), .rst_rd_ni(link_rst_n_s),
    .rvalid_o(op_valid), .rready_i(op_ready), .rdata_o(op_data), .rdepth_o(op_depth));

  prim_fifo_async #(.Width(64), .Depth(LINK_FIFO_D)) ififo(
    .clk_wr_i(link_clk), .rst_wr_ni(link_rst_n_s),
    .wvalid_i(ip_valid), .wready_o(ip_ready), .wdata_i(ip_data), .wdepth_o(ip_depth_unused),
    .clk_rd_i(clk_ns), .rst_rd_ni(rst_n_s),
    .rvalid_o(ic_valid), .rready_i(ic_ready), .rdata_o(ic_data), .rdepth_o(ic_depth_unused));

  logic txn_done, lm_busy;
  forte_link_phy #(.BEATS(LINK_BEATS)) phy(
    .link_clk, .link_rst_n(link_rst_n_s),
    .ocmd_valid(op_valid), .ocmd_ready(op_ready), .ocmd_data(op_data), .ocmd_depth(op_depth_w),
    .ibeat_valid(ip_valid), .ibeat_ready(ip_ready), .ibeat_data(ip_data),
    .io_o(lm_io_o), .io_i, .req, .wr, .ready, .rvalid,
    .txn_done, .busy(lm_busy), .hold(hold_link));

  // Occupancy outputs we do not consume.  Sunk rather than left dangling so the
  // synthesis flow does not warn.
  logic unused_depths;
  assign unused_depths = ^{oc_depth_unused, ip_depth_unused, ic_depth_unused};

  // ---- scan mux -------------------------------------------------------------
  // EIGHT PARALLEL SCAN CHAINS EACH WAY (docs/impl_plan_link_clocking.md s11):
  // io_in[7:0] are scan_in[7:0] and io_out[7:0] are scan_out[7:0] when
  // test_mode=1.  The pads already point the right way for that, so test mode
  // only changes what drives io_o, never a pad's direction.
  // CSRs go on chain 0, registers from the other subsystems on 1..7; shift time
  // is set by the LONGEST chain, so DFT insertion should balance them.
  //
  // The shift clock is core_clk, not a pin.  Standard scan shifts on the
  // functional clock, which the tester already drives through its own pad; a
  // dedicated scan clock would cost a link pin and leave seven chains one way
  // instead of eight, for nothing.
  //
  // The one-flop chain stubs below reserve the structure; DFT insertion replaces
  // them.  scan_en is qualified with test_mode (scan_en_dft, in DFT HOLD above):
  // on its own it would shift the chains under a running core if it ever
  // glitched in functional mode.
  // ---- DFT lock -------------------------------------------------------------
  // THE PIN AND THE REGISTER ARE AN AND.  hdl/forte_dft_lock.sv is a
  // memory-mapped register that resets to 1 and that boot software clears once
  // it no longer needs scan; with no efuses on this part it is the only thing
  // standing between a booted system and full scan access to every flop,
  // including the register file and the CSRs.  Both pins are qualified, not just
  // scan_en: test_mode on its own puts the scan chains on io_out, and leaving
  // that reachable would let a locked part still drive its scan-out pins.
  //
  // Clearing it is one-way until reset, so there is no software path back to a
  // scannable part.  Reset DOES re-enable DFT -- nothing here is non-volatile --
  // and on this board rst_n is an FPGA output, so this defends against a runtime
  // compromise and not against physical access.  See the header of
  // forte_dft_lock.sv for the rest of the threat model.
  //
  // TEST_MODE IS SYNCHRONISED; SCAN_EN IS NOT.  test_mode is a board strap with
  // no timing relationship to core_clk (the SDC false-paths it), and it selects
  // what drives the io_out pads.  Raw, any noise on the pin reached the link
  // outputs between clock edges and could go metastable in scan_q's enable.
  // Through two flops it can change only on a core_clk edge.  It is static for a
  // whole test session, so the two-cycle lag costs nothing.  Two things it does
  // NOT do: hold a floating pin low (the pad has no pull; the board must strap
  // it), or reset -- rst_n is a DFT reset that ATPG may pulse mid-test, and that
  // must not drop test mode.  The flops come up random for two cycles after the
  // clock starts, which is inside rst_n on any sane bring-up.
  //
  // scan_en cannot take the same treatment: the tester toggles it between shift
  // and capture, and two cycles of lag would shift on the capture cycle.  (A
  // synchronised copy, scan_en_s, is used only to pick hold mode at entry.)
  //
  // DFT: the tmsync flops must stay OFF the scan chains (shifting them would
  // drop test mode mid-shift), and DRC must be told their output is 1 in test,
  // as it is for the dft_lock flop.
  // tmsync, test_mode_dft and scan_en_dft are declared in DFT HOLD above.

  logic [LINK_W-1:0] scan_q;
  always_ff @(posedge core_clk) if (test_mode_dft & scan_en_dft) scan_q <= io_i;

  // There used to be a test-mode override on the pad directions here, because
  // dir was itself a scanned flop and would have reversed every pad on every
  // shift cycle.  With dedicated io_in / io_out pads there is no direction to
  // protect: test mode only selects what io_out carries.
  assign io_o = test_mode_dft ? scan_q : lm_io_o;

  // ---- status: three distinguishable rates, never frozen ---------------------
  // In the LINK domain: txn_done and busy are the phy's, and counting them in
  // the core domain would need a crossing for a signal whose only consumer is an
  // LED.  status leaves the die straight from here -- one slow signal with no
  // coherency requirement, so no synchroniser is owed.
  //
  // WHAT WAS WRONG BEFORE.  status used to be a tap on a counter of completed
  // transactions, so the blink was driven only by traffic and the pin FROZE
  // whenever nothing completed.  That made the two states you most need to tell
  // apart during bring-up -- the core halted or spinning in cache, and the link
  // wedged mid-transaction -- produce exactly the same picture, and a frozen pin
  // is also indistinguishable from a very slow blink.
  //
  // Now the blink always comes from a free-running counter and only its RATE is
  // modulated, so "never frozen" is structural rather than a hope:
  //
  //   stalled   phy busy and nothing has completed for 2**STATUS_IDLE_BITS
  //             cycles -- a transaction started and did not finish
  //   active    something completed recently
  //   quiet     phy idle and nothing has completed recently -- alive, no traffic
  //
  // A dead link_clk still freezes it, which is the one case this cannot cover;
  // clk_out is the instrument for that (docs/impl_plan_link_clocking.md s6.1)
  // and is strictly better at it, which is why status does not also try.
  logic [STATUS_SLOW_BIT:0] tick;
  always_ff @(posedge link_clk or negedge link_rst_n_s)
    if (!link_rst_n_s) tick <= '0;
    else               tick <= tick + 1'b1;

  // Saturating: clears on every completion, otherwise counts up and sticks at
  // all-ones.  Saturating rather than wrapping matters -- a wrapping counter
  // would drop out of the stalled indication periodically while still wedged.
  logic [STATUS_IDLE_BITS-1:0] quiet_cnt;
  logic                        quiet_max;
  assign quiet_max = (quiet_cnt == {STATUS_IDLE_BITS{1'b1}});
  always_ff @(posedge link_clk or negedge link_rst_n_s)
    if (!link_rst_n_s)    quiet_cnt <= '0;
    else if (txn_done)    quiet_cnt <= '0;
    else if (!quiet_max)  quiet_cnt <= quiet_cnt + 1'b1;

  assign status = quiet_max ? (lm_busy ? tick[STATUS_FAST_BIT]    // stalled
                                       : tick[STATUS_SLOW_BIT])   // quiet
                            : tick[STATUS_ACT_BIT];               // active

  // ---- clk_out --------------------------------------------------------------
  // THE VALUE OF THIS PIN IS IN THE CLOCK TREE, NOT HERE.  In RTL it is just the
  // link clock on a port.  What makes it useful is where CTS taps it: it has to
  // come off the link tree at the SAME depth as the phy's io output registers,
  // because the whole point is that the pad and insertion delay common to both
  // cancels on the ASIC->FPGA path.  Tapped at the wrong depth it is merely a
  // clock on a pin and the FPGA has to treat the link as asynchronous again.
  //
  // Option 3 makes that nearly free -- this driver and the io flops are both
  // inside the small link domain, a few hundred microns apart, so the skew is
  // bounded by placement rather than by constraint (s6.1).
  //
  // Needs a create_generated_clock on the port in the SDC, which does not exist
  // yet (s10).  It is also the best bring-up instrument on the chip: scope it
  // and you know the die is receiving and distributing a clock before anything
  // else has to work.
  assign clk_out = link_clk;

`ifndef SYNTHESIS
  // One length for every transaction, so a build whose two caches disagree has
  // no correct LINK_BEATS at all.  Checked here rather than left to the HBURST
  // assertion in forte_link_core, which would catch only whichever cache went
  // second.
  initial if (P.ICACHE_LINELENINBITS != P.DCACHE_LINELENINBITS)
    $fatal(1, "forte_chip: ICACHE line %0d b != DCACHE line %0d b; the link carries one burst length for both",
           P.ICACHE_LINELENINBITS, P.DCACHE_LINELENINBITS);
`endif

endmodule
