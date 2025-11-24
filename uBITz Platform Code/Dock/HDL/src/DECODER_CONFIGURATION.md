µBITz Dock – Decoder and IRQ Router Configuration
==================================================

This document describes how the Dock microcontroller (MCU) configures the CPLD
address decoder (`addr_decoder`) and interrupt router (`irq_router`), with a
focus on:

- The configuration signals between MCU and CPLD.
- The internal configuration logic (tables and state).
- The byte-level register maps the MCU writes.

Where relevant, fields are tied back to the logical structures in the Core
specification (`WindowMap[]` and `IntRouting[]` in the CPU descriptor).

---

1. Configuration Buses – Overview
---------------------------------

The CPLD exposes two simple, MCU-driven configuration ports:

- **Decoder configuration bus** (into `addr_decoder_cfg`):
  - Signals: `cfg_clk`, `cfg_we`, `cfg_addr[7:0]`, `cfg_wdata[7:0]`.
  - Purpose: Program I/O window tables (BASE, MASK, SLOT, OP).
  - Direction: MCU→CPLD only (no readback).

- **IRQ routing configuration bus** (into `irq_router`):
  - Signals: `cfg_clk`, `cfg_wr_en`, `cfg_rd_en`,
    `cfg_addr[CFG_ADDR_WIDTH-1:0]`, `cfg_wdata[31:0]`, `cfg_rdata[31:0]`.
  - Purpose: Program per-slot maskable INT and NMI routing entries.
  - Direction: MCU→CPLD for writes; optional CPLD→MCU readback.

In a typical implementation, both ports are driven by the same MCU over a small
set of parallel wires (shared or separate chip‑selects as needed). The MCU is
responsible for:

- Fetching the CPU descriptor and Tile descriptors over the platform’s
  enumeration bus.
- Translating the logical `WindowMap[]` and `IntRouting[]` tables into the
  concrete per-slot/per-window entries used by the CPLD.
- Issuing the required configuration writes on `cfg_clk`.

All configuration writes are synchronous to `cfg_clk` and edge‑triggered; there
is no handshake or response beyond `cfg_rdata` in the IRQ router.

---

2. Decoder Configuration Port (`addr_decoder_cfg`)
--------------------------------------------------

### 2.1 Signals

From the MCU into `addr_decoder` / `addr_decoder_cfg`:

- `cfg_clk` – configuration clock.
- `cfg_we` – active‑high write enable.
- `cfg_addr[7:0]` – 8‑bit configuration byte address.
- `cfg_wdata[7:0]` – 8‑bit configuration data.

There is no `cfg_rdata` for this block; the MCU must track what it wrote or
observe the flattened outputs indirectly via debug.

### 2.2 Internal tables

The submodule `addr_decoder_cfg` owns four flattened arrays:

- `base_flat[NUM_WIN*ADDR_W-1:0]` – BASE address for each window.
- `mask_flat[NUM_WIN*ADDR_W-1:0]` – MASK for each window.
- `slot_flat[NUM_WIN*3-1:0]` – 3‑bit slot index per window.
- `op_flat[NUM_WIN*8-1:0]` – 8‑bit OP field per window.

These correspond conceptually to the CPU descriptor’s `WindowMap[]` entries:

- `IOWin` → BASE.
- `Mask` → MASK.
- `OpSel` → OP (with a simplified encoding).
- Slot selection is derived from the enumerated mapping of (Function, Instance)
  to a physical Dock slot and stored in `slot_flat`.

On reset/initialization (`initial` block), all windows are disabled:

- `base_flat` and `mask_flat` are cleared (match nothing).
- `slot_flat` is set to slot `0`.
- `op_flat` is set to `8'hFF` (accept any read or write, though the window is
  effectively disabled by the zeroed BASE/MASK).

### 2.3 Address map and layout

`addr_decoder_cfg` defines:

- `CFG_BYTES = (ADDR_W + 7) / 8` – number of bytes per BASE/MASK entry.
- `BASE_OFF = 0`.
- `MASK_OFF = BASE_OFF + NUM_WIN * CFG_BYTES`.
- `SLOT_OFF = MASK_OFF + NUM_WIN * CFG_BYTES`.
- `OP_OFF   = SLOT_OFF + NUM_WIN`.

All accesses are **byte addressed** via `cfg_addr`. For a given window index
`w` (`0 <= w < NUM_WIN`):

