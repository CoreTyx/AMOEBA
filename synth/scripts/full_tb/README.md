# Full scan testbench

Gate-level check of the scan chains from the package pins: every scanned
register (PC, pipeline, hardened CSRs) is loaded, captured, reset and read back
through the eight chains. For the DC side and the overall flow see
`../HANDOFF.md` (section 1 is the quick start) and `../../DFT_FLOW.md`.

**Typical run on ece-427-02:**

```bash
cd /groups/ece427-group4/dft_testing/synth
make synth DFT_SCOPE=full && make dft          # netlist + scandef + phase file in synout/dft/
cd scripts/full_tb
./run.sh --regen +SCAN_OP=both         # must end "DFT TB PASS"
```

## Run flow

**Create `full_tb/paths.sh`, beside `run.sh`, before running the testbench or
regression. It is local configuration and is not included in Git.** Run the
commands below from `synth/scripts/full_tb/` with VCS available.

The bench targets the current pins: eight chains `c<k>`, scan in on `io_in[k]`
and out on `io_out[k]`, from a netlist synthesised with `DFT_SCOPE=full`
(`make synth DFT_SCOPE=full`; the default `pc` scope puts only the PC on the
chains, and then only A/M/B/E have anything to test). `test_mode` goes through
a two-flop synchroniser in `forte_chip`, so each time the bench raises it, it
idles `TM_SYNC` (3) cycles with `scan_en` low before shifting. Phase I uses the
repo's current link agent (`hvl/pin/pin_link_agent.sv`, `hdl/forte_link_pkg.sv`).

Verified results (`./run.sh --regen +SCAN_OP=both`, every phase passes, 419
cases):
- TSMC 65nm on ece-427-02 (2026-11-12): 1,297 cells, 8 chains of 162–163,
  netlist from `make dft` (`synout/dft/`); `BREAK_SE` (17 errors) and
  `BREAK_MAP` (1) fail as they should.
- FreePDK45 on EWS (2026-11-11): 1,298 cells, about 9 min;
  `BREAK_SE` and `BREAK_MAP` fail as they should.

See `../HANDOFF.md` section 11.

### 1. Configure paths

```bash
# full_tb/paths.sh — ordinary Bash assignments; no export needed
# Use the make dft outputs: netlist, scandef and phase file from one run.
NETLIST=/groups/ece427-group4/dft_testing/synth/synout/dft/forte_top.gate.v
SCANDEF=/groups/ece427-group4/dft_testing/synth/synout/dft/forte_top.scandef
STDCELL_MODELS=(/path/to/cells/*.v)
SRAM_MODELS=(/path/to/srams/*.v)
PAD_MODELS=(/path/to/pads.v)
VCS_FLAGS=(+define+ARM_UD_MODEL -debug_acc+all -kdb -j4)
# Optional: logical-phase file; otherwise ./scan_phase.txt if present, else
# forte_top.scan_phase.txt beside SCANDEF (written by dft_insert.tcl)
# LOGICAL_PHASE=/path/to/scan_phase.txt
# Optional: link sources for phase I if the repo's hdl/ and hvl/ are not
# three levels up from full_tb (as on a VM with only synth/ copied)
# LINK_PKG=/path/to/hdl/forte_link_pkg.sv
# LINK_AGENT=/path/to/hvl/pin/pin_link_agent.sv
# SCAN_HOOKUPS=0  # Disable internal diagnostics; default is 1
```

Use a matching netlist, scandef and phase file, all from the same DC run:
`synout/dft/` after `make dft`, or `synout/` after `make synth` alone. Mixing
them (for example a `synout/dft/` netlist with the `synout/` phase file) gives
wrong results without any error. Use matching cell/SRAM/pad models. Model settings accept
files, directories, or arrays of paths/globs. Relative paths resolve from the
caller's directory. `SCANDEF` defaults to `forte_top.scandef` beside the netlist.
Simulation is zero-delay: nonempty `SDF` is rejected; `SDF_CORNER` has no effect.

### 2. Update mappings and logical phase

