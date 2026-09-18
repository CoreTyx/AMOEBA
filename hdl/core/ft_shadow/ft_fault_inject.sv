// Test-only result-path fault injector for a shadow-FU replica.
// FAULT_INJECT is an elaboration-time switch: normal builds reduce this block
// to a wire, while the standalone FT testbench enables the configurable fault.
module ft_fault_inject #(
  parameter int WIDTH = 64,
  parameter bit FAULT_INJECT = 1'b0
) (
  input  logic [WIDTH-1:0] data_i,
  input  logic             fi_enable,
  // 00: XOR selected bit, 01: force it low, 10: force it high.  11 is reserved.
  input  logic [1:0]       fi_kind,
  input  logic [$clog2(WIDTH)-1:0] fi_bit,
  output logic [WIDTH-1:0] data_o
);

  generate
    if (!FAULT_INJECT) begin : g_disabled
      // Keep production logic and timing identical to the uninjected wrapper.
      assign data_o = data_i;
    end else begin : g_enabled
      int unsigned bit_index;

      always_comb begin
        data_o = data_i;
        // Widen before the range check; WIDTH need not be a power of two.
        bit_index = fi_bit;
        if (fi_enable && (bit_index < WIDTH)) begin
          case (fi_kind)
            2'b00: data_o[bit_index] = ~data_i[bit_index];
            2'b01: data_o[bit_index] = 1'b0;
            2'b10: data_o[bit_index] = 1'b1;
            default: ; // Reserved encoding deliberately injects no fault.
          endcase
        end
      end
    end
  endgenerate
endmodule
