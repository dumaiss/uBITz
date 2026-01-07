# μBITz Engineering Diary

> Central engineering log for μBITz: decisions, constraints, rejected ideas, open questions.

---

## 2025-12-28– Daily Engineering Diary

### Decisions

- **Decision: Option A — Delete the Dock Serial Profile (FRLVDS) outright** from the normative v1.x spec set.
    
- Promote a **single universal PCIe x16 pinout** across Host/Bank/Tile slots by repurposing the former `SER_*` pin group as canonical core sideband/memory-control signals (e.g., `/MREQ`, `/MEM0_CS`, `/MEM1_CS`, etc.), eliminating Host/Bank vs Tile pinout exceptions.
    

### Constraints

- Pinouts are hard to change later; changes are cheapest right now (no external users).
    
- Keep the builder experience simple: fewer profiles, fewer “special” pins.
    
- Preserve a path to future bus-master / tile-to-tile features without committing to it now.
    

### Rejected Ideas (and why)

- Keep Serial Profile “just in case” — ongoing PHY/protocol/spec/test burden with no compelling current use-case.
    
- Archive Serial as non-normative while still reserving SER pins — preserves clutter and blocks universal-slot pinout benefits.
    

### Open Questions

- If Serial is removed, what is the best long-term use of the reclaimed SER_* pins (memory sideband vs clocks vs future expansion bits)?
    
- Should “universal connector” be a formal v1.x goal (swap-any-card-without-damage), or just a convenience?
    

### Notes

- Host/Bank specs already repurpose SER_* pins as `/MREQ`, `/MEM0_CS`, `/MEM1_CS` via a Core Connector overlay; extending that to Tile slots would eliminate the last major pinout mismatch.