After regenerating the netlist or changing scan selection:

1. Point `paths.sh` at the new netlist/scandef pair. Update the register table
   in `src/scan_map.awk` for changed names, classifications, and reset values.
2. Review the logical phase. `dft_insert.tcl` writes `forte_top.scan_phase.txt`
   beside the scandef, and `--regen` uses it unless `LOGICAL_PHASE` or a local
   `scan_phase.txt` overrides it. Each entry is
   `<full scandef instance path> <0|1>`: `0` means physical Q matches the logical
   RTL bit; `1` means it is inverted. `synthesis.tcl` runs `compile_ultra
   -no_seq_output_inversion`, so expect all `0`, and the DC log line
   `DFT phase: ... 0 stored inverted`. `dft_write_phase` reads each cell's
   phase from the netlist (a cell with Q and QN whose RTL-named net hangs off QN
   is `1`; single-output cells are `0`) and
   lists any such cell in `reports/dft/dft_phase.rpt`; B and F's exact reset
   values cross-check it. **Q versus QN
   scan-output selection does not establish logical phase.** Do not reuse old
   instance paths.
3. Regenerate metadata and run a baseline check:

```bash
./run.sh --regen +SCAN_PHASES=E '+SCAN_CASE=E reset value' +SCAN_OP=both
```

`--regen` rebuilds `sim/scan_map.generated.svh`, optional
`sim/scan_hookups.generated.svh`, and its `.report.tsv`, then compiles and runs.
It **never generates or overwrites the logical-phase input**. Do not hand-edit
the generated map; fix its inputs and regenerate.

For verified phase changes to entries already present in the phase file:

```bash
python3 src/set_scan_phase.py '*verified_instance_pattern*' 1 --file scan_phase.txt
# Check the reported matched/changed counts, then rerun --regen.
```

The utility changes matching flags; it does not discover polarity or add
missing entries. Regenerate after changing netlist, scandef, phase corrections,
or generators. Normal runs reuse cached metadata; `run.sh` stops and asks for
`--regen` when the map is missing or older than the netlist, scandef, phase
file or `src/scan_map.awk`.

### 3. Run and inspect results

```bash
./run.sh +SCAN_OP=both  # Full suite, including R100 and I16
./regress.sh           # Ten runs with separate logs and a summary
```

The regression runs baseline repetition, E load-only, D capture, E/P/H/F,
the full suite, R1000, and I64. H includes baseline sentinels; R1000 uses an
extended watchdog. Runs continue after failures. Do not run simulations or
regressions concurrently: they share `sim/`.

Current logs: `sim/run.log`, `compile.log`, `sim.log`, and `pin_trace.log`.
Regression archives: `regressions/<timestamp>_<pid>/`, including per-run
commands/logs/phase results and `summary.tsv`; previous logs go in `preexisting/`.
Regression exits are 0 for all PASS, 1 for any failure, and 2 for partial-only
coverage. A standalone passing run with explicit skips returns success but
reports partial coverage. Observed X/Z values are not sanitized. Mismatches
count per register; structural/protocol errors are reported separately.

```bash
./run.sh clean  # Remove build/current logs; retain cached metadata and phase input
```

Regression archives are preserved. These commands require no metadata
regeneration unless its inputs changed.

## Tests and interpretation

Pin comparisons determine pass/fail; internal hookups are diagnostic only.
A/M/B always run first. A map or constrained-baseline failure blocks dependent
cases. The remaining default order is `CDEPHFRI`.

| Phase | Check |
|---|---|
| A | Measure eight chain lengths/inversions; check repeating `0011` transport. |
| M | Check map lengths, inversion parity, unique register-bit assignments, and classifications. |
| B | Reset, run 200 clocks without memory responses, compare resettable bits, and save baseline. |
| C | Random shift-through data, corrected for measured chain lengths/inversions. |
| D | Reload baseline, apply one capture edge, and compare all scanned cells. |
| E | Fixed, walking-bit, and random PC patterns; other cells stay at baseline. |
| P | Individual data, valid ECC, sticky-fault and legal MPP patterns; coherent U-mode privilege copies. |
| H | Inject ECC/privilege-copy faults or reserved MPP; check repair, stored values, and MSECFAULT flags. |
| F | Load all ones, inverted baseline, or random data; reset and compare resettable bits. |
| R | Multi-register edge/random patterns with legal MPP and valid ECC; alternate valid, SEC, DED, parity-only, and TMR cases. |
| I | Execute short generated RV64 sequences through the link agent, then verify selected state through scan. |

