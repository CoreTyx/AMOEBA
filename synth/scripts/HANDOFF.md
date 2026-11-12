## 1. Where things live

In your mom

## 2. Files

| File | Read by | Role |
|---|---|---|
| `dft_procs.tcl` | `synthesis.tcl` and `dft_insert.tcl` | Shared procs: Q/QN-aware control hookups (`dft_bind_hookups`), the per-cell phase file (`dft_write_phase`) |
| `dft_setup.tcl` | `synthesis.tcl`, **before** `compile_ultra` | Picks the flops to scan (`DFT_SCOPE`), keeps the four control nets, declares the existing test signals |
| `dft_insert.tcl` | `synthesis.tcl` after compile (integrated), or `make dft` (standalone) | Declares the 8 chains `io_in[k] -> io_out[k]`, runs `insert_dft`, writes the protocol, scandef, phase file and reports |
| `pc_tb/run.sh`, `pc_tb/scan_map.awk`, `pc_tb/tb_scan.sv` | you / VCS | The PC bench (section 10). **Ported to `io_in`/`io_out`**; the one to run with `DFT_SCOPE=pc` |
| `full_tb/` | you / VCS | Full bench: every register on the chains (PC, pipeline, hardened CSRs). Needs a `DFT_SCOPE=full` netlist; see `full_tb/README.md` |
| `HANDOFF.md` | people | This file |

**Generated, safe to delete:** `scan_map.svh`, `simv_scan`, `simv_scan.daidir/`, `csrc/`, `compile.log`, `sim.log`, `ucli.key`. They are written into the folder `run.sh` lives in.

**DC outputs:**
- `synout/forte_top.pre_dft.ddc`: the checkpoint before insertion.
- `$SYN_OUT_DIR` (default `outputs/`): `forte_top.spf`, `forte_top.scandef`, `forte_top.scan_phase.txt`; standalone runs also write `forte_top.gate.v` and `forte_top.gate.ddc`.
- `reports/dft/` next to `dft_insert.tcl`: `dft_signals.rpt`, `dft_drc_pre.rpt`, `dft_preview.rpt`, `dft_drc_post.rpt`, `dft_scan_path.rpt`, `dft_phase.rpt`.

## 3. How DFT fits into synthesis

This is the DFT part of `synthesis.tcl` on ece-427-02. It is not in this folder.

```tcl
source dft_procs.tcl
source dft_setup.tcl                 ;# DFT_SCOPE=pc (default) or full
compile_ultra -scan -gate_clock -retime
change_names -rules verilog -hierarchy
change_names -rules nameRules -hierarchy
dft_bind_hookups chip
# Binds the four preserved nets to their mapped pins (error unless exactly one
# net and one driver each), then releases their dont_touch:
#   dft_unlocked  -> existing_dft Constant, traced back to the lock flop's Q or QN
#   test_mode_s   -> existing_dft Constant, traced back to the tmsync flop's Q or QN
#   scan_en_dft   -> spec ScanEnable -port scan_en   -hookup_pin <net driver> -active_state 1
#   test_mode_dft -> spec TestMode   -port test_mode -hookup_pin <net driver> -active_state 1
file mkdir synout
write -format ddc -hierarchy -output synout/forte_top.pre_dft.ddc
set dft_standalone false
source dft_insert.tcl
# Time functional mode only: every scan mux and Q->SI path drops out of timing.
set_case_analysis 0 [get_ports {test_mode scan_en}]
```

Why things are in this order:
- **`-scan`:** a test-ready compile maps every flop to a scan flop. `insert_dft -unscan` later turns the unused ones back into plain flops. Without `-scan`, DC uses the scan mux as a functional mux, and those cells can't be put on a chain.
- **Hookups after mapping:** the control-net hookups are bound after mapping and `change_names`, because RTL pin names don't survive mapping. `dft_setup.tcl` preserves the four nets (`enable_keep_signal_dt_net`, `set_dont_touch`) so they can be found.
- **Q/QN-aware constants:** `dft_unlocked` and `test_mode_s` are 1 in test mode, but DC may drive either net from a flop's QN, or from Q through an inverter. `dft_trace_driver` walks from the net's driver back through buffers and inverters (lib `function` `A` / `!A`) to the flop, places the Constant on the flop pin it reaches, and flips `-active_state` once per inverter. The log shows each one as `DFT hookup: chip/dft_unlocked=1 -> <pin> (Q|QN, <cell>, n inversion(s), active_state a)`, then the walk and what the flop stores. A hard-coded "Q pin, 1" (the old `dft.tcl`) was wrong whenever DC chose QN.
- **`set_case_analysis` after insertion:** placed there so `dft_drc`/`insert_dft` never see `test_mode` forced to 0 while the protocol holds it at 1.

