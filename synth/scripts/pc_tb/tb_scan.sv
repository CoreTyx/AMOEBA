// tb_scan.sv -- pin-level check of the scan chains in the scanned forte_top,
// and of the PC flops on them.  The chains also carry the pipeline registers
// and hardened CSRs (dft_setup.tcl); those shift through A and C, and the PC
// phases keep them in a consistent state (see NON-PC CELLS), but their own
// values are not checked.
//
// Drives and observes ONLY the package pins.  The chains are the ones
// dft_insert.tcl declares: c0..c7, scan in on io_in[k], scan out on io_out[k].
// Below, chain k = 1..8 is c(k-1): io_in[k-1] -> io_out[k-1].  Chain lengths and
// inversions are discovered from the pins.  Which PC bit each cell holds comes
// from the scandef: run.sh turns it into scan_map.svh (+define+SCAN_MAP).
// Without it the PC phases that need it (exact B, E, F) are skipped.
//
// INVERTING CHAINS.  insert_dft may take a cell's scan output from QN (the
// scandef says "( OUT QN )"); each such cell inverts what passes through it.
// A chain with an odd number of them is inverting: it shifts out ~in, and after
// a zero flush its scan-out sits at 1.  inv[k] is that parity, read from the
// pin.  With the map, the inversion between scan-in and each cell (a_inv) and
// between each cell and scan-out (b_inv) is known too, so a PC value can be
// loaded into the flops and read out of them exactly.
//
// LOGICAL PHASE.  Separately from the scan path, a flop could store its RTL bit
// inverted.  dft_insert.tcl writes forte_top.scan_phase.txt (one line per scan
// cell, 1 = inverted); run.sh passes it to scan_map.awk as map_ph, and a_inv /
// b_inv then run to the RTL bit rather than to the flop.  dft_setup.tcl
// forbids inverted storage, so it is all 0 unless DC was told otherwise; B and
// F (exact reset values) would catch a wrong entry.
//
// NON-PC CELLS.  Random data in the pipeline registers and CSRs is not a state
// the core can hold: a bad ECC codeword repairs itself even while stalled, and
// MSECFAULT / MFTSTATUS have no enable, so a capture clock would rewrite them
// and could start a trap.  So whenever the PC phases load a value they load
// every non-PC cell with what it held after B's reset (an X there loads as 0),
// and only the PC cells are compared.
//
//   A  lengths      shift zeros and read each scan-out: that is inv[k].  Then
//                   one 1 into every io_in; the cycle io_out[k] first differs
//                   from inv[k] is that chain's length.  With
//                   +define+EXPECTED_CELLS=n the total must be n (M checks
//                   every chain against the scandef anyway).
//                   Then a 0011 flush through every chain.
//   M  map          scan_map.svh against the pins: every chain the length A
//                   found, inversions adding up to inv[k] (this also fixes the
//                   last cell's, which the scandef leaves out), every PC bit on
//                   exactly one cell.
//   B  PC readout   reset, run with ready=0 so the first fetch (RESET_VEC) never
//                   completes and the PC sits at the reset vector, then shift
//                   out.  With the map: decoded, must equal RESET_VEC exactly, and
//                   no PC bit X (other cells may be: not every pipeline register
//                   has a reset).  Without it: never X, and at most one 1 in the
//                   non-inverting chains (meaningful only while the chains hold
//                   nothing but the PC).
//   C  round trip   random data in, the same data (through inv[k]) out.
//   D  load + hold  shift random data in, one capture clock with scan enable
//                   off (the core is stalled, so the PC flops hold), shift out:
//                   must be what was loaded (through inv[k]).  Then the same
//                   with B's readout, which puts the PC back.  With the map the
//                   random data is a random PC (NON-PC CELLS) and only the PC is
//                   compared; without it every cell is, which only holds while
//                   the chains carry nothing but the PC.
//   E  PC hold      PC values loaded through the map, held, read back through
//                   it: all 0, all 1, checkerboards, walking 1 and walking 0 over
//                   every PC bit, random.  One capture clock in test mode, and a
//                   longer hold in functional mode (test_mode=0) for a few.
//   F  PC reset     PC values loaded, then a functional reset: every bit must
//                   come back as RESET_VEC.  pcreg has no reset pin; reset
//                   reaches it through PCNextF, so this checks that path for
//                   every bit.
// Ends with the PC bits that failed anywhere, then "DFT TB PASS" or "DFT TB FAIL".
//
// What the pins cannot check: the ORDER of the cells in a chain is taken from
// the scandef.  E reads back through the same map it loads through, so a
// swapped pair would still pass E; only bits whose reset value differs (B, F:
// PC[31] against its neighbours) would show it.  A wrong inversion does show,
// in B and F.  +define+BREAK_MAP corrupts one inversion as a self-test.
//
// Pins follow docs/top_level_plan.md s3: test_mode static for the session,
// scan enable toggled per cycle on scan_en.  The link is two one-way buses:
// the bench always drives io_in (scan-in in test mode, 0 otherwise) and reads
// scan-out from io_out.  No pad changes direction.
// The DFT lock resets to unlocked, so it does not get in the way here; it is
// not tested.
//
// TEST_MODE IS SYNCHRONISED in forte_chip (tmsync, two core_clk flops), so
// test_mode_dft -- which selects what io_out carries, and may gate the scan-out
// mux or clock-gate test pins insert_dft added -- follows the pin two edges
// late.  Every time test_mode rises the bench holds scan_en low and idles
// TM_SYNC cycles (enter_test) before it shifts.  The core is stalled on ready=0
// throughout, so those cycles change nothing.  scan_en is not synchronised.
//
// Test cycle as the SPF: 100 ns; inputs change at 10 ns, io_out sampled at
// 40 ns, core_clk rises at 50 ns.

