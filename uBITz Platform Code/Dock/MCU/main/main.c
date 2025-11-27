#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "ubitz_cpld_cfg.h"
#include "ubitz_enumerator.h"
#include "ubitz_monitor.h"

// Minimal entry point: reset snapshot and start UART monitor on core 1.
void app_main(void) {
    // Hold /RESET low during enumeration to keep platform quiescent.
    ubitz_reset_init();
    ubitz_reset_assert();

    ubitz_snapshot_reset();
    ubitz_cpu_desc_t cpu = {0};
    ubitz_bank_desc_t bank = {0};
    ubitz_dev_desc_t tiles[UBITZ_MAX_TILES] = {0};
    uint8_t slots[UBITZ_MAX_TILES] = {0};
    ubitz_decode_binding_t wins[UBITZ_MAX_WINDOWS] = {0};
    ubitz_irq_binding_t irqs[UBITZ_MAX_IRQ_ROUTES] = {0};
    int tile_count = 0, win_count = 0, irq_count = 0;
    bool win_collision = false;
    bool irq_duplicate = false;

    if (ubitz_i2c_init() != ESP_OK) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_I2C_ERROR);
        goto done;
    }
    if (ubitz_cpld_cfg_init() != ESP_OK) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_UNKNOWN_FAIL);
        goto done;
    }

    esp_err_t err = ubitz_read_cpu_desc(&cpu);
    if (err != ESP_OK || !ubitz_validate_cpu_desc(&cpu)) {
        ubitz_snapshot_set_failure(err == ESP_OK ? UBITZ_ENUM_CPU_DESC_BAD : UBITZ_ENUM_I2C_ERROR);
        goto done;
    }

    err = ubitz_read_bank_desc(&bank);
    if (err != ESP_OK) {
        ubitz_snapshot_set_failure(err == ESP_OK ? UBITZ_ENUM_BANK_DESC_BAD : UBITZ_ENUM_I2C_ERROR);
        goto done;
    }
    if (bank.data_bus_width != cpu.data_bus_width) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_BANK_WIDTH_MISMATCH);
        goto done;
    }
    if (!ubitz_validate_bank_desc(&bank, &cpu)) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_BANK_DESC_BAD);
        goto done;
    }

    for (int slot = 0; slot < UBITZ_MAX_TILES; ++slot) {
        esp_err_t dev_err = ubitz_read_dev_desc(UBITZ_TILE_BASE_ADDR + slot, &tiles[tile_count]);
        if (dev_err == ESP_OK) {
            for (int inst = 0; inst < 7; ++inst) {
                if (tiles[tile_count].inst[inst].function != 0x00 &&
                    tiles[tile_count].inst[inst].data_bus_width > cpu.data_bus_width) {
                    ubitz_snapshot_set_failure(UBITZ_ENUM_DEV_WIDTH_INCOMPAT);
                    goto done;
                }
            }
            slots[tile_count++] = slot;
        } else if (dev_err != ESP_FAIL) {
            ubitz_snapshot_set_failure(UBITZ_ENUM_I2C_ERROR);
            goto done;
        }
    }

    for (int i = 0; i < 16 && !win_collision; ++i) {
        const ubitz_window_entry_t *wi = &cpu.window[i];
        if (wi->function == 0x00) {
            continue;
        }
        for (int j = i + 1; j < 16; ++j) {
            const ubitz_window_entry_t *wj = &cpu.window[j];
            if (wj->function == 0x00) {
                continue;
            }
            if (wi->iowin == wj->iowin && wi->mask == wj->mask && wi->opsel == wj->opsel &&
                (wi->function != wj->function || wi->instance != wj->instance)) {
                win_collision = true;
                break;
            }
        }
    }
    if (win_collision) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_WINDOW_COLLISION);
        goto done;
    }

    if (!ubitz_build_window_map(&cpu, tiles, slots, tile_count, wins, &win_count)) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_REQUIRED_WINDOW_MISSING);
        goto done;
    }
    for (int i = 0; i < win_count; ++i) {
        if (!wins[i].width_ok) {
            ubitz_snapshot_set_failure(UBITZ_ENUM_DEV_WIDTH_INCOMPAT);
            goto done;
        }
    }

    for (int i = 0; i < 16 && !irq_duplicate; ++i) {
        const ubitz_introute_entry_t *ri = &cpu.introute[i];
        if (ri->function == 0x00) {
            continue;
        }
        for (int j = i + 1; j < 16; ++j) {
            const ubitz_introute_entry_t *rj = &cpu.introute[j];
            if (rj->function == 0x00) {
                continue;
            }
            if (ri->function == rj->function && ri->instance == rj->instance &&
                ri->channel == rj->channel) {
                irq_duplicate = true;
                break;
            }
        }
    }
    if (irq_duplicate) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_ROUTE_DUPLICATE);
        goto done;
    }

    if (!ubitz_build_irq_map(&cpu, tiles, slots, tile_count, irqs, &irq_count)) {
        ubitz_snapshot_set_failure(UBITZ_ENUM_ROUTE_MISSING);
        goto done;
    }

    ubitz_cpld_program_decoder(wins, win_count);
    ubitz_cpld_program_irq_router(irqs, irq_count);
    ubitz_snapshot_publish(&cpu, &bank, tiles, tile_count, wins, win_count, irqs, irq_count);

done:
    ubitz_reset_release();

    ubitz_monitor_start();
    vTaskDelay(portMAX_DELAY);
}
