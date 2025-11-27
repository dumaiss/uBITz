#pragma once
// Central pin assignment header for the ESP32-S3 Dock MCU.
// Replace placeholder values with final PCB mappings.

// I2C enumeration bus (Tiles/CPU/Bank descriptors)
#define UBITZ_I2C_SCL_PIN   0   // default SCL0
#define UBITZ_I2C_SDA_PIN   1   // default SDA0

// Platform reset (/RESET drives Host/Bank/Tiles/decoder), active-low
#define UBITZ_RESET_GPIO    21

// CPLD configuration bus (address decoder / IRQ router)
#define UBITZ_CFG_CLK_GPIO   33
#define UBITZ_CFG_WE_GPIO    34   // Decoder cfg_we
#define UBITZ_CFG_WR_GPIO    35   // IRQ cfg_wr_en
#define UBITZ_CFG_RD_GPIO    36   // IRQ cfg_rd_en (unused in current HDL)
#define UBITZ_CFG_ADDR0_GPIO 37
#define UBITZ_CFG_ADDR1_GPIO 38
#define UBITZ_CFG_ADDR2_GPIO 39
#define UBITZ_CFG_ADDR3_GPIO 40
#define UBITZ_CFG_ADDR4_GPIO 41
#define UBITZ_CFG_ADDR5_GPIO 42
#define UBITZ_CFG_ADDR6_GPIO 43
#define UBITZ_CFG_ADDR7_GPIO 44
#define UBITZ_CFG_DATA0_GPIO 45
#define UBITZ_CFG_DATA1_GPIO 46
#define UBITZ_CFG_DATA2_GPIO 47
#define UBITZ_CFG_DATA3_GPIO 48
#define UBITZ_CFG_DATA4_GPIO 15
#define UBITZ_CFG_DATA5_GPIO 16
#define UBITZ_CFG_DATA6_GPIO 19
#define UBITZ_CFG_DATA7_GPIO 20

// UART monitor (command interface)
#define UBITZ_MONITOR_TX_PIN 17
#define UBITZ_MONITOR_RX_PIN 18
