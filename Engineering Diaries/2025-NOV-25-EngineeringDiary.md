# μBITz Engineering Diary

> Central engineering log for μBITz: decisions, constraints, rejected ideas, open questions.

---
## Decisions

* **Dock Management MCU**

  * Use **ESP32-S3-WROOM-1** as the Dock management MCU for the reference implementation.
  * Split firmware into:

    * **Core** (factory app): enumeration, address decoder/IRQ router programming, PD/power logic, monitor, personality flasher.
    * **Personality** (OTA app): Slot 0 Dock Services (RTC, power, HID shims, telemetry, etc.).
  * Builders are expected to modify **Personality** only; Core is treated as immutable in normal workflows.

* **Clock / RTC**

  * Use **RV-3028-C7** as the Dock RTC:

    * I²C interface.
    * Integrated crystal.
    * Very low backup current.
    * 3.3 V operation with coin cell on VBAT.

* **Power Domains**

  * Define two domains:

    * **Always-On (AON)**: ESP32-S3, RV-3028, PD controller logic, I²C pull-ups, service-port UART side.
    * **System**: Host, Banks, Tiles, USB hub + downstream ports, other heavy Dock logic.
  * System rails (5V_SYS / 3V3_SYS) are gated through FETs or load switches under Dock MCU control.

* **5 V Source Selection for AON**

  * AON input **5V_AON_IN** is fed by **diode-OR**:

    * VBUS_PD (from PD power port).
    * VBUS_PC (from service USB).
  * Use two Schottky diodes sized for AON current; either source can power AON.
  * System rails are powered **only** from the PD path, never from the PC’s 5 V.

* **USB Port Roles**

  * **Port A (USB-C)**: “Power + HID”

    * Used for **USB-C PD power entry** from a brick.
    * No data connection to ESP32-S3; used only for PD and power.
    * PD controller output feeds 5V_SYS and contributes to AON via diode-OR.
  * **Port B (USB)**: “Service”

    * Connected to a **USB-to-UART bridge** (FTDI/CP2102/CH340-class).
    * Provides a **serial monitor** and flashing path to the ESP32-S3.
    * PC VBUS may be OR’ed into 5V_AON_IN via a Schottky diode to allow PC-powered service mode.

* **USB Hub / HID**

  * Provide a 4-port USB 2.0 hub on the Dock so keyboard/gamepads do **not** consume a Tile slot.
  * Reference hub IC: **USB2514B** (4-port HS hub, self-powered).
  * ESP32-S3 USB OTG FS used **only in host mode**, connected to the hub’s upstream port.
  * Four downstream ports wired to front-panel USB-A connectors for HID devices.

* **Monitor & Flashing**

  * Service port uses a **USB-UART bridge**; ESP32-S3 sees a plain UART.
  * Core runs a **text monitor** over UART:

    * Status, enumeration, IRQ routing, power state, logs.
    * “Flash personality” mode that accepts hex-encoded firmware and writes only to the personality partition (with CRC/checks).
  * Monitor **refuses flashing** when system rails are on (active system); flashing is allowed only in service mode (rails off).

* **Slot 0 Dock Services — v1 Set**

  * Implement the following services in the initial Personality:

    * **RTC Service**: basic time/date + optional alarms.
    * **Power / Reset / Watchdog Service**: soft power control, boot/reset reason, Dock-level watchdog.
    * **HID Service**: USB HID → generic keycodes and/or legacy keyboard matrices (e.g. C64).
    * **System Health / Telemetry Service**: PD contract info, rail-good bits, basic temperature.
    * **Slot Inventory Service**: per-slot presence + type/class ID + simple capability flags.
    * **Interrupt Routing Introspection**: read-only view of IRQ channel → CPU line mapping and mask/pending snapshots.

## Constraints

* **Reference Only**

  * All of this is **reference implementation**, not a μBITz base-spec requirement.
  * Other Dock designs may use different MCUs, RTCs, hubs, or power entry schemes as long as the core Host/Dock/Tile contracts are respected.

* **MCU Platform**

  * MCU must:

    * Run robust Core firmware (enumeration, power, monitor).
    * Support a separate Personality partition that can be updated safely by builders.
    * Have USB host capability for HID (handled here by ESP32-S3).

