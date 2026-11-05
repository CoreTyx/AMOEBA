// Software selection of fault-injection units. Byte register at FI_CONTROL_ADDR.
// [0] ALU result/arithmetic/shift, [1] comparison, [2] MUL, [3] DIV,
// [4] register-file ECC, [5] pipeline-register ECC, [6] cache correctable,
// [7] cache uncorrectable.  Every unit resets off: injection needs software
// to arm units here AND the external fault_inject master enable, which the
// core ANDs with this mask.
module fault_inject_apb import cvw::*; (
  input  logic        PCLK, PRESETn,
  input  logic        PSEL, PENABLE, PWRITE,
  input  logic [63:0] PWDATA,
  input  logic [7:0]  PSTRB,
  output logic [63:0] PRDATA,
  output logic        PREADY,
  output logic [FI_UNITS-1:0] FaultInjectMask
);
  // Every unit resets off.  Simulator builds made for injection (ECE411_SIM_INJECT, which
  // also ties the master pin high) model boot software that armed the six core units.
`ifdef ECE411_SIM_INJECT
  localparam logic [FI_UNITS-1:0] RESET_MASK = 8'h3f;
`else
  localparam logic [FI_UNITS-1:0] RESET_MASK = '0;
`endif

  // Address 0x1007_000b uses byte lane 3 of the 64-bit peripheral bus.
  // Commit only in the APB access phase with that byte strobe asserted.
  always_ff @(posedge PCLK) begin
    if (!PRESETn) FaultInjectMask <= RESET_MASK;
    else if (PSEL & PENABLE & PWRITE & PSTRB[3])
      FaultInjectMask <= PWDATA[31:24];
  end

  assign PRDATA = {32'b0, FaultInjectMask, 24'b0};
  assign PREADY = 1'b1;

  logic unused;
  assign unused = ^{PWDATA[63:32], PWDATA[23:0], PSTRB[7:4], PSTRB[2:0]};
endmodule
