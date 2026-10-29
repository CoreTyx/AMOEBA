///////////////////////////////////////////////////////////////////////////////
// tb_link_slave -- the FPGA link slave against the real ASIC bridge.
//
//   AHB master BFM -> amoeba_link_master (+ amoeba_link_train, muxed as in
//   amoeba_chip) -> 16-bit link -> amoeba_link_slave -> amoeba_mem_bram
//
// What it proves, in order:
//   1. training: the ASIC side declares the link trained off the slave's echo
//   2. singles of every HSIZE, both directions, byte lanes right
//   3. INCR8 write then INCR8 read of the same line
//   4. back-to-back bursts, including the pipelined accept (next NONSEQ in
//      the final beat's slot)
//   5. an abort: the BFM drops to IDLE mid-burst as Wally does on FlushD; the
//      ASIC bridge drains, the SLAVE'S BURST STILL RUNS ALL 8 BEATS, and the
//      re-read returns the line
//   6. TA honoured on every dir edge and the bus never driven from both ends
//
// The monitor on the slave's AHB is the point of the exercise: every line op
// must be exactly one INCR8 (NONSEQ + 7 SEQ, consecutive addresses, no early
// termination) and every single op exactly one SINGLE, whatever the ASIC side
// did.  That is the property the DDR path depends on.
///////////////////////////////////////////////////////////////////////////////

