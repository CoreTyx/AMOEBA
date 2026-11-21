// Phase S invariants. Included after res_snap()/res_compare().
// Observe settled state midway between clock edges; boundary samples cover
// the last held edge before exit. Scanned cells are stable only in tm mode.
bit res_mon = 0, res_hold_mon = 0, res_cells_mon = 0;
bit res_control_mon = 0, res_arm_suspect = 0;
bit res_retention_failed, res_link_failed, res_lock_failed, res_se_failed;
int res_req_n, res_wr_n, res_link_err0;
int res_req_z_n, res_wr_z_n, res_req_x_n, res_wr_x_n;
int res_hold_samples, res_retention_bad, res_lock_bad, res_se_bad;
logic res_lock_start;
string res_check_tag, res_check_variant;
res_snap_t res_hold_ref;
localparam string RES_HOLD_CSR [5] = '{"MSCRATCH", "MTVEC", "MEPC", "MCAUSE", "MTVAL"};

function automatic bit res_checks_csr_complete();
  if (!DIAG_CSR_OK) return 0;
  foreach (RES_HOLD_CSR[i])
    if (!diag_csr_by_name.exists(RES_HOLD_CSR[i])) return 0;
  return 1;
endfunction

task automatic res_checks_require_probes();
  if (!DIAG_RF_OK) skip_check("S RF retention", "register-file probes unavailable");
  foreach (RES_HOLD_CSR[i])
    if (!DIAG_CSR_OK || !diag_csr_by_name.exists(RES_HOLD_CSR[i]))
      skip_check({"S CSR retention ", RES_HOLD_CSR[i]}, "CSR probe unavailable");
  if (!DIAG_LOCK_OK) skip_check("S DFT lock", "permission probe unavailable");
  if (!DIAG_SE_OK) skip_check("S scan-enable qualification", "effective scan-enable probe unavailable");
  $display("S CHECK COVERAGE: rf=%0b csrs=%0d lock=%0b effective_se=%0b scan_registers=%0d",
           DIAG_RF_OK, diag_csr_by_name.num(), DIAG_LOCK_OK, DIAG_SE_OK, internal_raw_by_name.num());
endtask

// Package pads can be disabled by DFT insertion. Only a definite one proves
// an asserted handshake; keep X/Z visible without treating them as activity.
task automatic res_checks_link_pin(input string pin_name, input logic value,
                                  inout int asserted, z_samples, x_samples);
  case (value)
    1'b1: asserted++;
    1'bz: begin
      if (z_samples == 0)
        $display("[%0t] WARNING: %s: S paused-link %s=Z (pad may be disabled; internal isolation unproven)",
                 $time, res_check_tag, pin_name);
      z_samples++;
    end
    1'bx: begin
      if (x_samples == 0)
        $display("[%0t] WARNING: %s: S paused-link %s=X (assertion state unknown)",
                 $time, res_check_tag, pin_name);
      x_samples++;
    end
    default: ; // known zero: idle
  endcase
endtask

