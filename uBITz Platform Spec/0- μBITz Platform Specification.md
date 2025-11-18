# μBITz Platform Specification v1.0

# μBITz Platform Specification v1.0

## Multi-Platform Retro-Modern Computing Architecture

---

# Part 0 — Platform Overview and Architecture

**Status:** Normative

**Version:** 1.0

**Date:** 2025

---

## 0.1 What is μBITz Platform?

The μBITz Platform is a modular, multi-platform computing architecture designed for retro-modern systems. It provides a standardized framework for building complete computer systems by composing four fundamental subsystems:

- **μBITz Host** — CPU boards implementing complete platform logic
- **μBITz Bank** — Memory subsystem providing word-addressed RAM/ROM
- **μBITz Dock** — I/O expansion interconnect for peripherals
- **μBITz Tile** — Peripheral devices that attach to the Dock bus

Together, these subsystems enable hobbyists and enthusiasts to build authentic retro computing platforms (C64, Apple II, ZX Spectrum, etc.) while leveraging modern components, modularity, and cross-platform device compatibility.

**Key Characteristics:**
- **Platform-centric design**: Each CPU board defines a complete platform personality
- **Logical separation**: CPU, Memory, and I/O are independent, replaceable subsystems
- **Width flexibility**: Supports 8-bit through 32-bit address and data paths
- **Cross-platform devices**: Peripherals work across different CPU platforms
- **Hobbyist-first**: Accessible components, readable timing, thorough documentation

---

## 0.2 Design Philosophy

### 0.2.1 Appropriate Complexity Principle

The μBITz Platform targets hobbyist and enthusiast systems where:

- System complexity is manageable by individuals or small teams
- Trace lengths are typically <6 inches (within backplane)
- Data rates are modest (≤500 Mbps for I/O, ≤100 MHz for memory)
- Applications are not safety-critical
- Standard debugging tools are sufficient (oscilloscope, logic analyzer)

**We prioritize:**
 ✓ Simplicity over redundancy
 ✓ Performance over absolute integrity
 ✓ Ease of implementation over comprehensive protection
 ✓ Clear failure modes over silent error correction
 ✓ Learning value over production optimization

**This platform is NOT designed for:**
- Safety certification (medical, automotive, aerospace)
- Cryptographic integrity requirements
- Long-distance communication (>1 meter)
- Harsh environments (industrial, military)
- Cache-coherent multiprocessing
- High-speed DMA or bus mastering

> Warning: As the specification author states: “I’m going to personally hunt you down and smack you on the head if you use this standard for critical applications.” 😄
> 

### 0.2.2 Core Design Principles

1. **Subsystem Independence**
    
    Each subsystem (Host, Bank, Dock, Tile) has clear boundaries and can be designed, tested, and replaced independently.
    
2. **Platform Personality**
    
    The CPU board defines the complete platform identity; peripherals adapt to the platform, not vice versa.
    
3. **Enumeration and Discovery**
    
    All subsystems use I²C-based enumeration with EEPROM descriptors for automatic configuration and conflict detection.
    
4. **Deterministic Semantics**
    
    Synchronous operation with explicit ready/wait signaling; no hidden retries or undefined timing.
    
5. **Width Scalability**
    
    Support 8/16/32-bit address and data widths; subsystems declare capabilities and validate compatibility at enumeration.
    
6. **Hobbyist Accessibility**
    
    Use commodity connectors, through-hole-friendly options, standard signaling levels, and debuggable protocols.
    

---

## 0.3 Target Users

### 0.3.1 Who This Platform Serves

**Primary Users:**
- Hobbyists building retro-style computers from scratch
- Educators teaching computer architecture and system design
- Retrocomputing enthusiasts modernizing classic platforms
- Board designers creating portable, reusable peripherals
- Firmware developers writing cross-platform drivers
- Collectors and preservationists creating maintainable systems

**Secondary Users:**
- Small-scale manufacturers of retro computing products
- Museum and exhibition system builders
- Prototype developers for embedded retro-inspired products

### 0.3.2 Non-Target Applications

The μBITz Platform is **explicitly NOT intended** for:
- Safety-critical systems (life support, transportation, industrial control)
- Security-sensitive applications (payment systems, authentication)
- High-reliability commercial products requiring certification
- Systems with cache coherency or sophisticated memory management
- High-speed applications requiring PCIe-class performance
- Production systems requiring vendor support or warranties

---

## 0.4 Platform Architecture

### 0.4.1 Subsystem Roles

The μBITz Platform consists of four mandatory subsystems, each with distinct responsibilities:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      μBITz PLATFORM                                         │
│                                                                             │
│  ┌──────────────┐      ┌──────────────┐  ┌──────────────┐    ┌──────────┐   │
│  │  μBITz Host  │◄────►│  μBITz Bank  │  │  μBITz Tiles │    │  μBITz   │   │
│  │  (CPU Board) │      │ (Memory Sub) │  │   (Devices)  │    │   Dock   │   │
│  │              │      │              │  │              │    │ (I/O Bus)│   │
│  │  - Platform  │      │  - Word RAM  │  │  - Video     │    │          │   │
│  │  - Timing    │      │  - ROM/Flash │  │  - Sound     │    │          │   │
│  │  - Control   │      │  - Mapping   │  │  - HID       │    │          │   │
│  └──────┬───────┘      └──────┬───────┘  └──────┬───────┘    │          │   │
│         │                     │                 │            │          │   │
│         │                     │                 │            │          │   │
│         └─────────────────────┼─────────────────┼────────────┤          │   │
│                               │                              └──────────┘   │
│                               │                                             │
│                    Common Backplane Infrastructure                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 0.4.2 Subsystem Descriptions

### μBITz Host (CPU Board)

**Specification Document:** *μBITz Host Specification v1.0*

**Role:** Implements the complete platform personality, CPU, and system control logic.

**Responsibilities:**
- Execute the target platform’s CPU instruction set (Z80, 6502, 68000, etc.)
- Generate all bus timing and control signals
- Implement platform-specific chipset logic (interrupt controllers, timers, DMA, etc.)
- Provide CPU Descriptor via I²C EEPROM declaring:
- Platform identity (e.g., “C64”, “APPLE2”, “ZX48K”)
- CPU type and capabilities
- Address bus width (8/16/32 bits)
- Data bus width (8/16/32 bits)
- Interrupt acknowledge mode
- I/O window mapping policy
- Interrupt routing policy
- Implement CPU-side memory interface (address generation, timing)
- Handle CPU-side I/O operations (IN/OUT or memory-mapped I/O)

