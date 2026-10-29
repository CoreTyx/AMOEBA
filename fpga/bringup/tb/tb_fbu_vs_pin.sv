///////////////////////////////////////////////////////////////////////////////
// tb_fbu_vs_pin.sv -- the bring-up gateware against the pin bench.
//
// forte_emu_dut (frozen forte_top with the FPGA's stand-ins) driven by fbu_top,
// with a behavioural line memory behind it.  The PS is modelled here and
// touches fbu_top only through its AXI4-Lite registers, polling in one loop as
// sw/forte does: it interprets the pin bench's command language (+CMD, same
// commands and meaning as hvl/pin/pin_tb.sv), drains the link trace and the
// console, and writes pin_trace.log and uart.log in the bench's formats.
// Without +CMD it runs the bench's default flow.  fbu_vs_pin.sh compares.
//
// Plusargs as the bench: +MEMLST +CMD +FPGA_SEED +FPGA_GAP_PCT +FPGA_RD_LAT
// +FPGA_MEM +FPGA_WDOG +FPGA_MUTATE +TOHOST +TIMEOUT +MAX_ERRORS +UART_DIV.
// Gateware-only: +NODET +MEM_LAT +TRACE +UART_LOG +BOOT_GATE
// +BOOT_GATE_SELFTEST +BOOT_GATE_RETRIES.
//
// Built with BOARD_TOP, the design is the PYNQ PL top (forte_pynq_top: the
// same fbu_top with the block-RAM memory) and the PS loads every image through
// the memory's AXI4-Lite port, after filling its windows with the bench's
// unwritten-memory pattern, as sw/forte does.
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
  bit          gate_enable   = 0;
  bit          gate_selftest = 0;
  int          gate_retries  = 2;

  // ---- AXI4-Lite, driven by the PS model; bus_to_mem picks the memory port ----
  logic        arst_n  = 1'b0;
  bit          bus_to_mem = 0;
  logic [19:0] awaddr  = '0;
  logic        awvalid = 1'b0;
  logic        awready;
  logic [31:0] wdata   = '0;
  logic [3:0]  wstrb   = 4'hF;
  logic        wvalid  = 1'b0;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready  = 1'b0;
  logic [19:0] araddr  = '0;
  logic        arvalid = 1'b0;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready  = 1'b0;

  // ---- pins ----
  logic              rst_n;
  logic [1:0]        irq;
  logic              fault_inject, test_mode, scan_en, uart_rx;
  logic [LINK_W-1:0] io_o, io_oe, io_i;
  logic              ready, rvalid_pin;
  logic              dir, req, wr, clk_out, uart_tx, status;

