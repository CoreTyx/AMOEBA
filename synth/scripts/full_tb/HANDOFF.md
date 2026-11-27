# Handoff: post-PnR DFT tests with SDF

Status as of 2026-11-27.
- **Branch:** `dft-postpnr-sdf` on GitHub
  (https://github.com/CoreTyx/AMOEBA/tree/dft-postpnr-sdf), based on
  `dft-hold-integration` (`e56ecf8`). Not merged.
- **On the VM:** this tree is unpacked at `/groups/ece427-group4/dft_post_pnr/dft_pnr_testing`.
- **Paths file:** `/groups/ece427-group4/dft_post_pnr/vm_paths.sh`, beside the checkout.
- **Doc locations:** this file is the current status. The run details are in
  `README.md` here (section "Post-PnR from vm_paths.sh"), and the synthesis side
  is in `synth/DFT_FLOW.md`.

## Goal

Check the DFT hold and scan path on the **post-PnR netlist with its SDF**:
- scan-out and scan-in work with real delays and timing checks on;
- a program paused by hold sessions, with its state scanned out and scanned
  back in, still finishes correctly.

The VM provides only the PnR `.v` and `.sdf`. Neither PnR nor synthesis gives
us a scandef or logical-phase file for that netlist, so the tests have to work
from those two files and the cell, SRAM and pad models.

## How to run it on the VM

```bash
cd /groups/ece427-group4/dft_post_pnr
# once: the paths file lives HERE, beside the checkout, so a new copy of the
# repo unpacked over dft_pnr_testing/ never replaces it
cp dft_pnr_testing/hvl/pin/vm_paths.example.sh vm_paths.sh   # or copy the post-PnR flow's own
vi vm_paths.sh           # NETLIST=<PnR .v>  SDF=<its .sdf/.sdf.gz>  models, VCS_FLAGS, IGNORE_CELLS

module load Synopsys_x86-64      # if vcs is not on PATH
tmux new -s dft
cd /groups/ece427-group4/dft_post_pnr/dft_pnr_testing
synth/scripts/full_tb/postpnr_dft.sh --quick --ignore-neg-delay   # setup check, minutes
synth/scripts/full_tb/postpnr_dft.sh --ignore-neg-delay           # full, hours (both corners)
cat synth/scripts/full_tb/results/<stamp>/SUMMARY                 # paste this back
```

Every script looks for the paths file in this order:
1. `--vm-paths FILE`;
2. `$VM_PATHS`;
3. `../vm_paths.sh`, beside the checkout;
4. `hvl/pin/vm_paths.sh`.

Other options:
- `--corners min,max` is the default.
- `--from N` restarts at stage N. Discovery is cached per netlist.
- `--ignore-neg-delay` lets through the two small negative IOPATH delays we
  already know about in the VM SDF (`SDFCOM_NIOD`). Every line it affects says
  "not sign-off".

`SUMMARY` holds only counts, verdicts and RTL register names. It has no cell
names, model text or SDF values, so it is safe to paste anywhere. The full
logs stay on the VM in `results/<stamp>.tgz`.

## What the one command does (`synth/scripts/full_tb/postpnr_dft.sh`)

| Stage | What it shows |
|---|---|
| 1 preflight | The paths and models exist, `vcs` is on PATH, the netlist has `module forte_top` (pad ring included), and the SDF has `TIMINGCHECK`. It also counts the RECREM entries. |
| 2 discover | The chain order, scan-path inversions and logical phase, found by simulating the netlist (below). Zero-delay, cached. |
| 3 zero-delay full_tb | Every phase (A M B C D E P H F R I S) on the PnR netlist with the discovered data. Then `+define+BREAK_SE` and `+define+BREAK_MAP` must FAIL. A failure here comes from the data or the logic, not timing. |
| 4 timing, per corner | `full_tb --timing`: first phase S, 40 cases. Each pauses a program, scans its state out, scans it back in, resumes, and compares with a run that had no session. Then `regress.sh --timing`, 11 jobs. Clocks: 10 MHz functional, 1 MHz scan. Timing checks are on, and any violation fails. |
| 5 holds, per corner | The pin bench's DFT hold regression on the netlist with the SDF: programs with 16 holds each, plus the IRQ case. The link traffic must match an unheld run of the same build. |

## How phase and chain order are found without a scandef

`run.sh --regen` runs discovery when no scandef is given. `--discover` forces it
even when one is given; the given files are then only compared, as counts.
- `src/discover_cells.py` lists every flop in the netlist by its physical Q: a
  leaf cell with a connected Q or QN, excluding the SRAM and pad macros.
- `src/scan_discover.svh` (a `+define+SCAN_DISCOVER` build of `tb_scan.sv`)
  works in these steps:
  1. Record every flop at reset.
  2. Enter hold-mode scan with reset held, and flush zeros through the chains.
  3. Shift one 1 into each `io_in[k]`. The flop that holds it after step n is
     cell n. Its value after the zero flush is the inversion from scan-in.
  4. Random loads confirm each candidate. Flops that sample `io_in` every cycle
     (the link PHY's input registers) are set aside: they keep tracking `io_in`
     while scan enable is low.
  5. An off-chain twin (the `scan_q` stub, which copies cell 1) is set aside by
     forcing each candidate's Q. Only the real cell drives the next one.
- `src/discover_meta.py` writes `forte_top.scandef` (order, with `OUT Q|QN` from
  the inversions seen) and `forte_top.scan_phase.txt`.
  - A cell stores its bit inverted when its Q at reset is the complement of its
    register's RTL reset value, from `scan_map.awk`'s table.
  - The 64 cells of `ReadDataMWReg`, which has no reset, are "not observed" and
    get phase 0. Phases E, P and I check them by function.
  - PnR does not invert stored values; it only resizes and buffers cells.

## Shared SDF rules (the same for both benches)

- `hvl/pin/sdf_prep.sh` unpacks `.gz` and requires `TIMINGCHECK`. When the SDF
  has RECREM entries and no model has a `$recrem` check, it writes them as
  SETUPHOLD. Otherwise VCS drops them silently, which on the VM gave 24 false
  violations and then X.
- Flags: `-negdelay +neg_tchk +define+NTC +define+RECREM`; `+define+ARM_UD_*`
  is dropped for SDF builds.
- `hvl/pin/sdf_msgs.sh` judges the annotation. It accepts only:
  - `SDFCOM_UHICD` on wires into `forte_top` output ports;
  - `SDFCOM_IWSBA` on INTERCONNECT through an assign;
  - with `--ignore-neg-delay`, `SDFCOM_NIOD`.

  Each one is checked against its SDF line, and anything else fails. When VCS
  reuses an unchanged build, the log of the compile it reused is judged.
- `src/timing_report.py` counts violations by check kind, bench phase and
  register.
- `IGNORE_CELLS` stubs come from `hvl/pin/pin.sh ignored-cells`.

## Changes from `dft-hold-integration`

- `hvl/pin/`:
  - The post-PnR pin bench is taken unchanged from `postpnr_verif`.
  - `pin.sh` uses `sdf_msgs.sh`, adds the `ignored-cells` command, and looks
    for `../vm_paths.sh`.
  - `pin_tb.sv` `dft_hold` pauses the link agent's sampler during the hold. On
    a netlist, `io_out` carries scan-out then, and it can be X. `req`/`wr` are
    still checked every frozen cycle.
  - `hold_regress.sh`:
    - runs with `SIM=vcs DUT=gate`, with the SDF per corner;
    - uses the prebuilt `hold_images/*.lst` when there is no RISC-V compiler;
    - on gate runs, makes the gapped profile hold with scan enable low. Scan
      enable high through a hold shifts the real chains with nothing reloaded,
      which corrupts the program by design. The reload case is phase S.
- `synth/scripts/full_tb/`: `postpnr_dft.sh`, discovery, the `run.sh` rework
  (vm_paths, `--corner`, `--ignore-neg-delay`, `IGNORE_CELLS`), `regress.sh`
  options, `timing_report.py`, the README section, and `standin/` (the EWS
  FreePDK45 stand-in builder).

## What has been checked (on EWS, with no VM access)

The stand-in is a FreePDK45 synthesis of this branch's own DFT flow. It has
1,299 scan cells on 8 chains, the same count as the VM's last full-scope run.
- **Discovery against DC's own scandef:** all 1,299 positions match, including
  the 925 inverted scan outputs. The phase agrees for all 1,235 observable
  cells.
- **An inverter inserted on a scan path:** discovery adjusts, and phases A, M,
  B and C pass. DC's original scandef would fail phase M on that netlist.
- **Zero-delay full_tb with the discovered data:** phases A, M, B and C pass.
  - Phase S fails 4 checks, but fails identically with DC's own scandef.
  - The cause is a quirk of the stand-in, not of discovery:
    `internal_hookups.py` probes the net named `chip.scan_en_dft`, which is
    inverted in the FreePDK45 mapping.
- **SDF stages:**
  - bad annotation is rejected, and `SDFCOM_NIOD` fails unless
    `--ignore-neg-delay` is given;
  - violations are counted without names;
  - a run with 0 violations passes the timing check.
- **Pin-bench holds:**
  - RTL: basic_arith fast and gapped, plus irq, pass.
  - Stand-in gate netlist, zero-delay: basic_arith fast and gapped pass, and irq
    passes with 4/4 holds.
  - The prebuilt-image path passes.
- **`postpnr_dft.sh --quick` end to end:** stages 1 to 3 PASS. Stage 4 fails as
  expected on the stand-in's synthesis-only SDF (below). I stopped stage 5 by
  hand, for the same reason.

## Not yet shown, and what to watch on the VM

- **A program running under a real SDF.** The stand-in's DC SDF (no clock tree,
  unbuffered nets with a fanout of about 1,300) hangs both benches before any
  link traffic. Only the VM's real PnR SDF can show this. The post-PnR pin
  bench already passes on that SDF at 200 MHz (`postpnr_verif`).
- **The scan-enable probe.** If phase S reports "effective SE=1 outside test
  mode", first check whether `chip.scan_en_dft` in the PnR netlist carries the
  true or the inverted value. It is a name-based probe (see above).
- **Any of these in SUMMARY counts as a finding:**
  - timing violations in phase S or stage 5, split by phase and register;
  - DIFFERENT counts when a scandef or phase file is given;
  - stage 2 positions that are "still ambiguous" or have "no flop probe".
- **The DFT and P&R handoff's Innovus scan package** (Sid's handoff README): not
  run in Innovus yet. Until it is, the PnR was done without scan-chain
  awareness or scan hold views, so scan-path hold violations are likely.