`timescale 1ns/1ps

`ifndef RESET_VEC
  `define RESET_VEC 64'h8000_0000
`endif

module tb_scan;

  localparam int N       = 8;     // chains c0..c7: io_in[k] in, io_out[k] out
  localparam int MAX_LEN = 512;   // give up on a chain longer than this
  localparam int TM_SYNC = 3;     // cycles for test_mode through tmsync (2 flops) + 1

  // ---- DUT ------------------------------------------------------------------
  logic        clk = 1'b0;
  logic        rst_n, ready, rvalid, uart_rx, test_mode, scan_en, fault_inject;
  logic [1:0]  irq;
  logic [N:1]  si;
  wire  [N:1]  so;
  wire  [N-1:0] io_in, io_out;
  wire          req, wr, clk_out, uart_tx, status;

  // Scan in on io_in, scan out on io_out: chain k is bit k-1 of each.
  assign io_in = si;
  assign so    = io_out;

  forte_top dut (
    .core_clk(clk), .rst_n, .io_in, .io_out, .req, .clk_out, .wr, .ready, .rvalid,
    .irq, .uart_tx, .uart_rx, .test_mode, .scan_en, .fault_inject, .status);

  always #50 clk = ~clk;            // rises at 50, 150, ...

  int errors = 0;
  int len [N:1];                    // discovered in phase A
  logic inv [N:1];                  // 1: the chain shifts out ~in (odd QN count)
  int maxlen = 0;

  task automatic fail(input string msg);
    errors++;
    if (errors <= 50) $display("[%0t] ERROR: %s", $time, msg);
  endtask

  // ---- scan map (phase M) ---------------------------------------------------
  // Cell j of chain k, j = 1 next to scan-in.
  typedef logic [63:0] pc_t;
  int   map_len [N:1];
  int   map_bit [N:1][1:MAX_LEN];   // PC bit the cell holds; -1: not a PC flop
  int   map_qn  [N:1][1:MAX_LEN];   // 1: scan output from QN; 2: not in the scandef
  int   map_ph  [N:1][1:MAX_LEN];   // 1: the flop stores its RTL bit inverted (scan_phase.txt)
  logic a_inv   [N:1][1:MAX_LEN];   // inversion from scan-in to the cell's SI
  logic b_inv   [N:1][1:MAX_LEN];   // inversion from the cell's Q to scan-out
  logic cell_rst [N:1][1:MAX_LEN];  // each cell's value after B's reset; X read as 0
  bit   map_ok   = 0;
  pc_t  on_chain = '0;              // PC bits some cell holds
  pc_t  bad_bits = '0;              // PC bits that failed in B, E or F
`ifdef SCAN_MAP
  `include "scan_map.svh"
`endif

  // Scan enable: the scan_en pin.
  task automatic set_se(input logic v);
`ifdef BREAK_SE
    v = 1'b0;                       // self-test: the chains must then fail
