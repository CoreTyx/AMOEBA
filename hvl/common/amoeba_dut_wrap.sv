///////////////////////////////////////////////////////////////////////////////
// amoeba_dut_wrap.sv
//
// The ASIC top as a testbench DUT, on the same ports as rv64_core_wrapper:
// clk/rst, one mem_itf channel, the monitor_* RVFI outputs.  top_tb.svh
// swaps the module name and nothing else changes -- memory model, tohost
// snoop, generated rvfi_reference.svh, monitor.
//
//   amoeba_top      the chip, behavioural pads
//   amoeba_link_model   the FPGA side of the link, into mem_itf
//   rvfi_tap        the pipeline taps, by hierarchical reference into the core
//
// TRAIN_LEN is shortened so training costs ~150 cycles per run instead of ~8k.
///////////////////////////////////////////////////////////////////////////////

`include "amoeba_config_select.vh"

module amoeba_dut_wrap import amoeba_link_pkg::*; #(
    parameter int TRAIN_LEN = 64
)(
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
    output logic        monitor_mem_extamo
);

    // ---- the pads -----------------------------------------------------------
    wire [LINK_W-1:0] io;
    logic dir, req, wr, burst, ready, rvalid, status, uart_tx;

    amoeba_top #(.TRAIN_LEN(TRAIN_LEN)) top (
        .clk, .rst_n(~rst), .io, .dir, .req, .wr, .burst, .ready, .rvalid,
        .irq(2'b00), .uart_tx, .uart_rx(1'b1), .test_mode(1'b0), .scan_en(1'b0), .status);

    amoeba_link_model #(.TRAIN_LEN(TRAIN_LEN)) model (
        .clk, .rst, .io, .dir, .req, .wr, .burst, .ready, .rvalid,
        .mem_addr, .mem_rmask, .mem_wmask, .mem_wdata, .mem_rdata, .mem_resp);

    // ---- RVFI taps, same wiring as rv64_core_wrapper ------------------------
    rvfi_tap tap (
        .clk, .rst,
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
    // aborted counts transfers the bridge finished after the core had left:
    // the abort path is only proven if this is nonzero on a branchy workload.
    longint unsigned n_txn = 0, n_rd = 0, n_wr = 0, n_abort = 0, n_pending = 0;
    logic aborted_q, pending_q;
    always @(posedge clk) begin
        aborted_q <= top.chip.link.aborted;
        pending_q <= top.chip.link.pending;
        if (top.chip.link.txn_done) begin
            n_txn <= n_txn + 1;
            if (top.chip.link.wr_r) n_wr <= n_wr + 1; else n_rd <= n_rd + 1;
        end
        if (top.chip.link.aborted & ~aborted_q) n_abort   <= n_abort + 1;
        if (top.chip.link.pending & ~pending_q) n_pending <= n_pending + 1;
    end
    // Diagnostics for the abort path: flushes while a read is in flight, and
    // cycles where the master shows IDLE mid-burst (what the bridge keys on).
    longint unsigned n_flush_rd = 0, n_idle_midburst = 0;
    always @(posedge clk) begin
        if (top.chip.soc.core.FlushD & top.chip.soc.core.ebu.ebu.IFUSelect & (top.chip.link.st inside {5, 6, 7})) n_flush_rd <= n_flush_rd + 1;
        if ((top.chip.link.st == 6) & (top.chip.link.HTRANS == 2'b00) & ~top.chip.link.last_beat & top.chip.link.burst_r)
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
            end else if (top.chip.link.st == 6 && top.chip.link.wcnt == 5 && top.chip.link.rvalid_s &&
                         top.chip.link.burst_r && top.chip.soc.core.ebu.ebu.IFUSelect) begin
                if (force_cnt + 1 >= force_abort_n) begin
                    force top.chip.soc.core.ifu.bus.icache.ahbcacheinterface.Flush = 1'b1;
                    forcing   <= 1'b1;
                    force_cnt <= 0;
                end else force_cnt <= force_cnt + 1;
            end
        end
    end

    // ---- +LINK_TRACE: transaction-level trace of the bridge and the model ---
    bit link_trace = 0;
    initial if ($test$plusargs("LINK_TRACE")) link_trace = 1;
    logic trained_q;
    always @(posedge clk) begin
        trained_q <= top.chip.trained;
        if (link_trace) begin
            if (top.chip.trained & ~trained_q)
                $display("[LINK %0t] trained", $time);
            if (top.chip.link.accept)
                $display("[LINK %0t] accept  addr=%h wr=%b burst=%b st=%0d pending=%b",
                         $time, top.chip.link.HADDR[31:0], top.chip.link.HWRITE, top.chip.link.HBURST,
                         top.chip.link.st, top.chip.link.pending);
            if (top.chip.link.req & ~top.chip.link.dir)
                $display("[LINK %0t] req while dir=0", $time);
            if (top.chip.link.HREADYOUT & top.chip.link.st != 0)
                $display("[LINK %0t] beat    st=%0d wcnt=%0d hrdata=%h", $time,
                         top.chip.link.st, top.chip.link.wcnt, top.chip.link.HRDATA);
            if (model.lst == 4 /* L_HDR1 */)
                $display("[LINK %0t] model   header hi=%h lo=%h wr=%b burst=%b", $time,
                         model.hdr_hi, model.io_i, model.wr, model.burst);
            if (model.mem_busy & model.mem_resp)
                $display("[LINK %0t] model   mem %s addr=%h data=%h", $time,
                         model.mem_rmask != 0 ? "rd" : "wr", model.mem_addr,
                         model.mem_rmask != 0 ? model.mem_rdata : model.mem_wdata);
        end
    end

endmodule
