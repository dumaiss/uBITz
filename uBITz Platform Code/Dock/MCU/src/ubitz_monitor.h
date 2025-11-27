#pragma once
#include "driver/uart.h"
#include "ubitz_enumerator.h"
#include "ubitz_pins.h"

#define UBITZ_MONITOR_UART_NUM   UART_NUM_1
#define UBITZ_MONITOR_BAUD       115200
#define UBITZ_MONITOR_STACK_WORDS 4096
#define UBITZ_MONITOR_TASK_PRIO   5
#define UBITZ_MONITOR_CORE        1   // Run on APP CPU

void ubitz_monitor_start(void);