`endif
    scan_en = v;
  endtask

  // One test cycle: drive scan-in, strobe scan-out, clock.  Returns just after
  // the edge, so a pin changed after it is stable for the whole next cycle.
  task automatic cycle(input logic [N:1] in_bits, output logic [N:1] out_bits);
    @(negedge clk); #10;
    si = in_bits;
    #30;
    out_bits = so;
    @(posedge clk); #5;
  endtask

  task automatic idle(input int n);
    logic [N:1] unused;
    repeat (n) cycle('0, unused);
  endtask

  // Raise test_mode and let it through tmsync before the first shift edge.
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
  typedef logic bits_t [N:1][MAX_LEN];
  task automatic shift(input bits_t in, output bits_t out);
    logic [N:1] i_b, o_b;
    for (int t = 0; t < maxlen; t++) begin
      for (int k = 1; k <= N; k++) i_b[k] = in[k][t];
      cycle(i_b, o_b);
      for (int k = 1; k <= N; k++) out[k][t] = o_b[k];
    end
  endtask

  function automatic string chain_str(input bits_t b, input int k);
    string s = "";
    for (int t = 0; t < len[k]; t++) s = {s, $sformatf("%b", b[k][t])};
    return s;
  endfunction

  // The shift-in stream that leaves PC value v in the PC flops and every other
  // cell as it was after B's reset (NON-PC CELLS).
  function automatic bits_t encode(input pc_t v);
    bits_t in = '{default: 1'b0};
    for (int k = 1; k <= N; k++)
      for (int j = 1; j <= len[k]; j++)
        in[k][maxlen - j] = (map_bit[k][j] >= 0 ? v[map_bit[k][j]] : cell_rst[k][j]) ^ a_inv[k][j];
    return in;
  endfunction

  // The PC value in the flops, from the stream shifted out of them.  Bits on no
  // chain (PC[0]) read 0.
  function automatic pc_t decode(input bits_t out);
    pc_t v = '0;
    for (int k = 1; k <= N; k++)
      for (int t = 0; t < len[k]; t++)
        if (map_bit[k][len[k] - t] >= 0)
          v[map_bit[k][len[k] - t]] = out[k][t] ^ b_inv[k][len[k] - t];
    return v;
  endfunction

  function automatic string bit_list(input pc_t m, input int max_n);
    string s = "";
    int n = 0;
    for (int b = 63; b >= 0; b--)
      if (m[b] === 1'b1) begin
        n++;
        if (n <= max_n) s = {s, $sformatf(" %0d", b)};
      end
    if (n > max_n) s = {s, " ..."};
    return s;
  endfunction

  // Compare a decoded PC against the expected value, on the bits the chains hold.
  task automatic check_pc(input string tag, input pc_t got, input pc_t exp);
    pc_t wrong = '0;
    for (int b = 0; b < 64; b++)
      if (on_chain[b] && got[b] !== exp[b]) wrong[b] = 1'b1;
    if (wrong != '0) begin
      bad_bits |= wrong;
      fail($sformatf("%s: PC read %h, expected %h; wrong bit(s):%s",
                     tag, got, exp & on_chain, bit_list(wrong, 12)));
    end
  endtask

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
  endtask

  // ---- M: the scandef's map against the pins -----------------------------------
  task automatic phase_m();
`ifndef SCAN_MAP
    $display("[%0t] M: no scan map (run.sh found no scandef): exact B, E and F skipped", $time);
`else
    int seen [64];
    string s;
    $display("[%0t] M: scan map", $time);
    foreach (map_len[k]) map_len[k] = 0;
    foreach (map_bit[k, j]) begin map_bit[k][j] = -1; map_qn[k][j] = 0; map_ph[k][j] = 0; end
    scan_map_init();
`ifdef BREAK_MAP
    // self-test: move an inversion one cell along c0, keeping the chain's parity
    map_qn[1][1] = map_qn[1][1] == 1 ? 0 : 1;
    map_qn[1][2] = map_qn[1][2] == 1 ? 0 : 1;
