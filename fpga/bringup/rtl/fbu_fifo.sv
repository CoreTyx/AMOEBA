///////////////////////////////////////////////////////////////////////////////
// fbu_fifo.sv -- single-clock first-word-fall-through FIFO.  A write to a full
// FIFO is dropped and sets the sticky overflow flag.
///////////////////////////////////////////////////////////////////////////////
module fbu_fifo #(
  parameter int WIDTH      = 8,
  parameter int DEPTH_LOG2 = 4
)(
  input  logic                  clk,
  input  logic                  arst_n,
  input  logic                  clear,

  input  logic                  push,
  input  logic [WIDTH-1:0]      push_data,
  output logic                  full,
  output logic                  overflow,

  input  logic                  pop,
  output logic [WIDTH-1:0]      head,
  output logic                  empty,

  output logic [DEPTH_LOG2:0]   level
);

  localparam int DEPTH = 1 << DEPTH_LOG2;

  logic [WIDTH-1:0]    storage [DEPTH];
  logic [DEPTH_LOG2:0] write_ptr;
  logic [DEPTH_LOG2:0] read_ptr;
  logic [DEPTH_LOG2:0] stored;
  logic                head_valid;
  logic                storage_empty;
  logic                storage_full;
  logic                write;
  logic                refill_head;

  assign stored        = write_ptr - read_ptr;
  assign storage_empty = stored == '0;
  assign storage_full  = stored == (DEPTH_LOG2 + 1)'(DEPTH);
  assign full          = storage_full;
  assign empty         = !head_valid;
  assign level         = stored + (DEPTH_LOG2 + 1)'(head_valid);
  assign write         = push && !storage_full;
  assign refill_head   = !storage_empty && (!head_valid || pop);

  always_ff @(posedge clk) begin
    if (write)
      storage[write_ptr[DEPTH_LOG2-1:0]] <= push_data;
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      write_ptr  <= '0;
      read_ptr   <= '0;
      head_valid <= 1'b0;
      head       <= '0;
      overflow   <= 1'b0;
    end else if (clear) begin
      write_ptr  <= '0;
      read_ptr   <= '0;
      head_valid <= 1'b0;
      overflow   <= 1'b0;
    end else begin
      if (write)
        write_ptr <= write_ptr + 1'b1;
      if (push && storage_full)
        overflow <= 1'b1;
      if (refill_head) begin
        head       <= storage[read_ptr[DEPTH_LOG2-1:0]];
        read_ptr   <= read_ptr + 1'b1;
        head_valid <= 1'b1;
      end else if (pop) begin
        head_valid <= 1'b0;
      end
    end
  end

endmodule
