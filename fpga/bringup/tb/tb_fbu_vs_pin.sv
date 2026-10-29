///////////////////////////////////////////////////////////////////////////////
// tb_fbu_vs_pin.sv -- the bring-up gateware against the pin bench.
//
// forte_emu_dut (frozen forte_top with the FPGA's stand-ins) driven by
// fbu_link_slave, fbu_pin_ctl and fbu_uart.  The PS is modelled here: it
// interprets the pin bench's command language (+CMD, same commands and
// meaning as hvl/pin/pin_tb.sv) by setting the gateware's controls, and writes
// pin_trace.log and uart.log in the bench's formats.  Without +CMD it runs the
// bench's default flow.  fpga/bringup/tb/fbu_vs_pin.sh compares the results.
//
// Plusargs as the bench: +MEMLST +CMD +FPGA_SEED +FPGA_GAP_PCT +FPGA_RD_LAT
// +FPGA_MEM +FPGA_WDOG +FPGA_MUTATE +TOHOST +TIMEOUT +MAX_ERRORS +UART_DIV.
// Gateware-only: +NODET +MEM_LAT +TRACE +UART_LOG +BOOT_GATE
// +BOOT_GATE_SELFTEST +BOOT_GATE_RETRIES.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module tb_fbu_vs_pin;
  import forte_link_pkg::*;
  import fbu_pkg::*;

  localparam int BEATS       = 2;
  localparam int LINE_W      = 64 * BEATS;
  localparam int PRESCALE    = 1;
  localparam int MATCH_BYTES = 32;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  // ---- knobs ----
  int unsigned seed        = 1;
  int          gap_pct     = 0;
  int          rd_lat      = 0;
  int          wdog        = 1000;
  int          mutate      = 0;
  int          mem_lat     = 1;
  int          max_errors  = 1;
  longint      timeout     = 10_000_000;
  logic [63:0] tohost_addr = 64'h8080_0000;
  string       mem_policy  = "rand";
  string       trace_path  = "pin_trace.log";
  string       uart_path   = "uart.log";
  bit          det         = 1;

  // ---- PS-side controls ----
  logic        arst_n          = 1'b0;
  logic        prng_load       = 1'b0;
  logic [63:0] prng_init_v     = '0;
  logic        release_chip    = 1'b0;
  logic [1:0]  irq_level       = '0;
  logic        fault_level     = 1'b0;
  logic        pulse_start     = 1'b0;
  logic [31:0] pulse_cycles    = '0;
  logic        gate_enable     = 1'b0;
  logic        gate_selftest   = 1'b0;
  logic [3:0]  gate_retries    = 4'd2;
  logic [23:0] uart_bit_cycles = 24'(16 << PRESCALE);
  logic [7:0]  uart_gap_bits   = '0;
  logic        tx_push         = 1'b0;
  logic [9:0]  tx_entry        = '0;
  logic        rx_pop;

  logic [$clog2(MATCH_BYTES + 1)-1:0] match_len     [2] = '{default: '0};
  logic [8*MATCH_BYTES-1:0]           match_pattern [2] = '{default: '0};
  logic                               match_clear   [2] = '{default: 1'b0};
  logic                               match_hit     [2];
  logic                               match_pulse   [2];

  // ---- pins ----
  logic              rst_n;
  logic [1:0]        irq;
  logic              fault_inject, test_mode, scan_en, uart_rx, uart_rx_from_uart;
  logic [LINK_W-1:0] io_o, io_i;
  logic              io_oe, ready, rvalid;
  logic              dir, req, wr, clk_out, uart_tx, status;

  forte_emu_dut dut (
    .core_clk(clk), .rst_n,
    .fpga_io_o(io_o), .fpga_io_oe({LINK_W{io_oe}}), .fpga_io_i(io_i),
    .dir, .req, .wr, .clk_out, .uart_tx, .status,
    .ready, .rvalid, .irq, .uart_rx,
    .test_mode, .scan_en, .fault_inject);

  // ---- link slave ----
  logic              m_req_valid, m_req_ready, m_req_wr, m_rsp_valid;
  logic [31:0]       m_req_addr;
  logic [LINE_W-1:0] m_req_data, m_rsp_data;
  logic [63:0]       cyc, tohost_val, first_err_cyc, rec_cyc, rec_tohost_cyc, rec_tohost_val;
  logic [31:0]       n_rd, n_wr, err_now, err_sticky, err_count, rec_addr;
  logic [4:0]        first_err;
  logic              tohost_seen, rec_valid, rec_wr, rec_tohost;
  logic [LINE_W-1:0] rec_line;

  fbu_link_slave #(.BEATS(BEATS)) slave (
    .clk, .arst_n,
    .cfg_det(det), .cfg_gap_pct(7'(gap_pct)), .cfg_rd_lat(16'(rd_lat)), .cfg_wdog(16'(wdog)),
    .cfg_mem_base(32'h8000_0000), .cfg_mem_limit(32'h8FFF_FFFF), .cfg_reset_vec(32'h8000_0000),
    .cfg_tohost_addr(tohost_addr[31:0]), .cfg_mutate(2'(mutate)),
    .prng_load, .prng_init(prng_init_v),
    .rst_n_pin(rst_n), .dir, .req, .wr, .io_i, .io_o, .io_oe, .ready, .rvalid,
    .m_req_valid, .m_req_ready, .m_req_wr, .m_req_addr, .m_req_data,
    .m_rsp_valid, .m_rsp_data, .m_rsp_err(1'b0),
    .cyc, .n_rd, .n_wr, .tohost_seen, .tohost_val,
    .err_now, .err_sticky, .err_count, .first_err, .first_err_cyc,
    .rec_valid, .rec_cyc, .rec_wr, .rec_addr, .rec_line,
    .rec_tohost, .rec_tohost_cyc, .rec_tohost_val);

  // ---- pin control ----
  logic [31:0] reset_count;
  logic [63:0] cycles_total;
  logic [15:0] gate_passes, gate_fails;
  logic        gate_gave_up;
  logic [32:0] gate_last_header;

  fbu_pin_ctl pin_ctl (
    .clk, .arst_n,
    .cfg_release(release_chip), .cfg_irq(irq_level), .cfg_fault_inject(fault_level),
    .cfg_test_mode(1'b0), .cfg_scan_en(1'b0), .cfg_rx_force_en(1'b0), .cfg_rx_force_val(1'b1),
    .reset_pulse_start(pulse_start), .reset_pulse_cycles(pulse_cycles),
    .cfg_gate_enable(gate_enable), .cfg_gate_selftest(gate_selftest),
    .cfg_gate_retries(gate_retries), .cfg_gate_timeout(16'd1000),
    .req, .wr, .io_i, .uart_rx_from_uart,
    .rst_n, .irq, .fault_inject, .test_mode, .scan_en, .uart_rx,
    .reset_count, .cycles_total, .gate_passes, .gate_fails, .gate_gave_up, .gate_last_header);

  // ---- console ----
  logic [8:0]  rx_head;
  logic        rx_valid, rx_overflow, tx_full, tx_overflow, tx_busy;
  logic [31:0] n_uart_rx, n_uart_tx, n_framing_errors;

  fbu_uart #(.MATCH_BYTES(MATCH_BYTES)) uart (
    .clk, .arst_n, .clear(1'b0),
    .cfg_rx_bit_cycles(uart_bit_cycles), .cfg_tx_bit_period_q8({uart_bit_cycles, 8'd0}),
    .cfg_tx_gap_bits(uart_gap_bits),
    .uart_tx, .uart_rx(uart_rx_from_uart),
    .rx_head, .rx_valid, .rx_pop, .rx_level(), .rx_overflow,
    .tx_push, .tx_entry, .tx_full, .tx_overflow, .tx_level(), .tx_busy,
    .n_rx(n_uart_rx), .n_tx(n_uart_tx), .n_framing_errors,
    .cfg_match_len(match_len), .cfg_match_pattern(match_pattern),
    .match_clear, .match_hit, .match_pulse);

  // ---- link trace ----
  logic [319:0] trace_head;
  logic         trace_valid;
  logic         trace_pop;
  logic [11:0]  trace_level;
  logic [31:0]  trace_written, trace_dropped;
  logic         trace_overflow;

  fbu_link_trace #(.BEATS(BEATS)) trace (
    .clk, .arst_n, .clear(1'b0),
    .cfg_enable(1'b1), .cfg_stop_on_error(max_errors == 1),
    .link_cyc(cyc), .chip_in_reset(!rst_n),
    .rec_valid, .rec_cyc, .rec_wr, .rec_addr, .rec_line, .rec_tohost,
    .rec_end_cyc(rec_tohost_cyc), .rec_tohost_val, .err_now, .irq,
    .head(trace_head), .head_valid(trace_valid), .pop(trace_pop), .level(trace_level),
    .records_written(trace_written), .records_dropped(trace_dropped), .overflow(trace_overflow));

  // ---- behavioural line memory, as pin_link_agent's ----
  logic [63:0] mem [longint unsigned];

  function automatic logic [63:0] mix64(input logic [63:0] z);
    z = (z ^ (z >> 30)) * 64'hBF58_476D_1CE4_E5B9;
    z = (z ^ (z >> 27)) * 64'h94D0_49BB_1331_11EB;
    return z ^ (z >> 31);
  endfunction

  function automatic logic [63:0] mem_rd(input logic [63:0] a);
    longint unsigned k = a >> 3;
    if (mem.exists(k))
      return mem[k];
    if (mem_policy == "zero")
      return '0;
    return mix64(k ^ (64'(seed) << 40));
  endfunction

  function automatic int load_lst(input string path);
    int              fd;
    int              n = 0;
    longint unsigned k = 0;
    string           line;
    logic [63:0]     w;
    fd = $fopen(path, "r");
    if (fd == 0)
      return -1;
    while ($fgets(line, fd)) begin
      if (line.len() == 0 || line.getc(0) == "\n" || line.getc(0) == "/" || line.getc(0) == "#")
        continue;
      if (line.getc(0) == "@") begin
        void'($sscanf(line.substr(1, line.len() - 1), "%h", k));
      end else if ($sscanf(line, "%h", w) == 1) begin
        mem[k] = w;
        k++;
        n++;
      end
    end
    $fclose(fd);
    return n;
  endfunction

  assign m_req_ready = 1'b1;
  logic [LINE_W-1:0] rsp_pipe [$];
  int                rsp_due  [$];
  int                now = 0;

  always @(posedge clk) begin
    now++;
    m_rsp_valid <= 1'b0;
    if (rsp_due.size() != 0 && rsp_due[0] <= now) begin
      m_rsp_valid <= 1'b1;
      m_rsp_data  <= rsp_pipe.pop_front();
      void'(rsp_due.pop_front());
    end
    if (m_req_valid && m_req_ready) begin
      if (m_req_wr) begin
        for (int b = 0; b < BEATS; b++)
          mem[(64'(m_req_addr) >> 3) + b] = m_req_data[64 * b +: 64];
      end else begin
        logic [LINE_W-1:0] l;
        for (int b = 0; b < BEATS; b++)
          l[64 * b +: 64] = mem_rd(64'(m_req_addr) + 64'(8 * b));
        rsp_pipe.push_back(l);
        rsp_due.push_back(now + mem_lat);
      end
    end
  end

  // ---- errors, trace and console log ----
  // Link errors stop the trace inside fbu_link_trace.  Errors only this
  // testbench sees (console, exit code) stop it here, the same way.
  int     trace_fd;
  int     uart_fd;
  bit     finished    = 0;
  longint stop_cyc    = -1;
  longint tb_stop_cyc = -1;
  int     link_errors = 0;
  int     tb_errors   = 0;

  function automatic int total_errors();
    return link_errors + tb_errors;
  endfunction

  function automatic void tb_err(input string m);
    tb_errors++;
    $display("[FBU_TB] ERROR cyc %0d: %s", cyc, m);
    if (total_errors() >= max_errors && stop_cyc < 0) begin
      stop_cyc    = longint'(cyc) + 1;
      tb_stop_cyc = stop_cyc;
    end
  endfunction

  always @(posedge clk) begin
    if (!finished && err_now != '0 && stop_cyc < 0) begin
      link_errors += $countones(err_now);
      if (total_errors() >= max_errors)
        stop_cyc = longint'(cyc) + 1;
    end
  end

  function automatic void write_record(input logic [319:0] r);
    logic [3:0]  kind;
    logic [63:0] at;
    logic [63:0] end_at;
    string       s;
    kind   = r[31:28];
    at     = r[95:32];
    end_at = r[319:256];
    case (kind)
      4'd1: begin
        if (tb_stop_cyc >= 0 && longint'(end_at) > tb_stop_cyc)
          return;
        s = "";
        for (int b = 0; b < BEATS; b++)
          s = {s, $sformatf(" %016h", r[128 + 64 * b +: 64])};
        $fdisplay(trace_fd, "L %0d %s %08h%s", at, r[27] ? "W" : "R", r[127:96], s);
      end
      4'd2: begin
        if (tb_stop_cyc >= 0 && longint'(at) > tb_stop_cyc)
          return;
        $fdisplay(trace_fd, "T %0d %016h", at, r[191:128]);
      end
      4'd3: begin
        for (int i = 1; i < 32; i++) begin
          if (r[96 + i]) begin
            link_err_t e = link_err_t'(i);
            $fdisplay(trace_fd, "E %0d %s", at, e.name());
          end
        end
      end
      4'd4: $fdisplay(trace_fd, "I %0d %0d %0d", at, r[25:24], r[23]);
      default: $display("[FBU_TB] ERROR: trace record of unknown kind %0d", kind);
    endcase
  endfunction

  assign trace_pop = trace_valid;

  always @(posedge clk) begin
    if (trace_valid && !finished)
      write_record(trace_head);
  end

  assign rx_pop = rx_valid;

  always @(posedge clk) begin
    if (rx_valid && !finished) begin
      if (rx_head[8])
        tb_err($sformatf("framing error on uart_tx (byte %02h)", rx_head[7:0]));
      else
        $fwrite(uart_fd, "%c", rx_head[7:0]);
    end
    if (match_pulse[1] && !finished)
      tb_err("console printed the fail pattern");
  end

  // ---- the PS model ----
  task automatic cycles(input longint n);
    repeat (n) @(posedge clk);
  endtask

  task automatic set_match(input int m, input string text);
    match_len[m]     <= '0;
    match_pattern[m] <= '0;
    @(posedge clk);
    for (int i = 0; i < text.len() && i < MATCH_BYTES; i++)
      match_pattern[m][8 * i +: 8] <= text.getc(text.len() - 1 - i);
    match_len[m]   <= ($clog2(MATCH_BYTES + 1))'(text.len());
    match_clear[m] <= 1'b1;
    @(posedge clk);
    match_clear[m] <= 1'b0;
  endtask

  task automatic send_entry(input logic [1:0] kind, input logic [7:0] data);
    while (tx_full)
      @(posedge clk);
    tx_entry <= {kind, data};
    tx_push  <= 1'b1;
    @(posedge clk);
    tx_push  <= 1'b0;
  endtask

  task automatic do_reset(input longint n);
    pulse_cycles <= 32'(n + 1);
    pulse_start  <= 1'b1;
    release_chip <= 1'b1;
    @(posedge clk);
    pulse_start  <= 1'b0;
    cycles(n + 1);
  endtask

  function automatic string rest_after(input string s, input int n);
    int i = 0;
    for (int w = 0; w < n; w++) begin
      while (i < s.len() && (s.getc(i) == " " || s.getc(i) == "\t"))
        i++;
      while (i < s.len() && !(s.getc(i) == " " || s.getc(i) == "\t"))
        i++;
    end
    while (i < s.len() && (s.getc(i) == " " || s.getc(i) == "\t"))
      i++;
    return (i < s.len()) ? s.substr(i, s.len() - 1) : "";
  endfunction

  function automatic string chomp(input string s);
    while (s.len() != 0 && (s.getc(s.len() - 1) == "\n" || s.getc(s.len() - 1) == "\r"))
      s = s.substr(0, s.len() - 2);
    return s;
  endfunction

  function automatic string unescape(input string s);
    string o = "";
    for (int i = 0; i < s.len(); i++) begin
      if (s.getc(i) == "\\" && i + 1 < s.len()) begin
        i++;
        case (s.getc(i))
          "n":     o = {o, "\n"};
          "r":     o = {o, "\r"};
          default: o = {o, $sformatf("%c", s.getc(i))};
        endcase
      end else begin
        o = {o, $sformatf("%c", s.getc(i))};
      end
    end
    return o;
  endfunction

  bit    done       = 0;
  int    exit_code  = -1;
  bit    have_fail_pattern = 0;

  task automatic verdict(input bit pass, input string why);
    link_err_t fe;
    if (done)
      return;
    done = 1;
    repeat (4) @(posedge clk);
    for (int i = 0; i < 100 && trace_valid; i++)
      @(posedge clk);
    finished = 1;
    $fclose(trace_fd);
    $fclose(uart_fd);
    fe = link_err_t'(first_err);
    $display("[FBU_TB] cycles=%0d link_rd=%0d link_wr=%0d uart_rx=%0d uart_tx=%0d errors=%0d first=%s@%0d",
             cyc, n_rd, n_wr, n_uart_rx, n_uart_tx, total_errors(), fe.name(), first_err_cyc);
    $display("[FBU_TB] trace written=%0d dropped=%0d overflow=%0d", trace_written, trace_dropped, trace_overflow);
    $display("[FBU_TB] gate passes=%0d fails=%0d gave_up=%0d last_header=%09h resets=%0d",
             gate_passes, gate_fails, gate_gave_up, gate_last_header, reset_count);
    if (pass && total_errors() == 0)
      $display("PIN_TB_RESULT: PASS");
    else if (!pass)
      $display("PIN_TB_RESULT: FAIL %s", why);
    else
      $display("PIN_TB_RESULT: FAIL %0d checker errors", total_errors());
    $finish;
  endtask

  task automatic check_stop();
    if (stop_cyc >= 0)
      verdict(0, $sformatf("%0d checker errors", total_errors()));
  endtask

  task automatic exec(input string raw, input int lineno);
    string       ln;
    string       cmd;
    string       a1;
    string       a2;
    string       a3;
    int          n;
    longint      t;
    longint      v;
    ln = chomp(raw);
    n  = $sscanf(ln, "%s %s %s %s", cmd, a1, a2, a3);
    if (n < 1 || cmd.getc(0) == "#")
      return;
    $display("[FBU_TB] cmd %0d: %s", lineno, ln);
    case (cmd)
      "mem_policy": begin
        if (a1 != "rand" && a1 != "zero")
          tb_err($sformatf("mem_policy %s: hardware has rand or zero only", a1));
        mem_policy = a1;
      end
      "load_lst": begin
        n = load_lst(a1);
        if (n <= 0)
          tb_err($sformatf("load_lst %s failed", a1));
        else
          $display("[FBU_TB] loaded %0d words from %s", n, a1);
      end
      "reset": begin
        void'($sscanf(a1, "%d", t));
        exit_code = -1;
        do_reset(t);
      end
      "run": begin
        void'($sscanf(a1, "%d", t));
        for (v = 0; v < t && stop_cyc < 0; v++)
          @(posedge clk);
      end
      "run_until_tohost": begin
        void'($sscanf(a1, "%d", t));
        for (v = 0; v < t && !tohost_seen && stop_cyc < 0; v++)
          @(posedge clk);
        check_stop();
        if (!tohost_seen)
          verdict(0, $sformatf("timeout: no tohost write in %0d cycles", t));
        exit_code = int'(tohost_val >> 1);
        $display("[FBU_TB] tohost = %h (exit code %0d) after %0d cycles", tohost_val, exit_code, v);
        if (tohost_val[0] !== 1'b1)
          tb_err($sformatf("tohost %h has bit 0 clear", tohost_val));
      end
      "run_until_uart": begin
        string want;
        void'($sscanf(a1, "%d", t));
        want = unescape(rest_after(ln, 2));
        set_match(0, want);
        for (v = 0; v < t && !match_hit[0] && stop_cyc < 0; v++)
          @(posedge clk);
        check_stop();
        if (!match_hit[0])
          verdict(0, $sformatf("timeout: console never printed \"%s\" in %0d cycles", want, t));
        $display("[FBU_TB] console printed \"%s\" after %0d cycles", want, v);
      end
      "expect_tohost": begin
        void'($sscanf(a1, "%d", v));
        if (exit_code != int'(v))
          tb_err($sformatf("exit code %0d, expected %0d", exit_code, v));
      end
      "uart_div": begin
        void'($sscanf(a1, "%d", v));
        uart_bit_cycles <= 24'(16 * (v << PRESCALE));
        @(posedge clk);
      end
      "uart_send": begin
        string text;
        text = unescape(rest_after(ln, 1));
        for (int i = 0; i < text.len(); i++)
          send_entry(2'd0, text.getc(i));
      end
      "uart_send_ferr": begin
        void'($sscanf(a1, "%h", v));
        send_entry(2'd1, 8'(v));
      end
      "uart_gap": begin
        void'($sscanf(a1, "%d", v));
        uart_gap_bits <= 8'(v);
        @(posedge clk);
      end
      "uart_fail": begin
        if (have_fail_pattern)
          tb_err("uart_fail: the gateware matches one fail pattern");
        have_fail_pattern = 1;
        set_match(1, unescape(rest_after(ln, 1)));
      end
      "irq": begin
        void'($sscanf(a1, "%d", v));
        void'($sscanf(a2, "%d", t));
        irq_level[v] <= t[0];
        @(posedge clk);
      end
      "fault_inject": begin
        void'($sscanf(a1, "%d", v));
        fault_level <= v[0];
        @(posedge clk);
      end
      "dump_mem": begin
        logic [63:0] base;
        int          fd;
        void'($sscanf(a1, "%h", base));
        void'($sscanf(a2, "%d", v));
        fd = $fopen(a3, "w");
        for (longint i = 0; i < v; i += 8)
          $fdisplay(fd, "%016h %016h", base + 64'(i), mem_rd(base + 64'(i)));
        $fclose(fd);
      end
      "finish": verdict(1, "");
      default:  tb_err($sformatf("line %0d: unknown command '%s'", lineno, cmd));
    endcase
  endtask

  initial begin
    int    v;
    string s;
    string memlst;
    string cmd_path;
    string line;
    int    fd;
    int    lineno = 0;

    if ($value$plusargs("FPGA_SEED=%d", v))    seed = v;
    if ($value$plusargs("FPGA_GAP_PCT=%d", v)) gap_pct = v;
    if ($value$plusargs("FPGA_RD_LAT=%d", v))  rd_lat = v;
    if ($value$plusargs("FPGA_WDOG=%d", v))    wdog = v;
    if ($value$plusargs("FPGA_MUTATE=%d", v))  mutate = v;
    if ($value$plusargs("FPGA_MEM=%s", s))     mem_policy = s;
    if ($value$plusargs("MEM_LAT=%d", v))      mem_lat = v;
    if ($value$plusargs("MAX_ERRORS=%d", v))   max_errors = v;
    if ($value$plusargs("UART_DIV=%d", v))     uart_bit_cycles = 24'(16 * (v << PRESCALE));
    if ($value$plusargs("TOHOST=%h", tohost_addr)) ;
    if ($value$plusargs("TIMEOUT=%d", timeout)) ;
    if ($value$plusargs("TRACE=%s", s))        trace_path = s;
    if ($value$plusargs("UART_LOG=%s", s))     uart_path = s;
    if ($test$plusargs("NODET"))               det = 0;
    if ($test$plusargs("BOOT_GATE"))           gate_enable = 1'b1;
    if ($test$plusargs("BOOT_GATE_SELFTEST"))  gate_selftest = 1'b1;
    if ($value$plusargs("BOOT_GATE_RETRIES=%d", v)) gate_retries = 4'(v);
    trace_fd = $fopen(trace_path, "w");
    uart_fd  = $fopen(uart_path, "w");

    prng_init_v = prng_seed_state(seed);
    cycles(2);
    arst_n <= 1'b1;
    @(posedge clk);
    prng_load <= 1'b1;
    @(posedge clk);
    prng_load <= 1'b0;
    $display("[FBU_TB] seed %0d gap %0d%% rd_lat %0d mem_lat %0d %s%s",
             seed, gap_pct, rd_lat, mem_lat, det ? "DET" : "natural",
             gate_enable ? (gate_selftest ? " boot-gate-selftest" : " boot-gate") : "");

    if ($value$plusargs("CMD=%s", cmd_path)) begin
      fd = $fopen(cmd_path, "r");
      if (fd == 0)
        verdict(0, $sformatf("cannot open command script %s", cmd_path));
      while ($fgets(line, fd)) begin
        lineno++;
        exec(line, lineno);
        check_stop();
        if (done)
          break;
      end
      $fclose(fd);
    end else begin
      if (!$value$plusargs("MEMLST=%s", memlst))
        verdict(0, "neither +CMD nor +MEMLST given");
      exec({"load_lst ", memlst}, 1);
      exec("reset 16", 2);
      exec($sformatf("run_until_tohost %0d", timeout), 3);
      exec("expect_tohost 0", 4);
    end
    verdict(1, "");
  end

endmodule
