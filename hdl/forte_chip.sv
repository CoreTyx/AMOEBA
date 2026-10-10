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
// Bus ownership: forte_link_phy is the only driver.  There is no training FSM
// to arbitrate with -- the core leaves reset as soon as rst_n is released, and
// it is the FPGA that decides when that happens (hdl/forte_link_pkg.sv).
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
  // link
  output logic [LINK_W-1:0] io_o,
  output logic [LINK_W-1:0] io_oe,          // per pad; all == dir in functional mode
  input  logic [LINK_W-1:0] io_i,
  output logic              dir,
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
  // Fault injection enable, straight from the pad.  forte_soc instantiates
  // wallypipelinedcore directly, so leaving this unconnected would drive X into
  // the ECC and FT logic.  One name the whole way down: this started as the
  // ASIC side's rename of ecc_inject_en, and main's #43 renamed their end to
  // the same thing, so there is no longer a translation at any boundary.
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

  logic [LINK_W-1:0] lm_io_o;
  logic              lm_io_oe, lm_dir;

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

  assign reset_ext = ~rst_n_s;

  synchronizer irq0sync(.clk(core_clk), .d(irq[0]),  .q(irq_s[0]));
  synchronizer irq1sync(.clk(core_clk), .d(irq[1]),  .q(irq_s[1]));
  synchronizer rxsync  (.clk(core_clk), .d(uart_rx), .q(uart_rx_s));

  logic dft_unlocked;
  forte_soc #(.P(P), .PERIPH_ONCHIP(PERIPH_ONCHIP)) soc(
    .core_clk, .reset_ext, .reset(reset_soc), .ExternalStall(1'b0), .fault_inject,
    .dft_unlocked,
    .HRDATAEXT, .HREADYEXT, .HRESPEXT, .HSELEXT, .HCLK, .HRESETn,
    .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HBURST, .HPROT, .HTRANS, .HMASTLOCK, .HREADY,
    .UARTSin(uart_rx_s), .UARTSout(uart_tx),
    .ExtIrq(irq_s), .MExtIntIn(irq_s[0]), .SExtIntIn(irq_s[1]));

  // ---- link bridge, across the crossing -------------------------------------
  // core domain          |  link domain
  //   forte_link_core   |
  //     cmd + beats  --> | ofifo --> forte_link_phy --> pads
  //     read beats   <-- | ififo <--      (assembles beats from 16-bit words)
  //
  // The crossing carries transactions and 64-bit beats, never 16-bit link
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
    .clk_wr_i(core_clk), .rst_wr_ni(rst_n_s),
    .wvalid_i(oc_valid), .wready_o(oc_ready), .wdata_i(oc_data), .wdepth_o(oc_depth_unused),
    .clk_rd_i(link_clk), .rst_rd_ni(link_rst_n_s),
    .rvalid_o(op_valid), .rready_i(op_ready), .rdata_o(op_data), .rdepth_o(op_depth));

  prim_fifo_async #(.Width(64), .Depth(LINK_FIFO_D)) ififo(
    .clk_wr_i(link_clk), .rst_wr_ni(link_rst_n_s),
    .wvalid_i(ip_valid), .wready_o(ip_ready), .wdata_i(ip_data), .wdepth_o(ip_depth_unused),
    .clk_rd_i(core_clk), .rst_rd_ni(rst_n_s),
    .rvalid_o(ic_valid), .rready_i(ic_ready), .rdata_o(ic_data), .rdepth_o(ic_depth_unused));

  logic txn_done, lm_busy;
  forte_link_phy #(.BEATS(LINK_BEATS)) phy(
    .link_clk, .link_rst_n(link_rst_n_s),
    .ocmd_valid(op_valid), .ocmd_ready(op_ready), .ocmd_data(op_data), .ocmd_depth(op_depth_w),
    .ibeat_valid(ip_valid), .ibeat_ready(ip_ready), .ibeat_data(ip_data),
    .io_o(lm_io_o), .io_oe(lm_io_oe), .io_i, .dir(lm_dir), .req, .wr, .ready, .rvalid,
    .txn_done, .busy(lm_busy));

  // Occupancy outputs we do not consume.  Sunk rather than left dangling so the
  // synthesis flow does not warn.
  logic unused_depths;
  assign unused_depths = ^{oc_depth_unused, ip_depth_unused, ic_depth_unused};

  // ---- bus ownership and scan mux -------------------------------------------
  // EIGHT PARALLEL SCAN CHAINS EACH WAY (docs/impl_plan_link_clocking.md s11):
  // io[7:0] are scan_in[7:0] and io[15:8] are scan_out[7:0] when test_mode=1.
  // CSRs go on chain 0, registers from the other subsystems on 1..7; shift time
  // is set by the LONGEST chain, so DFT insertion should balance them.
  //
  // The shift clock is core_clk, not a pin.  Standard scan shifts on the
  // functional clock, which the tester already drives through its own pad; a
  // dedicated scan clock would cost two of the sixteen bus pins and leave seven
  // chains each way instead of eight, for nothing.
  //
  // The one-flop chain stubs below reserve the structure; DFT insertion replaces
  // them.  scan_en is qualified with test_mode: on its own it would shift the
  // chains under a running core if it ever glitched in functional mode.
  // ---- DFT lock -------------------------------------------------------------
  // THE PIN AND THE REGISTER ARE AN AND.  hdl/forte_dft_lock.sv is a
  // memory-mapped register that resets to 1 and that boot software clears once
  // it no longer needs scan; with no efuses on this part it is the only thing
  // standing between a booted system and full scan access to every flop,
  // including the register file and the CSRs.  Both pins are qualified, not just
  // scan_en: test_mode on its own remaps the pads, and leaving that reachable
  // would let a locked part still have its bus mapped onto the scan pins.
  //
  // Clearing it is one-way until reset, so there is no software path back to a
  // scannable part.  Reset DOES re-enable DFT -- nothing here is non-volatile --
  // and on this board rst_n is an FPGA output, so this defends against a runtime
  // compromise and not against physical access.  See the header of
  // forte_dft_lock.sv for the rest of the threat model.
  logic test_mode_dft, scan_en_dft;
  assign test_mode_dft = test_mode & dft_unlocked;
  assign scan_en_dft   = scan_en   & dft_unlocked;

  logic [7:0] scan_q;
  always_ff @(posedge core_clk) if (test_mode_dft & scan_en_dft) scan_q <= io_i[7:0];

  // The test-mode override on dir and io_oe is load-bearing, not cosmetic: dir
  // is itself a scanned flop, so during shift it toggles pseudo-randomly, and
  // anything deriving the pad directions from it would reverse all sixteen pads
  // every shift cycle.  In test mode the directions are fixed by the scan
  // mapping instead -- the low half driven in, the high half driven out.
  assign dir   = lm_dir;
  assign io_o  = test_mode_dft ? {scan_q, 8'h00} : lm_io_o;
  assign io_oe = test_mode_dft ? {8'hFF, 8'h00}  : {LINK_W{lm_io_oe}};

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
