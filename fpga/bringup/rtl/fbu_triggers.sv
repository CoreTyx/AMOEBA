///////////////////////////////////////////////////////////////////////////////
// fbu_triggers.sv -- control-pin actions at an exact cycle or event, which the
// PS cannot time (docs/impl_plan_fpga_rtl_freeze.md s5.4).
//
// Each trigger, once armed, waits for its source and performs its action;
// with repeat it re-arms, otherwise it disarms.  Sources: link cycle == arg0,
// a console matcher, the link slave entering state arg0, a random delay of
// arg0 + (rand & arg1) cycles, any link error.  Actions: rst_n low, irq line
// set / clear (the same irq bits the PS writes) / pulse, start the
// fault_inject pattern.  `length` is the rst_n or irq pulse in cycles.
///////////////////////////////////////////////////////////////////////////////
module fbu_triggers #(
  parameter int TRIGGERS = 4
)(
  input  logic        clk,
  input  logic        arst_n,

  input  logic [3:0]  cfg_source [TRIGGERS],
  input  logic [3:0]  cfg_action [TRIGGERS],
  input  logic        cfg_repeat [TRIGGERS],
  input  logic        cfg_line   [TRIGGERS],
  input  logic [15:0] cfg_length [TRIGGERS],
  input  logic [31:0] cfg_arg0   [TRIGGERS],
  input  logic [31:0] cfg_arg1   [TRIGGERS],
  input  logic        arm        [TRIGGERS],
  input  logic        disarm     [TRIGGERS],

  input  logic [31:0] link_cyc_low,
  input  logic        match_pulse [2],
  input  logic [2:0]  link_state,
  input  logic        link_error,

  output logic        armed       [TRIGGERS],
  output logic [31:0] fired       [TRIGGERS],

  output logic        reset_start,
  output logic [31:0] reset_cycles,
  output logic [1:0]  irq_set,
  output logic [1:0]  irq_clear,
  output logic [1:0]  irq_pulse,
  output logic        fault_start
);

  localparam logic [3:0] SRC_CYCLE  = 4'd1;
  localparam logic [3:0] SRC_MATCH0 = 4'd2;
  localparam logic [3:0] SRC_MATCH1 = 4'd3;
  localparam logic [3:0] SRC_STATE  = 4'd4;
  localparam logic [3:0] SRC_RANDOM = 4'd5;
  localparam logic [3:0] SRC_ERROR  = 4'd6;

  localparam logic [3:0] ACT_RESET     = 4'd1;
  localparam logic [3:0] ACT_IRQ_SET   = 4'd2;
  localparam logic [3:0] ACT_IRQ_CLEAR = 4'd3;
  localparam logic [3:0] ACT_IRQ_PULSE = 4'd4;
  localparam logic [3:0] ACT_FAULT     = 4'd5;

  logic [2:0]  link_state_prev;
  logic        fire        [TRIGGERS];
  logic [31:0] countdown   [TRIGGERS];
  logic [31:0] rand_state  [TRIGGERS];
  logic [15:0] irq_pulse_left [2];

  function automatic logic [31:0] xorshift32(input logic [31:0] x);
    logic [31:0] a;
    logic [31:0] b;
    a = x ^ (x << 13);
    b = a ^ (a >> 17);
    return b ^ (b << 5);
  endfunction

  always_comb begin
    for (int t = 0; t < TRIGGERS; t++) begin
      case (cfg_source[t])
        SRC_CYCLE:  fire[t] = link_cyc_low == cfg_arg0[t];
        SRC_MATCH0: fire[t] = match_pulse[0];
        SRC_MATCH1: fire[t] = match_pulse[1];
        SRC_STATE:  fire[t] = link_state == cfg_arg0[t][2:0] && link_state_prev != cfg_arg0[t][2:0];
        SRC_RANDOM: fire[t] = countdown[t] == '0;
        SRC_ERROR:  fire[t] = link_error;
        default:    fire[t] = 1'b0;
      endcase
      fire[t] = fire[t] && armed[t];
    end
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      link_state_prev <= '0;
      armed           <= '{default: 1'b0};
      fired           <= '{default: '0};
      countdown       <= '{default: '0};
      rand_state      <= '{default: 32'h1};
    end else begin
      link_state_prev <= link_state;
      for (int t = 0; t < TRIGGERS; t++) begin
        if (disarm[t]) begin
          armed[t] <= 1'b0;
        end else if (arm[t]) begin
          armed[t]      <= 1'b1;
          rand_state[t] <= xorshift32(rand_state[t] ^ cfg_arg1[t]);
          countdown[t]  <= cfg_arg0[t] + (rand_state[t] & cfg_arg1[t]);
        end else if (fire[t]) begin
          fired[t] <= fired[t] + 32'd1;
          armed[t] <= cfg_repeat[t];
          if (cfg_source[t] == SRC_RANDOM) begin
            rand_state[t] <= xorshift32(rand_state[t]);
            countdown[t]  <= cfg_arg0[t] + (xorshift32(rand_state[t]) & cfg_arg1[t]);
          end
        end else if (armed[t] && cfg_source[t] == SRC_RANDOM) begin
          countdown[t] <= countdown[t] - 32'd1;
        end
      end
    end
  end

  // ---- actions ----
  always_comb begin
    reset_start  = 1'b0;
    reset_cycles = '0;
    fault_start  = 1'b0;
    irq_set      = '0;
    irq_clear    = '0;
    for (int t = 0; t < TRIGGERS; t++) begin
      if (fire[t] && cfg_action[t] == ACT_IRQ_SET)
        irq_set[cfg_line[t]] = 1'b1;
      if (fire[t] && cfg_action[t] == ACT_IRQ_CLEAR)
        irq_clear[cfg_line[t]] = 1'b1;
      if (fire[t] && cfg_action[t] == ACT_RESET) begin
        reset_start  = 1'b1;
        reset_cycles = 32'(cfg_length[t]);
      end
      if (fire[t] && cfg_action[t] == ACT_FAULT)
        fault_start = 1'b1;
    end
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      irq_pulse      <= '0;
      irq_pulse_left <= '{default: '0};
    end else begin
      for (int line = 0; line < 2; line++) begin
        if (irq_pulse_left[line] != '0) begin
          irq_pulse_left[line] <= irq_pulse_left[line] - 16'd1;
          if (irq_pulse_left[line] == 16'd1)
            irq_pulse[line] <= 1'b0;
        end
      end
      for (int t = 0; t < TRIGGERS; t++) begin
        if (fire[t] && cfg_action[t] == ACT_IRQ_PULSE) begin
          irq_pulse[cfg_line[t]]      <= 1'b1;
          irq_pulse_left[cfg_line[t]] <= cfg_length[t];
        end
      end
    end
  end

endmodule
