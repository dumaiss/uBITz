µBITz Dock – Address Decoder and IRQ Router
===========================================

This directory contains the Dock‑side address decoder, its supporting submodules,
and two related interrupt-routing blocks:

- `addr_decoder.v` – top‑level address decoder / bus arbiter.
- `addr_decoder_cfg.v` – configuration storage for decode windows.
- `addr_decoder_match.v` – combinational address/window matcher and slot picker.
- `addr_decoder_fsm.v` – /READY handshake and chip‑select (`cs_n`) generator.
- `addr_decoder_datapath.v` – data‑bus transceiver and 0xFF‑filler control.
- `addr_decoder_irq.v` – legacy interrupt aggregator / Mode‑2 ack resolver.
- `irq_router.v` – newer, configurable interrupt router with Mode‑2 support.

Testbenches (e.g. `addr_decoder_tb.v`, `irq_router_tb.v`, `addr_decoder_complex_tb.v`)
exercise these modules but are not described in detail here.

Additional documentation in this directory:

- `DECODER_CONFIGURATION.md` – how the Dock MCU programs the CPLD window tables and interrupt routing (config buses, address maps, and register layout).
- `SIGNALS.md` – mapping between CPLD ports and the platform logical signal set (CPU/Dock/Device pins and their roles).
- `Test Suite.md` – structured description of all `*_tb.v` testbenches, including scenarios, expected behaviour, and pass/fail criteria.

For detailed behavioural tests and expected timing for Mode‑2 vector cycles
across `addr_decoder` and `irq_router`, see `Mode-2-Interrupt-Test.md` in this
directory. For the normative Dock‑level behaviour and how the HDL maps onto the
platform I/O and interrupt model, refer to:

- `0.0- μBITz Platform Specification.md`
- `1.0- μBITz Dock Specification.md`
- `1.1- Part 1 — Core Logical Specification.md`

---

addr_decoder – Top‑Level Address Decoder / Bus Arbiter
------------------------------------------------------

**Module:** `addr_decoder` (in `addr_decoder.v`)

**Responsibility**

- Implements a parameterizable I/O address decoder for up to `NUM_WIN` windows
  and `NUM_SLOTS` chip‑select outputs.
- Arbitrates Dock I/O cycles, generating:
  - Per‑slot active‑low chip selects (`cs_n[NUM_SLOTS-1:0]`).
  - A CPU‑visible /READY handshake (`ready_n`).
  - Control for external Host↔Tile data transceivers
    (`data_oe_n`, `data_dir`, `ff_oe_n`, `io_r_w_`).
- Integrates with the interrupt router to steer Z80 Mode‑2 vector fetches to
  the currently active interrupt slot even when the address decode would
  otherwise miss.

**Key Parameters**

- `ADDR_W` – width of the Host address bus (default 32).
- `NUM_WIN` – number of decode windows (default 16, up to 16).
- `NUM_SLOTS` – number of Dock slots / chip‑select outputs (default 5).

**Key Inputs**

- `addr[ADDR_W-1:0]` – current Host address.
- `iorq_n` – active‑low I/O cycle qualifier.
- `clk`, `rst_n` – main synchronous clock and active‑low reset.
- `r_w_` – CPU read/write: `1` = read, `0` = write.
- `dev_ready_n[NUM_SLOTS-1:0]` – per‑slot device ready (active‑low: `0` = busy).
- `irq_int_active` – from `irq_router`: a routed maskable INT is currently active.
- `irq_int_slot[SLOT_IDX_WIDTH-1:0]` – slot index owning that active INT.
- `irq_vec_cycle` – Host has tagged the current I/O cycle as a Mode‑2 vector read.
- `cfg_clk`, `cfg_we`, `cfg_addr[7:0]`, `cfg_wdata[7:0]` – configuration bus
  used to program the address windows via `addr_decoder_cfg`.

**Key Outputs**

- `ready_n` – active‑low /READY back to the Host.
- `io_r_w_` – qualified read/write signal exported to Tiles during I/O cycles.
- `data_oe_n` – active‑low enable for Host↔Tile data transceivers.
- `data_dir` – transceiver direction: `1` = Tiles→Host (read), `0` = Host→Tiles.
- `ff_oe_n` – active‑low enable for a constant `0xFF` driver on the Host data bus
  during unmapped reads.
- `win_valid` – latched indication that this cycle hit a configured window
  (after any Mode‑2 override).
