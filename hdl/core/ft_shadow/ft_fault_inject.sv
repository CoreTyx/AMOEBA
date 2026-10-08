// Periodic runtime fault injection. Each instance chooses its own result bit
// and fault kind with a 16-bit Galois LFSR (x^16+x^14+x^13+x^11+1).
// Distinct seeds also stagger the one-cycle events across replicas/channels.
module ft_fault_inject #(
  parameter int WIDTH = 64,
  parameter logic [15:0] SEED = 16'hA001
) (
  input  logic clk, reset,
  input  logic [WIDTH-1:0] data_i,
  input  logic             fi_enable,
  output logic [WIDTH-1:0] data_o
);
  logic [15:0] lfsr;
  logic [8:0] count;
  logic [$clog2(WIDTH)-1:0] fi_bit;
  logic [1:0] fi_kind;
  logic inject_now;

  // Free-running sequences; enable only gates corruption. One event every
  // 512 clocks leaves time for a transient mismatch to retry successfully.
  always_ff @(posedge clk) begin
    if (reset) begin
      lfsr <= SEED;
      count <= SEED[8:0];
    end else begin
      lfsr <= {1'b0, lfsr[15:1]} ^ (lfsr[0] ? 16'hB400 : 16'h0000);
      count <= count + 9'd1;
    end
  end
  assign fi_bit = lfsr[$clog2(WIDTH)-1:0];
  // 00 XOR, 01 stuck-at-0, 10 stuck-at-1, 11 no corruption this event.
  assign fi_kind = lfsr[15:14];
  assign inject_now = fi_enable & ~reset & (&count);

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
