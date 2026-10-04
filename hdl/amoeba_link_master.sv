///////////////////////////////////////////////////////////////////////////////
// amoeba_link_master.sv
//
// AHB-Lite slave on the SoC's external port -> the 16-bit off-chip link
// (pkg/amoeba_link_pkg.sv).  Drop-in for hdl/ahb_to_memitf.sv.
//
// One transaction at a time.  Address phase is latched when the core's
// address phase completes (HREADY is the uncore's mux, not ours: the previous
// data phase may belong to the APB bridge), then:
//
//   LM_START     wait for ready (see "ready" in pkg/amoeba_link_pkg.sv: it is a
//             hint with a guard band, not a handshake)
//   LM_HDR0/1    req=1, io = A[31:16], A[15:0] -- the whole address, no bits stolen
//   LM_WDATA     32 words of HWDATA, LSW first, back to back.
//             HREADYEXT pulses on the 4th word of each beat so the core
//             presents the next beat exactly when it is needed.
//   LM_RD_TA     dir=0, TA idle cycles
//   LM_RD_DATA   collect rvalid words; HREADYEXT + HRDATA on every 4th
//   LM_RD_TA2    TA idle cycles after the last word, then dir=1
//
// THE ABORT RULE.  buscachefsm drops to ADR_PHASE on FlushD in the same
// cycle, so an I-fetch line fill can lose its master mid-burst.  Once the
// header has left the chip the FPGA is committed to the full word count, so
// this bridge always finishes it.  What it must NOT do is complete an AHB
// beat while the master has moved on: a NONSEQ appearing at a beat boundary
// is the master's *next* request, and pulsing HREADY then would accept it
// while we are still draining the old one.  So at a non-final beat boundary
// HREADYEXT pulses only if HTRANS==SEQ (the master is still in this burst);
// otherwise the bridge drains silently and the master, which only issues a
// new NONSEQ while HREADY=1, waits for LM_IDLE.  Only reads are ever aborted
// (the D-cache's buscachefsm has Flush tied low); the write path drains the
// same way for symmetry.
//
// Pipelined next request: at the final beat's HREADYEXT pulse the master may
// already present the next NONSEQ.  It is accepted at that edge (HREADY=1),
// latched into nxt_*, and started once the bus is back in the ASIC's hands.
//
// Inbound pins are captured on the falling edge and re-registered on the
// rising edge (docs/top_level_plan.md s6): hold margin against an FPGA whose
// clock-to-out is shorter than this die's clock-tree insertion, at no cost
// in latency.
//
// INCR8 ONLY (pkg/amoeba_link_pkg.sv): the wire carries no size and no byte
// strobes, because with PERIPH_ONCHIP=1 every off-chip access is a cacheable
// line fill or writeback -- measured zero singles in 4032 transactions across
// the ISA regression.  HSIZE and HBURST survive as ports only so the assertions
// at the bottom can catch a transfer this link cannot express.
//
// Reset: from HRESETn, the core's synchronised reset -- wallypipelinedcore
// parks nothing on its AHB while held in reset (fpga/pynq/rtl/amoeba_pynq_top.sv).
// There is no longer a `run` gate: link training is gone and the FPGA holds
// rst_n until it is ready to serve (pkg/amoeba_link_pkg.sv).
///////////////////////////////////////////////////////////////////////////////

