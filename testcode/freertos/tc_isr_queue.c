// @freertos-cflags -DconfigUSE_TICK_HOOK=1 -DconfigTICK_RATE_HZ=20000
/*
 * tc_isr_queue.c -- ISR -> task traffic: queue sends and task notifications
 * from the tick interrupt (vApplicationTickHook runs in the timer ISR).
 *
 * Every tick the ISR sends a sequence number to a queue; every 4th tick it
 * notifies a second task.  The consumer (highest priority) must receive every
 * number exactly once and in order, and the notification count must match.
 * This is the path every interrupt-driven driver uses, exercised thousands of
 * times with the ISR racing the consumer's critical sections.
 *
 * Exit codes: 0 pass, 1 out of order / lost, 2 queue overflowed in the ISR,
 *             3 notification count wrong, 4 timeout.
 */
#include "FreeRTOS.h"
#include "task.h"
#include "queue.h"
#include "test_utils_freertos.h"

#define N_ITEMS 400

static QueueHandle_t g_q;
static TaskHandle_t g_notified;
static volatile uint32_t g_sent, g_drops, g_notes_sent, g_enabled;

void vApplicationTickHook(void) {
    if (!g_enabled || g_sent >= N_ITEMS) return;
    BaseType_t woken = pdFALSE;
    uint32_t v = g_sent;
    if (xQueueSendFromISR(g_q, &v, &woken) == pdPASS) g_sent++;
    else g_drops++;
    if ((v & 3) == 0 && g_notified) { vTaskNotifyGiveFromISR(g_notified, &woken); g_notes_sent++; }
    portYIELD_FROM_ISR(woken);
}

static volatile uint32_t g_notes_got;
static void notified(void *pv) {
    (void)pv;
    for (;;) g_notes_got += ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
}

static void consumer(void *pv) {
    (void)pv;
    g_enabled = 1;
    for (uint32_t want = 0; want < N_ITEMS; want++) {
        uint32_t v;
        if (xQueueReceive(g_q, &v, 100) != pdPASS) tohost_exit(4);
        if (v != want) tohost_exit(1);
    }
    vTaskDelay(4);
    if (g_drops) tohost_exit(2);
    if (g_notes_got != g_notes_sent || g_notes_sent < N_ITEMS / 4 - 1) tohost_exit(3);
    tohost_exit(0);
}

int app_main(void) {
    g_q = xQueueCreate(16, sizeof(uint32_t));
    check(g_q != NULL, 4);
    xTaskCreate(notified, "note", configMINIMAL_STACK_SIZE, NULL, tskIDLE_PRIORITY + 2, &g_notified);
    xTaskCreate(consumer, "cons", configMINIMAL_STACK_SIZE * 2, NULL, configMAX_PRIORITIES - 1, NULL);
    vTaskSuspend(NULL);
    return 0;
}