## Continuing this work

### Rules
- **No foundry IP leaves the VM.** Cell names, model or `.lib` text and SDF
  values never go into git, docs, chat or pasted logs.
  - `SUMMARY`, `timing_summary.log` and stage 2's output are safe: counts, RTL
    register names and verdicts only.
  - Raw logs (`compile.log`, `sim.log`, `discover.log`, `sim/meta/`) are
    VM-only.
  - When you need to show something from them, reduce it to counts or
    SAME/DIFFERENT first.
- **Getting code onto the VM.** This copy was shipped as a `git archive`
  tarball (below). The VM can also reach GitHub: the post-PnR flow does
  `git pull` in `/groups/ece427-group4/post_pnr_tb/AMOEBA`, so a `git clone -b
  dft-postpnr-sdf` there works too. Either way, keep `vm_paths.sh` beside the
  checkout, never inside it.
- **One simulation per checkout at a time.** `run.sh`'s build and log folders
  are shared, so `regress.sh` and `postpnr_dft.sh` run their jobs one after
  another.

### Change something and ship it to the VM
```bash
# EWS
git clone git@github.com:CoreTyx/AMOEBA.git && cd AMOEBA && git checkout dft-postpnr-sdf
# ... edit, test (below), commit, push ...
git archive --format=tar.gz --prefix=dft_pnr_testing/ -o ~/dft_pnr_testing.tgz HEAD
scp ~/dft_pnr_testing.tgz <netid>@ece-427-02.ece.illinois.edu:/groups/ece427-group4/dft_post_pnr/
# VM
cd /groups/ece427-group4/dft_post_pnr && tar -xzf dft_pnr_testing.tgz   # vm_paths.sh is untouched
```
To start from scratch on the VM, remove `dft_pnr_testing/` before unpacking.
`synth/scripts/full_tb/sim/meta/` caches discovery per netlist, keyed by path,
size and modification time. A new netlist is discovered again by itself.

