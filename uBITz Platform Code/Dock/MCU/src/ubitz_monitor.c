#include "ubitz_monitor.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "driver/uart.h"
#include "esp_log.h"
#include "esp_system.h"
#include "ubitz_enumerator.h"
#include <string.h>

static const char *TAG = "ubitz_monitor";
static const int RX_BUF_SIZE = 256;

static const char *fail_reason_str(ubitz_enum_fail_t r) {
    switch (r) {
    case UBITZ_ENUM_OK: return "OK";
    case UBITZ_ENUM_CPU_DESC_BAD: return "cpu_desc_bad";
    case UBITZ_ENUM_BANK_DESC_BAD: return "bank_desc_bad";
    case UBITZ_ENUM_BANK_WIDTH_MISMATCH: return "bank_width_mismatch";
    case UBITZ_ENUM_WINDOW_COLLISION: return "window_collision";
    case UBITZ_ENUM_REQUIRED_WINDOW_MISSING: return "required_window_missing";
    case UBITZ_ENUM_ROUTE_DUPLICATE: return "route_duplicate";
    case UBITZ_ENUM_ROUTE_MISSING: return "route_missing";
    case UBITZ_ENUM_DEV_WIDTH_INCOMPAT: return "dev_width_incompat";
    case UBITZ_ENUM_I2C_ERROR: return "i2c_error";
    default: return "unknown_fail";
    }
}

static void uart_write(const char *s) {
    uart_write_bytes(UBITZ_MONITOR_UART_NUM, s, strlen(s));
}

static void print_tiles(const ubitz_enum_snapshot_t *snap) {
    char buf[256];
    snprintf(buf, sizeof(buf), "tiles: count=%d\r\n", snap->tile_count);
    uart_write(buf);
    for (int i = 0; i < snap->tile_count; ++i) {
        const ubitz_dev_desc_t *d = &snap->tiles[i];
        for (int inst = 0; inst < 7; ++inst) {
            if (d->inst[inst].function == 0x00) {
                continue;
            }
            snprintf(buf, sizeof(buf),
                     "slot=%d func=0x%02X inst=%d dbw=%u abw=%u int_mask=0x%02X name=%.16s\r\n",
                     i, d->inst[inst].function, d->inst[inst].instance,
                     d->inst[inst].data_bus_width, d->inst[inst].addr_bus_width,
                     d->inst[inst].int_channel, d->inst[inst].name);
            uart_write(buf);
        }
    }
}

static void print_host(const ubitz_enum_snapshot_t *snap) {
    char buf[256];
    snprintf(buf, sizeof(buf),
             "host: dbw=%u abw=%u int_ack_mode=0x%02X platform=%.28s cpu_type=0x%02X\r\n",
             snap->cpu.data_bus_width, snap->cpu.addr_bus_width,
             snap->cpu.int_ack_mode, snap->cpu.platform_id, snap->cpu.cpu_type);
    uart_write(buf);
    // Windows
    for (int i = 0; i < UBITZ_MAX_WINDOWS; ++i) {
        const ubitz_window_entry_t *w = &snap->cpu.window[i];
        if (w->function == 0x00) {
            continue;
        }
        snprintf(buf, sizeof(buf),
                 "win[%d]: func=0x%02X inst=%d iowin=0x%08X mask=0x%08X opsel=0x%02X flags=0x%02X\r\n",
                 i, w->function, w->instance, w->iowin, w->mask, w->opsel, w->flags);
        uart_write(buf);
    }
    // IRQ routes
    for (int i = 0; i < 16; ++i) {
        const ubitz_introute_entry_t *r = &snap->cpu.introute[i];
        if (r->function == 0x00) {
            continue;
        }
        snprintf(buf, sizeof(buf),
                 "irq[%d]: func=0x%02X inst=%d chan=0x%02X dest=0x%02X mode=%u stretch=%u\r\n",
                 i, r->function, r->instance, r->channel, r->dest_pin, r->mode, r->stretch_us);
        uart_write(buf);
    }
}