* **Power**

  * PD controller must be able to:

    * Negotiate autonomously or from static config to bring up enough power for AON before MCU is fully active (no chicken-and-egg).
  * PC 5 V from the service port must **never** backfeed or power 5V_SYS / 3V3_SYS.
  * AON power budget must remain within what the diode-OR’ed 5 V sources and AON buck can safely supply.

* **Safety / Brick-Resistance**

  * Core firmware must be protected from accidental overwrite via monitor.
  * Personality flashing must be constrained to:

    * A known partition address range.
    * Explicit user actions (enter flash mode, send hex, CRC OK).
  * Flashing is disallowed while system rails are up.

* **Complexity vs Hobbyist Friendliness**

  * Prefer simple, understandable circuits:

    * Diode-OR instead of mandatory dedicated power mux IC.
    * UART-based monitor instead of complex multi-interface bootloader.
  * USB topology must be intuitive: one port for power/HID, one for debug.

## Rejected Ideas (with reasons)

* **Single USB-C for Both PD and Service (OTG Role Switching + Mux)**

  * Rejected because:

    * Requires USB 2.0 analog switch/mux for D+/D− routing between hub and PC.
    * Adds complexity in role management (host vs device) on ESP32-S3.
    * More chances for “two hosts on one bus” corner cases and user confusion.
  * Two physical connectors (PD+HID and Service) are clearer and safer.

* **Using ESP32-S3 USB Device Directly for Service Port**

  * Rejected because:

    * Increases firmware complexity (USB device stack, descriptors, DFU/CDC).
    * Ties flashing and monitoring to USB functionality of ESP32-S3 instead of simple UART.
    * Harder for hobbyists compared to a plain COM port over FTDI.

* **DS3231M / PCF8563 as RTC**

  * DS3231M:

    * Very user-friendly and accurate but **unnecessarily expensive** for Dock reference.
  * PCF8563:

    * Cheaper but requires external crystal and calibration considerations.
  * RV-3028 chosen instead: integrated crystal, low power, reasonable price.

* **Forcing Dock Services in the Platform Spec**

  * Rejected because:

    * The platform needs to remain flexible; not all Docks require advanced management.
    * Some builders may want bare-bones Docks without RTC, HID, or PD.
  * Dock Services remain **optional reference features**, not a base contract.

## Open Questions

* **Exact Slot 0 Register Map**

  * Need a separate, CPU-agnostic document that defines:

    * Register layout and bit fields for each v1 service.
    * How to handle endianness and alignment for 8-bit vs 16-bit vs 32-bit cores.

* **How Much PD We Standardize in the Reference**

  * Which PD controller to bless as the primary example (TPS25750 vs STUSB4500 vs something else).
  * How much PD status gets exposed into Slot 0 telemetry vs left internal to the Dock MCU.

* **Event / Fault Logging**

  * Whether to add a minimal persistent fault/event log in v1:

    * Storage location (AON flash vs Host-visible space).
    * Minimum entry format and capacity.

* **NMI / Panic Service**

  * How to standardize NMI/panic injection across different Host CPUs.
  * Whether this should be part of v1 Dock Services or reserved for v2 once more CPU boards exist.

* **Tile Firmware Update Service**

  * Whether Dock will eventually act as a universal programmer for Tiles.
  * What a simple, generic “Tile update” protocol would look like (sideband buses, addressing, versioning).

## Notes

* The “engineering diary” / daily Markdown summary format is a useful complement to the long conversational logs:

  * Captures **decisions and constraints** in a compact, project-ready way.
  * Makes it easier to see which ideas were **rejected and why**, without rereading entire chat transcripts.
  * Provides a natural place to accumulate **open questions** that can be turned into future design tasks or spec sections.
* The Dock Management MCU and services are shaping up to be a **soft southbridge**:

  * AON brain + PD + RTC + HID + slot inventory + health.
  * Personality layer gives builders a safe place to adapt Dock behavior to their target platform without risking the base management stack.



````markdown
# μBITz Dock — Reference Management & Power Architecture

