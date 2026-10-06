///////////////////////////////////////////////////////////////////////////////
// forte_link_model.sv
//
// Testbench slave for the off-chip link: the FPGA, as far as the ASIC can
// tell.  Speaks pkg/forte_link_pkg.sv on one side and the testbench's
// mem_itf_w_mask on the other, so the whole existing regression runs through
// the real protocol with the memory model, tohost snoop and RVFI unchanged.
//
//   header     req=1 for two cycles: A[31:16] then A[15:0].  wr comes off the
//              pins.  Every transfer is a full BEATS-beat burst, so there is
//              no size and no byte strobes on the wire, and no `burst` pin
//   write      4*BEATS words, contiguous, LSW first; beats are queued and
//              written to mem_itf in order with every lane live
//   read       beats are fetched from mem_itf in order into a line buffer
//              and streamed as they arrive, after dir has fallen and TA has
//              elapsed; the bus is released after the last word
//   ready      "may start", asserted only while the queue can take TWO lines.
//              See "the ready guard band" in pkg/forte_link_pkg.sv: the ASIC
//              samples ready through two registers and issues req a cycle
//              later, so a req can arrive up to GUARD cycles after ready fell.
//              Keeping a spare line in reserve makes that race a non-event
//              instead of a queue overflow.
//
// +LINK_GAPS=1 (+LINK_SEED=n) withholds ready and rvalid at random so the
// ASIC's handling of both is exercised; the protocol guarantees neither is
// ever required to be immediate.
// Checks: req only while dir=1; a header only while idle; the model never
// drives while dir=1; the queue never overflows; TA honoured on both dir edges.
//
// BEATS must be the SAME expression forte_chip uses -- DCACHE_LINELENINBITS /
// AHBW -- or the model and the DUT disagree about where a transaction ends and
// the regression hangs rather than failing.  hvl/common/forte_dut_wrap.sv passes
// it from config.vh for exactly that reason.  This module was written when the
// count was hardcoded to 8 in three places at once; see "ONE BURST LENGTH PER
// BUILD" in pkg/forte_link_pkg.sv for what that cost.
///////////////////////////////////////////////////////////////////////////////

