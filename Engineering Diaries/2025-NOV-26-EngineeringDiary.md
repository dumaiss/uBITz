# μBITz Engineering Diary

> Central engineering log for μBITz: decisions, constraints, rejected ideas, open questions.

---

## 2025-11-26 – Daily Engineering Diary

### Decisions

- **Dock power source & rails**
    
    - Reference Dock will use **USB-C PD (power-only)** as the primary input, electrically tolerant up to **20 V**, but the backplane will only expose **+5V_MAIN** and **+3V3_MAIN**.
        
    - The Dock SHALL always provide both 5 V and 3.3 V rails to the backplane; no 12 V rail is exported.
        
- **Tile-local auxiliary rails**
    
    - Any additional voltages (e.g., 12 V, ±12 V for SID/audio/legacy DRAM) must be generated **on Tiles** from the 5 V/3.3 V rails and MUST NOT be fed back into the Dock rails.
        
- **Power domains**
    
    - Split into **AON domain (3V3_AON)** for MCU/RTC/USB and **main domain (3V3_MAIN/5V_MAIN)** for Host/Bank/Tiles and the Dock CPLD/FPGA.
        
    - AON is powered from either PD or service USB via a **power mux + wide-input buck**.
        
- **Master switch behaviour**
    
    - A **mechanical DPST master switch** ("big fat switch") is adopted as a **true breaker**:
        
        - When OFF: disconnects both PD VBUS and service USB VBUS from Dock power, so **AON and main rails are completely dead** (only RTC coin cell remains).
            
        - When ON: enables the Dock power domain; AON and main rails are then controlled by regulators and firmware.
            
- **Soft power model**
    
    - A **momentary PWR button** is read by the Dock MCU in the AON domain.
        
    - MCU drives a single **MAIN_ON_REQ** signal that enables both 5 V and 3.3 V main rails.
        
    - Host can also request shutdown; MCU performs a controlled power-off (drop MAIN_ON_REQ after handshake/timeout).
        
- **Protection strategy**
    
    - All external connectors (PD, service USB) get **ESD protection, input fuses/eFuses, and TVS** close to the connector.
        
    - Main rails get **rail-level eFuses/PPPTCs**, with optional **per-slot PPTCs** on 5 V (and maybe 3.3 V) for kid-proofing.
        
- **POR & sequencing**
    
    - Adopt **"Option B – lightweight but solid"** sequencing:
        
        - Single supervisor on **3V3_AON** holds MCU in reset until AON is valid.
            
        - MCU controls MAIN_ON_REQ.
            
        - Buck regulators' PG outputs plus an MCU-controlled DOCK_LOGIC_RESET# gate the Dock CPLD/FPGA reset.
            
        - Reset ordering: AON + MCU → main rails → CPLD → SYS_RESET# release to Host/Bank/Tiles.
            
- **Cross-domain signalling**
    
    - Keep Dock MCU on AON and Dock CPLD/FPGA on main (3V3_MAIN).
        
    - All MCU→CPLD nets get **small series resistors (22–68 Ω)**; firmware keeps these GPIOs high-Z until 3V3_MAIN is good and Dock logic reset is released.
        
- **Documentation & reuse**
    
    - Power system is captured as a standalone **"Dock Power System Architecture"** document with a block diagram and BOM, intended to be reusable as a generic **USB-C PD power brick recipe** for other projects.
        
- **PD contract & 5 V-only behaviour**
    
    - Reference Dock is dimensioned for a USB-C PD source of at least **15 V @ 3 A (45 W)**, with **20 V @ 3 A** as a higher-headroom option for hungrier builds.
        
    - If PD negotiation yields only **5 V**, the Dock remains in **STANDBY/service-only**: AON is powered, but `MAIN_ON_REQ` is held low so backplane rails stay off.
        
- **Protection coordination rule**
    
    - Rail-level eFuses and per-slot PPTCs are sized so that `I_rail_nominal ≥ N_slots × I_slot_hold`, encouraging a single faulty Tile to trip its own PPTC rather than collapsing the entire rail.
        

### Constraints

