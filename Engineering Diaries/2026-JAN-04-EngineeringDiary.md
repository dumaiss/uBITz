# μBITz Engineering Diary

> Central engineering log for μBITz: decisions, constraints, rejected ideas, open questions.

---

## 2026-01-04– Daily Engineering Diary

### Decisions

* **Buffered Dock / internal 3.3 V domain**: The Dock becomes an active, buffered backplane. Dock logic remains strictly 3.3 V.
* **Per-slot VIO selection (3.3 V or 5 V)**: Each slot declares its I/O logic voltage via a strap pin; the Dock generates a per-slot VIO rail to power slot-facing translator supplies.
* **Two strap pins per slot**:
  * **`SLOT_PRSNTn`** (presence): card straps to GND → present.
  * **`SLOT_VIO5Vn`** (I/O voltage select): card straps to GND → **5 V I/O**; float → **3.3 V I/O**.
* **Bus-mastering electrical readiness**: Keep existing `/BUS_REQ[n]` (per-slot) + single `/BUS_GNT` (Host→Dock). Dock FPGA only *samples* `/BUS_GNT` (never drives).
* **Per-slot gating**: Data bus `D[]` is gated per-slot with `/OE`. Address `A[]` is gated using the same slot-selection decision (wired for bus mastering later).

### Constraints

* Timing budget target: **~50–70 ns** for combinational decisions that must affect bus gating.
* Must handle:
  * Empty slot: one side of transceivers unconnected.
  * CPU Hi‑Z phases (e.g., 6809/6309 HALT/hold states).
  * No “GPIO0..5 presence” assumptions; presence is explicit via strap.
* Avoid new edge-connector pins for bus mastering (no “B72 sacrifice”).

### Rejected Ideas (and why)

* **Auto-bidirectional shifters for the main bus (TXS/TXB for A[]/D[])**: direction and heavy bus loading are better handled with explicit DIR/OE devices.
* **Occupancy by inference (no presence pin)**: attractive, but creates ambiguous “empty == universal” edge cases and complicates default-safe behavior.

### Open Questions

* Do we want to gate address for **all** non-master slots (broadcast address) or only the selected target slot (point-to-point address)?
* Do we need any “bus hold / keeper” behavior on internal bus nets to reduce floating/noise during Hi‑Z phases?

### Notes

* The voltage straps are **logic-interface declarations only**. Slot power rails (5 V and 3.3 V) are provided by the Dock as defined elsewhere.

---

# Mini-Architecture: Buffered Dock Voltage + Bus Transceivers

> Purpose: A practical wiring and control model for (1) per-slot VIO selection, (2) per-slot bus gating, and (3) safe behavior with Hi‑Z and empty slots.

## 1) Principles

1. **Dock logic is always 3.3 V.** Dock FPGA/MCU never sees 5 V levels directly.
2. **Slots may be 3.3 V-I/O or 5 V-I/O.** The Dock adapts electrically per slot.
3. **Explicit direction + explicit enable.** Bus translation uses devices with `DIR` and `/OE` (no “guessing” direction).
4. **Safe defaults.** When uncertain (boot, empty slot, strap missing), the Dock defaults to:
   * Slot **disabled** (bus isolated)
   * Slot VIO = **3.3 V**
5. **Bus-mastering wiring is present even if not implemented yet.** The Dock will already have:
   * per-slot `/BUS_REQ[n]` input(s)
   * a single `/BUS_GNT` input from Host (safe-to-switch indication)
   * transceivers wired so DIR/OE can be switched later

## 2) Strap pins and semantics

### 2.1 `SLOT_PRSNTn` (Presence)

* Dock side: **10 kΩ pull-up to +3V3_AON**.
* Card side: **strap to GND**.

Interpretation:
* `SLOT_PRSNTn=0` → **card present**
* `SLOT_PRSNTn=1` → **empty slot**

### 2.2 `SLOT_VIO5Vn` (Slot I/O voltage select)

* Dock side: **10 kΩ pull-up to +3V3_AON**.
* Card side:
  * strap to GND → **5 V I/O**
  * float → **3.3 V I/O**

Interpretation:
* `SLOT_VIO5Vn=0` → slot interface is **5 V**
* `SLOT_VIO5Vn=1` → slot interface is **3.3 V**

Rationale:
* Empty slot naturally reads `1` (pulled up) → defaults to **3.3 V** selection.

## 3) Per-slot VIO rail generation

Define `VIO_SLOT[n]` as the **slot-facing supply** for bus transceivers and any Dock→slot output buffers.

Requirements:
* `VIO_SLOT[n]` MUST be **off** when:
  * main rails are off, OR
  * slot is empty (`SLOT_PRSNTn=1`)
* `VIO_SLOT[n]` MUST be **3.3 V** when `SLOT_VIO5Vn=1`
* `VIO_SLOT[n]` MUST be **5 V** when `SLOT_VIO5Vn=0`

Implementation sketch:
* Gate VIO with `SLOT_EN[n] = MAIN_ON && (SLOT_PRSNTn==0)`
* Select between +3V3_MAIN and +5V_MAIN using `SLOT_VIO5Vn`.

## 4) Direction and enabling

### 4.1 Signal groups

**Group A — Address bus (`A[]`)**
* Treated as “master → target” only.
* Routed through direction-controlled, tri-statable transceivers.

**Group D — Data bus (`D[]`)**
* Bidirectional, but only **two participants** should be enabled at a time (initiator + responder).

**Group C — Control from Dock (`/CS[n]`, `/INT_ACK[n]`, etc.)**
* Generated in Dock logic (3.3 V) and level-shifted to `VIO_SLOT[n]`.
* Optional: tri-state when slot disabled.

