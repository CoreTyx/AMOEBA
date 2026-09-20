///////////////////////////////////////////////////////////////////////////////
// amoeba_asic_wrapper.sv
//
// The ASIC top in the fabric, on the same ports as amoeba_soc_wrapper -- so
// amoeba_pynq_top swaps one module name and the control block, bus probe,
// both memory backends, the block design and sw/amoeba/ see the bus they see
// today.
//
//   amoeba_top          the chip, behavioural pads (hdl/amoeba_top.sv)
//   amoeba_link_slave   the FPGA end of the 16-bit link, an AHB-Lite master
//   io[15:0]            the bidirectional bus between them, resolved inside
//                       the fabric.  Vivado converts an internal tristate to
//                       mux logic, which is what stage A/B want; stage C
//                       replaces it with IOBUFs on real pins.
//
// What changes at this boundary, port by port (docs/impl_plan_fpga_linux.md s3):
//
//   reset_ext     -> rst_n.  Inside, rst_n release starts link TRAINING; the
//                    core is held until the link is trained, so the first
//                    fetch is ~2 x TRAIN_LEN cycles after release.
//   HRESETn       is the slave's reset, and deasserts BEFORE the core's --
//                    the same order BRIDGE_LEAD already establishes.
//   HSELEXT       = a transaction is open on the slave's bus.  Everything on
//                    the link is external memory: CLINT, PLIC and UART are
//                    on the die and never leave it.
//   HREADY        = the backend's HREADYEXT.  The slave is the only master
//                    and nothing is behind it.
//   ExternalStall is NOT a pad.  Accepted and ignored; amoeba_trace runs in
//                    windowed / drop-on-overflow mode under this DUT.
//   UARTSin/out   are the uart_rx / uart_tx pads.  The PL console still comes
//                    from the AHB snoop, by hierarchical reference into the
//                    SoC's internal bus (amoeba_pynq_top).
//
// Nothing here drives anything inside amoeba_top except its pins.
///////////////////////////////////////////////////////////////////////////////

`include "amoeba_config_select.vh"

module amoeba_asic_wrapper import cvw::*; import amoeba_link_pkg::*; #(
    parameter int TRAIN_LEN = TRAIN_LEN_DEFAULT,
    // Register the link's inbound pins once in the slave before use.  The
    // structure a real pad needs; one cycle of latency per transaction.
    parameter bit LINK_IN_REG = 1'b1
)(
    input  logic                  clk,
    input  logic                  reset_ext,   // synchronous in the PL; the chip resynchronises it
    output logic                  reset,       // the SoC's synchronized reset, for waves

    input  logic                  ExternalStall,   // no such pad: ignored

    // AHB-Lite master, to the memory backend -- reconstructed by the slave
    input  logic [AHBW-1:0]       HRDATAEXT,
    input  logic                  HREADYEXT,
    input  logic                  HRESPEXT,
    output logic                  HSELEXT,
    output logic                  HCLK,
    output logic                  HRESETn,
    output logic [PA_BITS-1:0]    HADDR,
    output logic [AHBW-1:0]       HWDATA,
    output logic [XLEN/8-1:0]     HWSTRB,
    output logic                  HWRITE,
    output logic [2:0]            HSIZE,
    output logic [2:0]            HBURST,
    output logic [3:0]            HPROT,
    output logic [1:0]            HTRANS,
    output logic                  HMASTLOCK,
    output logic                  HREADY,

    // Console pads
    input  logic                  UARTSin,
    output logic                  UARTSout,

    // ---- beyond amoeba_soc_wrapper -----------------------------------------
    input  logic [1:0]            irq,         // the irq[1:0] pads (PLIC sources 3 and 6)
    output logic                  status,      // the status pad: trained & heartbeat
    input  logic                  link_clear,  // counters
    output logic                  link_trained,
    output logic                  link_failed,
    output logic [31:0]           link_xact,
    output logic [31:0]           link_rd,
    output logic [31:0]           link_wr,
    output logic [31:0]           link_retrain,
    output logic [31:0]           link_wdog,
    output logic [31:0]           link_err
);

    `include "parameter-defs.vh"

    // ---- the link ------------------------------------------------------------
    wire  [LINK_W-1:0] io;
    logic              dir, req, wr, burst, ready, rvalid;
    logic              rst_n;
    assign rst_n = ~reset_ext;

    // ---- the chip --------------------------------------------------------------
    amoeba_top #(.TRAIN_LEN(TRAIN_LEN)) top (
        .clk       (clk),
        .rst_n     (rst_n),
        .io        (io),
        .dir       (dir),
        .req       (req),
        .wr        (wr),
        .burst     (burst),
        .ready     (ready),
        .rvalid    (rvalid),
        .irq       (irq),
        .uart_tx   (UARTSout),
        .uart_rx   (UARTSin),
        .test_mode (1'b0),
        .scan_en   (1'b0),
        .status    (status)
    );

    // ---- the FPGA end ------------------------------------------------------
    logic [LINK_W-1:0] sl_io_o;
    logic              sl_io_oe;
    assign io = sl_io_oe ? sl_io_o : {LINK_W{1'bz}};

    logic [7:0] sl_hwstrb;

    amoeba_link_slave #(
        .TRAIN_LEN (TRAIN_LEN),
        .PA_BITS   (PA_BITS),
        .IN_REG    (LINK_IN_REG)
    ) slave (
        .clk          (clk),
        .rstn         (rst_n),
        .io_i         (io),
        .io_o         (sl_io_o),
        .io_oe        (sl_io_oe),
        .dir          (dir),
        .req          (req),
        .wr           (wr),
        .burst        (burst),
        .ready        (ready),
        .rvalid       (rvalid),
        .HSEL         (HSELEXT),
        .HADDR        (HADDR),
        .HTRANS       (HTRANS),
        .HWRITE       (HWRITE),
        .HSIZE        (HSIZE),
        .HBURST       (HBURST),
        .HPROT        (HPROT),
        .HMASTLOCK    (HMASTLOCK),
        .HWDATA       (HWDATA),
        .HWSTRB       (sl_hwstrb),
        .HRDATA       (HRDATAEXT),
        .HREADY       (HREADYEXT),
        .HRESP        (HRESPEXT),
        .clear        (link_clear),
        .trained      (link_trained),
        .failed       (link_failed),
        .stat_xact    (link_xact),
        .stat_rd      (link_rd),
        .stat_wr      (link_wr),
        .stat_retrain (link_retrain),
        .stat_wdog    (link_wdog),
        .stat_err     (link_err)
    );

    assign HWSTRB  = sl_hwstrb[XLEN/8-1:0];
    assign HCLK    = clk;
    assign HRESETn = rst_n;
    assign HREADY  = HREADYEXT;

    // Read-only, for waves: the same downward reference the trace taps use.
    assign reset = top.chip.soc.reset;

    logic unused;
    assign unused = &{1'b0, ExternalStall};

endmodule
