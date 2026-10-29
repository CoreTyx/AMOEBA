///////////////////////////////////////////////////////////////////////////////
// fbu_top.sv -- the bring-up gateware: the chip's 32 pins on one side, an
// AXI4-Lite register file (fbu_pkg REG_*) and a line memory port on the other.
///////////////////////////////////////////////////////////////////////////////
module fbu_top import forte_link_pkg::*, fbu_pkg::*; #(
  parameter int BEATS            = 2,
  parameter int TRACE_DEPTH_LOG2 = 11,
  localparam int LINE_W          = 64 * BEATS
)(
  input  logic              clk,
  input  logic              arst_n,

  input  logic [11:0]       s_axil_awaddr,
  input  logic              s_axil_awvalid,
  output logic              s_axil_awready,
  input  logic [31:0]       s_axil_wdata,
  input  logic [3:0]        s_axil_wstrb,
  input  logic              s_axil_wvalid,
  output logic              s_axil_wready,
  output logic [1:0]        s_axil_bresp,
  output logic              s_axil_bvalid,
  input  logic              s_axil_bready,
  input  logic [11:0]       s_axil_araddr,
  input  logic              s_axil_arvalid,
  output logic              s_axil_arready,
  output logic [31:0]       s_axil_rdata,
  output logic [1:0]        s_axil_rresp,
  output logic              s_axil_rvalid,
  input  logic              s_axil_rready,

  output logic              rst_n,
  output logic [1:0]        irq,
  output logic              fault_inject,
  output logic              test_mode,
  output logic              scan_en,
  output logic              uart_rx,
  output logic [LINK_W-1:0] io_o,
  output logic [LINK_W-1:0] io_oe,
  output logic              ready,
  output logic              rvalid,
  input  logic [LINK_W-1:0] io_i,
  input  logic              dir,
  input  logic              req,
  input  logic              wr,
  input  logic              clk_out,
  input  logic              uart_tx,
  input  logic              status,

  output logic              m_req_valid,
  input  logic              m_req_ready,
  output logic              m_req_wr,
  output logic [31:0]       m_req_addr,
  output logic [LINE_W-1:0] m_req_data,
  input  logic              m_rsp_valid,
  input  logic [LINE_W-1:0] m_rsp_data,
  input  logic              m_rsp_err,

  output logic              link_error_seen,
  output logic              tohost_seen,
  output logic              boot_gate_gave_up
);

  localparam int MATCH_BYTES = 32;
  localparam int MATCH_LEN_W = $clog2(MATCH_BYTES + 1);

  // ---- register port ----
  logic        reg_write;
  logic [11:0] reg_waddr;
  logic [31:0] reg_wdata;
  logic [3:0]  reg_wstrb;
  logic        reg_read;
  logic [11:0] reg_raddr;
  logic [31:0] reg_rdata;

  fbu_axil #(.ADDR_W(12)) axil (
    .clk, .arst_n,
    .s_awaddr(s_axil_awaddr), .s_awvalid(s_axil_awvalid), .s_awready(s_axil_awready),
    .s_wdata(s_axil_wdata), .s_wstrb(s_axil_wstrb), .s_wvalid(s_axil_wvalid), .s_wready(s_axil_wready),
    .s_bresp(s_axil_bresp), .s_bvalid(s_axil_bvalid), .s_bready(s_axil_bready),
    .s_araddr(s_axil_araddr), .s_arvalid(s_axil_arvalid), .s_arready(s_axil_arready),
    .s_rdata(s_axil_rdata), .s_rresp(s_axil_rresp), .s_rvalid(s_axil_rvalid), .s_rready(s_axil_rready),
    .reg_write, .reg_waddr, .reg_wdata, .reg_wstrb, .reg_read, .reg_raddr, .reg_rdata);

  function automatic logic written(input logic [11:0] offset);
    return reg_write && reg_waddr == offset;
  endfunction

  // ---- soft reset: everything below the register file, for a few cycles ----
  logic [2:0] soft_reset_cycles;
  logic       blocks_rst_n;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n)
      soft_reset_cycles <= '0;
    else if (written(REG_SOFT_RESET))
      soft_reset_cycles <= '1;
    else if (soft_reset_cycles != '0)
      soft_reset_cycles <= soft_reset_cycles - 3'd1;
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n)
      blocks_rst_n <= 1'b0;
    else
      blocks_rst_n <= soft_reset_cycles == '0;
  end

  // ---- configuration registers ----
  logic [31:0] scratch;
  logic [7:0]  pin_ctrl;
  logic [31:0] bootgate;
  logic [31:0] link_cfg;
  logic [31:0] link_wdog;
  logic [63:0] prng_init;
  logic [31:0] mem_base;
  logic [31:0] mem_limit;
  logic [31:0] reset_vec;
  logic [31:0] tohost_addr;
  logic [1:0]  trace_ctrl;
  logic [23:0] uart_rx_bit;
  logic [31:0] uart_tx_period;
  logic [7:0]  uart_tx_gap;
  logic [MATCH_LEN_W-1:0]   match_len     [2];
  logic [8*MATCH_BYTES-1:0] match_pattern [2];

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      scratch        <= '0;
      pin_ctrl       <= 8'h00;
      bootgate       <= {16'd1000, 8'h20, 8'h00};
      link_cfg       <= 32'h0000_0001;
      link_wdog      <= 32'd1000;
      prng_init      <= prng_seed_state(32'd1);
      mem_base       <= 32'h8000_0000;
      mem_limit      <= 32'h8FFF_FFFF;
      reset_vec      <= 32'h8000_0000;
      tohost_addr    <= 32'h8080_0000;
      trace_ctrl     <= 2'b01;
      uart_rx_bit    <= 24'd32;
      uart_tx_period <= 32'd32 << 8;
      uart_tx_gap    <= '0;
      match_len      <= '{default: '0};
      match_pattern  <= '{default: '0};
    end else if (reg_write) begin
      case (reg_waddr)
        REG_SCRATCH:        scratch        <= reg_wdata;
        REG_PIN_CTRL:       pin_ctrl       <= reg_wdata[7:0];
        REG_BOOTGATE:       bootgate       <= reg_wdata;
        REG_LINK_CFG:       link_cfg       <= reg_wdata;
        REG_LINK_WDOG:      link_wdog      <= reg_wdata;
        REG_PRNG_INIT_LO:   prng_init[31:0]  <= reg_wdata;
        REG_PRNG_INIT_HI:   prng_init[63:32] <= reg_wdata;
        REG_MEM_BASE:       mem_base       <= reg_wdata;
        REG_MEM_LIMIT:      mem_limit      <= reg_wdata;
        REG_RESET_VEC:      reset_vec      <= reg_wdata;
        REG_TOHOST_ADDR:    tohost_addr    <= reg_wdata;
        REG_TRACE_CTRL:     trace_ctrl     <= reg_wdata[1:0];
        REG_UART_RX_BIT:    uart_rx_bit    <= reg_wdata[23:0];
        REG_UART_TX_PERIOD: uart_tx_period <= reg_wdata;
        REG_UART_TX_GAP:    uart_tx_gap    <= reg_wdata[7:0];
        REG_UART_MATCH_LEN: begin
          match_len[0] <= reg_wdata[MATCH_LEN_W-1:0];
          match_len[1] <= reg_wdata[8 +: MATCH_LEN_W];
        end
        default: begin
          for (int w = 0; w < MATCH_BYTES / 4; w++) begin
            if (reg_waddr == REG_UART_MATCH0 + 12'(4 * w))
              match_pattern[0][32 * w +: 32] <= reg_wdata;
            if (reg_waddr == REG_UART_MATCH1 + 12'(4 * w))
              match_pattern[1][32 * w +: 32] <= reg_wdata;
          end
        end
      endcase
    end
  end

  // ---- link slave ----
  logic [63:0]       link_cyc;
  logic [31:0]       link_rd;
  logic [31:0]       link_wr;
  logic [63:0]       tohost_val;
  logic [31:0]       err_now;
  logic [31:0]       err_sticky;
  logic [31:0]       err_count;
  logic [4:0]        first_err;
  logic [63:0]       first_err_cyc;
  logic              rec_valid;
  logic [63:0]       rec_cyc;
  logic              rec_wr;
  logic [31:0]       rec_addr;
  logic [LINE_W-1:0] rec_line;
  logic              rec_tohost;
  logic [63:0]       rec_end_cyc;
  logic [63:0]       rec_tohost_val;
  logic              slave_io_oe;

  fbu_link_slave #(.BEATS(BEATS)) link (
    .clk, .arst_n(blocks_rst_n),
    .cfg_det(link_cfg[0]), .cfg_gap_pct(link_cfg[7:1]), .cfg_rd_lat(link_cfg[31:16]),
    .cfg_wdog(link_wdog[15:0]), .cfg_mutate(link_wdog[17:16]),
    .cfg_mem_base(mem_base), .cfg_mem_limit(mem_limit), .cfg_reset_vec(reset_vec),
    .cfg_tohost_addr(tohost_addr),
    .prng_load(written(REG_PRNG_LOAD)), .prng_init,
    .rst_n_pin(rst_n), .dir, .req, .wr, .io_i, .io_o, .io_oe(slave_io_oe), .ready, .rvalid,
    .m_req_valid, .m_req_ready, .m_req_wr, .m_req_addr, .m_req_data,
    .m_rsp_valid, .m_rsp_data, .m_rsp_err,
    .cyc(link_cyc), .n_rd(link_rd), .n_wr(link_wr), .tohost_seen, .tohost_val,
    .err_now, .err_sticky, .err_count, .first_err, .first_err_cyc,
    .rec_valid, .rec_cyc, .rec_wr, .rec_addr, .rec_line,
    .rec_tohost, .rec_tohost_cyc(rec_end_cyc), .rec_tohost_val);

  assign io_oe           = {LINK_W{slave_io_oe}};
  assign link_error_seen = err_sticky != '0;

  // ---- control pins ----
  logic        uart_rx_from_uart;
  logic [31:0] reset_count;
  logic [63:0] cycles_total;
  logic [15:0] gate_passes;
  logic [15:0] gate_fails;
  logic        gate_gave_up;
  logic [32:0] gate_last_header;

  fbu_pin_ctl pins (
    .clk, .arst_n(blocks_rst_n),
    .cfg_release(pin_ctrl[0]), .cfg_fault_inject(pin_ctrl[1]),
    .cfg_test_mode(pin_ctrl[2]), .cfg_scan_en(pin_ctrl[3]), .cfg_irq(pin_ctrl[5:4]),
    .cfg_rx_force_en(pin_ctrl[6]), .cfg_rx_force_val(pin_ctrl[7]),
    .reset_pulse_start(written(REG_RST_PULSE)), .reset_pulse_cycles(reg_wdata),
    .cfg_gate_enable(bootgate[0]), .cfg_gate_selftest(bootgate[1]),
    .cfg_gate_retries(bootgate[7:4]), .cfg_gate_timeout(bootgate[31:16]),
    .req, .wr, .io_i, .uart_rx_from_uart,
    .rst_n, .irq, .fault_inject, .test_mode, .scan_en, .uart_rx,
    .reset_count, .cycles_total, .gate_passes, .gate_fails, .gate_gave_up, .gate_last_header);

  assign boot_gate_gave_up = gate_gave_up;

  // ---- console ----
  logic [8:0]  uart_rx_head;
  logic        uart_rx_valid;
  logic [10:0] uart_rx_level;
  logic        uart_rx_overflow;
  logic        uart_tx_full;
  logic        uart_tx_overflow;
  logic [6:0]  uart_tx_level;
  logic        uart_tx_busy;
  logic [31:0] uart_n_rx;
  logic [31:0] uart_n_tx;
  logic [31:0] uart_n_ferr;
  logic        match_clear [2];
  logic        match_hit   [2];
  logic        match_pulse [2];

  assign match_clear[0] = written(REG_UART_MATCH_CTRL) && reg_wdata[0];
  assign match_clear[1] = written(REG_UART_MATCH_CTRL) && reg_wdata[1];

  fbu_uart #(.RX_FIFO_LOG2(10), .TX_FIFO_LOG2(6), .MATCH_BYTES(MATCH_BYTES)) console (
    .clk, .arst_n(blocks_rst_n), .clear(written(REG_UART_CLEAR)),
    .cfg_rx_bit_cycles(uart_rx_bit), .cfg_tx_bit_period_q8(uart_tx_period),
    .cfg_tx_gap_bits(uart_tx_gap),
    .uart_tx, .uart_rx(uart_rx_from_uart),
    .rx_head(uart_rx_head), .rx_valid(uart_rx_valid), .rx_pop(written(REG_UART_RX_POP)),
    .rx_level(uart_rx_level), .rx_overflow(uart_rx_overflow),
    .tx_push(written(REG_UART_TX_PUSH)), .tx_entry(reg_wdata[9:0]),
    .tx_full(uart_tx_full), .tx_overflow(uart_tx_overflow), .tx_level(uart_tx_level),
    .tx_busy(uart_tx_busy),
    .n_rx(uart_n_rx), .n_tx(uart_n_tx), .n_framing_errors(uart_n_ferr),
    .cfg_match_len(match_len), .cfg_match_pattern(match_pattern),
    .match_clear, .match_hit, .match_pulse);

  // ---- link trace ----
  logic [319:0]              trace_head;
  logic                      trace_valid;
  logic [TRACE_DEPTH_LOG2:0] trace_level;
  logic [31:0]               trace_written;
  logic [31:0]               trace_dropped;
  logic                      trace_overflow;

  fbu_link_trace #(.BEATS(BEATS), .DEPTH_LOG2(TRACE_DEPTH_LOG2)) trace (
    .clk, .arst_n(blocks_rst_n), .clear(written(REG_TRACE_CLEAR)),
    .cfg_enable(trace_ctrl[0]), .cfg_stop_on_error(trace_ctrl[1]),
    .link_cyc, .chip_in_reset(!rst_n),
    .rec_valid, .rec_cyc, .rec_wr, .rec_addr, .rec_line, .rec_tohost,
    .rec_end_cyc, .rec_tohost_val, .err_now, .irq,
    .head(trace_head), .head_valid(trace_valid), .pop(written(REG_TRACE_POP)),
    .level(trace_level), .records_written(trace_written), .records_dropped(trace_dropped),
    .overflow(trace_overflow));

  // ---- register reads ----
  logic [31:0] pin_in;
  logic [31:0] match_words [2][MATCH_BYTES / 4];

  assign pin_in = {7'd0, clk_out, rvalid, ready, rst_n, uart_tx, status, wr, req, dir, io_i};

  always_comb begin
    for (int m = 0; m < 2; m++)
      for (int w = 0; w < MATCH_BYTES / 4; w++)
        match_words[m][w] = match_pattern[m][32 * w +: 32];
  end

  always_comb begin
    reg_rdata = '0;
    case (reg_raddr)
      REG_ID:               reg_rdata = FBU_ID;
      REG_VERSION:          reg_rdata = FBU_VERSION;
      REG_CAPS:             reg_rdata = {16'd0, 8'(TRACE_DEPTH_LOG2), 4'd0, 4'(BEATS)};
      REG_SCRATCH:          reg_rdata = scratch;
      REG_PIN_CTRL:         reg_rdata = {24'd0, pin_ctrl};
      REG_PIN_IN:           reg_rdata = pin_in;
      REG_RST_COUNT:        reg_rdata = reset_count;
      REG_BOOTGATE:         reg_rdata = bootgate;
      REG_BOOTGATE_STAT:    reg_rdata = {14'd0, gate_last_header[32], gate_gave_up, gate_fails};
      REG_BOOTGATE_HDR:     reg_rdata = gate_last_header[31:0];
      REG_BOOTGATE_PASSES:  reg_rdata = {16'd0, gate_passes};
      REG_LINK_CYC_LO:      reg_rdata = link_cyc[31:0];
      REG_LINK_CYC_HI:      reg_rdata = link_cyc[63:32];
      REG_CYC_TOTAL_LO:     reg_rdata = cycles_total[31:0];
      REG_CYC_TOTAL_HI:     reg_rdata = cycles_total[63:32];
      REG_LINK_CFG:         reg_rdata = link_cfg;
      REG_LINK_WDOG:        reg_rdata = link_wdog;
      REG_PRNG_INIT_LO:     reg_rdata = prng_init[31:0];
      REG_PRNG_INIT_HI:     reg_rdata = prng_init[63:32];
      REG_MEM_BASE:         reg_rdata = mem_base;
      REG_MEM_LIMIT:        reg_rdata = mem_limit;
      REG_RESET_VEC:        reg_rdata = reset_vec;
      REG_LINK_ERR:         reg_rdata = err_sticky;
      REG_LINK_ERR_COUNT:   reg_rdata = err_count;
      REG_FIRST_ERR:        reg_rdata = {27'd0, first_err};
      REG_FIRST_ERR_CYC_LO: reg_rdata = first_err_cyc[31:0];
      REG_FIRST_ERR_CYC_HI: reg_rdata = first_err_cyc[63:32];
      REG_LINK_RD:          reg_rdata = link_rd;
      REG_LINK_WR:          reg_rdata = link_wr;
      REG_TOHOST_ADDR:      reg_rdata = tohost_addr;
      REG_TOHOST_STAT:      reg_rdata = {31'd0, tohost_seen};
      REG_TOHOST_VAL_LO:    reg_rdata = tohost_val[31:0];
      REG_TOHOST_VAL_HI:    reg_rdata = tohost_val[63:32];
      REG_TRACE_CTRL:       reg_rdata = {30'd0, trace_ctrl};
      REG_TRACE_LEVEL:      reg_rdata = 32'(trace_level);
      REG_TRACE_WRITTEN:    reg_rdata = trace_written;
      REG_TRACE_DROPPED:    reg_rdata = trace_dropped;
      REG_TRACE_STAT:       reg_rdata = {30'd0, trace_overflow, trace_valid};
      REG_UART_RX_BIT:      reg_rdata = {8'd0, uart_rx_bit};
      REG_UART_TX_PERIOD:   reg_rdata = uart_tx_period;
      REG_UART_TX_GAP:      reg_rdata = {24'd0, uart_tx_gap};
      REG_UART_RX_DATA:     reg_rdata = {uart_rx_valid, 22'd0, uart_rx_head};
      REG_UART_STAT:        reg_rdata = {28'd0, uart_tx_busy, uart_tx_overflow, uart_tx_full, uart_rx_overflow};
      REG_UART_RX_LEVEL:    reg_rdata = 32'(uart_rx_level);
      REG_UART_TX_LEVEL:    reg_rdata = 32'(uart_tx_level);
      REG_UART_N_RX:        reg_rdata = uart_n_rx;
      REG_UART_N_TX:        reg_rdata = uart_n_tx;
      REG_UART_N_FERR:      reg_rdata = uart_n_ferr;
      REG_UART_MATCH_LEN:   reg_rdata = {16'd0, 8'(match_len[1]), 8'(match_len[0])};
      REG_UART_MATCH_CTRL:  reg_rdata = {30'd0, match_hit[1], match_hit[0]};
      default: begin
        for (int w = 0; w < 10; w++)
          if (reg_raddr == REG_TRACE_HEAD + 12'(4 * w))
            reg_rdata = trace_head[32 * w +: 32];
        for (int w = 0; w < MATCH_BYTES / 4; w++) begin
          if (reg_raddr == REG_UART_MATCH0 + 12'(4 * w))
            reg_rdata = match_words[0][w];
          if (reg_raddr == REG_UART_MATCH1 + 12'(4 * w))
            reg_rdata = match_words[1][w];
        end
      end
    endcase
  end

endmodule
