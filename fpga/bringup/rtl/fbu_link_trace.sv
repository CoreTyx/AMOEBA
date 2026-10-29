///////////////////////////////////////////////////////////////////////////////
// fbu_link_trace.sv -- the link trace, as records the PS drains.
//
// One record per pin_trace.log line (hvl/pin/pin_link_agent.sv format), ten
// 32-bit words:
//   word 0     [31:28] kind (L, T, E, I), [27] write, [25:24] irq line, [23] irq level
//   words 1-2  cycle (L: the cycle the header started)
//   word 3     L: address; E: error bits (fbu_pkg::link_err_t)
//   words 4-7  L: the line; T: words 4-5 the tohost value
//   words 8-9  L: the cycle the transaction finished
//
// Records of one cycle are kept in the bench's order: T, L, E, I.  With
// cfg_stop_on_error, nothing that happened after the cycle of the first error
// is kept, as the bench stops at its first error.
///////////////////////////////////////////////////////////////////////////////
module fbu_link_trace #(
  parameter int BEATS      = 2,
  parameter int DEPTH_LOG2 = 11,
  localparam int LINE_W    = 64 * BEATS,
  localparam int RECORD_W  = 320
)(
  input  logic                clk,
  input  logic                arst_n,
  input  logic                clear,

  input  logic                cfg_enable,
  input  logic                cfg_stop_on_error,

  input  logic [63:0]         link_cyc,
  input  logic                chip_in_reset,
  input  logic                rec_valid,
  input  logic [63:0]         rec_cyc,
  input  logic                rec_wr,
  input  logic [31:0]         rec_addr,
  input  logic [LINE_W-1:0]   rec_line,
  input  logic                rec_tohost,
  input  logic [63:0]         rec_end_cyc,
  input  logic [63:0]         rec_tohost_val,
  input  logic [31:0]         err_now,
  input  logic [1:0]          irq,

  output logic [RECORD_W-1:0] head,
  output logic                head_valid,
  input  logic                pop,
  output logic [DEPTH_LOG2:0] level,
  output logic [31:0]         records_written,
  output logic [31:0]         records_dropped,
  output logic                overflow
);

  localparam logic [3:0] KIND_L = 4'd1;
  localparam logic [3:0] KIND_T = 4'd2;
  localparam logic [3:0] KIND_E = 4'd3;
  localparam logic [3:0] KIND_I = 4'd4;

  localparam int CANDIDATES = 5;
  localparam int STAGE_LOG2 = 3;
  localparam int STAGE      = 1 << STAGE_LOG2;

  // ---- this cycle's records, in order ----
  logic [RECORD_W-1:0] candidate       [CANDIDATES];
  logic                candidate_valid [CANDIDATES];
  logic [63:0]         candidate_cyc   [CANDIDATES];
  logic [1:0]          irq_prev;
  logic [63:0]         err_cyc;

  assign err_cyc = link_cyc + 64'd1;

  always_comb begin
    for (int c = 0; c < CANDIDATES; c++) begin
      candidate[c]       = '0;
      candidate_valid[c] = 1'b0;
      candidate_cyc[c]   = '0;
    end

    candidate[0][31:28]   = KIND_T;
    candidate[0][95:32]   = rec_end_cyc;
    candidate[0][191:128] = rec_tohost_val;
    candidate_valid[0]    = rec_valid && rec_tohost;
    candidate_cyc[0]      = rec_end_cyc;

    candidate[1][31:28]   = KIND_L;
    candidate[1][27]      = rec_wr;
    candidate[1][95:32]   = rec_cyc;
    candidate[1][127:96]  = rec_addr;
    candidate[1][128 +: LINE_W] = rec_line;
    candidate[1][319:256] = rec_end_cyc;
    candidate_valid[1]    = rec_valid;
    candidate_cyc[1]      = rec_end_cyc;

    candidate[2][31:28]   = KIND_E;
    candidate[2][95:32]   = err_cyc;
    candidate[2][127:96]  = err_now;
    candidate_valid[2]    = err_now != '0;
    candidate_cyc[2]      = err_cyc;

    for (int line = 0; line < 2; line++) begin
      candidate[3 + line][31:28] = KIND_I;
      candidate[3 + line][25:24] = 2'(line);
      candidate[3 + line][23]    = irq[line];
      candidate[3 + line][95:32] = link_cyc;
      candidate_valid[3 + line]  = irq[line] != irq_prev[line] && !chip_in_reset;
      candidate_cyc[3 + line]    = link_cyc;
    end
  end

  // ---- stop at the first error ----
  logic        stopped;
  logic [63:0] stop_cyc;
  logic        keep [CANDIDATES];

  always_comb begin
    for (int c = 0; c < CANDIDATES; c++)
      keep[c] = cfg_enable && candidate_valid[c] && !(stopped && candidate_cyc[c] > stop_cyc);
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      stopped  <= 1'b0;
      stop_cyc <= '0;
      irq_prev <= '0;
    end else if (clear) begin
      stopped  <= 1'b0;
      irq_prev <= irq;
    end else begin
      irq_prev <= irq;
      if (cfg_stop_on_error && !stopped && keep[2]) begin
        stopped  <= 1'b1;
        stop_cyc <= err_cyc;
      end
    end
  end

  // ---- staging: up to CANDIDATES in per cycle, one out to the FIFO ----
  logic [RECORD_W-1:0] stage [STAGE];
  logic [STAGE_LOG2:0] stage_count;
  logic [STAGE_LOG2-1:0] stage_head;
  logic [STAGE_LOG2:0] kept_count;
  logic [STAGE_LOG2:0] slot_offset [CANDIDATES];
  logic                stage_fits;
  logic                stage_pop;
  logic                fifo_full;
  logic                fifo_empty;

  always_comb begin
    kept_count = '0;
    for (int c = 0; c < CANDIDATES; c++) begin
      slot_offset[c] = kept_count;
      if (keep[c])
        kept_count = kept_count + 1'b1;
    end
  end

  assign stage_pop  = stage_count != '0 && !fifo_full;
  assign stage_fits = stage_count - (STAGE_LOG2 + 1)'(stage_pop) + kept_count <= (STAGE_LOG2 + 1)'(STAGE);

  always_ff @(posedge clk) begin
    if (stage_fits) begin
      for (int c = 0; c < CANDIDATES; c++) begin
        if (keep[c])
          stage[STAGE_LOG2'(stage_head + stage_count[STAGE_LOG2-1:0] + slot_offset[c][STAGE_LOG2-1:0])] <= candidate[c];
      end
    end
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      stage_count     <= '0;
      stage_head      <= '0;
      records_written <= '0;
      records_dropped <= '0;
    end else if (clear) begin
      stage_count     <= '0;
      stage_head      <= '0;
      records_written <= '0;
      records_dropped <= '0;
    end else begin
      stage_count <= stage_count - (STAGE_LOG2 + 1)'(stage_pop) + (stage_fits ? kept_count : '0);
      if (stage_pop)
        stage_head <= stage_head + 1'b1;
      if (stage_pop)
        records_written <= records_written + 32'd1;
      if (!stage_fits)
        records_dropped <= records_dropped + 32'(kept_count);
    end
  end

  fbu_fifo #(.WIDTH(RECORD_W), .DEPTH_LOG2(DEPTH_LOG2)) records (
    .clk, .arst_n, .clear,
    .push(stage_pop), .push_data(stage[stage_head]), .full(fifo_full), .overflow(overflow),
    .pop, .head, .empty(fifo_empty), .level);

  assign head_valid = !fifo_empty;

endmodule