> **Scope**  
> This document describes the **reference implementation** of the μBITz Dock “southbridge”:
> - Dock Management MCU (ESP32-S3)
> - Always-On vs System power domains
> - USB-C PD power entry
> - RTC
> - USB hub & HID attachment
> - Service/debug interface
> - Slot 0 Dock Services
>
> None of this is mandatory for the μBITz Platform spec. It is a **recipe** for builders.

---

## 1. High-Level Goals

- Provide a **Dock Management MCU** that:
  - Enumerates Host/Bank/Tiles and programs the address decoder & IRQ router.
  - Owns **Dock Services** as a virtual **Slot 0** device (RTC, power, HID, etc.).
  - Exposes a **monitor** for debug & manual firmware updates.

- Allow builders to:
  - Replace the **“personality”** firmware that implements Slot 0 behavior.
  - Keep a **small Core firmware immutable** (monitor, enumeration, flash writer).

- Power model:
  - USB-C PD used as the main **system power entry**.
  - Separate **Always-On (AON)** and **System** power domains.
  - Optional **hard power switch**, plus **soft power** logic (ATX-style).

- I/O:
  - On-Dock **USB hub** with 4 ports for keyboards/controllers.
  - **No Tile slot wasted** on basic keyboard I/O.
  - Dedicated **Service port** for monitor + flashing.

---

## 2. Dock Management MCU

### 2.1 Choice

- **Reference MCU:** **ESP32-S3-WROOM-1** module  
  - Dual-core Xtensa + USB OTG FS  
  - Integrated Flash + optional PSRAM  
  - 3.3 V operation  
  - USB host capable for HID via TinyUSB / ESP-IDF  
  - Wi-Fi/BLE present but **not required** by the platform; treated as optional extras.

### 2.2 Firmware Partitioning

Use the ESP32’s standard partition concept:

- **Bootloader**  
  Tiny, rarely touched.

- **Core application** (e.g. `factory` partition)
  - Dock enumeration & descriptor scanning.
  - Programming address decoder & IRQ router (CPLD/FPGA).
  - Power management logic (soft power, PD interaction).
  - UART/serial monitor (on a dedicated UART).
  - Flash writer for the personality partition.
  - Enforces safety rules (e.g., *no personality flashing while system rails are on*).

- **Personality application** (e.g. `ota_0`, possibly `ota_1`)
  - Implements Slot 0 Dock Services:
    - RTC access as host-visible registers.
    - Power control registers / events.
    - HID → host personality shims (C64, PC-style, etc.).
    - Optional extra services (telemetry, inventory, etc.).
  - Builders only replace this partition.

**Key rule:**  
Builder tooling and monitor commands are restricted to **personality partitions**; Core is immutable in normal workflows.

---

## 3. Power Architecture

### 3.1 Domains

- **Always-On (AON) domain**
  - Supplied from **5V_AON_IN → 3V3_AON buck**.
  - Includes:
    - ESP32-S3 Dock MCU
    - RTC (RV-3028)
    - USB-C PD controller logic
    - I²C pull-ups and light logic
    - Service-port FTDI’s UART side (if running at 3.3 V)

- **System domain**
  - Supplied from **5V_SYS → 3V3_SYS**.
  - Includes:
    - Host card, Bank card(s), Tiles
    - USB hub and downstream USB-A ports
    - Any heavy logic on the Dock

- **Isolation**
  - System rails are gated by **high-side FETs / load switches** controlled by the Dock MCU.
  - AON domain remains powered as long as a valid 5 V source exists.

### 3.2 Power Sources & OR-ing

Two possible 5 V sources:

- **VBUS_PD** – from USB-C PD port (Port A)
- **VBUS_PC** – from the PC on the Service port (Port B)

**AON input (5V_AON_IN):**

