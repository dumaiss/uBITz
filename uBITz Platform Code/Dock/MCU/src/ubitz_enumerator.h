#pragma once
// uBITz enumerator: reads CPU/Device descriptors over I2C and builds
// window decode and interrupt routing tables per Core spec.
// Pin placeholders use ESP32-S3 WROOM sheet: SCL0=GPIO0, SDA0=GPIO1.

#include <stdint.h>
#include <stdbool.h>
#include "esp_err.h"
#include "driver/i2c.h"

#include "ubitz_pins.h"

#define UBITZ_I2C_PORT      I2C_NUM_0
#define UBITZ_I2C_FREQ_HZ   400000

// Default 7-bit I2C addresses (adjust to actual EEPROM wiring)
#define UBITZ_CPU_DESC_ADDR   0x50  // CPU card EEPROM
#define UBITZ_BANK_DESC_ADDR  0x51  // Bank card EEPROM
#define UBITZ_TILE_BASE_ADDR  0x52  // First tile slot EEPROM; slots use base+slot

#define UBITZ_CPU_DESC_LEN    416
#define UBITZ_BANK_DESC_LEN   256
#define UBITZ_DEV_DESC_LEN    256
#define UBITZ_MAX_TILES       5
#define UBITZ_MAX_WINDOWS     16
#define UBITZ_MAX_IRQ_ROUTES  32

typedef enum { UBITZ_OP_ANY = 0xFF, UBITZ_OP_READ = 0x01, UBITZ_OP_WRITE = 0x00 } ubitz_opsel_t;

typedef struct __attribute__((packed)) {
    uint8_t  function;
    uint8_t  instance;
    uint32_t iowin;
    uint32_t mask;
    uint8_t  opsel;
    uint8_t  flags;   // bit0: Required
    uint8_t  reserved[2];
} ubitz_window_entry_t;

typedef struct __attribute__((packed)) {
    uint8_t function;
    uint8_t instance;
    uint8_t channel;   // bitfield per spec
    uint8_t dest_pin;  // 0-3 = CPU_INT, 0x10-0x11 = CPU_NMI
    uint8_t mode;      // 0=edge, 1=level
    uint8_t stretch_us;
    uint8_t reserved[2];
} ubitz_introute_entry_t;

typedef struct __attribute__((packed)) {
    uint8_t  magic[4];      // "UPCI"
    uint8_t  version;
    uint8_t  device_type;   // 0x01=CPU
    uint8_t  reserved1[10];
    char     manufacturer[16];
    char     platform_id[28];
    uint8_t  cpu_type;
    uint8_t  data_bus_width;
    uint8_t  addr_bus_width;
    uint8_t  int_ack_mode;
    ubitz_window_entry_t   window[16];
    ubitz_introute_entry_t introute[16];
} ubitz_cpu_desc_t;

typedef struct __attribute__((packed)) {
    uint8_t  magic[4];      // "UPCI"
    uint8_t  version;
    uint8_t  device_type;   // 0x02 = Peripheral
    uint8_t  reserved1[10];
    struct {
        uint8_t function;
        uint8_t instance;
        uint8_t data_bus_width;
        uint8_t addr_bus_width;
        uint8_t int_ack_mode;
        uint8_t int_channel;   // bitmask per spec
        uint8_t hw_version;
        uint8_t fw_version;
        char    name[16];
        uint8_t reserved2[7];
    } inst[7];
    uint8_t reserved3[16];
} ubitz_dev_desc_t;

typedef struct __attribute__((packed)) {
    uint8_t  magic[4];       // "UPCI"
    uint8_t  spec_version;   // Must be 0x01 for this layout
    uint8_t  device_type;    // 0x03 = Bank (Memory Board)
    uint8_t  reserved1[10];
    char     vendor_id[16];
    char     board_id[16];
    uint8_t  bank_revision;
    uint8_t  ram_addr_width;
    uint8_t  rom_addr_width;
    uint8_t  data_bus_width; // Must equal Host data bus width
    uint8_t  reserved2[204];
} ubitz_bank_desc_t;

typedef struct {
    ubitz_window_entry_t  win;
    uint8_t               slot;
    uint8_t               width_ok;   // 1 if device width <= CPU width
} ubitz_decode_binding_t;

typedef struct {
    ubitz_introute_entry_t route;
    uint8_t                slot;
} ubitz_irq_binding_t;

typedef enum {
    UBITZ_ENUM_OK = 0,
    UBITZ_ENUM_CPU_DESC_BAD,
    UBITZ_ENUM_BANK_DESC_BAD,
    UBITZ_ENUM_BANK_WIDTH_MISMATCH,
    UBITZ_ENUM_WINDOW_COLLISION,
    UBITZ_ENUM_REQUIRED_WINDOW_MISSING,
    UBITZ_ENUM_ROUTE_DUPLICATE,
    UBITZ_ENUM_ROUTE_MISSING,
    UBITZ_ENUM_DEV_WIDTH_INCOMPAT,
    UBITZ_ENUM_I2C_ERROR,
    UBITZ_ENUM_UNKNOWN_FAIL
} ubitz_enum_fail_t;

typedef struct {
    bool                    success;
    ubitz_enum_fail_t       fail_reason;
    ubitz_cpu_desc_t        cpu;
    ubitz_bank_desc_t       bank;
    ubitz_dev_desc_t        tiles[UBITZ_MAX_TILES];
    int                     tile_count;
    ubitz_decode_binding_t  windows[UBITZ_MAX_WINDOWS];
    int                     window_count;
    ubitz_irq_binding_t     irq_routes[UBITZ_MAX_IRQ_ROUTES];
    int                     irq_route_count;
} ubitz_enum_snapshot_t;

esp_err_t ubitz_i2c_init(void);
esp_err_t ubitz_read_cpu_desc(ubitz_cpu_desc_t *out);
esp_err_t ubitz_read_dev_desc(uint8_t i2c_addr, ubitz_dev_desc_t *out);
esp_err_t ubitz_read_bank_desc(ubitz_bank_desc_t *out);
bool      ubitz_validate_cpu_desc(const ubitz_cpu_desc_t *cpu);
bool      ubitz_validate_bank_desc(const ubitz_bank_desc_t *bank, const ubitz_cpu_desc_t *cpu);
esp_err_t ubitz_reset_init(void);
void      ubitz_reset_assert(void);
void      ubitz_reset_release(void);
bool      ubitz_build_window_map(const ubitz_cpu_desc_t *cpu,
                                  const ubitz_dev_desc_t *devs, const uint8_t *slots,
                                  int dev_count, ubitz_decode_binding_t *out, int *out_count);
bool      ubitz_build_irq_map(const ubitz_cpu_desc_t *cpu,
                              const ubitz_dev_desc_t *devs, const uint8_t *slots,
                              int dev_count, ubitz_irq_binding_t *out, int *out_count);

// Snapshot helpers for monitor/UART access
void                          ubitz_snapshot_reset(void);
void                          ubitz_snapshot_set_failure(ubitz_enum_fail_t reason);
void                          ubitz_snapshot_publish(const ubitz_cpu_desc_t *cpu,
                                                     const ubitz_bank_desc_t *bank,
                                                     const ubitz_dev_desc_t *devs, int dev_count,
                                                     const ubitz_decode_binding_t *wins, int win_count,
                                                     const ubitz_irq_binding_t *irqs, int irq_count);
const ubitz_enum_snapshot_t  *ubitz_snapshot_get(void);
