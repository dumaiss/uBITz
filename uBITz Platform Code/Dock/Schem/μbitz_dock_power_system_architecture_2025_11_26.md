# μBITz Dock Power System Architecture

> High-level power and control design for the reference μBITz Dock, PD-capable up to 20 V but exporting only 3.3 V and 5 V to the backplane.

---

## 1. Goals & Scope

This document defines the **high-level power architecture** for the reference μBITz Dock:

- Power input via **USB-C PD (power-only)**, capable of accepting up to **20 V** contracts.
    
- The Dock **only guarantees** two rails on the backplane:
    
    - **+5V_MAIN** (mandatory)
        
    - **+3V3_MAIN** (mandatory)
        
- No 12 V or negative rails are provided by the Dock. Builders MAY derive additional local rails (e.g., 12 V, ±12 V) **on Tiles** from the Dock rails.
    
- A separate **always-on (AON) domain** powers the Dock MCU, RTC logic, and service USB interface.
    
- An **RTC** is backed by a coin cell / VBAT so that timekeeping survives total power loss.
    
- A **service USB port** connects the Dock MCU to an external modern PC.
    
- The Dock supports:
    
    - Power from **USB-C PD only**,
        
    - Power from **service USB only** (for AON/service),
        
    - **Both** present at the same time.
        
- A **direct mechanical master switch** ("big fat switch") kills all Dock power (AON + main rails), leaving only the RTC coin cell.
    
- A **momentary power button** plus firmware-controlled logic implement soft power sequencing (ON/OFF) when the master switch is ON.
    
- Robust **protection** (ESD, fuses/eFuses, per-rail and optional per-slot limiting) provides "kid protection" for builders.
    

This design is intended to be reusable as a general **USB-C PD power brick** for other projects.

---

## 2. Power Inputs, Rails, and Domains

### 2.1 Inputs

- **USB-C PD power-only port**
    
    - Provides **VBUS_PD_RAW** (5–20 V negotiated via PD).
        
    - Used as the **primary power source** for μBITz.
        
- **USB service port (to PC)**
    
    - Provides **VBUS_PC_RAW** (5 V from PC).
        
    - Used as an **auxiliary power source** for the AON domain.
        

### 2.2 Dock rails

Derived rails inside the Dock:

- **+5V_MAIN**
    
    - Main 5 V rail
        
    - Exported to the backplane and SHALL be provided by the Dock.
        
    - Derived from VBUS_PD (post-protection/master switch) via a buck regulator.
        
- **+3V3_MAIN**
    
    - Main 3.3 V rail
        
    - Exported to the backplane and SHALL be provided by the Dock.
        
    - Derived from VBUS_PD (post-protection/master switch) via a buck regulator (or from +5V_MAIN via a secondary buck; implementation choice).
        
- **+3V3_AON**
    
    - Always-on 3.3 V rail
        
    - Powers Dock MCU, RTC logic (VCC), config flash, USB PHY, and housekeeping logic.
        
    - Derived from a **power-muxed** input that can be fed by PD or PC.
        
- **VBAT_RTC**
    
    - Coin cell or supercap-backed VBAT for RTC.
        
    - Feeds only the RTC VBAT pin so timekeeping survives total power loss.
        

### 2.3 Tile-local auxiliary rails

- The Dock **does not** export 12 V, negative rails, or any other auxiliary rails.
    
- Tiles are **allowed** to derive local rails from +5V_MAIN or +3V3_MAIN, e.g.:
    
    - 12 V for analog sections or legacy DRAM,
        
    - ±12 V for audio chips (e.g., SID) or op-amps.
        
- Tiles MUST NOT back-feed power onto +5V_MAIN or +3V3_MAIN.
    

### 2.4 Power budget and PD contract

The Dock power system is sized so that a single USB-C PD source can supply a fully populated μBITz stack (Host, Bank, and four Tiles) with margin. Exact numbers depend on the specific Host/Bank/Tile implementations; the table below is therefore **illustrative** and MUST be refined once concrete boards exist.

|Subsystem|Example @ 5 V|Example @ 3.3 V|Notes|
|---|---|---|---|
|Host CPU card|~0.5 A|~0.3 A|Retro CPU + glue + local peripherals|
|Bank memory card|~0.3 A|~0.2 A|SRAM / DRAM, address decode, etc.|
|Tile (per slot)|~0.3 A|~0.2 A|Worst-case “heavy” Tile (VDP, sound, etc.)|
|Dock logic (MCU/CPLD)|negligible|~0.1 A|AON + main logic overhead|

For a fully populated Dock with four Tiles, this example budget yields:

- **5 V rail (example):**
    
    - Host + Bank ≈ 0.8 A
        
    - 4 × Tiles ≈ 1.2 A
        
    - **Total ≈ 2.0 A** @ 5 V
        
- **3.3 V rail (example):**
    
    - Host + Bank ≈ 0.5 A
        
    - 4 × Tiles ≈ 0.8 A
        
    - Dock logic ≈ 0.1 A
        
    - **Total ≈ 1.4 A** @ 3.3 V
        

With regulator efficiency in the 85–90% range, this corresponds to roughly **20–25 W** of DC load in a “worst-case but reasonable” configuration. To keep generous margin and allow for future hungrier Tiles, the reference Dock targets a PD contract of:

- **Recommended PD profile:** at least **15 V @ 3 A** (45 W)
    
- **Acceptable alternate:** **20 V @ 3 A** for additional headroom (e.g., particularly power-hungry Tiles)
    

#### 2.4.1 Behaviour with insufficient PD capability (e.g., 5 V only)

If the PD sink negotiates only **5 V** (or if no explicit PD contract can be established and the source falls back to 5 V default):

- The Dock **MAY** power the AON domain from 5 V (subject to regulator limits).
    
- The Dock MCU **SHOULD keep MAIN_ON_REQ deasserted** so that +5V_MAIN and +3V3_MAIN remain off.
    
