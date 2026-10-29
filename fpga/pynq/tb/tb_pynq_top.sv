///////////////////////////////////////////////////////////////////////////////
// tb_pynq_top -- the whole PL top, driven the way the PS drives it.
//
// amoeba_pynq_top with the block RAM backend, an AXI4-Lite master BFM on the
// control port standing in for the Cortex-A9, and a FreeRTOS image loaded by
// backdoor.  The bring-up sequence is the one sw/amoeba/device.py runs:
//
//   1. load the image            over the AXI4-Lite image window, as the PS does
//   2. clear the monitors        CTRL = MON_CLEAR | CORE_RESET
//   3. release CORE_RESET        CTRL = 0
//   4. DUT_ASIC: wait for STATUS.link_trained
//   5. drain UART_DATA to stdout until STATUS.tohost_valid
//
// The console is drained twice over: UART_DATA (the AHB snoop) and SER_DATA
// (amoeba_uart_xcvr's deserializer on the 16550's SOUT).  The two streams
// must be identical at the end of every run -- the serializer, the divisor
// shadow and the deserializer are all checked on every image that way, and
// under DUT_ASIC so is amoeba_top's uart_tx port.
//
// +SERIAL=1 types at the guest: when the console says ECHO READY (see
// testcode/freertos/uart_echo_app.c) the bench pushes "hello\r" through
// SER_TX and requires the echo to come back on the console.  That is the
// only path INTO the guest, and under DUT_ASIC it is amoeba_top's uart_rx.
//
// Everything between the ctl registers and the DUT is therefore exercised
// before Vivado sees it: the DUT generate, the hierarchical taps, the console
// snoop on the SoC's internal bus, the reset-then-train sequence, and the
// link slave against block RAM.  Run with -GDUT_ASIC=1'b1 for the ASIC top,
// -GDUT_ASIC=1'b0 for the soft core (same image, same expected output).
//
//   +IMAGE=<file>     64-bit words, hex, from EXT_MEM_BASE, for $readmemh
//   +TIMEOUT=<cycles> default 4,000,000
//   +LINK_LOOP_PS=<n> AMOEBA_LINK_PINS builds: the looped clock's delay (3000)
//   +SERIAL=1         type "hello\r" at ECHO READY, expect it echoed
///////////////////////////////////////////////////////////////////////////////

`include "amoeba_config_select.vh"

module tb_pynq_top #(
    parameter bit DUT_ASIC  = 1'b1,
    parameter int TRAIN_LEN = 64,
    parameter int MEM_KB    = 128
) ();

    logic clk = 0;
    always #5 clk = ~clk;
    logic aresetn = 0;

    int errors = 0;

    // ---- AXI4-Lite control, the PS's GP0 --------------------------------------
    logic [11:0] ctl_awaddr = '0, ctl_araddr = '0;
    logic        ctl_awvalid = 0, ctl_awready, ctl_wvalid = 0, ctl_wready;
    logic [31:0] ctl_wdata = '0, ctl_rdata;
    logic [3:0]  ctl_wstrb = 4'hF;
    logic [1:0]  ctl_bresp, ctl_rresp;
    logic        ctl_bvalid, ctl_bready = 0, ctl_arvalid = 0, ctl_arready, ctl_rvalid, ctl_rready = 0;

    // ---- AXI4-Lite image window ------------------------------------------------
    logic [31:0] mem_awaddr = '0, mem_wdata = '0, mem_rdata;
    logic        mem_awvalid = 0, mem_awready, mem_wvalid = 0, mem_wready, mem_bvalid, mem_bready = 0;
    logic        mem_arready, mem_rvalid;
    logic [1:0]  mem_bresp, mem_rresp;

    logic [63:0] trace_tdata;
    logic [7:0]  trace_tkeep;
    logic        trace_tvalid, trace_tlast;

    logic        m_ahb_hsel, m_ahb_hwrite, m_ahb_hmastlock, m_ahb_hresetn, m_ahb_hready_bus;
    logic [31:0] m_ahb_haddr;
    logic [63:0] m_ahb_hwdata;
    logic [7:0]  m_ahb_hwstrb;
    logic [2:0]  m_ahb_hsize, m_ahb_hburst;
    logic [3:0]  m_ahb_hprot;
    logic [1:0]  m_ahb_htrans;
    logic        uart_txd_obs;

`ifdef AMOEBA_LINK_PINS
    // Stage C in simulation: the ribbon is a wire per pin, and the looped
    // clock arrives LINK_LOOP_NS late -- the ODDR, ribbon, IBUF and BUFG the
    // board will add -- so the chip runs skewed against the slave, as it
    // will on the bench.  The io net is shared by both inouts, as a ribbon
    // makes it.
    // +LINK_LOOP_PS=<n> sweeps it: the simulated eye, to compare with the
    // bench's IDELAY sweep.  The tb clock is 10 ns, so the chip's negedge
    // capture sits 5 ns after the slave's launch edge plus this delay.
    int unsigned link_loop_ps = 3000;
    initial void'($value$plusargs("LINK_LOOP_PS=%d", link_loop_ps));
    wire [15:0] ribbon_io;
    wire        a_dir, a_req, a_wr, a_burst, b_ready, b_rvalid, b_clk, status_led, uart_tx_pin;
    logic       a_clk = 0;
    always @(b_clk) a_clk <= #(link_loop_ps * 1ps) b_clk;