**Key Outputs:**
- Address bus: `A[AddressBusWidth-1:0]`
- Data bus: `D[DataBusWidth-1:0]` (bidirectional)
- Memory control: `/MREQ`, `R/W_`, `/READY`, `/ROM_CS`, `/RAM_CS` handling
- I/O control: `/IORQ`, `R/W_`, `/READY` handling
- Interrupt inputs: `CPU_INT[3:0]`, `CPU_NMI[3:0]`
- Interrupt acknowledge: `/CPU_ACK[3:0]`
- System control: `/RESET`, `/BUSRQ`, `/BUSACK` (platform-specific)

**Dependencies:**
- Requires μBITz Bank for memory operations
- Requires μBITz Dock for I/O operations
- Must negotiate compatibility during enumeration

---

### μBITz Bank (Memory Subsystem)

**Specification Document:** *μBITz Bank Specification v1.0*

**Role:** Provides word-addressed memory (RAM and ROM/Flash) with configurable mapping.

**Responsibilities:**
- Implement physical memory storage (SRAM, DRAM, Flash, ROM)
- Support declared address and data widths from CPU board
- Provide Bank Descriptor via I²C EEPROM declaring:
- Total memory capacity and type (RAM/ROM/Flash)
- Memory organization (byte/word/longword access)
- Address width support (8/16/32 bits)
- Data width support (8/16/32 bits)
- Decode memory address ranges and chip selects
- Handle memory timing (setup, hold, wait states)
- Support atomic multi-byte operations per declared data width
- Provide memory initialization and testing capabilities
- Behaves as a static memory. If dynamic RAM is used in implementation, the Bank implementation is responsible for its own refresh

**Key Inputs:**
- Memory address: `A[AddressBusWidth-1:0]`
- Memory data: `D[DataBusWidth-1:0]` (write operations)
- Memory control: `/MREQ`, `R/W_` (1=read, 0=write), `/ROM_CS`, `/RAM_CS`

**Key Outputs:**
- Memory data: `D[DataBusWidth-1:0]` (read operations)
- `/READY` or ready signaling for slow memory
- Bank status signals (platform-specific)

**Dependencies:**
- Receives addressing and control from μBITz Host
- Must support CPU board’s declared widths
- Operates independently of μBITz Dock

**Design Constraints:**
- Memory operations complete synchronously with CPU assert wait states
- Read data must be valid before CPU samples (setup time)
- Write data must be held stable during write pulse (hold time)
- Banking is the responsibility of the μBITz Core
- ROM regions must be write-protected in hardware

---

### μBITz Dock (I/O Expansion Bus)

**Specification Document:** *μBITz Dock Specification v1.0*

**Role:** Standardized I/O interconnect supporting multiple physical profiles.

**Responsibilities:**
- Provide backplane infrastructure (power, signals, slots)
- Support 1-4 peripheral device slots
- Implement function-based address routing (not geographic)
- Provide Device Descriptors via I²C EEPROM for each peripheral
- Route I/O transactions based on CPU window mapping
- Handle interrupt routing from devices to CPU pins
- Support multiple physical profiles:
- **Serial Profile**: M.2 connector with LVDS framing (10-bit symbols)
- **Parallel Profile**: PCIe x16 connector (signal reuse only)
- **Minimal Profile**: MCU-based bridge with internal serialization
- Implement enumeration and conflict detection
- Provide `/READY` stretching for device wait states
- Manage per-slot chip selects (`/CS[Slot-1:0]`)
- Route per-slot interrupt channels to CPU interrupt pins

**Key Inputs (from CPU):**
- I/O address: `A[AddressBusWidth-1:0]`
- I/O data: `D[DataBusWidth-1:0]` (write operations)
- I/O request: `/IORQ`
- Operation: `R/W_` (1=read, 0=write)
- Interrupt acknowledge: `/CPU_ACK[3:0]`

**Key Outputs (to CPU):**
- I/O data: `D[DataBusWidth-1:0]` (read operations)
- Ready/wait: `/READY`
- Interrupt requests: `CPU_INT[3:0]`, `CPU_NMI[3:0]`

**Key Signals (per device slot):**
- Slot select: `/CS[n]`
- Forwarded address and data (profile-specific encoding)
- Interrupt channels: `INT_CH[3:0]`, `NMI_CH[3:0]` (device→backplane)
- Interrupt acknowledge: `/INT_ACK[3:0]` (backplane→device)

**Dependencies:**
- Receives I/O operations from μBITz Host
- Must support CPU board’s declared widths (Serial) or provide full width (Parallel)
- Operates independently of μBITz Bank

**Dependencies:**
- Receives I/O operations from μBITz Host
- Must support CPU board’s declared widths (Serial) or provide full width (Parallel)
- Operates independently of μBITz Bank

**Device Support:**
- Video controllers (VIC-II, VDP, etc.)
- Sound synthesizers (SID, YM2149, OPL, etc.)
- Human input devices (keyboard, joystick, mouse)
- Storage interfaces (floppy, IDE, SD card)
- Serial communications (UART, RS-232)
- Parallel ports (printer, GPIO)
- Network interfaces (Ethernet, WiFi)
- Real-time clocks
- Custom/vendor-specific functions

---

## 0.5 System Integration

### 0.5.1 Enumeration and Configuration

All three subsystems participate in a unified enumeration sequence coordinated by the backplane (or CPU board in Minimal profile):

**Phase 1: Descriptor Discovery**
1. Assert `/RESET` to all subsystems
2. Read CPU Descriptor from μBITz Host
3. Read Bank Descriptor from μBITz Bank
4. Read Device Descriptors from μBITz Dock slots

**Phase 2: Compatibility Validation**
1. Validate Bank address/data width ≤ CPU declared widths
2. Validate Dock device widths per profile rules:
- Serial: Device width ≤ CPU width (or fail)
- Parallel: All widths exposed; devices adapt
3. Verify no I/O window conflicts (duplicate function/instance mappings)
4. Verify all required functions (per CPU WindowMap[]) are present
5. If a transaction targets no mapped window, reads complete with all-ones (`0xFF/0xFFFF/0xFFFFFFFF`) and writes are ignored (profile may short-circuit before issuing a device transaction).

**Phase 3: Resource Assignment**
1. Build I/O routing table: (IOWin, Mask, OpSel) → Slot
2. Build interrupt routing table: (Function, Instance, Channel) → CPU pin
3. Configure memory banking if required
4. Apply platform-specific initialization

