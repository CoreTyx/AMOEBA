///////////////////////////////////////////////////////////////////////////////
// amoeba_uncore.sv
//
// The on-die uncore for the AMOEBA ASIC, derived from CVW's uncore.sv.
//
// What is here and why:
//   adrdecs + HSEL unswizzle      the same decode the core's PMA checker uses,
//                                 so the two never disagree about a region
//   ahbapbbridge + clint_apb      the CLINT stays on the die (BRINGUP.md s2):
//                                 ~2k GE, and mtime = core cycles by construction
//   uart_apb, plic_apb            PERIPH_ONCHIP=1 (this branch's primary
//                                 config): on the die, behind the same bridge
//   HRDATA/HREADY/HRESP muxes,    verbatim from uncore.sv, trimmed to the
//   hseldelayreg                  slaves that exist
//
// What is gone: GPIO, SPI, SDC, on-chip RAM, boot ROM.  All are
// *_SUPPORTED=0 in pkg/config_asic.vh; there is nothing to instantiate.
//
// PERIPH_ONCHIP=0 keeps the off-chip variant alive for the area comparison:
// PLIC and UART are then not instantiated, their selects are folded into
// HSELEXT so the accesses leave over the link with the PMA still treating
// the regions as uncached, non-idempotent peripherals, and the external
// interrupt lines come in on MExtIntIn/SExtIntIn instead.
///////////////////////////////////////////////////////////////////////////////

