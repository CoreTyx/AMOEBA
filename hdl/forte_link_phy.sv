///////////////////////////////////////////////////////////////////////////////
// forte_link_phy.sv
//
// The link domain: flits in, pins out.  This is hdl/forte_link_master.sv with
// its AHB face replaced by a FIFO face -- the LM_* FSM, the TA counters, the
// word accounting, the dir control and the negedge inbound capture are all the
// same logic, because none of it was ever AHB-specific.
//
//   LM_START     wait for ready (see "ready" in hdl/forte_link_pkg.sv: a hint
//                with a guard band, not a handshake)
//   LM_HDR0/1    req=1, io = A[31:16], A[15:0]
//   LM_WDATA     WORDS words, LSW first, back to back; a new data flit is
//                popped every fourth word
//   LM_RD_TA     dir=0, TA idle cycles
//   LM_RD_DATA   collect rvalid words; push a beat every fourth
//   LM_RD_TA2    TA idle cycles after the last word, then dir=1
//
// THE BUFFERING INVARIANT.  hdl/forte_link_pkg.sv and top_level_plan.md s4:
// "there is no mid-transaction handshake in either direction, so the ASIC never
// stalls once started".  The FPGA cannot absorb an underrun -- there is no pin
// for it.  So this module must not begin a transaction until the WHOLE thing is
// in the outbound FIFO: ocmd_depth >= BEATS+1 for a write (1 command + BEATS
// beats), >= 1 for a read.  That is why the FIFO's occupancy output is
// load-bearing rather than decorative.
//
// BEATS is a per-build parameter, not 8 -- see "ONE BURST LENGTH PER BUILD" in
// hdl/forte_link_pkg.sv.  Nothing in this module needs to know WHY the count is
// what it is; it only has to agree with forte_link_core and the slave, and
// forte_chip drives all three from one expression.
//
// The abort rule does NOT live here.  Once a command is popped this module
// always finishes it on the wire; whether the AHB master is still interested is
// forte_link_core's problem, which is where HTRANS is visible.
//
// Inbound pins are captured on the falling edge and re-registered on the rising
// edge (docs/top_level_plan.md s6).  With the link domain's own small clock tree
// the hold margin no longer depends on the core tree's insertion delay
// (docs/impl_plan_link_clocking.md s4), but the two stages stay: the second one
// is the retiming this FSM reads.
///////////////////////////////////////////////////////////////////////////////

