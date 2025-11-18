# μBITz Dock Specification v1.0

# μBITz Dock Specification v1.0

## μBITz Platform I/O Bus Architecture

---

# Part 0 — Overview, Rationale, and Scope

## 0.1 What is μBITz Dock?

μBITz Dock is a small, modular I/O-only expansion interconnect for multi-platform retro-modern systems. It standardizes a simple, Z80-like I/O model (windowed, register-file semantics) while allowing multiple physical realizations (“profiles”) that fit different build styles. It implements function-routing (as opposed to geographic or address routing). The CPU board implements a complete platform (C64, Apple II, ZX Spectrum, etc.) while peripheral cards provide standardized devices (video, sound, storage, I/O) that work across platforms.

Across all profiles, software sees **the same logical device model**: functions (windows), registers, interrupts, and enumeration.

**Key Design Principles:**
- One CPU card
- Up to 4 peripheral cards
- I²C enumeration with EEPROM-based configuration
- Function-based addressing
- Interrupt routing with CPU-defined mapping

## **0.2 Design Philosophy Statement**

Design Principle: Appropriate Complexity

μBITz targets hobbyist and enthusiast systems where:

- Trace lengths are <6 inches (backplane only)
- Data rates are modest (100 Mbps)
- Applications are not safety-critical
- Debugging tools are available (scope, logic analyser)

Therefore, we prioritize:
✓ Simplicity over redundancy
✓ Performance over absolute integrity
✓ Ease of implementation over comprehensive protection
✓ Clear failure modes over silent error correction

If your application requires:

- Safety certification (medical, automotive, aerospace)
- Cryptographic integrity (tamper detection)
- Long-distance communication (>1 meter)
- Harsh environments (industrial, military)

Then μBITz is not the appropriate standard. Use PCIe, CAN bus,
or other certified protocols designed for those requirements.

As the specification author has stated: "I'm going to personally
hunt you down and smack you on the head if you use this standard for
critical applications." You have been warned. 😄

## 0.3 Why we made it

- **Bridge retro and modern**: Keep 8/16-bit CPU friendliness while scaling up to 24-bit address and 32-bit data paths.
- **Hobbyist-first**: Readable timing, READY wait-state stretching, open-drain interrupts, and widely available connectors.
- **Portability**: The same driver works on Serial, Parallel, and Minimal builds.
- **Learning & reuse**: Clean separation between logic and physical layers; a single spec with multiple parts.

## 0.4 Who this targets (and who it doesn’t)

**Targets**

- Hobbyists and educators building retro-style computers.
- Board/device designers who want a portable register interface.
- Firmware developers writing drivers once for all profiles.
- Portable device builders (Minimal profile) using an MCU to emulate many peripherals.

**Non-targets**

- Safety-critical or life-support systems.
- PCI/PCIe compatibility (μBITz is not PCI/PCIe).
- Cache-coherent shared memory, DMA buses, or hot-plug at arbitrary points (unless explicitly stated in a profile).

## 0.5 Design principles

1. **One logical model, many physiques**
    
    Functions/windows + registers are **identical** across profiles.
    
2. **Simple, deterministic semantics**
    
    Synchronous reads/writes; **/READY** can stretch cycles. No hidden retries.
    
3. **Scaled but bounded widths**
    
    CPU declares **AddressBusWidth ∈ {8,16,32}**, **DataBusWidth ∈ {8,16,32}**.
    
    - Serial: backplane/devices MUST support the CPU’s declared widths or fail enumeration.
    - Parallel: connector always exposes **A[31:0], D[31:0]**; backplane/devices adapt.
4. **Interrupts that fit retro mental models**
    
    **/INT_CH[3:0]** and **/NMI_CH[3:0]**. Optional **Mode-2-style acknowledge** using **/INT_ACK[3:0]**; device returns an **8-bit vector index**, CPU supplies the vector base from its I register.
    
5. **Encoding that favors debuggability**
    
    Serial uses 10-bit symbols (**4b + parity + 4b + parity**) instead of 8b/10b. Easy to probe and reason about.
    
6. **Stable, commodity connectors**
    - Serial: **M.2** (PRO pin philosophy; no “straps/locks”).
    - Parallel: **PCIe x16** edge; **do not reassign power/ground pins**; use **3.3 V** and optional **5 V** only; **no 12 V** usage.
7. **Single profile per backplane**
    
    No mixing Serial/Parallel on the same backplane. Reduces ambiguity and build cost. Implementers can easily develop carrier bridge cards Serial ↔ Parallel
    
