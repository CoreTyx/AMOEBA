///////////////////////////////////////////////////////////////////////////////
// fbu_pin_ctl.sv -- the chip's control inputs: rst_n, irq[1:0], fault_inject,
// test_mode, scan_en, and the uart_rx override.
//
// Boot gate (forte_link_pkg, "no link training"): after every release of rst_n
// the first transaction must be a read of the reset vector.  The gate watches
// the pins for it; on a different header, or none within the timeout, it
// re-asserts rst_n for a few cycles and tries again, and after the allowed
// retries holds the chip in reset.  Self-test inverts the verdict, so the
// failure path runs on every build.
///////////////////////////////////////////////////////////////////////////////
module fbu_pin_ctl import forte_link_pkg::*; #(
  parameter logic [15:0] BOOT_HDR_HI = 16'h8000,
  parameter logic [15:0] BOOT_HDR_LO = 16'h0000,
  parameter int          GATE_RESET_CYCLES = 16
)(
  input  logic              clk,
  input  logic              arst_n,

  input  logic              cfg_release,
  input  logic [1:0]        cfg_irq,
  input  logic              cfg_fault_inject,
  input  logic              cfg_test_mode,
  input  logic              cfg_scan_en,
  input  logic              cfg_rx_force_en,
  input  logic              cfg_rx_force_val,

  input  logic              reset_pulse_start,
  input  logic [31:0]       reset_pulse_cycles,

  input  logic              cfg_gate_enable,
  input  logic              cfg_gate_selftest,
  input  logic [3:0]        cfg_gate_retries,
  input  logic [15:0]       cfg_gate_timeout,

  input  logic              req,
  input  logic              wr,
  input  logic [LINK_W-1:0] io_i,
  input  logic              uart_rx_from_uart,

  output logic              rst_n,
  output logic [1:0]        irq,
  output logic              fault_inject,
  output logic              test_mode,
  output logic              scan_en,
  output logic              uart_rx,

  output logic [31:0]       reset_count,
  output logic [63:0]       cycles_total,
  output logic [15:0]       gate_passes,
  output logic [15:0]       gate_fails,
  output logic              gate_gave_up,
  output logic [32:0]       gate_last_header
);

  typedef enum logic [2:0] {
    G_IDLE,
    G_WAIT_HEADER_HI,
    G_WAIT_HEADER_LO,
    G_RESETTING,
    G_GAVE_UP
  } gate_state_t;

  gate_state_t gate_state;
  logic [15:0] gate_timer;
  logic [3:0]  gate_retries_used;
  logic [15:0] header_hi;
  logic        header_wr;
  logic        gate_holds_reset;
  logic        header_is_boot_fetch;
  logic        gate_verdict_pass;

  logic [31:0] pulse_left;
  logic        pulse_active;
  logic        rst_n_d;
  logic        released;
  logic        released_by_gate;

  assign pulse_active      = pulse_left != '0;
  assign gate_holds_reset  = gate_state == G_RESETTING || gate_state == G_GAVE_UP;
  assign rst_n_d           = cfg_release && !pulse_active && !reset_pulse_start && !gate_holds_reset;
  assign released          = rst_n_d && !rst_n;
  assign header_is_boot_fetch = header_hi == BOOT_HDR_HI && io_i == BOOT_HDR_LO && !header_wr;
  assign gate_verdict_pass    = header_is_boot_fetch != cfg_gate_selftest;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      rst_n        <= 1'b0;
      irq          <= '0;
      fault_inject <= 1'b0;
      test_mode    <= 1'b0;
      scan_en      <= 1'b0;
      uart_rx      <= 1'b1;
    end else begin
      rst_n        <= rst_n_d;
      irq          <= cfg_irq;
      fault_inject <= cfg_fault_inject;
      test_mode    <= cfg_test_mode;
      scan_en      <= cfg_scan_en;
      uart_rx      <= cfg_rx_force_en ? cfg_rx_force_val : uart_rx_from_uart;
    end
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      pulse_left   <= '0;
      reset_count  <= '0;
      cycles_total <= '0;
    end else begin
      cycles_total <= cycles_total + 64'd1;
      if (reset_pulse_start)
        pulse_left <= reset_pulse_cycles - 32'd1;
      else if (pulse_active)
        pulse_left <= pulse_left - 32'd1;
      if (rst_n && !rst_n_d)
        reset_count <= reset_count + 32'd1;
    end
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      gate_state        <= G_IDLE;
      gate_timer        <= '0;
      gate_retries_used <= '0;
      header_hi         <= '0;
      header_wr         <= 1'b0;
      released_by_gate  <= 1'b0;
      gate_passes       <= '0;
      gate_fails        <= '0;
      gate_gave_up      <= 1'b0;
      gate_last_header  <= '0;
    end else if (!cfg_gate_enable) begin
      gate_state        <= G_IDLE;
      gate_retries_used <= '0;
      released_by_gate  <= 1'b0;
      gate_gave_up      <= 1'b0;
    end else begin
      case (gate_state)
        G_IDLE: begin
          if (released) begin
            if (!released_by_gate)
              gate_retries_used <= '0;
            released_by_gate <= 1'b0;
            gate_timer       <= cfg_gate_timeout;
            gate_state       <= G_WAIT_HEADER_HI;
          end
        end

        G_WAIT_HEADER_HI: begin
          if (!rst_n) begin
            gate_state <= G_IDLE;
          end else if (req) begin
            header_hi  <= io_i;
            header_wr  <= wr;
            gate_state <= G_WAIT_HEADER_LO;
          end else if (gate_timer == '0) begin
            gate_fails       <= gate_fails + 16'd1;
            gate_last_header <= '1;
            gate_timer       <= 16'(GATE_RESET_CYCLES);
            gate_state       <= G_RESETTING;
          end else begin
            gate_timer <= gate_timer - 16'd1;
          end
        end

        G_WAIT_HEADER_LO: begin
          gate_last_header <= {header_wr, header_hi, io_i};
          if (gate_verdict_pass) begin
            gate_passes <= gate_passes + 16'd1;
            gate_state  <= G_IDLE;
          end else begin
            gate_fails <= gate_fails + 16'd1;
            gate_timer <= 16'(GATE_RESET_CYCLES);
            gate_state <= G_RESETTING;
          end
        end

        G_RESETTING: begin
          if (gate_timer != '0) begin
            gate_timer <= gate_timer - 16'd1;
          end else if (gate_retries_used == cfg_gate_retries) begin
            gate_gave_up <= 1'b1;
            gate_state   <= G_GAVE_UP;
          end else begin
            gate_retries_used <= gate_retries_used + 4'd1;
            released_by_gate  <= 1'b1;
            gate_state        <= G_IDLE;
          end
        end

        G_GAVE_UP: begin
        end

        default: gate_state <= G_IDLE;
      endcase
    end
  end

endmodule