- **Builder expectations**
    
    - Master power switch must behave like a real mains switch from the builder’s perspective: when OFF, the machine is electrically safe for card swaps and probing.
        
- **Backplane contract stability**
    
    - μBITz backplane contract remains 5 V + 3.3 V only; no future Dock rev should introduce 12 V or negative rails on standard connector pins.
        
- **PD envelope**
    
    - Front-end parts (mux, TVS, bucks) must be rated for **up to 20 V** input to keep the design reusable beyond μBITz.
        
- **Thermal / current budget**
    
    - Main rails preliminarily sized in the **3–4 A** class for both 5 V and 3.3 V; final limits depend on Host + worst-case Tile population.
        
- **PD inrush behaviour**
    
    - Bulk capacitance and power-path FETs must respect **USB-C PD inrush limits** by following the PD sink’s reference design (gate slew control, bulk caps behind the controlled FET) and keeping effective plug-in inrush below a few amps, to be validated on hardware.
        
- **Schematic organisation**
    
    - The Dock schematic will have a dedicated **Power + Control** sheet matching the architecture doc’s block diagram.
        
- **Schematic organisation**
    
    - The Dock schematic will have a dedicated **Power + Control** sheet matching the architecture doc’s block diagram.
        

### Rejected Ideas (and why)

- **Kill switch that only disables main rails (AON stays alive)**
    
    - Rejected because builders expect the “big switch” to remove all Dock power; having AON still live would be surprising and potentially unsafe for probing.
        
- **Providing a native 12 V rail on the Dock**
    
    - Rejected to keep the backplane contract simple and avoid propagating higher voltages; 12 V and exotic rails will remain Tile-local.
        
- **Heavy analog power sequencer IC**
    
    - Rejected as unnecessary complexity since the Dock MCU in AON can orchestrate sequencing with the help of a simple supervisor and regulator PG pins.
        
- **Relying only on internal POR (no external supervisor)**
    
    - Rejected to avoid ambiguous MCU start-up behaviour and brown-out glitches; external AON supervisor adds deterministic bring-up for minimal cost.
        

### Open Questions

- **Exact PD contract and power budget**
    
    - Final decision needed on target PD profile (e.g., 12 V vs 15 V vs 20 V; 3 A vs 5 A) and corresponding worst-case Dock load.
        
- **Regulator family & sizing**
    
    - Need to confirm regulator choices and currents based on a concrete “maxed-out” build (e.g., Z80 Host + SRAM-heavy Bank + 4 Tiles including VDP/Sound).
        
- **Per-slot protection granularity**
    
    - Decide whether the reference Dock uses per-slot PPTCs on both rails, only on 5 V, or grouped per pair of slots.
        
- **Monitoring & telemetry**
    
    - How much rail/PD telemetry should the MCU expose (input voltage sense, per-rail current/overcurrent events, etc.)? Is this just for debugging or part of the official Dock API?
        
- **Host-visible power states**
    
    - Define how the Dock exposes HARD OFF / STANDBY / ON / SERVICE-ONLY to the Host (e.g., status register vs. dedicated pins) so OS/firmware can make informed decisions.
        

### Notes

- The Dock power architecture is now well-specified at a block-diagram level and is ready to be translated into KiCad schematic sheets.
    
- The BOM in the Dock Power System Architecture doc is intentionally conservative (over-rated parts) to keep the design broadly reusable; later revisions can optimise for cost and availability.
    
- The chosen PD/mux/regulator/supervisor pattern can be standardised as a μBITz "power brick" module and reused on future boards (e.g., all-in-one consoles, Tile carriers) with minimal changes.
    
- Once a first Dock prototype is built, real-world current measurements will feed back into tightening PD contract, fuse values, and regulator choices.
    
- An external review of the Dock power architecture confirmed the overall structure (AON/main split, master switch semantics, protection, sequencing) and highlighted that remaining work is largely numeric tuning (PD profile, fuse/eFuse values, thermal margins) rather than structural changes.
    
- Future diary entries should capture: concrete part selections (with supplier/stock notes), layout constraints (connector placement, copper pours), bring-up test plans (what to probe first, expected waveforms), and any deviations from the reference power brick pattern on derivative boards.