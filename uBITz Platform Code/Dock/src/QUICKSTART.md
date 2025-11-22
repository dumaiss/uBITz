# µBITz Dock – Decoder/IRQ Router Quick Start

This guide surfaces the most common wiring and programming tasks needed to get
a Dock build running, **before** diving into the full specifications.

It assumes the default reference parameters:

- `ADDR_W = 32`, `NUM_WIN = 16`, `NUM_SLOTS = 5`
- `NUM_TILE_INT_CH = 2`, `NUM_CPU_INT = 4`, `NUM_CPU_NMI = 2`

For other parameter sets, see `DECODER_CONFIGURATION.md` and the Verilog
modules themselves.

## 1. Wiring Cheat Sheet

Use `SIGNALS.md` for full details; this is the minimum wiring you typically
need in a Parallel/Minimal profile build.

**CPU ↔ CPLD**

- `/IORQ` → `addr_decoder.iorq_n` (active-low qualifier).
- `A[31:0]` → `addr_decoder.addr[31:0]`.
- `R/W_` → `addr_decoder.r_w_`.
- `/READY` ← `addr_decoder.ready_n`.
- `/RESET` → `addr_decoder.rst_n` and `irq_router.rst_n`.
- `/CPU_INT[3:0]` ← `irq_router.cpu_int[3:0]`.
- `/CPU_NMI[1:0]` ← `irq_router.cpu_nmi[1:0]`.
- `/CPU_ACK` → both:
  - `addr_decoder.irq_vec_cycle` (after level translation to active-high),
  - `irq_router.irq_ack` (after level translation to active-high).
- `D[7:0]` data bus:
  - Connected via external transceivers controlled by:
    - `addr_decoder.data_oe_n`, `addr_decoder.data_dir`, `addr_decoder.ff_oe_n`.

**Dock MCU ↔ CPLD (configuration)**

You can share a single `cfg_clk` for both blocks, or use two clocks if needed.

- Decoder config:
  - `MCU.cfg_clk`   → `addr_decoder.cfg_clk`
  - `MCU.cfg_we`    → `addr_decoder.cfg_we`
  - `MCU.cfg_addr`  → `addr_decoder.cfg_addr[7:0]`
  - `MCU.cfg_wdata` → `addr_decoder.cfg_wdata[7:0]`
- IRQ router config:
  - `MCU.cfg_clk`     → `irq_router.cfg_clk`
  - `MCU.cfg_wr_en`   → `irq_router.cfg_wr_en`
  - `MCU.cfg_rd_en`   → `irq_router.cfg_rd_en` (optional)
  - `MCU.cfg_addr`    → `irq_router.cfg_addr[CFG_ADDR_WIDTH-1:0]`
  - `MCU.cfg_wdata`   → `irq_router.cfg_wdata[31:0]`
  - `MCU.cfg_rdata`   ← `irq_router.cfg_rdata[31:0]` (optional debug/readback)

**Tiles/Devices ↔ CPLD**

- Per slot:
  - `/CS_n` per slot ← `addr_decoder.cs_n[slot]`.
  - `R/W_` toward Tile ← `addr_decoder.io_r_w_`.
  - `/READY` from Tile → `addr_decoder.dev_ready_n[slot]`.
  - `/INT_CH[1:0]` from Tile → `irq_router.tile_int_req` bits for that slot.
  - `/NMI_CH` from Tile → `irq_router.tile_nmi_req[slot]`.
  - `/INT_ACK` to Tile ← `irq_router.slot_ack[slot]`.
- Data bus pins on the Dock are shared among Tiles and controlled by the
  transceivers driven by `data_oe_n`/`data_dir`/`ff_oe_n`.

## 2. Programming I/O Windows (addr_decoder)

The MCU programs the decoder window tables via `addr_decoder.cfg_*`. Internally
the CPLD stores:

Configuration writes must be done while the host CPU is in reset or the Dock bus is idle. Live reconfiguration during active I/O cycles is not supported and may cause transient mis-decodes or mis-routed interrupts.

- BASE[w] – 32‑bit base address for window `w`.
- MASK[w] – 32‑bit mask for window `w`.
- SLOT[w] – slot index (0..`NUM_SLOTS-1`, stored in `SLOT_IDX_WIDTH` bits; 3 bits in the default build).
- OP[w]   – 8‑bit operation gate (read/write).

### 2.1 Address map (default 32‑bit, 16‑window build)

For `ADDR_W = 32`, `NUM_WIN = 16`:

