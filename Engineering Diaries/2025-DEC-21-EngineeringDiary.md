# μBITz Engineering Diary

> Central engineering log for μBITz: decisions, constraints, rejected ideas, open questions.

---

## 2025-12-21– Daily Engineering Diary

### Problem Statement

**Address alignment**: A CPU (or CPU-like Host) may place a device’s **register index** in the “middle” of an address field (e.g., A3–A5) rather than in the low bits. Some Tiles would like to decode registers by simply sampling the **lowest address bits** (e.g., A[2:0] for 8 registers). The question is whether **alignment/normalization** should be performed by the **Host** (before the address reaches the Dock) or by the **Dock** (rewriting/rewiring the address before forwarding it to the Tile).

### Decisions

* **Keep status quo:** require the **Host** to perform any necessary address alignment/normalization for register addressing.
* Do **not** implement Dock-side alignment (address rewrite / “virtual rewire”) in v1.x.
* If a future platform truly requires complex alignment beyond a small Host PLD/CPLD, consider adding an optional Dock feature later.

### Constraints

* Keep **builder ergonomics** high: simple Hosts and “real IC” Tiles should be implementable with small PLDs/CPLDs (avoid making builders become FPGA specialists for basic Tiles).
* Preserve support for **sparse / legacy addressing** patterns common in retro recreations.
* Avoid turning the Dock into an **active address bridge** and a timing-critical element unless strongly justified.

### Worked Examples

#### Example 1 — ColecoVision

*Memory map* is cleanly range-decodable; register indexing is naturally in low address bits when it exists.

*I/O ports* use A7=1 and A6/A5 as device selects, with A4..A0 as sub-selection. In practice, Coleco devices typically do not expose “address-bit indexed register files” in the way that creates alignment pressure; the common access patterns do not require a Dock rewrite.

**Result:** no compelling need for Dock alignment; Host-side mapping remains straightforward.

#### Example 2 — Commodore 64 (C64)

Memory-mapped I/O regions (VIC-II, SID, CIA, etc.) are selected by higher address bits (e.g., A15..A8 or similar) and the *register/sub-address* is effectively in the low byte, which is already “right-aligned.”

The more complex part of C64 memory behavior is internal banking/visibility, which is a Host/platform concern and does not motivate a Dock-side address rewrite.

**Result:** again, no compelling need for Dock alignment; the Host mapping complexity is dominated by banking logic, not register alignment.

#### General pattern found

The “register address in the middle” problem most often comes from **word/longword alignment** (e.g., register spacing of 2 or 4 bytes), which typically reduces to a simple **shift/permutation** on the Host side (often achievable by wiring choices or a small PLD/CPLD).

### Rejected Ideas (and why)

* **Dock performs alignment by rewriting the address before forwarding to the Tile.**
  * Requires the address bus to pass *through* the Dock logic (active bridge): `A_in[31:0]` and `A_out[31:0]` (2× address pins) plus more routing/timing constraints.
  * Increases Dock verification burden (timing/settling relative to `/CS` and `/READY`) and likely pushes to a **larger FPGA** than otherwise required.

* **Restrict addressing to prefix masks only** to guarantee natural right-alignment.
  * Simplifies interoperability but discards legitimate **sparse mappings** used in recreations.

### Open Questions

* If Dock-side alignment is ever introduced in a future revision, define a “safe default” where the Dock **does nothing unless configured**.
* If Dock-side alignment is ever introduced, preferred transform class is a **“virtual rewire”** mapping (e.g., `Ain3 → Aout0`, `Ain4 → Aout1`, `Ain5 → Aout2`, …) rather than only a shift.
* If a “virtual rewire” is adopted, decide:
  * where/how it is encoded (likely in CPU descriptor per window),
  * how many address bits are in-scope for mapping (e.g., low 8/16 only vs full 32),
  * and validation rules (e.g., forbid ambiguous duplicate mappings, define behavior for unmapped bits).

### Notes

* Conclusion after tire-kicking: Host-side alignment does not significantly increase Host complexity in typical retro cases, while Dock-side rewrite would materially increase Dock complexity by turning it into an active address bridge.

