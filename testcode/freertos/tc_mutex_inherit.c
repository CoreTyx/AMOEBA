/*
 * tc_mutex_inherit.c -- priority inheritance (the Mars Pathfinder case).
 *
 * LOW (prio 1) takes a mutex; HIGH (prio 3) blocks on it; MEDIUM (prio 2)
 * spins.  With inheritance LOW runs at HIGH's priority until it gives the
 * mutex, so MEDIUM cannot run in between; then LOW drops back and HIGH gets
 * the mutex.  Checked: LOW's priority while boosted and after, that MEDIUM did
 * not run while LOW was boosted, and the order of events.  Repeated 20 times.
 *
 * Exit codes: 0 pass, 1 not boosted, 2 not restored, 3 medium ran during
 * the inversion window, 4 wrong order, 5 timeout.
 */
#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "test_utils_freertos.h"

static SemaphoreHandle_t g_mx;
static TaskHandle_t g_low, g_high, g_med;
static volatile uint64_t g_med_count;
static volatile int g_phase, g_round;

static void medium(void *pv) { (void)pv; for (;;) g_med_count++; }

static void high(void *pv) {
    (void)pv;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);   /* LOW holds the mutex now */
        g_phase = 2;
        if (xSemaphoreTake(g_mx, 1000) != pdPASS) tohost_exit(5);
        if (g_phase != 4) tohost_exit(4);          /* LOW released before we got it */
        g_phase = 5;
        xSemaphoreGive(g_mx);
        vTaskSuspend(g_med);                       /* or MEDIUM starves LOW from here on */
    }
}

static void low(void *pv) {
    (void)pv;
    for (int r = 0; r < 20; r++) {
        g_phase = 0;
        xSemaphoreTake(g_mx, portMAX_DELAY);
        g_phase = 1;
        xTaskNotifyGive(g_high);                   /* HIGH preempts, blocks on the mutex */
        if (g_phase != 2) tohost_exit(4);
        if (uxTaskPriorityGet(NULL) != tskIDLE_PRIORITY + 3) tohost_exit(1);
        vTaskResume(g_med);                        /* MEDIUM is ready but must not run */
        uint64_t m0 = g_med_count;
        for (volatile int i = 0; i < 3000; i++) ;   /* long critical section, ticks happen */
        if (g_med_count != m0) tohost_exit(3);
        g_phase = 4;
        xSemaphoreGive(g_mx);                      /* HIGH runs now */
        if (g_phase != 5) tohost_exit(4);
        if (uxTaskPriorityGet(NULL) != tskIDLE_PRIORITY + 1) tohost_exit(2);
        vTaskSuspend(g_med);
    }
    tohost_exit(0);
}

int app_main(void) {
    /* create everything before anyone can preempt the root task */
    vTaskPrioritySet(NULL, configMAX_PRIORITIES - 1);
    g_mx = xSemaphoreCreateMutex();
    check(g_mx != NULL, 5);
    xTaskCreate(high, "high", configMINIMAL_STACK_SIZE * 2, NULL, tskIDLE_PRIORITY + 3, &g_high);
    xTaskCreate(medium, "med", configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 2, &g_med);
    vTaskSuspend(g_med);
    xTaskCreate(low, "low", configMINIMAL_STACK_SIZE * 2, NULL, tskIDLE_PRIORITY + 1, &g_low);
    vTaskSuspend(NULL);
    return 0;
}
