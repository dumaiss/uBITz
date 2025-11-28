# ESP32-S3 Dock MCU – GPIO Assignment (Provisional)

> This table is a **provisional** mapping for the reference Dock. It is intended to guide schematic capture and will be
> updated as routing and signal integrity constraints are better understood. GPIO numbers are examples and MUST be
> cross-checked against the ESP32-S3-WROOM module datasheet before finalizing.

## Legend

- **Dir**: I = input, O = output, IO = bidirectional (or configurable).
- **Status**:
  - `USED_DIRECT` – intended to be wired directly from ESP32 to Dock Digital logic.
  - `VIA_EXPANDER` – handled by the GPIO expander, not directly by ESP32.
  - `RESERVED/UNUSED` – not used in this reference design (may be free, strapping, or module-internal).

> **NOTE:** The specific GPIO numbers below are placeholders and MAY change. The architectural guarantees are:
> (1) Slot 0 Tile interface is wired directly, (2) CPLD config buses and other slow controls are driven via the GPIO
> expander, and (3) USB D+/D− pins are dedicated to USB host and not reused as generic GPIO.

## 1. Direct MCU GPIOs (conceptual mapping)

| GPIO# (provisional) | Pin Name (SoC) | Function Group           | Signal(s) / Role                             | Dir | Status       | Notes                                      |
|---------------------|----------------|--------------------------|----------------------------------------------|-----|--------------|--------------------------------------------|
| TBD_01              | GPIOx          | Slot 0 Tile              | D0                                          | IO  | USED_DIRECT  | Part of Dock data bus to CPLD.             |
| TBD_02              | GPIOx          | Slot 0 Tile              | D1                                          | IO  | USED_DIRECT  |                                            |
| TBD_03              | GPIOx          | Slot 0 Tile              | D2                                          | IO  | USED_DIRECT  |                                            |
| TBD_04              | GPIOx          | Slot 0 Tile              | D3                                          | IO  | USED_DIRECT  |                                            |
| TBD_05              | GPIOx          | Slot 0 Tile              | D4                                          | IO  | USED_DIRECT  |                                            |
| TBD_06              | GPIOx          | Slot 0 Tile              | D5                                          | IO  | USED_DIRECT  |                                            |
| TBD_07              | GPIOx          | Slot 0 Tile              | D6                                          | IO  | USED_DIRECT  |                                            |
| TBD_08              | GPIOx          | Slot 0 Tile              | D7                                          | IO  | USED_DIRECT  |                                            |
| TBD_09              | GPIOx          | Slot 0 Tile              | A_LOCAL0                                    | O   | USED_DIRECT  | Local Tile address bit 0.                  |
| TBD_10              | GPIOx          | Slot 0 Tile              | A_LOCAL1                                    | O   | USED_DIRECT  |                                            |
| TBD_11              | GPIOx          | Slot 0 Tile              | A_LOCAL2                                    | O   | USED_DIRECT  |                                            |
| TBD_12              | GPIOx          | Slot 0 Tile              | A_LOCAL3                                    | O   | USED_DIRECT  |                                            |
| TBD_13              | GPIOx          | Slot 0 Tile              | /CS_0                                      | O   | USED_DIRECT  | Chip-select for Dock Services Tile.        |
| TBD_14              | GPIOx          | Slot 0 Tile              | R/W_                                       | O   | USED_DIRECT  | Shared with other Tiles via CPLD.         |
| TBD_15              | GPIOx          | Slot 0 Tile              | READY_0#                                   | O   | USED_DIRECT  | Slot 0 ready output into CPLD.             |
| TBD_16              | GPIOx          | Slot 0 Tile              | INT_CH0_0                                  | O   | USED_DIRECT  | Slot 0 interrupt channel 0.                |
| TBD_17              | GPIOx          | Slot 0 Tile              | INT_CH1_0                                  | O   | USED_DIRECT  | Slot 0 interrupt channel 1.                |
| TBD_18              | GPIOx          | Slot 0 Tile              | NMI_CH_0                                   | O   | USED_DIRECT  | Slot 0 NMI request.                        |
| TBD_19              | GPIOx          | I²C Master               | I2C_MCU_SCL                                | IO  | USED_DIRECT  | To TCA9548A upstream SCL.                  |
| TBD_20              | GPIOx          | I²C Master               | I2C_MCU_SDA                                | IO  | USED_DIRECT  | To TCA9548A upstream SDA.                  |
| TBD_21              | GPIOx          | Service UART             | UART_MON_TX                                | O   | USED_DIRECT  | To FT232R RXD.                             |
| TBD_22              | GPIOx          | Service UART             | UART_MON_RX                                | I   | USED_DIRECT  | From FT232R TXD.                           |
| TBD_23              | GPIOx          | Service UART             | UART_MON_RTS                               | O   | USED_DIRECT  | To FT232R CTS.                             |
| TBD_24              | GPIOx          | Service UART             | UART_MON_CTS                               | I   | USED_DIRECT  | From FT232R RTS.                           |
| TBD_25              | GPIOx          | Power Control            | MAIN_ON_REQ                                | O   | USED_DIRECT  | Request to enable main rails.              |
| TBD_26              | GPIOx          | Power Status             | PG_5V_MAIN                                 | I   | USED_DIRECT  | Power-good indication from 5 V.            |
| TBD_27              | GPIOx          | Power Status             | PG_3V3_MAIN                                | I   | USED_DIRECT  | Power-good indication from 3.3 V.          |
| TBD_28              | GPIOx          | Debug / LEDs             | DBG_LED0                                   | O   | USED_DIRECT  | Optional; may be dropped if GPIO tight.    |
| TBD_29              | GPIOx          | Debug / LEDs             | DBG_LED1                                   | O   | USED_DIRECT  | Optional; may be dropped if GPIO tight.    |

