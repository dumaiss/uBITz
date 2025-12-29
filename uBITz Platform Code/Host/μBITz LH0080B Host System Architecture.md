# μBITz LH0080B Host System Architecture

## 1. Overview

This document defines the **architecture** for a μBITz Host card built around a **Sharp LH0080B** (Z80-compatible) CPU, with:

- A **5V “CPU island”** (CPU + legacy TTL)
- A **3.3V μBITz backplane interface**
- **24-bit effective memory addressing** (CPU 16-bit + mapper adds 8 bits ⇒ 24-bit)
- μBITz bus declared as **AddressBusWidth = 32** (upper unused address bits tied low)

This is an architecture-only document intended to gate **schematic capture**.

---

## 2. Goals and Non-Goals

### Goals
- Provide a practical, buildable Z80-class Host for μBITz (Dock + Bank + Tiles).
- Meet μBITz requirements:
  - **AddressBusWidth = 32**
  - **DataBusWidth = 8**
  - **ROM resides in Bank**
  - **No memory-map reservations** in this document (policy is configurable).
- Support up to **6 MHz** CPU clock with margin through conservative component choices.
- Keep the design hobbyist-friendly (no exotic power sequencing, no FPGA dependency).

### Non-Goals
- Freezing a definitive memory map (ROM/RAM windowing policy is left configurable).
- Guaranteeing CLK_REF compatibility across all Tiles (Host-dependent by design).
- Final timing closure (validated during prototype + layout with trace-aware timing).

---

## 3. System Context and Constraints

### 3.1 Voltage Domains
- **5V**: CPU island (LH0080B, SN74LS612, any 74LS/TTL glue as needed)
- **3.3V**: μBITz bus (Dock backplane)

Dock is assumed to provide both rails. No local regulation is required for v1.

### 3.2 Bus Width Declaration
- μBITz bus is declared **32-bit addressing**.
- This design drives **A[23:0]** and ties **A[31:24] = 0**.

### 3.3 Interrupt Model
- CPU exposes only:
  - `/INT` (maskable interrupt)
  - `/NMI` (non-maskable interrupt)
- Dock/Tiles may expose multiple interrupt channels; Host combines them down to `/INT` and `/NMI`.

---

## 4. High-Level Block Diagram (ASCII)

```text
                     μBITz Host Card (LH0080B)
┌────────────────────────────────────────────────────────────────────┐
│  5V CPU Island                                                     │
│                                                                    │
│  ┌──────────┐   A[15:0]   ┌──────────────┐   A_ext[23:16]         │
│  │ LH0080B  │────────────►│ SN74LS612     │───────────────┐       │
│  │ (Z80)    │             │ Memory Mapper │               │       │
│  └────┬─────┘             └──────┬───────┘               │       │
│       │  D[7:0]                 │ (map ctl)               │       │
│       │                          ▼                        │       │
│       │                    ┌──────────────┐               │       │
│       │                    │ ATF1504AS    │               │       │
│       │                    │ CPLD         │               │       │
│       │                    │ (glue +      │               │       │
│       │                    │ μBITz adapt) │               │       │
│       │                    └──────┬───────┘               │       │
│       │                           │                       │       │
│       │                           │ DIR/OE, /CPU_ACK,     │       │
│       │                           │ /READY↔/WAIT,         │       │
│       │                           │ /IORQ,/MREQ,R/W_,     │       │
│       │                           │ INT combine           │       │
│       │                           │                       │       │
│       └──────────────┬────────────┴──────────────┬────────┘       │
│                      │                           │                │
│                      ▼                           ▼                │
│                 ┌──────────┐               ┌──────────┐           │
│                 │ Level    │               │ Host      │           │
│                 │ Shifters │               │ Descriptor│           │
│                 │ 5V↔3V3   │               │ EEPROM    │           │
│                 └────┬─────┘               └────┬─────┘           │
│                      │                          │ I²C             │
└──────────────────────┼──────────────────────────┼─────────────────┘
                       │                          │
                       ▼                          ▼
                 μBITz Core Connector        μBITz I²C Fabric
                 (3.3V bus levels)          (3.3V I²C)

A[31:24] are tied low (0). A[23:0] driven via LS612 + translation.

             5V CPU ISLAND                   3.3V μBITz BUS
```

---
## 5. Component Selection

### 5.1 CPLD (Glue / Cycle Qualifiers / DIR Control / Mapper Control)

**Selected:** `ATF1504AS-10AU44`

