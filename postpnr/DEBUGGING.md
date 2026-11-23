# Debugging a post-PnR run: simulation, SDF, or PnR?

When a `run.sh` row or build fails, first work out **which layer is wrong**. Each layer has its own owner and its own fix:

| Layer | What it is | Who fixes it | Typical fix |
|---|---|---|---|
| **Simulation setup** | VCS flags, the cell/SRAM/pad models in `vm_paths.sh`, how the SDF is fed to VCS, the bench's pass rules | us (`hvl/pin/pin.sh`, `postpnr/run.sh`, `vm_paths.sh`) | a flag, a define, a model order, a script change |
| **SDF** | the delay/check file PnR wrote: its form, its corners, what it contains | PnR, on request | re-run `write_sdf` with other options or another analysis view |
| **PnR / layout** | the placed-and-routed design itself: real timing paths | PnR | fix the constraints (SDC), re-run timing optimisation |
| **RTL** | the design | RTL owners | almost never at this stage: the golden already passed on the RTL |

**Rule of thumb:** suspect the simulation setup first, the SDF second, PnR third. A simulation-setup or SDF problem usually shows up as a **round number, a silent zero, or something that does not change with the clock or the corner**. A real layout problem has realistic, non-round numbers and gets worse at a faster clock or the slower corner.

**IP rule (see `ONBOARDING.md`):** library model text, `.lib` contents, cell names and SDF delay values do not go into git, docs or chats. Every command below prints counts, buckets or SAME/DIFFERENT only, or our own design's instance names and run logs, which are fine to share.

Paths below are relative to the VM checkout, `/groups/ece427-group4/post_pnr_tb/AMOEBA`. `$O` is a results folder, `postpnr/results/<stamp>`, and `$S` is the SDF being simulated (named in `$O/SUMMARY`).

---

## 1. Where the run stopped

`run.sh` runs in stages, and each stage stops on its own kind of failure. The last `STOPPED:` line in `$O/SUMMARY` names the stage.

| Stage | Stops on | Most likely layer | Log |
|---|---|---|---|
| preflight | a missing model, port or tool | simulation setup (`vm_paths.sh`) | `$O/preflight.log` |
| **build** | VCS compile error, or **any SDF message not explicitly accepted** | simulation setup or SDF | `$O/build_<corner>.log` (sample); full log in `sim/pin/build/vcs_gate_sdf<corner>/build.log` |
| run | a row ends `FAIL` | any; read the row (section 3) | `$O/runs/<corner>/<name>.pin.log`, `$O/runs/<corner>/<name>/` |

