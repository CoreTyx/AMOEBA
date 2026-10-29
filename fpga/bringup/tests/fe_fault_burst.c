// fe_fault_burst.c -- fe_fault_pin.c for a patterned fault_inject pin
// (fe_fault_burst.cmd, fe_fault_off.cmd): a round no longer needs its detect
// counter to rise, since the pin may let few or no faults through.
#define FI_PIN_PATTERNED
#include "fe_fault_pin.c"
