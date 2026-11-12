// tb_scan.sv -- pin-level test of the scan chains in the scanned forte_top and
// of every register on them: the PC, the pipeline registers and the hardened
// CSRs that dft_setup.tcl selects.
//
// Pass/fail uses the package pins; internal hookups are diagnostic only.
// The chains are the ones
// dft_insert.tcl declares: c0..c7, scan in on io_in[k], scan out on io_out[k].
// Below, chain k = 1..8 is c(k-1): io_in[k-1] -> io_out[k-1].  Chain lengths and
// inversions are discovered from the pins.  Which register bit each cell holds
// comes from the scandef: run.sh turns it into scan_map.svh (scan_map.awk),
// whose table also gives each register's group, kind and reset value.
//
// INVERTING CHAINS.  insert_dft may take a cell's scan output from QN (the
// scandef says "( OUT QN )"); each such cell inverts what passes through it.
// A chain with an odd number of them is inverting: it shifts out ~in, and after
// a zero flush its scan-out sits at 1.  inv[k] is that parity, read from the
// pin.  With the map, the inversion between scan-in and each cell (a_inv) and
// between each cell and scan-out (b_inv) is known too, so any value can be
// loaded into the flops and read out of them exactly.
//
// SINGLE-CAPTURE CONTRACT. load_in_reset aligns the first capture with the
// first functional edge after reset (RST_LAT must match the reset pipeline).
// The unscanned FetchCheckedQ is still reset to zero: the IFU fetch-check
// interlock holds the pipeline for that edge, provided no HPTW fault or flush
// overrides it. CTRL cells stay at their checked reset baseline, leaving no
// valid older instruction to branch, return, write a CSR, or trap. This is a
// directed first-edge expectation, not a guarantee supplied by ready=0.
// Subsequent edges can advance unscanned fetch/cache/bus state, and a flush
// can release the stall. Reloading base does not restore that unscanned state.
// +SCAN_SWEEP enables the longer D/E retention experiments explicitly; their
// unchanged-state expectation is diagnostic and their failures remain fatal.
// The ECC registers repair a 1-bit error even while stalled, so they are only
// loaded with valid codewords except where a check injects an error on purpose.
// While a load shifts, every pattern passes through the control cells upstream
// of it, and with the stall released by a passing branch bit the logic OFF the
// chains (CSRs, bus FSM, register file) would act on them.  So every load holds
// the functional reset through the shift and releases it as the last bit goes
// in (load_in_reset). Each independent case first gets a functional reset
// with scan disabled. This isolates test history; it does not recreate B's
// 200-clock non-scan state. Scan cells take SI whatever reset does: the core's
// resets are synchronous.
// Every check loads all cells: the register under test gets its pattern, every
// other cell its value after B's reset ("base").  Every cell is compared on
// the way out, so a check also fails if loading one register disturbs another.
//
//   A  lengths      shift zeros and read each scan-out: that is inv[k].  Then
//                   one 1 into every io_in; the cycle io_out[k] first differs
//                   from inv[k] is that chain's length.  With
//                   +define+EXPECTED_CELLS=n the total must be n.  Then a 0011
//                   flush through every chain.
//   M  map          scan_map.svh against the pins: every chain the length A
//                   found, inversions adding up to inv[k] (this also fixes the
//                   last cell's, which the scandef leaves out), every register
//                   bit on at most one cell, no cell of an unknown register or
//                   of the DFT lock.  Prints each chain's registers, the bits a
//                   register has no cell for (constant or merged flops), and the
//                   cells per group.
//   B  reset        reset, run 200 clocks without external responses, shift
//                   out: every cell must hold its register's reset value (X only
//                   where the register has no reset).  What is read is "base".
//   C  round trip   random data in, the same data (through inv[k]) out.
//   D  capture      base loaded, one capture edge in test mode, unloaded: every
//                   cell unchanged. Long holds only with +SCAN_SWEEP.
//   E  PC           PC values held, every other cell at base: all 0, all 1,
//                   checkerboards, walking 1 and walking 0 over every PC bit,
//                   random. +SCAN_SWEEP adds functional-mode hold experiments
//                   at EXT_MEM PCs (FETCH_BASE/FETCH_MASK).
//   P  registers    each DATA, ECC, MPP, STICKY and MSECFAULT register on its
//                   own: all 1, 0x5555..., 0xAAAA..., random (an ECC register
//                   gets the codeword of each), one capture edge.  Then all six
//                   privmode copies at U mode.
//   H  hardening    one capture edge each, every cell compared:
//                     ECC 1-bit error   in a data or Hamming bit: repaired,
//                                       MSECFAULT[4] set
//                     privmode copies   one copy bad: held, MSECFAULT[0];
//                                       two bad: held, MSECFAULT[3];
//                                       reserved 10 in one copy: MSECFAULT[0]
//                     mstatus.MPP = 10  held, MSECFAULT[1]
//                     ECC 2-bit error   held, MSECFAULT[5]
//                   +define+NO_HARDEN skips H.
//   F  reset        every cell loaded (all 1, ~base, random; control registers
//                   too), then a functional reset: every cell back at its reset
//                   value.
//   R  randomized   multi-register first-edge patterns and modeled faults.
//   I  instructions short RV64 sequences, WFI endpoint, scan-visible writes.
// Ends with one line per group and register that failed, the PC bits that
// failed, then "DFT TB PASS" or "DFT TB FAIL".
//
// What the pins cannot check: the ORDER of the cells in a chain is taken from
// the scandef.  A check reads back through the same map it loads through, so a
// swapped pair only shows where the two reset values differ (B, F).  A wrong
// inversion does show, in B and F.  +define+BREAK_MAP corrupts one inversion as
// a self-test.
//
// Pins follow docs/top_level_plan.md s3: test_mode static for the session,
// scan enable toggled per cycle on scan_en.  The link is two one-way buses, so
// no pad changes direction: io_in carries scan-in (the bench's si) except while
// the link agent runs phase I, and io_out carries scan-out in test mode.
// The DFT lock resets to unlocked, so it does not get in the way here; it is
// not tested.
//
// TEST_MODE IS SYNCHRONISED in forte_chip (tmsync, two core_clk flops), so
// test_mode_dft -- which selects what io_out carries -- follows the pin two
// edges late; scan_en is not synchronised.  Every time test_mode rises the
// bench holds scan_en low and idles TM_SYNC cycles (enter_test) before it
// shifts.  Those are functional edges: where they follow a reset (load) they
// change nothing; after B's stall, a functional hold or phase I they are a few
// more cycles of the same stall, which the checks already rely on.
//
// Test cycle as the SPF: 100 ns; inputs change at 10 ns, io_out sampled at
// 40 ns, core_clk rises at 50 ns.

`timescale 1ns/1ps

`ifndef RESET_VEC
  `define RESET_VEC 64'h8000_0000
`endif
// core_clk edges from rst_n rising to the core leaving reset: forte_rst_sync
// (2) then forte_soc's resetsync (2).
`ifndef RST_LAT
  `define RST_LAT 4
`endif
`ifndef SCAN_MAX_LEN
  `define SCAN_MAX_LEN 1024
`endif
// PCs for E's functional-mode holds: inside EXT_MEM (pkg/config.vh,
// 0x8000_0000 + 0x0FFF_FFFF), word aligned.
`ifndef FETCH_BASE
  `define FETCH_BASE 64'h8000_0000
`endif
`ifndef FETCH_MASK
  `define FETCH_MASK 64'h0FFF_FFFC
`endif

module tb_scan;

  // FSDB path is relative to the simulator's working directory.