`build_<corner>.log` shows only the **first 40 lines** of the SDF messages (`pin.sh`'s `head -40`), so it often ends mid-message. That is not a crash. The full list is in the build directory's `build.log`, and the line `pin.sh: SDF annotation: N SDF message(s): <TAG> xN ...` counts them by type.

Count SDF messages by type and show the first of each:

```bash
B=sim/pin/build/vcs_gate_sdfmax/build.log
grep -oE '(Warning|Error)-\[SDF[A-Z0-9_]*\]' "$B" | sort | uniq -c
awk '/(Warning|Error)-\[SDF[A-Z0-9_]*\]/{t=$0; sub(/.*\[/,"",t); sub(/\].*/,"",t); if(!(t in s)){s[t]=1; n=6}} n-->0' "$B"
```

Each VCS SDF message cites `<sdf file>, <line>` on the line after its tag, so you can always go to the exact SDF entry: `sed -n '<line>p' "$S"`.

---

## 2. Build failures: SDF annotation

`pin.sh` (`sdf_gate()`) fails the build on **every** VCS `SDF*` message except the cases below, each of which is checked individually:

| Message | Meaning | Accepted? |
|---|---|---|
| `SDFCOM_UHICD` Up-hierarchy Interconnect Delay ignored | a wire from a cell to a `forte_top` **output port** leaves the annotated scope, so VCS cannot annotate it | yes, if its SDF line is such a wire; `run.sh` tightens the output window by the largest (`sdf_out_wires.py`) |
| `SDFCOM_IWSBA` INTERCONNECT will still be annotated | a cell-to-cell wire whose net passes through an `assign` in the netlist; VCS annotates it anyway | yes, if its SDF line is an `INTERCONNECT` (**unrelated to UHICD**, despite often appearing nearby) |
| `SDFCOM_NIOD` Negative IOPATH Delay encountered | a negative cell delay that `-negdelay` could not absorb into a neighbouring delay, so VCS treats that arc as 0 | only with `run.sh --ignore-neg-delay`, which marks the run **not sign-off** |
| anything else | an SDF entry not annotated, so some delay or check is missing | no |

Common failures and what they turned out to be:

- **`SDFCOM_ICBF` Instance cannot be found.** VCS looks for each SDF `INSTANCE` path under `pin_tb.dut` (the `-sdf max:pin_tb.dut:<file>` scope, `pin.sh`). Check that the instance really is directly inside `module forte_top` **in the netlist VCS compiled** (the `vcs` line in `build.log`), not just somewhere in some `.v`:
  ```bash
  N=<netlist from build.log>
  awk '/^[[:space:]]*module[[:space:]]/{m=$2;sub(/\(.*/,"",m)} /[[:space:]]U82528[[:space:]]*\(/{print FNR": module "m}' "$N"
  grep -m1 -i '(DESIGN' "$S"          # the module the SDF was written for
  ```
  A different module means the SDF and netlist have different hierarchy (re-export both from one session). On 2026-11-22 the ICBF warnings disappeared after a clean rebuild (`rm -rf sim/pin/build/vcs_gate_sdfmax`); a stale incremental build is the suspected cause, not proven.
- **A paired-looking message is not a pair.** Do not assume two warnings belong together because they appear together. Compare the SDF lines each one cites. UHICD (pad wires, SDF lines 30 onwards) and IWSBA (CSR wires near line 42140) looked related but were not.
- **VCS exits 139 after ~1 s, `Failed to mkdir .../simv.daidir/...`.** That is a segfault on a broken build directory: a half-written `simv.daidir`, another user's files, or a full disk. Check `ls -ld`, `df -h`, then `rm -rf sim/pin/build/vcs_gate_sdf<corner>` and rebuild.
- **Fixing a check in `pin.sh`:** test it on synthetic logs before pushing. Extract `sdf_gate()` with `sed -n '/^sdf_gate() {/,/^}/p'`, stub `src_hash` and `die`, and feed it a `build.log` that uses the real message format from the VM.

### What the build gate cannot see

**VCS silently drops an SDF entry that has no matching check in the cell model.** No message, so the gate passes, and the model's built-in placeholder limit is checked instead. The only symptom is at run time: violations with suspiciously round limits. See section 4.

---

## 3. Reading a failed row

```
FAIL smoke   max  func=FAIL tchk=24 win=0 trace=DIFF  <why>
```

Read the fields in this order, because an earlier one usually explains the later ones:

1. **`tchk`** (timing violations). A failed check makes the cell model drive its output **X**. The X then spreads, so `tchk>0` often *causes* `func=FAIL` and `trace=DIFF`. Fix `tchk` first.
2. **`func`** (the bench's own verdict). `[PIN_TB] ERROR ... status is x` and the like name the first pin that went wrong and the cycle. With `--max-errors 1` (the default) the run stops there, so a short `pin_trace.log` ("ends after 0 records") is a consequence, not a separate bug.
3. **`win`** (pad output windows, `hvl/pin/pin_cycle_trace.sv`). With no SDC, `--clk-mhz` disables this check.
4. **`trace`** (equivalence with the golden RTL). Only meaningful once the first three are clean.

```bash
O=postpnr/results/<stamp>; L=$O/runs/max/smoke/sim.log.gz
zcat "$L" | grep -m3 -iE 'error|x on|unknown'                       # the bench's first error
zcat "$L" | awk '/Timing violation in/{i=$NF; sub(/_reg_[0-9]*_$/,"_reg_*",i); getline; split($0,a,/[,:]/); print i, a[1], a[3]}' \
  | sed 's/\$setuphold( *//' | sort | uniq -c                        # violations by register group, check and pin
zcat "$L" | grep -m1 -B1 -A4 'Timing violation'                      # the first one in full, with its limits
```

---

## 4. Timing violations (`tchk>0`): real, or a setup artefact?

A VCS violation line looks like:

```
$setuphold( posedge CK:97738, negedge R:98098, limits: (1000,500) );
```

The times are in ps. Here `R` was released 360 ps after the clock edge, against a 500 ps hold (removal) limit. Ask these questions in order:

1. **Which pin?** Group the violations by pin (the command above).
   - Many flops all failing on `negedge R` at about the same time means a **reset release** problem: one root cause.
   - Violations on `D` of a synchroniser's **first** stage (`prim_flop_2sync` `stage1`) are expected clock-crossing metastability, not a bug.
   - On anything else, a real path is the suspect.
2. **Are the limits real?** Round limits such as `(1000,500)` are very likely the model's placeholders. Compare the SDF's check for that instance and pin with what VCS reported. This prints SAME/DIFFERENT only:
   ```bash
   awk 'BEGIN{sc=1000} /\(TIMESCALE/{t=$0; gsub(/[()]|TIMESCALE|[[:space:]]/,"",t); n=t+0; if(!n)n=1; u=t; gsub(/[0-9.]/,"",u); sc=n*(u=="ps"?1:u=="us"?1e6:1000)}
        /\(CELL[[:space:]]*(\(|$)/{p=0} /INSTANCE/&&/tick_reg/&&/(_|\[)0(_|\\?\])/{p=1;c++}
        p&&c==1&&/(SETUP|HOLD|RECOV|REMOV|RECREM)/&&/[( ]R[) ]/{f++; k=$1; gsub(/\(/,"",k); s=$0; sub(/.*CK\)?/,"",s); d=1
          while(match(s,/-?[0-9]*\.?[0-9]+/)){v=substr(s,RSTART,RLENGTH)*sc; if(v!=1000&&v!=500)d=0; s=substr(s,RSTART+RLENGTH)}
          print "SDF check on R: " k " -> " (d?"SAME as the reported limits":"DIFFERENT: VCS is not using the SDF value")}
        END{if(!c)print "instance not found"; else if(!f)print "SDF has NO check on R"}' "$S"
   ```
   Replace `tick_reg` and `R` with the instance and pin in question, and `1000`/`500` with the reported limits.
   - **SAME:** the limit is real, so it is a **PnR** problem (section 6).
   - **DIFFERENT or NO check:** the SDF value is not reaching the model's check. That is a **simulation-setup** problem.
3. **Which checks do the models have?** `postpnr/variants.sh --static-only` counts, for each `STDCELL_MODELS` file, the modules with each kind of timing check, and the SDF's check entries by kind. An SDF check kind that no model has is exactly what VCS drops without a message.

The SDF-to-Verilog mapping (IEEE 1364-2005, Table 16-2) has no cross-kind matches:

| SDF | annotates only |
|---|---|
| `SETUPHOLD v1 v2` | `$setup(v1)`, `$hold(v2)`, `$setuphold(v1,v2)` |
| `RECREM v1 v2` | `$recovery(v1)`, `$removal(v2)`, `$recrem(v1,v2)` |

### Case study (2026-11-22): `RECREM` silently dropped

- **Symptom:** 24 `$setuphold` violations on `negedge R` (the `tick` counter and async-FIFO synchroniser flops), all limits `(1000,500)`. `status` went X, and the bench stopped at cycle 29.
- **Cause:** PnR writes async-reset recovery/removal as `RECREM` (277 entries, one per reset flop). All 8 library variants check reset with `$setuphold(posedge CK, negedge R)` and have no `$recrem`. VCS had nothing to annotate, printed nothing, and every reset flop kept the placeholder. Only the flops nearest the reset synchronisers failed.
- **Fix (simulation setup):** `run.sh --recrem-as-setuphold`. Recovery is a setup time for the reset pin and removal a hold time, so the run simulates a line-for-line copy of the SDF with `(RECREM` rewritten as `(SETUPHOLD`. Pins, edges and values are untouched, and the slots line up (recovery to setup, removal to hold). The copy is cached in `postpnr/work/sdf/`.
- **Not the fix:** the RTL (`forte_rst_sync` is a correct async-assert, sync-release reset synchroniser), PnR, or the clock. A removal check is relative to one edge, so 100 MHz and 200 MHz fail alike.

---

## 5. `trace=DIFF` with `func=PASS`: real difference, or timing shift?

First compare by content and order only:

```bash
G=postpnr/golden/<sha12>/traces/<name>/pin_trace.log; D=$O/runs/max/<name>/pin_trace.log
python3 bin/pin_trace_cmp.py $G $D --no-cycles | head -3
paste <(sed -n 9,13p $G) <(sed -n 9,13p $D)          # golden | netlist, around the first difference
```

`L <cycle> R|W <addr> <data...>` records are our own design's behaviour (not library IP), so they are fine to share.

- **`--no-cycles` matches, and only the cycle numbers differ by a small, constant amount:** a clock-domain-crossing shift. `core_clk` and `link_clk` come from one pad (`hdl/forte_chip.sv:53`) but get separate clock trees after PnR, so an async-FIFO pointer (`prim_flop_2sync`) can be caught an edge earlier or later than in RTL. A real chip does the same, and the FPGA side handshakes, so this is not a bug. On 2026-11-22 smoke was 2 cycles early from record 10 on. Use `run.sh --cycle-slack N` (agreed: 4), section 7.
- **Address, data or order differ:** a real functional difference. Debug with waves: rerun that image with `WAVES=1` and `+PIN_FSDB` through `hvl/pin/pin.sh` with the same environment, and use `bin/vcd_first_x.py` to find the first X.
- **The shift keeps growing, or exceeds the slack:** not a fixed crossing latency. Investigate.

---

## 6. Is it really PnR?

Hand a problem to PnR only after sections 4 and 5 rule out the simulation setup. Signs of a real layout problem:

- the SDF's own limit is the one violated (SAME in section 4), with realistic, non-round numbers;
- it gets worse at a higher `--clk-mhz` (setup-type) or on the fast corner (hold-type);
- PnR's own timing report on that pin shows negative slack, or shows no check at all.

Common PnR-side causes for reset-path problems:

- an SDC exception that is too broad: a `set_false_path` or `set_ideal_network` reaching the **synchronised** resets (`*rst_n_s*`, the `rstsync`/`linkrstsync` outputs), not just the raw `rst_n` input port. The synchroniser-to-`R` path is then never timed or buffered;
- recovery/removal analysis not switched on, so hold optimisation never fixes removal.

Ask PnR to confirm positive removal slack on the pin in question in their timing report before re-writing the netlist and SDF.

---

## 7. Is the SDF what we think it is?

### Does it have two real corners?

`run.sh` simulates `max` and `min` from one SDF's `(min:typ:max)` triples, unless the drop folder has two SDFs named `*max*`/`*min*`. A single-corner SDF makes the min half of a sweep a near-copy of max. Check the min/max ratios, which prints counts only:

```bash
awk '{k=""; if($0~/\(IOPATH/)k="IOPATH"; else if($0~/\(INTERCONNECT/)k="INTERCONNECT"; else if($0~/\((SETUP|HOLD|SETUPHOLD|RECREM|WIDTH|PERIOD)[ (]/)k="CHECK"; if(k=="")next
     s=$0; while(match(s,/\(-?[0-9.]*:-?[0-9.]*:-?[0-9.]*\)/)){split(substr(s,RSTART+1,RLENGTH-2),v,":"); s=substr(s,RSTART+RLENGTH); if(v[3]+0<=0)continue
       r=v[1]/v[3]; b=(r==1?"=1":r>=0.95?"0.95-1":r>=0.8?"0.80-0.95":r>=0.6?"0.60-0.80":"<0.60"); c[k" "b]++}} END{for(x in c)print x, c[x]}' "$S" | sort
```

- **Timing checks all `=1` and wires mostly `=1`:** one process corner. The min/max differences come only from slew or derating, mostly 5-20%. This is our SDF as of 2026-11-22. A further sign: the min and max runs report the same `[PIN_IO] clk_out insertion` to the picosecond.
- **Cell delays mostly `0.60-0.80` or lower, and checks differing:** a real fast corner.

For a real fast corner, ask PnR for a second SDF written from the hold/fast analysis view. Put both in `drop/` with `max` and `min` in their names, and leave `SDF=` unset in `vm_paths.sh`.

### How big are the negative delays?

`SDFCOM_NIOD` arcs run as 0 instead of slightly negative. Size them, which prints buckets only:

```bash
B=sim/pin/build/vcs_gate_sdfmax/build.log; ts=$(grep -m1 -oE 'TIMESCALE[^)]*' "$S")
for l in $(grep -A1 'Warning-\[SDFCOM_NIOD\]' "$B" | grep -oE ', [0-9]+[[:space:]]*$' | tr -dc '0-9\n' | grep .); do
  sed -n "${l}p" "$S" | awk -v l="$l" -v ts="$ts" 'BEGIN{sc=(ts~/ps/)?1:1000} {m=0; s=$0; while(match(s,/-[0-9]*\.?[0-9]+/)){v=-substr(s,RSTART,RLENGTH)*sc; if(v>m)m=v; s=substr(s,RSTART+RLENGTH)}
    print "SDF line " l ": most negative " (m<5?"under 5 ps":m<20?"5-20 ps":m<50?"20-50 ps":"OVER 50 ps")}'
done
```

On 2026-11-22 there were 2, under 5 ps and 5-20 ps: negligible against a 5 ns period, but still an open item (`ONBOARDING.md`).

---

## 8. The run options that change the rules

Each is off by default, and SUMMARY and the `TOTAL` line say when one is used:

| Option | Layer | What it changes | Sign-off? |
|---|---|---|---|
| `--recrem-as-setuphold` | simulation setup | simulates the SDF with `RECREM` written as `SETUPHOLD` (section 4) | yes: no check is loosened, the real values reach the model |
| `--cycle-slack N` | pass rule | netlist link records must match the golden in content and order, each within N cycles; console exact; per-cycle pin trace not compared; row shows `trace=MATCH(+-S)` | agreed policy, N=4 |
| `--ignore-neg-delay` | build gate | `SDFCOM_NIOD` counted, not failed | **no** |
| `--clk-mhz MHZ` with no SDC | bench timing | I/O timing derived from the clock; no output-window check | **no** (not an I/O sign-off) |
| `INITREG=0\|1\|random` (env) | initial state | registers start at a value instead of X | **no**, triage only |

The most defensible command with today's drop (one corner, no SDC, 2 tiny negative delays):

```bash
postpnr/run.sh --clk-mhz 200 --corners max --jobs 4 --recrem-as-setuphold --cycle-slack 4 --ignore-neg-delay
```

Once PnR supplies an SDC and a fast-corner SDF, and the negative delays are closed:

```bash
postpnr/run.sh --jobs 4 --recrem-as-setuphold --cycle-slack 4
```