`ifdef BOARD_TOP
  logic        ctl_awready, ctl_wready, ctl_bvalid, ctl_arready, ctl_rvalid;
  logic        mem_awready, mem_wready, mem_bvalid, mem_arready, mem_rvalid;
  logic [1:0]  ctl_bresp, ctl_rresp, mem_bresp, mem_rresp;
  logic [31:0] ctl_rdata, mem_rdata;
  logic [3:0]  led;

  assign awready = bus_to_mem ? mem_awready : ctl_awready;
  assign wready  = bus_to_mem ? mem_wready  : ctl_wready;
  assign bvalid  = bus_to_mem ? mem_bvalid  : ctl_bvalid;
  assign bresp   = bus_to_mem ? mem_bresp   : ctl_bresp;
  assign arready = bus_to_mem ? mem_arready : ctl_arready;
  assign rvalid  = bus_to_mem ? mem_rvalid  : ctl_rvalid;
  assign rdata   = bus_to_mem ? mem_rdata   : ctl_rdata;
  assign rresp   = bus_to_mem ? mem_rresp   : ctl_rresp;

  forte_pynq_top #(.BEATS(BEATS), .TRACE_DEPTH_LOG2(15)) board (
    .aclk(clk), .aresetn(arst_n),
    .s_axi_ctl_awaddr(awaddr[11:0]), .s_axi_ctl_awvalid(awvalid && !bus_to_mem), .s_axi_ctl_awready(ctl_awready),
    .s_axi_ctl_wdata(wdata), .s_axi_ctl_wstrb(wstrb), .s_axi_ctl_wvalid(wvalid && !bus_to_mem),
    .s_axi_ctl_wready(ctl_wready), .s_axi_ctl_bresp(ctl_bresp), .s_axi_ctl_bvalid(ctl_bvalid),
    .s_axi_ctl_bready(bready && !bus_to_mem), .s_axi_ctl_araddr(araddr[11:0]),
    .s_axi_ctl_arvalid(arvalid && !bus_to_mem), .s_axi_ctl_arready(ctl_arready),
    .s_axi_ctl_rdata(ctl_rdata), .s_axi_ctl_rresp(ctl_rresp), .s_axi_ctl_rvalid(ctl_rvalid),
    .s_axi_ctl_rready(rready && !bus_to_mem),
    .s_axi_mem_awaddr(awaddr), .s_axi_mem_awvalid(awvalid && bus_to_mem), .s_axi_mem_awready(mem_awready),
    .s_axi_mem_wdata(wdata), .s_axi_mem_wstrb(4'hF), .s_axi_mem_wvalid(wvalid && bus_to_mem),
    .s_axi_mem_wready(mem_wready), .s_axi_mem_bresp(mem_bresp), .s_axi_mem_bvalid(mem_bvalid),
    .s_axi_mem_bready(bready && bus_to_mem), .s_axi_mem_araddr(araddr),
    .s_axi_mem_arvalid(arvalid && bus_to_mem), .s_axi_mem_arready(mem_arready),
    .s_axi_mem_rdata(mem_rdata), .s_axi_mem_rresp(mem_rresp), .s_axi_mem_rvalid(mem_rvalid),
    .s_axi_mem_rready(rready && bus_to_mem),
    .led);

  localparam int          WINDOWS       = 3;
  localparam logic [31:0] WINDOW_BASE [WINDOWS] = '{32'h8000_0000, 32'h8080_0000, 32'h8FEF_C000};
  localparam int          WINDOW_BYTES[WINDOWS] = '{128 * 1024, 4 * 1024, 16 * 1024};
`else
  forte_emu_dut dut (
    .core_clk(clk), .rst_n,
    .fpga_io_o(io_o), .fpga_io_oe(io_oe), .fpga_io_i(io_i),
    .dir, .req, .wr, .clk_out, .uart_tx, .status,
    .ready, .rvalid(rvalid_pin), .irq, .uart_rx,
    .test_mode, .scan_en, .fault_inject);

  logic              m_req_valid, m_req_ready, m_req_wr, m_rsp_valid;
  logic [31:0]       m_req_addr;
  logic [LINE_W-1:0] m_req_data, m_rsp_data;

  fbu_top #(.BEATS(BEATS), .TRACE_DEPTH_LOG2(15)) fbu (
    .clk, .arst_n,
    .s_axil_awaddr(awaddr), .s_axil_awvalid(awvalid), .s_axil_awready(awready),
    .s_axil_wdata(wdata), .s_axil_wstrb(wstrb), .s_axil_wvalid(wvalid), .s_axil_wready(wready),
    .s_axil_bresp(bresp), .s_axil_bvalid(bvalid), .s_axil_bready(bready),
    .s_axil_araddr(araddr), .s_axil_arvalid(arvalid), .s_axil_arready(arready),
    .s_axil_rdata(rdata), .s_axil_rresp(rresp), .s_axil_rvalid(rvalid), .s_axil_rready(rready),
    .rst_n, .irq, .fault_inject, .test_mode, .scan_en, .uart_rx,
    .io_o, .io_oe, .ready, .rvalid(rvalid_pin),
    .io_i, .dir, .req, .wr, .clk_out, .uart_tx, .status,
    .m_req_valid, .m_req_ready, .m_req_wr, .m_req_addr, .m_req_data,
    .m_rsp_valid, .m_rsp_data, .m_rsp_err(1'b0),
    .link_error_seen(), .tohost_seen(), .boot_gate_gave_up());

