# μBITz Dock Digital System Architecture

> High-level digital and logical design for the reference μBITz Dock — how the Dock MCU, CPLD, I²C fabric, service UART and USB HID hub cooperate to implement the Core logical model.

---

## 1. Goals & Scope

This document defines the **digital subsystem architecture** for the reference μBITz Dock. It sits alongside the Dock Power System Architecture and the Core / Dock specifications.

### 1.1 Goals

The reference Dock digital subsystem should:

- Implement the **Core logical model** (Part 1) on the backplane side:
    
    - Address decode and `/CS[n]` generation.
        
    - `/READY` stretching and cycle bounding.
        
    - Per-slot interrupt routing and Mode-2-style acknowledge.
        
- Present the Dock’s own logic (RTC, USB HID hub, power control, etc.) as a **normal μBITz Tile**, using a reserved **Virtual Slot 0**.
    
- Centralize **enumeration and configuration** in a Dock MCU so that:
    
    - The same Dock can support many CPU boards and platforms.
        
    - The decode / IRQ fabric is configured from descriptors instead of hardwired.
        
- Provide a robust **service monitor** path over USB → FTDI → UART for:
    
    - First-time MCU bring-up.
        
    - Flashing test firmware.
        
    - User monitor functions (uploading HEX/S-records, diagnostics).
        
- Leave the **Host and Bank pinouts symmetric** and keep the Dock logic agnostic to which one is in which Core slot.
    

### 1.2 Out of scope

This document does **not** specify:

- Tile-internal architectures (VDP, Sound, IO Tiles, etc.).
    
- CPU or Bank internals.
    
- Analog power conversion and protection (see Dock Power System Architecture).
    
- Exact MCU firmware APIs or Tile register maps (those get their own specs).
    

---

## 2. Top-Level Digital Block Diagram

Conceptually, the Dock digital subsystem looks like this:

```text
                 ┌────────────────────────────────────┐
                 │             μBITz Dock             │
                 │                                    │
                 │  ┌──────────────┐   cfg_*   ┌────┐ │
CPU Board  ⇄ Bus │  │   Dock MCU   │──────────│CPLD│─┼─► /CS[0..N]
(Host)     ======│  │ ESP32-S3     │   via    │Mach│ │
                 │  │  (Tile #0)   │ MCP23017 │XO2 │─┼─► INT routing
                 │  └──────┬───────┘  (§4.5)  └────┘ │
                 │         │   ▲                     │
                 │   UART  │   │ I²C ch.0..7         │
PC (service) ─USB─► FT232R ┘   │ via TCA9548A        │
                 │             │                     │
                 │     Dock-local I²C devices        │
                 │   (RTC, PD, GPIO expander,        │
                 │    USB hub ctrl, FRU, etc.)       │
                 │             │                     │
                 │   Slot 1 I²C ─────────► Tile 1    │
                 │   Slot 2 I²C ─────────► Tile 2    │
                 │   Slot 3 I²C ─────────► Tile 3    │
                 │   Slot 4 I²C ─────────► Tile 4    │
                 └────────────────────────────────────┘
```

- The **Host CPU bus** terminates at the Dock via the Core connector and a set of data-bus transceivers (physically located near the Host board). The Dock CPLD sees the logical Core signals (`A[]`, `/IORQ`, `R/W_`, `/CPU_ACK`, interrupt pins, etc.).
    
- The **CPLD** implements `addr_decoder` and `irq_router` and exposes a virtual Tile interface to the Dock MCU (Virtual Slot 0).
    
- The **Dock MCU** is the I²C master for the entire platform, configures the CPLD via a GPIO expander, and exposes Dock services as a Tile.
    
- A **TCA9548A I²C switch** provides per-slot I²C segments so multiple boards can reuse the same descriptor address ranges without conflict.
    
- An **FT232R-class USB–UART bridge** gives the PC a reliable console path into the Dock MCU.
    

---

## 3. Relationship to Core & Dock Specifications

- The **Core Logical Specification** defines:
    
    - The logical signals (`/IORQ`, `R/W_`, `A[]`, `D[]`, `/READY`, `/CS[n]`, `/CPU_INT[]`, `/CPU_NMI[]`, `/CPU_ACK`, `INT_CH[]`, `NMI_CH`, `INT_ACK`).
        
    - Cycle semantics and `/READY` behavior.
        
    - The CPU descriptor (`WindowMap[]`, `IntRouting[]`) and enumeration concepts.
        
- The **Dock Specification** states that:
    
    - The Dock is responsible for address decode, bus arbitration, and interrupt routing.
        
    - The Dock may contain active logic (MCU, CPLD) to implement this behavior.
        

This **Dock Digital System Architecture** describes one concrete implementation:

- A **MachXO2 CPLD** that implements `addr_decoder` and `irq_router`.
    
- An **ESP32-S3 Dock MCU** that:
    
    - Reads platform descriptors over I²C.
        
    - Translates them into the configuration tables expected by the CPLD.
        
    - Exposes the Dock’s own features as a standard μBITz Tile (Virtual Slot 0).
        

---

## 4. Major Digital Components

### 4.1 Dock MCU — ESP32-S3-WROOM

**Role:** system supervisor, I²C master, Dock Services Tile, CPLD configuration engine.

Key responsibilities:

1. **I²C master for enumeration and control**
    
    - Drives a single I²C bus to a **TCA9548A 1→8 switch**.
        
    - Uses that to reach:
        
        - Dock-local devices: RTC, PD controller, USB hub control endpoint, GPIO expander, Dock FRU, any power / status logic.
            
        - Host CPU I²C EEPROM (CPU descriptor, configuration).
            
        - Bank I²C EEPROM (Bank descriptor).
            
        - Tile I²C EEPROMs (one per physical slot).
            
2. **Configuration of the CPLD**
    
    - Drives the `addr_decoder_cfg` and `irq_router_cfg` ports via a **low-speed parallel config bus** implemented on a dedicated **MCP23017 I²C GPIO expander** (see §4.5).
        
    - The underlying logical ports remain:
        
        - `addr_decoder_cfg`: address/decode window table writes.
            
        - `irq_router_cfg`: interrupt routing table writes.
            
    - The **physical pins** for these config ports are sourced from the expander rather than direct MCU GPIO, so the HDL does not need to change.
        
    - At boot, the MCU:
        
        - Reads the CPU’s `WindowMap[]` and `IntRouting[]` tables from the CPU descriptor.
            
        - Reads each Tile’s descriptor and the Bank descriptor.
            
        - Builds a concrete, per-slot **window table** and **interrupt routing table**.
            
        - Writes those tables into the CPLD via the expander-backed config bus.
            
    - Because all config writes are **boot-time only** (and the system is held in reset until configuration completes), the extra latency of the I²C expander is acceptable and does not affect runtime performance.
        
3. **Dock Services Tile (Virtual Slot 0)**
    
    - Appears to the Host as a standard μBITz Tile:
        
        - 8-bit data bus (`D[7:0]`).
            
        - Small address sub-bus (nominally **4 bits**, enough for 16 registers; can be extended in future revisions).
            
        - `/CS_0` (virtual slot 0 chip-select) from CPLD.
            
        - Shared `R/W_` and `/READY` semantics identical to any other Tile.
            
    - Provides Dock-level features via its register map (to be defined in a separate Dock Services spec), including:
        
        - RTC access (read/write date/time, alarms, coarse monotonic time).
            
        - PD / power status (current contract, rail-good summaries, soft power state).
            
        - USB HID hub status (which ports have devices, basic device type flags).
            
        - Optional GPIO or debug status for Dock signals.
            
        - Optional “enumeration view” registers giving the Host a summary of discovered devices.
            
    - For representative HID-related Slot 0 register usage, see **§7.6**.
        
4. **Service monitor endpoint**
    
    - Connects to an **FT232R-class USB–UART** bridge:
        
        - MCU `UARTx_TX` ↔ FT232 `RXD`.
            
        - MCU `UARTx_RX` ↔ FT232 `TXD`.
            
        - MCU `UARTx_RTS` ↔ FT232 `CTS`.
            
        - MCU `UARTx_CTS` ↔ FT232 `RTS`.
            
    - Exposes a text/binary monitor over a separate **Service USB** connector.
        
    - Supports reliable uploads of HEX and S-record files using RTS/CTS flow control so that user mistakes or long transfers do not corrupt uploads.
        
5. **Optional CPLD bitstream update**
    
    - Hardware provisions a path from the MCU to the MachXO2’s configuration interface (e.g., I²C sysCONFIG or shared JTAG pins) so that future firmware can reprogram the CPLD bitstream in-system.
        
    - v1 firmware may ship without this implemented; the hardware simply ensures the signals are available.
        

#### 4.1.4 GPIO Budget and Direct vs. Expander Lines

The ESP32-S3 has a finite number of usable GPIOs once USB, flash, and strapping pins are reserved.  
To keep the design within budget while still exposing a rich Dock feature set, GPIOs are split into:

- **Timing-sensitive / high-priority signals → direct GPIO**
    
- **Boot-time / low-rate configuration signals → MCP23017 I²C GPIO expander (see §4.5)**
    

At architecture level, the budget closes as follows (numbers are approximate and finalized in the dedicated pin-map document):

