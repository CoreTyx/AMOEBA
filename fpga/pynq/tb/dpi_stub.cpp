// hdl/core/generic/mem/ram1p1rwbe.sv imports getenvval() to find $WALLY for
// a boot-RAM preload that no configuration here enables.  Verilator still
// emits the DPI wrapper, so the link needs a symbol.
#include <cstdlib>
extern "C" const char *getenvval(const char *name) {
    const char *v = std::getenv(name);
    return v ? v : "";
}
