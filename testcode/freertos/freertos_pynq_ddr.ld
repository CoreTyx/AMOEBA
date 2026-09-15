/*
 * freertos_pynq_ddr.ld -- FreeRTOS on the PYNQ-Z2, against the DDR carve-out.
 *
 * The third of three layouts, and the differences between them are all forced
 * by where `tohost` has to sit:
 *
 *   freertos_wally.ld      simulation.  128 MB of testbench memory, so
 *                          tohost at RAM+8 MB is an ordinary address.
 *   freertos_pynq.ld       128 KiB of block RAM.  amoeba_mem_bram truncates
 *                          rather than faulting, so RAM+8 MB aliases onto the
 *                          reset vector -- tohost moves to the top page of
 *                          the array, RAM+128 KiB-4 KiB.
 *   this file              256 MiB of DDR.  RAM+8 MB is real memory again,
 *                          and the RTL goes back to the fixed address.
 *
 * TOHOST IS NOT A CHOICE HERE.  amoeba_pynq_top.sv derives the address the
 * bus monitor watches:
 *
 *     TOHOST_ADDR = MEM_BRAM ? (EXT_MEM_BASE + MEM_KB*1024 - 4096)
 *                            : 0x8080_0000
 *
 * so an AXI build watches 0x8080_0000 and this script must PROVIDE exactly
 * that.  If the two drift apart the run prints correct console output and
 * then hangs forever waiting for an exit nobody saw.  Amoeba.load() checks
 * the ELF's symbol against regs.tohost_addr() before starting the core, so
 * the mistake is caught at load time rather than as a timeout -- but only if
 * you keep all three in step.
 *
 * KEEP tohost 4 KiB-ALIGNED.  htif_writeback() in syscalls_amoeba.c evicts it
 * by conflict, and the sweep is written assuming set index 0, which every
 * 4 KiB-aligned address has for any way size up to 4 KiB.  0x8080_0000 is
 * 8 MiB-aligned, so this holds with room to spare.
 *
 * Layout:
 *
 *   0x8FFF_FFFF  +-- top of the 256 MiB carve-out
 *        ...     |   248 MiB, UNUSED BY THE PROGRAM and deliberately so:
 *                |   this is where a test that wants to exercise the high
 *   0x8080_1000  |   address bits of the AXI bridge puts its working set.
 *                |   See MEMTEST_BASE in tc_mem_stress.c -- confined to the
 *                |   8 MiB below, address bits 23 and up never change and a
 *                +-- bridge that drops one would go unnoticed.
 *   0x8080_0000  tohost / fromhost      (fixed by the RTL; HTIF only)
 *   0x807F_F000  guard page
 *   0x807F_F000  IRQ stack top, growing down
 *                main stack top = IRQ top - 4096 (crt0 does the subtraction)
 *      ...       slack, then the FreeRTOS heap inside .bss
 *   0x8000_0000  .text
 *
 * The 8 MiB region below tohost is the whole budget for code, data, heap and
 * stacks, because .bss growing past 0x8080_0000 would land on the HTIF page.
 * LENGTH below makes that a link-time error rather than a silent collision,
 * so raising configTOTAL_HEAP_SIZE too far fails loudly.
 */

OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  /* Deliberately NOT the full 256 MiB: this region ends where tohost begins,
   * so overflowing it is a linker error instead of a corrupted exit word. */
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 8M
}

/* Top page of RAM is left unmapped by the stack as a guard between it and the
 * HTIF page directly above. */
__freertos_irq_stack_top = ORIGIN(RAM) + LENGTH(RAM) - 0x1000;

PROVIDE(tohost   = 0x80800000);
PROVIDE(fromhost = 0x80800008);

SECTIONS
{
  . = 0x80000000;

  .text :
  {
    *(.text.init)
    *(.text)
    *(.text.*)
    . = ALIGN(8);
  } > RAM

  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
    . = ALIGN(8);
  } > RAM

  .data :
  {
    __global_pointer$ = . + 0x800;
    *(.sdata)
    *(.sdata.*)
    *(.data)
    *(.data.*)
    . = ALIGN(8);
  } > RAM

  .tdata :
  {
    _tdata_begin = .;
    *(.tdata)
    *(.tdata.*)
    _tdata_end = .;
    . = ALIGN(8);
  } > RAM

  .tbss :
  {
    *(.tbss)
    *(.tbss.*)
    _tbss_end = .;
    . = ALIGN(8);
  } > RAM

  .bss :
  {
    _bss_start = .;
    *(.sbss)
    *(.sbss.*)
    *(.bss)
    *(.bss.*)
    . = ALIGN(8);
    _bss_end = .;
  } > RAM

  _end = .;
}
