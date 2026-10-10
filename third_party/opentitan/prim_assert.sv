// WRITTEN FOR THIS REPO -- NOT OpenTitan source.  See README.md.
//
// prim_fifo_async.sv does `include "prim_assert.sv" and uses exactly two
// macros.  Upstream's prim_assert.sv pulls in four more headers plus
// prim_flop_macros.sv, which is disproportionate for vendoring one module.
// This provides the two macros it needs and nothing else.
`ifndef PRIM_ASSERT_SV
`define PRIM_ASSERT_SV

// Elaboration-time check.  This one earns its keep: prim_fifo_async is correct
// only for a power-of-two Depth, and ParamCheckDepth_A is what catches a bad
// parameter.  Works in every simulator.
`define ASSERT_INIT(__name, __prop)                                        \
  initial begin                                                            \
    if (!(__prop)) $fatal(1, "ASSERT_INIT(%s) failed", `"__name`");        \
  end

// Concurrent assertion.  Upstream passes the disable condition (active high) as
// the fourth argument.
//
// prim_fifo_async's two uses (GrayWptr_A, GrayRptr_A) are both of the form
// `##1 $countones(ptr ^ $past(ptr)) <= 1`, and Verilator 5.026 cannot evaluate
// a `##` cycle delay inside a sequence expression -- it is a hard
// %Error-UNSUPPORTED, not a warning.  So the macro is real under VCS, which has
// full SVA, and empty under Verilator.
//
// The invariant is NOT lost: tb/tb_prim_fifo_async.sv checks the same property
// (at most one Gray-pointer bit changes per clock) in a form Verilator runs.
`ifdef ECE411_VERILATOR
  `define ASSERT(__name, __prop, __clk, __rst)
`else
  `define ASSERT(__name, __prop, __clk, __rst)                             \
    __name: assert property (@(posedge __clk) disable iff (__rst) (__prop)) \
      else $fatal(1, "ASSERT(%s) failed", `"__name`");
`endif

`endif