- BASE bytes:
  - `cfg_addr = BASE_OFF + w*CFG_BYTES + b`, `0 <= b < CFG_BYTES`.
  - Writes `cfg_wdata` into `base_flat[w*ADDR_W + 8*b +: 8]`.
- MASK bytes:
  - `cfg_addr = MASK_OFF + w*CFG_BYTES + b`, `0 <= b < CFG_BYTES`.
  - Writes `cfg_wdata` into `mask_flat[w*ADDR_W + 8*b +: 8]`.
- SLOT register:
  - `cfg_addr = SLOT_OFF + w`.
  - Writes `cfg_wdata[2:0]` into `slot_flat[w*3 +: 3]`.
- OP register:
  - `cfg_addr = OP_OFF + w`.
  - Writes `cfg_wdata[7:0]` into `op_flat[w*8 +: 8]`.

For the default build (`ADDR_W = 32`, `NUM_WIN = 16`):

- `CFG_BYTES = 4`.
- Address ranges:
  - BASE region: `0x00–0x3F` (16 windows × 4 bytes).
  - MASK region: `0x40–0x7F`.
  - SLOT region: `0x80–0x8F` (16 1‑byte entries).
  - OP region:   `0x90–0x9F` (16 1‑byte entries).

### 2.4 OP field semantics

The `op_flat` entries are interpreted by `addr_decoder_match` as a simple
direction gate:

- `8'hFF` – accept both reads and writes (no gating).
- `8'h01` – read‑only window:
  - Matches only when the I/O cycle is a READ.
- `8'h00` – write‑only window:
  - Matches only when the I/O cycle is a WRITE.

This is a simplified encoding relative to the spec’s `OpSel`; the MCU must
reduce any richer semantics down to this set when programming the CPLD.

### 2.5 MCU programming model

At a high level, the MCU:

1. Reads the CPU descriptor’s `WindowMap[0..15]`.
2. Decides which logical functions should be implemented by real Tiles on the
   Dock and which remain unmapped.
3. For each window `w` it wants the CPLD to recognize:
   - Computes BASE and MASK from the descriptor’s `IOWin` and `Mask`.
   - Determines the physical slot index for the function/instance and writes
     it into `slot_flat`.
   - Chooses an appropriate `OpSel` → OP mapping (`FF`, `01`, or `00`).
4. Issues the necessary `cfg_we` writes on `cfg_clk` to populate all BASE,
   MASK, SLOT, and OP bytes.

There is no requirement to fill all 16 windows; entries with BASE/MASK left at
zero remain effectively disabled.

---

3. IRQ Routing Configuration Port (`irq_router`)
-----------------------------------------------

### 3.1 Signals

From the MCU into `irq_router`:

- `cfg_clk` – configuration clock.
- `cfg_wr_en` – active‑high write enable.
- `cfg_rd_en` – active‑high read enable.
- `cfg_addr[CFG_ADDR_WIDTH-1:0]` – route entry index.
- `cfg_wdata[31:0]` – write data (only `cfg_wdata[7:0]` is stored).

From `irq_router` back to the MCU:

- `cfg_rdata[31:0]` – readback data, synchronous to `cfg_clk`.

In the current HDL revision, `cfg_rdata` is always driven to `32'h0000_0000`
and there is no decode logic on `cfg_rd_en`; reads are effectively reserved
for future extensions.

### 3.2 Internal routing tables

The IRQ router stores two families of 8‑bit route entries:

- Maskable INT routing:
  - `int_route_slot_ch[slot][ch]` – per slot (`0..NUM_SLOTS-1`) and channel
    (`0..NUM_TILE_INT_CH-1`).
- NMI routing:
  - `nmi_route_slot[slot]` – one entry per slot.

Each entry encodes:

- Bit 7 – enable:
  - `1` = routing enabled.
  - `0` = this source is ignored.
- Bits 3:0 – CPU index:
  - For maskable INTs: CPU INT vector index (`0..NUM_CPU_INT-1`).
  - For NMIs: CPU NMI vector index (`0..NUM_CPU_NMI-1`).
- Bits 6:4 – reserved, currently unused.

On reset (`rst_n` low in the config domain), all entries are cleared to `8'h00`
(disabled).

### 3.3 Address map and layout

