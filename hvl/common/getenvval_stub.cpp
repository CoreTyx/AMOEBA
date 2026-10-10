// hdl/core/generic/mem/ram1p1rwe.sv (and rom1p1r.sv) declare a Verilator-only DPI-C import,
// `getenvval`, used only by an optional PRELOAD_ENABLED simulation-preload path that no config in
// this repo actually enables. No C++ implementation of it exists anywhere else in the repo.
//
// The production top_tb build (sim/Makefile, -O3) apparently gets away with this because
// Verilator's optimizer prunes the dead `if (PRELOAD_ENABLED) ... getenvval() ...` branch before
// ever emitting a C++ symbol reference for it. Smaller, standalone testbenches built at -O2 (this
// repo's existing ecc_secded_dected_test/ft_shadow_test targets, and the new cache_integration_test
// target) that pull in ram1p1rwe.sv apparently don't get the same pruning and fail to link with
// "undefined reference to `getenvval'" without this file.
//
// This is a minimal, correct implementation (not a stub in the sense of "fake data") -- it just
// wasn't checked in anywhere. Link it into any standalone Verilator target that hits the same error.
#include <cstdlib>

extern "C" const char* getenvval(const char* env_name) {
  const char* v = std::getenv(env_name);
  return v ? v : "";
}
