# **μBITz Power Module - 2-Layer PCB Layout Guide**

---

## **Board Specifications:**

```
Layers: 2L
Copper weight: 2oz (70µm) both layers
Thickness: 1.6mm standard
Manufacturer: JLCPCB
Min trace/space: 0.127mm/0.127mm (5/5mil)
Min hole: 0.3mm
Surface finish: ENIG or HASL lead-free
```

---

## **Layer Stack:**

```
L1 (Top):    Power routing - VBUS_PD_RAW, VIN_AON, 3.3V, 5V pours
             Component side - all ICs, passives, connectors
             
L2 (Bottom): Solid GND plane + minimal critical routing if needed
             Thermal dissipation plane
```

---

## **Trace Width Requirements (2oz Copper):**

### **Power Traces:**

|Net|Current|Temp Rise|Width (Top)|Width (Bottom)|Notes|
|---|---|---|---|---|---|
|**VBUS_PD_RAW**|3A|10°C|1.5mm min|1.0mm|USB-C PD 20V input|
|**VIN_AON**|3A|10°C|1.5mm min|1.0mm|After mux, to regulators|
|**5V_MAIN**|4A|10°C|1.5mm min|1.0mm|From U6 to connector|
|**3V3_AON**|1A|10°C|1.0mm|0.8mm|From U4 to connector|
|**3V3_MAIN**|2A|10°C|1.0mm|0.8mm|From U7 to connector|
|**GND**|Return|—|Solid pour|Solid pour|Bottom plane|

**Use pours wherever possible instead of traces!**

### **Signal Traces:**

|Net|Type|Width|Notes|
|---|---|---|---|
|**I2C (SCL/SDA)**|100kHz|0.25mm|No special routing|
|**D+/D-**|UART|0.25mm|No differential pair needed|
|**PGOOD**|DC|0.25mm|Standard signal|
|**EN**|DC|0.25mm|Standard signal|
|**/ALERT**|DC|0.25mm|Standard signal|

---

## **KiCad Net Classes:**

**Setup: File → Board Setup → Design Rules → Net Classes**

```
Net Class: Power_High
├─ Nets: VBUS_PD_RAW, VIN_AON
├─ Trace width: 1.5mm (minimum)
├─ Clearance: 0.5mm
├─ Via drill: 0.4mm
└─ Via diameter: 0.8mm

Net Class: Power_Medium
├─ Nets: 5V_MAIN
├─ Trace width: 1.5mm
├─ Clearance: 0.3mm
├─ Via drill: 0.4mm
└─ Via diameter: 0.8mm

Net Class: Power_Low
├─ Nets: 3V3_AON, 3V3_MAIN
├─ Trace width: 1.0mm
├─ Clearance: 0.3mm
├─ Via drill: 0.4mm
└─ Via diameter: 0.8mm

Net Class: Signals
├─ Nets: I2C_SCL, I2C_SDA, PGOOD, EN, /ALERT, D+, D-
├─ Trace width: 0.25mm
├─ Clearance: 0.2mm
├─ Via drill: 0.3mm
└─ Via diameter: 0.6mm

Net Class: Default (GND)
├─ Trace width: 0.25mm
├─ Clearance: 0.2mm
└─ Use zones/pours
```

---

## **Component Placement Strategy:**

### **Power Flow Layout (Left to Right):**

```
[Input] ══════► [Processing] ══════► [Regulation] ══════► [Output]

USB-C     J_SW      TPS2121      LMR51450 (×3)      TMS
connector  header    mux          buck regs       connector
   │         │         │              │               │
   ▼         ▼         ▼              ▼               ▼
STUSB4500   Switch  Input     Inductors/Caps      Power
           routing  caps      Output caps         output
```

**Detailed placement:**

```
Top view (components on top layer):

┌─────────────────────────────────────────────────────┐
│                                                     │
│  [USB-C]  [STUSB    [J_SW]   [TPS2121]            │
│   PD       4500]      4pin     mux                 │
│            + caps            + caps                │
│                                                     │
│  [Service                                          │
│   USB]                                             │
│                                                     │
│                              ┌─[U4: 3V3_AON]──┐   │
│                              │  LMR51450       │   │
│                              │  + L1 + Cout    │   │
│                              │                 │   │
│                              ├─[U6: 5V_MAIN]──┤   │
│                              │  LMR51450       │   │
│                              │  + L2 + Cout    │   │
│                              │                 │   │
│                              ├─[U7: 3V3_MAIN]─┤   │
│                              │  LMR51450       │   │
│                              │  + L3 + Cout    │   │
│                              │                 │   │
│                              └─────────────────┘   │
│                                                     │
│  [BAT54TW]  [PGOOD                      [TMS-110]  │
│   diodes]    pull-up]                    2×10 conn │
│                                                     │
└─────────────────────────────────────────────────────┘

Dimensions: ~80mm × 50mm (approximate)
```