**Phase 4: Operational**
1. Release `/RESET`
2. CPU begins execution
3. Subsystems respond to their assigned address ranges
4. Fault LED remains OFF (or Status LED indicates ready)

**Enumeration Failure:**
- Missing required function → FAULT LED solid ON
- Width incompatibility → FAULT LED solid ON
- Window conflict → FAULT LED solid ON
- Descriptor read error → FAULT LED solid ON

### 0.5.2 Bus Width Negotiation

The platform supports flexible bus widths with the following rules:

**Address Bus Width:**
- CPU declares: 8, 16, or 32 bits
- Bank must support: ≥ CPU width (for full address space access)
- Dock devices (Serial): Must support CPU width or fail enumeration
- Dock devices (Parallel): Always receive full A[31:0]; internally decode as needed

**Data Bus Width:**
- CPU declares: 8, 16, or 32 bits

**Width compatibility (normative):**

1. Device `DataBusWidth ≤ CPU DataBusWidth` → PASS;
2. Device `DataBusWidth > CPU DataBusWidth` → FAIL;
    
    Serial backplanes **MUST** honor the CPU’s declared widths or fail enumeration; Parallel **always** exposes `A[31:0], D[31:0]` on the connector.
    

**Little-Endian Byte Ordering:**
- All multi-byte values use little-endian byte ordering
- `D[7:0]` = least significant byte
- `D[15:8]` = next byte (16-bit systems)
- `D[23:16]`, `D[31:24]` = additional bytes (32-bit systems)

### 0.5.3 Signal Domains

The platform defines three distinct signal domains:

**Memory Domain (CPU ↔︎ Bank):**
- Memory address bus: `A[AddressBusWidth-1:0]`
- Memory data bus: `D[DataBusWidth-1:0]`
- Memory request: `/MREQ`
- Read/Write: `R/W_n`(1=read, 0=write)
- Wait/Ready: `/READY` 
- Banking signals: Platform-specific

**I/O Domain (CPU ↔︎ Dock):**
- I/O address bus: `A[AddressBusWidth-1:0]`
- I/O data bus: `D[DataBusWidth-1:0]`
- I/O request: `/IORQ`
- Read/Write: `R/W_` (1=read, 0=write)
- Ready: `/READY`
- Chip selects: `/CS[Slots-1:0]`

**Interrupt Domain (Dock → CPU):**
- Maskable interrupts: `CPU_INT[3:0]` ← routed from `INT_CH[3:0]` per slot
- Non-maskable interrupts: `CPU_NMI[3:0]` ← routed from `NMI_CH[3:0]` per slot
- Acknowledge: `/CPU_ACK[3:0]` → routed to `/INT_ACK[3:0]` per slot
- Open-drain, active-low, level-based signaling

**Control Domain (Common):**
- System reset: `/RESET`
- Enumeration bus: I²C (SCL, SDA)

---

## 0.6 Logical Contracts

### 0.6.1 Memory Transaction Contract (CPU ↔︎ Bank)

**CPU Obligations:**
1. Drive valid address on `A[]` before asserting `/MREQ`
2. Hold address stable throughout memory cycle
3. For writes: Drive data on `D[]` before asserting `R/W_`
4. For reads: Sample data from `D[]` after `R/W_` asserted and `/READY` deasserted
5. Respect `/READY` signal; do not complete cycle until `/READY` released
6. Hold `/MREQ` asserted until cycle complete

**Bank Obligations:**
1. Ignore `A[]` and `D[]` when `/MREQ` = 1 (deasserted)
2. Decode address and determine hit/miss within propagation delay
3. For reads: Drive `D[]` with valid data before releasing `/READY`
4. For writes: Latch `D[]` before cycle completes; update storage atomically
5. Assert `/READY` if cycle cannot complete immediately
6. Release `/READY` only when data valid (read) or write committed (write)
7. Drive `D[]` to high-impedance when not selected or on writes

**Timing Guarantees:**
- Address setup time before `/MREQ`: Platform-specific, typically ≥10ns
- Data valid before `/READY` release: Platform-specific, typically ≥20ns
- Write data hold after `R/W_` release: Platform-specific, typically ≥10ns

### 0.6.2 I/O Transaction Contract (CPU ↔︎ Dock)

**CPU Obligations:**
1. Drive address on `A[]` and assert `/IORQ` to start I/O cycle
2. Drive `R/W_` (1=read, 0=write) at cycle start
3. For writes: Drive data on `D[]` before asserting `/IORQ`
4. For reads: Sample data from `D[]` after `/READY` = 1
5. Hold `/IORQ` asserted until `/READY` = 1
6. Implement timeout policy for hung devices (platform-specific)
7. After timeout, complete read with 0xFF/0xFFFF/0xFFFFFFFF; ignore writes

**Dock Backplane Obligations:**
1. Decode `(A[] & IOMask) == (IOWin & IOMask)` and `OpSel` match
2. Assert exactly one `/CS[n]` to selected slot (one-hot)
3. Forward complete address `A[]` to selected device (no rewriting)
4. Hold `/READY` = 0 from start of cycle until device ready
5. For reads: Ensure `D[]` valid from device before releasing `/READY`
6. For writes: Ensure device has latched `D[]` before releasing `/READY`
7. Release `/READY` = 1 to complete cycle
8. If no window match: Return 0xFF/0xFFFF/0xFFFFFFFF for reads; ignore writes
9. Never deassert `/CS[n]` while `/IORQ` = 0

**Device Obligations:**
1. Ignore all signals when `/CS[n]` = 1 (deasserted)
2. When `/CS[n]` = 0 and `/IORQ` = 0: Decode address internally
3. For reads: Drive valid data on `D[]` (active lanes only)
4. For writes: Latch data from `D[]` (active lanes only)
5. Stretch cycle if needed (backplane handles `/READY`)
6. Apply multi-byte writes atomically per declared data width
7. For Mode-2 interrupt ack: Return 8-bit vector index when `/INT_ACK[k]` asserted

### 0.6.3 Interrupt Contract (Dock → CPU)

**Device Obligations:**
1. Assert `INT_CH[k]` or `NMI_CH[k]` when interrupt condition occurs
2. Hold line asserted (level-based) until condition serviced
3. For Mode-2: When `/INT_ACK[k]` asserted during I/O cycle, return 8-bit vector index
4. Return 0xFF if interrupt not claimed or ack received in error
5. Clear interrupt per documented semantics (read-to-clear, write-to-clear, etc.)
6. Never drive interrupt lines when not asserting (open-drain topology)

