///////////////////////////////////////////////////////////////////////////////
// fbu_axil.sv -- AXI4-Lite slave to a single-cycle register port.
//
// One transaction at a time.  A write is taken when both its address and data
// have arrived (in either order) and issued as one reg_write cycle; a read is
// one reg_read cycle with reg_rdata sampled in that cycle.  Responses are OKAY.
///////////////////////////////////////////////////////////////////////////////
module fbu_axil #(
  parameter int ADDR_W = 12
)(
  input  logic              clk,
  input  logic              arst_n,

  input  logic [ADDR_W-1:0] s_awaddr,
  input  logic              s_awvalid,
  output logic              s_awready,
  input  logic [31:0]       s_wdata,
  input  logic [3:0]        s_wstrb,
  input  logic              s_wvalid,
  output logic              s_wready,
  output logic [1:0]        s_bresp,
  output logic              s_bvalid,
  input  logic              s_bready,
  input  logic [ADDR_W-1:0] s_araddr,
  input  logic              s_arvalid,
  output logic              s_arready,
  output logic [31:0]       s_rdata,
  output logic [1:0]        s_rresp,
  output logic              s_rvalid,
  input  logic              s_rready,

  output logic              reg_write,
  output logic [ADDR_W-1:0] reg_waddr,
  output logic [31:0]       reg_wdata,
  output logic [3:0]        reg_wstrb,
  output logic              reg_read,
  output logic [ADDR_W-1:0] reg_raddr,
  input  logic [31:0]       reg_rdata
);

  logic have_addr;
  logic have_data;

  assign s_awready = !have_addr && !s_bvalid;
  assign s_wready  = !have_data && !s_bvalid;
  assign s_arready = !s_rvalid;
  assign s_bresp   = 2'b00;
  assign s_rresp   = 2'b00;
  assign reg_write = have_addr && have_data && !s_bvalid;
  assign reg_read  = s_arvalid && s_arready;
  assign reg_raddr = s_araddr;

  always_ff @(posedge clk or negedge arst_n) begin
    if (!arst_n) begin
      have_addr <= 1'b0;
      have_data <= 1'b0;
      reg_waddr <= '0;
      reg_wdata <= '0;
      reg_wstrb <= '0;
      s_bvalid  <= 1'b0;
      s_rvalid  <= 1'b0;
      s_rdata   <= '0;
    end else begin
      if (s_awvalid && s_awready) begin
        have_addr <= 1'b1;
        reg_waddr <= s_awaddr;
      end
      if (s_wvalid && s_wready) begin
        have_data <= 1'b1;
        reg_wdata <= s_wdata;
        reg_wstrb <= s_wstrb;
      end
      if (reg_write) begin
        have_addr <= 1'b0;
        have_data <= 1'b0;
        s_bvalid  <= 1'b1;
      end else if (s_bvalid && s_bready) begin
        s_bvalid <= 1'b0;
      end
      if (reg_read) begin
        s_rvalid <= 1'b1;
        s_rdata  <= reg_rdata;
      end else if (s_rvalid && s_rready) begin
        s_rvalid <= 1'b0;
      end
    end
  end

endmodule
