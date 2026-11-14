// Phase S: a resumable scan session.  A generated RV64 program runs through the
// link agent; at cycle N the bench quiets the link, pauses the agent (without
// resetting it), enters test mode in hold mode (enter_hold), unloads every
// chain, reloads what it read, unloads and reloads once more, leaves test mode
// (exit_hold), unpauses the agent and lets the program finish.  Memory image,
// signature, tohost, write log and the scan state at the final WFI must equal a
// reference run of the same program without a session.
//
// Variants per program and N (tag "S prog <p> N=<n> <variant>"):
//   session  the full session above
//   tm       the same entry and exit, but K = 4*maxlen scan_en=0 edges in test
//            mode instead of the four shift passes: a core that is not frozen
//            in test mode fails this without any shifting
//   ctl      no test mode and no scan_en: only the link pause, as long as a
//            session.  It must pass on any design; a failure is a bench/oracle
//            problem, not a DFT one.
// The verdict uses pins and the agent's memory.  Register file, CSR and scan
// cell hookups (internal_hookups.py) are diagnostic only: on failure they name
// the likely cause (cause 1-4 lines).

localparam logic [63:0] RES_DATA = 64'h8001_0000;   // 16 KiB: four times the D$
localparam logic [63:0] RES_SIG  = 64'h8002_0000;
localparam logic [63:0] RES_TRAP = `RESET_VEC + 64'h3000;
localparam int RES_DATA_DW = 2048, RES_SIG_DW = 48, RES_CODE_B = 'h3200;
localparam int RES_PARK = 256;                       // cycles after tohost before the final readout
localparam int RES_NSIG_CSR = 8;
localparam logic [11:0] RES_CSR [RES_NSIG_CSR] = '{12'h340, 12'h305, 12'h341, 12'h342,
                                                   12'h343, 12'h300, 12'h7c0, 12'h7c1};
localparam string RES_CSR_NAME [RES_NSIG_CSR] = '{"mscratch", "mtvec", "mepc", "mcause",
                                                  "mtval", "mstatus", "MSECFAULT", "RANDINSTRFREQ"};
localparam logic [31:0] RES_FENCEI = 32'h0000100f;

int resume_progs = 4, resume_budget = 60000;
int resume_n [$];
logic [63:0] res_prng;

// Ordered write log: address and both beats of every completed link write.
logic [63:0] res_wlog [$];
bit res_wlog_on = 0;
always @(link.n_wr)
  if (res_wlog_on) begin
    res_wlog.push_back(64'(link.addr));
    res_wlog.push_back(link.line_w[0]);
    res_wlog.push_back(link.line_w[1]);
  end

// Link activity while the agent is paused (cause 3).
bit res_mon = 0;
int res_req_n, res_wr_n;
always @(posedge clk)
  if (res_mon) begin
    if (req !== 1'b0) res_req_n++;
    if (wr !== 1'b0) res_wr_n++;
  end

function automatic logic [63:0] res_rand();
  res_prng ^= res_prng << 13;
  res_prng ^= res_prng >> 7;
  res_prng ^= res_prng << 17;
  return res_prng;
endfunction

// ---- RV64 encoders ------------------------------------------------------------
function automatic logic [31:0] rv_r(input logic [6:0] f7, input logic [4:0] rs2, rs1,
                                     input logic [2:0] f3, input logic [4:0] rd,
                                     input logic [6:0] op = 7'h33);
  return {f7, rs2, rs1, f3, rd, op};
endfunction
function automatic logic [31:0] rv_i(input logic [11:0] imm, input logic [4:0] rs1,
                                     input logic [2:0] f3, input logic [4:0] rd,
                                     input logic [6:0] op = 7'h13);
  return {imm, rs1, f3, rd, op};
endfunction
function automatic logic [31:0] rv_s(input logic [11:0] imm, input logic [4:0] rs2, rs1,
                                     input logic [2:0] f3);
  return {imm[11:5], rs2, rs1, f3, imm[4:0], 7'h23};
endfunction
function automatic logic [31:0] rv_b(input logic [12:0] off, input logic [4:0] rs2, rs1,
                                     input logic [2:0] f3);
  return {off[12], off[10:5], rs2, rs1, f3, off[4:1], off[11], 7'h63};
endfunction
function automatic logic [31:0] rv_jal(input logic [20:0] off, input logic [4:0] rd);
  return {off[20], off[10:1], off[11], off[19:12], rd, 7'h6f};
endfunction

// ---- the program --------------------------------------------------------------
// Setup (mtvec, bases, operands, mscratch/mepc/mcause/mtval, RANDINSTRFREQ),
// then a loop of ALU ops, MUL/DIV (64- and 32-bit), loads and stores over a
// 16 KiB region (misses and write-backs in the 4 KiB D$), a data-dependent
// branch and CSR swaps; then x1..x31 and eight CSRs to the signature, fence.i,
// tohost = 1, fence.i, WFI.  Any trap writes tohost = (0x400|mcause)<<1 | 1.
task automatic res_image(input int p, output int iters);
  logic [63:0] loop_pc;
  link.mem.delete();
  link.mem_policy = "x";
  res_prng = 64'h2545_F491_4F6C_DD1D ^ (64'(scan_seed) << 32) ^ 64'(p + 1);
  void'(res_rand());
  for (int off = 0; off < RES_CODE_B; off += 8)
    link.mem_wr(`RESET_VEC + 64'(off), {EXEC_NOP, EXEC_NOP}, 8'hff);
  for (int i = 0; i < RES_DATA_DW; i++) link.mem_wr(RES_DATA + 64'(8*i), res_rand(), 8'hff);
  for (int i = 0; i < RES_SIG_DW; i++)  link.mem_wr(RES_SIG + 64'(8*i), '0, 8'hff);
  link.mem_wr({link.tohost_addr[63:4], 4'b0}, '0, 8'hff);
  link.mem_wr({link.tohost_addr[63:4], 4'b0} + 8, '0, 8'hff);
  iters = 10 + 2 * (p % 4);

  emit_pc = `RESET_VEC;
  emit_const(5, RES_TRAP);      emit_csr(12'h305, 1, 0, 5);
  emit_const(31, RES_DATA);
  emit_const(30, RES_SIG);
  emit_const(28, link.tohost_addr);
  for (int r = 1; r <= 8; r++) emit_const(5'(r), res_rand());
  for (int r = 9; r <= 26; r++)
    emit32(rv_r(r % 3 && r % 2 ? 7'h20 : 7'h00, 5'(r - 7), 5'(r - 8),   // sub/add/xor
                r % 3 ? 3'b000 : 3'b100, 5'(r)));
  emit_csr(12'h340, 1, 0, 1);   // mscratch = x1
  emit_csr(12'h341, 1, 0, 2);   // mepc = x2
  emit_csr(12'h342, 1, 0, 3);   // mcause = x3
  emit_csr(12'h343, 1, 0, 4);   // mtval = x4
  emit32(exec_i(12'(3 + p % 5), 0, 0, 5));
  emit_csr(12'h7c1, 1, 0, 5);   // RANDINSTRFREQ: dummy insertion on during the loop
  emit_const(29, 64'(iters));

  loop_pc = emit_pc;
  emit32(rv_r(0, 2, 1, 0, 9));                   // add  x9, x1, x2
  emit32(rv_r(0, 3, 9, 4, 10));                  // xor  x10, x9, x3
  emit32(rv_r(0, 4, 10, 1, 11));                 // sll  x11, x10, x4
  emit32(rv_r(1, 10, 9, 0, 12));                 // mul  x12, x9, x10
  emit32(rv_r(1, 12, 11, 3, 13));                // mulhu x13, x11, x12
  emit32(exec_i(1, 5, 3'b110, 14));              // ori  x14, x5, 1
  emit32(rv_r(1, 14, 12, 4, 15));                // div  x15, x12, x14
  emit32(rv_r(1, 6, 13, 7, 16));                 // remu x16, x13, x6
  emit32(rv_r(1, 14, 15, 4, 17, 7'h3b));         // divw x17, x15, x14
  emit32(rv_r(1, 7, 16, 0, 18, 7'h3b));          // mulw x18, x16, x7
  emit32(exec_i(7, 9, 3'b101, 19));              // srli x19, x9, 7
  emit32(exec_i(12'd2047, 19, 3'b111, 19));      // andi x19, x19, 2047
  emit32(exec_i(3, 19, 3'b001, 19));             // slli x19, x19, 3
  emit32(rv_r(0, 31, 19, 0, 19));                // add  x19, x19, x31
  emit32(rv_i(0, 19, 3'b011, 20, 7'h03));        // ld   x20, 0(x19)
  emit32(rv_r(0, 15, 20, 0, 20));                // add  x20, x20, x15
  emit32(rv_s(0, 20, 19, 3'b011));               // sd   x20, 0(x19)
  emit32(exec_i(5, 29, 3'b001, 21));             // slli x21, x29, 5
  emit32(rv_r(0, 12, 21, 4, 21));                // xor  x21, x21, x12
  emit32(exec_i(12'd2047, 21, 3'b111, 21));      // andi x21, x21, 2047
  emit32(exec_i(3, 21, 3'b001, 21));             // slli x21, x21, 3
  emit32(rv_r(0, 31, 21, 0, 21));                // add  x21, x21, x31
  emit32(rv_i(4, 21, 3'b010, 22, 7'h03));        // lw   x22, 4(x21)
  emit32(rv_s(0, 18, 21, 3'b010));               // sw   x18, 0(x21)
  emit32(rv_s(6, 17, 21, 3'b001));               // sh   x17, 6(x21)
  emit32(rv_s(3, 16, 19, 3'b000));               // sb   x16, 3(x19)
  emit32(rv_i(1, 21, 3'b100, 23, 7'h03));        // lbu  x23, 1(x21)
  emit_csr(12'h340, 1, 24, 20);                  // csrrw x24, mscratch, x20
  emit_csr(12'h341, 1, 25, 12);                  // csrrw x25, mepc, x12
  emit_csr(12'h343, 1, 26, 22);                  // csrrw x26, mtval, x22
  emit32(exec_i(1, 9, 3'b111, 27));              // andi x27, x9, 1
  emit32(rv_b(13'd8, 0, 27, 3'b000));            // beq  x27, x0, +8
  emit32(exec_i(12'd3, 8, 3'b000, 8));           // addi x8, x8, 3
  emit32(rv_r(0, 12, 2, 4, 1));                  // xor  x1, x2, x12
  emit32(rv_r(0, 15, 3, 0, 2));                  // add  x2, x3, x15
  emit32(rv_r(7'h20, 16, 4, 0, 3));              // sub  x3, x4, x16
  emit32(rv_r(0, 24, 5, 3'b110, 4));             // or   x4, x5, x24
  emit32(rv_r(0, 20, 6, 0, 5));                  // add  x5, x6, x20
  emit32(rv_r(0, 23, 7, 4, 6));                  // xor  x6, x7, x23
  emit32(rv_r(0, 25, 8, 0, 7));                  // add  x7, x8, x25
  emit32(rv_r(0, 26, 1, 4, 8));                  // xor  x8, x1, x26
  emit32(exec_i(12'hfff, 29, 0, 29));            // addi x29, x29, -1
  emit32(rv_b(13'(loop_pc - emit_pc), 0, 29, 3'b001)); // bne x29, x0, loop

  for (int r = 1; r <= 31; r++) emit32(rv_s(12'(8*r), 5'(r), 30, 3'b011));
  for (int c = 0; c < RES_NSIG_CSR; c++) begin
    emit_csr(RES_CSR[c], 2, 5, 0);                         // csrr x5, csr
    emit32(rv_s(12'(8*(32+c)), 5, 30, 3'b011));            // sd x5, sig[32+c]
  end
  emit_csr(12'h7c1, 1, 0, 0);                              // dummy insertion off
  emit32(RES_FENCEI);
  emit32(exec_i(1, 0, 0, 5));
  emit32(rv_s(0, 5, 28, 3'b011));                          // tohost = 1
  emit32(RES_FENCEI);
  emit32(EXEC_WFI); emit32(rv_jal(-21'sd4, 0));
  if (emit_pc >= RES_TRAP) $fatal(1, "S: program overruns the trap handler at %h", RES_TRAP);
  emit_pc = RES_TRAP;
  emit_csr(12'h341, 2, 7, 0);                              // sig[0] = mepc
  emit_csr(12'h343, 2, 8, 0);                              // sig[47] = mtval
  emit_const(6, RES_SIG);
  emit32(rv_s(0, 7, 6, 3'b011));
  emit32(rv_s(12'(8*(RES_SIG_DW-1)), 8, 6, 3'b011));
  emit_csr(12'h342, 2, 5, 0);
  emit32(exec_i(12'h400, 5, 3'b110, 5));
  emit32(exec_i(1, 5, 3'b001, 5));
  emit32(exec_i(1, 5, 3'b110, 5));
  emit_const(6, link.tohost_addr);
  emit32(rv_s(0, 5, 6, 3'b011));
  emit32(RES_FENCEI);
  emit32(EXEC_WFI); emit32(rv_jal(-21'sd4, 0));
  if (emit_pc >= `RESET_VEC + RES_CODE_B) $fatal(1, "S: trap handler overruns the code window");
endtask

// ---- one run --------------------------------------------------------------------
typedef struct {
  int          cycles;           // reset release to tohost
  bit          done;
  logic [63:0] tohost;
  logic [63:0] data [RES_DATA_DW];
  logic [63:0] sig [RES_SIG_DW];
  logic [63:0] wlog [$];
  st_t         final_st;
  int          link_errors;
} res_result_t;

task automatic res_release_link();
  link_paused = 0;
  link.paused = 0;
  link.hold_ready = 0;
endtask

task automatic res_start(input int p, input int lat, output int iters);
  link_active = 0; res_release_link();
  rst_n = 0; idle(20);
  set_se(0); test_mode = 0;
  res_image(p, iters);
  link.gap_pct = 0;
  link.rd_latency = lat;
  link.tohost_seen = 0;           // the agent's reset does not clear these
  link.tohost_val = '0;
  res_wlog.delete();
  res_wlog_on = 1;
  link_active = 1; idle(20); rst_n = 1;
endtask

// Up to n cycles; stops early at tohost when stop_at_tohost, and at a link
// error (the run has failed already; no point running out the budget).
task automatic res_cycles(input int n, input bit stop_at_tohost, inout int cyc);
  logic [N:1] unused;
  int e0 = link.errors;
  for (int i = 0; i < n; i++) begin
    if (stop_at_tohost && (link.tohost_seen || link.errors != e0)) break;
    cycle('0, unused);
    cyc++;
  end
endtask

// Bring the link to rest: the agent idles with ready low for GUARD+2 cycles
// with no req (a request the chip launched inside the guard band completes
// first).  Then the agent is paused and the pins go to the bench.
task automatic res_quiesce(input string tag, inout int cyc);
  int quiet = 0, spent = 0;
  logic [N:1] unused;
  link.hold_ready = 1;
  while (quiet < 5) begin
    cycle('0, unused);
    cyc++; spent++;
    if (link.st.name() == "A_IDLE" && req === 1'b0 && link.ready === 1'b0) quiet++;
    else quiet = 0;
    if (spent > 4000) begin
      fail({tag, ": the link did not come to rest within 4000 cycles"});
      break;
    end
  end
  link.paused = 1;
  link_paused = 1;
  $display("[%0t] S: %s: link quiet after %0d cycles, agent paused at link cycle %0d", $time, tag, spent, link.cyc);
endtask

task automatic res_finish(input string tag, input int budget, inout int cyc, inout res_result_t r);
  bits_t raw;
  res_cycles(budget - cyc, 1, cyc);
  r.done = link.tohost_seen;
  r.cycles = cyc;
  r.tohost = link.tohost_val;
  if (r.done) res_cycles(RES_PARK, 0, cyc);
  res_wlog_on = 0;
  r.wlog = res_wlog;
  for (int i = 0; i < RES_DATA_DW; i++) r.data[i] = link.mem_rd(RES_DATA + 64'(8*i));
  for (int i = 0; i < RES_SIG_DW; i++)  r.sig[i]  = link.mem_rd(RES_SIG + 64'(8*i));
  r.link_errors = link.errors;
  res_quiesce({tag, " final"}, cyc);
  enter_test();
  snapshot_internal({tag, " final"});
  scan_readout({tag, " final"}, raw);
  r.final_st = decode(raw);
  res_release_link();
  link_active = 0;
endtask

// ---- non-scan diagnostics ---------------------------------------------------------
typedef struct {
  logic [ECC_CW-1:0] rf [1:31];
  val_t csr [string];
  val_t cells [string];
  logic unlocked;
} res_snap_t;

function automatic res_snap_t res_snap();
  res_snap_t s;
  for (int i = 1; i <= 31; i++) s.rf[i] = diag_rf_q[(i-1)*ECC_CW +: ECC_CW];
  s.csr = diag_csr_by_name;
  s.cells = internal_raw_by_name;
  s.unlocked = diag_dft_unlocked;
  return s;
endfunction

string res_cause [$];       // what the session diagnostics point at

// Rows/CSRs/cells changed from a to b.  same_rows: rows that changed to a
// value shared with another changed row.
task automatic res_compare(input string what, input res_snap_t a, input res_snap_t b,
                           input bit cells, output int rows, output int same_rows,
                           output string detail);
  int by_val [logic [ECC_CW-1:0]];
  string s = "";
  rows = 0; same_rows = 0;
  if (DIAG_RF_OK) begin
    for (int i = 1; i <= 31; i++)
      if (b.rf[i] !== a.rf[i]) begin
        rows++;
        if (!$isunknown(b.rf[i])) by_val[b.rf[i]]++;
      end
    foreach (by_val[v]) if (by_val[v] >= 2) same_rows += by_val[v];
    if (rows > 0) begin
      s = $sformatf("%0d register-file row(s) changed:", rows);
      for (int i = 1, n = 0; i <= 31 && n < 6; i++)
        if (b.rf[i] !== a.rf[i]) begin
          s = {s, $sformatf(" x%0d %h->%h", i, a.rf[i][ECC_CW-1 -: ECC_DW], b.rf[i][ECC_CW-1 -: ECC_DW])};
          n++;
        end
    end
  end
  foreach (b.csr[n])
    if (a.csr.exists(n) && a.csr[n] !== b.csr[n])
      s = {s, $sformatf(" %s %h->%h", n, a.csr[n][63:0], b.csr[n][63:0])};
  if (cells) begin
    int nc = 0;
    foreach (b.cells[n])
      if (a.cells.exists(n) && a.cells[n] !== b.cells[n]) begin
        nc++;
        if (pc_r >= 0 && n == reg_name[pc_r])
          s = {s, $sformatf(" PC %h->%h", a.cells[n][63:0], b.cells[n][63:0])};
      end
    if (nc > 0) s = {s, $sformatf(" %0d scan register(s) changed", nc)};
  end
  detail = s;
  $display("[%0t] S DIAG: %s: %s", $time, what, s == "" ? "no non-scan change" : s);
endtask

// ---- the session -------------------------------------------------------------------
// Returns with test_mode=0, scan_en=0, the agent still paused.
task automatic res_session(input string tag, input string variant, inout int cyc);
  res_snap_t s0, s1, s2;
  bits_t zeros = '{default: '{default: 1'b0}};
  bits_t rec1, rec2, thru;
  int rows, same, link_err0 = link.errors, shift_bad = 0, again_bad = 0;
  string d, bad_chains = "";
  bit shifted;
  res_req_n = 0; res_wr_n = 0;
  res_mon = 1;
  s0 = res_snap();
  if (variant == "ctl") begin
    idle(4 * maxlen + 2 * TM_SYNC + 3);
    cyc += 4 * maxlen + 2 * TM_SYNC + 3;
  end else begin
    enter_hold(shifted);
    if (shifted)
      res_cause.push_back("cause 4: scan_en shifted the chains outside test mode: the first three cells of every chain took the arm pattern (scan_en not qualified by test_mode)");
    s1 = res_snap();
    // Five functional edges write at most five rows, each its own value.
    res_compare({tag, ": arm and entry (functional edges)"}, s0, s1, 0, rows, same, d);
    if (same >= 6)
      res_cause.push_back($sformatf("cause 1: clock-gate TE forced non-scan flops while armed (scan_en=1, test_mode=0): %0d register-file rows took one shared value (%0d of %0d register-file clock gates have TE=%s; %0d of %0d chip-wide)",
                                    same, DIAG_RF_ICG_TE, DIAG_RF_ICG, DIAG_RF_TE_NET, DIAG_ICG_TE, DIAG_ICG));
    if (variant == "tm") idle(4 * maxlen);
    else begin
      // enter_hold() leaves scan_en low (the protocol's frozen idle edges);
      // the unload and reload shift, so raise it, as enter_test() does.
      set_se(1'b1);
      if (scan_en !== 1'b1) fail($sformatf("%s: scan_en is %b for the unload; the session would not shift", tag, scan_en));
      shift(zeros, rec1);
      shift(encode(decode(rec1)), thru);
      // The zeros the unload shifted in come out first: inv[k] on every chain.
      for (int k = 1; k <= N; k++) begin
        int bad = 0, ones = 0;
        for (int t = 0; t < len[k]; t++) begin
          bad += thru[k][t] !== inv[k];
          ones += thru[k][t] === 1'b1;
        end
        if (bad) bad_chains = {bad_chains, $sformatf(" c%0d:%0d/%0d%s", k-1, bad, len[k],
                               ones == 0 ? "(all 0)" : (ones == len[k] ? "(all 1)" : ""))};
        shift_bad += bad;
      end
      shift(zeros, rec2);
      for (int k = 1; k <= N; k++)
        for (int t = 0; t < len[k]; t++) if (rec2[k][t] !== rec1[k][t]) again_bad++;
      shift(encode(decode(rec1)), thru);
      if (shift_bad) begin
        fail($sformatf("%s: the zeros shifted in by the unload came out wrong during the reload in %0d bit(s), chain:wrong/length%s",
                       tag, shift_bad, bad_chains));
        res_cause.push_back({"cause 6: the chains do not shift cleanly with the core live (reset not held, as the protected readout does):", bad_chains});
      end
      if (again_bad) fail($sformatf("%s: the second unload differs from the first in %0d bit(s)", tag, again_bad));
    end
    cyc += 4 * maxlen + 3 + TM_SYNC;
    s2 = res_snap();
    exit_hold();
    cyc += TM_SYNC;
    res_compare({tag, ": test mode, entry to exit"}, s1, s2, variant == "tm", rows, same, d);
    if (same >= 2 && variant == "session")
      res_cause.push_back($sformatf("cause 1: clock-gate TE forced non-scan flops during shift: %0d register-file rows took one shared value (%0d of %0d register-file clock gates have TE=%s; %0d of %0d chip-wide)",
                                    same, DIAG_RF_ICG_TE, DIAG_RF_ICG, DIAG_RF_TE_NET, DIAG_ICG_TE, DIAG_ICG));
    if (d != "" && !(same >= 2 && same == rows && variant == "session"))
      res_cause.push_back({"cause 2: core not frozen in test mode:", d});
    if (DIAG_LOCK_OK && s0.unlocked === 1'b1 && (s1.unlocked !== 1'b1 || s2.unlocked !== 1'b1))
      res_cause.push_back($sformatf("cause 5: the DFT lock was cleared %s (dft_unlocked 1->0): from then on scan_en and test_mode do nothing; the core, running on corrupted state, wrote forte_dft_lock",
                                    s1.unlocked !== 1'b1 ? "during arm/entry" : "in test mode"));
  end
  res_mon = 0;
  if (res_req_n || res_wr_n || link.errors != link_err0)
    res_cause.push_back($sformatf("cause 3: link not isolated: req active on %0d and wr on %0d session cycle(s), %0d link agent error(s)%s",
                                  res_req_n, res_wr_n, link.errors - link_err0,
                                  link.errors != link_err0 ? {": ", link.last_err} : ""));
endtask

// ---- comparison --------------------------------------------------------------------
function automatic bit res_has(input string s, input string sub);
  for (int i = 0; i + sub.len() <= s.len(); i++)
    if (s.substr(i, i + sub.len() - 1) == sub) return 1;
  return 0;
endfunction

function automatic string res_sig_name(input int i);
  if (i >= 1 && i <= 31) return $sformatf("x%0d", i);
  if (i >= 32 && i < 32 + RES_NSIG_CSR) return RES_CSR_NAME[i-32];
  return $sformatf("sig[%0d]", i);
endfunction

task automatic res_check(input string tag, input res_result_t ref_r, input res_result_t r,
                         input int link_err0);
  int n;
  string s;
  if (!r.done) begin
    fail($sformatf("%s: no tohost by cycle %0d (reference: tohost at %0d); stopped at the budget or the first link error",
                   tag, r.cycles, ref_r.cycles));
  end else if (r.tohost !== ref_r.tohost)
    fail($sformatf("%s: tohost %h, reference %h%s", tag, r.tohost, ref_r.tohost,
                   r.tohost[0] && r.tohost[11] ? $sformatf(" (trap, mcause %0d)", r.tohost[10:1]) : ""));
  n = 0; s = "";
  for (int i = 0; i < RES_SIG_DW; i++)
    if (r.sig[i] !== ref_r.sig[i]) begin
      if (n < 8) s = {s, $sformatf(" %s=%h(ref %h)", res_sig_name(i), r.sig[i], ref_r.sig[i])};
      n++;
    end
  if (n) fail($sformatf("%s: %0d signature word(s) differ:%s", tag, n, s));
  n = 0; s = "";
  for (int i = 0; i < RES_DATA_DW; i++)
    if (r.data[i] !== ref_r.data[i]) begin
      if (n < 4) s = {s, $sformatf(" %h=%h(ref %h)", RES_DATA + 64'(8*i), r.data[i], ref_r.data[i])};
      n++;
    end
  if (n) fail($sformatf("%s: %0d data word(s) differ:%s", tag, n, s));
  if (r.wlog.size() != ref_r.wlog.size() || r.wlog != ref_r.wlog) begin
    int first = -1;
    for (int i = 0; i < r.wlog.size() && i < ref_r.wlog.size(); i++)
      if (r.wlog[i] !== ref_r.wlog[i]) begin first = i / 3; break; end
    if (first < 0) first = (r.wlog.size() < ref_r.wlog.size() ? r.wlog.size() : ref_r.wlog.size()) / 3;
    fail($sformatf("%s: link writes: %0d, reference %0d; first difference at write %0d%s", tag,
                   r.wlog.size() / 3, ref_r.wlog.size() / 3, first,
                   3*first < r.wlog.size() ? $sformatf(" (to %h)", r.wlog[3*first][31:0]) : ""));
    res_cause.push_back($sformatf("cause 2: core not frozen in test mode: link writes differ from the reference (%0d vs %0d, first difference at write %0d)",
                                  r.wlog.size() / 3, ref_r.wlog.size() / 3, first));
  end
  if (r.link_errors != link_err0)
    fail($sformatf("%s: %0d link agent error(s): %s", tag, r.link_errors - link_err0, link.last_err));
  check({tag, " final WFI scan"}, r.final_st, ref_r.final_st);
endtask

task automatic phase_s();
  string s;
  int n_case = 0, n_bad = 0, cov_ses = 0, cov_tm = 0, cov_ctl = 0;
  if (scan_op == "load") begin
    skip_check("S", "the resumable session requires capture/both, not SCAN_OP=load");
    return;
  end
  if (!DIAG_RF_OK || !DIAG_CSR_OK)
    $display("[%0t] S: register-file/CSR hookups unavailable (SCAN_HOOKUPS=0 or names not found): cause 1/2 diagnostics limited", $time);
  else
    $display("[%0t] S: diagnostics on %s and %0d machine CSRs; %0d of %0d register-file clock gates have TE=%s",
             $time, DIAG_RF_PATH, diag_csr_by_name.num(), DIAG_RF_ICG_TE, DIAG_RF_ICG, DIAG_RF_TE_NET);
  n_pat = 0; n_pat_bad = 0;
  for (int p = 0; p < resume_progs; p++) begin
    res_result_t ref_r;
    int iters, cyc, lat = p % 4, ns [$];
    string variants [$];
    bit any = 0;
    string ptag = $sformatf("S prog %0d", p);
    // The reference runs if a case of this program can match the filter; the
    // case tags need N, which needs the reference.
    any = case_filter == "" || case_selected(ptag) || !res_has(case_filter, "prog ") ||
          res_has(case_filter, {ptag, " "});
    if (!any) continue;
    $display("[%0t] CASE: %s reference seed=%0d", $time, ptag, scan_seed);
    begin
      int e0 = link.errors;
      cyc = 0;
      res_start(p, lat, iters);
      res_finish({ptag, " reference"}, resume_budget, cyc, ref_r);
      $display("S REFERENCE: %s iterations=%0d latency=%0d cycles=%0d tohost=%h link_writes=%0d link_errors=%0d",
               ptag, iters, lat, ref_r.cycles, ref_r.tohost, ref_r.wlog.size() / 3, ref_r.link_errors - e0);
      if (!ref_r.done || ref_r.tohost !== 64'd1 || ref_r.link_errors != e0) begin
        fail($sformatf("%s reference: the program did not complete cleanly (tohost %s %h, trap mepc %h mtval %h, %0d link errors); bench or design problem, no session run",
                       ptag, ref_r.done ? "seen" : "not seen", ref_r.tohost, ref_r.sig[0],
                       ref_r.sig[RES_SIG_DW-1], ref_r.link_errors - e0));
        continue;
      end
    end
    if (resume_n.size() > 0) ns = resume_n;
    else for (int i = 0; i < 3; i++)
      ns.push_back(ref_r.cycles * (20 + 25*i) / 100 + (p * 97 + i * 31) % 61);
    foreach (ns[i]) begin
      // session at every N; tm and ctl at the middle one
      variants = '{"session"};
      if (i == ns.size() / 2) begin variants.push_back("tm"); variants.push_back("ctl"); end
      foreach (variants[v]) begin
        res_result_t r;
        string tag = $sformatf("%s N=%0d %s", ptag, ns[i], variants[v]);
        int e0 = errors, le0;
        if (!case_selected(tag)) continue;
        if (ns[i] >= ref_r.cycles) begin
          skip_check(tag, $sformatf("N beyond the program's %0d cycles", ref_r.cycles));
          continue;
        end
        cases_selected++; n_case++; n_pat++;
        $display("[%0t] CASE: %s seed=%0d", $time, tag, scan_seed);
        res_cause.delete();
        le0 = link.errors;
        cyc = 0;
        res_start(p, lat, iters);
        res_cycles(ns[i], 1, cyc);
        if (link.tohost_seen) begin
          skip_check(tag, "the program finished before N");
          link_active = 0;
          continue;
        end
        res_quiesce(tag, cyc);
        $display("[%0t] S: %s: %s at cycle %0d", $time, tag, variants[v] == "ctl" ? "link pause" : "session", cyc);
        res_session(tag, variants[v], cyc);
        res_release_link();
        res_finish(tag, ref_r.cycles * 3 / 2 + 2000, cyc, r);
        res_check(tag, ref_r, r, le0);
        if (variants[v] == "session") cov_ses++;
        else if (variants[v] == "tm") cov_tm++;
        else cov_ctl++;
        $display("S RESUME: %s cycles=%0d (reference %0d) %s", tag, r.cycles, ref_r.cycles,
                 errors == e0 ? "PASS" : "FAIL");
        if (errors != e0) begin
          n_pat_bad++; n_bad++;
          if (variants[v] == "ctl")
            res_cause.push_front("ctl failed: the link pause alone changes the result; the oracle, not the DFT, is wrong");
          if (res_cause.size() == 0) res_cause.push_back("no diagnostic fired (hookups off or a cause outside the register file/CSRs/link)");
          foreach (res_cause[c]) $display("[%0t] S CAUSE: %s: %s", $time, tag, res_cause[c]);
        end
      end
    end
  end
  $display("[%0t] S COVERAGE: programs=%0d session=%0d tm=%0d ctl=%0d cases=%0d failed=%0d",
           $time, resume_progs, cov_ses, cov_tm, cov_ctl, n_case, n_bad);
endtask
