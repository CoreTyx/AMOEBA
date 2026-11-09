///////////////////////////////////////////////////////////////////////////////
// forte_pynq_top.sv -- the PL for DUT=forte on the PYNQ-Z2.
//
// The frozen forte_top in the fabric (forte_emu_dut), driven through its pins
// by the bring-up gateware (fbu_top), with its external memory in block RAM
// (fbu_mem_bram) or, with MEM_AXI, in the PS DDR (fbu_mem_axi_hp).  One clock:
// aclk is FCLK_CLK0 and also the chip's core_clk.
//
//   s_axi_ctl  GP0 -> fbu_top registers (fbu_pkg REG_*)
//   s_axi_mem  GP0 -> fbu_mem_bram port B (image load, window bases); unused with MEM_AXI
//   m_axi_hp   fbu_mem_axi_hp -> HP0 -> DDR carve-out; idle without MEM_AXI
//   led[0] status pin   led[1] chip released   led[2] tohost seen
//   led[3] link error or boot gate gave up
///////////////////////////////////////////////////////////////////////////////
module forte_pynq_top import forte_link_pkg::*; #(
  parameter int BEATS            = 2,
  parameter int TRACE_DEPTH_LOG2 = 11,
  parameter int MEM_W0_KB        = 128,
  parameter int MEM_W1_KB        = 4,
  parameter int MEM_W2_KB        = 16,
  parameter int MEM_AXI          = 0,
  parameter logic [31:0] DDR_CARVEOUT = 32'h1000_0000
)(
  input  logic        aclk,
  input  logic        aresetn,

  input  logic [11:0] s_axi_ctl_awaddr,
  input  logic        s_axi_ctl_awvalid,
  output logic        s_axi_ctl_awready,
  input  logic [31:0] s_axi_ctl_wdata,
  input  logic [3:0]  s_axi_ctl_wstrb,
  input  logic        s_axi_ctl_wvalid,
  output logic        s_axi_ctl_wready,
  output logic [1:0]  s_axi_ctl_bresp,
  output logic        s_axi_ctl_bvalid,
  input  logic        s_axi_ctl_bready,
  input  logic [11:0] s_axi_ctl_araddr,
  input  logic        s_axi_ctl_arvalid,
  output logic        s_axi_ctl_arready,
  output logic [31:0] s_axi_ctl_rdata,
  output logic [1:0]  s_axi_ctl_rresp,
  output logic        s_axi_ctl_rvalid,
  input  logic        s_axi_ctl_rready,

  input  logic [19:0] s_axi_mem_awaddr,
  input  logic        s_axi_mem_awvalid,
  output logic        s_axi_mem_awready,
  input  logic [31:0] s_axi_mem_wdata,
  input  logic [3:0]  s_axi_mem_wstrb,
  input  logic        s_axi_mem_wvalid,
  output logic        s_axi_mem_wready,
  output logic [1:0]  s_axi_mem_bresp,
  output logic        s_axi_mem_bvalid,
  input  logic        s_axi_mem_bready,
  input  logic [19:0] s_axi_mem_araddr,
  input  logic        s_axi_mem_arvalid,
  output logic        s_axi_mem_arready,
  output logic [31:0] s_axi_mem_rdata,
  output logic [1:0]  s_axi_mem_rresp,
  output logic        s_axi_mem_rvalid,
  input  logic        s_axi_mem_rready,

  output logic [5:0]  m_axi_hp_awid,
  output logic [31:0] m_axi_hp_awaddr,
  output logic [3:0]  m_axi_hp_awlen,
  output logic [2:0]  m_axi_hp_awsize,
  output logic [1:0]  m_axi_hp_awburst,
  output logic [1:0]  m_axi_hp_awlock,
  output logic [3:0]  m_axi_hp_awcache,
  output logic [2:0]  m_axi_hp_awprot,
  output logic [3:0]  m_axi_hp_awqos,
  output logic        m_axi_hp_awvalid,
  input  logic        m_axi_hp_awready,
  output logic [5:0]  m_axi_hp_wid,
  output logic [63:0] m_axi_hp_wdata,
  output logic [7:0]  m_axi_hp_wstrb,
  output logic        m_axi_hp_wlast,
  output logic        m_axi_hp_wvalid,
  input  logic        m_axi_hp_wready,
  input  logic [5:0]  m_axi_hp_bid,
  input  logic [1:0]  m_axi_hp_bresp,
  input  logic        m_axi_hp_bvalid,
  output logic        m_axi_hp_bready,
  output logic [5:0]  m_axi_hp_arid,
  output logic [31:0] m_axi_hp_araddr,
  output logic [3:0]  m_axi_hp_arlen,
  output logic [2:0]  m_axi_hp_arsize,
  output logic [1:0]  m_axi_hp_arburst,
  output logic [1:0]  m_axi_hp_arlock,
  output logic [3:0]  m_axi_hp_arcache,
  output logic [2:0]  m_axi_hp_arprot,
  output logic [3:0]  m_axi_hp_arqos,
  output logic        m_axi_hp_arvalid,
  input  logic        m_axi_hp_arready,
  input  logic [5:0]  m_axi_hp_rid,
  input  logic [63:0] m_axi_hp_rdata,
  input  logic [1:0]  m_axi_hp_rresp,
  input  logic        m_axi_hp_rlast,
  input  logic        m_axi_hp_rvalid,
  output logic        m_axi_hp_rready,

  output logic [3:0]  led
);

  localparam int LINE_W = 64 * BEATS;

  // ---- the chip's pins ----
  logic              rst_n;
  logic [1:0]        irq;
  logic              fault_inject;
  logic              test_mode;
  logic              scan_en;
  logic              uart_rx;
  logic [LINK_W-1:0] io_o;
  logic [LINK_W-1:0] io_oe;
  logic [LINK_W-1:0] io_i;
  logic              ready;
  logic              rvalid;
  logic              dir;
  logic              req;
  logic              wr;
  logic              clk_out;
  logic              uart_tx;
  logic              status;

  forte_emu_dut chip (
    .core_clk(aclk), .rst_n,
    .fpga_io_o(io_o), .fpga_io_oe(io_oe), .fpga_io_i(io_i),
    .dir, .req, .wr, .clk_out, .uart_tx, .status,
    .ready, .rvalid, .irq, .uart_rx,
    .test_mode, .scan_en, .fault_inject);

  // ---- bring-up gateware ----
  logic              m_req_valid;
  logic              m_req_ready;
  logic              m_req_wr;
  logic [31:0]       m_req_addr;
  logic [LINE_W-1:0] m_req_data;
  logic              m_rsp_valid;
  logic [LINE_W-1:0] m_rsp_data;
  logic              m_rsp_err;
  logic              link_error_seen;
  logic              tohost_seen;
  logic              boot_gate_gave_up;
  fbu_pkg::mem_stat_t mem_stat;

  fbu_top #(.BEATS(BEATS), .TRACE_DEPTH_LOG2(TRACE_DEPTH_LOG2), .MEM_AXI(MEM_AXI != 0)) fbu (
    .clk(aclk), .arst_n(aresetn),
    .s_axil_awaddr(s_axi_ctl_awaddr), .s_axil_awvalid(s_axi_ctl_awvalid), .s_axil_awready(s_axi_ctl_awready),
    .s_axil_wdata(s_axi_ctl_wdata), .s_axil_wstrb(s_axi_ctl_wstrb), .s_axil_wvalid(s_axi_ctl_wvalid),
    .s_axil_wready(s_axi_ctl_wready), .s_axil_bresp(s_axi_ctl_bresp), .s_axil_bvalid(s_axi_ctl_bvalid),
    .s_axil_bready(s_axi_ctl_bready), .s_axil_araddr(s_axi_ctl_araddr), .s_axil_arvalid(s_axi_ctl_arvalid),
    .s_axil_arready(s_axi_ctl_arready), .s_axil_rdata(s_axi_ctl_rdata), .s_axil_rresp(s_axi_ctl_rresp),
    .s_axil_rvalid(s_axi_ctl_rvalid), .s_axil_rready(s_axi_ctl_rready),
    .rst_n, .irq, .fault_inject, .test_mode, .scan_en, .uart_rx,
    .io_o, .io_oe, .ready, .rvalid,
    .io_i, .dir, .req, .wr, .clk_out, .uart_tx, .status,
    .m_req_valid, .m_req_ready, .m_req_wr, .m_req_addr, .m_req_data,
    .m_rsp_valid, .m_rsp_data, .m_rsp_err, .mem_stat,
    .link_error_seen, .tohost_seen, .boot_gate_gave_up);

  // ---- external memory ----
  if (MEM_AXI != 0) begin : g_ddr
    fbu_mem_axi_hp #(.BEATS(BEATS), .DDR_CARVEOUT(DDR_CARVEOUT)) mem (
      .clk(aclk), .arst_n(aresetn), .chip_in_reset(!rst_n),
      .req_valid(m_req_valid), .req_ready(m_req_ready), .req_wr(m_req_wr),
      .req_addr(m_req_addr), .req_data(m_req_data),
      .rsp_valid(m_rsp_valid), .rsp_data(m_rsp_data), .rsp_err(m_rsp_err),
      .m_axi_awid(m_axi_hp_awid), .m_axi_awaddr(m_axi_hp_awaddr), .m_axi_awlen(m_axi_hp_awlen),
      .m_axi_awsize(m_axi_hp_awsize), .m_axi_awburst(m_axi_hp_awburst), .m_axi_awlock(m_axi_hp_awlock),
      .m_axi_awcache(m_axi_hp_awcache), .m_axi_awprot(m_axi_hp_awprot), .m_axi_awqos(m_axi_hp_awqos),
      .m_axi_awvalid(m_axi_hp_awvalid), .m_axi_awready(m_axi_hp_awready),
      .m_axi_wid(m_axi_hp_wid), .m_axi_wdata(m_axi_hp_wdata), .m_axi_wstrb(m_axi_hp_wstrb),
      .m_axi_wlast(m_axi_hp_wlast), .m_axi_wvalid(m_axi_hp_wvalid), .m_axi_wready(m_axi_hp_wready),
      .m_axi_bid(m_axi_hp_bid), .m_axi_bresp(m_axi_hp_bresp), .m_axi_bvalid(m_axi_hp_bvalid),
      .m_axi_bready(m_axi_hp_bready),
      .m_axi_arid(m_axi_hp_arid), .m_axi_araddr(m_axi_hp_araddr), .m_axi_arlen(m_axi_hp_arlen),
      .m_axi_arsize(m_axi_hp_arsize), .m_axi_arburst(m_axi_hp_arburst), .m_axi_arlock(m_axi_hp_arlock),
      .m_axi_arcache(m_axi_hp_arcache), .m_axi_arprot(m_axi_hp_arprot), .m_axi_arqos(m_axi_hp_arqos),
      .m_axi_arvalid(m_axi_hp_arvalid), .m_axi_arready(m_axi_hp_arready),
      .m_axi_rid(m_axi_hp_rid), .m_axi_rdata(m_axi_hp_rdata), .m_axi_rresp(m_axi_hp_rresp),
      .m_axi_rlast(m_axi_hp_rlast), .m_axi_rvalid(m_axi_hp_rvalid), .m_axi_rready(m_axi_hp_rready),
      .mem_err(mem_stat.err), .first_err_addr(mem_stat.first_err_addr),
      .first_err_resp(mem_stat.first_err_resp), .reads(mem_stat.reads), .writes(mem_stat.writes),
      .dropped_writes(mem_stat.dropped_writes), .read_latency_max(mem_stat.read_latency_max),
      .read_latency_sum(mem_stat.read_latency_sum));

    // No image port: the PS writes the carve-out directly.  A stray access
    // completes with SLVERR rather than hanging the GP port.
    assign s_axi_mem_awready = s_axi_mem_awvalid && s_axi_mem_wvalid && !s_axi_mem_bvalid;
    assign s_axi_mem_wready  = s_axi_mem_awready;
    assign s_axi_mem_bresp   = 2'b10;
    assign s_axi_mem_arready = !s_axi_mem_rvalid;
    assign s_axi_mem_rdata   = '0;
    assign s_axi_mem_rresp   = 2'b10;

    always_ff @(posedge aclk or negedge aresetn) begin
      if (!aresetn) begin
        s_axi_mem_bvalid <= 1'b0;
        s_axi_mem_rvalid <= 1'b0;
      end else begin
        if (s_axi_mem_awready)
          s_axi_mem_bvalid <= 1'b1;
        else if (s_axi_mem_bready)
          s_axi_mem_bvalid <= 1'b0;
        if (s_axi_mem_arvalid && s_axi_mem_arready)
          s_axi_mem_rvalid <= 1'b1;
        else if (s_axi_mem_rready)
          s_axi_mem_rvalid <= 1'b0;
      end
    end
  end else begin : g_bram
    fbu_mem_bram #(.BEATS(BEATS), .W0_KB(MEM_W0_KB), .W1_KB(MEM_W1_KB), .W2_KB(MEM_W2_KB)) mem (
      .clk(aclk), .arst_n(aresetn),
      .req_valid(m_req_valid), .req_ready(m_req_ready), .req_wr(m_req_wr),
      .req_addr(m_req_addr), .req_data(m_req_data),
      .rsp_valid(m_rsp_valid), .rsp_data(m_rsp_data), .rsp_err(m_rsp_err),
      .s_awaddr(s_axi_mem_awaddr), .s_awvalid(s_axi_mem_awvalid), .s_awready(s_axi_mem_awready),
      .s_wdata(s_axi_mem_wdata), .s_wstrb(s_axi_mem_wstrb), .s_wvalid(s_axi_mem_wvalid),
      .s_wready(s_axi_mem_wready), .s_bresp(s_axi_mem_bresp), .s_bvalid(s_axi_mem_bvalid),
      .s_bready(s_axi_mem_bready), .s_araddr(s_axi_mem_araddr), .s_arvalid(s_axi_mem_arvalid),
      .s_arready(s_axi_mem_arready), .s_rdata(s_axi_mem_rdata), .s_rresp(s_axi_mem_rresp),
      .s_rvalid(s_axi_mem_rvalid), .s_rready(s_axi_mem_rready));

    assign mem_stat = '0;

    assign m_axi_hp_awid    = '0;
    assign m_axi_hp_awaddr  = '0;
    assign m_axi_hp_awlen   = '0;
    assign m_axi_hp_awsize  = '0;
    assign m_axi_hp_awburst = '0;
    assign m_axi_hp_awlock  = '0;
    assign m_axi_hp_awcache = '0;
    assign m_axi_hp_awprot  = '0;
    assign m_axi_hp_awqos   = '0;
    assign m_axi_hp_awvalid = 1'b0;
    assign m_axi_hp_wid     = '0;
    assign m_axi_hp_wdata   = '0;
    assign m_axi_hp_wstrb   = '0;
    assign m_axi_hp_wlast   = 1'b0;
    assign m_axi_hp_wvalid  = 1'b0;
    assign m_axi_hp_bready  = 1'b1;
    assign m_axi_hp_arid    = '0;
    assign m_axi_hp_araddr  = '0;
    assign m_axi_hp_arlen   = '0;
    assign m_axi_hp_arsize  = '0;
    assign m_axi_hp_arburst = '0;
    assign m_axi_hp_arlock  = '0;
    assign m_axi_hp_arcache = '0;
    assign m_axi_hp_arprot  = '0;
    assign m_axi_hp_arqos   = '0;
    assign m_axi_hp_arvalid = 1'b0;
    assign m_axi_hp_rready  = 1'b1;
  end

  // ---- LEDs ----
  always_ff @(posedge aclk) begin
    led[0] <= status;
    led[1] <= rst_n;
    led[2] <= tohost_seen;
    led[3] <= link_error_seen || boot_gate_gave_up;
  end

endmodule
