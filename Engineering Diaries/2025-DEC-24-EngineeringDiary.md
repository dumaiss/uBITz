# μBITz Engineering Diary

> Central engineering log for μBITz: decisions, constraints, rejected ideas, open questions.

---

## 2025-12-24– Daily Engineering Diary

### Decisions

- Define μBITz v1 as a **single-master memory system**: Host/Bank own the memory bus; Tiles remain peripherals behind the Dock.
    
- Prefer **Dock-side and/or Bank-side copy engines** (descriptor-driven) instead of true bus-master Tiles.
    
- Treat “DMA” primarily as **cross-domain bulk copy** (Bank RAM ↔ Tile windows, Tile ↔ Tile), not classic shared-RAM arbitration.
    
- Keep an **optional Dock Blitter Service** modeled after Amiga Agnus semantics (operation-level compatibility, not cycle-accurate), exposed as an enumerable Dock function (virtual Slot 0), with host personalities choosing where/if it appears in their address map.
    
- For Bank-involved transfers, baseline arbitration is **Exclusive Bus Lock** (CPU is stalled via `/READY` for the duration); optionally allow a **Cycle-Steal** mode where the Dock time-slices and the CPU sees periodic `/READY` stalls.
    
- For Tile↔Tile (Tile-only) transfers, allow a **non-blocking** fast path that does not touch the Host↔Bank bus.
    
- Resolve pin pressure by allocating reserved backplane GPIO primarily to **timing and limited debug** (e.g., CLK_REF0/CLK_REF1 + minimal DBG lines); push most debug into I²C expanders/local headers.
    
- **Forward-compatibility reservation:** allocate **per-slot bus-mastering arbitration pins** on the PCIe connector (e.g., `BM_REQn` + `BM_GNTn` per Tile slot) and keep them **RESERVED/NC** in v1; protocol to be specified later.
    

### Constraints

- Current limiting factor for future-proofing arbitration is **connector pin budget**, not Dock FPGA/CPLD I/O; reserve the minimum viable set now.
    
- BYOM: Host/Bank memory is private; Tiles have private VRAM/buffers; there is no shared “Chip RAM” bus.
    
- Pin budget is tight; avoid per-slot bus arbitration pins (REQ/GNT) unless a concrete v2 use-case forces it.
    
- Any blitter/DMA mechanism MUST ensure **no bus contention** (only one bus driver at a time) and be compatible with multiple CPU families.
    
- Blitter compatibility target is **semantic** (register + operation behavior), not cycle-accurate timing.
    

### Rejected Ideas (and why)

- **True bus-master Tile DMA** (per-slot REQ/GNT): pin-expensive, architecturally misaligned with BYOM, and mostly unnecessary with modern RAM at retro CPU speeds.
    
- **Special pointer “domain encoding”** in blitter registers (e.g., 0x80+ tile domains): adds abstraction/documentation burden and reduces host-personality flexibility.
    
- Over-promising “non-blocking” Bank RAM blits: Bank-involved transfers still stall the CPU; the win is _stalling for far less time_, not true parallel execution.
    

### Open Questions

- For **Tile-initiated DMA**, do we want true Tile bus mastering (requires an arbitration protocol and likely per-slot identity), or do we accept “Tile-requested DMA” executed by a Dock/Bank blitter service (no Tile bus mastering)?
    
- Should the Core logical signal set add an **optional Bus-Hold handshake** (`/BUSREQ` + `/BUSACK`-style) that Hosts implement in their bus adapter to provide an explicit, portable “bus released” acknowledgement for DMA/blitter engines?
    
- What is the **portable** definition of a “safe point” to seize the bus (end-of-cycle detection, per-CPU heuristics, conservative `/READY` strategy)?
    
- How should **capability discovery** work for optional features (Cycle-Steal support, Tile-only fast path, max throughput, alignment constraints)?
    
- Do we need a minimal, generic **bus-owner** indicator internally (or externally) to simplify debug and validation?
    
- Where should the “copy engine” live by default (Dock FPGA vs Dock MCU vs Bank), and what are the long-term test hooks?
    

### Notes

- Per-slot arbitration is feasible on the Parallel Profile (PCIe-style connector has ample pins): consider **per-slot request/grant** lines (analogous to per-slot interrupts) so the Dock arbiter can identify the requesting Tile.
    
- Key mental model correction: **Tile-only** transfers can be non-blocking; **Bank-involved** transfers are blocking but can be _orders of magnitude shorter_.
    
- The “retro personality” angle (Amiga/C64-style hosts) benefits from a blitter primitive that can be mapped to legacy register layouts by the Host, without hardcoding addresses in the Dock.