static void print_bank(const ubitz_enum_snapshot_t *snap) {
    char buf[256];
    snprintf(buf, sizeof(buf),
             "bank: vendor=%.16s board=%.16s rev=0x%02X ram_aw=%u rom_aw=%u dbw=%u\r\n",
             snap->bank.vendor_id, snap->bank.board_id, snap->bank.bank_revision,
             snap->bank.ram_addr_width, snap->bank.rom_addr_width, snap->bank.data_bus_width);
    uart_write(buf);
}

static void print_errors(const ubitz_enum_snapshot_t *snap) {
    char buf[256];
    snprintf(buf, sizeof(buf), "enum success=%d reason=%s\r\n",
             snap->success, fail_reason_str(snap->fail_reason));
    uart_write(buf);
    // Windows with width_ok flag (if populated)
    for (int i = 0; i < snap->window_count; ++i) {
        snprintf(buf, sizeof(buf),
                 "winbind[%d]: func=0x%02X inst=%d slot=%d mask_pop=%d width_ok=%d\r\n",
                 i, snap->windows[i].win.function, snap->windows[i].win.instance,
                 snap->windows[i].slot, __builtin_popcount(snap->windows[i].win.mask),
                 snap->windows[i].width_ok);
        uart_write(buf);
    }
}

static void handle_command(const char *cmd) {
    const ubitz_enum_snapshot_t *snap = ubitz_snapshot_get();
    if (strcmp(cmd, "lstiles") == 0) {
        print_tiles(snap);
    } else if (strcmp(cmd, "showhost") == 0) {
        print_host(snap);
    } else if (strcmp(cmd, "showbank") == 0) {
        print_bank(snap);
    } else if (strcmp(cmd, "showerrors") == 0) {
        print_errors(snap);
    } else if (strcmp(cmd, "reset") == 0) {
        uart_write("resetting platform + MCU...\r\n");
        ubitz_reset_assert();
        vTaskDelay(pdMS_TO_TICKS(1000));
        ubitz_reset_release();
        vTaskDelay(pdMS_TO_TICKS(10));
        esp_restart();
    } else {
        uart_write("unknown command\r\n");
    }
}

static void monitor_task(void *arg) {
    uint8_t *data = (uint8_t *)malloc(RX_BUF_SIZE);
    if (!data) {
        ESP_LOGE(TAG, "no mem for monitor buffer");
        vTaskDelete(NULL);
    }
    int idx = 0;
    while (1) {
        int len = uart_read_bytes(UBITZ_MONITOR_UART_NUM, data + idx, 1, pdMS_TO_TICKS(100));
        if (len <= 0) {
            continue;
        }
        if (data[idx] == '\r' || data[idx] == '\n') {
            data[idx] = 0;
            if (idx > 0) {
                handle_command((char *)data);
            }
            idx = 0;
            continue;
        }
        idx++;
        if (idx >= RX_BUF_SIZE - 1) {
            idx = 0; // overflow guard
        }
    }
}

void ubitz_monitor_start(void) {
    uart_config_t cfg = {
        .baud_rate = UBITZ_MONITOR_BAUD,
        .data_bits = UART_DATA_8_BITS,
        .parity = UART_PARITY_DISABLE,
        .stop_bits = UART_STOP_BITS_1,
        .flow_ctrl = UART_HW_FLOWCTRL_DISABLE,
        .source_clk = UART_SCLK_DEFAULT,
    };
    ESP_ERROR_CHECK(uart_driver_install(UBITZ_MONITOR_UART_NUM, RX_BUF_SIZE, RX_BUF_SIZE, 0, NULL, 0));
    ESP_ERROR_CHECK(uart_param_config(UBITZ_MONITOR_UART_NUM, &cfg));
    ESP_ERROR_CHECK(uart_set_pin(UBITZ_MONITOR_UART_NUM, UBITZ_MONITOR_TX_PIN, UBITZ_MONITOR_RX_PIN, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE));

    xTaskCreatePinnedToCore(monitor_task, "ubitz_monitor", UBITZ_MONITOR_STACK_WORDS, NULL,
                            UBITZ_MONITOR_TASK_PRIO, NULL, UBITZ_MONITOR_CORE);
    ESP_LOGI(TAG, "monitor started on UART%d TX=%d RX=%d", UBITZ_MONITOR_UART_NUM, UBITZ_MONITOR_TX_PIN, UBITZ_MONITOR_RX_PIN);
}