**Group I — Slot→Dock status/requests (`/INT`, `/NMI`, `/BUS_REQ[n]`, etc.)**
* Observed by Dock/Host; level-shift into Dock’s 3.3 V domain.

### 4.2 `/OE` policy

Core rule:
* If a slot is **not selected**, its bus transceivers MUST be **disabled** (`/OE=1`).

Practical baseline (no bus mastering implemented yet):
* A transaction selects **exactly one target slot**.
* Enable:
  * Host slot transceivers as needed for the transaction direction.
  * Target slot transceivers as needed.
* Disable:
  * All other slots.

### 4.3 `DIR` policy

Define two conceptual “roles” during a transaction:
* **Initiator**: the bus master (today: Host)
* **Responder**: the selected device slot

For `D[]` (data):
* Write cycle: Initiator drives data → Responder receives.
* Read cycle: Responder drives data → Initiator receives.

For `A[]` (address):
* Initiator drives address; responder(s) receive.

**Future bus mastering:**
* When implemented, the Initiator role can move from Host to a Tile.
* The DIR/OE wiring is already prepared: the Dock only needs to change the role assignment.

## 5) Hi‑Z and empty-slot behavior

### 5.1 Empty slot

If `SLOT_PRSNTn=1` (empty):
* `VIO_SLOT[n]` is **off**.
* All `A[]/D[]` transceivers for that slot are **disabled** (`/OE=1`).
* Dock→slot outputs (like `/CS[n]`) are either:
  * disabled (preferred), OR
  * driven but harmless (no receiver).

This prevents a “floating far-end” from injecting noise into the internal bus fabric.

### 5.2 CPU / bus owner Hi‑Z phases

When the current bus owner (e.g., 6809/6309 in a hold state) drives the external bus Hi‑Z:

* The Dock MUST treat address/data as **undefined** unless the cycle qualifier indicates an active transaction.
* Control qualifiers (`/IORQ`, `/MREQ`, `/CS` generation policy, etc.) should have **safe pull-ups** so that an idle/Hi‑Z bus does not look like a valid transaction.

Optional hardening:
* Weak pulls (e.g., 47 kΩ–100 kΩ) or “keeper” behavior on internal `A[]/D[]` nets can reduce chatter during Hi‑Z, but is not strictly required if decode is properly qualified.

## 6) Broadcast vs intercepted/forwarded

### Observed by Dock only (not forwarded)

* `SLOT_PRSNTn` and `SLOT_VIO5Vn` (strap pins)
* `/BUS_GNT` (Host → Dock, sampled only)

### Intercepted and forwarded/used in routing

* `/BUS_REQ[n]` (Tile/Bank → Host/Dock arbitration path)
* Slot interrupts (`/INT_CHx`, `/NMI_CH`) into Dock for routing/ack.

### Dock-generated per-slot outputs

* `/CS[n]`, `/INT_ACK[n]` (and any per-slot control qualifiers)

### Shared/broadcast timing signals

* `/RESET` (global)
* Clock distribution signals (as defined by the profile)

---

# Suggested Parts (starting point)

> Goal: parts that support 3.3 V on the Dock side and 3.3 V / 5 V selectable on the slot side, with explicit `DIR` and `/OE`, and with powered-off isolation.

## A) Main bus translators (Address/Data)

Pick one of these “DIR + /OE, dual-supply” families for `A[]` and `D[]`:

1. **TI SN74LVC8T245 / SN74LVC16T245**
   * Dual-supply, `DIR` + `/OE`.
   * Wide supply range suitable for **3.3↔5 V** translation.
   * 16-bit variant reduces chip count for wide buses.

2. **Nexperia 74LVC8T245 / 74LVCH8T245**
   * Similar role: dual-supply translating transceiver.
   * Wide VCC(A)/VCC(B) range including **5.0 V**.

3. **TI SN74LVCC3245A** (3.3↔5 focus)
   * Port A around 3.3 V domain, Port B supports 5 V domain.
   * Good fit when Dock-side is always 3.3 V and slot-side is 3.3/5.

Selection notes:
* Prefer devices that specify **powered-off isolation / partial power-down** behavior.
* Use the same family consistently to reduce verification burden.

## B) Dock → slot control outputs (per-slot voltage)

1. **SN74LV1T34** (single-supply level-shifting buffer)
   * Power at `VIO_SLOT[n]` so output matches slot I/O voltage.
   * Feed with Dock 3.3 V logic.

2. **SN74LVC1T45 / SN74LVC2T45** (dual-supply, fixed direction)
   * Use when you want explicit dual-rail translation with `DIR`.

## C) I²C (enumeration)

1. **PCA9306** (I²C/SMBus translator with EN)
   * Simple, bidirectional, designed for I²C.

2. **TXS0102**
   * Works for open-drain and some push-pull low-speed signals.
   * Prefer PCA9306 for “pure I²C”.

## D) Per-slot VIO selection (3.3 vs 5)

Two practical patterns:

1. **Power MUX per slot (simple, integrated)**
   * Example: **TPS2113A** (2.8–5.5 V range)
   * Use strap logic to select which input becomes `VIO_SLOT[n]`.

2. **Two load switches (cheap, flexible)**
   * Example: **TPS2291x / TPS2296x** family for each rail.
   * Drive enables as complements of `SLOT_VIO5Vn` (and also gate with slot presence + MAIN_ON).

## E) Small glue logic

* **74HC04 / 74LVC1G04** (inversion)
* **74HC00 / 74LVC1G00** (NAND)
* **74LVC1G08** (AND)

Use only where it reduces FPGA timing pressure or simplifies bring-up/debug.

