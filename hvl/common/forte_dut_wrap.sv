///////////////////////////////////////////////////////////////////////////////
// forte_dut_wrap.sv
//
// The ASIC top as a testbench DUT, on the same ports as rv64_core_wrapper:
// clk/rst, one mem_itf channel, the monitor_* RVFI outputs.  top_tb.svh
// swaps the module name and nothing else changes -- memory model, tohost
// snoop, generated rvfi_reference.svh, monitor.
//
//   forte_top      the chip, behavioural pads
//   forte_link_model   the FPGA side of the link, into mem_itf
//   rvfi_tap        the pipeline taps, by hierarchical reference into the core
//
///////////////////////////////////////////////////////////////////////////////

`include "config.vh"

module forte_dut_wrap import forte_link_pkg::*; (
    input  logic        clk,
    input  logic        rst,
    // Deliberately still ecc_inject_en, not fault_inject: top_tb.svh drives one
    // shared port list for this DUT and rv64_core_wrapper, and the wrapper is
    // held byte-identical to their branch.  The pin-side name appears on the
    // forte_top instantiation below.
    input  logic        ecc_inject_en,   // driven by top_tb

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
    output logic        monitor_mem_extamo
);

    // ---- the pads -----------------------------------------------------------
    wire [LINK_W-1:0] io;
    logic dir, req, wr, burst, ready, rvalid, status, uart_tx;

    forte_top top (
        // No link_clk here: forte_top has only the core_clk PAD and ties
        // link_clk to it internally.  Driving the two domains independently
        // means instantiating forte_chip directly -- which is exactly what the
        // two-clock testbench in docs/impl_plan_link_clocking.md s9a is for.
        .core_clk(clk), .rst_n(~rst), .fault_inject(ecc_inject_en),
        .io, .dir, .req, .wr, .burst, .ready, .rvalid,
        .irq(2'b00), .uart_tx, .uart_rx(1'b1), .test_mode(1'b0), .scan_en(1'b0), .status);

    // BEATS must be the DUT's.  forte_chip derives it as DCACHE_LINELENINBITS /
    // AHBW from the same config.vh this file includes, so the two cannot drift
    // apart silently -- a line resize moves both or neither.  Hardcoding 8 here
    // is what made a 512 -> 128 bit line change hang the regression with no
    // diagnostic at all.
    forte_link_model #(.BEATS(DCACHE_LINELENINBITS / AHBW)) model (
        .clk, .rst, .io, .dir, .req, .wr, .burst, .ready, .rvalid,
        .mem_addr, .mem_rmask, .mem_wmask, .mem_wdata, .mem_rdata, .mem_resp);

    // ---- RVFI taps, same wiring as rv64_core_wrapper ------------------------
    rvfi_tap tap (
        .clk, .rst,
        // The SoC's own reset releases a few cycles after rst; until then its
        // pipeline controls are X in 4-state simulation.  rvfi_tap holds its
        // registers in reset for as long as this is high so none of those Xs is
        // ever captured -- the same rst_rvfi the wrapper builds inline.
        .reset_soc      (top.chip.reset_soc),
        // Taken-branch resolution and the injected-dummy flags.  Without these
        // monitor_pc_wdata falls back to a pipeline lookahead that a mispredict
        // flush has already emptied, and tc_rand_instr_insert fails on
        // "mismatch in pc_wdata" -- it is the test that makes that window
        // reachable.  See rvfi_tap.sv.
        .PCSrcE         (top.chip.soc.core.PCSrcE),
        .InjectD        (top.chip.soc.core.InjectD),
        .DummyE         (top.chip.soc.core.ieu.c.DummyE),
        .DummyM         (top.chip.soc.core.ieu.c.DummyM),
        .StallE         (top.chip.soc.core.StallE),
        .StallM         (top.chip.soc.core.StallM),
        .StallW         (top.chip.soc.core.StallW),
        .FlushE         (top.chip.soc.core.FlushE),
        .FlushM         (top.chip.soc.core.FlushM),
        .FlushW         (top.chip.soc.core.FlushW),
        .InstrValidM    (top.chip.soc.core.ieu.InstrValidM),
        .InstrValidE    (top.chip.soc.core.ieu.InstrValidE),
        .InstrValidD    (top.chip.soc.core.ieu.InstrValidD),
        .InstrRawD      (top.chip.soc.core.ifu.InstrRawD),
        .PCM            (top.chip.soc.core.ifu.PCM),
        .PCD            (top.chip.soc.core.ifu.PCD),
        .PCE            (top.chip.soc.core.ifu.PCE),
        .TrapM          (top.chip.soc.core.TrapM),
        .RetM           (top.chip.soc.core.RetM),
        .InterruptM     (top.chip.soc.core.priv.priv.InterruptM),
        .EPCM           (top.chip.soc.core.EPCM),
        .TrapVectorM    (top.chip.soc.core.TrapVectorM),
        .PrivilegeModeW (top.chip.soc.core.PrivilegeModeW),
        .GPRAddr        (top.chip.soc.core.ieu.dp.regf.a3),
        .GPRWen         (top.chip.soc.core.ieu.dp.regf.we3),
        .GPRValue       (top.chip.soc.core.ieu.dp.regf.wd3),
        .Rs1D           (top.chip.soc.core.ieu.dp.regf.a1),
        .Rs2D           (top.chip.soc.core.ieu.dp.regf.a2),
        .ForwardedSrcAE (top.chip.soc.core.ieu.ForwardedSrcAE),
        .ForwardedSrcBE (top.chip.soc.core.ieu.ForwardedSrcBE),
        .MemRWM         (top.chip.soc.core.MemRWM),
        .Funct3M        (top.chip.soc.core.Funct3M),
        .IEUAdrM        (top.chip.soc.core.IEUAdrM),
        .WriteDataM     (top.chip.soc.core.lsu.LSUWriteDataM[63:0]),
        .ReadDataW      (top.chip.soc.core.ReadDataW[63:0]),
`ifndef ECE411_NO_FLOAT
        .Frs1D_i        (top.chip.soc.core.fpu.fpu.fregfile.a1),
        .Frs2D_i        (top.chip.soc.core.fpu.fpu.fregfile.a2),
        .Frs3D_i        (top.chip.soc.core.fpu.fpu.fregfile.a3),
        .Frs1DataD_i    (top.chip.soc.core.fpu.fpu.fregfile.rd1),
        .Frs2DataD_i    (top.chip.soc.core.fpu.fpu.fregfile.rd2),
        .Frs3DataD_i    (top.chip.soc.core.fpu.fpu.fregfile.rd3),
        .Frd_we4_i      (top.chip.soc.core.fpu.fpu.fregfile.we4),
        .Frd_a4_i       (top.chip.soc.core.fpu.fpu.fregfile.a4),
        .Frd_wd4_i      (top.chip.soc.core.fpu.fpu.fregfile.wd4),
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

    // ---- link statistics, printed at the end of every run -------------------
    // NOTE ON THE PROBES BELOW.  These are hierarchical references into the
    // DUT, and that has now broken twice on refactors: once when inserting a
    // state shifted the enum values these compared against (fixed in 6ad99fe by
    // moving the enums into the package), and again when the bridge split in
    // two and `link` became `linkcore` + `phy`.  Both times the ISA regression
    // stayed green and only the link_abort gate caught it.  The structural fix
    // is a monitor interface the DUT exports deliberately, rather than the
    // testbench reaching in; until then, expect to re-point these whenever the
    // bridge hierarchy moves.
    //   core domain (forte_link_core): the AHB side, the abort rule, pending
    //   link domain (forte_link_phy):  the pins, the word counters, txn_done
    // aborted counts transfers the bridge finished after the core had left:
    // the abort path is only proven if this is nonzero on a branchy workload.
    longint unsigned n_txn = 0, n_rd = 0, n_wr = 0, n_abort = 0, n_pending = 0;
    logic aborted_q, pending_q;
    always @(posedge clk) begin
        aborted_q <= top.chip.linkcore.aborted;
        pending_q <= top.chip.linkcore.pending;
        if (top.chip.phy.txn_done) begin
            n_txn <= n_txn + 1;
            if (top.chip.phy.wr_r) n_wr <= n_wr + 1; else n_rd <= n_rd + 1;
        end
        if (top.chip.linkcore.aborted & ~aborted_q) n_abort   <= n_abort + 1;
        if (top.chip.linkcore.pending & ~pending_q) n_pending <= n_pending + 1;
    end
    // Flit accounting across the crossing.  If these do not balance the two
    // halves disagree about how many beats a transaction has, and stale beats
    // poison every transaction after the first.
    longint unsigned n_cmd_push = 0, n_cmd_pop = 0, n_beat_push = 0, n_beat_pop = 0;
    always @(posedge clk) begin
        if (top.chip.linkcore.cmd_push   & top.chip.linkcore.ocmd_ready) n_cmd_push  <= n_cmd_push  + 1;
        if (top.chip.phy.ocmd_ready & top.chip.phy.ocmd_valid
                                    & top.chip.phy.ocmd_data[64])        n_cmd_pop   <= n_cmd_pop   + 1;
        if (top.chip.phy.ibeat_valid     & top.chip.phy.ibeat_ready)     n_beat_push <= n_beat_push + 1;
        if (top.chip.linkcore.rpop)                                      n_beat_pop  <= n_beat_pop  + 1;
    end
    final $display("[FLIT] cmd_push=%0d cmd_pop=%0d beat_push=%0d beat_pop=%0d",
                   n_cmd_push, n_cmd_pop, n_beat_push, n_beat_pop);
    // Diagnostics for the abort path: flushes while a read is in flight, and
    // cycles where the master shows IDLE mid-burst (what the bridge keys on).
    longint unsigned n_flush_rd = 0, n_idle_midburst = 0;
    always @(posedge clk) begin
        if (top.chip.soc.core.FlushD & top.chip.soc.core.ebu.ebu.IFUSelect & (top.chip.phy.st inside {LM_RD_TA, LM_RD_DATA, LM_RD_TA2})) n_flush_rd <= n_flush_rd + 1;
        if ((top.chip.phy.st == LM_RD_DATA) & (top.chip.linkcore.HTRANS == 2'b00) & ~top.chip.linkcore.last_beat)
            n_idle_midburst <= n_idle_midburst + 1;
    end
    final $display("[LINK] transactions=%0d reads=%0d writes=%0d aborted=%0d pipelined=%0d flushD_during_ifetch=%0d idle_midburst_cycles=%0d",
                   n_txn, n_rd, n_wr, n_abort, n_pending, n_flush_rd, n_idle_midburst);

    // ---- +LINK_FORCE_ABORT=n: abort every n-th I-fetch burst mid-flight ----
    // In this core a flush cause that exists when the fetch stalls resolves in
    // the first stall cycle, before the address phase reaches the bridge, and
    // CommittedF holds interrupts off during a fill -- so bare-metal and
    // FreeRTOS never produce a bus-level abort.  To prove the drain path,
    // force the I-cache bus FSM's Flush input for one cycle in the middle of
    // a burst: buscachefsm drops to ADR_PHASE and HTRANS goes IDLE exactly as
    // on a real flush, while the cache FSM (which is not flushed) still wants
    // the line and re-requests it, so the program is unaffected.
    int force_abort_n = 0;
    initial void'($value$plusargs("LINK_FORCE_ABORT=%d", force_abort_n));
    int          force_cnt = 0;
    logic        forcing = 1'b0;
    always @(posedge clk) begin
        if (force_abort_n > 0) begin
            if (forcing) begin
                release top.chip.soc.core.ifu.bus.icache.ahbcacheinterface.Flush;
                forcing <= 1'b0;
            // Word 1, i.e. inside the FIRST beat, and NOT a fixed word part-way
            // through a 32-word burst.  forte_link_core only latches `aborted`
            // at a NON-FINAL beat boundary -- beat_ok is unconditionally true
            // once last_beat holds -- so the forced flush has to land early
            // enough that HTRANS has gone IDLE before a non-final beat is
            // retired.  This used to be `wcnt == 5`, which was beat 1 of 8 at a
            // 512-bit line and is beat 1 of 2 (the LAST beat) at 128 bits: the
            // injection still fired, the flush still happened, and not one
            // transfer could be aborted by it.  aborted/flushD_during_ifetch/
            // idle_midburst_cycles all went to zero and the only thing that
            // noticed was the link_abort gate.  Word 1 is in a non-final beat
            // for every BEATS >= 2, which forte_link_core enforces.
            end else if (top.chip.phy.st == LM_RD_DATA && top.chip.phy.wcnt == 1 && top.chip.phy.rvalid_s &&
                         top.chip.soc.core.ebu.ebu.IFUSelect) begin
                if (force_cnt + 1 >= force_abort_n) begin
                    force top.chip.soc.core.ifu.bus.icache.ahbcacheinterface.Flush = 1'b1;
                    forcing   <= 1'b1;
                    force_cnt <= 0;
                end else force_cnt <= force_cnt + 1;
            end
        end
    end

    // ---- +LINK_PINS=n: cycle-by-cycle pin trace of the first n cycles after
    //      the first accept.  This is the ground truth for
    //      docs/top_level_plan.md s4's timing tables -- hand-deriving the
    //      cycle alignment from the FSM is how off-by-ones get into specs.
    int  pins_n = 0;
    int  pins_cnt = 0;
    bit  pins_armed = 0;
    bit  pins_wr_only = 0;        // +LINK_PINS_WR arms on the first WRITE accept
    initial void'($value$plusargs("LINK_PINS=%d", pins_n));
    initial if ($test$plusargs("LINK_PINS_WR")) pins_wr_only = 1;
    always @(posedge clk) if (pins_n > 0) begin
        if (!pins_armed && top.chip.linkcore.accept
                        && (!pins_wr_only || top.chip.linkcore.HWRITE)) begin
            pins_armed <= 1'b1;
            $display("# cyc PHYst      io    dir req rvld drv   | COREst   bcnt abt ok htq hro note");
        end
        if (pins_armed && pins_cnt < pins_n) begin
            pins_cnt <= pins_cnt + 1;
            $display("P %4d %-10s %4h   %b   %b   %b  %-5s | %-9s %0d   %b   %b  %2b  %b  %s",
                pins_cnt,
                top.chip.phy.st.name(),
                io, dir, req, rvalid,
                (top.chip.io_oe[0] && !model.io_oe) ? "ASIC" :
                (!top.chip.io_oe[0] && model.io_oe) ? "fpga" :
                (!top.chip.io_oe[0] && !model.io_oe) ? "--"   : "BOTH!",
                top.chip.linkcore.st.name(),
                top.chip.linkcore.bcnt,
                top.chip.linkcore.aborted,
                top.chip.linkcore.beat_ok,
                top.chip.linkcore.htrans_q,
                top.chip.linkcore.HREADYOUT,
                top.chip.linkcore.accept ? "accept" :
                top.chip.linkcore.rpop   ? "rpop"   :
                top.chip.linkcore.wpush  ? "wpush"  : "");
        end
    end

    // ---- +LINK_TRACE: transaction-level trace of the bridge and the model ---
    bit link_trace = 0;
    initial if ($test$plusargs("LINK_TRACE")) link_trace = 1;
    always @(posedge clk) begin
        if (link_trace) begin
            if (top.chip.linkcore.accept)
                $display("[LINK %0t] accept  addr=%h wr=%b burst=%b st=%0d pending=%b",
                         $time, top.chip.linkcore.HADDR[31:0], top.chip.linkcore.HWRITE, top.chip.linkcore.HBURST,
                         top.chip.phy.st, top.chip.linkcore.pending);
            if (top.chip.phy.req & ~top.chip.phy.dir)
                $display("[LINK %0t] req while dir=0", $time);
            if (top.chip.linkcore.HREADYOUT & top.chip.phy.st != LM_IDLE)
                $display("[LINK %0t] beat    st=%0d wcnt=%0d hrdata=%h", $time,
                         top.chip.phy.st, top.chip.phy.wcnt, top.chip.linkcore.HRDATA);
            if (model.lst == LS_HDR1)
                $display("[LINK %0t] model   header hi=%h lo=%h wr=%b burst=%b", $time,
                         model.hdr_hi, model.io_i, model.wr, model.burst);
            if (model.mem_busy & model.mem_resp)
                $display("[LINK %0t] model   mem %s addr=%h data=%h", $time,
                         model.mem_rmask != 0 ? "rd" : "wr", model.mem_addr,
                         model.mem_rmask != 0 ? model.mem_rdata : model.mem_wdata);
        end
    end

endmodule
