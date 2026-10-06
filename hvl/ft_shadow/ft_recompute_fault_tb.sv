// Independent arithmetic oracle and deterministic runtime-injection regression.
// Run with THRESHOLD=1/2/3 and TEST_XLEN=32/64 via sim/Makefile.
`include "config.vh"
module ft_recompute_fault_tb #(
    parameter int THRESHOLD = 2,
    TEST_XLEN = 64
);
  import cvw::*;
  `include "parameter-defs.vh"
  function automatic cvw_t test_config(input cvw_t original);
    cvw_t changed;
    changed = original;
    changed.XLEN = TEST_XLEN;
    changed.LOG_XLEN = $clog2(TEST_XLEN);
    // Exercise optional ALU operations even when the production configuration
    // omits them. This fixture does not change the core's feature selection.
    changed.ZBA_SUPPORTED = 1;
    changed.ZBB_SUPPORTED = 1;
    changed.ZBKB_SUPPORTED = 1;
    return changed;
  endfunction
  localparam cvw_t TP = test_config(P);
  localparam int N = TP.XLEN;
  localparam logic [1:0] FI_PRIMARY = 1, FI_SHADOW = 2, FI_XOR = 0, FI_STUCK1 = 2;
  logic clk = 0, reset, flush, valid, advance;
  logic [N-1:0] a, b, ca, cb, result, sum;
  logic signed_cmp, w64, uw64, sub, bmu;
  logic [2:0] select_op, funct3, balu;
  logic [3:0] bselect, zbbselect;
  logic fi_enable;
  logic [1:0] target, kind, channel, flags;
  logic [$clog2(N+2)-1:0] bit_index;
  logic stall, unresolved, pe_primary, pe_shadow, cmp_pe_primary, cmp_pe_shadow;
  int checks = 0;
  logic [N-1:0] vectors[9];
  logic [31:0] rotated_word;

  logic mul_active, mul_flush, mul_fi_enable, mul_stall, mul_unresolved;
  logic [N-1:0] mul_a, mul_b;
  logic [2:0] mul_funct3;
  logic [2*N-1:0] mul_prod;
  logic [1:0] mul_target, mul_kind;
  logic [$clog2(2*N)-1:0] mul_bit;
  logic mul_pe_primary, mul_pe_shadow;
  logic div_active, div_signed, div_w64, div_fi_enable, div_stall, div_unresolved, div_busy;
  logic [N-1:0] div_a, div_b, div_quot, div_rem;
  logic [1:0] div_target, div_kind;
  logic [$clog2(N)-1:0] div_bit;
  logic div_channel, div_pe_primary, div_pe_shadow;
  always #5 clk = ~clk;

  ft_alu #(
      .P(TP),
      .TE_THRESHOLD(THRESHOLD)
  ) dut (
      .clk,
      .reset,
      .flush,
      .valid,
      .advance,
      .A(a),
      .B(b),
      .cmp_a(ca),
      .cmp_b(cb),
      .cmp_sgnd(signed_cmp),
      .W64(w64),
      .UW64(uw64),
      .SubArith(sub),
      .ALUSelect(select_op),
      .BSelect(bselect),
      .ZBBSelect(zbbselect),
      .Funct3(funct3),
      .BALUControl(balu),
      .Funct7(7'b0),
      .Rs2E(5'b0),
      .BMUActive(bmu),
      .CZero(2'b0),
      .fi_enable,
      .fi_target(target),
      .fi_kind(kind),
      .fi_bit(bit_index),
      .fi_channel(channel),
      .ALUResult(result),
      .Sum(sum),
      .flags,
      .stall_req(stall),
      .unresolved,
      .pe_primary,
      .pe_shadow,
      .cmp_pe_primary,
      .cmp_pe_shadow
  );
  ft_mul #(
      .P(TP),
      .TE_THRESHOLD(THRESHOLD)
  ) mul_dut (
      .clk,
      .reset,
      .StallM(mul_stall),
      .FlushM(mul_flush),
      .ForwardedSrcAE(mul_a),
      .ForwardedSrcBE(mul_b),
      .Funct3E(mul_funct3),
      .MulActiveE(mul_active),
      .fi_enable(mul_fi_enable),
      .fi_target(mul_target),
      .fi_kind(mul_kind),
      .fi_bit(mul_bit),
      .ProdM(mul_prod),
      .stall_req(mul_stall),
      .unresolved(mul_unresolved),
      .pe_primary(mul_pe_primary),
      .pe_shadow(mul_pe_shadow)
  );
  ft_div #(
      .P(TP),
      .TE_THRESHOLD(THRESHOLD)
  ) div_dut (
      .clk,
      .reset,
      .StallM(1'b0),
      .FlushE(flush),
      .IntDivE(div_active),
      .DivSignedE(div_signed),
      .W64E(div_w64),
      .ForwardedSrcAE(div_a),
      .ForwardedSrcBE(div_b),
      .fi_enable(div_fi_enable),
      .fi_target(div_target),
      .fi_kind(div_kind),
      .fi_bit(div_bit),
      .fi_channel(div_channel),
      .DivBusyE(div_busy),
      .QuotM(div_quot),
      .RemM(div_rem),
      .stall_req(div_stall),
      .unresolved(div_unresolved),
      .pe_primary(div_pe_primary),
      .pe_shadow(div_pe_shadow)
  );

  task automatic check(input logic condition, input string label_text);
    checks++;
    if (condition !== 1'b1)
      $fatal(1, "%s at %0t N=%0d threshold=%0d", label_text, $time, N, THRESHOLD);
  endtask
  function automatic string target_name(input logic [1:0] value);
    case (value)
      1: return "primary";
      2: return "shadow";
      default: return "both/none";
    endcase
  endfunction
  function automatic string kind_name(input logic [1:0] value);
    case (value)
      0: return "xor";
      1: return "stuck-0";
      2: return "stuck-1";
      default: return "reserved";
    endcase
  endfunction
  function automatic logic [1:0] compare_ref(input logic [N-1:0] x, y, input logic sgnd);
    return {x == y, sgnd ? ($signed(x) < $signed(y)) : (x < y)};
  endfunction
  function automatic logic [N-1:0] shift_ref(input logic [N-1:0] x, input int amount,
                                             input int mode, input logic word_op,
                                             input logic unsigned_word);
    logic [N-1:0] operand, shifted;
    logic [31:0] word_result;
    operand = unsigned_word ? N'(x[31:0]) : x;
    if (word_op) begin
      case (mode)
        0: word_result = operand[31:0] << (amount & 31);
        1: word_result = operand[31:0] >> (amount & 31);
        default: word_result = $signed(operand[31:0]) >>> (amount & 31);
      endcase
      return N'($signed(word_result));
    end
    case (mode)
      0: shifted = operand << amount;
      1: shifted = operand >> amount;
      default: shifted = $signed(operand) >>> amount;
    endcase
    return shifted;
  endfunction
  task automatic drive_defaults;
    flush = 0;
    valid = 0;
    advance = 1;
    a = 0;
    b = 0;
    ca = 5;
    cb = 7;
    signed_cmp = 0;
    w64 = 0;
    uw64 = 0;
    sub = 0;
    bmu = 0;
    select_op = 0;
    funct3 = 0;
    balu = 0;
    bselect = 0;
    zbbselect = 0;
    fi_enable = 0;
    target = 0;
    kind = 0;
    channel = 0;
    bit_index = 0;
    mul_active = 0;
    mul_flush = 0;
    mul_fi_enable = 0;
    mul_a = 0;
    mul_b = 0;
    mul_funct3 = 0;
    mul_target = 0;
    mul_kind = 0;
    mul_bit = 0;
    div_active = 0;
    div_signed = 0;
    div_w64 = 0;
    div_fi_enable = 0;
    div_a = 0;
    div_b = 0;
    div_target = 0;
    div_kind = 0;
    div_bit = 0;
    div_channel = 0;
  endtask
  task automatic reset_case;
    @(negedge clk);
    drive_defaults();
    reset = 1;
    repeat (2) @(posedge clk);
    @(negedge clk);
    reset = 0;
  endtask
  task automatic clock_edge;
    @(posedge clk);
    #1;
  endtask
  task automatic set_operation(input int op);
    valid = 1;
    a = N'('h12);
    b = N'('h24);
    select_op = 0;
    sub = 0;
    bmu = 0;
    w64 = 0;
    uw64 = 0;
    bselect = 0;
    funct3 = 0;
    balu = 0;
    case (op)
      1: sub = 1;
      2: begin
        select_op = 2;
        sub = 1;
        a = N'(1) << (N - 1);
        b = 1;
      end
      3: begin
        select_op = 3;
        sub = 1;
        a = '1;
        b = 1;
      end
      4: begin
        select_op = 1;
        bmu = 1;
        funct3 = 5;
        a = N'('h98765432);
        b = 3;
      end
      5: begin
        select_op = 1;
        bmu = 1;
        funct3 = 5;
        sub = 1;
        w64 = (N == 64);
        a = N'('h80000000);
        b = 5;
      end
      6: begin
        select_op = 1;
        bmu = 1;
        funct3 = 1;
        a = 3;
        b = 4;
      end
      7: begin
        select_op = 1;
        bmu = 1;
        funct3 = 1;
        uw64 = (N == 64);
        bselect = (N == 64) ? 1 : 0;
        a = '1;
        b = 7;
      end
      8: begin
        select_op = 1;
        bmu = 1;
        funct3 = 5;
        balu = 4;
        a = 3;
        b = 4;
      end  // ROR
      9: begin
        sub = 1;
        w64 = (N == 64);
      end  // SUBW (unsupported diagnosis)
      default: ;
    endcase
  endtask

  task automatic persistent_case(input int op, input int selected_channel, input int physical_bit,
                                 input logic [1:0] replica_target, input logic expect_isolation);
    logic [N-1:0] expected_result, expected_sum;
    logic [1:0] expected_flags;
    logic initial_bit;
    logic [N:0] saved_arithmetic, saved_compare;
    reset_case();
    set_operation(op);
    #1;
    expected_result = result;
    expected_sum = sum;
    expected_flags = flags;
    channel = 2'(selected_channel);
    bit_index = $clog2(N + 2)'(physical_bit);
    target = replica_target;
    case (selected_channel)
      0: initial_bit = expected_result[physical_bit];
      1: initial_bit = dut.arith_raw[0][physical_bit];
      2: initial_bit = dut.shift_raw[0][physical_bit];
      default: initial_bit = dut.cmp_raw[0][physical_bit];
    endcase
    kind = initial_bit ? 1 : 2;
    fi_enable = 1;
    #1;
    check(stall && result == '0 && sum == '0 && flags == '0, "mismatch masks all outputs");
    clock_edge();
    saved_arithmetic = dut.normal_arith[0];
    saved_compare = dut.normal_cmp[0];
    check(!dut.alu_capture_normal && !dut.cmp_capture_normal, "capture is a first-edge pulse");
    repeat (THRESHOLD - 1) begin
      clock_edge();
      check(dut.normal_arith[0] == saved_arithmetic && dut.normal_cmp[0] == saved_compare,
            "retry preserves snapshots");
    end
    if (expect_isolation) begin
      check(stall && !unresolved, "diagnostic cycle holds transaction");
      clock_edge();
      check(
          !stall && !unresolved && result==expected_result && sum==expected_sum && flags==expected_flags,
          "isolation selects original healthy outputs");
      if (selected_channel == 3)
        check(
            cmp_pe_primary==replica_target[0] && cmp_pe_shadow==replica_target[1] && !pe_primary && !pe_shadow,
            "CMP isolates independently");
      else
        check(
            pe_primary==replica_target[0] && pe_shadow==replica_target[1] && !cmp_pe_primary && !cmp_pe_shadow,
            "ALU isolates independently");
      @(negedge clk);
      a  = a + N'(8);
      b  = b + N'(1);
      ca = ca + N'(5);
      cb = cb + N'(5);
      #1;
      check(!stall && !unresolved, "subsequent operation retains selected replica");
    end else
      check(unresolved && !stall && result == '0 && sum == '0 && flags == '0,
            "unsupported operation releases only masked fault");
    $display("PASS persistent op=%0d channel=%0d bit=%0d replica=%s kind=%s result=%h flags=%b",
             op, selected_channel, physical_bit, target_name(target), kind_name(kind),
             expected_result, expected_flags);
  endtask

  task automatic transient_case(input int selected_channel, input logic [1:0] replica_target);
    reset_case();
    set_operation(selected_channel == 2 ? 4 : 0);
    channel = 2'(selected_channel);
    target = replica_target;
    bit_index = 0;
    kind = FI_XOR;
    fi_enable = 1;
    #1;
    check(stall, "runtime enable activates mismatch");
    clock_edge();
    @(negedge clk);
    fi_enable = 0;
    repeat (THRESHOLD + 2) clock_edge();
    check(!stall && !unresolved && flags == 2'b01, "transient recovers");
    check(result == (selected_channel == 2 ? shift_ref(a, int'(b), 1, 0, 0) : a + b),
          "transient returns independent oracle result");
  endtask

  task automatic independent_controllers(input logic cmp_first);
    reset_case();
    set_operation(0);
    channel = cmp_first ? 3 : 0;
    target = FI_PRIMARY;
    kind = 2;
    bit_index = 0;
    fi_enable = 1;
    repeat (THRESHOLD + 1) clock_edge();
    check(cmp_first ? cmp_pe_primary : pe_primary, "first lane isolates");
    @(negedge clk);
    channel = cmp_first ? 0 : 3;
    target  = FI_SHADOW;
    repeat (THRESHOLD + 1) clock_edge();
    check(
        (cmp_first ? (cmp_pe_primary && pe_shadow) : (pe_primary && cmp_pe_shadow)) && !stall && !unresolved,
        "other lane recovers with different replica selection");
    check(result == a + b && flags == compare_ref(ca, cb, signed_cmp),
          "independent selected outputs are correct");
    @(negedge clk);
    fi_enable = 0;
    flush = 1;
    clock_edge();
    check(!pe_primary && !pe_shadow && !cmp_pe_primary && !cmp_pe_shadow,
          "flush clears both controllers");
  endtask
  // Exercise the physical injection point and real recovery controller at
  // every masked shift amount, including word sign and displacement boundaries.
  task automatic shift_fault_sweep;
    logic [N-1:0] expected;
    int fault_bit;
    for (int word_op = 0; word_op < ((N == 64) ? 2 : 1); word_op++)
      for (int mode = 0; mode < 3; mode++)
        for (int amount = 0; amount < N; amount++)
          for (int replica_id = 1; replica_id <= 2; replica_id++)
            for (int boundary = 0; boundary < 2; boundary++) begin
              reset_case();
              valid = 1;
              select_op = 1;
              bmu = 1;
              a = N'(64'hfedcba9887654321);
              b = N'(amount);
              w64 = 1'(word_op);
              funct3 = (mode == 0) ? 1 : 5;
              sub = (mode == 2);
              expected = shift_ref(a, amount, mode, w64, 0);
              fault_bit = boundary ? (word_op ? 31 : N - 1) : 0;
              #1;
              channel = 2;
              target = 2'(replica_id);
              bit_index = $clog2(N + 2)'(fault_bit);
              kind = expected[fault_bit] ? 1 : 2;
              fi_enable = 1;
              #1;
              check(stall, "physical shift fault detected at every amount");
              repeat (THRESHOLD + 1) clock_edge();
              check(!stall && !unresolved && result == expected,
                    "physical shift recovery matches independent reference");
              check(pe_primary == (replica_id == 1) && pe_shadow == (replica_id == 2),
                    "shift sweep isolates injected replica");
            end
    if (N == 64)
      for (int amount = 0; amount < N; amount++) begin
        reset_case();
        valid = 1;
        select_op = 1;
        bmu = 1;
        uw64 = 1;
        bselect = 1;
        funct3 = 1;
        a = N'(64'hfedcba98ffffffff);
        b = N'(amount);
        expected = shift_ref(a, amount, 0, 0, 1);
        channel = 2;
        target = FI_PRIMARY;
        bit_index = 0;
        kind = expected[0] ? 1 : 2;
        fi_enable = 1;
        repeat (THRESHOLD + 1) clock_edge();
        check(pe_primary && !unresolved && result == expected,
              "SLLI.UW physical recovery at every amount");
      end
  endtask

  task automatic launch_mul(input logic [1:0] target, input logic [1:0] kind);
    begin
      mul_active = 1'b1;
      mul_a = 64'd13;
      mul_b = 64'd11;
      mul_funct3 = 3'b000;
      mul_fi_enable = 1'b1;
      mul_target = target;
      mul_kind = kind;
      mul_bit = 0;
    end
  endtask

  task automatic mul_transient(input logic [1:0] target, input string test_id);
    begin
      reset_case();
      launch_mul(target, FI_XOR);
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT target=%s kind=%s bit=%0d", $time,
               test_id, mul_a, mul_b, mul_funct3, target_name(target), kind_name(mul_kind),
               mul_bit);
      // First edge fills the M-stage partial-product registers.  Keep the
      // fault through the next edge so the controller actually enters RETRY.
      @(posedge clk);
      #1;
      @(posedge clk);
      #1;
      if (THRESHOLD == 1) begin
        check(mul_unresolved && !mul_stall && mul_prod == '0, {
              test_id, ": threshold-one sampled transient traps without diagnosis"});
        $display("PASS %s threshold=1 (no MUL isolation relation)", test_id);
        return;
      end
      check(mul_stall, {test_id, ": mismatch stalls"});
      $display(
          "  injected: primary raw/product=%0h/%0h shadow raw/product=%0h/%0h; arch product=%0h stall=%b",
          mul_dut.primary_prod_raw, mul_dut.primary_prod, mul_dut.shadow_prod_raw,
          mul_dut.shadow_prod, mul_prod, mul_stall);
      @(negedge clk);
      mul_fi_enable = 1'b0;
      @(posedge clk);
      #1;
      check(!mul_stall && !mul_unresolved && mul_prod == 128'd143, {
            test_id, ": replay restores product"});
      $display("  recovered: fault disabled; product=%0h stall=%b unresolved=%b", mul_prod,
               mul_stall, mul_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic mul_persistent(input logic [1:0] target, input string test_id);
    begin
      reset_case();
      launch_mul(target, FI_STUCK1);
      // 13 * 11 is 0x8f; bit 4 is known zero, so stuck-at-1 differs.
      mul_bit = 4;
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT target=%s kind=%s bit=%0d", $time,
               test_id, mul_a, mul_b, mul_funct3, target_name(target), kind_name(mul_kind),
               mul_bit);
      @(posedge clk);
      #1;
      @(posedge clk);
      #1;
      check(mul_stall || (THRESHOLD == 1 && mul_unresolved), {
            test_id, ": initial mismatch contained"});
      $display(
          "  injected: primary raw/product=%0h/%0h shadow raw/product=%0h/%0h; arch product=%0h stall=%b",
          mul_dut.primary_prod_raw, mul_dut.primary_prod, mul_dut.shadow_prod_raw,
          mul_dut.shadow_prod, mul_prod, mul_stall);
      repeat (THRESHOLD - 1) clock_edge();
      check(mul_unresolved && !mul_stall && mul_prod == '0, {test_id, ": persistent fault traps"});
      check(!mul_pe_primary && !mul_pe_shadow, {test_id, ": no unsupported isolation"});
      $display("  outcome: product=%0h unresolved=%b (MUL has no isolation relation)", mul_prod,
               mul_unresolved);
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
      div_active = 1'b1;
      div_signed = 1'b0;
      div_w64 = 1'b0;
      div_a = 64'd100;
      div_b = 64'd7;
      div_fi_enable = 1'b1;
      div_target = target;
      div_channel = channel;
      div_kind = kind;
      div_bit = 0;
    end
  endtask

  task automatic div_transient(input logic [1:0] target, input logic channel, input string test_id);
    begin
      reset_case();
      launch_div(target, channel, FI_XOR);
      $display(
          "[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b; INJECT target=%s channel=%s kind=%s bit=%0d",
          $time, test_id, div_a, div_b, div_signed, target_name(target),
          channel ? "remainder" : "quotient", kind_name(div_kind), div_bit);
      clock_edge();
      @(negedge clk);
      div_a = 0;
      div_b = 0;
      wait_div_complete();
      if (THRESHOLD == 1) begin
        while (!div_unresolved) clock_edge();
        check(!div_stall && div_quot == '0 && div_rem == '0, {
              test_id, ": threshold-one sampled transient traps without diagnosis"});
        $display("PASS %s threshold=1 (no DIV isolation relation)", test_id);
        return;
      end
      check(div_stall, {test_id, ": completed mismatch stalls"});
      $display(
          "  injected: primary raw q/r=%0h/%0h injected=%0h/%0h shadow raw q/r=%0h/%0h injected=%0h/%0h; arch q/r=%0h/%0h",
          div_dut.primary_quot_raw, div_dut.primary_rem_raw, div_dut.primary_quot,
          div_dut.primary_rem, div_dut.shadow_quot_raw, div_dut.shadow_rem_raw,
          div_dut.shadow_quot, div_dut.shadow_rem, div_quot, div_rem);
      @(negedge clk);
      div_fi_enable = 1'b0;
      wait_div_complete();
      check(!div_stall && !div_unresolved && div_quot == 64'd14 && div_rem == 64'd2, {
            test_id, ": retry restores quotient and remainder"});
      $display("  recovered: fault disabled; quotient/remainder=%0h/%0h stall=%b unresolved=%b",
               div_quot, div_rem, div_stall, div_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic div_persistent(input logic [1:0] target, input logic channel,
                                input string test_id);
    begin
      reset_case();
      launch_div(target, channel, FI_STUCK1);
      // 100/7 gives q=0xe and r=0x2, so bit 0 differs when forced high.
      $display(
          "[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b; INJECT target=%s channel=%s kind=%s bit=%0d",
          $time, test_id, div_a, div_b, div_signed, target_name(target),
          channel ? "remainder" : "quotient", kind_name(div_kind), div_bit);
      clock_edge();
      @(negedge clk);
      div_a = 0;
      div_b = 0;
      wait_div_complete();
      check(div_stall || div_unresolved, {test_id, ": initial completed mismatch contained"});
      $display(
          "  injected: primary raw q/r=%0h/%0h injected=%0h/%0h shadow raw q/r=%0h/%0h injected=%0h/%0h; arch q/r=%0h/%0h",
          div_dut.primary_quot_raw, div_dut.primary_rem_raw, div_dut.primary_quot,
          div_dut.primary_rem, div_dut.shadow_quot_raw, div_dut.shadow_rem_raw,
          div_dut.shadow_quot, div_dut.shadow_rem, div_quot, div_rem);
      while (!div_unresolved) clock_edge();
      check(div_unresolved && !div_stall && div_quot == '0 && div_rem == '0, {
            test_id, ": persistent fault traps"});
      check(!div_pe_primary && !div_pe_shadow, {test_id, ": no unsupported isolation"});
      $display(
          "  outcome: quotient/remainder=%0h/%0h unresolved=%b (DIV has no isolation relation)",
          div_quot, div_rem, div_unresolved);
      $display("PASS %s", test_id);
    end
  endtask


  initial begin
    reset = 1;
    drive_defaults();
    vectors[0] = 0;
    vectors[1] = 1;
    vectors[2] = '1;
    vectors[3] = N'(1) << (N - 1);
    vectors[4] = vectors[3] - 1;
    vectors[5] = vectors[3] + 1;
    vectors[6] = N'('h80000000);
    vectors[7] = N'('h7fffffff);
    vectors[8] = N'(64'hfedcba9876543210);
    reset_case();
    valid = 1;
    // Independent architectural references, including subtraction overflow.
    foreach (vectors[i])
    foreach (vectors[j]) begin
      a  = vectors[i];
      b  = vectors[j];
      ca = a;
      cb = b;
      for (int sg = 0; sg < 2; sg++) begin
        signed_cmp = 1'(sg);
        sub = 1;
        select_op = sg ? 2 : 3;
        #1;
        check(flags == compare_ref(ca, cb, signed_cmp), "extended comparison reference");
        check(result == N'(signed_cmp ? ($signed(a) < $signed(b)) : (a < b)), "SLT/SLTU reference");
      end
      select_op = 0;
      sub = 0;
      #1;
      check(result == a + b && sum == a + b, "ADD reference");
      sub = 1;
      #1;
      check(result == a - b && sum == a - b, "SUB reference");
      bmu = 1;
      bselect = 2;
      for (int sg = 0; sg < 2; sg++)
      for (int maximum = 0; maximum < 2; maximum++) begin
        funct3 = sg ? 4 : 5;
        zbbselect = 4'(3 + 4 * maximum);
        #1;
        check(result == (((sg ? ($signed(a) < $signed(b)) : (a < b)) ^ (maximum != 0)) ? a : b),
              "signed/unsigned min/max reference");
      end
      bmu = 0;
      bselect = 0;
      zbbselect = 0;
    end
    // All legal amounts and all boundary operand patterns, including word masking.
    foreach (vectors[i])
    for (int word_op = 0; word_op < ((N == 64) ? 2 : 1); word_op++)
    for (int mode = 0; mode < 3; mode++)
    for (int amount = 0; amount < N; amount++) begin
      a = vectors[i];
      b = N'(amount);
      w64 = 1'(word_op);
      bmu = 1;
      select_op = 1;
      funct3 = (mode == 0) ? 1 : 5;
      sub = (mode == 2);
      #1;
      check(result == shift_ref(a, amount, mode, w64, 0), "shift architectural reference");
      // The healthy diagnostic relation must hold at each legal amount.
      check(shift_ref(a, amount, mode, w64, 0) == dut.shift_result(dut.shift_raw[0], 0),
            "wide normal slice reference");
      force dut.alu_recompute = 1;
      #1;
      check(result == 0 && dut.shift_result(dut.shift_raw[0], 1) == shift_ref(
            a, amount, mode, w64, 0), "wide shifted diagnostic relation");
      release dut.alu_recompute;
    end
    w64 = 0;
    if (N == 64)
      foreach (vectors[i])
      for (int amount = 0; amount < N; amount++) begin
        a = vectors[i];
        b = N'(amount);
        bmu = 1;
        select_op = 1;
        funct3 = 1;
        sub = 0;
        uw64 = 1;
        bselect = 1;
        #1;
        check(result == shift_ref(a, amount, 0, 0, 1), "SLLI.UW zero extension reference");
      end
    uw64 = 0;
    bselect = 0;
    balu = 4;
    w64 = 0;
    foreach (vectors[i])
    for (int amount = 0; amount < N; amount++) begin
      a = vectors[i];
      b = N'(amount);
      sub = 0;
      funct3 = 5;
      #1;
      check(result == ((a >> amount) | (a << ((N - amount) % N))), "ROR ring reference");
      funct3 = 1;
      #1;
      check(result == ((a << amount) | (a >> ((N - amount) % N))), "ROL ring reference");
    end
    if (N == 64) begin
      w64 = 1;
      foreach (vectors[i])
      for (int amount = 0; amount < N; amount++) begin
        a = vectors[i];
        b = N'(amount);
        rotated_word = (a[31:0] >> (amount & 31)) | (a[31:0] << ((32 - (amount & 31)) % 32));
        funct3 = 5;
        #1;
        check(result == N'($signed(rotated_word)), "RORW masked ring reference");
        rotated_word = (a[31:0] << (amount & 31)) | (a[31:0] >> ((32 - (amount & 31)) % 32));
        funct3 = 1;
        #1;
        check(result == N'($signed(rotated_word)), "ROLW masked ring reference");
      end
      w64 = 0;
    end
    for (int replica_id = 1; replica_id <= 2; replica_id++) begin
      for (int ch = 0; ch < 4; ch++) transient_case(ch, 2'(replica_id));
      persistent_case(0, 0, 0, 2'(replica_id), 1);
      persistent_case(1, 0, 0, 2'(replica_id), 1);
      persistent_case(0, 1, N, 2'(replica_id), 1);
      persistent_case(1, 1, N, 2'(replica_id), 1);
      persistent_case(2, 1, N, 2'(replica_id), 1);
      persistent_case(3, 1, N, 2'(replica_id), 1);
      persistent_case(2, 0, 0, 2'(replica_id), 1);
      persistent_case(3, 0, 0, 2'(replica_id), 1);
      persistent_case(0, 3, 0, 2'(replica_id), 1);
      persistent_case(0, 3, N, 2'(replica_id), 1);
      persistent_case(4, 2, 0, 2'(replica_id), 1);
      persistent_case(4, 2, N - 1, 2'(replica_id), 1);
      persistent_case(5, 2, 31, 2'(replica_id), 1);
      persistent_case(6, 2, 0, 2'(replica_id), 1);
      persistent_case(7, 2, N - 1, 2'(replica_id), 1);
      persistent_case(4, 0, 0, 2'(replica_id), 1);
      persistent_case(4, 1, 0, 2'(replica_id), 0);
      persistent_case(8, 0, 0, 2'(replica_id), 0);
      if (N == 64) persistent_case(9, 0, 0, 2'(replica_id), 0);
    end
    independent_controllers(0);
    independent_controllers(1);
    // Persistent XOR preserves the complement relation in both copies: ambiguous.
    for (int ch = 0; ch < 4; ch++) begin
      reset_case();
      set_operation(ch == 2 ? 4 : 0);
      fi_enable = 1;
      target = FI_PRIMARY;
      kind = FI_XOR;
      channel = 2'(ch);
      bit_index = 0;
      repeat (THRESHOLD + 1) clock_edge();
      if (ch == 2) check(pe_primary && !unresolved, "physical shift XOR diagnosed");
      else check(unresolved && !pe_primary && !cmp_pe_primary, "both-pass diagnosis traps");
    end
    // Distinct stuck faults in both result replicas disagree normally and both
    // fail the complement check. The second fault uses a separate physical bit.
    reset_case();
    set_operation(0);
    channel = 0;
    target = 1;
    kind = 2;
    bit_index = 0;
    fi_enable = 1;
    force dut.replica[1].result_fi.fi_enable = 1'b1;
    force dut.replica[1].result_fi.fi_bit = 3;
    repeat (THRESHOLD + 1) clock_edge();
    check(unresolved && !pe_primary && !pe_shadow, "both-fail diagnosis is unresolved");
    release dut.replica[1].result_fi.fi_enable;
    release dut.replica[1].result_fi.fi_bit;
    // A changing persistent fault must not replace the first mismatch snapshot.
    reset_case();
    set_operation(0);
    channel = 1;
    target = 1;
    kind = 2;
    bit_index = 0;
    fi_enable = 1;
    #1;
    check(dut.alu_capture_normal && !dut.cmp_capture_normal, "independent first ALU capture pulse");
    clock_edge();
    @(negedge clk);
    bit_index = 3;
    repeat (THRESHOLD - 1) clock_edge();
    check(dut.normal_arith[0] == {1'b0, (a + b) | N'(1)},
          "first snapshot survives changed retry fault");
    clock_edge();
    check(pe_primary && !unresolved && result == a + b,
          "changed retry fault still selects healthy replica");
    // Flush cancels an in-flight comparison diagnosis as well as isolation.
    reset_case();
    set_operation(0);
    channel = 3;
    target = 1;
    kind = 0;
    bit_index = 0;
    fi_enable = 1;
    clock_edge();
    @(negedge clk);
    flush = 1;
    fi_enable = 0;
    clock_edge();
    check(!stall && !unresolved && dut.normal_cmp[0] == '0,
          "flush cancels in-flight diagnosis and snapshots");
    // Range checks and reserved encodings are no-ops, including narrower channels.
    reset_case();
    set_operation(0);
    fi_enable = 1;
    target = 3;
    for (int ch = 0; ch < 4; ch++) begin
      channel = 2'(ch);
      kind = 3;
      bit_index = 0;
      #1;
      check(!stall && result == a + b, "reserved kind no-op");
      kind = 0;
      bit_index = $clog2(N + 2)'((ch == 0) ? N : ((ch == 2) ? N + 2 : N + 1));
      #1;
      check(!stall && result == a + b, "invalid index does not alias");
    end
    // Valid gates both controllers; capture is asserted before the first edge.
    reset_case();
    set_operation(0);
    valid = 0;
    fi_enable = 1;
    target = 1;
    channel = 3;
    kind = 2;
    #1;
    check(!stall && !dut.cmp_capture_normal, "invalid execute instruction cannot capture");
    valid = 1;
    #1;
    check(dut.cmp_capture_normal && !dut.alu_capture_normal, "independent first CMP capture pulse");
    clock_edge();
    @(negedge clk);
    reset = 1;
    clock_edge();
    check(!unresolved && !cmp_pe_primary, "reset clears diagnosis");
    // A terminal fault must survive downstream backpressure even after the
    // injector is disabled. Exercise both independent architectural lanes.
    for (int lane = 0; lane < 2; lane++) begin
      reset_case();
      set_operation(0);
      advance = 0;
      channel = lane == 0 ? 0 : 3;
      target = FI_PRIMARY;
      kind = FI_XOR;
      bit_index = 0;
      fi_enable = 1;
      repeat (THRESHOLD + 1) clock_edge();
      check(unresolved, "ambiguous diagnosis reaches terminal fault");
      @(negedge clk);
      fi_enable = 0;
      repeat (4) begin
        clock_edge();
        check(unresolved && result == '0 && sum == '0 && flags == '0,
              "terminal fault and masking survive backpressure");
      end
      @(negedge clk);
      advance = 1;
      clock_edge();
      check(!unresolved, "terminal fault clears after acceptance");
    end
    shift_fault_sweep();
    mul_transient(FI_PRIMARY, "MUL transient primary");
    mul_transient(FI_SHADOW, "MUL transient shadow");
    mul_persistent(FI_PRIMARY, "MUL persistent primary");
    mul_persistent(FI_SHADOW, "MUL persistent shadow");
    div_transient(FI_PRIMARY, 0, "DIV quotient transient primary");
    div_transient(FI_SHADOW, 1, "DIV remainder transient shadow");
    div_persistent(FI_PRIMARY, 0, "DIV quotient persistent primary");
    div_persistent(FI_SHADOW, 1, "DIV remainder persistent shadow");
    $display("PASS ft_recompute_fault_tb XLEN=%0d threshold=%0d checks=%0d", N, THRESHOLD, checks);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "testbench timeout");
  end
endmodule