**What a change needs:**
- **Full re-synthesis:** any change to `dft_setup.tcl` or to `compile_ultra`. `dft_setup.tcl` runs before compile, and its attributes are saved in the pre-DFT `.ddc`.
- **`make dft` is enough:** a change to `dft_insert.tcl` only. It reads `synout/forte_top.pre_dft.ddc` (or `$DFT_PRE_DDC`) in a fresh `dc_shell` (`dft_standalone true`).
- **Standalone runs skip `synthesis.tcl`:** so they don't apply the `set_case_analysis`. If that matters, add it to `dft_insert.tcl` after `insert_dft`.

Not done: false-pathing the `io_in[*]`/`io_out[*]` buses. It is still timed against the link `set_input_delay`/`set_output_delay` in the SDC, on its functional paths only.

## 4. `dft_setup.tcl`: what gets scanned

- **Scope:** run on `forte_top`. The pad ring is included; only the `chip` instance is kept as a hierarchy boundary (`set_ungroup chip false`, boundary optimisation allowed).
- **Scope** (`DFT_SCOPE` in the environment, exported by the Makefile; `make synth DFT_SCOPE=full`):
  - `pc` (default): the `pc` group only, 63 flops after PC[0] is optimised away. The bench is `pc_tb/`.
  - `full`: all three groups below. The bench is `full_tb/`.
- **Scan groups** (`scan_group_*`): one hierarchical pattern per line, matched against the elaborated, pre-compile names. `*` spans hierarchy, and only sequential cells are taken, each once.

  | Group | Contents |
  |---|---|
  | `pc` | `*/ifu/pcreg/q_reg*` |
  | `pipeline` | Pipeline stage registers: IFU (`PCDReg`, `PCEReg`, `PCMReg`, `Instr*Reg`, `Compressed*Reg`, `Spill*Reg`, `AlignedInstrRawDFlop`, `PCSrcMReg`, `InstrMisalignedReg`), controller (`controlreg[DEMW]`, `Rs1EReg`, `Rs2EReg`, `Rd[EMW]Reg`), the 7 ECC datapath registers (`RD1EReg`, `RD2EReg`, `ImmExtEReg`, `SrcAMReg`, `IEUResultMReg`, `WriteDataMReg`, `IFResultWReg`), LSU (`AddressMReg`, `ReadDataMWReg`), MDU (`W64MReg`, `MDUResultWReg`, `divfaultreg`; the old `PP1Reg`/`PP2Reg` went with the shift-add multiplier), priv (`faultreg[DEM]`, `CSRValWReg`, `wfiWReg`) |
  | `hardened_csr` | privmode TMR copies `privmodereg_*`, `privchkreg_*`; `STATUS_MPP`; `MSECFAULT_REGW`; `RANDINSTRFREQreg`; `FTStatusSticky` |

  Not scanned: the divider iteration state, caches, TLBs and register file.
- **Pattern checks:** a pattern that matches nothing prints a `WARNING`. A group that matches nothing is an `error`. The log prints the flop count per group. After any change, check the counts: the RTL widths add up to about 1,600 flops (pc 64, pipeline ≈1,470, hardened_csr ≈60).
- **`set_dont_retime` on every scan flop:** `-retime` would otherwise move or rename these registers, and the scandef names would stop matching the RTL. This is a timing cost (section 12).
- **Scan selection:** every edge-triggered register is first made non-scan, then only the groups are enabled. Two sets of flops are forced non-scan and not retimed, and the script errors if either matches nothing:
  - The DFT lock (`chip/soc/uncore/dftlock/*`). It must never be on a chain.
  - test_mode's synchroniser (`chip/tmsync/*`). Shifting it would drop test mode mid-shift.
- **No inverted storage:** `compile_ultra -no_seq_output_inversion` in `synthesis.tcl`. The variable `compile_seqmap_enable_output_inversion false` (set in `dft_setup.tcl`) only covers `compile`; `compile_ultra` ignores it and, without the option, stored 14 of the full scope's scan cells inverted on FreePDK45 (`FTStatusSticky[6]`, `AlignedInstrRawDFlop[2,3,5..15]`). With the option, and with every scan flop kept out of retiming, each scan cell holds its RTL bit in true polarity.
- **Preserved nets:** `chip/scan_en_dft`, `chip/test_mode_dft`, `chip/test_mode_s`, `chip/dft_unlocked`. The script errors unless all four exist.
- **Existing test signals:**
  - `ScanClock core_clk`, timing `{45 55}`. The single `core_clk` pad feeds both `core_clk` and `link_clk`, so there is no second test clock.
  - `Reset rst_n`, active 0.
  - `Constant test_mode`, active 1.
- **Scan configuration:** `multiplexed_flip_flop`, `-clock_mixing no_mix`, internal-pin DRC enabled. A port-only `ScanEnable scan_en` spec is declared here and replaced by the hookup in `synthesis.tcl`.

## 5. `dft_insert.tcl`: the chains

- **Eight chains** `c0..c7`. Scan-in is `io_in[k]` and scan-out is `io_out[k]`, the dedicated one-way link pads. Nothing changes direction in test mode. There are 8 of each, so no more than 8 chains. `insert_dft` balances the scan flops across them: 8 each with `pc` (7 on one chain), ≈200 each with `full`.
- **Settings:**
  - `test_default_period 100` (ns).
  - `set_dft_insertion_configuration -preserve_design_name true -synthesis_optimization all -unscan true`.
