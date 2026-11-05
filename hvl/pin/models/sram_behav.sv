///////////////////////////////////////////////////////////////////////////////
// sram_behav.sv -- LOCAL STAND-INS for the vendor SRAM macros, never sign-off.
//
// `SYNTHESIS sets USE_SRAM=1 (pkg/config.vh), so the netlist -- and the pin
// bench's `rtl` reference, built the same way -- goes through the wrappers in
// hdl/core/generic/mem/ram1p1rwbe_<D>x<W>.sv down to rf_sp_<D>_<W> / sram_sp_<D>_<W> macros whose
// models come with the PDK and are not in this repository.  On the VM the real
// models are compiled instead (hvl/pin/vm_paths.sh: SRAM_MODELS); this file
// exists only so the bench elaborates under Verilator.
//
// The wrappers do not connect BWEB: these macros write the whole row.  That is
// safe only because the D$ merges partial stores into the full line before
// re-encoding its line-wide ECC (hdl/core/cache/cacheway.sv, data array).  The
// `rtl` vs `rtl_sva` trace comparison checks it: rtl_sva uses the byte-masked
// behavioural RAM, so a cache that relied on the mask would diverge.
//
// RETN and EMA are ports, as on the PDK macros.  Anything but RETN=1 reads X,
// as the PDK model does in retention, so a wrapper that stops driving RETN
// fails here too.  EMA (margin) has no functional effect.
//
// Behaviour follows the RTL's behavioural RAM: address registered on an enabled
// edge, read combinational from it; active-low CEN/WEN.  The array is `logic`,
// so it starts X in a 4-state simulator.  Some macros are wider at the port
// than their name -- rf_sp_16_46 and rf_sp_32_45 are 48 bits, rf_sp_64_53 is 56
// and rf_sp_64_137 is 140 -- because the wrappers pad D and drop the top of Q.
///////////////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps

module pin_rf_sp #(parameter int DEPTH = 64, parameter int WIDTH = 128) (
  input  logic                     CLK, CEN, WEN,
  input  logic [$clog2(DEPTH)-1:0] A,
  input  logic [WIDTH-1:0]         D,
  output logic [WIDTH-1:0]         Q
);
  logic [WIDTH-1:0]         mem [DEPTH];
  logic [$clog2(DEPTH)-1:0] ad;
  always @(posedge CLK) if (!CEN) begin
    ad <= A;
    if (!WEN) mem[A] <= D;
  end
  assign Q = mem[ad];
endmodule

// PIN_RF_SP_GENERIC_ONLY: just pin_rf_sp, for hvl/pin/selftest/sram_cmp_tb.sv,
// which compares it with the PDK models of the same names.
`ifndef PIN_RF_SP_GENERIC_ONLY
`define PIN_RF_SP(NAME, DEP, WID) \
module NAME (input logic CLK, CEN, WEN, input logic [$clog2(DEP)-1:0] A, \
             input logic [WID-1:0] D, output logic [WID-1:0] Q, \
             input logic RETN, input logic [2:0] EMA); \
  logic [WID-1:0] q; \
  pin_rf_sp #(.DEPTH(DEP), .WIDTH(WID)) m (.CLK, .CEN, .WEN, .A, .D, .Q(q)); \
  assign Q = (RETN === 1'b1) ? q : {WID{1'bx}};  /* retention, as the PDK model */ \
endmodule

`PIN_RF_SP(rf_sp_64_128, 64, 128)
`PIN_RF_SP(rf_sp_64_46,  64, 46)
`PIN_RF_SP(rf_sp_64_44,  64, 44)
`PIN_RF_SP(rf_sp_32_128, 32, 128)
`PIN_RF_SP(rf_sp_32_45,  32, 48)
`PIN_RF_SP(rf_sp_16_128, 16, 128)
`PIN_RF_SP(rf_sp_16_46,  16, 48)
`PIN_RF_SP(rf_sp_64_53,  64, 56)
`PIN_RF_SP(rf_sp_64_137, 64, 140)
// One tag and one data array per cache (4f54add): exact width, no padding.
`PIN_RF_SP(sram_sp_128_137, 128, 137)
`PIN_RF_SP(sram_sp_128_53,  128, 53)
`PIN_RF_SP(sram_sp_256_137, 256, 137)
`PIN_RF_SP(sram_sp_256_53,  256, 53)
`endif