Rationale:
- Enough logic for:
  - cycle qualification (/MREQ vs /IORQ handling)
  - generating μBITz qualifiers (`/MEM0_CS`, `/MEM1_CS`, `R/W_`, `/CPU_ACK`)
  - data-transceiver DIR/OE control
  - clock divide and basic safety interlocks
  - optional mapper control exposure (host-defined)

Resource estimate (order-of-magnitude):
- ~40 macrocells class (cycle qualifier + interrupt combine + DIR safety + clock divide + misc glue)
- 64 macrocell device provides margin.

#### CPLD pin budget (validation)

**ATF1504AS-10AU44 provides 32 user I/O pins** in the 44-lead package.

A practical breakdown (two cases):

**A) Minimal CPLD pin case (~22 pins)**
Assumes:
- Only a *small subset* of address bits are used for internal I/O windowing, or decode is done with minimal external glue.
- Address/data buses do not route through CPLD.

Pins (approx):
- CPU control inputs: `/MREQ`, `/IORQ`, `/RD`, `/WR`, `/M1`, `/RESET` → ~6
- μBITz bus inputs: `/READY`, `CPU_INT[x]`, `CPU_NMI[x]` → ~6–8
- CPU outputs: `/WAIT`, `/INT`, `/NMI` → ~3
- μBITz qualifiers outputs: `/MEM0_CS`, `/MEM1_CS`, `R/W_`, `/CPU_ACK` → ~4
- Data-transceiver control: `DIR`, `/OE` → ~2

**Total:** ~21–23 pins (≈65–72% of 32)

**B) “Decode-in-CPLD” case (~28–30 pins)**
Adds:
- CPU `A[7:0]` into CPLD for clean I/O window decode → +8 pins

**Total:** ~29–31 pins (tight but still feasible; leaves minimal headroom)

**Conclusion:** The ATF1504AS-10AU44 fits, but decide early whether I/O decode lives in CPLD or in small external decode.

---

### 5.2 Address / Control Level Shifting (5V → 3.3V)

**Selected:** `SN74LVC245A` (multiple as needed)

Rationale:
- 5V-tolerant inputs when powered at 3.3V
- Fast enough for 6 MHz-class bus timing
- Unidirectional use is straightforward (Host → Dock)

Timing note (use worst-case numbers in budgeting):
- Datasheet feature summary indicates **max propagation delay ≈ 6.3 ns at 3.3V**.

---

### 5.3 Data Bus Level Shifting (Bidirectional)

**Selected:** `SN74LVC8T245` (DIR-controlled dual-supply transceiver)

Rationale:
- Explicit **DIR** control avoids ambiguous auto-direction behavior in shared buses.
- Suitable for true bidirectional data bus behavior across voltage domains.

Timing note (use worst-case numbers in budgeting):
- Representative switching characteristics show **low-single-digit ns** class delays (order of ~5 ns worst-case).

---

### 5.4 Open-Drain Control Buffers (Optional / as needed)

**Candidate:** `SN74LVC1G07` (open-drain buffer)

Used when a signal must behave as **true “low-wins”** at the electrical level (wired-AND semantics).
(Exact usage depends on whether a net is shared vs single-driver in the μBITz profile.)

---

### 5.5 Address Expansion (Memory Mapper)

**Selected:** `SN74LS612`

Role:
- Provides **banked mapping** to expand effective memory addressing by **8 bits**
  (CPU 16-bit → **24-bit effective** memory offset).

Notes:
- This part is legacy TTL and should be treated as a significant power consumer.

---

### 5.6 Host Descriptor EEPROM (“Descriptor Island”)

**Candidate:** `24LC08` (or equivalent 1KB+ I²C EEPROM)

Requirements:
- At least **1KB** for descriptor and future expansion.
- Lives on μBITz I²C management bus (not inside CPLD).

---

### 5.7 Clock Source

**Selected:** `14.31818 MHz` oscillator (NTSC colorburst-derived frequency)

Rationale:
- Common, stable, easy to source
- Allows dividing down to **3.579545 MHz** (/4) and other integer-ish rates via CPLD logic.

---

## 6. Power Architecture

### 6.1 Rails
- **5V**: CPU island primary rail
- **3.3V**: μBITz bus / translator-side rail
- No additional rails required.

### 6.2 Decoupling Strategy
- 0.1 µF per IC (placed at each VCC pin pair)
- Bulk:
  - 10–47 µF near CPU island entry
  - 10–47 µF near translator cluster
- If noise is observed in prototype:
  - add ferrite bead isolation between Dock 5V and CPU island 5V (optional)