`endif
    map_ok = 1;
    foreach (seen[b]) seen[b] = 0;
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
      // A flop that stores its bit inverted: a_inv/b_inv run to the RTL bit.
      for (int j = 1; j <= last; j++)
        if (map_ph[k][j] == 1) begin
          a_inv[k][j] ^= 1'b1;
          b_inv[k][j] ^= 1'b1;
        end
      s = "";
      for (int j = 1; j <= last; j++) begin
        if (map_bit[k][j] < 0) s = {s, " ?"};
        else begin
          s = {s, $sformatf(" %0d", map_bit[k][j])};
          if (map_bit[k][j] < 64) begin seen[map_bit[k][j]]++; on_chain[map_bit[k][j]] = 1'b1; end
        end
        if (map_qn[k][j] == 1) s = {s, "~"};
        if (map_ph[k][j] == 1) s = {s, "!"};
      end
      $display("[%0t] M: c%0d, PC bits from scan-in to scan-out (~ = scan out of QN, ! = stored inverted):%s", $time, k-1, s);
    end
    for (int b = 0; b < 64; b++)
      if (seen[b] > 1) begin
        fail($sformatf("M: PC[%0d] is on %0d cells", b, seen[b]));
        map_ok = 0;
      end
    s = "";
    for (int b = 1; b < 64; b++) if (seen[b] == 0) s = {s, $sformatf(" %0d", b)};
    if (s != "") fail($sformatf("M: PC bits on no chain:%s", s));
    if (!map_ok) $display("[%0t] M: the map does not match the pins: exact B, E and F skipped", $time);
`endif
  endtask

  // ---- B: PC readout ----------------------------------------------------------------
  bits_t pc_read;
  task automatic phase_b();
    bits_t zeros = '{default: 1'b0};
    int ones = 0, n_inv = 0;
    pc_t pc;
    $display("[%0t] B: PC readout after reset", $time);
    set_se(1'b0); test_mode = 1'b0;
    rst_n = 1'b0; idle(20);
    rst_n = 1'b1; idle(200);                          // ready=0: the fetch never completes
    enter_test();                                     // ends just after an edge: no extra shift
    shift(zeros, pc_read);
    for (int k = 1; k <= N; k++) begin
      $display("[%0t] B: c%0d, first bit out first: %s%s", $time, k-1, chain_str(pc_read, k),
               string'(inv[k] === 1'b1 && !map_ok ? "  (inverting: raw, not checked bit by bit)" : ""));
      if (inv[k] === 1'b1) n_inv++;
      for (int t = 0; t < len[k]; t++) begin
        if ($isunknown(pc_read[k][t]) && (!map_ok || map_bit[k][len[k] - t] >= 0))
          fail($sformatf("B: c%0d bit %0d is X", k-1, t));
        if (pc_read[k][t] === 1'b1 && inv[k] !== 1'b1) ones++;
        if (map_ok) cell_rst[k][len[k] - t] = (pc_read[k][t] ^ b_inv[k][len[k] - t]) === 1'b1;
      end
    end
    if (map_ok) begin
      pc = decode(pc_read);
      $display("[%0t] B: PC = %h", $time, pc);
      check_pc("B reset value", pc, `RESET_VEC);
    end
    else if (n_inv == 0 ? ones != 1 : ones > 1)
      fail($sformatf("B: %0d ones read out of the non-inverting chains; PC = 0x8000_0000 has %s one",
                     ones, n_inv == 0 ? "exactly" : "at most"));
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
  endtask

  // ---- D: load, capture with the core stalled, unload ------------------------------------
  task automatic load_hold_unload(input string tag, input bits_t load);
    bits_t zeros = '{default: 1'b0}, got, unused;
    shift(load, unused);
    set_se(1'b0);                                     // one capture edge
    @(posedge clk); #5;
    set_se(1'b1);
    shift(zeros, got);
    for (int k = 1; k <= N; k++)
      for (int t = 0; t < len[k]; t++)
        if (got[k][t] !== (load[k][maxlen - len[k] + t] ^ inv[k]))
          fail($sformatf("%s: c%0d bit %0d read %b, loaded %b%s", tag, k-1, t, got[k][t],
                         load[k][maxlen - len[k] + t], string'(inv[k] === 1'b1 ? " (inverting)" : "")));
  endtask

  task automatic phase_d();
    bits_t load = '{default: 1'b0};
    $display("[%0t] D: load, capture, unload", $time);
    if (map_ok) begin
      // The map is there: a random PC, every other cell in its reset state
      hold_pc("D random", {$urandom, $urandom});
      hold_pc("D restore PC", decode(pc_read));
      return;
    end
    for (int k = 1; k <= N; k++)
      for (int t = 0; t < maxlen; t++) load[k][t] = $urandom_range(1);
    load_hold_unload("D random", load);
    // B's readout, shifted back in, puts the PC back where it was; an inverting
    // chain inverts on the way in as well, so it gets the readout inverted
    load = '{default: 1'b0};
    for (int k = 1; k <= N; k++)
      for (int t = 0; t < len[k]; t++) load[k][maxlen - len[k] + t] = pc_read[k][t] ^ inv[k];
    load_hold_unload("D restore PC", load);
  endtask

  // ---- E: PC values held ----------------------------------------------------------------
  int n_pat, n_pat_bad;

  // Load v into the PC, hold it, read it back.  func_cyc = 0: one capture clock
  // in test mode.  Otherwise func_cyc clocks in functional mode (test_mode=0,
  // io_out back with the link), plus TM_SYNC more while test_mode settles; the
  // fetch stays stalled on ready=0 throughout.
  task automatic hold_pc(input string tag, input pc_t v, input int func_cyc = 0);
    bits_t zeros = '{default: 1'b0}, got, unused;
    int err0 = errors;
    shift(encode(v), unused);
    set_se(1'b0);
    if (func_cyc == 0) begin
      @(posedge clk); #5;
    end
    else begin
      test_mode = 1'b0;
      idle(func_cyc);
      enter_test();
    end
    set_se(1'b1);
    shift(zeros, got);
    check_pc(tag, decode(got), v);
    n_pat++;
    if (errors != err0) n_pat_bad++;
  endtask

  task automatic phase_e();
    pc_t v;
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
      if (on_chain[b]) begin
        hold_pc($sformatf("E walking 1, PC[%0d]", b),  pc_t'(1) << b);
        hold_pc($sformatf("E walking 0, PC[%0d]", b), ~(pc_t'(1) << b));
      end
    for (int i = 0; i < 16; i++) begin
      v = {$urandom, $urandom};
      hold_pc($sformatf("E random %0d", i), v);
    end
    // Held for longer, with the chip in functional mode
    hold_pc("E functional hold, all 1",     '1,          50);
    hold_pc("E functional hold, 0x5555...", {32{2'b01}}, 50);
    hold_pc("E functional hold, 0xAAAA...", {32{2'b10}}, 50);
    v = {$urandom, $urandom};
    hold_pc("E functional hold, random",    v,           50);
    $display("[%0t] E: %0d values, %0d failed", $time, n_pat, n_pat_bad);
  endtask

  // ---- F: reset over a loaded PC --------------------------------------------------------
  task automatic reset_pc(input string tag, input pc_t v);
    bits_t zeros = '{default: 1'b0}, got, unused;
    int err0 = errors;
    shift(encode(v), unused);
    set_se(1'b0); test_mode = 1'b0;
    rst_n = 1'b0; idle(20);
    rst_n = 1'b1; idle(200);                          // as B: the fetch stalls on ready=0
    enter_test();
    shift(zeros, got);
    check_pc(tag, decode(got), `RESET_VEC);
    n_pat++;
    if (errors != err0) n_pat_bad++;
  endtask

  task automatic phase_f();
    $display("[%0t] F: reset over a loaded PC", $time);
    n_pat = 0; n_pat_bad = 0;
    reset_pc("F from all 1",          '1);
    reset_pc("F from ~reset value",   ~`RESET_VEC);
    reset_pc("F from 0x5555...",      {32{2'b01}});
    reset_pc("F from 0xAAAA...",      {32{2'b10}});
    for (int i = 0; i < 4; i++)
      reset_pc($sformatf("F from random %0d", i), {$urandom, $urandom});
    $display("[%0t] F: %0d resets, %0d failed", $time, n_pat, n_pat_bad);
  endtask

  // ---- run ---------------------------------------------------------------------------------
  initial begin
    rst_n = 1'b0; ready = 1'b0; rvalid = 1'b0; irq = '0; uart_rx = 1'b1;
    fault_inject = 1'b0; test_mode = 1'b0; si = '0;
    set_se(1'b0);
    idle(20); rst_n = 1'b1; idle(5);

    phase_a();
    if (maxlen == 0) fail("no chain shifts at all; skipping M-F");
    else begin
      phase_m();
      phase_b();
      phase_c();
      phase_d();
      if (map_ok) begin
        phase_e();
        phase_f();
      end
    end

    if (map_ok) begin
      if (bad_bits == '0) $display("PC: all %0d bits on the chains passed B, E and F", $countones(on_chain));
      else                $display("PC: bits that failed in B, E or F:%s", bit_list(bad_bits, 64));
    end
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
