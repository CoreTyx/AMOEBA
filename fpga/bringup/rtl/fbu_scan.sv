///////////////////////////////////////////////////////////////////////////////
// fbu_scan.sv -- the test-mode pins: a pattern out on io[7:0], a capture of
// io[15:8] (docs/impl_plan_fpga_rtl_freeze.md s5.5, CTRL-14..18).
//
// A session runs `len` cycles.  In cycle k it drives pattern[k][7:0] on
// io[7:0] and, when cfg_pattern_scan_en is set, pattern[k][8] on scan_en
// (otherwise the PIN_CTRL bit), and it captures io[15:8] into capture[k].
// The frozen chip's stub is `scan_q <= io[7:0]` while test_mode, scan_en and
// unlocked, with io[15:8] = scan_q, so the capture is the pattern a fixed
// number of cycles late while scan_en is high, held while it is low; the PS
// checks that exactly.  The PS writes the pattern and reads the capture one
// entry at a time at `addr`.
//
// keep_hierarchy: Vivado 2024.1's cross-boundary optimisation of the whole
// PL top removes the capture memory (silently; the gateware synthesized alone
// keeps it), and every capture then reads 0.  make test-scan-netlist checks
// the synthesized result.
///////////////////////////////////////////////////////////////////////////////
(* keep_hierarchy = "yes" *)
module fbu_scan #(
  parameter int DEPTH_LOG2 = 10
)(
  input  logic                  clk,
  input  logic                  arst_n,

  input  logic                  start,
  input  logic [DEPTH_LOG2:0]   cfg_len,
  input  logic                  cfg_pattern_scan_en,
  input  logic                  cfg_scan_en,

  input  logic [DEPTH_LOG2-1:0] addr,
  input  logic                  pattern_write,
  input  logic [8:0]            pattern_data,
  output logic [7:0]            capture_data,

  input  logic [7:0]            scan_out,
  output logic [7:0]            scan_in,
  output logic                  scan_en,
  output logic                  running,
  output logic                  done
);

  logic [8:0]            pattern [1 << DEPTH_LOG2];
  logic [7:0]            capture [1 << DEPTH_LOG2];
  logic [DEPTH_LOG2:0]   index;

  always_ff @(posedge clk)
    if (pattern_write)
      pattern[addr] <= pattern_data;

  always_ff @(posedge clk)
    if (running)
      capture[index[DEPTH_LOG2-1:0]] <= scan_out;

  assign capture_data = capture[addr];

  always_ff @(posedge clk or negedge arst_n)
    if (!arst_n) begin
      running <= 1'b0;
      done    <= 1'b0;
      index   <= '0;
      scan_in <= '0;
      scan_en <= 1'b0;
    end else if (start) begin
      running <= cfg_len != '0;
      done    <= cfg_len == '0;
      index   <= '0;
    end else if (running) begin
      scan_in <= pattern[index[DEPTH_LOG2-1:0]][7:0];
      scan_en <= cfg_pattern_scan_en ? pattern[index[DEPTH_LOG2-1:0]][8] : cfg_scan_en;
      index   <= index + 1'b1;
      if (index + 1'b1 == cfg_len) begin
        running <= 1'b0;
        done    <= 1'b1;
      end
    end else begin
      scan_en <= cfg_scan_en;
    end

endmodule
