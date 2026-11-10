///////////////////////////////////////////////////////////////////////////////
// forte_top.sv
//
// The ASIC: forte_chip plus the pad ring.  DESIGN_TOP for synthesis and lint.
//
// Pad list (docs/top_level_plan.md s3): core_clk, rst_n, io_in[7:0],
// io_out[7:0], req, wr, clk_out, ready, rvalid, irq[1:0], uart_tx, uart_rx,
// test_mode, scan_en, fault_inject, status -- 31 signal pads.  Power and ground are the
// pad library's business and are NOT instantiated here; see "what this ring
// does not do" below.
//
// THE PAD RING IS THE ONLY THING `SYNTHESIS CHANGES HERE.  With it defined the
// PDK wrappers are instantiated; without it the pads are behavioural, which is
// what simulation and the FPGA rehearsal use.  Everything else -- the core-side
// nets, the forte_chip instance -- is identical either way, so the two
// configurations cannot drift apart in anything but the cells themselves.
//
// The PDK wrappers, and the one convention that matters: `chipout` is
// always the signal at the CHIP BOUNDARY (the pin) and `chipin` is always the
// signal inside the die.  So for an input pad chipout is the cell's input and
// chipin its output, and for an output pad it is the other way round.  The
// module's own ports therefore carry the pad names and connect to chipout;
// forte_chip connects to the internal nets, suffixed _i for what the die
// receives and _o for what it drives.
//
//   io_in  (input  wire  chipout, output wire  chipin)
//   io_out (output wire  chipout, input  wire  chipin)
//
// THE LINK IS TWO ONE-WAY BUSES, io_in[7:0] and io_out[7:0], on plain io_in and
// io_out cells.  It used to be sixteen io_tri pads with a tristate enable each
// and a dir pin; nothing on the link changes direction any more, so none of
// that exists (hdl/forte_link_pkg.sv).  The PORTS io_in / io_out share their
// names with the CELLS io_in / io_out.  That is legal -- modules and ports live
// in different namespaces -- and it reads naturally enough below, where every
// io_in port bit goes through an io_in cell.
//
// WHAT THIS RING DOES NOT DO, because the wrappers above cannot express
// it -- each is a question for whoever owns the pad library, not something to
// be guessed at here:
//   - No power or ground pads.  Count, placement and the IR-drop budget are a
//     floorplan decision.
//   - No pull-ups or pull-downs.  io_in has no pull terminal, so the
//     pull-down on test_mode/scan_en and pull-up on uart_rx that this file
//     used to carry as a TODO cannot be asked for through it; they need either
//     a pulled variant of the cell or an explicit on-die resistor.
//   - No dedicated clock pad for core_clk.  It goes through the same io_in as
//     every other input; if the library has a clock-input cell with better
//     jitter or duty-cycle behaviour, core_clk wants it.
//   - No ESD or antenna cells beyond whatever io_* already contain.
///////////////////////////////////////////////////////////////////////////////

