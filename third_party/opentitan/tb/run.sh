#!/bin/bash
# Standalone check of the vendored async FIFO at the width, depth and NON-INTEGER
# clock ratio the link uses.  Run this after re-vendoring prim_fifo_async.sv.
set -euo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
cd "$OUT"
verilator --binary -j 4 --timing --timescale 1ns/1ps -Wall \
  +define+ECE411_VERILATOR +incdir+"$R" \
  "$R/prim_flop_2sync.sv" "$R/prim_fifo_async.sv" "$R/tb/tb_prim_fifo_async.sv" \
  --top-module tb_prim_fifo_async -o fifotb
./obj_dir/fifotb
