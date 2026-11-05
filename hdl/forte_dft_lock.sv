///////////////////////////////////////////////////////////////////////////////
// forte_dft_lock.sv
//
// One memory-mapped register that disables the DFT pins.  APB slave.
//
// WHY IT EXISTS.  This tapeout has no efuses, so there is nothing
// one-time-programmable to blow after test.  Scan gives full read/write access
// to every flop on the die, including the register file and the CSRs, so a part
// that leaves the tester with scan still reachable has no protected state at
// all.  The substitute is a register that boot software clears once it no longer
// needs DFT.
//
//   reset       unlocked = 1   DFT permitted, so the part is testable from the
//                              instant it powers up and before any software runs
//   write 0     unlocked = 0   DFT refused
//   write 1     no effect      see STICKY below
//
// forte_chip qualifies BOTH test_mode and scan_en with this bit, so when it is
// clear the pads stay functional and the chains cannot be shifted.  The pin and
// the register are an AND: DFT needs unlocked=1 AND the pin asserted.
//
// STICKY.  Clearing is one-way until reset.  A register that software could set
// back to 1 would make every code-execution bug a scan-unlock, which defeats
// the point -- the attacker's job would be to write one word rather than to get
// physical access.  Re-enabling DFT in the lab therefore means resetting the
// part, which is the intended cost.
//
// WHAT THIS DOES NOT DEFEND AGAINST, and it matters:
//   - RESET RE-ENABLES DFT.  There is no non-volatile state, so the lock cannot
//     survive a power cycle by construction.  Anyone who can drive rst_n can
//     unlock, and on this board rst_n is an FPGA OUTPUT.  This protects against
//     a runtime software compromise, not against physical access.
//   - IT IS ONLY AS GOOD AS THE BOOT FLOW.  Nothing clears it automatically.
//     If boot software never writes 0, DFT stays open for the life of the power
//     cycle.  Clearing it belongs at the end of early init, after whatever last
//     needs scan and before any untrusted code runs.
//   - THE `unlocked` FLOP MUST BE EXCLUDED FROM THE SCAN CHAINS, and from any
//     test-mode reset bypass DFT insertion adds.  On the chain it is observable
//     and, worse, settable.  The gating in forte_chip means a locked part
//     cannot shift at all, so this is belt-and-braces rather than the only
//     barrier -- but it is the kind of belt that is cheap now and impossible
//     later.  It needs a set_scan_element false (or the flow's equivalent) in
//     the insertion script, which does not exist yet.
//
// Address: see DFTLOCK_ADDR in hdl/forte_uncore.sv.  It sits in a hole in the
// CLINT's region rather than in a region of its own, because every region the
// PMA permits has to come from pkg/config.vh, and enabling a spare one there
// would also instantiate a CVW peripheral in the legacy DUT.
///////////////////////////////////////////////////////////////////////////////

module forte_dft_lock import cvw::*; #(
  parameter cvw_t P
)(
  input  logic                PCLK, PRESETn,
  input  logic                PSEL, PENABLE, PWRITE,
  input  logic [P.XLEN-1:0]   PWDATA,
  input  logic [P.XLEN/8-1:0] PSTRB,
  output logic [P.XLEN-1:0]   PRDATA,
  output logic                PREADY,

  // 1 = DFT permitted.  Consumed in forte_chip, where the pads are.
  output logic                unlocked
);

  // Reset value is 1: a part that came up locked could not be tested at all.
  // Cleared by any write whose low lane is enabled and whose low data is 0; a
  // write of 1 is silently ignored, which is what makes it sticky.
  always_ff @(posedge PCLK) begin
    if (!PRESETn)                                              unlocked <= 1'b1;
    else if (PSEL & PENABLE & PWRITE & PSTRB[0] & ~PWDATA[0])  unlocked <= 1'b0;
  end

  // Readable so software can confirm the clear took, and so a bring-up script
  // can tell a locked part from a dead bus.
  assign PRDATA = {{(P.XLEN-1){1'b0}}, unlocked};
  assign PREADY = 1'b1;          // single-cycle; nothing here can stall

  // PWDATA above the low lane and the rest of PSTRB are deliberately unread --
  // one register, one meaningful lane.  Sunk so synthesis does not warn.
  logic unused;
  assign unused = ^{PWDATA[P.XLEN-1:1], PSTRB[P.XLEN/8-1:1]};

endmodule
