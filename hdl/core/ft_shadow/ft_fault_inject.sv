// Runtime-controlled result-path injector. The driver determines duration;
// disabling injection passes data through without resetting recovery state.
module ft_fault_inject #(parameter int WIDTH = 64) (
  input  logic [WIDTH-1:0] data_i,
  input  logic fi_enable,
  // 00: XOR selected bit, 01: force low, 10: force high, 11: no-op.
  input  logic [1:0] fi_kind,
  input  logic [((WIDTH <= 1) ? 1 : $clog2(WIDTH))-1:0] fi_bit,
  output logic [WIDTH-1:0] data_o
);
  int unsigned bit_index;
  always_comb begin
    data_o = data_i;
    bit_index = int'(fi_bit);
    if (fi_enable && (bit_index < WIDTH)) begin
      case (fi_kind)
        2'b00: data_o[bit_index] = ~data_i[bit_index];
        2'b01: data_o[bit_index] = 1'b0;
        2'b10: data_o[bit_index] = 1'b1;
        default: ;
      endcase
    end
  end
endmodule
