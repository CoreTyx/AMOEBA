// Independent core integration regression: tiny ROM, real pipeline/CSR/trap
// machinery, private directed injector forces, and the shared runtime enable.
// Testbench clocks/scoreboards deliberately use blocking assignments.
/* verilator lint_off BLKSEQ */
/* verilator lint_off SYNCASYNCNET */
module ft_core_fault_tb;
  logic clk = 0, rst = 1;
  always #5 clk = ~clk;
  logic [63:0] mem_addr, mem_rdata, mem_wdata;
  logic [7:0] mem_rmask, mem_wmask;
  logic mem_resp;
  logic monitor_valid, monitor_trap;
  logic [63:0] monitor_pc_rdata, monitor_pc_wdata, monitor_rd_wdata;
  logic [4:0] monitor_rd_addr;
  logic [31:0] rom[256];
  logic [63:0] regs[32];
  logic mul_fi_enable = 0;
  logic [1:0] mul_fi_target = 1, mul_fi_kind = 0;
  logic [6:0] mul_fi_bit = 0;
  logic div_fi_enable = 0, div_fi_channel = 0;
  logic [1:0] div_fi_target = 1, div_fi_kind = 0;
  logic [5:0] div_fi_bit = 0;
  logic fault_inject = 0, directed = 1;
  logic fi_enable = 0;
  logic [1:0] fi_target = 1, fi_kind = 0, fi_channel = 0;
  logic [6:0] fi_bit = 0;

  // Stable scenario IDs keep diagnostics comparable across formatting changes.
  localparam int SC_HEALTHY = 0;
  localparam int SC_ALU_ISOLATION = 1;
  localparam int SC_CMP_ISOLATION = 2;
  localparam int SC_BNE_TRAP = 3;
  localparam int SC_BGE_TRAP = 4;
  localparam int SC_ALU_TRANSIENT = 5;
  localparam int SC_ADDRESS_ISOLATION = 6;
  localparam int SC_MUL_TRAP = 7;
  localparam int SC_MUL_TRANSIENT = 8;
  localparam int SC_DIV_QUOT_TRAP = 9;
  localparam int SC_DIV_TRANSIENT = 10;
  localparam int SC_DIV_REM_TRAP = 11;
  localparam int SC_CMP_BACKPRESSURE = 12;
  localparam int SC_ALU_BACKPRESSURE = 13;
  localparam int SC_MUL_BACKPRESSURE = 14;
  localparam int SC_DIV_BACKPRESSURE = 15;
  localparam int SC_SHARED_INJECTION = 16;
  localparam int SC_LATE_DIV_INJECTION = 17;
  localparam int SC_LATE_REM_INJECTION = 18;
  localparam int SC_LATE_DIV_BACKPRESSURE = 19;
  localparam int SC_LATE_REM_BACKPRESSURE = 20;
  localparam int SC_FAULT_CONTROL = 21;
  localparam int SCENARIO_COUNT = 22;
  int control_reads;

  int checks = 0, scenario, held_cycles, retired_branches, trap_count;
  logic injected, finished, held_last;
  int backpressure_cycles;
  logic backpressure_started;
  logic [63:0] held_pc;
  localparam logic [63:0] BASE = 64'h80000000, BRANCH_PC = BASE + 28;

  logic probe_csr = 0, probe_ret = 0, probe_trap = 0, probe_wfi = 0, probe_pending = 0;
  logic probe_stall_w, probe_flush_e;
  // Directly exercise older-flush priority, including interrupted WFI, whose
  // trap intentionally preserves W while clearing the younger stages.
    hazard flush_priority_probe (
      .BPWrongE(1'b0),
      .CSRWriteFenceM(probe_csr),
      .RetM(probe_ret),
      .TrapM(probe_trap),
      .StructuralStallD(1'b0),
      .LSUStallM(1'b0),
      .IFUStallF(1'b0),
      .FPUStallD(1'b0),
      .ExternalStall(1'b0),
      .DivBusyE(1'b0),
      .FDivBusyE(1'b0),
      .FTStall(1'b1),
      .wfiM(probe_wfi),
      .IntPendingM(probe_pending),
      .InjectD(1'b0),
      .StallF(),
      .StallD(),
      .StallE(),
      .StallM(),
      .StallW(probe_stall_w),
      .FlushD(),
      .FlushE(probe_flush_e),
      .FlushM(),
      .FlushW()
  );

  // Only retirement fields needed by the independent scoreboard are connected.
  /* verilator lint_off PINMISSING */
    rv64_core_wrapper dut (
      .clk,
      .rst,
      .mem_addr,
      .mem_rmask,
      .mem_wmask,
      .mem_rdata,
      .mem_wdata,
      .mem_resp,
      .fault_inject,
      .monitor_valid,
      .monitor_trap,
      .monitor_pc_rdata,
      .monitor_pc_wdata,
      .monitor_rd_addr,
      .monitor_rd_wdata,
      .mstatus_rdata(64'b0),
      .misa_rdata(64'b0),
      .mie_rdata(64'b0),
      .mtvec_rdata(64'b0),
      .mscratch_rdata(64'b0),
      .mepc_rdata(64'b0),
      .mcause_rdata(64'b0),
      .mtval_rdata(64'b0),
      .mip_rdata(64'b0),
      .mcycle_rdata(64'b0),
      .minstret_rdata(64'b0)
  );
  /* verilator lint_on PINMISSING */
  // Directed cases override injector internals, without adding RTL test ports.
  // Releasing these forces exercises the shared enable and actual LFSRs.
  always @* begin
    if (directed) begin
      force dut.soc.core.ieu.dp.ftalu.replica[0].result_fi.inject_now = fi_enable & fi_target[0] & (fi_channel == 2'd0);
      force dut.soc.core.ieu.dp.ftalu.replica[0].result_fi.fi_bit = $clog2(64)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[0].result_fi.fi_kind = fi_kind;
      force dut.soc.core.ieu.dp.ftalu.replica[0].arith_fi.inject_now = fi_enable & fi_target[0] & (fi_channel == 2'd1);
      force dut.soc.core.ieu.dp.ftalu.replica[0].arith_fi.fi_bit = $clog2(64 + 1)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[0].arith_fi.fi_kind = fi_kind;
      force dut.soc.core.ieu.dp.ftalu.replica[0].shift_fi.inject_now = fi_enable & fi_target[0] & (fi_channel == 2'd2);
      force dut.soc.core.ieu.dp.ftalu.replica[0].shift_fi.fi_bit = $clog2(64 + 2)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[0].shift_fi.fi_kind = fi_kind;
      force dut.soc.core.ieu.dp.ftalu.replica[0].cmp_fi.inject_now = fi_enable & fi_target[0] & (fi_channel == 2'd3);
      force dut.soc.core.ieu.dp.ftalu.replica[0].cmp_fi.fi_bit = $clog2(64 + 1)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[0].cmp_fi.fi_kind = fi_kind;
      force dut.soc.core.ieu.dp.ftalu.replica[1].result_fi.inject_now = fi_enable & fi_target[1] & (fi_channel == 2'd0);
      force dut.soc.core.ieu.dp.ftalu.replica[1].result_fi.fi_bit = $clog2(64)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[1].result_fi.fi_kind = fi_kind;
      force dut.soc.core.ieu.dp.ftalu.replica[1].arith_fi.inject_now = fi_enable & fi_target[1] & (fi_channel == 2'd1);
      force dut.soc.core.ieu.dp.ftalu.replica[1].arith_fi.fi_bit = $clog2(64 + 1)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[1].arith_fi.fi_kind = fi_kind;
      force dut.soc.core.ieu.dp.ftalu.replica[1].shift_fi.inject_now = fi_enable & fi_target[1] & (fi_channel == 2'd2);
      force dut.soc.core.ieu.dp.ftalu.replica[1].shift_fi.fi_bit = $clog2(64 + 2)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[1].shift_fi.fi_kind = fi_kind;
      force dut.soc.core.ieu.dp.ftalu.replica[1].cmp_fi.inject_now = fi_enable & fi_target[1] & (fi_channel == 2'd3);
      force dut.soc.core.ieu.dp.ftalu.replica[1].cmp_fi.fi_bit = $clog2(64 + 1)'(fi_bit);
      force dut.soc.core.ieu.dp.ftalu.replica[1].cmp_fi.fi_kind = fi_kind;
      force dut.soc.core.mdu.mdu.ftmul.primary_fi.inject_now = mul_fi_enable & mul_fi_target[0];
      force dut.soc.core.mdu.mdu.ftmul.primary_fi.fi_bit = mul_fi_bit;
      force dut.soc.core.mdu.mdu.ftmul.primary_fi.fi_kind = mul_fi_kind;
      force dut.soc.core.mdu.mdu.ftmul.shadow_fi.inject_now = mul_fi_enable & mul_fi_target[1];
      force dut.soc.core.mdu.mdu.ftmul.shadow_fi.fi_bit = mul_fi_bit;
      force dut.soc.core.mdu.mdu.ftmul.shadow_fi.fi_kind = mul_fi_kind;
      force dut.soc.core.mdu.mdu.div.ftdiv.primary_quot_fi.inject_now = div_fi_enable & div_fi_target[0] &
          (div_fi_channel == 1'b0);
      force dut.soc.core.mdu.mdu.div.ftdiv.primary_quot_fi.fi_bit = div_fi_bit;
      force dut.soc.core.mdu.mdu.div.ftdiv.primary_quot_fi.fi_kind = div_fi_kind;
      force dut.soc.core.mdu.mdu.div.ftdiv.primary_rem_fi.inject_now = div_fi_enable & div_fi_target[0] &
          (div_fi_channel == 1'b1);
      force dut.soc.core.mdu.mdu.div.ftdiv.primary_rem_fi.fi_bit = div_fi_bit;
      force dut.soc.core.mdu.mdu.div.ftdiv.primary_rem_fi.fi_kind = div_fi_kind;
      force dut.soc.core.mdu.mdu.div.ftdiv.shadow_quot_fi.inject_now = div_fi_enable & div_fi_target[1] &
          (div_fi_channel == 1'b0);
      force dut.soc.core.mdu.mdu.div.ftdiv.shadow_quot_fi.fi_bit = div_fi_bit;
      force dut.soc.core.mdu.mdu.div.ftdiv.shadow_quot_fi.fi_kind = div_fi_kind;
      force dut.soc.core.mdu.mdu.div.ftdiv.shadow_rem_fi.inject_now = div_fi_enable & div_fi_target[1] &
          (div_fi_channel == 1'b1);
      force dut.soc.core.mdu.mdu.div.ftdiv.shadow_rem_fi.fi_bit = div_fi_bit;
      force dut.soc.core.mdu.mdu.div.ftdiv.shadow_rem_fi.fi_kind = div_fi_kind;
    end else begin
      release dut.soc.core.ieu.dp.ftalu.replica[0].result_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[0].result_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[0].result_fi.fi_kind;
      release dut.soc.core.ieu.dp.ftalu.replica[0].arith_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[0].arith_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[0].arith_fi.fi_kind;
      release dut.soc.core.ieu.dp.ftalu.replica[0].shift_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[0].shift_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[0].shift_fi.fi_kind;
      release dut.soc.core.ieu.dp.ftalu.replica[0].cmp_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[0].cmp_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[0].cmp_fi.fi_kind;
      release dut.soc.core.ieu.dp.ftalu.replica[1].result_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[1].result_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[1].result_fi.fi_kind;
      release dut.soc.core.ieu.dp.ftalu.replica[1].arith_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[1].arith_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[1].arith_fi.fi_kind;
      release dut.soc.core.ieu.dp.ftalu.replica[1].shift_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[1].shift_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[1].shift_fi.fi_kind;
      release dut.soc.core.ieu.dp.ftalu.replica[1].cmp_fi.inject_now;
      release dut.soc.core.ieu.dp.ftalu.replica[1].cmp_fi.fi_bit;
      release dut.soc.core.ieu.dp.ftalu.replica[1].cmp_fi.fi_kind;
      release dut.soc.core.mdu.mdu.ftmul.primary_fi.inject_now;
      release dut.soc.core.mdu.mdu.ftmul.primary_fi.fi_bit;
      release dut.soc.core.mdu.mdu.ftmul.primary_fi.fi_kind;
      release dut.soc.core.mdu.mdu.ftmul.shadow_fi.inject_now;
      release dut.soc.core.mdu.mdu.ftmul.shadow_fi.fi_bit;
      release dut.soc.core.mdu.mdu.ftmul.shadow_fi.fi_kind;
      release dut.soc.core.mdu.mdu.div.ftdiv.primary_quot_fi.inject_now;
      release dut.soc.core.mdu.mdu.div.ftdiv.primary_quot_fi.fi_bit;
      release dut.soc.core.mdu.mdu.div.ftdiv.primary_quot_fi.fi_kind;
      release dut.soc.core.mdu.mdu.div.ftdiv.primary_rem_fi.inject_now;
      release dut.soc.core.mdu.mdu.div.ftdiv.primary_rem_fi.fi_bit;
      release dut.soc.core.mdu.mdu.div.ftdiv.primary_rem_fi.fi_kind;
      release dut.soc.core.mdu.mdu.div.ftdiv.shadow_quot_fi.inject_now;
      release dut.soc.core.mdu.mdu.div.ftdiv.shadow_quot_fi.fi_bit;
      release dut.soc.core.mdu.mdu.div.ftdiv.shadow_quot_fi.fi_kind;
      release dut.soc.core.mdu.mdu.div.ftdiv.shadow_rem_fi.inject_now;
      release dut.soc.core.mdu.mdu.div.ftdiv.shadow_rem_fi.fi_bit;
      release dut.soc.core.mdu.mdu.div.ftdiv.shadow_rem_fi.fi_kind;
    end
  end
  always_comb begin
    mem_resp  = (|mem_rmask) | (|mem_wmask);
    mem_rdata = 0;
    if (mem_addr >= BASE && mem_addr < BASE + 1024)
      mem_rdata = {rom[int'((mem_addr-BASE)>>2)+1], rom[int'((mem_addr-BASE)>>2)]};
  end
  function automatic logic [31:0] addi(input int rd, rs1, imm);
    return {12'(imm), 5'(rs1), 3'b000, 5'(rd), 7'b0010011};
  endfunction
  function automatic logic [31:0] csr_read(input int rd, address);
    return {12'(address), 5'b0, 3'b010, 5'(rd), 7'b1110011};
  endfunction
  function automatic logic [31:0] branch(input int funct, rs1, rs2, displacement);
    logic [12:0] offset;
    offset = 13'(displacement);
    return {offset[12], offset[10:5], 5'(rs2), 5'(rs1), 3'(funct), offset[4:1], offset[11], 7'b1100011};
  endfunction
  function automatic logic mdu_case(input int test_case);
    return (test_case >= SC_MUL_TRAP && test_case <= SC_DIV_REM_TRAP) ||
        (test_case >= SC_MUL_BACKPRESSURE && test_case <= SC_DIV_BACKPRESSURE) ||
        (test_case >= SC_LATE_DIV_INJECTION && test_case <= SC_LATE_REM_BACKPRESSURE);
  endfunction
  function automatic logic trap_case(input int test_case);
    return test_case == SC_BNE_TRAP || test_case == SC_BGE_TRAP ||
        test_case == SC_MUL_TRAP || test_case == SC_DIV_QUOT_TRAP || test_case == SC_DIV_REM_TRAP ||
        (test_case >= SC_CMP_BACKPRESSURE && test_case <= SC_DIV_BACKPRESSURE);
  endfunction
  task automatic check(input logic condition, input string label_text);
    checks++;
    if (condition !== 1'b1) $fatal(1, "scenario=%0d %s at %0t", scenario, label_text, $time);
  endtask
  task automatic check_unit_enables(input logic [5:0] expected);
    check(dut.soc.core.ieu.dp.ftalu.replica[0].result_fi.fi_enable == expected[0], "unit gate: ieu.dp.ftalu.replica[0].result_fi.fi_enable");
    check(dut.soc.core.ieu.dp.ftalu.replica[1].result_fi.fi_enable == expected[0], "unit gate: ieu.dp.ftalu.replica[1].result_fi.fi_enable");
    check(dut.soc.core.ieu.dp.ftalu.replica[0].arith_fi.fi_enable == expected[0], "unit gate: ieu.dp.ftalu.replica[0].arith_fi.fi_enable");
    check(dut.soc.core.ieu.dp.ftalu.replica[1].arith_fi.fi_enable == expected[0], "unit gate: ieu.dp.ftalu.replica[1].arith_fi.fi_enable");
    check(dut.soc.core.ieu.dp.ftalu.replica[0].shift_fi.fi_enable == expected[0], "unit gate: ieu.dp.ftalu.replica[0].shift_fi.fi_enable");
    check(dut.soc.core.ieu.dp.ftalu.replica[1].shift_fi.fi_enable == expected[0], "unit gate: ieu.dp.ftalu.replica[1].shift_fi.fi_enable");
    check(dut.soc.core.ieu.dp.ftalu.replica[0].cmp_fi.fi_enable == expected[1], "unit gate: ieu.dp.ftalu.replica[0].cmp_fi.fi_enable");
    check(dut.soc.core.ieu.dp.ftalu.replica[1].cmp_fi.fi_enable == expected[1], "unit gate: ieu.dp.ftalu.replica[1].cmp_fi.fi_enable");
    check(dut.soc.core.mdu.mdu.ftmul.primary_fi.fi_enable == expected[2], "unit gate: mdu.mdu.ftmul.primary_fi.fi_enable");
    check(dut.soc.core.mdu.mdu.ftmul.shadow_fi.fi_enable == expected[2], "unit gate: mdu.mdu.ftmul.shadow_fi.fi_enable");
    check(dut.soc.core.mdu.mdu.div.ftdiv.primary_quot_fi.fi_enable == expected[3], "unit gate: mdu.mdu.div.ftdiv.primary_quot_fi.fi_enable");
    check(dut.soc.core.mdu.mdu.div.ftdiv.shadow_quot_fi.fi_enable == expected[3], "unit gate: mdu.mdu.div.ftdiv.shadow_quot_fi.fi_enable");
    check(dut.soc.core.mdu.mdu.div.ftdiv.primary_rem_fi.fi_enable == expected[3], "unit gate: mdu.mdu.div.ftdiv.primary_rem_fi.fi_enable");
    check(dut.soc.core.mdu.mdu.div.ftdiv.shadow_rem_fi.fi_enable == expected[3], "unit gate: mdu.mdu.div.ftdiv.shadow_rem_fi.fi_enable");
    check(dut.soc.core.ieu.dp.regf.inj1.inject_en == expected[4], "unit gate: ieu.dp.regf.inj1.inject_en");
    check(dut.soc.core.ieu.dp.regf.inj2.inject_en == expected[4], "unit gate: ieu.dp.regf.inj2.inject_en");
    check(dut.soc.core.ieu.dp.RD1EReg.inject_en == expected[5], "unit gate: ieu.dp.RD1EReg.inject_en");
    check(dut.soc.core.ieu.dp.RD2EReg.inject_en == expected[5], "unit gate: ieu.dp.RD2EReg.inject_en");
    check(dut.soc.core.ieu.dp.ImmExtEReg.inject_en == expected[5], "unit gate: ieu.dp.ImmExtEReg.inject_en");
    check(dut.soc.core.ieu.dp.SrcAMReg.inject_en == expected[5], "unit gate: ieu.dp.SrcAMReg.inject_en");
    check(dut.soc.core.ieu.dp.IEUResultMReg.inject_en == expected[5], "unit gate: ieu.dp.IEUResultMReg.inject_en");
    check(dut.soc.core.ieu.dp.WriteDataMReg.inject_en == expected[5], "unit gate: ieu.dp.WriteDataMReg.inject_en");
    check(dut.soc.core.ieu.dp.IFResultWReg.inject_en == expected[5], "unit gate: ieu.dp.IFResultWReg.inject_en");
  endtask

  task automatic load_program(input logic bge);
    foreach (rom[i]) rom[i] = 32'h00000013;
    rom[0]  = 32'h00000297;  // auipc t0,0
    rom[1]  = addi(5, 5, 256);
    rom[2]  = 32'h30529073;  // csrw mtvec,t0
    rom[3]  = addi(8, 0, 64);
    rom[4]  = addi(9, 0, 0);
    rom[5]  = addi(9, 9, 1);
    rom[6]  = addi(8, 8, -1);
    rom[7]  = branch(bge ? 5 : 1, 8, 0, -8);
    rom[8]  = addi(10, 0, 42);
    rom[9]  = csr_read(11, 'h7c2);
    rom[10] = 32'h0000006f;
    rom[64] = csr_read(12, 'h342);
    rom[65] = csr_read(13, 'h341);
    rom[66] = csr_read(14, 'h7c2);
    rom[67] = 32'h0000006f;
  endtask

  // Record architecturally committed register values, rather than calculating
  // expected behavior from the FT replica outputs.
  always @(posedge clk) begin
    if (rst) begin
      foreach (regs[i]) regs[i] = 0;
      retired_branches = 0;
      trap_count = 0;
      finished = 0;
      control_reads = 0;
    end else if (monitor_valid) begin
      if (monitor_rd_addr != 0 && !monitor_trap) regs[monitor_rd_addr] = monitor_rd_wdata;
      if (scenario == SC_FAULT_CONTROL && monitor_rd_addr == 10 && !monitor_trap) begin
        check(monitor_rd_wdata == ((control_reads == 0 || control_reads == 8) ? 63 :
              ((control_reads == 1) ? 0 : (1 << (control_reads - 2)))), "software byte readback of unit mask");
        control_reads++;
      end
      if (monitor_trap) begin
        trap_count++;
        check(monitor_pc_rdata == (mdu_case(scenario) ? BASE + 20 : BRANCH_PC),
              "fault trap retains original instruction PC");
      end
      if (!mdu_case(scenario) && monitor_pc_rdata == BRANCH_PC && !monitor_trap) retired_branches++;
      if (monitor_pc_rdata == ((scenario == SC_FAULT_CONTROL) ? BASE + 108 : (mdu_case(scenario) ? BASE + 28 : ((scenario == SC_SHARED_INJECTION) ? BASE + 44 : BASE + 40))) ||
              monitor_pc_rdata == BASE + 268)
        finished = 1;
    end
  end

  // Run every directed scenario and the shared-enable LFSR scenario.
  initial begin
    #1;
    check(probe_stall_w && !probe_flush_e, "FT holds without older flush");
    for (int cause = 0; cause < 4; cause++) begin
      probe_csr = (cause == 0);
      probe_ret = (cause == 1);
      probe_trap = (cause >= 2);
      probe_wfi = (cause == 3);
      probe_pending = (cause == 3);
      #1;
      check(!probe_stall_w && probe_flush_e, "older CSR/return/trap/WFI flush overrides FT hold");
    end
    for (scenario = SC_HEALTHY; scenario < SCENARIO_COUNT; scenario++) begin
      @(negedge clk);
      rst = 1;
      directed = (scenario != SC_SHARED_INJECTION && scenario != SC_FAULT_CONTROL);
      fault_inject = (scenario == SC_SHARED_INJECTION);
      fi_enable = 0;
      mul_fi_enable = 0;
      div_fi_enable = 0;
      force dut.soc.core.ExternalStall = 1'b0;
      backpressure_cycles  = 0;
      backpressure_started = 0;
      load_program(scenario == SC_BGE_TRAP);
      if (scenario == SC_SHARED_INJECTION) begin
        rom[3]  = addi(8, 0, 1024);  // run through several real injection periods
        rom[10] = csr_read(15, 'h7c0);
        rom[11] = 32'h0000006f;
      end
      if (mdu_case(scenario)) begin
        rom[3] = addi(8, 0, 13);
        rom[4] = addi(9, 0, 11);
        // mul/divu/remu a0,s0,s1
        rom[5] = {
          7'b0000001,
          5'd9,
          5'd8,
          3'((scenario == SC_MUL_TRAP || scenario == SC_MUL_TRANSIENT || scenario == SC_MUL_BACKPRESSURE) ?
             0 : ((scenario == SC_DIV_REM_TRAP || scenario == SC_LATE_REM_INJECTION ||
                   scenario == SC_LATE_REM_BACKPRESSURE) ? 7 : 5)),
          5'd10,
          7'b0110011
        };
        rom[6] = csr_read(11, 'h7c2);
        rom[7] = 32'h0000006f;
      end
      if (scenario == SC_FAULT_CONTROL) begin
        foreach (rom[i]) rom[i] = 32'h00000013;
        rom[0] = 32'h100702b7; // lui t0,0x10070
        rom[1] = addi(5, 5, 11);
        rom[2] = 32'h0002c503; // lbu a0,0(t0): reset mask
        for (int unit_index = 0; unit_index < 8; unit_index++) begin
          rom[3 + 3*unit_index] = addi(6, 0, (unit_index == 0) ? 0 : ((unit_index == 7) ? 63 : (1 << (unit_index-1))));
          rom[4 + 3*unit_index] = 32'h00628023; // sb t1,0(t0)
          rom[5 + 3*unit_index] = 32'h0002c503; // lbu a0,0(t0)
        end
        rom[27] = 32'h0000006f;
      end
      held_cycles = 0;
      injected = 0;
      held_last = 0;
      repeat (6) @(negedge clk);
      rst = 0;
      // Hang guard, not a performance check. The slowest scenario (SC_SHARED_INJECTION) needs ~3.1k
      // cycles on main and ~12.4k with swe-cache-ec's multi-cycle cache hits; 50k leaves headroom.
      for (int cycle = 0; cycle < 50000 && !finished; cycle++) begin
        @(negedge clk);
        if (!injected && scenario != SC_HEALTHY && scenario < SC_SHARED_INJECTION && !mdu_case(scenario) && dut.soc.core.InstrValidE && dut.soc.core.PCE == BRANCH_PC && dut.soc.core.ForwardedSrcAE == 8) begin
          // This loop has trained the predictor before diagnosis begins.
          check(!dut.soc.core.BPWrongE && dut.soc.core.PCSrcE, "faulted branch is predicted taken");
          check(dut.soc.core.ieu.dp.SrcAE == BRANCH_PC && dut.soc.core.ieu.dp.SrcBE == 64'hfffffffffffffff8,
                "branch target and comparison have independent operands");
          fi_target = (scenario == SC_CMP_ISOLATION) ? 2 : 1;
          fi_channel = (scenario == SC_CMP_ISOLATION || scenario == SC_BNE_TRAP || scenario == SC_BGE_TRAP ||
                        scenario == SC_CMP_BACKPRESSURE) ? 3 : ((scenario == SC_ADDRESS_ISOLATION) ? 1 : 0);
          fi_kind = (scenario == SC_ADDRESS_ISOLATION) ?
              1 : ((scenario == SC_BNE_TRAP || scenario == SC_BGE_TRAP || scenario == SC_ALU_TRANSIENT ||
                    scenario >= SC_CMP_BACKPRESSURE) ? 0 : 2);
          fi_bit = (scenario == SC_ADDRESS_ISOLATION) ? 64 : 0;
          fi_enable = 1;
          injected = 1;
          #1;
          check(dut.soc.core.FTStall, "directed injector fault reaches merged ALU/CMP");
        end
        if (!injected && scenario < SC_LATE_DIV_INJECTION && mdu_case(scenario) && dut.soc.core.InstrValidE && dut.soc.core.PCE == BASE + 20) begin
          if (scenario == SC_MUL_TRAP || scenario == SC_MUL_TRANSIENT || scenario == SC_MUL_BACKPRESSURE) begin
            mul_fi_enable = 1;
            mul_fi_target = (scenario == SC_MUL_TRANSIENT) ? 2 : 1;
            mul_fi_kind = (scenario == SC_MUL_TRANSIENT) ? 0 : 2;
            mul_fi_bit = (scenario == SC_MUL_TRANSIENT) ? 0 : 4;
          end else begin
            div_fi_enable = 1;
            div_fi_target = (scenario == SC_DIV_TRANSIENT) ? 2 : 1;
            div_fi_kind = (scenario == SC_DIV_TRANSIENT) ? 0 : 2;
            div_fi_bit = (scenario == SC_DIV_REM_TRAP || scenario == SC_DIV_TRANSIENT) ? 0 : 4;
            div_fi_channel = (scenario == SC_DIV_REM_TRAP);
          end
          injected = 1;
        end
        // The instruction has already passed its E-stage comparison. A later
        // injector event must not change the accepted M-stage result, including
        // when an unrelated stall extends its lifetime in M.
        if (!injected && scenario >= SC_LATE_DIV_INJECTION && scenario <= SC_LATE_REM_BACKPRESSURE && dut.soc.core.InstrValidM &&
            dut.soc.core.PCM == BASE + 20) begin
          div_fi_enable = 1;
          div_fi_target = 1;
          div_fi_kind = 2;
          div_fi_bit = 4;
          div_fi_channel = (scenario == SC_LATE_REM_INJECTION || scenario == SC_LATE_REM_BACKPRESSURE);
          injected = 1;
          if (scenario >= SC_LATE_DIV_BACKPRESSURE) begin
            force dut.soc.core.ExternalStall = 1'b1;
            backpressure_cycles = 4;
          end
        end
        // Stall independently of FT after diagnosis completes. Disabling the
        // fault prevents a new mismatch from hiding a lost terminal indication.
        if (scenario >= SC_CMP_BACKPRESSURE && scenario <= SC_DIV_BACKPRESSURE && !backpressure_started &&
            ((scenario == SC_MUL_BACKPRESSURE && dut.soc.core.FTUnresolvedM) ||
             (scenario == SC_DIV_BACKPRESSURE && dut.soc.core.mdu.mdu.div.ftdiv.unresolved) || (
             (scenario == SC_CMP_BACKPRESSURE || scenario == SC_ALU_BACKPRESSURE) && dut.soc.core.FTUnresolvedE))) begin
          force dut.soc.core.ExternalStall = 1'b1;
          fi_enable = 0;
          mul_fi_enable = 0;
          div_fi_enable = 0;
          backpressure_started = 1;
          backpressure_cycles = 4;
        end else if (backpressure_cycles > 0) begin
          if (scenario < SC_LATE_DIV_INJECTION)
            check(
                (scenario == SC_MUL_BACKPRESSURE) ? dut.soc.core.FTUnresolvedM :
                    ((scenario == SC_DIV_BACKPRESSURE) ? dut.soc.core.mdu.mdu.div.ftdiv.unresolved :
                     dut.soc.core.FTUnresolvedE),
                "terminal fault survives external stall");
          backpressure_cycles--;
          if (backpressure_cycles == 0) force dut.soc.core.ExternalStall = 1'b0;
        end
        if (scenario == SC_FAULT_CONTROL) begin
          fault_inject = cycle[0]; // verify the pin gates every programmed mask
          #1;
          check_unit_enables(dut.soc.FaultInjectMask & {6{fault_inject}});
        end
        #1;
        if (held_last) check(dut.soc.core.PCE == held_pc, "execute PC holds across FT stall edge");
        if (dut.soc.core.FTStall && !dut.soc.core.TrapM) begin
          held_cycles++;
          check(
              dut.soc.core.StallF && dut.soc.core.StallD && dut.soc.core.StallE && dut.soc.core.StallM &&
                  dut.soc.core.StallW,
              "all stages held");
          check(!dut.soc.core.PCSrcE && !dut.soc.core.FlushE,
                "diagnosis cannot redirect or prediction-flush held branch");
          check(!monitor_valid, "no retirement while diagnosis stalls");
        end
        if (dut.soc.core.FTUnresolvedE || dut.soc.core.FTUnresolvedM)
          check(!dut.soc.core.PCSrcE, "unresolved branch cannot redirect");
        if (scenario == SC_ALU_TRANSIENT && held_cycles == 2) fi_enable = 0;
        if (scenario == SC_MUL_TRANSIENT && held_cycles == 2) mul_fi_enable = 0;
        if (scenario == SC_DIV_TRANSIENT && held_cycles == 2) div_fi_enable = 0;
        // Persistent fault is disabled after its diagnosed transaction leaves E;
        // isolation/CSR status must survive independently of injector enable.
        if (injected && !dut.soc.core.FTStall && dut.soc.core.PCE != BRANCH_PC) fi_enable = 0;
        #1;
        held_last = dut.soc.core.FTStall && dut.soc.core.StallE;
        held_pc   = dut.soc.core.PCE;
      end
      check(finished, "program reaches architectural completion");
      if (scenario != SC_HEALTHY && scenario != SC_SHARED_INJECTION && scenario < SC_LATE_DIV_INJECTION)
        check(injected && held_cycles > 0, "runtime fault actually exercised");
      if (scenario >= SC_CMP_BACKPRESSURE && scenario <= SC_DIV_BACKPRESSURE)
        check(backpressure_started, "terminal backpressure exercised");
      if (trap_case(scenario)) begin
        check(trap_count == 1 && regs[12] == 16 && regs[13] == (mdu_case(scenario) ? BASE + 20 : BRANCH_PC),
              "precise machine cause-16 trap");
        check(regs[14][6] && regs[10] == 0, "unresolved sticky status and no younger retirement");
      end else if (scenario == SC_FAULT_CONTROL) begin
        check(trap_count == 0 && control_reads == 9 && regs[10] == 63,
              "byte stores/loads control all six units without traps");
      end else if (scenario >= SC_LATE_DIV_INJECTION) begin
        check(
            injected && trap_count == 0 && regs[11] == 0 &&
                regs[10] == ((scenario == SC_LATE_REM_INJECTION || scenario == SC_LATE_REM_BACKPRESSURE) ? 2 : 1),
            "accepted DIV/REM result survives late injection and M-stage stalls");
      end else if (scenario == SC_MUL_TRANSIENT) begin
        check(trap_count == 0 && regs[10] == 143 && regs[11] == 0, "core MUL transient retires correct product");
      end else if (scenario == SC_DIV_TRANSIENT) begin
        check(trap_count == 0 && regs[10] == 1 && regs[11] == 0,
              "core DIV transient retries original forwarded operands");
      end else if (scenario == SC_SHARED_INJECTION) begin
        check(held_cycles > 0, "shared enable exercises actual LFSR faults");
        check(trap_count == 0 && regs[10] == 42 && regs[9] == 1024 && retired_branches == 1024,
              "periodic FT injection recovers and retires the loop correctly");
        check(regs[15][4] && regs[11] == 0, "ECC SEC appears in MSECFAULT while FTSTATUS contains only ft_* status");
      end else begin
        check(trap_count == 0 && regs[10] == 42 && regs[9] == 64 && retired_branches == 64,
              "correct branch retirement and loop result");
        if (scenario == SC_ALU_ISOLATION || scenario == SC_ADDRESS_ISOLATION)
          check(regs[11][0], "ALU sticky isolation CSR bit");
        if (scenario == SC_CMP_ISOLATION) check(regs[11][1] && !regs[11][0], "separate CMP sticky isolation CSR bit");
        if (scenario == SC_HEALTHY || scenario == SC_ALU_TRANSIENT)
          check(regs[11] == 0, "healthy/transient status unchanged");
      end
      $display("PASS core scenario=%0d held=%0d branches=%0d traps=%0d status=%h", scenario, held_cycles,
               retired_branches, trap_count, regs[trap_case(scenario)?14 : 11]);
    end
    $display("PASS ft_core_fault_tb checks=%0d", checks);
    $finish;
  end
endmodule
