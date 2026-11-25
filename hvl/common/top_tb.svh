  longint timeout;
    initial begin
        $value$plusargs("TIMEOUT_ECE411=%d", timeout);
    end

    localparam int CHANNELS = 1;
    localparam int XLEN = 64;
    localparam int ILEN = 32;

    // RISC-V HTif tohost address — fixed in both bin/link.ld (bare-metal) and
    // freertos_wally.ld (FreeRTOS) at 0x80800000.  All test programs write
    // here on exit; the testbench fires $finish or $fatal depending on code.
    // +TOHOST_ADDR_ECE411=<hex> overrides it for programs with their own
    // layout (riscv-tests place .tohost right after .text.init).
    longint unsigned TOHOST_ADDR = 64'h8080_0000;
    initial begin
        longint unsigned a;
        if ($value$plusargs("TOHOST_ADDR_ECE411=%h", a)) TOHOST_ADDR = a;
    end

    mem_itf_w_mask #(
        .CHANNELS(1),
        .AWIDTH(XLEN),
        .DWIDTH(XLEN)
    ) mem_itf(.*);

    simple_memory_w_mask simple_memory(.itf(mem_itf));

    mon_itf #(
        .CHANNELS(CHANNELS),
        .XLEN(XLEN),
        .ILEN(ILEN)
    ) mon_itf(.*);

    monitor #(
        .CHANNELS(CHANNELS),
        .XLEN(XLEN),
        .ILEN(ILEN)
    ) monitor(.itf(mon_itf));

    // ECC and FT error injection enable: 1 when built with +define+ECE411_SIM_INJECT,
    // 0 otherwise.  Wired as a real port so DFT can substitute a test controller.
`ifdef ECE411_SIM_INJECT
    logic fault_inject = 1'b1;
`else
    logic fault_inject = 1'b0;
