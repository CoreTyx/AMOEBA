# Pin-level bench for `forte_top`

Post-synthesis verification of the ASIC.  The bench is the bring-up FPGA in
simulation: it drives and observes `forte_top` **through its pads only**, so
the RTL, the synthesized netlist and (later) the placed-and-routed netlist all
run the same bench. Gate checks use pads only; RTL hold checks additionally
observe representative internal state. The RTL flow in `sim/` (Spike
co-simulation, RVFI) remains the authority on whether
a *program* is correct, and this bench establishes that the *chip* does the same
thing at its pins.

## What the bench does (the FPGA's jobs)

| Job | Where | Notes |
|---|---|---|
| External memory + link protocol | `pin_link_agent.sv` | `hdl/forte_link_pkg.sv` protocol, 256 MiB sparse memory, `tohost` detection, random `ready`/`rvalid` gaps and read latency |
| Console | `pin_uart_agent.sv` | 8N1 at a fixed divisor: one bit = `16 * (div << UART_PRESCALE)` core clocks (32 at div 1) |
| `rst_n`, `irq[1:0]`, `fault_inject`, `test_mode`/`scan_en`, `status` | `pin_tb.sv` | `irq` = PLIC sources 3 and 6; hold/resume here, inserted-chain checks in `full_tb` |
| Command interface | `pin_tb.sv` | the script language below |

**Clocking**, as on the board: `core_clk` (100 MHz) comes from the bench and
`forte_top` ties `link_clk` to it.  Bench outputs launch `FPGA_TCO_PS` (2 ns)
after the `core_clk` posedge; chip outputs are sampled `FPGA_SAMPLE_PS` (5 ns)
after the `clk_out` posedge, so an SDF run's clock insertion delay is tracked
the way the FPGA tracks it.

**4-state.**  Every earlier test ran 2-state.  Here the chip's flops start X,
unwritten memory can read back X (`mem_policy x`), `io_in` can carry X between
read words (`+FPGA_IO_IDLE=x`), and every sampled pin is checked with `$isunknown`.  Verilator
collapses all of that to 2-state: a Verilator pass validates the bench and the
flow, **not** X behaviour.  That is what the VCS runs are for.

## Checks

Link (each is an error, and the first error ends the run by default):
`req`/`wr` never X/Z; `io_out` never X/Z (the chip drives it continuously and
parks it at 0 between transactions); `req` for exactly four cycles (the four
address bytes), never mid-transaction; `wr` held; every address in `EXT_MEM` and
line-aligned; the first transaction after reset is a read of
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
JOBS=1 hvl/pin/hold_regress.sh              # RTL hold/resume versus reference execution
SIM=verilator DUT=rtl TAG=irq_hold hvl/pin/pin.sh run hvl/pin/tests/irq.c hvl/pin/tests/irq_hold.cmd
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
| `dft_hold <cycles>` | Pause the link, arm `scan_en`, enter hold without reset, check each frozen clock, exit and resume. Requires positive cycles; quiet-link timeout defaults to 10,000 clocks. Gate runs check `req`/`wr`; RTL also checks RF, pipeline, timer, cache/bus FSMs, MDU, page walker, fault/CSR/PLIC state and write enables. No actual scan chains in RTL; `full_tb` phase S tests shifting/reload. |
| `dft_locked <cycles>` | The same pin sequence as a hold entry, then `scan_en` toggling as for a shift, on a part whose software cleared the DFT lock (`hdl/forte_dft_lock.sv`): nothing may happen, and the link keeps running. RTL checks `test_mode_dft`, `scan_en_dft` and `hold` stay low every cycle; any build relies on the program still finishing (`tests/dft_lock.cmd`). |
| `dft ...` | fails: scan shifting is tested at gate level (`synth/scripts/full_tb` on `dft`) |
| `finish` | pass, if no checker has fired |

## Plusargs

`+FPGA_TCO_PS` `+FPGA_SAMPLE_PS` `+FPGA_RD_LAT` `+FPGA_GAP_PCT` `+FPGA_SEED`
`+FPGA_MEM=x|zero|rand` `+FPGA_IO_IDLE=0|x|z` `+FPGA_X_IN_RESET` `+FPGA_WDOG` `+UART_DIV`
`+UART_PRESCALE` `+UART_TX_GAP` `+UART_QUIET` `+MAX_ERRORS` `+TIMEOUT` `+CLK_PS`.
Hold controls: `+DFT_QUIET_TIMEOUT=<cycles>`, `+DFT_HOLD_SE=0|1` (default 0;
1 exercises asserted scan enable while RTL is frozen, without inserted chains).
`+FPGA_MUTATE=1..3` breaks the bench on purpose (self-test only).

`hold_regress.sh` builds once (Verilator; `JOBS` defaults to 1), then runs
arithmetic, sorting and memory/CSR workloads under fast and gapped link timing.
Each profile compares uninterrupted execution with 16 holds of 1–5,000 clocks
at different entry points. Both runs check exit code and drain the exit fence
before comparing ordered pin traffic with timestamps ignored. All 16 holds
must execute; a zero-cycle simulation cannot pass. Logs, source hashes and a
summary go to ignored `sim/pin/hold_regress/<timestamp>_<pid>/`.
An additional IRQ workload checks four holds around level-sensitive interrupt
service, matching both pin traffic and UART bytes: 100 hold sessions total.
These checks are representative, not exhaustive SRAM/RTL-state coverage.
For mapped-netlist checks and limitations see
[the DFT flow](../../synth/DFT_FLOW.md) and
[full_tb](../../synth/scripts/full_tb/README.md).

Waveforms (VCS): `WAVES=1` on both the build and the run (it selects a separate
build directory, `<sim>_<dut>_waves`), plus `+PIN_VCD` (and `+PIN_VCD_CYCLES=n`,
default 400, 0 = whole run) on the run; `pin.vcd` lands in the run directory.
`bin/vcd_first_x.py pin.vcd --after <ns>` lists the first signals to go X.
For Verdi, `+PIN_FSDB` instead (VCS only) writes the whole run to `wave.fsdb`;
open it with `verdi -ssf <run dir>/wave.fsdb`.

    WAVES=1 SIM=vcs DUT=rtl_sva hvl/pin/pin.sh build
    WAVES=1 SIM=vcs DUT=rtl_sva TAG=w hvl/pin/pin.sh run sim/pin/images/uart_echo.lst \
        sim/pin/images/uart_echo.cmd +PIN_VCD +PIN_VCD_CYCLES=5600

`selftest/sram_cmp.sh` compares each PDK `rf_sp_*` model in `SRAM_MODELS` with
the RTL's behavioural RAM under random traffic (part of the VCS self-test).  A
difference is SRAM behaviour the caches were never verified against.