- `win_index[3:0]` – index of the matched window.
- `sel_slot[2:0]` – selected slot for this cycle (after Mode‑2 override).
- `cs_n[NUM_SLOTS-1:0]` – active‑low chip‑selects for each Dock slot.

**Internal Structure and Dataflow**

1. `addr_decoder_cfg` holds per‑window configuration tables as flattened buses:
   `base_flat`, `mask_flat`, `slot_flat`, `op_flat`.
2. `addr_decoder_match` uses those tables to:
   - Determine if the current `(addr, r_w_, iorq_n)` hits any window.
   - Output:
     - `is_read_sig`, `is_write_sig` – decoded direction.
     - `win_valid_sig`, `win_index_sig` – window hit and index.
     - `sel_slot_sig` – slot selection derived from the matching window.
3. Mode‑2 override logic:
   - When `irq_vec_cycle == 1` and `irq_int_active == 1`,
     `sel_slot_mux` is forced to `irq_int_slot`, and `win_valid_mux` is forced
     to `1` (if the slot index is in range).
   - This guarantees that the Mode‑2 vector fetch is steered to the interrupting
     slot even if the address does not match any window.
4. `addr_decoder_fsm` consumes `win_valid_mux`, `sel_slot_mux`, and `dev_ready_n`
   to:
   - Assert a single internal `cs` bit for the active slot.
   - Generate `ready_n_sig` implementing the /READY handshake protocol.
5. `addr_decoder_datapath` uses `is_read_sig`, `is_write_sig`, `win_valid_mux`
   and `iorq_n` to:
   - Decide when to enable data transceivers (`data_oe_n`).
   - Select direction (`data_dir`).
   - Enable the 0xFF filler driver on unmapped reads (`ff_oe_n`).
   - Produce a qualified `io_r_w_` for Tiles.
6. Final mapping:
   - `cs_n` is the active‑low inversion of `cs`.
   - `ready_n`, `win_valid`, `win_index`, and `sel_slot` are latched from the
     internal muxed signals.

The `addr_decoder` itself never carries the data bus; it only produces control
signals for other Dock‑side logic and transceivers.

---

addr_decoder_cfg – Configuration Storage
----------------------------------------

**Module:** `addr_decoder_cfg` (in `addr_decoder_cfg.v`)

**Responsibility**

- Stores the per‑window configuration:
  - `BASE` address.
  - `MASK` bits.
  - `SLOT` assignment.
  - `OP` gating byte for read/write qualification.
- Exposes flattened views (`base_flat`, `mask_flat`, `slot_flat`, `op_flat`) that
  are easy for downstream combinational logic to consume.

**Key Parameters**

- `ADDR_W` – width of address fields.
- `NUM_WIN` – number of decode windows.

**Key Inputs**

- `cfg_clk` – configuration clock.
- `cfg_we` – write enable (byte‑wide).
- `cfg_addr[7:0]` – configuration byte address.
- `cfg_wdata[7:0]` – configuration data byte.

**Key Outputs**

- `base_flat[NUM_WIN*ADDR_W-1:0]` – concatenated `BASE` registers.
- `mask_flat[NUM_WIN*ADDR_W-1:0]` – concatenated `MASK` registers.
- `slot_flat[NUM_WIN*3-1:0]` – concatenated `SLOT` (3‑bit) selects.
- `op_flat[NUM_WIN*8-1:0]` – concatenated `OP` fields.

**Configuration Layout**

- `CFG_BYTES = ceil(ADDR_W / 8)` – bytes per `BASE`/`MASK` value.
- Byte offsets:
  - `BASE` bytes  at `BASE_OFF + w*CFG_BYTES + byte`.
  - `MASK` bytes  at `MASK_OFF + w*CFG_BYTES + byte`.
  - `SLOT` (3 bits) at `SLOT_OFF + w` (taken from `cfg_wdata[2:0]`).
  - `OP` (8 bits) at `OP_OFF + w`.
- Initial defaults:
  - `base_flat` and `mask_flat` cleared (windows disabled).
  - `slot_flat` set to slot `0`.
  - `op_flat` set to `0xFF` (accept any read/write).

The module only supports writes; there is no readback path on the config bus.

---

addr_decoder_match – Address Window Matching
--------------------------------------------

**Module:** `addr_decoder_match` (in `addr_decoder_match.v`)

**Responsibility**

- Decodes whether the current I/O cycle hits any configured window and selects
  which window/slot should respond.

**Key Inputs**