**`SCAN_OP` controls load verification:** `capture` (default) loads, captures,
and reads back; `load` omits capture; `both` first checks load/readback, then
independently resets/reloads and checks capture. Failed loads block capture.
F substitutes reset recovery for capture. I has no scan-loaded stimulus:
`capture`/`both` execute it identically; `load` explicitly skips it. Comparison
counts include load checks and sentinels; I contributes one per execution.

D/E/P/H/R reset independently with scan disabled before loading. Reset is
released `RST_LAT` shift clocks before load completion (default four), aligning
capture with the first functional edge. These checks rely on the reset IFU
fetch-check interlock, inert controls, and no overriding fault/flush; external
`ready=rvalid=0` alone does not guarantee a stall. Current test mode does not
implement the proposed global halt. Unreset bits are excluded from reset
comparisons; only unconstrained baseline *stimulus* is filled with zeros.

**Protected readout is the default.** After capture, select scan, assert
`rst_n=0`, and shift out the pre-reset contents. Scan takes precedence over
functional reset in the selected cells; contents advance through the chain,
not through a saved internal snapshot. Incoming zeros destructively replace
them. Expected captured values, including nonzero fault flags, remain unchanged.
Reset is restored afterward. A/C transport checks do not use this protection.

R defaults to 100 iterations with zero/all-one, sign-bit/extreme, checkerboard,
and random patterns. Controls remain inert, privilege copies coherent, and
fault flags initially clear. Incomplete ECC mappings are excluded explicitly;
I fails if required endpoint mappings are missing. R reports stimulus counts
and distinct SEC bits, not exhaustive fault coverage. The current decoder does
not flag/repair overall-parity-only errors; R characterizes this limitation.

I defaults to 16 sequences across ADD/XOR/shift/MUL, RANDINSTRFREQ set/clear and
32-bit truncation, MSCRATCH readback, and MPP WARL behavior. MSECFAULT W1C is
checked on a clean baseline. The first 32 sequences use edge operand pairs;
later ones use random pairs. A defined 4 KiB instruction window exercises
multiple cache lines, latency 0–15, and gap profiles 0/10/25%; no ELF or data
loads/stores are used. After 4096–4127 clocks, scan must show the aligned WFI
in M, its following ADD in E, their PCs, expected RD1E/RD2E codewords and CSR
values, and clear MSECFAULT. Fetch PC must be known/aligned in the terminal
window, with at least two completed instruction reads and no memory writes.
Other dynamic cells are unconstrained. Operand-settling NOPs and controlled
insertion periods make these expectations explicit.

The link agent is disabled before scan takes the pins: the bench holds its
`rst_n` low (no checks, no transaction state), forces ready/rvalid low and
gives `io_in` back to the scan-in drive. Memory and errors persist; each next
case resets the DUT. Destructive scanning does not support execution resumption.

## Controls and diagnostics