- In this state, the Dock is effectively in **STANDBY / service-only** mode:
    
    - MCU and RTC are powered.
        
    - USB service functions (firmware update, diagnostics) may be available.
        
    - Backplane rails are disabled; Host/Bank/Tiles are not powered.
        

The Dock firmware should treat “insufficient PD power” as a distinct state (e.g., via an internal status flag or LED indication), so builders understand why the machine cannot be fully powered from a weak 5 V-only source.

---

## 3. Protection Front-End ("Kid Protection")

### 3.1 USB-C PD input protection

At the USB-C PD connector:

1. **ESD protection**
    
    - Low-capacitance ESD arrays on CC1/CC2, SBU1/SBU2 (if used), D+/D– (if data ever used), and VBUS shell.
        
2. **Input fuse / eFuse**
    
    - Polyfuse or dedicated eFuse on VBUS_PD_RAW to protect against downstream shorts.
        
    - Rated for up to 20 V and the maximum negotiated PD current.
        
3. **TVS diode & filter**
    
    - Unidirectional TVS rated above max PD voltage (e.g., 24–30 V) on VBUS_PD_RAW.
        
    - LC or ferrite + capacitor filter to tame hot-plug ringing and EMI.
        
4. **PD sink controller**
    
    - PD sink IC negotiates 5–20 V contracts with the source.
        
    - Takes its bias supply from protected VBUS_PD_RAW.
        

After these elements, we define **VBUS_PD_PROT**.

In the reference implementation, the PD sink IC is placed **upstream of the master switch** and is powered directly from VBUS/CC according to its datasheet (dead-battery mode). This means that when a USB-C cable is plugged in but the master switch is OFF, the PD sink may draw a very small quiescent current (≪ 1 mA) to maintain CC terminations and negotiate. All Dock rails downstream of the master switch (+3V3_AON, +5V_MAIN, +3V3_MAIN) remain completely unpowered in this state.

### 3.2 Service USB input protection

At the service USB connector:

1. **ESD protection** on D+, D–, connector shield.
    
2. **Small polyfuse** on VBUS_PC_RAW to limit Dock draw from the PC.
    
3. **TVS diode** for 5 V transients.
    

After these, we define **VBUS_PC_PROT**.

---

## 4. Master Power Switch (Mechanical High-Side)

### 4.1 Behaviour

The **master power switch** is a **direct high-side mechanical switch** that:

- When OFF:
    
    - Disconnects VBUS_PD_PROT and VBUS_PC_PROT from the Dock’s internal power domain.
        
    - Ensures **+3V3_AON, +3V3_MAIN, +5V_MAIN are all OFF**.
        
    - Dock MCU, USB PHY, Host/Bank/Tiles, etc. are completely unpowered.
        
    - Only the RTC coin cell (VBAT_RTC) remains live.
        
- When ON:
    
    - Connects VBUS_PD_PROT to **VBUS_PD_SYS**.
        
    - Connects VBUS_PC_PROT to **VBUS_PC_SYS**.
        
    - Allows the AON and main regulators to operate.
        

This matches the builder expectation that flipping the "big fat switch" OFF makes the machine electrically safe for:

- Plugging/removing Tiles,
    
- Clipping probes to the backplane or cards,
    
- Reconfiguration without any Dock rails being live.
    

### 4.2 Implementation

- Use a suitably rated **2-pole mechanical switch** (toggle/rocker):
    
    - Pole 1: VBUS_PD_PROT → VBUS_PD_SYS
        
    - Pole 2: VBUS_PC_PROT → VBUS_PC_SYS
        
- The switch must be rated for at least 24 V DC and the maximum expected current (e.g., 3–5 A).
    
- Wiring between the connector area and the switch should be short and separated from sensitive signals.
    

---

## 5. AON Power Path & Soft Power Control

### 5.1 AON power-mux and regulator

When the master switch is ON, both VBUS_PD_SYS and VBUS_PC_SYS are available to the Dock.

The AON rail is derived as follows:

- **Inputs to AON power-mux:**
    
    - VBUS_PD_SYS (5–20 V from PD)
        
    - VBUS_PC_SYS (5 V from PC)
        
- **Power-mux behaviour:**
    
    - Provides reverse-current blocking so inputs don’t back-feed each other.
        
    - PD side typically has priority when both are present.
        
- **AON regulator:**
    
    - A wide-input buck (e.g., 4.5–20 V → 3.3 V).
        
    - Output is **+3V3_AON**.
        
- **Loads on +3V3_AON:**
    
    - Dock MCU
        
    - RTC VCC (VBAT still on coin cell)
        
    - Config flash for MCU
        
    - USB PHY or MCU’s USB interface
        
    - Any minimal housekeeping logic (power-good sensing, etc.).
        

### 5.2 Soft power control

Soft power is implemented in the **AON domain**, via the MCU.

**Inputs to MCU:**

- **PWR_BTN#** – front-panel **momentary** power button, active-low.
    
- **PG_5V_MAIN, PG_3V3_MAIN** – power-good outputs from main regulators/eFuses.
    
- **Presence indication** of VBUS_PD_SYS and/or VBUS_PC_SYS (for state decisions).
    

**Outputs from MCU:**

- **MAIN_ON_REQ** – firmware-controlled request to enable main rails.
    
- **SYS_RESET#** – global system reset signal to Host/Bank/Tiles.
    

**Main regulator enables:**

- 5 V buck / eFuse has **EN_5V_MAIN**.
    
- 3.3 V buck / eFuse has **EN_3V3_MAIN**.
    

We define:

```text
EN_5V_MAIN  <= MAIN_ON_REQ
EN_3V3_MAIN <= MAIN_ON_REQ
```

In the reference design, this follows **Option A – gate the bucks directly**:

- `EN_5V_MAIN` is wired to the **enable pin of the 5 V buck regulator**.
    
