///////////////////////////////////////////////////////////////////////////////
// amoeba_chip.sv
//
// The die minus its pads: two reset synchronisers, the SoC, the link bridge
// across a clock-domain crossing, the scan mux.  This is the boundary DFT
// insertion and gate-level simulation see.  amoeba_top adds the pad cells.
//
// TWO CLOCK DOMAINS (docs/impl_plan_link_clocking.md s4).  core_clk runs the
// core and the AHB side of the bridge; link_clk runs the pin side.  The reason
// is not frequency -- they are the same frequency today -- it is that the
// packaging is non-standard, so pad and package parasitics and the uncertainty
// on them are uncharacterised, and a small capture domain next to the pads buys
// margin that does not depend on knowing those numbers.
//
// amoeba_top ties link_clk to the single core_clk pad.  The port exists at THIS
// level so a testbench can drive the two domains at a non-integer ratio: with
// one clock port, RTL simulation sees zero skew between the domains and the
// Gray-coded pointer logic in the FIFOs is never exercised at all.
//
// Bus ownership: amoeba_link_phy is the only driver.  There is no training FSM
// to arbitrate with -- the core leaves reset as soon as rst_n is released, and
// it is the FPGA that decides when that happens (pkg/amoeba_link_pkg.sv).
///////////////////////////////////////////////////////////////////////////////