`endif

`ifdef ECE411_SIM_INJECT
    // The unit mask resets to 0 on silicon; built with ECE411_SIM_INJECT it resets with the six
    // core units armed (fault_inject_apb.sv).  The ECC programs pass whether or not anything was
    // injected, so make sure it was armed.
  `ifdef ECE411_DUT_FORTE
    `define FICONTROL dut.top.chip.soc.uncore.faultcontrol
  `else
    `define FICONTROL dut.soc.uncoregen.uncore.faultcontrol
  `endif
    logic [1:0] fi_out_of_reset = '1;  // only a real reset (PRESETn low, then high) is checked
    always @(posedge clk) begin
      fi_out_of_reset <= {fi_out_of_reset[0], `FICONTROL.PRESETn};
      if (fi_out_of_reset == 2'b01 && `FICONTROL.FaultInjectMask != 8'h3f)
        $fatal(1, "fault-injection units not armed out of reset: mask %h", `FICONTROL.FaultInjectMask);
    end

    // Arm more injection units mid-run, once the console prints a given line:
    //   +FI_ARM_MASK_ECE411=<hex>     units to add to FI_CONTROL (80 = cache DED, 40 = cache SEC)
    //   +FI_ARM_ON_UART_ECE411=<pat>  '|'-separated patterns, matched like +UART_PASS_ECE411
    // The cache units cannot be armed from reset: an injected DED lands within a few hundred
    // cycles, before OpenSBI has a trap handler.  The units go into fault_inject_apb's
    // simulation-only SimArmMask, which keeps them set even if software rewrites
    // FI_CONTROL.  Used by `make -C sim linux_failstop_cache_ded`.
    string      fi_arm_on_uart = "";
    logic [7:0] fi_arm_mask    = '0;
    bit         fi_arm_req     = 1'b0;   // set by uart_flush_line on a matching line
    bit         fi_armed       = 1'b0;
    initial begin
      void'($value$plusargs("FI_ARM_ON_UART_ECE411=%s", fi_arm_on_uart));
      void'($value$plusargs("FI_ARM_MASK_ECE411=%h", fi_arm_mask));
    end
    always @(posedge clk) begin
      if (fi_arm_req && !fi_armed) begin
        fi_armed               <= 1'b1;
        `FICONTROL.SimArmMask  <= fi_arm_mask;
        $display("TB: fault injection armed at %0t: adding units %h to FI_CONTROL", $time, fi_arm_mask);
      end
    end
`endif

`ifdef ECE411_DUT_FORTE
    forte_dut_wrap dut (
`else
    rv64_core_wrapper dut (
`endif
        .clk      (clk),
        .rst      (rst),
        .mem_addr  (mem_itf.addr [0]),
        .mem_rmask (mem_itf.rmask[0]),
        .mem_wmask (mem_itf.wmask[0]),
        .mem_rdata (mem_itf.rdata[0]),
        .mem_wdata (mem_itf.wdata[0]),
        .mem_resp  (mem_itf.resp [0]),
        .fault_inject (fault_inject)
    );

    `include "rvfi_reference.svh"

    // ---- where the DUT keeps its RVFI state -------------------------------
    // The two DUTs put the same signals in different places, and several blocks
    // below reach in by hierarchical reference.  rv64_core_wrapper has the RVFI
    // taps INLINE and the SoC one level down; forte_dut_wrap instantiates
    // rvfi_tap as a child and the SoC three levels down, inside the chip and the
    // pad ring.  Spelling either hierarchy literally gives a block that compiles
    // for exactly one DUT and fails to elaborate for the other -- which is what
    // ECE411_RETIRE_TRACE (legacy-only, on dut.DummyW) and the ECE411_LINUX
    // misaligned-access flag (forte-only, on dut.tap.Funct3W) each did.
    //
    // RT_TAP resolves to whatever holds the RVFI pipeline registers.  Reading a
    // module's input ports by hierarchical reference is legal, so the same names
    // work whether they are locals (legacy) or ports (forte).
`ifdef ECE411_DUT_FORTE
    `define RT_TAP  dut.tap
    `define RT_CORE dut.top.chip.soc.core
`else
    `define RT_TAP  dut
    `define RT_CORE dut.soc.core
`endif

`ifdef ECE411_SIM_INJECT
    // +FI_ONESHOT_ECE411: after arming, stop both caches' injectors (cachefi.sv
    // SimCancel: no new events, pending flips dropped) as soon as the first D$
    // uncorrectable-error trap (cause 20 or 21) is taken.  The injector arms a tag flip and
    // a line flip every 512 cycles; left running it keeps landing DEDs in the
    // firmware's own stack while its trap entry is still saving registers, and that
    // nested trap corrupts the entry (mscratch already swapped) -- a test artefact,
    // not something two independent upsets would do within a few hundred cycles.
    bit fi_oneshot  = 1'b0;
    bit fi_stopped  = 1'b0;
    initial fi_oneshot = $test$plusargs("FI_ONESHOT_ECE411");
    always @(posedge clk) begin
      if (fi_oneshot && fi_armed && !fi_stopped && `RT_CORE.DCacheEccDedTrapTakenM) begin
        fi_stopped <= 1'b1;
        `RT_CORE.lsu.bus.dcache.dcache.faultinject.SimCancel <= 1'b1;
        `RT_CORE.ifu.bus.icache.icache.faultinject.SimCancel <= 1'b1;
        $display("TB: cause-20/21 trap taken at %0t (PC %h): cache injection stopped",
                 $time, `RT_CORE.priv.priv.PCM);
      end
    end
`endif

`ifdef ECE411_RETIRE_TRACE
    // ---- retirement trace (AMOEBA random instruction insertion) ------------
    // One line per instruction that actually retires, real and dummy interleaved
    // in retirement order.  Writeback is the only place both streams appear
    // together and the only place flushes have already been filtered out:
    // anything killed by a branch mispredict or a trap never reaches W, so it is
    // never printed.
    //
    // The core's own InstrD/InstrM pipeline never carries a dummy -- the injection
    // mux lives inside the IEU, and the IFU keeps piping the real instruction that
    // is being held in Decode -- so the issued encoding is pipelined separately
    // here, mirroring the enables and clears of the wrapper's M->W registers.
    // Compressed instructions therefore appear in expanded 32-bit form and will
    // not match the .dis byte for byte.
    logic [31:0] TrcInstrE, TrcInstrM, TrcInstrW;
    logic [63:0] TrcRetireCtr;

    always_ff @(posedge clk) begin
        if (rst) begin
            TrcInstrE <= '0; TrcInstrM <= '0; TrcInstrW <= '0;
            TrcRetireCtr <= '0;
        end else begin
            if (!`RT_TAP.StallE) TrcInstrE <= `RT_TAP.FlushE ? '0 : `RT_CORE.ieu.InstrDMux;
            if (!`RT_TAP.StallM) TrcInstrM <= `RT_TAP.FlushM ? '0 : TrcInstrE;
            if (!`RT_TAP.StallW) TrcInstrW <= (`RT_TAP.FlushW & ~`RT_TAP.TrapM) ? '0 : TrcInstrM;

            // Reads the pre-edge Writeback values, i.e. the instruction retiring now.
            if (!`RT_TAP.StallW) begin
                if (`RT_TAP.DummyW) begin
                    TrcRetireCtr <= TrcRetireCtr + 64'd1;
                    $display("[retire] %5d DUMMY               %08h  rs1=x%0d rs2=x%0d -> p%0d",
                             TrcRetireCtr, TrcInstrW, TrcInstrW[19:15], TrcInstrW[24:20],
                             `RT_CORE.ieu.c.DummySelW ? 33 : 32);
                end else if (`RT_TAP.InstrValidW && (|`RT_TAP.PCW)) begin
                    TrcRetireCtr <= TrcRetireCtr + 64'd1;
                    $display("[retire] %5d real  pc=%08h  %08h  rd=x%0d rs1=x%0d rs2=x%0d",
                             TrcRetireCtr, `RT_TAP.PCW[31:0], TrcInstrW,
                             TrcInstrW[11:7], TrcInstrW[19:15], TrcInstrW[24:20]);
                end
            end
        end
    end
`endif

    // ---- misaligned-access flag for the RVFI waiver ------------------------
    // Recomputed here rather than read from mon_itf.mem_addr, which the wrapper
    // has already masked to an 8-byte boundary and so cannot reveal
    // misalignment.  Funct3W[1:0] encodes the access size as log2(bytes).
`ifdef ECE411_LINUX
    wire [63:0] acc_size_mask = (64'd1 << `RT_TAP.Funct3W[1:0]) - 64'd1;
    assign mon_itf.mem_misaligned[0] = mon_itf.valid[0] && (|`RT_TAP.MemRWW) &&
                                       ((`RT_TAP.IEUAdrW & acc_size_mask) != 64'd0);