module forte_link_phy import forte_link_pkg::*; #(
  // Beats per transaction; set by hdl/forte_chip.sv from the core config.  The
  // default matches a 512-bit line and exists only because SystemVerilog needs
  // one -- forte_chip always overrides it.
  parameter BEATS = 8
)(
  input  logic               link_clk,
  input  logic               link_rst_n,

  // outbound flits, read side of the core->link FIFO
  input  logic               ocmd_valid,
  output logic               ocmd_ready,
  input  logic [64:0]        ocmd_data,     // {is_cmd, payload}
  // Occupancy of the outbound FIFO, widened by forte_chip to one fixed width so
  // this module does not have to know how deep that FIFO happens to be.
  input  logic [DEPTH_W-1:0] ocmd_depth,

  // inbound beats, write side of the link->core FIFO
  output logic               ibeat_valid,
  input  logic               ibeat_ready,
  output logic [63:0]        ibeat_data,

  // link pins
  output logic [LINK_W-1:0]  io_o,
  output logic               io_oe,        // == dir
  input  logic [LINK_W-1:0]  io_i,
  output logic               dir,
  output logic               req,
  output logic               wr,
  input  logic               ready,
  input  logic               rvalid,

  output logic               txn_done,     // one-cycle pulse per completed transaction
  // High whenever a transaction is on the wire.  Only consumer is the status
  // pin, which needs to tell "nothing is happening" from "something started and
  // never finished" -- the two look identical from txn_done alone.
  output logic               busy
);

  localparam TA_W = (TA < 2) ? 1 : $clog2(TA + 1);

  // Words on the wire per transaction, and the width needed to index them.
  // BEATS >= 2 (checked in forte_link_core), so WORDS >= 8 and WCNT_W >= 3.
  localparam WORDS  = BEATS * WORDS_PER_BEAT;
  localparam WCNT_W = $clog2(WORDS);

  // ---- inbound capture: negedge, then posedge ------------------------------
  logic [LINK_W-1:0] io_n, io_s;
  logic              ready_n, ready_s, rvalid_n, rvalid_s;
  always_ff @(negedge link_clk) {io_n, ready_n, rvalid_n} <= {io_i, ready, rvalid};
  always_ff @(posedge link_clk) {io_s, ready_s, rvalid_s} <= {io_n, ready_n, rvalid_n};

  // ---- state ----------------------------------------------------------------
  link_st_t st;                        // states in hdl/forte_link_pkg.sv

  logic [31:0]     addr_r;
  logic            wr_r;
  logic [63:0]     wdat_r;             // the write beat being serialized
  logic [WCNT_W-1:0] wcnt;             // word within the transaction
  logic [47:0]     beat_r;             // first three words of the beat being assembled
  logic [TA_W-1:0] ta_cnt;

  logic [1:0] sub;
  logic       last_word, beat_end;

  assign sub       = wcnt[1:0];
  assign beat_end  = (sub == 2'd3);
  assign last_word = (wcnt == WCNT_W'(WORDS - 1));   // BEATS beats x 4 words

  // A command may be taken only when the whole transaction is buffered.
  logic cmd_is_wr, cmd_present, cmd_complete;
  assign cmd_is_wr    = ocmd_data[63];
  assign cmd_present  = ocmd_valid & ocmd_data[64];                 // is_cmd
  assign cmd_complete = cmd_present & (cmd_is_wr ? (ocmd_depth >= DEPTH_W'(BEATS + 1)) : 1'b1);

  // The FIFO is popped for the command, then once per write beat.  On the
  // fourth word of a beat the next beat is pulled so wdat_r holds it by the
  // cycle word 0 is registered -- the same one-ahead discipline the old
  // HREADYOUT pulse gave this FSM for free.
  assign ocmd_ready = ((st == LM_IDLE)  & cmd_complete)
                    | ((st == LM_HDR0)  & wr_r)
                    | ((st == LM_WDATA) & beat_end & ~last_word);

  // A read beat is pushed on every fourth rvalid word.
  assign ibeat_valid = (st == LM_RD_DATA) & rvalid_s & beat_end;
  assign ibeat_data  = {io_s, beat_r};

  assign busy = (st != LM_IDLE);

  assign txn_done = (st == LM_WDATA & last_word)
                  | (st == LM_RD_TA2 & ta_cnt == TA_W'(TA - 1));

  // Asynchronous reset, unlike the synchronous HRESETn style this FSM inherited
  // from forte_link_master.  Two reasons: everything else in the link domain
  // (both FIFO ports, the status heartbeat) takes link_rst_n asynchronously, and
  // mixing the two on one net is a real design smell -- Verilator flags it as
  // SYNCASYNCNET.  More importantly this module drives pads: an async assert
  // parks the bus (dir=1, io_oe=1, io_o=0) the instant reset is asserted rather
  // than waiting for an edge, which is what a pad-facing module should do.
  always_ff @(posedge link_clk or negedge link_rst_n) begin
    if (!link_rst_n) begin
      st <= LM_IDLE; io_o <= '0; io_oe <= 1'b1; dir <= 1'b1;
      req <= 1'b0; wr <= 1'b0;
      addr_r <= '0; wr_r <= 1'b0; wdat_r <= '0;
      wcnt <= '0; beat_r <= '0; ta_cnt <= '0;
    end else begin
      case (st)
        LM_IDLE: begin
          req <= 1'b0; wr <= 1'b0; io_o <= '0; io_oe <= 1'b1; dir <= 1'b1;
          if (cmd_complete) begin
            addr_r <= ocmd_data[31:0];
            wr_r   <= cmd_is_wr;
            st     <= LM_START;
          end
        end

        LM_START: begin
          if (ready_s) begin
            io_o <= addr_r[31:16]; req <= 1'b1; wr <= wr_r;
            st <= LM_HDR0;
          end
        end

        // The first write beat is pulled here (ocmd_ready above), so wdat_r
        // holds beat 0 by the time LM_WDATA registers word 0.
        LM_HDR0: begin
          io_o <= addr_r[15:0];
          st <= LM_HDR1;
        end

        LM_HDR1: begin
          req <= 1'b0;
          if (wr_r) begin
            io_o <= wdat_r[15:0]; wcnt <= WCNT_W'(1);  // word 0 is on the pins next cycle
            st <= LM_WDATA;
          end else begin
            io_o <= '0; io_oe <= 1'b0; dir <= 1'b0; ta_cnt <= '0; wcnt <= '0;
            st <= LM_RD_TA;
          end
        end

        LM_WDATA: begin
          // io_o shows word wcnt-1 this cycle; register word wcnt for the next.
          io_o <= wdat_r[16 * wcnt[1:0] +: 16];
          if (last_word) st <= LM_IDLE;
          else           wcnt <= wcnt + WCNT_W'(1);
        end

        LM_RD_TA: begin
          ta_cnt <= ta_cnt + 1'b1;
          if (ta_cnt == TA_W'(TA - 1)) begin ta_cnt <= '0; st <= LM_RD_DATA; end
        end

        LM_RD_DATA: begin
          if (rvalid_s) begin
            case (sub)
              2'd0: beat_r[15:0]  <= io_s;
              2'd1: beat_r[31:16] <= io_s;
              2'd2: beat_r[47:32] <= io_s;
              default: ;                         // the 4th goes straight out
            endcase
            wcnt <= wcnt + WCNT_W'(1);
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

      // The popped write beat lands here.  Not in the case above: the pop is
      // driven combinationally from ocmd_ready, which spans three states.
      if (ocmd_ready & ocmd_valid & ~ocmd_data[64]) wdat_r <= ocmd_data[63:0];
    end
  end

`ifndef SYNTHESIS
  // Assertions are gated on `armed`, not on link_rst_n directly.  Reading the
  // reset as a qualifier inside a clocked block makes Verilator see it as a
  // SYNCHRONOUS reset, which collides with the asynchronous use everywhere else
  // in this domain (both FIFO ports, the status heartbeat) -- SYNCASYNCNET, and
  // a legitimate complaint about one net serving two reset styles.  `armed` also
  // means "at least one clock past reset release", which is what these checks
  // want anyway: none of them is meaningful on the first cycle out of reset.
  logic armed;
  always_ff @(posedge link_clk or negedge link_rst_n)
    if (!link_rst_n) armed <= 1'b0; else armed <= 1'b1;

  // Exactly BEATS beats must leave for every read.  Fewer and the core waits for
  // one that never comes; more and the surplus poisons the next transaction.
  localparam PC_W = $clog2(BEATS + 1);
  logic [PC_W-1:0] push_cnt;
  always_ff @(posedge link_clk or negedge link_rst_n)
    if (!link_rst_n)                        push_cnt <= '0;
    else if (st == LM_IDLE)                 push_cnt <= '0;
    else if (ibeat_valid & ibeat_ready)     push_cnt <= push_cnt + PC_W'(1);
  always @(posedge link_clk)
    if (armed & st == LM_RD_TA2 & ta_cnt == TA_W'(TA - 1))
      assert (push_cnt == PC_W'(BEATS))
        else $fatal(1, "link phy: pushed %0d beats for a read, not %0d", push_cnt, BEATS);

  // The FPGA cannot absorb an underrun, so a transaction must never start
  // without its whole payload buffered.
  always @(posedge link_clk) if (armed & st == LM_IDLE & cmd_complete & cmd_is_wr)
    assert (ocmd_depth >= DEPTH_W'(BEATS + 1))
      else $fatal(1, "link phy: write started with only %0d of %0d flits buffered", ocmd_depth, BEATS + 1);
  // A data flit where a command was expected, or the reverse, means the two
  // sides have lost sync -- what the is_cmd tag is for.
  always @(posedge link_clk) if (armed & st == LM_IDLE & ocmd_valid & ~ocmd_data[64])
    $fatal(1, "link phy: data flit at the head of the outbound FIFO while idle");
  always @(posedge link_clk) if (armed & st == LM_WDATA & ocmd_ready & ocmd_valid & ocmd_data[64])
    $fatal(1, "link phy: command flit where a write beat was expected");
  // The inbound FIFO is sized to BEATS+2 against at most BEATS beats in flight
  // with the core draining, so it can never refuse a push.  If it ever does, a
  // beat is lost.
  always @(posedge link_clk) if (armed & ibeat_valid)
    assert (ibeat_ready) else $fatal(1, "link phy: inbound FIFO full -- read beat dropped");
`endif

endmodule
