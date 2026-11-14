#!/bin/bash
# postpnr/prepare.sh -- the golden half of post-PnR verification (local: needs the
# RISC-V toolchain and Verilator; the TSMC VM has neither).
#
#   postpnr/prepare.sh [options]
#
#   --rtl-ref REF      the commit the netlist was made from (default: RTL_REF in
#                      $PNR_DIR/pnr.env, else origin/main)
#   --tiers LIST       comma list (default directed,bm,isa,rtos,fi,linux,fuzz);
#                      fi_matrix adds 6 armed runs per isa/ecc program
#   --fuzz N           Cascade programs to generate (default 300; 0 = none)
#   --seed S           Cascade seed (default 201)
#   --jobs J           parallel simulations and generators (default 8)
#   --linux-lst PATH   Linux boot image (default testcode/linux/build/boot.lst
#                      in the RTL tree); without one linux_m0 is skipped
#   --drop-failing     leave an image that fails on the golden RTL out of the
#                      golden (named in GOLDEN) instead of stopping
#   --reuse-images     keep golden/<sha>/images as they are (rerun traces only)
#
# Writes postpnr/golden/<sha12>/:
#   GOLDEN         what this is: RTL commit, bench commit, tools, tiers, seeds
#   rtl/           hdl/ and pkg/ at that commit (what the VM's DUT=rtl compiles)
#   images/        MANIFEST, <name>.lst [.cmd] [.args] -- every program, prebuilt
#   traces/<name>/ pin_cycle.log.gz, pin_trace.log, uart.log, RESULT, sim.log.gz:
#                  the golden RTL run (Verilator DUT=rtl, this checkout's bench)
#
# The golden is made at the bench's default clock and I/O timing.  The traces
# count cycles from reset release and sample inputs at the clock edge, so they
# do not depend on the period or the I/O delays (postpnr/selfcheck.sh proves it):
# one golden serves every SDC and both corners.
#
# Every golden run must pass.  A failing golden is not a golden: the script
# stops (or, with --drop-failing, removes that image and says so).
#
# Then: postpnr/pack.sh, copy the bundle to the VM, postpnr/run.sh there.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$R"
die() { echo "prepare.sh: $*" >&2; exit 1; }

REF="" TIERS="directed,bm,isa,rtos,fi,linux,fuzz" FUZZ=300 SEED=201 JOBS=8 LINUX="" DROP=0 REUSE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --rtl-ref) REF="$2"; shift;;
    --tiers) TIERS="$2"; shift;;
    --fuzz) FUZZ="$2"; shift;;
    --seed) SEED="$2"; shift;;
    --jobs) JOBS="$2"; shift;;
    --linux-lst) LINUX="$2"; shift;;
    --drop-failing) DROP=1;;
    --reuse-images) REUSE=1;;
    -h|--help) sed -n '2,/^set -euo/{/^set -euo/d;p}' "$0"; exit 0;;
    *) die "unknown option $1 (--help)";;
  esac
  shift
done

if [ -z "$REF" ] && [ -n "${PNR_DIR:-}" ] && [ -f "$PNR_DIR/pnr.env" ]; then
  REF="$(bash -c 'source "$1" >/dev/null 2>&1; echo "${RTL_REF:-}"' _ "$PNR_DIR/pnr.env")"
fi
REF="${REF:-origin/main}"
SHA="$(git rev-parse --verify "$REF^{commit}" 2>/dev/null)" || die "no such commit: $REF (git fetch?)"
S12="${SHA:0:12}"
G="$R/postpnr/golden/$S12"
W="$R/postpnr/work"
mkdir -p "$G" "$W"
echo "prepare: golden RTL $REF = $SHA -> $G"

# ---- the RTL tree ---------------------------------------------------------------
# This checkout when its hdl/, pkg/ and testcode/ are exactly that commit's;
# otherwise a detached worktree of it.  The BENCH (hvl/pin, bin/) is always this
# checkout's.
if git diff --quiet "$SHA" -- hdl pkg testcode && [ -z "$(git status --porcelain -- hdl pkg)" ]; then
  RTL="$R"
else
  RTL="$W/rtl_$S12"
  if [ ! -d "$RTL" ]; then git worktree add -q --detach "$RTL" "$SHA"; fi
  [ "$(git -C "$RTL" rev-parse HEAD)" = "$SHA" ] || die "$RTL is not at $SHA"
fi
echo "prepare: RTL tree $RTL"
rm -rf "$G/rtl"; mkdir -p "$G/rtl"
git archive "$SHA" hdl pkg | tar -x -C "$G/rtl"

# FreeRTOS needs its kernel submodule, which a worktree lacks: borrow any
# checkout's that has one.
if [[ ",$TIERS," == *,rtos,* ]] && [ -z "${FREERTOS_KERNEL_DIR:-}" ]; then
  for d in "$RTL" "$R" "$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"; do
    [ -f "$d/third_party/FreeRTOS-Kernel/tasks.c" ] && { export FREERTOS_KERNEL_DIR="$d/third_party/FreeRTOS-Kernel"; break; }
  done
  [ -n "${FREERTOS_KERNEL_DIR:-}" ] || die "rtos tier: no FreeRTOS-Kernel checkout (git submodule update --init third_party/FreeRTOS-Kernel, or set FREERTOS_KERNEL_DIR)"
fi

# ---- images ---------------------------------------------------------------------------
if [ $REUSE = 1 ] && [ -f "$G/images/MANIFEST" ]; then
  echo "prepare: reusing $(wc -l < "$G/images/MANIFEST") images"
