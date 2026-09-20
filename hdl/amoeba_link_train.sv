///////////////////////////////////////////////////////////////////////////////
// amoeba_link_train.sv
//
// Link training and the core-reset gate (docs/top_level_plan.md s6).
//
// After rst_n releases the ASIC owns the bus and drives TRAIN_LEN words of a
// known LFSR sequence (dir=1, req=0) so the FPGA can centre its input delay.
// It then releases the bus (dir=0) and, after TA idle cycles, expects the
// FPGA to echo the same TRAIN_LEN words with rvalid=1 so the FPGA can centre
// its output phase.  Every word matches -> trained: the core comes out of
// reset and the link master takes the bus.  A mismatch, or no echo within
// the timeout, retries; after TRAIN_RETRIES failures the core is held in
// reset and status stays low so a dead link is visible on the LED.
//
// The FPGA needs only dir to frame this: it never sees req during training,
// and a falling dir without a preceding req means "echo now".
///////////////////////////////////////////////////////////////////////////////

module amoeba_link_train import amoeba_link_pkg::*; #(
  parameter TRAIN_LEN = TRAIN_LEN_DEFAULT,
  parameter RETRIES   = TRAIN_RETRIES
)(
  input  logic              clk,
  input  logic              rst_n,

  output logic [LINK_W-1:0] io_o,
  output logic              io_oe,        // == dir while training
  input  logic [LINK_W-1:0] io_i,
  output logic              dir,
  input  logic              rvalid,

  output logic              trained,
  output logic              failed
);

  localparam CNT_W  = $clog2(TRAIN_LEN + 1);
  localparam TO_W   = CNT_W + 2;       // echo timeout = 4 x TRAIN_LEN
  localparam RTRY_W = $clog2(RETRIES + 1);
  localparam TA_W   = (TA < 2) ? 1 : $clog2(TA + 1);

  // inbound: negedge capture, posedge re-register (as the link master)
  logic [LINK_W-1:0] io_n, io_s;
  logic              rvalid_n, rvalid_s;
  always_ff @(negedge clk) {io_n, rvalid_n} <= {io_i, rvalid};
  always_ff @(posedge clk) {io_s, rvalid_s} <= {io_n, rvalid_n};

  typedef enum logic [2:0] {TX, TA1, RX, TA2, DONE, FAIL} st_t;
  st_t st;

  logic [15:0]       lfsr;
  logic [CNT_W-1:0]  cnt;
  logic [TO_W-1:0]   timeout;
  logic [RTRY_W-1:0] retries;
  logic [TA_W-1:0]   ta_cnt;

  assign trained = (st == DONE);
  assign failed  = (st == FAIL);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      st <= TX; lfsr <= TRAIN_SEED; cnt <= '0; timeout <= '0; retries <= '0; ta_cnt <= '0;
      io_o <= TRAIN_SEED; io_oe <= 1'b1; dir <= 1'b1;
    end else begin
      case (st)
        TX: begin
          // io_o shows lfsr this cycle; advance for the next.
          io_o <= lfsr_next(lfsr); lfsr <= lfsr_next(lfsr);
          cnt <= cnt + 1'b1;
          if (cnt == CNT_W'(TRAIN_LEN - 1)) begin
            io_o <= '0; io_oe <= 1'b0; dir <= 1'b0; ta_cnt <= '0;
            lfsr <= TRAIN_SEED; cnt <= '0; timeout <= '0;
            st <= TA1;
          end
        end

        TA1: begin
          ta_cnt <= ta_cnt + 1'b1;
          if (ta_cnt == TA_W'(TA - 1)) begin ta_cnt <= '0; st <= RX; end
        end

        RX: begin
          timeout <= timeout + 1'b1;
          if (rvalid_s) begin
            lfsr <= lfsr_next(lfsr); cnt <= cnt + 1'b1;
            if (io_s != lfsr)                   st <= (retries == RTRY_W'(RETRIES)) ? FAIL : TX;
            else if (cnt == CNT_W'(TRAIN_LEN - 1)) begin ta_cnt <= '0; st <= TA2; end
          end else if (timeout == '1)           st <= (retries == RTRY_W'(RETRIES)) ? FAIL : TX;
          // retry bookkeeping
          if ((rvalid_s & io_s != lfsr) | (~rvalid_s & timeout == '1)) begin
            retries <= retries + 1'b1; lfsr <= TRAIN_SEED; cnt <= '0;
            io_o <= TRAIN_SEED; io_oe <= 1'b1; dir <= 1'b1;
          end
        end

        TA2: begin
          ta_cnt <= ta_cnt + 1'b1;
          if (ta_cnt == TA_W'(TA - 1)) begin io_oe <= 1'b1; dir <= 1'b1; io_o <= '0; st <= DONE; end
        end

        DONE: ;                                  // link master owns the bus now
        FAIL: begin io_oe <= 1'b0; dir <= 1'b0; end
        default: st <= FAIL;
      endcase
    end
  end

endmodule