`include "amoeba_config_select.vh"

module amoeba_chip import cvw::*; import amoeba_link_pkg::*; #(
  parameter logic PERIPH_ONCHIP = 1'b1,
  parameter HB_BIT        = 15          // status heartbeat: link-transaction counter tap
)(
  input  logic              core_clk,
  input  logic              link_clk,       // tied to the core_clk pad in amoeba_top
  input  logic              rst_n,
  // link
  output logic [LINK_W-1:0] io_o,
  output logic [LINK_W-1:0] io_oe,          // per pad; all == dir in functional mode
  input  logic [LINK_W-1:0] io_i,
  output logic              dir,
  output logic              req,
  output logic              wr,
  output logic              burst,
  input  logic              ready,
  input  logic              rvalid,
  // interrupts, console
  input  logic [1:0]        irq,            // PERIPH_ONCHIP=1: PLIC sources; =0: meip, seip
  output logic              uart_tx,
  input  logic              uart_rx,
  // test
  input  logic              test_mode,
  input  logic              scan_en,
  // status
  output logic              status
);

  `include "parameter-defs.vh"

  // ---- reset ----------------------------------------------------------------
  // One pad, one synchroniser per domain: asserted asynchronously to both,
  // released synchronously in each.  Releasing a single synchronised reset
  // asynchronously into both sides of an async FIFO can leave its two pointers
  // mutually inconsistent, which is the classic failure of that structure
  // (third_party/opentitan/README.md).
  logic rst_n_s, link_rst_n_s;
  amoeba_rst_sync rstsync    (.clk(core_clk), .rst_n_in(rst_n), .rst_n_out(rst_n_s));
  amoeba_rst_sync linkrstsync(.clk(link_clk), .rst_n_in(rst_n), .rst_n_out(link_rst_n_s));

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

  amoeba_soc #(.P(P), .PERIPH_ONCHIP(PERIPH_ONCHIP)) soc(
    .core_clk, .reset_ext, .reset(reset_soc), .ExternalStall(1'b0),
    .HRDATAEXT, .HREADYEXT, .HRESPEXT, .HSELEXT, .HCLK, .HRESETn,
    .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HBURST, .HPROT, .HTRANS, .HMASTLOCK, .HREADY,
    .UARTSin(uart_rx_s), .UARTSout(uart_tx),
    .ExtIrq(irq_s), .MExtIntIn(irq_s[0]), .SExtIntIn(irq_s[1]));

  // ---- link bridge, across the crossing -------------------------------------
  // core domain          |  link domain
  //   amoeba_link_core   |
  //     cmd + beats  --> | ofifo --> amoeba_link_phy --> pads
  //     read beats   <-- | ififo <--      (assembles beats from 16-bit words)
  //
  // The crossing carries transactions and 64-bit beats, never 16-bit link
  // words: serialization is a link-domain implementation detail.
  logic                oc_valid, oc_ready;     // core -> ofifo (write side)
  logic [FLIT_W-1:0]   oc_data;
  logic                op_valid, op_ready;     // ofifo -> phy  (read side)
  logic [FLIT_W-1:0]   op_data;
  logic [FIFO_DW-1:0]  op_depth;               // load-bearing: see the phy
  logic [FIFO_DW-1:0]  oc_depth_unused;

  logic                ip_valid, ip_ready;     // phy -> ififo  (write side)
  logic [63:0]         ip_data;
  logic                ic_valid, ic_ready;     // ififo -> core (read side)
  logic [63:0]         ic_data;
  logic [FIFO_DW-1:0]  ip_depth_unused, ic_depth_unused;

  amoeba_link_core #(.HADDR_W(P.PA_BITS)) linkcore(
    .HCLK, .HRESETn,
    .HSEL(HSELEXT), .HADDR, .HTRANS, .HWRITE, .HSIZE, .HBURST, .HWDATA, .HREADY,
    .HRDATA(HRDATAEXT), .HREADYOUT(HREADYEXT), .HRESP(HRESPEXT),
    .ocmd_valid(oc_valid), .ocmd_ready(oc_ready), .ocmd_data(oc_data),
    .ibeat_valid(ic_valid), .ibeat_ready(ic_ready), .ibeat_data(ic_data));

  prim_fifo_async #(.Width(FLIT_W), .Depth(FIFO_D)) ofifo(
    .clk_wr_i(core_clk), .rst_wr_ni(rst_n_s),
    .wvalid_i(oc_valid), .wready_o(oc_ready), .wdata_i(oc_data), .wdepth_o(oc_depth_unused),
    .clk_rd_i(link_clk), .rst_rd_ni(link_rst_n_s),
    .rvalid_o(op_valid), .rready_i(op_ready), .rdata_o(op_data), .rdepth_o(op_depth));

  prim_fifo_async #(.Width(64), .Depth(FIFO_D)) ififo(
    .clk_wr_i(link_clk), .rst_wr_ni(link_rst_n_s),
    .wvalid_i(ip_valid), .wready_o(ip_ready), .wdata_i(ip_data), .wdepth_o(ip_depth_unused),
    .clk_rd_i(core_clk), .rst_rd_ni(rst_n_s),
    .rvalid_o(ic_valid), .rready_i(ic_ready), .rdata_o(ic_data), .rdepth_o(ic_depth_unused));

  logic txn_done;
  amoeba_link_phy phy(
    .link_clk, .link_rst_n(link_rst_n_s),
    .ocmd_valid(op_valid), .ocmd_ready(op_ready), .ocmd_data(op_data), .ocmd_depth(op_depth),
    .ibeat_valid(ip_valid), .ibeat_ready(ip_ready), .ibeat_data(ip_data),
    .io_o(lm_io_o), .io_oe(lm_io_oe), .io_i, .dir(lm_dir), .req, .wr, .burst, .ready, .rvalid,
    .txn_done);

  // Occupancy outputs we do not consume.  Sunk rather than left dangling so the
  // synthesis flow does not warn.
  logic unused_depths;
  assign unused_depths = ^{oc_depth_unused, ip_depth_unused, ic_depth_unused};

  // ---- bus ownership and scan mux -------------------------------------------
  // Scan: io[7:0] are scan_in, io[15:8] are scan_out.  The one-flop chain
  // stubs below reserve the structure; DFT insertion replaces them.
  logic [7:0] scan_q;
  always_ff @(posedge core_clk) if (scan_en) scan_q <= io_i[7:0];

  assign dir   = lm_dir;
  assign io_o  = test_mode ? {scan_q, 8'h00} : lm_io_o;
  assign io_oe = test_mode ? {8'hFF, 8'h00}  : {LINK_W{lm_io_oe}};

  // ---- status ---------------------------------------------------------------
  // In the LINK domain: txn_done is the phy's, and counting it in the core
  // domain would need a crossing for a signal whose only consumer is an LED.
  // status leaves the die straight from here -- a slow single bit with no
  // coherency requirement, so no synchroniser is owed.
  logic [HB_BIT:0] hb;
  always_ff @(posedge link_clk or negedge link_rst_n_s)
    if (!link_rst_n_s) hb <= '0; else if (txn_done) hb <= hb + 1'b1;
  assign status = hb[HB_BIT];

endmodule