- **Sequence:**
  1. `report_dft_signal` (spec and existing_dft).
  2. `create_test_protocol`.
  3. `dft_drc` (pre).
  4. `preview_dft`.
  5. `insert_dft`.
  6. `dft_drc` (post).
  7. `change_names`.
  8. `report_scan_path` (chains and cells).
  9. `write_test_protocol` (`.spf`) and `write_scan_def` (`.scandef`).
  10. In standalone mode only: write the gate `.v` and `.ddc`, then `exit`.
- **QN inversions:** by default `insert_dft` takes each cell's scan output from whichever of Q/QN has more slack, so some chains invert. The commented-out `set test_disable_find_best_scan_out true` makes it pick by availability instead; the man page says the result can still invert. The benches handle inversions either way.
  - Count them: `grep -c 'OUT QN' ../synout/forte_top.scandef`.
- **Logical phase (`forte_top.scan_phase.txt`):** after `write_scan_def`, `dft_write_phase` writes one line per scan cell, `<scandef instance path> <0|1>`, where 1 means the flop stores its RTL bit inverted. This is the same format as `full_tb`'s `LOGICAL_PHASE`, and `pc_tb/run.sh` reads it as `SCAN_PHASE`.
  - The rule reads the netlist: DC keeps the RTL signal's name on the net that carries it, so a cell is written 1 when the net on QN has a design name and the net on Q is generated (`nNNN`) or absent. Scan-path nets (`test_si*`, `test_so*`) don't count as names. QN-only fanout alone is **not** evidence, because logic that wants `~q` legitimately reads QN of a true-polarity flop.
  - On the netlist built without `-no_seq_output_inversion`, the rule picked exactly the 14 cells that `full_tb` phase B read inverted. With the option it should write all 0; any phase-1 cell prints a `DFT phase: WARNING` and is listed with its net names in `dft_phase.rpt`. The benches' exact reset checks (B, F) stay the independent check.
  - `reports/dft/dft_phase.rpt` lists every cell: chain, index, scan-out pin, Q/QN functional load counts, and phase. It ends with totals and notes (QN-only fanout, no functional load, cells not found).
- **Checking DRC** (in `reports/dft/`):

  ```bash
  grep -ciE 'error|fatal' dft_drc_post.rpt            # must be 0
  sed -n '/DRC Report/,/Test design rule checking completed/p' dft_drc_post.rpt
  grep -oE '\([A-Z]+[0-9]+(-[0-9]+)?\)' dft_drc_post.rpt | sed -E 's/[()]//g; s/-[0-9]+$//' | sort | uniq -c | sort -rn
  ```

  Warnings on flops that are deliberately non-scan are expected. A warning that names a scanned register deserves a look.

## 6. The chip's DFT hardware (`hdl/forte_chip.sv`)

- **Gated test pins:**
  - `test_mode_s`: `test_mode` through a 2-flop `synchronizer tmsync` on `core_clk`. It follows the pin two edges late.
  - `test_mode_dft = test_mode_s & dft_unlocked`
  - `scan_en_dft = scan_en & dft_unlocked`. Not synchronised: the tester toggles it per cycle.
- **Link pads:** two one-way 8-bit buses, `io_in` (FPGA→ASIC) and `io_out` (ASIC→FPGA). There is no `dir` pin and no tristate. In test mode `io_out` carries `scan_q` (`io_o = test_mode_dft ? scan_q : lm_io_o`), and `insert_dft` adds its scan-out mux in front of each `io_out` pad.
- **Chain stubs:** the RTL holds an 8-flop `scan_q` stub that reserves the structure. `insert_dft` builds the real chains.
- **DFT lock:** `hdl/forte_dft_lock.sv` is an APB register in the uncore.
  - It resets to `unlocked = 1`. Software writing 0 locks DFT until the next reset.
  - The benches never write it, so the part stays unlocked. The lock itself is not tested.
- **Reset:** `rst_n` goes through `forte_rst_sync`. It asserts asynchronously and releases two `core_clk` edges later. Core resets are synchronous.

## 7. Running a bench

Both benches use the same `run.sh` interface and the same env file.

```bash
cd /groups/ece427-group4/dft_testing/synth/scripts/pc_tb
./run.sh env.s                          # expect "DFT TB PASS"
./run.sh env.s +define+BREAK_SE         # self-test: must FAIL
./run.sh env.s +define+BREAK_MAP        # self-test: must FAIL
```

`full_tb/` has its own runner and `paths.sh`; see `full_tb/README.md`.

**The env file** is sourced by `run.sh` when given as the first argument. Pass it explicitly: on ece-427-02, variables exported in the interactive shell did not reach `run.sh`, and the cause was never found.

