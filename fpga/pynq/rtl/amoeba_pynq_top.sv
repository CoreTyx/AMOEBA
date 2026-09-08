///////////////////////////////////////////////////////////////////////////////
// amoeba_pynq_top.sv
//
// PL top level for the PYNQ-Z2 build.  Everything the PS can see or do is a
// port on this module; everything inside is either the DUT or the scaffolding
// that lets the PS drive it.
//
//   PS (Cortex-A9)                 PL (this module)
//   --------------                 ----------------
//   GP0 -> AXI4-Lite (ctl) ....... amoeba_ctl       reset, triggers, counters,
//                                                   console FIFO, tohost
//   GP0 -> AXI4-Lite (mem) ....... amoeba_mem_bram  image load (BRAM builds)
//   HP0 <- AXI DMA S2MM .......... amoeba_trace     commit records
//   HP0 <-> ahblite_axi_bridge ... (block design)   DDR memory (AXI builds)
//
// ONE CLOCK.  aclk is FCLK_CLK0 from the PS, and the core, the AXI-Lite block,
// the monitors, the trace FIFO and both PS-facing AXI interfaces all run on it.
// There is no clock-domain crossing anywhere in this design, which is worth
// keeping true: every CDC added here is a bug that only shows up at temperature.
//
// TWO RESETS, AND THE PS OWNS THE SECOND ONE.  aresetn resets the PL
// scaffolding.  The core's reset is a bit in amoeba_ctl that comes out of
// configuration ASSERTED, so after the bitstream loads nothing is fetching.
// The bring-up sequence follows from that, and is the same for every image:
//
//   1. load the image        (BRAM window, or the DDR carve-out)
//   2. configure the trace   (mode, triggers) -- safe, the core is halted
//   3. clear the monitors    (CTRL.MON_CLEAR | CTRL.TRACE_CLEAR)
//   4. release CTRL.CORE_RESET
//   5. poll UART_DATA for the console, STATUS for tohost, drain the DMA
//
// TWO MEMORY BACKENDS, ONE DESIGN.  MEM_BRAM is the only difference between
// the FreeRTOS bring-up bitstream and the Linux bitstream.  Keeping it a
// parameter rather than a fork means a bug found in one is fixed in both, and
// the BRAM build stays useful afterwards as the deterministic one: DDR refresh
// jitters interrupt arrival, so a failing DDR run is not necessarily
// reproducible, and reproducibility is what the trace windows depend on.
//
// NO SERIAL PINS.  The console the PS reads is the AHB snoop in
// amoeba_bus_mon, and a physical UART would be redundant with it for two
// reasons and useless for a third.  It is redundant because the snoop sees
// every byte the guest writes to the transmit register, before serialization
// and with no baud-rate delay.  It is useless because the 16550's divisor is
// programmed by the guest against PCLK, which is FCLK_CLK0 here -- 25 MHz on
// the board against the 100 MHz the simulation assumes -- so every divisor the
// FreeRTOS and Linux drivers write is off by 4x and the line emits garbage
// until someone retunes it per-clock.  And it is not worth retuning, because
// uart_apb is PL scaffolding: the tapeout boundary is wallypipelinedcore, one
// level down, so nothing about the serializer's behaviour transfers to silicon.
//
// The peripheral itself stays instantiated and fully alive.  It has to: LSR's
// THRE/TEMT is what stops the 8250 driver's wait_for_xmitr() spinning, and that
// register is read over APB into the core, which preserves the TX state machine
// and baud generator whether or not SOUT reaches a pin.  uart_txd_obs carries
// SOUT out as an observation point for an ILA; the block design leaves it
// unconnected.  UARTSin is tied to the idle-mark level.
//
// If a genuine snoop-vs-serial equivalence check is ever wanted, the cheap form
// is a PL-side deserializer rather than pins: amoeba_bus_mon already shadows
// LCR[7] for DLAB, so it can capture the DLL/DLM writes at the same time and
// configure the receiver to whatever divisor the guest chose, with no manual
// tuning and no dependence on what FCLK ended up being.
//
// THE TAPS ARE HIERARCHICAL REFERENCES, ON PURPOSE.  amoeba_soc_wrapper stays
// byte-identical to what the utilization gate measures and to what goes to the
// ASIC; no debug ports are cut into it.  The commit-trace signals are read out
// of the SoC instance by downward reference below, which is what CVW's own
// third_party/cvw/fpga/src/fpgaTopArtyA7.sv does to feed rvvisynth -- Vivado
// synthesizes read-only cross-module references.  They are reads only: nothing
// here drives anything inside the DUT except ExternalStall, a real port.
///////////////////////////////////////////////////////////////////////////////