- `addr[ADDR_W-1:0]` – Host address.
- `iorq_n` – active‑low I/O qualifier.
- `r_w_` – CPU direction (`1` = read, `0` = write).
- `base_flat`, `mask_flat`, `slot_flat`, `op_flat` – flattened tables from
  `addr_decoder_cfg`.

**Key Outputs**

- `is_read` – `1` when this cycle is a read.
- `is_write` – `1` when this cycle is a write.
- `win_valid` – `1` if any window is active for this cycle.
- `win_index[WIN_INDEX_W-1:0]` – index of the selected window.
- `sel_slot[2:0]` – slot index associated with the selected window.

**Match Logic**

- For each window `w`:
  - Unpack `base[w]`, `mask[w]`, `slot[w]`, `op[w]`.
  - Compute `masked_equal = ~(addr ^ base[w])`.
  - Compute `bit_match = (~mask[w]) | masked_equal`.
    - Mask bits force “don’t care” where `mask[w]` is `1`.
  - `raw_hit[w] = &bit_match` – all bits compatible with `BASE`/`MASK`.
  - `op_ok[w]` – direction gating:
    - `0xFF` – match any read or write.
    - `0x01` – read‑only entries (requires `is_read`).
    - `0x00` – write‑only entries (requires `is_write`).
  - `hit[w] = raw_hit[w] & op_ok[w]`.
  - `win_active[w] = hit[w] & ~iorq_n` – qualified by active I/O cycle.
- Priority encoder:
  - Scans `win_active` from lowest to highest index.
  - First asserted window wins; sets `win_valid` and `win_index`.
- Slot mapping:
  - When `win_valid = 1`, `sel_slot` is taken from `slot[win_index]`.

All logic here is purely combinational.

---

addr_decoder_fsm – /READY and Chip‑Select FSM
---------------------------------------------

**Module:** `addr_decoder_fsm` (in `addr_decoder_fsm.v`)

**Responsibility**

- Synchronizes per‑slot `dev_ready_n` signals into the main clock domain.
- Implements the /READY handshake and per‑slot chip‑select (`cs`) generation.

**Key Inputs**

- `clk`, `rst_n` – synchronous clock and active‑low reset.
- `iorq_n` – active‑low I/O qualifier.
- `win_valid` – window hit indication from the decoder (after Mode‑2 override).
- `sel_slot[2:0]` – selected slot.
- `dev_ready_n[NUM_SLOTS-1:0]` – per‑slot ready signals (active‑low).

**Key Outputs**

- `cs[NUM_SLOTS-1:0]` – internal active‑high chip‑selects.
- `ready_n` – active‑low /READY to the Host.

**Behavior**

- Two‑stage synchronizer brings `dev_ready_n` into the `clk` domain.
- FSM with two states:
  - `S_IDLE` – waits for `!iorq_n && win_valid`:
    - Latches `sel_slot` into `active_slot`.
    - Asserts `cs` for `active_slot`.
    - Drives `ready_n` low to indicate the cycle is in progress.
  - `S_ACTIVE` – holds `cs[active_slot]` while `!iorq_n`:
    - `ready_n` reflects the synchronized device ready for `active_slot`
      (low while busy, high when ready).
    - When `iorq_n` goes high again, deasserts `cs` and returns to `S_IDLE`.

All slot‑to‑`cs` mapping is done via a small helper function so that only one
chip‑select bit is asserted at a time.

---

addr_decoder_datapath – Data Bus Control
----------------------------------------

**Module:** `addr_decoder_datapath` (in `addr_decoder_datapath.v`)

**Responsibility**

- Pure combinational datapath that controls:
  - The Host↔Tile data transceivers (`data_oe_n`, `data_dir`).
  - The 0xFF filler driver for unmapped reads (`ff_oe_n`).
  - A qualified I/O read/write signal for Tiles (`io_r_w_`).

**Key Inputs**

- `iorq_n` – I/O cycle qualifier.
- `is_read` – decoder‑derived read flag.
- `is_write` – decoder‑derived write flag.
- `win_valid` – mapped vs. unmapped window indication.

**Key Outputs**

- `data_oe_n` – active‑low transceiver enable, asserted only for mapped cycles.
- `data_dir` – direction: `1` for Tile→Host, `0` for Host→Tile.
- `ff_oe_n` – active‑low enable for the 0xFF filler driver on unmapped reads.
- `io_r_w_` – read/write signal exported to Tiles:
  - During I/O cycles, passes through the CPU’s read intent (`is_read`).
  - Outside I/O cycles, defaults to “read” (`1`) for safety.

**Behavior**

