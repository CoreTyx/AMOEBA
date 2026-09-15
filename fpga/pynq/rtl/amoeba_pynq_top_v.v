//////////////////////////////////////////////////////////////////////////////
// amoeba_pynq_top_v.v
//
// Verilog-2001 shim around amoeba_pynq_top, and the reason it exists is a hard
// Vivado restriction rather than a design choice:
//
//   ERROR: [filemgmt 56-195] Reference 'amoeba_pynq_top' contains top file
//   '.../amoeba_pynq_top.sv' of type SystemVerilog.  This type is not allowed
//   as the top file in the reference.
//
// IPI's `create_bd_cell -type module` requires the referenced top to be Verilog
// or VHDL.  Everything below this file may be SystemVerilog -- and all of it
// is -- but the file IPI points at may not be.  So this is a pure pass-through:
// no logic, no defaults that differ from the real top, nothing to keep in step
// except the port list.
//
// PA_BITS is hardcoded to 56 in the ports that carry a full core address,
// because a Verilog-2001 file cannot include pkg/config-shared.vh, which
// derives it as (XLEN==32 ? 34 : 56).  Every configuration in this project is
// RV64, so 56 it is; amoeba_pynq_top carries an elaboration-time $error if
// that ever stops being true, so this cannot silently truncate.
//
// m_ahb_haddr is the exception at 32 bits, and deliberately so: it does not
// carry a core address.  amoeba_pynq_top rebases it onto the DDR carve-out for
// ahblite_axi_bridge, whose address port is 32 bits wide.
//////////////////////////////////////////////////////////////////////////////

