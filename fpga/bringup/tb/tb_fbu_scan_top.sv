///////////////////////////////////////////////////////////////////////////////
// tb_fbu_scan_top.sv -- the scan sessions of fe_scan.cmd (CTRL-14) against
// forte_pynq_top_v alone, through its AXI4-Lite control port.
//
// The top is the RTL forte_pynq_top_v, or (+define+SCAN_TB_TOP=forte_dut_0)
// the bitstream build's synthesized DUT, written with write_verilog -mode
// funcsim: the ports are the same, so a capture path that synthesis removes
// fails here before it reaches the board.  The checker is fe_scan's: io_out
// must be the pattern a fixed latency late while scan_en was high, held while
// it was low, and exactly one latency in 1..6 may fit.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`ifndef SCAN_TB_TOP
  `define SCAN_TB_TOP forte_pynq_top_v
`endif
module tb_fbu_scan_top;
  import fbu_pkg::*;

  localparam int LEN = 1024;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic arst_n = 1'b0;

  logic [11:0] awaddr = '0;
  logic        awvalid = 1'b0;
  logic        awready;
  logic [31:0] wdata = '0;
  logic        wvalid = 1'b0;
  logic        wready;
  logic [1:0]  bresp;
  logic        bvalid;
  logic        bready = 1'b0;
  logic [11:0] araddr = '0;
  logic        arvalid = 1'b0;
  logic        arready;
  logic [31:0] rdata;
  logic [1:0]  rresp;
  logic        rvalid;
  logic        rready = 1'b0;
  logic [3:0]  led;

  int errors = 0;

  `SCAN_TB_TOP board (
    .aclk(clk), .aresetn(arst_n),
    .s_axi_ctl_awaddr(awaddr), .s_axi_ctl_awvalid(awvalid), .s_axi_ctl_awready(awready),
    .s_axi_ctl_wdata(wdata), .s_axi_ctl_wstrb(4'hF), .s_axi_ctl_wvalid(wvalid),
    .s_axi_ctl_wready(wready), .s_axi_ctl_bresp(bresp), .s_axi_ctl_bvalid(bvalid),
    .s_axi_ctl_bready(bready), .s_axi_ctl_araddr(araddr), .s_axi_ctl_arvalid(arvalid),
    .s_axi_ctl_arready(arready), .s_axi_ctl_rdata(rdata), .s_axi_ctl_rresp(rresp),
    .s_axi_ctl_rvalid(rvalid), .s_axi_ctl_rready(rready),
    .s_axi_mem_awaddr(20'd0), .s_axi_mem_awvalid(1'b0), .s_axi_mem_awready(),
    .s_axi_mem_wdata(32'd0), .s_axi_mem_wstrb(4'h0), .s_axi_mem_wvalid(1'b0),
    .s_axi_mem_wready(), .s_axi_mem_bresp(), .s_axi_mem_bvalid(),
    .s_axi_mem_bready(1'b0), .s_axi_mem_araddr(20'd0),
    .s_axi_mem_arvalid(1'b0), .s_axi_mem_arready(),
    .s_axi_mem_rdata(), .s_axi_mem_rresp(), .s_axi_mem_rvalid(),
    .s_axi_mem_rready(1'b0),
    .m_axi_hp_awready(1'b0), .m_axi_hp_wready(1'b0), .m_axi_hp_bid(6'd0), .m_axi_hp_bresp(2'b00),
    .m_axi_hp_bvalid(1'b0), .m_axi_hp_arready(1'b0), .m_axi_hp_rid(6'd0), .m_axi_hp_rdata(64'd0),
    .m_axi_hp_rresp(2'b00), .m_axi_hp_rlast(1'b0), .m_axi_hp_rvalid(1'b0),
    .m_axi_sink_awready(1'b0), .m_axi_sink_wready(1'b0), .m_axi_sink_bid(6'd0), .m_axi_sink_bresp(2'b00),
    .m_axi_sink_bvalid(1'b0), .m_axi_sink_arready(1'b0), .m_axi_sink_rid(6'd0), .m_axi_sink_rdata(64'd0),
    .m_axi_sink_rresp(2'b00), .m_axi_sink_rlast(1'b0), .m_axi_sink_rvalid(1'b0),
    .led);

  task automatic reg_write(input logic [11:0] a, input logic [31:0] d);
    bit aw_done;
    bit w_done;
    @(negedge clk);
    awaddr  = a;
    awvalid = 1'b1;
    wdata   = d;
    wvalid  = 1'b1;
    aw_done = 0;
    w_done  = 0;
    while (!(aw_done && w_done)) begin
      @(posedge clk);
      if (awready) aw_done = 1;
      if (wready)  w_done  = 1;
      @(negedge clk);
      if (aw_done) awvalid = 1'b0;
      if (w_done)  wvalid  = 1'b0;
    end
    bready = 1'b1;
    do @(posedge clk); while (!bvalid);
    @(negedge clk);
    bready = 1'b0;
  endtask

  task automatic reg_read(input logic [11:0] a, output logic [31:0] d);
    @(negedge clk);
    araddr  = a;
    arvalid = 1'b1;
    do @(posedge clk); while (!arready);
    @(negedge clk);
    arvalid = 1'b0;
    rready  = 1'b1;
    while (!rvalid) @(posedge clk);
    d = rdata;
    @(negedge clk);
    rready = 1'b0;
  endtask

  task automatic scan_session(input int seed);
    logic [7:0]  pattern  [LEN];
    logic        pat_en   [LEN];
    logic [7:0]  captured [LEN];
    logic [31:0] xorshift;
    logic [31:0] pin_ctrl_before;
    logic [31:0] ctrl;
    logic [31:0] word;
    int          fits;
    int          fit_latency;
    xorshift = 32'(seed) ^ 32'h9E37_79B9;
    reg_write(REG_SCAN_CTRL, 32'd2);
    reg_write(REG_SCAN_ADDR, 32'd0);
    for (int i = 0; i < LEN; i++) begin
      xorshift = xorshift ^ (xorshift << 13);
      xorshift = xorshift ^ (xorshift >> 17);
      xorshift = xorshift ^ (xorshift << 5);
      pattern[i] = xorshift[7:0];
      pat_en[i]  = xorshift[9:8] != 2'd0;
      reg_write(REG_SCAN_PATTERN, {23'd0, pat_en[i], pattern[i]});
    end
    reg_write(REG_SCAN_LEN, 32'(LEN));
    reg_read(REG_PIN_CTRL, pin_ctrl_before);
    reg_write(REG_PIN_CTRL, pin_ctrl_before | 32'h4);
    reg_write(REG_SCAN_CTRL, 32'd3);
    do reg_read(REG_SCAN_CTRL, ctrl); while (ctrl[8]);
    reg_write(REG_PIN_CTRL, pin_ctrl_before);
    for (int i = 0; i < LEN; i++) begin
      reg_write(REG_SCAN_ADDR, 32'(i));
      reg_read(REG_SCAN_CAPTURE, word);
      captured[i] = word[7:0];
    end
    fits = 0;
    fit_latency = -1;
    for (int latency = 1; latency <= 6; latency++) begin
      bit         ok;
      bit         known;
      logic [7:0] q;
      ok    = 1;
      known = 0;
      q     = '0;
      for (int j = 0; j < LEN; j++) begin
        if (j >= latency && pat_en[j - latency]) begin
          q     = pattern[j - latency];
          known = 1;
        end
        if (known && captured[j] !== q)
          ok = 0;
      end
      if (ok) begin
        fits++;
        fit_latency = latency;
      end
    end
    if (fits == 1) begin
      $display("[SCAN_TB] seed %0d: capture matches at latency %0d", seed, fit_latency);
    end else begin
      errors++;
      $display("[SCAN_TB] seed %0d: capture fits %0d latencies; first entries %h %h %h %h %h %h %h %h",
               seed, fits, captured[0], captured[1], captured[2], captured[3],
               captured[4], captured[5], captured[6], captured[7]);
    end
  endtask

  initial begin
    logic [31:0] id;
    repeat (4) @(posedge clk);
    arst_n = 1'b1;
    repeat (8) @(posedge clk);
    reg_read(REG_ID, id);
    if (id != FBU_ID) begin
      errors++;
      $display("[SCAN_TB] REG_ID %h, expected %h", id, FBU_ID);
    end
    scan_session(1);
    scan_session(2);
    if (errors == 0)
      $display("tb_fbu_scan_top PASS");
    else
      $display("tb_fbu_scan_top FAIL %0d", errors);
    $finish;
  end

  initial begin
    #50ms;
    $display("tb_fbu_scan_top FAIL timeout");
    $finish;
  end

endmodule