**Dock Backplane Obligations:**
1. Provide pull-up resistors on all interrupt lines (typically 3.3kΩ to 3.3V)
2. Route each slot’s channels to CPU pins per IntRouting table
3. OR multiple device channels to same CPU pin if mapped (wired-OR)
4. For Mode-2 ack: Identify asserting slot from channel state
5. Route `/CPU_ACK[k]` to `/INT_ACK[k]` on asserting slot only
6. If multiple slots assert same channel: Return 0xFF; do not query devices
7. For Serial profile: Issue vector read to device (ADDR=0x00, R/W=1, SZ=8-bit)

**CPU Obligations:**
1. Sample `CPU_INT[3:0]` and `CPU_NMI[3:0]` per platform timing
2. For Mode-2: Assert `/CPU_ACK[k]` for selected channel during I/O cycle
3. Drive `/IORQ` = 0 and `R/W_` = 1 during ack cycle (vector read)
4. Sample 8-bit vector index from `D[7:0]`
5. Use internal vector base register (I register or equivalent) as high byte
6. Jump to handler at address `{VectorBase, VectorIndex}`
7. Service device(s); read status registers to identify source if multiple devices share pin
8. If no IntAckMode (Mode 0x00): Poll device status registers; no ack cycle

---

## 0.7 Power and Reset

### 0.7.1 Power Domains

The platform defines standardized power rails provided by the backplane:

**Mandatory Rails:**
- **+3.3V** (VCC): Primary logic power for all subsystems
- Regulation: ±5% (3.135V - 3.465V)
- Ripple: <50mV peak-to-peak
- Load: Per-subsystem budgets defined in component specifications

**Optional Rails:**
- **+5V** (VCC5): For legacy devices and interfaces
- Regulation: ±5% (4.75V - 5.25V)
- Load: Platform-specific; must be documented

- **+12V** (VCC12): Reserved; not used in v1.0
    - Parallel profile explicitly forbids repurposing PCIe 12V pins

**Ground:**
- **GND**: Common ground for all signals and power
- Star-point grounding at backplane recommended
- Separate analog/digital grounds permitted if documented

### 0.7.2 Reset Sequence

**System Reset (`/RESET`):**
1. Active-low, synchronous reset signal
2. Asserted by CPU board or backplane supervisor
3. Minimum pulse width: 10 CPU clock cycles or 1μs, whichever is longer
4. All subsystems must initialize to known state:
- CPU: Program counter to reset vector; registers cleared
- Bank: Memory contents preserved (RAM) or defined (ROM); banking to default state
- Dock: Device registers to documented reset defaults; interrupts deasserted

**Power-On Reset:**
1. Hold `/RESET` asserted until all power rails stable (typically 100ms)
2. Execute enumeration sequence (see §0.5.1)
3. Release `/RESET` only after enumeration success or timeout
4. If enumeration fails: Keep FAULT LED on; do not release `/RESET`

**Warm Reset:**
1. Assert `/RESET` for minimum pulse width
2. Skip enumeration (descriptors already loaded)
3. Reinitialize subsystem state machines
4. Release `/RESET`

---

## 0.8 Compliance and Certification

### 0.8.1 Subsystem Compliance

A **μBITz Host** compliant CPU board must:
- Provide valid CPU Descriptor via I²C EEPROM (address 0x50)
- Declare AddressBusWidth, DataBusWidth, IntAckMode, WindowMap[], IntRouting[]
- Generate all required control signals per memory and I/O contracts
- Handle `/READY` stretching with timeout policy
- For Mode-2: Implement vector base register and ack cycle

A **μBITz Bank** compliant memory board must:
- Provide valid Bank Descriptor via I²C EEPROM (address 0x51)
- Support declared widths or fail enumeration
- Meet memory timing contracts (setup, hold, access time)
- Implement atomic multi-byte operations
- Preserve RAM contents through reset (or document volatile behavior)

A **μBITz Dock** compliant I/O system must:
- Provide enumeration and descriptor access for all slots
- Implement function-based routing per CPU WindowMap[]
- Implement interrupt routing per CPU IntRouting[]
- Follow profile-specific electrical and timing rules (Serial/Parallel/Minimal)
- Assert FAULT LED on enumeration failure
- Virtualize `/READY` during device transactions

### 0.8.2 Platform Compliance

A **complete μBITz Platform** must:
- Include one CPU board (μBITz Host)
- Include one memory board (μBITz Bank)
- Include one I/O backplane (μBITz Dock) with 0-4 device slots
- Include one Device (μBITz Tile)
- Successfully complete enumeration sequence
- Pass integration test suite (defined per component specifications)

### 0.8.3 Interoperability Testing

Implementations should verify:
- Cross-platform device compatibility (same device works on different CPU boards)
- Width negotiation (8/16/32-bit combinations)
- Interrupt routing (all channels, Mode-2 ack)
- Enumeration failure modes (missing devices, conflicts)
- Timing margins (setup/hold violations, ready stretching)

---

## 0.9 Versioning and Evolution

### 0.9.1 Specification Versioning

**Version Format:** `MAJOR.MINOR`
- **MAJOR**: Incompatible changes (pin maps, contracts, descriptor formats)
- **MINOR**: Backward-compatible additions (new optional features, reserved fields)

**Current Version:** 1.0 (Initial release)

### 0.9.2 Compatibility Rules

**Forward Compatibility:**
- v1.x subsystems should work with v1.y subsystems (y > x)
- New descriptors may add fields; parsers must ignore unknown fields
- Reserved values become defined; old implementations treat as invalid

**Backward Compatibility:**
- v1.y subsystems may work with v1.x subsystems (y > x) if no new required features
- Descriptor version field indicates capabilities

**Cross-Major Version:**
- No compatibility guarantees across major versions (1.x vs 2.x)
- Migration guides provided for each major revision

### 0.9.3 Reserved for Future Use

The following areas are reserved for future specification versions:

**Reserved Values:**
- IntAckMode: 0x02-0xFF (currently: 0x00=None, 0x01=Mode-2)
- Function IDs: 0x0A-0x0F (standard), 0x10-0xFD (vendor-specific)
- Control tokens (Serial): Additional 10-bit patterns beyond SOF/EOF/IDLE/ERR

**Reserved Features:**
- Bus mastering and DMA (requires arbitration protocol)
- Cache coherency (requires snoop/coherency protocol)
- Hot-plug (requires slot power control and link training)
- Multi-master I/O (requires arbitration)
- Partial writes/byte enables (requires lane masking)

