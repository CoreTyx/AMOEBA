///////////////////////////////////////////////////////////////////////////////
// amoeba_link_model.sv
//
// Testbench slave for the off-chip link: the FPGA, as far as the ASIC can
// tell.  Speaks pkg/amoeba_link_pkg.sv on one side and the testbench's
// mem_itf_w_mask on the other, so the whole existing regression runs through
// the real protocol with the memory model, tohost snoop and RVFI unchanged.
//
//   training   after reset, a falling dir with no req pending means "echo":
//              wait TA, drive TRAIN_LEN LFSR words with rvalid=1, release
//   header     req=1 for two cycles: A[31:16] then A[15:0]; wr/burst sampled
//   write      4 (single) or 32 (burst) words, contiguous, LSW first; beats
//              are queued and written to mem_itf in order
//   read       beats are fetched from mem_itf in order into a line buffer
//              and streamed as they arrive, after dir has fallen and TA has
//              elapsed; the bus is released after the last word
//   ready      "may start"; low while the write queue could not take a line
//
// +LINK_GAPS=1 (+LINK_SEED=n) withholds ready and rvalid at random so the
// ASIC's handling of both is exercised; the protocol guarantees neither is
// ever required to be immediate.
//
// Checks: req only while dir=1; a header only while idle; the model never
// drives while dir=1; TA honoured on both dir edges.
///////////////////////////////////////////////////////////////////////////////

