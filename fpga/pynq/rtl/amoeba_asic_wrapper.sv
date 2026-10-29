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
// AMOEBA_LINK_PINS (stage C, docs/impl_plan_fpga_linux.md s5): the two halves
// are split across real pins.  The ASIC's 23 link pins (io, dir, req, wr,
// burst, ready, rvalid, clk) come out as link_a_*, the slave's as link_b_*,
// and a ribbon between two headers closes the loop.  The clock crosses it
// too: aclk leaves on link_b_clk through an ODDR and returns on link_a_clk
// to clock amoeba_top -- so the chip is clocked as the die will be, by a
// clock that arrived through a pad, with its data returning the other way.
// Without the define the loop is closed inside the fabric, as in stages A/B.
//
// Nothing here drives anything inside amoeba_top except its pins.
///////////////////////////////////////////////////////////////////////////////

`include "amoeba_config_select.vh"

module amoeba_asic_wrapper import cvw::*; import amoeba_link_pkg::*; #(
    parameter int TRAIN_LEN = TRAIN_LEN_DEFAULT,
    // Register the link's inbound pins once in the slave before use.  The
    // structure a real pad needs; one cycle of latency per transaction.
    parameter bit LINK_IN_REG = 1'b1,
    // LINK_PINS: the MMCM that forwards the clock.  VCO = clk x MULT must
    // land in 600..1200 MHz; build.tcl picks MULT from FCLK_MHZ.  The phase
    // step is 1/56 of the VCO period, 56 x MULT steps per clk period.
    parameter int MMCM_MULT     = 32,
    parameter int CLK_PERIOD_PS = 40000    // an integer: it crosses IPI and a Verilog-2001 shim
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

`ifdef AMOEBA_LINK_PINS
    ,
    // ---- stage C: the link on real pins ------------------------------------
    // A = the ASIC's pads; B = the FPGA end.  Loop A<->B with a ribbon.
    input  wire                   link_a_clk,      // <- link_b_clk, via the ribbon
    inout  wire  [LINK_W-1:0]     link_a_io,
    output wire                   link_a_dir,
    output wire                   link_a_req,
    output wire                   link_a_wr,
    output wire                   link_a_burst,
    input  wire                   link_a_ready,
    input  wire                   link_a_rvalid,
    output wire                   link_b_clk,      // aclk, forwarded
    inout  wire  [LINK_W-1:0]     link_b_io,
    input  wire                   link_b_dir,
    input  wire                   link_b_req,
    input  wire                   link_b_wr,
    input  wire                   link_b_burst,
    output wire                   link_b_ready,
    output wire                   link_b_rvalid,
    // The eye instrument: an IDELAYE2 on every inbound pin of side B, all
    // on one tap value.  refclk200 feeds the IDELAYCTRL (200 MHz, 78 ps per
    // tap on 7-series); idelay_ld loads idelay_tap; idelay_rdy is the
    // calibration done flag.  The chip's side has no such thing -- it is
    // the DUT.
    input  wire                   refclk200,
    input  wire  [4:0]            idelay_tap,
    input  wire                   idelay_ld,
    output wire                   idelay_rdy,
    // The coarse eye instrument: the forwarded clock comes from an MMCM
    // whose fine phase shift moves the chip's whole timing across the
    // slave's period.  ps_en steps once in the ps_incr direction; ps_done
    // says the step has landed.  Held in reset by rst (the PL reset), not
    // the core's, so a phase survives a core reset -- the sweep sets it,
    // then trains.
    input  wire                   rst,
    input  wire                   ps_en,
    input  wire                   ps_incr,
    output wire                   ps_done,
    output wire                   mmcm_locked
`endif
);

    `include "parameter-defs.vh"

    // ---- the link ------------------------------------------------------------
    // a_*: the chip's side of the link.  b_*: the slave's.  Joined below,
    // either by wire (A/B) or by the pins (stage C).  The chip's
    // bidirectional bus is a macro, not a wire: an inout has to be the net
    // itself at the chip's port -- an assign between two nets is one-way.
    wire               a_dir, a_req, a_wr, a_burst, a_ready, a_rvalid, a_clk;
    logic              b_dir, b_req, b_wr, b_burst, b_ready, b_rvalid;
    logic              rst_n;
    assign rst_n = ~reset_ext;