- **Direct ESP32-S3 GPIOs (~29 used):**
    
    - **Virtual Slot 0 local bus (~18 lines)**
        
        - Data, local address, `/CS_0`, `/READY_0#`, `INT_CH[1:0]`, `NMI_CH`, plus a small margin.
            
        - These participate directly in I/O cycles and `/READY` stretching, so they **must** be direct.
            
    - **I²C master (~2 lines)**
        
        - `I2C_MCU_SCL`, `I2C_MCU_SDA` → upstream to TCA9548A.
            
        - Lives on **3V3_AON** so enumeration remains available whenever the Dock MCU is alive.
            
    - **Service UART with flow control (~4 lines)**
        
        - `UART_MON_TX`, `UART_MON_RX`, `UART_MON_RTS`, `UART_MON_CTS` → FT232R.
            
        - Required for robust HEX/S-record uploads (RTS/CTS).
            
    - **Power control and status (~3 lines)**
        
        - `MAIN_ON_REQ` (MCU → power sheet).
            
        - `PG_5V_MAIN`, `PG_3V3_MAIN` (power-good inputs to MCU).
            
    - **Debug / status (~2 lines)**
        
        - Optional debug LEDs, test mux, or trace pins.
            
    - **Spare margin (~3 GPIOs)**
        
        - Reserved for future features or board-spin fixes.
            
- **Low-rate configuration & slow control (via MCP23017, 13 bits used):**
    
    - **CPLD config bus signals** (addr/data strobes and bus) driven through the expander.
        
    - Any additional slow Dock-local “strap” or debug lines that can tolerate 100s of µs latency.
        

Key properties:

- **No timing-critical signals** are placed behind the expander.
    
- The **MCU→CPLD logical interface** (window tables and IRQ routing) is unchanged; only the physical fan-out is different.
    
- The Dock can still hold the entire system in reset until all expander-backed config writes complete, so the slower bus is architecturally safe.
    

Exact ESP32-S3 pin numbers for each function are defined in the separate  
`esp32s3_gpio_assignments.md` document; this section only fixes the **categories and counts** so schematic capture and layout have a clear target.

---

### 4.2 Dock CPLD — LCMXO2-4000HC

**Role:** stateless bus fabric and interrupt router.

Implemented HDL blocks:

- `addr_decoder` – matches I/O cycles to windows and asserts `/CS[n]` and `/READY`.
    
- `irq_router` – routes per-slot interrupt lines to CPU interrupt pins and handles Mode-2 acks.
    

Sizing and utilization (reference build): synthesis of `addr_decoder` + `irq_router` with the reference parameters  
(ADDR_W = 32, NUM_WIN = 16, NUM_SLOTS = 5, NUM_TILE_INT_CH = 2, NUM_CPU_INT = 4, NUM_CPU_NMI = 2) produces on the  
order of ~2.3k LUTs and ~80 I/Os. This _does not_ fit in an XO2-1200 device, but is well within the capacity of the  
LCMXO2-4000HC (4k LUTs, 144-pin TQFP), leaving comfortable margin for small future extensions.

The CPLD powers up from its internal non-volatile configuration, providing a safe default mapping (e.g., all windows  
disabled). The Dock MCU is responsible for writing real configuration tables (via the MCP23017-backed config bus) before the Host begins normal I/O.

### 4.3 FTDI USB–UART Bridge — FT232R

**Role:** bidirectional USB-to-UART bridge for Dock monitor and first-time MCU access.

- Upstream: connected to the **Service USB** Type-B or Type-C connector.
    
- Downstream: connected to one UART on the ESP32-S3, with full RTS/CTS handshaking.
    
- Optionally:
    
    - `DTR` and `RTS` pins may be wired (via small transistors) to the MCU’s `EN` and `BOOT` pins to support automated entry into the ROM bootloader for flashing.
        
    - A small jumper or solder bridge can disconnect these for safety once development stabilizes.
        

### 4.4 USB HID Hub (Summary)

**Role:** aggregate front-panel USB HID devices and make them available to the Dock MCU.

- A multi-port USB 2.0 hub is placed on the Dock:
    
    - Upstream port connects to the **Dock MCU’s USB OTG** interface (host mode).
        
    - Downstream ports connect to USB-A (or USB-C) panel connectors for keyboard, mouse, gamepads, etc.
        
- The Dock MCU runs USB host firmware to:
    
    - Enumerate HID devices.
        
    - Translate their events into Tile-accessible registers or messages exposed through the Dock Services Tile.
        

**Details of the USB hub implementation are described in full in §7.**

### 4.5 GPIO Expander — MCP23017

**Role:** Provide additional low-speed GPIOs for the CPLD configuration bus and other slow Dock-local signals, reducing pressure on the ESP32-S3’s direct GPIO budget.

The reference design uses an **MCP23017**:

- 16-bit I²C GPIO expander (2×8-bit ports: GPA[7:0], GPB[7:0]).
    
- Operates at 3.3 V (`+3V3_AON`).
    
- Standard 100–400 kHz I²C interface.
    

#### 4.5.1 Placement in the I²C Fabric

- The MCP23017 resides on the **Dock-local I²C segment** (TCA9548A **channel 0**, see §8.1).
    
- It shares that segment with other Dock-local devices:
    
    - RTC (RV-8523-C3)
        
    - Dock FRU EEPROM
        
    - PD controller / power monitors
        
    - USB hub control endpoint (if any)
        
    - Optional MachXO2 sysCONFIG I²C interface
        

I²C details:

- Address pins (`A0–A2`) strapped to a fixed Dock-local value (e.g., `0b000` → `0x20`).
    
- All lines use the **MCU-side pull-ups** on SCL/SDA (no extra pull-ups required if trace length is modest).
    

#### 4.5.2 Signals Driven Through the Expander

The MCP23017’s GPIO bits are allocated to slow, non-timing-critical signals, primarily:

- **CPLD configuration bus:**
    
    - Address and data lines used to program:
        
        - `addr_decoder_cfg` tables (window base/mask/OP).
            
        - `irq_router_cfg` tables (function/instance/channel → CPU INT/NMI).
            
    - Strobe/enable lines for the configuration FSM(s) in the CPLD.
        
- **Misc. slow Dock-local controls** (optional):
    
    - Board “straps” or mode selects that are only sampled at boot.
        
    - Debug LEDs or test mux selects.
        

In the current reference allocation:

- **13 of 16 bits** are assigned to CPLD config and related slow controls.
    
- **3 bits** remain reserved for future use (spare debug, extra config selects, etc.).
    

The **logical interface** is defined in `DECODER_CONFIGURATION.md` and the Verilog modules; this document only fixes the fact that **MCP23017 bits are the physical drivers** for those config pins.

#### 4.5.3 Timing and Reliability Considerations

- All expander-driven signals are **boot-time only**:
    
    - The Dock MCU uses the MCP23017 to push configuration tables into the CPLD.
        
    - The system remains in reset while these writes are performed.
        
    - Normal Host I/O cycles do not depend on the expander.
        
- Typical timings:
    
    - At 400 kHz I²C and short wires, a single 16-bit port write is on the order of **tens of µs**.
        
    - A complete configuration sequence (all windows + interrupt routes) fits well within **a few ms** even with conservative firmware.
        
- If the expander fails or is missing:
    
    - The CPLD remains in its **safe default** configuration.
        
    - The Dock MCU can detect the fault (I²C errors) and refuse to release system reset, preventing undefined behavior on the bus.
        

#### 4.5.4 Power Domain and Reset

- The MCP23017 is powered from **`+3V3_AON`**, matching the Dock MCU’s always-on domain:
    
    - Ensures the expander is available as soon as the MCU boots.
        
    - Allows future low-power modes where MAIN rails are off but Dock logic is still alive.
        
- Reset behavior:
    
    - The expander resets to all pins as inputs with weak pull-ups.
        
    - The CPLD must treat “all-inputs/high-Z” on its config pins as “no configuration yet” and stay in a safe state until valid patterns arrive.
        

---

## 5. CPU ↔ Dock Bus Interaction

### 5.1 Logical view

From the CPU’s point of view, the Dock is a pure backplane:

- It presents:
    
    - `A[AddressBusWidth-1:0]`, `D[DataBusWidth-1:0]` (via Host-side transceivers).
        
    - `/IORQ`, `R/W_`, `/READY`, `/RESET`.
        
    - `CPU_INT[3:0]`, `CPU_NMI[1:0]`, `/CPU_ACK`.
        
- The CPU card synthesizes `/IORQ` and publishes its **CPU Descriptor** on the enumeration bus.
    

The Dock CPLD:

1. **Receives each I/O cycle** where `/IORQ=0`.
    
2. **Matches the address** against its internal window table (BASE/MASK/OP for up to 16 windows).
    
3. **Selects a slot** for the winning window and asserts exactly one `/CS[n]=0`.
    
4. **Pulls `/READY` low** at the start of the cycle.
    
5. **Waits for the selected slot** to release its own `slot_ready_n[n]` line.
    
6. **Releases `/READY` high**, at which point the CPU can complete the cycle.
    

This behavior is identical regardless of whether the selected slot is:

- A physical Tile (Slots 1..N), or
    
- The Dock Services Tile (Virtual Slot 0 implemented by the MCU).
    

### 5.2 Data bus transceivers

To keep the Host bus safe and clean:

- The Host board implements a bank of bidirectional **data transceivers** between the CPU’s data bus and the Dock’s data bus.
    
- These transceivers are enabled only during valid I/O cycles where the CPLD has asserted a slot `/CS[n]`.
    
- Outside I/O cycles, or during memory cycles (`/MREQ` only), the Dock side of the data bus is effectively disconnected from the CPU.
    

The Dock digital subsystem assumes:

- When a Tile slot’s `/CS[n]` is active, the corresponding data bus lanes are live and follow the normal Core semantics.
    
- When no `/CS[n]` is active, the Dock does not drive the data bus at all.
    