module tb_link_slave import amoeba_link_pkg::*; ();

    localparam int          TRAIN_LEN = 64;
    localparam int          PA_BITS   = 56;
    localparam logic [63:0] MEM_BASE  = 64'h8000_0000;
    localparam int          MEM_KB    = 16;

    localparam logic [1:0] T_IDLE = 2'b00, T_NONSEQ = 2'b10, T_SEQ = 2'b11;

    logic clk = 0;
    always #5 clk = ~clk;
    logic rst_n = 0;

    int errors = 0;

    // ---- link ----------------------------------------------------------------
    wire  [LINK_W-1:0] io;
    logic dir, req, wr, burst, ready, rvalid;

    // ---- ASIC side: train + master, muxed as amoeba_chip does ----------------
    logic [LINK_W-1:0] tr_io_o, lm_io_o, asic_io_o;
    logic              tr_oe, tr_dir, lm_oe, lm_dir, asic_oe;
    logic              trained, failed, txn_done;

    amoeba_link_train #(.TRAIN_LEN(TRAIN_LEN)) train (
        .clk(clk), .rst_n(rst_n),
        .io_o(tr_io_o), .io_oe(tr_oe), .io_i(io), .dir(tr_dir), .rvalid(rvalid),
        .trained(trained), .failed(failed));

    // BFM-driven AHB into the bridge
    logic               HSEL = 0, HWRITE = 0;
    logic [PA_BITS-1:0] HADDR = '0;
    logic [1:0]         HTRANS = T_IDLE;
    logic [2:0]         HSIZE = 3'b011, HBURST = 3'b000;
    logic [63:0]        HWDATA = '0, HRDATA;
    logic               HREADY, HRESP;

    amoeba_link_master #(.HADDR_W(PA_BITS)) link (
        .HCLK(clk), .HRESETn(rst_n), .run(trained),
        .HSEL(HSEL), .HADDR(HADDR), .HTRANS(HTRANS), .HWRITE(HWRITE), .HSIZE(HSIZE),
        .HBURST(HBURST), .HWDATA(HWDATA), .HREADY(HREADY),
        .HRDATA(HRDATA), .HREADYOUT(HREADY), .HRESP(HRESP),
        .io_o(lm_io_o), .io_oe(lm_oe), .io_i(io), .dir(lm_dir), .req(req), .wr(wr),
        .burst(burst), .ready(ready), .rvalid(rvalid), .txn_done(txn_done));

    assign asic_io_o = trained ? lm_io_o : tr_io_o;
    assign asic_oe   = trained ? lm_oe   : tr_oe;
    assign dir       = trained ? lm_dir  : tr_dir;
    assign io = asic_oe ? asic_io_o : {LINK_W{1'bz}};

    // ---- FPGA side: slave + block RAM ---------------------------------------
    logic [LINK_W-1:0] sl_io_o;
    logic              sl_oe;
    assign io = sl_oe ? sl_io_o : {LINK_W{1'bz}};

    logic               s_HSEL, s_HWRITE, s_HMASTLOCK, s_HREADY, s_HRESP;
    logic [PA_BITS-1:0] s_HADDR;
    logic [1:0]         s_HTRANS;
    logic [2:0]         s_HSIZE, s_HBURST;
    logic [3:0]         s_HPROT;
    logic [63:0]        s_HWDATA, s_HRDATA;
    logic [7:0]         s_HWSTRB;
    logic               sl_trained, sl_failed;
    logic [31:0]        st_xact, st_rd, st_wr, st_retrain, st_wdog, st_err;

    amoeba_link_slave #(.TRAIN_LEN(TRAIN_LEN), .PA_BITS(PA_BITS)) slave (
        .clk(clk), .rstn(rst_n),
        .io_i(io), .io_o(sl_io_o), .io_oe(sl_oe),
        .dir(dir), .req(req), .wr(wr), .burst(burst), .ready(ready), .rvalid(rvalid),
        .HSEL(s_HSEL), .HADDR(s_HADDR), .HTRANS(s_HTRANS), .HWRITE(s_HWRITE),
        .HSIZE(s_HSIZE), .HBURST(s_HBURST), .HPROT(s_HPROT), .HMASTLOCK(s_HMASTLOCK),
        .HWDATA(s_HWDATA), .HWSTRB(s_HWSTRB), .HRDATA(s_HRDATA), .HREADY(s_HREADY),
        .HRESP(s_HRESP),
        .clear(1'b0), .trained(sl_trained), .failed(sl_failed),
        .stat_xact(st_xact), .stat_rd(st_rd), .stat_wr(st_wr), .stat_retrain(st_retrain),
        .stat_wdog(st_wdog), .stat_err(st_err));

    amoeba_mem_bram #(.PA_BITS(PA_BITS), .MEM_BASE(MEM_BASE), .MEM_KB(MEM_KB)) mem (
        .clk(clk), .rstn(rst_n), .s_axi_aresetn(1'b1),
        .HSEL(s_HSEL), .HADDR(s_HADDR), .HTRANS(s_HTRANS), .HWRITE(s_HWRITE),
        .HSIZE(s_HSIZE), .HWDATA(s_HWDATA), .HWSTRB(s_HWSTRB),
        .HRDATA(s_HRDATA), .HREADY(s_HREADY), .HRESP(s_HRESP),
        .s_axi_awaddr('0), .s_axi_awvalid(1'b0), .s_axi_awready(),
        .s_axi_wdata('0), .s_axi_wstrb('0), .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bresp(), .s_axi_bvalid(), .s_axi_bready(1'b1),
        .s_axi_araddr('0), .s_axi_arvalid(1'b0), .s_axi_arready(),
        .s_axi_rdata(), .s_axi_rresp(), .s_axi_rvalid(), .s_axi_rready(1'b1));

    function automatic int widx(input logic [63:0] a);
        return int'((a - MEM_BASE) >> 3);
    endfunction

    // ---- monitor: the slave's AHB ------------------------------------------
    // Every accepted address phase.  A line op must be NONSEQ INCR8 followed
    // by exactly seven SEQ at consecutive addresses; a single op one SINGLE.
    int          mon_bursts = 0, mon_singles = 0;
    int          mon_beats_left = 0;
    logic [63:0] mon_expect;
    always @(posedge clk) if (rst_n && s_HREADY) begin
        if (s_HSEL && s_HTRANS == T_NONSEQ) begin
            if (mon_beats_left != 0) begin
                $display("FAIL  monitor: NONSEQ with %0d beats of the previous burst outstanding", mon_beats_left);
                errors++;
            end
            if (s_HBURST == HBURST_INCR8) begin
                if (s_HSIZE != 3'b011) begin $display("FAIL  monitor: INCR8 with HSIZE=%0d", s_HSIZE); errors++; end
                mon_beats_left = 7; mon_expect = 64'(s_HADDR) + 8; mon_bursts++;
            end else if (s_HBURST == HBURST_SINGLE) begin
                mon_singles++;
            end else begin
                $display("FAIL  monitor: HBURST=%b", s_HBURST); errors++;
            end
        end else if (s_HSEL && s_HTRANS == T_SEQ) begin
            if (mon_beats_left == 0) begin $display("FAIL  monitor: SEQ outside a burst"); errors++; end
            else begin
                if (64'(s_HADDR) != mon_expect) begin
                    $display("FAIL  monitor: SEQ address %h, expected %h", s_HADDR, mon_expect); errors++;
                end
                mon_beats_left--; mon_expect += 8;
            end
        end else if (s_HTRANS == T_IDLE || !s_HSEL) begin
            if (mon_beats_left != 0) begin
                $display("FAIL  monitor: burst terminated early with %0d beats left", mon_beats_left);
                errors++; mon_beats_left = 0;
            end
        end else begin
            $display("FAIL  monitor: HTRANS=BUSY"); errors++;
        end
    end

    // ---- monitor: the link pins --------------------------------------------
    // Never both driving; TA idle cycles after every dir edge before the new
    // owner drives.
    int   ta_since_fall = 100, ta_since_release = 100;
    logic dir_q = 1, sl_oe_q = 0;
    always @(posedge clk) if (rst_n) begin
        if (asic_oe && sl_oe) begin $display("FAIL  link: both ends driving io"); errors++; end
        if (dir_q && !dir) ta_since_fall = 0; else ta_since_fall++;
        if (sl_oe_q && !sl_oe) ta_since_release = 0; else ta_since_release++;
        if (sl_oe && !sl_oe_q && ta_since_fall < TA) begin
            $display("FAIL  link: slave drove %0d cycles after dir fell (TA=%0d)", ta_since_fall, TA); errors++;
        end
        if (dir && !dir_q && ta_since_release < TA) begin
            $display("FAIL  link: dir rose %0d cycles after the slave released (TA=%0d)", ta_since_release, TA); errors++;
        end
        dir_q = dir; sl_oe_q = sl_oe;
    end

    // The bridge's own abort flag, so the abort test is known to have aborted.
    int   n_abort = 0;
    logic aborted_q = 0;
    always @(posedge clk) begin
        if (link.aborted && !aborted_q) n_abort++;
        aborted_q = link.aborted;
    end

    // ---- AHB master BFM ------------------------------------------------------
    // Drives on the negedge, decides on the value HREADY will have at the
    // coming posedge.  `chain` leaves the last data phase open so the next
    // call's NONSEQ lands in the slot where IDLE would have been -- the
    // pipelined accept path in the bridge.
    logic        pend_valid = 0, pend_write = 0;
    logic [63:0] pend_wdata = '0, pend_rdata = '0;
    int unsigned cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    task automatic wait_ready(input string what);
        int unsigned start = cyc;
        #1;
        while (!HREADY) begin
            @(negedge clk); #1;
            if (cyc - start > 2000) begin
                $display("FAIL  %s: HREADY stuck low for 2000 cycles", what);
                errors++;
                $display("\n=== %0d error(s) ===", errors);
                $finish;
            end
        end
    endtask

    task automatic ahb_xfer(input bit write, input logic [63:0] addr, input int nbeats,
                            input logic [2:0] size, inout logic [63:0] data[8],
                            input bit chain = 0, input int abort_after = -1);
        int last = nbeats;
        if (abort_after >= 0) last = abort_after;   // beats actually completed by the master
        for (int i = 0; i <= last; i++) begin
            // A chained call is already sitting at the negedge its predecessor
            // returned on; the NONSEQ goes in that very slot.
            if (!(i == 0 && pend_valid)) @(negedge clk);
            if (i < nbeats && (abort_after < 0 || i < abort_after)) begin
                HSEL = 1; HTRANS = (i == 0) ? T_NONSEQ : T_SEQ; HADDR = PA_BITS'(addr + 8 * i);
                HWRITE = write; HSIZE = size; HBURST = (nbeats == 8) ? HBURST_INCR8 : HBURST_SINGLE;
            end else if (i == nbeats && chain) begin
                // Last data phase stays open: its HWDATA must be on the bus
                // NOW (the bridge serialises it from this cycle on), and the
                // next call's NONSEQ takes the address-phase slot.
                HWDATA = data[i - 1];
                pend_valid = 1; pend_write = write; pend_wdata = data[i - 1];
                return;
            end else begin
                HSEL = 0; HTRANS = T_IDLE;
            end
            if (i > 0)          HWDATA = data[i - 1];
            else if (pend_valid) HWDATA = pend_wdata;
            wait_ready(write ? "write" : "read");
            if (i > 0 && !write)                data[i - 1] = HRDATA;
            if (i == 0 && pend_valid) begin
                if (!pend_write) pend_rdata = HRDATA;
                pend_valid = 0;
            end
        end
        if (abort_after >= 0) begin
            // The master has walked away.  Its next transfer waits for HREADY,
            // which the bridge holds low until the line has drained.
            @(negedge clk); HSEL = 0; HTRANS = T_IDLE;
            wait_ready("drain after abort");
        end
    endtask

    // Writes complete on the link before they reach memory: wait for the
    // slave's queues and pipeline to empty before looking at the array.
    task automatic drain();
        int unsigned start = cyc;
        while (slave.dq_count != 0 || slave.a_valid || slave.d_valid || slave.lst == 5) begin
            @(negedge clk);
            if (cyc - start > 2000) begin
                $display("FAIL  drain: slave still busy after 2000 cycles"); errors++;
                $display("\n=== %0d error(s) ===", errors); $finish;
            end
        end
        repeat (3) @(negedge clk);
    endtask

    task automatic check64(input string what, input logic [63:0] got, input logic [63:0] want);
        if (got !== want) begin
            $display("FAIL  %s: got %h, want %h", what, got, want);
            errors++;
        end
    endtask

    // ---- the tests -------------------------------------------------------------
    logic [63:0] d[8], r[8], z[8];
    logic [63:0] line_a, line_b, line_c;
    int          n_xact = 0;

    initial begin
        for (int i = 0; i < 8; i++) z[i] = '0;
        line_a = MEM_BASE + 64'h1000;
        line_b = MEM_BASE + 64'h2040;
        line_c = MEM_BASE + 64'h3F80;

        for (int i = 0; i < (MEM_KB * 1024) / 8; i++) mem.mem[i] = 64'hFFFF_FFFF_FFFF_FFFF;

        repeat (3) @(negedge clk);
        rst_n = 1;

        // 1. training
        begin
            int unsigned start = cyc;
            while (!trained && !failed && cyc - start < 8 * TRAIN_LEN) @(negedge clk);
            if (!trained) begin $display("FAIL  training: not trained after %0d cycles (failed=%0d)", cyc - start, failed); errors++; end
            else $display("training: trained after %0d cycles", cyc - start);
            if (sl_trained) begin $display("FAIL  slave reports trained before any header"); errors++; end
        end

        // 2. singles, every HSIZE, byte lanes
        d[0] = 64'h1122_3344_5566_7788;
        ahb_xfer(1, line_a + 0, 1, 3'b011, d); n_xact++; drain();
        check64("write d single", mem.mem[widx(line_a)], 64'h1122_3344_5566_7788);
        d[0] = 64'hAAAA_AAAA_DEAD_BEEF;
        ahb_xfer(1, line_a + 8 + 4, 1, 3'b010, d); n_xact++; drain();   // word at offset 4: lanes 7:4
        check64("write w single", mem.mem[widx(line_a + 8)], 64'hAAAA_AAAA_FFFF_FFFF);
        d[0] = 64'h0000_CAFE_0000_0000;
        ahb_xfer(1, line_a + 16 + 4, 1, 3'b001, d); n_xact++; drain();  // half at offset 4: lanes 5:4
        check64("write h single", mem.mem[widx(line_a + 16)], 64'hFFFF_CAFE_FFFF_FFFF);
        d[0] = 64'h0000_0000_00A5_0000;
        ahb_xfer(1, line_a + 24 + 2, 1, 3'b000, d); n_xact++; drain();  // byte at offset 2
        check64("write b single", mem.mem[widx(line_a + 24)], 64'hFFFF_FFFF_FFA5_FFFF);
        if (!sl_trained) begin $display("FAIL  slave not trained after headers"); errors++; end

        r[0] = 'x; ahb_xfer(0, line_a + 0, 1, 3'b011, r);      n_xact++;
        check64("read d single", r[0], 64'h1122_3344_5566_7788);
        r[0] = 'x; ahb_xfer(0, line_a + 8 + 4, 1, 3'b010, r);  n_xact++;
        check64("read w single", r[0], 64'hAAAA_AAAA_FFFF_FFFF);
        r[0] = 'x; ahb_xfer(0, line_a + 16 + 6, 1, 3'b001, r); n_xact++;
        check64("read h single", r[0], 64'hFFFF_CAFE_FFFF_FFFF);
        r[0] = 'x; ahb_xfer(0, line_a + 24 + 2, 1, 3'b000, r); n_xact++;
        check64("read b single", r[0], 64'hFFFF_FFFF_FFA5_FFFF);
        $display("singles: ok");

        // 3. one line, both ways
        for (int i = 0; i < 8; i++) d[i] = {32'h0B00_0000 + i, 32'hF00D_0000 + 16 * i};
        ahb_xfer(1, line_b, 8, 3'b011, d); n_xact++; drain();
        for (int i = 0; i < 8; i++) check64($sformatf("line write beat %0d", i), mem.mem[widx(line_b) + i], d[i]);
        for (int i = 0; i < 8; i++) r[i] = 'x;
        ahb_xfer(0, line_b, 8, 3'b011, r); n_xact++;
        for (int i = 0; i < 8; i++) check64($sformatf("line read beat %0d", i), r[i], d[i]);
        $display("line: ok");

        // 4. back-to-back, pipelined accept: write A, write C, read A, read C
        //    with each NONSEQ presented in the previous transaction's last slot
        for (int i = 0; i < 8; i++) d[i] = 64'hA000_0000_0000_0000 + 64'(i) * 64'h0101_0101_0101_0101;
        ahb_xfer(1, line_a, 8, 3'b011, d, .chain(1)); n_xact++;
        for (int i = 0; i < 8; i++) d[i] = 64'hC000_0000_0000_0000 + 64'(i) * 64'h1111_1111_1111_1111;
        ahb_xfer(1, line_c, 8, 3'b011, d, .chain(1)); n_xact++;
        for (int i = 0; i < 8; i++) r[i] = 'x;
        ahb_xfer(0, line_a, 8, 3'b011, r, .chain(1)); n_xact++;
        for (int i = 0; i < 7; i++) check64($sformatf("chained read A beat %0d", i), r[i],
                                            64'hA000_0000_0000_0000 + 64'(i) * 64'h0101_0101_0101_0101);
        for (int i = 0; i < 8; i++) r[i] = 'x;
        ahb_xfer(0, line_c, 8, 3'b011, r); n_xact++;
        check64("chained read A beat 7", pend_rdata, 64'hA000_0000_0000_0000 + 64'd7 * 64'h0101_0101_0101_0101);
        for (int i = 0; i < 8; i++) check64($sformatf("chained read C beat %0d", i), r[i],
                                            64'hC000_0000_0000_0000 + 64'(i) * 64'h1111_1111_1111_1111);
        // a single chained straight after a burst, and a burst after a single
        d[0] = 64'h5151_5151_5151_5151;
        ahb_xfer(1, line_b + 32, 1, 3'b011, d, .chain(1)); n_xact++;
        for (int i = 0; i < 8; i++) r[i] = 'x;
        ahb_xfer(0, line_b, 8, 3'b011, r); n_xact++;
        check64("single then burst, beat 4", r[4], 64'h5151_5151_5151_5151);
        check64("single then burst, beat 3", r[3], {32'h0B00_0003, 32'hF00D_0030});
        $display("back-to-back / pipelined: ok");

        // 5. abort: the master drops to IDLE after two beats of a line read
        for (int i = 0; i < 8; i++) r[i] = 'x;
        ahb_xfer(0, line_c, 8, 3'b011, r, .abort_after(2)); n_xact++;
        // Beat 0 was delivered before the IDLE; beat 1's data phase was
        // abandoned by the master and the bridge did not complete it (the
        // core would have re-requested the line).
        check64("aborted read beat 0", r[0], 64'hC000_0000_0000_0000);
        for (int i = 0; i < 8; i++) r[i] = 'x;
        ahb_xfer(0, line_c, 8, 3'b011, r); n_xact++;
        for (int i = 0; i < 8; i++) check64($sformatf("re-read after abort beat %0d", i), r[i],
                                            64'hC000_0000_0000_0000 + 64'(i) * 64'h1111_1111_1111_1111);
        // and a write straight after, to be sure nothing is left in the queues
        for (int i = 0; i < 8; i++) d[i] = 64'h0DDB_A115_0000_0000 + 64'(i);
        ahb_xfer(1, line_c, 8, 3'b011, d); n_xact++; drain();
        for (int i = 0; i < 8; i++) check64($sformatf("write after abort beat %0d", i), mem.mem[widx(line_c) + i], d[i]);
        $display("abort: ok");

        // 6. a burst of mixed traffic with no waits between
        for (int k = 0; k < 16; k++) begin
            for (int i = 0; i < 8; i++) d[i] = 64'(k) * 64'h0000_0001_0000_0001 + 64'(i) * 64'h0001_0000_0001_0000;
            ahb_xfer(1, line_a + 64 * (k % 4), 8, 3'b011, d, .chain(1)); n_xact++;
            for (int i = 0; i < 8; i++) r[i] = 'x;
            ahb_xfer(0, line_a + 64 * (k % 4), 8, 3'b011, r, .chain(k != 15)); n_xact++;
            for (int i = 0; i < 7; i++) check64($sformatf("mix %0d beat %0d", k, i), r[i], d[i]);
            if (k == 15) check64("mix 15 beat 7", r[7], d[7]);
        end
        $display("mixed traffic: ok");

        repeat (20) @(negedge clk);

        // ---- bookkeeping ---------------------------------------------------
        if (int'(st_xact) != n_xact) begin $display("FAIL  slave counted %0d transactions, tb issued %0d", st_xact, n_xact); errors++; end
        if (mon_bursts + mon_singles != n_xact) begin
            $display("FAIL  monitor saw %0d INCR8 + %0d SINGLE, tb issued %0d", mon_bursts, mon_singles, n_xact); errors++;
        end
        if (mon_beats_left != 0) begin $display("FAIL  monitor: burst still open at the end"); errors++; end
        if (n_abort != 1) begin $display("FAIL  bridge aborted %0d times, expected exactly 1", n_abort); errors++; end
        if (st_retrain != 0) begin $display("FAIL  slave counted %0d retrains", st_retrain); errors++; end
        if (st_err != 0)     begin $display("FAIL  slave stat_err = %h", st_err); errors++; end
        if (sl_failed)       begin $display("FAIL  slave reports failed"); errors++; end
        $display("slave: xact=%0d rd=%0d wr=%0d retrain=%0d wdog=%0d err=%h  monitor: INCR8=%0d SINGLE=%0d  bridge aborts=%0d",
                 st_xact, st_rd, st_wr, st_retrain, st_wdog, st_err, mon_bursts, mon_singles, n_abort);

        if (errors == 0) $display("tb_link_slave PASS");
        else             $display("\n=== %0d error(s) ===", errors);
        $finish;
    end

    initial begin
        #2_000_000;
        $display("FAIL  global timeout");
        $finish;
    end

endmodule