`ifdef AMOEBA_LINK_PINS
    `define AMOEBA_A_IO link_a_io
    assign link_a_dir   = a_dir;
    assign link_a_req   = a_req;
    assign link_a_wr    = a_wr;
    assign link_a_burst = a_burst;
    assign a_ready    = link_a_ready;
    assign a_rvalid   = link_a_rvalid;
    assign a_clk      = link_a_clk;
    assign link_b_ready  = b_ready;
    assign link_b_rvalid = b_rvalid;

    // Side B's inbound pins, through the delay line.  b_in_raw is what the
    // pad sees; b_in_dly is what the slave samples.  [15:0] io, then dir,
    // req, wr, burst.
    logic [LINK_W-1:0] sl_io_o;
    logic              sl_io_oe;
    wire  [LINK_W+3:0] b_in_raw, b_in_dly;
    assign {b_burst, b_wr, b_req, b_dir} = b_in_dly[LINK_W+3:LINK_W];
    assign b_in_raw[LINK_W+3:LINK_W] = {link_b_burst, link_b_wr, link_b_req, link_b_dir};
  `ifdef SYNTHESIS
    // Clock forwarding.  clk -> MMCM (x MULT / MULT, fine phase shift) ->
    // BUFG -> ODDR toggling 1/0 -> the pin: aclk, at the phase the sweep
    // set, with the same clock-to-out as a data pin.  The slave keeps
    // running on clk itself, so the phase is exactly the chip's timing
    // relative to the FPGA end -- what a real board's clock insertion is.
    wire clk_fb, clk_fb_buf, clk_ps, clk_ps_buf;
    MMCME2_ADV #(
        .CLKIN1_PERIOD(CLK_PERIOD_PS / 1000.0), .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(MMCM_MULT), .CLKOUT0_DIVIDE_F(MMCM_MULT),
        .CLKOUT0_USE_FINE_PS("TRUE"), .COMPENSATION("ZHOLD"), .BANDWIDTH("OPTIMIZED")
    ) mmcm (
        .CLKIN1(clk), .CLKIN2(1'b0), .CLKINSEL(1'b1),
        .CLKFBIN(clk_fb_buf), .CLKFBOUT(clk_fb), .CLKFBOUTB(),
        .CLKOUT0(clk_ps), .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(mmcm_locked), .RST(rst), .PWRDWN(1'b0),
        .PSCLK(clk), .PSEN(ps_en), .PSINCR(ps_incr), .PSDONE(ps_done),
        .DADDR(7'd0), .DCLK(1'b0), .DEN(1'b0), .DI(16'd0), .DWE(1'b0), .DO(), .DRDY(),
        .CLKINSTOPPED(), .CLKFBSTOPPED());
    BUFG bufg_fb (.I(clk_fb), .O(clk_fb_buf));
    BUFG bufg_ps (.I(clk_ps), .O(clk_ps_buf));
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"), .INIT(1'b0), .SRTYPE("SYNC")) clk_fwd (
        .Q(link_b_clk), .C(clk_ps_buf), .CE(1'b1), .D1(1'b1), .D2(1'b0), .R(1'b0), .S(1'b0));
    // Explicit IOBUFs so the delay line can sit between the pad and the
    // slave's flops; the chip's side keeps the inferred ones.
    for (genvar i = 0; i < LINK_W; i++) begin : g_iob
        IOBUF iob (.IO(link_b_io[i]), .I(sl_io_o[i]), .T(~sl_io_oe), .O(b_in_raw[i]));
    end
    (* IODELAY_GROUP = "amoeba_link" *)
    IDELAYCTRL idelayctrl (.REFCLK(refclk200), .RST(reset_ext), .RDY(idelay_rdy));
    for (genvar i = 0; i < LINK_W + 4; i++) begin : g_idly
        (* IODELAY_GROUP = "amoeba_link" *)
        IDELAYE2 #(
            .IDELAY_TYPE("VAR_LOAD"), .DELAY_SRC("IDATAIN"), .IDELAY_VALUE(0),
            .HIGH_PERFORMANCE_MODE("TRUE"), .SIGNAL_PATTERN("DATA"),
            .REFCLK_FREQUENCY(200.0), .CINVCTRL_SEL("FALSE"), .PIPE_SEL("FALSE")
        ) idly (
            .C(clk), .LD(idelay_ld), .CNTVALUEIN(idelay_tap), .CNTVALUEOUT(),
            .IDATAIN(b_in_raw[i]), .DATAOUT(b_in_dly[i]),
            .CE(1'b0), .INC(1'b0), .LDPIPEEN(1'b0), .REGRST(1'b0), .DATAIN(1'b0), .CINVCTRL(1'b0));
    end
  `else
    assign link_b_clk = clk;
    assign link_b_io  = sl_io_oe ? sl_io_o : {LINK_W{1'bz}};
    assign b_in_raw[LINK_W-1:0] = link_b_io;
    assign b_in_dly   = b_in_raw;          // no delay line in simulation
    assign idelay_rdy = 1'b1;
    // No MMCM in simulation: a step "lands" the next cycle and nothing moves;
    // tb_pynq_top's +LINK_LOOP_PS is the simulated phase instead.
    logic ps_done_q;
    always_ff @(posedge clk) ps_done_q <= ps_en;
    assign ps_done     = ps_done_q;
    assign mmcm_locked = ~rst;
    logic unused_idly;
    assign unused_idly = &{1'b0, refclk200, idelay_tap, idelay_ld, ps_incr};
  `endif
`else
    // Closed inside the fabric: one net, resolved by the two tristate
    // drivers (Vivado turns it into mux logic).
    wire [LINK_W-1:0] io;
    `define AMOEBA_A_IO io
    logic [LINK_W-1:0] sl_io_o;
    logic              sl_io_oe;
    wire  [LINK_W-1:0] b_io_in;
    assign io      = sl_io_oe ? sl_io_o : {LINK_W{1'bz}};
    assign b_io_in = io;
    assign b_dir    = a_dir;
    assign b_req    = a_req;
    assign b_wr     = a_wr;
    assign b_burst  = a_burst;
    assign a_ready  = b_ready;
    assign a_rvalid = b_rvalid;
    assign a_clk    = clk;
`endif

    // ---- the chip --------------------------------------------------------------
    amoeba_top #(.TRAIN_LEN(TRAIN_LEN)) top (
        .clk       (a_clk),
        .rst_n     (rst_n),
        .io        (`AMOEBA_A_IO),
        .dir       (a_dir),
        .req       (a_req),
        .wr        (a_wr),
        .burst     (a_burst),
        .ready     (a_ready),
        .rvalid    (a_rvalid),
        .irq       (irq),
        .uart_tx   (UARTSout),
        .uart_rx   (UARTSin),
        .test_mode (1'b0),
        .scan_en   (1'b0),
        .status    (status)
    );

    // ---- the FPGA end ------------------------------------------------------
    logic [7:0] sl_hwstrb;

    amoeba_link_slave #(
        .TRAIN_LEN (TRAIN_LEN),
        .PA_BITS   (PA_BITS),
        .IN_REG    (LINK_IN_REG)
    ) slave (
        .clk          (clk),
        .rstn         (rst_n),
`ifdef AMOEBA_LINK_PINS
        .io_i         (b_in_dly[LINK_W-1:0]),
`else
        .io_i         (b_io_in),
`endif
        .io_o         (sl_io_o),
        .io_oe        (sl_io_oe),
        .dir          (b_dir),
        .req          (b_req),
        .wr           (b_wr),
        .burst        (b_burst),
        .ready        (b_ready),
        .rvalid       (b_rvalid),
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

`undef AMOEBA_A_IO

endmodule
