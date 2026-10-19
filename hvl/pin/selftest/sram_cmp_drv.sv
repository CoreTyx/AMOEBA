///////////////////////////////////////////////////////////////////////////////
// sram_cmp_drv.sv -- does a PDK SRAM model behave the way the RTL assumes?
//
// Under `SYNTHESIS (USE_SRAM=1) the caches use rf_sp_<D>_<W> macros.  The
// RTL's own behavioural RAM (hdl/core/generic/mem/ram1p1rwbe.sv, `ram`
// branch) registers the address on an enabled edge and reads combinationally
// from it -- so the cycle after a write, Q shows the NEW data -- and every
// earlier regression ran on that model.  hvl/pin/models/sram_behav.sv's
// pin_rf_sp implements exactly that.  This drives a PDK model and pin_rf_sp
// with identical random traffic and compares Q every cycle, so any behaviour
// the caches were never verified against shows up here with the operation
// that exposed it, rather than as an X on a pin thousands of cycles later.
//
// Inputs change at the negedge; Q is compared at the next negedge, i.e. after
// the posedge that executed the operation.  Phase 1 writes every address once
// (so "never written" is not a difference); phase 2 is random reads, writes
// and idle cycles over a few addresses, so read-after-write and write-after-
// read hit the same word often.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module sram_cmp_drv #(parameter int DEPTH = 64, parameter int WIDTH = 128,
                      parameter string NAME = "?", parameter int CYCLES = 20000) (
  input  logic                     clk,
  output logic                     cen, wen,
  output logic [$clog2(DEPTH)-1:0] a,
  output logic [WIDTH-1:0]         d,
  input  wire  [WIDTH-1:0]         q_model,   // the PDK model
  input  wire  [WIDTH-1:0]         q_ref      // pin_rf_sp: what the RTL assumes
);
  localparam int AW = $clog2(DEPTH);
  typedef enum {OP_IDLE, OP_READ, OP_WRITE} op_t;

  int  diffs = 0, cycles = 0;
  int  by_op[3] = '{0, 0, 0};
  bit  done = 0;
  logic [63:0] prng = 64'h2545_F491_4F6C_DD1D;
  function automatic logic [63:0] rnd();
    prng ^= prng << 13; prng ^= prng >> 7; prng ^= prng << 17;
    return prng;
  endfunction
  localparam int NW = (WIDTH + 63) / 64;
  function automatic logic [WIDTH-1:0] rnd_word();
    logic [64*NW-1:0] w;
    for (int k = 0; k < NW; k++) w[64*k +: 64] = rnd();
    return w[WIDTH-1:0];
  endfunction
  function automatic string opname(input op_t o);
    return o == OP_READ ? "read" : o == OP_WRITE ? "write" : "idle";
  endfunction

  op_t         op;               // the operation whose result check() compares

  task automatic issue(input op_t o, input logic [AW-1:0] addr);
    op = o; a = addr;
    cen = (o == OP_IDLE);
    wen = (o != OP_WRITE);
    d   = rnd_word();
  endtask

  task automatic check();
    cycles++;
    if (q_model !== q_ref) begin
      diffs++; by_op[op]++;
      if (diffs <= 3)
        $display("SRAM_CMP %s: cycle %0d, after %s of addr %0d: model Q=%h, RTL assumes %h",
                 NAME, cycles, opname(op), a, q_model, q_ref);
    end
  endtask

  initial begin
    cen = 1; wen = 1; a = '0; d = '0; op = OP_IDLE;
    // phase 1: every address written once
    for (int i = 0; i < DEPTH; i++) begin
      @(negedge clk); if (i) check();
      issue(OP_WRITE, AW'(i));
    end
    // phase 2: random traffic over 4 addresses
    repeat (CYCLES) begin
      logic [63:0] r;
      @(negedge clk); check();
      r = rnd();
      issue(r[2:0] < 3 ? OP_READ : r[2:0] < 6 ? OP_WRITE : OP_IDLE, AW'(r[9:8]));
    end
    @(negedge clk); check();
    $display("SRAM_CMP %s: %0d cycles, %0d differences (after read %0d, after write %0d, after idle %0d)",
             NAME, cycles, diffs, by_op[OP_READ], by_op[OP_WRITE], by_op[OP_IDLE]);
    done = 1;
  end
endmodule
