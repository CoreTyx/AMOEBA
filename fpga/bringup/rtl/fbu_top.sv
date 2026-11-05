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
  localparam int TRIGGERS    = 4;
  // The core leaves reset after forte_rst_sync's and forte_soc's 2-flop
  // synchronisers, so its fault counter starts 4 cycles into the link count
  // (measured: fe_fault_cal.cmd).
  localparam logic [8:0] CHIP_RESET_SYNC_CYCLES = 9'd4;
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

  // Data registers take the bytes WSTRB selects.  A register whose write has a
  // side effect (a pop, a push, a pulse) acts only on a whole-word write; any
  // narrower write is counted in PARTIAL_WRITES instead of guessed at.
  logic        full_word;
  logic [31:0] byte_mask;
  logic [31:0] partial_writes;

  assign full_word = reg_wstrb == 4'hF;
  assign byte_mask = {{8{reg_wstrb[3]}}, {8{reg_wstrb[2]}}, {8{reg_wstrb[1]}}, {8{reg_wstrb[0]}}};

  function automatic logic written(input logic [11:0] offset);
    return reg_write && full_word && reg_waddr == offset;
  endfunction

  function automatic logic [31:0] merged(input logic [31:0] old);
    return (old & ~byte_mask) | (reg_wdata & byte_mask);
  endfunction

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n)
      partial_writes <= '0;
    else if (reg_write && !full_word)
      partial_writes <= partial_writes + 32'd1;
  end

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
  logic [3:0]   fi_mode;
  logic         fi_start_on_release;
  logic [31:0]  fi_arg0;
  logic [31:0]  fi_arg1;
  logic [31:0]  fi_seed;
  logic [3:0]   fi_latency;
  logic [8:0]   fi_phase_ofs;
  logic [511:0] fi_phase_mask;
  logic [31:0]  fi_ctrl_written;
  logic [31:0]  scan_ctrl_written;
  logic [31:0]  trig_ctrl [TRIGGERS];
  logic [31:0]  trig_arg0 [TRIGGERS];
  logic [31:0]  trig_arg1 [TRIGGERS];
  logic         scan_pattern_scan_en;
  logic [10:0]  scan_len;
  logic [9:0]   scan_addr;

  assign fi_ctrl_written = merged({27'd0, fi_start_on_release, fi_mode});
  assign scan_ctrl_written = merged({30'd0, scan_pattern_scan_en, 1'b0});

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
      fi_mode             <= '0;
      fi_start_on_release <= 1'b0;
      fi_arg0             <= '0;
      fi_arg1             <= '0;
      fi_seed             <= 32'h1;
      fi_latency          <= 4'd4;
      fi_phase_ofs        <= CHIP_RESET_SYNC_CYCLES;
      fi_phase_mask       <= '0;
      trig_ctrl           <= '{default: '0};
      trig_arg0           <= '{default: '0};
      trig_arg1           <= '{default: '0};
      scan_pattern_scan_en <= 1'b0;
      scan_len             <= '0;
      scan_addr            <= '0;
    end else begin
      if (reg_write) begin
      case (reg_waddr)
        REG_SCRATCH:        scratch          <= merged(scratch);
        REG_PIN_CTRL:       pin_ctrl         <= 8'(merged(32'(pin_ctrl)));
        REG_BOOTGATE:       bootgate         <= merged(bootgate);
        REG_LINK_CFG:       link_cfg         <= merged(link_cfg);
        REG_LINK_WDOG:      link_wdog        <= merged(link_wdog);
        REG_PRNG_INIT_LO:   prng_init[31:0]  <= merged(prng_init[31:0]);
        REG_PRNG_INIT_HI:   prng_init[63:32] <= merged(prng_init[63:32]);
        REG_MEM_BASE:       mem_base         <= merged(mem_base);
        REG_MEM_LIMIT:      mem_limit        <= merged(mem_limit);
        REG_RESET_VEC:      reset_vec        <= merged(reset_vec);
        REG_TOHOST_ADDR:    tohost_addr      <= merged(tohost_addr);
        REG_TRACE_CTRL:     trace_ctrl       <= 2'(merged(32'(trace_ctrl)));
        REG_UART_RX_BIT:    uart_rx_bit      <= 24'(merged(32'(uart_rx_bit)));
        REG_UART_TX_PERIOD: uart_tx_period   <= merged(uart_tx_period);
        REG_UART_TX_GAP:    uart_tx_gap      <= 8'(merged(32'(uart_tx_gap)));
        REG_FI_CTRL: begin
          fi_mode             <= fi_ctrl_written[3:0];
          fi_start_on_release <= fi_ctrl_written[4];
        end
        REG_FI_ARG0:        fi_arg0      <= merged(fi_arg0);
        REG_FI_ARG1:        fi_arg1      <= merged(fi_arg1);
        REG_FI_SEED:        fi_seed      <= merged(fi_seed);
        REG_FI_LATENCY:     fi_latency   <= 4'(merged(32'(fi_latency)));
        REG_FI_PHASE_OFS:   fi_phase_ofs <= 9'(merged(32'(fi_phase_ofs)));
        REG_SCAN_CTRL:      scan_pattern_scan_en <= scan_ctrl_written[1];
        REG_SCAN_LEN:       scan_len             <= 11'(merged(32'(scan_len)));
        REG_SCAN_ADDR:      scan_addr            <= 10'(merged(32'(scan_addr)));
        REG_SCAN_PATTERN:   scan_addr            <= scan_addr + 1'b1;
        REG_UART_MATCH_LEN: begin
          match_len[0] <= MATCH_LEN_W'(merged(32'(match_len[0])));
          match_len[1] <= MATCH_LEN_W'(merged(32'(match_len[1]) << 8) >> 8);
        end
        default: begin
          for (int w = 0; w < MATCH_BYTES / 4; w++) begin
            if (reg_waddr == REG_UART_MATCH0 + 12'(4 * w))
              match_pattern[0][32 * w +: 32] <= merged(match_pattern[0][32 * w +: 32]);
            if (reg_waddr == REG_UART_MATCH1 + 12'(4 * w))
              match_pattern[1][32 * w +: 32] <= merged(match_pattern[1][32 * w +: 32]);
          end
          for (int w = 0; w < 16; w++)
            if (reg_waddr == REG_FI_PHASE_MASK + 12'(4 * w))
              fi_phase_mask[32 * w +: 32] <= merged(fi_phase_mask[32 * w +: 32]);
          for (int t = 0; t < TRIGGERS; t++) begin
            if (reg_waddr == REG_TRIG + 12'(16 * t))
              trig_ctrl[t] <= merged(trig_ctrl[t]) & 32'hFFFF_03FF;
            if (reg_waddr == REG_TRIG + 12'(16 * t + 4))
              trig_arg0[t] <= merged(trig_arg0[t]);
            if (reg_waddr == REG_TRIG + 12'(16 * t + 8))
              trig_arg1[t] <= merged(trig_arg1[t]);
          end
        end
      endcase
      end
      pin_ctrl[5:4] <= (reg_write && reg_waddr == REG_PIN_CTRL ? 2'(merged(32'(pin_ctrl)) >> 4) : pin_ctrl[5:4])
                       & ~trigger_irq_clear | trigger_irq_set;
    end
  end

  // ---- link slave ----
  logic [63:0]       link_cyc;
  logic [31:0]       link_rd;
  logic [31:0]       link_wr;
  logic [63:0]       tohost_val;
  logic [63:0]       tohost_cyc;
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
  logic [LINK_W-1:0] slave_io_o;
  logic              slave_io_oe;
  logic [2:0]        link_state;

  fbu_link_slave #(.BEATS(BEATS)) link (
    .clk, .arst_n(blocks_rst_n),
    .cfg_det(link_cfg[0]), .cfg_gap_pct(link_cfg[7:1]), .cfg_rd_lat(link_cfg[31:16]),
    .cfg_wdog(link_wdog[15:0]), .cfg_mutate(link_wdog[17:16]),
    .cfg_mem_base(mem_base), .cfg_mem_limit(mem_limit), .cfg_reset_vec(reset_vec),
    .cfg_tohost_addr(tohost_addr),
    .prng_load(written(REG_PRNG_LOAD)), .prng_init,
    .rst_n_pin(rst_n), .dir, .req, .wr, .io_i, .io_o(slave_io_o), .io_oe(slave_io_oe), .ready, .rvalid,
    .m_req_valid, .m_req_ready, .m_req_wr, .m_req_addr, .m_req_data,
    .m_rsp_valid, .m_rsp_data, .m_rsp_err,
    .cyc(link_cyc), .state_now(link_state), .n_rd(link_rd), .n_wr(link_wr), .tohost_seen, .tohost_val, .tohost_cyc,
    .err_now, .err_sticky, .err_count, .first_err, .first_err_cyc,
    .rec_valid, .rec_cyc, .rec_wr, .rec_addr, .rec_line,
    .rec_tohost, .rec_tohost_cyc(rec_end_cyc), .rec_tohost_val);

  // ---- test mode: fbu_scan has io instead of the link slave ----
  logic [7:0] scan_in;
  logic [7:0] scan_capture;
  logic       scan_running;
  logic       scan_done;

  fbu_scan scan (
    .clk, .arst_n(blocks_rst_n),
    .start(written(REG_SCAN_CTRL) && reg_wdata[0]), .cfg_len(scan_len),
    .cfg_pattern_scan_en(scan_pattern_scan_en), .cfg_scan_en(pin_ctrl[3]),
    .addr(scan_addr), .pattern_write(written(REG_SCAN_PATTERN)), .pattern_data(reg_wdata[8:0]),
    .capture_data(scan_capture),
    .scan_out(io_i[15:8]), .scan_in, .scan_en, .running(scan_running), .done(scan_done));

  assign io_o            = test_mode ? {8'h00, scan_in} : slave_io_o;
  assign io_oe           = test_mode ? {8'h00, 8'hFF} : {LINK_W{slave_io_oe}};
  assign link_error_seen = err_sticky != '0;

  // ---- control pins ----
  logic        uart_rx_from_uart;
  logic [31:0] reset_count;
  logic [63:0] cycles_total;
  logic [15:0] gate_passes;
  logic [15:0] gate_fails;
  logic        gate_gave_up;
  logic [32:0] gate_last_header;

  logic        fault_inject_d;
  logic [1:0]  trigger_irq_set;
  logic [1:0]  trigger_irq_clear;
  logic [1:0]  trigger_irq_pulse;
  logic        trigger_reset;
  logic [31:0] trigger_reset_cycles;
  logic        trigger_fault_start;

  fbu_pin_ctl pins (
    .clk, .arst_n(blocks_rst_n),
    .cfg_release(pin_ctrl[0]), .cfg_fault_inject(fault_inject_d),
    .cfg_test_mode(pin_ctrl[2]), .cfg_irq(pin_ctrl[5:4] | trigger_irq_pulse),
    .cfg_rx_force_en(pin_ctrl[6]), .cfg_rx_force_val(pin_ctrl[7]),
    .reset_pulse_start(written(REG_RST_PULSE) || trigger_reset),
    .reset_pulse_cycles(trigger_reset ? trigger_reset_cycles : reg_wdata),
    .cfg_gate_enable(bootgate[0]), .cfg_gate_selftest(bootgate[1]),
    .cfg_gate_retries(bootgate[7:4]), .cfg_gate_timeout(bootgate[31:16]),
    .req, .wr, .io_i, .uart_rx_from_uart,
    .rst_n, .irq, .fault_inject, .test_mode, .uart_rx,
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

  // ---- fault_inject pattern ----
  logic        rst_n_q;
  logic        released;
  logic        fi_running;
  logic [8:0]  fi_phase_now;
  logic [63:0] fi_high_cycles;
  logic [31:0] fi_edges;
  logic [31:0] fi_events [9];

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n)
      rst_n_q <= 1'b0;
    else
      rst_n_q <= rst_n;
  end

  assign released = rst_n && !rst_n_q;

  fbu_fi_gen fault (
    .clk, .arst_n(blocks_rst_n),
    .cfg_mode(fi_mode), .cfg_static(pin_ctrl[1]), .cfg_arg0(fi_arg0), .cfg_arg1(fi_arg1),
    .cfg_seed(fi_seed), .cfg_phase_ofs(fi_phase_ofs), .cfg_latency(fi_latency),
    .cfg_phase_mask(fi_phase_mask),
    .start((written(REG_FI_CTRL) && reg_wdata[8]) || trigger_fault_start || (fi_start_on_release && released)),
    .stop(written(REG_FI_CTRL) && reg_wdata[9]),
    .clear_counts(written(REG_FI_CTRL) && reg_wdata[10]),
    .chip_in_reset(!rst_n), .link_cyc_low(link_cyc[8:0]),
    .fault_inject_d, .running(fi_running), .chip_phase_now(fi_phase_now),
    .high_cycles(fi_high_cycles), .edges(fi_edges), .events(fi_events));

  // ---- status and clk_out ----
  localparam int CLKOUT_WINDOW_LOG2 = 20;

  logic [31:0] stat_last;
  logic [31:0] stat_min;
  logic [31:0] stat_max;
  logic [31:0] stat_edges;
  logic [1:0]  stat_class;
  logic        stat_level;
  logic [31:0] stat_glitches;
  logic [31:0] clkout_edges;

  fbu_status_mon #(.CLKOUT_WINDOW_LOG2(CLKOUT_WINDOW_LOG2)) status_mon (
    .clk, .arst_n(blocks_rst_n), .status, .clk_out, .clear(written(REG_STAT_CLASS)),
    .last(stat_last), .min(stat_min), .max(stat_max), .edges(stat_edges),
    .status_class(stat_class), .level(stat_level), .glitches(stat_glitches), .clkout_edges);

  // ---- triggers ----
  logic [3:0]  trig_source [TRIGGERS];
  logic [3:0]  trig_action [TRIGGERS];
  logic        trig_repeat [TRIGGERS];
  logic        trig_line   [TRIGGERS];
  logic [15:0] trig_length [TRIGGERS];
  logic        trig_arm    [TRIGGERS];
  logic        trig_disarm [TRIGGERS];
  logic        trig_armed  [TRIGGERS];
  logic [31:0] trig_fired  [TRIGGERS];

  always_comb begin
    for (int t = 0; t < TRIGGERS; t++) begin
      trig_source[t] = trig_ctrl[t][3:0];
      trig_action[t] = trig_ctrl[t][7:4];
      trig_repeat[t] = trig_ctrl[t][8];
      trig_line[t]   = trig_ctrl[t][9];
      trig_length[t] = trig_ctrl[t][31:16];
      trig_arm[t]    = written(REG_TRIG + 12'(16 * t)) && reg_wdata[10];
      trig_disarm[t] = written(REG_TRIG + 12'(16 * t)) && reg_wdata[11];
    end
  end

  fbu_triggers #(.TRIGGERS(TRIGGERS)) triggers (
    .clk, .arst_n(blocks_rst_n),
    .cfg_source(trig_source), .cfg_action(trig_action), .cfg_repeat(trig_repeat),
    .cfg_line(trig_line), .cfg_length(trig_length), .cfg_arg0(trig_arg0), .cfg_arg1(trig_arg1),
    .arm(trig_arm), .disarm(trig_disarm),
    .link_cyc_low(link_cyc[31:0]), .match_pulse, .link_state, .link_error(err_now != '0),
    .armed(trig_armed), .fired(trig_fired),
    .reset_start(trigger_reset), .reset_cycles(trigger_reset_cycles),
    .irq_set(trigger_irq_set), .irq_clear(trigger_irq_clear), .irq_pulse(trigger_irq_pulse),
    .fault_start(trigger_fault_start));

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
      REG_PARTIAL_WRITES:   reg_rdata = partial_writes;
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
      REG_TOHOST_CYC_LO:    reg_rdata = tohost_cyc[31:0];
      REG_TOHOST_CYC_HI:    reg_rdata = tohost_cyc[63:32];
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
      REG_FI_CTRL:          reg_rdata = {15'd0, fi_running, 11'd0, fi_start_on_release, fi_mode};
      REG_FI_ARG0:          reg_rdata = fi_arg0;
      REG_FI_ARG1:          reg_rdata = fi_arg1;
      REG_FI_SEED:          reg_rdata = fi_seed;
      REG_FI_HIGH_CYC_LO:   reg_rdata = fi_high_cycles[31:0];
      REG_FI_HIGH_CYC_HI:   reg_rdata = fi_high_cycles[63:32];
      REG_FI_EDGES:         reg_rdata = fi_edges;
      REG_FI_LATENCY:       reg_rdata = 32'(fi_latency);
      REG_FI_PHASE_OFS:     reg_rdata = 32'(fi_phase_ofs);
      REG_FI_PHASE_NOW:     reg_rdata = 32'(fi_phase_now);
      REG_SCAN_CTRL:        reg_rdata = {22'd0, scan_done, scan_running, 6'd0, scan_pattern_scan_en, 1'b0};
      REG_SCAN_LEN:         reg_rdata = 32'(scan_len);
      REG_SCAN_ADDR:        reg_rdata = 32'(scan_addr);
      REG_SCAN_CAPTURE:     reg_rdata = {24'd0, scan_capture};
      REG_STAT_LAST:        reg_rdata = stat_last;
      REG_STAT_MIN:         reg_rdata = stat_min;
      REG_STAT_MAX:         reg_rdata = stat_max;
      REG_STAT_EDGES:       reg_rdata = stat_edges;
      REG_STAT_CLASS:       reg_rdata = {23'd0, stat_level, 6'd0, stat_class};
      REG_STAT_GLITCH:      reg_rdata = stat_glitches;
      REG_CLKOUT_EDGES:     reg_rdata = clkout_edges;
      REG_CLKOUT_WINDOW:    reg_rdata = 32'd1 << CLKOUT_WINDOW_LOG2;
      default: begin
        for (int w = 0; w < 10; w++)
          if (reg_raddr == REG_TRACE_HEAD + 12'(4 * w))
            reg_rdata = trace_head[32 * w +: 32];
        for (int g = 0; g < 9; g++)
          if (reg_raddr == REG_FI_EVENTS + 12'(4 * g))
            reg_rdata = fi_events[g];
        for (int w = 0; w < 16; w++)
          if (reg_raddr == REG_FI_PHASE_MASK + 12'(4 * w))
            reg_rdata = fi_phase_mask[32 * w +: 32];
        for (int t = 0; t < TRIGGERS; t++) begin
          if (reg_raddr == REG_TRIG + 12'(16 * t))
            reg_rdata = trig_ctrl[t] | {19'd0, trig_armed[t], 12'd0};
          if (reg_raddr == REG_TRIG + 12'(16 * t + 4))
            reg_rdata = trig_arg0[t];
          if (reg_raddr == REG_TRIG + 12'(16 * t + 8))
            reg_rdata = trig_arg1[t];
          if (reg_raddr == REG_TRIG + 12'(16 * t + 12))
            reg_rdata = trig_fired[t];
        end
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
