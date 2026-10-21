///////////////////////////////////////////
// ft_fault_inject.sv
//
// Written: Siddharth Rau (sidrau2@illinois.edu)
//
// Purpose: Periodic runtime single-bit injection into execution-result channels.
//
// Usage:
// Instantiated on replica result channels in ft_alu, ft_mul, and ft_div, driven
// by the core's shared generator (ft_fault_gen).  fi_enable gates corruption;
// WIDTH selects the channel width and distinct PHASE values stagger events
// across replicas and channels.
//
// Functionality:
// On the cycle the shared counter reaches PHASE (once every 512 clocks), the
// shared LFSR selects a physical bit and XOR, stuck-at-zero, stuck-at-one, or
// no corruption. Out-of-range indices skip corruption. Reset suppresses
// injection; disabled channels pass data through unchanged.
///////////////////////////////////////////

module ft_fault_inject import cvw::*; #(
  parameter int WIDTH = 64,
  parameter logic [FI_COUNT_BITS-1:0] PHASE = '1
) (
  input  logic                     reset,
  input  logic [15:0]              lfsr,          // shared generator
  input  logic [FI_COUNT_BITS-1:0] count,
  input  logic [WIDTH-1:0]         data_i,
  input  logic                     fi_enable,
  output logic [WIDTH-1:0]         data_o
);
  logic [$clog2(WIDTH)-1:0] fi_bit;
  logic [1:0] fi_kind;
  logic inject_now;

  // One event every 512 clocks leaves time for a transient mismatch to retry
  // successfully.
  assign fi_bit = lfsr[$clog2(WIDTH)-1:0];
  // 00 XOR, 01 stuck-at-0, 10 stuck-at-1, 11 no corruption this event.
  assign fi_kind = lfsr[15:14];
  assign inject_now = fi_enable & ~reset & (count == PHASE);

  always_comb begin
    data_o = data_i;
    // Extended arithmetic/shift widths are not powers of two. Invalid LFSR
    // indices skip the event instead of aliasing a valid bit.
    if (inject_now && (int'(fi_bit) < WIDTH)) begin
      case (fi_kind)
        2'b00: data_o[fi_bit] = ~data_i[fi_bit];
        2'b01: data_o[fi_bit] = 1'b0;
        2'b10: data_o[fi_bit] = 1'b1;
        default: ;
      endcase
    end
  end
endmodule
