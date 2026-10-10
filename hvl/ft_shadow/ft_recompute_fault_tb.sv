// Direct arithmetic-module and recovery tests; no processor or instruction decoder.
// sim/Makefile runs 32/64-bit datapaths at each mismatch threshold (1, 2, 3).
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
    // Enable optional arithmetic paths for direct ALU-control tests only.
    // TP is local to this testbench; processor/ISA/Linux builds still use P.
    changed.ZBA_SUPPORTED = 1;
    changed.ZBB_SUPPORTED = 1;
    changed.ZBKB_SUPPORTED = 1;
    return changed;
  endfunction
  localparam cvw_t TP = test_config(P);
  localparam int N = TP.XLEN;
  localparam logic [1:0] FI_PRIMARY = 1, FI_SHADOW = 2, FI_XOR = 0, FI_STUCK0 = 1, FI_STUCK1 = 2;
  localparam int OP_ADD = 0;
  localparam int OP_SUB = 1;
  localparam int OP_SLT = 2;
  localparam int OP_SLTU = 3;
  localparam int OP_SRL = 4;
  localparam int OP_SRA = 5;
  localparam int OP_SLL = 6;
  localparam int OP_SLLI_UW = 7;
  localparam int OP_ROR = 8;
  localparam int OP_SUBW = 9;
  localparam int CH_RESULT = 0;
  localparam int CH_ARITH = 1;
  localparam int CH_SHIFT = 2;
  localparam int CH_CMP = 3;

  logic clk = 0, reset, flush, valid, advance;
  logic [N-1:0] a, b, ca, cb, result, sum;
  logic signed_cmp, w64, uw64, sub, bmu;
  logic [2:0] select_op, funct3, balu;
  logic [3:0] bselect, zbbselect;
  logic fi_enable, second_result_fault;
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
  // The testbench clock deliberately uses a blocking assignment.
  /* verilator lint_off BLKSEQ */
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */

  // These injectors run without forces to check the production stimulus source.
  logic random_enable = 0;
  logic [N+1:0] random_input = '1, random_out0, random_out1;
    ft_fault_inject #(.WIDTH(N+2), .SEED(16'hA001)) random_fi0(
    .clk, .reset, .fi_enable(random_enable), .data_i(random_input), .data_o(random_out0));
    ft_fault_inject #(.WIDTH(N+2), .SEED(16'hA041)) random_fi1(
    .clk, .reset, .fi_enable(random_enable), .data_i(random_input), .data_o(random_out1));

    ft_alu #(.P(TP), .TE_THRESHOLD(THRESHOLD)) dut(
    .clk, .reset, .flush, .valid,
    .advance, .A(a), .B(b), .cmp_a(ca), .cmp_b(cb), .cmp_sgnd(signed_cmp),
    .W64(w64), .UW64(uw64), .SubArith(sub), .ALUSelect(select_op), .BSelect(bselect),
    .ZBBSelect(zbbselect), .Funct3(funct3), .BALUControl(balu), .Funct7(7'b0), .Rs2E(5'b0),
    .BMUActive(bmu), .CZero(2'b0), .fi_enable, .ALUResult(result), .Sum(sum), .flags,
    .stall_req(stall), .unresolved, .pe_primary, .pe_shadow, .cmp_pe_primary, .cmp_pe_shadow);
    ft_mul #(.P(TP), .TE_THRESHOLD(THRESHOLD)) mul_dut(
    .clk, .reset, .StallM(mul_stall), .FlushM(mul_flush), .ForwardedSrcAE(mul_a),
    .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .MulActiveE(mul_active),
    .fi_enable(mul_fi_enable),
    .ProdM(mul_prod), .stall_req(mul_stall), .unresolved(mul_unresolved),
    .pe_primary(mul_pe_primary), .pe_shadow(mul_pe_shadow));
    ft_div #(.P(TP), .TE_THRESHOLD(THRESHOLD)) div_dut(
    .clk, .reset, .StallM(div_stall), .FlushE(flush), .FlushM(flush), .IntDivE(div_active), .DivSignedE(div_signed),
    .W64E(div_w64), .ForwardedSrcAE(div_a), .ForwardedSrcBE(div_b), .fi_enable(div_fi_enable),
    .DivBusyE(div_busy), .QuotM(div_quot), .RemM(div_rem), .stall_req(div_stall),
    .unresolved(div_unresolved), .pe_primary(div_pe_primary), .pe_shadow(div_pe_shadow));

  // Directed recovery tests override only private injector selections/events.
  // Production RTL exposes a shared enable and generates these values locally.
  always @* begin
    force dut.replica[0].result_fi.inject_now = fi_enable & target[0] & (channel == 2'd0);
    force dut.replica[0].result_fi.fi_bit = $clog2(N)'(bit_index);
    force dut.replica[0].result_fi.fi_kind = kind;
    force dut.replica[0].arith_fi.inject_now = fi_enable & target[0] & (channel == 2'd1);
    force dut.replica[0].arith_fi.fi_bit = $clog2(N + 1)'(bit_index);
    force dut.replica[0].arith_fi.fi_kind = kind;
    force dut.replica[0].shift_fi.inject_now = fi_enable & target[0] & (channel == 2'd2);
    force dut.replica[0].shift_fi.fi_bit = $clog2(N + 2)'(bit_index);
    force dut.replica[0].shift_fi.fi_kind = kind;
    force dut.replica[0].cmp_fi.inject_now = fi_enable & target[0] & (channel == 2'd3);
    force dut.replica[0].cmp_fi.fi_bit = $clog2(N + 1)'(bit_index);
    force dut.replica[0].cmp_fi.fi_kind = kind;
    force dut.replica[1].result_fi.inject_now = second_result_fault | (fi_enable & target[1] & (channel == 2'd0));
    force dut.replica[1].result_fi.fi_bit = second_result_fault ? $clog2(N)'(3) : $clog2(N)'(bit_index);
    force dut.replica[1].result_fi.fi_kind = kind;
    force dut.replica[1].arith_fi.inject_now = fi_enable & target[1] & (channel == 2'd1);
    force dut.replica[1].arith_fi.fi_bit = $clog2(N + 1)'(bit_index);
    force dut.replica[1].arith_fi.fi_kind = kind;
    force dut.replica[1].shift_fi.inject_now = fi_enable & target[1] & (channel == 2'd2);
    force dut.replica[1].shift_fi.fi_bit = $clog2(N + 2)'(bit_index);
    force dut.replica[1].shift_fi.fi_kind = kind;
    force dut.replica[1].cmp_fi.inject_now = fi_enable & target[1] & (channel == 2'd3);
    force dut.replica[1].cmp_fi.fi_bit = $clog2(N + 1)'(bit_index);
    force dut.replica[1].cmp_fi.fi_kind = kind;
    force mul_dut.primary_fi.inject_now = mul_fi_enable & mul_target[0];
    force mul_dut.primary_fi.fi_bit = mul_bit;
    force mul_dut.primary_fi.fi_kind = mul_kind;
    force mul_dut.shadow_fi.inject_now = mul_fi_enable & mul_target[1];
    force mul_dut.shadow_fi.fi_bit = mul_bit;
    force mul_dut.shadow_fi.fi_kind = mul_kind;
    force div_dut.primary_quot_fi.inject_now = div_fi_enable & div_target[0] & (div_channel == 1'b0);
    force div_dut.primary_quot_fi.fi_bit = div_bit;
    force div_dut.primary_quot_fi.fi_kind = div_kind;
    force div_dut.primary_rem_fi.inject_now = div_fi_enable & div_target[0] & (div_channel == 1'b1);
    force div_dut.primary_rem_fi.fi_bit = div_bit;
    force div_dut.primary_rem_fi.fi_kind = div_kind;
    force div_dut.shadow_quot_fi.inject_now = div_fi_enable & div_target[1] & (div_channel == 1'b0);
    force div_dut.shadow_quot_fi.fi_bit = div_bit;
    force div_dut.shadow_quot_fi.fi_kind = div_kind;
    force div_dut.shadow_rem_fi.inject_now = div_fi_enable & div_target[1] & (div_channel == 1'b1);
    force div_dut.shadow_rem_fi.fi_bit = div_bit;
    force div_dut.shadow_rem_fi.fi_kind = div_kind;
  end

  task automatic check(input logic condition, input string label_text);
    checks++;
    if (condition !== 1'b1) $fatal(1, "%s at %0t N=%0d threshold=%0d", label_text, $time, N, THRESHOLD);
  endtask
  function automatic string target_name(input logic [1:0] value);
    case (value)
      FI_PRIMARY: return "primary";
      FI_SHADOW: return "shadow";
      default: return "both/none";
    endcase
  endfunction
  function automatic string kind_name(input logic [1:0] value);
    case (value)
      FI_XOR: return "xor";
      FI_STUCK0: return "stuck-0";
      FI_STUCK1: return "stuck-1";
      default: return "reserved";
    endcase
  endfunction
  function automatic logic [1:0] compare_ref(input logic [N-1:0] x, y, input logic sgnd);
    return {x == y, sgnd ? ($signed(x) < $signed(y)) : (x < y)};
  endfunction
  function automatic logic [N-1:0] shift_ref(input logic [N-1:0] x, input int amount, input int mode,
                                             input logic word_op, input logic unsigned_word);
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
    second_result_fault = 0;
    target = 0;
    kind = 0;
    channel = 2'(CH_RESULT);
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
  task automatic random_injector_test;
    logic transparent, single_bit, staggered, skipped_invalid;
    logic [3:0] kinds_seen;
    logic [N+1:0] bits_changed;
    int events, last_event;
    reset_case();
    transparent = 1;
    single_bit = 1;
    staggered = 1;
    skipped_invalid = 0;
    kinds_seen = 0;
    bits_changed = 0;
    events = 0;
    last_event = -1;
    repeat (1024) begin
      clock_edge();
      transparent &= random_out0 == random_input && random_out1 == random_input;
    end
    check(transparent, "disabled LFSR injectors pass through across event boundaries");
    @(negedge clk);
    random_enable = 1;
    for (int cycle = 0; cycle < 16384; cycle++) begin
      // Alternate whole event windows so both stuck-at polarities can corrupt.
      @(negedge clk);
      random_input = cycle[9] ? '1 : '0;
      clock_edge();
      single_bit &= $onehot0(random_out0 ^ random_input) && $onehot0(random_out1 ^ random_input);
      staggered &= !(random_fi0.inject_now && random_fi1.inject_now);
      bits_changed |= random_out0 ^ random_input;
      if (random_fi0.inject_now) begin
        if (last_event >= 0) check(cycle - last_event == 512, "LFSR event period");
        last_event = cycle;
        events++;
        kinds_seen[random_fi0.fi_kind] = 1;
        if (int'(random_fi0.fi_bit) >= N + 2) begin
          skipped_invalid = 1;
          check(random_out0 == random_input, "out-of-range LFSR selection skips corruption");
        end
      end else check(random_out0 == random_input, "corruption lasts only the event cycle");
    end
    check(events == 32 && kinds_seen == 4'b1111, "LFSR exercises all fault kinds");
    check(single_bit && staggered, "single-bit events are staggered between replicas");
    check(skipped_invalid && $countones(bits_changed) > 3, "LFSR selects multiple physical bits");
    @(negedge clk);
    reset = 1;
    clock_edge();
    check(random_out0 == random_input && random_fi0.lfsr == 16'hA001 && random_fi1.lfsr == 16'hA041,
          "reset suppresses injection and restores seeds");
    random_enable = 0;
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
      OP_SUB:  sub = 1;
      OP_SLT: begin
        select_op = 2;
        sub = 1;
        a = N'(1) << (N - 1);
        b = 1;
      end
      OP_SLTU: begin
        select_op = 3;
        sub = 1;
        a = '1;
        b = 1;
      end
      OP_SRL: begin
        select_op = 1;
        bmu = 1;
        funct3 = 5;
        a = N'('h98765432);
        b = 3;
      end
      OP_SRA: begin
        select_op = 1;
        bmu = 1;
        funct3 = 5;
        sub = 1;
        w64 = (N == 64);
        a = N'('h80000000);
        b = 5;
      end
      OP_SLL: begin
        select_op = 1;
        bmu = 1;
        funct3 = 1;
        a = 3;
        b = 4;
      end
      OP_SLLI_UW: begin
        select_op = 1;
        bmu = 1;
        funct3 = 1;
        uw64 = (N == 64);
        bselect = (N == 64) ? 1 : 0;
        a = '1;
        b = 7;
      end
      OP_ROR: begin
        select_op = 1;
        bmu = 1;
        funct3 = 5;
        balu = 4;
        a = 3;
        b = 4;
      end  // ROR
      OP_SUBW: begin
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
      CH_RESULT: initial_bit = expected_result[physical_bit];
      CH_ARITH:  initial_bit = dut.arith_raw[0][physical_bit];
      CH_SHIFT:  initial_bit = dut.shift_raw[0][physical_bit];
      default:   initial_bit = dut.cmp_raw[0][physical_bit];
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
      check(dut.normal_arith[0] == saved_arithmetic && dut.normal_cmp[0] == saved_compare, "retry preserves snapshots");
    end
    if (expect_isolation) begin
      check(stall && !unresolved, "diagnostic cycle holds transaction");
      clock_edge();
      check(!stall && !unresolved && result == expected_result && sum == expected_sum && flags == expected_flags,
            "isolation selects original healthy outputs");
      if (selected_channel == CH_CMP)
        check(cmp_pe_primary == replica_target[0] && cmp_pe_shadow == replica_target[1] && !pe_primary && !pe_shadow,
              "CMP isolates independently");
      else
        check(pe_primary == replica_target[0] && pe_shadow == replica_target[1] && !cmp_pe_primary && !cmp_pe_shadow,
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
    $display("PASS persistent op=%0d channel=%0d bit=%0d replica=%s kind=%s result=%h flags=%b", op, selected_channel,
             physical_bit, target_name(target), kind_name(kind), expected_result, expected_flags);
  endtask

  task automatic transient_case(input int selected_channel, input logic [1:0] replica_target);
    reset_case();
    set_operation(selected_channel == CH_SHIFT ? OP_SRL : OP_ADD);
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
    check(result == (selected_channel == CH_SHIFT ? shift_ref(a, int'(b), 1, 0, 0) : a + b),
          "transient returns independent oracle result");
  endtask

  task automatic independent_controllers(input logic cmp_first);
    reset_case();
    set_operation(OP_ADD);
    channel = 2'(cmp_first ? CH_CMP : CH_RESULT);
    target = FI_PRIMARY;
    kind = 2;
    bit_index = 0;
    fi_enable = 1;
    repeat (THRESHOLD + 1) clock_edge();
    check(cmp_first ? cmp_pe_primary : pe_primary, "first lane isolates");
    @(negedge clk);
    channel = 2'(cmp_first ? CH_RESULT : CH_CMP);
    target  = FI_SHADOW;
    repeat (THRESHOLD + 1) clock_edge();
    check((cmp_first ? (cmp_pe_primary && pe_shadow) : (pe_primary && cmp_pe_shadow)) && !stall && !unresolved,
          "other lane recovers with different replica selection");
    check(result == a + b && flags == compare_ref(ca, cb, signed_cmp), "independent selected outputs are correct");
    @(negedge clk);
    fi_enable = 0;
    flush = 1;
    clock_edge();
    check(!pe_primary && !pe_shadow && !cmp_pe_primary && !cmp_pe_shadow, "flush clears both controllers");
  endtask
  // Exercise the physical injection point and real recovery controller at
  // every masked shift amount, including word sign and displacement boundaries.
  task automatic shift_fault_sweep;
    logic [N-1:0] expected;
    // Only the physical bit index is consumed below; upper int bits are unused.
    /* verilator lint_off UNUSEDSIGNAL */
    int fault_bit;
    /* verilator lint_on UNUSEDSIGNAL */
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
              fault_bit = (boundary != 0) ? ((word_op != 0) ? 31 : N - 1) : 0;
              #1;
              channel = 2'(CH_SHIFT);
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
        channel = 2'(CH_SHIFT);
        target = FI_PRIMARY;
        bit_index = 0;
        kind = expected[0] ? 1 : 2;
        fi_enable = 1;
        repeat (THRESHOLD + 1) clock_edge();
        check(pe_primary && !unresolved && result == expected, "SLLI.UW physical recovery at every amount");
      end
  endtask

  task automatic launch_mul(input logic [1:0] replica_target, input logic [1:0] fault_kind);
    begin
      mul_active = 1'b1;
      mul_a = N'(13);
      mul_b = N'(11);
      mul_funct3 = 3'b000;
      mul_fi_enable = 1'b1;
      mul_target = replica_target;
      mul_kind = fault_kind;
      mul_bit = 0;
    end
  endtask

  task automatic mul_transient(input logic [1:0] replica_target, input string test_id);
    begin
      reset_case();
      launch_mul(replica_target, FI_XOR);
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT target=%s kind=%s bit=%0d", $time, test_id, mul_a, mul_b,
               mul_funct3, target_name(replica_target), kind_name(mul_kind), mul_bit);
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
      $display("  injected: primary raw/product=%0h/%0h shadow raw/product=%0h/%0h; arch product=%0h stall=%b",
               mul_dut.primary_prod_raw, mul_dut.primary_prod, mul_dut.shadow_prod_raw, mul_dut.shadow_prod, mul_prod,
               mul_stall);
      @(negedge clk);
      mul_fi_enable = 1'b0;
      @(posedge clk);
      #1;
      check(!mul_stall && !mul_unresolved && mul_prod == (2*N)'(143), {test_id, ": replay restores product"});
      $display("  recovered: fault disabled; product=%0h stall=%b unresolved=%b", mul_prod, mul_stall, mul_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic mul_persistent(input logic [1:0] replica_target, input string test_id);
    begin
      reset_case();
      launch_mul(replica_target, FI_STUCK1);
      // 13 * 11 is 0x8f; bit 4 is known zero, so stuck-at-1 differs.
      mul_bit = 4;
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT target=%s kind=%s bit=%0d", $time, test_id, mul_a, mul_b,
               mul_funct3, target_name(replica_target), kind_name(mul_kind), mul_bit);
      @(posedge clk);
      #1;
      @(posedge clk);
      #1;
      check(mul_stall || (THRESHOLD == 1 && mul_unresolved), {test_id, ": initial mismatch contained"});
      $display("  injected: primary raw/product=%0h/%0h shadow raw/product=%0h/%0h; arch product=%0h stall=%b",
               mul_dut.primary_prod_raw, mul_dut.primary_prod, mul_dut.shadow_prod_raw, mul_dut.shadow_prod, mul_prod,
               mul_stall);
      repeat (THRESHOLD - 1) clock_edge();
      check(mul_unresolved && !mul_stall && mul_prod == '0, {test_id, ": persistent fault traps"});
      check(!mul_pe_primary && !mul_pe_shadow, {test_id, ": no unsupported isolation"});
      $display("  outcome: product=%0h unresolved=%b (MUL has no isolation relation)", mul_prod, mul_unresolved);
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

  task automatic launch_div(input logic [1:0] replica_target, input logic fault_channel, input logic [1:0] fault_kind);
    begin
      div_active = 1'b1;
      div_signed = 1'b0;
      div_w64 = 1'b0;
      div_a = N'(100);
      div_b = N'(7);
      div_fi_enable = 1'b1;
      div_target = replica_target;
      div_channel = fault_channel;
      div_kind = fault_kind;
      div_bit = 0;
    end
  endtask

  task automatic div_transient(input logic [1:0] replica_target, input logic fault_channel, input string test_id);
    begin
      reset_case();
      launch_div(replica_target, fault_channel, FI_XOR);
      $display("[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b; INJECT target=%s channel=%s kind=%s bit=%0d", $time,
               test_id, div_a, div_b, div_signed, target_name(replica_target), fault_channel ? "remainder" : "quotient", kind_name(div_kind), div_bit);
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
          div_dut.primary_quot_raw, div_dut.primary_rem_raw, div_dut.primary_quot, div_dut.primary_rem,
          div_dut.shadow_quot_raw, div_dut.shadow_rem_raw, div_dut.shadow_quot, div_dut.shadow_rem, div_quot, div_rem);
      @(negedge clk);
      div_fi_enable = 1'b0;
      wait_div_complete();
      clock_edge();  // accept the checked E-stage result into the M-stage output
      check(!div_stall && !div_unresolved && div_quot == N'(14) && div_rem == N'(2), {
            test_id, ": retry restores quotient and remainder"});
      $display("  recovered: fault disabled; quotient/remainder=%0h/%0h stall=%b unresolved=%b", div_quot, div_rem,
               div_stall, div_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic div_persistent(input logic [1:0] replica_target, input logic fault_channel, input string test_id);
    begin
      reset_case();
      launch_div(replica_target, fault_channel, FI_STUCK1);
      // 100/7 gives q=0xe and r=0x2, so bit 0 differs when forced high.
      $display("[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b; INJECT target=%s channel=%s kind=%s bit=%0d", $time,
               test_id, div_a, div_b, div_signed, target_name(replica_target), fault_channel ? "remainder" : "quotient", kind_name(div_kind), div_bit);
      clock_edge();
      @(negedge clk);
      div_a = 0;
      div_b = 0;
      wait_div_complete();
      check(div_stall || div_unresolved, {test_id, ": initial completed mismatch contained"});
      $display(
          "  injected: primary raw q/r=%0h/%0h injected=%0h/%0h shadow raw q/r=%0h/%0h injected=%0h/%0h; arch q/r=%0h/%0h",
          div_dut.primary_quot_raw, div_dut.primary_rem_raw, div_dut.primary_quot, div_dut.primary_rem,
          div_dut.shadow_quot_raw, div_dut.shadow_rem_raw, div_dut.shadow_quot, div_dut.shadow_rem, div_quot, div_rem);
      while (!div_unresolved) clock_edge();
      check(div_unresolved && !div_stall && div_quot == '0 && div_rem == '0, {test_id, ": persistent fault traps"});
      check(!div_pe_primary && !div_pe_shadow, {test_id, ": no unsupported isolation"});
      $display("  outcome: quotient/remainder=%0h/%0h unresolved=%b (DIV has no isolation relation)", div_quot,
               div_rem, div_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  initial begin
    // Parameter diagnostics belong in verification, not synthesizable RTL.
    if (THRESHOLD < 1) $fatal(1, "THRESHOLD must be positive");
    reset = 1;
    drive_defaults();
    random_injector_test();
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
        select_op = (sg != 0) ? 2 : 3;
        #1;
        check(flags == compare_ref(ca, cb, signed_cmp), "extended comparison reference");
        check(result == (signed_cmp ? N'($signed(a) < $signed(b)) : N'(a < b)), "SLT/SLTU reference");
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
        funct3 = (sg != 0) ? 4 : 5;
        zbbselect = 4'(3 + 4 * maximum);
        #1;
        check(result == ((((sg != 0) ? ($signed(a) < $signed(b)) : (a < b)) ^ (maximum != 0)) ? a : b),
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
      check(shift_ref(a, amount, mode, w64, 0) == dut.shift_result(dut.shift_raw[0], 0), "wide normal slice reference");
      force dut.alu_recompute = 1;
      #1;
      check(result == 0 && dut.shift_result(dut.shift_raw[0], 1) == shift_ref(a, amount, mode, w64, 0),
            "wide shifted diagnostic relation");
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
      persistent_case(OP_ADD, CH_RESULT, 0, 2'(replica_id), 1);
      persistent_case(OP_SUB, CH_RESULT, 0, 2'(replica_id), 1);
      persistent_case(OP_ADD, CH_ARITH, N, 2'(replica_id), 1);
      persistent_case(OP_SUB, CH_ARITH, N, 2'(replica_id), 1);
      persistent_case(OP_SLT, CH_ARITH, N, 2'(replica_id), 1);
      persistent_case(OP_SLTU, CH_ARITH, N, 2'(replica_id), 1);
      persistent_case(OP_SLT, CH_RESULT, 0, 2'(replica_id), 1);
      persistent_case(OP_SLTU, CH_RESULT, 0, 2'(replica_id), 1);
      persistent_case(OP_ADD, CH_CMP, 0, 2'(replica_id), 1);
      persistent_case(OP_ADD, CH_CMP, N, 2'(replica_id), 1);
      persistent_case(OP_SRL, CH_SHIFT, 0, 2'(replica_id), 1);
      persistent_case(OP_SRL, CH_SHIFT, N - 1, 2'(replica_id), 1);
      persistent_case(OP_SRA, CH_SHIFT, 31, 2'(replica_id), 1);
      persistent_case(OP_SLL, CH_SHIFT, 0, 2'(replica_id), 1);
      persistent_case(OP_SLLI_UW, CH_SHIFT, N - 1, 2'(replica_id), 1);
      persistent_case(OP_SRL, CH_RESULT, 0, 2'(replica_id), 1);
      persistent_case(OP_SRL, CH_ARITH, 0, 2'(replica_id), 0);
      persistent_case(OP_ROR, CH_RESULT, 0, 2'(replica_id), 0);
      if (N == 64) persistent_case(OP_SUBW, CH_RESULT, 0, 2'(replica_id), 0);
    end
    independent_controllers(0);
    independent_controllers(1);
    // Persistent XOR preserves the complement relation in both copies: ambiguous.
    for (int ch = 0; ch < 4; ch++) begin
      reset_case();
      set_operation(ch == CH_SHIFT ? OP_SRL : OP_ADD);
      fi_enable = 1;
      target = FI_PRIMARY;
      kind = FI_XOR;
      channel = 2'(ch);
      bit_index = 0;
      repeat (THRESHOLD + 1) clock_edge();
      if (ch == CH_SHIFT) check(pe_primary && !unresolved, "physical shift XOR diagnosed");
      else check(unresolved && !pe_primary && !cmp_pe_primary, "both-pass diagnosis traps");
    end
    // Distinct stuck faults in both result replicas disagree normally and both
    // fail the complement check. The second fault uses a separate physical bit.
    reset_case();
    set_operation(OP_ADD);
    channel = 2'(CH_RESULT);
    target = 1;
    kind = 2;
    bit_index = 0;
    fi_enable = 1;
    second_result_fault = 1;
    repeat (THRESHOLD + 1) clock_edge();
    check(unresolved && !pe_primary && !pe_shadow, "both-fail diagnosis is unresolved");
    second_result_fault = 0;
    // A changing persistent fault must not replace the first mismatch snapshot.
    reset_case();
    set_operation(OP_ADD);
    channel = 2'(CH_ARITH);
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
    check(dut.normal_arith[0] == {1'b0, (a + b) | N'(1)}, "first snapshot survives changed retry fault");
    clock_edge();
    check(pe_primary && !unresolved && result == a + b, "changed retry fault still selects healthy replica");
    // Flush cancels an in-flight comparison diagnosis as well as isolation.
    reset_case();
    set_operation(OP_ADD);
    channel = 2'(CH_CMP);
    target = 1;
    kind = 0;
    bit_index = 0;
    fi_enable = 1;
    clock_edge();
    @(negedge clk);
    flush = 1;
    fi_enable = 0;
    clock_edge();
    check(!stall && !unresolved && dut.normal_cmp[0] == '0, "flush cancels in-flight diagnosis and snapshots");
    // Range checks and reserved encodings are no-ops, including narrower channels.
    reset_case();
    set_operation(OP_ADD);
    fi_enable = 1;
    target = 3;
    for (int ch = 0; ch < 4; ch++) begin
      channel = 2'(ch);
      kind = 3;
      bit_index = 0;
      #1;
      check(!stall && result == a + b, "reserved kind no-op");
      if (ch != CH_RESULT) begin  // All result-channel indices are valid for power-of-two XLEN.
        kind = 0;
        bit_index = $clog2(N + 2)'((ch == CH_SHIFT) ? N + 2 : N + 1);
        #1;
        check(!stall && result == a + b, "invalid index does not alias");
      end
    end
    // Valid gates both controllers; capture is asserted before the first edge.
    reset_case();
    set_operation(OP_ADD);
    valid = 0;
    fi_enable = 1;
    target = 1;
    channel = 2'(CH_CMP);
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
      set_operation(OP_ADD);
      advance = 0;
      channel = 2'(lane == 0 ? CH_RESULT : CH_CMP);
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
