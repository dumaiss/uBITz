# μBITz Engineering Diary

> Central engineering log for μBITz: decisions, constraints, rejected ideas, open questions.

---

## 2025-12-25– Daily Engineering Diary

### Decisions

* Replace the original 3-sense-pin scheme with a **2-pin, no-occupancy** strap scheme per slot:
  * `DRV5V#` (active-low): strapped low only if the device may drive 5 V outputs onto the shared bus.
  * `SENS3V#` (active-low): strapped low only if the device is **3.3 V-only** (not 5 V tolerant).
  * Dock provides pull-ups to **+3V3_AON**; an empty slot reads `1/1` and is treated as “safe/universal” for the interlock.
* Implement compatibility as a **damage-prevention interlock**:
  * Block only the hazardous case: **(someone drives 5 V) AND (someone is 3.3 V-only)**.
* For Dock-generated **control outputs** (active-low by convention), use **open-drain drivers** with pull-ups selected to match the emergent system voltage:
  * Pull up to **+5V_MAIN** when `ANY_DRV5V=1`.
  * Pull up to **+3V3_MAIN** when `ANY_DRV5V=0`.
  * Address/data bus remains push-pull and is not Dock-driven.
* Correct earlier misunderstanding: **VCC_3V3_STBY is removed/renamed**; the profile exposes only VCC_3V3 (plus optional VCC_5V where supported).

### Constraints

* Sense logic must work from the Dock’s **AON domain** only (no dependence on slot power or MCU GPIO sampling).
* Avoid repurposing power/ground pins for sensing to stay aligned with platform connector principles.
* Control outputs may be open-drain; the **address/data bus must remain push-pull** and is outside this pull-up selection mechanism.

### Rejected Ideas (and why)

* GND-based occupancy sensing: unnecessary once the interlock is expressed as a 2-pin hazard test; also conflicts with “don’t reassign power/ground” guidance.
* Treating `VCC_3V3_STBY` as a guaranteed standby rail for slots: not true in the reference Dock; replaced with a single VCC_3V3 concept.

### Open Questions

* Pin allocation: which exact per-slot connector pins carry `DRV5V#` and `SENS3V#` across all profiles without constraining future features.
* Pull-up selection circuit detail: simplest robust implementation (e.g., always-weak AON pull-up + stronger switched MAIN pull-up) for deterministic levels before PG.

### Notes

* Update all scenario truth tables and boolean equations to reflect **active-low straps** and the new hazard-only compatibility rule.
* Add conformance language requiring Tiles/Hosts/Banks to populate straps (or explicitly document the risk of defaulting to “safe/universal”).

