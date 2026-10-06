// Runtime-controlled result-path injector. The driver determines duration;
// disabling injection passes data through without resetting recovery state.
module ft_fault_inject #(parameter int WIDTH = 64) (
  input  logic [WIDTH-1:0] data_i, // raw result from one execution-unit replica
  input  logic fi_enable,         // wrapper has decoded bundle enable, target, and channel
  // 00: XOR selected bit, 01: force low, 10: force high, 11: no-op.
  input  logic [1:0] fi_kind,
  input  logic [$clog2(WIDTH)-1:0] fi_bit, // physical bit index; invalid is a no-op
  output logic [WIDTH-1:0] data_o  // post-injection result supplied to checking/recovery logic
);
  always_comb begin
    data_o = data_i;
    if (fi_enable && (int'(fi_bit) < WIDTH)) begin
      case (fi_kind)
        2'b00: data_o[fi_bit] = ~data_i[fi_bit];
        2'b01: data_o[fi_bit] = 1'b0;
        2'b10: data_o[fi_bit] = 1'b1;
        default: ;
      endcase
    end
  end
endmodule
