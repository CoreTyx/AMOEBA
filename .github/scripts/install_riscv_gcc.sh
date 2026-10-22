#!/usr/bin/env bash
#=============================================================================
# Install the RISC-V cross compiler every CI job that builds test code uses.
#
# bin/toolchain.py requires riscv64 Linux gcc 14.2.0.  On EWS that is the
# riscv64-unknown-linux-gnu-gcc ece411.sh puts on PATH; here it is Ubuntu 24.04's
# gcc-14 cross package, the same GCC release.
#
# Ubuntu names the compiler riscv64-linux-gnu-gcc-14.  toolchain.py looks for
# riscv64-linux-gnu-gcc and uses one directory for every tool, so each
# riscv64-linux-gnu-* tool gets an unversioned link in one directory on PATH.
#
# Also works on an Ubuntu 24.04 machine outside CI: without RUNNER_TEMP the
# links go in ~/.local/riscv-gcc/bin, and without GITHUB_PATH it prints the PATH
# line to add.
#=============================================================================
set -euo pipefail

GCC_VERSION=14.2.0

# In CI the downloaded packages are kept in DEBS, which the workflows cache
# (actions/cache, keyed on this script), so jobs install from the cache instead
# of downloading the compiler again.
APT_CACHE=()
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  DEBS="$HOME/.cache/riscv-gcc-debs"
  mkdir -p "$DEBS/partial"
  sudo chown _apt "$DEBS/partial"
  APT_CACHE=(-o Dir::Cache::Archives="$DEBS" -o APT::Keep-Downloaded-Packages=true)
fi
sudo apt-get install -y --no-install-recommends "${APT_CACHE[@]}" \
  gcc-14-riscv64-linux-gnu binutils-riscv64-linux-gnu
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  sudo chown -R "$(id -u):$(id -g)" "$DEBS"
fi

BIN="${RUNNER_TEMP:-$HOME/.local}/riscv-gcc/bin"
mkdir -p "$BIN"
for tool in /usr/bin/riscv64-linux-gnu-*; do
  name=$(basename "$tool")
  ln -sf "$tool" "$BIN/${name%-14}"
done
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$BIN" >> "$GITHUB_PATH"
else
  echo "Add to your shell profile:  export PATH=\"$BIN:\$PATH\""
fi

found=$("$BIN/riscv64-linux-gnu-gcc" -dumpfullversion)
if [ "$found" != "$GCC_VERSION" ]; then
  echo "::error::riscv64-linux-gnu-gcc is $found, not $GCC_VERSION; bin/toolchain.py will refuse it"
  exit 1
fi
PATH="$BIN:$PATH" python3 bin/toolchain.py