```bash
NETLIST=/path/to/forte_top.gate.v                  # must contain module forte_top (pads included)
SCANDEF=/path/to/forte_top.scandef                 # default: forte_top.scandef next to NETLIST
STDCELL_MODELS=(/path/to/stdcells/*.v)             # array form: all files
SRAM_MODELS=/path/to/sram_models                   # a folder: every .v/.sv in it
PAD_MODELS="/path/io_in.sv /path/io_out.sv"        # space-separated, globs allowed
SCAN_PHASE=/path/to/forte_top.scan_phase.txt       # default: next to SCANDEF; missing = all phase 0, with a warning
VCS_FLAGS="+define+EXPECTED_CELLS=63"              # optional, added after the defaults
```

- **Forms each `*_MODELS` accepts:** a file, a glob, a folder, several of those separated by spaces, or a bash array. Arrays can't be exported, so they only work from the env file.
- **Files listed twice** are compiled once. A file that is also in `STDCELL_MODELS` stays a `-v` library.

**What `run.sh` does:**
1. Sources the env file and resolves the file lists to absolute paths.
2. Requires the scandef (the full bench can't run without it; `pc_tb` makes it optional) and runs `awk -v LOGICAL_PHASE=$SCAN_PHASE -f scan_map.awk SCANDEF > scan_map.svh`.
3. Checks that the netlist has `module forte_top`.
4. Compiles: `vcs -full64 -sverilog -timescale=1ns/1ps +nospecify +notimingcheck`, then `VCS_FLAGS`, then your extra args. The order is pad/SRAM models as sources, then `tb_scan.sv`, then the netlist, then the standard cells with `-v` (the same order as `hvl/pin/pin.sh`). This is a zero-delay functional simulation.
5. Runs `./simv_scan -l sim.log`. The terminal shows only `[time]` lines, the `GROUP:`/`REG:`/`PC:` summary and `DFT TB`. Everything is in `sim.log`.

**Defines:**

| Define | Effect |
|---|---|
| `BREAK_SE` | Holds scan enable off; phase A must fail |
| `BREAK_MAP` | Moves one QN inversion between cells 1 and 2 of c0 (parity kept); B and F must fail |
| `NO_HARDEN` | Skips phase H (full bench) |
| `EXPECTED_CELLS=n` | Phase A fails unless the chains total n cells |
| `RESET_VEC=64'h…` | PC reset vector, default `64'h8000_0000` |

## 8. `scan_map.awk`: from the scandef to the bench's map

- **Parsing:** reads the `SCANCHAINS` section. Each chain must be named `cN`; chain `cN` becomes `k = N+1` in the bench. Cells are numbered from scan-in (`j = 1`) in file order, START to STOP.
  - **Inversions:** `( OUT QN )` marks an inverting cell. The STOP cell's scan-out pin isn't in the scandef, so it is written as 2 and the bench works it out from the pin.
- **Register key and bit:**
  1. Strip `chip/` and the `soc_core_` prefix, and take the trailing index as the bit (`_5_`, `_5`, `[5]`; no index means bit 0).
  2. Drop the flop's own name (`q_reg`, `cw_stored_reg`, `<signal>_reg`) and the `_store` level of `flopenrc_ecc`. For example:

  ```
  chip/soc_core_ifu_pcreg_q_reg_1_                       -> ifu_pcreg, bit 1
  chip/soc_core_ieu_dp_RD1EReg_cw_stored_reg_5_          -> ieu_dp_RD1EReg, bit 5
  chip/soc_core_ieu_dp_ImmExtEReg_store_cw_stored_reg_5_ -> ieu_dp_ImmExtEReg, bit 5
  chip/soc_core_priv_csr_csrsr_STATUS_MPP_reg_1_         -> priv_csr_csrsr_STATUS_MPP, bit 1
  ```

- **The table** (`row(...)` calls in `BEGIN`): one row per register `dft_setup.tcl` selects. Each row gives the end of the name (an ERE anchored at `_` or `/` and at the end), the group, the kind and the reset value. The first matching row wins. Reset values are hex, `x` (no reset) or `pc` (`RESET_VEC`).

  | Kind | Meaning for the bench | Registers |
  |---|---|---|
  | `K_PC` | Deep-tested in phase E; reset value `RESET_VEC` | `pcreg` |
  | `K_DATA` | Can hold any value while stalled | Most pipeline data registers, `RANDINSTRFREQreg`. `AlignedInstrRawDFlop` resets to `13` (nop); `ReadDataMWReg` has no reset |
  | `K_ECC` | 72-bit SECDED codeword; valid codewords only, except deliberate errors in H | The 7 ECC registers |
  | `K_CTRL` | Could flush or unstall: loaded only with its reset value | `controlreg*`, `faultreg*`, `PCSrcMReg`, `InstrMisalignedReg`, `divfaultreg`, `wfiWReg`, `Spill*Reg`, `Compressed*Reg` |
  | `K_TMR` | A privmode copy, reset `3` (M mode); `reg_sub` 0–2 = mode a–c, 3–5 = check a–c | `privmodereg_[abc]`, `privchkreg_[abc]` |
  | `K_MPP` | `2'b10` sets MSECFAULT[1] | `STATUS_MPP` |
  | `K_MSECFAULT` | The sticky fault CSR the H checks read | `MSECFAULT_REGW` |
  | `K_STICKY` | Holds while stalled | `FTStatusSticky` |
  | `K_LOCK` | Must never be on a chain: phase M error | `dftlock`, `unlocked` |
  | `K_UNKNOWN` | No row matched: phase M error ("add a row for it") | — |

- **Output** (`scan_map_init()` in `scan_map.svh`):
  - Per register: `reg_name`, `reg_group`, `reg_kind`, `reg_rst`, `reg_sub`.
  - Per cell: `map_reg`, `map_bit`, `map_qn` (with the cell name as a comment).
  - One `map_notes` line per table row that matched no cell: a register `dft_setup.tcl` selected that isn't on the chains, or a name that changed. The bench prints these in phase M.

## 9. `tb_scan.sv`: the full bench

**Pin protocol:**
- The bench drives and reads only package pins.
- One test cycle is 100 ns, as in the SPF: inputs change at 10 ns, `io_out` is sampled at 40 ns, `core_clk` rises at 50 ns.
- `test_mode` stays high while testing. `scan_en` high shifts; an edge with `scan_en` low is a capture.
- `test_mode` is synchronised on chip (`tmsync`), so after each rise the bench idles `TM_SYNC` = 3 cycles with `scan_en` low before shifting.
- The bench drives `io_in` with scan-in (0 when idle), except in phase I, where the link agent drives it.
- `ready` and `rvalid` stay 0, `irq` 0, `uart_rx` 1, `fault_inject` 0.

**State model:**
- `st_t` is the value in every cell, `[k][j]`. `bits_t` is one bit per shift cycle.
- `encode(st)` gives the stream that leaves `st` in the cells; `decode(out)` turns the unloaded stream back into cell values. Both use the inversion from scan-in to each cell (`a_inv`) and from each cell to scan-out (`b_inv`), computed in M from the QN map.
- `reg_put(st, r, v)` and `reg_val(st, r)` set or read a whole register, through the `reg_k`/`reg_j` index built in M.
- `hold(tag, load, exp, func_cyc)` is the basic step. It shifts `load` in, then either applies one capture edge or runs `func_cyc` functional cycles (`test_mode=0`). It then shifts out and calls `check(tag, got, exp)`.
- `check()` compares **every** cell where `exp` is not X. It prints one error per register that differs: read value, expected value, wrong bits.
- **base** is the state read out in phase B, with X read as 0. Every later test starts from base and changes only what it tests, so a change in any other cell points at an unwanted interaction.

**Why a capture gives a predictable result:**
- **Every stage stalls.** With `ready=0` the first fetch never completes, so `IFUStallF` stalls every stage (`StallWCause` in `hazard.sv`). Registers with a `~Stall` enable hold what was loaded.
- **No exception can trap.** While that fetch is outstanding, `TrapM = (ExceptionM & ~CommittedF) | InterruptM`, so no exception traps. MIE is 0 after reset, so there are no interrupts either.
- **Flushes are still possible.** They come from mret, a CSR write fence or a branch mispredict, all driven by the control registers. So those (`K_CTRL`) only ever hold their reset value.
- **ECC registers repair themselves.** A 1-bit error is repaired on the next edge even while stalled, so ECC registers get valid codewords. The bench's `ecc_enc()` is a copy of `ecc_secded_enc` for 64 data bits.

**Phases**, in run order:

| | Checks |
|---|---|
| A | Shift zeros and read each scan-out: that is the chain's inversion. Then one 1 into every chain: the cycle it appears gives the length. Then a 0011… flush through all chains |
| M | Map vs pins: lengths, QN parity (this also settles the last cell's inversion), each register bit on at most one cell, no `UNKNOWN`/`LOCK` cells, PC[1..63] all present. Prints each chain as runs of registers, the bits a register has no cell for, the unmatched table rows, and cells per group. If the map doesn't match, B and D–H are skipped |
| B | Reset, 200 cycles stalled, unload: every cell equals its reset value (X allowed only where there is no reset). The result becomes base |
| C | Random data shifted through for 8×maxlen cycles: out equals in, delayed by the chain length and inverted per chain |
| D | Base held for one capture edge, and again for 50 functional cycles |
| E | PC: all 0, all 1, six alternating patterns (0x5555…, 0xAAAA…, 0x3333…, 0xCCCC…, 0x0F0F…, 0xF0F0…), the reset value, walking 1 and walking 0 over every PC bit, 16 random, and 4 functional-mode holds |
| P | Each `DATA`/`STICKY`/`MSECFAULT` register alone: all 1, 0x5555…, 0xAAAA…, random. Each `ECC` register: the codeword of each pattern (only all-1 if it has missing cells). `MPP` = 01 and 11. All six privmode copies = 00 (U mode) |
| H | One capture edge each. ECC 1-bit error in a data bit and a Hamming bit: repaired, MSECFAULT[4] (one case preloads MSECFAULT[0] to check that flags OR in). One bad privmode copy, for each of the six: held, MSECFAULT[0]. Two bad mode copies: MSECFAULT[3]. A reserved 10 in copy a: MSECFAULT[0]. MPP = 10: held, MSECFAULT[1]. ECC 2-bit error: held, MSECFAULT[5]. The DED cases run last because they latch the non-scan DED trap record, which only a reset clears |
| F | All 1s, ~base, then 4 random: load all cells (control included), reset, unload: every cell equals its reset value |

**End of the run:**
- One `GROUP:` line per group: registers, cells, which failed.
- One `REG:` line per failing register, with the union of wrong bits.
- A `PC:` line, then `DFT TB PASS` or `DFT TB FAIL (n errors)`.
- Only the first 50 errors are printed in full; the summary covers all of them.

**Limits and constants:**
- `MAX_LEN` 1024 cells per chain; `MAX_REGS` 256; `MAX_W` 256 bits per register (the widest is an ECC codeword at 72).
- ECC: 64 data + 7 Hamming + 1 parity = 72 bits, laid out as `{data, parity, hamming}`.
- MSECFAULT bits: 0 TMR correctable, 1 MPP reserved, 3 TMR uncorrectable, 4 ECC SEC, 5 ECC DED.
- Timeout 100 ms of simulated time. A full run is about 150k test cycles (≈16 ms) with ≈200-cell chains. At gate level, expect it to take a long time in wall-clock terms.

**What the pins can't check:**
- **Cell order** within a chain comes from the scandef. A swapped pair only shows where the two reset values differ (B, F).
- **A wrong inversion** does show, which is what `BREAK_MAP` exercises.

## 10. `pc_tb/`

The PC-focused bench. It is the first bench to run on a new netlist, and the one for `DFT_SCOPE=pc`.
- **Pins:** `io_in[k-1]` is chain k's scan-in, always driven by the bench (0 outside test). `io_out[k-1]` is its scan-out.
- **test_mode synchroniser:** every time `test_mode` rises, the bench holds `scan_en` low for `TM_SYNC` = 3 cycles (`enter_test`) before it shifts. That covers the two tmsync flops, whichever of scan enable or test mode `insert_dft` used for its scan-out mux and clock-gate test pins. The core is stalled on `ready=0`, so those cycles change nothing.
- **Map:** `scan_map.awk` records which PC bit each cell holds (`map_bit`, -1 for a non-PC cell), its scan-out QN flag (`map_qn`) and its logical phase (`map_ph`, from `SCAN_PHASE`). Phase M prints `~` for a QN scan-out and `!` for a cell stored inverted.
- **Phases:** A (lengths), M (map vs pins), B (PC = `RESET_VEC`, no PC bit X), C (round trip), D (load, capture, unload), E (PC patterns), F (reset over a loaded PC, every bit back to `RESET_VEC`).
- **Non-PC cells:** every load puts them back to the value they held after B's reset, and only PC bits are compared. That makes it usable on the widened chains too.
- **Without a scandef** it still runs A, C and coarse versions of B and D. Those coarse checks only make sense if the chains hold nothing but the PC.
- **When to use it:** as a fast first check of the PC, or to tell a PC problem apart from a pipeline/CSR one when the full bench fails.

## 11. Status

- **Ported to the 8-in/8-out link (this revision):** `dft_setup.tcl`, `dft_insert.tcl`, the new `dft_procs.tcl`, the SDC block and the DFT calls in `synthesis.tcl`, `pc_tb/` and `full_tb/`. `dft_setup_full.tcl` and `dft_insert_full.tcl` were merged into `DFT_SCOPE`, and the old below-pad `dft.tcl` was removed.
- **Files to copy to the IP VM:** `synth/{synthesis.tcl,dft_procs.tcl,dft_setup.tcl,dft_insert.tcl,Makefile}`, `synth/scripts/pc_tb/{run.sh,scan_map.awk,tb_scan.sv}` and `synth/scripts/full_tb/` (all of it except `sim/` and `regressions/`), plus `hdl/forte_link_pkg.sv` and `hvl/pin/pin_link_agent.sv` for full_tb's phase I (or set `LINK_PKG`/`LINK_AGENT` in `paths.sh`), plus `hdl/` and `pkg/` if the VM's copy predates the `io_in`/`io_out` RTL. The VM's `io_drivers/` needs only `io_in.sv` and `io_out.sv`.
- **Verified locally on EWS (2026-11-11), with FreePDK45 in place of TSMC:**
  - Setup: DC W-2024.09, the real `synthesis.tcl` (`DFT_SCOPE=pc`), behavioural pads, SRAMs as black boxes. FreePDK45's `stdcells.db` has no `test_cell` models, so a copy with `test_cell` added to the `SDFF*` cells was used.
  - Integrated run: 16 min. Post-insertion DRC had 0 errors and 0 fatals. 8 chains, 63 PC cells (c0–c6 have 8, c7 has 7), 55 scan out of QN.
  - Hookups: DC drove `test_mode_s` from **`tmsync/q_reg/QN`**. The tracer put the Constant on that QN pin with active state 1. A hard-coded Q pin would have been wrong there.
  - `scan_phase.txt` is all 0 for the PC cells. Standalone `make dft`-style insertion from the checkpoint gives the same result in about 1 min.
  - `pc_tb` passes on both netlists: B reads `PC = 0x8000_0000`, E passes 155/155, F passes 8/8. `BREAK_SE` and `BREAK_MAP` fail, and `run.sh` now exits non-zero on a FAIL.
  - Local-only quirk: FreePDK45's `stdcells.v` drives its own `RN`/`SN` input nets through `ng_xbuf` unless `+define+TETRAMAX` is given. Without it, `rst_n` reads X. The TSMC models on the VM don't need this.
- **Scandef STOP:** this DC writes `+ STOP U8 B`: the input pin of the scan-out mux in front of `io_out[k]`, not `PIN io_out[k]`. A STOP is a chain endpoint, never a scan cell. `pc_tb/scan_map.awk` and `dft_procs.tcl` now ignore it; before this, they counted it as a ninth cell per chain. `full_tb/src/scan_map.awk` and `internal_hookups.py` have the same fix.
- **Full scope (`DFT_SCOPE=full`) verified locally on EWS (2026-11-11), same setup:**
  - 1,347 flops selected (pc 64, pipeline 1,217, hardened_csr 66); 1,298 scan cells after DC merged or removed constant bits; 8 chains of 162–163; post-insertion DRC 0 errors and 0 fatals.
  - **Inverted storage found and fixed.** The first full run used plain `compile_ultra`, which ignores `compile_seqmap_enable_output_inversion` and stored 14 scan cells inverted (`FTStatusSticky[6]`, `AlignedInstrRawDFlop[2,3,5..15]`). full_tb phase B caught them, and an RTL simulation of the same reset-and-stall confirmed the RTL values. `synthesis.tcl` now passes `-no_seq_output_inversion`: 0 cells stored inverted, cell area +0.46%, same setup slack. `dft_write_phase` now reads the polarity from the netlist instead of assuming it (section 5); on the inverted netlist it found exactly those 14.
  - `full_tb`, `./run.sh --regen +SCAN_OP=both`: every phase A, M, B, C, D, E, P, H, F, R, I passes, 419 cases, `DFT TB PASS`, on both netlists (the inverted one with the phase file from the rule). Phase I ran all 16 programs through the link agent to their WFI, 40–52 line reads each, with no link errors. `BREAK_SE` and `BREAK_MAP` fail. A full suite takes about 9 min of simulation.
  - Not on the chains: `PCSrcMReg` and `InstrMisalignedReg` (no cell matches their table rows; DC optimised them away or renamed them), and the multiplier's old `PP1Reg`/`PP2Reg`, which no longer exist.
- **Earlier result, on the old 16-bit-link netlist:** PC-only passed. 63 PC flops: c0–c6 had 8 cells each and c7 had 7; c0 and c7 inverted. `DFT TB PASS`, and post-insertion DRC had 0 errors and 0 fatals.
- **Earlier full-bench checks, before a real netlist existed:** VCS W-2024.09 against a behavioural stand-in for the chip (275 cells, built with the real `ecc_secded_enc/dec` RTL):
  - The clean run passes.
  - `BREAK_SE` and `BREAK_MAP` fail as they should.
  - Four injected faults each failed in the expected phase and named the right register and bit: no ECC repair (H), a stuck capture bit (P), a wrong reset value (B, F), and an unknown cell name (M).
- **Next steps on ece-427-02:**
  1. Re-synthesise with the current scripts (`make synth`, or `make synth DFT_SCOPE=full` for full_tb).
  2. Check the per-group flop counts, the `DFT hookup:` lines, `DFT phase: ... 0 stored inverted`, any `WARNING` lines in the DC log, and the DRC reports.
  3. Check timing at 400 MHz.
  4. Run `pc_tb/` on the pc netlist, or `full_tb/run.sh --regen` on the full one.
- **Bring-up errors seen on the VM** (fixes in `full_tb/README.md`, Troubleshooting):
  - Phase A found 63 cells: the netlist was the `pc` scope; `full_tb` needs `DFT_SCOPE=full`.
  - Phase M reported one more cell per chain in the scandef than at the pins: a stale `full_tb/src/scan_map.awk` (counts the `STOP` entry) or a cached map; copy the current `src/` and use `--regen`.
  - `Identifier 'TA' not declared`: the old 16-bit `pin_link_agent.sv` on the VM.
  - `XMRE` in `scan_hookups.generated.svh`: the TSMC netlist's flattened instance names (`chip.soc_core_...`) do not match the paths `internal_hookups.py` generates. Run with `SCAN_HOOKUPS=0` until the generator is fixed for that netlist; the hookups are diagnostics only.

## 12. Known issues and risks

- **Non-scan state can change during a shift.** Control registers are on the chains, so while data shifts through them the logic around them sees passing values. Logic that isn't scanned can then act on them (a CSR write, a flush, a bus request). If D/E/P failures show control registers cleared or the PC moved, and the failures don't trace back to the register under test, this is the likely cause.
  - The stand-in chip can't show this effect.
  - Fixes are in the hardware or the selection (take the control registers off the chain), not in the bench.
- **ECC parity-bit errors are never detected.** `hdl/core/generic/ecc/ecc_secded_dec.sv` raises SEC/DED only when the syndrome is non-zero. A flip in the overall-parity bit (codeword bit 7) is therefore neither flagged nor repaired: it stays latent until a second error makes it a DED. Phase H doesn't inject there. This is an RTL issue, not a bench issue.
- **Timing.** The full scope keeps 1,347 flops out of retiming. If 400 MHz no longer closes, trim the `pipeline` group first, then re-synthesise.
- **Merged or constant flops.** `compile_ultra` removes constant flops and merges identical ones. PC[0] is gone; ImmExtE's sign-extended data bits are likely merged. Phase M lists such bits as notices.
  - The bench compares only cells that exist.
  - For an ECC register with missing cells, it loads only all-0/all-1 data and puts injected errors in the Hamming bits.
- **Shift-path hold timing isn't checked.** `set_case_analysis 0` on `test_mode`/`scan_en` removes Q→SI paths from timing. Shift is slow, so setup doesn't matter, but a real hold violation would break a chain on silicon. Check hold in a separate test-mode timing run.
- **Cell names must survive.** The awk table matches post-`change_names` names. If the `nameRules` rules or the RTL hierarchy change names, phase M reports `UNKNOWN` registers or unmatched rows; update the table.
- **The DFT lock is not tested.** The benches leave it unlocked.
- **Runtime.** Chains are about 25× longer than the PC-only ones. The full `full_tb` suite took about 9 min of zero-delay gate simulation on the FreePDK45 netlist; TSMC cell models and SDF timing will be slower.

## 13. How-tos

**Scan another register**
1. Add its pattern to the right group in `dft_setup.tcl`.
2. Add a row to `scan_map.awk`, choosing the kind by what the register does while the pipeline is stalled:
   - `K_DATA` if any value is harmless.
   - `K_CTRL` if a value could flush, trap or start an FSM.
   - `K_ECC` for a codeword.
3. Give it its RTL reset value (`x` if none).
4. Re-synthesise and run both benches.

**A register fails P or H, but its RTL really does change it.** Example: a checker that sets a sticky bit when it sees loaded data. Confirm in the RTL, then change the register's kind in the awk table, usually to `K_CTRL`.

**Debugging a `REG:` line**
1. Find the first `ERROR` for that register in `sim.log`. The tag says which phase and pattern.
2. Read it:
   - Only B and F: a reset-path problem.
   - D, E or P but not B: the capture/enable path.
   - Only in tests of *another* register: an interaction.
3. The cell names are in the comments in `scan_map.svh`.

**After any change to `tb_scan.sv` or `scan_map.awk`:** run `+define+BREAK_SE` and `+define+BREAK_MAP`. Both must fail.

**Chain inversions:** `grep -c 'OUT QN' ../synout/forte_top.scandef`. Chain lengths: `grep -A5 ScanChain ../synout/forte_top.spf`.

## 14. RTL behind the bench's assumptions (AMOEBA)

| Assumption | File |
|---|---|
| Fetch stall stalls every stage | `hdl/core/hazard/hazard.sv` (`StallWCause`, StallF..W chain) |
| No exception traps while the fetch is committed | `hdl/core/privileged/trap.sv` (`TrapM`) |
| ECC storage: repair while stalled, DED holds | `hdl/core/generic/flop/flopenrc_cw.sv`, `flopenrc_ecc.sv` |
| Codeword layout and decode | `hdl/core/generic/ecc/ecc_secded_enc.sv`, `ecc_secded_dec.sv` |
| privmode TMR copies, voting, reset to M | `hdl/core/privileged/privmode.sv` |
| MSECFAULT bit map and sticky update | `hdl/core/privileged/csrharden.sv`, `csrm.sv` |
| FTStatusSticky, the DED trap record, multiplier checker tied off | `hdl/core/wally/wallypipelinedcore.sv`, `hdl/core/mdu/mdu.sv` |
| Pipeline registers' enables and resets | `hdl/core/ifu/ifu.sv`, `ieu/controller.sv`, `ieu/datapath.sv`, `lsu/lsu.sv`, `mdu/`, `privileged/` |
| Test-mode pad mapping, lock gating | `hdl/forte_chip.sv`, `hdl/forte_dft_lock.sv` |
| Reset synchroniser | `hdl/forte_rst_sync.sv` |
