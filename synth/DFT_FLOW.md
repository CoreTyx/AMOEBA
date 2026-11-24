# DFT synthesis and verification

## 1. Run synthesis and scan insertion

Run these commands on the VM from the existing project directory. Git is not
needed on the VM.

Before starting:

- Keep the VM's `synth/libs.mk`, pad wrappers in `io_drivers/`, and licensed
  cell/SRAM libraries in place.
- Make sure `libs.mk` points to the intended libraries and exports the tool and
  output settings used by `synthesis.tcl`.
- Archive any results you need. `make synth` cleans its report/output folders.

```bash
cd synth
module load Synopsys_x86-64

make SHELL=/bin/bash '.SHELLFLAGS=-e -o pipefail -c' \
    synth DFT_SCOPE=full SYN_OUT_DIR="$PWD/synout" REPORT_DIR="$PWD/reports"

make SHELL=/bin/bash '.SHELLFLAGS=-e -o pipefail -c' \
    dft DFT_SCOPE=full
```

The Bash settings support the Makefile's logging pipelines and propagate
pipeline failures on supported GNU make versions. Also inspect the DC logs
and DRC reports, rather than relying on the presence of output files alone.

These are two different operations:

- **`make synth`** compiles the RTL, saves a mapped checkpoint before scan
  insertion, then performs an integrated scan insertion.
- **`make dft`** starts a fresh DC session and repeats insertion from that
  checkpoint. It does not compile the RTL again. The separate output directory
  makes this the recommended set of files for full_tb.

**Set the scan scope during synthesis.** `DFT_SCOPE=full` selects the PC,
selected pipeline registers, and hardened CSRs. The default, `pc`, selects only
the PC. Setting `DFT_SCOPE=full` on `make dft` does not change a PC-only checkpoint
into a full-scope checkpoint. Actual cell counts depend on mapping and library.

`DFT_KEEP_ALL=1` is an optional synthesis setting that retains selected constant,
unloaded or duplicate state that DC would otherwise optimize away. Changing it
requires synthesis again.

## 2. Find the outputs

Paths below are relative to `synth/`, using the commands above.

| Path | Contents |
|---|---|
| `synout/forte_top.pre_dft.ddc` | Mapped checkpoint before insertion. This is the input to `make dft`. |
| `synout/dft/forte_top.gate.v` | Scan-inserted netlist from `make dft`. |
| `synout/dft/forte_top.gate.ddc` | Inserted design in DC format. |
| `synout/dft/forte_top.scandef` | Chain order, cells and connections. |
| `synout/dft/forte_top.scan_phase.txt` | Logical storage polarity for each scan cell. |
| `synout/dft/forte_top.spf` | Test protocol. |
| `reports/synthesis.log` | Synthesis and integrated-insertion console log. |
| `reports/dft/dft.log` | Standalone `make dft` console log. |
| `reports/dft/` | DFT signal, clock-gate, DRC, chain and phase reports. |
| `reports/pre_dft/`, `reports/scan_mode/` | Pre-insertion and scan-mode reports. Functional reports are directly under `reports/`. |

The integrated insertion from `make synth` also writes netlist, DDC, scandef,
phase and protocol files directly under `synout/`. It additionally writes
`forte_top.gate.sdf` and `.gate.sdc` there.

**Use one matching output set.** For example, pair the netlist in `synout/dft/`
with the scandef and phase file from that same directory and generation.
Standalone `make dft` does not regenerate SDF. Do not pair its changed netlist
with an older SDF from the integrated insertion.

## 3. Run full_tb on the inserted netlist

**Create `synth/scripts/full_tb/paths.sh` before running anything in full_tb.**
This is VM-local configuration. Use absolute paths for the files from step 2
and matching simulation models:

```bash
# synth/scripts/full_tb/paths.sh
NETLIST=/absolute/path/to/project/synth/synout/dft/forte_top.gate.v
SCANDEF=/absolute/path/to/project/synth/synout/dft/forte_top.scandef
LOGICAL_PHASE=/absolute/path/to/project/synth/synout/dft/forte_top.scan_phase.txt
STDCELL_MODELS=(/path/to/standard_cells/*.v)
SRAM_MODELS=(/path/to/sram_models/*.v)
PAD_MODELS=(/path/to/pad_models.v)
VCS_FLAGS=()  # Add any defines/options required by your library models.
SDF=
```

These are ordinary Bash assignments, with no export required. Model settings
can contain files, globs or directories. Keep the actual pad/SRAM models and
required model defines consistent with synthesis.

From `synth/`, after loading the Synopsys module:

```bash
cd scripts/full_tb
./run.sh --regen +SCAN_OP=both
./regress.sh
```

- `--regen` builds the scan map and internal hookups from the new files. It
  does not synthesize hardware or generate the logical-phase input.
- `SCAN_OP=both` checks loading first, then independently reloads and checks
  capture for the scan-pattern tests.
- A/M/B always run first. The default remaining phases are C/D/E/P/H/F/R/I/S,
  including randomized patterns, fault injection, instruction execution and
  reset-free hold/restore/resume.
- `regress.sh` runs 11 jobs with separate logs, including R1000, I64 and S with
  eight programs.