- Derives helper signals:
  - `io_cycle = ~iorq_n`.
  - `mapped_io = io_cycle & win_valid`.
  - `unmapped_io = io_cycle & ~win_valid`.
  - `mapped_read = mapped_io & is_read`.
  - `mapped_write = mapped_io & is_write`.
  - `unmapped_read = unmapped_io & is_read`.
- Drives:
  - `data_oe_n = ~(mapped_read | mapped_write)` – only mapped cycles see an
    enabled data path.
  - `data_dir = is_read` – direction is based solely on CPU intent.
  - `ff_oe_n = ~unmapped_read` – enable 0xFF filler only for unmapped reads.
  - `io_r_w_ = iorq_n ? 1'b1 : is_read`.

---

irq_router – Configurable Interrupt Router
------------------------------------------

**Module:** `irq_router` (in `irq_router.v`)

**Responsibility**

- Provides a more flexible, MCU‑configurable interrupt router for Dock tiles.
- Routes per‑slot maskable INT channels and NMIs to a limited set of CPU
  interrupt pins.
- Tracks exactly one active interrupt source at a time, prioritizing NMIs over
  maskable INTs and lower slot/channel indices.
- Exports metadata about the currently active maskable interrupt to the
  address decoder to support Z80 Mode‑2 vector steering.

**Key Parameters**

- `NUM_SLOTS` – number of tiles/slots.
- `NUM_CPU_INT` – number of CPU INT outputs.
- `NUM_CPU_NMI` – number of CPU NMI outputs.
- `NUM_TILE_INT_CH` – maskable INT channels per slot (typically 2).
- `CFG_ADDR_WIDTH` – width of the config address bus.

**Key Inputs**

- `clk`, `rst_n` – main clock and synchronous reset.
- `cfg_clk` – configuration clock.
- `tile_int_req[NUM_SLOTS*NUM_TILE_INT_CH-1:0]` – per‑slot maskable INT
  requests (active‑high).
- `tile_nmi_req[NUM_SLOTS-1:0]` – per‑slot NMI requests (active‑high).
- `irq_ack` – one‑clock pulse indicating the CPU performed an IRQ acknowledge
  cycle (decoded elsewhere).
- `cfg_wr_en`, `cfg_rd_en` – config bus strobes.
- `cfg_addr[CFG_ADDR_WIDTH-1:0]` – config address.
- `cfg_wdata[31:0]` – data written into route tables.

**Key Outputs**

- `cpu_int[NUM_CPU_INT-1:0]` – active‑high CPU INT drives.
- `cpu_nmi[NUM_CPU_NMI-1:0]` – active‑high CPU NMI drives.
- `slot_ack[NUM_SLOTS-1:0]` – per‑slot, one‑clock acknowledge pulse for
  maskable interrupts.
- `irq_int_active` – asserted when there is a routed, active maskable INT.
- `irq_int_slot[SLOT_IDX_WIDTH-1:0]` – slot index of the active maskable INT.
- `cfg_rdata[31:0]` – readback of route table entries (writes only use `wdata[7:0]`).

**Configuration Model**

- Internally maintains:
  - `int_route_slot_ch[slot][ch]` – 8‑bit entries for maskable INT routing:
    - Bit 7 – enable.
    - Bits 3:0 – CPU INT index for this source.
  - `nmi_route_slot[slot]` – 8‑bit entries for NMI routing:
    - Bit 7 – enable.
    - Bits 3:0 – CPU NMI index for this slot.
- Address map (byte‑granular, using `cfg_addr`):
  - `0 .. NUM_SLOTS*NUM_TILE_INT_CH-1`:
    - Maskable INT routing for each `(slot, channel)` pair.
  - `NUM_SLOTS*NUM_TILE_INT_CH .. NUM_SLOTS*NUM_TILE_INT_CH + NUM_SLOTS-1`:
    - NMI routing for each slot.
- Writes:
  - On `cfg_wr_en`, updates the selected entry with `cfg_wdata[7:0]`.
- Reads:
  - On reset, route entries default to zero (disabled).
  - Readback behavior is simple and driven into `cfg_rdata` on `cfg_clk`.

**Pending and Active Tracking**

- Combines current tile requests and route enables into:
  - `pending_int` – flattened mask of routed, asserted maskable INT sources.
  - `pending_nmi` – mask of routed, asserted NMIs per slot.
- `active_*` registers capture the currently serviced interrupt:
  - `active_valid` – any interrupt currently active.
  - `active_is_nmi` – NMI vs. maskable INT.
  - `active_slot` – owning slot index.
  - `active_ch` – channel index for maskable INTs.
  - `active_cpu_idx` – stored route entry (`{enable, idx[3:0]}`).
