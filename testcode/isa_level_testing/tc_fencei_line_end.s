# tc_fencei_line_end.s
#
# fence.i followed by an instruction that starts in the last two bytes of a
# 16-byte I-cache line.  Found by bin/fuzz.py (seeds 348, 2785, 4811).
#
#   offset 0x0  nop
#   offset 0x4  nop
#   offset 0x8  c.nop
#   offset 0xa  fence.i
#   offset 0xe  c.li t0, 1        <- last two bytes of the line
#   next line   addi t1, t0, 5
#
# Expected: t1 = 6 and tohost exit(0).
# Observed (Verilator, no-Spike build): the core retires the c.li at 0x8000001e
# and never retires anything again; the testbench times out.  In the fuzz
# programs the same layout instead retired an instruction whose low half came
# from offset 0xe of the following line.
# Controls that pass: fence.i replaced by nop; one extra c.nop so the c.li no
# longer ends the line.
#
#   make -C sim run_verilator_top_tb_no_spike TIMEOUT=20000 \
#       PROG=../testcode/isa_level_testing/tc_fencei_line_end.s
#
# Not auto-discovered by ISA_LEVEL_TESTS / CI (they only glob *.c).

    .option norvc
    .section .init, "ax"
    .globl _start
_start:
    li   t0, 0
    li   t1, 0
    .option rvc
    .balign 16
    .option norvc
    nop
    nop
    .option rvc
    c.nop
    .option norvc
    fence.i
    .option rvc
    c.li t0, 1
    .option norvc
    addi t1, t0, 5
    li   t2, 6
    li   a0, 1
    bne  t1, t2, fail
    li   a0, 0
fail:
    slli a0, a0, 1
    ori  a0, a0, 1
    la   t0, tohost
    sd   a0, 0(t0)
    slti x0, x0, -256
1:  j    1b
