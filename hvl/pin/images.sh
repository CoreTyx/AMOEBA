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
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$R/sim/pin/images"
rm -rf "$OUT"; mkdir -p "$OUT"
: > "$OUT/MANIFEST"

add() {  # $1 = name, $2 = .lst, [$3 = .cmd], [$4 = DUTs, default "rtl gate"]
  cp "$2" "$OUT/$1.lst"
  [ -z "${3:-}" ] || cp "$3" "$OUT/$1.cmd"
  echo "$1 ${4:-rtl gate}" >> "$OUT/MANIFEST"
  echo "  $1 (${4:-rtl gate})"
}

gen() {  # $1 = source; prints the .lst path
  ( cd "$R/sim" && python3 "$R/bin/generate_memory_file.py" -8 "$1" >/dev/null 2>&1 ) \
    || { echo "images.sh: cannot build $1" >&2; exit 1; }
  echo "$R/sim/bin/memory_8.lst"
}

echo "== pin directed"
add smoke     "$(gen "$R/hvl/pin/tests/smoke.c")"
add uart_echo "$(gen "$R/hvl/pin/tests/uart_echo.c")" "$R/hvl/pin/tests/uart_echo.cmd"
add irq       "$(gen "$R/hvl/pin/tests/irq.c")"       "$R/hvl/pin/tests/irq.cmd"
add uart_lsr  "$(gen "$R/hvl/pin/tests/uart_lsr.c")"  "$R/hvl/pin/tests/uart_lsr.cmd"

echo "== baremetal"
for f in "$R"/testcode/baremetal/*.c; do add "bm_$(basename "${f%.c}")" "$(gen "$f")"; done

echo "== isa_level_testing"
for f in "$R"/testcode/isa_level_testing/tc_*.c "$R"/testcode/isa_level_testing/tcf_*.c; do
  [ -f "$f" ] || continue
  add "isa_$(basename "${f%.c}")" "$(gen "$f")"
done

echo "== freertos"
for f in "$R"/testcode/freertos/tc_*.c; do
  n="$(basename "${f%.c}")"
  rm -f "$R/testcode/freertos/freertos_wally.elf"
  make -s -C "$R/testcode/freertos" build PROG="$f" >/dev/null 2>&1 || { echo "images.sh: freertos $n failed" >&2; exit 1; }
  add "rtos_$n" "$(gen "$R/testcode/freertos/freertos_wally.elf")"
done

if [ -f "$R/testcode/linux/build/boot.lst" ]; then
  # The full boot (linux.cmd, 416M cycles) is a local Verilator run; the VM
  # gets the two prefixes that fit its time budget.  One image, two scripts.
  echo "== linux"
  add linux_m0 "$R/testcode/linux/build/boot.lst" "$R/hvl/pin/tests/linux_m0.cmd" "rtl gate"
  add linux_m3 "$R/testcode/linux/build/boot.lst" "$R/hvl/pin/tests/linux_m3.cmd" "rtl"
fi

echo "$(wc -l < "$OUT/MANIFEST") images in $OUT"
if [ "${1:-}" = pack ]; then
  tar -C "$R/sim/pin" -czf "$R/sim/pin/images.tgz" images
  echo "packed: $R/sim/pin/images.tgz  (copy to the VM checkout's sim/pin/ and untar)"
fi