else
  if [[ ",$TIERS," == *,fuzz,* ]] && [ "$FUZZ" -gt 0 ]; then
    [ -d "$R/third_party/cascade/.git" ] || hvl/pin/fuzz/get_cascade.sh
    rm -rf "$G/fuzz"
    echo "prepare: generating $FUZZ Cascade programs, seed $SEED"
    python3 bin/pin_fuzz.py gen "$FUZZ" --seed "$SEED" --out "$G/fuzz" --jobs "$JOBS" > "$W/fuzz_gen.log" 2>&1 \
      || { tail -20 "$W/fuzz_gen.log"; die "pin_fuzz.py gen failed (log $W/fuzz_gen.log)"; }
    echo "prepare: $(ls "$G"/fuzz/fz_*.lst | wc -l) fuzz programs"
  fi
  [ -n "$LINUX" ] && { [ -f "$LINUX" ] || die "--linux-lst: no such file $LINUX"; export LINUX_LST="$LINUX"; }
  if [[ ",$TIERS," == *,linux,* ]] && [ ! -f "${LINUX_LST:-$RTL/testcode/linux/build/boot.lst}" ]; then
    echo "prepare: WARNING no Linux image (make -C testcode/linux, or --linux-lst): linux_m0 skipped"
  fi
  # images.sh shares sim/bin/memory_8.lst in the tree it runs from: one at a time.
  TIERS="$TIERS" IMAGES_OUT="$G/images" PIN_RTL_ROOT="$RTL" FUZZ_DIR="$G/fuzz" \
    hvl/pin/images.sh > "$W/images.log" 2>&1 || { tail -20 "$W/images.log"; die "images.sh failed (log $W/images.log)"; }
  echo "prepare: $(wc -l < "$G/images/MANIFEST") images"
fi

# ---- golden runs --------------------------------------------------------------------------
export PIN_RTL_ROOT="$G/rtl" PIN_BUILD="$W/build_verilator_$S12" PIN_RUNS="$G/traces"
SIM=verilator DUT=rtl hvl/pin/pin.sh build > "$W/build.log" 2>&1 \
  || { tail -30 "$W/build.log"; die "Verilator build failed (log $W/build.log)"; }
rm -rf "$G/traces"; mkdir -p "$G/traces"

# Only images that run on the netlist need a golden.
awk '$0 ~ / gate( |$)/ {print $1}' "$G/images/MANIFEST" > "$W/golden.list"
echo "prepare: $(wc -l < "$W/golden.list") golden runs, $JOBS at a time"
export G
one() {   # one image: run it, keep the evidence small
  local n="$1" a=() cmd=""
  [ -f "$G/images/$n.cmd" ] && cmd="$G/images/$n.cmd"
  [ -f "$G/images/$n.args" ] && read -r -a a < "$G/images/$n.args"
  SIM=verilator DUT=rtl hvl/pin/pin.sh run "$G/images/$n.lst" ${cmd:+"$cmd"} \
      +TIMEOUT=10000000 +UART_QUIET ${a[@]+"${a[@]}"} > /dev/null 2>&1 || true
  rm -f "$G/traces/$n/memory.lst" "$G/traces/$n/script.cmd"
  [ -f "$G/traces/$n/sim.log" ] && gzip -f "$G/traces/$n/sim.log"
  printf '%-44s %s\n' "$n" "$(cat "$G/traces/$n/RESULT" 2>/dev/null || echo 'PIN_TB_RESULT: FAIL no RESULT')"
}
export -f one
xargs -a "$W/golden.list" -P "$JOBS" -I{} bash -c 'one "$@"' _ {} | tee "$W/golden.results"

fails="$(grep -v 'PIN_TB_RESULT: PASS' "$W/golden.results" | awk '{print $1}' || true)"
dropped=""
if [ -n "$fails" ]; then
  if [ $DROP = 1 ]; then
    for n in $fails; do
      sed -i "/^$n /d" "$G/images/MANIFEST"
      rm -f "$G/images/$n".{lst,cmd,args}
      dropped="$dropped $n"
    done
    echo "prepare: WARNING dropped $(wc -w <<<"$fails") image(s) that fail on the golden RTL:$dropped"
  else
    echo "prepare: FAILED on the golden RTL (no golden written):"
    grep -v 'PIN_TB_RESULT: PASS' "$W/golden.results" | sed 's/^/  /'
    rm -f "$G/GOLDEN"
    exit 1
  fi
fi

{
  echo "rtl_ref:    $REF"
  echo "rtl_sha:    $SHA"
  echo "bench_sha:  $(git rev-parse HEAD)$(git status --porcelain -- hvl/pin bin postpnr | grep -q . && echo ' + uncommitted changes')"
  echo "made:       $(date '+%F %T') on $(hostname)"
  echo "simulator:  $(verilator --version 2>/dev/null | head -1)"
  echo "toolchain:  $(riscv64-unknown-elf-gcc --version 2>/dev/null | head -1)"
  echo "tiers:      $TIERS"
  echo "fuzz:       $( [[ ",$TIERS," == *,fuzz,* ]] && echo "$FUZZ programs, seed $SEED" || echo none)"
  echo "images:     $(wc -l < "$G/images/MANIFEST") ($(awk '$0 ~ / gate( |$)/' "$G/images/MANIFEST" | wc -l) with a golden trace)"
  echo "dropped:    ${dropped:- none}"
} > "$G/GOLDEN"
echo "prepare: golden ready: $G"
cat "$G/GOLDEN"
echo "next: postpnr/pack.sh $S12"