### 6.3 Power Budget (conservative planning numbers)

| Block | Rail | Current (typ / max) | Status |
|------:|------|----------------------|--------|
| LH0080B CPU | 5V | up to ~200 mA | datasheet-based |
| SN74LS612 | 5V | ~112 mA typ, up to ~230 mA (mode-dependent) | datasheet-based |
| ATF1504AS CPLD | 5V | ~40 mA (budget placeholder) | estimate (verify) |
| Translators (245 + 8T245) | 3.3V | ~20 mA (budget placeholder) | estimate (verify) |
| EEPROM + misc | 3.3V | <5 mA | estimate |

**Planning total (worst-case):** on the order of **~0.45–0.50 A combined** (dominated by 5V CPU + LS612)

**Action:** validate with real measurements early (prototype bring-up).

---

## 7. Clocking Strategy

### 7.1 CPU clock
- Oscillator feeds CPLD.
- CPLD generates **CPU_CLK** via divider.
- Target: configurable “up to 6 MHz” (exact set of divisors is a Host implementation choice).

### 7.2 CLK_REF policy (μBITz backplane)
- Host may optionally export **CLK_REF** derived from its oscillator/divider.
- This is a Host-specific convenience, not guaranteed by μBITz across all Hosts.

---

## 8. Reset Strategy

- `/RESET` is sourced from Dock/backplane and distributed to:
  - CPU `/RESET`
  - CPLD reset input (so internal state machines start clean)
- Add a **reset indicator LED** driven from `/RESET` (through appropriate buffering/resistance).

---

## 9. μBITz Bus Interface

### 9.1 Address bus (declared 32-bit)
- Drive:
  - `A[23:0]` = mapped memory offset (or I/O offset during I/O cycles)
  - `A[31:24]` = 0

### 9.2 Data bus (8-bit)
- Bidirectional via `SN74LVC8T245` (DIR + OE controlled by CPLD).
- DIR safety rules:
  - Never enable both sides simultaneously in opposite directions.
  - Switch direction only when bus is idle (or during defined turnarounds).

### 9.3 Control / Qualifiers
CPLD is responsible for producing clean μBITz qualifiers:
- `/MREQ` and `/IORQ` qualification as required by μBITz timing rules
- `R/W_` derived from CPU read/write strobes
- `/MEM0_CS` and `/MEM1_CS` (policy-defined; no fixed windows reserved here)
- `/CPU_ACK` generation for interrupt acknowledge (Z80 IM2-style)

`/READY` from Bank/Dock is adapted to Z80 `/WAIT` behavior.

---

## 10. Address Expansion and Mapping

### 10.1 Effective address growth
- CPU presents 16-bit address.
- Mapper provides additional **8 bits**, yielding **24-bit effective** memory offset.

### 10.2 Page model (conceptual)
- 4KB-page class mapping (lower address bits pass through; upper bits mapped).
- Mapping policy (identity map, banked RAM, ROM windows, etc.) is **TBD and configurable**.

### 10.3 Mapper control interface
- CPLD must provide an internal control mechanism for the mapper:
  - register programming
  - map enable/disable behavior
  - safe updates (avoid half-written mappings)
- **No I/O port allocation is standardized here.** That convention is left to Host firmware/software.

---

## 11. Interrupts and CPU_ACK

### 11.1 Interrupt combining
- Combine Dock interrupt channels down to CPU pins:
  - Any asserted `CPU_INT[x]` ⇒ CPU `/INT` asserted (active-low “low-wins” combine)
  - Any asserted `CPU_NMI[x]` ⇒ CPU `/NMI` asserted

### 11.2 Interrupt acknowledge
- Generate `/CPU_ACK` in the Z80 interrupt acknowledge condition (e.g., `/M1` + I/O acknowledge behavior).
- Ensure the Dock/Tiles can present an interrupt vector during the acknowledge phase as required.

---

## 12. Programming, Debug, and Test

### 12.1 CPLD programming
- Provide JTAG header for ATF1504AS programming.

### 12.2 Recommended test points
Minimum:
- 5V, 3.3V, GND
- CPU_CLK, CLK_REF (if present)
- `/RESET`
- `/MREQ`, `/IORQ`, `/RD`, `/WR`, `/WAIT`
- DIR, /OE of data translator
- `/MEM0_CS`, `/MEM1_CS`, `/READY`

### 12.3 Bring-up hooks (recommended)
- Optional clock divide “safe mode” strap (boot at slow clock)
- Optional “mapper disabled / identity map” strap for early debug

