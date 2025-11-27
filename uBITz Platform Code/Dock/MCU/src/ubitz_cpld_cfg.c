#include "ubitz_cpld_cfg.h"
#include "driver/gpio.h"

// Helper arrays for address/data bit driving.
static const gpio_num_t addr_pins[8] = {
    UBITZ_CFG_ADDR0_GPIO, UBITZ_CFG_ADDR1_GPIO, UBITZ_CFG_ADDR2_GPIO, UBITZ_CFG_ADDR3_GPIO,
    UBITZ_CFG_ADDR4_GPIO, UBITZ_CFG_ADDR5_GPIO, UBITZ_CFG_ADDR6_GPIO, UBITZ_CFG_ADDR7_GPIO,
};
static const gpio_num_t data_pins[8] = {
    UBITZ_CFG_DATA0_GPIO, UBITZ_CFG_DATA1_GPIO, UBITZ_CFG_DATA2_GPIO, UBITZ_CFG_DATA3_GPIO,
    UBITZ_CFG_DATA4_GPIO, UBITZ_CFG_DATA5_GPIO, UBITZ_CFG_DATA6_GPIO, UBITZ_CFG_DATA7_GPIO,
};

static inline void set_addr(uint8_t a) {
    for (int i = 0; i < 8; ++i) {
        gpio_set_level(addr_pins[i], (a >> i) & 0x1);
    }
}

static inline void set_data(uint8_t d) {
    for (int i = 0; i < 8; ++i) {
        gpio_set_level(data_pins[i], (d >> i) & 0x1);
    }
}

static inline void pulse_clk(void) {
    gpio_set_level(UBITZ_CFG_CLK_GPIO, 1);
    gpio_set_level(UBITZ_CFG_CLK_GPIO, 0);
}

// Decoder write: cfg_we high, latch on cfg_clk edge.
static void dec_write(uint8_t addr, uint8_t data) {
    set_addr(addr);
    set_data(data);
    gpio_set_level(UBITZ_CFG_WE_GPIO, 1);
    pulse_clk();
    gpio_set_level(UBITZ_CFG_WE_GPIO, 0);
}

// IRQ router write: cfg_wr_en high, latch on cfg_clk edge.
static void irq_write(uint8_t addr, uint8_t data) {
    set_addr(addr);
    set_data(data);
    gpio_set_level(UBITZ_CFG_WR_GPIO, 1);
    pulse_clk();
    gpio_set_level(UBITZ_CFG_WR_GPIO, 0);
}

esp_err_t ubitz_cpld_cfg_init(void) {
    gpio_config_t cfg = {
        .mode = GPIO_MODE_OUTPUT,
        .pull_up_en = GPIO_PULLUP_DISABLE,
        .pull_down_en = GPIO_PULLDOWN_DISABLE,
        .intr_type = GPIO_INTR_DISABLE,
    };
    // Configure control pins
    uint64_t mask = (1ULL << UBITZ_CFG_CLK_GPIO) |
                    (1ULL << UBITZ_CFG_WE_GPIO) |
                    (1ULL << UBITZ_CFG_WR_GPIO) |
                    (1ULL << UBITZ_CFG_RD_GPIO);
    for (int i = 0; i < 8; ++i) {
        mask |= (1ULL << addr_pins[i]);
        mask |= (1ULL << data_pins[i]);
    }
    cfg.pin_bit_mask = mask;
    esp_err_t err = gpio_config(&cfg);
    if (err != ESP_OK) {
        return err;
    }
    gpio_set_level(UBITZ_CFG_CLK_GPIO, 0);
    gpio_set_level(UBITZ_CFG_WE_GPIO, 0);
    gpio_set_level(UBITZ_CFG_WR_GPIO, 0);
    gpio_set_level(UBITZ_CFG_RD_GPIO, 0);
    return ESP_OK;
}

// Map OpSel to CPLD OP encoding (simplified).
static uint8_t op_encode(uint8_t opsel) {
    if (opsel == UBITZ_OP_READ) {
        return 0x01;
    }
    if (opsel == UBITZ_OP_WRITE) {
        return 0x00;
    }
    return 0xFF; // ANY
}

void ubitz_cpld_program_decoder(const ubitz_decode_binding_t *wins, int count) {
    // BASE region: 0x00-0x3F, MASK region: 0x40-0x7F, SLOT: 0x80-0x8F, OP: 0x90-0x9F
    for (int idx = 0; idx < count; ++idx) {
        const ubitz_decode_binding_t *b = &wins[idx];
        uint32_t base = b->win.iowin;
        uint32_t mask = b->win.mask;
        uint8_t slot  = b->slot & 0x07;
        uint8_t op    = op_encode(b->win.opsel);
        int w = idx; // programming in sorted order supplied by builder
        // Write BASE bytes
        for (int byte = 0; byte < 4; ++byte) {
            dec_write(0x00 + w * 4 + byte, (base >> (8 * byte)) & 0xFF);
        }
        // Write MASK bytes
        for (int byte = 0; byte < 4; ++byte) {
            dec_write(0x40 + w * 4 + byte, (mask >> (8 * byte)) & 0xFF);
        }
        // SLOT
        dec_write(0x80 + w, slot);
        // OP
        dec_write(0x90 + w, op);
    }
}

// Helpers for IRQ routing flattening
static inline uint8_t int_entry(uint8_t dest_pin) {
    return 0x80 | (dest_pin & 0x0F); // bit7 enable, low nibble dest
}

static inline uint8_t nmi_entry(uint8_t dest_pin) {
    return 0x80 | (dest_pin & 0x0F); // same format
}

void ubitz_cpld_program_irq_router(const ubitz_irq_binding_t *irqs, int count) {
    // Assume 5 slots, 2 INT channels per slot: maskable idx = slot*2 + ch
    // NMI entries follow at idx = NUM_SLOTS*2 + slot
    const int num_slots = 5;
    for (int i = 0; i < count; ++i) {
        const ubitz_irq_binding_t *b = &irqs[i];
        uint8_t chmask = b->route.channel;
        uint8_t dest = b->route.dest_pin;
        if (chmask & 0x01) { // INT_CH0
            uint8_t idx = (b->slot * 2) + 0;
            irq_write(idx, int_entry(dest));
        }
        if (chmask & 0x02) { // INT_CH1
            uint8_t idx = (b->slot * 2) + 1;
            irq_write(idx, int_entry(dest));
        }
        if (chmask & 0x10) { // NMI
            uint8_t idx = (num_slots * 2) + b->slot;
            // dest_pin expected 0x10/0x11 -> map to NMI index 0/1
            uint8_t nmi_dest = (dest >= 0x10) ? (dest - 0x10) : dest;
            irq_write(idx, nmi_entry(nmi_dest));
        }
    }
}
