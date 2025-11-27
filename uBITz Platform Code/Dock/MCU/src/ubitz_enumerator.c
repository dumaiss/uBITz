#include "ubitz_enumerator.h"
#include <string.h>

#include "driver/gpio.h"

static int popcount32(uint32_t v) { return __builtin_popcount(v); }
static int popcount8(uint8_t v) { return __builtin_popcount(v); }

static bool magic_ok(const uint8_t m[4]) {
    return m[0] == 'U' && m[1] == 'P' && m[2] == 'C' && m[3] == 'I';
}

// Enumeration snapshot state for monitor/UART consumption.
static ubitz_enum_snapshot_t g_snapshot;

// Read a block from a 16-bit addressed EEPROM over I2C.
static esp_err_t i2c_read_block(uint8_t dev_addr, uint16_t offset, uint8_t *buf, size_t len) {
    i2c_cmd_handle_t cmd = i2c_cmd_link_create();
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (dev_addr << 1) | I2C_MASTER_WRITE, true);
    i2c_master_write_byte(cmd, (offset >> 8) & 0xFF, true);
    i2c_master_write_byte(cmd, offset & 0xFF, true);
    i2c_master_start(cmd);
    i2c_master_write_byte(cmd, (dev_addr << 1) | I2C_MASTER_READ, true);
    if (len > 1) {
        i2c_master_read(cmd, buf, len - 1, I2C_MASTER_ACK);
    }
    i2c_master_read_byte(cmd, buf + len - 1, I2C_MASTER_NACK);
    i2c_master_stop(cmd);
    esp_err_t err = i2c_master_cmd_begin(UBITZ_I2C_PORT, cmd, pdMS_TO_TICKS(50));
    i2c_cmd_link_delete(cmd);
    return err;
}

esp_err_t ubitz_i2c_init(void) {
    i2c_config_t cfg = {
        .mode = I2C_MODE_MASTER,
        .sda_io_num = UBITZ_I2C_SDA_PIN,
        .scl_io_num = UBITZ_I2C_SCL_PIN,
        .sda_pullup_en = GPIO_PULLUP_ENABLE,
        .scl_pullup_en = GPIO_PULLUP_ENABLE,
        .master.clk_speed = UBITZ_I2C_FREQ_HZ,
    };
    ESP_ERROR_CHECK(i2c_param_config(UBITZ_I2C_PORT, &cfg));
    return i2c_driver_install(UBITZ_I2C_PORT, cfg.mode, 0, 0, 0);
}

esp_err_t ubitz_read_cpu_desc(ubitz_cpu_desc_t *out) {
    esp_err_t err = i2c_read_block(UBITZ_CPU_DESC_ADDR, 0, (uint8_t *)out, UBITZ_CPU_DESC_LEN);
    if (err != ESP_OK) {
        return err;
    }
    return (magic_ok(out->magic) && out->device_type == 0x01) ? ESP_OK : ESP_FAIL;
}

esp_err_t ubitz_read_dev_desc(uint8_t i2c_addr, ubitz_dev_desc_t *out) {
    esp_err_t err = i2c_read_block(i2c_addr, 0, (uint8_t *)out, UBITZ_DEV_DESC_LEN);
    if (err != ESP_OK) {
        return err;
    }
    return (magic_ok(out->magic) && out->device_type == 0x02) ? ESP_OK : ESP_FAIL;
}

esp_err_t ubitz_read_bank_desc(ubitz_bank_desc_t *out) {
    esp_err_t err = i2c_read_block(UBITZ_BANK_DESC_ADDR, 0, (uint8_t *)out, UBITZ_BANK_DESC_LEN);
    if (err != ESP_OK) {
        return err;
    }
    return (magic_ok(out->magic) && out->device_type == 0x03 && out->spec_version == 0x01)
               ? ESP_OK
               : ESP_FAIL;
}

bool ubitz_validate_cpu_desc(const ubitz_cpu_desc_t *cpu) {
    if (!magic_ok(cpu->magic) || cpu->device_type != 0x01) {
        return false;
    }
    if (cpu->data_bus_width != 8 && cpu->data_bus_width != 16 && cpu->data_bus_width != 32) {
        return false;
    }
    if (cpu->addr_bus_width != 8 && cpu->addr_bus_width != 16 && cpu->addr_bus_width != 32) {
        return false;
    }
    return true;
}