- `EN_3V3_MAIN` is wired to the **enable pin of the 3.3 V buck regulator**.
    

The bucks themselves are therefore the primary switches for the main rails; any eFuses or PPTCs sit downstream as protection devices only, not as the main on/off control.

(Optionally, EN signals may be gated further if per-slot power control is added.)

### 5.3 Soft power state machine (informative)

When the **master switch is ON** and AON is present:

1. **Standby (soft OFF)**
    
    - MCU boots from +3V3_AON.
        
    - MAIN_ON_REQ = 0 → +5V_MAIN and +3V3_MAIN are off.
        
    - Dock is in a low-power standby state.
        
2. **Power-on sequence**
    
    - User presses PWR button.
        
    - If VBUS_PD_SYS is present, MCU sets MAIN_ON_REQ = 1.
        
    - Regulators enable, PG_5V_MAIN and PG_3V3_MAIN assert.
        
    - MCU then deasserts SYS_RESET# to Host/Bank/Tiles.
        
3. **Soft power-off sequence**
    
    - User presses PWR button while system is on, or Host issues shutdown command.
        
    - MCU notifies Host (e.g., via Dock register or interrupt) and waits for ack or timeout.
        
    - MCU asserts SYS_RESET# (optional) and then sets MAIN_ON_REQ = 0.
        
    - Main rails drop; MCU remains running on +3V3_AON.
        
4. **Service-only mode**
    
    - If PD is absent but PC USB is present and master is ON:
        
        - AON rail is powered from VBUS_PC_SYS via the power-mux.
            
        - MAIN_ON_REQ remains 0.
            
        - Dock MCU can enumerate as a USB device and be serviced (firmware updates, diagnostics).
            

---

## 6. Main Rails & Backplane Power Distribution

### 6.1 Main regulators

From VBUS_PD_SYS (after master switch):

- **5 V main buck** → +5V_MAIN
    
- **3.3 V main buck** → +3V3_MAIN
    

Both regulators:

- Must tolerate up to 20 V input (matching max PD contract).
    
- Should provide power-good outputs.
    
- Feed into downstream protection for the backplane.
    

### 6.2 Rail-level protection

Immediately after the main regulators:

- **Rail eFuses or polyfuses** on:
    
    - +5V_MAIN
        
    - +3V3_MAIN
        

Functions:

- Current limiting
    
- Short-circuit protection
    
- (For eFuses) over-voltage and thermal protection.
    

### 6.3 Per-slot or per-group limiting (optional but recommended)

For builder-friendliness:

- Consider per-slot polyfuses on +5V_MAIN (and optionally +3V3_MAIN).
    
- Alternatively, per-pair/per-group limiting to balance cost vs protection.
    

Benefits:

- A short or fault on one Tile does not pull down the entire backplane.
    
- The reference Dock demonstrates best practices, even if minimal implementations choose simpler protection.
    

### 6.4 Backplane contracts

From the perspective of Host/Bank/Tiles:

- The Dock provides:
    
    - **+5V_MAIN** and **+3V3_MAIN** within the specified tolerances.
        
    - Maximum total current per rail (TBD in spec).
        
    - Optional per-slot current limits (if implemented).
        
- Host/Bank/Tiles SHALL:
    
    - Treat +5V_MAIN and +3V3_MAIN as inputs only.
        
    - Not source power back onto these rails.
        
    - Derive any auxiliary rails locally, and not expose them onto standard backplane pins.
        

### 6.5 Protection coordination (rail vs slot limits)

To ensure that a fault on a single Tile does not immediately collapse the entire Dock, the rail-level protection and any per-slot PPTCs should be dimensioned coherently.

Design rule:

- Let **N_slots** be the maximum number of powered Tile slots.
    
- Let **I_slot_hold** be the PPTC hold current selected per slot on a given rail.
    
- Let **I_rail_nominal** and **I_rail_trip** be the nominal and trip currents of the rail-level eFuse or protection device.
    

Then:

- Choose **I_rail_nominal ≥ N_slots × I_slot_hold**, so that all slots can legitimately draw near their hold currents without nuisance tripping the rail.
    
- Ensure **I_rail_trip** is high enough to tolerate a single-slot fault long enough for that slot’s PPTC to heat and trip, but still low enough to protect connectors and copper in the event of multiple simultaneous faults.
    

Illustrative example (to be tuned once real current budgets are known):

|Rail|Rail device (example)|Rail nominal / trip (example)|Per-slot PPTC (example)|Notes|
|---|---|---|---|---|
|+5V_MAIN|STEF05 eFuse|~5 A nominal / 6–7 A trip|1.1 A hold / 2.2 A trip|With 4 slots, N_slots × I_slot_hold ≈ 4.4 A, below rail nominal|
|+3V3_MAIN|STEF033 / STEF4S|~3 A nominal / 4–5 A trip|0.75 A hold / 1.5 A trip|Similar logic for 3.3 V rail|

These numbers are **examples only**; the key requirement is that **slot protection is meaningfully lower than the rail limit**, so that a single bad Tile tends to isolate itself rather than pulling the whole Dock down.

### 6.6 Fault detection and MCU response

Where protection devices expose digital status (e.g., FAULT pins, I²C flags), the Dock MCU should monitor them and react in a predictable way. A suggested mapping is:

|Fault condition|Detector / source|Recommended MCU behaviour|
|---|---|---|
|PD over-voltage / error on input|PD sink IC status / I²C flags (if connected)|Optionally log the event (e.g. diagnostic counter), and keep MAIN_ON_REQ deasserted until the PD controller reports a valid, safe contract again.|
|+5V_MAIN over-current / short|5 V rail eFuse FAULT# (if available)|Record fault, drop MAIN_ON_REQ to shut down main rails, optionally attempt a limited number of automatic restarts with back-off.|
|+3V3_MAIN over-current / short|3.3 V rail eFuse FAULT#|Same pattern as 5 V: log, shut down, and optionally retry.|
|Single-slot over-current|Per-slot PPTC (thermal, passive)|No direct digital signal; the MCU may only infer via abnormal rail behaviour (e.g., PG flicker). The main guarantee is that other slots continue to be powered.|
|3V3_MAIN brown-out|Regulator PG_3V3_MAIN deasserted, or MCU ADC on rail|Treat as an immediate fault: assert SYS_RESET#, deassert MAIN_ON_REQ, and wait for rails and PD status to stabilise before allowing another power-on.|

