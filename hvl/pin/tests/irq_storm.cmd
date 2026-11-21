# hvl/pin/tests/irq_storm.cmd -- generated (see irq_storm.c for the protocol).
# Run with: hvl/pin/pin.sh run hvl/pin/tests/irq_storm.c hvl/pin/tests/irq_storm.cmd
load_lst $MEM
uart_div 1
uart_fail PIN_STORM_BAD
reset 16
run_until_uart 400000 PIN_STORM_ARMED
run 82
irq 1 1
run_until_uart 200000 A6_1
irq 1 0
run 106
uart_send r
run_until_uart 400000 R_1
run 42
irq 0 1
run_until_uart 200000 A3_1
irq 0 0
run 142
uart_send r
run_until_uart 400000 R_2
run 192
irq 0 1
run_until_uart 200000 A3_2
irq 0 0
run 154
uart_send r
run_until_uart 400000 R_3
run 264
irq 0 1
run_until_uart 200000 A3_3
irq 0 0
run 59
uart_send r
run_until_uart 400000 R_4
run 49
irq 0 1
run_until_uart 200000 A3_4
irq 0 0
run 116
uart_send r
run_until_uart 400000 R_5
run 40
irq 1 1
run_until_uart 200000 A6_2
irq 1 0
run 66
uart_send r
run_until_uart 400000 R_6
run 287
irq 0 1
run_until_uart 200000 A3_5
irq 0 0
run 113
uart_send r
run_until_uart 400000 R_7
run 294
irq 0 1
run_until_uart 200000 A3_6
irq 0 0
run 36
uart_send r
run_until_uart 400000 R_8
run 327
irq 0 1
run_until_uart 200000 A3_7
irq 0 0
run 165
uart_send r
run_until_uart 400000 R_9
run 300
irq 0 1
run_until_uart 200000 A3_8
irq 0 0
run 154
uart_send r
run_until_uart 400000 R_10
run 30
irq 1 1
run_until_uart 200000 A6_3
irq 1 0
run 61
uart_send r
run_until_uart 400000 R_11
run 290
irq 0 1
run_until_uart 200000 A3_9
irq 0 0
run 39
uart_send r
run_until_uart 400000 R_12
run 219
irq 1 1
run_until_uart 200000 A6_4
irq 1 0
run 41
uart_send r
run_until_uart 400000 R_13
run 297
irq 0 1
run_until_uart 200000 A3_10
irq 0 0
run 83
uart_send r
run_until_uart 400000 R_14
run 57
irq 0 1
run_until_uart 200000 A3_11
irq 0 0
run 153
uart_send r
run_until_uart 400000 R_15
run 195
irq 0 1
run_until_uart 200000 A3_12
irq 0 0
run 29
uart_send r
run_until_uart 400000 R_16
run 293
irq 0 1
run_until_uart 200000 A3_13
irq 0 0
run 20
uart_send r
run_until_uart 400000 R_17
run 259
irq 0 1
run_until_uart 200000 A3_14
irq 0 0
run 179
uart_send r
run_until_uart 400000 R_18
run 165
irq 1 1
run_until_uart 200000 A6_5
irq 1 0
run 124
uart_send r
run_until_uart 400000 R_19
run 190
irq 1 1
run_until_uart 200000 A6_6
irq 1 0
run 81
uart_send r
run_until_uart 400000 R_20
run 97
irq 0 1
run_until_uart 200000 A3_15
irq 0 0
run 183
uart_send r
run_until_uart 400000 R_21
run 46
irq 0 1
run_until_uart 200000 A3_16
irq 0 0
run 152
uart_send r
run_until_uart 400000 R_22
run 273
irq 1 1
run_until_uart 200000 A6_7
irq 1 0
run 131
uart_send r
run_until_uart 400000 R_23
run 378
irq 1 1
run_until_uart 200000 A6_8
irq 1 0
run 119
uart_send r
run_until_uart 400000 R_24
uart_send b
run_until_uart 400000 B_READY
irq 0 1
irq 1 1
run_until_uart 200000 A6_9
run_until_uart 200000 A3_17
irq 0 0
irq 1 0
run 100
uart_send r
run_until_uart 400000 R_25
uart_send t
run_until_uart 400000 T_SET
irq 0 1
run 3000
irq 1 1
run_until_uart 200000 A6_10
irq 1 0
irq 0 0
run 100
uart_send q
run_until_uart 400000 PIN_STORM_DONE
run_until_tohost 400000
expect_tohost 0
finish
