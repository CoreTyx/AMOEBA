// Small instruction streams using the post-synthesis pin-link driver. No ELF,
// internal force, or program reference model is involved in the verdict.
localparam logic [31:0] EXEC_NOP = 32'h00000013, EXEC_WFI = 32'h10500073;
localparam logic [31:0] EXEC_ADD = 32'h00628033; // add x0,x5,x6
logic [63:0] emit_pc;

function automatic int exec_reg(input string suffix);
  int found = -1;
  for (int r = 0; r < n_regs; r++) begin
    int start = reg_name[r].len() - suffix.len();
    if (start >= 0 && reg_name[r].substr(start, reg_name[r].len()-1) == suffix) begin
      if (found >= 0) return -1; // ambiguous mappings cannot establish an oracle
      found = r;
    end
  end
  return found;
endfunction

function automatic bit exec_complete(input int r, input int first, input int width);
  if (r < 0) return 0;
  for (int b = first; b < width; b++) if (reg_k[r][b] == 0) return 0;
  return 1;
endfunction

function automatic logic [31:0] exec_i(input logic [11:0] imm,
    input logic [4:0] rs, input logic [2:0] fn, input logic [4:0] rd);
  return {imm, rs, fn, rd, 7'h13};
endfunction

function automatic void emit32(input logic [31:0] insn);
  for (int b = 0; b < 4; b++) link.mem_wr_byte(emit_pc + 64'(b), insn[8*b+:8]);
  emit_pc += 4;
endfunction

// Nibble construction avoids RV64 LUI/ADDI sign-extension pitfalls, including
// bit 63, 0x80000000, and long runs of ones. Arithmetic wraps at 64 bits.
function automatic void emit_const(input logic [4:0] rd, input logic [63:0] value);
  emit32(exec_i({8'b0,value[63:60]}, 0, 0, rd));
  for (int n = 14; n >= 0; n--) begin
    emit32(exec_i(12'd4, rd, 3'b001, rd));
    emit32(exec_i({8'b0,value[4*n+:4]}, rd, 0, rd));
  end
endfunction

function automatic void emit_csr(input logic [11:0] csr, input logic [2:0] fn,
                                 input logic [4:0] rd, input logic [4:0] rs);
  emit32({csr,rs,fn,rd,7'h73});
endfunction

// Returns an independently calculated architectural result, not a prediction
// from DUT signals. x5/x6 are later read by the ADD parked behind WFI.
task automatic exec_image(input int i, output logic [63:0] x5, output logic [63:0] x6,
    output logic [31:0] freq, output logic [1:0] mpp, output logic [63:0] park);
  logic [63:0] a, b, v;
  int modes[3] = '{0,1,3};
  a = 64'(edge_or_random(i)); b = 64'(edge_or_random(i+3));
  case (i / 8)
    0: begin a = 0; b = 0; end
    1: begin a = '1; b = 1; end
    2: begin a = 64'h8000000000000000; b = '1; end
    3: begin a = 64'h7fffffffffffffff; b = 64'h8000000000000000; end
    default: begin a = {$urandom,$urandom}; b = {$urandom,$urandom}; end
  endcase
  if (i % 8 == 4 && i < 32) begin
    // Include disabled, densely enabled, all-one, and sign-bit periods, with
    // distinctive high bits and a nonzero set/clear readback where applicable.
    case (i / 8)
      0: a = 64'hd39a024700000000;
      1: a = 64'hd39a024700000001;
      2: a = 64'hd39a0247ffffffff;
      3: a = 64'hd39a024780000000;
    endcase
    b = 64'hc57edcba00005aa5;
  end
  link.mem.delete();
  link.mem_policy = "x";
  // Every reachable instruction byte is defined. Any fetch elsewhere retains
  // X (or fails the link address checker), including a trap to mtvec=0.
  for (int off = 0; off < 4096; off += 8)
    link.mem_wr(`RESET_VEC + 64'(off), {EXEC_NOP,EXEC_NOP}, 8'hff);
  emit_pc = `RESET_VEC;
  repeat (16 + (i % 16)) emit32(EXEC_NOP);
  // Exercise W1C before the operations under test. Any later security fault
  // must remain observable at the endpoint rather than being cleared away.
  emit_const(12, '1); emit_csr(12'h7c0, 1, 0, 12);
  emit_const(10, a); emit_const(11, b);
  emit_csr(12'h340, 1, 0, 11); // mscratch = b
  emit_csr(12'h340, 2, 6, 0);  // x6 = mscratch; CSRRS x0 does not write
  x6 = b; freq = 0;
  mpp = 2'(modes[i % 3]);
  emit_const(12, 64'(mpp) << 11);
  emit_csr(12'h300, 1, 0, 12); // mstatus: MIE/TW clear; current privilege stays M
  case (i % 8)
    0: begin emit32({7'b0,5'd11,5'd10,3'b000,5'd5,7'h33}); x5 = a+b; end
    1: begin emit32({7'b0,5'd11,5'd10,3'b100,5'd5,7'h33}); x5 = a^b; end
    2: begin emit32({7'b0,5'd11,5'd10,3'b001,5'd5,7'h33}); x5 = a << b[5:0]; end
    3: begin emit32({7'b1,5'd11,5'd10,3'b000,5'd5,7'h33}); x5 = a*b; end
    4: begin
      emit_csr(12'h7c1, 1, 0, 10); // low 32 bits writable
      emit_csr(12'h7c1, 2, 0, 11); // set bits
      emit_csr(12'h7c1, 3, 0, 10); // clear bits
      v = (a | b) & ~a;
      emit_csr(12'h7c1, 2, 5, 0);  // read, no write
      emit_csr(12'h7c1, 3, 0, 0);  // CSRRC x0 also no write
      emit_csr(12'h7c1, 2, 5, 0);  // observe the value AFTER the no-write operation
      emit_csr(12'h7c1, 1, 0, 0);  // CSRRW x0 DOES write zero; disable insertion
      x5 = {32'b0,v[31:0]};
    end
    5: begin
      emit_csr(12'h340, 2, 0, 10);
      emit_csr(12'h340, 3, 0, 11);
      emit_csr(12'h340, 2, 5, 0);
      x5 = (b | a) & ~b;
    end
    6: begin
      emit_const(12, 64'd2 << 11); // reserved MPP must retain previous legal MPP
      emit_csr(12'h300, 1, 0, 12);
      emit_csr(12'h300, 2, 5, 0);
      emit32(exec_i(12'd11,5,3'b101,5));
      emit32(exec_i(12'd3,5,3'b111,5));
      x5 = 64'(mpp);
    end
    7: begin
      // Only from a fresh reset: no previously captured dummy is carried in.
      // The immediate first strobe captures a dummy; the next is >2^31 clocks away.
      freq = a[31:0] | 32'h80000000;
      emit_const(12, {32'hd39a0247,freq}); // tests RV64->32-bit CSR truncation
      emit_csr(12'h7c1, 1, 0, 12);
      emit_csr(12'h7c1, 2, 5, 0);
      x5 = {32'b0,freq};
    end
  endcase
  // Operand registers capture the register file before forwarding. Allow the
  // last x5/x6 write to retire and dummy insertion to drain before parking.
  repeat (8) emit32(EXEC_NOP);
  while (emit_pc[3:0] != 0) emit32(EXEC_NOP);
  park = emit_pc;
  emit32(EXEC_WFI); emit32(EXEC_ADD); emit32(EXEC_NOP); emit32(EXEC_NOP);
  $display("I IMAGE: iteration=%0d kind=%0d a=%016h b=%016h x5=%016h x6=%016h freq=%08h MPP=%0d WFI=%016h",
           i, i%8, a, b, x5, x6, freq, mpp, park);
endtask

task automatic phase_i();
  int pcm = exec_reg("_PCMReg"), pce = exec_reg("_PCEReg");
  int im = exec_reg("_InstrMReg"), ie = exec_reg("_InstrEReg");
  int rd1 = exec_reg("_RD1EReg"), rd2 = exec_reg("_RD2EReg");
  int fr = exec_reg("/RANDINSTRFREQreg");
  int kinds[8] = '{default:0};
  n_pat = 0; n_pat_bad = 0;
  if (scan_op == "load") begin
    skip_check("I", "instruction execution requires capture/both, not SCAN_OP=load");
    return;
  end
  if (!(exec_complete(pc_r,1,64) && exec_complete(pcm,1,64) && exec_complete(pce,1,64) &&
        exec_complete(im,0,32) && exec_complete(ie,0,32) &&
        exec_complete(rd1,0,ECC_CW) && exec_complete(rd2,0,ECC_CW) &&
        exec_complete(fr,0,32) && exec_complete(mpp_r,0,2) && exec_complete(msf_r,0,7))) begin
    fail("I: missing, ambiguous or incomplete mandatory PC/instruction/operand/CSR mapping; execution coverage unavailable");
    return;
  end
  for (int i = 0; i < exec_iters; i++) begin
    logic [63:0] x5, x6, park, actual_pc;
    logic [31:0] freq;
    logic [1:0] mpp;
    string tag = $sformatf("I iteration %0d kind=%0d", i, i%8);
    if (!case_selected(tag)) continue;
    cases_selected++; kinds[i%8]++;
    exec_image(i, x5, x6, freq, mpp, park);
    for (int rep = 0; rep < case_repeats; rep++) begin
      bits_t raw;
      st_t got, ex;
      int initial_link_errors = link.errors;
      longint reads_before = link.n_rd;
      longint writes_before = link.n_wr;
      $display("[%0t] CASE: %s repeat=%0d/%0d seed=%0d operation=execute", $time,tag,rep+1,case_repeats,scan_seed);
      link_active = 0; rst_n = 0; idle(20);
      set_se(0); test_mode = 0;
      link.gap_pct = (i%3 == 0) ? 0 : ((i%3 == 1) ? 10 : 25);
      link.rd_latency = i%16;
      link_active = 1; idle(20); rst_n = 1;
      // Bounded budget. Failure to reach WFI is checked through scan, never
      // inferred from elapsed time or a lack of link traffic.
      idle(4096 + (i % 32));
      // This task returns in the post-edge launch slot. Disable the agent
      // BEFORE remapping the bus, select scan before any further rising edge.
      link_active = 0; test_mode = 1; set_se(1);
      snapshot_internal(tag);
      scan_readout(tag, raw); got = decode(raw);
      ex = '{default:'{default:1'bx}};
      ex = reg_put(ex, pcm, val_t'(park));
      ex = reg_put(ex, pce, val_t'(park+4));
      ex = reg_put(ex, im, val_t'(EXEC_WFI));
      ex = reg_put(ex, ie, val_t'(EXEC_ADD));
      ex = reg_put(ex, rd1, val_t'(ecc_enc(x5)));
      ex = reg_put(ex, rd2, val_t'(ecc_enc(x6)));
      ex = reg_put(ex, fr, val_t'(freq));
      ex = reg_put(ex, mpp_r, val_t'(mpp));
      ex = reg_put(ex, msf_r, '0);
      check(tag, got, ex);
      actual_pc = 64'(reg_val(got, pc_r));
      if ($isunknown(actual_pc) || actual_pc < park || actual_pc > park+16 || actual_pc[1:0] != 0)
        fail($sformatf("%s: PC=%h outside terminal window [%h,%h]",tag,actual_pc,park,park+16));
      if (link.errors != initial_link_errors)
        fail($sformatf("%s: %0d link errors: %s",tag,link.errors-initial_link_errors,link.first_err));
      if (link.n_rd - reads_before < 2) fail({tag, ": fewer than two completed instruction line reads"});
      if (link.n_wr != writes_before) fail({tag, ": unexpected memory write in an instruction-only sequence"});
      $display("I EXEC: %s PC=%016h instruction_lines=%0d gaps=%0d latency=%0d",tag,actual_pc,link.n_rd-reads_before,link.gap_pct,link.rd_latency);
    end
  end
  $display("I COVERAGE: ADD=%0d XOR=%0d SLL=%0d MUL=%0d RAND_CSR=%0d MSCRATCH=%0d MPP_WARL=%0d RAND_DIRECT=%0d comparisons=%0d failed=%0d",
           kinds[0],kinds[1],kinds[2],kinds[3],kinds[4],kinds[5],kinds[6],kinds[7],n_pat,n_pat_bad);
endtask
