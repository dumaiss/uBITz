# 2025-11-27 – Dock Digital Architecture

## Decisions

- **Digital Architecture Phase is officially complete.**
  - The **μBITz Dock Digital System Architecture** is now the **single normative reference** for:
    - ESP32-S3 Dock MCU roles,
    - MachXO2 `addr_decoder` + `irq_router` fabric,
    - USB HID hub subsystem,
    - I²C fabric (TCA9548A + Dock-local devices),
    - Virtual Slot 0 (Dock Services Tile),
    - Service UART (FT232R) path.
  - Architecture status: **Approved & Ready for Schematic Capture**.

- **CPLD choice locked:**  
  - Final part: **LCMXO2-4000HC-4TG144C**.  
  - 1200HC was rejected due to LUT overflow; 4000HC leaves comfortable headroom for future tweaks.

- **GPIO strategy finalized:**
  - **Direct ESP32-S3 GPIO** reserved for:
    - Slot 0 Tile interface (data, local address, CS, READY, INT lines),
    - I²C master bus upstream of TCA9548A,
    - Service UART with RTS/CTS,
    - Critical power control pins (`MAIN_ON_REQ`, `SYS_RESET#`, `PG_*` sense),
    - USB OTG D+/D− (GPIO19/20),
    - HUB_RESET#,
    - A small number of debug/status LEDs.
  - **MCP23017 I²C GPIO expander** will:
    - Drive the CPLD config buses for decoder + IRQ router,
    - Cover other slow Dock-local control pins that are strictly boot-time / low-duty.
  - This closes the GPIO budget with margin while preserving timing where needed.

- **Config timing model agreed:**
  - CPLD comes up from NVCM in a **safe neutral state**:
    - All windows disabled,
    - `/CS[n]` deasserted,
    - Interrupt routing tables effectively “off,”
    - `/READY` behavior kept benign for unmapped cycles.
  - Dock MCU (on 3V3_AON with the expander) is responsible for:
    - Bringing up the I²C fabric (TCA9548A),
    - Reading Host/Bank/Tile descriptors,
    - Programming window + IRQ tables into the CPLD over the expander bus,
    - Only then releasing `/RESET` to the rest of the system.

- **Virtual Slot 0 contract is stable:**
  - Dock MCU is exposed as a **Dock Services Tile** on **Slot 0**:
    - 8-bit data,
    - Small local address sub-bus (nominally 4 bits, expandable later),
    - Normal `R/W_`, `/READY`, `/CS_0`, interrupt behavior.
  - Slot 0 is how the Host sees:
    - RTC, power status, USB HID hub summary,
    - Future Dock services, including enumeration views.

- **USB HID hub architecture is frozen:**
  - ESP32-S3 USB OTG (GPIO19/20) in host mode → **GL850G/FE1.1s** 4-port hub → front-panel USB ports.
  - Single shared +5V rail for HID connectors (no per-port power switching in v1).
  - HUB_RESET# from MCU used for global hub reset and re-enumeration.

- **Hierarchical sheet boundary defined:**
  - Dock Digital will be captured as **one KiCad hierarchical sheet** with:
    - Clean interface for Core bus, Tile slot control lines, I²C branches, power control, USB/service ports.
  - This sheet will be considered the implementation of the approved architecture.

- **Definition-of-Done stamp adopted:**
  - The “μBITz Dock Digital Architecture — Definition of Done Report” is now the **formal sign-off record** for this phase and will live alongside the architecture doc.

---

## Constraints

- **Power domains:**
  - ESP32-S3 Dock MCU and MCP23017 must both live on **+3V3_AON**:
    - Ensures Dock-local I²C, expander and MCU are always available during configuration and soft power transitions.
  - USB hub logic on 3V3_MAIN, downstream VBUS on 5V_MAIN, with sufficient current budget (≈2 A) reserved for HID devices.

- **Timing / signal integrity:**
  - No timing- or cycle-critical paths (READY, Slot 0 bus, Tile interrupts, CPU interrupt pins) may go through the GPIO expander.
  - USB OTG:
    - GPIO19/20 **dedicated** to D−/D+, 90 Ω diff, length-matched, continuous ground reference.
  - CPLD must meet timing for:
    - Address decode and `/CS[n]` generation,
    - `/READY` stretching and aggregation of per-slot READY,
    - Interrupt routing and Mode-2-style acknowledge.

- **Safety / bring-up:**
  - System must remain in a benign state until:
    - CPLD window table and IRQ routing are configured,
    - Power-good lines indicate stable rails,
    - MCU explicitly releases system reset.
  - External JTAG remains mandatory for CPLD recovery even if in-system update hooks exist.

- **Documentation discipline:**
  - The merged **Dock Digital System Architecture** file is the authoritative spec; diaries and DoD stamp describe intent and history but are non-normative.
  - Power details (USB current budget, PD roles, etc.) live in the Power Architecture and are only referenced, not duplicated.