**Intentionally NOT Reserved:**
- PCI/PCIe compatibility (not a goal)
- High-speed serial protocols >1 Gbps (out of scope)
- Differential memory interfaces (DDR, etc.)

---

## 0.10 Documentation Structure

The complete μBITz Platform specification consists of:

**Core Specifications:**
1. **μBITz Platform Specification v1.0** (this document)
- Overall architecture, philosophy, contracts

1. **μBITz Host Specification v1.0**
    - CPU board requirements, descriptor format, timing
    - Memory interface details
    - I/O interface details
    - Platform-specific implementations (Z80, 6502, 68000, etc.)
2. **μBITz Bank Specification v1.0**
    - Memory board requirements, descriptor format
    - Memory types (SRAM, DRAM, Flash, ROM)
    - Banking and mapping schemes
    - Timing specifications
3. **μBITz Dock Specification v1.0** (provided)
    - Part 0: Overview
    - Part 1: Core logical model (windows, registers, interrupts)
    - Part 2: Serial profile (M.2, LVDS, framed protocol)
    - Part 3: Parallel profile (PCIe connector, parallel signals)
    - Part 4: Minimal profile (MCU bridge)
    - Part 5: Reference implementation

**Supporting Documents:**
- Device driver templates and examples
- Enumeration flow diagrams
- Timing diagrams and waveforms
- Compliance test procedures
- Design guidelines and best practices
- Known issues and errata

---

## 0.11 Acknowledgments and License

### 0.11.1 Design Philosophy

The μBITz Platform embodies decades of retro computing knowledge and modern engineering practice. It is designed for education, experimentation, and enjoyment—not for profit or production use.

### 0.11.2 License

This specification is released under **[LICENSE TO BE DETERMINED]**.

**Permitted Uses:**
- Personal and educational projects
- Open-source hardware designs
- Hobbyist community sharing
- Academic research and teaching

**Restrictions:**
- No warranty or liability for any use
- Not for safety-critical applications
- Attribution required for derivative works

### 0.11.3 Contributing

The μBITz Platform specification is a living document. Feedback, corrections, and improvement suggestions are welcome through **[CONTRIBUTION PROCESS TO BE DETERMINED]**.

---

## 0.12 Glossary

**Address Bus Width**: Number of bits in the address bus (8, 16, or 32)

**Atomic Operation**: Multi-byte operation that completes as a single logical transaction

**Backplane**: Physical infrastructure providing power, signals, and slots

**Bank Switching**: Technique to access more memory than address space allows

**Chip Select (CS)**: Signal indicating which device should respond to a bus operation

**CPU Board**: μBITz Host subsystem implementing platform personality

**Data Bus Width**: Number of bits in the data bus (8, 16, or 32)

**Descriptor**: EEPROM-stored metadata describing subsystem capabilities

**Device**: Peripheral card in μBITz Dock slot providing a function

**Enumeration**: Discovery and configuration process at system startup

**Function**: Logical device type (video, sound, storage, etc.)

**Instance**: Specific occurrence of a function (e.g., UART instance 0)

**Interrupt Acknowledge (ACK)**: CPU signal to service an interrupt request

**Interrupt Channel**: One of 8 per-slot interrupt lines (4 INT + 4 NMI)

**I/O Request (IORQ)**: Signal qualifying an I/O bus transaction

**Little-Endian**: Byte ordering with least significant byte at lowest address

**Memory Request (MREQ)**: Signal qualifying a memory bus transaction

**Mode-2**: Z80-style vectored interrupt with 8-bit vector index

**Open-Drain**: Output driver that can only pull low (requires external pull-up)

**Platform**: Complete system personality (C64, Apple II, etc.)

**Profile**: Physical implementation variant (Serial, Parallel, Minimal)

**Ready/Wait**: Flow control signal for slow memory or I/O devices

**Register**: Device-internal storage location accessed via I/O operations

**Slot**: Physical connector position on backplane for one device

**Subsystem**: One of three major platform components (Host, Bank, Dock)

**Vector Base**: High byte of interrupt vector address (CPU I register)

**Vector Index**: Low byte of interrupt vector address (device-supplied)

**Window**: I/O address range mapped to a function (16-byte granularity)

**Word-Addressed Memory**: Memory accessed by CPU address bus (vs. block storage)

---

## Appendix A: Example System Configurations

### A.1 Minimal C64-Style System

**μBITz Host:**
- Platform: “C64”
- CPU: 6502 @ 1 MHz (or 65C02 @ 2 MHz)
- Address width: 16-bit
- Data width: 8-bit
- IntAckMode: 0x00 (polling)

**μBITz Bank:**
- 64KB SRAM (0x0000-0xFFFF)
- 8KB Character ROM (mapped via banking)
- No banking by default

**μBITz Dock (Minimal Profile):**
- Slot 0: VIC-II compatible video (Function=VIDEO, Instance=0)
- Slot 1: SID compatible sound (Function=SOUND, Instance=0)
- Slot 2: CIA compatible I/O (Function=HID, Instance=0)
- Slot 3: CIA compatible I/O (Function=HID, Instance=1)

**I/O Mapping:**

```
0xD000-0xD3FF: VIC-II (Window 0xD, Mask 0xFC)
0xD400-0xD7FF: SID    (Window 0xD4, Mask 0xFC)
0xDC00-0xDCFF: CIA1   (Window 0xDC, Mask 0xFF)
0xDD00-0xDDFF: CIA2   (Window 0xDD, Mask 0xFF)
```

### A.2 Apple II-Style System

**μBITz Host:**
- Platform: “APPLE2”
- CPU: 6502 @ 1 MHz
- Address width: 16-bit
- Data width: 8-bit
- IntAckMode: 0x00 (no hardware interrupts by default)

**μBITz Bank:**
- 64KB SRAM (48KB main + 16KB language card)
- 12KB ROM (Monitor + Integer BASIC)
- Banking: Language card soft switches

**μBITz Dock (Parallel Profile):**
- Slot 0: Video generator (Function=VIDEO, Instance=0)
- Slot 1: Disk II controller (Function=STORAGE, Instance=0)
- Slot 2: Serial card (Function=SERIAL, Instance=0)

**I/O Mapping (soft switches):**

```
0xC000-0xC0FF: Soft switches and I/O
0xC100-0xC7FF: Peripheral ROM space
0xC800-0xCFFF: Expansion ROM
```

