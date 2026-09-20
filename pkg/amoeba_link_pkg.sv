///////////////////////////////////////////////////////////////////////////////
// amoeba_link_pkg.sv
//
// The off-chip link, in one place.  The ASIC-side bridge (hdl/amoeba_link_master),
// the testbench slave model (hvl/common/amoeba_link_model) and the FPGA slave
// all elaborate against these, so a protocol change is one edit.
//
// The link is a 16-bit bidirectional bus that carries only addresses and
// data.  Transaction type is on dedicated pins, held for the whole
// transaction, so nothing on the bus is decoded by either side:
//
//   req=1, cycle 0   io = HADDR[31:16]   bits 30:29 carry HSIZE[1:0] (always
//   req=1, cycle 1   io = HADDR[15:0]    zero in every configured region)
//   otherwise        io = data word      64-bit beat as 4 words, LSW first
//   wr, burst        held from req until the last word
//   ready            "may start": the ASIC issues req only after sampling
//                    ready=1, and the FPGA then accepts the whole transaction
//   rvalid           read data word on io this cycle; gaps allowed
//   dir              1 = ASIC drives io, 0 = ASIC has released it; the single
//                    source of truth for bus ownership.  TA idle cycles are
//                    guaranteed by the ASIC on every change.
//
// See docs/top_level_plan.md s4.
///////////////////////////////////////////////////////////////////////////////
package amoeba_link_pkg;

  localparam int LINK_W          = 16;      // io[LINK_W-1:0]
  localparam int ADDR_WORDS      = 2;       // 32-bit address on a 16-bit bus
  localparam int WORDS_PER_BEAT  = 64 / LINK_W;              // 4
  localparam int BEATS_PER_LINE  = 8;                        // INCR8, AHBW=64
  localparam int WORDS_PER_LINE  = WORDS_PER_BEAT * BEATS_PER_LINE;  // 32
  localparam int TA              = 2;       // turnaround idle cycles per dir change

  // Training: after reset the ASIC drives TRAIN_LEN LFSR words with dir=1,
  // then releases the bus and expects the same TRAIN_LEN words echoed back.
  // The FPGA centres its input delay on the outbound phase and its output
  // phase on the echo.  Overridable per instance so simulation stays short.
  localparam int          TRAIN_LEN_DEFAULT = 4096;
  localparam int          TRAIN_RETRIES     = 8;
  localparam logic [15:0] TRAIN_SEED        = 16'hACE1;

  // AHB HBURST encodings the bridge cares about.
  localparam logic [2:0] HBURST_SINGLE = 3'b000;
  localparam logic [2:0] HBURST_INCR8  = 3'b101;

  // 16-bit Fibonacci LFSR, taps 16,14,13,11 (x^16 + x^14 + x^13 + x^11 + 1).
  function automatic logic [15:0] lfsr_next(input logic [15:0] s);
    logic fb;
    fb = s[15] ^ s[13] ^ s[12] ^ s[10];
    return {s[14:0], fb};
  endfunction

  // Address as it goes on the bus: the physical address with HSIZE[1:0]
  // riding in bits 30:29.  Every configured region (0x0200_0000 CLINT,
  // 0x0C00_0000 PLIC, 0x1000_0000 UART, 0x8000_0000 EXT_MEM) has those bits
  // zero; the bridge asserts it in simulation.
  function automatic logic [31:0] addr_pack(input logic [31:0] haddr, input logic [1:0] hsize);
    return {haddr[31], hsize, haddr[28:0]};
  endfunction

  function automatic logic [31:0] addr_unpack(input logic [31:0] w);
    return {w[31], 2'b00, w[28:0]};
  endfunction

  function automatic logic [1:0] size_unpack(input logic [31:0] w);
    return w[30:29];
  endfunction

  // Byte strobes for a single beat from size + offset, as ahb_to_memitf does.
  function automatic logic [7:0] size_to_mask(input logic [1:0] hsize, input logic [2:0] offset);
    case (hsize)
      2'b00:   return 8'h01 << offset;
      2'b01:   return 8'h03 << {offset[2:1], 1'b0};
      2'b10:   return 8'h0F << {offset[2], 2'b0};
      default: return 8'hFF;
    endcase
  endfunction

endpackage
