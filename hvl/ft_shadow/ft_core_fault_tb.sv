// Independent core integration regression: tiny ROM, real pipeline/CSR/trap
// machinery, and only the intentionally core-local runtime injection hooks.
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
  logic fi_enable = 0;
  logic [1:0] fi_target = 1, fi_kind = 0, fi_channel = 0;
  logic [6:0] fi_bit = 0;
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
      .ecc_inject_en(1'b0),
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
  assign dut.soc.core.ALUFiEnable = fi_enable;
  assign dut.soc.core.ALUFiTarget = fi_target;
  assign dut.soc.core.ALUFiKind = fi_kind;
  assign dut.soc.core.ALUFiChannel = fi_channel;
  assign dut.soc.core.ALUFiBit = fi_bit;
  assign dut.soc.core.MULFiEnable = mul_fi_enable;
  assign dut.soc.core.MULFiTarget = mul_fi_target;
  assign dut.soc.core.MULFiKind = mul_fi_kind;
  assign dut.soc.core.MULFiBit = mul_fi_bit;
  assign dut.soc.core.DIVFiEnable = div_fi_enable;
  assign dut.soc.core.DIVFiTarget = div_fi_target;
  assign dut.soc.core.DIVFiKind = div_fi_kind;
  assign dut.soc.core.DIVFiBit = div_fi_bit;
  assign dut.soc.core.DIVFiChannel = div_fi_channel;
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
    return {
      offset[12], offset[10:5], 5'(rs2), 5'(rs1), 3'(funct), offset[4:1], offset[11], 7'b1100011
    };
  endfunction
  function automatic logic mdu_case(input int test_case);
    return (test_case >= 7 && test_case <= 11) || test_case >= 14;
  endfunction
  function automatic logic trap_case(input int test_case);
    return test_case == 3 || test_case == 4 || test_case == 7 ||
           test_case == 9 || test_case == 11 || test_case >= 12;
  endfunction
  task automatic check(input logic condition, input string label_text);
    checks++;
    if (condition !== 1'b1) $fatal(1, "scenario=%0d %s at %0t", scenario, label_text, $time);
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
    end else if (monitor_valid) begin
      if (monitor_rd_addr != 0 && !monitor_trap) regs[monitor_rd_addr] = monitor_rd_wdata;
      if (monitor_trap) begin
        trap_count++;
        check(monitor_pc_rdata == (mdu_case(scenario) ? BASE + 20 : BRANCH_PC),
              "fault trap retains original instruction PC");
      end
      if (!mdu_case(scenario) && monitor_pc_rdata == BRANCH_PC && !monitor_trap)
        retired_branches++;
      if(monitor_pc_rdata==(mdu_case(scenario)?BASE+28:BASE+40) || monitor_pc_rdata==BASE+268)
        finished = 1;
    end
  end

  // 0 healthy, 1 ALU isolation, 2 CMP isolation, 3/4 BNE/BGE trap,
  // 5 ALU transient, 6 address isolation, 7 MUL trap, 8 MUL transient,
  // 9 DIV quotient trap, 10 DIV transient, 11 DIV remainder trap,
  // 12/13 CMP/ALU terminal backpressure, 14/15 MUL/DIV terminal backpressure.
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
    for (scenario = 0; scenario < 16; scenario++) begin
      @(negedge clk);
      rst = 1;
      fi_enable = 0;
      mul_fi_enable = 0;
      div_fi_enable = 0;
      force dut.soc.core.ExternalStall = 1'b0;
      backpressure_cycles = 0;
      backpressure_started = 0;
      load_program(scenario == 4);
      if (mdu_case(scenario)) begin
        rom[3] = addi(8, 0, 13);
        rom[4] = addi(9, 0, 11);
        // mul/divu/remu a0,s0,s1
        rom[5] = {
          7'b0000001, 5'd9, 5'd8,
          3'((scenario == 7 || scenario == 8 || scenario == 14) ? 0 : ((scenario == 11) ? 7 : 5)),
          5'd10, 7'b0110011
        };
        rom[6] = csr_read(11, 'h7c2);
        rom[7] = 32'h0000006f;
      end
      held_cycles = 0;
      injected = 0;
      held_last = 0;
      repeat (6) @(negedge clk);
      rst = 0;
      for (int cycle = 0; cycle < 10000 && !finished; cycle++) begin
        @(negedge clk);
        if(!injected && scenario!=0 && !mdu_case(scenario) && dut.soc.core.InstrValidE &&
           dut.soc.core.PCE==BRANCH_PC && dut.soc.core.ForwardedSrcAE==8) begin
          // This loop has trained the predictor before diagnosis begins.
          check(!dut.soc.core.BPWrongE && dut.soc.core.PCSrcE, "faulted branch is predicted taken");
          check(
              dut.soc.core.ieu.dp.SrcAE==BRANCH_PC && dut.soc.core.ieu.dp.SrcBE==64'hfffffffffffffff8,
              "branch target and comparison have independent operands");
          fi_target = (scenario == 2) ? 2 : 1;
          fi_channel=(scenario==2 || scenario==3 || scenario==4 || scenario==12)?3:((scenario==6)?1:0);
          fi_kind=(scenario==6)?1:((scenario==3 || scenario==4 || scenario==5 || scenario>=12)?0:2);
          fi_bit = (scenario == 6) ? 64 : 0;
          fi_enable = 1;
          injected = 1;
          #1;
          check(dut.soc.core.FTStall, "core hook reaches merged ALU/CMP");
        end
        if(!injected && mdu_case(scenario) && dut.soc.core.InstrValidE && dut.soc.core.PCE==BASE+20) begin
          if (scenario == 7 || scenario == 8 || scenario == 14) begin
            mul_fi_enable = 1;
            mul_fi_target = (scenario == 8) ? 2 : 1;
            mul_fi_kind = (scenario == 8) ? 0 : 2;
            mul_fi_bit = (scenario == 8) ? 0 : 4;
          end else begin
            div_fi_enable = 1;
            div_fi_target = (scenario == 10) ? 2 : 1;
            div_fi_kind = (scenario == 10) ? 0 : 2;
            div_fi_bit = (scenario == 11 || scenario == 10) ? 0 : 4;
            div_fi_channel = (scenario == 11);
          end
          injected = 1;
        end
        // Stall independently of FT after diagnosis completes. Disabling the
        // fault prevents a new mismatch from hiding a lost terminal indication.
        if (scenario >= 12 && !backpressure_started &&
            ((scenario == 14 && dut.soc.core.FTUnresolvedM) ||
             (scenario == 15 && dut.soc.core.mdu.mdu.div.ftdiv.unresolved) ||
             ((scenario == 12 || scenario == 13) && dut.soc.core.FTUnresolvedE))) begin
          force dut.soc.core.ExternalStall = 1'b1;
          fi_enable = 0;
          mul_fi_enable = 0;
          div_fi_enable = 0;
          backpressure_started = 1;
          backpressure_cycles = 4;
        end else if (backpressure_cycles > 0) begin
          check((scenario == 14) ? dut.soc.core.FTUnresolvedM :
                ((scenario == 15) ? dut.soc.core.mdu.mdu.div.ftdiv.unresolved :
                 dut.soc.core.FTUnresolvedE), "terminal fault survives external stall");
          backpressure_cycles--;
          if (backpressure_cycles == 0) force dut.soc.core.ExternalStall = 1'b0;
        end
        #1;
        if (held_last) check(dut.soc.core.PCE == held_pc, "execute PC holds across FT stall edge");
        if (dut.soc.core.FTStall && !dut.soc.core.TrapM) begin
          held_cycles++;
          check(
              dut.soc.core.StallF && dut.soc.core.StallD && dut.soc.core.StallE && dut.soc.core.StallM && dut.soc.core.StallW,
              "all stages held");
          check(!dut.soc.core.PCSrcE && !dut.soc.core.FlushE,
                "diagnosis cannot redirect or prediction-flush held branch");
          check(!monitor_valid, "no retirement while diagnosis stalls");
        end
        if (dut.soc.core.FTUnresolvedE || dut.soc.core.FTUnresolvedM)
          check(!dut.soc.core.PCSrcE, "unresolved branch cannot redirect");
        if (scenario == 5 && held_cycles == 2) fi_enable = 0;
        if (scenario == 8 && held_cycles == 2) mul_fi_enable = 0;
        if (scenario == 10 && held_cycles == 2) div_fi_enable = 0;
        // Persistent fault is disabled after its diagnosed transaction leaves E;
        // isolation/CSR status must survive independently of injector enable.
        if (injected && !dut.soc.core.FTStall && dut.soc.core.PCE != BRANCH_PC) fi_enable = 0;
        #1;
        held_last = dut.soc.core.FTStall && dut.soc.core.StallE;
        held_pc   = dut.soc.core.PCE;
      end
      check(finished, "program reaches architectural completion");
      if (scenario != 0) check(injected && held_cycles > 0, "runtime fault actually exercised");
      if (scenario >= 12) check(backpressure_started, "terminal backpressure exercised");
      if (trap_case(scenario)) begin
        check(
            trap_count==1 && regs[12]==16 && regs[13]==(mdu_case(scenario)?BASE+20:BRANCH_PC),
            "precise machine cause-16 trap");
        check(regs[14][6] && regs[10] == 0, "unresolved sticky status and no younger retirement");
      end else if (scenario == 8) begin
        check(trap_count == 0 && regs[10] == 143 && regs[11] == 0,
              "core MUL transient retires correct product");
      end else if (scenario == 10) begin
        check(trap_count == 0 && regs[10] == 1 && regs[11] == 0,
              "core DIV transient retries original forwarded operands");
      end else begin
        check(trap_count == 0 && regs[10] == 42 && regs[9] == 64 && retired_branches == 64,
              "correct branch retirement and loop result");
        if (scenario == 1 || scenario == 6) check(regs[11][0], "ALU sticky isolation CSR bit");
        if (scenario == 2)
          check(regs[11][1] && !regs[11][0], "separate CMP sticky isolation CSR bit");
        if (scenario == 0 || scenario == 5)
          check(regs[11] == 0, "healthy/transient status unchanged");
      end
      $display("PASS core scenario=%0d held=%0d branches=%0d traps=%0d status=%h", scenario,
               held_cycles, retired_branches, trap_count,
               regs[trap_case(scenario)?14 : 11]);
    end
    $display("PASS ft_core_fault_tb checks=%0d", checks);
    $finish;
  end
endmodule