`endif

    amoeba_pynq_top #(
        .MEM_BRAM  (1'b1),
        .MEM_KB    (MEM_KB),
        .TRACE     (1'b0),
        .DUT_ASIC  (DUT_ASIC),
        .TRAIN_LEN (TRAIN_LEN)
    ) dut (
        .aclk (clk), .aresetn (aresetn),
        .s_axi_ctl_awaddr (ctl_awaddr), .s_axi_ctl_awvalid (ctl_awvalid), .s_axi_ctl_awready (ctl_awready),
        .s_axi_ctl_wdata (ctl_wdata), .s_axi_ctl_wstrb (ctl_wstrb), .s_axi_ctl_wvalid (ctl_wvalid),
        .s_axi_ctl_wready (ctl_wready), .s_axi_ctl_bresp (ctl_bresp), .s_axi_ctl_bvalid (ctl_bvalid),
        .s_axi_ctl_bready (ctl_bready), .s_axi_ctl_araddr (ctl_araddr), .s_axi_ctl_arvalid (ctl_arvalid),
        .s_axi_ctl_arready (ctl_arready), .s_axi_ctl_rdata (ctl_rdata), .s_axi_ctl_rresp (ctl_rresp),
        .s_axi_ctl_rvalid (ctl_rvalid), .s_axi_ctl_rready (ctl_rready),
        .m_axis_trace_tdata (trace_tdata), .m_axis_trace_tkeep (trace_tkeep),
        .m_axis_trace_tvalid (trace_tvalid), .m_axis_trace_tready (1'b1), .m_axis_trace_tlast (trace_tlast),
        .s_axi_mem_awaddr (mem_awaddr), .s_axi_mem_awvalid (mem_awvalid), .s_axi_mem_awready (mem_awready),
        .s_axi_mem_wdata (mem_wdata), .s_axi_mem_wstrb (4'hF), .s_axi_mem_wvalid (mem_wvalid), .s_axi_mem_wready (mem_wready),
        .s_axi_mem_bresp (mem_bresp), .s_axi_mem_bvalid (mem_bvalid), .s_axi_mem_bready (mem_bready),
        .s_axi_mem_araddr ('0), .s_axi_mem_arvalid (1'b0), .s_axi_mem_arready (mem_arready),
        .s_axi_mem_rdata (mem_rdata), .s_axi_mem_rresp (mem_rresp), .s_axi_mem_rvalid (mem_rvalid),
        .s_axi_mem_rready (1'b1),
        .m_ahb_hsel (m_ahb_hsel), .m_ahb_haddr (m_ahb_haddr), .m_ahb_hwdata (m_ahb_hwdata),
        .m_ahb_hwstrb (m_ahb_hwstrb), .m_ahb_hwrite (m_ahb_hwrite), .m_ahb_hsize (m_ahb_hsize),
        .m_ahb_hburst (m_ahb_hburst), .m_ahb_hprot (m_ahb_hprot), .m_ahb_htrans (m_ahb_htrans),
        .m_ahb_hmastlock (m_ahb_hmastlock), .m_ahb_hrdata ('0), .m_ahb_hready (1'b1), .m_ahb_hresp (1'b0),
        .m_ahb_hresetn (m_ahb_hresetn), .m_ahb_hready_bus (m_ahb_hready_bus),
        .uart_txd_obs (uart_txd_obs)
`ifdef AMOEBA_LINK_PINS
        ,
        .link_a_clk (a_clk), .link_a_io (ribbon_io),
        .link_a_dir (a_dir), .link_a_req (a_req), .link_a_wr (a_wr), .link_a_burst (a_burst),
        .link_a_ready (b_ready), .link_a_rvalid (b_rvalid),
        .link_b_clk (b_clk), .link_b_io (ribbon_io),
        .link_b_dir (a_dir), .link_b_req (a_req), .link_b_wr (a_wr), .link_b_burst (a_burst),
        .link_b_ready (b_ready), .link_b_rvalid (b_rvalid),
        .status_led (status_led), .uart_tx_pin (uart_tx_pin),
        .refclk200 (1'b0)
`endif
    );

    // ---- register map, from sw/amoeba/regs.py ----------------------------------
    localparam logic [11:0] R_CTRL = 12'h0C, R_STATUS = 12'h10, R_UART_DATA = 12'h14,
                            R_CYCLES_LO = 12'h20, R_RETIRED_LO = 12'h28, R_TRAPS = 12'h30,
                            R_TOHOST_LO = 12'h34, R_CAPS = 12'h08,
                            R_LINK_XACT = 12'hA0, R_LINK_RETRAIN = 12'hAC, R_LINK_ERR = 12'hB8,
                            R_SER_DATA = 12'hC4, R_SER_LEVEL = 12'hC8, R_SER_TX = 12'hCC,
                            R_SER_TICK = 12'hD4;
    localparam logic [31:0] CTRL_CORE_RESET = 1, CTRL_MON_CLEAR = 2;
    localparam int ST_CORE_RESET = 0, ST_UART_VALID = 1, ST_TOHOST_VALID = 3,
                   ST_LINK_TRAINED = 6, ST_LINK_FAILED = 7, ST_SER_VALID = 9;

    int unsigned cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    task automatic axi_write(input [11:0] a, input [31:0] d);
        bit aw_done, w_done, b_done;
        b_done = 0;
        @(negedge clk);
        ctl_awaddr = a; ctl_wdata = d; ctl_awvalid = 1; ctl_wvalid = 1; ctl_bready = 1;
        while (!b_done) begin
            aw_done = ctl_awvalid && ctl_awready;
            w_done  = ctl_wvalid  && ctl_wready;
            b_done  = ctl_bvalid  && ctl_bready;
            @(posedge clk); @(negedge clk);
            if (aw_done) ctl_awvalid = 0;
            if (w_done)  ctl_wvalid  = 0;
        end
        ctl_awvalid = 0; ctl_wvalid = 0; ctl_bready = 0;
    endtask

    task automatic axi_read(input [11:0] a, output [31:0] d);
        bit ar_done, r_done;
        r_done = 0; d = 'x;
        @(negedge clk);
        ctl_araddr = a; ctl_arvalid = 1; ctl_rready = 1;
        while (!r_done) begin
            ar_done = ctl_arvalid && ctl_arready;
            r_done  = ctl_rvalid  && ctl_rready;
            if (r_done) d = ctl_rdata;
            @(posedge clk); @(negedge clk);
            if (ar_done) ctl_arvalid = 0;
        end
        ctl_arvalid = 0; ctl_rready = 0;
    endtask

    task automatic mem_write(input [31:0] a, input [31:0] d);
        bit aw_done, w_done, b_done;
        b_done = 0;
        @(negedge clk);
        mem_awaddr = a; mem_wdata = d; mem_awvalid = 1; mem_wvalid = 1; mem_bready = 1;
        while (!b_done) begin
            aw_done = mem_awvalid && mem_awready;
            w_done  = mem_wvalid  && mem_wready;
            b_done  = mem_bvalid  && mem_bready;
            @(posedge clk); @(negedge clk);
            if (aw_done) mem_awvalid = 0;
            if (w_done)  mem_wvalid  = 0;
        end
        mem_awvalid = 0; mem_wvalid = 0; mem_bready = 0;
    endtask

    // +DBG: every trap, with its PC -- the first thing to look at when a run
    // retires millions of instructions and prints nothing.  Through the tap
    // wires amoeba_pynq_top exports, not dotted paths into the DUT: Verilator
    // resolves a testbench's dotted names against the submodule's DEFAULT
    // parameters, i.e. the soft-core arm of the generate, whatever -G says.
    always @(posedge clk) if ($test$plusargs("DBG") && dut.tap_TrapM && !dut.tap_StallM)
        $display("[TRAP] c%0d pc=%h", cyc, dut.tap_PCM);

    // +DBG_BUS: every accepted address phase off EXT_MEM on the SoC's internal
    // bus -- the UART, CLINT and PLIC traffic the console snoop decodes.
    always @(posedge clk) if ($test$plusargs("DBG_BUS") && dut.bus_HREADY && dut.bus_HTRANS[1]
                              && dut.bus_HADDR[31:28] != 4'h8)
        $display("[BUS] c%0d %s addr=%h pc=%h", cyc, dut.bus_HWRITE ? "W" : "R", dut.bus_HADDR, dut.tap_PCM);

    // +DBG_PC: every retired PC after cycle +DBG_FROM (histogram it to find a spin)
    int unsigned dbg_from = 0;
    initial void'($value$plusargs("DBG_FROM=%d", dbg_from));
    always @(posedge clk) if ($test$plusargs("DBG_PC") && cyc > dbg_from && dut.tap_InstrValidM && !dut.tap_StallM && !dut.tap_FlushM)
        $display("[PC] %h", dut.tap_PCM);

    // ---- the run -------------------------------------------------------------
    string       image;
    int unsigned timeout = 4_000_000;
    logic [31:0] v, st, caps;
    int          nbytes = 0, ntrained = 0;
    byte         line[$];
    string       snoop_s = "", ser_s = "", last_line = "";
    bit          serial = 0, typed = 0;

    task automatic flush_line();
        string s = "";
        foreach (line[i]) s = {s, string'(line[i])};
        $display("[UART] %s", s);
        last_line = s;
        line.delete();
    endtask

    // One byte onto the line.  The FIFO is 16 deep and the PS-side driver
    // checks `full` first; so does this.
    task automatic ser_putc(input byte c);
        logic [31:0] t;
        do axi_read(R_SER_TX, t); while (t[31]);
        axi_write(R_SER_TX, 32'(c));
    endtask

    // Drain the deserializer's FIFO into ser_s.
    task automatic drain_ser();
        logic [31:0] d;
        forever begin
            axi_read(R_SER_DATA, d);
            if (!d[8]) break;
            ser_s = {ser_s, string'(d[7:0])};
        end
    endtask

    function automatic bit find_str(input string hay, input string needle);
        for (int i = 0; i + needle.len() <= hay.len(); i++)
            if (hay.substr(i, i + needle.len() - 1) == needle) return 1;
        return 0;
    endfunction

    initial begin
        if (!$value$plusargs("IMAGE=%s", image)) begin
            $display("FAIL  no +IMAGE=<hex>"); $finish;
        end
        void'($value$plusargs("TIMEOUT=%d", timeout));
        serial = $test$plusargs("SERIAL");

        repeat (8) @(negedge clk);
        aresetn = 1;
        repeat (4) @(negedge clk);

        // Load: one 64-bit word per line, from EXT_MEM_BASE, as two 32-bit
        // AXI writes each.  The core is held in reset throughout, which is
        // the condition tb_mem_axi exists to defend.
        begin
            int fd, n, nw = 0;
            logic [63:0] w;
            fd = $fopen(image, "r");
            if (fd == 0) begin $display("FAIL  cannot open %0s", image); $finish; end
            while (!$feof(fd)) begin
                n = $fscanf(fd, "%h\n", w);
                if (n != 1) break;
                mem_write(32'(nw * 8),     w[31:0]);
                mem_write(32'(nw * 8 + 4), w[63:32]);
                nw++;
            end
            $fclose(fd);
            $display("image: %0d words loaded over the AXI window at cycle %0d", nw, cyc);
        end

        axi_read(R_CAPS, caps);
        $display("CAPS=%08x  dut=%0s", caps, caps[9] ? "asic+link" : "soc");
        if (caps[9] != DUT_ASIC) begin $display("FAIL  CAPS.asic_link disagrees with the build"); errors++; end
        axi_read(R_STATUS, st);
        if (!st[ST_CORE_RESET]) begin $display("FAIL  core not held in reset out of configuration"); errors++; end

        axi_write(R_CTRL, CTRL_MON_CLEAR | CTRL_CORE_RESET);
        axi_write(R_CTRL, 32'h0);
        $display("core released at cycle %0d", cyc);

        if (DUT_ASIC) begin
            int unsigned t0 = cyc;
            do axi_read(R_STATUS, st);
            while (!st[ST_LINK_TRAINED] && !st[ST_LINK_FAILED] && cyc - t0 < 40 * TRAIN_LEN + 2000);
            if (!st[ST_LINK_TRAINED]) begin
                $display("FAIL  link not trained after %0d cycles: STATUS=%08x", cyc - t0, st); errors++;
            end else begin
                ntrained = cyc - t0;
                $display("link trained: first header %0d cycles after release", ntrained);
            end
        end

        // Console until tohost.
        forever begin
            axi_read(R_STATUS, st);
            if (st[ST_UART_VALID]) begin
                axi_read(R_UART_DATA, v);
                if (v[8]) begin
                    nbytes++;
                    snoop_s = {snoop_s, string'(v[7:0])};
                    if (v[7:0] == 8'h0A) flush_line();
                    else if (v[7:0] != 8'h0D) line.push_back(byte'(v[7:0]));
                    if (serial && !typed && last_line == "ECHO READY") begin
                        typed = 1;
                        $display("[SER] typing \"hello\\r\" at cycle %0d", cyc);
                        ser_putc("h"); ser_putc("e"); ser_putc("l"); ser_putc("l"); ser_putc("o");
                        ser_putc(8'h0D);
                    end
                end
            end else if (st[ST_SER_VALID]) begin
                drain_ser();
            end else if (st[ST_TOHOST_VALID]) begin
                break;
            end else if (cyc > timeout) begin
                if (line.size()) flush_line();
                $display("FAIL  timeout at %0d cycles with no tohost", cyc); errors++;
                break;
            end
        end
        if (line.size()) flush_line();

        // The serializer is up to a 16550 FIFO behind the snoop: give it 24
        // frames at the rate in effect to catch up, then compare.
        begin
            logic [31:0] tick, lvl;
            int unsigned t0 = cyc;
            axi_read(R_SER_TICK, tick);
            do drain_ser();
            while (ser_s.len() < snoop_s.len() && cyc - t0 < 24 * 10 * 16 * tick[19:0]);
            axi_read(R_SER_LEVEL, lvl);
            $display("serial: tick=%0d (lcr=%02x) %0d bytes deserialized, %0d snooped, ferr=%0d overflow=%0d",
                     tick[19:0], tick[31:24], ser_s.len(), snoop_s.len(), lvl[23:16], lvl[31]);
            if (ser_s != snoop_s) begin
                int i;
                for (i = 0; i < snoop_s.len() && i < ser_s.len(); i++) if (ser_s[i] != snoop_s[i]) break;
                $display("FAIL  deserialized console differs from the snoop at byte %0d: snoop %02x, serial %02x",
                         i, i < snoop_s.len() ? snoop_s[i] : 8'hxx, i < ser_s.len() ? ser_s[i] : 8'hxx);
                errors++;
            end
            if (lvl[23:16] != 0 || lvl[31]) begin $display("FAIL  serial framing errors / overflow"); errors++; end
            if (serial) begin
                if (!typed) begin $display("FAIL  +SERIAL but the guest never said ECHO READY"); errors++; end
                else if (!find_str(snoop_s, "hello\nECHO DONE")) begin
                    $display("FAIL  the echo did not come back"); errors++;
                end else $display("serial: echo came back through the guest");
            end
        end

        axi_read(R_TOHOST_LO, v);
        $display("tohost = 0x%08x -> exit code %0d", v, v >> 1);
        if (st[ST_TOHOST_VALID] && (v >> 1) != 0) begin $display("FAIL  program exit code %0d", v >> 1); errors++; end

        begin
            logic [31:0] cyc_lo, ret_lo, traps, xact, retrain, err;
            axi_read(R_CYCLES_LO, cyc_lo); axi_read(R_RETIRED_LO, ret_lo); axi_read(R_TRAPS, traps);
            axi_read(R_LINK_XACT, xact);  axi_read(R_LINK_RETRAIN, retrain); axi_read(R_LINK_ERR, err);
            $display("cycles=%0d retired=%0d traps=%0d console_bytes=%0d  link: xact=%0d retrain=%0d err=%08x",
                     cyc_lo, ret_lo, traps, nbytes, xact, retrain, err);
            if (ret_lo == 0) begin $display("FAIL  0 retired"); errors++; end
            if (DUT_ASIC && xact == 0) begin $display("FAIL  no link transactions"); errors++; end
            if (DUT_ASIC && (retrain != 0 || err != 0)) begin $display("FAIL  link retrain/err"); errors++; end
        end

        if (errors == 0) $display("tb_pynq_top PASS");
        else             $display("\n=== %0d error(s) ===", errors);
        $finish;
    end

endmodule