For a complete result, require `DFT TB PASS` without partial coverage, and
confirm that all intended phases executed. Phase S reports retention and DFT
control coverage separately. Missing required probes produce explicit skips.
Paused req/wr X/Z produces warnings, not failures. A definite `1` on either
handshake still fails, as do agent errors, retention/control violations and
scan-data mismatches. A pad warning does not prove internal link isolation.

Current logs are under `scripts/full_tb/sim/`. Regression logs and
`summary.tsv` are under `scripts/full_tb/regressions/<timestamp>_<pid>/`.
Run simulations sequentially because they share the build/current-log folder.
Full_tb is zero-delay and rejects nonempty SDF.

Useful focused checks, from `scripts/full_tb/`:

```bash
./run.sh +SCAN_PHASES=S +SCAN_OP=both
./run.sh +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL
./regress.sh --unload-reset     # compare protected/unprotected legacy readout
./run.sh +define+BREAK_SE       # must fail: shifting disabled
./run.sh +define+BREAK_MAP      # must fail: map inversion corrupted
./run.sh +SCAN_OP=both          # restore the normal build after negative checks
```

See [full_tb/README.md](scripts/full_tb/README.md) for each phase, plusargs,
readout protection and coverage limits.

## 4. Decide what must be regenerated

| Change | Required steps |
|---|---|
| RTL, processor configuration, libraries, synthesis settings or selected scan registers | `make synth`, `make dft`, then full_tb `--regen` and verification. |
| Insertion-only settings such as chain stitching | `make dft` using a compatible checkpoint, then full_tb `--regen` and verification. |
| Map classifications, verified phase input or hookup generator | Regenerate the bench metadata and rerun verification. Re-synthesize if the hardware also changed. |
| Only a test case, iteration count or other runtime plusarg | Reuse the matching metadata and run the bench. |

After any RTL or processor-configuration update, rebuild from RTL. Repeating
`make dft` alone uses the hardware saved in the existing checkpoint and does
not incorporate source changes.

If `make dft` reports no target for `synout/forte_top.pre_dft.ddc`, first run
synthesis successfully. A previously inserted `.gate.ddc` is not that input.

## Flow implementation

| File | Responsibility |
|---|---|
| `synthesis.tcl` | Read RTL, apply setup, compile, check hold/clock gating, save the checkpoint, insert scan and write reports/outputs. |
| `dft_setup.tcl` | Select PC/full scope, declare test controls and protect selected state/control paths during compilation. |
| `dft_procs.tcl` | Resolve mapped DFT control drivers, check hold/ICG structure, and write logical-phase metadata. |
| `dft_insert.tcl` | Restore checkpoint attributes, connect eight chains, run DRC/insertion and export scan files. |

The flow keeps the named `chip` boundary while allowing optimization across
it. It preserves the scan-enable synchronizer path so compilation cannot make
hold mode unreachable. Selected scan registers are protected from retiming
and inappropriate clock gating. Post-compile checks reject mixed scan/non-scan
clock gates and missing required hold dependencies. Post-insertion checks
verify ICG test-enable connections.

The effective RTL controls are:

```text
test_mode_dft = test_mode_s & dft_unlocked
scan_en_dft   = scan_en & test_mode_dft
hold         = test_mode_dft & hold_mode
```

`test_mode_s` is synchronized. `hold_mode` samples synchronized scan enable
while test mode is low and remains selected during the session. The tester
arms SE before raising TM for hold mode, and keeps SE low before entering
legacy capture mode. Full_tb implements both entry sequences.

DFT analysis assumes unlocked permission, settled test mode and legacy
`hold_mode=0`. These declarations do not tie the hardware controls to constants
or establish that the resumable hold protocol works. Phase S checks that
protocol behaviorally.

The flow keeps logical storage polarity separate from Q/QN scan-path
inversion. `-no_seq_output_inversion` prevents inverted storage during compile,
and exported phase metadata records the actual mapped result.

## Acceptance and verification limits

- Inspect `dft_drc_pre.rpt`, `dft_drc_post.rpt`, `dft_preview.rpt`,
  `dft_scan_path.rpt`, `dft_cg_config.rpt` and `dft_phase.rpt` under
  `reports/dft/`. Require valid eight-chain connectivity and no DRC errors or
  fatals.
- Require hold-selector, clock-gate mixing, full-scope hold-coverage and ICG
  hookup checks to pass. Do not use `DFT_HOLD_COVERAGE=warn` to qualify a design
  with missing hold coverage. Structural dependence is not proof of retention.
- PC-only scope uses `scripts/pc_tb/`, not the full-scope register tests. Its
  runner takes an explicit paths file and uses `SCAN_PHASE` for polarity.
  It does not test resumable hold. Use full scope for the procedure above.
- Conventional capture readout holds reset by default and is destructive.
  A resumable phase S session never asserts reset while preserving state.
- Hold stops MTIME and PLIC state, but UART and input synchronizers continue
  running. Short pulses and active peripheral traffic need separate handling.
- Full_tb does not provide ATPG fault coverage, instruction-by-instruction ISA
  proof, Linux scan/resume qualification or physical timing signoff.

For native hold-only checks, run `JOBS=2 hvl/pin/hold_regress.sh` from the
repository root. For ordinary functional gate verification, configure
`hvl/pin/vm_paths.sh` and use the VCS pin-bench commands in
[hvl/pin/README.md](../hvl/pin/README.md). That flow supports matching SDF, but
does not replace scan timing qualification.