task automatic res_checks_sample();
  if (res_mon) begin
    res_checks_link_pin("req", req, res_req_n, res_req_z_n, res_req_x_n);
    res_checks_link_pin("wr", wr, res_wr_n, res_wr_z_n, res_wr_x_n);
    if ((req === 1'b1 || wr === 1'b1 || link.errors != res_link_err0) && !res_link_failed) begin
      res_link_failed = 1;
      fail($sformatf("%s: S isolation violation: req=%b wr=%b agent_errors=%0d while link paused",
                     res_check_tag, req, wr, link.errors - res_link_err0));
    end
    if (res_control_mon && DIAG_LOCK_OK && diag_dft_unlocked !== 1'b1) begin
      res_lock_bad++;
      if (!res_lock_failed) begin
        res_lock_failed = 1;
        fail($sformatf("%s: S DFT permission violation: unlocked=%b during session",
                       res_check_tag, diag_dft_unlocked));
      end
    end
    if (res_control_mon && DIAG_SE_OK && test_mode === 1'b0 && diag_scan_en_dft !== 1'b0) begin
      res_se_bad++;
      if (!res_se_failed) begin
        res_se_failed = 1;
        fail($sformatf("%s: S scan-enable violation: effective SE=%b outside test mode",
                       res_check_tag, diag_scan_en_dft));
      end
    end
  end
  if (res_hold_mon) begin
    int rows, same;
    string detail;
    res_snap_t now_state = res_snap();
    res_hold_samples++;
    res_compare(res_check_tag, res_hold_ref, now_state, res_cells_mon, rows, same, detail, 1);
    if (detail != "") begin
      res_retention_bad++;
      if (!res_retention_failed) begin
        res_retention_failed = 1;
        fail($sformatf("%s: S retention violation during settled hold: %s", res_check_tag, detail));
      end
    end
  end
endtask

always @(negedge clk) res_checks_sample();

task automatic res_checks_begin(input string tag, input string variant);
  res_check_tag = tag; res_check_variant = variant;
  res_req_n = 0; res_wr_n = 0; res_link_err0 = link.errors;
  res_req_z_n = 0; res_wr_z_n = 0; res_req_x_n = 0; res_wr_x_n = 0;
  res_hold_samples = 0; res_retention_bad = 0; res_lock_bad = 0; res_se_bad = 0;
  res_retention_failed = 0; res_link_failed = 0; res_lock_failed = 0; res_se_failed = 0;
  res_arm_suspect = 0; res_hold_mon = 0; res_cells_mon = 0;
  res_control_mon = variant != "ctl";
  res_lock_start = diag_dft_unlocked;
  res_mon = 1;
  res_checks_sample();
endtask

task automatic res_checks_hold_begin(input res_snap_t state_at_entry, input bit check_cells);
  if (check_cells && internal_raw_by_name.num() == 0)
    skip_check({res_check_tag, " hold-only scan-cell retention"}, "scan-cell probes unavailable");
  res_hold_ref = state_at_entry;
  res_cells_mon = check_cells;
  res_hold_mon = 1;
endtask

task automatic res_checks_hold_end();
  res_checks_sample();
  res_hold_mon = 0; // exit synchronizer clocks may legitimately resume execution
endtask

task automatic res_checks_end();
  string retention_status, lock_status, se_status, isolation_status;
  if (res_hold_mon) res_checks_hold_end();
  res_checks_sample();
  res_mon = 0;
  if (res_control_mon && res_hold_samples == 0) begin
    res_retention_failed = 1;
    fail({res_check_tag, ": S retention monitor observed no held samples"});
  end
  retention_status = res_check_variant == "ctl" ? "N/A" :
                     (res_retention_failed ? "FAIL" :
                     (!DIAG_RF_OK || !res_checks_csr_complete() ||
                      (res_cells_mon && internal_raw_by_name.num() == 0) ? "PARTIAL" : "PASS"));
  lock_status = !res_control_mon ? "N/A" : (!DIAG_LOCK_OK ? "UNAVAILABLE" :
                (res_lock_failed ? "FAIL" : "PASS"));
  se_status = !res_control_mon ? "N/A" : (!DIAG_SE_OK ? "UNAVAILABLE" :
              (res_se_failed ? "FAIL" : "PASS"));
  isolation_status = res_link_failed ? "FAIL" :
                     ((res_req_z_n || res_wr_z_n || res_req_x_n || res_wr_x_n) ? "WARN" : "PASS");
  $display("S CHECKS: %s isolation=%s req_asserted_samples=%0d wr_asserted_samples=%0d req_z_samples=%0d wr_z_samples=%0d req_x_samples=%0d wr_x_samples=%0d agent_errors=%0d",
           res_check_tag, isolation_status, res_req_n, res_wr_n,
           res_req_z_n, res_wr_z_n, res_req_x_n, res_wr_x_n, link.errors-res_link_err0);
  $display("S CHECKS: %s retention=%s samples=%0d bad_samples=%0d rf=%0b csrs=%0d scan_cells_checked=%0b",
           res_check_tag, retention_status, res_hold_samples, res_retention_bad,
           DIAG_RF_OK, diag_csr_by_name.num(), res_cells_mon);
  $display("S CHECKS: %s lock=%s start=%b end=%b bad_samples=%0d effective_se=%s bad_samples=%0d arm_pattern_suspect=%0b(heuristic)",
           res_check_tag, lock_status, res_lock_start, diag_dft_unlocked, res_lock_bad,
           se_status, res_se_bad, res_arm_suspect);
endtask
