/*
 * Process entry for the freestanding boot-test userland:
 * _start -> main(argc, argv, envp) -> exit_group(main's return value).
 *
 * The kernel enters with sp pointing at argc, followed by argv[0..argc-1],
 * NULL, envp[...], NULL.  sp is already 16-byte aligned as the psABI needs.
 */

.equ __NR_exit_group, 94

.section .text._start, "ax"
.globl _start
_start:
    /* gp must be loaded without relaxation, or the linker would rewrite this
     * very sequence as gp-relative. */
    .option push
    .option norelax
    la      gp, __global_pointer$
    .option pop

    ld      a0, 0(sp)              /* argc */
    addi    a1, sp, 8              /* argv */
    slli    a2, a0, 3
    add     a2, a2, a1
    addi    a2, a2, 8              /* envp = &argv[argc + 1] */
    call    main

    li      a7, __NR_exit_group    /* a0 already holds main's return value */
    ecall
1:  j       1b
