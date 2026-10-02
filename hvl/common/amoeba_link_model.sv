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
//   header     req=1 for two cycles: A[31:16] then A[15:0].  wr comes off the
//              pins; burst is always 1 -- the link is INCR8 only, so there is
//              no size and no byte strobes on the wire
//   write      32 words, contiguous, LSW first; beats are queued and written
//              to mem_itf in order with every lane live
//   read       beats are fetched from mem_itf in order into a line buffer
//              and streamed as they arrive, after dir has fallen and TA has
//              elapsed; the bus is released after the last word
//   ready      "may start", asserted only while the queue can take TWO lines.
//              See "the ready guard band" in pkg/amoeba_link_pkg.sv: the ASIC
//              samples ready through two registers and issues req a cycle
//              later, so a req can arrive up to GUARD cycles after ready fell.
//              Keeping a spare line in reserve makes that race a non-event
//              instead of a queue overflow.
//
// +LINK_GAPS=1 (+LINK_SEED=n) withholds ready and rvalid at random so the
// ASIC's handling of both is exercised; the protocol guarantees neither is
// ever required to be immediate.
// +LINK_TRAIN_ERR=n corrupts word n of the FIRST echo so the ASIC's training
// retry is exercised; the second attempt is clean and training then passes.
//
// Checks: req only while dir=1; a header only while idle; the model never
// drives while dir=1; the queue never overflows; TA honoured on both dir
// edges -- including on a retry, which is what +LINK_TRAIN_ERR proves.
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
  bit          train_err = 0;
  logic [15:0] train_err_word = '0;
  logic [31:0] prng = 32'h1234_5678;
  initial begin
    int seed, w;
    if ($test$plusargs("LINK_GAPS")) gaps = 1;
    if ($value$plusargs("LINK_SEED=%d", seed)) prng = 32'(seed) ^ 32'hA5A5_0001;
    if ($value$plusargs("LINK_TRAIN_ERR=%d", w)) begin
      train_err = 1; train_err_word = 16'(w);
    end
  end
  function automatic logic [31:0] prng_next(input logic [31:0] s);
    return {s[30:0], s[31] ^ s[21] ^ s[1] ^ s[0]};
  endfunction

  // ---- in-order memory op queue --------------------------------------------
  // Four lines deep so `ready` can be withdrawn while two lines still fit:
  // one for the transaction already in flight and one for the transaction the
  // guard band allows to arrive after ready fell.
  localparam int QD = 4 * BEATS_PER_LINE;
  typedef struct packed { logic is_wr; logic [63:0] addr; logic [63:0] data; logic [7:0] mask; } op_t;
  op_t        q[QD];
  logic [5:0] q_head, q_tail;             // 6 bits: full/empty via wrap bit
  logic       q_empty, q_full;
  logic [5:0] q_count;
  assign q_count = q_tail - q_head;
  assign q_empty = (q_count == 0);
  assign q_full  = (q_count == 6'(QD));

  // ---- read line buffer (owned by the memory FSM) ---------------------------
  logic [63:0] rbuf[BEATS_PER_LINE];
  logic [7:0]  rbuf_valid;
  logic [2:0]  rd_fill;                   // next beat index to fill from memory
  logic        rd_start;                  // pulse: new read transaction

  // ---- link state ------------------------------------------------------------
  link_slave_st_t lst;                 // states in pkg/amoeba_link_pkg.sv
  logic [15:0] hdr_hi;
  logic [31:0] taddr;
  logic        twr;
  logic [5:0]  wcnt;                      // words in this transaction
  logic [47:0] wacc;
  logic [15:0] lfsr;
  logic [15:0] tcnt;
  logic [3:0]  ta_cnt;
  logic        dir_q;
  logic        read_pending;              // header seen, bus not yet returned
  logic [3:0]  rd_queue_idx;              // beats queued so far (0..8)
  logic        gap_ready, gap_rvalid;
  logic [3:0]  echo_try;                  // which echo attempt this is

  wire [63:0] taddr_al  = 64'({taddr[31:3], 3'b000});
  wire [63:0] beat_addr = taddr_al + 64'(wcnt[5:2]) * 8;
  wire        last_word = (wcnt == 6'd31);   // INCR8 only: 8 beats x 4 words
  wire        rd_more   = (rd_queue_idx <= 4'd7);

  always_ff @(posedge clk) begin
    if (rst) begin
      lst <= LS_TRAIN; io_o <= '0; io_oe <= 1'b0; ready <= 1'b0; rvalid <= 1'b0;
      q_tail <= '0; rd_start <= 1'b0;
      wcnt <= '0; wacc <= '0; lfsr <= TRAIN_SEED; tcnt <= '0; ta_cnt <= '0; dir_q <= 1'b1;
      read_pending <= 1'b0; hdr_hi <= '0; taddr <= '0; twr <= 1'b0;
      rd_queue_idx <= 4'd8; gap_ready <= 1'b0; gap_rvalid <= 1'b0;
      echo_try <= '0;
    end else begin
      dir_q <= dir;
      prng  <= prng_next(prng);
      gap_ready  <= gaps & (prng[3:0] == 4'd0);      // ~6% of cycles
      gap_rvalid <= gaps & (prng[7:5] == 3'd0);      // ~12% of cycles
      rvalid   <= 1'b0;
      rd_start <= 1'b0;

      // ready: may start.  Idle, with room for TWO full lines -- one for the
      // transaction this invites and one for the transaction that may still
      // arrive inside the guard band after ready falls.
      ready <= (lst == LS_IDLE) & (q_count <= 6'(QD - 2*BEATS_PER_LINE)) & ~gap_ready;

      // Read beats are queued one per cycle from the header on, whenever the
      // queue has room; writes and reads never push in the same cycle because
      // the ASIC cannot be sending write words during a read.
      if (rd_more & ~q_full & lst != LS_WDATA & lst != LS_HDR1) begin
        q[q_tail[4:0]] <= '{is_wr: 1'b0, addr: taddr_al + 64'(rd_queue_idx) * 8,
                            data: '0, mask: 8'hFF};
        q_tail <= q_tail + 1'b1;
        rd_queue_idx <= rd_queue_idx + 1'b1;
      end

      case (lst)
        // --- training: wait for the ASIC to release the bus, then echo ------
        LS_TRAIN: begin
          ready <= 1'b0;
          if (dir_q & ~dir) begin
            ta_cnt <= '0; lfsr <= TRAIN_SEED; tcnt <= '0;
            echo_try <= echo_try + 1'b1; lst <= LS_ECHO_TA;
          end
        end
        LS_ECHO_TA: begin
          ta_cnt <= ta_cnt + 1'b1;
          if (ta_cnt == 4'(TA - 1)) lst <= LS_ECHO;
        end
        LS_ECHO: begin
          // A correct ASIC gives TA before taking the bus back (RETRY_TA), so
          // this never fires -- but a slave that kept driving into a reclaimed
          // bus would be shorting the pad ring, so model the safe behaviour.
          if (dir) begin
            io_oe <= 1'b0; rvalid <= 1'b0; lst <= LS_TRAIN;
          end else begin
            io_oe <= 1'b1; rvalid <= 1'b1; lfsr <= lfsr_next(lfsr);
            io_o <= (train_err & echo_try == 4'd1 & tcnt == train_err_word) ? ~lfsr : lfsr;
            tcnt <= tcnt + 1'b1;
            if (tcnt == 16'(TRAIN_LEN - 1)) lst <= LS_IDLE;
          end
        end

        // --- idle: header, or a retrain ------------------------------------
        LS_IDLE: begin
          io_oe <= 1'b0; rvalid <= 1'b0;
          if (req) begin
            hdr_hi <= io_i; lst <= LS_HDR1;
          end else if (dir_q & ~dir & ~read_pending) begin
            // dir fell with nothing outstanding: the ASIC is retraining
            ta_cnt <= '0; lfsr <= TRAIN_SEED; tcnt <= '0;
            echo_try <= echo_try + 1'b1; lst <= LS_ECHO_TA;
          end
        end
        LS_HDR1: begin
          taddr  <= {hdr_hi, io_i};                // the whole address, unpacked
          twr    <= wr; wcnt <= '0; wacc <= '0;
          if (wr) lst <= LS_WDATA;
          else begin
            rd_queue_idx <= '0; rd_start <= 1'b1;
            read_pending <= 1'b1; ta_cnt <= '0; lst <= LS_RD_TA;
          end
        end

        // --- write: words arrive back to back ------------------------------
        LS_WDATA: begin
          case (wcnt[1:0])
            2'd0: wacc[15:0]  <= io_i;
            2'd1: wacc[31:16] <= io_i;
            2'd2: wacc[47:32] <= io_i;
            default: begin
              if (q_full) $fatal(1, "link model: op queue overflow -- the ready guard band was violated");
              q[q_tail[4:0]] <= '{is_wr: 1'b1, addr: beat_addr, data: {io_i, wacc}, mask: 8'hFF};
              q_tail <= q_tail + 1'b1;
            end
          endcase
          wcnt <= wcnt + 1'b1;
          if (last_word) lst <= LS_IDLE;
        end

        // --- read: wait for the bus, TA, then stream as beats arrive --------
        LS_RD_TA: begin
          if (~dir) begin
            ta_cnt <= ta_cnt + 1'b1;
            if (ta_cnt == 4'(TA - 1)) begin ta_cnt <= '0; lst <= LS_RD; end
          end else ta_cnt <= '0;
        end
        LS_RD: begin
          if (rbuf_valid[wcnt[4:2]] & ~gap_rvalid) begin
            io_oe <= 1'b1; io_o <= rbuf[wcnt[4:2]][16 * wcnt[1:0] +: 16]; rvalid <= 1'b1;
            wcnt <= wcnt + 1'b1;
            if (last_word) begin read_pending <= 1'b0; lst <= LS_IDLE; end
          end else begin
            io_oe <= 1'b0; rvalid <= 1'b0;
          end
        end
        default: lst <= LS_IDLE;
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
          if (~q[q_head[4:0]].is_wr) begin
            rbuf[rd_fill] <= mem_rdata; rbuf_valid[rd_fill] <= 1'b1; rd_fill <= rd_fill + 1'b1;
          end
          q_head <= q_head + 1'b1;
        end
      end else if (~q_empty) begin
        mem_addr  <= q[q_head[4:0]].addr;
        mem_wdata <= q[q_head[4:0]].data;
        mem_wmask <= q[q_head[4:0]].is_wr ? q[q_head[4:0]].mask : 8'h00;
        mem_rmask <= q[q_head[4:0]].is_wr ? 8'h00 : q[q_head[4:0]].mask;
        mem_busy  <= 1'b1;
      end
    end
  end

  // ---- protocol checks -------------------------------------------------------
  always_ff @(posedge clk) if (!rst) begin
    if (req & ~dir)                         $error("link model: req while dir=0");
    if (req & lst != LS_IDLE & lst != LS_HDR1) $error("link model: header while busy (state %0d)", lst);
    if (io_oe & dir)                        $error("link model: driving io while dir=1");
    if (mem_wmask != '0 & mem_addr[2:0] != 3'b000) $error("link model: unaligned write to memory: %h", mem_addr);
    // The link is INCR8 only.  A single arriving here means the ASIC issued a
    // transfer the protocol cannot describe -- the mirror of the HBURST
    // assertion in amoeba_link_master.
    if (lst == LS_HDR1 & ~burst) $error("link model: single transfer -- the link is INCR8 only");
  end

endmodule