8. **Descriptors & enumeration**
    
    I²C EEPROMS describe CPU and devices. Minimal may omit CPU EEPROM; MCU uses defaults.
    
9. **Availability & serviceability**
    
    Through-hole-friendly options (Parallel), simple probing, predictable power domains.
    

## 0.6 Non-goals (v1.0)

- Bus mastering/DMA and cache coherency.
- Dynamic re-assignment of power/ground on standardized connectors.
- Cross-profile adapters in the same chassis.

## 0.7 Profiles at a glance

| Part | Profile | Connector / Physical | Width Exposure | Slots | Encoding / Transfer | Notes |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | **Core** | (logical only) | A: 8/16/32; D: 8/16/32 (declared by CPU) | — | — | Windows/registers, interrupts, descriptors |
| 2 | **Serial** | M.2 (LVDS pairs) | Must honor CPU-declared widths | 1–4 | 10-bit (4b+P,4b+P) | Same logical semantics; /INT_ACK[3:0] at CPU boundary |
| 3 | **Parallel** | PCIe x16 (repurposed) | **Always** A[31:0], D[31:0] on connector | 1–4 | Parallel bus | Keep PCIe PWR/GND pin roles; 3.3 V + optional 5 V; no 12 V |
| 4 | **Minimal** | CPU↔backplane: Parallel header | As per Parallel at CPU boundary | n/a | Internal bridge | MCU side serializes via reference bridge; optional CPU EEPROM |
| 5 | **Ref Impl** | Serial reference design | Matches Part 2 | n/a | Matches Part 2 | HDL/firmware, tools, examples |

## 0.8 Normative language

Keywords **MUST**, **SHOULD**, **MAY**, **MUST NOT**, **SHOULD NOT** are normative. Informative notes are labeled “Note”.

## 0.9 Compliance model (overview)

- **CPU compliance**: publishes valid descriptor (widths, IntAckMode). Handles /READY. In Mode-2, uses internal I register; expects 8-bit vector index on ack.
- **Device compliance**: implements function windows and registers; supports Mode-2 by supplying an 8-bit vector index when its INT channel is acknowledged; otherwise returns 0xFF.
- **Backplane compliance (Serial)**: honors CPU widths; implements link bring-up, framing, /INT_ACK[3:0] handling, and vector fetch path.
- **Backplane compliance (Parallel/Minimal)**: exposes full A[23:0], D[31:0]; provides /RD, /WR, /READY, /INT_CH[3:0], /NMI_CH[3:0], /INT_ACK[3:0], I²C, /RESET. Minimal includes the **parallel↔serial bridge** to the MCU.
- **Reference bridge compliance (Minimal)**: implements the specified frame format, flow control, and timing between the parallel side and the MCU.

## 0.10 Versioning & compatibility

- **v1.0** is the first public spec. Minor revisions (v1.0.x) will not change pin maps or logical semantics. Major revisions may extend fields, add channels, or new profiles but will preserve existing behavior whenever possible.

## 0.11 Safety & handling

- Not for safety-critical use. Observe ESD precautions. Unless a profile explicitly states otherwise, **power down before card insertion/removal**. Serial backplanes MAY support controlled slot power gating and link training.

## 0.12 Key terms

- **Window**: 16-entry function space selected by the high address nibble.
- **Register**: 8-bit address within the window (low nibble + width).
- **CPU card**: Host processor board that declares widths and interrupt ack mode.
- **Device card**: Peripheral implementing one or more functions.
- **Backplane**: Physical interposer providing power, signals, slots, and enumeration.
- **Vector index**: 8-bit value supplied by the device during Mode-2 ack.
- **Vector base**: High byte from the CPU’s I register; not provided by devices.
- **/INT_ACK[3:0]**: Active-low lines used to acknowledge the corresponding **/INT_CH[3:0]**.

## 0.12 How to use this document

1. **Read Part 0** (this section) to decide which profile fits your build.
2. **Implement Part 1** (Core) in your firmware and device register maps.
3. **Pick one physical Part** (2: Serial, 3: Parallel, or 4: Minimal) and follow its pin map, timing, and power rules.
4. For a working baseline, study **Part 5** (Reference Implementation).

[Part 1 — Core Logical Specification](Part%201%20%E2%80%94%20Core%20Logical%20Specification%2029c84f5aa5ee80819925c9344484c7f7.md)

[Part 2 — Serial Profile (Framed LVDS)](Part%202%20%E2%80%94%20Serial%20Profile%20(Framed%20LVDS)%2029d84f5aa5ee80a3ba2fc569e5a5cb9a.md)