---

## Rejected Ideas (with Reasons)

- **Using only MCU GPIOs for CPLD configuration:**
  - **Reason:** Blew through GPIO budget once Slot 0, USB, UART+RTS/CTS, power control, and debug signals were counted.
  - **Impact:** Would have forced ugly compromises (dropping flow control, losing debug lines, or multiplexing pins).
  - **Decision:** Move all config and slow control to MCP23017; keep direct GPIOs for timing-critical functions.

- **Per-port USB power switching in v1 Dock:**
  - **Reason:** Requires at least 4 extra MCU GPIOs, 4 load switches, additional fault monitoring and firmware logic.
  - **Impact:** Increases complexity, layout effort, BOM cost, and GPIO pressure with limited benefit for HID-only usage.
  - **Decision:** Use a **single shared PPTC/eFuse** for all 4 ports; handle faults via hub reset and user-level intervention. Leave per-port control as a future “builder upgrade.”

- **Over-specifying Dock Services register map inside the architecture doc:**
  - **Reason:** Register-level detail is likely to iterate as firmware and higher-level use cases (RTC, HID, power) evolve.
  - **Impact:** Would freeze too many details prematurely, forcing doc churn with each firmware experiment.
  - **Decision:** Architecture doc describes **categories and behavior**, but the normative register map will live in a separate “Dock Services Tile” spec.

- **Relying solely on MCU-driven CPLD bitstream updates:**
  - **Reason:** Removes a hard recovery path if MCU firmware or update protocol misbehaves.
  - **Impact:** Risky for prototypes and field updates; unacceptable for a builder-friendly platform.
  - **Decision:** Hardware supports in-system updates, but **external JTAG** remains the primary and mandatory recovery mechanism.

---

## Open Questions

- **Final MCP23017 bit mapping:**
  - Which exact bits/ports drive:
    - `addr_decoder_cfg_*` bus,
    - `irq_router_cfg_*` bus,
    - Any remaining slow control lines?
  - Needs to be locked in and mirrored between:
    - Dock schematic,
    - `DECODER_CONFIGURATION.md`,
    - CPLD HDL config port definitions.

- **Exact ESP32-S3 GPIO assignment table:**
  - We still need a concrete `esp32s3_gpio_assignments.md` that:
    - Picks real pin numbers for Slot 0 bus, HUB_RESET#, power control, I²C, UART, debug LEDs, etc.,
    - Respects all strapping rules and boot constraints for the module.

- **Dock Services Tile register map:**
  - How to slice the address space cleanly between:
    - Identification/status,
    - RTC access,
    - Power and soft-control,
    - USB HID (keyboard/mouse/gamepad),
    - Debug / CPLD introspection.
  - Needs its own spec and some practical firmware experiments.

- **Test and bring-up strategy for USB hub and HID stack:**
  - Exact plan for:
    - Probing the hub via the monitor,
    - Exercising enumeration (fake keyboard/mouse scripts),
    - Validating the HID → Slot 0 register translations on a real Host CPU.

- **Scope of Dock-local sensors / telemetry:**
  - Which I²C sensors (temp, current, voltage) are truly worth adding on CH0 versus leaving space for future Tiles?

---

## Notes

- **Today’s main outcome:**  
  The Dock Digital Architecture moved from “iterating with two models (Claude + ChatGPT) and scattered notes” to a **merged, internally consistent spec** with a formal Definition-of-Done stamp. This closes the architecture phase and unlocks schematic work.

- The merged document now:
  - Clearly ties the Dock MCU, CPLD, I²C fabric, USB hub, and Virtual Slot 0 into a single mental model.
  - Aligns with the **Core Logical Specification**, Dock spec, and Power Architecture without contradictions.
  - Provides a clean KiCad hierarchical-sheet contract so schematic capture can proceed without guessing at the boundaries.

- The GPIO-expander compromise turned out to be a good fit:
  - It respects the user’s instinct of “**real-time on direct GPIO, configuration over I²C is fine**.”
  - It preserved the existing HDL and avoided another round of rework in the decoder/IRQ router.

- The DoD report is effectively a **snapshot of architectural intent**:
  - What changed (and why),
  - Which trade-offs were accepted,
  - What remains flexible for later phases.

---

## Next Steps

- Spin up a **Dock Digital** KiCad hierarchical sheet using the interface table as the pin contract.
- Draft and iterate on `esp32s3_gpio_assignments.md` until it aligns with:
  - The architecture doc,
  - ESP32-S3 strap/boot constraints,
  - PCB layout realities.
- Lock down MCP23017 bit assignments and update:
  - Schematic symbols/nets,
  - CPLD config HDL,
  - `DECODER_CONFIGURATION.md`.
- Start sketching a **Dock Services Tile** register map, starting with:
  - RTC + basic status,
  - Minimal USB HID keyboard/mouse registers,
  - A small introspection window for CPLD config/state.

