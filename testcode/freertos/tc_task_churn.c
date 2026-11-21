/*
 * tc_task_churn.c -- spawn and delete many short-lived tasks.
 *
 * A creator task starts batches of 8 worker tasks at a higher priority; each
 * worker computes a value, sends it through a queue and deletes itself.  The
 * idle task frees each deleted task's TCB and stack, so after every batch the
 * creator sleeps a tick and checks that the heap returned to its baseline --
 * a leak, a double free or a corrupted heap_4 free list (all of which follow
 * from a context switch that loses state at the wrong moment) shows up as a
 * drift or as the malloc-failed hook (exit 2).
 *
 * Exit codes: 0 pass, 11 wrong value, 2 heap exhausted (malloc hook), 3 stack
 * overflow (hook), 12 queue create failed, 13 heap drifted, 14 create failed,
 * 15 queue timeout.  (Old list:
 *             3 heap drifted, 4 create failed, 5 queue timeout.
 */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "test_utils_freertos.h"

#define BATCH   8
#define BATCHES 20

static QueueHandle_t g_q;

static uint64_t model(uint64_t n) {
    uint64_t v = n;
    for (int i = 0; i < 64; i++) v = v * 6364136223846793005ULL + (uint64_t)i;
    return v;
}
static void worker(void *pv) {
    uint64_t n = (uint64_t)(uintptr_t)pv, msg[2] = { n, model(n) };
    xQueueSend(g_q, msg, portMAX_DELAY);
    vTaskDelete(NULL);
}
static void creator(void *pv) {
    (void)pv;
    /* the heap before any churn: every batch must give back exactly this much */
    vTaskDelay(2);
    size_t baseline = xPortGetFreeHeapSize();
    uint64_t next = 1;
    for (int b = 0; b < BATCHES; b++) {
        uint8_t seen[BATCH] = { 0 };
        uint64_t first = next;
        for (int i = 0; i < BATCH; i++, next++)
            if (xTaskCreate(worker, "wk", configMINIMAL_STACK_SIZE, (void *)(uintptr_t)next, tskIDLE_PRIORITY + 3, NULL) != pdPASS)
                tohost_exit(14);
        for (int i = 0; i < BATCH; i++) {
            uint64_t msg[2];
            if (xQueueReceive(g_q, msg, 1000) != pdPASS) tohost_exit(15);
            if (msg[0] < first || msg[0] >= first + BATCH || msg[1] != model(msg[0])) tohost_exit(11);
            seen[msg[0] - first]++;
        }
        for (int i = 0; i < BATCH; i++) check(seen[i] == 1, 11);
        /* the idle task frees deleted tasks' TCBs and stacks; give it up to
         * 20 ticks to bring the heap back to the baseline (a leak never does) */
        int t = 0;
        while (xPortGetFreeHeapSize() != baseline && t++ < 20) vTaskDelay(1);
        if (xPortGetFreeHeapSize() != baseline) tohost_exit(13);
    }
    tohost_exit(0);
}

int app_main(void) {
    g_q = xQueueCreate(BATCH, 2 * sizeof(uint64_t));
    check(g_q != NULL, 12);
    xTaskCreate(creator, "creator", configMINIMAL_STACK_SIZE * 4, NULL, tskIDLE_PRIORITY + 2, NULL);
    vTaskSuspend(NULL);
    return 0;
}
