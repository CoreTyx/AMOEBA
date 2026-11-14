#!/bin/bash
# hvl/pin/images.sh -- build every program the pin bench runs into
# sim/pin/images/, so a machine without a RISC-V toolchain (the VCS VMs) can
# run them.  Each image is <name>.lst plus an optional <name>.cmd (a script,
# with $MEM expanding to the image).  MANIFEST lists "<name> <duts...>" per
# line in run order; vm_run.sh runs exactly what MANIFEST names, on those DUTs.
#
#   hvl/pin/images.sh            build all tiers
#   hvl/pin/images.sh pack       ... and tar them to sim/pin/images.tgz (for the VM,
#                                use hvl/pin/vm_pack.sh, which includes these)
#
# Tiers: pin directed tests, baremetal, isa_level_testing (incl. forte-only
# tcf_*), FreeRTOS.  Linux is built by testcode/linux and added when present.
#
# Environment (postpnr/prepare.sh sets these):
#   TIERS=a,b,...   which tiers, default directed,bm,isa,rtos,linux,fuzz.  Also:
#                   fi         fault-injection unit tests (fi_units, fi_rfpipe),
#                              the recorded vectors, and baremetal_ecc unarmed
#                   fi_matrix  every isa/baremetal_ecc program armed by
#                              bin/fi_arm_lst.py (0x5F, 0x6F) at fi_always.sh's
#                              three link settings -- 6 images per program
#   IMAGES_OUT=dir  where to write (default sim/pin/images)
#   PIN_RTL_ROOT    take testcode/ from this tree (the RTL a golden is made from)
#   LINUX_LST       the Linux boot image, if not at testcode/linux/build/boot.lst
#   FREERTOS_KERNEL_DIR   passed to testcode/freertos (a worktree has no submodules)
# An image may come with <name>.args: plusargs every run of it must use (the
# link knobs the fault-injection images were recorded with).
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
T="${PIN_RTL_ROOT:-$R}"
OUT="${IMAGES_OUT:-$R/sim/pin/images}"
TIERS=",${TIERS:-directed,bm,isa,rtos,linux,fuzz},"
tier() { [[ "$TIERS" == *",$1,"* ]]; }
rm -rf "$OUT"; mkdir -p "$OUT"
: > "$OUT/MANIFEST"

add() {  # $1 = name, $2 = .lst, [$3 = .cmd], [$4 = DUTs, default "rtl gate"], [$5 = plusargs]
  cp "$2" "$OUT/$1.lst"
  [ -z "${3:-}" ] || cp "$3" "$OUT/$1.cmd"
  [ -z "${5:-}" ] || echo "$5" > "$OUT/$1.args"
  echo "$1 ${4:-rtl gate}" >> "$OUT/MANIFEST"
  echo "  $1 (${4:-rtl gate})${5:+ $5}"
}

gen() {  # $1 = source; prints the .lst path
  ( cd "$R/sim" && python3 "$R/bin/generate_memory_file.py" -8 "$1" >/dev/null 2>&1 ) \
    || { echo "images.sh: cannot build $1" >&2; exit 1; }
  echo "$R/sim/bin/memory_8.lst"
}

if tier directed; then
echo "== pin directed"
add smoke     "$(gen "$R/hvl/pin/tests/smoke.c")"
add uart_echo "$(gen "$R/hvl/pin/tests/uart_echo.c")" "$R/hvl/pin/tests/uart_echo.cmd"
add irq       "$(gen "$R/hvl/pin/tests/irq.c")"       "$R/hvl/pin/tests/irq.cmd"
add uart_lsr  "$(gen "$R/hvl/pin/tests/uart_lsr.c")"  "$R/hvl/pin/tests/uart_lsr.cmd"
fi

