///////////////////////////////////////////
// tcf_dft_lock.c
//
// TC_DFT_LOCK - the memory-mapped register that disables the DFT pins.
//
// NAMED tcf_, NOT tc_, AND THAT PREFIX IS LOAD-BEARING.  The register lives in
// hdl/forte_uncore.sv, so it exists only in the ASIC hierarchy; on the legacy
// DUT this address falls inside the CLINT's region and clint_apb answers 0 for
// it, so the test fails there for a reason that has nothing to do with the DUT.
// Both sim/Makefile and .github/workflows/ci.yml therefore treat tcf_* as
// forte-only: the default ISA matrix skips them and the DUT=forte job runs them.
// A hardcoded filename exclusion was the first attempt and is the wrong shape --
// it rots the moment a second forte-only test is added, which is the same way
// lint/Makefile ended up globbing hdl/amoeba_*.sv after the rename.
//
// This tapeout has no efuses, so there is nothing one-time-programmable to blow
// after test.  hdl/forte_dft_lock.sv is the substitute: a register that resets
// to 1 (DFT permitted) and that boot software clears once it no longer needs
// scan.  forte_chip qualifies BOTH test_mode and scan_en with it.
//
// Checked here through real loads and stores rather than by forcing the flop,
// because the thing most likely to be wrong is not the flop -- it is the path
// to it.  The register sits in a hole in the CLINT's region, carved out in
// forte_uncore so that neither pkg/config.vh nor any CVW file had to change, so
// this test covers the PMA permitting the address, adrdecs selecting the CLINT
// region, forte_uncore taking that one address away from clint_apb, the APB
// bridge routing it, and the register itself.  Getting any of those wrong shows
// up here as a read of the wrong value or a bus fault.
//
// THE STICKY CHECK IS THE IMPORTANT ONE.  Clearing has to be one-way until
// reset: a register software could set back to 1 would turn every
// code-execution bug into a scan unlock, which is the whole thing the lock is
// supposed to prevent.
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"
#include <stdint.h>

// CLINT_BASE + 0xF000.  See DFTLOCK_OFF in hdl/forte_uncore.sv.  Above
// everything clint_apb implements (msip +0x0000, mtimecmp +0x4000,
// mtime +0xBFF8), and inside a region the PMA already permits.
#define DFT_LOCK_ADDR   0x0200F000UL
#define DFT_LOCK        (*(volatile uint64_t *)DFT_LOCK_ADDR)

static void tc_dft_lock(void) {
    test_begin("TC_DFT_LOCK");

    // Resets to 1, so the part is testable from power-up and before any
    // software runs.  A part that came up locked could not be tested at all.
    check("reads 1 out of reset (DFT permitted)", DFT_LOCK & 1ULL, 1ULL);

    // Writing 1 while unlocked is a no-op, not a toggle.
    DFT_LOCK = 1ULL;
    check("write 1 while unlocked leaves it unlocked", DFT_LOCK & 1ULL, 1ULL);

    // The clear.  Everything after this point runs on a locked part.
    DFT_LOCK = 0ULL;
    check("write 0 locks DFT", DFT_LOCK & 1ULL, 0ULL);

    // Sticky: no software path back to a scannable part.
    DFT_LOCK = 1ULL;
    check("write 1 after lock stays locked (sticky)", DFT_LOCK & 1ULL, 0ULL);

    DFT_LOCK = ~0ULL;
    check("write all-ones stays locked", DFT_LOCK & 1ULL, 0ULL);

    // A second clear is harmless -- boot software should not have to know
    // whether something already locked it.
    DFT_LOCK = 0ULL;
    check("redundant write 0 stays locked", DFT_LOCK & 1ULL, 0ULL);

    // The part has to keep working with DFT locked: this is the state it spends
    // its whole functional life in, so a few more bus accesses afterwards are
    // worth making.  The UART traffic from check() above is already doing this.
    check("bus still live after locking", DFT_LOCK & ~1ULL, 0ULL);
}

int main(void) {
    tc_dft_lock();
    print_summary();
    test_finish();
}
