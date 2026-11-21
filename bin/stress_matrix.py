#!/usr/bin/env python3
"""
stress_matrix.py -- turn the `// @stress` headers of testcode/stress into the
GitHub Actions matrix for one CI tier.

Header syntax (first lines of each test; key=value, space separated):

    // @stress tier=pr seeds=2 nightly_seeds=8 weekly_seeds=32 build=no_spike
    //         duts=legacy,forte timeout=20000000 expect=pass pin=yes ecc=yes dummy=yes
    // @stress-variant build=no_spike duts=forte

  tier            lowest tier the test runs in: pr < nightly < weekly
  seeds           seeds per DUT in the pr tier (default 1)
  nightly_seeds   seeds per DUT nightly (default max(4, seeds))
  weekly_seeds    seeds per DUT weekly (default 2 * nightly_seeds)
  build           spike (Spike lock-step co-sim, -DCOSIM) | no_spike (RVFI only)
  duts            DUTs to run on (legacy = rv64_core_wrapper, forte = ASIC top)
  timeout         cycle budget per run
  expect          pass | fail (harness self-checks must FAIL)
  ecc / dummy     nightly+ variants: also run on the ECC-injection build /
                  with random dummy-instruction insertion (default yes for
                  no_spike pass tests; set =no to opt out)
  pin             nightly: also run on the chip-level pin bench (default yes)
  @stress-variant an extra configuration with overrides (e.g. a co-sim test's
                  forte run without Spike)

Each matrix entry is one CI job running a list of seeds sequentially, so the
matrix stays under GitHub's 256-entry limit and each job under the 6 h cap.

    python3 bin/stress_matrix.py --tier pr            # JSON {"include": [...]}
    python3 bin/stress_matrix.py --tier nightly --pin # pin-bench matrix
    python3 bin/stress_matrix.py --tier pr --list     # human-readable
    python3 bin/stress_matrix.py --check              # validate every header
"""
import argparse
import glob
import json
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.join(REPO, "testcode", "stress")
TIERS = ["pr", "nightly", "weekly"]
KNOWN = {"tier", "seeds", "nightly_seeds", "weekly_seeds", "build", "duts", "timeout",
         "expect", "ecc", "dummy", "pin", "xfail"}
CHUNK = {"pr": 2, "nightly": 8, "weekly": 16}
SCALE = {"pr": 1, "nightly": 2, "weekly": 4}
MAX_ENTRIES = 256


def parse(path):
    base, variants = None, []
    with open(path) as f:
        for line in f:
            m = re.match(r"\s*//\s*@stress(-variant)?\s+(.*)$", line)
            if not m:
                if base is not None and not line.startswith("//"):
                    break
                continue
            kv = dict(tok.split("=", 1) for tok in m.group(2).split() if "=" in tok)
            bad = set(kv) - KNOWN
            if bad:
                raise SystemExit(f"{path}: unknown @stress key(s) {sorted(bad)}")
            if m.group(1):
                variants.append(kv)
            else:
                base = kv
    return base, variants


def tests():
    out = []
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.c"), recursive=True)):
        if os.sep + "lib" + os.sep in path:
            continue
        base, variants = parse(path)
        if base is None:
            continue
        out.append((path, base, variants))
    return out


def seeds_for(cfg, tier):
    pr = int(cfg.get("seeds", 1))
    nightly = int(cfg.get("nightly_seeds", max(4, pr)))
    weekly = int(cfg.get("weekly_seeds", 2 * nightly))
    return {"pr": pr, "nightly": nightly, "weekly": weekly}[tier]


def chunks(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i + n]