- Behavior:
  - While `active_valid` is true, the router watches the underlying request:
    - If the source deasserts, `active_valid` is cleared.
  - When the router is idle (`!active_valid_next`), selection occurs:
    - First, scans NMIs (by slot index). First matching slot wins.
    - If no NMIs pending, scans maskable INTs by `(slot, channel)` order.
    - The first routed, asserted source becomes the new active interrupt.

**CPU‑Facing Outputs**

- `irq_int_active`:
  - True when `active_valid`, `!active_is_nmi`, the route entry is enabled
    (`active_cpu_idx[7] == 1`), and `active_slot` is in range.
  - In this case, `irq_int_slot` is set to `active_slot` (truncated to
    `SLOT_IDX_WIDTH` bits).
- `cpu_int` / `cpu_nmi`:
  - Cleared by default.
  - If a routed, enabled maskable INT is active:
    - Asserts `cpu_int[active_cpu_idx[3:0]]` when the index is in range.
  - If a routed, enabled NMI is active:
    - Asserts `cpu_nmi[active_cpu_idx[3:0]]` when the index is in range.
- `slot_ack`:
  - Cleared by default.
  - When `irq_ack` is seen while a maskable INT is active (`!active_is_nmi`):
    - Pulses `slot_ack[active_slot]` for one clock, if `active_slot` is in range.
  - This pulse can be used by the owning Tile to perform local “ack” behavior.

---

Overall Architecture: Address Decoder + IRQ Router
--------------------------------------------------

At a high level, the Dock responds to Host I/O cycles as follows:

1. The Host initiates an I/O cycle (`iorq_n == 0`, with `addr` and `r_w_` set).
2. `addr_decoder_cfg` provides the configured `BASE`/`MASK`/`SLOT`/`OP` tables.
3. `addr_decoder_match` evaluates the current cycle against all windows:
   - If a window matches and passes OP gating, it asserts `win_valid_sig`,
     sets `win_index_sig` and `sel_slot_sig`.
4. In normal cycles:
   - `addr_decoder` uses `sel_slot_sig` and `win_valid_sig`.
   - `addr_decoder_fsm` asserts the corresponding `cs_n[slot]` and drives
     `ready_n` based on `dev_ready_n[slot]`.
   - `addr_decoder_datapath` controls the data transceivers and 0xFF filler
     depending on whether the cycle is mapped and whether it is a read or write.
5. In Mode‑2 vector fetch cycles:
   - Elsewhere, `irq_router` monitors all tile INT/NMI requests and tracks one
     active source at a time.
   - When the active source is a routed maskable INT:
     - `irq_int_active` is asserted.
     - `irq_int_slot` provides the slot index of the interrupting tile.
   - The Host asserts `irq_vec_cycle` for the specific I/O read used as a
     Mode‑2 vector fetch.
   - During such a cycle, `addr_decoder` overrides the normal decode:
     - Forces `sel_slot` to `irq_int_slot`.
     - Forces `win_valid` high (if the slot index is valid).
   - The FSM and datapath then behave as if a normal mapped I/O read occurred
     for that slot, ensuring that vector fetches are steered to the interrupting
     tile regardless of the address map.

In effect:

- `irq_router` decides *which slot currently owns the CPU’s attention* and
  provides metadata about that slot.
- `addr_decoder` decides *how Host I/O cycles map to slots and when to let data
  flow*.
- The Mode‑2 override path stitches them together so that the CPU’s interrupt
  acknowledge and vector fetch cycles interact correctly with the Dock’s
  multi‑slot architecture.

The Mode‑2 interaction, including concrete scenarios and pass/fail criteria for
slot selection and chip‑select behaviour, is specified and exercised in
`Mode-2-Interrupt-Test.md`.

### Informative timing diagrams

The following ASCII timing diagrams illustrate typical sequences. Exact CPU
phasing and wait‑state insertion are defined by the Platform and Dock specs;
these diagrams capture how the Dock logic responds.

#### I/O READ (mapped window, device already ready)