module amoeba_link_master import amoeba_link_pkg::*; #(
  parameter HADDR_W = 56
)(
  input  logic               HCLK, HRESETn,

  // AHB-Lite slave (external port of amoeba_soc)
  input  logic               HSEL,
  input  logic [HADDR_W-1:0] HADDR,
  input  logic [1:0]         HTRANS,       // 00 IDLE 01 BUSY 10 NONSEQ 11 SEQ
  input  logic               HWRITE,
  input  logic [2:0]         HSIZE,
  input  logic [2:0]         HBURST,
  input  logic [63:0]        HWDATA,
  input  logic               HREADY,       // the uncore's mux: address phase completes on this
  output logic [63:0]        HRDATA,
  output logic               HREADYOUT,
  output logic               HRESP,

  // link
  output logic [LINK_W-1:0]  io_o,
  output logic               io_oe,        // == dir
  input  logic [LINK_W-1:0]  io_i,
  output logic               dir,
  output logic               req,
  output logic               wr,
  output logic               burst,
  input  logic               ready,
  input  logic               rvalid,

  output logic               txn_done      // one-cycle pulse per completed transaction
);

  localparam logic [1:0] HTRANS_IDLE = 2'b00, HTRANS_NONSEQ = 2'b10, HTRANS_SEQ = 2'b11;

  // HSIZE and HBURST feed assertions only now that INCR8 is implicit on the
  // wire.  Sink them so the synthesis flow does not warn about unread inputs.
  logic unused_attrs;
  assign unused_attrs = ^{HSIZE, HBURST};
  localparam TA_W = (TA < 2) ? 1 : $clog2(TA + 1);

  // ---- inbound capture: negedge, then posedge ------------------------------
  logic [LINK_W-1:0] io_n, io_s;
  logic              ready_n, ready_s, rvalid_n, rvalid_s;
  always_ff @(negedge HCLK) {io_n, ready_n, rvalid_n} <= {io_i, ready, rvalid};
  always_ff @(posedge HCLK) {io_s, ready_s, rvalid_s} <= {io_n, ready_n, rvalid_n};

  // ---- state ----------------------------------------------------------------
  link_st_t st;                        // states in pkg/amoeba_link_pkg.sv

  logic [31:0] addr_r, nxt_addr;
  logic        wr_r, nxt_wr, pending;
  logic [4:0]  wcnt;                 // word within the transaction
  logic [47:0] beat_r;               // first three words of the beat being assembled
  logic [TA_W-1:0] ta_cnt;
  logic        aborted;

  logic [1:0]  sub;                  // word within the beat
  logic [1:0]  htrans_q;             // HTRANS a cycle ago: breaks the HREADY->HTRANS->HREADYOUT loop
  logic        last_word, beat_end, last_beat, beat_ok, accept;
  always_ff @(posedge HCLK) htrans_q <= HTRANS;

  assign sub       = wcnt[1:0];
  assign beat_end  = (sub == 2'd3);
  assign last_word = (wcnt == 5'd31);          // INCR8: 8 beats x 4 words
  assign last_beat = (wcnt[4:2] == 3'd7);
  // Complete this AHB beat only if the master is still here for it.  HTRANS
  // is looked at through a register: Wally's HTRANS mux depends on HREADY,
  // so a combinational look would loop.  The master holds SEQ for the whole
  // beat, and a flush in the pulse cycle itself cannot raise NONSEQ (~Flush
  // gates it), so the one-cycle-old value is exact.  Never pulse while a
  // pipelined transaction is pending: its data phase must stay stalled.
  assign beat_ok   = ~aborted & ~pending & (last_beat | (htrans_q == HTRANS_SEQ));

  // Address phase of a transfer to us completes on the mux'd HREADY.
  assign accept = HSEL & (HTRANS == HTRANS_NONSEQ) & HREADY;   // SEQ beats belong to the current burst

  // ---- AHB response ----------------------------------------------------------
  logic wr_pulse, rd_pulse;
  assign wr_pulse  = (st == LM_WDATA)   & beat_end & beat_ok;
  assign rd_pulse  = (st == LM_RD_DATA) & rvalid_s & beat_end & beat_ok;
  assign HREADYOUT = (st == LM_IDLE & ~pending) | wr_pulse | rd_pulse;
  assign HRDATA    = {io_s, beat_r};
  assign HRESP     = 1'b0;              // no error path (BRINGUP.md s2)

  // The address phase of a transfer to us completes whenever the mux'd HREADY
  // is high with HSEL & HTRANS[1] -- in LM_IDLE, at the final beat's pulse, or
  // in a turnaround state if the delayed select happens to be "none".  It is
  // accepted wherever it lands: straight into the working registers from
  // LM_IDLE, otherwise into the single pending slot.  Its data phase then stalls
  // on HREADYOUT=0 until we get to it, so a second one cannot arrive.
  assign txn_done = (st == LM_WDATA & last_word) | (st == LM_RD_TA2 & ta_cnt == TA_W'(TA - 1));

  always_ff @(posedge HCLK) begin
    if (!HRESETn) begin
      st <= LM_IDLE; io_o <= '0; io_oe <= 1'b1; dir <= 1'b1; req <= 1'b0; wr <= 1'b0; burst <= 1'b0;
      addr_r <= '0; wr_r <= 1'b0;
      nxt_addr <= '0; nxt_wr <= 1'b0; pending <= 1'b0;
      wcnt <= '0; beat_r <= '0; ta_cnt <= '0; aborted <= 1'b0;
    end else begin
      case (st)
        LM_IDLE: begin
          req <= 1'b0; wr <= 1'b0; burst <= 1'b0; io_o <= '0; io_oe <= 1'b1; dir <= 1'b1;
          aborted <= 1'b0;
          if (pending) begin
            addr_r <= nxt_addr; wr_r <= nxt_wr;
            pending <= 1'b0;
            st <= LM_START;
          end
        end

        LM_START: begin
          if (ready_s) begin
            io_o <= addr_r[31:16]; req <= 1'b1; wr <= wr_r; burst <= 1'b1;
            st <= LM_HDR0;
          end
        end

        LM_HDR0: begin
          io_o <= addr_r[15:0];
          st <= LM_HDR1;
        end

        LM_HDR1: begin
          req <= 1'b0;
          if (wr_r) begin
            io_o <= HWDATA[15:0]; wcnt <= 5'd1;   // word 0 is on the pins next cycle
            st <= LM_WDATA;
          end else begin
            io_o <= '0; io_oe <= 1'b0; dir <= 1'b0; ta_cnt <= '0; wcnt <= '0;
            st <= LM_RD_TA;
          end
        end

        LM_WDATA: begin
          // io_o shows word wcnt-1 this cycle; register word wcnt for the next.
          // On the 4th word of a beat HREADYOUT pulses (if beat_ok) so the core
          // has the next beat on HWDATA by the cycle it is needed.
          io_o <= HWDATA[16 * wcnt[1:0] +: 16];
          if (~beat_ok & beat_end) aborted <= 1'b1;
          if (last_word) st <= LM_IDLE;
          else           wcnt <= wcnt + 5'd1;
        end

        LM_RD_TA: begin
          ta_cnt <= ta_cnt + 1'b1;
          if (ta_cnt == TA_W'(TA - 1)) begin ta_cnt <= '0; st <= LM_RD_DATA; end
        end

        LM_RD_DATA: begin
          if (rvalid_s) begin
            if (~beat_ok & beat_end) aborted <= 1'b1;
            case (sub)
              2'd0: beat_r[15:0]  <= io_s;
              2'd1: beat_r[31:16] <= io_s;
              2'd2: beat_r[47:32] <= io_s;
              default: ;
            endcase
            wcnt <= wcnt + 5'd1;
            if (last_word) begin ta_cnt <= '0; st <= LM_RD_TA2; end
          end
        end

        LM_RD_TA2: begin
          ta_cnt <= ta_cnt + 1'b1;
          if (ta_cnt == TA_W'(TA - 1)) begin
            io_oe <= 1'b1; dir <= 1'b1;
            st <= LM_IDLE;
          end
        end

        default: st <= LM_IDLE;
      endcase

      // Accept, wherever the address phase completes (see above).
      if (accept) begin
        if (st == LM_IDLE & ~pending) begin
          addr_r <= HADDR[31:0]; wr_r <= HWRITE;
          st <= LM_START;
        end else begin
          nxt_addr <= HADDR[31:0]; nxt_wr <= HWRITE; pending <= 1'b1;
        end
      end
    end
  end

`ifndef SYNTHESIS
  // The pending slot is single: a second accept while one is pending would
  // mean the data phase of the pending one did not stall, which the uncore's
  // HREADY mux makes impossible.
  always_ff @(posedge HCLK) if (HRESETn & accept & pending & st != LM_IDLE)
    $fatal(1, "link: second pipelined accept");
  // The address is sent whole, so the only remaining constraint is 32 bits.
  always_ff @(posedge HCLK) if (HRESETn & accept) begin
    assert (HADDR[HADDR_W-1:32] == '0) else $fatal(1, "link: HADDR above 4 GB: %h", HADDR);
    // INCR8 only: the wire carries no size and no strobes, so anything else is
    // a transfer this link cannot express.  With PERIPH_ONCHIP=1 nothing can
    // generate one; these fire the day that stops being true.
    assert (HBURST == HBURST_INCR8)
      else $fatal(1, "link: HBURST %b -- the link is INCR8 only", HBURST);
    assert (HSIZE == 3'b011 & HADDR[2:0] == 3'b000)
      else $fatal(1, "link: INCR8 with HSIZE %b at %h is not a full aligned beat", HSIZE, HADDR);
  end
  // Writes are never aborted (D-cache Flush is tied low); if that changes,
  // junk goes to memory and this is the first thing to fire.
  always_ff @(posedge HCLK) if (HRESETn & st == LM_WDATA & beat_end & ~beat_ok)
    $fatal(1, "link: write burst abandoned by the master");
`endif

endmodule