def entries(tier, pin=False):
    out = []
    ti = TIERS.index(tier)
    for path, base, variants in tests():
        rel = os.path.relpath(path, REPO)
        name = os.path.splitext(os.path.basename(path))[0]
        if TIERS.index(base.get("tier", "pr")) > ti:
            continue
        expect = base.get("expect", "pass")
        configs = []
        for i, cfg in enumerate([base] + variants):
            merged = dict(base)
            merged.update(cfg)
            configs.append((i, merged))
        for vi, cfg in configs:
            build = cfg.get("build", "no_spike")
            duts = cfg.get("duts", "legacy").split(",")
            if vi > 0 and tier == "pr":
                # PR: variants only contribute DUTs the base config lacks, 1 seed
                pass
            for dut in duts:
                if pin:
                    continue
                n = seeds_for(cfg, tier)
                if tier == "pr" and dut != "legacy":
                    n = 1                     # forte (link model) is slower: one seed per PR
                if vi > 0 and tier == "pr":
                    n = 1
                seeds = list(range(1, n + 1))
                link_args = ""
                if dut == "forte" and tier != "pr":
                    link_args = "rand"        # +LINK_GAPS=1 +LINK_SEED=<seed> per run
                for part, chunk in enumerate(chunks(seeds, CHUNK[tier])):
                    out.append(dict(
                        name=name, path=rel, build=build, dut=dut,
                        seeds=" ".join(map(str, chunk)), timeout=int(cfg.get("timeout", 10000000)),
                        expect=expect, scale=SCALE[tier], link_args=link_args, variant="",
                        xfail=cfg.get("xfail", ""),
                        id=f"{name}-{dut}-{build}-{chunk[0]}"))
            # nightly+ variants on the legacy no-spike build
            if tier != "pr" and vi == 0 and expect == "pass" and not pin:
                n = max(2, seeds_for(cfg, tier) // 4)
                for var in ("ecc", "dummy"):
                    if cfg.get(var, "yes") != "yes":
                        continue
                    out.append(dict(
                        name=name, path=rel, build="ecc" if var == "ecc" else "no_spike", dut="legacy",
                        seeds=" ".join(map(str, range(101, 101 + n))), timeout=2 * int(cfg.get("timeout", 10000000)),
                        expect="pass", scale=1, link_args="", variant=var, xfail=cfg.get("xfail", ""),
                        id=f"{name}-{var}"))
        if pin and tier != "pr" and expect == "pass" and base.get("pin", "yes") == "yes":
            n = 2 if tier == "nightly" else 4
            out.append(dict(name=name, path=rel, seeds=" ".join(map(str, range(1, n + 1))),
                            timeout=int(base.get("timeout", 10000000)), id=f"pin-{name}"))
    return out


# Simulator builds: (build, dut) -> verilator dir under sim/verilator, make
# target, cache-key prefix.  The keys match ci.yml's where the build is the
# same, so a commit's binaries are compiled once across both workflows.
BUILDS = {
    ("no_spike", "legacy"): ("build_no_spike", "build_isa_tests", "no-spike-build"),
    ("no_spike", "forte"):  ("build_no_spike_forte", "build_isa_tests DUT=forte", "stress-no-spike-forte-build"),
    ("spike", "legacy"):    ("build", "verilator/build/Vtop_tb", "spike-build"),
    ("ecc", "legacy"):      ("build_ecc_inject", "verilator/build_ecc_inject/Vtop_tb", "ecc-inject-build"),
}


def builds_for(tier):
    need = sorted({(e["build"], e["dut"]) for e in entries(tier)})
    out = []
    for b, d in need:
        if (b, d) not in BUILDS:
            raise SystemExit(f"no simulator build for build={b} dut={d}")
        dir_, target, key = BUILDS[(b, d)]
        out.append(dict(build=b, dut=d, dir=dir_, target=target, key=key, spike="true" if b == "spike" else "false"))
    return out


def main():
    if len(sys.argv) == 4 and sys.argv[1] == "--build-info":
        dir_, target, key = BUILDS[(sys.argv[2], sys.argv[3])]
        print(f"dir={dir_}\ntarget={target}\nkey={key}\nspike={'true' if sys.argv[2] == 'spike' else 'false'}")
        return 0
    if len(sys.argv) == 3 and sys.argv[1] == "--builds":
        print(json.dumps({"include": builds_for(sys.argv[2])}, separators=(",", ":")))
        return 0
    ap = argparse.ArgumentParser()
    ap.add_argument("--tier", choices=TIERS, default="pr")
    ap.add_argument("--pin", action="store_true", help="pin-bench matrix (nightly/weekly)")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args()
    if a.check:
        n = 0
        for path, base, variants in tests():
            for cfg in [base] + variants:
                if cfg.get("build", "no_spike") not in ("spike", "no_spike"):
                    raise SystemExit(f"{path}: build must be spike or no_spike")
                for d in cfg.get("duts", "legacy").split(","):
                    if d not in ("legacy", "forte"):
                        raise SystemExit(f"{path}: unknown dut {d}")
            if base.get("tier", "pr") not in TIERS:
                raise SystemExit(f"{path}: unknown tier")
            n += 1
        for t in TIERS:
            for p in (False, True):
                e = entries(t, p)
                if len(e) > MAX_ENTRIES:
                    raise SystemExit(f"tier {t} pin={p}: {len(e)} matrix entries > {MAX_ENTRIES}")
        print(f"{n} stress tests, headers OK; matrix sizes: " +
              ", ".join(f"{t}={len(entries(t))}/{len(entries(t, True))}pin" for t in TIERS))
        return 0
    e = entries(a.tier, a.pin)
    if a.list:
        for x in e:
            print(f"{x['id']:50s} seeds=[{x['seeds']}] timeout={x['timeout']}")
        print(f"{len(e)} entries")
        return 0
    if len(e) > MAX_ENTRIES:
        raise SystemExit(f"{len(e)} matrix entries > {MAX_ENTRIES}")
    print(json.dumps({"include": e}, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    sys.exit(main())
