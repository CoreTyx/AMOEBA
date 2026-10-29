///////////////////////////////////////////////////////////////////////////////
// fbu_mem_bram.sv -- the chip's external memory in block RAM, as three windows
// of the EXT_MEM space (code and data, the tohost line, the stack top).
//
// Port A serves fbu_top's line interface: one line per request, read data
// the next cycle.  A read outside every window returns POISON with an error,
// a write outside is counted and dropped.
//
// Port B is the PS's AXI4-Lite window, for loading images and reading memory
// back, and the window bases.  It runs on the PL reset, never on the chip's:
// a PS write to a port held in reset never completes, and a Zynq GP port has
// no timeout (feature/top_level, rtl/amoeba_mem_bram.sv).  Port B is only
// used while the chip is held in reset, so the ports are not arbitrated.
//
// Port B map (byte offsets):
//   0x00000  window 0 (W0_KB)        0x40000  window 1 (W1_KB)
//   0x80000  window 2 (W2_KB)        0xC0000  registers:
//     +0x00/04/08  window 0/1/2 base     +0x0C  out-of-window writes
//     +0x10        last out-of-window address
///////////////////////////////////////////////////////////////////////////////
module fbu_mem_bram #(
  parameter int          BEATS   = 2,
  parameter int          W0_KB   = 128,
  parameter int          W1_KB   = 4,
  parameter int          W2_KB   = 16,
  parameter logic [31:0] W0_BASE = 32'h8000_0000,
  parameter logic [31:0] W1_BASE = 32'h8080_0000,
  parameter logic [31:0] W2_BASE = 32'h8FEF_C000,
  localparam int         LINE_W  = 64 * BEATS
)(
  input  logic              clk,
  input  logic              arst_n,

  input  logic              req_valid,
  output logic              req_ready,
  input  logic              req_wr,
  input  logic [31:0]       req_addr,
  input  logic [LINE_W-1:0] req_data,
  output logic              rsp_valid,
  output logic [LINE_W-1:0] rsp_data,
  output logic              rsp_err,

  input  logic [19:0]       s_awaddr,
  input  logic              s_awvalid,
  output logic              s_awready,
  input  logic [31:0]       s_wdata,
  input  logic [3:0]        s_wstrb,
  input  logic              s_wvalid,
  output logic              s_wready,
  output logic [1:0]        s_bresp,
  output logic              s_bvalid,
  input  logic              s_bready,
  input  logic [19:0]       s_araddr,
  input  logic              s_arvalid,
  output logic              s_arready,
  output logic [31:0]       s_rdata,
  output logic [1:0]        s_rresp,
  output logic              s_rvalid,
  input  logic              s_rready
);

  localparam int LINE_BYTES   = LINE_W / 8;
  localparam int LINE_SHIFT   = $clog2(LINE_BYTES);
  localparam int WINDOWS      = 3;
  localparam logic [63:0] POISON = 64'hBAAD_C0DE_DEAD_BEEF;

  localparam int WINDOW_KB [WINDOWS] = '{W0_KB, W1_KB, W2_KB};

  // ---- window bases ----
  logic [31:0] window_base [WINDOWS];
  logic [31:0] out_of_window_writes;
  logic [31:0] out_of_window_last;

  // ---- port B decode ----
  logic        b_write;
  logic [19:0] b_waddr;
  logic [31:0] b_wdata;
  logic [3:0]  b_wstrb;
  logic        b_read;
  logic [19:0] b_raddr;
  logic        b_read_pending;
  logic [1:0]  b_read_region;
  logic [1:0]  b_read_lane;
  logic [31:0] b_read_register;

  // ---- per-window storage ----
  logic [LINE_W-1:0] a_read_data   [WINDOWS];
  logic [LINE_W-1:0] b_read_data   [WINDOWS];
  logic              a_hit         [WINDOWS];
  logic              a_hit_any;
  logic              a_read_hit    [WINDOWS];
  logic              a_read_missed;
  logic              a_read_issued;

  always_comb begin
    a_hit_any = 1'b0;
    for (int w = 0; w < WINDOWS; w++) begin
      a_hit[w]  = req_addr - window_base[w] < 32'(WINDOW_KB[w] * 1024);
      a_hit_any = a_hit_any || a_hit[w];
    end
  end

  assign req_ready = 1'b1;

  for (genvar w = 0; w < WINDOWS; w++) begin : g_window
    localparam int LINES  = WINDOW_KB[w] * 1024 / LINE_BYTES;
    localparam int INDEX_W = $clog2(LINES);

    logic [LINE_W-1:0]  storage [LINES];
    logic [INDEX_W-1:0] a_index;
    logic [INDEX_W-1:0] b_index;
    logic               b_write_here;
    logic [LINE_BYTES-1:0] b_byte_enable;

    assign a_index       = INDEX_W'((req_addr - window_base[w]) >> LINE_SHIFT);
    assign b_index       = INDEX_W'((b_write_here ? b_waddr : b_raddr) >> LINE_SHIFT);
    assign b_write_here  = b_write && b_waddr[19:18] == 2'(w);
    assign b_byte_enable = LINE_BYTES'(b_wstrb) << (4 * b_waddr[LINE_SHIFT-1:2]);

    always_ff @(posedge clk) begin
      if (req_valid && a_hit[w]) begin
        if (req_wr)
          storage[a_index] <= req_data;
        a_read_data[w] <= storage[a_index];
      end
    end

    always_ff @(posedge clk) begin
      if (b_write_here || b_read) begin
        for (int i = 0; i < LINE_BYTES; i++)
          if (b_write_here && b_byte_enable[i])
            storage[b_index][8 * i +: 8] <= b_wdata[8 * (i % 4) +: 8];
        b_read_data[w] <= storage[b_index];
      end
    end
  end

  // ---- port A response ----
  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      a_read_issued <= 1'b0;
      a_read_missed <= 1'b0;
      for (int w = 0; w < WINDOWS; w++)
        a_read_hit[w] <= 1'b0;
    end else begin
      a_read_issued <= req_valid && !req_wr;
      a_read_missed <= req_valid && !req_wr && !a_hit_any;
      for (int w = 0; w < WINDOWS; w++)
        a_read_hit[w] <= a_hit[w];
    end
  end

  always_comb begin
    rsp_valid = a_read_issued;
    rsp_err   = a_read_missed;
    rsp_data  = {BEATS{POISON}};
    for (int w = 0; w < WINDOWS; w++)
      if (a_read_hit[w])
        rsp_data = a_read_data[w];
  end

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      out_of_window_writes <= '0;
      out_of_window_last   <= '0;
    end else if (req_valid && !a_hit_any) begin
      out_of_window_last <= req_addr;
      if (req_wr)
        out_of_window_writes <= out_of_window_writes + 32'd1;
    end
  end

  // ---- port B: AXI4-Lite, read data one cycle after the access ----
  logic have_addr;
  logic have_data;

  assign s_awready = !have_addr && !s_bvalid;
  assign s_wready  = !have_data && !s_bvalid;
  assign s_arready = !s_rvalid && !b_read_pending && !(have_addr && have_data);
  assign s_bresp   = 2'b00;
  assign s_rresp   = 2'b00;
  assign b_write   = have_addr && have_data && !s_bvalid;
  assign b_read    = s_arvalid && s_arready;
  assign b_raddr   = s_araddr;

  always_comb begin
    case (b_raddr[4:2])
      3'd0:    b_read_register = window_base[0];
      3'd1:    b_read_register = window_base[1];
      3'd2:    b_read_register = window_base[2];
      3'd3:    b_read_register = out_of_window_writes;
      3'd4:    b_read_register = out_of_window_last;
      default: b_read_register = '0;
    endcase
  end

  logic [31:0] b_register_value;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      have_addr        <= 1'b0;
      have_data        <= 1'b0;
      b_waddr          <= '0;
      b_wdata          <= '0;
      b_wstrb          <= '0;
      s_bvalid         <= 1'b0;
      s_rvalid         <= 1'b0;
      s_rdata          <= '0;
      b_read_pending   <= 1'b0;
      b_read_region    <= '0;
      b_read_lane      <= '0;
      b_register_value <= '0;
      window_base[0]   <= W0_BASE;
      window_base[1]   <= W1_BASE;
      window_base[2]   <= W2_BASE;
    end else begin
      if (s_awvalid && s_awready) begin
        have_addr <= 1'b1;
        b_waddr   <= s_awaddr;
      end
      if (s_wvalid && s_wready) begin
        have_data <= 1'b1;
        b_wdata   <= s_wdata;
        b_wstrb   <= s_wstrb;
      end
      if (b_write) begin
        have_addr <= 1'b0;
        have_data <= 1'b0;
        s_bvalid  <= 1'b1;
        if (b_waddr[19:18] == 2'd3 && b_waddr[4:2] < 3'(WINDOWS))
          window_base[b_waddr[3:2]] <= b_wdata;
      end else if (s_bvalid && s_bready) begin
        s_bvalid <= 1'b0;
      end

      b_read_pending <= b_read;
      if (b_read) begin
        b_read_region    <= b_raddr[19:18];
        b_read_lane      <= b_raddr[LINE_SHIFT-1:2];
        b_register_value <= b_read_register;
      end
      if (b_read_pending) begin
        s_rvalid <= 1'b1;
        if (b_read_region == 2'd3)
          s_rdata <= b_register_value;
        else
          s_rdata <= b_read_data[b_read_region][32 * b_read_lane +: 32];
      end else if (s_rvalid && s_rready) begin
        s_rvalid <= 1'b0;
      end
    end
  end

endmodule
