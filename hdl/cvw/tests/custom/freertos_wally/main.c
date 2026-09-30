#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>

#include "FreeRTOS.h"
#include "task.h"
#include "semphr.h"
#include "timers.h"

#include "wally_uart.h"
#include "wally_clint.h"

#include <stdint.h>

/* Count leading zeros for 64-bit integer */
int __clzdi2(uint64_t x) {
    if (x == 0) return 64;
    int n = 0;
    if ((x & 0xFFFFFFFF00000000ULL) == 0) { n += 32; x <<= 32; }
    if ((x & 0xFFFF000000000000ULL) == 0) { n += 16; x <<= 16; }
    if ((x & 0xFF00000000000000ULL) == 0) { n +=  8; x <<=  8; }
    if ((x & 0xF000000000000000ULL) == 0) { n +=  4; x <<=  4; }
    if ((x & 0xC000000000000000ULL) == 0) { n +=  2; x <<=  2; }
    if ((x & 0x8000000000000000ULL) == 0) { n +=  1; }
    return n;
}

/* Also provide 32-bit version in case it's needed */
int __clzsi2(uint32_t x) {
    if (x == 0) return 32;
    int n = 0;
    if ((x & 0xFFFF0000U) == 0) { n += 16; x <<= 16; }
    if ((x & 0xFF000000U) == 0) { n +=  8; x <<=  8; }
    if ((x & 0xF0000000U) == 0) { n +=  4; x <<=  4; }
    if ((x & 0xC0000000U) == 0) { n +=  2; x <<=  2; }
    if ((x & 0x80000000U) == 0) { n +=  1; }
    return n;
}

/* ------------------------------------------------------------
 * Semaphore to serialize printf across tasks.
 * FreeRTOS printf is not re-entrant so we gate it.
 * ------------------------------------------------------------ */
static SemaphoreHandle_t xPrintMutex;

/* Safe printf wrapper - tasks use this instead of printf directly */
static void task_printf(const char *fmt, ...) {
    /* For simplicity in this demo, tasks print short fixed strings
       via uart_puts which is safe to call from any context.
       For full printf support, use xSemaphoreTake/Give around printf. */
    (void)fmt;
}

static void vTerminateTask(void *pvParameters) {
    (void)pvParameters;
    // Wait 50 FreeRTOS ticks to let other tasks demonstrate switching
    vTaskDelay(50);
    printf("\r\nFreeRTOS demo complete.\r\n");
    printf("Task1 and Task2 demonstrated preemptive scheduling.\r\n");
    exit(0);  // terminates Wally simulation via tohost
}
/* ------------------------------------------------------------
 * Task 1: blinks at 1 Hz (1000ms period)
 * Demonstrates vTaskDelay
 * ------------------------------------------------------------ */
