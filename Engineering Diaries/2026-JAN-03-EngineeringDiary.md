
---

## 2026-01-03– Daily Engineering Diary

### Decisions

* Treat Option 1 and Option 2 as one mechanism: **bounded `/READY`** parameterized by a Host-declared maximum wait budget.
* Keep the existing **mostly-asynchronous framing** and “dance”: CPU asserts `/IORQ↓`, Dock/backplane **immediately claims** the cycle by pulling CPU-visible `/READY↓`, then asserts `/CS[n]↓` after decode is stable; `/READY↑` indicates completion; `/IORQ↑` ends the cycle; `/CS↑` deselects.
* Make `/READY` explicitly **non-indefinite**: Dock/backplane **MUST NOT** hold CPU-visible `/READY=0` longer than the Host’s stated capability.
* Add `ReadyMaxuS` (µs) to the **CPUDescriptor** by repurposing header reserved bytes: replace `Reserved1[10]` with `uint32_t ReadyMaxuS` + `Reserved1[6]`, preserving header size (16 bytes) and overall descriptor size (416 bytes).
* Define **timeout completion** as a normative behavior when `ReadyMaxuS` expires: release `/READY→1` to complete the cycle; reads return all-ones on active width; writes are treated as not committed; latch a timeout fault for software.
* Add non-normative Tile guidance to prefer **no-wait** designs (buffering, command/status, polling/IRQ) to avoid bus stalls.

### Constraints

* Some Hosts (e.g., 6809-class) cannot tolerate long wait-state stretching; `/READY` cannot be treated as indefinitely holdable.
* `/IORQ` must not be deasserted while `/READY=0`, so the CPU cannot be relied upon to “abort” a hung cycle; the Dock/backplane must enforce the bound.
* CPUDescriptor is a fixed-size binary structure; new fields must preserve offsets and total size unless a version bump is intended.
* Returning `0xFF` on timeout is potentially ambiguous as data, so a separate fault indication is required.

### Rejected Ideas (and why)

* Add a new handshake pin (e.g., `/RACK`) to support indefinite stalls: increases connector/pin complexity and still does not solve CPUs that cannot be halted mid-cycle; bounded `/READY` + timeout completion covers the safety need.
* Split-transaction I/O as the primary model: increases Dock statefulness and software complexity; contradicts the simple synchronous contract.

### Open Questions

* What is the canonical **fault reporting mechanism** for timeout completion (Dock status register, per-slot IRQ, both) and the minimum latched info (slot id, cycle type, address bits)?
* What are sensible recommended defaults for `ReadyMaxuS` per CPU family/profile (Z80-like vs 6502/6809-like), and should the Dock also impose an absolute hard cap regardless of Host setting?
* Should Tiles optionally advertise a worst-case response time in EEPROM so the Dock can detect incompatibilities early?

### Notes

* Codex implementation requires patching multiple files: Core Logical (new §1.6.0 + claim-step edits), Platform (timeout enforcement responsibilities), Host Spec (descriptor field), Tile Base (guidance), and Parallel Profile (remove CPU-timeout wording; reflect the “dance” in examples).

