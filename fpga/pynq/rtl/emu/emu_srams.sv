///////////////////////////////////////////////////////////////////////////////
// emu_srams.sv -- FPGA stand-ins for the vendor SRAM macros.
//
// `SYNTHESIS sets USE_SRAM=1 (pkg/config.vh), so the cache and predictor
// arrays go through hdl/core/generic/mem/ram1p1rwbe_<D>x<W>.sv down to
// rf_sp_<D>_<W> / sram_sp_<D>_<W>.  The PDK models are not synthesizable and not
// in this repository; these are.
//
// Port widths are exactly those of hvl/pin/models/sram_behav.sv (some macros
// are wider at the port than their name, because the wrappers pad D and drop
// the top of Q).  fpga/scripts/check_frozen.sh diffs the macro table below
// against that file.
//
// Behaviour equals the bench model's -- address registered on an enabled edge,
// read from it -- written in the canonical write-first form so Vivado infers
// block RAM or LUTRAM: with one port, the registered-address read and the
// registered write-first read return the same data on every cycle.
//
// RETN: the PDK model reads X in retention.  Hardware has no X, so the
// stand-in reads all ones, which every SECDED array reports as uncorrectable.
// Every wrapper ties RETN to 1'b1 (the fix from the post-synth bench);
// check_frozen.sh checks that statically, which is where this can be caught.
///////////////////////////////////////////////////////////////////////////////

module emu_rf_sp #(parameter int DEPTH = 64, parameter int WIDTH = 128) (
  input  logic                     CLK, CEN, WEN,
  input  logic [$clog2(DEPTH)-1:0] A,
  input  logic [WIDTH-1:0]         D,
  output logic [WIDTH-1:0]         Q
);
  logic [WIDTH-1:0] mem [DEPTH];
  always_ff @(posedge CLK) if (!CEN) begin
    if (!WEN) begin
      mem[A] <= D;
      Q      <= D;
    end else
      Q      <= mem[A];
  end
endmodule

`define EMU_RF_SP(NAME, DEP, WID) \
module NAME (input logic CLK, CEN, WEN, input logic [$clog2(DEP)-1:0] A, \
             input logic [WID-1:0] D, output logic [WID-1:0] Q, \
             input logic RETN, input logic [2:0] EMA); \
  logic [WID-1:0] q; \
  emu_rf_sp #(.DEPTH(DEP), .WIDTH(WID)) m (.CLK, .CEN, .WEN, .A, .D, .Q(q)); \
  assign Q = RETN ? q : {WID{1'b1}};  /* retention reads poison */ \
  logic unused; \
  assign unused = ^EMA; \
endmodule

`EMU_RF_SP(rf_sp_64_128, 64, 128)
`EMU_RF_SP(rf_sp_64_46,  64, 46)
`EMU_RF_SP(rf_sp_64_44,  64, 44)
`EMU_RF_SP(rf_sp_32_128, 32, 128)
`EMU_RF_SP(rf_sp_32_45,  32, 48)
`EMU_RF_SP(rf_sp_16_128, 16, 128)
`EMU_RF_SP(rf_sp_16_46,  16, 48)
`EMU_RF_SP(rf_sp_64_53,  64, 56)
`EMU_RF_SP(rf_sp_64_137, 64, 140)
`EMU_RF_SP(sram_sp_128_137, 128, 137)
`EMU_RF_SP(sram_sp_128_53,  128, 53)
`EMU_RF_SP(sram_sp_256_137, 256, 137)
`EMU_RF_SP(sram_sp_256_53,  256, 53)
