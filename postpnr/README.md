# Post-PnR chip-level verification

This flow checks that the placed-and-routed netlist of `forte_top`:

- **is functionally the RTL:** it does exactly what the RTL does at every pin, every cycle;
- **meets setup and hold:** it does so with its back-annotated delays (SDF) and the I/O timing in its SDC.

Each check runs every program we have on both sides and compares what crossed the pins:
- the directed pin tests
- baremetal, the ISA tests and FreeRTOS
- the fault-injection tests
- the Linux boot prefix
- 300 Cascade fuzz programs

```
 local (toolchain, Verilator)                 VM (VCS, PDK models)
 ─────────────────────────────                ───────────────────────────────────
 postpnr/prepare.sh                           PNR_DIR=/drop postpnr/run.sh
   RTL @ RTL_REF  ──► golden traces             netlist + SDF(max) ──► traces ─┐
   images (all tiers, fuzz)                     netlist + SDF(min) ──► traces ─┤
 postpnr/pack.sh ──► postpnr_bundle_<sha>.tgz ──►  compare with golden ◄────────┘
                                                 SUMMARY: func / tchk / win / trace
```

## 1. The drop folder

Put whatever PnR produced in one folder, anywhere, and point `PNR_DIR` at it:

| file | what |
|---|---|
| `forte_top.v` (or the only `*.v`, `.gz` ok) | post-PnR netlist; ports exactly `forte_top`'s |
| `*.sdf` (`.gz` ok) | **one** SDF with `min:typ:max` triples, **or two**, named so the corner shows (`*max*`/`*ss*`/`*slow*`/`*wc*` and `*min*`/`*ff*`/`*fast*`/`*bc*`) |
| `forte_top.sdc` (or the only `*.sdc`) | the SDC PnR signed off with, **as PnR wrote it** (`write_sdc`: flat, literal values) |
| `pnr.env` (optional) | `RTL_REF=<sha>`: the commit the netlist was made from. Also any `vm_paths.sh` override (`STDCELL_MODELS=(...)`, `VCS_FLAGS=(...)`) |

Always set `RTL_REF`. Without it, `run.sh` cannot prove the golden is the netlist's RTL, and it says so in `SUMMARY`.

## 2. Make the golden (local)

```
postpnr/prepare.sh --rtl-ref <sha>              # or PNR_DIR=... to read pnr.env
postpnr/selfcheck.sh                            # optional: the comparison's assumptions
postpnr/pack.sh                                 # -> postpnr/postpnr_bundle_<sha12>.tgz
```

**What `prepare.sh` does:**
- Checks out `<sha>` (a worktree, unless this checkout already is that RTL).
- Builds every image with `hvl/pin/images.sh`. Fuzz is your recipe:
  - `hvl/pin/fuzz/get_cascade.sh` (once)
  - `bin/pin_fuzz.py gen 300 --seed 201 --jobs 8`
- Runs each image on the Verilator RTL with this checkout's bench.
- Writes `postpnr/golden/<sha12>/{GOLDEN, rtl/, images/, traces/}`.

The golden runs double as `pin_fuzz.py run`, the RTL pre-check: every image must pass. A failing image stops the script. `--drop-failing` instead leaves it out, and `GOLDEN` names it.

**Options:**
- `--tiers directed,bm,isa,rtos,fi,linux,fuzz`: the default set. Add `fi_matrix` for 6 armed runs per ISA/ECC program.
- `--fuzz N --seed S`
- `--jobs J`
- `--linux-lst PATH`: if `testcode/linux/build/boot.lst` isn't built, give the image here, or `linux_m0` is skipped.

FreeRTOS needs `third_party/FreeRTOS-Kernel`; any checkout's copy is borrowed, or set `FREERTOS_KERNEL_DIR`.

**EWS quirks for Verilator:**
- Use a `g++` wrapper that adds `-fcoroutines`, first on `PATH`.
- Set `PERL5LIB=$PWD/sim/perl5`.

## 3. Run on the VM

The golden is committed as `postpnr/postpnr_bundle_<sha12>.tgz` (`golden/` itself is ignored), so a clone of this branch has everything. Our layout:

```
/groups/ece427-group4/post_pnr_tb/
  AMOEBA/        clone on postpnr_verif: bench, golden, builds, results
  vm_paths.sh    the TSMC model paths (format: hvl/pin/vm_paths.example.sh)
  drop/          what PnR produced (section 1)
```

`run.sh` writes builds (`sim/pin/build/`) and results (`postpnr/results/`) inside the checkout it runs from, so the checkout is what lives in the group folder. Use a clone, not a worktree: a worktree points into your home directory, which the group cannot read.

Once:

```
umask 002
git -C ~/AMOEBA fetch origin && git -C ~/AMOEBA checkout postpnr_verif && git -C ~/AMOEBA pull
mkdir -p /groups/ece427-group4/post_pnr_tb/drop && cd /groups/ece427-group4/post_pnr_tb
git clone --branch postpnr_verif ~/AMOEBA AMOEBA
cd AMOEBA
tar -xzf postpnr/postpnr_bundle_<sha12>.tgz ./postpnr/golden        # the golden only
[ -f ../vm_paths.sh ] || cp hvl/pin/vm_paths.example.sh ../vm_paths.sh   # then fill in the model paths
chmod -R g+rwX /groups/ece427-group4/post_pnr_tb
find /groups/ece427-group4/post_pnr_tb -type d -exec chmod g+s {} +
```

