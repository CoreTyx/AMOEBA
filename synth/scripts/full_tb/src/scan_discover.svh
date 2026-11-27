// scan_discover.svh -- chain order, scan-path inversions and reset values from
// the netlist alone (no scandef), for +define+SCAN_DISCOVER builds of tb_scan.
//
// discover_probes.generated.svh (src/discover_cells.py) gives disc_q: the
// physical Q of every flop in the netlist.  After phase A has measured each
// chain from the pins:
//   1. reset values: rst_n low with the clock running, every probe recorded.
//      This is what the logical phase comes from: a cell whose register resets
//      to r and whose physical Q reads ~r stores the bit inverted.
//   2. hold-mode scan entry with reset still held, so non-scan state is either
//      in reset or frozen; zeros flushed; every probe recorded (the baseline).
//   3. per chain k: one 1 into io_in[k], then zeros.  After cycle t the 1 sits
//      in cell t+1: the probes that differ from the baseline then are that
//      cell's candidates (normally exactly one).  The cell's baseline value is
//      its inversion from scan-in (it holds 0 ^ inv after a zero flush).
//   4. DISC_PASSES random loads: each candidate must hold the value the stream
//      put in its position (through its inversion); candidates that do not are
//      dropped.  Every position must end with exactly one, used once.
//   4b. flops that sample io_in every cycle whatever scan enable does (input
//      registers) are set aside: with scan_en low they keep tracking io_in.
//   4c. a remaining twin (a flop holding the same data, off the chain) is told
//      apart by forcing each candidate's Q: the next cell follows only its own.
//   5. discover.tsv: "C <k> <j> <probe> <inv_in> <q_at_reset>" per cell, plus
//      "L <k> <len> <pin_inv>" per chain.
// Prints counts only; names stay in the generated files.

`ifndef DISC_TRK
  `define DISC_TRK 24
`endif
`ifndef DISC_PASSES
  `define DISC_PASSES 6
`endif