`endif

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

`ifndef BOARD_TOP
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
`endif

  // ---- AXI4-Lite accesses ----
  // One process performs every bus handshake; the PS code posts a request and
  // waits for it, so each access costs a few lines wherever it is used.
  task automatic step();
    @(posedge clk);
    #1;
  endtask

  logic [19:0] bus_addr;
  logic [31:0] bus_wdata;
  logic [3:0]  bus_wstrb = 4'hF;
  logic [31:0] bus_rdata;
  bit          bus_write;
  bit          bus_busy = 0;

  initial begin : bus_server
    bit aw_taken;
    bit w_taken;
    bit b_taken;
    bit ar_taken;
    bit r_taken;
    forever begin
      wait (bus_busy);
      if (bus_write) begin
        awaddr  = bus_addr;
        awvalid = 1'b1;
        wdata   = bus_wdata;
        wstrb   = bus_wstrb;
        wvalid  = 1'b1;
        do begin
          aw_taken = awvalid && awready;
          w_taken  = wvalid && wready;
          step();
          if (aw_taken)
            awvalid = 1'b0;
          if (w_taken)
            wvalid = 1'b0;
        end while (awvalid || wvalid);
        bready = 1'b1;
        do begin
          b_taken = bvalid;
          step();
        end while (!b_taken);
        bready = 1'b0;
      end else begin
        araddr  = bus_addr;
        arvalid = 1'b1;
        do begin
          ar_taken = arready;
          step();
        end while (!ar_taken);
        arvalid = 1'b0;
        rready  = 1'b1;
        do begin
          r_taken   = rvalid;
          bus_rdata = rdata;
          step();
        end while (!r_taken);
        rready = 1'b0;
      end
      bus_busy = 0;
    end
  end

  task automatic reg_write(input logic [11:0] a, input logic [31:0] d);
    bus_to_mem = 0;
    bus_addr  = 20'(a);
    bus_wdata = d;
    bus_write = 1;
    bus_busy  = 1;
    wait (!bus_busy);
  endtask

  task automatic reg_write_strobe(input logic [11:0] a, input logic [31:0] d, input logic [3:0] strobe);
    bus_wstrb = strobe;
    reg_write(a, d);
    bus_wstrb = 4'hF;
  endtask

  task automatic reg_read(input logic [11:0] a, output logic [31:0] d);
    bus_to_mem = 0;
    bus_addr  = 20'(a);
    bus_write = 0;
    bus_busy  = 1;
    wait (!bus_busy);
    d = bus_rdata;
  endtask

`ifdef BOARD_TOP
  task automatic mem_port_write(input logic [19:0] a, input logic [31:0] d);
    bus_to_mem = 1;
    bus_addr   = a;
    bus_wdata  = d;
    bus_write  = 1;
    bus_busy   = 1;
    wait (!bus_busy);
    bus_to_mem = 0;
  endtask

  task automatic mem_port_read(input logic [19:0] a, output logic [31:0] d);
    bus_to_mem = 1;
    bus_addr   = a;
    bus_write  = 0;
    bus_busy   = 1;
    wait (!bus_busy);
    d          = bus_rdata;
    bus_to_mem = 0;
  endtask

  function automatic int window_of(input logic [63:0] a);
    for (int w = 0; w < WINDOWS; w++)
      if (a - 64'(WINDOW_BASE[w]) < 64'(WINDOW_BYTES[w]))
        return w;
    return -1;
  endfunction

  function automatic logic [19:0] port_b_offset(input logic [63:0] a);
    int w;
    w = window_of(a);
    return 20'(w << 18) + 20'(a - 64'(WINDOW_BASE[w]));
  endfunction
`endif

  task automatic reg_read64(input logic [11:0] lo, output logic [63:0] d);
    logic [31:0] l;
    logic [31:0] h;
    reg_read(lo, l);
    reg_read(lo + 12'd4, h);
    d = {h, l};
  endtask

  // ---- PS state ----
  int     trace_fd;
  int     uart_fd;
  int     link_errors     = 0;
  int     tb_errors       = 0;
  longint tb_stop_cyc     = -1;
  longint tohost_cyc      = -1;
  bit     fail_pattern_on = 0;
  bit     fail_reported   = 0;
  bit     done            = 0;
  int     exit_code       = -1;
  logic [7:0] pin_ctrl    = '0;

  function automatic int total_errors();
    return link_errors + tb_errors;
  endfunction

  task automatic tb_err(input string m);
    logic [63:0] c;
    tb_errors++;
    reg_read64(REG_LINK_CYC_LO, c);
    $display("[FBU_TB] ERROR cyc %0d: %s", c, m);
    if (total_errors() >= max_errors && tb_stop_cyc < 0)
      tb_stop_cyc = longint'(c) + 1;
  endtask

  function automatic bit after_stop(input logic [63:0] at);
    if (tb_stop_cyc >= 0 && longint'(at) > tb_stop_cyc)
      return 1;
    if (tohost_cyc >= 0 && longint'(at) > tohost_cyc)
      return 1;
    return 0;
  endfunction

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
        if (after_stop(end_at))
          return;
        s = "";
        for (int b = 0; b < BEATS; b++)
          s = {s, $sformatf(" %016h", r[128 + 64 * b +: 64])};
        $fdisplay(trace_fd, "L %0d %s %08h%s", at, r[27] ? "W" : "R", r[127:96], s);
      end
      4'd2: begin
        if (after_stop(at))
          return;
        $fdisplay(trace_fd, "T %0d %016h", at, r[191:128]);
        if (tohost_cyc < 0)
          tohost_cyc = longint'(at);
      end
      4'd3: begin
        if (after_stop(at))
          return;
        for (int i = 1; i < 32; i++) begin
          if (r[96 + i]) begin
            link_err_t e = link_err_t'(i);
            $fdisplay(trace_fd, "E %0d %s", at, e.name());
          end
        end
      end
      4'd4: begin
        if (after_stop(at))
          return;
        $fdisplay(trace_fd, "I %0d %0d %0d", at, r[25:24], r[23]);
      end
      default: $display("[FBU_TB] ERROR: trace record of unknown kind %0d", kind);
    endcase
  endfunction

  task automatic drain_trace(input int max_records);
    logic [31:0]  stat;
    logic [319:0] r;
    logic [31:0]  w;
    for (int n = 0; n < max_records; n++) begin
      reg_read(REG_TRACE_STAT, stat);
      if (!stat[0])
        return;
      for (int i = 0; i < 10; i++) begin
        reg_read(REG_TRACE_HEAD + 12'(4 * i), w);
        r[32 * i +: 32] = w;
      end
      reg_write(REG_TRACE_POP, 32'd1);
      write_record(r);
    end
  endtask

  task automatic drain_uart(input int max_bytes);
    logic [31:0] d;
    for (int n = 0; n < max_bytes; n++) begin
      reg_read(REG_UART_RX_DATA, d);
      if (!d[31])
        return;
      reg_write(REG_UART_RX_POP, 32'd1);
      if (d[8])
        tb_err($sformatf("framing error on uart_tx (byte %02h)", d[7:0]));
      else
        $fwrite(uart_fd, "%c", d[7:0]);
    end
  endtask

  task automatic service();
    logic [31:0] v;
    reg_read(REG_LINK_ERR_COUNT, v);
    link_errors = int'(v);
    if (fail_pattern_on && !fail_reported) begin
      reg_read(REG_UART_MATCH_CTRL, v);
      if (v[1]) begin
        fail_reported = 1;
        tb_err("console printed the fail pattern");
      end
    end
    drain_uart(16);
    drain_trace(8);
  endtask

  function automatic bit stopped();
    return total_errors() >= max_errors;
  endfunction

  task automatic verdict(input bit pass, input string why);
    logic [31:0] stat;
    logic [31:0] v [8];
    if (done)
      return;
    done = 1;
    repeat (8) step();
    do begin
      drain_trace(1 << 16);
      drain_uart(1 << 16);
      reg_read(REG_TRACE_STAT, stat);
    end while (stat[0]);
    $fclose(trace_fd);
    $fclose(uart_fd);
    reg_read(REG_LINK_RD, v[0]);
    reg_read(REG_LINK_WR, v[1]);
    reg_read(REG_UART_N_RX, v[2]);
    reg_read(REG_UART_N_TX, v[3]);
    reg_read(REG_TRACE_WRITTEN, v[4]);
    reg_read(REG_TRACE_DROPPED, v[5]);
    reg_read(REG_BOOTGATE_STAT, v[6]);
    reg_read(REG_BOOTGATE_PASSES, v[7]);
    $display("[FBU_TB] link_rd=%0d link_wr=%0d uart_rx=%0d uart_tx=%0d errors=%0d",
             v[0], v[1], v[2], v[3], total_errors());
    $display("[FBU_TB] trace written=%0d dropped=%0d", v[4], v[5]);
    $display("[FBU_TB] gate passes=%0d fails=%0d gave_up=%0d", v[7][15:0], v[6][15:0], v[6][16]);
    if (pass && total_errors() == 0)
      $display("PIN_TB_RESULT: PASS");
    else if (!pass)
      $display("PIN_TB_RESULT: FAIL %s", why);
    else
      $display("PIN_TB_RESULT: FAIL %0d checker errors", total_errors());
    $finish;
  endtask

  task automatic check_stop();
    service();
    if (stopped())
      verdict(0, $sformatf("%0d checker errors", total_errors()));
  endtask

  // Wait n chip cycles, servicing as the PS would.
  task automatic run_cycles(input longint n);
    logic [63:0] start;
    logic [63:0] now_cyc;
    reg_read64(REG_CYC_TOTAL_LO, start);
    do begin
      service();
      if (stopped())
        return;
      reg_read64(REG_CYC_TOTAL_LO, now_cyc);
    end while (now_cyc - start < 64'(n));
  endtask

  task automatic set_match(input int m, input string text);
    logic [31:0] lens;
    logic [31:0] w;
    logic [11:0] base;
    base = (m == 0) ? REG_UART_MATCH0 : REG_UART_MATCH1;
    for (int word = 0; word < MATCH_BYTES / 4; word++) begin
      w = '0;
      for (int b = 0; b < 4; b++) begin
        int i;
        i = 4 * word + b;
        if (i < text.len())
          w[8 * b +: 8] = text.getc(text.len() - 1 - i);
      end
      reg_write(base + 12'(4 * word), w);
    end
    reg_read(REG_UART_MATCH_LEN, lens);
    lens[8 * m +: 8] = 8'(text.len());
    reg_write(REG_UART_MATCH_LEN, lens);
    reg_write(REG_UART_MATCH_CTRL, 32'(1 << m));
  endtask

  task automatic send_entry(input logic [1:0] kind, input logic [7:0] data);
    logic [31:0] stat;
    do
      reg_read(REG_UART_STAT, stat);
    while (stat[1]);
    reg_write(REG_UART_TX_PUSH, {22'd0, kind, data});
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

`ifdef BOARD_TOP
  // Fill every window with what the bench's memory holds there (the image, and
  // its unwritten-memory pattern elsewhere), then read the image back.
  task automatic board_load();
    logic [63:0] word;
    logic [31:0] lo;
    logic [31:0] hi;
    int          outside = 0;
    int          not_ext_mem = 0;
    int          mismatched = 0;
    foreach (mem[k]) begin
      if ((64'(k) << 3) >> 28 != 64'h8)
        not_ext_mem++;
      else if (window_of(64'(k) << 3) < 0)
        outside++;
    end
    if (not_ext_mem != 0)
      $display("[FBU_TB] load_lst: %0d image words lie outside EXT_MEM and are not loaded", not_ext_mem);
    if (outside != 0)
      tb_err($sformatf("load_lst: %0d image words fall outside the memory windows", outside));
    for (int w = 0; w < WINDOWS; w++) begin
      for (int off = 0; off < WINDOW_BYTES[w]; off += 8) begin
        word = mem_rd(64'(WINDOW_BASE[w]) + 64'(off));
        mem_port_write(20'(w << 18) + 20'(off), word[31:0]);
        mem_port_write(20'(w << 18) + 20'(off) + 20'd4, word[63:32]);
      end
    end
    foreach (mem[k]) begin
      if (window_of(64'(k) << 3) >= 0) begin
        mem_port_read(port_b_offset(64'(k) << 3), lo);
        mem_port_read(port_b_offset(64'(k) << 3) + 20'd4, hi);
        if ({hi, lo} != mem[k])
          mismatched++;
      end
    end
    if (mismatched != 0)
      tb_err($sformatf("load_lst: %0d image words read back wrong through the memory port", mismatched));
    else
      $display("[FBU_TB] memory windows filled and the image read back");
  endtask
`endif

  task automatic exec(input string raw, input int lineno);
    string       ln;
    string       cmd;
    string       a1;
    string       a2;
    string       a3;
    int          n;
    longint      t;
    longint      v;
    logic [31:0] r;
    logic [63:0] r64;
    logic [63:0] start;
    logic [63:0] now_cyc;
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
`ifdef BOARD_TOP
        board_load();
`endif
      end
      "reset": begin
        void'($sscanf(a1, "%d", t));
        exit_code = -1;
        tohost_cyc = -1;
        reg_write(REG_RST_PULSE, 32'(t + 1));
        pin_ctrl[0] = 1'b1;
        reg_write(REG_PIN_CTRL, {24'd0, pin_ctrl});
        run_cycles(t + 1);
      end
      "run": begin
        void'($sscanf(a1, "%d", t));
        run_cycles(t);
      end
      "run_until_tohost": begin
        void'($sscanf(a1, "%d", t));
        reg_read64(REG_CYC_TOTAL_LO, start);
        do begin
          service();
          if (stopped())
            return;
          reg_read(REG_TOHOST_STAT, r);
          reg_read64(REG_CYC_TOTAL_LO, now_cyc);
        end while (!r[0] && now_cyc - start < 64'(t));
        if (!r[0])
          verdict(0, $sformatf("timeout: no tohost write in %0d cycles", t));
        reg_read64(REG_TOHOST_VAL_LO, r64);
        exit_code = int'(r64 >> 1);
        $display("[FBU_TB] tohost = %h (exit code %0d)", r64, exit_code);
        if (r64[0] !== 1'b1)
          tb_err($sformatf("tohost %h has bit 0 clear", r64));
      end
      "run_until_uart": begin
        string want;
        void'($sscanf(a1, "%d", t));
        want = unescape(rest_after(ln, 2));
        set_match(0, want);
        reg_read64(REG_CYC_TOTAL_LO, start);
        do begin
          service();
          if (stopped())
            return;
          reg_read(REG_UART_MATCH_CTRL, r);
          reg_read64(REG_CYC_TOTAL_LO, now_cyc);
        end while (!r[0] && now_cyc - start < 64'(t));
        if (!r[0])
          verdict(0, $sformatf("timeout: console never printed \"%s\" in %0d cycles", want, t));
        $display("[FBU_TB] console printed \"%s\"", want);
      end
      "expect_tohost": begin
        void'($sscanf(a1, "%d", v));
        if (exit_code != int'(v))
          tb_err($sformatf("exit code %0d, expected %0d", exit_code, v));
      end
      "uart_div": begin
        void'($sscanf(a1, "%d", v));
        reg_write(REG_UART_RX_BIT, 32'(16 * (v << PRESCALE)));
        reg_write(REG_UART_TX_PERIOD, 32'(16 * (v << PRESCALE)) << 8);
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
        reg_write(REG_UART_TX_GAP, 32'(v));
      end
      "uart_fail": begin
        if (fail_pattern_on)
          tb_err("uart_fail: the gateware matches one fail pattern");
        fail_pattern_on = 1;
        set_match(1, unescape(rest_after(ln, 1)));
      end
      "irq": begin
        void'($sscanf(a1, "%d", v));
        void'($sscanf(a2, "%d", t));
        pin_ctrl[4 + v] = t[0];
        reg_write(REG_PIN_CTRL, {24'd0, pin_ctrl});
      end
      "fault_inject": begin
        void'($sscanf(a1, "%d", v));
        pin_ctrl[1] = v[0];
        reg_write(REG_PIN_CTRL, {24'd0, pin_ctrl});
      end
      "dump_mem": begin
        logic [63:0] base;
        int          fd;
        void'($sscanf(a1, "%h", base));
        void'($sscanf(a2, "%d", v));
        fd = $fopen(a3, "w");
        for (longint i = 0; i < v; i += 8) begin
`ifdef BOARD_TOP
          logic [31:0] lo;
          logic [31:0] hi;
          if (window_of(base + 64'(i)) < 0) begin
            tb_err($sformatf("dump_mem: %h is outside the memory windows", base + 64'(i)));
            break;
          end
          mem_port_read(port_b_offset(base + 64'(i)), lo);
          mem_port_read(port_b_offset(base + 64'(i)) + 20'd4, hi);
          $fdisplay(fd, "%016h %016h", base + 64'(i), {hi, lo});
`else
          $fdisplay(fd, "%016h %016h", base + 64'(i), mem_rd(base + 64'(i)));
`endif
        end
        $fclose(fd);
      end
      "finish": verdict(1, "");
      default:  tb_err($sformatf("line %0d: unknown command '%s'", lineno, cmd));
    endcase
  endtask

  // A write narrower than a word merges into a data register and is ignored,
  // and counted, by a register with a side effect (diag_write_width.py found
  // the PYNQ's Linux splitting Python's word stores into two halfwords).
  task automatic wstrb_self_test();
    logic [31:0] v;
    logic [31:0] partial_before;
    logic [31:0] sent_before;
    logic [31:0] partial_after;
    logic [31:0] sent_after;
    logic [31:0] idle_entry;
    idle_entry = {22'd0, 2'd3, 8'd1};
    reg_write(REG_SCRATCH, 32'h0000_0000);
    reg_write_strobe(REG_SCRATCH, 32'hDEAD_BEEF, 4'b0011);
    reg_read(REG_SCRATCH, v);
    if (v != 32'h0000_BEEF)
      tb_err($sformatf("wstrb: SCRATCH after a low-half write reads %08h, expected 0000beef", v));
    reg_write_strobe(REG_SCRATCH, 32'hCAFE_0000, 4'b1100);
    reg_read(REG_SCRATCH, v);
    if (v != 32'hCAFE_BEEF)
      tb_err($sformatf("wstrb: SCRATCH after a high-half write reads %08h, expected cafebeef", v));
    reg_read(REG_PARTIAL_WRITES, partial_before);
    reg_read(REG_UART_N_TX, sent_before);
    reg_write_strobe(REG_UART_TX_PUSH, idle_entry, 4'b0011);
    reg_write_strobe(REG_UART_TX_PUSH, idle_entry, 4'b1100);
    repeat (4) step();
    reg_read(REG_PARTIAL_WRITES, partial_after);
    reg_read(REG_UART_N_TX, sent_after);
    if (sent_after != sent_before)
      tb_err($sformatf("wstrb: two half-word writes to UART_TX_PUSH queued %0d entries, expected 0", sent_after - sent_before));
    if (partial_after - partial_before != 2)
      tb_err($sformatf("wstrb: PARTIAL_WRITES rose by %0d, expected 2", partial_after - partial_before));
    reg_write(REG_UART_TX_PUSH, idle_entry);
    repeat (4) step();
    reg_read(REG_UART_N_TX, sent_after);
    if (sent_after - sent_before != 1)
      tb_err($sformatf("wstrb: one whole-word write to UART_TX_PUSH queued %0d entries, expected 1", sent_after - sent_before));
    $display("[FBU_TB] wstrb self-test done");
  endtask

  task automatic configure();
    logic [63:0] init;
    logic [31:0] id;
    reg_read(REG_ID, id);
    if (id != FBU_ID)
      verdict(0, $sformatf("ID register reads %08h, expected %08h", id, FBU_ID));
    init = prng_seed_state(seed);
    reg_write(REG_LINK_CFG, {16'(rd_lat), 8'd0, 7'(gap_pct), det});
    reg_write(REG_LINK_WDOG, {14'd0, 2'(mutate), 16'(wdog)});
    reg_write(REG_PRNG_INIT_LO, init[31:0]);
    reg_write(REG_PRNG_INIT_HI, init[63:32]);
    reg_write(REG_PRNG_LOAD, 32'd1);
    reg_write(REG_TOHOST_ADDR, tohost_addr[31:0]);
    reg_write(REG_TRACE_CTRL, {30'd0, max_errors == 1, 1'b1});
    reg_write(REG_BOOTGATE, {16'd1000, 8'd0, 4'(gate_retries), 2'b00, gate_selftest, gate_enable});
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
    if ($value$plusargs("TOHOST=%h", tohost_addr)) ;
    if ($value$plusargs("TIMEOUT=%d", timeout)) ;
    if ($value$plusargs("TRACE=%s", s))        trace_path = s;
    if ($value$plusargs("UART_LOG=%s", s))     uart_path = s;
    if ($test$plusargs("NODET"))               det = 0;
    if ($test$plusargs("BOOT_GATE"))           gate_enable = 1;
    if ($test$plusargs("BOOT_GATE_SELFTEST"))  gate_selftest = 1;
    if ($value$plusargs("BOOT_GATE_RETRIES=%d", v)) gate_retries = v;
    trace_fd = $fopen(trace_path, "w");
    uart_fd  = $fopen(uart_path, "w");

    repeat (2) step();
    arst_n = 1'b1;
    repeat (8) step();
    configure();
    if ($test$plusargs("WSTRB_TEST"))
      wstrb_self_test();
    if ($value$plusargs("UART_DIV=%d", v))
      exec($sformatf("uart_div %0d", v), 0);
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
      check_stop();
      exec($sformatf("run_until_tohost %0d", timeout), 3);
      check_stop();
      exec("expect_tohost 0", 4);
    end
    check_stop();
    verdict(1, "");
  end

endmodule
