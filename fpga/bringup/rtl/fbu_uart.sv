///////////////////////////////////////////////////////////////////////////////
// fbu_uart.sv -- the FPGA's console on the chip's uart_tx / uart_rx pins.
//
// Spec: hvl/pin/pin_uart_agent.sv.  8N1.  The chip's bit time is
// 16 * (divisor << UART_PRESCALE) core cycles and is invisible at the pins, so
// the PS sets both directions' bit times to match the program.
//
// Transmit entries are {kind, data}:
//   TX_BYTE      a normal frame
//   TX_BAD_STOP  the frame with its stop bit driven 0 (uart_send_ferr)
//   TX_BREAK     the line held low for `data` bit times
//   TX_IDLE      the line held high for `data` bit times
// The transmit bit period is fractional (1/256 cycle) so the baud tolerance of
// the chip's receiver can be swept.
//
// Received bytes are pushed as {framing_error, byte}.  Two matchers compare the
// most recent received bytes against a PS-written pattern, last byte first in
// pattern[7:0]; a hit is sticky until cleared and also pulses for triggers.
///////////////////////////////////////////////////////////////////////////////
module fbu_uart #(
  parameter int RX_FIFO_LOG2 = 10,
  parameter int TX_FIFO_LOG2 = 6,
  parameter int MATCH_BYTES  = 32,
  localparam int MATCH_LEN_W = $clog2(MATCH_BYTES + 1)
)(
  input  logic                     clk,
  input  logic                     arst_n,
  input  logic                     clear,

  input  logic [23:0]              cfg_rx_bit_cycles,
  input  logic [31:0]              cfg_tx_bit_period_q8,
  input  logic [7:0]               cfg_tx_gap_bits,

  input  logic                     uart_tx,
  output logic                     uart_rx,

  output logic [8:0]               rx_head,
  output logic                     rx_valid,
  input  logic                     rx_pop,
  output logic [RX_FIFO_LOG2:0]    rx_level,
  output logic                     rx_overflow,

  input  logic                     tx_push,
  input  logic [9:0]               tx_entry,
  output logic                     tx_full,
  output logic                     tx_overflow,
  output logic [TX_FIFO_LOG2:0]    tx_level,
  output logic                     tx_busy,

  output logic [31:0]              n_rx,
  output logic [31:0]              n_tx,
  output logic [31:0]              n_framing_errors,

  input  logic [MATCH_LEN_W-1:0]   cfg_match_len   [2],
  input  logic [8*MATCH_BYTES-1:0] cfg_match_pattern [2],
  input  logic                     match_clear     [2],
  output logic                     match_hit       [2],
  output logic                     match_pulse     [2]
);

  typedef enum logic [1:0] {TX_BYTE, TX_BAD_STOP, TX_BREAK, TX_IDLE} tx_kind_t;

  // ---- receive ----
  typedef enum logic [1:0] {RX_WAIT_START, RX_CHECK_START, RX_DATA, RX_STOP} rx_state_t;

  logic        line_meta;
  logic        line;
  logic        line_prev;
  rx_state_t   rx_state;
  logic [23:0] rx_countdown;
  logic [2:0]  rx_bit;
  logic [7:0]  rx_shift;
  logic        rx_byte_done;
  logic [8:0]  rx_byte;
  logic [23:0] rx_bit_cycles;
  logic        rx_empty;

  assign rx_bit_cycles = cfg_rx_bit_cycles == '0 ? 24'd1 : cfg_rx_bit_cycles;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      line_meta <= 1'b1;
      line      <= 1'b1;
      line_prev <= 1'b1;
    end else begin
      line_meta <= uart_tx;
      line      <= line_meta;
      line_prev <= line;
    end
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      rx_state     <= RX_WAIT_START;
      rx_countdown <= '0;
      rx_bit       <= '0;
      rx_shift     <= '0;
      rx_byte_done <= 1'b0;
      rx_byte      <= '0;
    end else if (clear) begin
      rx_state     <= RX_WAIT_START;
      rx_byte_done <= 1'b0;
    end else begin
      rx_byte_done <= 1'b0;
      case (rx_state)
        RX_WAIT_START: begin
          if (line_prev && !line) begin
            rx_countdown <= rx_bit_cycles / 2 - 24'd1;
            rx_state     <= RX_CHECK_START;
          end
        end
        RX_CHECK_START: begin
          if (rx_countdown != '0)
            rx_countdown <= rx_countdown - 24'd1;
          else if (line)
            rx_state <= RX_WAIT_START;
          else begin
            rx_countdown <= rx_bit_cycles - 24'd1;
            rx_bit       <= '0;
            rx_state     <= RX_DATA;
          end
        end
        RX_DATA: begin
          if (rx_countdown != '0)
            rx_countdown <= rx_countdown - 24'd1;
          else begin
            rx_shift     <= {line, rx_shift[7:1]};
            rx_bit       <= rx_bit + 3'd1;
            rx_countdown <= rx_bit_cycles - 24'd1;
            if (rx_bit == 3'd7)
              rx_state <= RX_STOP;
          end
        end
        RX_STOP: begin
          if (rx_countdown != '0)
            rx_countdown <= rx_countdown - 24'd1;
          else begin
            rx_byte_done <= 1'b1;
            rx_byte      <= {!line, rx_shift};
            rx_state     <= RX_WAIT_START;
          end
        end
        default: rx_state <= RX_WAIT_START;
      endcase
    end
  end

  fbu_fifo #(.WIDTH(9), .DEPTH_LOG2(RX_FIFO_LOG2)) rx_fifo (
    .clk, .arst_n, .clear,
    .push(rx_byte_done), .push_data(rx_byte), .full(), .overflow(rx_overflow),
    .pop(rx_pop), .head(rx_head), .empty(rx_empty), .level(rx_level));

  assign rx_valid = !rx_empty;

  // ---- matchers on the received stream ----
  logic [8*MATCH_BYTES-1:0] recent;
  logic                     recent_updated;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      recent         <= '0;
      recent_updated <= 1'b0;
    end else begin
      recent_updated <= rx_byte_done;
      if (rx_byte_done)
        recent <= {recent[8*MATCH_BYTES-9:0], rx_byte[7:0]};
    end
  end

  for (genvar m = 0; m < 2; m++) begin : g_match
    logic equal;

    always_comb begin
      equal = cfg_match_len[m] != '0;
      for (int i = 0; i < MATCH_BYTES; i++)
        if (i < int'(cfg_match_len[m]) && recent[8*i +: 8] != cfg_match_pattern[m][8*i +: 8])
          equal = 1'b0;
    end

    assign match_pulse[m] = recent_updated && equal;

    always_ff @(posedge clk or negedge arst_n) begin
      if (!arst_n)
        match_hit[m] <= 1'b0;
      else if (match_clear[m])
        match_hit[m] <= 1'b0;
      else if (match_pulse[m])
        match_hit[m] <= 1'b1;
    end
  end

  // ---- transmit ----
  typedef enum logic [1:0] {TXS_IDLE, TXS_FRAME, TXS_LEVEL, TXS_GAP} tx_state_t;

  logic        tx_empty;
  logic [9:0]  tx_head;
  logic        tx_pop;
  tx_state_t   tx_state;
  logic [8:0]  tx_shift;
  logic [7:0]  tx_bits_left;
  logic [31:0] tx_phase_q8;
  logic        tx_bit_end;
  tx_kind_t    tx_head_kind;

  fbu_fifo #(.WIDTH(10), .DEPTH_LOG2(TX_FIFO_LOG2)) tx_fifo (
    .clk, .arst_n, .clear,
    .push(tx_push), .push_data(tx_entry), .full(tx_full), .overflow(tx_overflow),
    .pop(tx_pop), .head(tx_head), .empty(tx_empty), .level(tx_level));

  assign tx_head_kind = tx_kind_t'(tx_head[9:8]);
  assign tx_busy      = tx_state != TXS_IDLE;
  assign tx_pop       = tx_state == TXS_IDLE && !tx_empty;
  assign tx_bit_end   = tx_phase_q8 + 32'd256 >= cfg_tx_bit_period_q8;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      tx_state      <= TXS_IDLE;
      tx_shift      <= '1;
      tx_bits_left  <= '0;
      tx_phase_q8   <= '0;
      uart_rx       <= 1'b1;
    end else if (clear) begin
      tx_state <= TXS_IDLE;
      uart_rx  <= 1'b1;
    end else begin
      case (tx_state)
        TXS_IDLE: begin
          uart_rx     <= 1'b1;
          tx_phase_q8 <= '0;
          if (tx_pop) begin
            case (tx_head_kind)
              TX_BYTE: begin
                tx_shift     <= {1'b1, tx_head[7:0]};
                tx_bits_left <= 8'd10;
                tx_state     <= TXS_FRAME;
                uart_rx      <= 1'b0;
              end
              TX_BAD_STOP: begin
                tx_shift     <= {1'b0, tx_head[7:0]};
                tx_bits_left <= 8'd10;
                tx_state     <= TXS_FRAME;
                uart_rx      <= 1'b0;
              end
              TX_BREAK: begin
                tx_bits_left <= tx_head[7:0];
                tx_state     <= TXS_LEVEL;
                uart_rx      <= 1'b0;
              end
              default: begin
                tx_bits_left <= tx_head[7:0];
                tx_state     <= TXS_LEVEL;
              end
            endcase
          end
        end

        TXS_FRAME: begin
          if (!tx_bit_end) begin
            tx_phase_q8 <= tx_phase_q8 + 32'd256;
          end else begin
            tx_phase_q8  <= tx_phase_q8 + 32'd256 - cfg_tx_bit_period_q8;
            tx_shift     <= {1'b1, tx_shift[8:1]};
            tx_bits_left <= tx_bits_left - 8'd1;
            if (tx_bits_left == 8'd1) begin
              uart_rx      <= 1'b1;
              tx_bits_left <= cfg_tx_gap_bits;
              if (cfg_tx_gap_bits != '0)
                tx_state <= TXS_GAP;
              else
                tx_state <= TXS_IDLE;
            end else begin
              uart_rx <= tx_shift[0];
            end
          end
        end

        TXS_LEVEL, TXS_GAP: begin
          if (tx_bits_left == '0) begin
            uart_rx  <= 1'b1;
            tx_state <= TXS_IDLE;
          end else if (!tx_bit_end) begin
            tx_phase_q8 <= tx_phase_q8 + 32'd256;
          end else begin
            tx_phase_q8  <= tx_phase_q8 + 32'd256 - cfg_tx_bit_period_q8;
            tx_bits_left <= tx_bits_left - 8'd1;
            if (tx_bits_left == 8'd1) begin
              uart_rx  <= 1'b1;
              tx_state <= TXS_IDLE;
            end
          end
        end

        default: tx_state <= TXS_IDLE;
      endcase
    end
  end

  // ---- counters ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      n_rx             <= '0;
      n_tx             <= '0;
      n_framing_errors <= '0;
    end else if (clear) begin
      n_rx             <= '0;
      n_tx             <= '0;
      n_framing_errors <= '0;
    end else begin
      if (rx_byte_done)
        n_rx <= n_rx + 32'd1;
      if (rx_byte_done && rx_byte[8])
        n_framing_errors <= n_framing_errors + 32'd1;
      if (tx_pop)
        n_tx <= n_tx + 32'd1;
    end
  end

endmodule
