OUTPUT_ARCH( "riscv" )
ENTRY( _start )

MEMORY
{
  RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 128M
}

__freertos_irq_stack_top = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  . = 0x80000000;

  .text :
  {
    *(.text.init)
    *(.text)
    *(.text.*)
  } > RAM

  .rodata :
  {
    *(.rodata)
    *(.rodata.*)
  } > RAM

  .data :
  {
    __global_pointer$ = . + 0x800;
    *(.sdata)
    *(.sdata.*)
    *(.data)
    *(.data.*)
  } > RAM

  .tdata :
  {
    _tdata_begin = .;
    *(.tdata)
    *(.tdata.*)
    _tdata_end = .;
  } > RAM

  .tbss :
  {
    *(.tbss)
    *(.tbss.*)
    _tbss_end = .;
  } > RAM

  .bss :
  {
    _bss_start = .;
    *(.sbss)
    *(.sbss.*)
    *(.bss)
    *(.bss.*)
    _bss_end = .;
  } > RAM

  _end = .;

  /* tohost/fromhost: required by syscalls.c for exit() and printf()
     Place in RAM at a fixed address the testbench monitors */
  .tohost :
  {
    PROVIDE( tohost = . );
    . += 8;
    PROVIDE( fromhost = . );
    . += 8;
  } > RAM
}
