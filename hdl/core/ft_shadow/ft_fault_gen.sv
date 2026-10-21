///////////////////////////////////////////
// ft_fault_gen.sv
//
// Purpose: The one random source for every runtime fault-injection site in the core.
//
// Usage:
// Instantiated once in wallypipelinedcore.  Its LFSR and counter are broadcast to
// the injection sites (ft_fault_inject, ecc_bit_flip, ecc_flip_mask), each of
// which fires when the counter equals its own phase, takes its bit (and kind)
// from the LFSR at that moment, and corrupts only while its own unit is enabled.
//
// Functionality:
// Free-running from reset; enables only gate corruption at the sites.  Sites
// with different phases never fire in the same cycle, which keeps a replica
// and its shadow from ever taking the same fault.
///////////////////////////////////////////

module ft_fault_gen import cvw::*; (
  input  logic                     clk, reset,
  output logic [15:0]              lfsr,
  output logic [FI_COUNT_BITS-1:0] count
);
  always_ff @(posedge clk)
    if (reset) begin
      lfsr  <= FI_LFSR_SEED;
      count <= '0;
    end else begin
      lfsr  <= fi_lfsr_next(lfsr);
      count <= count + 1'b1;
    end
endmodule
