///////////////////////////////////////////////////////////////////////////////
// amoeba_link_slave.sv
//
// The FPGA end of the off-chip link (pkg/amoeba_link_pkg.sv): the 16-bit bus
// on one side, an AHB-Lite MASTER on the other.  Synthesizable counterpart of
// hvl/common/amoeba_link_model.sv, and the module that lets amoeba_pynq_top
// keep every other piece of the PYNQ design unchanged -- the bus it drives is
// the bus amoeba_soc_wrapper drove.
//
// Link side (mirrors the model exactly, since the model is what the ASIC
// bridge has been proven against):
//
//   training   a falling dir with nothing outstanding means "echo": wait TA,
//              drive TRAIN_LEN LFSR words with rvalid=1, release.
//   header     req=1 for two cycles: A[31:16] then A[15:0]; wr/burst sampled.
//   write      32 (burst) or 4 words, LSW first, into the beat FIFO; the
//              transaction descriptor is queued when the last word lands.
//   read       descriptor queued at the header; beats fetched into the line
//              buffer and streamed with rvalid as they land, once dir has
//              fallen and TA has elapsed.  Bus released after the last word.
//   ready      "may start": link idle AND room for a whole line in the queues.
//
// AHB side.  ONE BURST PER TRANSACTION, THE SAME SHAPE THE CORE EMITS.  A line
// op is one INCR8 (NONSEQ + 7 SEQ, address phase pipelined over the previous
// data phase); a single op is one SINGLE at the header's HSIZE.  Both memory
// backends already accept exactly this from wallypipelinedsoc, so
// ahb_to_memitf sees nothing new and ahblite_axi_bridge keeps a line fill as
// one 8-beat AXI burst -- which is the whole reason the AHB is exported
// unflattened (amoeba_soc_wrapper.sv).
//
// THIS MASTER NEVER TERMINATES A BURST EARLY.  Wally's FlushD aborts are
// absorbed on the ASIC side: the link master drains the full line and
// discards it, so every transaction this module starts runs to completion.
// The bridge's burst-termination path is never entered from here.
//
// Ordering: descriptors are processed in order, so a read after a write to
// the same line sees the write.  Writes are issued only once every beat of
// the transaction is in the FIFO, so a burst never stalls waiting for the
// link and no BUSY transfers are needed.
//
// Errors: there is no error path back to the ASIC (BRINGUP.md s2).  A beat
// answered with HRESP=1 returns POISON and is counted; the transaction still
// completes on the link.
//
// IN_REG registers the inbound pins once on the clock before anything looks
// at them -- the structure a real pad needs (IOB flops in stage C), at one
// cycle of latency per transaction which the protocol tolerates by design.
///////////////////////////////////////////////////////////////////////////////