(Additional direct GPIOs can be added as needed; the intent is to keep the **total number of direct GPIOs on the Dock MCU
comfortably below the available budget**.)

## 2. Signals handled via GPIO expander

The GPIO expander provides at least 16 bits that are treated as “virtual GPIOs” for low-speed control. Examples:

| Expander Bit | Function Group      | Signal(s) / Role                           | Notes                                  |
|--------------|---------------------|--------------------------------------------|----------------------------------------|
| EXP0         | CPLD config bus     | CFG_ADDR0                                  | Part of parallel config address bus.   |
| EXP1         | CPLD config bus     | CFG_ADDR1                                  |                                        |
| EXP2         | CPLD config bus     | CFG_ADDR2                                  |                                        |
| EXP3         | CPLD config bus     | CFG_ADDR3                                  |                                        |
| EXP4         | CPLD config bus     | CFG_ADDR4                                  |                                        |
| EXP5         | CPLD config bus     | CFG_ADDR5                                  |                                        |
| EXP6         | CPLD config bus     | CFG_ADDR6                                  |                                        |
| EXP7         | CPLD config bus     | CFG_ADDR7                                  |                                        |
| EXP8         | CPLD config bus     | CFG_DATA0                                  | Part of parallel config data bus.      |
| EXP9         | CPLD config bus     | CFG_DATA1                                  |                                        |
| EXP10        | CPLD config bus     | CFG_DATA2                                  |                                        |
| EXP11        | CPLD config bus     | CFG_DATA3                                  |                                        |
| EXP12        | CPLD config bus     | CFG_WE                                    | Write-enable strobe into config port.  |
| EXP13        | USB hub control     | HUB_RESET#                                 | Hub reset (active-low).                |
| EXP14        | Debug / misc        | TBD                                        | Reserve for future slow control.       |
| EXP15        | Debug / misc        | TBD                                        | Reserve for future slow control.       |

Exact mapping of expander bits to CPLD pins will be captured in the Dock schematic and can be adjusted without
affecting the overall architecture.

## 3. Reserved / unavailable GPIOs

Some ESP32-S3 GPIOs on the WROOM module are reserved for flash, PSRAM, USB D+/D−, or boot strapping and MUST NOT be
repurposed arbitrarily. These are **not** assigned functional roles here and are left as `RESERVED/UNUSED` in this
reference design. Refer to the ESP32-S3-WROOM-1 datasheet for the canonical list of reserved pins.
