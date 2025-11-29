uBITz Dock - Decoder and IRQ Router Configuration
==================================================

This document describes how the Dock microcontroller (MCU) configures the CPLD
address decoder (`addr_decoder`) and interrupt router (`irq_router`) over the
shared 8-bit configuration bus exposed in `top.v`.

The MCU fills the tables described here after reading the platform descriptors
(CPU descriptor `WindowMap[]`/`IntRouting[]` and Tile descriptors) and mapping
logical functions onto physical slots/channels.

---

1. Configuration Bus - Overview
-------------------------------

A single 8-bit, write-only configuration bus is shared by both blocks.

- Signals: `cfg_clk`, `cfg_we`, `cfg_addr[7:0]`, `cfg_wdata[7:0]`.
- Address split:
  - Addresses **below** `IRQ_CFG_BASE` program the decoder window tables.
  - Addresses **at/above** `IRQ_CFG_BASE` program the IRQ routing tables with
    `irq_idx = cfg_addr - IRQ_CFG_BASE`.
- Default `IRQ_CFG_BASE` in `top.v` is `0xC0` (parameterizable). With the
  default decoder map this leaves a gap between the decoder OP region and the
  IRQ range, but the gap is not required by the logic.
- Direction: write-only for both blocks. The router zero-extends `cfg_wdata`
  to 32 bits internally; no readback is exposed on this shared bus.

All writes are synchronous to `cfg_clk` and latch on the rising edge when
`cfg_we` is asserted.

---

2. Decoder Configuration (`addr_decoder_cfg`)
---------------------------------------------

Valid when `cfg_addr < IRQ_CFG_BASE`.

### 2.1 Internal tables

`addr_decoder_cfg` owns four flattened arrays:
- `base_flat[NUM_WIN*ADDR_W-1:0]`  (BASE for each window)
- `mask_flat[NUM_WIN*ADDR_W-1:0]`  (MASK for each window)
- `slot_flat[NUM_WIN*3-1:0]`       (slot index per window)
- `op_flat[NUM_WIN*8-1:0]`         (OP gating per window)

Reset defaults: BASE/MASK cleared (disabled), SLOT=0, OP=0xFF (accept any
read/write, but window is effectively off because BASE/MASK are zero).

### 2.2 Address map and layout

Let `CFG_BYTES = (ADDR_W + 7) / 8`.
- `BASE_OFF = 0`
- `MASK_OFF = BASE_OFF + NUM_WIN * CFG_BYTES`
- `SLOT_OFF = MASK_OFF + NUM_WIN * CFG_BYTES`
- `OP_OFF   = SLOT_OFF + NUM_WIN`

For window `w` (0-based):
- BASE byte `b`:    `cfg_addr = BASE_OFF + w*CFG_BYTES + b` (0 <= b < CFG_BYTES)
- MASK byte `b`:    `cfg_addr = MASK_OFF + w*CFG_BYTES + b`
- SLOT register:    `cfg_addr = SLOT_OFF + w`      (uses `cfg_wdata[2:0]`)
- OP register:      `cfg_addr = OP_OFF + w`        (uses `cfg_wdata[7:0]`)

Default build (`ADDR_W = 32`, `NUM_WIN = 16`, `CFG_BYTES = 4`):
- BASE region: `0x00-0x3F`
- MASK region: `0x40-0x7F`
- SLOT region: `0x80-0x8F`
- OP region:   `0x90-0x9F`
(Addresses >= `IRQ_CFG_BASE` are ignored by the decoder.)

### 2.3 OP field semantics

OP is interpreted by `addr_decoder_match` as direction gating:
- `8'hFF` : accept reads and writes.
- `8'h01` : read-only window.
- `8'h00` : write-only window.

---

3. IRQ Routing Configuration (`irq_router`)
-------------------------------------------

Valid when `cfg_addr >= IRQ_CFG_BASE`; the router sees `idx = cfg_addr -
IRQ_CFG_BASE`.

### 3.1 Internal routing tables

8-bit entries:
- Maskable INT routing: `int_route_slot_ch[slot][ch]` (slot 0..NUM_SLOTS-1,
  channel 0..NUM_TILE_INT_CH-1).
- NMI routing: `nmi_route_slot[slot]` (one per slot).

Entry format:
- Bit 7: enable (1=routed, 0=ignored).
- Bits 3:0: CPU destination index (INT index for maskable, NMI index for NMI).
- Bits 6:4: reserved/ignored.

Reset: all entries `8'h00` (disabled).

### 3.2 Address map

Let `NUM_MASKABLE = NUM_SLOTS * NUM_TILE_INT_CH`.
- Maskable INT entries: `idx = 0 .. NUM_MASKABLE-1`.
  - `slot_sel = idx / NUM_TILE_INT_CH`
  - `ch_sel   = idx % NUM_TILE_INT_CH`
- NMI entries: `idx = NUM_MASKABLE .. NUM_MASKABLE + NUM_SLOTS - 1`.
  - `slot_sel = idx - NUM_MASKABLE`

Writes outside these ranges are ignored.

Default parameters (`NUM_SLOTS = 5`, `NUM_TILE_INT_CH = 2`, `IRQ_CFG_BASE = 0xC0`):
- Maskable entries: `idx 0..9` at bus addresses `0xC0..0xC9`
  - Slot 0 ch0 -> idx 0 (addr 0xC0)
  - Slot 0 ch1 -> idx 1 (addr 0xC1)
  - Slot 1 ch0 -> idx 2 (addr 0xC2)
  - Slot 1 ch1 -> idx 3 (addr 0xC3)
  - Slot 2 ch0 -> idx 4 (addr 0xC4)
  - Slot 2 ch1 -> idx 5 (addr 0xC5)
  - Slot 3 ch0 -> idx 6 (addr 0xC6)
  - Slot 3 ch1 -> idx 7 (addr 0xC7)
  - Slot 4 ch0 -> idx 8 (addr 0xC8)
  - Slot 4 ch1 -> idx 9 (addr 0xC9)
- NMI entries: `idx 10..14` at bus addresses `0xCA..0xCE`
  - Slot 0 NMI -> idx 10 (addr 0xCA)
  - Slot 1 NMI -> idx 11 (addr 0xCB)
  - Slot 2 NMI -> idx 12 (addr 0xCC)
  - Slot 3 NMI -> idx 13 (addr 0xCD)
  - Slot 4 NMI -> idx 14 (addr 0xCE)

### 3.3 MCU programming notes

- Write `8'h00` to disable a source.
- Write `{1'b1, 3'b000, cpu_idx[3:0]}` to route a source to CPU INT/NMI index
  `cpu_idx` (must be in range: `< NUM_CPU_INT` for maskable, `< NUM_CPU_NMI`
  for NMIs).
- Only bit 7 and bits 3:0 are used; bits 6:4 are ignored.

---

4. MCU Programming Summary
--------------------------

1) Decode windows: for each enabled window, write BASE bytes, MASK bytes,
   SLOT, and OP into the decoder address ranges (< `IRQ_CFG_BASE`).
2) IRQ routes: for each (slot, channel) or slot NMI, write the 8-bit entry
   into the IRQ address range starting at `IRQ_CFG_BASE`.
3) Writes are single-byte, synchronous to `cfg_clk` with `cfg_we` asserted.

The CPLD performs no discovery; it simply reflects whatever the MCU writes
into these tables.