### A.3 ZX Spectrum 48K-Style System

**μBITz Host:**
- Platform: “ZX48K”
- CPU: Z80 @ 3.5 MHz
- Address width: 16-bit
- Data width: 8-bit
- IntAckMode: 0x01 (Mode-2)

**μBITz Bank:**
- 48KB SRAM (0x4000-0xFFFF)
- 16KB ROM (0x0000-0x3FFF)
- No banking

**μBITz Dock (Serial Profile):**
- Slot 0: ULA video/audio (Function=VIDEO, Instance=0)
- Slot 1: Keyboard interface (Function=HID, Instance=0)
- Slot 2: Kempston joystick (Function=HID, Instance=1)

**I/O Mapping:**

```
0xFE: ULA (read: keyboard, write: border/speaker)
0x1F: Kempston joystick (read only)
```

**Interrupts:**

```
INT_CH0 → CPU_INT[0]: Frame interrupt (50/60 Hz)
Vector: 0xFF (IM2 mode with I=0x3F)
```

### A.4 Advanced 32-bit System

**μBITz Host:**
- Platform: “CUSTOM32”
- CPU: 68000 @ 16 MHz
- Address width: 24-bit (A[23:0])
- Data width: 16-bit (D[15:0])
- IntAckMode: 0x01 (Mode-2, autovector capable)

**μBITz Bank:**
- 16MB SRAM (0x000000-0xFFFFFF)
- 512KB Flash ROM (0x000000-0x07FFFF, bank-switched)
- Memory management unit for banking

**μBITz Dock (Parallel Profile):**
- Slot 0: Graphics controller (Function=VIDEO, Instance=0)
- Slot 1: Sound synthesizer (Function=SOUND, Instance=0)
- Slot 2: SCSI controller (Function=STORAGE, Instance=0)
- Slot 3: Ethernet controller (Function=NETWORK, Instance=0)

**I/O Mapping:**

```
0xFF0000-0xFF0FFF: Graphics (Window 0xFF0, Mask 0xFFF)
0xFF1000-0xFF1FFF: Sound    (Window 0xFF1, Mask 0xFFF)
0xFF2000-0xFF2FFF: SCSI     (Window 0xFF2, Mask 0xFFF)
0xFF3000-0xFF3FFF: Ethernet (Window 0xFF3, Mask 0xFFF)
```

**Interrupts:**

```
INT_CH0 → CPU_INT[2]: Graphics VBlank (IPL2, autovector)
INT_CH1 → CPU_INT[3]: Network packet (IPL3, vector $70)
NMI_CH0 → CPU_NMI[0]: Abort button
```

---

## Appendix B: Design Guidelines

### B.1 CPU Board Design

**Essential Considerations:**
1. Generate clean, monotonic edges on control signals
2. Implement comprehensive address decoding (memory vs. I/O)
3. Provide adequate timing margins (setup/hold)
4. Include reset circuitry with power-on delay
5. Use I²C EEPROM with write-protect (to prevent accidental corruption)
6. Include debug headers (address bus, data bus, control signals)
7. Implement watchdog timer for I/O timeout detection
8. Consider clock stretching during wait states

**Memory Interface Timing:**

```
Clock cycle timeline (example for 4MHz Z80):
T1: Address valid → /MREQ asserted
T2: /RD or /WR asserted → Data setup time
T3: Data sampled (read) or held (write)
Tw: /WAIT sampled; insert wait states if needed
T3': Final data sample or write completion
```

**I/O Interface Timing:**

```
Clock cycle timeline (example for 4MHz Z80):
T1: Address valid → /IORQ asserted
T2: /RD or /WR asserted → /READY sampled
Tw: Insert wait states while /READY = 0
T3: Data sampled (read) or write completion
```

### B.2 Memory Board Design

**RAM Considerations:**
1. Use fast SRAM (≤70ns) for simple designs
2. DRAM requires refresh controller and RAS/CAS generation
3. Provide battery backup for SRAM if required
4. Include write-protect jumpers for ROM-emulation mode
5. Add status LEDs (activity, bank select)

**ROM/Flash Considerations:**
1. Use in-system programmable Flash for development
2. Provide programming interface (separate from platform bus)
3. Add write-protect switch to prevent accidental erasure
4. Consider ROM socket for authentic retro feel

**Banking Schemes:**

```
Simple banking (4 banks of 16KB each):
- Bank select register at fixed I/O address
- Maps selected bank to CPU address window
- Typical for CP/M systems

Page-frame banking:
- Multiple bank select registers
- Each controls one page frame
- Allows complex memory layouts

Shadow RAM:
- ROM and RAM occupy same address range
- Soft switch selects active memory
- Typical for Apple II language card
```

### B.3 Device Design

**Register Layout Best Practices:**
1. Group related registers (status, control, data)
2. Use read-to-clear for status flags
3. Provide reset values for all registers
4. Document all reserved bits (must write 0, read undefined)
5. Align multi-byte registers to natural boundaries
6. Implement FIFOs for streaming data (audio, network)

**Interrupt Handling:**

```
Typical interrupt flow:
1. Device condition occurs → assert INT_CH[k]
2. CPU sees CPU_INT[x] (after routing)
3. CPU asserts /CPU_ACK[k] and /IORQ
4. Device returns vector index on D[7:0]
5. CPU forms address: {I_register, vector_index}
6. CPU jumps to interrupt handler
7. Handler reads device status register
8. Handler clears interrupt condition
9. Device deasserts INT_CH[k]
10. Handler returns from interrupt

Polled interrupt flow (IntAckMode=0x00):
1. Device condition occurs → assert INT_CH[k]
2. CPU sees CPU_INT[x] (after routing)
3. CPU jumps to handler (no ack cycle)
4. Handler polls all devices on that pin
5. Handler identifies source by reading status
6. Handler services device
7. Device deasserts INT_CH[k]
8. Handler returns from interrupt
```

**Wait State Generation:**

```
Simple wait state (device-side delay):
- Device requires N clock cycles to respond
- Backplane holds /READY=0 for N cycles
- CPU automatically inserts wait states

Dynamic wait state (busy flag):
- Device has variable processing time
- Device sets internal busy flag
- Backplane monitors busy → /READY
- CPU waits until device ready
```

### B.4 Backplane Design

**Power Distribution:**
1. Use wide traces or planes for power rails
2. Star-point ground connection to minimize ground loops
3. Bypass capacitors at each slot (100nF + 10µF)
4. Ferrite beads for noise isolation between slots
5. Current limiting or fuses per slot (optional)
6. Power sequencing: 3.3V first, then 5V, then /RESET release

