// Direct regression for shadow-FU result-path injection.  This testbench is
// intentionally separate from the SoC/RVFI infrastructure and enables the
// injection elaboration switch only on its local DUT instances.
`include "config.vh"

module ft_recompute_fault_tb;
  import cvw::*;
  `include "parameter-defs.vh"

  localparam logic [1:0] FI_PRIMARY = 2'b01;
  localparam logic [1:0] FI_SHADOW  = 2'b10;
  localparam logic [1:0] FI_XOR     = 2'b00;
  localparam logic [1:0] FI_STUCK1  = 2'b10;

  logic clk = 1'b0;
  logic reset;

  // ALU transaction and its wrapper-local injection controls.
  logic alu_valid, alu_w64, alu_uw64, alu_sub, alu_bmu, alu_channel;
  logic [P.XLEN-1:0] alu_a, alu_b, alu_result, alu_sum;
  logic [2:0] alu_select, alu_funct3, alu_balu;
  logic [3:0] alu_bselect, alu_zbbselect;
  logic [6:0] alu_funct7;
  logic [4:0] alu_rs2;
  logic [1:0] alu_czero, alu_target, alu_kind;
  logic [$clog2(P.XLEN)-1:0] alu_bit;
  logic alu_fi_enable, alu_stall, alu_unresolved, alu_pe_primary, alu_pe_shadow;

  // Comparator transaction and its wrapper-local injection controls.
  logic cmp_valid, cmp_sgnd, cmp_fi_enable, cmp_stall, cmp_unresolved;
  logic [P.XLEN-1:0] cmp_a, cmp_b;
  logic [1:0] cmp_flags, cmp_target, cmp_kind;
  logic cmp_bit, cmp_pe_primary, cmp_pe_shadow;

  // The multiplier's StallM loop matches its integration: the wrapper asks
  // the architectural pipeline to hold, but still reloads its saved inputs.
  logic mul_active, mul_flush, mul_fi_enable, mul_stall, mul_unresolved;
  logic [P.XLEN-1:0] mul_a, mul_b;
  logic [2:0] mul_funct3;
  logic [P.XLEN*2-1:0] mul_prod;
  logic [1:0] mul_target, mul_kind;
  logic [$clog2(P.XLEN*2)-1:0] mul_bit;
  logic mul_pe_primary, mul_pe_shadow;

  // The divider remains in E while it iterates.  Normal division does not
  // stall M in Wally; ft_div internally bypasses the architectural hold only
  // while it restarts a failed attempt.
  logic div_active, div_signed, div_w64, div_fi_enable, div_stall, div_unresolved, div_busy;
  logic [P.XLEN-1:0] div_a, div_b, div_quot, div_rem;
  logic [1:0] div_target, div_kind;
  logic [$clog2(P.XLEN)-1:0] div_bit;
  logic div_channel, div_pe_primary, div_pe_shadow;

  always #5 clk = ~clk;

  ft_alu #(.P(P), .TE_THRESHOLD(2), .FAULT_INJECT(1'b1)) alu_dut (
    .clk, .reset, .flush(1'b0), .valid(alu_valid), .A(alu_a), .B(alu_b),
    .W64(alu_w64), .UW64(alu_uw64), .SubArith(alu_sub), .ALUSelect(alu_select),
    .BSelect(alu_bselect), .ZBBSelect(alu_zbbselect), .Funct3(alu_funct3),
    .Funct7(alu_funct7), .Rs2E(alu_rs2), .BALUControl(alu_balu),
    .BMUActive(alu_bmu), .CZero(alu_czero), .fi_enable(alu_fi_enable),
    .fi_target(alu_target), .fi_kind(alu_kind), .fi_bit(alu_bit),
    .fi_channel(alu_channel), .ALUResult(alu_result), .Sum(alu_sum),
    .stall_req(alu_stall), .unresolved(alu_unresolved),
    .pe_primary(alu_pe_primary), .pe_shadow(alu_pe_shadow));

  ft_cmp #(.WIDTH(P.XLEN), .TE_THRESHOLD(2), .FAULT_INJECT(1'b1)) cmp_dut (
    .clk, .reset, .flush(1'b0), .valid(cmp_valid), .a(cmp_a), .b(cmp_b),
    .sgnd(cmp_sgnd), .fi_enable(cmp_fi_enable), .fi_target(cmp_target),
    .fi_kind(cmp_kind), .fi_bit(cmp_bit), .flags(cmp_flags), .stall_req(cmp_stall),
    .unresolved(cmp_unresolved), .pe_primary(cmp_pe_primary), .pe_shadow(cmp_pe_shadow));

  ft_mul #(.P(P), .TE_THRESHOLD(2), .FAULT_INJECT(1'b1)) mul_dut (
    .clk, .reset, .StallM(mul_stall), .FlushM(mul_flush), .ForwardedSrcAE(mul_a),
    .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .MulActiveE(mul_active),
    .fi_enable(mul_fi_enable), .fi_target(mul_target), .fi_kind(mul_kind),
    .fi_bit(mul_bit), .ProdM(mul_prod), .stall_req(mul_stall),
    .unresolved(mul_unresolved), .pe_primary(mul_pe_primary), .pe_shadow(mul_pe_shadow));

  ft_div #(.P(P), .TE_THRESHOLD(2), .FAULT_INJECT(1'b1)) div_dut (
    .clk, .reset, .StallM(1'b0), .FlushE(1'b0), .IntDivE(div_active),
    .DivSignedE(div_signed), .W64E(div_w64), .ForwardedSrcAE(div_a), .ForwardedSrcBE(div_b),
    .fi_enable(div_fi_enable), .fi_target(div_target), .fi_kind(div_kind), .fi_bit(div_bit),
    .fi_channel(div_channel), .DivBusyE(div_busy), .QuotM(div_quot), .RemM(div_rem),
    .stall_req(div_stall), .unresolved(div_unresolved),
    .pe_primary(div_pe_primary), .pe_shadow(div_pe_shadow));

  task automatic check(input logic condition, input string test_id);
    if (!condition) $fatal(1, "%s failed at time %0t", test_id, $time);
  endtask

  // Decode compact injection controls in the transcript; the raw and injected
  // replica signals printed below make each fault and subsequent recovery clear.
  function automatic string target_name(input logic [1:0] target);
    case (target)
      FI_PRIMARY: target_name = "primary";
      FI_SHADOW:  target_name = "shadow";
      2'b11:      target_name = "both";
      default:    target_name = "none";
    endcase
  endfunction

  function automatic string kind_name(input logic [1:0] kind);
    case (kind)
      FI_XOR:     kind_name = "xor";
      2'b01:      kind_name = "stuck-0";
      FI_STUCK1:  kind_name = "stuck-1";
      default:    kind_name = "reserved";
    endcase
  endfunction

  task automatic drive_defaults;
    begin
      alu_valid = 1'b0; alu_a = '0; alu_b = '0; alu_w64 = 1'b0; alu_uw64 = 1'b0;
      alu_sub = 1'b0; alu_select = 3'b000; alu_bselect = '0; alu_zbbselect = '0;
      alu_funct3 = '0; alu_funct7 = '0; alu_rs2 = '0; alu_balu = '0; alu_bmu = 1'b0;
      alu_czero = '0; alu_fi_enable = 1'b0; alu_target = '0; alu_kind = FI_XOR;
      alu_bit = '0; alu_channel = 1'b0;
      cmp_valid = 1'b0; cmp_a = '0; cmp_b = '0; cmp_sgnd = 1'b0;
      cmp_fi_enable = 1'b0; cmp_target = '0; cmp_kind = FI_XOR; cmp_bit = 1'b0;
      mul_active = 1'b0; mul_flush = 1'b0; mul_a = '0; mul_b = '0; mul_funct3 = 3'b000;
      mul_fi_enable = 1'b0; mul_target = '0; mul_kind = FI_XOR; mul_bit = '0;
      div_active = 1'b0; div_signed = 1'b0; div_w64 = 1'b0; div_a = '0; div_b = '0;
      div_fi_enable = 1'b0; div_target = '0; div_kind = FI_XOR; div_bit = '0; div_channel = 1'b0;
    end
  endtask

  // Reset separates cases because ALU isolation is intentionally sticky.
  task automatic reset_case;
    begin
      drive_defaults();
      reset = 1'b1;
      repeat (2) @(posedge clk);
      #1 reset = 1'b0;
      @(negedge clk);
    end
  endtask

  task automatic set_alu_add;
    begin
      alu_valid = 1'b1;
      alu_a = 64'h12;
      alu_b = 64'h24;
      alu_select = 3'b000;
    end
  endtask

  task automatic alu_transient(input logic [1:0] target, input string test_id);
    begin
      reset_case();
      set_alu_add();
      alu_fi_enable = 1'b1; alu_target = target; alu_kind = FI_XOR; alu_bit = 0;
      $display("[%0t] %s INPUT A=%0h B=%0h; INJECT target=%s channel=result kind=%s bit=%0d",
               $time, test_id, alu_a, alu_b, target_name(target), kind_name(alu_kind), alu_bit);
      @(posedge clk); #1;
      check(alu_stall, {test_id, ": mismatch stalls"});
      $display("  injected: primary raw/result/sum=%0h/%0h/%0h shadow raw/result/sum=%0h/%0h/%0h; arch result/sum=%0h/%0h stall=%b",
               alu_dut.primary_result_raw, alu_dut.primary_result, alu_dut.primary_sum,
               alu_dut.shadow_result_raw, alu_dut.shadow_result, alu_dut.shadow_sum,
               alu_result, alu_sum, alu_stall);
      @(negedge clk);
      alu_fi_enable = 1'b0;
      @(posedge clk); #1;
      check(!alu_stall && !alu_unresolved, {test_id, ": retry completes"});
      check(alu_result == 64'h36 && alu_sum == 64'h36, {test_id, ": correct result"});
      $display("  recovered: fault disabled; result/sum=%0h/%0h stall=%b unresolved=%b",
               alu_result, alu_sum, alu_stall, alu_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic alu_persistent(input logic [1:0] target, input logic channel, input string test_id);
    begin
      reset_case();
      set_alu_add();
      alu_fi_enable = 1'b1; alu_target = target; alu_kind = FI_STUCK1;
      alu_bit = 0; alu_channel = channel;
      $display("[%0t] %s INPUT A=%0h B=%0h; INJECT target=%s channel=%s kind=%s bit=%0d",
               $time, test_id, alu_a, alu_b, target_name(target),
               channel ? "sum" : "result", kind_name(alu_kind), alu_bit);
      @(posedge clk); #1;
      check(alu_stall, {test_id, ": initial mismatch stalls"});
      $display("  injected: primary result/sum raw=%0h/%0h injected=%0h/%0h; shadow raw=%0h/%0h injected=%0h/%0h",
               alu_dut.primary_result_raw, alu_dut.primary_sum_raw,
               alu_dut.primary_result, alu_dut.primary_sum,
               alu_dut.shadow_result_raw, alu_dut.shadow_sum_raw,
               alu_dut.shadow_result, alu_dut.shadow_sum);
      @(posedge clk); #1;
      check(alu_stall, {test_id, ": recompute stalls"});
      @(posedge clk); #1;
      check(!alu_stall && !alu_unresolved, {test_id, ": isolation completes"});
      check(alu_result == 64'h36 && alu_sum == 64'h36, {test_id, ": healthy copy selected"});
      if (target == FI_PRIMARY)
        check(alu_pe_primary && !alu_pe_shadow, {test_id, ": primary isolated"});
      else
        check(!alu_pe_primary && alu_pe_shadow, {test_id, ": shadow isolated"});
      $display("  recovered: result/sum=%0h/%0h isolated primary/shadow=%b/%b",
               alu_result, alu_sum, alu_pe_primary, alu_pe_shadow);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic cmp_transient(input logic [1:0] target, input string test_id);
    begin
      reset_case();
      cmp_valid = 1'b1; cmp_a = 64'd5; cmp_b = 64'd7;
      cmp_fi_enable = 1'b1; cmp_target = target; cmp_kind = FI_XOR; cmp_bit = 1'b0;
      $display("[%0t] %s INPUT a=%0h b=%0h signed=%b; INJECT target=%s kind=%s bit=%0d",
               $time, test_id, cmp_a, cmp_b, cmp_sgnd, target_name(target), kind_name(cmp_kind), cmp_bit);
      @(posedge clk); #1;
      check(cmp_stall, {test_id, ": mismatch stalls"});
      $display("  injected: primary raw/flags=%b/%b shadow raw/flags=%b/%b; arch flags=%b stall=%b",
               cmp_dut.primary_flags_raw, cmp_dut.primary_flags,
               cmp_dut.shadow_flags_raw, cmp_dut.shadow_flags, cmp_flags, cmp_stall);
      @(negedge clk);
      cmp_fi_enable = 1'b0;
      @(posedge clk); #1;
      check(!cmp_stall && !cmp_unresolved && cmp_flags == 2'b01,
             {test_id, ": retry restores flags"});
      $display("  recovered: fault disabled; flags=%b stall=%b unresolved=%b",
               cmp_flags, cmp_stall, cmp_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic cmp_persistent(input logic [1:0] target, input string test_id);
    begin
      reset_case();
      cmp_valid = 1'b1; cmp_a = 64'd5; cmp_b = 64'd7;
      cmp_fi_enable = 1'b1; cmp_target = target; cmp_kind = FI_STUCK1; cmp_bit = 1'b1;
      $display("[%0t] %s INPUT a=%0h b=%0h signed=%b; INJECT target=%s kind=%s bit=%0d",
               $time, test_id, cmp_a, cmp_b, cmp_sgnd, target_name(target), kind_name(cmp_kind), cmp_bit);
      @(posedge clk); #1;
      check(cmp_stall, {test_id, ": initial mismatch stalls"});
      $display("  injected: primary raw/flags=%b/%b shadow raw/flags=%b/%b; arch flags=%b stall=%b",
               cmp_dut.primary_flags_raw, cmp_dut.primary_flags,
               cmp_dut.shadow_flags_raw, cmp_dut.shadow_flags, cmp_flags, cmp_stall);
      @(posedge clk); #1;
      check(cmp_unresolved && !cmp_stall && cmp_flags == '0,
             {test_id, ": persistent fault traps"});
      check(!cmp_pe_primary && !cmp_pe_shadow, {test_id, ": no unsupported isolation"});
      $display("  outcome: flags=%b unresolved=%b (CMP has no isolation relation)",
               cmp_flags, cmp_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic launch_mul(input logic [1:0] target, input logic [1:0] kind);
    begin
      mul_active = 1'b1; mul_a = 64'd13; mul_b = 64'd11; mul_funct3 = 3'b000;
      mul_fi_enable = 1'b1; mul_target = target; mul_kind = kind; mul_bit = 0;
    end
  endtask

  task automatic mul_transient(input logic [1:0] target, input string test_id);
    begin
      reset_case();
      launch_mul(target, FI_XOR);
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT target=%s kind=%s bit=%0d",
               $time, test_id, mul_a, mul_b, mul_funct3, target_name(target), kind_name(mul_kind), mul_bit);
      // First edge fills the M-stage partial-product registers.  Keep the
      // fault through the next edge so the controller actually enters RETRY.
      @(posedge clk); #1;
      @(posedge clk); #1;
      check(mul_stall, {test_id, ": mismatch stalls"});
      $display("  injected: primary raw/product=%0h/%0h shadow raw/product=%0h/%0h; arch product=%0h stall=%b",
               mul_dut.primary_prod_raw, mul_dut.primary_prod,
               mul_dut.shadow_prod_raw, mul_dut.shadow_prod, mul_prod, mul_stall);
      @(negedge clk);
      mul_fi_enable = 1'b0;
      @(posedge clk); #1;
      check(!mul_stall && !mul_unresolved && mul_prod == 128'd143,
             {test_id, ": replay restores product"});
      $display("  recovered: fault disabled; product=%0h stall=%b unresolved=%b",
               mul_prod, mul_stall, mul_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic mul_persistent(input logic [1:0] target, input string test_id);
    begin
      reset_case();
      launch_mul(target, FI_STUCK1);
      // 13 * 11 is 0x8f; bit 4 is known zero, so stuck-at-1 differs.
      mul_bit = 4;
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT target=%s kind=%s bit=%0d",
               $time, test_id, mul_a, mul_b, mul_funct3, target_name(target), kind_name(mul_kind), mul_bit);
      @(posedge clk); #1;
      @(posedge clk); #1;
      check(mul_stall, {test_id, ": initial mismatch stalls"});
      $display("  injected: primary raw/product=%0h/%0h shadow raw/product=%0h/%0h; arch product=%0h stall=%b",
               mul_dut.primary_prod_raw, mul_dut.primary_prod,
               mul_dut.shadow_prod_raw, mul_dut.shadow_prod, mul_prod, mul_stall);
      @(posedge clk); #1;
      check(mul_unresolved && !mul_stall && mul_prod == '0,
             {test_id, ": persistent fault traps"});
      check(!mul_pe_primary && !mul_pe_shadow, {test_id, ": no unsupported isolation"});
      $display("  outcome: product=%0h unresolved=%b (MUL has no isolation relation)",
               mul_prod, mul_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic wait_div_complete;
    begin
      // IntDivE is driven before this task, so div.sv asserts DivBusyE on its
      // launch cycle and deasserts it only after the final restoring step.
      while (!div_busy) @(posedge clk);
      while (div_busy) @(posedge clk);
      #1;
    end
  endtask

  task automatic launch_div(input logic [1:0] target, input logic channel, input logic [1:0] kind);
    begin
      div_active = 1'b1; div_signed = 1'b0; div_w64 = 1'b0;
      div_a = 64'd100; div_b = 64'd7;
      div_fi_enable = 1'b1; div_target = target; div_channel = channel;
      div_kind = kind; div_bit = 0;
    end
  endtask

  task automatic div_transient(input logic [1:0] target, input logic channel, input string test_id);
    begin
      reset_case();
      launch_div(target, channel, FI_XOR);
      $display("[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b; INJECT target=%s channel=%s kind=%s bit=%0d",
               $time, test_id, div_a, div_b, div_signed, target_name(target),
               channel ? "remainder" : "quotient", kind_name(div_kind), div_bit);
      wait_div_complete();
      check(div_stall, {test_id, ": completed mismatch stalls"});
      $display("  injected: primary raw q/r=%0h/%0h injected=%0h/%0h shadow raw q/r=%0h/%0h injected=%0h/%0h; arch q/r=%0h/%0h",
               div_dut.primary_quot_raw, div_dut.primary_rem_raw, div_dut.primary_quot, div_dut.primary_rem,
               div_dut.shadow_quot_raw, div_dut.shadow_rem_raw, div_dut.shadow_quot, div_dut.shadow_rem,
               div_quot, div_rem);
      @(negedge clk);
      div_fi_enable = 1'b0;
      wait_div_complete();
      check(!div_stall && !div_unresolved && div_quot == 64'd14 && div_rem == 64'd2,
             {test_id, ": retry restores quotient and remainder"});
      $display("  recovered: fault disabled; quotient/remainder=%0h/%0h stall=%b unresolved=%b",
               div_quot, div_rem, div_stall, div_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic div_persistent(input logic [1:0] target, input logic channel, input string test_id);
    begin
      reset_case();
      launch_div(target, channel, FI_STUCK1);
      // 100/7 gives q=0xe and r=0x2, so bit 0 differs when forced high.
      $display("[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b; INJECT target=%s channel=%s kind=%s bit=%0d",
               $time, test_id, div_a, div_b, div_signed, target_name(target),
               channel ? "remainder" : "quotient", kind_name(div_kind), div_bit);
      wait_div_complete();
      check(div_stall, {test_id, ": initial completed mismatch stalls"});
      $display("  injected: primary raw q/r=%0h/%0h injected=%0h/%0h shadow raw q/r=%0h/%0h injected=%0h/%0h; arch q/r=%0h/%0h",
               div_dut.primary_quot_raw, div_dut.primary_rem_raw, div_dut.primary_quot, div_dut.primary_rem,
               div_dut.shadow_quot_raw, div_dut.shadow_rem_raw, div_dut.shadow_quot, div_dut.shadow_rem,
               div_quot, div_rem);
      wait_div_complete();
      check(div_unresolved && !div_stall && div_quot == '0 && div_rem == '0,
             {test_id, ": persistent fault traps"});
      check(!div_pe_primary && !div_pe_shadow, {test_id, ": no unsupported isolation"});
      $display("  outcome: quotient/remainder=%0h/%0h unresolved=%b (DIV has no isolation relation)",
               div_quot, div_rem, div_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  initial begin
    reset = 1'b0;
    drive_defaults();
    reset_case();
    set_alu_add();
    #1;
    check(alu_result == 64'h36 && alu_sum == 64'h36 && !alu_stall,
           "A0: ALU no-fault result");
    $display("[%0t] A0 INPUT A=%0h B=%0h; OUTPUT result/sum=%0h/%0h (no injection)",
             $time, alu_a, alu_b, alu_result, alu_sum);
    $display("PASS A0");

    alu_transient(FI_PRIMARY, "A1: ALU primary transient");
    alu_transient(FI_SHADOW,  "A2: ALU shadow transient");
    alu_persistent(FI_PRIMARY, 1'b0, "A3: ALU primary persistent result");
    alu_persistent(FI_SHADOW,  1'b1, "A4: ALU shadow persistent sum");
    cmp_transient(FI_PRIMARY, "C0: CMP primary transient");
    cmp_transient(FI_SHADOW,  "C1: CMP shadow transient");
    cmp_persistent(FI_PRIMARY, "C2: CMP primary persistent");
    cmp_persistent(FI_SHADOW,  "C3: CMP shadow persistent");
    mul_transient(FI_PRIMARY, "M0: MUL primary transient");
    mul_transient(FI_SHADOW,  "M1: MUL shadow transient");
    mul_persistent(FI_PRIMARY, "M2: MUL primary persistent");
    mul_persistent(FI_SHADOW,  "M3: MUL shadow persistent");
    div_transient(FI_PRIMARY, 1'b0, "D0: DIV primary transient quotient");
    div_transient(FI_SHADOW,  1'b1, "D1: DIV shadow transient remainder");
    div_persistent(FI_PRIMARY, 1'b0, "D2: DIV primary persistent quotient");
    div_persistent(FI_SHADOW,  1'b1, "D3: DIV shadow persistent remainder");
    $display("PASS: all shadow-FU injection tests");
    $finish;
  end
endmodule
