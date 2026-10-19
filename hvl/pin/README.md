# Pin-level bench for `forte_top`

Post-synthesis verification of the ASIC.  The bench is the bring-up FPGA in
simulation: it drives and observes `forte_top` **through its pads only**, so
the RTL, the synthesized netlist and (later) the placed-and-routed netlist all
run the same bench unchanged.  Nothing here reads a hierarchical signal; the
RTL flow in `sim/` (Spike co-simulation, RVFI) remains the authority on whether
a *program* is correct, and this bench establishes that the *chip* does the same
thing at its pins.

## What the bench does (the FPGA's jobs)

| Job | Where | Notes |
|---|---|---|
| External memory + link protocol | `pin_link_agent.sv` | `hdl/forte_link_pkg.sv` protocol, 256 MiB sparse memory, `tohost` detection, random `ready`/`rvalid` gaps and read latency |
| Console | `pin_uart_agent.sv` | 8N1 at a fixed divisor: one bit = `16 * (div << UART_PRESCALE)` core clocks (32 at div 1) |
| `rst_n`, `irq[1:0]`, `fault_inject`, `test_mode`/`scan_en`, `status` | `pin_tb.sv` | `irq` = PLIC sources 3 and 6; DFT is a stub until the DFT flow lands |
| Command interface | `pin_tb.sv` | the script language below |

**Clocking**, as on the board: `core_clk` (100 MHz) comes from the bench and
`forte_top` ties `link_clk` to it.  Bench outputs launch `FPGA_TCO_PS` (2 ns)
after the `core_clk` posedge; chip outputs are sampled `FPGA_SAMPLE_PS` (5 ns)
after the `clk_out` posedge, so an SDF run's clock insertion delay is tracked
the way the FPGA tracks it.

**4-state.**  Every earlier test ran 2-state.  Here the chip's flops start X,
unwritten memory can read back X (`mem_policy x`), the bus floats Z whenever
nobody owns it, and every sampled pin is checked with `$isunknown`.  Verilator
collapses all of that to 2-state: a Verilator pass validates the bench and the
flow, **not** X behaviour.  That is what the VCS runs are for.

## Checks

Link (each is an error, and the first error ends the run by default):
`dir`/`req`/`wr` never X/Z; `io` never X/Z while the chip drives a header or
write data; `req` only with `dir=1`, exactly two cycles, never mid-transaction;
`wr` held; no contention; TA honoured after the last `rvalid`; every address in
`EXT_MEM` and line-aligned; the first transaction after reset is a read of
`0x8000_0000`; a `req` more than 3 cycles after `ready` fell; a transaction
not finished within 1000 link cycles (watchdog).
UART: `uart_tx` never X/Z, framing (stop bit), optional fail patterns.
`status` and `clk_out`: never X/Z once out of reset.

## Running

```bash
# local (Verilator, RTL only)
SIM=verilator DUT=rtl hvl/pin/pin.sh build
SIM=verilator DUT=rtl hvl/pin/pin.sh run testcode/baremetal/sorting_algo.c
SIM=verilator DUT=rtl hvl/pin/pin.sh run hvl/pin/tests/irq.c hvl/pin/tests/irq.cmd
hvl/pin/selftest/run.sh                     # the harness's own tests
hvl/pin/vm_pack.sh                          # one file for the VM: sim/pin/vm_bundle.tgz

# VM (VCS, no git): see docs/postsynth_vm_runbook.md
tar -xzf vm_bundle.tgz; cp hvl/pin/vm_paths.example.sh hvl/pin/vm_paths.sh   # fill in, once
hvl/pin/vm_run.sh                           # paste back sim/pin/vm_results/SUMMARY
```

`DUT` is `rtl` (RTL with `SYNTHESIS` defined, so SRAM macros and pad cells as
synthesized), `rtl_sva` (RTL without it: behavioural arrays and pads, with the
RTL's SVA), or `gate` (netlist, VCS only).  Each run leaves
`sim/pin/runs/<sim>_<dut>/<name>/` with `RESULT`, `sim.log`, `pin_trace.log`
and `uart.log`; `pin.sh compare <runA> <runB>` requires two traces to match
cycle for cycle.

Programs end with `tohost = (code << 1) | 1` **followed by `fence.i`**: the D$ is
write-back, and only `fence.i` (which flushes it, `FenceI -> FlushDCache`) makes
the store visible on the link.  `bin/startup.s` does this for every bare-metal
test; an unexpected trap exits with code `0x400 | mcause`.

## Command scripts

`pin.sh run <program> <script.cmd>`; `$MEM` is the program image, `$RUN` the
run directory, `$REPO` the checkout.  One command per line, `#` comments:

| Command | Effect |
|---|---|
| `mem_policy x\|zero\|rand` | what unwritten memory reads as |
| `load_lst <path>` / `load_bin <path> <hexaddr>` | load memory |
| `reset <cycles>` | hold `rst_n` low, then release |
| `run <cycles>` | wait |
| `run_until_tohost <timeout>` / `run_until_uart <timeout> <text>` | wait for an event; timeout fails |
| `expect_tohost <code>` | exit code must match |
| `uart_div <n>` / `uart_gap <bits>` / `uart_send <text>` / `uart_fail <text>` | console |
| `irq <0\|1> <0\|1>` / `fault_inject <0\|1>` | pins |
| `dump_mem <hexaddr> <nbytes> <path>` | write memory to a file |
| `dft ...` | stub: fails until DFT testing exists |
| `finish` | pass, if no checker has fired |

## Plusargs

`+FPGA_TCO_PS` `+FPGA_SAMPLE_PS` `+FPGA_RD_LAT` `+FPGA_GAP_PCT` `+FPGA_SEED`
`+FPGA_MEM=x|zero|rand` `+FPGA_IO_IDLE=z|x` `+FPGA_X_IN_RESET` `+FPGA_WDOG` `+UART_DIV`
`+UART_PRESCALE` `+UART_TX_GAP` `+UART_QUIET` `+MAX_ERRORS` `+TIMEOUT` `+CLK_PS`.
`+FPGA_MUTATE=1..3` breaks the bench on purpose (self-test only).

Waveforms (VCS): build with `WAVES=1 SIM=vcs DUT=rtl hvl/pin/pin.sh build`, run with
`+PIN_VCD` (and `+PIN_VCD_CYCLES=n`, default 400, 0 = whole run) to get `pin.vcd`
in the run directory.

`selftest/sram_cmp.sh` compares each PDK `rf_sp_*` model in `SRAM_MODELS` with
the RTL's behavioural RAM under random traffic (part of the VCS self-test).  A
difference is SRAM behaviour the caches were never verified against.