**Signal Integrity:**
1. Keep clock traces short and matched
2. Avoid stubs on high-speed signals
3. Controlled impedance for Serial LVDS (100Ω differential)
4. Terminate open-drain lines (3.3kΩ pull-up typical)
5. Guard traces between adjacent signal pairs
6. Keep digital and analog grounds separate if mixed-signal devices present

**Enumeration Controller:**

```
Typical I²C addressing:
0x50: CPU Board EEPROM
0x51: Memory Board EEPROM
0x52: Dock Slot 0 Device EEPROM
0x53: Dock Slot 1 Device EEPROM
0x54: Dock Slot 2 Device EEPROM
0x55: Dock Slot 3 Device EEPROM

EEPROM size: 256 bytes minimum (descriptor size)
Recommended: 512 bytes or 1KB for future expansion
```

---

## Appendix C: Troubleshooting Guide

### C.1 Enumeration Failures

**FAULT LED Solid On:**

**Symptom**: System does not boot, FAULT LED illuminated

**Possible Causes**:
1. Missing required device (CPU WindowMap[] not satisfied)
2. I/O window conflict (two devices claim same window)
3. Width incompatibility (device cannot support CPU width)
4. I²C communication failure (cannot read descriptor)
5. Corrupted EEPROM descriptor

**Diagnostic Steps**:
1. Verify all required devices are installed
2. Read CPU descriptor: Check WindowMap[] for required functions
3. Read device descriptors: Verify Function/Instance declarations
4. Check for duplicate (IOWin, Mask, OpSel) mappings
5. Verify device widths ≤ CPU widths (Serial profile)
6. Use I²C analyzer to monitor descriptor reads
7. Compare descriptor checksums (if implemented)

### C.2 Memory Issues

**Symptom**: System boots but crashes randomly

**Possible Causes**:
1. Insufficient wait states (memory too slow)
2. Address bus contention (improper tri-stating)
3. Setup/hold timing violations
4. Power supply noise or insufficient bypassing
5. Cold solder joints or poor connections

**Diagnostic Steps**:
1. Scope memory address bus: Clean transitions, no ringing
2. Scope memory data bus: Valid data before CPU samples
3. Scope /MREQ, /RD, /WR: Proper sequencing and timing
4. Check /WAIT timing: Asserted early enough
5. Measure power rails under load: Stable voltage, low ripple
6. Run memory test pattern (walking 1s, walking 0s, checkerboard)

**Symptom**: Memory contents corrupted after power cycle

**Possible Causes**:
1. RAM instead of ROM in ROM socket
2. Write-protect not enabled on Flash
3. Battery backup circuit failed (SRAM)
4. Banking registers not initialized properly

### C.3 I/O Issues

**Symptom**: Device not responding to I/O operations

**Possible Causes**:
1. Wrong I/O window mapping in CPU descriptor
2. Device not claiming correct Function/Instance
3. /CS not asserted (routing error)
4. Address decode error in device
5. /IORQ not qualifying cycles properly

**Diagnostic Steps**:
1. Verify WindowMap[] entry matches device descriptor
2. Check I/O address decode logic
3. Scope /IORQ during I/O instruction
4. Scope /CS[n] to device: Should assert during operation
5. Scope A[] and D[] buses at device: Valid values
6. Check /READY timing: Device releasing at proper time

**Symptom**: I/O operations timeout

**Possible Causes**:
1. Device not releasing /READY
2. Missing pull-up on /READY (open-drain implementations)
3. Device SERDES not locked (Serial profile)
4. Slow device without proper wait state handling

### C.4 Interrupt Issues

**Symptom**: Interrupts not firing

**Possible Causes**:
1. Interrupt routing not configured in CPU descriptor
2. Wrong IntRouting[] entry (Function/Instance mismatch)
3. Missing pull-up on interrupt line
4. CPU interrupt mask not enabled (software issue)
5. Device not asserting interrupt line

**Diagnostic Steps**:
1. Check IntRouting[] entries in CPU descriptor
2. Verify device IntChannel declaration in descriptor
3. Scope INT_CH[k] at device: Should be low when asserted
4. Scope CPU_INT[x] at CPU: Should be low after routing
5. Check CPU interrupt enable flags (software)
6. Manually ground interrupt line: Does CPU respond?

**Symptom**: Spurious interrupts or interrupt storms

**Possible Causes**:
1. Device not clearing interrupt flag properly
2. Multiple devices sharing same pin without proper ISR polling
3. Noise on interrupt line (insufficient filtering)
4. Interrupt flag cleared before condition serviced (race condition)

**Diagnostic Steps**:
1. Read device status register in ISR: Verify flag set
2. Clear device interrupt flag explicitly
3. Re-read status: Verify flag cleared
4. Check if device immediately reasserts (unserviced condition)
5. Add debouncing or edge detection if needed

**Symptom**: Mode-2 vector not working

**Possible Causes**:
1. CPU IntAckMode not set to 0x01
2. Device not implementing vector register (ADDR=0x00)
3. /INT_ACK[k] not routed to device
4. Backplane returning 0xFF (multiple claimants)

**Diagnostic Steps**:
1. Verify CPU descriptor IntAckMode = 0x01
2. Scope /CPU_ACK[k] during ack cycle
3. Scope /INT_ACK[k] at device: Should assert
4. Scope D[7:0] during ack: Device should drive vector, not 0xFF
5. Check for multiple devices asserting same INT_CH[k]

---

## Appendix D: Reference Measurements

### D.1 Typical Timing Parameters

**Z80 @ 4 MHz (Example):**

```
Clock period (Tcy):        250 ns
Address setup (Tas):       30 ns (before /MREQ↓)
Address hold (Tah):        10 ns (after /MREQ↑)
Data setup (Tds):          50 ns (before sampling)
Data hold (Tdh):           0 ns (after sampling)
/RD, /WR pulse width:      150 ns minimum
/WAIT setup time:          40 ns (before T2 falling edge)
```

**6502 @ 1 MHz (Example):**

```
Clock period (Tcy):        1000 ns
Address setup (Tas):       PHI2↑ + 0 ns
Address hold (Tah):        Hold until next PHI2↑
Data setup (Tds):          100 ns (before PHI2↓)
Data hold (Tdh):           10 ns (after PHI2↓)
R/W setup time:            PHI2↑ + 0 ns
/READY setup time:         Sampled at PHI1↑
```

