///////////////////////////////////////////////////////////////////////////////
// fbu_link_slave.sv -- the bring-up FPGA's end of the link (forte_link_pkg),
// talking to the chip through its pins only.
//
// Spec: hvl/pin/pin_link_agent.sv.  Every decision and check here is the
// agent's, so a run of this slave and a pin-bench run with the same image and
// knobs produce the same pin trace (fpga/bringup/tb/fbu_vs_pin.sh).
//
// Chip outputs are used in the cycle the chip launched them and every output
// here comes from a flop: the chip captures them on its link-clock negedge.
//
// cfg_det=1 reproduces the bench exactly; a read line the backend has not
// returned by its first word is then an error rather than a stall.
///////////////////////////////////////////////////////////////////////////////
module fbu_link_slave import forte_link_pkg::*, fbu_pkg::*; #(
  parameter int BEATS = 2,
  localparam int LINE_W     = 64 * BEATS,
  localparam int WORDS      = 4 * BEATS,
  localparam int LINE_BYTES = 8 * BEATS,
  localparam int WORD_IDX_W = $clog2(WORDS + 1)
)(
  input  logic              clk,
  input  logic              arst_n,

  input  logic              cfg_det,
  input  logic [6:0]        cfg_gap_pct,
  input  logic [15:0]       cfg_rd_lat,
  input  logic [15:0]       cfg_wdog,
  input  logic [31:0]       cfg_mem_base,
  input  logic [31:0]       cfg_mem_limit,
  input  logic [31:0]       cfg_reset_vec,
  input  logic [31:0]       cfg_tohost_addr,
  input  logic [1:0]        cfg_mutate,
  input  logic              prng_load,
  input  logic [63:0]       prng_init,

  input  logic              rst_n_pin,
  input  logic              dir,
  input  logic              req,
  input  logic              wr,
  input  logic [LINK_W-1:0] io_i,
  output logic [LINK_W-1:0] io_o,
  output logic              io_oe,
  output logic              ready,
  output logic              rvalid,

  output logic              m_req_valid,
  input  logic              m_req_ready,
  output logic              m_req_wr,
  output logic [31:0]       m_req_addr,
  output logic [LINE_W-1:0] m_req_data,
  input  logic              m_rsp_valid,
  input  logic [LINE_W-1:0] m_rsp_data,
  input  logic              m_rsp_err,

  output logic [63:0]       cyc,
  output logic [2:0]        state_now,
  output logic [31:0]       n_rd,
  output logic [31:0]       n_wr,
  output logic              tohost_seen,
  output logic [63:0]       tohost_val,
  output logic [63:0]       tohost_cyc,
  output logic [31:0]       err_now,
  output logic [31:0]       err_sticky,
  output logic [31:0]       err_count,
  output logic [4:0]        first_err,
  output logic [63:0]       first_err_cyc,

  output logic              rec_valid,
  output logic [63:0]       rec_cyc,
  output logic              rec_wr,
  output logic [31:0]       rec_addr,
  output logic [LINE_W-1:0] rec_line,
  output logic              rec_tohost,
  output logic [63:0]       rec_tohost_cyc,
  output logic [63:0]       rec_tohost_val
);

  typedef enum logic [2:0] {
    S_IDLE,
    S_HEADER,
    S_WRITE_DATA,
    S_READ_TURNAROUND,
    S_READ_LATENCY,
    S_READ_DATA,
    S_READ_RELEASE
  } state_t;

  // ---- transaction state ----
  state_t                state;
  logic                  expect_boot_fetch;
  logic [3:0]            not_ready_cycles;
  logic [15:0]           addr_hi;
  logic                  transaction_is_write;
  logic [31:0]           transaction_addr;
  logic [63:0]           transaction_start_cyc;
  logic [WORD_IDX_W-1:0] word_idx;
  logic [2:0]            turnaround_cycles;
  logic [2:0]            release_cycles;
  logic [15:0]           latency_left;
  logic [LINE_W-1:0]     line_buf;
  logic                  read_line_ready;
  logic                  corrupt_read_line;

  logic [63:0]           rand_next;
  logic [6:0]            rand_next_mod100;

  // ---- next-state values ----
  state_t                state_d;
  logic                  expect_boot_fetch_d;
  logic [3:0]            not_ready_cycles_d;
  logic [15:0]           addr_hi_d;
  logic                  transaction_is_write_d;
  logic [31:0]           transaction_addr_d;
  logic [63:0]           transaction_start_cyc_d;
  logic [63:0]           cyc_d;
  logic [WORD_IDX_W-1:0] word_idx_d;
  logic [2:0]            turnaround_cycles_d;
  logic [2:0]            release_cycles_d;
  logic [15:0]           latency_left_d;
  logic [LINE_W-1:0]     line_buf_d;
  logic                  read_line_ready_d;
  logic                  corrupt_read_line_d;
  logic                  ready_d;
  logic                  rvalid_d;
  logic                  io_oe_d;
  logic [LINK_W-1:0]     io_o_d;

  logic                  chip_in_reset;
  logic                  draw_random;
  logic                  gap;
  logic [31:0]           err;
  logic                  transaction_done;
  logic                  tohost_hit;
  logic                  tohost_write;
  logic [63:0]           tohost_word;
  logic                  read_line_available;
  logic [LINE_W-1:0]     read_line;

  logic                  push;
  logic                  push_wr;
  logic [31:0]           push_addr;
  logic [LINE_W-1:0]     push_data;

  logic                  queue_wr   [2];
  logic [31:0]           queue_addr [2];
  logic [LINE_W-1:0]     queue_data [2];
  logic [1:0]            queue_count;
  logic                  queue_head;
  logic                  queue_tail;
  logic                  queue_full;
  logic                  queue_pop;
  logic                  queue_push;

  assign chip_in_reset = !rst_n_pin;
  assign state_now     = state;
  assign draw_random   = !chip_in_reset && cfg_gap_pct != '0;
  assign gap           = draw_random && rand_next_mod100 < cfg_gap_pct;

  // ---- the read line, usable in the cycle the backend returns it ----
  always_comb begin
    read_line_available = read_line_ready || m_rsp_valid;
    if (read_line_ready)
      read_line = line_buf;
    else if (corrupt_read_line)
      read_line = {m_rsp_data[LINE_W-1:64], ~m_rsp_data[63:0]};
    else
      read_line = m_rsp_data;
  end

  // ---- the agent ----
  always_comb begin
    state_d             = state;
    expect_boot_fetch_d = expect_boot_fetch;
    not_ready_cycles_d  = not_ready_cycles;
    addr_hi_d           = addr_hi;
    transaction_is_write_d     = transaction_is_write;
    transaction_addr_d         = transaction_addr;
    transaction_start_cyc_d    = transaction_start_cyc;
    cyc_d               = cyc;
    word_idx_d          = word_idx;
    turnaround_cycles_d = turnaround_cycles;
    release_cycles_d    = release_cycles;
    latency_left_d      = latency_left;
    line_buf_d          = line_buf;
    read_line_ready_d   = read_line_ready;
    corrupt_read_line_d = corrupt_read_line;
    ready_d             = ready;
    rvalid_d            = 1'b0;
    io_oe_d             = 1'b0;
    io_o_d              = io_o;
    err                 = '0;
    transaction_done           = 1'b0;
    tohost_write        = 1'b0;
    tohost_word         = tohost_val;
    tohost_hit          = 1'b0;
    push                = 1'b0;
    push_wr             = 1'b0;
    push_addr           = '0;
    push_data           = '0;

    if (m_rsp_valid && !read_line_ready) begin
      line_buf_d        = read_line;
      read_line_ready_d = 1'b1;
    end

    if (chip_in_reset) begin
      state_d             = S_IDLE;
      cyc_d               = '0;
      expect_boot_fetch_d = 1'b1;
      not_ready_cycles_d  = '0;
      ready_d             = 1'b0;
    end else begin
      cyc_d = cyc + 64'd1;

      if (req && !dir)
        err[LE_REQ_DIR0] = 1'b1;
      if (io_oe && dir)
        err[LE_CONTENTION] = 1'b1;
      if (io_oe && io_i != io_o)
        err[LE_IO_MISMATCH] = 1'b1;

      if (ready)
        not_ready_cycles_d = '0;
      else if (not_ready_cycles != '1)
        not_ready_cycles_d = not_ready_cycles + 4'd1;

      if (state != S_IDLE && cyc_d - transaction_start_cyc == 64'(cfg_wdog))
        err[LE_WATCHDOG] = 1'b1;

      case (state)
        S_IDLE: begin
          if (req) begin
            if (not_ready_cycles_d > 4'(GUARD))
              err[LE_GUARD] = 1'b1;
            addr_hi_d        = io_i;
            transaction_is_write_d  = wr;
            transaction_start_cyc_d = cyc_d;
            state_d          = S_HEADER;
          end
        end

        S_HEADER: begin
          if (!req)
            err[LE_HDR_REQ_DROP] = 1'b1;
          if (wr != transaction_is_write)
            err[LE_HDR_WR_CHG] = 1'b1;
          transaction_addr_d = {addr_hi, io_i};
          if (transaction_addr_d < cfg_mem_base || transaction_addr_d > cfg_mem_limit)
            err[LE_ADDR_RANGE] = 1'b1;
          if (transaction_addr_d % LINE_BYTES != 0)
            err[LE_ADDR_ALIGN] = 1'b1;
          if (expect_boot_fetch && (transaction_is_write || transaction_addr_d != cfg_reset_vec))
            err[LE_FIRST_XACT] = 1'b1;
          expect_boot_fetch_d = 1'b0;
          word_idx_d          = '0;
          ready_d             = 1'b0;
          if (transaction_is_write) begin
            state_d = S_WRITE_DATA;
          end else begin
            push                = 1'b1;
            push_addr           = transaction_addr_d;
            read_line_ready_d   = 1'b0;
            corrupt_read_line_d = cfg_mutate == 2'd1 && n_rd == '0;
            turnaround_cycles_d = '0;
            state_d             = S_READ_TURNAROUND;
          end
        end

        S_WRITE_DATA: begin
          if (req)
            err[LE_WD_REQ] = 1'b1;
          if (!dir)
            err[LE_WD_DIR] = 1'b1;
          if (!wr)
            err[LE_WD_WR] = 1'b1;
          line_buf_d[16 * word_idx +: 16] = io_i;
          word_idx_d = word_idx + 1'b1;
          if (word_idx_d == WORD_IDX_W'(WORDS)) begin
            push      = 1'b1;
            push_wr   = 1'b1;
            push_addr = transaction_addr;
            push_data = line_buf_d;
            if (cfg_tohost_addr >= transaction_addr && cfg_tohost_addr < transaction_addr + LINE_BYTES) begin
              tohost_write = 1'b1;
              tohost_word  = line_buf_d[64 * ((cfg_tohost_addr - transaction_addr) / 8) +: 64];
              if (cfg_mutate == 2'd2)
                tohost_word = 64'd3;
              tohost_hit = tohost_word != '0;
            end
            transaction_done = 1'b1;
            state_d   = S_IDLE;
          end
        end

        S_READ_TURNAROUND: begin
          if (req)
            err[LE_RTA_REQ] = 1'b1;
          if (dir)
            turnaround_cycles_d = '0;
          else
            turnaround_cycles_d = turnaround_cycles + 3'd1;
          if (turnaround_cycles_d >= 3'(TA)) begin
            latency_left_d = cfg_rd_lat;
            if (cfg_rd_lat != '0)
              state_d = S_READ_LATENCY;
            else
              state_d = S_READ_DATA;
          end
        end

        S_READ_LATENCY: begin
          if (dir)
            err[LE_RLAT_DIR] = 1'b1;
          latency_left_d = latency_left - 16'd1;
          if (latency_left_d == '0)
            state_d = S_READ_DATA;
        end

        S_READ_DATA: begin
          if (dir)
            err[LE_RD_DIR] = 1'b1;
          if (req)
            err[LE_RD_REQ] = 1'b1;
          if (!gap && !(cfg_mutate == 2'd3 && n_rd == 32'd10 && word_idx == WORD_IDX_W'(WORDS - 1))) begin
            if (!read_line_available) begin
              if (cfg_det)
                err[LE_LAT_OVERRUN] = 1'b1;
            end else begin
              io_oe_d    = 1'b1;
              rvalid_d   = 1'b1;
              io_o_d     = read_line[16 * word_idx +: 16];
              word_idx_d = word_idx + 1'b1;
              if (word_idx_d == WORD_IDX_W'(WORDS)) begin
                transaction_done        = 1'b1;
                release_cycles_d = '0;
                state_d          = S_READ_RELEASE;
              end
            end
          end
        end

        S_READ_RELEASE: begin
          release_cycles_d = release_cycles + 3'd1;
          if (dir && release_cycles_d <= 3'(TA))
            err[LE_REL_DIR] = 1'b1;
          if (release_cycles_d >= 3'(TA))
            state_d = S_IDLE;
        end

        default: state_d = S_IDLE;
      endcase

      if (state_d == S_IDLE && !req)
        ready_d = !gap && (cfg_det || queue_count == '0);
      else if (state_d != S_IDLE)
        ready_d = 1'b0;
    end

    if (push && queue_full && !queue_pop)
      err[LE_REQ_OVERFLOW] = 1'b1;
    if (m_rsp_valid && m_rsp_err)
      err[LE_MEM_ERR] = 1'b1;
  end

  // ---- two-line request queue to the backend ----
  assign queue_full  = queue_count == 2'd2;
  assign queue_pop   = m_req_valid && m_req_ready;
  assign queue_push  = push && (!queue_full || queue_pop);
  assign queue_tail  = queue_head ^ queue_count[0];
  assign m_req_valid = queue_count != '0;
  assign m_req_wr    = queue_wr[queue_head];
  assign m_req_addr  = queue_addr[queue_head];
  assign m_req_data  = queue_data[queue_head];

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      queue_count <= '0;
      queue_head  <= 1'b0;
    end else begin
      queue_count <= queue_count + 2'(queue_push) - 2'(queue_pop);
      if (queue_pop)
        queue_head <= !queue_head;
    end
  end

  always_ff @(posedge clk) begin
    if (queue_push) begin
      queue_wr[queue_tail]   <= push_wr;
      queue_addr[queue_tail] <= push_addr;
      queue_data[queue_tail] <= push_data;
    end
  end

  // ---- state registers ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      state             <= S_IDLE;
      expect_boot_fetch <= 1'b1;
      not_ready_cycles  <= '0;
      addr_hi           <= '0;
      transaction_is_write     <= 1'b0;
      transaction_addr         <= '0;
      transaction_start_cyc    <= '0;
      word_idx          <= '0;
      turnaround_cycles <= '0;
      release_cycles    <= '0;
      latency_left      <= '0;
      line_buf          <= '0;
      read_line_ready   <= 1'b0;
      corrupt_read_line <= 1'b0;
      ready             <= 1'b0;
      rvalid            <= 1'b0;
      io_oe             <= 1'b0;
      io_o              <= '0;
      cyc               <= '0;
    end else begin
      state             <= state_d;
      expect_boot_fetch <= expect_boot_fetch_d;
      not_ready_cycles  <= not_ready_cycles_d;
      addr_hi           <= addr_hi_d;
      transaction_is_write     <= transaction_is_write_d;
      transaction_addr         <= transaction_addr_d;
      transaction_start_cyc    <= transaction_start_cyc_d;
      word_idx          <= word_idx_d;
      turnaround_cycles <= turnaround_cycles_d;
      release_cycles    <= release_cycles_d;
      latency_left      <= latency_left_d;
      line_buf          <= line_buf_d;
      read_line_ready   <= read_line_ready_d;
      corrupt_read_line <= corrupt_read_line_d;
      ready             <= ready_d;
      rvalid            <= rvalid_d;
      io_oe             <= io_oe_d;
      io_o              <= io_o_d;
      cyc               <= cyc_d;
    end
  end

  // ---- random generator, one draw ahead ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      rand_next        <= '0;
      rand_next_mod100 <= '0;
    end else if (prng_load) begin
      rand_next        <= xorshift64(prng_init);
      rand_next_mod100 <= mod100(xorshift64(prng_init));
    end else if (draw_random) begin
      rand_next        <= xorshift64(rand_next);
      rand_next_mod100 <= mod100(xorshift64(rand_next));
    end
  end

  // ---- counters and tohost ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      n_rd        <= '0;
      n_wr        <= '0;
      tohost_seen <= 1'b0;
      tohost_val  <= '0;
      tohost_cyc  <= '0;
    end else begin
      if (transaction_done && transaction_is_write)
        n_wr <= n_wr + 32'd1;
      if (transaction_done && !transaction_is_write)
        n_rd <= n_rd + 32'd1;
      if (chip_in_reset) begin
        tohost_seen <= 1'b0;
        tohost_val  <= '0;
        tohost_cyc  <= '0;
      end else if (tohost_write) begin
        tohost_val <= tohost_word;
        if (tohost_hit && !tohost_seen) begin
          tohost_seen <= 1'b1;
          tohost_cyc  <= cyc_d;
        end
      end
    end
  end

  // ---- errors ----
  logic [4:0] lowest_err;

  always_comb begin
    lowest_err = LE_NONE;
    for (int i = 31; i >= 1; i--)
      if (err[i])
        lowest_err = 5'(i);
  end

  assign err_now = err;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      err_sticky    <= '0;
      err_count     <= '0;
      first_err     <= LE_NONE;
      first_err_cyc <= '0;
    end else begin
      err_sticky <= err_sticky | err;
      err_count  <= err_count + 32'($countones(err));
      if (err != '0 && first_err == LE_NONE) begin
        first_err     <= lowest_err;
        first_err_cyc <= cyc_d;
      end
    end
  end

  // ---- trace record per finished transaction ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      rec_valid      <= 1'b0;
      rec_cyc        <= '0;
      rec_wr         <= 1'b0;
      rec_addr       <= '0;
      rec_line       <= '0;
      rec_tohost     <= 1'b0;
      rec_tohost_cyc <= '0;
      rec_tohost_val <= '0;
    end else begin
      rec_valid <= transaction_done;
      if (transaction_done) begin
        rec_cyc        <= transaction_start_cyc;
        rec_wr         <= transaction_is_write;
        rec_addr       <= transaction_addr;
        rec_line       <= transaction_is_write ? line_buf_d : read_line;
        rec_tohost     <= tohost_hit;
        rec_tohost_cyc <= cyc_d;
        rec_tohost_val <= tohost_word;
      end
    end
  end

endmodule
