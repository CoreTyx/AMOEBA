module ft_mul import cvw::*; #(
  parameter cvw_t P,
  parameter int TE_THRESHOLD = 3
) (
  // Preserve Wally's E-input/M-output boundary while adding replay control.
  input  logic clk, reset,
  input  logic StallM, FlushM,
  input  logic [P.XLEN-1:0] ForwardedSrcAE, ForwardedSrcBE,
  input  logic [2:0] Funct3E,
  input  logic MulActiveE,
  // Runtime fault-injection input from core -> MDU. Enable gates corruption
  // of the full 2*XLEN product at fi_bit. Target[0]/[1] selects primary/shadow;
  // Kind 00/01/10/11 selects XOR/stuck-at-0/stuck-at-1/no-op.
  input  logic fi_enable,
  input  logic [1:0] fi_target,
  input  logic [1:0] fi_kind,
  input  logic [$clog2(P.XLEN*2)-1:0] fi_bit,
  output logic [P.XLEN*2-1:0] ProdM,
  output logic stall_req, unresolved, pe_primary, pe_shadow
);
  // saved_* is the architectural transaction; mul_* selects current E inputs
  // or that saved transaction during an M-stage replay.
  logic [P.XLEN-1:0] saved_a, saved_b, mul_a, mul_b;
  logic [2:0] saved_funct3, mul_funct3;
  logic mul_active_m, mismatch, replay_load;
  logic recompute_mode, isolated, use_shadow;
  logic [P.XLEN*2-1:0] primary_prod_raw, shadow_prod_raw;
  logic [P.XLEN*2-1:0] primary_prod, shadow_prod;
  logic internal_stall_m;

  // Save the transaction that produced the current partial product. A retry
  // must replay these exact operands while the architectural stages are held.
  always_ff @(posedge clk) begin
    if (reset | (FlushM & ~StallM)) begin
      saved_a <= '0;
      saved_b <= '0;
      saved_funct3 <= '0;
    end else if (MulActiveE & ~StallM) begin
      saved_a <= ForwardedSrcAE;
      saved_b <= ForwardedSrcBE;
      saved_funct3 <= Funct3E;
    end
  end
  flopenrc #(1) MulActiveMReg(clk, reset, FlushM, ~StallM, MulActiveE, mul_active_m);

  // The original multiplier is registered; compare completed products in M.
  assign mismatch = mul_active_m & ~isolated & (primary_prod != shadow_prod);
  // On every mismatch edge, load the saved transaction into the internal PP
  // registers even though the architectural pipeline is globally held.
  assign replay_load = mismatch;
  assign internal_stall_m = StallM & ~replay_load;
  assign mul_a = replay_load ? saved_a : ForwardedSrcAE;
  assign mul_b = replay_load ? saved_b : ForwardedSrcBE;
  assign mul_funct3 = replay_load ? saved_funct3 : Funct3E;

  // Permit the internal PP registers to load the saved retry transaction even
  // when the architectural hazard unit is asserting StallM.
  mul #(P.XLEN) primary(.clk, .reset, .StallM(internal_stall_m), .FlushM(FlushM & ~StallM),
    .ForwardedSrcAE(mul_a), .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .ProdM(primary_prod_raw));
  mul #(P.XLEN) shadow(.clk, .reset, .StallM(internal_stall_m), .FlushM(FlushM & ~StallM),
    .ForwardedSrcAE(mul_a), .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .ProdM(shadow_prod_raw));
  // Fault-injection endpoints: corrupt completed replica products before
  // the mismatch checker and the selected architectural product output.
  ft_fault_inject #(.WIDTH(P.XLEN*2)) primary_fi(
    .data_i(primary_prod_raw), .fi_enable(fi_enable & fi_target[0]),
    .fi_kind, .fi_bit, .data_o(primary_prod));
  ft_fault_inject #(.WIDTH(P.XLEN*2)) shadow_fi(
    .data_i(shadow_prod_raw), .fi_enable(fi_enable & fi_target[1]),
    .fi_kind, .fi_bit, .data_o(shadow_prod));

  // MUL uses DMR/retry only in this implementation.  A persistent mismatch
  // is unresolved; do not apply an invalid signedness-agnostic recompute rule.
  // A trap may request FlushM while unrelated backpressure holds M. Accept
  // that flush only when the architectural M-stage register accepts it too.
  ft_shadow_ctrl #(.TE_THRESHOLD(TE_THRESHOLD)) ctrl(
    .clk, .reset, .flush(FlushM & ~StallM), .valid(mul_active_m), .advance(~StallM), .mismatch,
    .recompute_supported(1'b0), .recompute_primary_ok(1'b0), .recompute_shadow_ok(1'b0),
    .recompute_mode, .capture_normal(), .stall_req, .unresolved, .isolated, .use_shadow,
    .pe_primary, .pe_shadow);

  // Mask stale/untrusted products while held or unresolved.
  assign ProdM = (stall_req | unresolved) ? '0 : (use_shadow ? shadow_prod : primary_prod);
endmodule