`irq_router` uses a flat index `idx = cfg_addr` to select route entries:

- Let:
  - `NUM_IRQ_SLOTS = NUM_SLOTS`.
  - `NUM_MASKABLE = NUM_SLOTS * NUM_TILE_INT_CH`.

- For **maskable INT routing entries**:
  - `idx` in `[0 .. NUM_MASKABLE-1]`.
  - `slot_sel = idx / NUM_TILE_INT_CH`.
  - `ch_sel   = idx % NUM_TILE_INT_CH`.
  - On write: `int_route_slot_ch[slot_sel][ch_sel] <= cfg_wdata[7:0]`.

- For **NMI routing entries**:
  - `idx` in `[NUM_MASKABLE .. NUM_MASKABLE + NUM_SLOTS - 1]`.
  - `slot_sel = idx - NUM_MASKABLE`.
  - On write: `nmi_route_slot[slot_sel] <= cfg_wdata[7:0]`.

Writes outside these ranges are ignored.

For the default parameters (`NUM_SLOTS = 5`, `NUM_TILE_INT_CH = 2`):

- `NUM_MASKABLE = 5 * 2 = 10`.
- Address ranges:
  - Maskable entries: `idx = 0..9`:
    - Slot 0, ch 0 → idx 0
    - Slot 0, ch 1 → idx 1
    - Slot 1, ch 0 → idx 2
    - Slot 1, ch 1 → idx 3
    - ...
    - Slot 4, ch 1 → idx 9
  - NMI entries: `idx = 10..14`:
    - Slot 0 NMI → idx 10
    - ...
    - Slot 4 NMI → idx 14

### 3.4 Use in routing logic

The router’s core logic uses these tables to:

- Build **pending** masks (`pending_int`, `pending_nmi`) that represent routed
  sources whose request lines are currently asserted.
- Select a single **active** interrupt at a time, with NMIs preferred over
  maskable INTs and lower slot/channel indices winning ties.
- Drive the CPU‑facing outputs:
  - `cpu_int[active_cpu_idx[3:0]]` when a maskable INT is active and enabled.
  - `cpu_nmi[active_cpu_idx[3:0]]` when an NMI is active and enabled.
- Export the active maskable INT to the decoder:
  - `irq_int_active` / `irq_int_slot`.
- Generate per‑slot acknowledge pulses:
  - `slot_ack[active_slot]` when `irq_ack` is asserted for an active maskable
    interrupt.

If a route entry is disabled (`bit7 == 0`), the corresponding source is
ignored for both pending detection and output routing.

### 3.5 MCU programming model

For interrupts, the Core spec defines an `IntRouting[16]` table in the CPU
descriptor. The Dock MCU must:

1. Read `IntRouting[]` and each Tile’s descriptor to understand which logical
   `(Function, Instance, Channel)` lives in which physical slot and channel.
2. For each (slot, channel) that should generate a CPU interrupt:
   - Choose a CPU destination:
     - `DestPin 0x00–0x03` → `CPU_INT[0..3]`.
     - `DestPin 0x10–0x11` → `CPU_NMI[0..1]`.
   - Encode an 8‑bit entry:
     - Bit 7 = `1` (enable).
     - Bits 3:0 = CPU pin index (`0..3` or `0..1`).
3. For each (slot, channel) that should be disabled, write `8'h00`.
4. Issue `cfg_wr_en` writes over `cfg_clk` to fill:
   - All maskable entries at indices `0..NUM_MASKABLE-1`.
   - All NMI entries at indices `NUM_MASKABLE..NUM_MASKABLE+NUM_SLOTS-1`.

Any channels with Function=0x00 in `IntRouting[]` (disabled) are left with
`enable = 0` in the CPLD tables and never reach the CPU.

---

4. Summary
----------

- The **decoder configuration bus** programs a 4‑table window decode engine
  (`BASE`, `MASK`, `SLOT`, `OP`), directly mirroring the logical `WindowMap[]`
  from the spec.
- The **IRQ routing configuration bus** programs compact per-slot/channel
  route entries that realize the logical `IntRouting[]` table in hardware,
  giving the Dock control over which Tile interrupts reach which CPU pins.
- Both ports are simple, MCU‑driven byte/word writers clocked by `cfg_clk`;
  the CPLD does not perform enumeration itself—it simply exposes the tables
  the MCU fills in. 

