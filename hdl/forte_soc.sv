///////////////////////////////////////////////////////////////////////////////
// forte_soc.sv
//
// wallypipelinedcore + forte_uncore.  Replaces wallypipelinedsoc for the
// ASIC: same core, same reset synchroniser, a purpose-built uncore, and only
// the pins the die has.  The external AHB port is byte-identical to the one
// wallypipelinedsoc exposes, so forte_link_master is a drop-in for
// ahb_to_memitf.
///////////////////////////////////////////////////////////////////////////////


module forte_soc import cvw::*; #(
  parameter cvw_t P,
  parameter logic   PERIPH_ONCHIP = 1'b1
)(
  input  logic                  core_clk,
  input  logic                  reset_ext,        // external asynchronous reset
  output logic                  reset,            // reset synchronised to core_clk
  input  logic                  ExternalStall,
// Master fault-injection pin; the core ANDs it with the per-unit APB mask.
  input  logic                  fault_inject,
  // external AHB-Lite port
  input  logic [P.AHBW-1:0]     HRDATAEXT,
  input  logic                  HREADYEXT, HRESPEXT,
  output logic                  HSELEXT,
  output logic                  HCLK, HRESETn,
  output logic [P.PA_BITS-1:0]  HADDR,
  output logic [P.AHBW-1:0]     HWDATA,
  output logic [P.XLEN/8-1:0]   HWSTRB,
  output logic                  HWRITE,
  output logic [2:0]            HSIZE,
  output logic [2:0]            HBURST,
  output logic [3:0]            HPROT,
  output logic [1:0]            HTRANS,
  output logic                  HMASTLOCK,
  output logic                  HREADY,
  // 1 = DFT permitted (hdl/forte_dft_lock.sv), from the uncore to forte_chip.
  output logic                  dft_unlocked,
  // pins
  input  logic                  UARTSin,
  output logic                  UARTSout,
  input  logic [1:0]            ExtIrq,
  input  logic                  MExtIntIn, SExtIntIn
);

  logic [P.AHBW-1:0]          HRDATA;
  logic                       HRESP;
  logic                       MTimerInt, MSwInt;
  logic [63:0]                MTIME_CLINT;
  logic                       MExtInt, SExtInt;

  logic [5:0] FaultInjectMask; // software unit enables from the on-die APB register

  // As wallypipelinedsoc: two-flop synchroniser on the asynchronous reset.
  synchronizer resetsync(.clk(core_clk), .d(reset_ext), .q(reset));

  wallypipelinedcore #(P) core(.clk(core_clk), .reset, .fault_inject, .FaultInjectMask,
    .MTimerInt, .MExtInt, .SExtInt, .MSwInt, .MTIME_CLINT,
    .HRDATA, .HREADY, .HRESP, .HCLK, .HRESETn, .HADDR, .HWDATA, .HWSTRB,
    .HWRITE, .HSIZE, .HBURST, .HPROT, .HTRANS, .HMASTLOCK, .ExternalStall,
    // Register-file ECC fault report, added on Making_HDL_Synthesizable.  Left
    // open as rv64_core_wrapper does: nothing in the ASIC consumes it yet, and
    // routing it to a pad is a decision for the DFT discussion.
    .PrivModeUncorrectableFaultW (),
    // SEC (corrected-error) counters for the register file and both caches, added on
    // swe-cache-ec. wallypipelinedsoc serves them as read-only registers at ECC_COUNTER_BASE via
    // uncore.sv; forte_uncore has no such slave yet, so they are left open here for the same
    // reason as above. Exposing them on the ASIC is a separate decision (see forte_uncore.sv).
    .RegfileSecCount (), .ICacheSecCount (), .DCacheSecCount ());

  forte_uncore #(.P(P), .PERIPH_ONCHIP(PERIPH_ONCHIP)) uncore(
    .HCLK, .HRESETn, .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HTRANS,
    .HRDATAEXT, .HREADYEXT, .HRESPEXT, .HSELEXT,
    .HRDATA, .HREADY, .HRESP,
    .dft_unlocked, .FaultInjectMask,
    .MTimerInt, .MSwInt, .MExtInt, .SExtInt, .MTIME_CLINT,
    .UARTSin, .UARTSout, .ExtIrq, .MExtIntIn, .SExtIntIn);

endmodule