module amoeba_link_model import amoeba_link_pkg::*; #(
  parameter int TRAIN_LEN = 64
)(
  input  logic              clk,
  input  logic              rst,
  inout  wire  [LINK_W-1:0] io,
  input  logic              dir,
  input  logic              req,
  input  logic              wr,
  input  logic              burst,
  output logic              ready,
  output logic              rvalid,
  // mem_itf_w_mask, one channel
  output logic [63:0]       mem_addr,
  output logic [7:0]        mem_rmask,
  output logic [7:0]        mem_wmask,
  output logic [63:0]       mem_wdata,
  input  logic [63:0]       mem_rdata,
  input  logic              mem_resp
);

  logic [LINK_W-1:0] io_o;
  logic              io_oe;
  assign io = io_oe ? io_o : {LINK_W{1'bz}};
  wire [LINK_W-1:0] io_i = io;

  // ---- plusargs --------------------------------------------------------------
  bit          gaps = 0;
  logic [31:0] prng = 32'h1234_5678;
  initial begin
    int seed;
    if ($test$plusargs("LINK_GAPS")) gaps = 1;
    if ($value$plusargs("LINK_SEED=%d", seed)) prng = 32'(seed) ^ 32'hA5A5_0001;
  end
  function automatic logic [31:0] prng_next(input logic [31:0] s);
    return {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
  endfunction

  // ---- in-order memory op queue --------------------------------------------
  localparam int QD = 16;
  typedef struct packed { logic is_wr; logic [63:0] addr; logic [63:0] data; logic [7:0] mask; } op_t;
  op_t        q[QD];
  logic [4:0] q_head, q_tail;             // 5 bits: full/empty via wrap bit
  logic       q_empty, q_full;
  logic [4:0] q_count;
  assign q_count = q_tail - q_head;
  assign q_empty = (q_count == 0);
  assign q_full  = (q_count == 5'(QD));

  // ---- read line buffer (owned by the memory FSM) ---------------------------
  logic [63:0] rbuf[BEATS_PER_LINE];
  logic [7:0]  rbuf_valid;
  logic [2:0]  rd_fill;                   // next beat index to fill from memory
  logic        rd_start;                  // pulse: new read transaction

  // ---- link state ------------------------------------------------------------
  typedef enum logic [3:0] {L_TRAIN, L_ECHO_TA, L_ECHO, L_IDLE, L_HDR1, L_WDATA, L_RD_TA, L_RD} l_t;
  l_t          lst;
  logic [15:0] hdr_hi;
  logic [31:0] taddr;
  logic [1:0]  tsize;
  logic        tburst, twr;
  logic [5:0]  wcnt;                      // words in this transaction
  logic [47:0] wacc;
  logic [15:0] lfsr;
  logic [15:0] tcnt;
  logic [3:0]  ta_cnt;
  logic        dir_q;
  logic        read_pending;              // header seen, bus not yet returned
  logic [3:0]  rd_queue_idx;              // beats queued so far (0..8)
  logic [2:0]  rd_beats;                  // beats in this read - 1
  logic        gap_ready, gap_rvalid;

  wire [63:0] beat_addr = 64'(taddr) + 64'(wcnt[5:2]) * 8;
  wire [7:0]  beat_mask = tburst ? 8'hFF : size_to_mask(tsize, taddr[2:0]);
  wire        last_word = tburst ? (wcnt == 6'd31) : (wcnt == 6'd3);
  wire        rd_more   = (rd_queue_idx <= 4'(rd_beats));

  always_ff @(posedge clk) begin
    if (rst) begin
      lst <= L_TRAIN; io_o <= '0; io_oe <= 1'b0; ready <= 1'b0; rvalid <= 1'b0;
      q_tail <= '0; rd_start <= 1'b0;
      wcnt <= '0; wacc <= '0; lfsr <= TRAIN_SEED; tcnt <= '0; ta_cnt <= '0; dir_q <= 1'b1;
      read_pending <= 1'b0; hdr_hi <= '0; taddr <= '0; tsize <= '0; tburst <= 1'b0; twr <= 1'b0;
      rd_queue_idx <= 4'd8; rd_beats <= '0; gap_ready <= 1'b0; gap_rvalid <= 1'b0;
    end else begin
      dir_q <= dir;
      prng  <= prng_next(prng);
      gap_ready  <= gaps & (prng[3:0] == 4'd0);      // ~6% of cycles
      gap_rvalid <= gaps & (prng[7:5] == 3'd0);      // ~12% of cycles
      rvalid   <= 1'b0;
      rd_start <= 1'b0;

      // ready: may start.  Idle, with room for a full line in the queue.
      ready <= (lst == L_IDLE) & (q_count <= 5'(QD - BEATS_PER_LINE)) & ~gap_ready;

      // Read beats are queued one per cycle from the header on, whenever the
      // queue has room; writes and reads never push in the same cycle because
      // the ASIC cannot be sending write words during a read.
      if (rd_more & ~q_full & lst != L_WDATA & lst != L_HDR1) begin
        q[q_tail[3:0]] <= '{is_wr: 1'b0, addr: 64'(taddr) + 64'(rd_queue_idx) * 8, data: '0, mask: 8'hFF};
        q_tail <= q_tail + 1'b1;
        rd_queue_idx <= rd_queue_idx + 1'b1;
      end

      case (lst)
        // --- training: wait for the ASIC to release the bus, then echo ------
        L_TRAIN: begin
          ready <= 1'b0;
          if (dir_q & ~dir) begin ta_cnt <= '0; lfsr <= TRAIN_SEED; tcnt <= '0; lst <= L_ECHO_TA; end
        end
        L_ECHO_TA: begin
          ta_cnt <= ta_cnt + 1'b1;
          if (ta_cnt == 4'(TA - 1)) lst <= L_ECHO;
        end
        L_ECHO: begin
          io_oe <= 1'b1; io_o <= lfsr; rvalid <= 1'b1; lfsr <= lfsr_next(lfsr);
          tcnt <= tcnt + 1'b1;
          if (tcnt == 16'(TRAIN_LEN - 1)) lst <= L_IDLE;
        end

        // --- idle: header, or a retrain ------------------------------------
        L_IDLE: begin
          io_oe <= 1'b0; rvalid <= 1'b0;
          if (req) begin
            hdr_hi <= io_i; lst <= L_HDR1;
          end else if (dir_q & ~dir & ~read_pending) begin
            // dir fell with nothing outstanding: the ASIC is retraining
            ta_cnt <= '0; lfsr <= TRAIN_SEED; tcnt <= '0; lst <= L_ECHO_TA;
          end
        end
        L_HDR1: begin
          taddr  <= addr_unpack({hdr_hi, io_i});
          tsize  <= size_unpack({hdr_hi, io_i});
          twr    <= wr; tburst <= burst; wcnt <= '0; wacc <= '0;
          if (wr) lst <= L_WDATA;
          else begin
            rd_queue_idx <= '0; rd_beats <= burst ? 3'd7 : 3'd0; rd_start <= 1'b1;
            read_pending <= 1'b1; ta_cnt <= '0; lst <= L_RD_TA;
          end
        end

        // --- write: words arrive back to back ------------------------------
        L_WDATA: begin
          case (wcnt[1:0])
            2'd0: wacc[15:0]  <= io_i;
            2'd1: wacc[31:16] <= io_i;
            2'd2: wacc[47:32] <= io_i;
            default: begin
              q[q_tail[3:0]] <= '{is_wr: 1'b1, addr: beat_addr, data: {io_i, wacc}, mask: beat_mask};
              q_tail <= q_tail + 1'b1;
            end
          endcase
          wcnt <= wcnt + 1'b1;
          if (last_word) lst <= L_IDLE;
        end

        // --- read: wait for the bus, TA, then stream as beats arrive --------
        L_RD_TA: begin
          if (~dir) begin
            ta_cnt <= ta_cnt + 1'b1;
            if (ta_cnt == 4'(TA - 1)) begin ta_cnt <= '0; lst <= L_RD; end
          end else ta_cnt <= '0;
        end
        L_RD: begin
          if (rbuf_valid[wcnt[4:2]] & ~gap_rvalid) begin
            io_oe <= 1'b1; io_o <= rbuf[wcnt[4:2]][16 * wcnt[1:0] +: 16]; rvalid <= 1'b1;
            wcnt <= wcnt + 1'b1;
            if (last_word) begin read_pending <= 1'b0; lst <= L_IDLE; end
          end else begin
            io_oe <= 1'b0; rvalid <= 1'b0;
          end
        end
        default: lst <= L_IDLE;
      endcase
    end
  end

  // ---- memory FSM: pop in order ---------------------------------------------
  logic mem_busy;
  always_ff @(posedge clk) begin
    if (rst) begin
      mem_busy <= 1'b0; mem_addr <= '0; mem_rmask <= '0; mem_wmask <= '0; mem_wdata <= '0;
      q_head <= '0; rbuf_valid <= '0; rd_fill <= '0;
    end else begin
      if (rd_start) begin rbuf_valid <= '0; rd_fill <= '0; end
      if (mem_busy) begin
        if (mem_resp) begin
          mem_rmask <= '0; mem_wmask <= '0; mem_busy <= 1'b0;
          if (~q[q_head[3:0]].is_wr) begin
            rbuf[rd_fill] <= mem_rdata; rbuf_valid[rd_fill] <= 1'b1; rd_fill <= rd_fill + 1'b1;
          end
          q_head <= q_head + 1'b1;
        end
      end else if (~q_empty) begin
        mem_addr  <= q[q_head[3:0]].addr;
        mem_wdata <= q[q_head[3:0]].data;
        mem_wmask <= q[q_head[3:0]].is_wr ? q[q_head[3:0]].mask : 8'h00;
        mem_rmask <= q[q_head[3:0]].is_wr ? 8'h00 : 8'hFF;
        mem_busy  <= 1'b1;
      end
    end
  end

  // ---- protocol checks -------------------------------------------------------
  always_ff @(posedge clk) if (!rst) begin
    if (req & ~dir)                         $error("link model: req while dir=0");
    if (req & lst != L_IDLE & lst != L_HDR1) $error("link model: header while busy (state %0d)", lst);
    if (io_oe & dir)                        $error("link model: driving io while dir=1");
  end

endmodule
