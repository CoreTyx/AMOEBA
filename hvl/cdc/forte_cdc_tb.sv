///////////////////////////////////////////////////////////////////////////////
// forte_cdc_tb.sv
//
// The two-clock testbench docs/impl_plan_link_clocking.md s9a requires.
//
// WHY THIS EXISTS.  forte_top ties link_clk to the core_clk pad, so the ISA
// regression runs both domains from one clock.  RTL has no clock tree, so that
// simulation sees ZERO SKEW between them: prim_fifo_async's Gray-coded pointers
// always cross at the same phase, the synchronisers never resolve anything
// marginal, and the entire reason for choosing two clock domains (s4) goes
// unexercised.  A green ISA regression says nothing at all about the CDC.
//
// So this bench instantiates forte_chip DIRECTLY -- not forte_top, which ties
// the clocks -- and drives core_clk and link_clk from independent generators at
// a non-integer ratio.  It then runs the ordinary ISA programmes through it and
// requires the flit balance to be exact and every assertion silent.
//
// This is strictly WORSE than the real part will see.  Silicon has one clock
// source and two trees with bounded skew; here the two clocks have no rational
// relationship and drift through every phase.  If it passes at 1:1.37 with
// arbitrary phase it will pass at 1:1.
//
// IT IS A SEPARATE TOP, not a mode bolted onto hvl/common/top_tb.svh, for two
// reasons.  The Verilator flow drives clk and rst from a C++ harness, so the
// shared bench cannot generate a second clock at all; and the FPGA side has to
// move wholesale into the link domain -- the link model is the FPGA, the FPGA's
// clock IS the link clock, and the memory behind it is the FPGA's memory.  Left
// on the core clock, mem_resp is a one-cycle pulse in the wrong domain and the
// model's handshake would miss it at a non-integer ratio, producing failures
// that say nothing about the DUT.  Built with `verilator --binary --timing`,
// the same way third_party/opentitan/tb exercises the FIFO alone.
//
// WHAT IT CHECKS
//   - the programme's own tohost exit code, snooped on the link-domain memory
//   - exact flit balance: every command and every beat pushed into a FIFO in
//     one domain comes out exactly once in the other.  These are the counters
//     that caught the reset-gating bug in a76988e, and s9a names them as what a
//     two-clock run should be gated on.  Each side is counted in ITS OWN clock
//     and compared only at the end, once everything has drained.
//   - every assertion inside forte_link_core and forte_link_phy, which fire on
//     $fatal: stale beats, beat-count disagreement, a data flit where a command
//     was expected, an inbound FIFO overflow.
//   - clk_out actually toggles.
//
// WHAT IT DOES NOT CHECK: there is no Spike co-simulation and no RVFI here.
// Instruction-level correctness is the ISA regression's job; this bench is
// about the crossing.
//
//   +LINK_HALF=<ns>   half-period of link_clk (default 3.6495 -> ratio 1.3701)
//   +CORE_HALF=<ns>   half-period of core_clk (default 5.0 -> 100 MHz)
//   +TIMEOUT_ECE411=n core-clock cycles before giving up
//   +MEMLST_ECE411=f  memory image, as the ordinary flow passes it
///////////////////////////////////////////////////////////////////////////////