### **Placement Guidelines:**

**Critical proximity (keep tight):**

1. Input caps near TPS2121 VIN pins (<5mm)
2. Output caps near each LMR51450 VOUT pins (<3mm)
3. Inductor immediately after each LMR51450 SW pin (<5mm)
4. Feedback resistors near FB pins (if external)
5. STUSB4500 caps near VDD pins

**Thermal spacing:**

- 5mm minimum between LMR51450 regulators (airflow)
- Keep inductors away from sensitive analog circuits
- Orient regulators same direction (easier assembly)

---

## **KiCad Routing Workflow:**

### **Phase 1: Component Placement**

```
1. Import footprints from schematic
2. Arrange components following power flow (left→right)
3. Group regulators together (U4, U6, U7 in row)
4. Place connectors at board edges:
   - USB-C, Service USB: back edge
   - J_SW: side edge (for wire routing)
   - TMS: front edge (mates with backplane)
5. Run DRC to check component clearances
```

**Hotkeys:**

- `M`: Move component
- `R`: Rotate component
- `F`: Flip component to bottom (don't do this - all on top)

---

### **Phase 2: Route Critical Signals FIRST**

**Route these before adding pours:**

```
Priority order:
1. I2C (SCL/SDA) from connector to STUSB4500
2. PGOOD signals from regulators to BAT54TW to connector
3. EN from connector to STEF4SPUR (or regulator enables)
4. /ALERT from STUSB4500 to connector
5. D+/D- from Service USB to connector (keep parallel-ish)
6. Feedback resistors (if external to LMR51450)
```

**Why route signals first:**

- More constrained routing (can't easily move later)
- Power pours are flexible (work around signals)
- Easier to see conflicts before pours fill board

**Signal routing tips:**

- Keep traces <100mm where possible
- Avoid right angles (use 45° bends)
- Don't route signals under switching nodes (LMR51450 SW pins)
- Keep I2C away from inductor fields

---

### **Phase 3: Add Power Pours (Top Layer)**

**Pour priority (do in this order):**

```
1. VIN_AON (highest priority)
   - From TPS2121 output to all 3 LMR51450 VIN pins
   - 2-3mm wide where possible
   - Priority: 3

2. VBUS_PD_RAW
   - From J_SW to TPS2121 input
   - 1.5-2mm wide
   - Priority: 2

3. 5V_MAIN
   - From U6 VOUT to connector (pins 3+13)
   - 1.5mm wide
   - Priority: 1

4. 3V3_AON
   - From U4 VOUT to connector (pins 5+15)
   - 1.0mm wide
   - Priority: 1

5. 3V3_MAIN
   - From U7 VOUT to connector (pins 1+11)
   - 1.0mm wide
   - Priority: 1

6. Local GND pours (top layer)
   - Around each regulator
   - Fill gaps between power pours
   - Connect to thermal vias
   - Priority: 0
```

**KiCad pour setup:**

```
Hotkey: Ctrl+Shift+Z (Add Filled Zone)

Zone Properties for each power net:
├─ Layer: F.Cu (top copper)
├─ Net: Select power net (e.g., VIN_AON)
├─ Clearance: 0.5mm (for high voltage), 0.3mm (for low voltage)
├─ Minimum width: 0.5mm
├─ Pad connections: 
│  ├─ Thermal reliefs: For signal pads (4 spokes, 0.3mm)
│  └─ Solid: For power pads (no thermal relief)
├─ Priority: Set as listed above (higher = fills first)
├─ Corner smoothing: Chamfer or fillet (1mm)
└─ Fill type: Solid
```

**Drawing the zone:**

1. Click to start outline
2. Follow board edge or component placement
3. Double-click to close zone
4. Press `B` to refill all zones

---

### **Phase 4: Bottom GND Plane**

**Create solid GND pour on bottom:**

```
Steps:
1. Switch to B.Cu (bottom copper) layer
2. Hotkey: Ctrl+Shift+Z (Add Filled Zone)
3. Select GND net
4. Draw zone covering entire board (edge to edge)
5. Zone properties:
   ├─ Clearance: 0.3mm (to board edge)
   ├─ Minimum width: 0.5mm
   ├─ Pad connections: Solid (for all GND pads)
   ├─ Priority: 0 (fills everything)
   └─ Fill type: Solid

6. Press `B` to fill
```

**Important:**

- Keep bottom as unbroken as possible
- Only route critical signals on bottom if desperate
- Every break in GND plane increases EMI

---

### **Phase 5: Thermal & Stitching Vias**

**Add vias AFTER pours are in place:**

#### **1. Thermal Vias (Under LMR51450):**

**For each WSON-12 thermal pad:**

```
Via array: 3×3 grid (9 vias total)
Via size: 0.3mm drill, 0.6mm pad
Spacing: 1.0mm pitch
Location: Under exposed thermal pad
Connection: Top → Bottom GND

Placement:
  ○ ○ ○
  ○ ○ ○  ← 3×3 grid under IC
  ○ ○ ○
```

**KiCad procedure:**

```
1. Place component (U4/U6/U7)
2. Zoom in on thermal pad
3. Hotkey: V (add via)
4. Set via size: 0.3mm drill, 0.6mm diameter
5. Place 9 vias in 3×3 grid
6. Set net to GND for all vias
7. Repeat for each regulator
```

**Alternative: Use footprint with integrated thermal vias**

- Modify LMR51450 footprint to include vias
- Saves time during layout

#### **2. Stitching Vias (Around Power Pours):**

**Purpose:** Connect top GND to bottom GND plane

```
Placement:
- Every 5-10mm along edges of power pours
- Creates "fence" around high-current paths
- Reduces EMI, improves return paths

Via size: 0.4mm drill, 0.8mm pad
Net: GND
Spacing: 5-10mm

Example around VIN_AON pour:
  ○ ════════════════════ ○
    [VIN_AON power pour]
  ○ ════════════════════ ○
  ↑                       ↑
  GND vias               GND vias
```

**KiCad via stitching plugin:**

- Plugin: Via Stitching (install from PCM)
- Select zone → Run plugin → Auto-place vias
- Or place manually with hotkey `V`

#### **3. Power Transition Vias (If Needed):**

**If power must change layers:**

```
Use via array (3-4 vias in parallel)
Via size: 0.4-0.6mm drill, 0.8-1.0mm pad
Spacing: 1-2mm apart
Net: Power net being transitioned

Example for 3A current:
  Via 1 ○
  Via 2 ○  ← Parallel vias
  Via 3 ○

Capacity: 3× 1A per via = 3A total
```

---

## **Design Rule Check (DRC):**

**Run DRC after each phase:**

```
Menu: Inspect → Design Rules Checker

Check for:
├─ Clearance violations (traces too close)
├─ Unconnected nets (missing connections)
├─ Minimum trace width violations
├─ Annular ring violations (vias too close to pad edges)
├─ Copper to edge clearance (<0.3mm)
└─ Silkscreen on pads

Fix all errors before proceeding to next phase
```

---

## **Thermal Management:**

### **Heat Dissipation Strategy:**

**2-layer board with 2oz copper:**

```
LMR51450 power dissipation (each):
  Efficiency: ~92%
  Loss: 8% of output power
  
U6 (5V @ 4A):
  Pout = 20W
  Ploss = 1.6W ← Most heat

Heat path:
  LMR51450 junction
       ↓
  Thermal pad (bottom of IC)
       ↓
  9× thermal vias (3×3 array)
       ↓
  Bottom GND plane (large copper area)
       ↓
  Heat spreads across board
```

**Thermal via effectiveness:**

```
Each 0.3mm via: ~0.15 W/°C thermal conductance
9 vias total: ~1.35 W/°C
1.6W dissipation / 1.35 W/°C = ~1.2°C rise (excellent!)

With 2oz copper bottom plane acting as heatsink
Actual junction temperature rise: <20°C above ambient
```

**Additional cooling (if needed):**

- Small heatsink on top of IC (if clearance allows)
- Airflow across regulators
- Keep inductors away (they also generate heat)

---

## **PCB Silkscreen Guidelines:**

### **Component Reference Designators:**

```
Always visible:
- U1, U2, U3... (ICs)
- L1, L2, L3... (inductors)
- C1, C2, C3... (caps)
- J1, J2... (connectors)
- SW1 (switch header)

Font: 1.0mm height, 0.15mm width
Layer: F.Silkscreen
```

### **Functional Labels:**

```
Near connectors:
- "USB-C PD 5-20V"
- "SERVICE USB 5V"
- "POWER SWITCH - J_SW"
- "TO BACKPLANE (TMS)"

Near regulators:
- "3V3 AON"
- "5V MAIN"  
- "3V3 MAIN"

Polarity markings:
- "+" and "-" near capacitors
- Pin 1 markers on ICs and connectors
- "GND" labels
```

### **Warning Text:**

```
Near J_SW:
"DO NOT PLUG/UNPLUG WHILE ON"

Near high voltage:
"CAUTION: 20V MAX"
```

---

## **Footprint Verification:**

### **Critical Footprints to Check:**

**LMR51450SDRRR (WSON-12):**

```
Package: 3×3mm WSON-12
Pad layout: Verify against datasheet
Thermal pad: 1.65 × 2.4mm (check datasheet)
Thermal vias: 3×3 array, 0.3mm drill

KiCad library: May need custom footprint
Source: TI website or SnapEDA
```

**Inductors (SRP series):**

```
SRP1038A (10×10mm): Check footprint exists
SRP7028A (7×7mm): Check footprint exists

Pad size: Match manufacturer recommendations
Clearance: Allow for inductor body height
```

**Connectors:**

```
TMS-110-01-G-D-006: Samtec library or custom
SMS-110-01-L-D: Same family
USB-C: Verify pinout matches schematic
J_SW (KK-254): Molex library
```

---

## **Common Layout Mistakes to Avoid:**

```
❌ Routing power as skinny traces (use pours!)
❌ Breaking bottom GND plane unnecessarily
❌ Forgetting thermal vias under LMR51450
❌ No stitching vias around power pours
❌ Wrong pad connections (power needs solid, not thermal relief)
❌ Switching node (SW pin) routed near sensitive signals
❌ Input/output caps too far from regulator pins
❌ D+/D- routed far apart (keep parallel-ish even for UART)
❌ No clearance for inductor height (check 3D view)
❌ Connector pin 1 not marked clearly
```

---

## **Pre-Fabrication Checklist:**

```
□ All nets connected (no airwires)
□ DRC passes with 0 errors
□ Thermal vias present under all 3 regulators (9 each)
□ Stitching vias around power pours
□ Bottom GND plane is continuous
□ Power pours are filled and visible
□ All component values in silkscreen
□ Connector pin 1 markers present
□ Board dimensions correct (~80×50mm)
□ Mounting holes added (if needed)
□ 3D view shows no component collisions
□ Gerber preview looks correct
□ Drill file includes all holes
□ Copper clearance to board edge ≥0.3mm
```

---

## **Gerber Generation:**

**KiCad: File → Plot**

```
Layers to export:
├─ F.Cu (top copper)
├─ B.Cu (bottom copper)
├─ F.Silkscreen
├─ B.Silkscreen (if used)
├─ F.Mask (solder mask)
├─ B.Mask
├─ Edge.Cuts (board outline)
└─ F.Paste (if using stencil)

Options:
├─ Plot format: Gerber
├─ Plot border and title block: OFF
├─ Plot footprint values: ON
├─ Plot footprint references: ON
├─ Exclude pads from silkscreen: ON
├─ Use Protel filename extensions: ON (for JLCPCB)
└─ Include netlist attributes: ON

Generate Drill Files:
├─ Drill file format: Excellon
├─ Drill units: Millimeters
├─ Zeros format: Decimal format
├─ Drill origin: Absolute
└─ Merge PTH and NPTH: NO
```

**Verify Gerbers:**

- Use Gerbv or KiCad's Gerber Viewer
- Check all layers align correctly
- Verify drill hits are in correct locations
- Check board outline is clean

---

## **JLCPCB Order Settings:**

```
PCB Specifications:
├─ Base Material: FR-4
├─ Layers: 2
├─ Dimensions: (auto-detected from gerbers)
├─ PCB Qty: 5 (minimum)
├─ PCB Thickness: 1.6mm
├─ PCB Color: Green (or your choice)
├─ Silkscreen: White
├─ Surface Finish: ENIG (better) or HASL lead-free
├─ Copper Weight: 2oz outer layers ← IMPORTANT!
├─ Gold Fingers: No
├─ Confirm Production file: No
└─ Remove Order Number: Yes (specify location)

Estimated cost: $35-45 for qty 5
Lead time: ~1 week
```

---

## **Assembly Considerations:**

**Soldering order (2oz copper requires more heat):**

```
1. Solder paste + hot plate method (recommended):
   - Apply paste to all SMD pads
   - Place components
   - Reflow on hot plate (~250°C peak)
   
2. Hand soldering (advanced):
   - Use high-wattage iron (60W+)
   - Higher temp needed (350-380°C)
   - 2oz copper sinks heat quickly
   - Preheat board if possible

3. Reflow oven (best):
   - Standard lead-free profile
   - Peak temp: 245-260°C
   - Most reliable for WSON packages
```

**Practice parts:**

- Order 5-10 extra LMR51450 for practice
- WSON-12 is challenging to hand-solder
- Consider ordering assembly service if not confident

---

**This should give you everything you need for the power module PCB layout in KiCad. Want me to clarify any specific step?**