///////////////////////////////////////////////////////////////////////////////
// forte_pynq_top.sv -- the PL for DUT=forte on the PYNQ-Z2.
//
// The frozen forte_top in the fabric (forte_emu_dut), driven through its pins
// by the bring-up gateware (fbu_top), with its external memory in block RAM
// (fbu_mem_bram).  One clock: aclk is FCLK_CLK0 and also the chip's core_clk.
//
//   s_axi_ctl  GP0 -> fbu_top registers (fbu_pkg REG_*)
//   s_axi_mem  GP0 -> fbu_mem_bram port B (image load, window bases)
//   led[0] status pin   led[1] chip released   led[2] tohost seen
//   led[3] link error or boot gate gave up
///////////////////////////////////////////////////////////////////////////////
module forte_pynq_top import forte_link_pkg::*; #(
  parameter int BEATS            = 2,
  parameter int TRACE_DEPTH_LOG2 = 11,
  parameter int MEM_W0_KB        = 128,
  parameter int MEM_W1_KB        = 4,
  parameter int MEM_W2_KB        = 16
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

  fbu_top #(.BEATS(BEATS), .TRACE_DEPTH_LOG2(TRACE_DEPTH_LOG2)) fbu (
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
    .m_rsp_valid, .m_rsp_data, .m_rsp_err,
    .link_error_seen, .tohost_seen, .boot_gate_gave_up);

  // ---- external memory ----
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

  // ---- LEDs ----
  always_ff @(posedge aclk) begin
    led[0] <= status;
    led[1] <= rst_n;
    led[2] <= tohost_seen;
    led[3] <= link_error_seen || boot_gate_gave_up;
  end

endmodule
