///////////////////////////////////////////////////////////////////////////////
// amoeba_chip.sv
//
// The die minus its pads: reset synchroniser, the SoC, the link bridge, the
// scan mux.  This is the boundary DFT insertion and gate-level simulation see.
// amoeba_top adds the pad cells.
//
// Bus ownership: the link bridge is the only driver.  There is no training FSM
// to arbitrate with any more -- the core leaves reset as soon as rst_n is
// released, and it is the FPGA that decides when that happens
// (pkg/amoeba_link_pkg.sv, docs/impl_plan_link_clocking.md s7).
///////////////////////////////////////////////////////////////////////////////

`include "amoeba_config_select.vh"

module amoeba_chip import cvw::*; import amoeba_link_pkg::*; #(
  parameter logic PERIPH_ONCHIP = 1'b1,
  parameter HB_BIT        = 15          // status heartbeat: link-transaction counter tap
)(
  input  logic              core_clk,
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
  logic rst_n_s;
  amoeba_rst_sync rstsync(.clk(core_clk), .rst_n_in(rst_n), .rst_n_out(rst_n_s));

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

  // ---- link master ----------------------------------------------------------
  logic txn_done;
  amoeba_link_master #(.HADDR_W(P.PA_BITS)) link(
    .HCLK, .HRESETn,
    .HSEL(HSELEXT), .HADDR, .HTRANS, .HWRITE, .HSIZE, .HBURST, .HWDATA, .HREADY,
    .HRDATA(HRDATAEXT), .HREADYOUT(HREADYEXT), .HRESP(HRESPEXT),
    .io_o(lm_io_o), .io_oe(lm_io_oe), .io_i, .dir(lm_dir), .req, .wr, .burst, .ready, .rvalid,
    .txn_done);

  // ---- bus ownership and scan mux -------------------------------------------
  // Scan: io[7:0] are scan_in, io[15:8] are scan_out.  The one-flop chain
  // stubs below reserve the structure; DFT insertion replaces them.
  logic [7:0] scan_q;
  always_ff @(posedge core_clk) if (scan_en) scan_q <= io_i[7:0];

  assign dir   = lm_dir;
  assign io_o  = test_mode ? {scan_q, 8'h00} : lm_io_o;
  assign io_oe = test_mode ? {8'hFF, 8'h00}  : {LINK_W{lm_io_oe}};

  // ---- status ---------------------------------------------------------------
  logic [HB_BIT:0] hb;
  always_ff @(posedge core_clk or negedge rst_n_s)
    if (!rst_n_s) hb <= '0; else if (txn_done) hb <= hb + 1'b1;
  assign status = hb[HB_BIT];

endmodule