module forte_top import forte_link_pkg::*; #(
  parameter logic PERIPH_ONCHIP = 1'b1
)(
  input  wire              core_clk,
  input  wire              rst_n,
  input  wire [LINK_W-1:0] io_in,        // link, FPGA -> ASIC
  output wire [LINK_W-1:0] io_out,       // link, ASIC -> FPGA
  output wire              req,
  // Forwarded link clock; see forte_chip.  Replaces the `burst` pin, which was
  // always 1 -- every transfer is a full line and the single path does not
  // exist -- so it carried no information at the cost of a pad.  If the library
  // has a dedicated clock-OUTPUT cell, this pin wants it rather than io_out.
  output wire              clk_out,
  output wire              wr,
  input  wire              ready,
  input  wire              rvalid,
  input  wire [1:0]        irq,
  output wire              uart_tx,
  input  wire              uart_rx,
  input  wire              test_mode,
  input  wire              scan_en,
  // Fault-injection master enable. The core ANDs this pin with the six unit
  // enables at MMIO 0x1007_000b; ECC and FT checking remain active when low.
  input  wire              fault_inject,
  output wire              status
);

  // ---- core-side nets, one per pad -----------------------------------------
  // _i is what the die receives, _o is what the die drives.  forte_chip talks
  // only to these, never to the ports, so the pad ring is the only difference
  // between the synthesis and simulation configurations.
  logic              core_clk_i, rst_n_i;
  logic [LINK_W-1:0] io_in_i, io_out_o;
  logic              req_o, wr_o, clk_out_o;
  logic              ready_i, rvalid_i;
  logic [1:0]        irq_i;
  logic              uart_tx_o, uart_rx_i;
  logic              test_mode_i, scan_en_i, fault_inject_i;
  logic              status_o;

  // link_clk is tied to the core_clk pad: one clock off the board, two clock
  // trees on the die (docs/impl_plan_link_clocking.md s4).  The separate port on
  // forte_chip is what lets a testbench drive the two domains independently and
  // actually exercise the FIFOs' pointer crossings; a single port would give
  // simulation zero skew and no coverage.  Splitting the frequencies later is a
  // one-line change here plus a pad.
  forte_chip #(.PERIPH_ONCHIP(PERIPH_ONCHIP)) chip(
    .core_clk      (core_clk_i),
    .link_clk      (core_clk_i),
    .rst_n         (rst_n_i),
    .io_o          (io_out_o),
    .io_i          (io_in_i),
    .req           (req_o),
    .wr            (wr_o),
    .clk_out       (clk_out_o),
    .ready         (ready_i),
    .rvalid        (rvalid_i),
    .irq           (irq_i),
    .uart_tx       (uart_tx_o),
    .uart_rx       (uart_rx_i),
    .test_mode     (test_mode_i),
    .scan_en       (scan_en_i),
    .fault_inject  (fault_inject_i),
    .status        (status_o));

`ifdef SYNTHESIS
  // ---- PDK pad cells --------------------------------------------------------
  io_in  io_core_clk     (.chipout (core_clk),     .chipin (core_clk_i));
  io_in  io_rst_n        (.chipout (rst_n),        .chipin (rst_n_i));
  io_in  io_ready        (.chipout (ready),        .chipin (ready_i));
  io_in  io_rvalid       (.chipout (rvalid),       .chipin (rvalid_i));
  io_in  io_irq0         (.chipout (irq[0]),       .chipin (irq_i[0]));
  io_in  io_irq1         (.chipout (irq[1]),       .chipin (irq_i[1]));
  io_in  io_uart_rx      (.chipout (uart_rx),      .chipin (uart_rx_i));
  io_in  io_test_mode    (.chipout (test_mode),    .chipin (test_mode_i));
  io_in  io_scan_en      (.chipout (scan_en),      .chipin (scan_en_i));
  io_in  io_fault_inject (.chipout (fault_inject), .chipin (fault_inject_i));

  io_out io_req          (.chipout (req),          .chipin (req_o));
  io_out io_wr           (.chipout (wr),           .chipin (wr_o));
  io_out io_clk_out      (.chipout (clk_out),      .chipin (clk_out_o));
  io_out io_uart_tx      (.chipout (uart_tx),      .chipin (uart_tx_o));
  io_out io_status       (.chipout (status),       .chipin (status_o));

  for (genvar i = 0; i < LINK_W; i++) begin : g_link
    io_in  io_link_in  (.chipout (io_in[i]),  .chipin (io_in_i[i]));
    io_out io_link_out (.chipout (io_out[i]), .chipin (io_out_o[i]));
  end

`else
  // ---- behavioural pads -----------------------------------------------------
  // Every pad is one-way, so every pad is a straight-through assign.
  assign core_clk_i     = core_clk;
  assign rst_n_i        = rst_n;
  assign ready_i        = ready;
  assign rvalid_i       = rvalid;
  assign irq_i          = irq;
  assign uart_rx_i      = uart_rx;
  assign test_mode_i    = test_mode;
  assign scan_en_i      = scan_en;
  assign fault_inject_i = fault_inject;
  assign io_in_i        = io_in;

  assign io_out         = io_out_o;
  assign req            = req_o;
  assign wr             = wr_o;
  assign clk_out        = clk_out_o;
  assign uart_tx        = uart_tx_o;
  assign status         = status_o;
`endif

endmodule
