// Directed check that the vendored prim_fifo_async works at the width, depth and
// clock ratio the link will use -- before it is wired into the bridge.
//
// The ratio is deliberately NON-INTEGER (1 : 1.37).  A 1:1 or 2:1 ratio samples
// the Gray-coded pointers at a fixed phase and hides exactly the crossing bugs
// this module exists to prevent.
// Testbench idioms, not design issues: blocking assignments for counters and
// clock generation, and one reset used both synchronously and asynchronously.
// The vendored prim_fifo_async.sv and prim_flop_2sync.sv are clean under -Wall
// with no waivers -- only this file needs them.
/* verilator lint_off BLKSEQ */
/* verilator lint_off SYNCASYNCNET */
module tb_prim_fifo_async;

  localparam int W = 65;      // outbound flit: {is_cmd, payload[63:0]}
  localparam int D = 16;      // one line (1 cmd + 8 beats) with slack

  logic wclk = 0, rclk = 0, rst_n = 0;

  // 10.0 ns core side, 7.299 ns link side -> ratio 1.3701..., not a rational
  // multiple of anything the design can resonate with.
  always #5.000  wclk = ~wclk;
  always #3.6495 rclk = ~rclk;

  logic          wvalid, wready, rvalid, rready;
  logic [W-1:0]  wdata, rdata;
  logic [4:0]    wdepth, rdepth;

  prim_fifo_async #(.Width(W), .Depth(D)) dut (
    .clk_wr_i(wclk), .rst_wr_ni(rst_n),
    .wvalid_i(wvalid), .wready_o(wready), .wdata_i(wdata), .wdepth_o(wdepth),
    .clk_rd_i(rclk), .rst_rd_ni(rst_n),
    .rvalid_o(rvalid), .rready_i(rready), .rdata_o(rdata), .rdepth_o(rdepth));

  // ---- writer: a known sequence, back to back whenever wready ----
  localparam int N = 2000;
  logic [W-1:0] expect_q[$];
  int n_wr = 0, n_rd = 0, n_bad = 0;
  logic [W-1:0] pat;

  always @(posedge wclk) begin
    if (!rst_n) begin
      wvalid <= 1'b0; wdata <= '0; pat <= 65'h1;
    end else begin
      // Offer a word whenever there is room and we have not finished.
      if (wready && n_wr < N) begin
        wvalid <= 1'b1;
        wdata  <= pat;
        pat    <= {pat[W-2:0], pat[W-1] ^ pat[60] ^ pat[7] ^ pat[0]};
      end else begin
        wvalid <= 1'b0;
      end
    end
  end
  // Count and record on the cycle the write is actually taken.
  always @(posedge wclk) if (rst_n && wvalid && wready) begin
    expect_q.push_back(wdata);
    n_wr++;
  end

  // ---- reader: drain with a varying backpressure pattern ----
  int rcnt = 0;
  always @(posedge rclk) begin
    if (!rst_n) begin
      rready <= 1'b0; rcnt <= 0;
    end else begin
      rcnt   <= rcnt + 1;
      rready <= (rcnt % 5) != 0;     // stall 1 in 5 so the FIFO actually fills
    end
  end

  always @(posedge rclk) if (rst_n && rvalid && rready) begin
    if (expect_q.size() == 0) begin
      $display("FAIL: read %h with nothing expected", rdata); n_bad++;
    end else begin
      logic [W-1:0] e; e = expect_q.pop_front();
      if (rdata !== e) begin
        $display("FAIL: word %0d got %h expected %h", n_rd, rdata, e); n_bad++;
      end
    end
    n_rd++;
  end

  // ---- the Gray-pointer invariant, in a form Verilator can run ----
  // prim_fifo_async states this itself as GrayWptr_A / GrayRptr_A, but those use
  // a `##1` sequence delay that Verilator 5.026 rejects outright, so
  // prim_assert.sv compiles them out under ECE411_VERILATOR.  This is the same
  // property: at most one bit of either Gray pointer may change per clock.  It
  // is the check that catches the pointer logic breaking, so it should not be
  // silently absent in the simulator the regression actually uses.
  logic [$bits(dut.fifo_wptr_gray_q)-1:0] wg_prev;
  logic [$bits(dut.fifo_rptr_gray_q)-1:0] rg_prev;

  always @(posedge wclk) begin
    if (!rst_n) wg_prev <= '0;
    else begin
      if ($countones(dut.fifo_wptr_gray_q ^ wg_prev) > 1) begin
        $display("FAIL: write Gray pointer changed %0d bits (%b -> %b)",
                 $countones(dut.fifo_wptr_gray_q ^ wg_prev), wg_prev, dut.fifo_wptr_gray_q);
        n_bad++;
      end
      wg_prev <= dut.fifo_wptr_gray_q;
    end
  end

  always @(posedge rclk) begin
    if (!rst_n) rg_prev <= '0;
    else begin
      if ($countones(dut.fifo_rptr_gray_q ^ rg_prev) > 1) begin
        $display("FAIL: read Gray pointer changed %0d bits (%b -> %b)",
                 $countones(dut.fifo_rptr_gray_q ^ rg_prev), rg_prev, dut.fifo_rptr_gray_q);
        n_bad++;
      end
      rg_prev <= dut.fifo_rptr_gray_q;
    end
  end

  // ---- occupancy must never exceed Depth on either side ----
  localparam logic [4:0] DMAX = 5'(D);
  always @(posedge wclk) if (rst_n && wdepth > DMAX) begin
    $display("FAIL: wdepth=%0d > Depth=%0d", wdepth, D); n_bad++;
  end
  always @(posedge rclk) if (rst_n && rdepth > DMAX) begin
    $display("FAIL: rdepth=%0d > Depth=%0d", rdepth, D); n_bad++;
  end

  initial begin
    repeat (5) @(posedge wclk);
    rst_n = 1;
    // Long enough to pass N words through with the stall pattern.
    repeat (40000) @(posedge rclk);
    $display("prim_fifo_async: wrote=%0d read=%0d mismatches=%0d still_queued=%0d",
             n_wr, n_rd, n_bad, expect_q.size());
    if (n_bad == 0 && n_rd == N && expect_q.size() == 0)
      $display("PRIM_FIFO_ASYNC PASS");
    else
      $display("PRIM_FIFO_ASYNC FAIL");
    $finish;
  end

endmodule
/* verilator lint_on SYNCASYNCNET */
/* verilator lint_on BLKSEQ */
