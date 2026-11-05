/* hvl/pin/tests/smoke.c -- smallest end-to-end program: compute, check, exit 0. */
int main(void) {
    volatile long acc = 0;
    for (int i = 0; i < 100; i++) acc += i * i;
    return acc == 328350 ? 0 : 1;
}