`include "discover_probes.generated.svh"

  logic [DISC_N-1:0] disc_rst, disc_base;
  int   disc_cand [N:1][1:MAX_LEN][$];
  int   disc_cell [N:1][1:MAX_LEN];
  logic disc_inv  [N:1][1:MAX_LEN];

  // Probes that differ from the baseline (X counts as differing only where the
  // baseline is known), 64 at a time so a quiet chunk costs one compare.
  task automatic disc_diff(output int idx [$]);
    idx = {};
    for (int w = 0; w * 64 < DISC_N; w++) begin
      int lo = w * 64, hi = (w * 64 + 63 < DISC_N) ? w * 64 + 63 : DISC_N - 1;
      if (disc_q[lo +: 64] === disc_base[lo +: 64] && hi == lo + 63) continue;
      for (int i = lo; i <= hi; i++)
        if (disc_q[i] !== disc_base[i] && !$isunknown(disc_base[i])) idx.push_back(i);
    end
  endtask

  task automatic phase_discover();
    logic [N:1] got;
    bit shifted;
    int fd, total = 0, ambiguous = 0, empty = 0, reused = 0, flips = 0, disturbed = 0, n_tracking = 0, n_twin = 0;
    bits_t zeros = '{default: '{default: 1'b0}}, out;
    $display("[%0t] DISCOVER: %0d flop probes", $time, DISC_N);

    // 1. reset values
    set_se(1'b0); test_mode = 1'b0;
    idle(TM_SYNC + 2);
    rst_n = 1'b0;
    idle(20);
    disc_rst = disc_q;

    // 2. hold-mode entry with reset held, zero flush, baseline
    enter_hold(shifted);
    set_se(1'b1);
    shift(zeros, out);
    disc_base = disc_q;

    // 3. one 1 down each chain
    for (int k = 1; k <= N; k++) begin
      for (int t = 0; t <= len[k]; t++) begin
        int d [$];
        logic [N:1] in_b = '0;
        if (t == 0) in_b[k] = 1'b1;
        cycle(in_b, got);
        disc_diff(d);
        if (t < len[k]) begin
          disc_cand[k][t+1] = d;
          if (d.size() > 1) flips++;
        end
        else if (d.size() != 0) disturbed += d.size();
      end
      // Flops off the chains that the 1 disturbed (none, if hold and reset
      // keep non-scan state still) are not candidates for later chains.
      disc_base = disc_q;
    end

    // 4. random loads: keep the candidates that hold what was shifted in
    for (int p = 0; p < `DISC_PASSES; p++) begin
      bits_t in;
      for (int k = 1; k <= N; k++)
        for (int t = 0; t < maxlen; t++) in[k][t] = $urandom_range(1);
      shift(in, out);
      for (int k = 1; k <= N; k++)
        for (int j = 1; j <= len[k]; j++) begin
          int keep [$];
          foreach (disc_cand[k][j][c]) begin
            int i = disc_cand[k][j][c];
            if (disc_q[i] === (in[k][maxlen - j] ^ disc_base[i])) keep.push_back(i);
          end
          disc_cand[k][j] = keep;
        end
    end

    // 4b. Flops that sample io_in every cycle (the link PHY's input registers,
    // the scan_q stub) copy cell 1 or 2 exactly: they are io_in delayed by
    // one or two edges, whatever scan enable does.  A scan cell does not take
    // io_in on a scan_en=0 edge.  So, with scan_en low, drive random io_in and
    // drop every candidate that still tracks io_in at its own delay.
    begin
      int amb = 0;
      for (int k = 1; k <= N; k++)
        for (int j = 1; j <= len[k]; j++) amb += disc_cand[k][j].size() > 1;
      if (amb) begin
        logic [N:1] hist [0:`DISC_TRK-1];
        logic [DISC_N-1:0] qh [0:`DISC_TRK-1];
        set_se(1'b0);
        for (int t = 0; t < `DISC_TRK; t++) begin
          hist[t] = N'($urandom);
          cycle(hist[t], got);
          qh[t] = disc_q;
        end
        for (int k = 1; k <= N; k++)
          for (int j = 1; j <= len[k] && j < `DISC_TRK - 4; j++) begin
            int keep [$];
            if (disc_cand[k][j].size() <= 1) continue;
            foreach (disc_cand[k][j][c]) begin
              int i = disc_cand[k][j][c];
              bit tracks = 1;
              // After edge t the flop at delay j holds hist[t-j+1].
              for (int t = j; t < `DISC_TRK; t++)
                if (qh[t][i] !== (hist[t - j + 1][k] ^ disc_base[i])) tracks = 0;
              if (!tracks) keep.push_back(i);
              else n_tracking++;
            end
            disc_cand[k][j] = keep;
          end
        set_se(1'b1);
      end
    end

    // 4c. Two flops can still hold identical data: a register that takes io_in
    // only on scan-enable edges (the scan_q stub) is cell 1's twin.  Only the
    // one on the chain feeds the next cell (or, last, the scan-out pin): force
    // each candidate's Q to 0 and then 1 and keep the one the next cell follows.
    for (int k = 1; k <= N; k++)
      for (int j = 1; j <= len[k]; j++) begin
        int keep [$];
        if (disc_cand[k][j].size() <= 1) continue;
        if (j < len[k] && disc_cand[k][j+1].size() != 1) continue;
        foreach (disc_cand[k][j][c]) begin
          int i = disc_cand[k][j][c];
          logic r [2];
          for (int b = 0; b < 2; b++) begin
            disc_fv = logic'(b);
            disc_force(i);
            if (j < len[k]) begin
              cycle('0, got);
              r[b] = disc_q[disc_cand[k][j+1][0]];
            end else begin
              #(settle_ns);
              r[b] = so[k];
            end
            disc_release(i);
          end
          if (!$isunknown(r[0]) && !$isunknown(r[1]) && r[0] !== r[1]) keep.push_back(i);
          else n_twin++;
        end
        disc_cand[k][j] = keep;
      end

    // 5. resolve and write
    begin
      bit used [int];
      for (int k = 1; k <= N; k++)
        for (int j = 1; j <= len[k]; j++) begin
          total++;
          disc_cell[k][j] = -1;
          if (disc_cand[k][j].size() == 0) begin empty++; continue; end
          if (disc_cand[k][j].size() > 1) begin ambiguous++; continue; end
          disc_cell[k][j] = disc_cand[k][j][0];
          disc_inv[k][j] = disc_base[disc_cell[k][j]];
          if (used.exists(disc_cell[k][j])) reused++;
          used[disc_cell[k][j]] = 1;
        end
    end
    if (empty)     fail($sformatf("DISCOVER: %0d chain position(s) with no flop probe that follows the shifted data (a flop without Q/QN, or multibit?)", empty));
    if (ambiguous) fail($sformatf("DISCOVER: %0d chain position(s) still ambiguous after %0d random loads", ambiguous, `DISC_PASSES));
    if (reused)    fail($sformatf("DISCOVER: %0d probe(s) assigned to two positions", reused));
    fd = $fopen("discover.tsv", "w");
    if (fd == 0) fail("DISCOVER: cannot write discover.tsv");
    else begin
      for (int k = 1; k <= N; k++) begin
        $fdisplay(fd, "L\t%0d\t%0d\t%b", k, len[k], inv[k]);
        for (int j = 1; j <= len[k]; j++) begin
          if (disc_cell[k][j] < 0 && disc_cand[k][j].size() > 1) begin
            string l = $sformatf("A\t%0d\t%0d", k, j);
            foreach (disc_cand[k][j][c]) l = {l, $sformatf("\t%0d", disc_cand[k][j][c])};
            $fdisplay(fd, "%s", l);
          end
          if (disc_cell[k][j] >= 0)
            $fdisplay(fd, "C\t%0d\t%0d\t%0d\t%b\t%b", k, j, disc_cell[k][j], disc_inv[k][j],
                      disc_rst[disc_cell[k][j]]);
        end
      end
      $fclose(fd);
    end
    begin
      int n_inv = 0, n_rst_x = 0;
      for (int k = 1; k <= N; k++)
        for (int j = 1; j <= len[k]; j++)
          if (disc_cell[k][j] >= 0) begin
            n_inv += disc_inv[k][j] === 1'b1;
            n_rst_x += $isunknown(disc_rst[disc_cell[k][j]]);
          end
      $display("[%0t] DISCOVER: %0d cells on %0d chains: %0d resolved, %0d with an inverting path from scan-in, %0d X at reset; %0d position(s) had several candidates before the random loads; %0d off-chain flop change(s) after a 1 left its chain; %0d io_in-sampling flop(s) and %0d off-chain twin(s) set aside",
               $time, total, N, total - empty - ambiguous, n_inv, n_rst_x, flips, disturbed, n_tracking, n_twin);
    end
    set_se(1'b0);
    test_mode = 1'b0;
    idle(TM_SYNC);
  endtask