- `CFG_BYTES = 4`
- Regions (all byte addressed via `cfg_addr`):
  - BASE region: `BASE_OFF = 0x00`
    - `w` in `[0..15]`, byte index `b` in `[0..3]`:
      - `cfg_addr = 0x00 + w*4 + b`
  - MASK region: `MASK_OFF = 0x40`
    - `cfg_addr = 0x40 + w*4 + b`
  - SLOT region: `SLOT_OFF = 0x80`
    - `cfg_addr = 0x80 + w`
  - OP region:   `OP_OFF = 0x90`
    - `cfg_addr = 0x90 + w`

The concrete offsets (`0x00`, `0x40`, `0x80`, `0x90`) are for the default build. For other parameter sets, recompute them from the formulas in `DECODER_CONFIGURATION.md`.

Values are written little‑endian: `cfg_wdata` at byte index `b` carries the
`8*b`..`8*b+7` bits of the 32‑bit word.

### 2.2 OP encodings

The OP byte is interpreted as:

- `0xFF` – window matches **both** reads and writes (no gating).
- `0x01` – window matches **reads only**.
- `0x00` – window matches **writes only**.

### 2.3 Example – “Map I/O window 0 to slot 1”

**Goal:** map 256 bytes starting at `0x1000_0000` to **slot 1**, for both reads and
writes:

- `w = 0`
- `BASE[0] = 0x1000_0000`
- `MASK[0] = 0xFFFF_FF00`  (256‑byte window)
- `SLOT[0] = 1`
- `OP[0] = 0xFF` (read+write)

MCU writes (LSB-first) on the decoder config bus:

1. BASE[0] at `cfg_addr = 0x00..0x03`:

   - `cfg_addr = 0x00` → `cfg_wdata = 0x00` (bits 7:0)
   - `cfg_addr = 0x01` → `cfg_wdata = 0x00` (bits 15:8)
   - `cfg_addr = 0x02` → `cfg_wdata = 0x00` (bits 23:16)
   - `cfg_addr = 0x03` → `cfg_wdata = 0x10` (bits 31:24)

2. MASK[0] at `cfg_addr = 0x40..0x43`:

   - `cfg_addr = 0x40` → `cfg_wdata = 0x00`
   - `cfg_addr = 0x41` → `cfg_wdata = 0xFF`
   - `cfg_addr = 0x42` → `cfg_wdata = 0xFF`
   - `cfg_addr = 0x43` → `cfg_wdata = 0xFF`

3. SLOT[0] at `cfg_addr = 0x80`:

   - `cfg_addr = 0x80` → `cfg_wdata = 0x01` (SLOT = 1)

4. OP[0] at `cfg_addr = 0x90`:

   - `cfg_addr = 0x90` → `cfg_wdata = 0xFF` (read+write)

On each write, the MCU should:

- Present `cfg_addr` and `cfg_wdata`.
- Assert `cfg_we = 1` for one rising edge of `cfg_clk`.
- Deassert `cfg_we` before changing `cfg_addr`/`cfg_wdata`.

### 2.4 Example – “Make window 0 read‑only”

Reusing the configuration above, to make window 0 **read‑only**:

- Write `0x01` to `cfg_addr = 0x90` (OP[0]):

  - `cfg_addr = 0x90` → `cfg_wdata = 0x01`

Writes to addresses in that window will then fall through to other windows or
become unmapped, depending on your mask/base layout.

## 3. Programming IRQ Routing (irq_router)

The MCU programs how per-slot/per-channel interrupt lines map to CPU INT/NMI
pins via `irq_router.cfg_*`.

Configuration writes must be done while the host CPU is in reset or the Dock bus is idle. Live reconfiguration during active I/O cycles is not supported and may cause transient mis-decodes or mis-routed interrupts.

Each route entry is an 8‑bit value:

- Bit 7 – enable:
  - `1` = routing enabled.
  - `0` = source ignored.
- Bits 3:0 – CPU index:
  - For maskable INTs: index into `CPU_INT[3:0]`.
  - For NMIs: index into `CPU_NMI[1:0]`.
- Bits 6:4 – reserved (write `0`).

The entry is stored in `cfg_wdata[7:0]` at an index derived from `cfg_addr`.

### 3.1 Address map (default 5 slots, 2 channels)

Parameters:

- `NUM_SLOTS = 5`
- `NUM_TILE_INT_CH = 2`

Then:

- `NUM_MASKABLE = NUM_SLOTS * NUM_TILE_INT_CH = 10`

**Maskable INT routing entries** (slot, channel → CPU_INT[x]):