module amoeba_pynq_top_v #(
    parameter MEM_BRAM        = 1,
    parameter MEM_KB          = 128,
    parameter TRACE           = 1,
    parameter TRACE_FIFO_LOG2 = 9,
    parameter PKT_RECORDS     = 256,
    // Base of the DDR carve-out in the PS map.  Set from opt(ddr_carveout) in
    // tcl/bd_pynq.tcl, the same value that tcl assigns as the AXI master's
    // address segment.  See amoeba_pynq_top.sv for what it does.
    parameter DDR_CARVEOUT_BASE = 32'h10000000
)(
    input  wire        aclk,
    input  wire        aresetn,

    input  wire [11:0] s_axi_ctl_awaddr,
    input  wire        s_axi_ctl_awvalid,
    output wire        s_axi_ctl_awready,
    input  wire [31:0] s_axi_ctl_wdata,
    input  wire [3:0]  s_axi_ctl_wstrb,
    input  wire        s_axi_ctl_wvalid,
    output wire        s_axi_ctl_wready,
    output wire [1:0]  s_axi_ctl_bresp,
    output wire        s_axi_ctl_bvalid,
    input  wire        s_axi_ctl_bready,
    input  wire [11:0] s_axi_ctl_araddr,
    input  wire        s_axi_ctl_arvalid,
    output wire        s_axi_ctl_arready,
    output wire [31:0] s_axi_ctl_rdata,
    output wire [1:0]  s_axi_ctl_rresp,
    output wire        s_axi_ctl_rvalid,
    input  wire        s_axi_ctl_rready,

    output wire [63:0] m_axis_trace_tdata,
    output wire [7:0]  m_axis_trace_tkeep,
    output wire        m_axis_trace_tvalid,
    input  wire        m_axis_trace_tready,
    output wire        m_axis_trace_tlast,

    input  wire [31:0] s_axi_mem_awaddr,
    input  wire        s_axi_mem_awvalid,
    output wire        s_axi_mem_awready,
    input  wire [31:0] s_axi_mem_wdata,
    input  wire [3:0]  s_axi_mem_wstrb,
    input  wire        s_axi_mem_wvalid,
    output wire        s_axi_mem_wready,
    output wire [1:0]  s_axi_mem_bresp,
    output wire        s_axi_mem_bvalid,
    input  wire        s_axi_mem_bready,
    input  wire [31:0] s_axi_mem_araddr,
    input  wire        s_axi_mem_arvalid,
    output wire        s_axi_mem_arready,
    output wire [31:0] s_axi_mem_rdata,
    output wire [1:0]  s_axi_mem_rresp,
    output wire        s_axi_mem_rvalid,
    input  wire        s_axi_mem_rready,

    output wire        m_ahb_hsel,
    // 32, not 56: the bridge's s_ahb_haddr is 32 bits and amoeba_pynq_top
    // rebases the core address onto the carve-out before driving this.
    output wire [31:0] m_ahb_haddr,
    output wire [63:0] m_ahb_hwdata,
    output wire [7:0]  m_ahb_hwstrb,
    output wire        m_ahb_hwrite,
    output wire [2:0]  m_ahb_hsize,
    output wire [2:0]  m_ahb_hburst,
    output wire [3:0]  m_ahb_hprot,
    output wire [1:0]  m_ahb_htrans,
    output wire        m_ahb_hmastlock,
    input  wire [63:0] m_ahb_hrdata,
    input  wire        m_ahb_hready,
    input  wire        m_ahb_hresp,
    output wire        m_ahb_hresetn,
    output wire        m_ahb_hready_bus,

    output wire        uart_txd_obs
);

    amoeba_pynq_top #(
        .MEM_BRAM          (MEM_BRAM[0]),
        .DDR_CARVEOUT_BASE (DDR_CARVEOUT_BASE),
        .MEM_KB            (MEM_KB),
        .TRACE             (TRACE[0]),
        .TRACE_FIFO_LOG2   (TRACE_FIFO_LOG2),
        .PKT_RECORDS       (PKT_RECORDS)
    ) u_top (
        .aclk                (aclk),
        .aresetn             (aresetn),

        .s_axi_ctl_awaddr    (s_axi_ctl_awaddr),
        .s_axi_ctl_awvalid   (s_axi_ctl_awvalid),
        .s_axi_ctl_awready   (s_axi_ctl_awready),
        .s_axi_ctl_wdata     (s_axi_ctl_wdata),
        .s_axi_ctl_wstrb     (s_axi_ctl_wstrb),
        .s_axi_ctl_wvalid    (s_axi_ctl_wvalid),
        .s_axi_ctl_wready    (s_axi_ctl_wready),
        .s_axi_ctl_bresp     (s_axi_ctl_bresp),
        .s_axi_ctl_bvalid    (s_axi_ctl_bvalid),
        .s_axi_ctl_bready    (s_axi_ctl_bready),
        .s_axi_ctl_araddr    (s_axi_ctl_araddr),
        .s_axi_ctl_arvalid   (s_axi_ctl_arvalid),
        .s_axi_ctl_arready   (s_axi_ctl_arready),
        .s_axi_ctl_rdata     (s_axi_ctl_rdata),
        .s_axi_ctl_rresp     (s_axi_ctl_rresp),
        .s_axi_ctl_rvalid    (s_axi_ctl_rvalid),
        .s_axi_ctl_rready    (s_axi_ctl_rready),

        .m_axis_trace_tdata  (m_axis_trace_tdata),
        .m_axis_trace_tkeep  (m_axis_trace_tkeep),
        .m_axis_trace_tvalid (m_axis_trace_tvalid),
        .m_axis_trace_tready (m_axis_trace_tready),
        .m_axis_trace_tlast  (m_axis_trace_tlast),

        .s_axi_mem_awaddr    (s_axi_mem_awaddr),
        .s_axi_mem_awvalid   (s_axi_mem_awvalid),
        .s_axi_mem_awready   (s_axi_mem_awready),
        .s_axi_mem_wdata     (s_axi_mem_wdata),
        .s_axi_mem_wstrb     (s_axi_mem_wstrb),
        .s_axi_mem_wvalid    (s_axi_mem_wvalid),
        .s_axi_mem_wready    (s_axi_mem_wready),
        .s_axi_mem_bresp     (s_axi_mem_bresp),
        .s_axi_mem_bvalid    (s_axi_mem_bvalid),
        .s_axi_mem_bready    (s_axi_mem_bready),
        .s_axi_mem_araddr    (s_axi_mem_araddr),
        .s_axi_mem_arvalid   (s_axi_mem_arvalid),
        .s_axi_mem_arready   (s_axi_mem_arready),
        .s_axi_mem_rdata     (s_axi_mem_rdata),
        .s_axi_mem_rresp     (s_axi_mem_rresp),
        .s_axi_mem_rvalid    (s_axi_mem_rvalid),
        .s_axi_mem_rready    (s_axi_mem_rready),

        .m_ahb_hsel          (m_ahb_hsel),
        .m_ahb_haddr         (m_ahb_haddr),
        .m_ahb_hwdata        (m_ahb_hwdata),
        .m_ahb_hwstrb        (m_ahb_hwstrb),
        .m_ahb_hwrite        (m_ahb_hwrite),
        .m_ahb_hsize         (m_ahb_hsize),
        .m_ahb_hburst        (m_ahb_hburst),
        .m_ahb_hprot         (m_ahb_hprot),
        .m_ahb_htrans        (m_ahb_htrans),
        .m_ahb_hmastlock     (m_ahb_hmastlock),
        .m_ahb_hrdata        (m_ahb_hrdata),
        .m_ahb_hready        (m_ahb_hready),
        .m_ahb_hresp         (m_ahb_hresp),
        .m_ahb_hresetn       (m_ahb_hresetn),
        .m_ahb_hready_bus    (m_ahb_hready_bus),

        .uart_txd_obs        (uart_txd_obs)
    );

endmodule
