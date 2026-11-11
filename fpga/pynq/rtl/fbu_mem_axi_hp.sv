///////////////////////////////////////////////////////////////////////////////
// fbu_mem_axi_hp.sv -- the chip's external memory in PS DDR, through S_AXI_HP0
// (docs/impl_plan_fpga_rtl_freeze.md s5.10, MEM_BACKEND=AXI).
//
// The request side is fbu_mem_bram's port A.  Each line is one AXI3 burst of
// BEATS 64-bit beats, ID 0, AxPROT 000: secure, because the board's
// TZ_DDR_RAM leaves every DDR segment secure-only and a non-secure access
// comes back DECERR (bd_pynq.tcl, the TrustZone note).
//
// EXT_MEM (0x8000_0000..0x8FFF_FFFF) maps onto the carve-out at
// DDR_CARVEOUT; the PS kernel runs with mem=256M and leaves it alone.  A
// request outside EXT_MEM never reaches AXI: a read returns POISON with an
// error, a write is counted and dropped, as in fbu_mem_bram.
//
// Writes are posted, up to MAX_WRITES waiting for B: the link slave keeps
// ready high in DET mode whatever its two-line queue holds, so a writeback
// burst must not wait for DDR.  A read waits until every write has its B (AXI
// orders nothing between the read and write channels) and one read is
// outstanding at a time (the link is serial).
//
// A read accepted or outstanding while the chip is in reset gets no response:
// the slave would take it as the line of the next read after release.  The
// burst still completes on AXI, which cannot abort.  Writes complete as
// issued, as on the bench.
//
// A bad RRESP serves POISON with rsp_err; a bad BRESP is sticky like it.
///////////////////////////////////////////////////////////////////////////////
module fbu_mem_axi_hp #(
  parameter int          BEATS        = 2,
  parameter logic [31:0] DDR_CARVEOUT = 32'h1000_0000,
  parameter int          MAX_WRITES   = 4,
  parameter int          LAT_BINS     = 8,
  localparam int         LINE_W       = 64 * BEATS
)(
  input  logic              clk,
  input  logic              arst_n,
  input  logic              chip_in_reset,

  input  logic              req_valid,
  output logic              req_ready,
  input  logic              req_wr,
  input  logic [31:0]       req_addr,
  input  logic [LINE_W-1:0] req_data,
  output logic              rsp_valid,
  output logic [LINE_W-1:0] rsp_data,
  output logic              rsp_err,

  output logic [5:0]        m_axi_awid,
  output logic [31:0]       m_axi_awaddr,
  output logic [3:0]        m_axi_awlen,
  output logic [2:0]        m_axi_awsize,
  output logic [1:0]        m_axi_awburst,
  output logic [1:0]        m_axi_awlock,
  output logic [3:0]        m_axi_awcache,
  output logic [2:0]        m_axi_awprot,
  output logic [3:0]        m_axi_awqos,
  output logic              m_axi_awvalid,
  input  logic              m_axi_awready,
  output logic [5:0]        m_axi_wid,
  output logic [63:0]       m_axi_wdata,
  output logic [7:0]        m_axi_wstrb,
  output logic              m_axi_wlast,
  output logic              m_axi_wvalid,
  input  logic              m_axi_wready,
  input  logic [5:0]        m_axi_bid,
  input  logic [1:0]        m_axi_bresp,
  input  logic              m_axi_bvalid,
  output logic              m_axi_bready,
  output logic [5:0]        m_axi_arid,
  output logic [31:0]       m_axi_araddr,
  output logic [3:0]        m_axi_arlen,
  output logic [2:0]        m_axi_arsize,
  output logic [1:0]        m_axi_arburst,
  output logic [1:0]        m_axi_arlock,
  output logic [3:0]        m_axi_arcache,
  output logic [2:0]        m_axi_arprot,
  output logic [3:0]        m_axi_arqos,
  output logic              m_axi_arvalid,
  input  logic              m_axi_arready,
  input  logic [5:0]        m_axi_rid,
  input  logic [63:0]       m_axi_rdata,
  input  logic [1:0]        m_axi_rresp,
  input  logic              m_axi_rlast,
  input  logic              m_axi_rvalid,
  output logic              m_axi_rready,

  output logic              mem_err,
  output logic [31:0]       first_err_addr,
  output logic [1:0]        first_err_resp,
  output logic [31:0]       reads,
  output logic [31:0]       writes,
  output logic [31:0]       dropped_writes,
  output logic [15:0]       read_latency_max,   // request accepted to rsp_valid
  output logic [47:0]       read_latency_sum,
  output logic [LAT_BINS-1:0][31:0] read_latency_hist   // 4 cycles a bin, the last open-ended
);

  localparam logic [31:0] EXT_MEM_BASE = 32'h8000_0000;
  localparam logic [31:0] EXT_MEM_MASK = 32'h0FFF_FFFF;
  localparam logic [63:0] POISON       = 64'hBAAD_C0DE_DEAD_BEEF;
  localparam int          BEAT_IDX_W   = $clog2(BEATS + 1);
  localparam int          WRITES_W     = $clog2(MAX_WRITES + 1);

  initial assert (MAX_WRITES >= 2 && (MAX_WRITES & (MAX_WRITES - 1)) == 0)
    else $error("MAX_WRITES must be a power of two, at least 2");

  logic                  in_ext_mem;
  logic [31:0]           ddr_addr;
  logic                  accept;
  logic                  accept_read;
  logic                  accept_write;
  logic                  accept_outside;

  logic                  write_addr_pending;
  logic [BEAT_IDX_W-1:0] write_beats_left;
  logic [LINE_W-1:0]     write_line;
  logic [WRITES_W-1:0]   writes_outstanding;
  logic                  write_acked;
  logic [31:0]           write_addr_fifo [MAX_WRITES];
  logic [$clog2(MAX_WRITES)-1:0] write_addr_head;
  logic [$clog2(MAX_WRITES)-1:0] write_addr_tail;
  logic                  write_channels_idle;

  logic                  read_busy;
  logic                  read_addr_pending;
  logic [BEAT_IDX_W-1:0] read_beat;
  logic [LINE_W-1:0]     read_line;
  logic                  read_bad;
  logic                  read_drop;
  logic [31:0]           read_req_addr;
  logic [15:0]           read_latency;
  logic                  read_done;

  logic                  poison_pending;

  assign in_ext_mem = (req_addr & ~EXT_MEM_MASK) == EXT_MEM_BASE;
  assign ddr_addr   = DDR_CARVEOUT | (req_addr & EXT_MEM_MASK);

  assign write_channels_idle = !write_addr_pending && write_beats_left == '0;
  assign write_acked         = m_axi_bvalid && m_axi_bready;

  always_comb begin
    req_ready = 1'b0;
    if (!read_busy && !poison_pending) begin
      if (!in_ext_mem)
        req_ready = 1'b1;
      else if (req_wr)
        req_ready = write_channels_idle && writes_outstanding != WRITES_W'(MAX_WRITES);
      else
        req_ready = write_channels_idle && writes_outstanding == '0;
    end
  end

  assign accept         = req_valid && req_ready;
  assign accept_outside = accept && !in_ext_mem;
  assign accept_write   = accept && in_ext_mem && req_wr;
  assign accept_read    = accept && in_ext_mem && !req_wr;

  // ---- write address and data ----
  assign m_axi_awid    = '0;
  assign m_axi_awlen   = 4'(BEATS - 1);
  assign m_axi_awsize  = 3'd3;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awlock  = 2'b00;
  assign m_axi_awcache = 4'b0011;
  assign m_axi_awprot  = 3'b000;
  assign m_axi_awqos   = '0;
  assign m_axi_awvalid = write_addr_pending;

  assign m_axi_wid     = '0;
  assign m_axi_wstrb   = '1;
  assign m_axi_wdata   = write_line[64 * (BEATS - int'(write_beats_left)) +: 64];
  assign m_axi_wlast   = write_beats_left == BEAT_IDX_W'(1);
  assign m_axi_wvalid  = write_beats_left != '0;
  assign m_axi_bready  = 1'b1;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      write_addr_pending <= 1'b0;
      write_beats_left   <= '0;
      writes_outstanding <= '0;
      m_axi_awaddr       <= '0;
    end else begin
      if (accept_write) begin
        write_addr_pending <= 1'b1;
        write_beats_left   <= BEAT_IDX_W'(BEATS);
        m_axi_awaddr       <= ddr_addr;
      end else begin
        if (m_axi_awvalid && m_axi_awready)
          write_addr_pending <= 1'b0;
        if (m_axi_wvalid && m_axi_wready)
          write_beats_left <= write_beats_left - 1'b1;
      end
      writes_outstanding <= writes_outstanding + WRITES_W'(accept_write) - WRITES_W'(write_acked);
    end
  end

  always_ff @(posedge clk)
    if (accept_write)
      write_line <= req_data;

  // B comes back in AW order (one ID), so the head names the acknowledged line.
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      write_addr_head <= '0;
      write_addr_tail <= '0;
    end else begin
      if (accept_write)
        write_addr_tail <= write_addr_tail + 1'b1;
      if (write_acked)
        write_addr_head <= write_addr_head + 1'b1;
    end
  end

  always_ff @(posedge clk)
    if (accept_write)
      write_addr_fifo[write_addr_tail] <= req_addr;

  // ---- read address and data ----
  assign m_axi_arid    = '0;
  assign m_axi_arlen   = 4'(BEATS - 1);
  assign m_axi_arsize  = 3'd3;
  assign m_axi_arburst = 2'b01;
  assign m_axi_arlock  = 2'b00;
  assign m_axi_arcache = 4'b0011;
  assign m_axi_arprot  = 3'b000;
  assign m_axi_arqos   = '0;
  assign m_axi_arvalid = read_addr_pending;
  assign m_axi_rready  = read_busy && !read_addr_pending;

  assign read_done = m_axi_rvalid && m_axi_rready && m_axi_rlast;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      read_busy         <= 1'b0;
      read_addr_pending <= 1'b0;
      read_beat         <= '0;
      read_bad          <= 1'b0;
      read_drop         <= 1'b0;
      read_req_addr     <= '0;
      read_latency      <= '0;
      m_axi_araddr      <= '0;
    end else if (accept_read) begin
      read_busy         <= 1'b1;
      read_addr_pending <= 1'b1;
      read_beat         <= '0;
      read_bad          <= 1'b0;
      read_drop         <= chip_in_reset;
      read_req_addr     <= req_addr;
      read_latency      <= 16'd1;
      m_axi_araddr      <= ddr_addr;
    end else if (read_busy) begin
      if (m_axi_arvalid && m_axi_arready)
        read_addr_pending <= 1'b0;
      if (chip_in_reset)
        read_drop <= 1'b1;
      if (read_latency != '1)
        read_latency <= read_latency + 16'd1;
      if (m_axi_rvalid && m_axi_rready) begin
        read_beat <= read_beat + 1'b1;
        if (m_axi_rresp != 2'b00)
          read_bad <= 1'b1;
      end
      if (read_done)
        read_busy <= 1'b0;
    end
  end

  always_ff @(posedge clk)
    if (m_axi_rvalid && m_axi_rready)
      read_line[64 * int'(read_beat) +: 64] <= m_axi_rdata;

  // ---- responses ----
  // One cycle after the last beat, like fbu_mem_bram's registered read.  An
  // out-of-window read answers the cycle after it is accepted.
  logic             read_complete;
  logic             read_complete_bad;
  logic             read_complete_drop;
  logic             read_last_beat_bad;

  assign read_last_beat_bad = m_axi_rresp != 2'b00;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      read_complete      <= 1'b0;
      read_complete_bad  <= 1'b0;
      read_complete_drop <= 1'b0;
      poison_pending     <= 1'b0;
    end else begin
      read_complete      <= read_done;
      read_complete_bad  <= read_bad || read_last_beat_bad;
      read_complete_drop <= read_drop || chip_in_reset;
      poison_pending     <= accept_outside && !req_wr && !chip_in_reset;
    end
  end

  always_comb begin
    rsp_valid = 1'b0;
    rsp_err   = 1'b0;
    rsp_data  = read_line;
    if (poison_pending) begin
      rsp_valid = 1'b1;
      rsp_err   = 1'b1;
      rsp_data  = {BEATS{POISON}};
    end else if (read_complete && !read_complete_drop) begin
      rsp_valid = 1'b1;
      rsp_err   = read_complete_bad;
      if (read_complete_bad)
        rsp_data = {BEATS{POISON}};
    end
  end

  // ---- status ----
  logic        bad_write_ack;
  logic        bad_read;
  logic [15:0] read_latency_to_rsp;
  logic [$clog2(LAT_BINS)-1:0] read_latency_bin;

  // Cycles from the request's acceptance to rsp_valid: what the slave's
  // DET-mode rd_latency must cover.
  assign read_latency_to_rsp = read_latency == '1 ? read_latency : read_latency + 16'd1;
  assign read_latency_bin    = read_latency_to_rsp >= 16'(4 * (LAT_BINS - 1)) ? $clog2(LAT_BINS)'(LAT_BINS - 1)
                                                                            : $clog2(LAT_BINS)'(read_latency_to_rsp >> 2);

  assign bad_write_ack = write_acked && m_axi_bresp != 2'b00;
  assign bad_read      = m_axi_rvalid && m_axi_rready && m_axi_rresp != 2'b00;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      mem_err          <= 1'b0;
      first_err_addr   <= '0;
      first_err_resp   <= '0;
      reads            <= '0;
      writes           <= '0;
      dropped_writes   <= '0;
      read_latency_max <= '0;
      read_latency_sum <= '0;
      read_latency_hist <= '0;
    end else begin
      if ((bad_write_ack || bad_read) && !mem_err) begin
        mem_err        <= 1'b1;
        first_err_addr <= bad_read ? read_req_addr : write_addr_fifo[write_addr_head];
        first_err_resp <= bad_read ? m_axi_rresp : m_axi_bresp;
      end
      if (accept_read)
        reads <= reads + 32'd1;
      if (accept_write)
        writes <= writes + 32'd1;
      if (accept_outside && req_wr)
        dropped_writes <= dropped_writes + 32'd1;
      if (read_done) begin
        read_latency_sum <= read_latency_sum + 48'(read_latency_to_rsp);
        read_latency_hist[read_latency_bin] <= read_latency_hist[read_latency_bin] + 32'd1;
        if (read_latency_to_rsp > read_latency_max)
          read_latency_max <= read_latency_to_rsp;
      end
    end
  end

endmodule