if tier bm; then
echo "== baremetal"
for f in "$T"/testcode/baremetal/*.c; do add "bm_$(basename "${f%.c}")" "$(gen "$f")"; done
fi

if tier isa; then
echo "== isa_level_testing"
for f in "$T"/testcode/isa_level_testing/tc_*.c "$T"/testcode/isa_level_testing/tcf_*.c; do
  [ -f "$f" ] || continue
  add "isa_$(basename "${f%.c}")" "$(gen "$f")"
done
fi

if tier rtos; then
echo "== freertos"
for f in "$T"/testcode/freertos/tc_*.c; do
  n="$(basename "${f%.c}")"
  rm -f "$T/testcode/freertos/freertos_wally.elf"
  make -s -C "$T/testcode/freertos" build PROG="$f" >/dev/null 2>&1 || { echo "images.sh: freertos $n failed" >&2; exit 1; }
  add "rtos_$n" "$(gen "$T/testcode/freertos/freertos_wally.elf")"
done
fi

if tier fi; then
  # hvl/pin/fi_always.sh's unit tests and vectors, plus the ECC programs
  # unarmed (the matrix's "off" runs).
  echo "== fault injection"
  add fi_units  "$(gen "$R/hvl/pin/tests/fi_units.c")"  "$R/hvl/pin/tests/fi_units.cmd"
  add fi_rfpipe "$(gen "$R/hvl/pin/tests/fi_rfpipe.c")" "$R/hvl/pin/tests/fi_rfpipe.cmd"
  [ -f "$R/hvl/pin/tests/vectors/tc_pmp_deny_arm5f.lst" ] && \
    add fiv_tc_pmp_deny_arm5f "$R/hvl/pin/tests/vectors/tc_pmp_deny_arm5f.lst" "$R/hvl/pin/tests/fi_always.cmd" \
        "rtl gate" "+FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7"
  for f in "$T"/testcode/baremetal_ecc/tc_*.c; do
    [ -f "$f" ] || continue
    add "ecc_$(basename "${f%.c}")" "$(gen "$f")"
  done
fi

if tier fi_matrix; then
  # fi_always.sh's matrix, as images: each program armed by bin/fi_arm_lst.py
  # (fault_inject held high by tests/fi_always.cmd) at its three link settings.
  echo "== fault-injection matrix"
  KNOBS=("g30s1|+FPGA_GAP_PCT=30 +FPGA_SEED=1" "g60s3|+FPGA_GAP_PCT=60 +FPGA_SEED=3"
         "g10s4l7|+FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7")
  tmp="$(mktemp -d)"
  for f in "$T"/testcode/isa_level_testing/tc_*.c "$T"/testcode/isa_level_testing/tcf_*.c "$T"/testcode/baremetal_ecc/tc_*.c; do
    [ -f "$f" ] || continue
    b="$(basename "${f%.c}")"
    [ "$b" = tc_fault_control ] && continue        # checks FI_CONTROL is 0 after reset
    cp "$(gen "$f")" "$tmp/off.lst"
    for arm in 0x5F 0x6F; do
      python3 "$R/bin/fi_arm_lst.py" "$tmp/off.lst" "$tmp/armed.lst" "$arm" >/dev/null
      for k in "${KNOBS[@]}"; do
        IFS='|' read -r kn ka <<<"$k"
        add "fim_${b}_${arm#0x}_$kn" "$tmp/armed.lst" "$R/hvl/pin/tests/fi_always.cmd" "rtl gate" "$ka"
      done
    done
  done
  rm -rf "$tmp"
fi

LINUX_LST="${LINUX_LST:-$T/testcode/linux/build/boot.lst}"
if tier linux && [ -f "$LINUX_LST" ]; then
  # The full boot (linux.cmd, 416M cycles) is a local Verilator run; the VM
  # gets the two prefixes that fit its time budget.  One image, two scripts.
  echo "== linux"
  add linux_m0 "$LINUX_LST" "$R/hvl/pin/tests/linux_m0.cmd" "rtl gate"
  add linux_m3 "$LINUX_LST" "$R/hvl/pin/tests/linux_m3.cmd" "rtl"
fi

# Fuzz programs for the VM (docs/postsynth_fuzz_plan.md, F3): whatever
# bin/pin_fuzz.py gen wrote to FUZZ_DIR, already checked on the RTL locally.
FUZZ_DIR="${FUZZ_DIR:-$R/sim/pin/fuzz/vm}"
if tier fuzz && compgen -G "$FUZZ_DIR/fz_*.lst" >/dev/null; then
  echo "== fuzz ($FUZZ_DIR)"
  for f in "$FUZZ_DIR"/fz_*.lst; do add "$(basename "${f%.lst}")" "$f" "${f%.lst}.cmd"; done
fi

echo "$(wc -l < "$OUT/MANIFEST") images in $OUT"
if [ "${1:-}" = pack ]; then
  tar -C "$R/sim/pin" -czf "$R/sim/pin/images.tgz" images
  echo "packed: $R/sim/pin/images.tgz  (copy to the VM checkout's sim/pin/ and untar)"
fi
