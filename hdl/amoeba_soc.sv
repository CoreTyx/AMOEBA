///////////////////////////////////////////////////////////////////////////////
// amoeba_soc.sv
//
// wallypipelinedcore + amoeba_uncore.  Replaces wallypipelinedsoc for the
// ASIC: same core, same reset synchroniser, a purpose-built uncore, and only
// the pins the die has.  The external AHB port is byte-identical to the one
// wallypipelinedsoc exposes, so amoeba_link_master is a drop-in for
// ahb_to_memitf.
///////////////////////////////////////////////////////////////////////////////


module amoeba_soc import cvw::*; #(
  parameter cvw_t P,
  parameter logic   PERIPH_ONCHIP = 1'b1
)(
  input  logic                  clk,
  input  logic                  reset_ext,        // external asynchronous reset
  output logic                  reset,            // reset synchronised to clk
  input  logic                  ExternalStall,
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

  // As wallypipelinedsoc: two-flop synchroniser on the asynchronous reset.
  synchronizer resetsync(.clk, .d(reset_ext), .q(reset));

  wallypipelinedcore #(P) core(.clk, .reset,
    .MTimerInt, .MExtInt, .SExtInt, .MSwInt, .MTIME_CLINT,
    .HRDATA, .HREADY, .HRESP, .HCLK, .HRESETn, .HADDR, .HWDATA, .HWSTRB,
    .HWRITE, .HSIZE, .HBURST, .HPROT, .HTRANS, .HMASTLOCK, .ExternalStall);

  amoeba_uncore #(.P(P), .PERIPH_ONCHIP(PERIPH_ONCHIP)) uncore(
    .HCLK, .HRESETn, .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HSIZE, .HTRANS,
    .HRDATAEXT, .HREADYEXT, .HRESPEXT, .HSELEXT,
    .HRDATA, .HREADY, .HRESP,
    .MTimerInt, .MSwInt, .MExtInt, .SExtInt, .MTIME_CLINT,
    .UARTSin, .UARTSout, .ExtIrq, .MExtIntIn, .SExtIntIn);

endmodule
