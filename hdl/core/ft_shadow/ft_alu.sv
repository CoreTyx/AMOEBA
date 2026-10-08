// E-stage ALU/address and architectural comparison protection. The two lanes
// have independent controllers and replica selections; only containment is
// shared. All widened results and diagnostic snapshots terminate here.
module ft_alu import cvw::*; #(
  parameter cvw_t P,
  parameter int TE_THRESHOLD = 3
) (
  input  logic clk, reset, flush, valid, advance,
  input  logic [P.XLEN-1:0] A, B,
  // Branches need PC+immediate and register comparison simultaneously.
  input  logic [P.XLEN-1:0] cmp_a, cmp_b,
  input  logic cmp_sgnd,
  input  logic W64, UW64, SubArith,
  input  logic [2:0] ALUSelect,
  input  logic [3:0] BSelect, ZBBSelect,
  input  logic [2:0] Funct3, BALUControl,
  input  logic [6:0] Funct7,
  input  logic [4:0] Rs2E,
  input  logic BMUActive,
  input  logic [1:0] CZero,
  // Shared runtime enable; each replica/channel selects faults locally.
  input  logic fi_enable,
  output logic [P.XLEN-1:0] ALUResult, Sum,
  output logic [1:0] flags, // unchanged comparator schema: {eq, lt}
  output logic stall_req, unresolved, pe_primary, pe_shadow,
  output logic cmp_pe_primary, cmp_pe_shadow
);
  logic [P.XLEN-1:0] result_raw[2], result_pre_fi[2], result_live[2];
  logic [P.XLEN:0] arith_raw[2], arith_live[2], cmp_raw[2], cmp_live[2];
  logic [P.XLEN+1:0] shift_raw[2], shift_live[2];
  logic [P.XLEN-1:0] normal_result[2];
  logic [P.XLEN:0] normal_arith[2], normal_cmp[2];
  logic [P.XLEN+1:0] normal_shift[2];
  logic [P.XLEN:0] cmp_extended_a, cmp_extended_b;
  logic alu_mismatch, cmp_mismatch, arithmetic_operation, slt_operation, shift_operation;
  logic alu_recompute, cmp_recompute, arith_recompute, shift_recompute;
  logic alu_capture_normal, cmp_capture_normal, alu_isolated, cmp_isolated;
  logic alu_use_shadow, cmp_use_shadow, alu_stall, cmp_stall, alu_unresolved, cmp_unresolved;
  logic alu_supported, alu_ok[2], cmp_ok[2];

  // Do not use BMUActive to exclude shifts: the existing BMU decoder also
  // recognizes ordinary shifts. Rotates keep their original n-bit ring.
  assign slt_operation = ~W64 & ~BMUActive &
                         ((ALUSelect == 3'b010) | (ALUSelect == 3'b011));
  assign arithmetic_operation = (~W64 & ~BMUActive & (ALUSelect == 3'b000)) | slt_operation;
  assign shift_operation = ~BALUControl[2] &
      ((ALUSelect == 3'b001) | ((ALUSelect == 3'b101) & ~P.ZBS_SUPPORTED)) &
      ((BSelect == 4'b0000) | ((BSelect == 4'b0001) & UW64));
  // A shift relation gives no evidence about a faulty independent address
  // channel. Such disagreement must trap, even if the shift itself is healthy.
  assign alu_supported = arithmetic_operation | (shift_operation & (arith_live[0] == arith_live[1]));
  assign arith_recompute = alu_recompute & arithmetic_operation;
  assign shift_recompute = alu_recompute & shift_operation;
  assign cmp_extended_a = {cmp_sgnd & cmp_a[P.XLEN-1], cmp_a};
  assign cmp_extended_b = {cmp_sgnd & cmp_b[P.XLEN-1], cmp_b};

  function automatic logic [P.XLEN-1:0] shift_result(
    input  logic [P.XLEN+1:0] wide, input logic diagnostic);
    logic [P.XLEN-1:0] aligned;
    aligned = diagnostic ? wide[P.XLEN+1:2] : wide[P.XLEN-1:0];
    if ((P.XLEN == 64) && W64)
      shift_result = {{(P.XLEN-32){aligned[31]}}, aligned[31:0]};
    else shift_result = aligned;
  endfunction

  for (genvar i = 0; i < 2; i++) begin : replica
    alu #(P) compute(.A, .B, .W64, .UW64, .SubArith, .ALUSelect,
      .BSelect, .ZBBSelect, .Funct3, .Funct7, .Rs2E, .BALUControl, .BMUActive, .CZero,
      .RecomputeArith(arith_recompute), .RecomputeShift(shift_recompute),
      .ArithWide(arith_raw[i]), .ShiftWide(shift_raw[i]),
      .ALUResult(result_raw[i]), .Sum());
    addsub #(.WIDTH(P.XLEN+1)) compare(
      .a(cmp_extended_a), .b(cmp_extended_b), .sub(1'b1),
      .recompute(cmp_recompute), .result(cmp_raw[i]));

    // Each physical result channel has its own LFSR and event phase.
    ft_fault_inject #(.WIDTH(P.XLEN), .SEED(16'hA001 + 16'(i*64))) result_fi(
      .clk, .reset, .fi_enable, .data_i(result_pre_fi[i]), .data_o(result_live[i]));
    ft_fault_inject #(.WIDTH(P.XLEN+1), .SEED(16'hA011 + 16'(i*64))) arith_fi(
      .clk, .reset, .fi_enable, .data_i(arith_raw[i]), .data_o(arith_live[i]));
    ft_fault_inject #(.WIDTH(P.XLEN+2), .SEED(16'hA021 + 16'(i*64))) shift_fi(
      .clk, .reset, .fi_enable, .data_i(shift_raw[i]), .data_o(shift_live[i]));
    ft_fault_inject #(.WIDTH(P.XLEN+1), .SEED(16'hA031 + 16'(i*64))) cmp_fi(
      .clk, .reset, .fi_enable, .data_i(cmp_raw[i]), .data_o(cmp_live[i]));

    // A shift-channel fault must reach the architectural output, including
    // word sign extension. The injection bit stays physical during diagnosis.
    assign result_pre_fi[i] = shift_operation ? shift_result(shift_live[i], shift_recompute) : result_raw[i];
    assign cmp_ok[i] = (cmp_live[i] == ~normal_cmp[i]);
    always_comb begin
      alu_ok[i] = 1'b0;
      if (arithmetic_operation) begin
        alu_ok[i] = (arith_live[i] == ~normal_arith[i]);
        if (slt_operation) begin
          alu_ok[i] &= (normal_result[i] == {{(P.XLEN-1){1'b0}}, normal_arith[i][P.XLEN]}) &
                       (result_live[i] == {{(P.XLEN-1){1'b0}}, arith_live[i][P.XLEN]});
        end else alu_ok[i] &= (result_live[i] == ~normal_result[i]);
      end else if (shift_operation) begin
        alu_ok[i] = (shift_result(normal_shift[i], 1'b0) == shift_result(shift_live[i], 1'b1)) &
                    (normal_result[i] == shift_result(normal_shift[i], 1'b0)) &
                    (result_live[i] == shift_result(shift_live[i], 1'b1)) &
                    (arith_live[i] == normal_arith[i]) & (arith_live[0] == arith_live[1]);
      end
    end
    always_ff @(posedge clk) begin
      if (reset | flush) begin
        normal_result[i] <= '0;
        normal_arith[i] <= '0;
        normal_shift[i] <= '0;
        normal_cmp[i] <= '0;
      end else begin
        if (alu_capture_normal) begin
          normal_result[i] <= result_live[i];
          normal_arith[i] <= arith_live[i];
          normal_shift[i] <= shift_live[i];
        end
        if (cmp_capture_normal) normal_cmp[i] <= cmp_live[i];
      end
    end
  end

  assign alu_mismatch = valid & ~alu_recompute & ~alu_isolated &
                       ((result_live[0] != result_live[1]) | (arith_live[0] != arith_live[1]));
  assign cmp_mismatch = valid & ~cmp_recompute & ~cmp_isolated & (cmp_live[0] != cmp_live[1]);
  ft_shadow_ctrl #(.TE_THRESHOLD(TE_THRESHOLD)) alu_ctrl(
    .clk, .reset, .flush, .valid, .advance, .mismatch(alu_mismatch), .recompute_supported(alu_supported),
    .recompute_primary_ok(alu_ok[0]), .recompute_shadow_ok(alu_ok[1]),
    .recompute_mode(alu_recompute), .capture_normal(alu_capture_normal),
    .stall_req(alu_stall), .unresolved(alu_unresolved), .isolated(alu_isolated),
    .use_shadow(alu_use_shadow), .pe_primary, .pe_shadow);
  ft_shadow_ctrl #(.TE_THRESHOLD(TE_THRESHOLD)) cmp_ctrl(
    .clk, .reset, .flush, .valid, .advance, .mismatch(cmp_mismatch), .recompute_supported(1'b1),
    .recompute_primary_ok(cmp_ok[0]), .recompute_shadow_ok(cmp_ok[1]),
    .recompute_mode(cmp_recompute), .capture_normal(cmp_capture_normal),
    .stall_req(cmp_stall), .unresolved(cmp_unresolved), .isolated(cmp_isolated),
    .use_shadow(cmp_use_shadow), .pe_primary(cmp_pe_primary), .pe_shadow(cmp_pe_shadow));

  assign stall_req = alu_stall | cmp_stall;
  assign unresolved = alu_unresolved | cmp_unresolved;
  always_comb begin
    ALUResult = result_live[alu_use_shadow];
    Sum = arith_live[alu_use_shadow][P.XLEN-1:0];
    flags = {cmp_live[cmp_use_shadow] == '0, cmp_live[cmp_use_shadow][P.XLEN]};
    if (stall_req | unresolved) begin
      ALUResult = '0;
      Sum = '0;
      flags = '0;
    end
  end
endmodule