```
clk         : ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐
             : ‾ └─‾ └─‾ └─‾ └─‾
iorq_n      : ‾‾‾‾\__________/‾‾‾‾‾‾
addr        :   A0==========A0
r_w_        :   ─────────1────────      (read)
win_valid   :   0   1────────1   0      (window hit while /IORQ low)
cs_n[slot]  :   1   0────────0   1      (active‑low CS for selected slot)
ready_n     :   1   0───1───────1       (/READY low for at least one cycle)
data_oe_n   :   1   0────────0   1      (transceivers enabled for mapped I/O)
data_dir    :   1   1────────1   1      (Tiles→Host for reads)
ff_oe_n     :   1   1────────1   1      (0xFF filler disabled for mapped hit)
```

- On `iorq_n` low with a configured window hit, `addr_decoder_match` asserts
  `win_valid` and selects `sel_slot`.
- On the next `clk` edge, `addr_decoder_fsm` latches `sel_slot`, asserts the
  corresponding `cs` (so `cs_n` goes low) and pulls `ready_n` low.
- Because `dev_ready_n[slot]` is already deasserted (device ready), the FSM
  releases `ready_n` high on the following cycle, ending the wait.
- `addr_decoder_datapath` enables the data transceivers (`data_oe_n == 0`) and
  drives `data_dir == 1` for the duration of the mapped read.

#### I/O WRITE (mapped window, device with wait)

```
clk         : ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐
iorq_n      : ‾‾‾‾\________________/‾‾‾‾
addr        :   A1====================A1
r_w_        :   ─────────0────────────────  (write)
win_valid   :   0   1──────────────1   0
dev_ready_n :   1   1────0────0────1       (0 = busy, 1 = ready)
cs_n[slot]  :   1   0──────────────0   1
ready_n     :   1   0────0────1────1       (/READY tracks dev_ready_n in ACTIVE)
data_oe_n   :   1   0──────────────0   1   (transceivers enabled)
data_dir    :   1   0──────────────0   1   (Host→Tiles for writes)
ff_oe_n     :   1   1──────────────1   1   (filler never used for mapped hit)
```

- As with reads, `win_valid` and `sel_slot` are asserted while `iorq_n` is low.
- `addr_decoder_fsm` asserts `cs` and initially drives `ready_n` low when the
  write is accepted.
- While in the ACTIVE state, `ready_n` follows the synchronized
  `dev_ready_n[slot]`:
  - `dev_ready_n == 0` → `ready_n` held low (device busy, cycle extended).
  - `dev_ready_n == 1` → `ready_n` released high (device ready, CPU may end I/O).
- `addr_decoder_datapath` enables the transceivers and sets `data_dir == 0`
  (Host→Tiles) for the duration of the mapped write.

#### IRQ ROUTE (maskable INT becoming active)

```
clk            : ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐
tile_int_req   : 0   1===================1   (slot S, channel k asserted)
pending_int    : 0   1===================1
active_valid   : 0   1===================1
active_slot    : X   S===================S
active_is_nmi  : X   0===================0   (maskable INT)
cpu_int[x]     : 0   1===================1   (if routing enabled and in range)
irq_int_active : 0   1===================1   (exported to addr_decoder)
irq_int_slot   : 0   S===================S
```

- When a routed maskable request in slot `S`/channel `k` asserts and no other
  interrupt is active, `irq_router`:
  - Marks the corresponding bit in `pending_int`.
  - Selects it as the new active source (`active_valid = 1`).
  - Records `active_slot = S`, `active_is_nmi = 0`, and the route entry.
- While active:
  - The configured `cpu_int[x]` line is driven high.
  - `irq_int_active` is asserted and `irq_int_slot` publishes the slot index
    to `addr_decoder` for Mode‑2 vector steering.

#### IRQ ACK (CPU acknowledge and per‑slot ack pulse)

```
clk            : ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐ ┌‾┐
tile_int_req   : 1===================1====0   (device holds INT until it clears cause)
active_valid   : 1===================1====0   (clears only when request deasserts)
cpu_int[x]     : 1===================1====0
irq_int_active : 1===================1====0
irq_ack        : 0       1────0               (CPU performs IRQ ack cycle)
slot_ack[S]    : 0       1────0               (one‑clock pulse to owning slot)
slot_ack[≠S]   : 0       0────0
```

- A rising `irq_ack` pulse while a maskable INT is active causes `irq_router`
  to:
  - Generate a one‑clock `slot_ack` pulse for the owning slot `S`
    (all other `slot_ack` bits remain low).
  - Leave `active_valid` and `irq_int_active` unchanged; ack does **not** clear
    the interrupt.
- The interrupt is considered cleared only when the device deasserts its
  `tile_int_req` line (`INT_CH[k]`), at which point `active_valid` falls and
  the corresponding `cpu_int[x]` and `irq_int_active` outputs return to 0.