`else
    assign mon_itf.mem_misaligned[0] = 1'b0;
`endif

    // ---- access/page-fault flag for the RVFI waiver -------------------------
    // The trap cause is not part of the RVFI taps, so it is carried from Memory
    // to Writeback here, next to the wrapper's TrapW.  Causes 1, 5, 7 are the
    // instruction, load and store access faults; 12, 13, 15 the page faults.
    logic [4:0] TrapCauseW;
    always_ff @(posedge clk)
        if (!`RT_TAP.StallW) TrapCauseW <= `RT_CORE.priv.priv.CauseM;
    // Causes 0, 4 and 6 (misaligned fetch/load/store) are waived outside the
    // Linux build as well: ZICCLSM_SUPPORTED = 0 in pkg/config.vh, so a
    // misaligned access TRAPS, and the monitor's model of the trapped
    // instruction (rd/mem_rmask fields) does not match CVW's RVFI taps.
    //
    // Causes 2 and 3 (illegal instruction, breakpoint) are NOT waived: the
    // monitor is generated for the chip's own ISA (sim/Makefile RVFIMON_ISA =
    // rv64imac), so an encoding the core traps on is one the model traps on too,
    // and the monitor checks those traps like any other instruction.  (A monitor
    // for rv64imafdc_zb needed them waived: it expected F/D/Zb to execute.)
    //
    // Causes 16, 19, 20 and 21 are the core's hardware-error traps (redundant
    // compute unresolved, register/pipeline ECC, D$ dirty line lost).  The model
    // has no ECC or redundancy, so it expects the instruction to complete; the
    // tests that raise them check cause, mepc and mtval themselves
    // (testcode/stress/mem/st_cache_ecc_directed.c, hvl/ft_shadow, hvl/ecc).
    assign mon_itf.mmu_fault[0] = mon_itf.valid[0] && `RT_TAP.TrapW &&
                                  (TrapCauseW inside {5'd0, 5'd1, 5'd4, 5'd5, 5'd6, 5'd7, 5'd12, 5'd13, 5'd15,
                                                      5'd16, 5'd19, 5'd20, 5'd21});

`ifndef ECE411_NO_RVFI
    // ---- ECC mailbox: deterministic cache corruption for directed tests -----
    // A program stores a target address to ECC_MBOX_ADDR, then ECC_MBOX_MAGIC|op
    // to ECC_MBOX_CMD.  When that store retires, the testbench flips two bits in
    // every way of the target's set whose stored tag matches the target -- two
    // flips make the codeword uncorrectable (DED):
    //   op 1 / 2   D$ tag / line        op 3 / 4   I$ tag / line
    //   op 15      flip back the bits the last op flipped (repair)
    // Rows are {tag|line, check bits} (cachearray.sv), so the flipped bits are
    // data bits above the check bits.  Sizes are read from the cache instance at
    // run time.  Inert unless that exact address and magic are stored (the top
    // page of RAM, above every program's stack).  Used by
    // testcode/stress/mem/st_cache_ecc_directed.c.
    localparam longint unsigned ECC_MBOX_ADDR  = 64'h8FFF_F000;
    localparam longint unsigned ECC_MBOX_CMD   = 64'h8FFF_F008;
    localparam longint unsigned ECC_MBOX_MAGIC = 64'hECC0_DE00;
  `define ECC_DC `RT_CORE.lsu.bus.dcache.dcache
  `define ECC_IC `RT_CORE.ifu.bus.icache.icache

    longint unsigned ecc_mbox_target = '0;
    int ecc_last_op = 0;                 // what op 15 undoes
    longint unsigned ecc_last_target = '0;

    // Row index of every way of the target's set whose tag matches, as a bit mask.
    function automatic int ecc_rows_dc(input longint unsigned adr, output int set, output int nways);
      int taglen, linelen, offlen, setlen, nsets, tw, hits;
      longint unsigned tagmask, want, have;
      nways   = $bits(`ECC_DC.HitWay);
      taglen  = $bits(`ECC_DC.Tag);
      linelen = $bits(`ECC_DC.ReadDataLine);
      nsets   = $size(`ECC_DC.CacheArray.CacheTagMem.ram.RAM) / nways;
      offlen  = $clog2(linelen / 8);
      setlen  = $clog2(nsets);
      tw      = $bits(`ECC_DC.CacheArray.CacheTagMem.ram.RAM[0]);
      tagmask = (64'(1) << taglen) - 1;
      set     = int'((adr >> offlen) & (64'(nsets) - 64'd1));
      want    = (adr >> (offlen + setlen)) & tagmask;
      hits    = 0;
      for (int w = 0; w < nways; w++) begin
        have = (64'(`ECC_DC.CacheArray.CacheTagMem.ram.RAM[w*nsets+set]) >> (tw - taglen)) & tagmask;
        if (have == want) hits |= (1 << w);
      end
      return hits;
    endfunction
    function automatic int ecc_rows_ic(input longint unsigned adr, output int set, output int nways);
      int taglen, linelen, offlen, setlen, nsets, tw, hits;
      longint unsigned tagmask, want, have;
      nways   = $bits(`ECC_IC.HitWay);
      taglen  = $bits(`ECC_IC.Tag);
      linelen = $bits(`ECC_IC.ReadDataLine);
      nsets   = $size(`ECC_IC.CacheArray.CacheTagMem.ram.RAM) / nways;
      offlen  = $clog2(linelen / 8);
      setlen  = $clog2(nsets);
      tw      = $bits(`ECC_IC.CacheArray.CacheTagMem.ram.RAM[0]);
      tagmask = (64'(1) << taglen) - 1;
      set     = int'((adr >> offlen) & (64'(nsets) - 64'd1));
      want    = (adr >> (offlen + setlen)) & tagmask;
      hits    = 0;
      for (int w = 0; w < nways; w++) begin
        have = (64'(`ECC_IC.CacheArray.CacheTagMem.ram.RAM[w*nsets+set]) >> (tw - taglen)) & tagmask;
        if (have == want) hits |= (1 << w);
      end
      return hits;
    endfunction

    // Flip the two bits for op at the target; returns how many ways were hit.
    // Tag ops flip the two lowest tag bits, line ops the two lowest line bits.
    /* verilator lint_off BLKSEQ */
    function automatic int ecc_apply(input int op, input longint unsigned adr);
      int set, nways, rows, n, tb, db;
      n = 0;
      if (op == 1 || op == 2) begin
        rows = ecc_rows_dc(adr, set, nways);
        tb = $bits(`ECC_DC.CacheArray.CacheTagMem.ram.RAM[0])  - $bits(`ECC_DC.Tag);
        db = $bits(`ECC_DC.CacheArray.CacheDataMem.ram.RAM[0]) - $bits(`ECC_DC.ReadDataLine);
        for (int w = 0; w < nways; w++) if (((rows >> w) & 1) != 0) begin
          n++;
          if (op == 1) begin
            `ECC_DC.CacheArray.CacheTagMem.ram.RAM[w*(($size(`ECC_DC.CacheArray.CacheTagMem.ram.RAM))/nways)+set][tb]   ^= 1'b1;
            `ECC_DC.CacheArray.CacheTagMem.ram.RAM[w*(($size(`ECC_DC.CacheArray.CacheTagMem.ram.RAM))/nways)+set][tb+1] ^= 1'b1;
          end else begin
            `ECC_DC.CacheArray.CacheDataMem.ram.RAM[w*(($size(`ECC_DC.CacheArray.CacheDataMem.ram.RAM))/nways)+set][db]   ^= 1'b1;
            `ECC_DC.CacheArray.CacheDataMem.ram.RAM[w*(($size(`ECC_DC.CacheArray.CacheDataMem.ram.RAM))/nways)+set][db+1] ^= 1'b1;
          end
        end
      end else if (op == 3 || op == 4) begin
        rows = ecc_rows_ic(adr, set, nways);
        tb = $bits(`ECC_IC.CacheArray.CacheTagMem.ram.RAM[0])  - $bits(`ECC_IC.Tag);
        db = $bits(`ECC_IC.CacheArray.CacheDataMem.ram.RAM[0]) - $bits(`ECC_IC.ReadDataLine);
        for (int w = 0; w < nways; w++) if (((rows >> w) & 1) != 0) begin
          n++;
          if (op == 3) begin
            `ECC_IC.CacheArray.CacheTagMem.ram.RAM[w*(($size(`ECC_IC.CacheArray.CacheTagMem.ram.RAM))/nways)+set][tb]   ^= 1'b1;
            `ECC_IC.CacheArray.CacheTagMem.ram.RAM[w*(($size(`ECC_IC.CacheArray.CacheTagMem.ram.RAM))/nways)+set][tb+1] ^= 1'b1;
          end else begin
            `ECC_IC.CacheArray.CacheDataMem.ram.RAM[w*(($size(`ECC_IC.CacheArray.CacheDataMem.ram.RAM))/nways)+set][db]   ^= 1'b1;
            `ECC_IC.CacheArray.CacheDataMem.ram.RAM[w*(($size(`ECC_IC.CacheArray.CacheDataMem.ram.RAM))/nways)+set][db+1] ^= 1'b1;
          end
        end
      end
      return n;
    endfunction
    /* verilator lint_on BLKSEQ */

    always @(posedge clk) begin
      if (!rst && mon_itf.valid[0] && mon_itf.mem_wmask[0] != '0) begin
        if (mon_itf.mem_addr[0] == ECC_MBOX_ADDR) ecc_mbox_target <= mon_itf.mem_wdata[0];
        if (mon_itf.mem_addr[0] == ECC_MBOX_CMD &&
            (mon_itf.mem_wdata[0] & ~64'hFF) == ECC_MBOX_MAGIC) begin
          automatic int op = int'(mon_itf.mem_wdata[0] & 64'hFF);
          automatic int n;
          if (op == 15) begin
            n = ecc_apply(ecc_last_op, ecc_last_target);   // a second flip of the same bits repairs
            $display("TB: ECC mailbox: repaired op %0d at %h (%0d way(s))", ecc_last_op, ecc_last_target, n);
            ecc_last_op <= 0;
          end else begin
            n = ecc_apply(op, ecc_mbox_target);
            $display("TB: ECC mailbox: op %0d at %h corrupted %0d way(s)", op, ecc_mbox_target, n);
            // The test must corrupt a resident line; anything else is a bug in the test.
            if (n == 0) $fatal(1, "TB: ECC mailbox: op %0d found no way holding %h", op, ecc_mbox_target);
            ecc_last_op     <= op;
            ecc_last_target <= ecc_mbox_target;
          end
        end
      end
    end
`endif

    // ---- UART transmit tap -------------------------------------------------
    // syscalls_amoeba.c reaches printf() -- and therefore configASSERT() -- by
    // storing bytes to the NS16550 transmit holding register at UART_BASE.
    // rv64_core_wrapper leaves the serial UARTSout pin unconnected, so rather
    // than decode a bit stream at an unknown baud rate we snoop the retired
    // byte store to THR on RVFI.  Line-buffered so the text interleaves
    // cleanly with the simulator's own $display output.
    localparam longint unsigned UART_THR_ADDR = 64'h1000_0000;

    string uart_line = "";

    // Declared here rather than with the other counters below: the console
    // printer cycle-stamps each line, and SystemVerilog needs the declaration
    // before that use.
    longint unsigned sim_cycle = '0;

    // ---- UART-driven pass/fail (Linux tier) --------------------------------
    // A Linux userland runs in U-mode with the MMU on, so it cannot reach the
    // HTif tohost address the bare-metal tiers use.  Instead the boot is judged
    // by what it prints: +UART_PASS_ECE411 ends the run successfully, and
    // +UART_FAIL_ECE411 aborts it immediately so a panic costs seconds rather
    // than the full cycle timeout.  Both take a '|'-separated pattern list and
    // match anywhere in a console line.  Unset (the default) means never match,
    // which leaves the bare-metal and FreeRTOS tiers behaving exactly as before.
    string uart_pass_str = "";
    string uart_fail_str = "";
    int    uart_log_fd   = 0;

    initial begin
        string s;
        if ($value$plusargs("UART_PASS_ECE411=%s", s)) uart_pass_str = s;
        if ($value$plusargs("UART_FAIL_ECE411=%s", s)) uart_fail_str = s;
        if ($value$plusargs("UARTLOG_ECE411=%s", s))   uart_log_fd   = $fopen(s, "w");
    end

    function automatic bit str_contains(input string haystack, input string needle);
        automatic int nl = needle.len();
        automatic int hl = haystack.len();
        if (nl == 0 || nl > hl) return 1'b0;
        for (int i = 0; i <= hl - nl; i++) begin
            if (haystack.substr(i, i + nl - 1) == needle) return 1'b1;
        end
        return 1'b0;
    endfunction

    function automatic bit str_matches_any(input string haystack, input string patterns);
        automatic int start = 0;
        automatic int plen  = patterns.len();
        if (plen == 0) return 1'b0;
        for (int i = 0; i <= plen; i++) begin
            if (i == plen || patterns[i] == "|") begin
                if (i > start && str_contains(haystack, patterns.substr(start, i - 1)))
                    return 1'b1;
                start = i + 1;
            end
        end
        return 1'b0;
    endfunction

    /* verilator lint_off BLKSEQ */  // string accumulation must be blocking
    function automatic void uart_flush_line();
        if (uart_line.len() != 0) begin
            automatic string line = uart_line;
`ifdef ECE411_LINUX
            // Cycle-stamped so a boot log doubles as a timing breakdown: the
            // cost of each phase is the difference between successive lines.
            $display("[UART @%0d] %s", sim_cycle, line);
`else
            $display("[UART] %s", line);
`endif
            uart_line = "";
            if (uart_log_fd != 0) begin
                $fwrite(uart_log_fd, "%s\n", line);
                $fflush(uart_log_fd);
            end
`ifdef ECE411_SIM_INJECT
            if (!fi_armed && fi_arm_mask != '0 && str_matches_any(line, fi_arm_on_uart))
                fi_arm_req = 1'b1;
`endif
            if (str_matches_any(line, uart_fail_str)) begin
                $error("TB: UART matched a failure pattern -- test FAILED");
                $fatal;
            end
            if (str_matches_any(line, uart_pass_str)) begin
                $display("TB: UART matched \"%s\" -- test PASSED", uart_pass_str);
                $finish;
            end
        end
    endfunction

`ifdef ECE411_LINUX
    // Tap the UART peripheral itself rather than RVFI.  monitor_mem_addr is
    // driven from IEUAdrW, which is a *virtual* address, so the RVFI snoop below
    // stops matching UART_THR_ADDR the moment Linux turns on the MMU -- the
    // console goes silent exactly when the boot gets interesting.  Watching the
    // peripheral's own write strobe is physical by construction and works in
    // every privilege mode.
    //
    // The strobe sits high for two PCLK cycles because the AHB-to-APB bridge
    // holds PENABLE an extra cycle; that is why the CVW model's own $write
    // prints every character twice.  Taking the rising edge yields exactly one
    // byte per store.
`ifdef ECE411_DUT_FORTE
    `define UARTPC dut.top.chip.soc.uncore.onchip.uart.uartPC
`else
    `define UARTPC dut.soc.uncoregen.uncore.uartgen.uart.uartPC
`endif
    wire       uart_we_level = ~`UARTPC.MEMWb &
                               (`UARTPC.A == 3'b000) &
                               ~`UARTPC.DLAB;
    logic      uart_we_level_q;
    always @(posedge clk) uart_we_level_q <= rst ? 1'b0 : uart_we_level;

    wire       uart_ch_valid = uart_we_level & ~uart_we_level_q;
    wire [7:0] uart_ch_data  = `UARTPC.Din;
`else
    wire       uart_ch_valid = mon_itf.valid[0] && mon_itf.mem_wmask[0][0] &&
                               mon_itf.mem_addr[0] == UART_THR_ADDR;
    wire [7:0] uart_ch_data  = mon_itf.mem_wdata[0][7:0];
`endif

    always @(posedge clk) begin
        if (!rst && uart_ch_valid) begin
            automatic logic [7:0] uart_ch = uart_ch_data;
            if (uart_ch == 8'h0A) begin
                uart_flush_line();
            end else if (uart_ch != 8'h0D) begin
                uart_line = $sformatf("%s%c", uart_line, uart_ch);
            end
        end
    end
    /* verilator lint_on BLKSEQ */

    // ---- Retired-PC ring buffer --------------------------------------------
    // Dumped on timeout so a hung program identifies its own spin loop without
    // a waveform dig: feed the addresses to the .dis to see where it is stuck.
    localparam int PC_HIST_DEPTH = 64;

    logic [XLEN-1:0]  pc_hist [PC_HIST_DEPTH];
    int               pc_hist_wr = 0;
    longint unsigned  pc_hist_order = '0;

    // Interrupt/trap accounting: distinguishes "the program deadlocked" from
    // "the timer tick never arrived", which look identical from the PC trace.
    longint unsigned  intr_count      = '0;
    longint unsigned  trap_count      = '0;
    longint unsigned  last_intr_cycle = '0;
    logic [XLEN-1:0]  last_intr_pc    = '0;

    always @(posedge clk) begin
        if (!rst) begin
            sim_cycle <= sim_cycle + 1;
            if (mon_itf.valid[0]) begin
                pc_hist[pc_hist_wr] <= mon_itf.pc_rdata[0];
                pc_hist_wr          <= (pc_hist_wr + 1) % PC_HIST_DEPTH;
                pc_hist_order       <= mon_itf.order[0];
                if (mon_itf.intr[0]) begin
                    intr_count      <= intr_count + 1;
                    last_intr_cycle <= sim_cycle;
                    last_intr_pc    <= mon_itf.pc_rdata[0];
                end
                if (mon_itf.trap[0]) trap_count <= trap_count + 1;
            end
        end
    end

    // ---- Optional full retired-PC log (+PCLOG_ECE411=<path>) ---------------
    // Off unless the plusarg is given.  Writes "cycle pc intr" per retirement so
    // a hang can be reconstructed offline against the ELF symbol table.
    int pclog_fd = 0;

    initial begin
        string pclog_path;
        if ($value$plusargs("PCLOG_ECE411=%s", pclog_path))
            pclog_fd = $fopen(pclog_path, "w");
    end

    always @(posedge clk) begin
        if (!rst && pclog_fd != 0 && mon_itf.valid[0])
            $fwrite(pclog_fd, "%0d %h %0d\n",
                    sim_cycle, mon_itf.pc_rdata[0], mon_itf.intr[0]);
    end

    function automatic void dump_pc_hist();
        if (pclog_fd != 0) $fflush(pclog_fd);
        $display("TB: %0d cycles, %0d interrupts taken, %0d traps taken",
                 sim_cycle, intr_count, trap_count);
        if (intr_count != 0)
            $display("TB: last interrupt at cycle %0d, entering pc %016h",
                     last_intr_cycle, last_intr_pc);
        $display("TB: last %0d retired PCs, oldest first (final rvfi_order=%0d):",
                 PC_HIST_DEPTH, pc_hist_order);
        for (int i = 0; i < PC_HIST_DEPTH; i++) begin
            automatic int idx = (pc_hist_wr + i) % PC_HIST_DEPTH;
            $display("  [%2d] %016h", i, pc_hist[idx]);
        end
    endfunction


    // HTif tohost monitor via RVFI: fires at store retirement, before cbo.flush.
    // Required for Spike DPI co-sim: Spike exits when it sees the sd to tohost,
    // so the next RVFI commit (cbo.flush) would trigger $fatal from spike_dpi_next.
    // Protocol: write (exit_code << 1) | 1 to tohost; bit 0 set means exit.
    always @(posedge clk) begin
        if (!rst && mon_itf.valid[0] && mon_itf.mem_wmask[0] != '0 &&
                mon_itf.mem_addr[0] == TOHOST_ADDR) begin
            automatic longint unsigned tohost_val;
            tohost_val = mon_itf.mem_wdata[0];
            if (tohost_val[0]) begin
                uart_flush_line();
                if (tohost_val == 64'd1) begin
                    $display("TB: tohost exit(0) -- test PASSED");
                    $finish;
                end else begin
                    $error("TB: tohost exit(%0d) -- test FAILED",
                           tohost_val >> 1);
                    $fatal;
                end
            end
        end
    end

    // AHB-level tohost fallback: fires after cbo.flush evicts the cache line.
    // Not needed when Spike DPI is active (RVFI check above fires first), but
    // kept as a safety net for bare-metal runs without DPI co-sim.
    always @(posedge clk) begin
        if (!rst && mem_itf.wmask[0] != '0 &&
                mem_itf.addr[0] == TOHOST_ADDR) begin
            automatic longint unsigned tohost_val;
            tohost_val = mem_itf.wdata[0];
            if (tohost_val[0]) begin
                uart_flush_line();
                if (tohost_val == 64'd1) begin
                    $display("TB: tohost exit(0) -- test PASSED");
                    $finish;
                end else begin
                    $error("TB: tohost exit(%0d) -- test FAILED",
                           tohost_val >> 1);
                    $fatal;
                end
            end
        end
    end

    // Under +STRICT_EXIT_ECE411 a halt is only a pass if a tohost exit was
    // already seen.  The tohost blocks above $finish on the store itself, so
    // in practice reaching the halt instruction at all means the program
    // never reported -- e.g. hand-written assembly that skips the protocol.
    bit strict_exit;
    initial strict_exit = $test$plusargs("STRICT_EXIT_ECE411");

    always @(posedge clk) begin
        if (mon_itf.halt) begin
            uart_flush_line();
`ifndef ECE411_LINUX
            if (strict_exit) begin
                dump_pc_hist();
                $error("TB: halted without a tohost exit (+STRICT_EXIT_ECE411) -- test FAILED");
                $fatal;
            end
`endif
            $finish;
        end
        if (timeout == 0) begin
            uart_flush_line();
            dump_pc_hist();
            $error("TB Error: Timed out");
            $fatal;
        end
        if (mem_itf.error != 0 || mon_itf.error != 0) begin
            uart_flush_line();
            $fatal;
        end
        timeout <= timeout - 1;
    end

