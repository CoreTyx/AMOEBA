///////////////////////////////////////////////////////////////////////////////
// fbu_dma_sink.sv -- the link trace and the console into two rings in PS
// memory, through an AXI3 write-only master (S_AXI_HP2;
// docs/impl_plan_fpga_rtl_freeze.md s5.3).
//
// The PS drains BRAM FIFOs a register at a time; on long runs the trace FIFO
// overflows near record 2070 and the console FIFO at 1024 bytes.  With a ring
// enabled this block pops that FIFO instead and writes each entry to PS
// memory, so the PS reads it in bulk:
//   trace    one record per 64-byte slot: five beats of the 320-bit record
//   console  one 16-bit entry, [7:0] the byte and [8] a framing error
// A slot is aligned to its size, so no burst crosses a 4 KB boundary.
//
// WR counts entries whose write has its B: what the PS may read.  An entry is
// issued only while (issued - RD) leaves room, so nothing unread is
// overwritten; a full ring leaves the FIFO to fill and drop as it does
// without the sink.  One write is in flight at a time, the two rings taking
// turns when both have an entry.  A bad BRESP is sticky in err; the entry
// still counts, so the PS sees the gap instead of a stall.
///////////////////////////////////////////////////////////////////////////////
module fbu_dma_sink import fbu_pkg::*; (
  input  logic          clk,
  input  logic          arst_n,

  input  sink_cfg_t     cfg,
  output sink_stat_t    stat,

  input  logic [319:0]  trace_head,
  input  logic          trace_valid,
  output logic          trace_pop,
  input  logic [8:0]    console_head,
  input  logic          console_valid,
  output logic          console_pop,

  output logic [5:0]    m_axi_awid,
  output logic [31:0]   m_axi_awaddr,
  output logic [3:0]    m_axi_awlen,
  output logic [2:0]    m_axi_awsize,
  output logic [1:0]    m_axi_awburst,
  output logic [1:0]    m_axi_awlock,
  output logic [3:0]    m_axi_awcache,
  output logic [2:0]    m_axi_awprot,
  output logic [3:0]    m_axi_awqos,
  output logic          m_axi_awvalid,
  input  logic          m_axi_awready,
  output logic [5:0]    m_axi_wid,
  output logic [63:0]   m_axi_wdata,
  output logic [7:0]    m_axi_wstrb,
  output logic          m_axi_wlast,
  output logic          m_axi_wvalid,
  input  logic          m_axi_wready,
  input  logic [5:0]    m_axi_bid,
  input  logic [1:0]    m_axi_bresp,
  input  logic          m_axi_bvalid,
  output logic          m_axi_bready
);

  localparam int TRACE_BEATS = 5;

  logic [31:0]  trace_issued;
  logic [31:0]  console_issued;
  logic [31:0]  trace_mask;
  logic [31:0]  console_mask;
  logic         trace_room;
  logic         console_room;
  logic         want_trace;
  logic         want_console;
  logic         take_trace;
  logic         take_console;
  logic         console_last;

  logic         busy;
  logic         busy_console;
  logic         aw_pending;
  logic [2:0]   beats_left;
  logic [319:0] record;
  logic [63:0]  console_beat;
  logic [7:0]   console_strb;
  logic         clear_pending;

  logic [31:0]  console_byte_addr;
  logic         acked;

  logic [31:0]  trace_wr;
  logic [31:0]  console_wr;
  logic         err;
  logic [1:0]   err_resp;

  assign trace_mask   = (32'd1 << cfg.trace_log2) - 32'd1;
  assign console_mask = (32'd1 << cfg.console_log2) - 32'd1;
  assign trace_room   = trace_issued - cfg.trace_rd <= trace_mask;
  assign console_room = console_issued - cfg.console_rd <= console_mask;

  assign want_trace   = cfg.trace_en && trace_valid && trace_room;
  assign want_console = cfg.console_en && console_valid && console_room;

  always_comb begin
    take_trace   = 1'b0;
    take_console = 1'b0;
    if (!busy && !clear_pending) begin
      if (want_console && (!want_trace || !console_last))
        take_console = 1'b1;
      else if (want_trace)
        take_trace = 1'b1;
    end
  end

  assign trace_pop   = take_trace;
  assign console_pop = take_console;

  assign console_byte_addr = cfg.console_base + ((console_issued & console_mask) << 1);
  assign acked             = m_axi_bvalid && m_axi_bready;

  // ---- one write: address, beats, response ----
  assign m_axi_awid    = '0;
  assign m_axi_awsize  = 3'd3;
  assign m_axi_awburst = 2'b01;
  assign m_axi_awlock  = 2'b00;
  assign m_axi_awcache = 4'b0011;
  assign m_axi_awprot  = 3'b000;
  assign m_axi_awqos   = '0;
  assign m_axi_awvalid = aw_pending;
  assign m_axi_wid     = '0;
  assign m_axi_wvalid  = beats_left != '0;
  assign m_axi_wlast   = beats_left == 3'd1;
  assign m_axi_wdata   = busy_console ? console_beat : record[64 * (TRACE_BEATS - int'(beats_left)) +: 64];
  assign m_axi_wstrb   = busy_console ? console_strb : 8'hFF;
  assign m_axi_bready  = busy && !aw_pending && beats_left == '0;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      busy           <= 1'b0;
      busy_console   <= 1'b0;
      aw_pending     <= 1'b0;
      beats_left     <= '0;
      console_last   <= 1'b0;
      m_axi_awaddr   <= '0;
      m_axi_awlen    <= '0;
    end else if (take_trace) begin
      busy           <= 1'b1;
      busy_console   <= 1'b0;
      aw_pending     <= 1'b1;
      beats_left     <= 3'(TRACE_BEATS);
      console_last   <= 1'b0;
      m_axi_awaddr   <= cfg.trace_base + ((trace_issued & trace_mask) << 6);
      m_axi_awlen    <= 4'(TRACE_BEATS - 1);
    end else if (take_console) begin
      busy           <= 1'b1;
      busy_console   <= 1'b1;
      aw_pending     <= 1'b1;
      beats_left     <= 3'd1;
      console_last   <= 1'b1;
      m_axi_awaddr   <= console_byte_addr & ~32'h7;
      m_axi_awlen    <= 4'd0;
    end else begin
      if (m_axi_awvalid && m_axi_awready)
        aw_pending <= 1'b0;
      if (m_axi_wvalid && m_axi_wready)
        beats_left <= beats_left - 3'd1;
      if (acked)
        busy <= 1'b0;
    end
  end

  always_ff @(posedge clk) begin
    if (take_trace)
      record <= trace_head;
    if (take_console) begin
      console_beat <= {4{7'd0, console_head}};
      console_strb <= 8'b11 << console_byte_addr[2:0];
    end
  end

  // ---- pointers and status ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      trace_issued     <= '0;
      console_issued   <= '0;
      trace_wr    <= '0;
      console_wr  <= '0;
      clear_pending    <= 1'b0;
      err         <= 1'b0;
      err_resp    <= '0;
    end else if (clear_pending && !busy) begin
      trace_issued     <= '0;
      console_issued   <= '0;
      trace_wr    <= '0;
      console_wr  <= '0;
      clear_pending    <= 1'b0;
      err         <= 1'b0;
      err_resp    <= '0;
    end else begin
      if (cfg.clear)
        clear_pending <= 1'b1;
      if (take_trace)
        trace_issued <= trace_issued + 32'd1;
      if (take_console)
        console_issued <= console_issued + 32'd1;
      if (acked && !busy_console)
        trace_wr <= trace_wr + 32'd1;
      if (acked && busy_console)
        console_wr <= console_wr + 32'd1;
      if (acked && m_axi_bresp != 2'b00 && !err) begin
        err      <= 1'b1;
        err_resp <= m_axi_bresp;
      end
    end
  end

  assign stat = '{err: err, err_resp: err_resp, busy: busy, trace_wr: trace_wr, console_wr: console_wr};

endmodule
