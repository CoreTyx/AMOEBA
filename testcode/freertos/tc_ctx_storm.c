// @freertos-cflags -DconfigTOTAL_HEAP_SIZE=163840
/*
 * tc_ctx_storm.c -- context-switch storm under a fast tick.
 *
 * Tick at 10 kHz (a faster tick leaves this core no time between ISRs) with 12 equal-priority
 * worker tasks that yield every few iterations and sleep a tick now and
 * then, so the kernel switches context thousands of times: on the tick
 * interrupt (preemption + time slicing), on taskYIELD (ecall path) and on
 * vTaskDelay.  Each worker keeps its running state in many live registers and
 * on its stack; a monitor at the top priority checks that nobody starves and,
 * at the end, that every worker's value equals the model for the number of
 * iterations it completed -- a register or stack word corrupted by any of
 * those switches makes the values diverge.
 *
 * Exit codes: 0 pass, 10+i worker i starved, 30+i worker i diverged,
 *             50 too few context switches observed.
 */
#include "FreeRTOS.h"
#include "task.h"
#include "test_utils_freertos.h"

#define NW      12
#define ROUNDS  8

typedef struct { volatile uint64_t iter, v, a, b, c, d; } wstate_t;
static wstate_t g_w[NW];
static volatile int g_stop;
static volatile uint64_t g_yields;

static inline uint64_t step(uint64_t v, uint64_t i, uint64_t k) {
    return (v ^ (v >> 17)) * 0x9E3779B97F4A7C15ULL + i * (2 * k + 1);
}

static void worker(void *pv) {
    uint64_t k = (uint64_t)(uintptr_t)pv;
    /* plenty of live state across every switch */
    uint64_t v = k, a = k * 3, b = k * 5, c = k * 7, d = k * 11, i = 0;
    volatile uint64_t stackbuf[16];
    for (int j = 0; j < 16; j++) stackbuf[j] = k * 100 + (uint64_t)j;
    while (!g_stop) {
        v = step(v, i, k); a += v; b ^= a; c += b >> 3; d = d * 31 + c;
        i++;
        g_w[k].iter = i; g_w[k].v = v; g_w[k].a = a; g_w[k].b = b; g_w[k].c = c; g_w[k].d = d;
        for (int j = 0; j < 16; j++) if (stackbuf[j] != k * 100 + (uint64_t)j) tohost_exit(70 + k);
        if ((i % 5) == 0) { g_yields++; taskYIELD(); }
        if ((i % 37) == 0) vTaskDelay(1);
    }
    vTaskSuspend(NULL);
}

static void monitor(void *pv) {
    (void)pv;
    uint64_t last[NW] = { 0 };
    for (int r = 0; r < ROUNDS; r++) {
        vTaskDelay(40);          /* several full rotations of 12 workers */
        for (int k = 0; k < NW; k++) {
            if (r > 2 && g_w[k].iter == last[k]) tohost_exit(10 + k);
            last[k] = g_w[k].iter;
        }
    }
    g_stop = 1;
    vTaskDelay(20);                                /* every worker parks */
    for (int k = 0; k < NW; k++) {
        uint64_t v = (uint64_t)k, a = (uint64_t)k * 3, b = (uint64_t)k * 5, c = (uint64_t)k * 7, d = (uint64_t)k * 11;
        for (uint64_t i = 0; i < g_w[k].iter; i++) { v = step(v, i, (uint64_t)k); a += v; b ^= a; c += b >> 3; d = d * 31 + c; }
        if (v != g_w[k].v || a != g_w[k].a || b != g_w[k].b || c != g_w[k].c || d != g_w[k].d) tohost_exit(30 + k);
    }
    if (g_yields < 100) tohost_exit(50);
    tohost_exit(0);
}

int app_main(void) {
    vTaskPrioritySet(NULL, configMAX_PRIORITIES - 1);
    for (int k = 0; k < NW; k++)
        /* one priority for all workers: with strict priorities, workers that
         * compute longer than they sleep would (legitimately) starve the lower
         * ones; at equal priority every tick and every yield must rotate them */
        xTaskCreate(worker, "w", configMINIMAL_STACK_SIZE * 2, (void *)(uintptr_t)k, tskIDLE_PRIORITY + 1, NULL);
    xTaskCreate(monitor, "mon", configMINIMAL_STACK_SIZE * 4, NULL, configMAX_PRIORITIES - 1, NULL);
    vTaskSuspend(NULL);
    return 0;
}