**68000 @ 8 MHz (Example):**

```
Clock period (Tcy):        125 ns (S0-S7 states)
Address setup (Tas):       S0: Address valid
Address hold (Tah):        Hold until S7
Data setup (Tds):          30 ns (before S6 falling edge)
Data hold (Tdh):           0 ns (after S6)
/AS, /DS pulse width:      S2-S6 (typically 375 ns)
/DTACK setup time:         30 ns (before S6 falling edge)
```

### D.2 Power Consumption Guidelines

**Typical Current Draw (per subsystem):**

**μBITz Host (CPU Board):**

```
Z80 @ 4 MHz:              ~50 mA @ 3.3V
6502 @ 1 MHz:             ~30 mA @ 3.3V
68000 @ 8 MHz:            ~100 mA @ 3.3V
Support logic (74HC):     ~10 mA @ 3.3V
Total budget:             150-200 mA @ 3.3V
```

**μBITz Bank (Memory):**

```
64KB SRAM (static):       ~20 mA @ 3.3V
1MB SRAM (static):        ~50 mA @ 3.3V
Flash ROM (idle):         ~5 mA @ 3.3V
Flash ROM (programming):  ~20 mA @ 3.3V
Total budget:             50-100 mA @ 3.3V
```

**μBITz Dock Device (typical):**

```
Simple I/O (UART, GPIO):  ~20 mA @ 3.3V
Video controller:         ~100 mA @ 3.3V
Sound synthesizer:        ~50 mA @ 3.3V
Network interface:        ~150 mA @ 3.3V
Storage controller:       ~75 mA @ 3.3V
Serial SERDES PHY:        ~30 mA @ 3.3V
Total per slot budget:    150-200 mA @ 3.3V
```

**System Total (4-slot maximum):**

```
CPU Board:                200 mA
Memory Board:             100 mA
4× Device Boards:         800 mA
Backplane overhead:       100 mA
Total system:             1200 mA @ 3.3V (4 watts)
Recommended PSU:          2A @ 3.3V (6.6 watts) minimum
```

---

## Appendix E: Migration from Other Systems

### E.1 From ISA Bus

**Key Differences:**
- μBITz uses function-based addressing (not geographic/slot addressing)
- No DMA or bus mastering in v1.0
- Narrower data bus (8/16 bits typical vs. 16 bits ISA)
- Simpler interrupt model (8 channels vs. ISA IRQ lines)
- Enumeration via I²C (not PnP configuration registers)

**Migration Strategy:**
1. Map ISA I/O addresses to μBITz windows
2. Convert ISA IRQ to IntChannel declarations
3. Replace DMA with programmed I/O or FIFOs
4. Adapt 16-bit ISA timing to 8-bit μBITz timing if needed

### E.2 From Commodore 64 Expansion Port

**Key Differences:**
- μBITz separates I/O (Dock) from memory (Bank)
- Multiple device slots (vs. single cartridge port)
- Enumeration replaces manual jumper configuration
- Standardized interrupt routing

**Migration Strategy:**
1. Split cart into separate I/O and memory boards if needed
2. Declare Function (e.g., Function=STORAGE for disk interface)
3. Map I/O registers to window (e.g., 0xDE00-0xDEFF)
4. Convert /GAME, /EXROM to banking descriptors
5. Map /IRQ, /NMI to IntChannel declarations

### E.3 From Apple II Slots

**Key Differences:**
- μBITz does not provide ROM space per slot
- Function-based addressing (not slot-based $Cn00 ranges)
- Enumeration replaces slot number self-identification

**Migration Strategy:**
1. Move slot firmware to device Flash or host ROM
2. Map slot I/O (*C*0*n*0−C0nF) to windows
3. Declare device function in descriptor
4. Convert slot interrupts to IntChannel

---

## Appendix F: Frequently Asked Questions

**Q: Can I mix Serial and Parallel devices on the same backplane?**

A: No. Each backplane supports only one profile. Choose Serial, Parallel, or Minimal for the entire system.

**Q: Why no DMA or bus mastering?**

A: v1.0 focuses on simplicity. DMA requires arbitration, multi-master protocols, and interrupt-driven state machines. Programmed I/O with FIFOs covers most retro use cases. Future versions may add DMA.

**Q: Can I use 12V for motor control or power amplifiers?**

A: Not on the standard connectors. Parallel profile explicitly forbids repurposing PCIe 12V pins. Add separate power connectors for high-voltage peripherals.

**Q: How do I handle multiple devices needing the same interrupt?**

A: Map both devices to the same CPU pin in IntRouting[]. The CPU ISR polls device status registers to identify which device(s) need service. This is standard practice on retro systems.

**Q: Can memory boards provide I/O registers?**

A: Memory boards should only provide RAM/ROM. I/O registers belong on Dock devices. If a memory board needs configuration (banking), expose those registers via a Dock device on the same physical board.

**Q: What if my CPU doesn’t have an I/O instruction?**

A: Use memory-mapped I/O. The CPU board synthesizes /IORQ by decoding specific address ranges. Example: 6502 maps *D*000−DFFF to I/O; CPU board asserts /IORQ for accesses in that range.

**Q: Can I hot-swap device cards?**

A: Not safely in v1.0. Power down before inserting or removing cards. Serial profile backplanes MAY implement slot power control and link training for hot-plug in future versions.

**Q: How do I implement a custom function type?**

A: Use Function IDs 0x10-0xFF (vendor-specific range). Document the register map and I/O protocol. Other builders can reuse your function type by matching the Function ID in their CPU descriptors.

**Q: What’s the maximum achievable I/O bandwidth?**

A: Depends on profile and CPU speed:
- Parallel @ 4MHz Z80: ~1 MB/s (byte I/O with 4 clocks/byte)
- Serial @ 250 Mbps line rate: ~20 MB/s effective (after framing overhead)
- Minimal: Limited by MCU bridge (typically 1-5 MB/s)

Real-world applications rarely exceed these limits in retro computing contexts.

---

**END OF μBITz PLATFORM SPECIFICATION v1.0**

[μBITz Dock Specification v1.0](%CE%BCBITz%20Dock%20Specification%20v1%200%2029c84f5aa5ee801ebf1adc59ea394003.md)

[μBITz Versatile Tile Classes — Overview Specification](%CE%BCBITz%20Versatile%20Tile%20Classes%20%E2%80%94%20Overview%20Specificat%202af84f5aa5ee8039b746f722fb57a73e.md)