| Argument | Default / purpose |
|---|---|
| `SCAN_PHASES=<letters>` | `CDEPHFRI`; ordered phases after A/M/B; letters may repeat. |
| `SCAN_CASE=<substring>` | All cases; case-sensitive filter. A/M/B/C unaffected; no executable match fails. |
| `SCAN_OP=capture|load|both` | `capture`; behavior described above. |
| `SCAN_RANDOM_ITERS=<n>` / `SCAN_EXEC_ITERS=<n>` | `100` / `16`; positive counts. Eight I cases cover all categories. |
| `SCAN_REPEAT=<n>` / `SCAN_SEED=<n>` | `1` / `1`; fresh preparation per repetition. Reproduction needs the same seed and phase order. |
| `SCAN_SENTINEL` | Off; baseline capture before each D/E/P/H/R case; failure blocks the target. |
| `SCAN_UNLOAD_NO_RESET` | Off; unprotected diagnostic readout. `SCAN_UNLOAD_RESET` explicitly requests the default; both flags together fail. |
| `SCAN_SWEEP` | Off; D's 50-clock hold and 1/2/4/8/16/50 sweeps in both modes, plus E's four 50-clock holds. |
| `SCAN_TIMEOUT_NS=<n>` | `100000000`; positive watchdog duration. |
| `FPGA_TCO_PS=<n>` | `2000`; post-rising-edge control delay, strictly between 0 and 50000 ps. |
| `FPGA_SAMPLE_PS=<n>` | `5000`; phase-I link sampling. I sets its own latency/gap profiles. |
| `SCAN_NO_DUMP` / `SCAN_TRACE_CYCLES` / `SCAN_TRACE_SHIFT` | Suppress failure dumps / enable cycle or shift tracing. |
| `+define+SCAN_FSDB` / `+define+NO_HARDEN` | Optional FSDB / explicitly skip H. |

The clock period is 100 ns; scan inputs launch 10 ns after the falling edge
and outputs sample 40 ns after it. Compiler flags such as `+define+...` go to
VCS; runtime plusargs go to simulation (`--` forces subsequent runtime args).

```bash
./run.sh +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL
./run.sh +SCAN_PHASES=I +SCAN_EXEC_ITERS=64 +SCAN_OP=both
./run.sh +SCAN_PHASES=P '+SCAN_CASE=RANDINSTRFREQreg all 1' +SCAN_UNLOAD_NO_RESET
./regress.sh --unload-reset  # Paired protected/unprotected cases; control failures remain failures
./run.sh +SCAN_PHASES=D +SCAN_SWEEP
./run.sh +define+BREAK_SE    # Expected failure: shifting disabled
./run.sh +define+BREAK_MAP   # Expected failure: corrupted inversion map
```

Long holds are optional diagnostics: scan reload does not restore unscanned
state, and a blocked link does not establish continuous retention. Requested
mismatches still fail. Passing these tests does not independently establish
mapping order/polarity, complete ECC/TMR behavior, general CPU correctness,
or ATPG fault/timing coverage. External fault injection, memory ECC, DFT-lock
transitions, and delayed/corner simulations remain outside current coverage.

## Troubleshooting

Errors seen when bringing the bench up on a new machine:

| Symptom | Cause | Fix |
|---|---|---|
| M: `cN is 9 cells in the scandef, 162 at the pins` (c7: 8) after A found the full chains | The cached map is the old PC-only one: the run reused `sim/` without `--regen` | `./run.sh --regen`. `run.sh` now refuses a map older than its netlist or scandef |
| B fails on many registers, and each `INTERNAL:` line shows `raw_Q` equal to the expected value while `logical_est` is wrong | The phase file marks true-polarity cells as inverted: an older `dft_write_phase` misread QN-only TSMC cells | Re-run insertion with the current `dft_procs.tcl` (`make dft`, or `make synth DFT_SCOPE=full`), or with a netlist built with `-no_seq_output_inversion` write an all-0 phase file: `awk '!/^#/{print $1, 0}' <scandef dir>/forte_top.scan_phase.txt > scan_phase.txt`, then `--regen` |
| B fails as above, but `make dft` printed `0 stored inverted` | `paths.sh` still points at `synout/`, so the bench read the old phase file there; `make dft` writes to `synout/dft/` | Point `NETLIST` and `SCANDEF` at `synout/dft/`; check that the run prints `logical phase from .../synout/dft/forte_top.scan_phase.txt` |
| `internal_hookups.py: map and scandef cell counts differ` (old versions: `AssertionError: Map and scandef cell counts differ`) | An old `internal_hookups.py` whose line-based parser missed cells in the TSMC scandef | Copy the current `src/internal_hookups.py`; it reads the scandef the same way as `scan_map.awk`, and prints per-chain counts if they still differ |
| `Error-[VFS_SDB_ERROR] ... tdc.sdb ... is corrupted` | Two runs building in the same `sim/`, or an interrupted compile | `./run.sh clean`, then rerun. If `clean` reports permission errors, the files belong to another user: have them delete `sim/`, or run from your own copy of `full_tb/` |
| A finds 63 cells (7 × 8 + 7) | The netlist was built with `DFT_SCOPE=pc` | `make synth DFT_SCOPE=full`, then `./run.sh --regen` |
| M: `cN is n+1 cells in the scandef, n at the pins` on every chain | An old `src/scan_map.awk` that counts the scandef `STOP` entry as a cell, or a cached map from before the fix | Copy the current `src/`; `grep -c stop_seen src/scan_map.awk` must print 0; rerun with `--regen` |
| `Error-[IND] Identifier 'TA' not declared` in `pin_link_agent.sv` | The old 16-bit link agent compiled against the new 8-bit `forte_link_pkg.sv` | Copy the current `hvl/pin/pin_link_agent.sv`, or point `LINK_AGENT` at it in `paths.sh` |
| `Error-[XMRE]` on `dut.chip.soc_core_..._reg_N_.Q` in `scan_hookups.generated.svh` | Seen with an older copy of the scripts; the current ones compile on the TSMC netlist | Copy the current `src/` and `--regen`. Fallback: `SCAN_HOOKUPS=0` in `paths.sh`; the hookups only add diagnostics, every check still runs without them |
| `INTERNAL UNAVAILABLE: <reg>[n] ... no_scan_map_entry` lines at the start | Information only: RTL bits DC removed as constant or merged (PC[0], unused control bits); phase M lists the same bits | None |

After copying new scripts or a new netlist, run once with `--regen`.

**Reading a phase-B failure:** under each `ERROR`, the `INTERNAL:` line shows
the flop outputs probed directly (`raw_Q`) next to what the bench decoded from
the pins. If `raw_Q` equals the expected value, the hardware is right and the
map or phase file is wrong; if `raw_Q` is wrong too, look at reset or the RTL.

## Files

| Path | Contents |
|---|---|
| `src/tb_scan.sv`, `src/scan_*.svh` | Scan tasks, directed/random tests, instruction builder/checks. |
| `src/{scan_map.awk,internal_hookups.py,set_scan_phase.py}` | Mapping generator, diagnostic generator, verified-phase editor. |
| `run.sh`, `regress.sh` | Entry points. |
| `paths.sh` (not in Git) | Local configuration: netlist, scandef, models. |
| `scan_phase.txt` (optional, not in Git) | A local phase file; overrides the one beside the scandef. Delete it once DC writes a correct one. |
| `sim/`, `regressions/` | Current metadata/build/logs; archived runs. |
| `generated/` | Checked-in hookup snapshots from the old 16-bit netlist, unused by the runner. |

## Open action items

- [ ] **Implement the DFT-session stall and rebuild/verify the DFT flow.** Tie
  the halt to qualified `test_mode_dft` so it persists when `scan_en=0`; audit
  unscanned side effects and synchronized mode-entry timing. Re-synthesize,
  redo scan selection (including revised multiplier state), regenerate metadata,
  remap/reverify logical phase, and verify capture/retention plus scan priority
  with the new netlist. Define intentional ECC/fault updates and any separate
  halt release needed for advancing functional capture.
- [x] **Port the testbench/DFT interface to the new I/O.** Chains are
  `io_in[k] -> io_out[k]`; phase I uses the current link agent; the bench waits
  out the test_mode synchroniser; scan_map.awk and internal_hookups.py treat the
  scandef STOP entry as the chain endpoint, not a cell.
- [ ] **Explain and fix unprotected readout corruption.** Compare matched
  protected/unprotected cases at the first divergence; inspect effective scan
  enable, DFT lock, pad mux, clocks/resets, and unscanned activity. Keep protected
  unloading as default until the supported unprotected procedure is verified.
