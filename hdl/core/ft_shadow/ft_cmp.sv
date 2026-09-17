module ft_cmp #(
  parameter WIDTH = 64,
  parameter int TE_THRESHOLD = 3,
  parameter bit FAULT_INJECT = 1'b0
) (
  // Inputs match Wally's comparator; flags are {equal, less-than}.
  input  logic clk, reset, flush, valid,
  input  logic [WIDTH-1:0] a, b,
  input  logic sgnd,
  // Test-only replica-output fault selection; tied off by the production IEU.
  input  logic fi_enable,
  input  logic [1:0] fi_target,
  input  logic [1:0] fi_kind,
  input  logic [$clog2(2)-1:0] fi_bit,
  output logic [1:0] flags,
  output logic stall_req, unresolved, pe_primary, pe_shadow
);
  // Controller state determines whether these combinational flags are
  // accepted, held, or masked for a precise trap.
  logic [1:0] primary_flags_raw, shadow_flags_raw;
  logic [1:0] primary_flags, shadow_flags;
  logic mismatch, recompute_mode, isolated, use_shadow;
  logic unused_primary_ok, unused_shadow_ok;

  // No generic safe recompute relation exists for all compare modes; use
  // retry-only behavior and trap on persistent disagreement.
  comparator #(WIDTH) primary(.a, .b, .sgnd, .flags(primary_flags_raw));
  comparator #(WIDTH) shadow(.a, .b, .sgnd, .flags(shadow_flags_raw));
  ft_fault_inject #(.WIDTH(2), .FAULT_INJECT(FAULT_INJECT)) primary_fi(
    .data_i(primary_flags_raw), .fi_enable(fi_enable & fi_target[0]),
    .fi_kind, .fi_bit, .data_o(primary_flags));
  ft_fault_inject #(.WIDTH(2), .FAULT_INJECT(FAULT_INJECT)) shadow_fi(
    .data_i(shadow_flags_raw), .fi_enable(fi_enable & fi_target[1]),
    .fi_kind, .fi_bit, .data_o(shadow_flags));
  assign mismatch = valid & ~isolated & (primary_flags != shadow_flags);
  assign unused_primary_ok = 1'b0;
  assign unused_shadow_ok = 1'b0;
  ft_shadow_ctrl #(.TE_THRESHOLD(TE_THRESHOLD)) ctrl(
    .clk, .reset, .flush, .valid, .mismatch, .recompute_supported(1'b0),
    .recompute_primary_ok(unused_primary_ok), .recompute_shadow_ok(unused_shadow_ok),
    .recompute_mode, .stall_req, .unresolved, .isolated, .use_shadow,
    .pe_primary, .pe_shadow);

  // Do not allow held/unresolved flags to redirect a branch.
  always_comb begin
    flags = use_shadow ? shadow_flags : primary_flags;
    if (stall_req | unresolved) flags = '0;
  end
endmodule