### Testing on EWS without the VM
- **Pin-bench holds on RTL** (Verilator, about 10 min):
  `PATH=/usr/bin:$PATH PERL5LIB=$PWD/sim/perl5 hvl/pin/hold_regress.sh`.
  On EWS the old Synopsys make 3.80 comes first on PATH, and Verilator needs
  `PERL5LIB`.
- **A full-chip netlist to run full_tb against:**
  `synth/scripts/full_tb/standin/build.sh <dir>` builds the FreePDK45 stand-in
  in about 20 min. It writes `<dir>/vm_paths.sh`. Its header lists the
  stand-in's quirks; use `SCAN_HOOKUPS=0` there. Then:
  ```bash
  synth/scripts/full_tb/run.sh --vm-paths <dir>/vm_paths.sh --discover-only
  SCAN_HOOKUPS=0 synth/scripts/full_tb/run.sh --vm-paths <dir>/vm_paths.sh --regen +SCAN_PHASES=C
  SIM=vcs DUT=gate PIN_VM_PATHS=<a copy with SDF=""> HOLD_PROGRAMS=testcode/baremetal/basic_arith.c hvl/pin/hold_regress.sh
  ```
  To check discovery against the truth, point `NETLIST` at
  `<dir>/repo/synth/synout/dft/forte_top.gate.v`, where DC's scandef and phase
  file sit beside it. Then `run.sh --discover-only --discover` prints the
  SAME/DIFFERENT counts.
