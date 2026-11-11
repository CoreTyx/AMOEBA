#!/usr/bin/env bash
# deploy_forte.sh -- copy the DUT=forte bitstream, sw/ and test images to the board.
#
#   fpga/pynq/sw/deploy_forte.sh [user@host] [run-dir-or-image ...]
#   MEM_BACKEND=AXI fpga/pynq/sw/deploy_forte.sh ...      (the DDR build)
#   MEM_BACKEND=AXI DEST=forte_ddr fpga/pynq/sw/deploy_forte.sh xilinx@192.168.2.99 \
#       testcode/linux/build/boot.lst                      (SYS-04: images/boot.lst)
#
# Images are .lst files (bin/generate_memory_file.py -8), or pin-bench run
# directories, from which memory.lst is taken under the run's name.  Scripts in
# hvl/pin/tests/*.cmd always go along.
set -euo pipefail
BOARD=${1:-xilinx@192.168.2.99}
shift || true
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
BITDIR=${BITDIR:-$HERE/../bit/forte-${MEM_BACKEND:-BRAM}}
DEST=${DEST:-forte}

[[ -f $BITDIR/forte.bit && -f $BITDIR/forte.hwh ]] || { echo "no $BITDIR/forte.bit/.hwh: make -C fpga/pynq bitstream-forte"; exit 1; }

STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/images" "$STAGE/scripts"
cp "$REPO"/hvl/pin/tests/*.cmd "$REPO"/fpga/bringup/tests/*.cmd "$STAGE/scripts/"
for x in "$@"; do
  if [[ -d $x && -f $x/memory.lst ]]; then
    cp "$x/memory.lst" "$STAGE/images/$(basename "$x").lst"
  elif [[ -f $x ]]; then
    cp "$x" "$STAGE/images/"
  else
    echo "no such image or run directory: $x"; exit 1
  fi
done

ssh "$BOARD" "mkdir -p ~/$DEST"
rsync -a --delete --exclude '__pycache__' --exclude '*.pyc' --exclude runs "$HERE/" "$BOARD:$DEST/sw/"
rsync -a "$BITDIR/forte.bit" "$BITDIR/forte.hwh" "$BOARD:$DEST/"
rsync -a "$STAGE/images" "$STAGE/scripts" "$BOARD:$DEST/"
echo "deployed to $BOARD:~/$DEST ($(ls "$STAGE/images" | wc -l) images)"
echo "  ssh $BOARD 'cd $DEST/sw && sudo python3 run_cmd.py ../images/smoke.lst --bitstream ../forte.bit'"
