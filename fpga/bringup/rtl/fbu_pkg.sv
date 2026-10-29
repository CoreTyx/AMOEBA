///////////////////////////////////////////////////////////////////////////////
// fbu_pkg.sv -- shared definitions of the bring-up FPGA gateware (fpga/bringup).
//
// Board-agnostic: no Xilinx primitives, no PS assumptions.  The gateware is the
// synthesizable twin of the pin bench (hvl/pin), and the bench is its spec:
// every random choice and every check here reproduces pin_link_agent.sv, so a
// gateware run and a bench run with the same image and knobs write the same
// pin trace, cycle for cycle (docs/impl_plan_fpga_rtl_freeze.md s8.1).
///////////////////////////////////////////////////////////////////////////////
package fbu_pkg;

  // ---- link checker error codes ---------------------------------------------
  // One bit each in the sticky LINK_ERR register.  1..20 are pin_link_agent's
  // checks, in its order; 21.. are the gateware's own.  The bench's X/Z checks
  // have no code: hardware is 2-state.
  typedef enum logic [4:0] {
    LE_NONE          = 5'd0,
    LE_REQ_DIR0      = 5'd1,   // req while dir=0
    LE_CONTENTION    = 5'd2,   // slave driving io while dir=1
    LE_IO_MISMATCH   = 5'd3,   // io resolves to something other than what the slave drives
    LE_WATCHDOG      = 5'd4,   // transaction not finished in WDOG cycles
    LE_GUARD         = 5'd5,   // req more than GUARD cycles after ready fell
    LE_HDR_REQ_DROP  = 5'd6,   // req dropped after one header word
    LE_HDR_WR_CHG    = 5'd7,   // wr changed inside the header
    LE_ADDR_RANGE    = 5'd8,   // address outside EXT_MEM
    LE_ADDR_ALIGN    = 5'd9,   // address not line-aligned
    LE_FIRST_XACT    = 5'd10,  // first transaction after reset is not a read of RESET_VEC
    LE_WD_REQ        = 5'd11,  // req during write data
    LE_WD_DIR        = 5'd12,  // dir fell during write data
    LE_WD_WR         = 5'd13,  // wr dropped during write data
    LE_RTA_REQ       = 5'd14,  // req during read turnaround
    LE_RLAT_DIR      = 5'd15,  // dir rose during read latency
    LE_RD_DIR        = 5'd16,  // dir rose during read data
    LE_RD_REQ        = 5'd17,  // req during read data
    LE_REL_DIR       = 5'd18,  // dir rose within TA cycles of the last rvalid
    LE_LAT_OVERRUN   = 5'd21,  // DET: line not back from the backend when its first word was due
    LE_REQ_OVERFLOW  = 5'd22,  // backend request queue full on a push
    LE_MEM_ERR       = 5'd23   // backend reported an error (sticky RESP, out-of-window)
  } link_err_t;

  // ---- the bench's random generator, in hardware -----------------------------
  // pin_link_agent: xorshift64, seeded 0x9E3779B97F4A7C15 ^ seed*0x2545F4914F6CDD1D
  // (0 -> 1), one rand64() per link cycle while rst_n=1 and gap_pct>0, and
  // gap = rand64() % 100 < gap_pct.  The seed arithmetic is done once by
  // whoever loads PRNG_INIT (the PS, or a testbench) -- see prng_seed_state().
  function automatic logic [63:0] xorshift64(input logic [63:0] x);
    logic [63:0] a, b;
    a = x ^ (x << 13);
    b = a ^ (a >> 7);
    return b ^ (b << 17);
  endfunction

  function automatic logic [63:0] prng_seed_state(input logic [31:0] seed);
    logic [63:0] p;
    p = 64'h9E37_79B9_7F4A_7C15 ^ (64'(seed) * 64'h2545_F491_4F6C_DD1D);
    return (p == '0) ? 64'h1 : p;
  endfunction

  // x % 100 for a 64-bit x, exactly, without a divider.  2^16, 2^32 and 2^48
  // are 36, 96 and 56 mod 100, so x == c0 + 36 c1 + 96 c2 + 56 c3 (mod 100) for
  // its 16-bit chunks c0..c3: a sum below 2^24.  Folding the same way once more
  // leaves t < 2^17, and t % 100 is t - 100*floor(t*41943 / 2^22) with one
  // correction: 41943/2^22 is below 1/100 by under 1e-8, so for t < 2^17 the
  // quotient is exact or one short and the remainder lies in [0, 200).
  function automatic logic [6:0] mod100(input logic [63:0] x);
    logic [24:0] s;
    logic [17:0] t;
    logic [35:0] p;
    logic [17:0] q, r;
    s = 25'(x[15:0]) + 25'(x[31:16]) * 25'd36 + 25'(x[47:32]) * 25'd96 + 25'(x[63:48]) * 25'd56;
    t = 18'(s[15:0]) + 18'(s[24:16]) * 18'd36;
    p = 36'(t) * 36'd41943;
    q = 18'(p >> 22);
    r = t - q * 18'd100;
    if (r >= 18'd100) r = r - 18'd100;
    return 7'(r);
  endfunction

endpackage