---

## 13. Risk Summary Table

| Risk | Before | After | Mitigation / Note |
|------|--------|-------|-------------------|
| CPLD too small | HIGH | LOW | ATF1504AS class device selected with margin |
| Level shifting timing | HIGH | MED | Use explicit DIR transceiver; validate in prototype |
| Power budget unknown | HIGH | MED | Conservative budget added; measure early |
| Mapper programming complexity | MED | MED | Keep policy/config flexible; define safe update rules |
| CLK_REF expectations | MED | LOW | Explicitly Host-dependent; document as non-guaranteed |
| Multi-interrupt fan-in | MED | LOW | Combine in CPLD; keep electrical semantics “low-wins” |

---

## 14. Pre-Schematic Checklist

### ✅ Resolved / Ready
- 5V CPU island + 3.3V bus partitioning
- CPLD family/size chosen (ATF1504AS-10AU44 class)
- Translator families chosen (LVC245A + LVC8T245)
- CLK source frequency chosen (14.31818 MHz)
- AddressBusWidth=32 strategy: drive A[23:0], tie A[31:24]=0
- ROM-in-Bank assumption confirmed

### ⚠️ Deferred (but tracked)
- Exact clock divisor set and strap strategy (prototype-defined)
- Final I/O decode strategy (CPLD vs external decode) and its pin impact
- Final mapper register model + software convention (no reservation here)
- Timing spreadsheet using real trace length estimates (layout phase)
- DIR/OE safety HDL review (implementation verification)
- Measured current draw on real hardware (bring-up)

---

## 15. Component BOM Summary (architecture-level)

| Ref    | Function                    | Suggested Part    | Qty       | Notes                                         |
| ------ | --------------------------- | ----------------- | --------- | --------------------------------------------- |
| U1     | CPU                         | LH0080B           | 1         | Z80-compatible                                |
| U2     | Address expansion / mapping | SN74LS612         | 1         | Legacy TTL; power-heavy                       |
| U3     | CPLD glue                   | ATF1504AS-10AU44  | 1         | JTAG programmable                             |
| U4..U6 | Addr/control shift          | SN74LVC245A       | ~2–4      | Depends on how many control lines grouped     |
| U7     | Data shift (bi-dir)         | SN74LVC8T245      | 1         | DIR/OE controlled                             |
| U8     | Descriptor EEPROM           | 24LC08 (or equiv) | 1         | ≥1KB                                          |
| X1     | Oscillator                  | 14.31818 MHz      | 1         | Feeds CPLD clock logic                        |
| (opt)  | Open drain buffer           | SN74LVC1G07       | as needed | Only for nets requiring low-wins electrically |

Costs are intentionally omitted here (part availability/price varies; fill from your preferred suppliers when finalizing BOM).

---

## 16. Open Items and Validation Plan

### 16.1 Architecturally resolved
- Major component classes selected (CPU / mapper / CPLD / translators / EEPROM)
- 32-bit bus declaration strategy (upper 8 bits tied low)
- 5V/3.3V partitioning concept

### 16.2 Still open (must be decided during schematic/HDL)
- I/O decode placement (CPLD vs external decode) and resulting CPLD pin usage
- Mapper control exposure (register model + safe update rules)
- DIR/OE state machine rules and proof against bus-fight
- Clock divisor set (and whether strap-based selection is needed)

### 16.3 Must validate in prototype
- Real current draw on 5V rail under worst-case toggling
- /READY↔/WAIT timing behavior through translators + CPLD
- Interrupt acknowledge vector timing with Dock/Tiles

### Sources

* Microchip ATF1504AS family datasheet (macrocells and 44-lead user I/O count).
* TI SN74LVC245A datasheet (feature summary includes max propagation delay at 3.3V). ([Texas Instruments][1])
* TI SN74LVC8T245 datasheet (switching characteristics table; ns-class delays). ([Hazymoon][2])
* Sharp LH0080B datasheet scan (DC characteristics / current consumption line item). 
* SN74LS612 datasheet scan (supply current figures by mode). 
* Additional LS612 behavior summary (address expansion description; secondary reference). 

[1]: https://www.ti.com/lit/gpn/SN74LVC245A "SN74LVC245A Octal Bus Transceiver With 3-State Outputs datasheet (Rev. X)"
[2]: https://www.hazymoon.jp/OpenBSD/annex/docs/74LS612.pdf "DATASHEET SEARCH SITE | WWW.ALLDATASHEET.COM"
