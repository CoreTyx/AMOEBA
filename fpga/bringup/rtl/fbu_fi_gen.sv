///////////////////////////////////////////////////////////////////////////////
// fbu_fi_gen.sv -- the fault_inject pin (docs/impl_plan_fpga_rtl_freeze.md s5.4.1).
//
// The pin is the chip's master enable for its own injectors.  Every injection
// site fires when the chip's free-running 9-bit fault counter equals the
// site's phase.  The counter starts when the core leaves reset, a fixed number
// of cycles after rst_n release, so it is mirrored here:
//   chip_phase(t) = (link cycles since release (t) - cfg_phase_ofs) mod 512
// and the pin decided at cycle t enables the sites at chip_phase(t + latency).
// cfg_phase_ofs is the core's reset synchronisers, checked by calibration
// (CTRL-12b); cfg_latency covers this module's output flop, the chip's
// synchronizer and its enable register.
//
// Modes: STATIC follows cfg_static; SQUARE high arg1 of every arg0 cycles;
// RANDOM alternates dwells of arg0 + (rand & arg1) cycles; PULSE high arg0
// cycles once; BURST high for arg0 whole 512-cycle periods from phase 0;
// PHASE high at the masked phases for arg0 periods (0: until stopped);
// SINGLE as PHASE for one period.
//
// events[g] counts the site firings the pin let through, per site group.
///////////////////////////////////////////////////////////////////////////////
module fbu_fi_gen (
  input  logic         clk,
  input  logic         arst_n,

  input  logic [3:0]   cfg_mode,
  input  logic         cfg_static,
  input  logic [31:0]  cfg_arg0,
  input  logic [31:0]  cfg_arg1,
  input  logic [31:0]  cfg_seed,
  input  logic [8:0]   cfg_phase_ofs,
  input  logic [3:0]   cfg_latency,
  input  logic [511:0] cfg_phase_mask,
  input  logic         start,
  input  logic         stop,
  input  logic         clear_counts,

  input  logic         chip_in_reset,
  input  logic [8:0]   link_cyc_low,

  output logic         fault_inject_d,
  output logic         running,
  output logic [8:0]   chip_phase_now,
  output logic [63:0]  high_cycles,
  output logic [31:0]  edges,
  output logic [31:0]  events [9]
);

  localparam logic [3:0] MODE_STATIC = 4'd0;
  localparam logic [3:0] MODE_SQUARE = 4'd1;
  localparam logic [3:0] MODE_RANDOM = 4'd2;
  localparam logic [3:0] MODE_PULSE  = 4'd3;
  localparam logic [3:0] MODE_BURST  = 4'd4;
  localparam logic [3:0] MODE_PHASE  = 4'd5;
  localparam logic [3:0] MODE_SINGLE = 4'd6;

  // Site phases (ft_alu.sv, ft_mul.sv, ft_div.sv, regfile.sv, datapath.sv,
  // ifu.sv, lsu.sv); the pipeline-register mask is decided a cycle earlier.
  localparam int GROUPS = 9;
  localparam int G_ALU0 = 0, G_ALU1 = 1, G_CMP = 2, G_MUL = 3, G_DIV = 4,
                 G_RF = 5, G_PIPE = 6, G_ICACHE = 7, G_DCACHE = 8;

  function automatic logic site_in_group(input int g, input logic [8:0] p);
    case (g)
      G_ALU0:   return p == 9'h1FE || p == 9'h1EE || p == 9'h1DE;
      G_ALU1:   return p == 9'h1BE || p == 9'h1AE || p == 9'h19E;
      G_CMP:    return p == 9'h1CE || p == 9'h18E;
      G_MUL:    return p == 9'h17E;
      G_DIV:    return p == 9'h15E;
      G_RF:     return p == 9'h1FF;
      G_PIPE:   return p == 9'h1FF;
      G_ICACHE: return p == 9'h13E;
      G_DCACHE: return p == 9'h11E;
      default:  return 1'b0;
    endcase
  endfunction

  logic [8:0]  target_phase;
  logic [8:0]  pipe_target_phase;
  logic [31:0] count;
  logic [31:0] periods_left;
  logic        level;
  logic [31:0] rand_state;
  logic        pin_d;
  logic        pin_q;
  logic        waiting_for_period;
  logic        periodic_mode;

  assign chip_phase_now    = link_cyc_low - cfg_phase_ofs;
  assign target_phase      = chip_phase_now + 9'(cfg_latency);
  assign pipe_target_phase = target_phase + 9'd1;
  assign periodic_mode     = cfg_mode == MODE_BURST || cfg_mode == MODE_PHASE || cfg_mode == MODE_SINGLE;

  function automatic logic [31:0] xorshift32(input logic [31:0] x);
    logic [31:0] a;
    logic [31:0] b;
    a = x ^ (x << 13);
    b = a ^ (a >> 17);
    return b ^ (b << 5);
  endfunction

  always_comb begin
    case (cfg_mode)
      MODE_STATIC: pin_d = cfg_static;
      MODE_SQUARE: pin_d = running && count < cfg_arg1;
      MODE_RANDOM: pin_d = running && level;
      MODE_PULSE:  pin_d = running;
      MODE_BURST:  pin_d = running && !waiting_for_period;
      MODE_PHASE,
      MODE_SINGLE: pin_d = running && !waiting_for_period && cfg_phase_mask[target_phase];
      default:     pin_d = 1'b0;
    endcase
  end

  assign fault_inject_d = pin_d;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      running      <= 1'b0;
      count        <= '0;
      periods_left <= '0;
      level        <= 1'b0;
      rand_state   <= 32'h1;
      waiting_for_period <= 1'b0;
    end else if (stop) begin
      running <= 1'b0;
    end else if (start) begin
      running            <= !(cfg_mode == MODE_BURST && cfg_arg0 == '0);
      level              <= 1'b1;
      rand_state         <= cfg_seed == '0 ? 32'h1 : cfg_seed;
      periods_left       <= cfg_mode == MODE_SINGLE ? 32'd1 : cfg_arg0;
      waiting_for_period <= periodic_mode && target_phase != 9'h1FF;
      if (cfg_mode == MODE_RANDOM)
        count <= cfg_arg0 + ((cfg_seed == '0 ? 32'h1 : cfg_seed) & cfg_arg1);
      else
        count <= '0;
    end else if (running && waiting_for_period) begin
      if (target_phase == 9'h1FF)
        waiting_for_period <= 1'b0;
    end else if (running) begin
      case (cfg_mode)
        MODE_SQUARE: begin
          if (count + 32'd1 >= cfg_arg0)
            count <= '0;
          else
            count <= count + 32'd1;
        end
        MODE_RANDOM: begin
          if (count == '0) begin
            rand_state <= xorshift32(rand_state);
            count      <= cfg_arg0 + (xorshift32(rand_state) & cfg_arg1);
            level      <= !level;
          end else begin
            count <= count - 32'd1;
          end
        end
        MODE_PULSE: begin
          if (count + 32'd1 >= cfg_arg0)
            running <= 1'b0;
          count <= count + 32'd1;
        end
        MODE_BURST, MODE_PHASE, MODE_SINGLE: begin
          if (target_phase == 9'h1FF && periods_left != '0) begin
            periods_left <= periods_left - 32'd1;
            if (periods_left == 32'd1)
              running <= 1'b0;
          end
        end
        default: ;
      endcase
    end
  end

  // ---- accounting ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      pin_q       <= 1'b0;
      high_cycles <= '0;
      edges       <= '0;
      events      <= '{default: '0};
    end else if (clear_counts) begin
      pin_q       <= pin_d;
      high_cycles <= '0;
      edges       <= '0;
      events      <= '{default: '0};
    end else begin
      pin_q <= pin_d;
      if (pin_d)
        high_cycles <= high_cycles + 64'd1;
      if (pin_d && !pin_q)
        edges <= edges + 32'd1;
      if (pin_d && !chip_in_reset) begin
        for (int g = 0; g < GROUPS; g++)
          if (site_in_group(g, g == G_PIPE ? pipe_target_phase : target_phase))
            events[g] <= events[g] + 32'd1;
      end
    end
  end

endmodule