// At file scope, before the module: the port list below uses PA_BITS.  The
// guard inside matters here -- this top and amoeba_soc_wrapper both need the
// config at compilation-unit scope and are compiled together.
`include "amoeba_config_select.vh"

module amoeba_pynq_top import cvw::*; #(
    // 1: block RAM behind ahb_to_memitf, image loaded over the AXI window.
    // 0: the AHB leaves this module for ahblite_axi_bridge in the BD.
    //
    // A bit rather than a "BRAM"/"AXI" string because this parameter has to
    // cross into amoeba_pynq_top_v.v, and a SystemVerilog string parameter
    // taking a Verilog string literal is not something to rely on.
    parameter bit    MEM_BRAM        = 1'b1,
    // 128 KiB is 32 of the XC7Z020's 140 block RAM tiles, against a FreeRTOS
    // image of about 79 KiB.  Block RAM is the binding resource in this design
    // now that the caches are 16 KiB each, so this is sized to the image rather
    // than to the address range -- raise it only against a real fit report.
    parameter int    MEM_KB          = 128,
    parameter bit    TRACE           = 1'b1,
    parameter int    TRACE_FIFO_LOG2 = 9,
    parameter int    PKT_RECORDS     = 256,
    // Base of the DDR carve-out in the PS's physical map, and the reason the
    // AHB address leaving this module is not the address the core emitted.
    //
    // Passed from opt(ddr_carveout) in tcl/bd_pynq.tcl, which is the SAME
    // value that tcl assigns as this master's address segment.  One source,
    // so the translation below and the interconnect's decode cannot disagree.
    // Ignored when MEM_BRAM = 1.
    parameter int unsigned DDR_CARVEOUT_BASE = 32'h1000_0000
)(
    input  logic                  aclk,
    input  logic                  aresetn,

    // ---- AXI4-Lite control, from GP0 ---------------------------------------
    input  logic [11:0]           s_axi_ctl_awaddr,
    input  logic                  s_axi_ctl_awvalid,
    output logic                  s_axi_ctl_awready,
    input  logic [31:0]           s_axi_ctl_wdata,
    input  logic [3:0]            s_axi_ctl_wstrb,
    input  logic                  s_axi_ctl_wvalid,
    output logic                  s_axi_ctl_wready,
    output logic [1:0]            s_axi_ctl_bresp,
    output logic                  s_axi_ctl_bvalid,
    input  logic                  s_axi_ctl_bready,
    input  logic [11:0]           s_axi_ctl_araddr,
    input  logic                  s_axi_ctl_arvalid,
    output logic                  s_axi_ctl_arready,
    output logic [31:0]           s_axi_ctl_rdata,
    output logic [1:0]            s_axi_ctl_rresp,
    output logic                  s_axi_ctl_rvalid,
    input  logic                  s_axi_ctl_rready,

    // ---- AXI4-Stream commit trace, to the DMA's S2MM channel ---------------
    output logic [63:0]           m_axis_trace_tdata,
    output logic [7:0]            m_axis_trace_tkeep,
    output logic                  m_axis_trace_tvalid,
    input  logic                  m_axis_trace_tready,
    output logic                  m_axis_trace_tlast,

    // ---- AXI4-Lite image load, from GP0 (MEM_BACKEND == "BRAM") ------------
    // Tied off in AXI/DDR builds, where the PS writes the carve-out directly.
    input  logic [31:0]           s_axi_mem_awaddr,
    input  logic                  s_axi_mem_awvalid,
    output logic                  s_axi_mem_awready,
    input  logic [31:0]           s_axi_mem_wdata,
    input  logic [3:0]            s_axi_mem_wstrb,
    input  logic                  s_axi_mem_wvalid,
    output logic                  s_axi_mem_wready,
    output logic [1:0]            s_axi_mem_bresp,
    output logic                  s_axi_mem_bvalid,
    input  logic                  s_axi_mem_bready,
    input  logic [31:0]           s_axi_mem_araddr,
    input  logic                  s_axi_mem_arvalid,
    output logic                  s_axi_mem_arready,
    output logic [31:0]           s_axi_mem_rdata,
    output logic [1:0]            s_axi_mem_rresp,
    output logic                  s_axi_mem_rvalid,
    input  logic                  s_axi_mem_rready,

    // ---- AHB-Lite master, for ahblite_axi_bridge (MEM_BACKEND == "AXI") ----
    // The outputs are driven in both builds so they stay usable as ILA probes;
    // the three inputs are only consumed when MEM_BACKEND == "AXI" and should
    // be tied off in the block design otherwise.
    output logic                  m_ahb_hsel,
    // 32 bits, not PA_BITS.  ahblite_axi_bridge's s_ahb_haddr is 32 bits wide
    // and the whole core address map fits below 4 GiB, so the top 24 bits of
    // HADDR are always zero.  Declaring the port at its real width makes the
    // truncation explicit here instead of silent in the block design.
    output logic [31:0]           m_ahb_haddr,
    output logic [63:0]           m_ahb_hwdata,
    output logic [7:0]            m_ahb_hwstrb,
    output logic                  m_ahb_hwrite,
    output logic [2:0]            m_ahb_hsize,
    output logic [2:0]            m_ahb_hburst,
    output logic [3:0]            m_ahb_hprot,
    output logic [1:0]            m_ahb_htrans,
    output logic                  m_ahb_hmastlock,
    input  logic [63:0]           m_ahb_hrdata,
    input  logic                  m_ahb_hready,
    input  logic                  m_ahb_hresp,
    // Reset for the external AHB slave, active low, asserted whenever the core
    // is.  ahblite_axi_bridge latches HRESP on failure and clears it only on a
    // transfer that succeeds, so a bridge reset only by the PL's aresetn keeps
    // an error from one run for the life of the bitstream.  Tying its reset to
    // the core's makes every run start from a clean slave.
    output logic                  m_ahb_hresetn,

    // The core's combined bus HREADY, for the bridge's s_ahb_hready_in.  An
    // AHB slave qualifies address phases on the BUS ready, not its own: with
    // hready_in looped back to the bridge's own hready_out (the previous
    // wiring), an address phase pipelined over a stalled internal-slave data
    // phase is accepted early and then detected AGAIN when the bus really
    // advances.  CVW's own fpgaTopArtyA7.sv wires the combined HREADY here.
    output logic                  m_ahb_hready_bus,

    // No console pins.  See "NO SERIAL PINS" in the header.
    output logic                  uart_txd_obs
);

    `include "parameter-defs.vh"

    localparam int PA = P.PA_BITS;

    // amoeba_pynq_top_v.v hardcodes 56, because a Verilog-2001 wrapper cannot
    // read the SystemVerilog config that derives it.  This is the guard rail:
    // an elaboration error rather than a silently truncated address bus.
    if (PA_BITS != 56) begin : g_pa_bits_mismatch
        $error("amoeba_pynq_top_v.v hardcodes PA_BITS=56, this config wants %0d", PA_BITS);
    end

    // The rebase above is only sound if the whole translated window fits in
    // the 32 bits the bridge's address port carries.  Checking it here turns a
    // mis-set ddr_carveout/ddr_size into an elaboration error rather than a
    // board that wraps onto the PS kernel at run time.
    if (!MEM_BRAM && ((64'(DDR_CARVEOUT_BASE) + P.EXT_MEM_RANGE) >= 64'h1_0000_0000)) begin : g_carveout_overflow
        $error("DDR carve-out 0x%0h + EXT_MEM_RANGE 0x%0h overruns 32 bits",
               DDR_CARVEOUT_BASE, P.EXT_MEM_RANGE);
    end

    // A carve-out that is not aligned to its own size makes the rebase carry
    // across the range boundary, so an address near the top of EXT_MEM lands
    // outside the assigned segment.  bd_pynq.tcl picks both; keep them
    // consistent.
    if (!MEM_BRAM && ((64'(DDR_CARVEOUT_BASE) & P.EXT_MEM_RANGE) != 64'd0)) begin : g_carveout_align
        $error("DDR carve-out 0x%0h is not aligned to EXT_MEM_RANGE 0x%0h",
               DDR_CARVEOUT_BASE, P.EXT_MEM_RANGE);
    end

    // ---- reset -------------------------------------------------------------
    logic rst;                              // PL reset, synchronous active high
    assign rst = ~aresetn;

    logic core_reset_sw, core_reset_ext, core_hold_req;
    assign core_hold_req = rst | core_reset_sw;

    // STAGGERED RELEASE: THE BRIDGE COMES OUT OF RESET BEFORE THE CORE DOES.
    //
    // Two requirements that look contradictory and are not:
    //
    //  - The bridge must be reset once per run.  ahblite_axi_bridge's HRESP is
    //    a latched register cleared only by a transfer that succeeds, so an
    //    error taken in one run survives into the next; and beat_ok is gated
    //    on !HRESP, so the beat counter then reads zero forever.  A probe
    //    whose numbers describe a flag latched in some earlier run is not a
    //    measurement.  Resetting the bridge only from aresetn gives that up.
    //
    //  - The bridge must not be reset in the same cycle the core starts
    //    fetching.  It spans two clock domains and only its AHB half is reset
    //    here; releasing both halves' view of the world simultaneously with
    //    the first transfer leaves nothing settled.
    //
    // So release the bridge on the software's request and hold the CORE for
    // BRIDGE_LEAD cycles longer.  The bridge gets a quiet window it can only
    // spend idling -- ahb_run is still built from core_reset_ext, so no
    // transfer can leave during it.
    localparam int BRIDGE_LEAD = 16;
    logic [4:0] lead_cnt;
    always_ff @(posedge aclk) begin
        if (rst)                 lead_cnt <= 5'(BRIDGE_LEAD);
        else if (core_hold_req)  lead_cnt <= 5'(BRIDGE_LEAD);
        else if (|lead_cnt)      lead_cnt <= lead_cnt - 1'b1;
    end

    assign core_reset_ext = core_hold_req | (|lead_cnt);

    // ---- DUT ---------------------------------------------------------------
    logic [P.AHBW-1:0]   HRDATAEXT;
    logic                HREADYEXT, HRESPEXT, HSELEXT;
    logic                HCLK, HRESETn;
    logic [PA-1:0]       HADDR;
    logic [P.AHBW-1:0]   HWDATA;
    logic [P.XLEN/8-1:0] HWSTRB;
    logic                HWRITE, HMASTLOCK, HREADY;
    logic [2:0]          HSIZE, HBURST;
    logic [3:0]          HPROT;
    logic [1:0]          HTRANS;
    logic                ExternalStall;
    logic                soc_reset;

    amoeba_soc_wrapper dut (
        .clk           (aclk),
        .reset_ext     (core_reset_ext),
        .reset         (soc_reset),
        .ExternalStall (ExternalStall),
        .HRDATAEXT     (HRDATAEXT),
        .HREADYEXT     (HREADYEXT),
        .HRESPEXT      (HRESPEXT),
        .HSELEXT       (HSELEXT),
        .HCLK          (HCLK),
        .HRESETn       (HRESETn),
        .HADDR         (HADDR),
        .HWDATA        (HWDATA),
        .HWSTRB        (HWSTRB),
        .HWRITE        (HWRITE),
        .HSIZE         (HSIZE),
        .HBURST        (HBURST),
        .HPROT         (HPROT),
        .HTRANS        (HTRANS),
        .HMASTLOCK     (HMASTLOCK),
        .HREADY        (HREADY),
        .UARTSin       (1'b1),         // idle-mark: nothing is driving RX
        .UARTSout      (uart_txd_obs)
    );

    // ---- THE AHB LEAVES THIS MODULE ONLY WHILE THE CORE IS RUNNING --------
    //
    // wallypipelinedcore does NOT park its AHB outputs while it is held in
    // reset.  Measured on hardware with the core halted and no image loaded:
    //
    //   HSEL=1 HTRANS=NONSEQ HWRITE=0 HBURST=INCR8 HSIZE=3 HREADY=1
    //
    // held statically, every cycle, for as long as reset is asserted.  It is
    // not a transfer in flight -- it is the ebu's combinational HTRANS decode
    // settling on NONSEQ out of reset -- but nothing downstream can tell the
    // difference, and an AHB slave is required to believe it.
    //
    // amoeba_mem_bram never saw this because it takes HRESETn and is therefore
    // held alongside the core.  ahblite_axi_bridge is reset from aresetn,
    // which does not deassert between runs, so it accepted that static NONSEQ
    // as a real burst 25 million times a second, issued AXI it could not
    // complete, and latched its (sticky) HRESP.  By the time the core was
    // released the bridge had been in an error state for a second and a half,
    // and the core's genuine first fetch was answered from that state.  The
    // symptom was "0 retired, 0 traps" and an error with no wait cycles, which
    // reads exactly like a bridge rejecting our fetch.
    //
    // Gating here rather than fixing the reset wiring alone: this makes it
    // structurally impossible for any transfer to leave while the core is
    // held, whatever the core's outputs do and whatever the slave's reset is
    // connected to.  HRESETn is the core's own synchronized reset; the
    // core_reset_ext term additionally covers the two-cycle window after
    // configuration where wallypipelinedsoc's reset synchroniser has not yet
    // shifted the asserted value through.
    logic ahb_run;
    assign ahb_run = HRESETn & ~core_reset_ext;

    // Released BRIDGE_LEAD cycles before core_reset_ext, by construction:
    // core_reset_ext holds until lead_cnt drains, this does not.
    assign m_ahb_hresetn   = ~core_hold_req;
    // ALWAYS SELECTED WHILE RUNNING, AND THAT IS THE FIX FOR ABORTED BURSTS.
    //
    // Wally terminates an in-flight cache-line fill whenever the fetch is
    // flushed -- buscachefsm takes .Flush(FlushD) and drops to ADR_PHASE, so
    // every branch redirect during a fill ends an INCR8 early.  That is legal
    // AHB and every simulation backend tolerates it.  ahblite_axi_bridge also
    // tolerates it -- it has a designed burst-termination path that swallows
    // the leftover AXI read beats -- but the ONLY entries into that path are
    // idle_detected/nonseq_detected, and both are qualified on S_AHB_HSEL=1.
    //
    // On an abort the IFU stops driving the fetch address, HADDR moves off
    // the external region, and HSELEXT drops in the very cycle the bridge
    // needed to see HSEL=1 + HTRANS=IDLE.  ongoing_burst then latches, RREADY
    // freezes with undelivered beats of an ARLEN=7 read AXI does not allow to
    // abandon, and the next fetch either wedges behind the corpse or is
    // served its stale beats.  Measured: two clean bursts, one abort, then a
    // dead bus and 0 retired for the rest of the run.
    //
    // So: the bridge is the only slave on this exported bus -- keep it
    // selected for as long as the core is running, and express "the core is
    // not talking to you" purely through HTRANS=IDLE.  A selected slave
    // seeing IDLE does nothing, except notice a terminated burst, which is
    // the entire point.
    assign m_ahb_hsel      = ahb_run;
    // Core PA -> PS PA.
    //
    // ahblite_axi_bridge does NOT translate: it drives the AHB address onto
    // AXI unchanged.  The core emits EXT_MEM_BASE-relative addresses starting
    // at 0x8000_0000; the block design assigns this master a segment at
    // DDR_CARVEOUT_BASE.  Without the rebase below the interconnect decodes
    // nothing at all, the access never completes, and -- because a Zynq GP/HP
    // port has no default slave and no timeout -- the core hangs forever on
    // its first instruction fetch.  That is the failure this line prevents,
    // and it is invisible in simulation because the Verilator tier drives
    // ahb_to_memitf directly and never sees the bridge.
    //
    // In a BRAM build the bus does not leave this module; the port is an
    // observation point for an ILA, so it carries the untranslated address.
    // The mask is a CLAMP, and it is doing safety work, not tidiness.
    //
    // The obvious form of this is a subtract and an add.  It is not used,
    // because the block design cannot bound this master: ahblite_axi_bridge
    // exposes no AXI address space of its own -- IPI models it as a
    // pass-through whose addresses come from the AHB side -- so there is
    // nothing to attach an address segment to, and the interconnect therefore
    // hands it the PS's ENTIRE 512 MB of DDR.  A stray core address would land
    // in the running Linux kernel, which presents as the board hanging at
    // random and is close to undiagnosable.
    //
    // AND-ing the offset with EXT_MEM_RANGE before OR-ing in the carve-out
    // base makes escape structurally impossible: every address this module can
    // emit is inside the carve-out by construction, whatever the core does.
    // An out-of-range access wraps within the window instead of leaving it.
    // The elaboration guards below are what make the OR equivalent to an add.
    assign m_ahb_haddr     = MEM_BRAM
                           ? 32'(HADDR)
                           : 32'(64'(DDR_CARVEOUT_BASE)
                                 | ((64'(HADDR) - P.EXT_MEM_BASE)
                                    & P.EXT_MEM_RANGE));
    assign m_ahb_hwdata    = 64'(HWDATA);
    assign m_ahb_hwstrb    = 8'(HWSTRB);
    assign m_ahb_hwrite    = HWRITE;
    assign m_ahb_hsize     = HSIZE;
    assign m_ahb_hburst    = HBURST;
    assign m_ahb_hprot     = HPROT;
    // IDLE unless the core is both running and genuinely addressing external
    // memory.  The HSELEXT term matters now that m_ahb_hsel no longer carries
    // it: without the mask an internal CLINT/UART access (HSELEXT=0,
    // HTRANS=NONSEQ) would read as a phantom transaction to the bridge.
    assign m_ahb_htrans    = (ahb_run & HSELEXT) ? HTRANS : 2'b00;
    assign m_ahb_hmastlock = HMASTLOCK;
    assign m_ahb_hready_bus = HREADY;

    // ---- memory backend ----------------------------------------------------
    if (MEM_BRAM) begin : g_mem
        logic [63:0] bram_hrdata;
        logic        bram_hready, bram_hresp;

        amoeba_mem_bram #(
            .PA_BITS  (PA),
            .MEM_BASE (P.EXT_MEM_BASE),
            .MEM_KB   (MEM_KB)
        ) mem (
            .clk           (HCLK),
            .rstn          (HRESETn),
            .s_axi_aresetn (aresetn),
            .HSEL          (HSELEXT),
            .HADDR         (HADDR),
            .HTRANS        (HTRANS),
            .HWRITE        (HWRITE),
            .HSIZE         (HSIZE),
            .HWDATA        (64'(HWDATA)),
            .HWSTRB        (8'(HWSTRB)),
            .HRDATA        (bram_hrdata),
            .HREADY        (bram_hready),
            .HRESP         (bram_hresp),
            .s_axi_awaddr  (s_axi_mem_awaddr),
            .s_axi_awvalid (s_axi_mem_awvalid),
            .s_axi_awready (s_axi_mem_awready),
            .s_axi_wdata   (s_axi_mem_wdata),
            .s_axi_wstrb   (s_axi_mem_wstrb),
            .s_axi_wvalid  (s_axi_mem_wvalid),
            .s_axi_wready  (s_axi_mem_wready),
            .s_axi_bresp   (s_axi_mem_bresp),
            .s_axi_bvalid  (s_axi_mem_bvalid),
            .s_axi_bready  (s_axi_mem_bready),
            .s_axi_araddr  (s_axi_mem_araddr),
            .s_axi_arvalid (s_axi_mem_arvalid),
            .s_axi_arready (s_axi_mem_arready),
            .s_axi_rdata   (s_axi_mem_rdata),
            .s_axi_rresp   (s_axi_mem_rresp),
            .s_axi_rvalid  (s_axi_mem_rvalid),
            .s_axi_rready  (s_axi_mem_rready)
        );

        assign HRDATAEXT = P.AHBW'(bram_hrdata);
        assign HREADYEXT = bram_hready;
        assign HRESPEXT  = bram_hresp;
    end else begin : g_mem
        assign HRDATAEXT = P.AHBW'(m_ahb_hrdata);
        assign HREADYEXT = m_ahb_hready;
        assign HRESPEXT  = m_ahb_hresp;
        // No image window in a DDR build: the PS writes the carve-out itself.
        // The slave still answers so a stray access cannot hang the PS.
        assign s_axi_mem_awready = s_axi_mem_awvalid;
        assign s_axi_mem_wready  = s_axi_mem_wvalid;
        assign s_axi_mem_bresp   = 2'b00;
        assign s_axi_mem_bvalid  = 1'b0;
        assign s_axi_mem_arready = s_axi_mem_arvalid;
        assign s_axi_mem_rdata   = 32'hDEAD_C0DE;
        assign s_axi_mem_rresp   = 2'b00;
        assign s_axi_mem_rvalid  = 1'b0;
    end

    // ---- control block -----------------------------------------------------
    logic        mon_clear, trace_clear;
    logic [1:0]  trace_mode;
    logic [63:0] trig_start, trig_pc;
    logic [31:0] trig_count;
    logic [7:0]  uart_data;
    logic        uart_valid, uart_pop, uart_overflow;
    logic [15:0] uart_level;
    logic [63:0] cycles, retired, tohost_data;
    logic [31:0] traps;
    logic        tohost_valid;
    logic [15:0] trace_level;
    logic [1:0]  trace_state;
    logic        trace_overflow;

    // CAPS lets the PS-side tooling refuse to talk to a bitstream it does not
    // understand, instead of writing triggers into a build that has no trace
    // path and waiting for records that will never arrive.
    localparam logic [31:0] CAPS_WORD = {
        16'(MEM_KB),                            // [31:16] memory size in KiB
        7'h0,
        TRACE,                                  // [    8] trace path present
        7'h0,
        MEM_BRAM                                // [    0] 1 = BRAM, 0 = AXI/DDR
    };

    // ---- external AHB probe ------------------------------------------------
    // Reset from aresetn, not HRESETn, so the counters survive a core reset and
    // can be read after a run that never started.  Cleared by MON_CLEAR along
    // with the other monitors.
    logic [31:0] bus_state, bus_xact, bus_beat, bus_err, bus_stall;
    logic [31:0] bus_addr, bus_xaddr, bus_wait;
    logic [31:0] bus_errwait, bus_errxact, bus_prestate;
    logic [31:0] bus_capdat, bus_capstat, bus_rstxact, bus_caprdat;
    logic [5:0]  bus_capsel;

    amoeba_bus_probe #(
        .PA_BITS (PA)
    ) probe (
        .clk         (aclk),
        .rstn        (aresetn),
        .clear       (mon_clear),
        // The GATED signals: the probe reports what the slave can see, so
        // rst_xact reading non-zero now means the gate above has failed
        // rather than merely describing the core's behaviour in reset.
        .HSEL        (m_ahb_hsel),
        .HTRANS      (m_ahb_htrans),
        .HWRITE      (HWRITE),
        .HBURST      (HBURST),
        .HSIZE       (HSIZE),
        .HADDR       (HADDR),
        .HREADY      (HREADYEXT),
        .HRESP       (HRESPEXT),
        .HRDATA      (HRDATAEXT),
        // core_reset_ext, not core_reset_sw: the gate above is built from
        // core_reset_ext, so watching core_reset_sw let `armed` and `rst_xact`
        // describe a different reset from the one that actually parks the
        // bus.  The two disagreed and the probe reported a transfer count and
        // a core_reset bit that could not both be true.
        .core_reset  (core_reset_ext),
        .xaddr       (m_ahb_haddr),
        .state       (bus_state),
        .xact_count  (bus_xact),
        .beat_count  (bus_beat),
        .err_count   (bus_err),
        .stall_count (bus_stall),
        .first_addr  (bus_addr),
        .max_wait    (bus_wait),
        .err_wait    (bus_errwait),
        .err_xact    (bus_errxact),
        .pre_state   (bus_prestate),
        .cap_sel     (bus_capsel),
        .cap_dat     (bus_capdat),
        .cap_rdat    (bus_caprdat),
        .cap_stat    (bus_capstat),
        .rst_xact    (bus_rstxact),
        .first_xaddr (bus_xaddr)
    );

    amoeba_ctl #(
        .ADDR_W (12),
        .CAPS   (CAPS_WORD)
    ) ctl (
        .aclk          (aclk),
        .aresetn       (aresetn),
        .s_axi_awaddr  (s_axi_ctl_awaddr),
        .s_axi_awvalid (s_axi_ctl_awvalid),
        .s_axi_awready (s_axi_ctl_awready),
        .s_axi_wdata   (s_axi_ctl_wdata),
        .s_axi_wstrb   (s_axi_ctl_wstrb),
        .s_axi_wvalid  (s_axi_ctl_wvalid),
        .s_axi_wready  (s_axi_ctl_wready),
        .s_axi_bresp   (s_axi_ctl_bresp),
        .s_axi_bvalid  (s_axi_ctl_bvalid),
        .s_axi_bready  (s_axi_ctl_bready),
        .s_axi_araddr  (s_axi_ctl_araddr),
        .s_axi_arvalid (s_axi_ctl_arvalid),
        .s_axi_arready (s_axi_ctl_arready),
        .s_axi_rdata   (s_axi_ctl_rdata),
        .s_axi_rresp   (s_axi_ctl_rresp),
        .s_axi_rvalid  (s_axi_ctl_rvalid),
        .s_axi_rready  (s_axi_ctl_rready),
        .core_reset    (core_reset_sw),
        .mon_clear     (mon_clear),
        .trace_clear   (trace_clear),
        .trace_mode    (trace_mode),
        .trig_start    (trig_start),
        .trig_pc       (trig_pc),
        .trig_count    (trig_count),
        .uart_data     (uart_data),
        .uart_valid    (uart_valid),
        .uart_pop      (uart_pop),
        .uart_level    (uart_level),
        .uart_overflow (uart_overflow),
        .cycles        (cycles),
        .retired       (retired),
        .traps         (traps),
        .tohost_valid  (tohost_valid),
        .tohost_data   (tohost_data),
        .trace_level   (trace_level),
        .trace_state   (trace_state),
        .trace_overflow(trace_overflow),
        .trace_stalling(ExternalStall),
        .bus_state     (bus_state),
        .bus_xact      (bus_xact),
        .bus_beat      (bus_beat),
        .bus_err       (bus_err),
        .bus_stall     (bus_stall),
        .bus_addr      (bus_addr),
        .bus_xaddr     (bus_xaddr),
        .bus_wait      (bus_wait),
        .bus_errwait   (bus_errwait),
        .bus_errxact   (bus_errxact),
        .bus_prestate  (bus_prestate),
        .bus_capsel    (bus_capsel),
        .bus_capdat    (bus_capdat),
        .bus_capstat   (bus_capstat),
        .bus_rstxact   (bus_rstxact),
        .bus_caprdat   (bus_caprdat)
    );

    // ---- bus monitor -------------------------------------------------------
    // TOHOST_ADDR is DERIVED, not written down twice.  In a BRAM build the
    // memory is MEM_KB and amoeba_mem_bram truncates the index rather than
    // faulting, so any address above the array aliases back into it: the
    // linker's usual 0x8080_0000 against a 128 KiB array is
    //   0x8080_0000 & 0x1_FFFF = 0
    // which is the reset vector, so the exit write would overwrite the first
    // instructions of the program it is reporting on.  tohost therefore lives
    // in the top page of whatever memory actually exists.
    //
    // testcode/freertos/freertos_pynq.ld MUST use the same formula.  If these
    // two drift apart the run produces correct console output and then hangs
    // forever, because the monitor never sees the exit -- which is a
    // considerably worse afternoon than a crash.
    //
    // The page alignment is load-bearing beyond tidiness: htif_writeback() in
    // syscalls_amoeba.c evicts tohost by conflict, and with 4 KiB ways and
    // 64-byte lines the set index is (addr >> 6) & 63, which is 0 for every
    // 4 KiB-aligned address.  The sweep is written assuming set 0.
    localparam logic [63:0] TOHOST_ADDR = MEM_BRAM
        ? (P.EXT_MEM_BASE + 64'(MEM_KB) * 64'd1024 - 64'd4096)
        : 64'h8080_0000;

    amoeba_bus_mon #(
        .PA_BITS     (PA),
        .AHBW        (P.AHBW),
        .UART_BASE   (P.UART_BASE),
        .TOHOST_ADDR (TOHOST_ADDR)
    ) mon (
        .clk           (aclk),
        .rst           (rst),
        .clear         (mon_clear),
        .core_reset    (core_reset_ext),
        .HADDR         (HADDR),
        .HWDATA        (HWDATA),
        .HWRITE        (HWRITE),
        .HTRANS        (HTRANS),
        .HREADY        (HREADY),
        .uart_data     (uart_data),
        .uart_valid    (uart_valid),
        .uart_pop      (uart_pop),
        .uart_level    (uart_level),
        .uart_overflow (uart_overflow),
        .tohost_valid  (tohost_valid),
        .tohost_data   (tohost_data),
        .cycles        (cycles)
    );

    // ---- commit trace ------------------------------------------------------
    if (TRACE) begin : g_trace
        amoeba_trace #(
            .XLEN        (P.XLEN),
            .PKT_RECORDS (PKT_RECORDS),
            .FIFO_LOG2   (TRACE_FIFO_LOG2)
        ) trace (
            .clk            (aclk),
            .rst            (rst),
            .clear          (trace_clear),
            .core_reset     (core_reset_ext),
            .mode           (trace_mode),
            .trig_start     (trig_start),
            .trig_pc        (trig_pc),
            .trig_count     (trig_count),

            // Downward references into the DUT.  These paths match the ones
            // hdl/rv64_core_wrapper.sv already uses for its RVFI monitor, so
            // the FPGA trace and the simulation monitor observe the same nets
            // and a divergence between them is a real difference, not a
            // different definition of "retired".
            .StallE         (dut.soc.core.StallE),
            .StallM         (dut.soc.core.StallM),
            .StallW         (dut.soc.core.StallW),
            .FlushE         (dut.soc.core.FlushE),
            .FlushM         (dut.soc.core.FlushM),
            .FlushW         (dut.soc.core.FlushW),
            .PCM            (dut.soc.core.ifu.PCM),
            .InstrValidM    (dut.soc.core.ieu.InstrValidM),
            .InstrRawD      (dut.soc.core.ifu.InstrRawD),
            .TrapM          (dut.soc.core.TrapM),
            .PrivilegeModeW (dut.soc.core.PrivilegeModeW),
            .GPRWen         (dut.soc.core.ieu.dp.regf.we3),
            .GPRAddr        (dut.soc.core.ieu.dp.regf.a3),
            .GPRValue       (dut.soc.core.ieu.dp.regf.wd3),

            .ExternalStall  (ExternalStall),
            .m_axis_tdata   (m_axis_trace_tdata),
            .m_axis_tvalid  (m_axis_trace_tvalid),
            .m_axis_tready  (m_axis_trace_tready),
            .m_axis_tlast   (m_axis_trace_tlast),
            .m_axis_tkeep   (m_axis_trace_tkeep),
            .retired        (retired),
            .traps          (traps),
            .level          (trace_level),
            .state          (trace_state),
            .overflow       (trace_overflow)
        );
    end else begin : g_trace
        assign ExternalStall       = 1'b0;
        assign m_axis_trace_tdata  = '0;
        assign m_axis_trace_tvalid = 1'b0;
        assign m_axis_trace_tlast  = 1'b0;
        assign m_axis_trace_tkeep  = '0;
        assign trace_level         = '0;
        assign trace_state         = '0;
        assign trace_overflow      = 1'b0;

        // retired/traps are NOT tied off here.  They used to be, and the
        // result was that every TRACE=0 build reported "0 retired, 0 traps"
        // whether the core was executing or wedged -- see amoeba_retire.sv.
        amoeba_retire #(.XLEN(P.XLEN)) retire_cnt (
            .clk         (HCLK),
            .rst         (rst),
            .clear       (mon_clear),
            .core_reset  (core_reset_ext),
            .StallW      (dut.soc.core.StallW),
            .FlushW      (dut.soc.core.FlushW),
            .PCM         (dut.soc.core.ifu.PCM),
            .InstrValidM (dut.soc.core.ieu.InstrValidM),
            .TrapM       (dut.soc.core.TrapM),
            .retired     (retired),
            .traps       (traps)
        );
    end

    // soc_reset is the DUT's synchronized reset, brought out for waves only.
    logic unused;
    assign unused = &{1'b0, soc_reset, s_axi_ctl_wstrb};

endmodule
