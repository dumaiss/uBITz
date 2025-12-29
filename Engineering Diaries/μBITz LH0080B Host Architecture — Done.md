# μBITz LH0080B Host Architecture — Definition of Done

**Document Version:** Rev 3 (Post-Claude Review)  
**Review Date:** December 20, 2024  
**Reviewer:** Claude (Architecture Assessment)  
**Status:** ✅ **APPROVED FOR SCHEMATIC CAPTURE**

---

## Executive Summary

The **μBITz LH0080B Host System Architecture** has successfully passed architectural review and is **cleared to proceed to schematic design**.

All critical architectural decisions have been made, component selections validated, and risk mitigation strategies defined. The design demonstrates sound engineering judgment appropriate for a hobbyist-accessible retro computing platform.

---

## Approval Criteria Met

|Criterion|Status|Evidence|
|---|:-:|---|
|**Major components specified**|✅|CPU, CPLD, MMU, translators all selected with part numbers|
|**Resource budgets validated**|✅|CPLD: 40/64 macrocells (38% margin); Pins: 22-30/34 (fits both scenarios)|
|**Voltage domain strategy defined**|✅|5V island + 3.3V bus with explicit level translation|
|**Timing approach established**|✅|Conservative worst-case values; validation deferred to prototype|
|**Power budget quantified**|✅|~450-500mA total with datasheet-backed estimates|
|**Risk mitigation documented**|✅|All HIGH risks reduced to LOW/MED with clear mitigation paths|
|**Open items tracked**|✅|Clear separation: Resolved / Implementation-phase / Prototype-phase|
|**Internal consistency**|✅|No contradictions; TBD items properly tracked|

---

## Key Architectural Decisions (Locked)

1. **CPLD:** ATF1504AS-10AU44 (64 macrocells, JTAG programmable)
2. **Address Translation:** SN74LVC245A × 3 (unidirectional, 5V→3.3V)
3. **Data Translation:** SN74LVC8T245 (bidirectional, manual DIR control)
4. **Memory Mapper:** SN74LS612 (16→24 bit expansion, +8 address bits)
5. **Bus Declaration:** AddressBusWidth=32, with A[31:24] tied low
6. **Power Source:** Dock-provided 5V + 3.3V (no local regulation)
7. **Clock Source:** 14.31818 MHz oscillator with CPLD-divided CPU clock

---

## Implementation Phase Responsibilities

The following items are **intentionally deferred** to schematic/HDL implementation:

### Schematic Phase

- I/O decode placement (in-CPLD vs external) → affects pin budget fork
- CPLD DIR/OE state machine design + safety review
- Mapper control register model + I/O port allocation
- Clock divider configuration (strap options if needed)

### Prototype Phase

- Timing validation with real trace lengths
- Power consumption measurements under load
- /READY↔/WAIT feedback path characterization
- Interrupt acknowledge timing verification

---

## Risk Acceptance

All residual **MEDIUM** risks are appropriate for this design phase:

- **Timing closure at 6 MHz:** Conservative component selection provides margin; prototype validation will confirm
- **Power budget:** Datasheet-backed estimates are conservative; early measurement will validate
- **DIR control complexity:** Standard practice for bidirectional translation; HDL review will verify safety

No **HIGH** risks remain unmitigated.

---

## Recommendation

**PROCEED TO SCHEMATIC CAPTURE** with the following conditions:

### Immediate Actions (Before Schematic Freeze)

1. Decide I/O decode strategy (affects CPLD pin budget: 22 vs 28-30 pins)
2. Select specific ATF1504AS package (confirm 34 I/O availability in 44-TQFP)
3. Define JTAG connector footprint (2×5 header or Tag-Connect)

### Near-Term Actions (During HDL Development)

4. Design CPLD DIR/OE control state machine
5. Define LS612 programming model + safe update rules
6. Create timing budget spreadsheet (use worst-case translator values documented)

### Prototype Phase

7. Validate power budget with real measurements
8. Characterize /READY→/WAIT timing with scope
9. Test interrupt acknowledge vector fetch timing

---

## Signoff

This architecture document provides sufficient definition to begin schematic capture while appropriately deferring implementation details to later phases. The design balances hobbyist accessibility with engineering rigor.

**Architecture Status:** ✅ **APPROVED**  
**Gate to Next Phase:** ✅ **CLEARED FOR SCHEMATIC DESIGN**

**Signed:**  
Claude (AI Technical Reviewer)  
December 20, 2024

---

## Appendix: Minor Corrections for Next Revision

**Non-blocking items** (can be corrected during schematic review):

1. Section 5.1 states "32 user I/O pins" — should be **34 user I/O** for ATF1504AS-10AU44 (44-TQFP)
    
    - _Impact: None (pin budgets of 22 and 28-30 still fit comfortably)_
2. Consider adding explicit note in Section 10.3 that LS612 requires **4 I/O addresses** (per datasheet)
    
    - _Impact: Informational only; doesn't change architecture_

---

**END OF SIGNOFF**