module ft_alu import cvw::*; #(parameter cvw_t P, parameter int TE_THRESHOLD = 3) (
  // Inputs are the existing E-stage ALU controls; outputs retain Wally's
  // result/address interface plus FT control and diagnosis.
  input  logic clk, reset, flush, valid,
  input  logic [P.XLEN-1:0] A, B,
  input  logic W64, UW64, SubArith,
  input  logic [2:0] ALUSelect,
  input  logic [3:0] BSelect, ZBBSelect,
  input  logic [2:0] Funct3, BALUControl,
  input  logic [6:0] Funct7,
  input  logic [4:0] Rs2E,
  input  logic BMUActive,
  input  logic [1:0] CZero,
  output logic [P.XLEN-1:0] ALUResult, Sum,
  output logic stall_req, unresolved, pe_primary, pe_shadow
);

  // Live copy outputs; normal_* preserves the first mismatch for diagnosis.
  logic [P.XLEN-1:0] primary_result, primary_sum, shadow_result, shadow_sum;
  logic [P.XLEN-1:0] normal_primary_result, normal_primary_sum;
  logic [P.XLEN-1:0] normal_shadow_result, normal_shadow_sum;
  logic [P.XLEN-1:0] recompute_a, recompute_b;
  logic mismatch, recompute_mode, isolated, use_shadow;
  logic recompute_supported, recompute_primary_ok, recompute_shadow_ok;

  // Only ordinary XLEN addition has a trusted complement relation. W-form,
  // subtraction, BMU, and other operations use retry-only escalation.
  assign recompute_supported = valid & ~W64 & ~SubArith & ~BMUActive &
                               (ALUSelect == 3'b000);
  assign recompute_a = recompute_mode ? (~A + {{(P.XLEN-1){1'b0}}, 1'b1}) : A;
  assign recompute_b = recompute_mode ? ~B : B;

  // Keep Wally's ALU implementation intact and duplicate its complete output.
  alu #(P) primary(.A(recompute_a), .B(recompute_b), .W64, .UW64, .SubArith,
    .ALUSelect, .BSelect, .ZBBSelect, .Funct3, .Funct7, .Rs2E, .BALUControl,
    .BMUActive, .CZero, .ALUResult(primary_result), .Sum(primary_sum));
  alu #(P) shadow(.A(recompute_a), .B(recompute_b), .W64, .UW64, .SubArith,
    .ALUSelect, .BSelect, .ZBBSelect, .Funct3, .Funct7, .Rs2E, .BALUControl,
    .BMUActive, .CZero, .ALUResult(shadow_result), .Sum(shadow_sum));

  // Recompute intentionally changes the operands, so normal mismatch checking
  // is disabled until the controller finishes diagnosis.
  assign mismatch = valid & ~recompute_mode & ~isolated &
                    ((primary_result != shadow_result) | (primary_sum != shadow_sum));
  assign recompute_primary_ok = (primary_result == ~normal_primary_result) &
                                (primary_sum == ~normal_primary_sum);
  assign recompute_shadow_ok  = (shadow_result == ~normal_shadow_result) &
                                (shadow_sum == ~normal_shadow_sum);

  ft_shadow_ctrl #(.TE_THRESHOLD(TE_THRESHOLD)) ctrl(
    .clk, .reset, .flush, .valid, .mismatch, .recompute_supported,
    .recompute_primary_ok, .recompute_shadow_ok, .recompute_mode, .stall_req,
    .unresolved, .isolated, .use_shadow, .pe_primary, .pe_shadow);

  // Save the first normal disagreement for the complement-based diagnosis.
  always_ff @(posedge clk) begin
    if (reset | flush) begin
      normal_primary_result <= '0;
      normal_primary_sum    <= '0;
      normal_shadow_result  <= '0;
      normal_shadow_sum     <= '0;
    end else if (valid & mismatch & ~recompute_mode & ~isolated) begin
      normal_primary_result <= primary_result;
      normal_primary_sum    <= primary_sum;
      normal_shadow_result  <= shadow_result;
      normal_shadow_sum     <= shadow_sum;
    end
  end

  // Mask outputs while the transaction is held or cannot be trusted.
  always_comb begin
    ALUResult = use_shadow ? shadow_result : primary_result;
    Sum       = use_shadow ? shadow_sum : primary_sum;
    if (stall_req | unresolved) begin
      ALUResult = '0;
      Sum       = '0;
    end
  end
endmodule
