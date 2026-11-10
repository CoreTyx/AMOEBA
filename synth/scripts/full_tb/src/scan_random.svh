// Randomized first-edge scan cases. Control remains at the reset baseline;
// legal data patterns and explicitly modeled fault effects form the oracle.
function automatic val_t edge_or_random(input int i);
  case (i % 8)
    0: return '0;
    1: return '1;
    2: return val_t'(64'h8000_0000_0000_0000);
    3: return val_t'(64'h7fff_ffff_ffff_ffff);
    4: return {MAX_W/2{2'b01}};
    5: return {MAX_W/2{2'b10}};
    default: return rand_val();
  endcase
endfunction

task automatic phase_r();
  st_t ld, ex;
  int complete[$];
  int incomplete[$];
  bit exclusions_reported = 0;
  int kinds[5] = '{default:0};
  int legal_mpp[3] = '{0,1,3};
  bit seen_sec[MAX_REGS][ECC_CW];
  foreach (ecc_r[i]) begin
    int r = ecc_r[i];
    if (reg_cells[r] == ECC_CW) complete.push_back(r);
    else incomplete.push_back(r);
  end
  n_pat = 0; n_pat_bad = 0;
  $display("[%0t] R: %0d multi-register iterations, seed=%0d", $time, random_iters, scan_seed);
  for (int i = 0; i < random_iters; i++) begin
    int kind = i % 5, r = -1, b0, b1;
    string tag;
    ld = base;
    for (int rr = 0; rr < n_regs; rr++) begin
      val_t v = edge_or_random(i + rr);
      case (reg_kind[rr])
        K_PC, K_DATA, K_STICKY: ld = reg_put(ld, rr, v);
        K_ECC: if (reg_cells[rr] == ECC_CW)
          ld = reg_put(ld, rr, val_t'(ecc_enc(v[63:0])));
        K_MPP: ld = reg_put(ld, rr, val_t'(legal_mpp[i % 3]));
        // Keep hardware flags initially clear so each injected fault is visible.
        K_MSECFAULT: ld = reg_put(ld, rr, '0);
        default: ; // inert CTRL and coherent M-mode TMR copies
      endcase
    end
    ex = ld;
    tag = $sformatf("R iteration %0d valid", i);
    if (kind inside {1,2,3}) begin
      bit flags_visible = msf_r >= 0;
      tag = $sformatf("R iteration %0d %s", i,
                     kind == 1 ? "SEC" : (kind == 2 ? "DED" : "parity-only"));
      if (flags_visible) begin
        if (kind != 2) flags_visible &= reg_k[msf_r][MSF_ECC_SEC] > 0;
        if (kind != 1) flags_visible &= reg_k[msf_r][MSF_ECC_DED] > 0;
      end
      if (complete.size() == 0 || !flags_visible) begin
        if (case_selected(tag)) skip_check(tag, "fault cases require complete ECC and MSECFAULT mappings");
        continue;
      end
      r = complete[(i / 5) % complete.size()];
      b0 = (i / (5 * complete.size())) % ECC_CW;
      if (kind == 3) b0 = ECC_R;
      else if (b0 == ECC_R) b0 = ECC_R + 1;
      b1 = (b0 + 1 + $urandom_range(ECC_CW-2)) % ECC_CW;
      ld = reg_put(ld, r, reg_val(ld, r) ^ (val_t'(1) << b0));
      if (kind == 1) begin
        ex = with_flag(ex, MSF_ECC_SEC);
      end else if (kind == 2) begin
        ld = reg_put(ld, r, reg_val(ld, r) ^ (val_t'(1) << b1));
        ex = with_flag(ld, MSF_ECC_DED);
      end else ex = ld; // current decoder neither flags nor repairs parity-only
      tag = {tag, $sformatf(" %s bits=%0d/%0d", reg_name[r], b0, kind == 2 ? b1 : b0)};
    end else if (kind == 4) begin
      int c = (i / 5) % 6;
      tag = $sformatf("R iteration %0d TMR copy=%0d", i, c);
      if (tmr_r[c] < 0 || msf_r < 0 ||
          reg_k[tmr_r[c]][0] == 0 || reg_k[tmr_r[c]][1] == 0 || reg_k[msf_r][MSF_TMR_SEC] == 0) begin
        if (case_selected(tag)) skip_check(tag, "TMR fault case requires privilege-copy and MSECFAULT mappings");
        continue;
      end
      ld = reg_put(ld, tmr_r[c], '0);
      ex = with_flag(ld, MSF_TMR_SEC);
    end
    if (case_selected(tag)) begin
      if (!exclusions_reported) begin
        foreach (incomplete[ii])
          skip_check({"R ", reg_name[incomplete[ii]]}, "incomplete ECC mapping; randomized codewords excluded");
        exclusions_reported = 1;
      end
      kinds[kind]++;
      if (kind == 1) seen_sec[r][b0] = 1;
    end
    hold(tag, ld, ex);
  end
  $display("[%0t] R COVERAGE: valid=%0d SEC=%0d DED=%0d parity-only=%0d TMR=%0d comparisons=%0d failed=%0d",
           $time, kinds[0], kinds[1], kinds[2], kinds[3], kinds[4], n_pat, n_pat_bad);
  foreach (complete[i]) begin
    int r = complete[i], count = 0;
    for (int b = 0; b < ECC_CW; b++) count += int'(seen_sec[r][b]);
    $display("R COVERAGE: %s SEC distinct stimulus bits=%0d/71 (overall parity excluded)", reg_name[r], count);
  end
endtask