`ifdef SCAN_FSDB
  initial begin : fsdb_dump
    $fsdbDumpfile("dump.fsdb");
    $fsdbDumpvars(0, tb_scan);
  end
`endif

  localparam int N        = 8;     // chains c0..c7: io_in[k] in, io_out[k] out
  localparam int TM_SYNC  = 3;     // cycles for test_mode through tmsync (2 flops) + 1
  localparam int MAX_LEN  = `SCAN_MAX_LEN; // maximum discoverable chain length
  localparam int MAX_REGS = 256;
  localparam int MAX_W    = 256;   // widest register (an ECC codeword: 72)
  localparam int ECC_DW   = 64;    // the ECC registers: XLEN data bits,
  localparam int ECC_R    = 7;     // 7 Hamming bits and an overall parity:
  localparam int ECC_CW   = 72;    // {data, parity, hamming} (ecc_secded_enc.sv)
  localparam int FUNC_CYC = 50;    // optional retention experiment, in cycles

  // MSECFAULT bits (csrharden.sv)
  localparam int MSF_TMR_SEC = 0, MSF_MPP = 1, MSF_TMR_UNC = 3, MSF_ECC_SEC = 4, MSF_ECC_DED = 5;

  // ---- DUT ------------------------------------------------------------------
  logic        clk = 1'b0;
  logic        rst_n, ready, rvalid, uart_rx, test_mode, scan_en, fault_inject;
  logic [1:0]  irq;
  logic [N:1]  si;
  bit link_active = 0;
  wire link_ready, link_rvalid;
  wire  [N:1]  so;
  wire  [N-1:0] io_in, io_out, link_io_in;
  wire          req, wr, clk_out, uart_tx, status;

  // Chain k is bit k-1 of each bus.  io_in is the agent's while it runs (phase
  // I), the bench's scan-in otherwise.
  assign io_in = link_active ? link_io_in : si;
  assign so    = io_out;
  always_comb begin
    ready = link_active ? link_ready : 1'b0;
    rvalid = link_active ? link_rvalid : 1'b0;
  end
  // The agent sees reset whenever it is not active: no checks, no transaction
  // state, ready/rvalid low, so scan traffic on io_out is never decoded.
  wire link_rst_n = rst_n & link_active;
  pin_link_agent #(.BEATS(2), .RESET_VEC(32'(`RESET_VEC))) link (
    .core_clk(clk), .clk_out, .rst_n(link_rst_n), .io_out, .io_in(link_io_in),
    .req, .wr, .ready(link_ready), .rvalid(link_rvalid));

  forte_top dut (
    .core_clk(clk), .rst_n, .io_in, .io_out, .req, .clk_out, .wr, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx, .test_mode, .scan_en, .fault_inject, .status);

  always #50 clk = ~clk;            // rises at 50, 150, ...

  int errors = 0;
  int len [N:1];                    // discovered in phase A
  logic inv [N:1];                  // 1: the chain shifts out ~in (odd QN count)
  int maxlen = 0;

  bit trace_cycles, trace_shift, dump_on_error = 1'b1;
  bit in_check_fail = 1'b0;
  bit have_snapshot = 1'b0;
  // A/M/B are prerequisites. Remaining letters execute in the requested order.
  string phase_order = "CDEPHFRI", case_filter = "", scan_op = "capture";
  bit baseline_ok = 0, sentinel_enabled = 0, sweep_enabled = 0;
  bit unload_reset_enabled = 1;
  int case_repeats = 1, cases_selected = 0, checks_skipped = 0;
  int unsigned scan_seed = 1;
  int random_iters = 100, exec_iters = 16;
  real launch_ns = 2.0; // post-synthesis FPGA_TCO_PS convention
  // Set +SCAN_NO_DUMP to omit large failure snapshots.
  // Set +SCAN_TRACE_CYCLES for per-clock traces or +SCAN_TRACE_SHIFT for shift progress.
  initial begin
    trace_cycles = $test$plusargs("SCAN_TRACE_CYCLES");
    trace_shift = $test$plusargs("SCAN_TRACE_SHIFT");
    dump_on_error = !$test$plusargs("SCAN_NO_DUMP");
    $display("[%0t] TRACE CONFIG: cycles=%0b shift=%0b dump_on_error=%0b", $time,
             trace_cycles, trace_shift, dump_on_error);
  end

  task automatic fail(input string msg);
    errors++;
    $display("[%0t] ERROR #%0d: %s", $time, errors, msg);
    if (dump_on_error && !in_check_fail)
      $display("[%0t] SCAN DUMP: no current compared scan snapshot for this structural error; SI=%b SO=%b SE=%b TM=%b RST_N=%b",
               $time, si, so, scan_en, test_mode, rst_n);
  endtask


  // Per-phase summary: errors counts fail() calls, not individual wrong bits.
  int phase_errors [0:10];
  bit phase_ran [0:10];
  int phase_skips [0:10];
  int phase_cases [0:10];
  bit phase_empty [0:10];
  string phase_names [0:10] = '{"A chain lengths", "M scan map", "B reset",
      "C round trip", "D base capture", "E PC", "P registers",
      "H hardening", "F reset recovery", "R randomized", "I instruction scan"};
  int phase_start_errors;
  int phase_start_cases, phase_start_skips;

  task automatic phase_begin(input int p);
    phase_start_errors = errors;
    phase_start_cases = cases_selected;
    phase_start_skips = checks_skipped;
    phase_ran[p] = 1'b1;
    $display("[%0t] PHASE START: %s (errors so far: %0d)",
             $time, phase_names[p], errors);
  endtask

  task automatic phase_end(input int p);
    phase_errors[p] += errors - phase_start_errors;
    phase_skips[p] += checks_skipped - phase_start_skips;
    phase_cases[p] += cases_selected - phase_start_cases;
    phase_empty[p] = p >= 4 && phase_cases[p] == 0;
    $display("[%0t] PHASE END: %s: %s (%0d new errors)",
             $time, phase_names[p], phase_errors[p] != 0 ? "FAIL" :
             (phase_empty[p] ? "SKIP" : (phase_skips[p] != 0 ? "PARTIAL" : "PASS")),
             phase_errors[p]);
  endtask

  task automatic phase_summary();
    $display("================ DFT PHASE SUMMARY ================");
    for (int p = 0; p < 11; p++)
      $display("PHASE: %-20s %-5s errors=%0d", phase_names[p],
               !phase_ran[p] ? "SKIP" : (phase_errors[p] != 0 ? "FAIL" :
               (phase_empty[p] ? "SKIP" : (phase_skips[p] != 0 ? "PARTIAL" : "PASS"))),
               phase_errors[p]);
    $display("PHASE: TOTAL errors=%0d", errors);
    $display("PHASE: selected_cases=%0d explicit_skips=%0d operation=%s", cases_selected, checks_skipped, scan_op);
    $display("===================================================");
  endtask

  function automatic bit case_selected(input string tag);
    if (case_filter == "") return 1;
    for (int i = 0; i + case_filter.len() <= tag.len(); i++)
      if (tag.substr(i, i + case_filter.len() - 1) == case_filter) return 1;
    return 0;
  endfunction

  task automatic skip_check(input string tag, input string reason);
    checks_skipped++;
    $display("[%0t] SKIP: %s: %s", $time, tag, reason);
  endtask


  // ---- scan map ---------------------------------------------------------------
  typedef enum int {G_PC, G_PIPELINE, G_HCSR, G_NONE} group_e;
  typedef enum int {K_PC, K_DATA, K_ECC, K_CTRL, K_TMR, K_MPP, K_MSECFAULT, K_STICKY,
                    K_LOCK, K_UNKNOWN} kind_e;
  typedef logic [MAX_W-1:0] val_t;
  typedef logic [63:0]      pc_t;
  typedef logic st_t   [N:1][1:MAX_LEN];  // the value in each cell, j = 1 next to scan-in
  typedef logic bits_t [N:1][MAX_LEN];    // one bit per shift cycle

  // From scan_map.svh
  int     n_regs;
  string  reg_name  [MAX_REGS];
  group_e reg_group [MAX_REGS];
  kind_e  reg_kind  [MAX_REGS];
  val_t   reg_rst   [MAX_REGS];          // reset value; X: no reset
  int     reg_sub   [MAX_REGS];          // privmode copy: 0-2 mode a-c, 3-5 check a-c
  string  map_notes [$];
  int     map_len [N:1];
  int     map_reg [N:1][1:MAX_LEN];      // register the cell belongs to
  int     map_bit [N:1][1:MAX_LEN];      // bit of it the cell holds
  int     map_qn  [N:1][1:MAX_LEN];      // 1: scan output from QN; 2: not in the scandef
  int     map_ph  [N:1][1:MAX_LEN];      // 1: the flop holds the bit inverted (only QN drives logic)
  // Built in M
  logic   a_inv   [N:1][1:MAX_LEN];      // inversion from scan-in to the cell's SI
  logic   b_inv   [N:1][1:MAX_LEN];      // inversion from the cell's Q to scan-out
  int     reg_k     [MAX_REGS][MAX_W];   // chain and cell of bit b of register r; k = 0: none
  int     reg_j     [MAX_REGS][MAX_W];
  int     reg_cells [MAX_REGS];
  int     reg_width [MAX_REGS];          // highest bit with a cell, plus one (ECC: ECC_CW)
  int     reg_fail  [MAX_REGS];          // checks the register failed
  val_t   reg_bad   [MAX_REGS];          // bits wrong in any of them
  bit     map_ok = 0;
  int     pc_r = -1, msf_r = -1, mpp_r = -1;
  int     tmr_r [6] = '{default: -1};
  int     ecc_r [$];
  st_t    base;                          // the cells after B's reset, X read as 0
  st_t    rst_exp;                       // the reset values, X where there is none