module forte_link_model import forte_link_pkg::*; #(
  parameter int BEATS = 8        // see the header: must match the DUT's
)(
  input  logic              clk,
  input  logic              rst,
  inout  wire  [LINK_W-1:0] io,
  input  logic              dir,
  input  logic              req,
  input  logic              wr,
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
  // Four lines deep so `ready` can be withdrawn while two lines still fit:
  // one for the transaction already in flight and one for the transaction the
  // guard band allows to arrive after ready fell.
  localparam int QD  = 4 * BEATS;
  localparam int QIW = $clog2(QD);        // index into q
  localparam int QCW = QIW + 1;           // one more bit: full/empty via wrap
  typedef struct packed { logic is_wr; logic [63:0] addr; logic [63:0] data; logic [7:0] mask; } op_t;
  op_t            q[QD];
  logic [QCW-1:0] q_head, q_tail;
  logic           q_empty, q_full;
  logic [QCW-1:0] q_count;
  assign q_count = q_tail - q_head;
  assign q_empty = (q_count == 0);
  assign q_full  = (q_count == QCW'(QD));

  // ---- read line buffer (owned by the memory FSM) ---------------------------
  // BEATS >= 2 is enforced by forte_link_core, so $clog2 is never asked for the
  // width of a one-element range.
  localparam int BCW = $clog2(BEATS);     // beat index, 0..BEATS-1
  logic [63:0]      rbuf[BEATS];
  logic [BEATS-1:0] rbuf_valid;
  logic [BCW-1:0]   rd_fill;              // next beat index to fill from memory
  logic             rd_start;             // pulse: new read transaction

  // ---- link state ------------------------------------------------------------
  link_slave_st_t lst;                 // states in pkg/forte_link_pkg.sv
  logic [15:0] hdr_hi;
  logic [31:0] taddr;
  logic        twr;
  localparam int WORDS  = 4 * BEATS;
  localparam int WCNT_W = $clog2(WORDS);  // >= 3, since BEATS >= 2
  localparam int RQW    = $clog2(BEATS + 1);
  logic [WCNT_W-1:0] wcnt;                // words in this transaction
  logic [47:0] wacc;
  logic [3:0]  ta_cnt;
  logic [RQW-1:0] rd_queue_idx;           // beats queued so far (0..BEATS)
  logic        gap_ready, gap_rvalid;

  // The beat index inside the transaction: wcnt divided by WORDS_PER_BEAT.
  wire [BCW-1:0] beat_idx = wcnt[WCNT_W-1:2];

  wire [63:0] taddr_al  = 64'({taddr[31:3], 3'b000});
  wire [63:0] beat_addr = taddr_al + 64'(beat_idx) * 8;
  wire        last_word = (wcnt == WCNT_W'(WORDS - 1));
  wire        rd_more   = (rd_queue_idx <= RQW'(BEATS - 1));

  always_ff @(posedge clk) begin
    if (rst) begin
      lst <= LS_IDLE; io_o <= '0; io_oe <= 1'b0; ready <= 1'b0; rvalid <= 1'b0;
      q_tail <= '0; rd_start <= 1'b0;
      wcnt <= '0; wacc <= '0; ta_cnt <= '0;
      hdr_hi <= '0; taddr <= '0; twr <= 1'b0;
      rd_queue_idx <= RQW'(BEATS); gap_ready <= 1'b0; gap_rvalid <= 1'b0;
    end else begin
      prng  <= prng_next(prng);
      gap_ready  <= gaps & (prng[3:0] == 4'd0);      // ~6% of cycles
      gap_rvalid <= gaps & (prng[7:5] == 3'd0);      // ~12% of cycles
      rvalid   <= 1'b0;
      rd_start <= 1'b0;

      // ready: may start.  Idle, with room for TWO full lines -- one for the
      // transaction this invites and one for the transaction that may still
      // arrive inside the guard band after ready falls.
      ready <= (lst == LS_IDLE) & (q_count <= QCW'(QD - 2*BEATS)) & ~gap_ready;

      // Read beats are queued one per cycle from the header on, whenever the
      // queue has room; writes and reads never push in the same cycle because
      // the ASIC cannot be sending write words during a read.
      if (rd_more & ~q_full & lst != LS_WDATA & lst != LS_HDR1) begin
        q[q_tail[QIW-1:0]] <= '{is_wr: 1'b0, addr: taddr_al + 64'(rd_queue_idx) * 8,
                                data: '0, mask: 8'hFF};
        q_tail <= q_tail + 1'b1;
        rd_queue_idx <= rd_queue_idx + 1'b1;
      end

      case (lst)
        // --- idle: wait for a header ---------------------------------------
        LS_IDLE: begin
          io_oe <= 1'b0; rvalid <= 1'b0;
          if (req) begin
            hdr_hi <= io_i; lst <= LS_HDR1;
          end
        end
        LS_HDR1: begin
          taddr  <= {hdr_hi, io_i};                // the whole address, unpacked
          twr    <= wr; wcnt <= '0; wacc <= '0;
          if (wr) lst <= LS_WDATA;
          else begin
            rd_queue_idx <= '0; rd_start <= 1'b1;
            ta_cnt <= '0; lst <= LS_RD_TA;
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
              q[q_tail[QIW-1:0]] <= '{is_wr: 1'b1, addr: beat_addr, data: {io_i, wacc}, mask: 8'hFF};
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
          if (rbuf_valid[beat_idx] & ~gap_rvalid) begin
            io_oe <= 1'b1; io_o <= rbuf[beat_idx][16 * wcnt[1:0] +: 16]; rvalid <= 1'b1;
            wcnt <= wcnt + 1'b1;
            if (last_word) lst <= LS_IDLE;
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
          if (~q[q_head[QIW-1:0]].is_wr) begin
            rbuf[rd_fill] <= mem_rdata; rbuf_valid[rd_fill] <= 1'b1; rd_fill <= rd_fill + 1'b1;
          end
          q_head <= q_head + 1'b1;
        end
      end else if (~q_empty) begin
        mem_addr  <= q[q_head[QIW-1:0]].addr;
        mem_wdata <= q[q_head[QIW-1:0]].data;
        mem_wmask <= q[q_head[QIW-1:0]].is_wr ? q[q_head[QIW-1:0]].mask : 8'h00;
        mem_rmask <= q[q_head[QIW-1:0]].is_wr ? 8'h00 : q[q_head[QIW-1:0]].mask;
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
    // There is no longer a single-transfer check here, because there is no
    // longer any way for the ASIC to ASK for one: with the burst pin gone every
    // transaction on the wire is BEATS beats by construction.  The check that
    // the core never requests something else is the HBURST assertion in
    // forte_link_core, against forte_link_pkg::hburst_for(BEATS).
  end

endmodule