static void vTask1(void *pvParameters) {
    (void)pvParameters;
    uint32_t count = 0;

    printf("Task1 started\r\n");

    for (;;) {
        printf("[Task1] tick %lu\r\n", (unsigned long)count++);
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}

/* ------------------------------------------------------------
 * Task 2: runs at 2 Hz (500ms period), higher priority
 * Demonstrates preemption over Task1
 * ------------------------------------------------------------ */
static void vTask2(void *pvParameters) {
    (void)pvParameters;
    uint32_t count = 0;

    printf("Task2 started\r\n");

    for (;;) {
        printf("[Task2] tick %lu\r\n", (unsigned long)count++);
        vTaskDelay(pdMS_TO_TICKS(500));
    }
}

/* ------------------------------------------------------------
 * Task 3: runs once, prints system info, then deletes itself
 * Demonstrates vTaskDelete and uxTaskGetStackHighWaterMark
 * ------------------------------------------------------------ */
static void vTask3(void *pvParameters) {
    (void)pvParameters;

    printf("Task3: one-shot info task\r\n");
    printf("  configTICK_RATE_HZ   = %lu\r\n", (unsigned long)configTICK_RATE_HZ);
    printf("  configTOTAL_HEAP_SIZE= %lu bytes\r\n", (unsigned long)configTOTAL_HEAP_SIZE);
    printf("  configMTIME_HZ       = %lu\r\n", (unsigned long)configMTIME_HZ);
    printf("  CLINT mtime at start = %llu\r\n", (unsigned long long)clint_get_time());

    printf("Task3 deleting itself\r\n");
    vTaskDelete(NULL);
}

/* ------------------------------------------------------------
 * Software timer callback: fires every 2 seconds
 * Demonstrates FreeRTOS software timers
 * ------------------------------------------------------------ */
static void vTimerCallback(TimerHandle_t xTimer) {
    (void)xTimer;
    static uint32_t fire_count = 0;
    printf("[Timer] fired %lu times\r\n", (unsigned long)++fire_count);
}

/* ------------------------------------------------------------
 * FreeRTOS hooks
 * ------------------------------------------------------------ */
void vApplicationMallocFailedHook(void) {
    printf("FATAL: malloc failed\r\n");
    for (;;);
}

void vApplicationStackOverflowHook(TaskHandle_t xTask, char *pcTaskName) {
    (void)xTask;
    printf("FATAL: stack overflow in task '%s'\r\n", pcTaskName);
    for (;;);
}

void vApplicationIdleHook(void) {
    /* Nothing — idle task just yields */
}

/* ------------------------------------------------------------
 * main: create tasks and start scheduler
 *
 * Note: crt.S from examples/C/common calls main() after
 * zeroing BSS and setting up the stack. FreeRTOS takes over
 * from here and never returns to crt.S.
 * ------------------------------------------------------------ */
int main(void) {
    printf("\r\n=== FreeRTOS on Wally ===\r\n");
    printf("Initializing...\r\n");

    /* Mutex for printf serialization (optional - demo uses fixed strings) */
    xPrintMutex = xSemaphoreCreateMutex();
    if (xPrintMutex == NULL) {
        printf("FATAL: could not create print mutex\r\n");
        for (;;);
    }

    /* Create tasks */
    BaseType_t ret;

    ret = xTaskCreate(vTask1, "Task1",
                      configMINIMAL_STACK_SIZE, NULL,
                      tskIDLE_PRIORITY + 1, NULL);
    if (ret != pdPASS) { printf("FATAL: Task1 create failed\r\n"); for(;;); }

    ret = xTaskCreate(vTask2, "Task2",
                      configMINIMAL_STACK_SIZE, NULL,
                      tskIDLE_PRIORITY + 2, NULL);   /* higher priority than Task1 */
    if (ret != pdPASS) { printf("FATAL: Task2 create failed\r\n"); for(;;); }

    ret = xTaskCreate(vTask3, "Task3",
                      configMINIMAL_STACK_SIZE * 2, NULL,
                      tskIDLE_PRIORITY + 3, NULL);   /* runs first, then deletes */
    if (ret != pdPASS) { printf("FATAL: Task3 create failed\r\n"); for(;;); }

    /* Software timer: fires every 2000ms */
    TimerHandle_t xTimer = xTimerCreate("SysTimer",
                                         pdMS_TO_TICKS(2000),
                                         pdTRUE,        /* auto-reload */
                                         NULL,
                                         vTimerCallback);
    if (xTimer != NULL) xTimerStart(xTimer, 0);

    printf("Starting scheduler...\r\n");

    // Add this task in main() before vTaskStartScheduler()
    ret = xTaskCreate(vTerminateTask, "Term",
                  configMINIMAL_STACK_SIZE, NULL,
                  tskIDLE_PRIORITY + 1, NULL);

    /* Hand control to FreeRTOS — does not return */
    vTaskStartScheduler();

    /* Should never reach here. If it does, heap exhaustion is the likely cause. */
    printf("FATAL: scheduler returned (heap exhaustion?)\r\n");
    for (;;);

    return 0;  /* unreachable, satisfies compiler */
}
// #include <stdio.h>
// #include <stdint.h>
// #include <stdlib.h>
// #include "wally_clint.h"

// // Minimal trap handler - just handles timer and returns
// void __attribute__((interrupt)) timer_handler(void) {
//     // Advance mtimecmp by one tick to clear the interrupt
//     CLINT_MTIMECMP = CLINT_MTIME + 1000000;
//     printf("Timer fired! mtime=%llu\r\n", (unsigned long long)CLINT_MTIME);
// }

// int main(void) {
//     printf("CLINT test starting\r\n");
//     printf("mtime = %llu\r\n", (unsigned long long)CLINT_MTIME);
//     printf("mtimecmp = %llu\r\n", (unsigned long long)CLINT_MTIMECMP);

//     // Install minimal direct-mode trap handler
//     uintptr_t handler = (uintptr_t)timer_handler;
//     __asm__ volatile("csrw mtvec, %0" :: "r"(handler & ~3UL)); // direct mode

//     // Set timer to fire soon
//     CLINT_MTIMECMP = CLINT_MTIME + 10000;

//     // Enable machine timer interrupt (MTIE = bit 7)
//     // __asm__ volatile("csrsi mie, 0x80");
//     __asm__ volatile("csrw mie, %0" :: "r"(0x80));   // MTIE bit 7


//     // Enable global interrupts (MIE = bit 3 in mstatus)
//     __asm__ volatile("csrsi mstatus, 0x8");

//     printf("Waiting for timer interrupt...\r\n");

//     // Spin and wait - timer should fire
//     for (volatile int i = 0; i < 100000000; i++) {
//         if (i % 10000000 == 0)
//             printf("spinning %d\r\n", i/10000000);
//     }

//     printf("Done\r\n");
//     exit(0);
// }