`include "scan_map.generated.svh"
`ifdef SCAN_NO_HOOKUPS
  // Diagnostic hookups are never required for the pin-level verdict.
  val_t internal_raw_by_name[string];
  val_t internal_est_by_name[string];
  val_t internal_available_by_name[string];
`else
`include "scan_hookups.generated.svh"
`endif

  // A scan unload overwrites the flop state. Save live hookups before shifting.
  val_t internal_raw_snapshot[string];
  val_t internal_est_snapshot[string];
  val_t internal_available_snapshot[string];
  val_t before_raw_snapshot[string];
  val_t before_est_snapshot[string];
  val_t before_available_snapshot[string];
  bit have_before_snapshot = 0;
  string internal_snapshot_tag;
  task automatic snapshot_internal(input string tag, input bit before_capture = 0);
    internal_snapshot_tag = tag;
    internal_raw_snapshot.delete();
    internal_est_snapshot.delete();
    internal_available_snapshot.delete();
    for (int r = 0; r < n_regs; r++) begin
      if (internal_raw_by_name.exists(reg_name[r]))
        internal_raw_snapshot[reg_name[r]] = internal_raw_by_name[reg_name[r]];
      if (internal_est_by_name.exists(reg_name[r]))
        internal_est_snapshot[reg_name[r]] = internal_est_by_name[reg_name[r]];
      if (internal_available_by_name.exists(reg_name[r]))
        internal_available_snapshot[reg_name[r]] = internal_available_by_name[reg_name[r]];
    end
    if (before_capture) begin
      before_raw_snapshot = internal_raw_snapshot;
      before_est_snapshot = internal_est_snapshot;
      before_available_snapshot = internal_available_snapshot;
      have_before_snapshot = 1;
    end
    $display("[%0t] TRACE internal snapshot: %s, physical_Q(no_logical_polarity)=%0d logical_est(Q_xor_map_ph)=%0d registers",
             $time, tag, internal_raw_snapshot.num(), internal_est_snapshot.num());
  endtask

  // Scan enable: the scan_en pin.
  task automatic set_se(input logic v);
`ifdef BREAK_SE
    v = 1'b0;                       // self-test: the chains must then fail
