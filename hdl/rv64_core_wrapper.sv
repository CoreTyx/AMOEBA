// The config must be included at file scope before the module definition.
// pkg/amoeba_config_select.vh holds the AMOEBA_CONFIG_* ladder for every top
// that needs it, behind a guard so two tops in one compilation unit do not
// redeclare the same parameters.
`include "amoeba_config_select.vh"

module rv64_core_wrapper import cvw::*; (
    input  logic        clk,
    input  logic        rst,

    output logic [63:0] mem_addr,
    output logic [7:0]  mem_rmask,
    output logic [7:0]  mem_wmask,
    input  logic [63:0] mem_rdata,
    output logic [63:0] mem_wdata,
    input  logic        mem_resp,

    output logic        monitor_valid,
    output logic [63:0] monitor_order,
    output logic [31:0] monitor_inst,
    output logic        monitor_trap,
    output logic        monitor_intr,
    output logic [1:0]  monitor_mode,
    output logic [1:0]  monitor_ixl,

    output logic [4:0]  monitor_rs1_addr,
    output logic [4:0]  monitor_rs2_addr,
    output logic [63:0] monitor_rs1_rdata,
    output logic [63:0] monitor_rs2_rdata,
    output logic [4:0]  monitor_rd_addr,
    output logic [63:0] monitor_rd_wdata,

    `ifndef ECE411_NO_FLOAT
    output logic [5:0]  monitor_frs1_addr,
    output logic [5:0]  monitor_frs2_addr,
    output logic [5:0]  monitor_frs3_addr,
    output logic [63:0] monitor_frs1_rdata,
    output logic [63:0] monitor_frs2_rdata,
    output logic [63:0] monitor_frs3_rdata,
    output logic [5:0]  monitor_frd_addr,
    output logic [63:0] monitor_frd_wdata,
    `endif

    output logic [63:0] monitor_pc_rdata,
    output logic [63:0] monitor_pc_wdata,
    output logic [63:0] monitor_mem_addr,
    output logic [7:0]  monitor_mem_rmask,
    output logic [7:0]  monitor_mem_wmask,
    output logic [63:0] monitor_mem_rdata,
    output logic [63:0] monitor_mem_wdata,
    output logic        monitor_mem_extamo,

    output logic [7:0]   mstatus_rmask,
    output logic [7:0]   mstatus_wmask,
    input  logic [63:0]  mstatus_rdata,
    output logic [63:0]  mstatus_wdata,

    output logic [7:0]   misa_rmask,
    output logic [7:0]   misa_wmask,
    input  logic [63:0]  misa_rdata,
    output logic [63:0]  misa_wdata,

    output logic [7:0]   mie_rmask,
    output logic [7:0]   mie_wmask,
    input  logic [63:0]  mie_rdata,
    output logic [63:0]  mie_wdata,

    output logic [7:0]   mtvec_rmask,
    output logic [7:0]   mtvec_wmask,
    input  logic [63:0]  mtvec_rdata,
    output logic [63:0]  mtvec_wdata,

    output logic [7:0]   mscratch_rmask,
    output logic [7:0]   mscratch_wmask,
    input  logic [63:0]  mscratch_rdata,
    output logic [63:0]  mscratch_wdata,

    output logic [7:0]   mepc_rmask,
    output logic [7:0]   mepc_wmask,
    input  logic [63:0]  mepc_rdata,
    output logic [63:0]  mepc_wdata,

    output logic [7:0]   mcause_rmask,
    output logic [7:0]   mcause_wmask,
    input  logic [63:0]  mcause_rdata,
    output logic [63:0]  mcause_wdata,

    output logic [7:0]   mtval_rmask,
    output logic [7:0]   mtval_wmask,
    input  logic [63:0]  mtval_rdata,
    output logic [63:0]  mtval_wdata,

    output logic [7:0]   mip_rmask,
    output logic [7:0]   mip_wmask,
    input  logic [63:0]  mip_rdata,
    output logic [63:0]  mip_wdata,

    output logic [7:0]   mcycle_rmask,
    output logic [7:0]   mcycle_wmask,
    input  logic [63:0]  mcycle_rdata,
    output logic [63:0]  mcycle_wdata,

    output logic [7:0]   minstret_rmask,
    output logic [7:0]   minstret_wmask,
    input  logic [63:0]  minstret_rdata,
    output logic [63:0]  minstret_wdata
);

    `include "parameter-defs.vh"

    // CSR ports unused for now (no CSR shadow checking)
    assign mstatus_rmask  = '0; assign mstatus_wmask  = '0; assign mstatus_wdata  = '0;
    assign misa_rmask     = '0; assign misa_wmask     = '0; assign misa_wdata     = '0;
    assign mie_rmask      = '0; assign mie_wmask      = '0; assign mie_wdata      = '0;
    assign mtvec_rmask    = '0; assign mtvec_wmask    = '0; assign mtvec_wdata    = '0;
    assign mscratch_rmask = '0; assign mscratch_wmask = '0; assign mscratch_wdata = '0;
    assign mepc_rmask     = '0; assign mepc_wmask     = '0; assign mepc_wdata     = '0;
    assign mcause_rmask   = '0; assign mcause_wmask   = '0; assign mcause_wdata   = '0;
    assign mtval_rmask    = '0; assign mtval_wmask    = '0; assign mtval_wdata    = '0;
    assign mip_rmask      = '0; assign mip_wmask      = '0; assign mip_wdata      = '0;
    assign mcycle_rmask   = '0; assign mcycle_wmask   = '0; assign mcycle_wdata   = '0;
    assign minstret_rmask = '0; assign minstret_wmask = '0; assign minstret_wdata = '0;

    // -------------------------------------------------------------------------
    // CVW SoC AHB-Lite signals
    // -------------------------------------------------------------------------
    localparam PA = P.PA_BITS;
    localparam AW = P.AHBW;

    logic [AW-1:0]   HRDATAEXT;
    logic            HREADYEXT, HRESPEXT;
    logic            HSELEXT;
    logic            HCLK, HRESETn;
    logic [PA-1:0]   HADDR;
    logic [AW-1:0]   HWDATA;
    logic [AW/8-1:0] HWSTRB;
    logic            HWRITE;
    logic [2:0]      HSIZE, HBURST;
    logic [3:0]      HPROT;
    logic [1:0]      HTRANS;
    logic            HMASTLOCK;
    logic            HREADY;
    logic            reset_soc;

    // -------------------------------------------------------------------------
    // CVW SoC instantiation
    // -------------------------------------------------------------------------
    wallypipelinedsoc #(P) soc (
        .clk        (clk),
        .reset_ext  (rst),
        .reset      (reset_soc),
        .ExternalStall (1'b0),
        .HRDATAEXT  (HRDATAEXT),
        .HREADYEXT  (HREADYEXT),
        .HRESPEXT   (HRESPEXT),
        .HSELEXT    (HSELEXT),
        .HCLK       (HCLK),
        .HRESETn    (HRESETn),
        .HADDR      (HADDR),
        .HWDATA     (HWDATA),
        .HWSTRB     (HWSTRB),
        .HWRITE     (HWRITE),
        .HSIZE      (HSIZE),
        .HBURST     (HBURST),
        .HPROT      (HPROT),
        .HTRANS     (HTRANS),
        .HMASTLOCK  (HMASTLOCK),
        .HREADY     (HREADY),
        .TIMECLK    (1'b0),
        .GPIOIN     (32'h0),
        .GPIOOUT    (),
        .GPIOEN     (),
        .UARTSin    (1'b1),
        .UARTSout   (),
        .SPIIn      (1'b0),
        .SPIOut     (),
        .SPICS      (),
        .SPICLK     (),
        .SDCIn      (1'b0),
        .SDCCmd     (),
        .SDCCS      (),
        .SDCCLK     ()
    );

    // -------------------------------------------------------------------------
    // AHB-Lite → mem_itf bridge
    // -------------------------------------------------------------------------
    ahb_to_memitf #(.AHB_PA_BITS(PA)) bridge (
        .clk      (HCLK),
        .HRESETn  (HRESETn),
        .HSEL     (HSELEXT),
        .HADDR    (HADDR),
        .HTRANS   (HTRANS),
        .HWRITE   (HWRITE),
        .HSIZE    (HSIZE),
        .HWDATA   (HWDATA),
        .HWSTRB   ({{(8-AW/8){1'b0}}, HWSTRB}),
        .HRDATA   (HRDATAEXT),
        .HREADY   (HREADYEXT),
        .HRESP    (HRESPEXT),
        .mem_addr  (mem_addr),
        .mem_rmask (mem_rmask),
        .mem_wmask (mem_wmask),
        .mem_wdata (mem_wdata),
        .mem_rdata (mem_rdata),
        .mem_resp  (mem_resp)
    );
    // -------------------------------------------------------------------------
    // RVFI monitor taps -- hdl/rvfi_tap.sv, fed by hierarchical reads of the
    // core.  The wrapper's monitor_* ports are the tap's outputs unchanged.
    // -------------------------------------------------------------------------
    rvfi_tap tap (
        .clk, .rst,
        .StallE         (soc.core.StallE),
        .StallM         (soc.core.StallM),
        .StallW         (soc.core.StallW),
        .FlushE         (soc.core.FlushE),
        .FlushM         (soc.core.FlushM),
        .FlushW         (soc.core.FlushW),
        .InstrValidM    (soc.core.ieu.InstrValidM),
        .InstrValidE    (soc.core.ieu.InstrValidE),
        .InstrValidD    (soc.core.ieu.InstrValidD),
        .InstrRawD      (soc.core.ifu.InstrRawD),
        .PCM            (soc.core.ifu.PCM),
        .PCD            (soc.core.ifu.PCD),
        .PCE            (soc.core.ifu.PCE),
        .TrapM          (soc.core.TrapM),
        .RetM           (soc.core.RetM),
        .InterruptM     (soc.core.priv.priv.InterruptM),
        .EPCM           (soc.core.EPCM),
        .TrapVectorM    (soc.core.TrapVectorM),
        .PrivilegeModeW (soc.core.PrivilegeModeW),
        .GPRAddr        (soc.core.ieu.dp.regf.a3),
        .GPRWen         (soc.core.ieu.dp.regf.we3),
        .GPRValue       (soc.core.ieu.dp.regf.wd3),
        .Rs1D           (soc.core.ieu.dp.regf.a1),
        .Rs2D           (soc.core.ieu.dp.regf.a2),
        .ForwardedSrcAE (soc.core.ieu.ForwardedSrcAE),
        .ForwardedSrcBE (soc.core.ieu.ForwardedSrcBE),
        .MemRWM         (soc.core.MemRWM),
        .Funct3M        (soc.core.Funct3M),
        .IEUAdrM        (soc.core.IEUAdrM),
        .WriteDataM     (soc.core.lsu.LSUWriteDataM[63:0]),
        .ReadDataW      (soc.core.ReadDataW[63:0]),
`ifndef ECE411_NO_FLOAT
        .Frs1D_i        (soc.core.fpu.fpu.fregfile.a1),
        .Frs2D_i        (soc.core.fpu.fpu.fregfile.a2),
        .Frs3D_i        (soc.core.fpu.fpu.fregfile.a3),
        .Frs1DataD_i    (soc.core.fpu.fpu.fregfile.rd1),
        .Frs2DataD_i    (soc.core.fpu.fpu.fregfile.rd2),
        .Frs3DataD_i    (soc.core.fpu.fpu.fregfile.rd3),
        .Frd_we4_i      (soc.core.fpu.fpu.fregfile.we4),
        .Frd_a4_i       (soc.core.fpu.fpu.fregfile.a4),
        .Frd_wd4_i      (soc.core.fpu.fpu.fregfile.wd4),
        .monitor_frs1_addr, .monitor_frs2_addr, .monitor_frs3_addr,
        .monitor_frs1_rdata, .monitor_frs2_rdata, .monitor_frs3_rdata,
        .monitor_frd_addr, .monitor_frd_wdata,
`endif
        .monitor_valid, .monitor_order, .monitor_inst, .monitor_trap,
        .monitor_intr, .monitor_mode, .monitor_ixl,
        .monitor_rs1_addr, .monitor_rs2_addr, .monitor_rs1_rdata, .monitor_rs2_rdata,
        .monitor_rd_addr, .monitor_rd_wdata,
        .monitor_pc_rdata, .monitor_pc_wdata,
        .monitor_mem_addr, .monitor_mem_rmask, .monitor_mem_wmask,
        .monitor_mem_rdata, .monitor_mem_wdata, .monitor_mem_extamo
    );

endmodule
