// Package-output Z diagnostics, independent of phase selection and verdicts.
// Observe value/control changes (including startup), not just clock samples.
// These are digital simulation events, not pulse-width or electrical checks.
localparam int OUTPUT_Z_W = N + 5;
wire [OUTPUT_Z_W-1:0] output_z_pins = {status, uart_tx, clk_out, wr, req, io_out};
bit output_z_ready = 0;
bit [OUTPUT_Z_W-1:0] output_z_previous, output_z_ever;
bit [OUTPUT_Z_W-1:0] output_z_reported [0:12][0:3];
longint unsigned output_z_episodes [0:OUTPUT_Z_W-1];
int output_z_phase = 12; // startup, before phase A

function automatic string output_z_pin_name(input int p);
  if (p < N) return $sformatf("io_out[%0d]", p);
  case (p-N)
    0: return "req";
    1: return "wr";
    2: return "clk_out";
    3: return "uart_tx";
    4: return "status";
    default: return "invalid";
  endcase
endfunction

function automatic string output_z_context_name(input int c);
  case (c)
    0: return "reset_or_unknown_reset";
    1: return "scan_shift_pins";
    2: return "test_mode_no_shift";
    default: return "functional_or_arm";
  endcase
endfunction

task automatic output_z_sample();
  bit [OUTPUT_Z_W-1:0] z;
  int context_id;
  string phase_label;
  if (output_z_phase == 12) phase_label = "startup";
  else phase_label = phase_names[output_z_phase];
  context_id = rst_n !== 1'b1 ? 0 :
               (test_mode === 1'b1 ? (scan_en === 1'b1 ? 1 : 2) : 3);
  for (int p = 0; p < OUTPUT_Z_W; p++) begin
    z[p] = output_z_pins[p] === 1'bz; // X is intentionally not classified as Z
    if (z[p]) begin
      output_z_ever[p] = 1;
      if (!output_z_previous[p]) output_z_episodes[p]++;
      if (!output_z_reported[output_z_phase][context_id][p]) begin
        output_z_reported[output_z_phase][context_id][p] = 1;
        $display("[%0t] OUTPUT Z: pin=%s phase=%s context=%s RST_N=%b TM=%b SE=%b link_active=%b link_paused=%b outputs=%b (warning; diagnostic only)",
                 $time, output_z_pin_name(p),
                 phase_label,
                 output_z_context_name(context_id), rst_n, test_mode, scan_en,
                 link_active, link_paused, output_z_pins);
      end
    end
  end
  output_z_previous = z;
endtask

initial begin
  foreach (output_z_episodes[p]) output_z_episodes[p] = 0;
  output_z_ready = 1;
  output_z_sample();
end

always @(output_z_pins or rst_n or test_mode or scan_en or
         link_active or link_paused or output_z_phase)
  if (output_z_ready) output_z_sample();

task automatic output_z_summary();
  $display("OUTPUT Z SUMMARY: diagnostic only; event-based from startup; contexts use package TM/SE, not effective internal SE; episodes count observed entries into Z");
  for (int p = 0; p < OUTPUT_Z_W; p++)
    $display("OUTPUT Z SUMMARY: pin=%s ever_z=%0b episodes=%0d",
             output_z_pin_name(p), output_z_ever[p], output_z_episodes[p]);
endtask
