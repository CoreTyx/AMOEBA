// pmp_stress_tb.sv -- the PMP checker against a reference model of the spec.
//
// OpenSBI isolates its own memory from Linux with PMP alone, so the checker's
// answer for every (config, address, size, privilege, access type) must be
// exactly the privileged spec's:
//   * entries are searched lowest-numbered first; the first entry that matches
//     ANY byte of the access decides
//   * if that entry matches only SOME bytes of the access, the access fails,
//     whatever its permissions (Priv. spec 3.7.1)
//   * M-mode is checked only against locked (L) entries; with no match M passes
//     and S/U fail (16 entries implemented)
//   * TOR uses the previous pmpaddr as the bottom (0 for entry 0); NA4/NAPOT
//     decode the trailing-ones encoding; OFF never matches
// Each seed builds random configurations around a focus address -- nested and
// overlapping NAPOT regions, TOR ranges (including empty ones), NA4 words,
// locked entries -- and probes addresses at and around every region edge with
// every size, privilege and access type.  100k checks per seed.
//
//   make -C sim pmp_stress_test SEED=n
`include "config.vh"

module pmp_stress_tb;
  import cvw::*;
  `include "parameter-defs.vh"

  localparam int N = P.PMP_ENTRIES;
  localparam int PAB = P.PA_BITS;

  logic                 clk = 0, reset = 0;
  logic [PAB-1:0]       PhysicalAddress;
  logic [1:0]           Priv;
  logic [7:0]           Cfg [N-1:0];
  logic [PAB-3:0]       Adr [N-1:0];
  logic                 Exec, Write, Read;
  logic [1:0]           Size;
  logic                 FaultF, FaultLd, FaultSt;

  pmpchecker #(.P(P), .MATCH_REG(0)) dut (
    .clk, .reset, .PhysicalAddress, .EffectivePrivilegeModeW(Priv),
    .PMPCFG_ARRAY_REGW(Cfg), .PMPADDR_ARRAY_REGW(Adr),
    .ExecuteAccessF(Exec), .WriteAccessM(Write), .ReadAccessM(Read),
    .Size, .CMOpM(4'b0),
    .PMPInstrAccessFaultF(FaultF), .PMPLoadAccessFaultM(FaultLd), .PMPStoreAmoAccessFaultM(FaultSt));

  // ---- reference model -----------------------------------------------------
  // byte range [lo, hi) of entry i; empty when hi <= lo
  function automatic void range_of(input int i, output longint unsigned lo, output longint unsigned hi);
    logic [1:0] mode = Cfg[i][4:3];
    longint unsigned a = 64'(Adr[i]);
    lo = 0; hi = 0;
    case (mode)
      2'b01: begin lo = (i == 0) ? 0 : (64'(Adr[i-1]) << 2); hi = a << 2; end
      2'b10: begin lo = a << 2; hi = lo + 4; end
      2'b11: begin
        int t = 0;
        while (t < PAB - 2 && a[t]) t++;
        if (t >= PAB - 2) begin lo = 0; hi = 64'(1) << PAB; end
        else begin
          lo = (a >> (t + 1)) << (t + 3);
          hi = lo + (64'(1) << (t + 3));
        end
      end
      default: ;
    endcase
  endfunction

  // returns 1 if the access must be allowed
  function automatic bit model(input longint unsigned addr, input int nbytes, input logic [1:0] prv, input int kind,
                               output bit partial);
    partial = 0;
    for (int i = 0; i < N; i++) begin
      longint unsigned lo, hi;
      int matched = 0;
      range_of(i, lo, hi);
      if (hi <= lo) continue;
      for (int b = 0; b < nbytes; b++) if (addr + b >= lo && addr + b < hi) matched++;
      if (matched == 0) continue;
      if (matched != nbytes) begin partial = 1; return 0; end
      if (prv == 2'b11 && !Cfg[i][7]) return 1;
      case (kind)
        0: return Cfg[i][0];   // load
        1: return Cfg[i][1];   // store / AMO
        default: return Cfg[i][2]; // fetch
      endcase
    end
    return prv == 2'b11;
  endfunction

  // ---- stimulus --------------------------------------------------------------
  longint unsigned focus;
  function automatic longint unsigned rnd64();
    return {$urandom, $urandom};
  endfunction

  task automatic randomize_cfg();
    focus = (rnd64() & ((64'(1) << (PAB - 1)) - 1)) & ~64'hfff;
    if ($urandom_range(0, 3) == 0) focus = 64'h8000_0000 + ($urandom & 32'h0fff_f000);
    for (int i = 0; i < N; i++) begin
      int sel = $urandom_range(0, 9);
      logic [1:0] mode = (sel < 2) ? 2'b00 : (sel < 5) ? 2'b11 : (sel < 8) ? 2'b01 : 2'b10;
      longint unsigned base;
      int k;
      Cfg[i] = {($urandom_range(0, 7) == 0), 2'b00, mode, 3'($urandom)};
      case (mode)
        2'b11: begin   // NAPOT of 2^(k) bytes, k = 3..16, near the focus
          k = $urandom_range(3, 16);
          base = (focus + (64'($urandom_range(0, 7)) << k) - (64'(4) << k)) & ~((64'(1) << k) - 1);
          Adr[i] = (PAB-2)'((base >> 2) | ((64'(1) << (k - 3)) - 1));
        end
        2'b01: Adr[i] = (PAB-2)'((focus + 64'($urandom_range(0, 1 << 15)) - 64'(1 << 14)) >> 2);   // TOR top
        2'b10: Adr[i] = (PAB-2)'((focus + 64'($urandom_range(0, 1 << 12)) - 64'(1 << 11)) >> 2);   // NA4
        default: Adr[i] = (PAB-2)'(rnd64() >> 2);
      endcase
      // The checker sees pmpaddr/pmpcfg as the CSR file legalizes them for grain
      // G (csrm.sv): NA4 is not selectable when G > 0, the low G bits of a
      // TOR/OFF address read 0, the low G-1 bits of a NAPOT address read 1.
      if (P.PMP_G > 0 && Cfg[i][4:3] == 2'b10) Cfg[i][4:3] = 2'b01;
      if (Cfg[i][4]) Adr[i] = Adr[i] | (PAB-2)'((64'(1) << (P.PMP_G > 0 ? P.PMP_G - 1 : 0)) - 1);
      else           Adr[i] = Adr[i] & ~(PAB-2)'((64'(1) << P.PMP_G) - 1);
    end
  endtask

  // an address at, just inside or just outside a random entry's edge
  function automatic longint unsigned pick_addr(int nbytes);
    longint unsigned lo, hi, a;
    int i = $urandom_range(0, N - 1);
    range_of(i, lo, hi);
    case ($urandom_range(0, 5))
      0: a = lo;
      1: a = hi - nbytes;
      2: a = hi;
      3: a = lo - nbytes;
      4: a = lo + 64'($urandom_range(0, 64)) * 4;
      default: a = focus + 64'($urandom_range(0, 1 << 15)) - 64'(1 << 14);
    endcase
    a = a & ~64'(nbytes - 1);                 // naturally aligned: misaligned accesses trap before PMP
    return a & ((64'(1) << PAB) - 1);
  endfunction

  int unsigned seed = 1, checks = 0, errors = 0, partial_checks = 0, partial_errors = 0;
  int unsigned nconf = 400, per_conf = 250;
  initial begin
    if ($value$plusargs("SEED=%d", seed)) ;
    void'($urandom(seed));
    for (int c = 0; c < nconf; c++) begin
      randomize_cfg();
      for (int v = 0; v < per_conf; v++) begin
        int sz = $urandom_range(0, 3), nbytes = 1 << sz, kind = $urandom_range(0, 2);
        longint unsigned a;
        bit allowed, partial, fault;
        if (kind == 2) begin sz = 1; nbytes = 2; end      // fetch: 2-byte parcels (C)
        a = pick_addr(nbytes);
        Priv = 2'($urandom_range(0, 3)); if (Priv == 2'b10) Priv = 2'b11;
        PhysicalAddress = PAB'(a);
        Size = 2'(sz);
        Read = (kind == 0); Write = (kind == 1); Exec = (kind == 2);
        #1;
        fault = (kind == 0) ? FaultLd : (kind == 1) ? FaultSt : FaultF;
        allowed = model(a, nbytes, Priv, kind, partial);
        checks++;
        if (partial) partial_checks++;
        if (fault == allowed) begin
          if (partial) partial_errors++;
          errors++;
          if (errors <= 10) begin
            $display("MISMATCH cfg#%0d addr=%h size=%0d priv=%0d kind=%0d: dut fault=%0d, model allowed=%0d%s",
                     c, a, nbytes, Priv, kind, fault, allowed, partial ? " (partial match)" : "");
            for (int i = 0; i < N; i++) begin
              longint unsigned lo, hi;
              range_of(i, lo, hi);
              $display("    e%0d cfg=%h adr=%h [%h, %h)", i, Cfg[i], Adr[i], lo, hi);
            end
          end
        end
      end
    end
    $display("pmp_stress_tb: seed=%0d checks=%0d errors=%0d (partial-match checks=%0d, of which wrong=%0d)",
             seed, checks, errors, partial_checks, partial_errors);
    // pmpadrdec decides an access by its base address.  That is exact because
    // the grain (pkg/config.vh PMP_G) is at least as large as any aligned
    // access, so a legal configuration has no partially matching accesses:
    // every mismatch, partial or not, fails.
    if (errors != 0)
      $fatal(1, "pmp_stress_tb: %0d mismatches (%0d of them partial matches)", errors, partial_errors);
    $display("ALL TESTS PASSED");
    $finish;
  end
endmodule