The exact policy (e.g., how many restart attempts to allow) is left to Dock firmware, but it should be **deterministic and documented** so that builders can reason about failure modes.

### 6.7 Inrush limiting and PD compatibility

USB-C PD sources typically enforce limits on inrush current and total input capacitance. To avoid nuisance trips when hot-plugging the Dock:

- Place the **largest bulk capacitance** on the PD path **behind** the PD sink’s controlled power FET (following the STUSB4500 reference design).
    
- Use the PD sink’s recommended gate network (RC / slew-rate control) for the power FET so that VBUS rises with a controlled slope rather than as a hard step.
    
- Keep additional bulk capacitance on VBUS_PD_RAW modest, relying instead on the main and AON bucks’ built-in soft-start behaviour and local output capacitors.
    
- As a design target, aim to keep effective inrush current **below ~3 A** during plug-in for compatibility with common PD chargers; verify against the chosen PD controller’s application notes and measured waveforms on the prototype.
    

If additional damping is required after bring-up measurements, an NTC thermistor on the PD input path may be added, but this should be a last resort due to its temperature dependence and impact on normal operating losses.

---

## 7. RTC Powering

The RTC has two power pins:

- **VBAT_RTC** (coin cell / supercap)
    
    - Keeps time when all other power is off.
        
- **VCC_RTC** (logic supply)
    
    - Connected to +3V3_AON.
        
    - Allows full RTC operation (register access, alarms, etc.) when AON is present (PD or PC + master ON).
        

Behaviour:

- Master OFF:
    
    - +3V3_AON is 0; RTC runs from VBAT_RTC only.
        
- Master ON, AON powered (PD or PC):
    
    - RTC runs from +3V3_AON.
        
    - VBAT_RTC acts as backup only.
        

---

## 8. Power States (Summary)

### 8.1 HARD OFF

- Master switch OFF.
    
- VBUS_PD_SYS = 0, VBUS_PC_SYS = 0.
    
- +3V3_AON = 0, +3V3_MAIN = 0, +5V_MAIN = 0.
    
- Dock MCU and USB interface unpowered.
    
- Only RTC on VBAT_RTC is alive.
    

This is the safe builder state for inserting/removing Tiles and connecting probes.

### 8.2 STANDBY (Soft OFF)

- Master switch ON.
    
- PD and/or PC USB present.
    
- AON powered via power-mux → +3V3_AON.
    
- MAIN_ON_REQ = 0 → main rails off.
    
- Dock MCU running; USB service available; RTC logic powered.
    

### 8.3 ON (System Running)

- Master switch ON.
    
- PD present (primary power); PC USB may or may not be present.
    
- AON powered.
    
- MCU has set MAIN_ON_REQ = 1.
    
- +5V_MAIN and +3V3_MAIN enabled; power-good asserted.
    
- Host/Bank/Tiles active.
    

### 8.4 Service-Only

- Master switch ON.
    
- PD absent; PC USB present.
    
- AON powered from PC; main rails off.
    
- Dock MCU accessible via USB for firmware update, diagnostics, etc.
    

---

## 9. Power-On Reset & Sequencing

### 9.1 Domains and responsibilities

- **AON domain (3V3_AON)**
    
    - Powers Dock MCU, RTC logic, config flash, USB PHY, and any small housekeeping logic.
        
    - Contains the **primary sequencing brain** (Dock MCU firmware).
        
- **Main domain (3V3_MAIN / 5V_MAIN)**
    
    - Powers the backplane (Host/Bank/Tiles) and the **Dock CPLD/FPGA** (decoder / IRQ router), which is placed on 3V3_MAIN.
        

The sequence is:

1. 3V3_AON comes up first when the master switch is ON.
    
2. Dock MCU comes out of reset and starts executing.
    
3. On a power-on request, MCU enables main rails (5V_MAIN, 3V3_MAIN).
    
4. Once main rails are good, CPLD/FPGA is released from reset.
    
5. Finally, system reset to Host/Bank/Tiles is released.
    

### 9.2 AON POR / supervision

The AON domain uses the **MCU's internal Brown-Out Detector (BOD)** for reset management:

- Modern MCUs have a robust built-in **Power-On Reset (POR)** and **Brown-Out Detection**:
    - Programmable BOD thresholds (typically 2.43V to 2.98V)
    - Automatic reset on power-up and voltage sag
    - ±50mV accuracy, sufficient for reliable operation

**For additional robustness:**

- The LMR33620 (U4) has a built-in **PGOOD** output that can be connected to ESP32.EN:
    - PGOOD goes HIGH when +3V3_AON is in regulation
    - If the regulator faults, PGOOD pulls low → ESP32 held in reset
    - Adds zero cost (already on the buck regulator)

This approach eliminates an unnecessary external component while maintaining reliable reset behavior.

### 9.3 Main rail bring-up and CPLD reset

- 5V_MAIN and 3V3_MAIN regulators expose **power-good (PG)** outputs.
    
- The Dock MCU controls a signal **MAIN_ON_REQ** that drives **EN_5V_MAIN** and **EN_3V3_MAIN**.
    

The recommended reset connection for the CPLD/FPGA is:

```text
CPLD_RESET# = PG_3V3_MAIN AND DOCK_LOGIC_RESET#
```

Where:

- **PG_3V3_MAIN** – high only when 3V3_MAIN is within spec.
    
