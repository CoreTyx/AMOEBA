#!/bin/bash
# hvl/pin/vm_pack.sh -- everything the VCS VM needs, as one file to copy.
#
#   hvl/pin/vm_pack.sh           rebuild the program images, then write sim/pin/vm_bundle.tgz
#   SKIP_IMAGES=1 hvl/pin/vm_pack.sh   reuse sim/pin/images as they are
#   hvl/pin/vm_pack.sh --list    print the paths that go in the bundle, and stop
#
# Run it on a machine with the repository and a RISC-V toolchain.  On the VM:
#   tar -xzf vm_bundle.tgz -C <checkout dir>     (overwrites bench and RTL files)
#   hvl/pin/vm_run.sh                            (preflight checks every file)
#
# The VM has no git, so the bundle carries its own identity and integrity:
#   VM_BUNDLE          when and from what it was packed (shown in SUMMARY)
#   VM_FILES.sha256    a checksum per file; vm_run.sh preflight refuses to run
#                      if any file is missing or differs, so a partial copy or
#                      a stale file cannot go unnoticed.
# hvl/pin/vm_paths.sh, the VM's own netlist and library paths, is never in the
# bundle, so unpacking a new one does not overwrite it.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$R"

# What the VM runs: the bench and its scripts, the trace comparison, and every
# RTL source pin.sh compiles for DUT=rtl/rtl_sva (all of hdl/core, the forte_*
# top, the config package, the CDC primitives in hdl/), plus the images.
PATHS=(hvl/pin bin/pin_trace_cmp.py bin/vcd_first_x.py docs/postsynth_vm_runbook.md
       hdl/core pkg hdl/prim_assert.sv hdl/prim_fifo_async.sv hdl/prim_flop_2sync.sv)
mapfile -t FORTE < <(ls hdl/forte_*.sv)
PATHS+=("${FORTE[@]}")

if [ "${1:-}" = --list ]; then printf '%s\n' "${PATHS[@]}" sim/pin/images; exit 0; fi

[ -n "${SKIP_IMAGES:-}" ] || hvl/pin/images.sh
[ -f sim/pin/images/MANIFEST ] || { echo "vm_pack.sh: no sim/pin/images/MANIFEST"; exit 1; }

STAGE="$R/sim/pin/vm_pack.stage"
rm -rf "$STAGE"; mkdir -p "$STAGE"
# Copy, leaving out the VM's own paths file and any local editor or build debris.
tar -cf - --exclude='hvl/pin/vm_paths.sh' --exclude='*.swp' --exclude='__pycache__' \
    "${PATHS[@]}" sim/pin/images | tar -xf - -C "$STAGE"

{
  echo "packed:  $(date '+%F %T') on $(hostname)"
  if command -v git >/dev/null && git rev-parse --git-dir >/dev/null 2>&1; then
    echo "commit:  $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)$(git status --porcelain -- "${PATHS[@]}" | grep -q . && echo ' + uncommitted changes')"
  fi
  echo "images:  $(wc -l < sim/pin/images/MANIFEST)"
} > "$STAGE/VM_BUNDLE"
( cd "$STAGE" && find . -type f ! -name VM_FILES.sha256 | sed 's|^\./||' | sort | xargs -d '\n' sha256sum ) \
  > "$STAGE/VM_FILES.sha256"

tar -C "$STAGE" -czf "$R/sim/pin/vm_bundle.tgz" .
rm -rf "$STAGE"
echo "wrote sim/pin/vm_bundle.tgz ($(du -h sim/pin/vm_bundle.tgz | cut -f1), $(wc -l < <(tar -tzf sim/pin/vm_bundle.tgz | grep -v '/$')) files)"
cat <<'EOF'
on the VM:  tar -xzf vm_bundle.tgz -C <checkout dir>  &&  hvl/pin/vm_run.sh
EOF