`include "config.vh"

module forte_cdc_tb import forte_link_pkg::*; ();

  localparam longint unsigned TOHOST_ADDR = 64'h8080_0000;

  // ---- the two clocks ------------------------------------------------------
  // Defaults are the ratio third_party/opentitan/tb/tb_prim_fifo_async.sv uses:
  // 10.0 ns core, 7.299 ns link -> 1.3701..., deliberately not a rational
  // multiple of anything the design could resonate with.
  real core_half = 5.0000;
  real link_half = 3.6495;
  logic core_clk = 1'b0;
  logic link_clk = 1'b0;

  initial begin
    void'($value$plusargs("CORE_HALF=%f", core_half));
    void'($value$plusargs("LINK_HALF=%f", link_half));
    $display("[CDC] core_half=%0.4f ns link_half=%0.4f ns ratio=%0.6f",
             core_half, link_half, core_half / link_half);
  end
  initial forever #(core_half) core_clk = ~core_clk;
  initial forever #(link_half) link_clk = ~link_clk;

  // ---- reset ---------------------------------------------------------------
  // One asynchronous assertion into both domains, exactly as the chip sees it:
  // forte_chip's two reset synchronisers are what make the release safe in each.
  // Releasing it off neither clock is deliberate -- it is the case the
  // synchronisers exist for.
  logic rst_n = 1'b0;
  logic rst;
  assign rst = ~rst_n;
  initial begin
    #(37.3);                 // not aligned to either clock
    rst_n = 1'b1;
  end

  // ---- the FPGA side, entirely in the link domain --------------------------
  mem_itf_w_mask #(.CHANNELS(1), .AWIDTH(64), .DWIDTH(64))
    mem_itf(.clk(link_clk), .rst(rst));

  simple_memory_w_mask simple_memory(.itf(mem_itf));

  // ---- pins ----------------------------------------------------------------
  wire  [LINK_W-1:0] io;
  logic [LINK_W-1:0] io_o, io_oe, io_i;
  logic              dir, req, wr, ready, rvalid, clk_out, status, uart_tx;

  // Behavioural pads, one enable per lane -- the same model forte_top uses.
  for (genvar i = 0; i < LINK_W; i++) begin : g_io
    assign io[i] = io_oe[i] ? io_o[i] : 1'bz;
  end
  assign io_i = io;

  forte_chip chip(
    .core_clk     (core_clk),
    .link_clk     (link_clk),
    .rst_n        (rst_n),
    .io_o, .io_oe, .io_i,
    .dir, .req, .wr, .ready, .rvalid,
    .clk_out      (clk_out),
    .irq          (2'b00),
    .uart_tx      (uart_tx),
    .uart_rx      (1'b1),
    .test_mode    (1'b0),
    .scan_en      (1'b0),
    .fault_inject (1'b0),
    .status       (status));

  // BEATS from the same expression forte_chip derives it from, so the model and
  // the DUT cannot disagree about where a transaction ends.
  forte_link_model #(.BEATS(DCACHE_LINELENINBITS / AHBW)) model (
    .clk(link_clk), .rst(rst),
    .io, .dir, .req, .wr, .ready, .rvalid,
    .mem_addr (mem_itf.addr [0]),
    .mem_rmask(mem_itf.rmask[0]),
    .mem_wmask(mem_itf.wmask[0]),
    .mem_wdata(mem_itf.wdata[0]),
    .mem_rdata(mem_itf.rdata[0]),
    .mem_resp (mem_itf.resp [0]));

  // ---- flit balance, counted per domain ------------------------------------
  // The whole point of the bench: a command or beat pushed into a FIFO in one
  // domain must come out exactly once in the other.  Each counter runs in the
  // clock of the side it observes -- counting both ends on one clock is what a
  // single-clock bench does and is exactly the thing that cannot be trusted
  // here.  They are compared only after everything has drained.
  longint unsigned n_cmd_push = 0, n_beat_pop  = 0;   // core domain
  longint unsigned n_cmd_pop  = 0, n_beat_push = 0;   // link domain

  always @(posedge core_clk) if (rst_n) begin
    if (chip.linkcore.cmd_push & chip.linkcore.ocmd_ready) n_cmd_push <= n_cmd_push + 1;
    if (chip.linkcore.rpop)                                n_beat_pop <= n_beat_pop + 1;
  end
  always @(posedge link_clk) if (rst_n) begin
    if (chip.phy.ocmd_ready & chip.phy.ocmd_valid & chip.phy.ocmd_data[64])
      n_cmd_pop <= n_cmd_pop + 1;
    if (chip.phy.ibeat_valid & chip.phy.ibeat_ready)
      n_beat_push <= n_beat_push + 1;
  end

  // ---- clk_out is alive ----------------------------------------------------
  // Cheap, but it is the pin the bring-up plan leans on hardest (s6.1), and a
  // tie-off would otherwise look exactly like success here.
  longint unsigned n_clk_out_edges = 0;
  always @(posedge clk_out) if (rst_n) n_clk_out_edges <= n_clk_out_edges + 1;

  // ---- transactions, for a sanity figure -----------------------------------
  longint unsigned n_txn = 0;
  always @(posedge link_clk) if (rst_n & chip.phy.txn_done) n_txn <= n_txn + 1;

  // ---- verdict -------------------------------------------------------------
  task automatic report_and_exit(input string why, input bit ok);
    bit balanced;
    balanced = (n_cmd_push == n_cmd_pop) && (n_beat_push == n_beat_pop);
    $display("[CDC] %s", why);
    $display("[CDC] transactions=%0d clk_out_edges=%0d", n_txn, n_clk_out_edges);
    $display("[FLIT] cmd_push=%0d cmd_pop=%0d beat_push=%0d beat_pop=%0d",
             n_cmd_push, n_cmd_pop, n_beat_push, n_beat_pop);
    if (!balanced)
      $display("[CDC] FLIT IMBALANCE -- a flit was lost or duplicated across the crossing");
    if (n_clk_out_edges == 0)
      $display("[CDC] clk_out never toggled");
    if (ok && balanced && n_clk_out_edges > 0 && n_txn > 0)
      $display("FORTE_CDC PASS");
    else
      $display("FORTE_CDC FAIL");
    $finish;
  endtask

  // ---- tohost ---------------------------------------------------------------
  // TWO DETECTORS, AND THE RETIREMENT ONE IS THE LOAD-BEARING ONE.  tohost lives
  // at 0x8080_0000, which is inside EXT_MEM and therefore CACHEABLE: the store
  // lands in the D-cache and does not reach the link unless something evicts the
  // line.  The programmes do not evict it -- they write tohost and then sit in
  // `wfi; j .-8` forever -- so a memory-side detector alone never fires and the
  // bench times out on a programme that in fact passed.  That is exactly what
  // this bench did first time out: core parked at the wfi loop with the flit
  // balance perfect and 130 transactions, all of them startup.
  //
  // hvl/common/top_tb.svh does not hit this because its primary detector is the
  // RVFI monitor, which fires at store retirement; its AHB-level one is a
  // documented "safety net" that is in practice dead code.  There is no RVFI
  // here, so the retirement check is done directly on the M stage.
  logic  exiting = 1'b0;
  bit    exit_ok = 1'b0;
  string exit_why = "";

  // Retirement: a committed store to tohost, before any cache gets involved.
  always @(posedge core_clk) begin
    if (rst_n && !exiting
        && chip.soc.core.ieu.InstrValidM
        && chip.soc.core.MemRWM[0]
        && !chip.soc.core.FlushM
        && !chip.soc.core.StallM
        && chip.soc.core.IEUAdrM == TOHOST_ADDR) begin
      automatic longint unsigned v = chip.soc.core.lsu.LSUWriteDataM[63:0];
      if (v[0]) begin
        exit_ok  = (v == 64'd1);
        exit_why = exit_ok ? "tohost exit(0) at retirement -- programme PASSED"
                           : $sformatf("tohost exit(%0d) at retirement -- programme FAILED", v >> 1);
        exiting <= 1'b1;
      end
    end
  end

  // Memory side, kept because it costs nothing and it is the one that proves the
  // write actually crossed the link when a programme does flush.
  always @(posedge link_clk) begin
    if (rst_n && !exiting && mem_itf.wmask[0] != '0 && mem_itf.addr[0] == TOHOST_ADDR) begin
      automatic longint unsigned v = mem_itf.wdata[0];
      if (v[0]) begin
        exit_ok  = (v == 64'd1);
        exit_why = exit_ok ? "tohost exit(0) seen in memory -- programme PASSED"
                           : $sformatf("tohost exit(%0d) seen in memory -- programme FAILED", v >> 1);
        exiting <= 1'b1;
      end
    end
  end

  // Drain BOTH domains before judging.  The flit balance is only a real check
  // once nothing is in flight; checked at the instant tohost retires it would be
  // a race against the transaction still on the wire.
  initial begin
    wait (exiting);
    repeat (400) @(posedge link_clk);
    repeat (400) @(posedge core_clk);
    report_and_exit(exit_why, exit_ok);
  end

  // ---- progress, for diagnosing a stall ------------------------------------
  // +CDC_PROGRESS=n prints the PC and the transaction count every n core cycles.
  // A two-clock bench that hangs gives no clue otherwise: the flit balance stays
  // perfect (nothing is in flight) and only the absolute counts look wrong.
  int progress_n = 0;
  initial void'($value$plusargs("CDC_PROGRESS=%d", progress_n));
  longint unsigned cyc = 0;
  always @(posedge core_clk) if (rst_n) begin
    cyc <= cyc + 1;
    if (progress_n > 0 && (cyc % progress_n) == 0)
      $display("[CDC] cyc=%0d pc=%h txn=%0d cmd_push=%0d instr_valid_w=%b",
               cyc, chip.soc.core.ifu.PCM, n_txn, n_cmd_push,
               chip.soc.core.ieu.InstrValidM);
  end

  longint unsigned timeout = 10000000;
  initial void'($value$plusargs("TIMEOUT_ECE411=%d", timeout));
  initial begin
    repeat (timeout) @(posedge core_clk);
    report_and_exit("TIMED OUT", 1'b0);
  end

endmodule