- **DOCK_LOGIC_RESET#** – asserted/deasserted by the Dock MCU when it wants the Dock logic (CPLD, etc.) to run.
    

This guarantees the CPLD/FPGA cannot run unless its rail is good **and** the MCU explicitly allows it.

### 9.4 Host/Tile reset ordering

- The Dock exposes a system reset line, **SYS_RESET#**, to Host/Bank/Tiles.
    
- Reset ordering is:
    
    1. Enable main rails via MAIN_ON_REQ.
        
    2. Wait for PG_5V_MAIN and PG_3V3_MAIN to assert.
        
    3. Release Dock logic (CPLD_RESET#) by deasserting DOCK_LOGIC_RESET#.
        
    4. After a short guard time, deassert SYS_RESET# to Host/Bank/Tiles.
        

From the backplane’s perspective, they see clean, monotonic rails followed by a well-timed reset release.

### 9.5 MCU ↔ CPLD signal protection (series resistors)

Because the MCU lives on AON and the CPLD on the main domain:

- All MCU signals that drive into the CPLD should have **small series resistors** (e.g., 22–68 Ω) to:
    
    - Limit inrush / back-powering current if one domain is up and the other is not.
        
    - Help with edge-rate control and ringing on fast edges.
        
- In firmware, MCU pins connected to the CPLD should be kept as inputs or high-Z until:
    
    - PG_3V3_MAIN is asserted, and
        
    - DOCK_LOGIC_RESET# has been released.
        

This keeps cross-domain interactions well-behaved without needing a separate sequencing IC.

### 9.6 Power-up timing (informative)

The exact timing of rails and resets depends on the chosen regulators and supervisor, but the **relative ordering** should follow this pattern. The timeline below shows an example sequence:

```text
t =   0 ms : Master switch turns ON. PD source sees CC terminations; PD negotiation begins.

 t ≈  2–5 ms : PD contract established; VBUS_PD_PROT becomes valid.
              AON buck starts; 3V3_AON ramps up under its soft-start profile.

 t ≈  5–10 ms : 3V3_AON crosses supervisor threshold.
               AON supervisor keeps MCU in reset for its internal delay (e.g., 100 ms).

 t ≈ 15–20 ms : AON supervisor deasserts MCU reset.
               MCU boots, samples PD / PC presence, enters STANDBY (MAIN_ON_REQ = 0).

 t ≈ 20–30 ms : User presses PWR button, or Host requests power-on.
               MCU asserts MAIN_ON_REQ.

 t ≈ 25–40 ms : 5V_MAIN and 3V3_MAIN bucks enable and ramp.
               PG_5V_MAIN and PG_3V3_MAIN assert once rails are within tolerance.

 t ≈ 40–50 ms : MCU observes both PG signals high.
               MCU deasserts DOCK_LOGIC_RESET#, allowing CPLD/FPGA to start.

 t ≈ 50–60 ms : After a small guard time, MCU deasserts SYS_RESET# to Host/Bank/Tiles.
               System is now fully ON.
```

Timings above are indicative only; the schematic and firmware should enforce the **ordering** constraints (AON → MCU → main rails → Dock logic → Host/Bank/Tiles), while the exact millisecond values are tuned based on the final regulator and supervisor choices.

---

## 10. Schematic Block Diagram (Reference)

> This section is a wiring guide for the schematic, not a normative spec. Signal names here should match the actual Dock schematic net labels as closely as possible.

### 10.1 Top-level power & control

Textual block diagram of the main power and control path:

```text
USB-C PD Conn
  |
 [ESD / CMC]
  |
 [PTC / eFuse]
  |
 [TVS + LC/RC Filter]
  |
 VBUS_PD_RAW
  |
 [PD Sink IC]
  |
 VBUS_PD_PROT ------------------------------+----------------------+
                                            |                      |
                                        (sense)                (to master switch)

Service USB Conn
  |
 [ESD]
  |
 [PTC]
  |
 [TVS]
  |
 VBUS_PC_PROT ------------------------------+----------------------+
                                            |                      |
                                        (sense)                (to master switch)


                 +------------------- Master Switch (2-pole) -------------------+
		         |                                                              
           VBUS_PD_SYS                                                                      VBUS_PC_SYS
                 |                                                                                |                
                 |                                                                                |
                 |                        +-----------------------------+
                 |                        | AON Path                    |
                 |                        |                             |
                 |                        v                             v
                 |                 [Power Mux / Ideal Diodes]   (optional sense)
                 |                        |
                 |                    VIN_AON
                 |                        |
                 |                 [AON Buck (4.5–20 V -> 3.3 V)]
                 |                        |
                 |                     +3V3_AON
                 |                        |
                 |    +-------------------+--------------------------+
                 |    |                   |                          |
                 |  Dock MCU           RTC VCC                  USB PHY/MCU-USB
                 |
                 |                              (AON Supervisor or PG Pin
                 |                                 monitors 3V3_AON)
                 |                              [Supervisor] -> MCU_RESET#
                 |
                 +---------------------- Main Rail Path ------------------------+
                                          |
                                          v
                              VBUS_PD_SYS (only)
                                          |
                        +-----------------+-----------------+
                        |                                   |
                        v                                   v
                 [5 V Buck Reg]                       [3.3 V Buck Reg]
                        |                                   |
                   PG_5V_MAIN                         PG_3V3_MAIN
                        |                                   |
                 [5 V eFuse/Polyfuse]              [3.3 V eFuse/Polyfuse]
                        |                                   |
                     +5V_MAIN                         +3V3_MAIN
                        |                                   |
                 (slot fuses / groups)         (slot fuses / groups)
                        |                                   |
                 Backplane 5 V pins              Backplane 3.3 V pins
```

Control signals (logical wiring):

```text
PWR_BTN#  -> MCU GPIO (with RC + ESD as needed)

MAIN_ON_REQ (MCU GPIO) -> EN_5V_MAIN, EN_3V3_MAIN

PG_5V_MAIN, PG_3V3_MAIN -> MCU GPIOs

MCU_RESET# <= AON supervisor output

DOCK_LOGIC_RESET# (MCU GPIO) ----+
                                 +--[AND]--> CPLD_RESET#
PG_3V3_MAIN ---------------------+

MCU SYS_RESET# -> Backplane SYS_RESET#
```

### 10.2 MCU ↔ CPLD / logic interconnect

```text
+3V3_AON domain                       +3V3_MAIN domain
----------------                       ----------------

MCU GPIO x  ---> [22–68 Ω] ---> CPLD input x
MCU GPIO y  ---> [22–68 Ω] ---> CPLD input y
...                             ...

CPLD outputs -> (optional series R) -> Dock / backplane control signals

CPLD VCC  = +3V3_MAIN
CPLD GND  = Dock GND
CPLD_RESET# as defined above
```

Guidelines:

- Keep MCU pins that talk to the CPLD configured as inputs or high-Z until:
    
    - PG_3V3_MAIN is asserted, and
        
    - DOCK_LOGIC_RESET# has been deasserted.
        
- Use series resistors on MCU→CPLD nets to limit cross-domain current and tame edge rates.
    

### 10.3 RTC and coin cell

```text
Coin Cell (+) ----[optional series R/diode]---- VBAT_RTC
Coin Cell (-) --------------------------------- GND

RTC VCC  = +3V3_AON
RTC GND  = GND

I2C/SPI lines from MCU -> series R (optional) -> RTC
```

### 10.4 Backplane power and reset view

From the backplane perspective:

```text
+5V_MAIN   -> Dock connector power pins (5 V rail), via rail fuse and optional slot fuses
+3V3_MAIN  -> Dock connector power pins (3.3 V rail), via rail fuse and optional slot fuses
GND        -> Common ground plane
SYS_RESET# -> Global reset line driven by Dock MCU

(Optionally)
PWR_GOOD   -> Indication that main rails are within tolerance (derived from PG_5V_MAIN & PG_3V3_MAIN)
```

The CPU Host, Bank, and Tiles only need to respect:

- Do not back-feed +5V_MAIN or +3V3_MAIN.
    
- Do not assume any rail other than 5 V and 3.3 V is present.
    
- Use SYS_RESET# and any exposed PWR_GOOD signals for their own internal sequencing.
    

---

## 11. Summary of Design Decisions

- Use **USB-C PD** as primary input, tolerant of up to **20 V**.
    
- Provide only **+5V_MAIN** and **+3V3_MAIN** on the backplane; **5 V is mandatory**, 3.3 V is mandatory.
    
- Allow Tiles to derive their own auxiliary rails from Dock rails; forbid back-feeding.
    
- Implement a **direct mechanical master switch** that cuts both PD and PC power paths before they reach Dock rails.
    
- Implement an **AON domain** powered via a PD/PC power-mux and wide-input buck to +3V3_AON.
    
- Implement **soft power** in firmware:
    
    - Momentary PWR button → MCU → MAIN_ON_REQ.
        
    - Host-initiated shutdown supported.
        
- Protect inputs with **ESD, fuses/eFuses, TVS**, and backplane rails with rail-level and optional per-slot protection.
    
- Back RTC with a coin cell on VBAT_RTC and power its logic from +3V3_AON when available.
    

This architecture should be stable, builder-friendly, and adaptable as a reusable PD power recipe for other retro/embedded projects.

## 12. Power System BOM (Draft)

> First-pass, implementation-oriented BOM for the Dock power system. Values and exact part numbers are indicative and should be tuned once current budgets and board constraints are finalized.

| Block / Ref                           | Function                              | Suggested Part                                                                            | Key Specs / Rationale                                                                            | Notes / Alternatives                                                                                  |
| ------------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------- |
| **USB-C PD Input**                    |                                       |                                                                                           |                                                                                                  |                                                                                                       |
| J1                                    | USB-C PD power-only receptacle        | Generic 24-pin USB-C receptacle, e.g. Amphenol / GCT mid- or top-mount                    | Full-feature Type‑C pinout; supports CC pins and VBUS up to 20 V                                 | Pick footprint family you’re comfortable assembling; through-hole shell preferred for robustness      |
| U1                                    | USB-C PD sink controller              | **STUSB4500QTR**                                                                          | Standalone USB‑C PD sink, configurable PDOs up to 20 V / 5 A, dead-battery support               | Well-documented, lots of hobbyist examples; NVM-configured, MCU can optionally tweak over I²C         |
| F1                                    | PD input protection (resettable fuse) | USB‑C‑rated PPTC (e.g. Littelfuse 20 V profile, ~3 A hold)<br>SMDC300F/24-2               | Protects against sustained shorts on VBUS_PD_RAW; sized for chosen PD contract (e.g. 20 V / 3 A) | Could be replaced by a high-voltage eFuse if you want tighter control                                 |
| D1                                    | PD VBUS TVS                           | 24–30 V unidirectional TVS in SMB/SMF<br>SMBJ24A                                          | Clamps hot-plug and surge spikes on VBUS_PD_RAW                                                  | Choose standoff > 22 V, low clamping; place close to connector                                        |
| ESD1                                  | USB-C data/CC ESD array               | 4–6 channel low‑cap USB‑C ESD array<br>ESDA25SC6                                          | Protects CC1/CC2, D+/D–, SBU pins                                                                | Any USB‑C‑rated ESD array you like; follow layout in datasheet                                        |
| **Service USB Input**                 |                                       |                                                                                           |                                                                                                  |                                                                                                       |
| J2                                    | Service USB connector                 | USB‑C or micro‑B receptacle (data+power)                                                  | Connects Dock MCU to host PC                                                                     | Using a different physical connector than J1 may avoid user confusion                                 |
| F2                                    | Service USB VBUS PPTC                 | PPTC ~0.75–1.1 A hold, 5 V<br>1206L050YR                                                  | Limits current drawn from PC’s USB port                                                          | Simple resettable fuse is fine here                                                                   |
| D2                                    | Service USB TVS                       | 5 V USB TVS<br>SMBJ5.0A                                                                   | Protects VBUS_PC_RAW from ESD / surges                                                           | Use a part optimised for 5 V USB                                                                      |
| ESD2                                  | USB data ESD array                    | 2–4 ch USB2.0 ESD array<br>USBLC6-2SC6                                                    | Protects D+/D– on service port                                                                   | Standard USB2 protection footprint                                                                    |
| **Mechanical Switches / UI**          |                                       |                                                                                           |                                                                                                  |                                                                                                       |
| SW1                                   | Master power switch (DPST)            | Panel‑mount toggle or rocker, DPST, ≥5 A @ 30 VDC                                         | Cuts both VBUS_PD_PROT and VBUS_PC_PROT before they enter the Dock                               | Make it physically obvious: “big fat” main power switch                                               |
| SW2                                   | PWR button (momentary)                | Panel‑mount, NO momentary pushbutton                                                      | User soft‑power control (to MCU)                                                                 | Debounce in firmware; small RC + series R for ESD is plenty                                           |
| **AON Power Path**                    |                                       |                                                                                           |                                                                                                  |                                                                                                       |
| U3                                    | PD/PC power mux (AON)                 | **TPS2121** or similar 2.7–22 V power mux<br>;<br>TPS2121RUXR                             | Ideal-diode OR with priority and current limit; handles PD up to 20 V and a few amps             | Massive overkill for AON current but very robust; you can later downsize to a cheaper mux if desired  |
| U4                                    | AON buck regulator                    | 20–36 V in → 3.3 V, ~0.5–1 A, e.g. **LMR33620** configured for 3.3 V<br><br>LMR51450SDRRR | Powers +3V3_AON for MCU, RTC VCC, USB PHY, glue                                                  | Any wide‑input synchronous buck in the 1–2 A class is fine; pick what you like from your usual vendor |
| L4, Cin4, Cout4                       | AON buck magnetics & caps             | Inductor ~4.7–10 µH, low‑ESR ceramics per U4 datasheet                                    | Size for worst‑case Vin (20 V) and AON load                                                      | Exact values from chosen buck’s design tool                                                           |
| U5                                    | AON supervisor / POR<br>              | 3.0–3.1 V SOT‑23 voltage supervisor<br><br>LTC1326CMS8#TRPBF                              | Holds Dock MCU in reset until +3V3_AON is good                                                   | Any low‑Iq “simple reset” IC with open‑drain / push‑pull output works                                 |
| **Main Regulators & Rail Protection** |                                       |                                                                                           |                                                                                                  |                                                                                                       |
| U6                                    | 5 V main buck                         | 20–36 V in → 5 V, ≥3–4 A, e.g. **LMR51450SDRRR** configured for 5 V                       | Main +5V_MAIN rail for backplane and logic                                                       | Size for worst‑case fully populated Dock; 3–4 A is a good starting point                              |
| L6, Cin6, Cout6                       | 5 V buck magnetics & caps             | Inductor ~4.7–10 µH, bulk + ceramic caps                                                  | Layout and values per U6 datasheet                                                               | Place input caps tight to VIN/GND, good thermal pour                                                  |
| U7                                    | 3.3 V main buck                       | Same family as U6, configured to 3.3 V (or a second LMR51450SDRRR)                        | Main +3V3_MAIN rail for backplane and CPLD/FPGA                                                  | Reusing same regulator family simplifies layout and BOM                                               |
| L7, Cin7, Cout7                       | 3.3 V buck magnetics & caps           | Similar class to L6/Cin6/Cout6                                                            | Sized for expected 3.3 V load                                                                    | Again, follow regulator datasheet design curves                                                       |
| U8                                    | 5 V rail eFuse                        | **STEF4SPUR** (5 V eFuse) or equivalent                                                   | Over‑current / over‑voltage protection on +5V_MAIN before backplane                              | Offers nice fault reporting and controlled restart behaviour                                          |
| U9                                    | 3.3 V rail eFuse                      | **STEF4SPUR** (3.3/5 V selectable)                                                        | Same protection idea for +3V3_MAIN                                                               | The dual‑mode STEF4S lets you stock one part for 3.3 and 5 V if you prefer                            |
| F3..Fn<br>                            | Optional per‑slot PPTCs<br>           | Small PPTCs on each slot’s +5V_MAIN (and optionally 3V3)<br><br>1812L150/33-2             | Limits damage from a single bad Tile                                                             | Grouping slots per‑fuse is an acceptable cost/space trade‑off                                         |
| **RTC & Backup Power**                |                                       |                                                                                           |                                                                                                  |                                                                                                       |
| B1                                    | Coin cell holder                      | CR1220/CR20                                                                               |                                                                                                  |                                                                                                       |

---

## 13. Test and Debug Points (Informative)

To simplify Dock bring-up, fault-finding, and firmware development, the reference design should expose **labelled test points** (pads, loops, or header pins) for key power nodes and control signals. These test points are not part of the backplane contract, but are strongly recommended for any Dock implementation.

### 13.1 Ground references

Provide at least **three robust GND test locations** distributed across the board, for example:

- Near the **PD / power cluster**.
    
- Near the **Dock MCU / AON logic**.
    
- Near the **backplane connector / slot region**.
    

These may be test loops, turret posts, or generous pads sized for scope ground clips. All should tie directly into the main GND plane (L2).

### 13.2 Input power nodes

Expose test access to the main PD/PC input nodes so that plug-in behaviour and PD negotiation can be observed:

- **TP_VBUS_PD_RAW** – PD VBUS after connector protection (fuse/TVS).
    
- **TP_VBUS_PD_PROT** – PD VBUS at the PD sink input / protected node.
    
- **TP_VBUS_PD_SYS** – PD VBUS after the master switch feeding the main/AON paths.
    
- **TP_VBUS_PC_SYS** – Service USB VBUS after the master switch.
    

These test points allow the designer to verify: connector behaviour, PD contract ramp-up, master switch operation, and power-mux input conditions.

### 13.3 Rails

Each regulated rail should have at least one clearly labelled DC test point near the corresponding regulator block:

- **TP_3V3_AON** – output of AON buck.
    
- **TP_5V_MAIN** – output of 5 V main buck (preferably after the rail eFuse if used, or both before/after if convenient).
    
- **TP_3V3_MAIN** – output of 3.3 V main buck (same comment as above).
    

On large boards, it is helpful to additionally provide small labelled pads for +5V_MAIN and +3V3_MAIN near the backplane connector, so that actual rail levels at the slot edge can be confirmed without reaching into the power corner.

### 13.4 Control, reset, and status

Key control and status signals involved in soft power and sequencing should be available at small test pads or on a compact bring-up header (e.g., 2×5 0.1" header). Recommended signals include:

- **TP_MAIN_ON_REQ** – MCU’s main-rail enable request.
    
- **TP_PG_5V_MAIN**, **TP_PG_3V3_MAIN** – power-good outputs for the main rails.
    
- **TP_DOCK_LOGIC_RESET#** – reset line controlling Dock logic (CPLD/FPGA) via the AND gate.
    
- **TP_SYS_RESET#** – global reset line to Host/Bank/Tiles.
    
- **TP_PD_SENSE** – divided-down PD input voltage (if the sense divider is implemented).
    
- **TP_PC_SENSE** – PC/service VBUS presence sense node (if implemented).
    

A small bring-up header that groups these signals with a nearby GND pin is highly recommended; it allows easy connection of a logic analyzer or an external controller for automated testing.

### 13.5 Physical style and labelling

- Use pad sizes appropriate to the expected use:
    
    - Larger pads or test loops for rails and VBUS nodes (to accept mini-grabbers and hooks).
        
    - Smaller pads for logic/control signals where fine probes or headers are more practical.
        
- Place each rail test point near the corresponding **local GND reference** (e.g., the nearest GND island or via cluster) so that probing rail + GND does not require long ground leads.
    
- Clearly label test points in silkscreen (e.g., `TP_5V`, `TP_3V3_AON`, `TP_MAIN_ON`, `TP_SYSRST`) so that builders can quickly locate them without the schematic.
    

These recommendations are intentionally non-normative: implementers may add more test points as needed, but a Dock that omits them entirely will be significantly harder to debug and bring up.

---

## 14. Power Sheet External Signals (Hierarchical Interface)

For schematic organisation, the Dock power system is intended to live on its own **KiCad hierarchical sheet**. This section treats the power system as a “module” with well-defined inputs and outputs.

Directions below are given **relative to the power sheet** (i.e., “Input” means a net driven from outside into the power sheet; “Output” means a net driven from the power sheet to the rest of the Dock).

|Signal|Direction (w.r.t. power sheet)|Type|Description / Usage|
|---|---|---|---|
|**+5V_MAIN**|Output|Power|Main 5 V rail generated by the power sheet and exported to the backplane and any other Dock sheets that need 5 V. Sourced from the 5 V buck and rail protection.|
|**+3V3_MAIN**|Output|Power|Main 3.3 V rail generated by the power sheet and exported to the backplane and Dock logic (e.g., CPLD/FPGA). Sourced from the 3.3 V buck and rail protection.|
|**+3V3_AON**|Output|Power|Always-on 3.3 V rail generated by the AON buck. Feeds the Dock MCU, RTC VCC, USB PHY and any other always-on logic on other sheets.|
|**VBAT_RTC**|Output|Power|Coin-cell backed RTC supply. The coin cell and any protection components live on the power sheet; the RTC IC’s VBAT pin on the logic sheet connects to this net.|
|**GND**|Bidirectional (global)|Power|System ground reference. Implemented primarily as a solid L2 plane; exposed as a global net and via test points, not usually a single hierarchical pin, but included here for completeness.|
|**MAIN_ON_REQ**|Input|Digital control|Soft-power enable request from Dock MCU/logic. When asserted, it drives the EN pins of the 5 V and 3.3 V main bucks (directly or via simple gating), turning on +5V_MAIN and +3V3_MAIN.|
|**PWR_BTN#**|Output|Digital input (to logic)|Debounced/protected net from the front-panel momentary power button. The button and ESD/RC network may reside on the power sheet; the PWR_BTN# net is exported to the MCU/logic sheet as a user input. Active-low by convention.|
|**PG_5V_MAIN**|Output|Digital status|Power-good indication for +5V_MAIN from the 5 V buck/eFuse. Exported to the MCU/logic sheet so firmware can verify rail health and implement fault policies.|
|**PG_3V3_MAIN**|Output|Digital status|Power-good indication for +3V3_MAIN from the 3.3 V buck/eFuse. Exported similarly to PG_5V_MAIN.|
|**PD_SENSE**|Output|Analog sense|Divided-down representation of the PD input voltage (VBUS_PD_SYS) suitable for an MCU ADC pin. Allows firmware to distinguish between 5 V vs 9/12/15/20 V contracts or detect loss of PD input.|
|**PC_SENSE**|Output|Digital/analog sense|Presence/voltage sense derived from the service USB VBUS (VBUS_PC_SYS). May be a simple digital detect or a divided-down analog level; used by MCU to detect whether a PC is connected.|

Implementers may choose to expose additional signals (e.g., a combined `PWR_GOOD_MAIN` flag or individual rail fault lines) as hierarchical pins if needed. The table above is the **minimal recommended interface** between the Dock power sheet and the rest of the schematic, and should be reflected in the KiCad hierarchical pin definitions for that sheet.