module amoeba_uncore import cvw::*; #(
  parameter cvw_t P,
  parameter logic   PERIPH_ONCHIP = 1'b1
)(
  // AHB-Lite from the core
  input  logic                 HCLK, HRESETn,
  input  logic [P.PA_BITS-1:0] HADDR,
  input  logic [P.AHBW-1:0]    HWDATA,
  input  logic [P.XLEN/8-1:0]  HWSTRB,
  input  logic                 HWRITE,
  input  logic [2:0]           HSIZE,
  input  logic [1:0]           HTRANS,
  // external port (to amoeba_link_master)
  input  logic [P.AHBW-1:0]    HRDATAEXT,
  input  logic                 HREADYEXT, HRESPEXT,
  output logic                 HSELEXT,
  // back to the core
  output logic [P.AHBW-1:0]    HRDATA,
  output logic                 HREADY, HRESP,
  output logic                 MTimerInt, MSwInt,
  output logic                 MExtInt, SExtInt,
  output logic [63:0]          MTIME_CLINT,
  // peripheral pins (PERIPH_ONCHIP=1)
  input  logic                 UARTSin,
  output logic                 UARTSout,
  input  logic [1:0]           ExtIrq,        // PLIC sources PLIC_GPIO_ID, PLIC_SPI_ID
  // external interrupt lines (PERIPH_ONCHIP=0)
  input  logic                 MExtIntIn, SExtIntIn
);

  localparam PERIPHS = 3;   // CLINT, PLIC, UART

  logic [11:0]                 HSELRegions;
  logic                        HSELDTIM, HSELIROM, HSELRam, HSELCLINT, HSELPLIC, HSELGPIO, HSELUART, HSELSDC, HSELSPI;
  logic                        HSELBootRom, HSELEXTRaw;
  logic                        HSELEXTD, HSELBRIDGE, HSELBRIDGED, HSELNoneD;
  logic [P.XLEN-1:0]           HREADBRIDGE;
  logic                        HRESPBRIDGE, HREADYBRIDGE;
  logic                        UARTIntr;

  logic                        PCLK, PRESETn, PWRITE, PENABLE;
  logic [PERIPHS-1:0]          PSEL, PREADY;
  logic [31:0]                 PADDR;
  logic [P.XLEN-1:0]           PWDATA;
  logic [P.XLEN/8-1:0]         PSTRB;
  logic [PERIPHS-1:0][P.XLEN-1:0] PRDATA;

  // Same decode as the PMA checker, access types don't-care (MMU has checked).
  adrdecs #(P) adrdecs(HADDR, 1'b1, 1'b1, 1'b1, HSIZE[1:0], HSELRegions);
  assign {HSELSPI, HSELSDC, HSELPLIC, HSELUART, HSELGPIO, HSELCLINT, HSELRam, HSELBootRom, HSELEXTRaw, HSELIROM, HSELDTIM} = HSELRegions[11:1];

  // Off-chip peripherals: their regions leave over the link.
  assign HSELEXT = PERIPH_ONCHIP ? HSELEXTRaw : (HSELEXTRaw | HSELPLIC | HSELUART);

  // AHB -> APB for the on-die peripherals.  PSEL[0]=CLINT, [1]=PLIC, [2]=UART.
  logic [PERIPHS-1:0] HSELAPB;
  assign HSELAPB = PERIPH_ONCHIP ? {HSELUART, HSELPLIC, HSELCLINT} : {2'b00, HSELCLINT};

  ahbapbbridge #(P, PERIPHS) ahbapbbridge (
    .HCLK, .HRESETn, .HSEL(HSELAPB), .HADDR, .HWDATA, .HWSTRB, .HWRITE, .HTRANS, .HREADY,
    .HRDATA(HREADBRIDGE), .HRESP(HRESPBRIDGE), .HREADYOUT(HREADYBRIDGE),
    .PCLK, .PRESETn, .PSEL, .PWRITE, .PENABLE, .PADDR, .PWDATA, .PSTRB, .PREADY, .PRDATA);
  assign HSELBRIDGE = |HSELAPB;

  clint_apb #(P) clint(.PCLK, .PRESETn, .PSEL(PSEL[0]), .PADDR(PADDR[15:0]), .PWDATA, .PSTRB, .PWRITE, .PENABLE,
    .PRDATA(PRDATA[0]), .PREADY(PREADY[0]), .MTIME(MTIME_CLINT), .MTimerInt, .MSwInt);

  if (PERIPH_ONCHIP) begin : onchip
    plic_apb #(P) plic(.PCLK, .PRESETn, .PSEL(PSEL[1]), .PADDR(PADDR[27:0]), .PWDATA, .PSTRB, .PWRITE, .PENABLE,
      .PRDATA(PRDATA[1]), .PREADY(PREADY[1]),
      .UARTIntr, .GPIOIntr(ExtIrq[0]), .SDCIntr(1'b0), .SPIIntr(ExtIrq[1]), .MExtInt, .SExtInt);

    uart_apb #(P) uart(
      .PCLK, .PRESETn, .PSEL(PSEL[2]), .PADDR(PADDR[2:0]), .PWDATA, .PSTRB, .PWRITE, .PENABLE,
      .PRDATA(PRDATA[2]), .PREADY(PREADY[2]),
      .SIN(UARTSin), .DSRb(1'b1), .DCDb(1'b1), .CTSb(1'b0), .RIb(1'b1),
      .SOUT(UARTSout), .RTSb(), .DTRb(),
      .OUT1b(), .OUT2b(), .INTR(UARTIntr), .TXRDYb(), .RXRDYb());
  end else begin : offchip
    assign PRDATA[1] = '0; assign PREADY[1] = 1'b1;
    assign PRDATA[2] = '0; assign PREADY[2] = 1'b1;
    assign UARTIntr  = 1'b0;
    assign UARTSout  = 1'b1;   // idle mark
    assign MExtInt   = MExtIntIn;
    assign SExtInt   = SExtIntIn;
  end

  // AHB read / response / ready muxes, from uncore.sv, for the slaves that exist.
  assign HRDATA = ({P.XLEN{HSELEXTD}}    & HRDATAEXT) |
                  ({P.XLEN{HSELBRIDGED}} & HREADBRIDGE);

  assign HRESP  = HSELEXTD    & HRESPEXT |
                  HSELBRIDGED & HRESPBRIDGE;

  assign HREADY = HSELEXTD    & HREADYEXT |
                  HSELBRIDGED & HREADYBRIDGE |
                  HSELNoneD;   // don't lock up the bus if no region is being accessed

  // Address-phase select delayed into the data phase, held while the slave
  // inserts wait states (AHB spec figure 4-2).  None selected on reset.
  logic [2:0] hseld;
  flopenl #(3) hseldelayreg(HCLK, ~HRESETn, HREADY, {HSELBRIDGE, HSELEXT, ~(HSELBRIDGE | HSELEXT)}, 3'b001, hseld);
  assign {HSELBRIDGED, HSELEXTD, HSELNoneD} = hseld;

endmodule