---

## 6. Virtual Slot 0 — Dock Services Tile

### 6.1 Motivation and slot numbering

- Physical Tile slots are currently numbered **1..4** on the reference Dock.
    
- Slot numbering for users and builders should remain intuitive even if future Dock designs add more slots.
    
- The Dock itself always exists and always provides system services.
    

To avoid a “mystery Slot 5” in the middle of the slot range, the Dock reserves **Virtual Slot 0** for its own services:

- Slot 0: **Dock Services Tile** (implemented by the Dock MCU).
    
- Slots 1..N: Physical Tile connectors.
    

### 6.2 Electrical interface

The Dock MCU connects to the CPLD as if it were a Tile on Slot 0:

- `D[7:0]` Dock-side data bus (8-bit)
    
- `A_local[3:0]` local register address (nominally 4 bits, with room to expand).
    
- `/CS_0` – slot-0 chip-select from CPLD.
    
- `R/W_` – shared read/write signal.
    
- `/READY_0` – Dock MCU’s per-slot ready output, combined into the global `/READY` by the CPLD.
    

This ensures that:

- From the Host’s perspective, **all Tiles look the same**, including the Dock.
    
- No special “Dock register space” has to be hard-coded in the CPLD.
    

### 6.3 Register map (high-level categories)

The exact register layout is defined in a dedicated **Dock Services Tile** specification, but at a high level the categories are:

1. **Identification & status**
    
    - Tile descriptor fields (class, vendor, product, revision).
        
    - Dock firmware version.
        
    - Basic health summary (rails OK, MCU uptime, watchdog flags).
        
2. **RTC access**
    
    - Read/write date/time.
        
    - Optional alarms or periodic tick configuration.
        
3. **Power & soft control**
    
    - Soft power state (on/off / sleep request).
        
    - Shutdown reason codes (power fault, user request, watchdog, etc.).
        
    - Hooks into the PD/power controller state machine (read-only or limited control).
        
4. **USB HID hub status**
    
    - Presence bits for each downstream port.
        
    - Basic decoded class/type flags (keyboard, mouse, gamepad, other).
        
    - Optional small event FIFO for queued HID events.
        
5. **Debug & configuration**
    
    - Read-only views into the CPLD configuration (e.g., window/route snapshots).
        
    - Optional controls for tracing / logging.
        

See **§7.6** for an example of how HID-related status and events are exposed via Slot 0 registers.

---

## 7. USB HID Hub

### 7.1 Overview and Role

The μBITz Dock includes an integrated **USB 2.0 hub** to provide front-panel HID (Human Interface Device) connectivity. This allows users to connect keyboards, mice, gamepads, and other USB HID peripherals directly to the Dock, making them accessible to the Host CPU through the Dock MCU's services interface (Virtual Slot 0).

#### 7.1.1 Design Philosophy

The USB hub serves several purposes in the μBITz ecosystem:

- **Retro-friendly input**: Modern USB keyboards/mice can be translated by the Dock MCU into formats suitable for vintage CPU architectures (PS/2-style scancodes, joystick port bits, etc.)
    
- **Centralized HID management**: The Dock MCU acts as an intelligent intermediary, handling USB enumeration and protocol complexity so the Host CPU sees only simple register-based I/O
    
- **Expandability**: Multiple HID devices can be connected simultaneously, with the Dock MCU arbitrating access and presenting combined state to the Host
    
- **Boot-time convenience**: USB devices are available immediately at power-on without requiring Host software drivers
    

#### 7.1.2 Out of Scope

The following are **not** goals for the USB hub subsystem:

- **Mass storage**: USB flash drives, hard disks, and other storage devices are not supported in the reference Dock design (future Tiles may add this)
    
- **USB-to-serial adapters**: The service UART (FT232R) is the primary path for PC communication; USB-serial on the HID ports would be redundant
    
- **High-speed USB**: Only USB 2.0 Full Speed (12 Mbps) is required; Hi-Speed (480 Mbps) is unnecessary for HID devices
    
- **Arbitrary USB devices**: Only HID-class devices (keyboards, mice, gamepads) are guaranteed to work; other device classes may or may not enumerate
    

---

### 7.2 System Architecture

#### 7.2.1 Signal Flow

```text
┌─────────────────────────────────────────────────┐
│                  μBITz Dock                     │
│                                                 │
│   ┌──────────────────┐      USB D+/D−          │
│   │   Dock MCU       │◄──────────────┐         │
│   │   ESP32-S3       │                │         │
│   │                  │        ┌───────▼──────┐  │
│   │  (USB OTG Host)  │        │   GL850G     │  │
│   │   GPIO19/20      │        │   USB Hub    │  │
│   └────────┬─────────┘        │   (4-port)   │  │
│            │                  └───┬──┬──┬──┬─┘  │
│            │ HUB_RESET#           │  │  │  │    │
│            └──────────────────────┘  │  │  │    │
│                                      │  │  │    │
│   Front Panel Connectors:            │  │  │    │
│   ┌──────────────────────────────────▼──▼──▼──┐ │
│   │  [USB-A/C] [USB-A/C] [USB-A/C] [USB-A/C]  │ │
│   │    Port 1    Port 2    Port 3    Port 4   │ │
│   └───────────────────────────────────────────┘ │
│                                                 │
│   Power: +5V_MAIN (from Dock power subsystem)  │
└─────────────────────────────────────────────────┘

User connects:
  - USB keyboard → Port 1
  - USB mouse   → Port 2
  - USB gamepad → Port 3/4
  
MCU enumerates devices, parses HID reports, presents state via
Slot 0 registers to Host CPU (e.g., Z80 reads scancode from I/O port).
```

#### 7.2.2 Upstream Connection

**ESP32-S3 USB OTG Interface:**

- **Pins:** GPIO19 (USB D−), GPIO20 (USB D+) — hardwired in ESP32-S3-WROOM module
    
- **Mode:** USB OTG in **Host mode** (MCU is the bus master)
    
- **Speed:** USB 2.0 Full Speed (12 Mbps)
    
- **Power:** 3.3V I/O levels (internal to ESP32-S3); hub interface operates at 3.3V logic
    

**Physical Connection:**

- Differential pair USB D+/D− routed from ESP32-S3 GPIO19/20 to GL850G upstream port
    
- **Impedance:** 90Ω differential (USB 2.0 spec requirement)
    
- **Routing:** Keep D+/D− traces matched length (±5 mil), avoid vias/splits, reference to solid ground plane
    
- **Termination:** GL850G has internal 1.5kΩ pull-up on D+ for Full Speed signaling
    

#### 7.2.3 Downstream Ports

**GL850G 4-Port Hub:**

- **Chip:** Genesys Logic GL850G (or compatible: FE1.1s, TUSB2046B)
    
- **Package:** SSOP-28 (hand-solderable, 0.65mm pitch)
    
- **Ports:** 4× independent downstream USB 2.0 ports
    
- **Speed:** Full Speed (12 Mbps) per port; Low Speed (1.5 Mbps) supported for legacy mice
    
- **Power:** Operates from single +3.3V rail (VDD33); downstream ports powered from +5V_MAIN
    

**Physical Connectors:**

