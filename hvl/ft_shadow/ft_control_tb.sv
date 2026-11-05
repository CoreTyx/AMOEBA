// Byte-lane, APB phase, bus decode, and PMA checks for both processor SoCs.
`include "config.vh"
module ft_control_tb;
  import cvw::*;
  `include "parameter-defs.vh"
  /* verilator lint_off BLKSEQ */
  logic clk = 0, reset_n = 0;
  always #5 clk = ~clk;
  /* verilator lint_on BLKSEQ */
  logic [P.PA_BITS-1:0] addr = '0;
  logic [63:0] wdata = 0;
  logic [7:0] strb = 0;
  logic write = 0;
  logic [2:0] size = 0;
  logic [1:0] trans = 0;
  logic [2:0] ready, resp, external_select;
  logic [63:0] rdata[3];
  logic [FI_UNITS-1:0] mask[3];
  logic external_ready = 1;
  int checks = 0;
  fault_events_t events = '0;  // fault flags into every uncore's counters

  // The same AHB requests exercise legacy and both ASIC peripheral placements.
  /* verilator lint_off PINMISSING */
  uncore #(P) legacy(
    .HCLK(clk), .HRESETn(reset_n), .TIMECLK(1'b0), .HADDR(addr), .HWDATA(wdata), .HWSTRB(strb),
    .HWRITE(write), .HSIZE(size), .HBURST(3'b0), .HPROT(4'b0011), .HTRANS(trans), .HMASTLOCK(1'b0),
    .HRDATAEXT(64'b0), .HREADYEXT(external_ready), .HRESPEXT(1'b0),
    .HRDATA(rdata[0]), .HREADY(ready[0]), .HRESP(resp[0]), .HSELEXT(external_select[0]), .FaultInjectMask(mask[0]), .FaultEvents(events),
    .GPIOIN(32'b0), .UARTSin(1'b1), .SPIIn(1'b0), .SDCIn(1'b0));
  for (genvar i = 0; i < 2; i++) begin : asic
    forte_uncore #(.P(P), .PERIPH_ONCHIP(i == 0)) dut(
      .HCLK(clk), .HRESETn(reset_n), .HADDR(addr), .HWDATA(wdata), .HWSTRB(strb),
      .HWRITE(write), .HSIZE(size), .HTRANS(trans),
      .HRDATAEXT(64'b0), .HREADYEXT(external_ready), .HRESPEXT(1'b0),
      .HRDATA(rdata[i+1]), .HREADY(ready[i+1]), .HRESP(resp[i+1]), .HSELEXT(external_select[i+1]),
      .FaultInjectMask(mask[i+1]), .FaultEvents(events), .UARTSin(1'b1), .ExtIrq(2'b0), .MExtIntIn(1'b0), .SExtIntIn(1'b0));
  end
  /* verilator lint_on PINMISSING */

  logic exec_access = 0, read_access = 1, write_access = 0, atomic_access = 0;
  logic cacheable, idempotent, tim, instr_fault, load_fault, store_fault;
  pmachecker #(P) pma(.PhysicalAddress(addr), .Size(size[1:0]), .CMOpM(4'b0), .AtomicAccessM(atomic_access),
    .ExecuteAccessF(exec_access), .WriteAccessM(write_access), .ReadAccessM(read_access), .PBMemoryType(2'b0),
    .Cacheable(cacheable), .Idempotent(idempotent), .SelTIM(tim),
    .PMAInstrAccessFaultF(instr_fault), .PMALoadAccessFaultM(load_fault), .PMAStoreAmoAccessFaultM(store_fault));

  task automatic check(input logic condition, input string message);
    checks++;
    if (condition !== 1'b1) $fatal(1, "%s at %0t", message, $time);
  endtask
  task automatic check_mask(input logic [FI_UNITS-1:0] expected);
    foreach (mask[i]) check(mask[i] == expected, "unit mask in every SoC");
  endtask
  task automatic transfer(input logic wr, input logic [63:0] data, input logic [7:0] strobes,
                          input logic [FI_UNITS-1:0] expected_before);
    @(negedge clk);
    addr = P.PA_BITS'(FI_CONTROL_ADDR);
    write = wr;
    size = 0;
    trans = 2'b10;
    #1;
    check(ready == 3'b111 && external_select == 0, "register stays on-chip and address phase accepted");
    @(posedge clk);
    @(negedge clk);
    trans = 0;
    wdata = data;
    strb = strobes;
    #1;
    check_mask(expected_before); // setup phase must not change the register
    check(ready == 0, "bridge holds the AHB transfer through APB setup");
    @(negedge clk);
    #1;
    check(ready == 3'b111 && resp == 0, "APB access completes without error");
    foreach (rdata[i]) check(rdata[i] == (64'(expected_before) << 24), "read data occupies only byte lane 3");
    @(posedge clk);
    #1;
  endtask

  // 32-bit AHB read of fault counter i in every SoC
  task automatic read_counter(input int i, input logic [15:0] expected, input string message);
    @(negedge clk);
    addr = P.PA_BITS'(ECC_COUNTER_BASE + 64'(4*i));
    write = 0;
    size = 2;
    trans = 2'b10;
    #1;
    check(!load_fault, "fault counters are readable words");
    @(posedge clk);
    @(negedge clk);
    trans = 0;
    while (ready != 3'b111) @(negedge clk);
    #1;
    foreach (rdata[k]) check(resp[k] == 0 && rdata[k][31:0] == {16'b0, expected} && rdata[k][63:32] == rdata[k][31:0],
                             $sformatf("%s (counter %0d, SoC %0d: %h)", message, i, k, rdata[k]));
    size = 0;
  endtask

  initial begin
    repeat (3) @(negedge clk);
    reset_n = 1;
    check_mask(8'h00); // every unit resets off
    transfer(0, 0, 0, 8'h00);
    transfer(1, 0, 8'h08, 8'h00);
    check_mask(0);
    for (int bit_index = 0; bit_index < FI_UNITS; bit_index++) begin
      transfer(1, 64'(1 << bit_index) << 24, 8'h08, bit_index == 0 ? 8'b0 : 8'(1 << (bit_index-1)));
      check_mask(8'(1 << bit_index));
      transfer(0, 0, 0, 8'(1 << bit_index));
    end
    transfer(1, '1, 8'h08, 8'h80);
    check_mask(8'hff); // every bit of the byte is a unit
    transfer(1, 0, 8'hf7, 8'hff);
    check_mask(8'hff); // every byte strobe except the register's lane
    transfer(1, 64'h000000002a000015, 8'h08, 8'hff);
    check_mask(8'h2a); // lane 3, not lane 0, supplies data

    // IDLE/BUSY transactions must not reach the APB register.
    @(negedge clk);
    wdata = 0;
    strb = 8'h08;
    for (int idle_kind = 0; idle_kind < 2; idle_kind++) begin
      trans = 2'(idle_kind);
      repeat (4) @(negedge clk);
      check_mask(8'h2a);
    end
    trans = 0;

    // A pending external transfer holds the bus. An unaccepted register address
    // must not update its mask while HREADY is low.
    addr = P.PA_BITS'(P.EXT_MEM_BASE);
    size = 3;
    write = 0;
    trans = 2'b10;
    external_ready = 0;
    @(negedge clk);
    addr = P.PA_BITS'(FI_CONTROL_ADDR);
    size = 0;
    write = 1;
    repeat (3) begin
      @(negedge clk);
      check(ready == 0, "external wait state holds all buses");
      check_mask(8'h2a);
    end
    // Withdraw the unaccepted address before releasing the external transfer.
    trans = 0;
    external_ready = 1;
    @(negedge clk);
    transfer(0, 0, 0, 8'h2a);

    // PMA permits only byte reads/writes at the exact address. Ordinary PMP
    // and virtual-memory permissions still apply outside this checker.
    @(negedge clk);
    addr = P.PA_BITS'(FI_CONTROL_ADDR);
    #1;
    check(!cacheable && !idempotent && !tim && !load_fault, "byte register is uncached device memory");
    read_access = 0;
    write_access = 1;
    #1;
    check(!store_fault, "byte store allowed");
    atomic_access = 1;
    #1;
    check(store_fault, "atomic access rejected");
    atomic_access = 0;
    write_access = 0;
    exec_access = 1;
    #1;
    check(instr_fault, "instruction fetch rejected");
    exec_access = 0;
    read_access = 1;
    for (int access_size = 1; access_size < 4; access_size++) begin
      size = 3'(access_size);
      #1;
      check(load_fault, "wider access rejected");
    end
    size = 0;
    addr = P.PA_BITS'(FI_CONTROL_ADDR - 1);
    #1;
    check(load_fault, "preceding byte is not an alias");
    addr = P.PA_BITS'(FI_CONTROL_ADDR + 1);
    #1;
    check(load_fault, "following byte is not an alias");
    // Fault counters: every error counts, levels count once per rising edge, counts saturate.
    for (int i = 0; i < FAULT_COUNTERS; i++) read_counter(i, 0, "counters reset to zero");
    @(negedge clk);
    events.RegfileSec = 2'b11;                     // two errors in one cycle
    events.PipeSec = 5'b10101;                     // three
    events.FTUnresolved = 2'b01;                   // a level, held below
    events.TmrCorrected = 1'b1;
    @(negedge clk);
    events.RegfileSec = 2'b00;
    events.PipeSec = 5'b0;
    repeat (3) @(negedge clk);
    events.FTUnresolved = 2'b00;
    events.TmrCorrected = 1'b0;
    @(negedge clk);
    events.FTUnresolved = 2'b01;                   // a second occurrence
    @(negedge clk);
    events.FTUnresolved = 2'b00;
    events.ICacheSec = 3'b111;                     // three a cycle: run counter 4 past its top
    repeat (21850) @(negedge clk);
    events.ICacheSec = 3'b000;
    read_counter(0, 2, "two errors in one cycle count two");
    read_counter(2, 3, "pipeline errors are counted per register");
    read_counter(9, 2, "an unresolved level counts once per occurrence");
    read_counter(16, 1, "a held TMR fault counts once");
    read_counter(4, 16'hffff, "counters saturate");
    read_counter(1, 0, "untouched counters stay zero");
    read_counter(FAULT_COUNTERS, 0, "unused words read zero");

    @(negedge clk);
    reset_n = 0;
    repeat (2) @(negedge clk);
    check_mask(8'h00);
    $display("PASS ft_control_tb checks=%0d", checks);
    $finish;
  end
  initial begin
    #1000000;                                      // hang guard; the counter run takes ~22k cycles
    $fatal(1, "fault-control test timeout");
  end
endmodule