bool ubitz_validate_bank_desc(const ubitz_bank_desc_t *bank, const ubitz_cpu_desc_t *cpu) {
    if (!magic_ok(bank->magic) || bank->device_type != 0x03 || bank->spec_version != 0x01) {
        return false;
    }
    // Enumeration MUST fail if Bank DataBusWidth != Host DataBusWidth (spec 1.11.3).
    return bank->data_bus_width == cpu->data_bus_width;
}

esp_err_t ubitz_reset_init(void) {
    gpio_config_t cfg = {
        .pin_bit_mask = 1ULL << UBITZ_RESET_GPIO,
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    esp_err_t err = gpio_config(&cfg);
    if (err != ESP_OK) {
        return err;
    }
    // Default deasserted (high); caller should assert before enumeration.
    return gpio_set_level(UBITZ_RESET_GPIO, 1);
}

void ubitz_reset_assert(void) {
    gpio_set_level(UBITZ_RESET_GPIO, 0);
}

void ubitz_reset_release(void) {
    gpio_set_level(UBITZ_RESET_GPIO, 1);
}

// Build window map bindings; returns false on required-missing or collisions.
bool ubitz_build_window_map(const ubitz_cpu_desc_t *cpu,
                            const ubitz_dev_desc_t *devs, const uint8_t *slots,
                            int dev_count, ubitz_decode_binding_t *out, int *out_count) {
    int o = 0;
    // Collisions: identical mask+IOWin for different functions are undefined; reject.
    for (int i = 0; i < 16; ++i) {
        const ubitz_window_entry_t *wi = &cpu->window[i];
        if (wi->function == 0x00) {
            continue;
        }
        for (int j = i + 1; j < 16; ++j) {
            const ubitz_window_entry_t *wj = &cpu->window[j];
            if (wj->function == 0x00) {
                continue;
            }
            if (wi->iowin == wj->iowin && wi->mask == wj->mask && wi->opsel == wj->opsel &&
                (wi->function != wj->function || wi->instance != wj->instance)) {
                return false; // ambiguous decode
            }
        }
    }

    for (int i = 0; i < 16; ++i) {
        const ubitz_window_entry_t *w = &cpu->window[i];
        if (w->function == 0x00) {
            continue;
        }
        int found = -1;
        int found_inst = -1;
        for (int d = 0; d < dev_count; ++d) {
            for (int inst = 0; inst < 7; ++inst) {
                if (devs[d].inst[inst].function == w->function &&
                    devs[d].inst[inst].instance == w->instance) {
                    found = d;
                    found_inst = inst;
                    break;
                }
            }
            if (found >= 0) {
                break;
            }
        }
        if (found < 0) {
            if (w->flags & 0x01) {
                return false; // required but missing
            }
            continue; // optional missing: ignore
        }
        uint8_t dev_width = devs[found].inst[found_inst].data_bus_width;
        bool width_ok = dev_width <= cpu->data_bus_width;
        out[o++] = (ubitz_decode_binding_t){ .win = *w, .slot = slots[found], .width_ok = width_ok };
    }
    // Write order: highest mask specificity first (popcount of mask).
    for (int i = 1; i < o; ++i) {
        ubitz_decode_binding_t key = out[i];
        int key_pc = popcount32(key.win.mask);
        int j = i - 1;
        while (j >= 0 && popcount32(out[j].win.mask) < key_pc) {
            out[j + 1] = out[j];
            --j;
        }
        out[j + 1] = key;
    }
    *out_count = o;
    return true;
}

static bool route_dup(const ubitz_introute_entry_t *a, const ubitz_introute_entry_t *b) {
    return a->function == b->function && a->instance == b->instance && a->channel == b->channel;
}

bool ubitz_build_irq_map(const ubitz_cpu_desc_t *cpu,
                         const ubitz_dev_desc_t *devs, const uint8_t *slots,
                         int dev_count, ubitz_irq_binding_t *out, int *out_count) {
    int o = 0;
    // Reject duplicate routing entries.
    for (int i = 0; i < 16; ++i) {
        if (cpu->introute[i].function == 0x00) {
            continue;
        }
        for (int j = i + 1; j < 16; ++j) {
            if (cpu->introute[j].function == 0x00) {
                continue;
            }
            if (route_dup(&cpu->introute[i], &cpu->introute[j])) {
                return false;
            }
        }
    }

    // Ensure each declared device channel has routing.
    for (int d = 0; d < dev_count; ++d) {
        for (int inst = 0; inst < 7; ++inst) {
            const uint8_t chmask = devs[d].inst[inst].int_channel;
            if (chmask == 0) {
                continue;
            }
            // INT_CH[0..1]
            for (int bit = 0; bit < 2; ++bit) {
                if ((chmask & (1 << bit)) == 0) {
                    continue;
                }
                bool ok = false;
                for (int r = 0; r < 16; ++r) {
                    const ubitz_introute_entry_t *e = &cpu->introute[r];
                    if (e->function == 0x00) {
                        continue;
                    }
                    if (e->function == devs[d].inst[inst].function &&
                        e->instance == devs[d].inst[inst].instance &&
                        (e->channel & (1 << bit))) {
                        ok = true;
                        out[o++] = (ubitz_irq_binding_t){ .route = *e, .slot = slots[d] };
                        break;
                    }
                }
                if (!ok) {
                    return false;
                }
            }
            // NMI_CH bit (0x10)
            if (chmask & 0x10) {
                bool ok = false;
                for (int r = 0; r < 16; ++r) {
                    const ubitz_introute_entry_t *e = &cpu->introute[r];
                    if (e->function == 0x00) {
                        continue;
                    }
                    if (e->function == devs[d].inst[inst].function &&
                        e->instance == devs[d].inst[inst].instance &&
                        (e->channel & 0x10)) {
                        ok = true;
                        out[o++] = (ubitz_irq_binding_t){ .route = *e, .slot = slots[d] };
                        break;
                    }
                }
                if (!ok) {
                    return false;
                }
            }
        }
    }
    // Write order: more specific channel bitmasks first (popcount of channel).
    for (int i = 1; i < o; ++i) {
        ubitz_irq_binding_t key = out[i];
        int key_pc = popcount8(key.route.channel);
        int j = i - 1;
        while (j >= 0 && popcount8(out[j].route.channel) < key_pc) {
            out[j + 1] = out[j];
            --j;
        }
        out[j + 1] = key;
    }
    *out_count = o;
    return true;
}

void ubitz_snapshot_reset(void) {
    memset(&g_snapshot, 0, sizeof(g_snapshot));
    g_snapshot.fail_reason = UBITZ_ENUM_UNKNOWN_FAIL;
}

void ubitz_snapshot_set_failure(ubitz_enum_fail_t reason) {
    g_snapshot.success = false;
    g_snapshot.fail_reason = reason;
}

void ubitz_snapshot_publish(const ubitz_cpu_desc_t *cpu,
                            const ubitz_bank_desc_t *bank,
                            const ubitz_dev_desc_t *devs, int dev_count,
                            const ubitz_decode_binding_t *wins, int win_count,
                            const ubitz_irq_binding_t *irqs, int irq_count) {
    g_snapshot.success = true;
    g_snapshot.fail_reason = UBITZ_ENUM_OK;
    if (cpu) {
        g_snapshot.cpu = *cpu;
    }
    if (bank) {
        g_snapshot.bank = *bank;
    }
    g_snapshot.tile_count = (dev_count > UBITZ_MAX_TILES) ? UBITZ_MAX_TILES : dev_count;
    for (int i = 0; i < g_snapshot.tile_count; ++i) {
        g_snapshot.tiles[i] = devs[i];
    }
    g_snapshot.window_count = (win_count > UBITZ_MAX_WINDOWS) ? UBITZ_MAX_WINDOWS : win_count;
    for (int i = 0; i < g_snapshot.window_count; ++i) {
        g_snapshot.windows[i] = wins[i];
    }
    g_snapshot.irq_route_count = (irq_count > UBITZ_MAX_IRQ_ROUTES) ? UBITZ_MAX_IRQ_ROUTES : irq_count;
    for (int i = 0; i < g_snapshot.irq_route_count; ++i) {
        g_snapshot.irq_routes[i] = irqs[i];
    }
}

const ubitz_enum_snapshot_t *ubitz_snapshot_get(void) {
    return &g_snapshot;
}