- **Connector type (builder's choice):**
    
    - **Option A:** 4× USB-A receptacles (traditional, bulky, robust)
        
    - **Option B:** 4× USB-C receptacles (modern, compact, data-only wiring)
        
    - **Option C:** Mixed (2× USB-A + 2× USB-C)
        
- **Placement:** Front panel of Dock enclosure for user accessibility
    
- **Pinout (per port):**
    
    - VBUS: +5V_MAIN (via shared protection, see §7.4)
        
    - D+, D−: Differential pair from GL850G downstream port
        
    - GND: Dock ground
        
    - (USB-C: CC pins tied to GND via 5.1kΩ for UFP advertisement, no PD)
        

---

### 7.3 Control and Reset

#### 7.3.1 Hub Reset Signal

**Signal:** `HUB_RESET#` (active-low)

- **Source:** Dock MCU GPIO output (exact GPIO assigned in GPIO allocation, see §12.1)
    
- **Destination:** GL850G pin 2 (RESET#)
    
- **Function:** Hardware reset for GL850G hub chip
    
- **Pull-up:** 10kΩ to +3.3V at GL850G (ensures hub stays in reset if MCU GPIO is tri-stated)
    

**Reset Sequence:**

1. At Dock power-on, MCU firmware initializes with `HUB_RESET# = 0` (hub held in reset)
    
2. MCU waits for +3.3V_AON and +5V_MAIN to stabilize (polls `PG_*` signals)
    
3. MCU asserts `HUB_RESET# = 1` (release GL850G from reset)
    
4. GL850G enumerates on ESP32-S3 USB host stack (~100–200 ms)
    
5. MCU begins polling for downstream HID device connections
    

**Firmware Control:**

- MCU can re-assert `HUB_RESET# = 0` to force hub re-enumeration if:
    
    - USB stack crashes or hangs
        
    - Overcurrent condition detected on downstream ports
        
    - User requests hub reset via Monitor service command
        

#### 7.3.2 Per-Port Power Control

**Design Decision: Simplified Power Model**

The reference Dock **does not implement** individual per-port power switching (no `PWREN1..4` control). This simplifies the design:

- **All 4 downstream ports** share a single +5V_MAIN power rail
    
- **Advantage:** Reduces MCU GPIO count (−4 pins), simpler schematic, lower BOM cost
    
- **Trade-off:** Cannot disable a single misbehaving port; entire hub must be reset via `HUB_RESET#`
    

**Rationale:**

- HID devices (keyboards, mice, gamepads) typically draw <100 mA per device
    
- Shared current limit of 2A for all 4 ports (500 mA per port, per USB 2.0 spec) is adequate
    
- Overcurrent protection is implemented at the rail level, not per-port (see §7.4)
    

**Future Extension:**

- Builders who need per-port control can add:
    
    - Load switches (e.g., TPS2051B) on each downstream VBUS line
        
    - 4 additional MCU GPIOs to drive power-enable pins
        
    - Firmware to monitor per-port current and selectively disable faulty ports
        
- This is not included in the reference design to keep GPIO budget under control
    

---

### 7.4 Power Distribution and Protection

#### 7.4.1 Power Rails

**GL850G Supply:**

- **VDD33 (pin 14):** +3.3V from Dock 3V3_MAIN rail
    
- **Current:** ~30 mA typical (hub logic only, not including downstream devices)
    
- **Decoupling:** 0.1 µF ceramic (close to VDD33 pin) + 10 µF tantalum bulk (shared with nearby 3.3V devices)
    

**Downstream Port Power:**

- **VBUS (per port):** +5V_MAIN from Dock power subsystem
    
- **Total budget:** 2A shared across all 4 ports (conservative; USB 2.0 allows 500 mA × 4 = 2A max)
    
- **Source:** Dock +5V_MAIN rail (buck regulator output, see Power Architecture)
    

The **Dock Power System Architecture** **MUST** budget at least **2 A** on the +5V_MAIN rail for the USB hub downstream ports (4 × 500 mA), in addition to any other +5V loads.

#### 7.4.2 Overcurrent Protection Strategy

**Shared Rail Protection:**

- A single **eFuse or resettable PPTC fuse** protects the entire USB hub +5V rail:
    
    - **Hold current:** 2.0 A (allows 4 ports × 500 mA)
        
    - **Trip current:** 3.0 A (fast trip on short circuit)
        
    - **Suggested part:** Bourns MF-MSMF200-2 (PPTC, 2A hold, 4A trip, 1812 package)
        
- **Placement:** Between +5V_MAIN rail and GL850G VBUS distribution point
    

**Per-Port Inline Resistance (Optional):**

- Small series resistors (0.1–0.5Ω, 0.5W) on each port's VBUS can provide:
    
    - Current sensing (voltage drop ∝ current)
        
    - Minor isolation (prevents one shorted port from instantly collapsing others)
        
- **Not required in reference design** but can be added by builders for debugging
    

**ESD Protection:**

- Each downstream D+/D− pair gets a **dual TVS diode** (USB-specific):
    
    - **Suggested part:** USBLC6-2SC6 (SOT-23-6, low capacitance, 6V clamp)
        
    - **Placement:** As close as possible to USB connector, between D+/D− and GND
        
- **VBUS ESD:** 15V unidirectional TVS on each downstream VBUS line (e.g., SMAJ5.0A)
    

#### 7.4.3 Fault Handling

**Overcurrent Scenario:**

1. User connects faulty USB device or creates short circuit on port
    
2. PPTC fuse heats up and increases resistance, limiting current to ~3A
    
3. +5V rail droops slightly; all 4 ports lose power
    
4. MCU detects +5V rail issue (optional: via ADC monitoring `PG_5V_MAIN`)
    
5. MCU asserts `HUB_RESET# = 0` to disable hub, waits for PPTC cool-down (~10s)
    
6. MCU logs fault event, optionally signals Host via Slot 0 status register
    
7. MCU releases `HUB_RESET# = 1` to retry enumeration
    

**No Automatic Recovery in v1.0:**

- Reference firmware does **not** implement automatic retry loops (avoids thermal runaway if fault persists)
    
- User must power-cycle Dock or issue Monitor command to reset hub
    

**Future Enhancement:**

- Add per-port current sensing (via inline shunt resistors + ADC)
    
- MCU firmware identifies which port caused overcurrent
    
- If per-port switches are added, disable only the faulty port
    

---

### 7.5 HID Device Enumeration and Protocol

#### 7.5.1 USB Host Stack on ESP32-S3

**Firmware Framework:**

- **ESP-IDF USB Host library** (built-in to ESP32-S3 SDK)
    
- Supports USB 2.0 enumeration, descriptor parsing, HID report parsing
    
- **Class drivers:** ESP-IDF includes HID class driver for keyboards, mice, generic HID
    

**Enumeration Flow:**

1. GL850G enumerates as a hub on MCU's USB bus
    
2. MCU issues hub-specific commands to query downstream port status
    
3. When user plugs device into port 1–4, GL850G signals port connect event
    
4. MCU enumerates device (GET_DESCRIPTOR, SET_CONFIGURATION)
    
5. MCU reads HID report descriptor to understand device capabilities
    
6. MCU begins polling device for HID reports (typically 8–125 Hz depending on device)
    

#### 7.5.2 Supported HID Device Types

**Guaranteed Support (v1.0 firmware):**

- **USB Keyboards:** Boot protocol (6-key rollover + modifiers) and Report protocol
    
- **USB Mice:** 3-button + scroll wheel, relative motion (X/Y deltas)
    
- **USB Gamepads:** Generic HID gamepad profile (buttons, analog sticks, D-pad)
    

**Partial Support (depends on device conformance):**

- **Joysticks:** Treated as gamepads if they use standard HID gamepad report format
    
- **Trackpads/Touchpads:** Basic mouse emulation only (no multi-touch gestures)
    

**Not Supported:**

- **USB storage devices** (mass storage class requires different driver stack)
    
- **USB audio** (complex isochronous transfers, out of scope for HID hub)
    
- **USB hubs** (GL850G downstream ports cannot cascade additional hubs)
    
- **Vendor-specific devices** (gaming keyboards with proprietary RGB control, etc.)
    

#### 7.5.3 HID-to-Retro Translation

The Dock MCU firmware translates USB HID reports into formats accessible to retro CPUs:

**Keyboard Translation:**

- USB HID scancode → **PS/2 Set 2 scancode** (for Z80/8080 systems expecting AT keyboard)
    
- Or USB → **ASCII character** (for simple terminal-style input)
    
- Or USB → **raw bitmap** (128-bit array, 1 bit per key for gaming/custom apps)
    
- **Stored in Slot 0 registers**, Host polls or receives interrupt on keypress
    

**Mouse Translation:**

- USB relative motion (X, Y deltas) + button states → **quadrature-encoded signals** (for systems expecting mechanical mouse)
    
- Or → **absolute X/Y position** (MCU integrates deltas into virtual framebuffer coordinates)
    
- Or → **simple digital joystick** (map mouse movement to 4-direction + fire buttons)
    

**Gamepad Translation:**

- USB HID gamepad report (buttons, axes) → **Atari/Commodore/Sega-style joystick port bits**
    
- MCU firmware provides configurable mapping (e.g., analog stick → digital D-pad, triggers → buttons)
    

---

### 7.6 Integration with Dock Services (Slot 0)

#### 7.6.1 Register-Based Interface

HID devices are exposed to the Host CPU as **memory-mapped registers** in the Dock MCU's Slot 0 I/O window:

**Example Register Map (subject to change, see Dock MCU Firmware spec for normative version):**

|Offset|Register Name|Width|Description|
|---|---|---|---|
|0x20|`KBD_STATUS`|8-bit|Keyboard status (0x01 = key available, 0x80 = buffer overrun)|
|0x21|`KBD_SCANCODE`|8-bit|Most recent scancode (read clears `key_available` flag)|
|0x22|`KBD_MODIFIERS`|8-bit|Modifier key state (Shift, Ctrl, Alt, GUI as bitmask)|
|0x24|`MOUSE_STATUS`|8-bit|Mouse status (0x01 = motion, 0x02 = button changed)|
|0x25|`MOUSE_BUTTONS`|8-bit|Button state (bits 0–2: L/M/R, bit 3: wheel click)|
|0x26|`MOUSE_DELTA_X`|8-bit|Signed X delta since last read (−128 to +127)|
|0x27|`MOUSE_DELTA_Y`|8-bit|Signed Y delta since last read|
|0x28|`GAMEPAD_BUTTONS_L`|8-bit|Gamepad buttons 0–7 (A, B, X, Y, L, R, Start, Select)|
|0x29|`GAMEPAD_BUTTONS_H`|8-bit|Gamepad buttons 8–15 (extended, D-pad as bits)|
|0x2A|`GAMEPAD_AXIS_LX`|8-bit|Left stick X axis (0 = left, 128 = center, 255 = right)|
|0x2B|`GAMEPAD_AXIS_LY`|8-bit|Left stick Y axis (0 = up, 128 = center, 255 = down)|
|...|(additional axes, multiple gamepad support)|||

**Access Pattern:**

- Host CPU performs normal I/O read to Slot 0 window offset (e.g., `IN A, (0x20)` on Z80)
    
- Dock CPLD asserts `/CS0` for Slot 0
    
- Dock MCU firmware services I/O cycle, returns register value on data bus
    
- MCU uses `/READY` stretching if USB stack is mid-transaction (typically <1 ms)
    

#### 7.6.2 Interrupt Generation

**HID Event Interrupts:**

- Dock MCU can assert `INT_CH0` or `INT_CH1` on Slot 0 to notify Host of HID events:
    
    - **INT_CH0:** Keyboard key pressed (scancode available in buffer)
        
    - **INT_CH1:** Mouse motion or button state change
        
- **Polled mode:** Host can ignore interrupts and simply poll `KBD_STATUS` / `MOUSE_STATUS` registers
    
- **Interrupt mode:** Host enables interrupts, services on IRQ, reads scancode/delta to clear flag
    

**Configuration:**

- Slot 0 interrupt routing is configured by Dock MCU at boot (via IRQ router config)
    
- Default: Map Slot 0 INT_CH0 → CPU_INT[0] (lowest priority, suitable for keyboard)
    

---

### 7.7 Schematic Integration Points

#### 7.7.1 Connections to Other Dock Subsystems

**To Dock MCU (ESP32-S3):**

- USB D+/D− (GPIO19/20) → GL850G upstream port
    
- `HUB_RESET#` (MCU GPIO, see §12.1) → GL850G pin 2
    
- (No other signals; hub is autonomous once enumerated)
    

**To Dock Power Sheet:**

- +3.3V_MAIN → GL850G VDD33 (pin 14) + decoupling
    
- +5V_MAIN → USB downstream VBUS (via shared eFuse/PPTC, `VBUS_HUB_5V`)
    
- GND → GL850G GND pins (multiple), USB connector shields
    

**To Front Panel / Enclosure:**

- 4× USB connectors (USB-A or USB-C) with D+/D−/VBUS/GND breakout
    
- Optional: Panel-mount LEDs for per-port activity (if GL850G LED pins are used)
    

#### 7.7.2 Layout Constraints

**Critical USB Signal Integrity:**

- **D+/D− differential pairs:**
    
    - 90Ω ±10% differential impedance
        
    - Length matching: ±5 mils (0.13 mm) within each pair
        
    - Avoid vias if possible; if vias are necessary, use via-in-pad or very short stubs
        
    - Keep pairs >15 mils away from other high-speed signals
        
- **Reference plane:** Continuous ground plane under all USB traces; no plane splits
    
- **Connectors:** USB connector shields must connect to chassis/enclosure ground (see Power Architecture for grounding strategy)
    

**GL850G Placement:**

- **Proximity to MCU:** Minimize upstream D+/D− trace length (<2 inches ideal)
    
- **Proximity to connectors:** Minimize downstream D+/D− lengths (<3 inches per port if possible)
    
- **Thermal:** GL850G dissipates ~100 mW; no heatsink required, but ensure airflow if enclosed
    

**Decoupling Caps:**

- Place 0.1 µF ceramic capacitor within 5mm of GL850G VDD33 pin (pin 14)
    
- Place 10 µF bulk capacitor within 10mm of GL850G
    
- If +5V and +3.3V rails are nearby, share bulk caps; otherwise provide local bulk
    

---

### 7.8 Bill of Materials (USB Hub Subsystem)

|Ref|Function|Suggested Part / Notes|Qty|
|---|---|---|---|
|U_HUB|USB 2.0 hub IC|GL850G (Genesys Logic, SSOP-28) or FE1.1s (FetiOn)|1|
|C_HUB1|Decoupling (VDD33)|0.1 µF, X7R/X5R, 0402 or 0603, 16V|1|
|C_HUB2|Bulk (VDD33)|10 µF, X5R/X7R, 0805 or 1206, 6.3V|1|
|R_HUB_RST|Reset pull-up|10 kΩ, 0402 or 0603, 5%, 1/16W|1|
|R_DP1..4|D+ pull-up (per port)|1.5 kΩ, 0402 or 0603, 1%, 1/16W (if not internal to GL850G)*|0–4|
|TVS_USB1..4|ESD protection (D+/D−)|USBLC6-2SC6 (dual TVS diode, SOT-23-6, <3.5pF)|4|
|TVS_VBUS1..4|ESD protection (VBUS)|SMAJ5.0A or similar (15V unidirectional TVS, SMA/DO-214AC)|4|
|F_USB|Overcurrent protection|Bourns MF-MSMF200-2 (PPTC, 2A hold, 1812) or eFuse alternative|1|
|J_USB1..4|Downstream USB connectors|USB-A receptacle (e.g., Molex 48037-2200) or USB-C (GCT USB4105)|4|
|Y_HUB|Crystal (if required)|12 MHz, ±50 ppm, 18pF load (check GL850G datasheet)**|0–1|
|C_XTAL1,2|Crystal load caps|18 pF, NPO/C0G, 0402 (if external crystal used)|0–2|

**Notes:**

- *GL850G has internal 1.5kΩ pull-ups on downstream D+ for Full Speed signaling; external resistors may not be needed (verify from datasheet).
    
- **Some GL850G variants have internal oscillator; check datasheet to confirm if external 12 MHz crystal is required.
    

**Cost Estimate (prototype qty 1–10):**

- GL850G: ~$0.50–1.00 USD
    
- Passives (caps, resistors): ~$0.50
    
- TVS diodes (4×): ~$1.00
    
- PPTC fuse: ~$0.30
    
- USB-A connectors (4×): ~$2.00–4.00 (or ~$3–6 for USB-C)
    
- **Total subsystem BOM:** ~$5–8 USD per Dock
    

---

### 7.9 Firmware Responsibilities

The Dock MCU firmware must implement the following to support the USB hub:

#### 7.9.1 Initialization Sequence

1. **At boot (before releasing Host from reset):**
    
    - Assert `HUB_RESET# = 0` (keep GL850G in reset)
        
    - Initialize ESP-IDF USB host stack
        
    - Wait for +5V_MAIN and +3.3V_MAIN `PG_*` signals to go high
        
    - Deassert `HUB_RESET# = 1` (release GL850G)
        
    - Wait ~200 ms for GL850G to enumerate on USB bus
        
2. **GL850G enumeration:**
    
    - USB host stack detects hub, reads hub descriptor
        
    - Firmware issues `SET_CONFIGURATION` to activate hub
        
    - Firmware begins polling hub interrupt endpoint for port status changes
        
3. **Downstream device handling:**
    
    - When port connect event occurs, enumerate device
        
    - Parse HID report descriptor, install appropriate class driver
        
    - Begin polling HID reports at device's preferred rate (8–125 Hz)
        

#### 7.9.2 Runtime Operation

**HID Report Processing:**

- On each HID report received:
    
    - Parse report fields (button states, axes, key codes)
        
    - Update internal state buffers (e.g., `kbd_scancode_fifo`, `mouse_delta_x/y`)
        
    - If Host interrupt is enabled, assert `INT_CH0` or `INT_CH1` on Slot 0
        

**Slot 0 Register Servicing:**

- When Host reads Slot 0 I/O register (e.g., `KBD_SCANCODE`):
    
    - Firmware services `/CS0` cycle, drives data bus with register value
        
    - Clear status flags as appropriate (e.g., `key_available = 0` after read)
        
    - Deassert interrupt if no more events pending
        

**Error Handling:**

- USB device disconnect: Clear state buffers, optionally signal Host via status register
    
- USB transaction timeout: Retry up to 3 times, then mark device as faulty
    
- Overcurrent on +5V rail: Assert `HUB_RESET# = 0`, log fault, wait for manual recovery
    

#### 7.9.3 Monitor Service Commands

The USB hub should expose debug/control commands via the Monitor service (UART):

- `usb_status` — Report GL850G enumeration state, number of devices connected, per-port status
    
- `usb_reset` — Assert `HUB_RESET#` to force hub re-enumeration
    
- `hid_list` — List all enumerated HID devices with VID/PID, interface details
    
- `hid_dump <port>` — Dump raw HID reports from device on specified port (for debugging custom devices)
    

---

### 7.10 Future Extensions and Variants

#### 7.10.1 Per-Port Power Control

Builders who need individual port control can add:

- **Load switches:** 4× TPS2051B (single-channel, 500 mA current limit, SOT-23-5)
    
- **MCU GPIOs:** 4 additional outputs to drive power-enable pins
    
- **Firmware:** Per-port overcurrent detection via switches' fault pins
    

**BOM impact:** +$2–3 USD, +4 MCU GPIOs

#### 7.10.2 USB-to-Legacy Adapters

Future Dock firmware or Tiles could provide:

- **USB keyboard → PS/2 adapter** (Dock Tile with PS/2 DIN connector, translates USB HID → PS/2 protocol)
    
- **USB mouse → Serial mouse** (translate USB → Microsoft/Logitech serial mouse protocol for vintage PCs)
    
- **USB gamepad → Atari/DB9 joystick** (Dock Tile with DB9 connectors, map USB buttons/axes to digital joystick signals)
    

These would be implemented as separate Tiles (physical slots 1–N) that communicate with Dock MCU via I²C or shared memory, not as part of the USB hub subsystem itself.

#### 7.10.3 Wireless USB Dongle Support

USB dongles for wireless keyboards/mice should work transparently:

- MCU sees the dongle as a HID device with standard report descriptor
    
- Dongle handles RF communication; MCU is unaware of wireless nature
    
- **Caveat:** Some proprietary dongles use vendor-specific protocols and may not enumerate as standard HID (test case-by-case)
    

#### 7.10.4 Alternative Hub ICs

If GL850G is unavailable, these alternatives are pin-compatible or require minor schematic changes:

- **FE1.1s** (FetiOn Technology, SSOP-28): Drop-in replacement, lower cost (~$0.30 USD)
    
- **TUSB2046B** (Texas Instruments, TSSOP-28): Higher-spec'd, integrated ESD protection, but higher cost (~$2 USD)
    
- **USB2514** (Microchip, QFN-36): 4-port hub with integrated flash for custom configuration, requires different pinout
    

---

### 7.11 Design Checklist

Before finalizing the USB hub subsystem schematic:

- Verify ESP32-S3 GPIO19/20 are not used by any other subsystem (they are hardwired to USB OTG)
    
- Confirm GL850G or alternative hub IC is in stock at preferred suppliers (check lead times)
    
- Select USB connector type (USB-A vs USB-C) based on enclosure design and user preference
    
- Route D+/D− pairs with 90Ω differential impedance, length matching ≤5 mils
    
- Place TVS diodes close to connectors (<10mm trace length)
    
- Add test points on upstream D+/D− for debugging enumeration issues
    
- Reserve MCU GPIO for `HUB_RESET#` in pin assignment / GPIO allocation (see §12.1)
    
- Cross-reference Power Architecture for +5V_MAIN current budget (ensure ≥2A available for USB hub)
    
- Document in schematic: "Per-port power switching is NOT implemented; all ports share +5V_MAIN via F_USB"
    
- Plan for front-panel connector mounting (chassis punch-outs, panel thickness, connector retention)
    

---

## 8. I²C Fabric & Addressing

### 8.1 Topology

The Dock uses a **single I²C master** (Dock MCU) and a **TCA9548A 1→8 I²C switch** to fan out the bus into independent segments.

- MCU I²C (SCL/SDA) connects to the upstream side of the TCA9548A.
    
- Each of the 8 downstream channels feeds one **I²C segment**.
    

Recommended channel mapping (baked into the reference Dock):

|TCA Channel|I²C Segment|Contents (typical)|
|--:|---|---|
|0|Dock-local|RTC, PD controller, USB hub ctrl, **GPIO expander (MCP23017)**, Dock FRU, optional MachXO2 sysCONFIG I²C|
|1|Host Core connector|CPU descriptor EEPROM, host-local I²C devices|
|2|Bank Core connector|Bank descriptor EEPROM, bank-local I²C devices|
|3|Tile Slot 1|Tile 1 descriptor + Tile-local I²C|
|4|Tile Slot 2|Tile 2 descriptor + Tile-local I²C|
|5|Tile Slot 3|Tile 3 descriptor + Tile-local I²C|
|6|Tile Slot 4|Tile 4 descriptor + Tile-local I²C|
|7|Spare / future|Extra Dock logic or future slots|

### 8.2 Addressing strategy

- Within each segment, devices use **standard I²C addresses** (e.g., `0x50` range for descriptors).
    
- Because each segment is independent, **the same address range can be reused** on different channels without conflict.
    
- The Dock MCU is responsible for:
    
    - Enabling one channel at a time on the TCA9548A.
        
    - Probing for expected descriptor devices (Host, Bank, Tiles).
        
    - Handling the case where a descriptor is missing or malformed.
        

### 8.3 Enumeration flow (MCU-centric)

At power-on reset, the Dock MCU:

1. Enables **channel 0** and initializes Dock-local I²C devices (RTC, PD, GPIO expander, hub, Dock FRU, etc.).
    
2. Enables **channel 1** and reads the **CPU Descriptor** from the Host.
    
3. Enables **channel 2** and reads the **Bank Descriptor**.
    
4. Enables **channels 3..N** and, for each, reads the Tile descriptor (if present).
    
5. Builds the effective platform layout:
    
    - CPU type, data/address widths, `IntAckMode`.
        
    - Available Tiles and their function/instance IDs.
        
    - Bank capabilities and sizes.
        
6. Translates this into concrete **window and interrupt routing tables** and pushes them into the CPLD (via MCP23017).
    
7. Exposes a summarized view of the discovered devices through the Dock Services Tile (so Host firmware can quickly inspect the topology if it wants to).
    

---

## 9. Service Monitor Path (USB ↔ FTDI ↔ UART)

### 9.1 Goals

- Provide a **robust, low-ceremony console** into the Dock MCU.
    
- Support copy-paste uploads of **Intel HEX** or **Motorola S-record** without corruption.
    
- Allow developers to flash test firmware with minimal external tools.
    

### 9.2 Wiring

- FT232R upstream port → Service USB connector.
    
- FT232R downstream pins:
    
    - `TXD` → MCU `UARTx_RX`.
        
    - `RXD` ← MCU `UARTx_TX`.
        
    - `CTS` → MCU `UARTx_RTS`.
        
    - `RTS` ← MCU `UARTx_CTS`.
        
    - Optional: `DTR`, `RTS` → small FETs → MCU `EN` / `BOOT` for auto-bootloader.
        

### 9.3 Usage modes

1. **Bring-up & debugging**
    
    - Bare-metal monitor that lets the user:
        
        - Inspect MCU registers and memory.
            
        - Toggle GPIOs.
            
        - Probe I²C devices.
            
        - Manually poke CPLD configuration registers.
            
2. **User-facing monitor**
    
    - Later, a richer monitor that:
        
        - Prints a device tree-like view of enumerated Tiles.
            
        - Allows uploading small firmware blobs or test images to Tiles.
            
        - Exposes log streams (e.g., interrupt trace, bus timing).
            
3. **MCU programming (first-time)**
    
    - The same FTDI UART can be used to enter the ESP32 ROM bootloader and flash the initial firmware image, via:
        
        - Hardware wiring from FTDI control pins to `EN` / `BOOT`, or
            
        - Manual button presses combined with a USB-serial flashing tool.
            

### 9.4 Monitor Protocol Robustness (RTS/CTS)

To make HEX/S-record uploads reliable:

- Monitor firmware **MUST** honor RTS/CTS hardware flow control.
    
- Upload protocol **SHOULD**:
    
    - Accept data in **bounded chunks** (e.g., lines or small blocks), not one monolithic megabyte slab.
        
    - Acknowledge each chunk or line (OK / error) so the host tool can retry.
        
- On overrun or parse error, firmware **SHOULD**:
    
    - Discard the current line/chunk.
        
    - Set a clear error flag / status code.
        
    - Require explicit user action (command) to resume an upload.
        

The exact monitor command set is defined in a separate **Dock Monitor Specification**.

---

## 10. CPLD Programming and Configuration

### 10.1 Runtime configuration via MCU

The **primary way** the Dock adapts to different Hosts and Tiles is via **runtime configuration** of the MachXO2 configuration tables:

- `addr_decoder_cfg` tables:
    
    - Per-window BASE, MASK, slot index, and OP (read/write/both).
        
- `irq_router_cfg` tables:
    
    - Per-function/instance/channel mapping to CPU interrupt pins, with optional stretch/edge modes.
        

The Dock MCU writes these tables after parsing descriptors, using the **MCP23017-backed configuration bus**. During normal operation, they are rarely changed.

### 10.2 Bitstream programming (optional in-system)

For development and field updates, the MachXO2 bitstream can be programmed in two ways:

1. **External JTAG header (recommended, always present)**
    
    - Standard 2×5 JTAG header near the CPLD.
        
    - Used for initial board bring-up and recovery if MCU firmware is not yet running.
        
2. **MCU-driven in-system update (optional, hardware-supported)**
    
    - The Dock PCB reserves MCU pins that can be wired to the MachXO2 sysCONFIG interface (I²C or JTAG).
        
    - Future Dock firmware may implement a safe update protocol (e.g., via the service monitor), but this is not required for the first revision.
        

The design guideline is: **never depend solely on MCU-driven updates**; always keep an external recovery path.

---

## 11. Reset and Boot Sequencing (Digital Perspective)

A simplified sequencing model for the digital subsystem:

1. **Power rails ramp** (see Power System Architecture).
    
2. **CPLD configures from NVCM** and enters a safe default state:
    
    - All windows disabled (no `/CS[n]` assertions).
        
    - `/READY` passes through or is forced ready for unmapped cycles.
        
    - Interrupt routing tables default to “off”.
        
3. **Dock MCU boots** from its own SPI flash.
    
4. Dock MCU:
    
    - Initializes I²C and the TCA9548A.
        
    - Enumerates Dock-local devices, Host, Bank, and Tiles.
        
    - Programs the MCP23017 and uses it to write final window and interrupt routing tables into the CPLD.
        
5. **Host CPU reset release**:
    
    - Depending on the power/control design, the Dock MCU or a power supervisor deasserts `/RESET` to the Host and Tiles once the CPLD is correctly configured.
        
6. **Normal operation**:
    
    - Host firmware uses the CPU descriptor’s `WindowMap[]` and `IntRouting[]` as its view of the system.
        
    - Physically, the Dock CPLD enforces that mapping, and the Dock Services Tile (Slot 0) provides introspection and control.
        

---

## 12. GPIO Allocation & Future Work

### 12.1 GPIO Allocation (ESP32-S3 Dock MCU)

This section captures **high-level GPIO constraints** relevant to the Dock digital architecture. Exact pin numbers are finalized in the Dock’s GPIO/pin map document; here we only reserve key functions.

**Hard-wired functions:**

- **USB OTG (HID Hub upstream):**
    
    - `GPIO19` → USB D−
        
    - `GPIO20` → USB D+
        
    - These pins are **dedicated to USB** and **MUST NOT** be reused for any other function.
        

**Reserved control signals:**

- **`HUB_RESET#`**
    
    - 1 dedicated ESP32-S3 GPIO output.
        
    - Drives the hub IC reset pin (GL850G RESET#, see §7.3.1).
        
    - Must be available from reset so firmware can hold the hub in reset during early boot.
        
    - Direction: Dock MCU → Dock Digital sheet (and onward to hub IC).
        

These constraints should be reflected in the detailed ESP32-S3 GPIO assignment table and the KiCad net naming (e.g., `USB_OTG_DM`, `USB_OTG_DP`, `USB_HUB_RESET#`).  
A high-level classification of which functions use direct GPIO vs. the MCP23017 expander is given in §4.1.4; exact pin numbers live in `esp32s3_gpio_assignments.md`.

### 12.2 Future Work & Open Questions

The following items are intentionally left flexible for later refinements and dedicated specs:

1. **Exact Dock Services register map**
    
    - Needs its own document once RTC, USB HID, and power-control use cases are fully nailed down.
        
2. **Width of the MCU’s local Tile address sub-bus**
    
    - Nominally 4 bits for now; may expand if the Dock Services Tile grows more complex.
        
3. **In-system CPLD bitstream update protocol**
    
    - Hardware hooks are present; firmware-level flows will be specified and tested later.
        
4. **Richer monitor features**
    
    - Binary upload helpers, scripting, Tile debug breakpoints, etc., can be layered on top of the basic monitor link.
        

This document should be updated as those details are finalized, but the **core relationships** between MCU, CPLD, I²C fabric, service UART, USB hub, and Tile/CPU/Bank remain stable for v1 of the reference Dock.

---

## 13. Bill of Materials (Draft)

> This BOM covers the **digital/control** side of the Dock (MCU, CPLD, I²C fabric, service UART, RTC/FRU, USB hub, GPIO expander). Power components and bulk connectors are defined in the Dock Power System Architecture and core Dock spec.

### 13.1 Major ICs

|Ref|Function|Suggested Part / Notes|
|---|---|---|
|U1|Dock MCU|ESP32-S3-WROOM-1 module (e.g., ESP32-S3-WROOM-1-N16R8), 3.3 V logic.|
|U2|CPLD / fabric|LCMXO2-4000HC-4TG144C (Lattice MachXO2, 4000 LUT, 144-pin TQFP, 3.3 V).|
|U3|Service USB–UART bridge|FT232RL / FT232RQ (FTDI USB↔UART with RTS/CTS hardware flow control).|
|U4|I²C switch|TCA9548APWR (TI 1→8 I²C switch, TSSOP-24, 3.3 V).|
|U5|Dock RTC|RV-8523-C3 (I²C RTC with integrated 32.768 kHz resonator).|
|U6|Dock FRU EEPROM|24LC04B / AT24C04 (2–4 kbit I²C EEPROM, 3.3 V; Dock descriptor, e.g. 0x52).|
|U7|USB 2.0 hub|GL850G (Genesys Logic, SSOP-28) or FE1.1s (alternative 4-port USB 2.0 hub).|
|U8|(Optional) extra SPI flash|W25Q32JV or similar, only if extra non-volatile storage is desired.|
|U9|(Optional) I²C monitor|TMP102 / INA219 or similar I²C temp/current sensor on Dock-local branch.|
|U10|GPIO expander|MCP23017-E/SO (Microchip 16-bit I²C GPIO expander for CPLD config bus).|

### 13.2 Service USB Port (FT232R Path)

|Ref|Function|Suggested Part / Notes|
|---|---|---|
|J1|Service USB connector|USB Micro-B or USB-C; dedicated "SERVICE" port to FT232R.|
|U3|USB–UART bridge|FT232RL / FT232RQ (from 13.1).|
|D1–D4|USB ESD protection|USBLC6-2SC6 or similar 2-line USB ESD array per connector as needed.|
|R_TX, R_RX|USB data series resistors|22–33 Ω in series with FT232R USBDP/USBDM where recommended.|
|R_U_TX/R_U_RX|UART series resistors|22–47 Ω in series with FT232R TXD/RXD to ESP32 UART (optional SI).|
|R_RTS/R_CTS|RTS/CTS series resistors|22–47 Ω in series between FT232R RTS/CTS and ESP32 RTS/CTS.|
|Q_EN, Q_BOOT|Boot/reset transistors|Small NPN / MOSFET pair to drive ESP32 EN and BOOT from FT232R DTR/RTS (optional).|

**Logical mapping (for the schematic pin map):**

- FT232R_TXD → ESP32 `UART_MON_RX`
    
- FT232R_RXD ← ESP32 `UART_MON_TX`
    
- FT232R_RTS → ESP32 `UART_MON_CTS`
    
- FT232R_CTS ← ESP32 `UART_MON_RTS`
    
- FT232R_DTR / RTS → (via Q_EN / Q_BOOT) → ESP32 `EN` / `BOOT` (optional auto-flash).
    

### 13.3 USB HID Hub Subsystem

(Consolidated from §7.8; reference designators here may be adjusted during schematic capture.)

|Ref|Function|Suggested Part / Notes|Qty|
|---|---|---|---|
|U7 / U_HUB|USB 2.0 hub IC|GL850G (Genesys Logic, SSOP-28) or FE1.1s (FetiOn)|1|
|C_HUB1|Decoupling (VDD33)|0.1 µF, X7R/X5R, 0402 or 0603, 16V|1|
|C_HUB2|Bulk (VDD33)|10 µF, X5R/X7R, 0805 or 1206, 6.3V|1|
|R_HUB_RST|Reset pull-up|10 kΩ, 0402 or 0603, 5%, 1/16W|1|
|R_DP1..4|D+ pull-up (per port)|1.5 kΩ, 0402 or 0603, 1%, 1/16W (if not internal to hub IC)*|0–4|
|TVS_USB1..4|ESD protection (D+/D−)|USBLC6-2SC6 (dual TVS diode, SOT-23-6, <3.5pF)|4|
|TVS_VBUS1..4|ESD protection (VBUS)|SMAJ5.0A or similar (15V unidirectional TVS, SMA/DO-214AC)|4|
|F_USB|Overcurrent protection|Bourns MF-MSMF200-2 (PPTC, 2A hold, 1812) or eFuse alternative|1|
|J2–J5 / J_USB1..4|Downstream USB connectors|USB-A receptacle (e.g., Molex 48037-2200) or USB-C (GCT USB4105)|4|
|Y_HUB|Crystal (if required)|12 MHz, ±50 ppm, 18pF load (check hub datasheet)**|0–1|
|C_XTAL1,2|Crystal load caps|18 pF, NPO/C0G, 0402 (if external crystal used)|0–2|

**Notes:**

- *GL850G/FE1.1s often provide internal D+ pull-ups; confirm whether external resistors are needed.
    
- **Some variants have internal oscillators; verify whether an external 12 MHz crystal is required.
    

### 13.4 I²C Fabric & Descriptors

|Ref|Function|Suggested Part / Notes|
|---|---|---|
|U4|I²C switch|TCA9548APWR (main fan-out from ESP32 I²C).|
|U5|RTC|RV-8523-C3 on Dock-local branch (CH0).|
|U6|Dock FRU EEPROM|24LC04B / AT24C04 at recommended Dock FRU address (e.g. 0x52).|
|R_SCL, R_SDA|I²C pull-ups (MCU side)|4.7–10 kΩ to 3.3 V on SCL/SDA upstream of TCA9548A.|
|R_CHx_SCL/SDA|I²C pull-ups (branch, optional)|4.7–10 kΩ per branch as needed for long runs / heavy loads.|

**Channel mapping reminder:**

- CH0: Dock-local (RTC, PD, Dock FRU, GPIO expander, MachXO2 sysCONFIG I²C, any local sensors).
    
- CH1: Host Core connector (Host FRU on Host board).
    
- CH2: Bank Core connector (Bank FRU on Bank board).
    
- CH3–CH6: Tile slots 1–4 (Tile FRUs on Tile boards).
    
- CH7: Spare / future.
    

### 13.5 CPLD & Programming

|Ref|Function|Suggested Part / Notes|
|---|---|---|
|U2|CPLD|LCMXO2-4000HC-4TG144C (MachXO2).|
|C_U2_*|Decoupling caps|0.1 µF per VCC pin + 1–4.7 µF bulk per rail cluster (see layout).|
|JTAG1|CPLD JTAG header|2×5 1.27 mm header or Tag-Connect footprint near U2.|
|R_TCK/TMS/TDI/TDO|Series resistors|33–47 Ω between U2 JTAG pins and header (and optional MCU GPIOs).|

MachXO2 primary I²C sysCONFIG pins connect to the Dock-local I²C branch (CH0) so future firmware can perform in-system reflash; JTAG1 remains the primary bring-up / recovery path.

### 13.6 Dock MCU Support (ESP32-S3-WROOM)

|Ref|Function|Suggested Part / Notes|
|---|---|---|
|U1|Dock MCU module|ESP32-S3-WROOM-1-N16R8 (or similar), 3.3 V.|
|C_U1_*|Decoupling caps|0.1 µF near each module VCC pin + local bulk (4.7–10 µF).|
|R_BOOTx|Boot strap resistors|As per Espressif reference design (GPIO0/BOOT, strapping pins).|
|J_MCU?|Optional debug header|Small header or test pads for extra debug pins if desired.|

(Exact Slot 0 data/address/CS/READY/INT pin assignments will be captured in the Dock schematic and pin-map documents.)

### 13.7 Connectors, Headers & Test Points (Digital)

|Ref|Function|Suggested Part / Notes|
|---|---|---|
|J1|Service USB|USB Micro-B / USB-C, shield tied to chassis/ground per power doc.|
|J2–J5|HID USB ports|USB-A/USB-C as chosen for front panel (see §7.2.3).|
|JTAG1|CPLD JTAG header|2×5 1.27 mm or Tag-Connect.|
|TP_*|Digital test points|`/IORQ`, `/READY`, `/RESET`, `/CS0`, a few `/CS[n]`, `CPU_INT`, one Tile `INT_CH`, I²C SCL/SDA (MCU side).|

Host/Bank/Tile edge connectors, and any additional digital-meets-power components (e.g., PD ICs, load switches), are specified in the Dock Specification and Power System Architecture and are not duplicated here.

### 13.8 Passives (Group-Level Summary)

A detailed resistor/capacitor BOM will be generated from the schematic; at architecture level, the following families are expected:

- **Decoupling capacitors**
    
    - 0.1 µF ceramic (0402/0603) for every IC VCC pin.
        
    - 1–10 µF ceramic bulk capacitors per supply region (MCU, CPLD, USB hub, FT232R, I²C fabric).
        
- **I²C pull-ups**
    
    - 4.7–10 kΩ on MCU-side SCL/SDA.
        
    - Optional 4.7–10 kΩ on long or heavily loaded branches.
        
- **USB / UART series resistors**
    
    - 22–33 Ω for USB D+/D− pairs where recommended by the hub/FTDI datasheets.
        
    - 22–47 Ω for sensitive UART/handshake lines if needed for signal integrity.
        
- **Strap / bias resistors**
    
    - ESP32 boot strapping network.
        
    - Any MachXO2 mode/program pins that require static pull-up/pull-down.
        

### 13.9 GPIO Expander & Config Bus

|Ref|Function|Suggested Part / Notes|
|---|---|---|
|U10|GPIO expander|MCP23017-E/SO (Microchip 16-bit I²C GPIO expander, SOIC-28, 3.3 V). DIP variant (-E/SP) may be used on prototypes.|
|R_U10_SCL, R_U10_SDA|Shared I²C pull-ups|Covered by `R_SCL`, `R_SDA` in §13.4 (no extra pull-ups needed if trace lengths are modest).|
|C_U10|Decoupling|0.1 µF ceramic, X7R/X5R, 0402/0603, placed close to U10 VDD.|
|ADDR_STRAPS|Address strap resistors|Three 0 Ω links or small resistors to strap MCP23017 `A0–A2` (e.g. all low → address 0x20).|

**Notes:**

- U10 sits on the **Dock-local I²C segment** (TCA9548A CH0, see §8.1).
    
- Its GPIO pins fan out to:
    
    - The MachXO2 CPLD configuration nets (address/data/strobes).
        
    - Optional low-speed Dock-local configuration or debug lines.
        
- Exact bit-to-net mapping is defined in `DECODER_CONFIGURATION.md` and in the Dock schematic; this document only standardizes **part choice and placement**.
    

This draft BOM is intended as a starting point; exact values, package sizes, and counts will be refined during schematic capture and PCB layout.

---

## 14. Hierarchical Sheet Interface (KiCad)

For schematic capture, the Dock digital subsystem is treated as a **single hierarchical sheet** in KiCad. This section summarizes its external "ports" in a software-style in/out interface, so the top-level design can treat the Dock Digital block as a module with well-defined responsibilities.

### 14.1 Sheet Role

The **Dock Digital** hierarchical sheet contains:

- Dock MCU (ESP32-S3-WROOM module).
    
- CPLD (MachXO2) with address decoder and IRQ router logic.
    
- TCA9548A I²C switch and Dock-local I²C devices (RTC, Dock FRU, PD, GPIO expander, optional sensors, hub control).
    
- FT232R USB–UART bridge for the Service port.
    
- USB hub IC for HID ports (if implemented on the Dock board).
    

It does **not** contain:

- Bulk power conversion (PD front-end, regulators, eFuses) — see Power sheet.
    
- Host/Bank/Tile card internals — see corresponding board sheets.
    
- The Core and Tile physical connectors themselves (these typically live on the top-level or dedicated connector sheets and connect into Dock Digital via nets).
    

### 14.2 External Interface Summary

The following table summarizes the main categories of nets crossing the Dock Digital sheet boundary. Exact net names can be adapted during schematic capture, but the groups and directions SHOULD be preserved.

|Group|Dir. (w.r.t Dock Digital sheet)|Net / Bus|Description / Notes|
|---|---|---|---|
|**Power & reset**|In|`+3V3_AON`, `+3V3_MAIN`, `+5V_MAIN`|Power rails provided by the Power sheet.|
||In|`PG_5V_MAIN`, `PG_3V3_MAIN`|Power-good inputs from main regulators/eFuses.|
||In|`PWR_BTN#`|Front-panel momentary power button (active-low).|
||Out|`MAIN_ON_REQ`|MCU request to enable/disable +5V_MAIN and +3V3_MAIN.|
||Out|`SYS_RESET#`|Global system reset to Host/Bank/Tiles, aligned with Core spec `/RESET`.|
|**Core CPU bus**|In|`CORE_A[ADDR_W-1:0]`|CPU address bus into CPLD logic.|
||In|`CORE_IORQ#`|I/O request (active-low) from CPU.|
||In|`CORE_R_W_`|Read/Write direction signal from CPU.|
||In|`CORE_CPU_ACK#`|Interrupt acknowledge / vector-cycle qualifier from CPU.|
||In/Out|`CORE_RESET#`|System reset; typically driven from Dock, but may also be sensed.|
||Out|`CORE_READY#`|READY signal back to CPU (CPLD output, Tile `/READY` aggregation).|
||Out|`CORE_CPU_INT[3:0]`|CPU interrupt lines driven by IRQ router.|
||Out|`CORE_CPU_NMI[1:0]`|CPU NMI lines driven by IRQ router.|
|**Tile slot control**|Out|`/CS[NUM_SLOTS:1]`|Per-slot chip-selects from CPLD to Tile connectors (Slots 1..N).|
||In|`SLOT_READY#[NUM_SLOTS:1]`|Per-slot READY inputs from Tiles back into CPLD.|
||In|`SLOT_INT_CH0[NUM_SLOTS:1]`|Per-slot INT channel 0 requests.|
||In|`SLOT_INT_CH1[NUM_SLOTS:1]`|Per-slot INT channel 1 requests.|
||In|`SLOT_NMI_CH[NUM_SLOTS:1]`|Per-slot NMI request lines.|
|**Virtual Slot 0**|Internal to sheet|`D[7:0]`, `A_LOCAL[3:0]`, `/CS_0`, `R/W_`, `READY_0#`, `INT_CH[1:0]`, `NMI_CH`|Dock MCU Tile interface; these nets stay inside the Dock Digital sheet.|
|**I²C branches**|Bi|`I2C_MCU_SCL`, `I2C_MCU_SDA`|Upstream I²C from ESP32 to TCA9548A.|
||Bi|`I2C_HOST_SCL`, `I2C_HOST_SDA`|Branch to Host connector (TCA9548A CH1).|
||Bi|`I2C_BANK_SCL`, `I2C_BANK_SDA`|Branch to Bank connector (CH2).|
||Bi|`I2C_SLOT1_SCL/SDA` … `I2C_SLOTn_SCL/SDA`|Branches to Tile slots 1..N (CH3+).|
|**Service USB**|Bi|`USB_SVC_DP`, `USB_SVC_DN`|Differential USB pair from Service connector to FT232R.|
||In|`VBUS_PC_RAW` / `VBUS_PC_SYS`|5 V from PC (after protection), for FT232R and AON power as defined in Power doc.|
|**USB HID hub**|Bi|`USB_HUB_DP`, `USB_HUB_DN`|Upstream USB D+/D− pair between Dock Digital and Power/connector sheet, if hub IC is placed here.|
||In|`VBUS_HUB_5V`|5 V rail for HID hub and downstream ports (from Power sheet).|
||Out|`USB_HUB_RESET#`|Active-low reset from Dock MCU to USB hub IC (GL850G RESET#).|
|**Misc. debug**|Out (optional)|`DBG_LED[n]`, `STATUS[n]`|Optional debug/status lines exposed to LEDs or headers on the top-level.|

In KiCad, these groups translate directly into **hierarchical sheet pins** on the Dock Digital sheet symbol. The internal implementation (MCU, CPLD, FTDI, hub, RTC, I²C switch, GPIO expander) is then free to evolve as long as these external contracts remain stable.

### Power Budget Guidelines

**Historical Context:**
A fully-loaded Commodore 64 drew 5W total (5V @ 1A).
This powered a complete computer system including CPU, 
graphics, sound, memory, and I/O.

**μBITz Power Budget:**
- 5V rail: 20W available (4× C64)
- 3.3V rail: 6.6W available (1.3× C64)
- Total: 26W+ (5× C64)

**Tile Design Targets:**
- Simple tiles: <1.5W (target 30% of C64)
- Complex tiles: <3W (target 60% of C64)
- Maximum: <5W (do not exceed complete C64!)

If your tile draws more than a complete C64 system,
reconsider your design choices!

**Why This Matters:**
✓ Ensures thermal manageability
✓ Allows multiple tiles in system
✓ Keeps power supply simple
✓ Maintains hobbyist accessibility
✓ No SCADs™ required beyond Power Module
```

---

## **Silkscreen Update:**

**Add to the Power Module output section:**
```
┌─────────────────────────────┐
│  5V @ 4A = 20W              │
│  "4× C64 Power Budget"      │
│                             │
│  3.3V @ 2A = 6.6W           │
│  "1.3× C64 Power Budget"    │
│                             │
│  Total: 5× C64 Capability   │
│  In a Modular Platform!     │
└─────────────────────────────┘
```

---

## **The Beautiful Irony:**
```
Modern "retro-style" SoC (like RP2040):
- Dual ARM cores @ 133MHz
- 264KB RAM
- Tons of peripherals
- Power consumption: ~100mW

That's 2% of a C64's power for 100× the computing power! 😄

But we're building AUTHENTIC retro, so:
- Real discrete logic
- Period-accurate chips  
- Educational value
- Hackability
- Fun factor

Worth the extra watts!