// Direct arithmetic-module and recovery tests; no processor or instruction decoder.
// Use the processor's 64-bit configuration at mismatch thresholds 1, 2, and 3.
`include "config.vh"
module ft_recompute_fault_tb #(
    parameter int THRESHOLD = 2
);
  import cvw::*;
  `include "parameter-defs.vh"
  function automatic cvw_t test_config(input cvw_t original);
    cvw_t changed;
    changed = original;
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
  logic load;
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
  logic [N-1:0] mul_prod;
  logic [1:0] mul_kind;
  logic [$clog2(2*N)-1:0] mul_bit;
  logic div_active, div_signed, div_w64, div_fi_enable, div_stall, div_unresolved, div_busy;
  logic [N-1:0] div_a, div_b, div_result;
  logic [1:0] div_kind;
  logic [$clog2(N)-1:0] div_bit;
  logic div_channel;                    // the instruction: 0 quotient, 1 remainder
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
    .advance, .load, .hold(1'b0), .A(a), .B(b), .cmp_a(ca), .cmp_b(cb), .cmp_sgnd(signed_cmp),
    .W64(w64), .UW64(uw64), .SubArith(sub), .ALUSelect(select_op), .BSelect(bselect),
    .ZBBSelect(zbbselect), .Funct3(funct3), .BALUControl(balu), .Funct7(7'b0), .Rs2E(5'b0),
    .BMUActive(bmu), .CZero(2'b0), .fi_enable, .cmp_fi_enable(fi_enable), .ALUResult(result), .Sum(sum), .flags,
    .stall_req(stall), .unresolved, .pe_primary, .pe_shadow, .cmp_pe_primary, .cmp_pe_shadow);
    ft_mul #(.P(TP), .TE_THRESHOLD(THRESHOLD)) mul_dut(
    .clk, .reset, .StallM(mul_stall), .FlushM(mul_flush), .HoldE(1'b0), .ForwardedSrcAE(mul_a),
    .ForwardedSrcBE(mul_b), .Funct3E(mul_funct3), .MulActiveE(mul_active),
    .fi_enable(mul_fi_enable),
    .ProdM(mul_prod), .stall_req(mul_stall), .unresolved(mul_unresolved));
    ft_div #(.P(TP), .TE_THRESHOLD(THRESHOLD)) div_dut(
    .clk, .reset, .StallM(div_stall), .FlushE(flush), .FlushM(flush), .IntDivE(div_active), .DivSignedE(div_signed),
    .RemE(div_channel), .W64E(div_w64), .ForwardedSrcAE(div_a), .ForwardedSrcBE(div_b), .fi_enable(div_fi_enable),
    .DivBusyE(div_busy), .DivResultM(div_result), .stall_req(div_stall), .unresolved(div_unresolved));

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
    force mul_dut.result_fi.inject_now = mul_fi_enable;
    force mul_dut.result_fi.fi_bit = mul_bit;
    force mul_dut.result_fi.fi_kind = mul_kind;
    force div_dut.result_fi.inject_now = div_fi_enable;
    force div_dut.result_fi.fi_bit = div_bit;
    force div_dut.result_fi.fi_kind = div_kind;
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
    load = 0;
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
    mul_kind = 0;
    mul_bit = 0;
    div_active = 0;
    div_signed = 0;
    div_w64 = 0;
    div_fi_enable = 0;
    div_a = 0;
    div_b = 0;
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
  // The ALU wrapper evaluates an operation over two clock edges: COMPUTE captures
  // the replicas' channels, COMPARE checks them and steps the controllers.  It
  // then either presents the result (stall low) or is back in COMPUTE to run the
  // operation again (stall high).  The fault cases below step by evaluations.
  task automatic alu_eval;
    repeat (2) clock_edge();
  endtask
  // Present the inputs as they now stand as a new instruction: the wrapper
  // restarts in COMPUTE.  Needed once a result has been presented, because the
  // wrapper does not look at its inputs again until the next instruction.
  task automatic alu_load;
    load = 1;
    clock_edge();
    load = 0;
  endtask
  // A new instruction, evaluated once.
  task automatic alu_run;
    alu_load();
    alu_eval();
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
        w64 = 1'b1;
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
        uw64 = 1'b1;
        bselect = 1;
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
        w64 = 1'b1;
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
    alu_eval();  // without the fault: the reference outputs
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
    alu_load();   // the same operation again, now with the fault
    clock_edge();
    // COMPARE: the mismatch is in front of the controllers, the result is withheld.
    check(stall && result == '0 && sum == '0 && flags == '0, "mismatch stalls and nothing is presented");
    clock_edge();
    saved_arithmetic = dut.normal_arith[0];
    saved_compare = dut.normal_cmp[0];
    check(!dut.alu_capture_normal && !dut.cmp_capture_normal, "capture is a first-edge pulse");
    repeat (THRESHOLD - 1) begin
      alu_eval();
      check(dut.normal_arith[0] == saved_arithmetic && dut.normal_cmp[0] == saved_compare, "retry preserves snapshots");
    end
    if (expect_isolation) begin
      check(stall && !unresolved, "diagnostic cycle holds transaction");
      alu_eval();  // the diagnosis
      alu_eval();  // the operation again, on the replica it selected
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
      alu_run();
      check(!stall && !unresolved, "subsequent operation retains selected replica");
    end else begin
      alu_eval();  // the evaluation that ends in the unresolved state is released
      check(unresolved && !stall && result == '0 && sum == '0 && flags == '0,
            "unsupported operation releases only masked fault");
    end
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
    clock_edge();
    check(stall && (dut.alu_mismatch || dut.cmp_mismatch), "runtime enable activates mismatch");
    clock_edge();
    @(negedge clk);
    fi_enable = 0;
    repeat (THRESHOLD + 2) alu_eval();
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
    repeat (THRESHOLD + 1) alu_eval();
    check(cmp_first ? cmp_pe_primary : pe_primary, "first lane isolates");
    @(negedge clk);
    channel = 2'(cmp_first ? CH_RESULT : CH_CMP);
    target  = FI_SHADOW;
    repeat (THRESHOLD + 1) alu_eval();
    alu_eval();  // the operation again, on the replicas now selected
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
    for (int word_op = 0; word_op < 2; word_op++)
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
              channel = 2'(CH_SHIFT);
              target = 2'(replica_id);
              bit_index = $clog2(N + 2)'(fault_bit);
              kind = expected[fault_bit] ? 1 : 2;
              fi_enable = 1;
              clock_edge();
              check(stall && dut.alu_mismatch, "physical shift fault detected at every amount");
              clock_edge();
              repeat (THRESHOLD) alu_eval();
              alu_eval();  // the operation again, on the replica the diagnosis selected
              check(!stall && !unresolved && result == expected,
                    "physical shift recovery matches independent reference");
              check(pe_primary == (replica_id == 1) && pe_shadow == (replica_id == 2),
                    "shift sweep isolates injected replica");
            end
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
      repeat (THRESHOLD + 1) alu_eval();
      alu_eval();  // the operation again, on the replica the diagnosis selected
      check(pe_primary && !unresolved && result == expected, "SLLI.UW physical recovery at every amount");
    end
  endtask

  task automatic launch_mul(input logic [1:0] fault_kind);
    begin
      mul_active = 1'b1;
      mul_a = N'(13);
      mul_b = N'(11);
      mul_funct3 = 3'b000;
      mul_fi_enable = 1'b1;
      mul_kind = fault_kind;
      mul_bit = 0;
    end
  endtask

  // The multiplier wrapper evaluates a product over two clock edges (SUM, then
  // COMPARE), and after a failed check takes two more to reload its partial products
  // (REPLAY, LOAD) before evaluating again.
  task automatic mul_eval;
    repeat (2) clock_edge();
  endtask
  task automatic mul_retry;
    repeat (4) clock_edge();
  endtask

  task automatic mul_transient(input string test_id);
    begin
      reset_case();
      launch_mul(FI_XOR);
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT kind=%s bit=%0d", $time, test_id, mul_a, mul_b,
               mul_funct3, kind_name(mul_kind), mul_bit);
      // First edge fills the M-stage partial-product registers.  Keep the
      // fault through the evaluation so the controller actually enters RETRY.
      repeat (3) clock_edge();  // operand register, half products, partial-product registers
      mul_eval();
      if (THRESHOLD == 1) begin
        mul_retry();  // the evaluation that ends in the unresolved state is released
        check(mul_unresolved && !mul_stall && mul_prod == '0, {
              test_id, ": threshold-one sampled transient traps"});
        $display("PASS %s threshold=1", test_id);
        return;
      end
      check(mul_stall, {test_id, ": failed check stalls"});
      $display("  injected: raw/product=%0h/%0h; arch product=%0h stall=%b",
               mul_dut.prod_raw, mul_dut.prod, mul_prod, mul_stall);
      @(negedge clk);
      mul_fi_enable = 1'b0;
      mul_retry();
      check(!mul_stall && !mul_unresolved && mul_prod == N'(143), {test_id, ": replay restores product"});
      $display("  recovered: fault disabled; product=%0h stall=%b unresolved=%b", mul_prod, mul_stall, mul_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic mul_persistent(input string test_id);
    begin
      reset_case();
      launch_mul(FI_STUCK1);
      // 13 * 11 is 0x8f; bit 4 is known zero, so stuck-at-1 differs.
      mul_bit = 4;
      $display("[%0t] %s INPUT a=%0h b=%0h funct3=%b; INJECT kind=%s bit=%0d", $time, test_id, mul_a, mul_b,
               mul_funct3, kind_name(mul_kind), mul_bit);
      repeat (3) clock_edge();  // operand register, half products, partial-product registers
      mul_eval();
      check(mul_stall && mul_prod == '0, {test_id, ": initial failed check contained"});
      $display("  injected: raw/product=%0h/%0h; arch product=%0h stall=%b",
               mul_dut.prod_raw, mul_dut.prod, mul_prod, mul_stall);
      repeat (THRESHOLD - 1) mul_retry();
      mul_retry();  // the evaluation that ends in the unresolved state is released
      check(mul_unresolved && !mul_stall && mul_prod == '0, {test_id, ": persistent fault traps"});
      $display("  outcome: product=%0h unresolved=%b", mul_prod, mul_unresolved);
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

  task automatic launch_div(input logic remainder, input logic [1:0] fault_kind);
    begin
      div_active = 1'b1;
      div_signed = 1'b0;
      div_w64 = 1'b0;
      div_a = N'(100);
      div_b = N'(7);
      div_fi_enable = 1'b1;
      div_channel = remainder;
      div_kind = fault_kind;
      div_bit = 0;
    end
  endtask

  task automatic div_transient(input logic remainder, input string test_id);
    begin
      reset_case();
      launch_div(remainder, FI_XOR);
      $display("[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b %s; INJECT kind=%s bit=%0d", $time,
               test_id, div_a, div_b, div_signed, remainder ? "remainder" : "quotient", kind_name(div_kind), div_bit);
      clock_edge();
      @(negedge clk);
      div_a = 0;
      div_b = 0;
      wait_div_complete();
      if (THRESHOLD == 1) begin
        while (!div_unresolved) clock_edge();
        check(!div_stall && div_result == '0, {test_id, ": threshold-one sampled transient traps"});
        $display("PASS %s threshold=1", test_id);
        return;
      end
      // The completed result has been captured, fault included; the wrapper
      // checks the captured copy on the next edge.
      check(div_stall, {test_id, ": completed failed check stalls"});
      $display("  injected: raw/result=%0h/%0h; arch result=%0h", div_dut.result_raw, div_dut.result, div_result);
      @(negedge clk);
      div_fi_enable = 1'b0;
      wait_div_complete();
      clock_edge();  // the captured retry result is checked
      clock_edge();  // accept the checked E-stage result into the M-stage output
      check(!div_stall && !div_unresolved && div_result == (remainder ? N'(2) : N'(14)), {
            test_id, ": retry restores the result"});
      $display("  recovered: fault disabled; result=%0h stall=%b unresolved=%b", div_result, div_stall, div_unresolved);
      $display("PASS %s", test_id);
    end
  endtask

  task automatic div_persistent(input logic remainder, input string test_id);
    begin
      reset_case();
      launch_div(remainder, FI_STUCK1);
      // 100/7 gives q=0xe and r=0x2, so bit 0 differs when forced high.
      $display("[%0t] %s INPUT dividend=%0h divisor=%0h signed=%b %s; INJECT kind=%s bit=%0d", $time,
               test_id, div_a, div_b, div_signed, remainder ? "remainder" : "quotient", kind_name(div_kind), div_bit);
      clock_edge();
      @(negedge clk);
      div_a = 0;
      div_b = 0;
      wait_div_complete();
      check(div_stall || div_unresolved, {test_id, ": initial completed failed check contained"});
      $display("  injected: raw/result=%0h/%0h; arch result=%0h", div_dut.result_raw, div_dut.result, div_result);
      while (!div_unresolved) clock_edge();
      check(div_unresolved && !div_stall && div_result == '0, {test_id, ": persistent fault traps"});
      $display("  outcome: result=%0h unresolved=%b", div_result, div_unresolved);
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
        alu_run();
        check(flags == compare_ref(ca, cb, signed_cmp), "extended comparison reference");
        check(result == (signed_cmp ? N'($signed(a) < $signed(b)) : N'(a < b)), "SLT/SLTU reference");
      end
      select_op = 0;
      sub = 0;
      alu_run();
      check(result == a + b && sum == a + b, "ADD reference");
      sub = 1;
      alu_run();
      check(result == a - b && sum == a - b, "SUB reference");
      bmu = 1;
      bselect = 2;
      for (int sg = 0; sg < 2; sg++)
      for (int maximum = 0; maximum < 2; maximum++) begin
        funct3 = (sg != 0) ? 4 : 5;
        zbbselect = 4'(3 + 4 * maximum);
        alu_run();
        check(result == ((((sg != 0) ? ($signed(a) < $signed(b)) : (a < b)) ^ (maximum != 0)) ? a : b),
              "signed/unsigned min/max reference");
      end
      bmu = 0;
      bselect = 0;
      zbbselect = 0;
    end
    // All legal amounts and all boundary operand patterns, including word masking.
    foreach (vectors[i])
    for (int word_op = 0; word_op < 2; word_op++)
    for (int mode = 0; mode < 3; mode++)
    for (int amount = 0; amount < N; amount++) begin
      a = vectors[i];
      b = N'(amount);
      w64 = 1'(word_op);
      bmu = 1;
      select_op = 1;
      funct3 = (mode == 0) ? 1 : 5;
      sub = (mode == 2);
      alu_run();
      check(result == shift_ref(a, amount, mode, w64, 0), "shift architectural reference");
      // The healthy diagnostic relation must hold at each legal amount.
      check(shift_ref(a, amount, mode, w64, 0) == dut.shift_result(dut.shift_raw[0], 0, w64), "wide normal slice reference");
      force dut.alu_recompute = 1;
      #1;
      // Selecting diagnostic arithmetic alone does not enter controller recovery.
      // Output masking is checked separately by the injected-fault cases.
      check(dut.shift_result(dut.shift_raw[0], 1, w64) == shift_ref(a, amount, mode, w64, 0),
            "wide shifted diagnostic relation");
      release dut.alu_recompute;
    end
    w64 = 0;
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
      alu_run();
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
      alu_run();
      check(result == ((a >> amount) | (a << ((N - amount) % N))), "ROR ring reference");
      funct3 = 1;
      alu_run();
      check(result == ((a << amount) | (a >> ((N - amount) % N))), "ROL ring reference");
    end
    w64 = 1;
    foreach (vectors[i])
    for (int amount = 0; amount < N; amount++) begin
      a = vectors[i];
      b = N'(amount);
      rotated_word = (a[31:0] >> (amount & 31)) | (a[31:0] << ((32 - (amount & 31)) % 32));
      funct3 = 5;
      alu_run();
      check(result == N'($signed(rotated_word)), "RORW masked ring reference");
      rotated_word = (a[31:0] << (amount & 31)) | (a[31:0] >> ((32 - (amount & 31)) % 32));
      funct3 = 1;
      alu_run();
      check(result == N'($signed(rotated_word)), "ROLW masked ring reference");
    end
    w64 = 0;
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
      persistent_case(OP_SUBW, CH_RESULT, 0, 2'(replica_id), 0);
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
      repeat (THRESHOLD + 1) alu_eval();
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
    repeat (THRESHOLD + 1) alu_eval();
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
    clock_edge();
    check(dut.alu_capture_normal && !dut.cmp_capture_normal, "independent first ALU capture pulse");
    clock_edge();
    @(negedge clk);
    bit_index = 3;
    repeat (THRESHOLD - 1) alu_eval();
    check(dut.normal_arith[0] == {1'b0, (a + b) | N'(1)}, "first snapshot survives changed retry fault");
    alu_eval();  // the diagnosis
    alu_eval();  // the operation again, on the replica it selected
    check(pe_primary && !unresolved && result == a + b, "changed retry fault still selects healthy replica");
    // Flush cancels an in-flight comparison diagnosis as well as isolation.
    reset_case();
    set_operation(OP_ADD);
    channel = 2'(CH_CMP);
    target = 1;
    kind = 0;
    bit_index = 0;
    fi_enable = 1;
    alu_eval();
    @(negedge clk);
    flush = 1;
    fi_enable = 0;
    clock_edge();
    check(!unresolved && dut.normal_cmp[0] == '0, "flush cancels in-flight diagnosis and snapshots");
    @(negedge clk);
    flush = 0;
    alu_eval();
    check(!stall && !unresolved && result == a + b, "operation completes cleanly after the flush");
    // Range checks and reserved encodings are no-ops, including narrower channels.
    reset_case();
    set_operation(OP_ADD);
    fi_enable = 1;
    target = 3;
    for (int ch = 0; ch < 4; ch++) begin
      channel = 2'(ch);
      kind = 3;
      bit_index = 0;
      alu_run();
      check(!stall && result == a + b, "reserved kind no-op");
      if (ch != CH_RESULT) begin  // All result-channel indices are valid for power-of-two XLEN.
        kind = 0;
        bit_index = $clog2(N + 2)'((ch == CH_SHIFT) ? N + 2 : N + 1);
        alu_run();
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
    clock_edge();
    check(!stall && !dut.cmp_capture_normal, "invalid execute instruction cannot capture");
    clock_edge();
    valid = 1;
    alu_load();
    clock_edge();
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
      repeat (THRESHOLD + 1) alu_eval();
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
    mul_transient("MUL transient");
    mul_persistent("MUL persistent");
    div_transient(0, "DIV quotient transient");
    div_transient(1, "DIV remainder transient");
    div_persistent(0, "DIV quotient persistent");
    div_persistent(1, "DIV remainder persistent");
    $display("PASS ft_recompute_fault_tb XLEN=%0d threshold=%0d checks=%0d", N, THRESHOLD, checks);
    $finish;
  end
  initial begin
    #1000000;
    $fatal(1, "testbench timeout");
  end
endmodule
