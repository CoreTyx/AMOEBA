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
// Records leave in the order they arrived, those of one cycle as T, L, E, I.
// Each kind waits in its own short queue at its own width; a queue of kind
// tags keeps the order, and the full record is assembled only as it enters
// the FIFO.  With cfg_stop_on_error nothing after the cycle of the first
// error is kept, as the bench stops at its first.
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

  typedef enum logic [2:0] {SRC_T, SRC_L, SRC_E, SRC_I0, SRC_I1} source_t;
  localparam int SOURCES = 5;

  localparam int T_W = 64 + 64;
  localparam int L_W = 64 + 1 + 32 + LINE_W + 64;
  localparam int E_W = 64 + 32;
  localparam int I_W = 64 + 1;

  // ---- this cycle's arrivals ----
  logic [1:0]  irq_prev;
  logic [63:0] err_cyc;
  logic        arriving      [SOURCES];
  logic [63:0] arrival_cyc   [SOURCES];
  logic        kept          [SOURCES];
  logic        stopped;
  logic [63:0] stop_cyc;

  assign err_cyc = link_cyc + 64'd1;

  always_comb begin
    arriving[SRC_T]     = rec_valid && rec_tohost;
    arrival_cyc[SRC_T]  = rec_end_cyc;
    arriving[SRC_L]     = rec_valid;
    arrival_cyc[SRC_L]  = rec_end_cyc;
    arriving[SRC_E]     = err_now != '0;
    arrival_cyc[SRC_E]  = err_cyc;
    arriving[SRC_I0]    = irq[0] != irq_prev[0] && !chip_in_reset;
    arrival_cyc[SRC_I0] = link_cyc;
    arriving[SRC_I1]    = irq[1] != irq_prev[1] && !chip_in_reset;
    arrival_cyc[SRC_I1] = link_cyc;
    for (int s = 0; s < SOURCES; s++)
      kept[s] = cfg_enable && arriving[s] && !(stopped && arrival_cyc[s] > stop_cyc);
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
      if (cfg_stop_on_error && !stopped && kept[SRC_E]) begin
        stopped  <= 1'b1;
        stop_cyc <= err_cyc;
      end
    end
  end

  // ---- per-kind queues and the tag queue that orders them ----
  logic           queue_full  [SOURCES];
  logic           queue_empty [SOURCES];
  logic           queue_push  [SOURCES];
  logic           queue_pop   [SOURCES];
  logic [T_W-1:0] t_head;
  logic [L_W-1:0] l_head;
  logic [E_W-1:0] e_head;
  logic [I_W-1:0] i_head      [2];

  localparam int TAG_LOG2 = 3;
  localparam int TAGS     = 1 << TAG_LOG2;

  source_t           tags [TAGS];
  logic [TAG_LOG2:0] tag_count;
  logic [TAG_LOG2-1:0] tag_head;
  logic [TAG_LOG2:0] tag_offset [SOURCES];
  logic [TAG_LOG2:0] arrivals;
  logic [TAG_LOG2:0] kept_count;
  logic              accepted [SOURCES];
  logic              arrivals_fit;
  logic              tag_pop;
  source_t           next_source;
  logic              fifo_full;
  logic              fifo_empty;
  logic [RECORD_W-1:0] record;

  always_comb begin
    arrivals   = '0;
    kept_count = '0;
    for (int s = 0; s < SOURCES; s++) begin
      accepted[s]   = kept[s] && !queue_full[s];
      tag_offset[s] = arrivals;
      if (accepted[s])
        arrivals = arrivals + 1'b1;
      if (kept[s])
        kept_count = kept_count + 1'b1;
    end
  end

  assign tag_pop      = tag_count != '0 && !fifo_full && !queue_empty[next_source];
  assign next_source  = tags[tag_head];
  assign arrivals_fit = tag_count - (TAG_LOG2 + 1)'(tag_pop) + arrivals <= (TAG_LOG2 + 1)'(TAGS);

  always_comb begin
    for (int s = 0; s < SOURCES; s++) begin
      queue_push[s] = accepted[s] && arrivals_fit;
      queue_pop[s]  = tag_pop && next_source == source_t'(s);
    end
  end

  fbu_fifo #(.WIDTH(T_W), .DEPTH_LOG2(1)) t_queue (
    .clk, .arst_n, .clear,
    .push(queue_push[SRC_T]), .push_data({rec_tohost_val, rec_end_cyc}),
    .full(queue_full[SRC_T]), .overflow(),
    .pop(queue_pop[SRC_T]), .empty(queue_empty[SRC_T]), .head(t_head), .level());

  fbu_fifo #(.WIDTH(L_W), .DEPTH_LOG2(1)) l_queue (
    .clk, .arst_n, .clear,
    .push(queue_push[SRC_L]), .push_data({rec_end_cyc, rec_line, rec_addr, rec_wr, rec_cyc}),
    .full(queue_full[SRC_L]), .overflow(),
    .pop(queue_pop[SRC_L]), .empty(queue_empty[SRC_L]), .head(l_head), .level());

  fbu_fifo #(.WIDTH(E_W), .DEPTH_LOG2(1)) e_queue (
    .clk, .arst_n, .clear,
    .push(queue_push[SRC_E]), .push_data({err_now, err_cyc}),
    .full(queue_full[SRC_E]), .overflow(),
    .pop(queue_pop[SRC_E]), .empty(queue_empty[SRC_E]), .head(e_head), .level());

  for (genvar line = 0; line < 2; line++) begin : g_irq_queue
    fbu_fifo #(.WIDTH(I_W), .DEPTH_LOG2(1)) i_queue (
      .clk, .arst_n, .clear,
      .push(queue_push[SRC_I0 + line]), .push_data({irq[line], link_cyc}),
      .full(queue_full[SRC_I0 + line]), .overflow(),
      .pop(queue_pop[SRC_I0 + line]), .head(i_head[line]), .empty(queue_empty[SRC_I0 + line]), .level());
  end

  always_ff @(posedge clk) begin
    for (int s = 0; s < SOURCES; s++)
      if (queue_push[s])
        tags[TAG_LOG2'(tag_head + tag_count[TAG_LOG2-1:0] + tag_offset[s][TAG_LOG2-1:0])] <= source_t'(s);
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      tag_count       <= '0;
      tag_head        <= '0;
      records_written <= '0;
      records_dropped <= '0;
    end else if (clear) begin
      tag_count       <= '0;
      tag_head        <= '0;
      records_written <= '0;
      records_dropped <= '0;
    end else begin
      tag_count <= tag_count - (TAG_LOG2 + 1)'(tag_pop) + (arrivals_fit ? arrivals : '0);
      if (tag_pop)
        tag_head <= tag_head + 1'b1;
      if (tag_pop)
        records_written <= records_written + 32'd1;
      records_dropped <= records_dropped + 32'(kept_count) - (arrivals_fit ? 32'(arrivals) : 32'd0);
    end
  end

  // ---- the record entering the FIFO ----
  always_comb begin
    record = '0;
    case (next_source)
      SRC_T: begin
        record[31:28]   = KIND_T;
        record[95:32]   = t_head[63:0];
        record[191:128] = t_head[127:64];
      end
      SRC_L: begin
        record[31:28]              = KIND_L;
        record[95:32]              = l_head[63:0];
        record[27]                 = l_head[64];
        record[127:96]             = l_head[96:65];
        record[128 +: LINE_W]      = l_head[97 +: LINE_W];
        record[319:256]            = l_head[97 + LINE_W +: 64];
      end
      SRC_E: begin
        record[31:28]  = KIND_E;
        record[95:32]  = e_head[63:0];
        record[127:96] = e_head[95:64];
      end
      default: begin
        record[31:28] = KIND_I;
        record[25:24] = next_source == SRC_I1 ? 2'd1 : 2'd0;
        record[23]    = next_source == SRC_I1 ? i_head[1][64] : i_head[0][64];
        record[95:32] = next_source == SRC_I1 ? i_head[1][63:0] : i_head[0][63:0];
      end
    endcase
  end

  fbu_fifo #(.WIDTH(RECORD_W), .DEPTH_LOG2(DEPTH_LOG2)) records (
    .clk, .arst_n, .clear,
    .push(tag_pop), .push_data(record), .full(fifo_full), .overflow(overflow),
    .pop, .head, .empty(fifo_empty), .level);

  assign head_valid = !fifo_empty;

endmodule