- `vcs`, `dc_shell` and the licence all work on EWS
  (`/software/Synopsys-2024_x86_64`).

### Where to look when something fails
| Symptom in SUMMARY | Look at (on the VM) |
|---|---|
| 1 preflight FAIL | `results/<stamp>/preflight.log`: the path or model it names |
| 2 discover: ambiguous / no flop probe / still differ | `sim/meta/<key>/discover.log`. Probes are flops with a connected Q/QN; multibit or unusual scan cells need `discover_cells.py` taught their pins |
| 3 zero-delay, M or B fails | Discovery or the `scan_map.awk` register table (a renamed register). B checks every reset value, so a wrong phase shows here |
| 4 annotation PROBLEM | `sim/timing_<c>/compile.log`. An SDF message that `hvl/pin/sdf_msgs.sh` does not accept. Never widen the rules to pass; ask what is not annotated |
| 4 or 5 TIMING VIOLATIONS | `timing_summary.log`, by phase and register. A real finding, unless it is at startup (X before reset) |
| 4 phase S "effective SE=1 outside test mode" | Whether the netlist's `chip.scan_en_dft` net is the true or the inverted signal |

## Next steps

1. Run `--quick`, then the full run, on the VM, and paste back `SUMMARY`.
2. Triage any failure by stage:
   - stage 2 or 3: discovery or the bench;
   - stage 4 or 5 with violations: real timing findings, to send back to PnR.
3. Once it is clean, open a PR from `dft-postpnr-sdf` into `dft-hold-integration`.
