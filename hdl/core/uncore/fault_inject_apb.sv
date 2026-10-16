// Software selection of fault-injection units. Byte register at FI_CONTROL_ADDR.
// [0] ALU result/arithmetic/shift, [1] comparison, [2] MUL, [3] DIV,
// [4] register-file ECC, [5] pipeline-register ECC; [7:6] read as zero.
// The core ANDs this mask with the external fault_inject master enable.
module fault_inject_apb import cvw::*; (
  input  logic        PCLK, PRESETn,
  input  logic        PSEL, PENABLE, PWRITE,
  input  logic [63:0] PWDATA,
  input  logic [7:0]  PSTRB,
  output logic [63:0] PRDATA,
  output logic        PREADY,
  output logic [5:0]  FaultInjectMask
);
  // Address 0x1007_000b uses byte lane 3 of the 64-bit peripheral bus.
  // Commit only in the APB access phase with that byte strobe asserted.
  always_ff @(posedge PCLK) begin
    if (!PRESETn) FaultInjectMask <= 6'h3f;
    else if (PSEL & PENABLE & PWRITE & PSTRB[3])
      FaultInjectMask <= PWDATA[29:24];
  end

  assign PRDATA = {32'b0, 2'b0, FaultInjectMask, 24'b0};
  assign PREADY = 1'b1;

  logic unused;
  assign unused = ^{PWDATA[63:30], PWDATA[23:0], PSTRB[7:4], PSTRB[2:0]};
endmodule