Extract only `./postpnr/golden`. The whole bundle would add `postpnr/BUNDLE.sha256`, and `run.sh` would then hold the checkout to the bundle's files, which fails after the next `git pull`.

`run.sh` takes the model paths from `$VM_PATHS` or `--vm-paths FILE` if given, else from `vm_paths.sh` beside the checkout (`../vm_paths.sh`), else from `hvl/pin/vm_paths.sh`. It prints which file it used and what each list holds. The lists are bash arrays in that file (`STDCELL_MODELS=(/path/*.v)`), not environment variables: an exported array never reaches the scripts.

`vm_paths.sh` needs `STDCELL_MODELS`, `SRAM_MODELS` (`rf_sp_64_128`, `_64_46`, `_64_53`, `_64_137`) and `PAD_MODELS` (`io_in`, `io_out`). `PDK_FIRST` and `VCS_FLAGS` are needed only if the models ask for them. The netlist and SDF come from one of two places:

- **`vm_paths.sh`:** set `NETLIST=...` and `SDF=...` (one SDF with min:typ:max triples; `.gz` allowed) and `run.sh` simulates exactly those. `SDC=...` there is optional. With no SDC anywhere, `run.sh` needs `--clk-mhz` and derives the I/O timing from the clock: inputs launched 25% (max corner) and 10% (min corner) of a period after the edge, outputs sampled at 75%, no pad output-window check. SUMMARY says so; it tests that the netlist runs at that clock, not the board I/O timing.
- **The drop folder:** leave `NETLIST` and `SDF` empty, put the PnR files and `pnr.env` (`RTL_REF=<sha>`) in `drop/`, and set `PNR_DIR=/groups/ece427-group4/post_pnr_tb/drop` in `vm_paths.sh` (the environment wins).

A drop folder set alongside `NETLIST`/`SDF` still supplies the SDC (if `vm_paths.sh` has none) and `pnr.env`.

If `STDCELL_MODELS` holds several variants of one library (the preflight warns when a cell is defined in more than one file), VCS takes each cell from the first file listed. `postpnr/variants.sh` builds the smoke test once per entry, with that entry first, and prints counts only: per file, the modules and the timing checks their specify blocks have, the SDF's timing checks by kind, and per build the count of each `SDF*` message. Keep the order whose build shows only `SDFCOM_UHICD`. `--static-only` skips the builds.

Each run, in a shell with `umask 002`:

```
cd /groups/ece427-group4/post_pnr_tb/AMOEBA
module load vcs && which vcs                                         # or the site's Synopsys setup
python3 postpnr/sdc_delays.py ../drop/*.sdc                           # the timing the bench will apply (if there is an SDC)
postpnr/variants.sh                                                   # once: which STDCELL_MODELS order
postpnr/run.sh --only '^smoke$' --corners max                         # minutes: models, ports, SDF annotation
postpnr/run.sh --jobs 4                                               # hours; each job holds a VCS licence
```

To update: `git -C ~/AMOEBA pull`, then `git pull` in the clone. If a new bundle came with the pull, extract its golden as above. `vm_paths.sh`, `drop/` and `results/` are untouched by both.

Without git, the bundle works on its own: `tar -xzf postpnr_bundle_<sha12>.tgz -C <dir>`, add `vm_paths.sh`, and run `PNR_DIR=... <dir>/postpnr/run.sh`. In that case `run.sh` checks every file against the bundle.

`--only '^(smoke|bm_|isa_)'` narrows the images, and `--corners max` runs one corner. `--with-vcs-rtl` also runs the golden RTL under 4-state VCS and compares it.

`--clk-mhz MHZ` runs `core_clk` at a target frequency instead of the SDC's period. The SDC's I/O delays are board delays and stay as they are; the negedge capture, sample points and output windows follow the new period, and `sdc_delays.py` refuses a period the I/O budget cannot fit (input delay `-max` must be under half a period, output delay `-max` under a period). The golden needs no change: its traces count cycles, not time. SUMMARY's `clock:` line and the `TOTAL` line name the clock. A pass at MHZ means no timing violation and identical pins on these programs at that clock. It is not STA: only the paths the programs exercise are checked. A clock faster than the SDC's is one PnR did not close timing at, and `sdc_delays.py` warns.

**Steps, each stopping the run on failure:**
1. **Bundle check.** If `postpnr/BUNDLE.sha256` is present (a bundle-only setup), every file must be as packed.
2. **Drop folder.** Find the files and record their checksums.
3. **Golden check.** The golden's RTL must be `RTL_REF`.
4. **SDC.** `sdc_delays.py` derives the bench's timing, or refuses.
5. **Corner builds.** One build per corner. Any `SDFCOM_*` message fails it, as does a missing SDF-annotation confirmation. `+neg_tchk`, `-negdelay`, `+define+NTC` and `+define+RECREM` are on, and timing checks are never disabled.
6. **Runs.** Every image × corner, compared with its golden.

