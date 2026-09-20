// amoeba_rst_sync.sv -- asynchronous assert, synchronous (2-flop) release.
module amoeba_rst_sync (
  input  logic clk,
  input  logic rst_n_in,
  output logic rst_n_out
);
  logic [1:0] q;
  always_ff @(posedge clk or negedge rst_n_in)
    if (!rst_n_in) q <= 2'b00;
    else           q <= {q[0], 1'b1};
  assign rst_n_out = q[1];
endmodule