- Index `idx = cfg_addr` in `0..9`:
  - `slot = idx / 2`
  - `chan = idx % 2`  (`0` = INT_CH0, `1` = INT_CH1)
  - Entry stored in `int_route_slot_ch[slot][chan]`.

**NMI routing entries** (slot → CPU_NMI[x]):

- Index `idx = cfg_addr` in `10..14`:
  - `slot = idx - 10`
  - Entry stored in `nmi_route_slot[slot]`.

### 3.2 Example – “Route slot 2 INT0 to CPU INT[1]”

**Goal:** when **slot 2, INT_CH0** asserts, drive `CPU_INT[1]`.

- Slot index: `slot = 2`
- Channel: `chan = 0` (INT_CH0)
- CPU INT index: `cpu_idx = 1`
- Enable bit: `1`

Compute the routing table index:

- `idx = slot * NUM_TILE_INT_CH + chan = 2 * 2 + 0 = 4`
- So `cfg_addr = 4`

Compute the 8‑bit entry:

- `entry = 0x80 | (cpu_idx & 0x0F) = 0x80 | 0x01 = 0x81`

MCU writes:

- `cfg_addr = 4`, `cfg_wdata = 0x0000_0081`, assert `cfg_wr_en` for one `cfg_clk`
  rising edge, then deassert.

From then on, when `tile_int_req[int_idx(2,0)]` is high and selected as the
active maskable interrupt, `irq_router` will drive `cpu_int[1] = 1`.

### 3.3 Example – “Route slot 3 NMI to CPU NMI[0]”

**Goal:** when **slot 3 NMI_CH** asserts, drive `CPU_NMI[0]`.

- Slot index: `slot = 3`
- CPU NMI index: `cpu_idx = 0`
- Enable bit: `1`

Compute the routing table index:

- `idx = NUM_MASKABLE + slot = 10 + 3 = 13`
- So `cfg_addr = 13`

Entry value:

- `entry = 0x80 | (cpu_idx & 0x0F) = 0x80`

MCU writes:

- `cfg_addr = 13`, `cfg_wdata = 0x0000_0080`, assert `cfg_wr_en` for one
  `cfg_clk` rising edge, then deassert.

### 3.4 Disabling a route

To disable a given source (maskable or NMI), write `0x00` to its entry
(`enable = 0`); the router will ignore that slot/channel completely.

**Important:** `irq_ack` does not clear the active interrupt by itself; the router keeps the INT active until the Tile deasserts its request. The per-slot `slot_ack` pulse can be used by Tiles as their “acknowledge received” indicator.

## 4. Mode‑2 Vector Path – Minimal Checklist

To make Z80‑style Mode‑2 vector interrupts work end‑to‑end:

1. **Wire `/CPU_ACK`** from the CPU to the CPLD and level‑translate as needed:
   - Drive `irq_router.irq_ack` (active-high pulse for each acknowledge cycle).
   - Drive `addr_decoder.irq_vec_cycle` (active-high *only* for the I/O read
     that performs the vector fetch).

2. **Program IRQ routing** so that each Tile’s maskable interrupt is mapped to
   an appropriate `CPU_INT[x]`:
   - Use the steps in section 3 to populate the maskable route entries.

3. **Program I/O windows** so that:
   - Each Tile’s vector endpoint (typically offset `0x00` in its window) is
     reachable via some `(BASE, MASK)` window in `addr_decoder`.
   - Or rely on the vector override path for completely unmapped addresses, as
     demonstrated in `addr_decoder_irq_vec_tb.v` and `Mode-2-Interrupt-Test.md`.

4. **CPU firmware**:
   - Sets `IntAckMode=Mode2` in its descriptor.
   - Performs a Mode‑2 acknowledge cycle that asserts `/CPU_ACK` and then
     issues the vector read I/O cycle.

With routing entries programmed, the IRQ router will:

- Track one active maskable source at a time.
- Export `(irq_int_active, irq_int_slot)` to the decoder.

When `irq_vec_cycle=1` and `irq_int_active=1`, the decoder will:

- Override its normal window selection.
- Assert `/CS` for the interrupting slot reported in `irq_int_slot`, even if
  the address would not otherwise decode to that slot.

## 5. Where to Go Next

- `DECODER_CONFIGURATION.md` – full description of config buses, address maps,
  and how `WindowMap[]` / `IntRouting[]` from the spec map into the CPLD.
- `SIGNALS.md` – mapping between HDL ports and the logical signal set in the
  Dock/Core specs, including CPU, Dock MCU, and Tile connections.
- `Test Suite.md` and `Mode-2-Interrupt-Test.md` – practical examples of
  windows and interrupts being configured and exercised in simulation. 