The result is in `postpnr/results/<stamp>/SUMMARY`, and everything else is in `postpnr/results/<stamp>.tgz`.

## 4. What PASS means

One row per image × corner:

```
PASS isa_tc_amo                               max  func=PASS tchk=0 win=0 trace=MATCH
FAIL bm_sorting_algo                          min  func=PASS tchk=3 win=0 trace=MATCH
```

| field | PASS when |
|---|---|
| `func` | The bench passed the program: tohost exit 0, no link-protocol error, no X/Z on any output, watchdogs quiet. |
| `tchk` | No VCS `Timing violation` (setup, hold, recovery, removal, width, period) from the cell models with SDF limits. **Any one fails the row**, even if `func` passed. `postpnr/waivers.txt` is the only exception: empty by policy, and waived hits stay listed. |
| `win` | Pad timing per the SDC. Every output settles by `T - output_delay(max)` after the `core_clk` edge and holds until `-output_delay(min)` after the next. VCS checks only see internal flops; this is the pad side (`hvl/pin/pin_cycle_trace.sv`). |
| `trace` | Pins, link transactions and console are identical to the golden RTL, **cycle for cycle** (`bin/pin_trace_cmp.py`). A mismatch shows the first differing cycle, field by field, with the link transactions around it. |

## 5. The timing the bench applies

`postpnr/sdc_delays.py <sdc>` prints exactly what it derived, and `run.sh` puts that at the top of `SUMMARY`.

- **Clock:** the `create_clock` period on `core_clk`.
- **Inputs:** every input launches `set_input_delay` after the `core_clk` edge: `-max` in the **max** corner (setup) and `-min` in the **min** corner (hold). `io_in`/`ready`/`rvalid` are captured on the chip's **negedge** (`forte_link_phy.sv`), so the setup check is against `T/2`.
- **Outputs:** sampled at `T - set_output_delay -max` after the edge, and window-checked as in §4.
  The wires from the pad drivers to `forte_top`'s output ports cannot be annotated by VCS (`SDFCOM_UHICD`: they leave the annotated scope). `pin.sh` accepts that message only when its SDF line is exactly such a wire, and `run.sh` measures the largest per output group (`sdf_out_wires.py`) and makes the **max** corner's window that much stricter, so a pass holds with the wire included. `SDFCOM_IWSBA` ("INTERCONNECT will still be annotated": a cell-to-cell wire whose net passes through an `assign` in the netlist) is also accepted, since VCS annotates that delay, but only when its SDF line is an `INTERCONNECT` entry. Any other `SDFCOM_*` still fails the build.

If the cell models check an async reset with `$setuphold(posedge CK, negedge R)` and have no `$recrem` (`postpnr/variants.sh --static-only` shows the counts), the SDF's `RECREM` entries reach no check and VCS drops them **without a message**, so the model's placeholder limits are checked instead. `run.sh --recrem-as-setuphold` simulates a line-for-line copy of the SDF with each `RECREM` keyword written as `SETUPHOLD` (same pins, edges and recovery/removal values), cached in `postpnr/work/sdf/`.
  A positive `-min` (the board's hold ending before the edge, as when `-min` equals `-max`) is checked as `-min 0`: nothing launched at an edge reaches the pad before it, so the SDC then requires only that outputs stay quiet from `T - max` to the edge. `sdc_delays.py` warns when it does this.

**`sdc_delays.py` refuses, and says why, when:**
- a link port or a slow output lacks a `-max` or a `-min`;
- an input is neither delayed nor false-pathed;
- a delay is relative to another clock (a virtual clock is accepted only with the same period and waveform), or uses `-clock_fall`;
- `in_max ≥ T/2`, `out_max ≥ T`, or `in_min < 0`;
- the file is a Tcl script (`if`, procs, unknown commands in `[...]`) rather than a flat SDC.

Note that `synth/constraints.sdc` has numbers marked PLACEHOLDER, and `synth/timing/constraints_65.sdc` has **no `-min` I/O delays**. An SDC derived from it is refused until the hold-side delays are given.

**The golden doesn't depend on the SDC.** Traces count cycles from reset release and sample inputs at the clock edge, so the golden does not depend on the period or the I/O delays. `selfcheck.sh` proves that on the RTL with a 7 ns clock and moved sample points.

## 6. Triage

- **`trace=DIFF`:** `runs/<corner>/<name>/CMP` names the first differing cycle and field.
  - Rerun that image with waves: `WAVES=1`, and `+PIN_FSDB` through `hvl/pin/pin.sh` with the same env.
  - `bin/vcd_first_x.py` finds the first X.
- **`tchk>0`:** `runs/<corner>/<name>/TCHK` holds the first violations: instance, check, times.
- **X from uninitialised state:** `INITREG=0|random postpnr/run.sh ...` starts registers at a value.
  - This is for triage only, and every row says so.
  - The sign-off run is the one without it.