```text
VBUS_PD ----|>|----+
             D1    |
                   +---- 5V_AON_IN → AON buck → 3V3_AON
VBUS_PC ----|>|----+
             D2
````

* D1, D2: Schottky diodes sized for AON current.
* Either source can power the AON rail.
* If both are present, the higher voltage wins; no backfeed between sources.

**System rails:**

* **5V_SYS** comes **only** from the PD power path on Port A.
* **3V3_SYS** derived from 5V_SYS.
* PC’s 5 V from the Service port **never** feeds 5V_SYS.

### 3.3 Power Control

* **Hard power (optional)**

  * Mechanical switch in series with PD power path:

    * OFF → PD controller and AON buck unpowered (RTC stays on coin cell).
    * ON → PD + AON enabled.

* **Soft power**

  * Momentary **POWER button** wired to a Dock MCU GPIO.
  * Dock MCU controls:

    * System FET enable lines (turn system rails on/off).
    * Host reset/“power good” lines as needed.
  * Shutdown sequence:

    * Host requests power-down via Slot 0, or user presses POWER.
    * Dock MCU signals Host, waits for timeout, then opens system FETs.

---

## 4. USB Topology & HID

### 4.1 Ports Overview

* **Port A – “Power + HID” USB-C**

  * For **power entry via PD** (power brick).
  * No data connection to ESP32-S3 (data lines reserved for PD signalling / left unused for data).
  * Feeds PD controller → 5V_SYS and contributes to AON via diode OR.

* **Port B – “Service” USB**

  * Connected to a **USB-to-UART bridge** (FTDI/CP2102/CH340 or similar).
  * Provides **UART console** to the Dock MCU.
  * Optionally OR-fed into AON (as above) to allow **service-only power** from the PC.

* **Internal USB host**

  * ESP32-S3’s USB OTG FS used **only in host mode**.
  * Connects to the **upstream port of a 4-port USB 2.0 hub IC** on the Dock.

### 4.2 USB Hub IC

* **Reference choice:** Microchip **USB2514B** (4-port USB 2.0 HS hub)

  * One upstream port → ESP32-S3.
  * Four downstream ports → front-panel USB-A connectors.
  * Self-powered hub using 5V_SYS.
  * Config via strap pins / optional EEPROM, but can run in a simple default “generic hub” mode.

* **Alternatives:** Terminus **FE1.1s**, TI TUSB4041, etc.

### 4.3 Runtime vs Service Modes

* **Runtime (normal)**:

  * PD plugged into Port A; 5V_SYS and 3V3_SYS enabled.
  * ESP32-S3 running Core + Personality.
  * USB hub powered, HID devices enumerated by S3 (host).
  * Service port (Port B) may be connected; UART monitor is active but **flash commands are disabled** while system rails are on.

* **Service-only**:

  * Only Port B (PC) connected, or PD present but system rails left off.
  * 3V3_AON powered; system rails off; hub unpowered.
  * ESP32-S3 offers monitor only; safe to perform personality flashing.

---

## 5. Real-Time Clock

### 5.1 RTC IC

* **Reference choice:** **RV-3028-C7**

  * I²C interface, integrated crystal.
  * Very low backup current.
  * Good accuracy, reasonable cost.

### 5.2 Wiring

* **Power**

  * `VDD` → 3V3_AON.
  * `GND` → GND.
  * `VBAT` → coin cell (CR1220/CR2032) per datasheet’s recommended circuit.

* **I²C**

  * `SCL`, `SDA` on the Dock management I²C bus (3V3_AON, shared with FRU/PD, etc.).
  * Pull-ups to 3V3_AON.

* **Interrupt**

  * `INT`/`CLKOUT` pin → a dedicated ESP32-S3 GPIO.
  * Used for 1 Hz ticks and/or alarm events (scheduled power-on, wake events).

### 5.3 Core vs Personality Usage

* **Core firmware**

  * Provides basic read/write of RTC time/date.
  * May use alarms for scheduled power events.
  * Exposes a simple internal API for time access.

* **Personality firmware**

  * Maps RTC into Slot 0 register space in a platform-friendly way:

    * Simple linear registers, or
    * Emulated legacy RTC layouts (e.g., C64-style, PC-AT-style) as needed.

---

## 6. Service Port & Monitor

### 6.1 USB-to-UART Bridge

* **Service USB (Port B)**

  * Connected to a USB-UART IC (e.g. **FT230X / FT232R / CP2102 / CH340**).
  * The bridge is powered from **PC VBUS** on Port B and presents a COM port to the host PC.

* **UART connection**

  * UART TX/RX between bridge and ESP32-S3 (e.g. UART0).
  * Optional small series resistors on TX/RX to avoid back-powering the MCU when completely off.
  * Logic levels at 3.3 V.

### 6.2 Roles

* **Flashing Core (factory path)**

  * For advanced users: ESP32’s ROM bootloader is reachable via UART for Core updates (using `esptool.py` or similar).
  * Not part of regular builder workflow; considered “dangerous / last resort.”

* **Monitor**

  * A simple text-based monitor runs in Core:

    * Inspect enumeration tables, address windows, IRQ routes.
    * Query power state / PD status.
    * Print logs.
  * Accepts commands over UART.

* **Personality Firmware Upload**

  * Monitor command enters a “flash personality” mode when **system rails are off**.
  * User pastes **hex-encoded binary** (Intel HEX/S-record or custom format).
  * Monitor:

    * Restricts writes strictly to the personality partition address range.
    * Validates checksum/CRC.
    * Marks partition as valid and offers a reboot into the new personality.

### 6.3 Safety Rules

* If `rails_on == true` (Dock actively powering Host/Tiles):

  * Monitor **rejects** any flash/erase commands for personality.
  * Monitor remains available for status and safe debug only.

* If `rails_on == false` (service mode):

  * Flashing commands are allowed.
  * Monitor may require an explicit “arm” command to avoid accidental flashing.

---

## 7. Slot 0 Dock Services – Overview

Slot 0 represents a **logical Dock Services device** exposed to the Host through the normal μBITz I/O model. All services are implemented in the **Personality** firmware, but the hardware and Core are designed to support and feed them.

Conceptually, Slot 0 is a small set of **register banks**, each corresponding to a service class:

* RTC
* Power / Reset / Watchdog
* HID / Keyboard / Gamepad abstraction
* System Health / Telemetry
* Slot Inventory / Topology
* Interrupt Routing Introspection

A Host OS or bare-metal program can read and write these registers without caring about:

* The physical Dock MCU type,
* The exact USB HID devices attached, or
* The underlying PD / I²C / descriptor plumbing.

The following sections list **recommended v1 services** and **candidate v2 services**, along with a minimal register footprint and semantics. Exact bit layouts are deliberately left out here so they can be defined per-CPU in a separate “Dock Services Register Map” document.

---

## 8. v1 Dock Services (Recommended)

These are the services that make sense to ship in the **first reference Dock personality**.

### 8.1 RTC Service

**Purpose**

Expose calendar time and alarms to the Host via Slot 0.

**Minimum register set (conceptual)**

* Time/date registers:

  * Seconds / Minutes / Hours
  * Day / Month / Year
* Control:

  * Enable/disable 1 Hz tick
  * Alarm enable
* Alarm:

  * Alarm time/date fields

**Notes**

* Backed by RV-3028 hardware; Personality handles conversion between RV-3028 format and Slot 0 registers.
* Optional CPU-specific shims (e.g., C64-style layouts) live entirely in Personality.

---

### 8.2 Power / Reset / Watchdog Service

**Purpose**

Provide a Dock-level, host-agnostic power control and reset interface.

**Minimum register set (conceptual)**

* Status:

  * `BOOT_REASON` flags (POR, soft reset, watchdog, PD fault, over-temp, user button)
  * `POWER_STATE` (AON only / system on)
* Control:

  * `POWER_CMD` (request shutdown / restart)
  * `RESET_HOST` (optional, controlled host reset)
* Watchdog:

  * `WD_TIMEOUT` (write timeout value)
  * `WD_KICK` (write to kick)
  * `WD_STATUS` (expired flag, last expiry reason)

**Notes**

* Personality enforces policies like:

  * Only allow forced host resets when a “debug allowed” bit is set.
* Core collaborates with Personality for the actual rail/FET switching, but the Slot 0 facing map is Personality-owned.

---

### 8.3 HID / Keyboard / Gamepad Service

**Purpose**

Abstract one or more USB HID devices (via Dock hub) into a stable Slot 0 input model.

**Minimum register set (conceptual)**

* Input state:

  * Key matrix or keycode FIFO
  * Modifier flags (shift/ctrl/alt, etc.)
  * Gamepad button/axis values where applicable
* Control:

  * Input mode (e.g., “generic keycodes”, “C64 matrix mode”, etc.)
  * Poll vs interrupt configuration

**Notes**

* ESP32-S3 + hub enumerates:

  * USB keyboards
  * Gamepads / joysticks
  * Mice (optional for v1)
* Personality translates HID usages into:

  * A generic internal representation
  * Then into platform-specific views (C64, PC-AT, etc.) when requested.
* Host always sees the same Slot 0 registers regardless of actual HID models plugged in.

---

### 8.4 System Health & Telemetry Service

**Purpose**

Expose Dock-level power and thermal info without requiring the Host to implement PD/I²C directly.

**Minimum register set (conceptual)**

* PD contract:

  * Voltage (mV)
  * Current (mA)
  * Active PDO index / flags
* Rails:

  * `5V_SYS_GOOD`
  * `3V3_SYS_GOOD`
  * Brownout/over-current flags
* Temperature:

  * Dock MCU temperature reading
  * Optional board temperature (if external sensor present)

**Notes**

* All read-only.
* Lets minimal ROM/monitors make smarter decisions than “try and hope”.

---

### 8.5 Slot Inventory / Topology Snapshot

**Purpose**

Provide a pre-digested “what’s installed” view of the Dock slots.

**Minimum register set (conceptual)**

* For each slot (Host/Bank/Tiles):

  * Presence flag
  * Tile type/class ID
  * Short capabilities flags (e.g., “video”, “sound”, “storage”)
  * Optional small numeric ID / version

**Notes**

* Personality reads these from Dock’s descriptor cache (which Core built during enumeration).
* Exposed as a linear table so even a simple Host can scan it once and build a device list.

---

### 8.6 Interrupt Routing Introspection (Read-only)

**Purpose**

Let the Host and debugger see how Dock interrupt channels are mapped to CPU lines.

**Minimum register set (conceptual)**

* For each Dock IRQ channel:

  * Mapped CPU INT/NMI line
  * Mask bit snapshot
  * Pending bit snapshot

**Notes**

* v1: read-only. Configuration is done via config path (Core, CPLD, etc.).
* Later, a v2 service might allow controlled, runtime remapping through Slot 0.

---

## 9. v2 / Future Dock Services (Informative)

These are useful extensions but not required in the first reference implementation.

### 9.1 Event / Fault Log Service

* A small circular log in AON RAM/flash with entries like:

  * “PD OCP occurred”
  * “Watchdog reset, slot N active”
  * “Tile in slot X removed/inserted”
* Slot 0 exposes:

  * Log head/tail pointers
  * A simple “read next entry” interface

### 9.2 NMI / Panic Injection Service

* Slot 0 control bits to:

  * Trigger a CPU NMI/panic for debugging
  * Let Dock assert NMI on critical power/thermal fault
* Highly CPU-specific; left for later once multiple core boards exist.

### 9.3 Tile Firmware Update Service

* Dock as a generic programmer:

  * Host (or external tool via monitor) streams a firmware blob to Dock.
  * Dock pushes it into a Tile over a standardized sideband (I²C/SPI/UART).
* Needs a separate “Tile update protocol” spec; not v1 territory.

### 9.4 Randomness / Unique ID Service

* Provide:

  * Dock-level unique ID/serial (from ESP32 or EEPROM)
  * A basic random number source (from ESP32 RNG) via Slot 0
* Useful for small Hosts that lack their own RNG/ID story.

---

## 10. Implementation Notes for Builders

* The **ESP32-S3 + RV-3028 + PD + 4-port hub + FTDI** combination is a **reference** Dock recipe, not a requirement.
* Variations are allowed as long as:

  * Host/Dock/Tile contracts from the μBITz spec are respected.
  * Slot 0 Dock Services (if present) behave as documented at the register level.
* Builders can:

  * Keep the Core firmware as-is and only customize Personality.
  * Or fork Core as well, provided they understand the risks (e.g., bricking Dock management).
* Nothing in this document changes the **μBITz base contracts**; it only standardizes **one concrete, hackable Dock implementation** others can clone, cut down, or supersize.

```
```