`endif
    if (scan_en !== v) $display("[%0t] TRACE set_se: %b -> %b", $time, scan_en, v);
    scan_en = v;
  endtask

  // One test cycle: drive scan-in, strobe scan-out, clock.  Returns just after
  // the edge, so a pin changed after it is stable for the whole next cycle.
  task automatic cycle(input logic [N:1] in_bits, output logic [N:1] out_bits);
    if (trace_cycles) $display("[%0t] TRACE cycle START: SI=%b SE=%b TM=%b RST=%b", $time, in_bits, scan_en, test_mode, rst_n);
    @(negedge clk); #10;
    si = in_bits;
    #30;
    out_bits = so;
    if (trace_cycles) $display("[%0t] TRACE cycle SAMPLE: SI=%b SO=%b", $time, in_bits, out_bits);
    @(posedge clk); #(launch_ns);
  endtask

  task automatic idle(input int n);
    logic [N:1] unused;
    $display("[%0t] TRACE idle START: %0d cycles (SE=%b TM=%b RST=%b)", $time, n, scan_en, test_mode, rst_n);
    repeat (n) cycle('0, unused);
    $display("[%0t] TRACE idle END: %0d cycles", $time, n);
  endtask

  // Raise test_mode and let it through tmsync before the first shift edge.
  // Returns just after an edge with scan selected, as the callers expect.
  task automatic enter_test();
    set_se(1'b0);
    test_mode = 1'b1;
    idle(TM_SYNC);
    set_se(1'b1);
  endtask

  // Shift maxlen cycles: chain k takes in[k][t] at cycle t and its output is
  // returned in out[k][t].  The first bit out of a chain is the one next to
  // its io_out; after the shift, chain k holds in[k][maxlen-len[k] .. maxlen-1],
  // cell j holding in[k][maxlen-j].
  task automatic shift(input bits_t in, output bits_t out);
    logic [N:1] i_b, o_b;
    $display("[%0t] TRACE shift START: %0d clocks, SE=%b TM=%b RST=%b", $time, maxlen, scan_en, test_mode, rst_n);
    for (int t = 0; t < maxlen; t++) begin
      if (trace_shift && (t % 32 == 0 || t == maxlen-1)) $display("[%0t] TRACE shift cycle=%0d/%0d", $time, t+1, maxlen);
      for (int k = 1; k <= N; k++) i_b[k] = in[k][t];
      cycle(i_b, o_b);
      for (int k = 1; k <= N; k++) out[k][t] = o_b[k];
    end
    $display("[%0t] TRACE shift END", $time);
  endtask

  // The shift-in stream that leaves s in the cells.
  function automatic bits_t encode(input st_t s);
    bits_t in = '{default: '{default: 1'b0}};
    for (int k = 1; k <= N; k++)
      for (int j = 1; j <= len[k]; j++)
        in[k][maxlen - j] = s[k][j] ^ a_inv[k][j];
    return in;
  endfunction

  // The cells, from the stream shifted out of them.
  function automatic st_t decode(input bits_t out);
    st_t s = '{default: '{default: 1'bx}};
    for (int k = 1; k <= N; k++)
      for (int t = 0; t < len[k]; t++)
        s[k][len[k] - t] = out[k][t] ^ b_inv[k][len[k] - t];
    return s;
  endfunction

  // Register r's value in s; bits with no cell read 0.
  function automatic val_t reg_val(input st_t s, input int r);
    val_t v = '0;
    for (int b = 0; b < reg_width[r]; b++)
      if (reg_k[r][b] > 0) v[b] = s[reg_k[r][b]][reg_j[r][b]];
    return v;
  endfunction

  // s with register r set to v (on the bits that have a cell).
  function automatic st_t reg_put(input st_t s, input int r, input val_t v);
    for (int b = 0; b < reg_width[r]; b++)
      if (reg_k[r][b] > 0) s[reg_k[r][b]][reg_j[r][b]] = v[b];
    return s;
  endfunction

  // base, with flag bit f of MSECFAULT also set
  function automatic st_t with_flag(input st_t s, input int f);
    return reg_put(s, msf_r, reg_val(s, msf_r) | (val_t'(1) << f));
  endfunction

  function automatic val_t rand_val();
    val_t v;
    for (int i = 0; i < MAX_W / 32; i++) v[i*32 +: 32] = $urandom;
    return v;
  endfunction

  // ecc_secded_enc for DATA_WIDTH = 64: {data, overall parity, hamming[6:0]}
  function automatic logic [ECC_CW-1:0] ecc_enc(input logic [ECC_DW-1:0] d);
    logic [ECC_R-1:0] h = '0;
    for (int k = 0; k < ECC_R; k++)
      for (int p = 1; p <= ECC_DW + ECC_R; p++)
        if ((p & (p - 1)) != 0 && ((p >> k) & 1))
          h[k] ^= d[p - $clog2(p + 1) - 1];
    return {d, ^d ^ ^h, h};
  endfunction

  function automatic string hexw(input val_t v, input int w);
    string s = "";
    for (int b = ((w + 3) / 4 - 1) * 4; b >= 0; b -= 4) s = {s, $sformatf("%h", v[b +: 4])};
    return s;
  endfunction

  function automatic string bit_list(input val_t m, input int max_n);
    string s = "";
    int n = 0;
    for (int b = MAX_W - 1; b >= 0; b--)
      if (m[b] === 1'b1) begin
        n++;
        if (n <= max_n) s = {s, $sformatf(" %0d", b)};
      end
    if (n > max_n) s = {s, " ..."};
    return s;
  endfunction

  // MSB first, one character per bit. Unavailable/Z values print as '-'.
  // Preserve X on an available output; never substitute a logical constant.
  function automatic string internal_bits(input val_t v, input val_t available, input int w);
    string s = "";
    for (int b = w - 1; b >= 0; b--)
      s = {s, (available[b] === 1'b1 && v[b] !== 1'bz) ? $sformatf("%b", v[b]) : "-"};
    return s;
  endfunction

  task automatic report_internal(input int r, input st_t got, input st_t exp);
    val_t available;
    if (!internal_raw_snapshot.exists(reg_name[r]) ||
        !internal_est_snapshot.exists(reg_name[r]) ||
        !internal_available_snapshot.exists(reg_name[r])) begin
      $display("[%0t] INTERNAL: %s no complete diagnostic snapshot; enable generated hookups with SCAN_HOOKUPS=1",
               $time, reg_name[r]);
      return;
    end
    available = internal_available_snapshot[reg_name[r]];
    if (have_before_snapshot && before_raw_snapshot.exists(reg_name[r]) &&
        before_est_snapshot.exists(reg_name[r]) && before_available_snapshot.exists(reg_name[r]))
      $display("[%0t] INTERNAL BEFORE CAPTURE: %s raw_Q='b%s logical_est(Q^map_ph)='b%s",
               $time, reg_name[r],
               internal_bits(before_raw_snapshot[reg_name[r]], before_available_snapshot[reg_name[r]], reg_width[r]),
               internal_bits(before_est_snapshot[reg_name[r]], before_available_snapshot[reg_name[r]], reg_width[r]));
    // raw_Q is physical Q (.Q or ~.QN), without map_ph correction.
    // logical_est applies map_ph only to available observations.
    $display("[%0t] INTERNAL: %s snapshot=%s raw_Q='b%s logical_est(Q^map_ph)='b%s scan_read=0x%s expected=0x%s",
             $time, reg_name[r], internal_snapshot_tag,
             internal_bits(internal_raw_snapshot[reg_name[r]], available, reg_width[r]),
             internal_bits(internal_est_snapshot[reg_name[r]], available, reg_width[r]),
             hexw(reg_val(got, r), reg_width[r]), hexw(reg_val(exp, r), reg_width[r]));
  endtask

  // Full non-destructive scan snapshot. Cells are printed in scan-in to
  // scan-out order; index 1 is nearest the scan-in pad. No extra DUT clocks.
  task automatic dump_scan(input string tag, input st_t got, input st_t exp);
    string actual_s, expect_s, bad_s;
    int lim;
    $display("[%0t] SCAN DUMP BEGIN: %s (1=nearest scan-in, X=unconstrained/unknown)", $time, tag);
    $display("[%0t] SCAN DUMP PINS: clk=%b rst_n=%b test_mode=%b scan_en=%b si=%b so=%b",
             $time, clk, rst_n, test_mode, scan_en, si, so);
    for (int k = 1; k <= N; k++) begin
      lim = len[k];
      if (lim < 0) lim = 0;
      if (lim > MAX_LEN) lim = MAX_LEN;
      $display("[%0t] SCAN DUMP c%0d io_in[%0d]->io_out[%0d], length=%0d inversion=%b",
               $time, k-1, k-1, k-1, len[k], inv[k]);
      for (int first = 1; first <= lim; first += 64) begin
        actual_s = ""; expect_s = ""; bad_s = "";
        for (int j = first; j <= lim && j < first+64; j++) begin
          actual_s = {actual_s, $sformatf("%b", got[k][j])};
          expect_s = {expect_s, $sformatf("%b", exp[k][j])};
          bad_s = {bad_s, (!$isunknown(exp[k][j]) && got[k][j] !== exp[k][j]) ? "^" : "."};
        end
        $display("  c%0d cells %0d..%0d ACT %s", k-1, first,
                 (first+63 < lim ? first+63 : lim), actual_s);
        $display("  c%0d cells %0d..%0d EXP %s", k-1, first,
                 (first+63 < lim ? first+63 : lim), expect_s);
        $display("  c%0d cells %0d..%0d DIF %s", k-1, first,
                 (first+63 < lim ? first+63 : lim), bad_s);
      end
    end
    $display("[%0t] SCAN DUMP END: %s", $time, tag);
  endtask

  // Compare the cells read against exp, wherever exp is not X; one error per
  // register that differs.
  int n_pat, n_pat_bad;
  task automatic check(input string tag, input st_t got, input st_t exp);
    val_t wrong [int];
    $display("[%0t] TRACE check START: %s", $time, tag);
    for (int k = 1; k <= N; k++)
      for (int j = 1; j <= len[k]; j++)
        if (!$isunknown(exp[k][j]) && got[k][j] !== exp[k][j]) begin
          int r = map_reg[k][j];
          if (!wrong.exists(r)) wrong[r] = '0;
          wrong[r][map_bit[k][j]] = 1'b1;
        end
    n_pat++;
    if (wrong.size() != 0) begin
      n_pat_bad++;
      if (dump_on_error) dump_scan(tag, got, exp);
    end
    in_check_fail = 1'b1;
    foreach (wrong[r]) begin
      reg_fail[r]++;
      reg_bad[r] |= wrong[r];
      fail($sformatf("%s: %s read %s, expected %s; wrong bit(s):%s", tag, reg_name[r],
                     hexw(reg_val(got, r), reg_width[r]), hexw(reg_val(exp, r), reg_width[r]),
                     bit_list(wrong[r], 12)));
      report_internal(r, got, exp);
    end
    in_check_fail = 1'b0;
    $display("[%0t] TRACE check END: %s, failing registers=%0d", $time, tag, wrong.size());
  endtask

  // Shift s in with rst_n low, raised RST_LAT edges before the end: the core
  // leaves reset just after the last shift edge, so the capture edge is its
  // first cycle out of reset, with s in the cells.
  task automatic prepare_case();
    // Called at the post-edge launch slot, never between loading and capture.
    // Allow reset to assert before disabling scan/remapping the shared pads.
    link_active = 0;
    rst_n = 1'b0;
    idle(20);
    set_se(1'b0);
    test_mode = 1'b0;
    idle(20);
    enter_test();                   // still in reset: the settle edges change nothing
  endtask

  task automatic load_in_reset(input st_t s);
    bits_t in = encode(s);
    logic [N:1] i_b, o_b;
    have_before_snapshot = 0;
    prepare_case();
    $display("[%0t] TRACE load_in_reset START: %0d scan clocks, reset release at cycle %0d", $time, maxlen, maxlen-`RST_LAT);
    rst_n = 1'b0;
    for (int t = 0; t < maxlen; t++) begin
      if (t == maxlen - `RST_LAT) begin
        rst_n = 1'b1;
        $display("[%0t] TRACE load_in_reset: release external reset at shift cycle %0d", $time, t);
      end
      for (int k = 1; k <= N; k++) i_b[k] = in[k][t];
      cycle(i_b, o_b);
    end
    $display("[%0t] TRACE task END: load_in_reset", $time);
  endtask

  // Observe the loaded/captured state before asserting reset. No extra clocks
  // are inserted: scan remains enabled throughout the reset-protected shift.
  // Reset must not override the selected cells' scan path. The pin comparison
  // still checks the original loaded/captured expectation, never reset values.
  task automatic scan_readout(input string tag, output bits_t got);
    bits_t zeros = '{default: '{default: 1'b0}};
    logic saved_rst_n = rst_n;
    if (scan_en !== 1'b1 || test_mode !== 1'b1) begin
      got = '{default: '{default: 1'bx}};
      fail({tag, ": readout requires scan_en=1 and test_mode=1"});
      return;
    end
    $display("[%0t] READOUT START: %s reset_protection=%b rst_n=%b SE=%b TM=%b",
             $time, tag, unload_reset_enabled, rst_n, scan_en, test_mode);
    if (unload_reset_enabled) rst_n = 1'b0;
    shift(zeros, got);
    for (int k = 1; k <= N; k++)
      for (int t = 0; t < len[k]; t++)
        if ($isunknown(got[k][t])) begin
          $display("[%0t] READOUT FIRST X/Z: %s c%0d sample=%0d (zero-based=%0d) reset_protection=%b",
                   $time, tag, k-1, t+1, t, unload_reset_enabled);
          break;
        end
    if (unload_reset_enabled) rst_n = saved_rst_n;
    $display("[%0t] READOUT END: %s rst_n=%b SE=%b TM=%b", $time, tag, rst_n, scan_en, test_mode);
  endtask

  // Load, hold, unload, compare.  func_cyc = 0: one capture clock in test mode.
  // Otherwise func_cyc clocks with scan disabled; keep_test_mode optionally
  // retains the scan pad mux. A single capture uses the fetch-check interlock; longer
  // unchanged-state holds are optional diagnostics, not guaranteed by ready=0.
  task automatic hold_once(input string tag, input st_t load, input st_t exp,
                           input int func_cyc = 0, input bit keep_test_mode = 0);
    bits_t got;
    $display("[%0t] TRACE hold START: %s, functional cycles=%0d", $time, tag, func_cyc);
    load_in_reset(load);
    snapshot_internal({tag, " before capture"}, 1'b1);
    set_se(1'b0);
    $display("[%0t] TRACE hold: SE=0, %s", $time, func_cyc == 0 ? "one capture edge" : "enter functional mode");
    if (func_cyc == 0) begin
      @(posedge clk); #(launch_ns);
    end
    else begin
      if (!keep_test_mode) test_mode = 1'b0;
      $display("[%0t] TRACE hold: test_mode=%b", $time, test_mode);
      idle(func_cyc);
      // Dropping test_mode costs TM_SYNC more functional edges to raise it.
      if (!keep_test_mode) enter_test();
      $display("[%0t] TRACE hold: test_mode=1", $time);
    end
    set_se(1'b1);
    snapshot_internal(tag);
    scan_readout(tag, got);
    check(tag, decode(got), exp);
    $display("[%0t] TRACE hold END: %s", $time, tag);
  endtask

  task automatic load_only(input string tag, input st_t load, output bit passed);
    bits_t got;
    int before_errors = errors;
    load_in_reset(load);
    snapshot_internal({tag, " after load, no capture"});
    // SE stays high: the first sample observes the loaded state before shifting.
    scan_readout({tag, " [load-only]"}, got);
    check({tag, " [load-only]"}, decode(got), load);
    passed = errors == before_errors;
  endtask

  task automatic hold(input string tag, input st_t load, input st_t exp,
                      input int func_cyc = 0, input bit keep_test_mode = 0);
    bit loaded;
    int sentinel_errors;
    if (!case_selected(tag)) return;
    cases_selected++;
    for (int rep = 0; rep < case_repeats; rep++) begin
      $display("[%0t] CASE: %s repeat=%0d/%0d seed=%0d operation=%s", $time,
               tag, rep+1, case_repeats, scan_seed, scan_op);
      if (sentinel_enabled) begin
        sentinel_errors = errors;
        hold_once({tag, " [baseline sentinel]"}, base, base);
        if (errors != sentinel_errors) begin
          skip_check(tag, "baseline sentinel failed; target not run");
          continue;
        end
      end
      if (scan_op == "load" || scan_op == "both") begin
        load_only(tag, load, loaded);
        if (!loaded) begin
          skip_check(tag, "load-only failed; capture result would be uninterpretable");
          continue;
        end
      end
      // Reload independently after the destructive diagnostic unload.
      if (scan_op != "load") hold_once(tag, load, exp, func_cyc, keep_test_mode);
    end
  endtask

  // Reset plus startup check at RESET_VEC without external memory responses.
  // This follows a naturally reached state; unlike scan reload, it preserves
  // coherence between scanned and unscanned logic. Returns in scan mode.
  task automatic reset_stalled();
    $display("[%0t] TRACE reset_stalled START", $time);
    set_se(1'b0); test_mode = 1'b0;
    rst_n = 1'b0; idle(20);
    rst_n = 1'b1;
    $display("[%0t] TRACE reset_stalled: deassert reset, wait 200 clocks without memory responses", $time);
    idle(200);
    enter_test();                   // TM_SYNC more stalled edges; ends just after one
    $display("[%0t] TRACE reset_stalled END", $time);
  endtask

  task automatic unload(output st_t s);
    bits_t got;
    have_before_snapshot = 0;
    $display("[%0t] TRACE unload START", $time);
    snapshot_internal("unload");
    scan_readout("unload", got);
    s = decode(got);
    $display("[%0t] TRACE unload END", $time);
  endtask

  function automatic string group_str(input group_e g);
    case (g)
      G_PC:       return "pc";
      G_PIPELINE: return "pipeline";
      G_HCSR:     return "hardened_csr";
      default:    return "no group";
    endcase
  endfunction

  // ---- A: lengths and flush -------------------------------------------------------
  task automatic phase_a();
    logic [N:1] got;
    int total = 0;
    $display("[%0t] A: chain lengths", $time);
    enter_test();
    idle(MAX_LEN);                                    // flush to zeros
    foreach (len[k]) len[k] = -1;
    for (int t = 0; t <= MAX_LEN; t++) begin
      cycle(t == 0 ? '1 : '0, got);
      for (int k = 1; k <= N; k++) begin
        if ($isunknown(got[k])) begin
          if (len[k] != 0)
            fail($sformatf("A: c%0d: io_out[%0d] is X after a zero flush (chain broken?)", k-1, k-1));
          len[k] = 0;
        end
        // t = 0 is strobed before the 1 is clocked in: the flushed value
        if (t == 0) inv[k] = got[k];
        else if (got[k] !== inv[k] && len[k] < 0) len[k] = t;
      end
    end
    for (int k = 1; k <= N; k++) begin
      if (len[k] <= 0) begin
        fail($sformatf("A: c%0d: the 1 from io_in[%0d] never reached io_out[%0d]", k-1, k-1, k-1));
        len[k] = 0;
      end
      $display("[%0t] A: c%0d (io_in[%0d] -> io_out[%0d]) length %0d%s", $time, k-1, k-1, k-1, len[k],
               string'(inv[k] === 1'b1 ? ", inverting" : ""));
      total += len[k];
      if (len[k] > maxlen) maxlen = len[k];
    end
    $display("[%0t] A: %0d scan cells in total", $time, total);
`ifdef EXPECTED_CELLS
    if (total != `EXPECTED_CELLS)
      fail($sformatf("A: %0d scan cells in total, expected %0d", total, `EXPECTED_CELLS));