module amoeba_link_slave import amoeba_link_pkg::*; #(
    parameter int TRAIN_LEN = TRAIN_LEN_DEFAULT,
    parameter int PA_BITS   = 56,
    parameter bit IN_REG    = 1'b1
)(
    input  logic                  clk,
    input  logic                  rstn,

    // ---- link pins ---------------------------------------------------------
    input  logic [LINK_W-1:0]     io_i,
    output logic [LINK_W-1:0]     io_o,
    output logic                  io_oe,
    input  logic                  dir,
    input  logic                  req,
    input  logic                  wr,
    input  logic                  burst,
    output logic                  ready,
    output logic                  rvalid,

    // ---- AHB-Lite master ---------------------------------------------------
    output logic                  HSEL,       // address phase valid
    output logic [PA_BITS-1:0]    HADDR,
    output logic [1:0]            HTRANS,
    output logic                  HWRITE,
    output logic [2:0]            HSIZE,
    output logic [2:0]            HBURST,
    output logic [3:0]            HPROT,
    output logic                  HMASTLOCK,
    output logic [63:0]           HWDATA,
    output logic [7:0]            HWSTRB,
    input  logic [63:0]           HRDATA,
    input  logic                  HREADY,
    input  logic                  HRESP,

    // ---- status, to amoeba_ctl ---------------------------------------------
    input  logic                  clear,      // counters, one-cycle pulse
    output logic                  trained,    // echoed, then saw a header
    output logic                  failed,     // the ASIC gave up retraining
    output logic [31:0]           stat_xact,
    output logic [31:0]           stat_rd,
    output logic [31:0]           stat_wr,
    output logic [31:0]           stat_retrain,
    output logic [31:0]           stat_wdog,  // cycles since the last header (saturating)
    output logic [31:0]           stat_err    // {train words mismatched, HRESP beats}
);

    localparam logic [1:0]  HTRANS_IDLE   = 2'b00;
    localparam logic [1:0]  HTRANS_NONSEQ = 2'b10;
    localparam logic [1:0]  HTRANS_SEQ    = 2'b11;
    localparam logic [63:0] POISON        = 64'hBAAD_C0DE_DEAD_BEEF;

    localparam int TC_W = (TRAIN_LEN < 2) ? 1 : $clog2(TRAIN_LEN);
    localparam int TA_W = (TA < 2) ? 1 : $clog2(TA + 1);

    // ---- inbound pins --------------------------------------------------------
    logic [LINK_W-1:0] io_s;
    logic              dir_s, req_s, wr_s, burst_s;
    if (IN_REG) begin : g_inreg
        always_ff @(posedge clk)
            {io_s, dir_s, req_s, wr_s, burst_s} <= {io_i, dir, req, wr, burst};
    end else begin : g_inreg
        assign {io_s, dir_s, req_s, wr_s, burst_s} = {io_i, dir, req, wr, burst};
    end

    // ---- queues --------------------------------------------------------------
    // Descriptors in order of arrival; beats of every queued write, in order.
    // Pushed by the link FSM, popped by the AHB FSM.
    localparam int DQ = 4;
    localparam int WQ = 16;
    typedef struct packed {
        logic        is_wr;
        logic        burst;
        logic [1:0]  size;
        logic [31:0] addr;
    } desc_t;

    desc_t       dq [DQ];
    logic [2:0]  dq_head, dq_tail;
    logic [2:0]  dq_count;
    logic [63:0] wq [WQ];
    logic [4:0]  wq_head, wq_tail;
    logic [4:0]  wq_count;
    assign dq_count = dq_tail - dq_head;
    assign wq_count = wq_tail - wq_head;

    // ---- read line buffer (owned by the AHB FSM) -----------------------------
    logic [63:0] rbuf [BEATS_PER_LINE];
    logic [7:0]  rbuf_valid;
    logic        rd_start;

    // ---- link FSM --------------------------------------------------------------
    typedef enum logic [2:0] {L_TRAIN, L_ECHO_TA, L_ECHO, L_IDLE, L_HDR1, L_WDATA, L_RD_TA, L_RD} l_t;
    l_t              lst;
    logic [15:0]     hdr_hi;
    logic [31:0]     taddr;
    logic [1:0]      tsize;
    logic            tburst;
    logic [5:0]      wcnt;
    logic [47:0]     wacc;
    logic [15:0]     lfsr;
    logic [TC_W-1:0] tcnt;
    logic [TA_W-1:0] ta_cnt;
    logic            dir_q;
    logic            read_pending;
    logic            echoed;                // at least one echo completed
    logic            hdr_seen;              // a header after an echo: the ASIC is trained

    wire last_word = tburst ? (wcnt == 6'd31) : (wcnt == 6'd3);
    wire dir_fall  = dir_q & ~dir_s;

    assign trained = hdr_seen;
    assign failed  = echoed & ~hdr_seen & (stat_retrain >= 32'(TRAIN_RETRIES));

    // Training-direction check, for stage C: while the ASIC drives its LFSR
    // pattern, follow it and count mismatches.  Sync on SEED followed by
    // next(SEED); the ASIC holds SEED for a few cycles out of reset, so the
    // first SEED alone is not the start of the sequence.
    logic [15:0] rx_lfsr, rx_prev;
    logic        rx_sync;
    logic [15:0] err_rx, err_hresp;
    assign stat_err = {err_rx, err_hresp};

    always_ff @(posedge clk) begin
        if (!rstn) begin
            lst <= L_TRAIN; io_o <= '0; io_oe <= 1'b0; ready <= 1'b0; rvalid <= 1'b0;
            dq_tail <= '0; wq_tail <= '0; rd_start <= 1'b0;
            hdr_hi <= '0; taddr <= '0; tsize <= '0; tburst <= 1'b0;
            wcnt <= '0; wacc <= '0; lfsr <= TRAIN_SEED; tcnt <= '0; ta_cnt <= '0;
            dir_q <= 1'b1; read_pending <= 1'b0; echoed <= 1'b0; hdr_seen <= 1'b0;
            stat_xact <= '0; stat_rd <= '0; stat_wr <= '0; stat_retrain <= '0;
            stat_wdog <= '0;
        end else begin
            dir_q    <= dir_s;
            rvalid   <= 1'b0;
            rd_start <= 1'b0;

            // "May start": idle, with room for a descriptor and a whole line.
            ready <= (lst == L_IDLE) & (dq_count <= 3'(DQ - 2))
                   & (wq_count <= 5'(WQ - BEATS_PER_LINE));

            if (clear) begin
                stat_xact <= '0; stat_rd <= '0; stat_wr <= '0; stat_retrain <= '0;
                stat_wdog <= '0;
            end else if (stat_wdog != '1) begin
                stat_wdog <= stat_wdog + 1'b1;
            end

            case (lst)
                // --- training: wait for the ASIC to release the bus, then echo
                L_TRAIN: begin
                    ready <= 1'b0;
                    if (dir_fall) begin
                        ta_cnt <= '0; lfsr <= TRAIN_SEED; tcnt <= '0;
                        lst <= L_ECHO_TA;
                    end
                end
                L_ECHO_TA: begin
                    ta_cnt <= ta_cnt + 1'b1;
                    if (ta_cnt == TA_W'(TA - 1)) lst <= L_ECHO;
                end
                L_ECHO: begin
                    io_oe <= 1'b1; io_o <= lfsr; rvalid <= 1'b1; lfsr <= lfsr_next(lfsr);
                    tcnt <= tcnt + 1'b1;
                    if (tcnt == TC_W'(TRAIN_LEN - 1)) begin
                        if (echoed && !clear) stat_retrain <= stat_retrain + 1'b1;
                        echoed <= 1'b1;
                        lst <= L_IDLE;
                    end
                end

                // --- idle: a header, or a retrain ---------------------------
                L_IDLE: begin
                    io_oe <= 1'b0; rvalid <= 1'b0;
                    if (req_s) begin
                        hdr_hi <= io_s;
                        lst <= L_HDR1;
                    end else if (dir_fall & ~read_pending) begin
                        // dir fell with nothing outstanding: the ASIC did not
                        // accept the last echo and is training again.
                        ta_cnt <= '0; lfsr <= TRAIN_SEED; tcnt <= '0;
                        lst <= L_ECHO_TA;
                    end
                end
                L_HDR1: begin
                    taddr  <= addr_unpack({hdr_hi, io_s});
                    tsize  <= size_unpack({hdr_hi, io_s});
                    tburst <= burst_s; wcnt <= '0; wacc <= '0;
                    hdr_seen  <= 1'b1;
                    stat_wdog <= '0;
                    if (!clear) begin
                        stat_xact <= stat_xact + 1'b1;
                        if (wr_s) stat_wr <= stat_wr + 1'b1;
                        else      stat_rd <= stat_rd + 1'b1;
                    end
                    if (wr_s) begin
                        lst <= L_WDATA;
                    end else begin
                        dq[dq_tail[1:0]] <= '{is_wr: 1'b0, burst: burst_s,
                                              size: size_unpack({hdr_hi, io_s}),
                                              addr: addr_unpack({hdr_hi, io_s})};
                        dq_tail <= dq_tail + 1'b1;
                        rd_start <= 1'b1; read_pending <= 1'b1; ta_cnt <= '0;
                        lst <= L_RD_TA;
                    end
                end

                // --- write: words back to back; beats into the FIFO ---------
                L_WDATA: begin
                    case (wcnt[1:0])
                        2'd0: wacc[15:0]  <= io_s;
                        2'd1: wacc[31:16] <= io_s;
                        2'd2: wacc[47:32] <= io_s;
                        default: begin
                            wq[wq_tail[3:0]] <= {io_s, wacc};
                            wq_tail <= wq_tail + 1'b1;
                        end
                    endcase
                    wcnt <= wcnt + 1'b1;
                    if (last_word) begin
                        dq[dq_tail[1:0]] <= '{is_wr: 1'b1, burst: tburst, size: tsize, addr: taddr};
                        dq_tail <= dq_tail + 1'b1;
                        lst <= L_IDLE;
                    end
                end

                // --- read: wait for the bus, TA, then stream as beats land --
                L_RD_TA: begin
                    if (~dir_s) begin
                        ta_cnt <= ta_cnt + 1'b1;
                        if (ta_cnt == TA_W'(TA - 1)) begin ta_cnt <= '0; lst <= L_RD; end
                    end else begin
                        ta_cnt <= '0;
                    end
                end
                L_RD: begin
                    if (rbuf_valid[wcnt[4:2]]) begin
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

    // Training-direction check, for stage C.  While the ASIC drives its LFSR
    // pattern (every dir=1 stretch before the first header: the first attempt
    // and any retry), follow it and count mismatches.  Sync on SEED followed
    // by next(SEED): the ASIC holds SEED for a few cycles out of reset, so a
    // lone SEED is not the start of the sequence.
    always_ff @(posedge clk) begin
        if (!rstn) begin
            rx_lfsr <= '0; rx_prev <= '0; rx_sync <= 1'b0; err_rx <= '0;
        end else begin
            if (clear) err_rx <= '0;
            rx_prev <= io_s;
            if (~dir_s | hdr_seen) begin
                rx_sync <= 1'b0;
            end else if (lst == L_TRAIN || lst == L_IDLE) begin
                if (~rx_sync) begin
                    if (rx_prev == TRAIN_SEED && io_s == lfsr_next(TRAIN_SEED)) begin
                        rx_sync <= 1'b1;
                        rx_lfsr <= lfsr_next(lfsr_next(TRAIN_SEED));
                    end
                end else begin
                    rx_lfsr <= lfsr_next(rx_lfsr);
                    if (io_s != rx_lfsr && err_rx != '1 && !clear) err_rx <= err_rx + 1'b1;
                end
            end
        end
    end

    // ---- AHB master FSM ----------------------------------------------------
    // Two pipeline slots, as AHB defines them: the address phase (a_*) and the
    // data phase (d_*).  Both advance together on HREADY.  A burst's next beat
    // takes the address phase as soon as the current one moves to data, and a
    // new descriptor takes it the cycle after a burst's last address phase --
    // so back-to-back transactions have no bubble.
    logic        a_valid, a_seq, a_wr, a_burst, a_last;
    logic [1:0]  a_size;
    logic [31:0] a_addr;
    logic [2:0]  a_beat;
    logic        d_valid, d_wr;
    logic [2:0]  d_beat;
    logic [7:0]  d_strb;

    desc_t dnext;
    assign dnext = dq[dq_head[1:0]];

    assign HSEL      = a_valid;
    assign HTRANS    = a_valid ? (a_seq ? HTRANS_SEQ : HTRANS_NONSEQ) : HTRANS_IDLE;
    assign HADDR     = PA_BITS'(a_addr);
    assign HWRITE    = a_wr;
    assign HSIZE     = a_burst ? 3'b011 : {1'b0, a_size};
    assign HBURST    = a_burst ? HBURST_INCR8 : HBURST_SINGLE;
    assign HPROT     = 4'b0011;             // data, privileged; nothing decodes it
    assign HMASTLOCK = 1'b0;
    assign HWDATA    = wq[wq_head[3:0]];    // head is always the beat in data phase
    assign HWSTRB    = d_strb;

    always_ff @(posedge clk) begin
        if (!rstn) begin
            a_valid <= 1'b0; a_seq <= 1'b0; a_wr <= 1'b0; a_burst <= 1'b0; a_last <= 1'b0;
            a_size <= '0; a_addr <= '0; a_beat <= '0;
            d_valid <= 1'b0; d_wr <= 1'b0; d_beat <= '0; d_strb <= '0;
            dq_head <= '0; wq_head <= '0; rbuf_valid <= '0; err_hresp <= '0;
        end else begin
            if (clear) err_hresp <= '0;
            if (rd_start) rbuf_valid <= '0;

            if (HREADY) begin
                // The data phase completes.
                if (d_valid) begin
                    if (d_wr) begin
                        wq_head <= wq_head + 1'b1;
                    end else begin
                        rbuf[d_beat]       <= HRESP ? POISON : HRDATA;
                        rbuf_valid[d_beat] <= 1'b1;
                    end
                    if (HRESP && err_hresp != '1 && !clear) err_hresp <= err_hresp + 1'b1;
                end
                // The address phase becomes the data phase.
                d_valid <= a_valid;
                d_wr    <= a_wr;
                d_beat  <= a_beat;
                d_strb  <= a_burst ? 8'hFF : size_to_mask(a_size, a_addr[2:0]);
                // Next address phase: the burst's next beat, a new descriptor,
                // or nothing.
                if (a_valid & ~a_last) begin
                    a_addr <= a_addr + 32'd8;
                    a_seq  <= 1'b1;
                    a_beat <= a_beat + 1'b1;
                    a_last <= (a_beat == 3'd6);
                end else if (dq_count != '0) begin
                    a_valid <= 1'b1;
                    a_seq   <= 1'b0;
                    a_wr    <= dnext.is_wr;
                    a_burst <= dnext.burst;
                    a_size  <= dnext.size;
                    a_addr  <= dnext.addr;
                    a_beat  <= '0;
                    a_last  <= ~dnext.burst;
                    dq_head <= dq_head + 1'b1;
                end else begin
                    a_valid <= 1'b0;
                    a_seq   <= 1'b0;
                end
            end
        end
    end

`ifndef SYNTHESIS
    // Protocol checks, the same ones the simulation model makes.
    always_ff @(posedge clk) if (rstn) begin
        if (req_s & ~dir_s)
            $error("link slave: req while dir=0");
        if (req_s & lst != L_IDLE & lst != L_HDR1)
            $error("link slave: header while busy (state %0d)", lst);
        if (io_oe & dir_s)
            $error("link slave: driving io while dir=1");
        if (a_valid & a_wr & ~a_seq & (wq_count < (a_burst ? 5'd8 : 5'd1)))
            $error("link slave: write burst issued before its beats arrived");
    end
`endif

endmodule
