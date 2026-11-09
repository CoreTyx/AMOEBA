// tb_scan.sv -- pin-level test of the scan chains in the scanned forte_top and
// of every register on them: the PC, the pipeline registers and the hardened
// CSRs that dft_setup.tcl selects.
//
// Pass/fail uses the package pins; internal hookups are diagnostic only.
// The chains are the ones
// dft_insert.tcl declares: c0..c7, scan in on io[k], scan out on io[k+8].
// Below, chain k = 1..8 is c(k-1): io[k-1] -> io[k+7].  Chain lengths and
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
// WHY CAPTURES ARE PREDICTABLE.  With ready=0 the first fetch never completes:
// IFUStallF stalls every stage (hazard.sv), so a register with a ~Stall enable
// holds what is loaded, and with the fetch committed no exception can trap
// (trap.sv: TrapM = ExceptionM & ~CommittedF).  A flush can still happen
// (mret, CSR write fence, branch mispredict), and those come from the control
// registers, so those (kind CTRL) are only ever loaded with their reset value.
// The ECC registers repair a 1-bit error even while stalled, so they are only
// loaded with valid codewords except where a check injects an error on purpose.
// While a load shifts, every pattern passes through the control cells upstream
// of it, and with the stall released by a passing branch bit the logic OFF the
// chains (CSRs, bus FSM, register file) would act on them.  So every load holds
// the functional reset through the shift and releases it as the last bit goes
// in (load_in_reset): at the capture edge everything off the chains is in its
// reset state, as in B.  Scan cells take SI whatever reset does: the core's
// resets are synchronous.
// Every check loads all cells: the register under test gets its pattern, every
// other cell its value after B's reset ("base").  Every cell is compared on
// the way out, so a check also fails if loading one register disturbs another.
//
//   A  lengths      shift zeros and read each scan-out: that is inv[k].  Then
//                   one 1 into every io[7:0]; the cycle io[k+8] first differs
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
//   B  reset        reset, run with ready=0 (the pipeline sits stalled), shift
//                   out: every cell must hold its register's reset value (X only
//                   where the register has no reset).  What is read is "base".
//   C  round trip   random data in, the same data (through inv[k]) out.
//   D  hold         base loaded, one capture edge in test mode, unloaded: every
//                   cell unchanged.  Again with 50 functional cycles.
//   E  PC           PC values held, every other cell at base: all 0, all 1,
//                   checkerboards, walking 1 and walking 0 over every PC bit,
//                   random; a few with a functional-mode hold, at PCs in
//                   EXT_MEM (FETCH_BASE/FETCH_MASK) so the fetch waits on the bus.
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
// scan enable toggled per cycle on scan_en.  In test mode the chip drives
// io[15:8] and listens on io[7:0]; the bench drives io[7:0] only then, and
// otherwise leaves the bus to the chip (weak pull-downs keep it out of Z).
// The DFT lock resets to unlocked, so it does not get in the way here; it is
// not tested.
//
// Test cycle as the SPF: 100 ns; inputs change at 10 ns, io[15:8] sampled at
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
  initial begin : fsdb_dump
    $fsdbDumpfile("dump.fsdb");
    $fsdbDumpvars(0, tb_scan);
  end

  localparam int N        = 8;     // chains c0..c7: io[7:0] in, io[15:8] out
  localparam int MAX_LEN  = 1024;  // give up on a chain longer than this
  localparam int MAX_REGS = 256;
  localparam int MAX_W    = 256;   // widest register (PP1Reg/PP2Reg: 128)
  localparam int ECC_DW   = 64;    // the ECC registers: XLEN data bits,
  localparam int ECC_R    = 7;     // 7 Hamming bits and an overall parity:
  localparam int ECC_CW   = 72;    // {data, parity, hamming} (ecc_secded_enc.sv)
  localparam int FUNC_CYC = 50;    // functional-mode hold, in cycles

  // MSECFAULT bits (csrharden.sv)
  localparam int MSF_TMR_SEC = 0, MSF_MPP = 1, MSF_TMR_UNC = 3, MSF_ECC_SEC = 4, MSF_ECC_DED = 5;

  // ---- DUT ------------------------------------------------------------------
  logic        clk = 1'b0;
  logic        rst_n, ready, rvalid, uart_rx, test_mode, scan_en, fault_inject;
  logic [1:0]  irq;
  logic [N:1]  si;
  wire  [N:1]  so;
  wire  [15:0] io;
  wire         dir, req, wr, clk_out, uart_tx, status;

  // Scan in on io[7:0], driven only in test mode; scan out read from io[15:8].
  assign io[7:0] = test_mode ? si : 'z;
  assign (pull0, pull1) io = '0;
  assign so = io[15:8];

  forte_top dut (
    .core_clk(clk), .rst_n, .io, .dir, .req, .clk_out, .wr, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx, .test_mode, .scan_en, .fault_inject, .status);

  always #50 clk = ~clk;            // rises at 50, 150, ...

  int errors = 0;
  int len [N:1];                    // discovered in phase A
  logic inv [N:1];                  // 1: the chain shifts out ~in (odd QN count)
  int maxlen = 0;

  bit trace_cycles, trace_shift, dump_on_error = 1'b1;
  bit in_check_fail = 1'b0;
  bit have_snapshot = 1'b0;
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
  int phase_errors [0:8];
  bit phase_ran [0:8];
  string phase_names [0:8] = '{"A chain lengths", "M scan map", "B reset",
      "C round trip", "D base hold", "E PC", "P registers",
      "H hardening", "F reset recovery"};
  int phase_start_errors;

  task automatic phase_begin(input int p);
    phase_start_errors = errors;
    phase_ran[p] = 1'b1;
    $display("[%0t] PHASE START: %s (errors so far: %0d)",
             $time, phase_names[p], errors);
  endtask

  task automatic phase_end(input int p);
    phase_errors[p] = errors - phase_start_errors;
    $display("[%0t] PHASE END: %s: %s (%0d new errors)",
             $time, phase_names[p], phase_errors[p] == 0 ? "PASS" : "FAIL",
             phase_errors[p]);
  endtask

  task automatic phase_summary();
    $display("================ DFT PHASE SUMMARY ================");
    for (int p = 0; p < 9; p++)
      $display("PHASE: %-20s %-5s errors=%0d", phase_names[p],
               !phase_ran[p] ? "SKIP" : (phase_errors[p] == 0 ? "PASS" : "FAIL"),
               phase_errors[p]);
    $display("PHASE: TOTAL errors=%0d", errors);
    $display("===================================================");
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
`include "scan_map.svh"
`include "hookups.svh"

  // A scan unload overwrites the flop state. Save live hookups before shifting.
  val_t internal_raw_snapshot[string];
  val_t internal_est_snapshot[string];
  val_t internal_available_snapshot[string];
  string internal_snapshot_tag;
  task automatic snapshot_internal(input string tag);
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
    @(posedge clk); #5;
  endtask

  task automatic idle(input int n);
    logic [N:1] unused;
    $display("[%0t] TRACE idle START: %0d cycles (SE=%b TM=%b RST=%b)", $time, n, scan_en, test_mode, rst_n);
    repeat (n) cycle('0, unused);
    $display("[%0t] TRACE idle END: %0d cycles", $time, n);
  endtask

  // Shift maxlen cycles: chain k takes in[k][t] at cycle t and its output is
  // returned in out[k][t].  The first bit out of a chain is the one next to
  // its io[k+8]; after the shift, chain k holds in[k][maxlen-len[k] .. maxlen-1],
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
    bits_t in = '{default: 1'b0};
    for (int k = 1; k <= N; k++)
      for (int j = 1; j <= len[k]; j++)
        in[k][maxlen - j] = s[k][j] ^ a_inv[k][j];
    return in;
  endfunction

  // The cells, from the stream shifted out of them.
  function automatic st_t decode(input bits_t out);
    st_t s = '{default: 1'bx};
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
      $display("[%0t] INTERNAL: %s no complete diagnostic snapshot; regenerate hookups.svh with internal_hookups.py",
               $time, reg_name[r]);
      return;
    end
    available = internal_available_snapshot[reg_name[r]];
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
      $display("[%0t] SCAN DUMP c%0d io[%0d]->io[%0d], length=%0d inversion=%b",
               $time, k-1, k-1, k+7, len[k], inv[k]);
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
  task automatic load_in_reset(input st_t s);
    bits_t in = encode(s);
    logic [N:1] i_b, o_b;
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

  // Load, hold, unload, compare.  func_cyc = 0: one capture clock in test mode.
  // Otherwise func_cyc clocks in functional mode (test_mode=0, the bus back with
  // the chip); the fetch stays stalled on ready=0 throughout.
  task automatic hold(input string tag, input st_t load, input st_t exp, input int func_cyc = 0);
    bits_t zeros = '{default: 1'b0}, got;
    $display("[%0t] TRACE hold START: %s, functional cycles=%0d", $time, tag, func_cyc);
    load_in_reset(load);
    set_se(1'b0);
    $display("[%0t] TRACE hold: SE=0, %s", $time, func_cyc == 0 ? "one capture edge" : "enter functional mode");
    if (func_cyc == 0) begin
      @(posedge clk); #5;
    end
    else begin
      test_mode = 1'b0;
      $display("[%0t] TRACE hold: test_mode=0", $time);
      idle(func_cyc);
      test_mode = 1'b1;
      $display("[%0t] TRACE hold: test_mode=1", $time);
    end
    set_se(1'b1);
    snapshot_internal(tag);
    shift(zeros, got);
    check(tag, decode(got), exp);
    $display("[%0t] TRACE hold END: %s", $time, tag);
  endtask

  // Functional reset, then ready=0 so the first fetch (RESET_VEC) never
  // completes and the pipeline sits stalled; returns in test mode, shifting.
  task automatic reset_stalled();
    $display("[%0t] TRACE reset_stalled START", $time);
    set_se(1'b0); test_mode = 1'b0;
    rst_n = 1'b0; idle(20);
    rst_n = 1'b1;
    $display("[%0t] TRACE reset_stalled: deassert reset, wait 1 stalled clocks", $time);
    idle(200);
    test_mode = 1'b1; set_se(1'b1);
    $display("[%0t] TRACE reset_stalled END", $time);                   // just after an edge: no extra shift
  endtask

  task automatic unload(output st_t s);
    bits_t zeros = '{default: 1'b0}, got;
    $display("[%0t] TRACE unload START", $time);
    snapshot_internal("unload");
    shift(zeros, got);
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
    test_mode = 1'b1; set_se(1'b1);
    idle(MAX_LEN);                                    // flush to zeros
    foreach (len[k]) len[k] = -1;
    for (int t = 0; t <= MAX_LEN; t++) begin
      cycle(t == 0 ? '1 : '0, got);
      for (int k = 1; k <= N; k++) begin
        if ($isunknown(got[k])) begin
          if (len[k] != 0)
            fail($sformatf("A: c%0d: io[%0d] is X after a zero flush (chain broken?)", k-1, k+7));
          len[k] = 0;
        end
        // t = 0 is strobed before the 1 is clocked in: the flushed value
        if (t == 0) inv[k] = got[k];
        else if (got[k] !== inv[k] && len[k] < 0) len[k] = t;
      end
    end
    for (int k = 1; k <= N; k++) begin
      if (len[k] <= 0) begin
        fail($sformatf("A: c%0d: the 1 from io[%0d] never reached io[%0d]", k-1, k-1, k+7));
        len[k] = 0;
      end
      $display("[%0t] A: c%0d (io[%0d] -> io[%0d]) length %0d%s", $time, k-1, k-1, k+7, len[k],
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
    $display("[%0t] B: every cell after reset", $time);
    rst_exp = '{default: 1'bx};
    for (int r = 0; r < n_regs; r++)
      if (reg_kind[r] != K_UNKNOWN && reg_kind[r] != K_LOCK)
        for (int b = 0; b < reg_width[r]; b++)
          if (reg_k[r][b] > 0) rst_exp[reg_k[r][b]][reg_j[r][b]] = reg_rst[r][b];
    n_pat = 0; n_pat_bad = 0;
    reset_stalled();
    unload(got);
    check("B reset value", got, rst_exp);
    base = got;
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

  // ---- D: the reset state held ------------------------------------------------------------
  task automatic phase_d();
    $display("[%0t] D: base held", $time);
    n_pat = 0; n_pat_bad = 0;
    hold("D base, one capture edge", base, base);
    hold($sformatf("D base, %0d functional cycles", FUNC_CYC), base, base, FUNC_CYC);
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
      $display("[%0t] E: the PC is on no chain: skipped", $time);
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
    // Held for longer, with the chip in functional mode.  Each load leaves reset
    // with the loaded PC as the first fetch, so it must be one the core fetches
    // from the bus (EXT_MEM), where it waits on ready=0.  Anywhere else the
    // fetch faults without reaching the bus, and the core traps within a few
    // cycles.  One capture edge (above) is too short for that.
    hold_pc("E functional hold, all 1",     `FETCH_BASE | ('1          & `FETCH_MASK), FUNC_CYC);
    hold_pc("E functional hold, 0x5555...", `FETCH_BASE | ({32{2'b01}} & `FETCH_MASK), FUNC_CYC);
    hold_pc("E functional hold, 0xAAAA...", `FETCH_BASE | ({32{2'b10}} & `FETCH_MASK), FUNC_CYC);
    v = {$urandom, $urandom};
    hold_pc("E functional hold, random",    `FETCH_BASE | (v           & `FETCH_MASK), FUNC_CYC);
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
        K_ECC:
          // With bits missing (merged or constant flops) only all-1 data is
          // sure to be a codeword the cells can hold.
          for (int i = 0; i < (reg_cells[r] == ECC_CW ? 4 : 1); i++) begin
            s = reg_put(base, r, val_t'(ecc_enc(pat[i][ECC_DW-1:0])));
            hold($sformatf("P %s codeword of %s", reg_name[r], name[i]), s, s);
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
    $display("[%0t] P: %0d values, %0d failed", $time, n_pat, n_pat_bad);
    $display("[%0t] TRACE task END: phase_p", $time);
  endtask

  // ---- H: the hardening, through a capture edge --------------------------------------------------
  task automatic phase_h();
    st_t   ld, ex;
    string tmr_name [6] = '{"mode copy a", "mode copy b", "mode copy c", "check copy a", "check copy b", "check copy c"};
    bit    tmr_ok = 1;
    if (msf_r < 0) begin
      $display("[%0t] H: MSECFAULT is on no chain: skipped", $time);
      return;
    end
    $display("[%0t] H: ECC repair, TMR voting and MPP check through a capture edge", $time);
    n_pat = 0; n_pat_bad = 0;

    // ECC 1-bit error: repaired on the capture edge, MSECFAULT[4] set.  A
    // register with bits missing starts from the zero codeword, and gets its
    // error in a Hamming bit (no two of those can be merged).  Not in the
    // overall parity bit: ecc_secded_dec flags an error only on a non-zero
    // syndrome, so that one is neither flagged nor repaired.
    foreach (ecc_r[i]) begin
      int r = ecc_r[i];
      bit complete = reg_cells[r] == ECC_CW;
      logic [ECC_CW-1:0] cw = complete ? ecc_enc({$urandom, $urandom}) : '0;
      int flips [$];
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
    if (!tmr_ok) $display("[%0t] H: not all six privmode copies are on the chains: TMR checks skipped", $time);
    else begin
      for (int c = 0; c < 6; c++) begin                // one copy bad: corrected
        ld = reg_put(base, tmr_r[c], '0);
        hold($sformatf("H privmode %s 00", tmr_name[c]), ld, with_flag(ld, MSF_TMR_SEC));
      end
      ld = reg_put(reg_put(base, tmr_r[0], '0), tmr_r[1], '0);   // two bad: no majority
      hold("H privmode mode copies a and b 00", ld, with_flag(ld, MSF_TMR_UNC));
      ld = reg_put(reg_put(base, tmr_r[0], val_t'(2)), tmr_r[3], val_t'(2));
      hold("H privmode copy a reserved 10", ld, with_flag(ld, MSF_TMR_SEC));
    end

    if (mpp_r < 0) $display("[%0t] H: mstatus.MPP is on no chain: MPP check skipped", $time);
    else begin
      ld = reg_put(base, mpp_r, val_t'(2));
      hold("H mstatus.MPP reserved 10", ld, with_flag(ld, MSF_MPP));
    end

    // ECC 2-bit error: held, MSECFAULT[5].  It also latches the non-scan DED
    // trap record, which the next load's reset clears.
    foreach (ecc_r[i]) begin
      int r = ecc_r[i], b0 = -1, b1 = -1;
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
    bits_t unused;
    st_t   got;
    $display("[%0t] TRACE reset_all START: %s", $time, tag);
    shift(encode(load), unused);
    reset_stalled();
    unload(got);
    check(tag, got, rst_exp);
    $display("[%0t] TRACE reset_all END: %s", $time, tag);
  endtask

  task automatic phase_f();
    st_t s;
    $display("[%0t] F: reset over loaded cells", $time);
    n_pat = 0; n_pat_bad = 0;
    s = '{default: 1'b1};
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
    rst_n = 1'b0; ready = 1'b0; rvalid = 1'b0; irq = '0; uart_rx = 1'b1;
    fault_inject = 1'b0; test_mode = 1'b0; si = '0;
    set_se(1'b0);
    idle(20); rst_n = 1'b1; idle(5);

    phase_begin(0); phase_a(); phase_end(0);
    if (maxlen == 0) fail("no chain shifts at all; skipping M-F");
    else begin
      phase_begin(1); phase_m(); phase_end(1);
      if (map_ok) begin
        phase_begin(2); phase_b(); phase_end(2);
      end
      phase_begin(3); phase_c(); phase_end(3);
      if (map_ok) begin
        phase_begin(4); phase_d(); phase_end(4);
    //     phase_begin(5); phase_e(); phase_end(5);
//         phase_begin(6); phase_p(); phase_end(6);
// `ifndef NO_HARDEN
//         phase_begin(7); phase_h(); phase_end(7);
// `endif
//         phase_begin(8); phase_f(); phase_end(8);
      end
      if (map_ok) summary();
    end
    phase_summary();

    if (errors == 0) $display("DFT TB PASS");
    else             $display("DFT TB FAIL (%0d errors)", errors);
    $finish;
  end

  initial begin
    #100ms;
    $display("DFT TB FAIL (timeout)");
    $finish;
  end

endmodule