`endif
    // 0011... through every chain: what comes out is what went in len[k] cycles earlier
    for (int t = 0; t < 3 * maxlen + 4; t++) begin
      cycle({N{t[1]}}, got);
      for (int k = 1; k <= N; k++)
        if (len[k] > 0 && t >= len[k] && got[k] !== (logic'((t - len[k]) >> 1 & 1) ^ inv[k]))
          fail($sformatf("A: flush, c%0d cycle %0d", k-1, t));
    end
    $display("[%0t] TRACE task END: phase_a", $time);
  endtask

  // ---- M: the scandef's map against the pins -----------------------------------
  task automatic phase_m();
    int    g_regs [4], g_cells [4];
    string s;
    $display("[%0t] M: scan map", $time);
    foreach (map_len[k]) map_len[k] = 0;
    scan_map_init();
`ifdef BREAK_MAP
    // self-test: move an inversion one cell along c0, keeping the chain's parity
    map_qn[1][1] = map_qn[1][1] == 1 ? 0 : 1;
    map_qn[1][2] = map_qn[1][2] == 1 ? 0 : 1;
`endif
    map_ok = 1;
    for (int k = 1; k <= N; k++) begin
      logic par;
      int   last;
      if (map_len[k] != len[k]) begin
        fail($sformatf("M: c%0d is %0d cells in the scandef, %0d at the pins", k-1, map_len[k], len[k]));
        map_ok = 0;
        continue;
      end
      if (len[k] == 0) continue;
      last = len[k];
      par  = 1'b0;
      for (int j = 1; j < last; j++) begin
        if (map_qn[k][j] == 2) begin
          fail($sformatf("M: c%0d cell %0d has no scan-out pin in the scandef", k-1, j));
          map_ok = 0;
        end
        par ^= (map_qn[k][j] == 1);
      end
      // The last cell's scan-out pin is not in the scandef: the pin decides it.
      if (map_qn[k][last] == 2) map_qn[k][last] = int'(par ^ inv[k]);
      else if ((par ^ (map_qn[k][last] == 1)) !== inv[k]) begin
        fail($sformatf("M: c%0d: the scandef's inversions give %0d, the pin %b", k-1, par ^ (map_qn[k][last] == 1), inv[k]));
        map_ok = 0;
      end
      a_inv[k][1] = 1'b0;
      for (int j = 2; j <= last; j++) a_inv[k][j] = a_inv[k][j-1] ^ (map_qn[k][j-1] == 1);
      b_inv[k][last] = (map_qn[k][last] == 1);
      for (int j = last - 1; j >= 1; j--) b_inv[k][j] = b_inv[k][j+1] ^ (map_qn[k][j] == 1);
      // A flop whose only output in use is QN holds the register bit inverted:
      // a_inv/b_inv then run to the bit, not to the flop.
      for (int j = 1; j <= last; j++) begin
        a_inv[k][j] ^= map_ph[k][j];
        b_inv[k][j] ^= map_ph[k][j];
      end
      // Each cell to its register bit; then the chain as runs of registers
      for (int j = 1; j <= last; j++) begin
        int r = map_reg[k][j], b = map_bit[k][j];
        if (r < 0 || r >= n_regs || b < 0 || b >= MAX_W) begin
          fail($sformatf("M: c%0d cell %0d: register %0d bit %0d is out of range", k-1, j, r, b));
          map_ok = 0;
        end
        else if (reg_k[r][b] != 0) begin
          fail($sformatf("M: %s[%0d] is on two cells: c%0d cell %0d and c%0d cell %0d",
                         reg_name[r], b, reg_k[r][b]-1, reg_j[r][b], k-1, j));
          map_ok = 0;
        end
        else begin
          reg_k[r][b] = k; reg_j[r][b] = j;
          reg_cells[r]++;
          if (b + 1 > reg_width[r]) reg_width[r] = b + 1;
        end
      end
      s = "";
      for (int j = 1; j <= last; ) begin
        int j1 = j, nqn = 0;
        while (j1 < last && map_reg[k][j1+1] == map_reg[k][j]) j1++;
        for (int jj = j; jj <= j1; jj++) nqn += (map_qn[k][jj] == 1);
        s = {s, " ", map_reg[k][j] >= 0 && map_reg[k][j] < n_regs ? reg_name[map_reg[k][j]] : "?",
             j1 == j ? $sformatf("[%0d]", map_bit[k][j]) : $sformatf("[%0d..%0d]", map_bit[k][j], map_bit[k][j1]),
             nqn > 0 ? $sformatf("(%0d~)", nqn) : ""};
        j = j1 + 1;
      end
      $display("[%0t] M: c%0d, scan-in to scan-out (n~ = n cells read from QN):%s", $time, k-1, s);
    end
    if (!map_ok) begin
      $display("[%0t] M: the map does not match the pins: B and D-H skipped", $time);
      return;
    end

    // Each register: what the bench may do with it, and the bits it has no cell for
    for (int r = 0; r < n_regs; r++) begin
      int w;
      if (reg_cells[r] == 0) continue;
      g_regs[reg_group[r]]++;
      g_cells[reg_group[r]] += reg_cells[r];
      case (reg_kind[r])
        K_UNKNOWN:   fail($sformatf("M: %s (%0d cells) is not in scan_map.awk's table: add a row for it",
                                    reg_name[r], reg_cells[r]));
        K_LOCK:      fail($sformatf("M: %s (%0d cells) is the DFT lock: it must not be on a chain",
                                    reg_name[r], reg_cells[r]));
        K_PC:        pc_r  = r;
        K_MSECFAULT: msf_r = r;
        K_MPP:       mpp_r = r;
        K_TMR:       tmr_r[reg_sub[r]] = r;
        K_ECC: begin
          ecc_r.push_back(r);
          if (reg_width[r] > ECC_CW)
            fail($sformatf("M: %s has a cell for codeword bit %0d; codewords are %0d bits",
                           reg_name[r], reg_width[r] - 1, ECC_CW));
          else reg_width[r] = ECC_CW;
        end
        default: ;
      endcase
      w = reg_width[r];
      s = "";
      for (int b = 0; b < w; b++) if (reg_k[r][b] == 0) s = {s, $sformatf(" %0d", b)};
      if (s != "")
        $display("[%0t] M: %s: %0d of %0d bits on the chains; none for bit(s):%s", $time,
                 reg_name[r], reg_cells[r], w, s);
      if (reg_kind[r] == K_PC)
        for (int b = 1; b < w; b++)
          if (reg_k[r][b] == 0) fail($sformatf("M: PC[%0d] is on no chain", b));
    end
    foreach (map_notes[i]) $display("[%0t] M: %s", $time, map_notes[i]);
    for (int g = 0; g < 4; g++)
      if (g_regs[g] > 0)
        $display("[%0t] M: %s: %0d register(s), %0d cells", $time, group_str(group_e'(g)), g_regs[g], g_cells[g]);
    $display("[%0t] TRACE task END: phase_m", $time);
  endtask

  // ---- B: reset values ----------------------------------------------------------------
  task automatic phase_b();
    st_t got;
    int before_errors = errors;
    $display("[%0t] B: every cell after reset", $time);
    rst_exp = '{default: '{default: 1'bx}};
    for (int r = 0; r < n_regs; r++)
      if (reg_kind[r] != K_UNKNOWN && reg_kind[r] != K_LOCK)
        for (int b = 0; b < reg_width[r]; b++)
          if (reg_k[r][b] > 0) rst_exp[reg_k[r][b]][reg_j[r][b]] = reg_rst[r][b];
    n_pat = 0; n_pat_bad = 0;
    reset_stalled();
    unload(got);
    check("B reset value", got, rst_exp);
    baseline_ok = errors == before_errors;
    if (!baseline_ok) begin
      $display("[%0t] BLOCKED: constrained reset baseline failed; dependent cases will not run", $time);
      return;
    end
    base = got;
    // Deliberate deterministic stimulus for unconstrained bits only. The
    // observation in got/rst_exp is never sanitized, and constrained Xs failed.
    foreach (base[k, j]) if (base[k][j] !== 1'b1) base[k][j] = 1'b0;
    if (pc_r >= 0) $display("[%0t] B: PC = %h", $time, pc_t'(reg_val(got, pc_r)));
    $display("[%0t] TRACE task END: phase_b", $time);
  endtask

  // ---- C: random round trip -----------------------------------------------------------
  task automatic phase_c();
    logic [N:1] got;
    logic [N:1] data [];
    $display("[%0t] C: random round trip", $time);
    data = new[maxlen * 8];
    foreach (data[t]) data[t] = N'($urandom);
    for (int t = 0; t < data.size(); t++) begin
      cycle(data[t], got);
      for (int k = 1; k <= N; k++)
        if (len[k] > 0 && t >= len[k] && got[k] !== (data[t - len[k]][k] ^ inv[k]))
          fail($sformatf("C: c%0d cycle %0d", k-1, t));
    end
    $display("[%0t] TRACE task END: phase_c", $time);
  endtask

  // ---- D: first capture; optional longer retention experiments ----------------------------
  task automatic phase_d();
    int durations [6] = '{1, 2, 4, 8, 16, FUNC_CYC};
    $display("[%0t] D: baseline first capture", $time);
    n_pat = 0; n_pat_bad = 0;
    hold("D base, one capture edge", base, base);
    if (sweep_enabled) begin
      $display("[%0t] DIAGNOSTIC D: long retention assumes a persistent stall; ready=0 does not guarantee it. Mismatches fail this run.", $time);
      hold($sformatf("D base, %0d functional cycles", FUNC_CYC), base, base, FUNC_CYC);
      foreach (durations[i]) begin
        hold($sformatf("D sweep functional %0d", durations[i]), base, base, durations[i]);
        hold($sformatf("D sweep test-mode %0d", durations[i]), base, base, durations[i], 1'b1);
      end
    end
    $display("[%0t] D: %0d holds, %0d failed", $time, n_pat, n_pat_bad);
    $display("[%0t] TRACE task END: phase_d", $time);
  endtask

  // ---- E: PC values held ----------------------------------------------------------------
  task automatic hold_pc(input string tag, input pc_t v, input int func_cyc = 0);
    st_t s = reg_put(base, pc_r, val_t'(v));
    $display("[%0t] TRACE hold_pc: %s PC=%h func_cyc=%0d", $time, tag, v, func_cyc);
    hold(tag, s, s, func_cyc);
  endtask

  task automatic phase_e();
    pc_t v;
    if (pc_r < 0) begin
      skip_check("E", "the PC is on no chain");
      return;
    end
    $display("[%0t] E: PC values through scan load, hold, scan unload", $time);
    n_pat = 0; n_pat_bad = 0;
    hold_pc("E all 0",       '0);
    hold_pc("E all 1",       '1);
    hold_pc("E 0x5555...",   {32{2'b01}});
    hold_pc("E 0xAAAA...",   {32{2'b10}});
    hold_pc("E 0x3333...",   {16{4'b0011}});
    hold_pc("E 0xCCCC...",   {16{4'b1100}});
    hold_pc("E 0x0F0F...",   {8{8'h0F}});
    hold_pc("E 0xF0F0...",   {8{8'hF0}});
    hold_pc("E reset value", `RESET_VEC);
    for (int b = 0; b < 64; b++)
      if (reg_k[pc_r][b] > 0) begin
        hold_pc($sformatf("E walking 1, PC[%0d]", b),  pc_t'(1) << b);
        hold_pc($sformatf("E walking 0, PC[%0d]", b), ~(pc_t'(1) << b));
      end
    for (int i = 0; i < 16; i++) begin
      v = {$urandom, $urandom};
      hold_pc($sformatf("E random %0d", i), v);
    end
    // An external-memory PC alone does not establish a persistent global
    // stall after scan reload. Keep these as explicitly requested experiments.
    if (sweep_enabled) begin
      $display("[%0t] DIAGNOSTIC E: long retention assumes a persistent stall; EXT_MEM addressing does not guarantee it. Mismatches fail this run.", $time);
      hold_pc("E functional hold, all 1",     `FETCH_BASE | ('1          & `FETCH_MASK), FUNC_CYC);
      hold_pc("E functional hold, 0x5555...", `FETCH_BASE | ({32{2'b01}} & `FETCH_MASK), FUNC_CYC);
      hold_pc("E functional hold, 0xAAAA...", `FETCH_BASE | ({32{2'b10}} & `FETCH_MASK), FUNC_CYC);
      v = {$urandom, $urandom};
      hold_pc("E functional hold, random",    `FETCH_BASE | (v           & `FETCH_MASK), FUNC_CYC);
    end
    $display("[%0t] E: %0d values, %0d failed", $time, n_pat, n_pat_bad);
    $display("[%0t] TRACE task END: phase_e", $time);
  endtask

  // ---- P: every other register held ---------------------------------------------------------
  task automatic phase_p();
    string name [4] = '{"all 1", "0x5555...", "0xAAAA...", "random"};
    val_t  pat  [4];
    st_t   s;
    $display("[%0t] P: each register's values through scan load, hold, scan unload", $time);
    n_pat = 0; n_pat_bad = 0;
    for (int r = 0; r < n_regs; r++) begin
      if (reg_cells[r] == 0) continue;
      pat = '{'1, {MAX_W/2{2'b01}}, {MAX_W/2{2'b10}}, rand_val()};
      case (reg_kind[r])
        K_DATA, K_STICKY, K_MSECFAULT:
          for (int i = 0; i < 4; i++) begin
            s = reg_put(base, r, pat[i]);
            hold($sformatf("P %s %s", reg_name[r], name[i]), s, s);
          end
        K_ECC: begin
          // Missing cells do not establish constant or merged-bit constraints.
          // Do not claim arbitrary codewords are representable without them.
          if (reg_cells[r] != ECC_CW) begin
            if (case_selected({"P ", reg_name[r]}))
              skip_check({"P ", reg_name[r]}, "incomplete ECC mapping; codeword representability unproven");
            continue;
          end
          for (int i = 0; i < 4; i++) begin
            s = reg_put(base, r, val_t'(ecc_enc(pat[i][ECC_DW-1:0])));
            hold($sformatf("P %s codeword of %s", reg_name[r], name[i]), s, s);
          end
        end
        K_MPP:
          for (int v = 1; v <= 3; v += 2) begin
            s = reg_put(base, r, val_t'(v));
            hold($sformatf("P %s = %0d", reg_name[r], v), s, s);
          end
        default: ;                  // PC: E.  CTRL, TMR: below and in H.
      endcase
    end
    if (tmr_r[0] >= 0 && tmr_r[1] >= 0 && tmr_r[2] >= 0 && tmr_r[3] >= 0 && tmr_r[4] >= 0 && tmr_r[5] >= 0) begin
      s = base;
      for (int c = 0; c < 6; c++) s = reg_put(s, tmr_r[c], '0);
      hold("P privmode: all six copies U (00)", s, s);
    end
    else if (case_selected("P privmode: all six copies U (00)"))
      skip_check("P privmode", "not all six privmode copies are on the chains");
    $display("[%0t] P: %0d values, %0d failed", $time, n_pat, n_pat_bad);
    $display("[%0t] TRACE task END: phase_p", $time);
  endtask

  // ---- H: the hardening, through a capture edge --------------------------------------------------
  task automatic phase_h();
    st_t   ld, ex;
    string tmr_name [6] = '{"mode copy a", "mode copy b", "mode copy c", "check copy a", "check copy b", "check copy c"};
    bit    tmr_ok = 1;
    if (msf_r < 0) begin
      skip_check("H", "MSECFAULT is on no chain");
      return;
    end
    $display("[%0t] H: ECC repair, privilege fault flags and MPP check through a capture edge", $time);
    n_pat = 0; n_pat_bad = 0;

    // ECC 1-bit error: repaired on the capture edge, MSECFAULT[4] set. Incomplete
    // mappings are skipped until their bit constraints are known. Not in the
    // overall parity bit: ecc_secded_dec flags an error only on a non-zero
    // syndrome, so that one is neither flagged nor repaired.
    foreach (ecc_r[i]) begin
      int r = ecc_r[i];
      bit complete = reg_cells[r] == ECC_CW;
      logic [ECC_CW-1:0] cw = complete ? ecc_enc({$urandom, $urandom}) : '0;
      int flips [$];
      if (!complete) begin
        if (case_selected({"H ECC 1-bit error: ", reg_name[r]}))
          skip_check({"H ECC 1-bit error: ", reg_name[r]}, "incomplete ECC mapping; codeword representability unproven");
        continue;
      end
      if (complete) flips.push_back(ECC_R + 1 + $urandom_range(ECC_DW - 1));
      flips.push_back($urandom_range(ECC_R - 1));    // a Hamming bit
      foreach (flips[f]) begin
        int b = flips[f];
        if (reg_k[r][b] == 0) continue;
        ld = reg_put(base, r, val_t'(cw ^ (ECC_CW'(1) << b)));
        ex = with_flag(reg_put(base, r, val_t'(cw)), MSF_ECC_SEC);
        if (i == 0 && f == 0) begin                  // MSECFAULT ORs: an earlier flag stays
          ld = with_flag(ld, MSF_TMR_SEC);
          ex = with_flag(ex, MSF_TMR_SEC);
        end
        hold($sformatf("H ECC 1-bit error: %s bit %0d", reg_name[r], b), ld, ex);
      end
    end

    // privmode TMR.  The copies hold while the pipeline is stalled; the vote
    // only raises the flags.
    for (int c = 0; c < 6; c++) tmr_ok &= tmr_r[c] >= 0;
    if (!tmr_ok) skip_check("H privmode", "not all six privmode copies are on the chains");
    else begin
      for (int c = 0; c < 6; c++) begin                // one copy bad: flag; stored copy holds
        ld = reg_put(base, tmr_r[c], '0);
        hold($sformatf("H privmode %s 00", tmr_name[c]), ld, with_flag(ld, MSF_TMR_SEC));
      end
      ld = reg_put(reg_put(base, tmr_r[0], '0), tmr_r[1], '0);   // two bad: no majority
      hold("H privmode mode copies a and b 00", ld, with_flag(ld, MSF_TMR_UNC));
      ld = reg_put(reg_put(base, tmr_r[0], val_t'(2)), tmr_r[3], val_t'(2));
      hold("H privmode copy a reserved 10", ld, with_flag(ld, MSF_TMR_SEC));
    end

    if (mpp_r < 0) skip_check("H mstatus.MPP", "MPP is on no chain");
    else begin
      ld = reg_put(base, mpp_r, val_t'(2));
      hold("H mstatus.MPP reserved 10", ld, with_flag(ld, MSF_MPP));
    end

    // ECC 2-bit error: held, MSECFAULT[5].  It also latches the non-scan DED
    // trap record, which the next load's reset clears.
    foreach (ecc_r[i]) begin
      int r = ecc_r[i], b0 = -1, b1 = -1;
      if (reg_cells[r] != ECC_CW) begin
        if (case_selected({"H ECC 2-bit error: ", reg_name[r]}))
          skip_check({"H ECC 2-bit error: ", reg_name[r]}, "incomplete ECC mapping; baseline codeword unproven");
        continue;
      end
      for (int b = 0; b <= ECC_R; b++)
        if (reg_k[r][b] > 0) begin
          if (b0 < 0) b0 = b;
          else if (b1 < 0) b1 = b;
        end
      if (b1 < 0) continue;
      ld = reg_put(base, r, (val_t'(1) << b0) | (val_t'(1) << b1));
      hold($sformatf("H ECC 2-bit error: %s bits %0d %0d", reg_name[r], b0, b1), ld, with_flag(ld, MSF_ECC_DED));
    end
    $display("[%0t] H: %0d checks, %0d failed", $time, n_pat, n_pat_bad);
    $display("[%0t] TRACE task END: phase_h", $time);
  endtask

  // ---- F: reset over loaded cells --------------------------------------------------------
  task automatic reset_all(input string tag, input st_t load);
    st_t   got;
    if (!case_selected(tag)) return;
    cases_selected++;
    for (int rep = 0; rep < case_repeats; rep++) begin
      $display("[%0t] CASE: %s repeat=%0d/%0d seed=%0d operation=%s", $time,
               tag, rep+1, case_repeats, scan_seed, scan_op);
      $display("[%0t] TRACE reset_all START: %s", $time, tag);
      // Unlike E/P/H, F intentionally resets AFTER loading. Verify that load
      // independently in diagnostic mode, then reload before the reset test.
      if (scan_op == "load" || scan_op == "both") begin
        bit loaded;
        load_only(tag, load, loaded);
        if (!loaded) begin
          skip_check(tag, "load-only failed; reset recovery not run");
          return;
        end
        if (scan_op == "load") continue;
      end
      load_in_reset(load);
      reset_stalled();
      unload(got);
      check(tag, got, rst_exp);
      $display("[%0t] TRACE reset_all END: %s", $time, tag);
    end
  endtask

  task automatic phase_f();
    st_t s;
    $display("[%0t] F: reset over loaded cells", $time);
    n_pat = 0; n_pat_bad = 0;
    s = '{default: '{default: 1'b1}};
    reset_all("F from all 1", s);
    foreach (s[k, j]) s[k][j] = ~base[k][j];
    reset_all("F from ~base", s);
    for (int i = 0; i < 4; i++) begin
      foreach (s[k, j]) s[k][j] = $urandom_range(1);
      reset_all($sformatf("F from random %0d", i), s);
    end
    $display("[%0t] F: %0d resets, %0d failed", $time, n_pat, n_pat_bad);
    $display("[%0t] TRACE task END: phase_f", $time);
  endtask

`include "scan_random.svh"
`include "scan_exec.svh"

  // ---- summary -----------------------------------------------------------------------------
  task automatic summary();
    int    g_regs [4], g_cells [4], g_bad [4];
    string g_list [4];
    for (int r = 0; r < n_regs; r++) begin
      if (reg_cells[r] == 0) continue;
      g_regs[reg_group[r]]++;
      g_cells[reg_group[r]] += reg_cells[r];
      if (reg_fail[r] > 0) begin
        g_bad[reg_group[r]]++;
        g_list[reg_group[r]] = {g_list[reg_group[r]], " ", reg_name[r]};
      end
    end
    for (int g = 0; g < 4; g++)
      if (g_regs[g] > 0)
        $display("GROUP: %s: %0d register(s), %0d cells: %s", group_str(group_e'(g)), g_regs[g], g_cells[g],
                 g_bad[g] == 0 ? "all passed" : $sformatf("%0d failed:%s", g_bad[g], g_list[g]));
    for (int r = 0; r < n_regs; r++)
      if (reg_fail[r] > 0)
        $display("REG: %s failed %0d check(s); wrong bit(s):%s", reg_name[r], reg_fail[r], bit_list(reg_bad[r], 32));
    if (pc_r >= 0) begin
      if (reg_fail[pc_r] == 0) $display("PC: all %0d bits on the chains passed", reg_cells[pc_r]);
      else                     $display("PC: bits that failed:%s", bit_list(reg_bad[pc_r], 64));
    end
    $display("[%0t] TRACE task END: summary", $time);
  endtask

  // ---- run ---------------------------------------------------------------------------------
  initial begin
    int timing_ps, seed_state;
    void'($value$plusargs("SCAN_PHASES=%s", phase_order));
    void'($value$plusargs("SCAN_CASE=%s", case_filter));
    void'($value$plusargs("SCAN_OP=%s", scan_op));
    void'($value$plusargs("SCAN_REPEAT=%d", case_repeats));
    void'($value$plusargs("SCAN_SEED=%d", scan_seed));
    void'($value$plusargs("SCAN_RANDOM_ITERS=%d", random_iters));
    void'($value$plusargs("SCAN_EXEC_ITERS=%d", exec_iters));
    if (random_iters < 1 || exec_iters < 1) $fatal(1, "iteration counts must be positive");
    if ($value$plusargs("FPGA_TCO_PS=%d", timing_ps)) launch_ns = timing_ps / 1000.0;
    if (!(launch_ns > 0 && launch_ns < 50)) $fatal(1, "FPGA_TCO_PS must be between 0 and 50000 exclusive");
    if (case_repeats < 1) $fatal(1, "SCAN_REPEAT must be positive");
    if (scan_op != "capture" && scan_op != "load" && scan_op != "both")
      $fatal(1, "SCAN_OP must be capture, load, or both");
    if (`RST_LAT < 1 || `RST_LAT > MAX_LEN) $fatal(1, "invalid RST_LAT");
    for (int i = 0; i < phase_order.len(); i++)
      if (!(phase_order.substr(i,i) inside {"A","M","B","C","D","E","P","H","F","R","I"}))
        $fatal(1, "SCAN_PHASES contains an unknown phase: %s", phase_order.substr(i,i));
    sentinel_enabled = $test$plusargs("SCAN_SENTINEL");
    sweep_enabled = $test$plusargs("SCAN_SWEEP");
    if ($test$plusargs("SCAN_UNLOAD_RESET") && $test$plusargs("SCAN_UNLOAD_NO_RESET"))
      $fatal(1, "choose only one of SCAN_UNLOAD_RESET and SCAN_UNLOAD_NO_RESET");
    unload_reset_enabled = !$test$plusargs("SCAN_UNLOAD_NO_RESET");
    seed_state = int'(scan_seed);
    seed_state = $urandom(seed_state);
    $display("[%0t] CONFIG: phases=%s case='%s' operation=%s repeat=%0d seed=%0d TCO=%0.3f ns sentinel=%b sweep=%b unload_reset=%b random_iters=%0d exec_iters=%0d",
             $time, phase_order, case_filter, scan_op, case_repeats, scan_seed, launch_ns, sentinel_enabled, sweep_enabled, unload_reset_enabled, random_iters, exec_iters);
    rst_n = 1'bx; irq = '0; uart_rx = 1'b1;
    fault_inject = 1'b0; test_mode = 1'b0; si = '0;
    set_se(1'b0);
    #0.5; rst_n = 1'b0;
    idle(20); rst_n = 1'b1; idle(5);

    phase_begin(0); phase_a(); phase_end(0);
    if (maxlen == 0) fail("no chain shifts at all; skipping M-F");
    else begin
      phase_begin(1); phase_m(); phase_end(1);
      if (maxlen < `RST_LAT) begin
        fail("discovered chains are too short for RST_LAT");
        map_ok = 0;
      end
      if (map_ok && phase_errors[1] == 0) begin
        phase_begin(2); phase_b(); phase_end(2);
      end
      for (int i = 0; i < phase_order.len(); i++) begin
        string p;
        p = phase_order.substr(i,i);
        if (p inside {"A", "M", "B"}) continue; // prerequisites already ran
        if (p != "C" && !baseline_ok) begin
          skip_check(p, "blocked by invalid map/reset baseline");
          continue;
        end
        case (p)
          "C": begin phase_begin(3); phase_c(); phase_end(3); end
          "D": begin phase_begin(4); phase_d(); phase_end(4); end
          "E": begin phase_begin(5); phase_e(); phase_end(5); end
          "P": begin phase_begin(6); phase_p(); phase_end(6); end
          "H": begin
`ifndef NO_HARDEN
            phase_begin(7); phase_h(); phase_end(7);
`else
            skip_check("H", "NO_HARDEN build");
`endif
          end
          "F": begin phase_begin(8); phase_f(); phase_end(8); end
          "R": begin phase_begin(9); phase_r(); phase_end(9); end
          "I": begin phase_begin(10); phase_i(); phase_end(10); end
        endcase
      end
      if (map_ok) summary();
    end
    if (case_filter != "" && cases_selected == 0)
      fail($sformatf("no executable cases matched SCAN_CASE='%s'; inspect any skip reasons", case_filter));
    phase_summary();

    if (errors == 0 && checks_skipped == 0) $display("DFT TB PASS");
    else if (errors == 0) $display("DFT TB PASS (partial coverage: %0d explicit skips)", checks_skipped);
    else             $display("DFT TB FAIL (%0d errors)", errors);
    if (errors != 0) $fatal(1, "DFT checks failed");
    $finish;
  end

  initial begin
    longint timeout_ns;
    timeout_ns = 100_000_000; // original 100 ms watchdog
    void'($value$plusargs("SCAN_TIMEOUT_NS=%d", timeout_ns));
    if (timeout_ns <= 0) $fatal(1, "SCAN_TIMEOUT_NS must be positive");
    #(timeout_ns);
    $display("DFT TB FAIL (timeout)");
    $fatal(1, "DFT timeout");
  end

endmodule
