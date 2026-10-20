///////////////////////////////////////////////////////////////////////////////
// pin_link_agent.sv
//
// The FPGA, as far as the chip's link pins can tell: the off-chip memory and
// the far end of hdl/forte_link_pkg.sv's protocol.  It is the simulation twin
// of the bring-up FPGA's link slave, and it touches PINS ONLY, so the same
// source drives the RTL forte_top and the synthesized netlist.
//
// TIMING.  Behavioural, on two clocks, the way the board sees them:
//   launch   FPGA outputs (io, ready, rvalid) change TCO after the core_clk
//            posedge.  The chip captures inbound pins on the link_clk NEGEDGE
//            (forte_link_phy), so TCO must stay below half a period.
//   capture  chip outputs (dir, req, wr, io) are sampled SAMPLE after the
//            clk_out posedge.  clk_out is the forwarded link clock, so in an
//            SDF run this tracks the chip's own insertion delay, as on the board.
// Sampling mid-cycle and launching after the edge is race-free in RTL, in a
// zero-delay netlist and with back-annotated delays alike, so an RTL run and a
// netlist run see the same cycle on every pin and their traces are comparable.
//
// RANDOMNESS is a private xorshift, not $urandom: $urandom is seeded per
// thread and its generator differs between simulators, and a Verilator run, a
// VCS RTL run and a VCS netlist run must make identical choices from one seed.
//
// MEMORY.  Sparse 64-bit words keyed by word index.  Never-written words read
// back per mem_policy: "x" (4-state stress -- garbage on the bus is X, not a
// value that happens to work), "zero", or "rand" (seeded; what DRAM looks like).
//
// CHECKS (pin level only).  No X/Z on dir/req/wr; no X/Z on io while the chip
// owns it inside a transaction; req only with dir=1, exactly ADDR_WORDS cycles,
// never mid-transaction; wr held; no contention (the agent never drives while
// dir=1); TA honoured after the last rvalid; every address inside EXT_MEM and
// line-aligned; the first transaction after reset is a read of RESET_VECTOR;
// a req arriving more than GUARD cycles after ready fell is a protocol error.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module pin_link_agent import forte_link_pkg::*; #(
  parameter int          BEATS      = 2,
  parameter logic [31:0] MEM_BASE   = 32'h8000_0000,
  parameter logic [31:0] MEM_LIMIT  = 32'h8FFF_FFFF,
  parameter logic [31:0] RESET_VEC  = 32'h8000_0000
)(
  input  logic              core_clk,
  input  logic              clk_out,
  input  logic              rst_n,           // the pin the agent itself drives (via the tb)
  inout  wire  [LINK_W-1:0] io,
  input  wire               dir,
  input  wire               req,
  input  wire               wr,
  output logic              ready,
  output logic              rvalid
);

  localparam int WORDS     = 4 * BEATS;      // 16-bit words per transaction
  localparam int LINE_B    = 8 * BEATS;      // bytes per line
  localparam int GUARD     = 3;              // see "the ready guard band", forte_link_pkg

  // ---- knobs (plusargs, overridable by tb commands) -----------------------
  real         tco_ns     = 2.0;             // +FPGA_TCO_PS
  real         sample_ns  = 5.0;             // +FPGA_SAMPLE_PS
  int          rd_latency = 0;               // extra cycles before the first word
  int          gap_pct    = 0;               // % of cycles ready/rvalid withheld
  string       idle_drive = "z";             // io when not validly driving: z|x
  string       mem_policy = "rand";
  int unsigned seed       = 1;
  logic [63:0] tohost_addr = 64'h8080_0000;
  string       trace_path = "pin_trace.log";
  int          mutate     = 0;               // +FPGA_MUTATE: harness self-test only
  bit          x_in_reset = 0;               // +FPGA_X_IN_RESET
  int          wdog_cyc   = 1000;            // +FPGA_WDOG: link cycles per transaction

  // ---- state visible to the tb --------------------------------------------
  int          errors     = 0;
  string       last_err   = "";
  string       first_err  = "";
  longint      cyc        = 0;               // link cycles since rst_n release
  longint      n_rd = 0, n_wr = 0;
  bit          tohost_seen = 0;
  logic [63:0] tohost_val  = '0;
  int          trace_fd   = 0;

  // ---- memory --------------------------------------------------------------
  logic [63:0] mem [longint unsigned];

  logic [63:0] prng = 64'h9E37_79B9_7F4A_7C15;
  function automatic logic [63:0] rand64();
    prng ^= prng << 13;
    prng ^= prng >> 7;
    prng ^= prng << 17;
    return prng;
  endfunction

  // splitmix64 finaliser: uninitialised memory is a function of (address,
  // seed) only, so it does not shift when an unrelated random choice changes.
  function automatic logic [63:0] mix64(input logic [63:0] z);
    z = (z ^ (z >> 30)) * 64'hBF58_476D_1CE4_E5B9;
    z = (z ^ (z >> 27)) * 64'h94D0_49BB_1331_11EB;
    return z ^ (z >> 31);
  endfunction

  function automatic logic [63:0] mem_rd(input logic [63:0] a);
    longint unsigned k = a >> 3;
    if (mem.exists(k)) return mem[k];
    case (mem_policy)
      "zero":  return '0;
      "x":     return 'x;
      default: return mix64(k ^ (64'(seed) << 40));              // a pure function of address and seed
    endcase
  endfunction

  function automatic void mem_wr(input logic [63:0] a, input logic [63:0] d, input logic [7:0] be);
    longint unsigned k = a >> 3;
    logic [63:0] w = (be == 8'hFF) ? '0 : mem_rd(a);
    for (int i = 0; i < 8; i++) if (be[i]) w[8*i +: 8] = d[8*i +: 8];
    mem[k] = w;
  endfunction

  // Byte-level helpers for the tb's loaders and dumps.
  function automatic void mem_wr_byte(input logic [63:0] a, input logic [7:0] b);
    mem_wr({a[63:3], 3'b000}, {8{b}}, 8'h01 << a[2:0]);
  endfunction
  function automatic logic [7:0] mem_rd_byte(input logic [63:0] a);
    logic [63:0] w = mem_rd(a);
    return w[8*a[2:0] +: 8];
  endfunction

  // .lst as written by bin/generate_memory_file.py -8: "@<word index>" lines
  // and one 64-bit hex word per line.  Returns the word count, -1 on error.
  function automatic int load_lst(input string path);
    int fd, n = 0;
    longint unsigned k = 0;
    string line;
    logic [63:0] w;
    fd = $fopen(path, "r");
    if (fd == 0) return -1;
    while ($fgets(line, fd)) begin
      if (line.len() == 0 || line.getc(0) == "\n" || line.getc(0) == "/" || line.getc(0) == "#") continue;
      if (line.getc(0) == "@") begin
        void'($sscanf(line.substr(1, line.len() - 1), "%h", k));
      end else if ($sscanf(line, "%h", w) == 1) begin
        mem[k] = w; k++; n++;
      end
    end
    $fclose(fd);
    return n;
  endfunction

  // Raw binary at a byte address.  Returns the byte count, -1 on error.
  function automatic int load_bin(input string path, input logic [63:0] base);
    int fd, c, n = 0;
    fd = $fopen(path, "rb");
    if (fd == 0) return -1;
    c = $fgetc(fd);
    while (c != -1) begin
      mem_wr_byte(base + 64'(n), 8'(c));
      n++;
      c = $fgetc(fd);
    end
    $fclose(fd);
    return n;
  endfunction

  function automatic int dump(input logic [63:0] base, input int nbytes, input string path);
    int fd = $fopen(path, "w");
    if (fd == 0) return -1;
    for (int i = 0; i < nbytes; i += 8) $fdisplay(fd, "%016h %016h", base + 64'(i), mem_rd(base + 64'(i)));
    $fclose(fd);
    return 0;
  endfunction

  // ---- error reporting -----------------------------------------------------
  function automatic void err(input string m);
    errors++;
    if (errors == 1) first_err = m;
    last_err = m;
    $display("[FPGA-LINK] ERROR @%0t cyc %0d: %s", $realtime, cyc, m);
    if (trace_fd) $fdisplay(trace_fd, "E %0d %s", cyc, m);
  endfunction

  // ---- pin drivers ---------------------------------------------------------
  logic [LINK_W-1:0] io_val;
  logic              io_en;
  logic              idle_x = 1'b0;        // idle_drive == "x", as a plain bit for the assign
  // FPGA_IO_IDLE=x drives X only while the chip has RELEASED the bus (dir=0)
  // and no read word is being returned -- garbage on a floating bus.  While
  // dir=1 the chip owns io and the FPGA must not drive it at all; driving X
  // there would be contention, not a model of anything on the board.
  assign io = io_en ? io_val : ((idle_x && dir === 1'b0) ? {LINK_W{1'bx}} : {LINK_W{1'bz}});

  initial begin
    int v;
    string s;
    if ($value$plusargs("FPGA_TCO_PS=%d", v))     tco_ns    = v / 1000.0;
    if ($value$plusargs("FPGA_SAMPLE_PS=%d", v))  sample_ns = v / 1000.0;
    if ($value$plusargs("FPGA_RD_LAT=%d", v))     rd_latency = v;
    if ($value$plusargs("FPGA_GAP_PCT=%d", v))    gap_pct   = v;
    if ($value$plusargs("FPGA_SEED=%d", v))       seed      = v;
    if ($value$plusargs("FPGA_IO_IDLE=%s", s))    idle_drive = s;
    idle_x = (idle_drive == "x");
    if ($value$plusargs("FPGA_MEM=%s", s))        mem_policy = s;
    if ($value$plusargs("FPGA_TRACE=%s", s))      trace_path = s;
    if ($value$plusargs("FPGA_MUTATE=%d", v))     mutate    = v;
    if ($test$plusargs("FPGA_X_IN_RESET"))        x_in_reset = 1;
    if ($value$plusargs("FPGA_WDOG=%d", v))       wdog_cyc  = v;
    if ($value$plusargs("TOHOST=%h", tohost_addr)) ;
    prng ^= 64'(seed) * 64'h2545_F491_4F6C_DD1D;
    if (prng == 0) prng = 64'h1;
    io_en = 1'b0; io_val = '0; ready = 1'b0; rvalid = 1'b0;
    trace_fd = $fopen(trace_path, "w");
    if (trace_fd == 0) $display("[FPGA-LINK] WARNING: cannot open trace %s", trace_path);
  end

  // ---- the agent -----------------------------------------------------------
  // Each sampler iteration is one link cycle: sample what the chip launched on
  // this clk_out edge and decide; the launcher drives the decision TCO after
  // the next core_clk edge.
  typedef enum {A_IDLE, A_HDR, A_WDATA, A_RD_TA, A_RD_LAT, A_RD_DATA, A_RD_REL} st_t;
  st_t         st;
  int          hdr_n, wcnt, ta_cnt, lat_cnt, rel_cnt, notready_cnt;
  logic [31:0] addr;
  logic        twr;
  logic [15:0] hdr_hi;
  logic [63:0] line_w[];               // beats of the current transaction
  bit          first_xact;
  longint      xact_start;
  string       words_s;

  function automatic bit unk(input logic [LINK_W-1:0] v); return $isunknown(v); endfunction

  task automatic finish_xact();
    string s = "";
    for (int b = 0; b < BEATS; b++) s = {s, $sformatf(" %016h", line_w[b])};
    if (trace_fd) $fdisplay(trace_fd, "L %0d %s %08h%s", xact_start, twr ? "W" : "R", addr, s);
    if (twr) n_wr++; else n_rd++;
  endtask

  // Next values of the agent's outputs: decided by the sampler, launched by
  // the launcher.  Two processes, because one loop waiting on both clocks in
  // turn would consume an edge of each and sample only every other cycle.
  logic n_ready = 1'b0, n_rvalid = 1'b0, n_en = 1'b0;
  logic [LINK_W-1:0] n_val = '0;

  initial begin : launcher
    forever begin
      @(posedge core_clk);
      #(tco_ns);
      ready = n_ready; rvalid = n_rvalid; io_en = n_en; io_val = n_val;
    end
  end

  initial begin : sampler
    logic s_dir, s_req, s_wr;
    logic [LINK_W-1:0] s_io;
    bit gap;
    line_w = new[BEATS];
    st = A_IDLE; first_xact = 1; notready_cnt = 0;
    forever begin
      @(posedge clk_out);
      #(sample_ns);
      s_dir = dir; s_req = req; s_wr = wr; s_io = io;

      n_rvalid = 1'b0; n_en = 1'b0;

      if (rst_n !== 1'b1) begin   // X (power-up) counts as in reset
        // +FPGA_X_IN_RESET: reset must dominate whatever the board does to
        // the inputs before it releases rst_n -- a 4-state-only question.
        st = A_IDLE; cyc = 0; first_xact = 1; notready_cnt = 0;
        n_ready  = x_in_reset ? 1'bx : 1'b0;
        n_rvalid = x_in_reset ? 1'bx : 1'b0;
      end else begin
        cyc++;
        gap = (gap_pct > 0) && ((rand64() % 100) < 64'(gap_pct));

        // -- always-on pin checks --------------------------------------------
        if ($isunknown({s_dir, s_req, s_wr})) err($sformatf("X/Z on dir/req/wr = %b%b%b", s_dir, s_req, s_wr));
        if (s_req && !s_dir) err("req while dir=0");
        if (io_en && s_dir === 1'b1) err("contention: agent driving io while dir=1");
        if (io_en && s_io !== io_val) err($sformatf("io resolves to %h while agent drives %h", s_io, io_val));
        notready_cnt = ready ? 0 : notready_cnt + 1;

        // Watchdog (the FPGA's WDOG): a transaction that has not finished in
        // WDOG_CYC link cycles is a hang -- e.g. dir never falls for a read.
        // Reported once per transaction, the moment it happens, instead of
        // after the whole run's timeout.
        if (st != A_IDLE && cyc - xact_start == longint'(wdog_cyc))
          err($sformatf("watchdog: %s %08h started at cycle %0d has not finished (state %s)",
                        twr ? "write" : "read", addr, xact_start, st.name()));

        case (st)
          A_IDLE: begin
            if (s_req === 1'b1) begin
              if (notready_cnt > GUARD) err($sformatf("req %0d cycles after ready fell (guard band %0d)", notready_cnt, GUARD));
              if (unk(s_io)) err($sformatf("X/Z on io in header word 0: %h", s_io));
              hdr_hi = s_io; twr = s_wr; xact_start = cyc; st = A_HDR;
            end
          end
          A_HDR: begin
            if (s_req !== 1'b1) err("req dropped after one header word");
            if (s_wr !== twr) err("wr changed inside the header");
            if (unk(s_io)) err($sformatf("X/Z on io in header word 1: %h", s_io));
            addr = {hdr_hi, s_io};
            if (addr < MEM_BASE || addr > MEM_LIMIT) err($sformatf("address %08h outside EXT_MEM", addr));
            if (addr % LINE_B != 0) err($sformatf("address %08h not line-aligned", addr));
            if (first_xact && (twr || addr != RESET_VEC))
              err($sformatf("first transaction is %s %08h, expected read of %08h", twr ? "write" : "read", addr, RESET_VEC));
            first_xact = 0;
            wcnt = 0;
            if (twr) st = A_WDATA;
            else begin
              for (int b = 0; b < BEATS; b++) line_w[b] = mem_rd({32'b0, addr} + 64'(8 * b));
              if (mutate == 1 && n_rd == 0) line_w[0] = ~line_w[0];   // self-test: corrupt the reset-vector fetch
              ta_cnt = 0; st = A_RD_TA;
            end
            n_ready = 1'b0;
          end
          A_WDATA: begin
            if (s_req === 1'b1) err("req during write data");
            if (s_dir !== 1'b1) err("dir fell during write data");
            if (s_wr !== 1'b1) err("wr dropped during write data");
            if (unk(s_io)) err($sformatf("X/Z on io in write word %0d of %08h: %h", wcnt, addr, s_io));
            line_w[wcnt / 4][16 * (wcnt % 4) +: 16] = s_io;
            wcnt++;
            if (wcnt == WORDS) begin
              for (int b = 0; b < BEATS; b++) mem_wr({32'b0, addr} + 64'(8 * b), line_w[b], 8'hFF);
              if (tohost_addr >= addr && tohost_addr < addr + LINE_B) begin
                tohost_val = line_w[(tohost_addr - addr) / 8];
                if (mutate == 2) tohost_val = 64'd3;                         // self-test: wrong exit code
                if (tohost_val != 0) begin
                  tohost_seen = 1;
                  if (trace_fd) $fdisplay(trace_fd, "T %0d %016h", cyc, tohost_val);
                end
              end
              finish_xact();
              st = A_IDLE;
            end
          end
          A_RD_TA: begin
            if (s_req === 1'b1) err("req during read turnaround");
            if (s_dir === 1'b0) ta_cnt++; else ta_cnt = 0;
            if (ta_cnt >= TA) begin lat_cnt = rd_latency; st = (rd_latency > 0) ? A_RD_LAT : A_RD_DATA; end
          end
          A_RD_LAT: begin
            if (s_dir !== 1'b0) err("dir rose during read latency");
            lat_cnt = lat_cnt - 1;
            if (lat_cnt == 0) st = A_RD_DATA;
          end
          A_RD_DATA: begin
            if (s_dir !== 1'b0) err("dir rose during read data");
            if (s_req === 1'b1) err("req during read data");
            if (!gap && !(mutate == 3 && n_rd == 10 && wcnt == WORDS - 1)) begin   // 3: drop a word
              n_en = 1'b1; n_rvalid = 1'b1;
              n_val = line_w[wcnt / 4][16 * (wcnt % 4) +: 16];
              wcnt++;
              if (wcnt == WORDS) begin finish_xact(); rel_cnt = 0; st = A_RD_REL; end
            end
          end
          A_RD_REL: begin
            // TA after the last rvalid before the chip may take the bus back.
            rel_cnt++;
            if (s_dir === 1'b1 && rel_cnt <= TA) err($sformatf("dir rose %0d cycles after last rvalid (TA=%0d)", rel_cnt, TA));
            if (rel_cnt >= TA) st = A_IDLE;
          end
        endcase

        if (st == A_IDLE && s_req !== 1'b1) n_ready = !gap;
        else if (st != A_IDLE) n_ready = 1'b0;
      end
    end
  end

  final if (trace_fd) $fclose(trace_fd);

endmodule
