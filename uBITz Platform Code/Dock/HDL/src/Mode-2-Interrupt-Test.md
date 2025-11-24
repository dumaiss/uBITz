# Addr Decoder ⇄ IRQ Router — Mode-2 Vector Tests

This document describes integration tests that verify the interaction between:

- `irq_router.v` — the Dock-side interrupt router with per-slot/channel routing; and
- `addr_decoder.v` — the Dock address decoder / bus arbiter.

The focus is the behaviour during Mode-2 style vector reads, using the new interface:

- `irq_int_active` — asserted when a **maskable, routed** interrupt is currently active.
- `irq_int_slot` — index of the slot that owns that active interrupt.
- `irq_vec_cycle` — asserted by the bus front-end for the I/O cycle that performs the vector read.

During a vector cycle with an active interrupt, the address decoder must override its normal window-based slot selection and talk to the slot reported by the interrupt router.

---

## Testbench Overview

The integration testbench instantiates both modules with small parameters:

- `ADDR_W = 32`
- `NUM_SLOTS = 4`
- `NUM_WIN = 4`
- `NUM_TILE_INT_CH = 2`
- `NUM_CPU_INT = 4`
- `NUM_CPU_NMI = 1`

One shared clock is used for both core logic and configuration (`clk = cfg_clk`), plus an active-low reset `rst_n`.

### DUT Connections

- `addr_decoder` is instantiated with:

  - CPU-side inputs: `addr`, `iorq_n`, `r_w_`, `clk`, `rst_n`
  - Per-slot readiness: `dev_ready_n[NUM_SLOTS-1:0]`
  - Config bus: `cfg_clk`, `cfg_we`, `cfg_addr`, `cfg_wdata`
  - New IRQ interface inputs: `irq_int_active`, `irq_int_slot`, `irq_vec_cycle`
  - Outputs: `ready_n`, `io_r_w_`, `data_oe_n`, `data_dir`, `ff_oe_n`, `win_valid`, `win_index`, `sel_slot`, `cs_n`

- `irq_router` is instantiated with:

  - Clock/reset: `clk`, `rst_n`, `cfg_clk`
  - Tile-side interrupts: `tile_int_req[NUM_SLOTS*NUM_TILE_INT_CH-1:0]`, `tile_nmi_req[NUM_SLOTS-1:0]`
  - Ack input: `irq_ack` (tied low in these tests)
  - CPU outputs: `cpu_int`, `cpu_nmi` (monitored as needed)
  - Per-slot ack: `slot_ack`
  - New exports: `irq_int_active`, `irq_int_slot`
  - Config bus: `cfg_wr_en`, `cfg_rd_en`, `cfg_addr`, `cfg_wdata`, `cfg_rdata`

The testbench also defines:

- A helper to compute `int_idx(slot, ch)` for indexing `tile_int_req`.
- A helper task to configure `addr_decoder` window 0 as “any I/O → slot 1”.
- A helper task to program a single `irq_router` maskable route entry.
- A helper task that performs a single I/O read cycle and returns sampled `cs_n` and `sel_slot`.

---

## Test A — Baseline Decode, No Active Interrupt

**Goal:** Confirm that, with no active interrupt and `irq_vec_cycle = 0`, the decoder uses the normal window configuration.

### Setup

1. Configure `addr_decoder` window 0 to:

   - Match any I/O address (`BASE = 0x0000_0000`, `MASK = 0x0000_0000`).
   - Route to slot 1 (`SLOT = 1`).
   - Accept any operation (`OP = 0xFF`).

2. Ensure:

   - `tile_int_req = 0`
   - `tile_nmi_req = 0`
   - `irq_vec_cycle = 0`

### Action

- Perform a single I/O read cycle with an arbitrary address (e.g. `0x12345678`).
- Sample `cs_n` and `sel_slot`.

### Expected Result

- `cs_n` has slot 1 asserted active-low; all other slots are inactive.
- `sel_slot` equals 1.

If `cs_n` or `sel_slot` differ from this expectation, the test fails.

---

## Test B — Vector Read Overrides Decode to Active Slot

**Goal:** When a maskable interrupt from slot 2 is active and the bus front-end tags a cycle as a vector read (`irq_vec_cycle = 1`), the decoder must select slot 2 instead of the normal window slot.

### Setup

1. Keep the window 0 configuration from Test A (any I/O → slot 1).

2. Configure `irq_router` so that:

   - Slot 2, channel 0 is routed to `CPU_INT[0]` with the route entry enabled.

3. Assert a maskable interrupt from slot 2:

   - Set `tile_int_req[int_idx(2, 0)] = 1`.
   - Wait enough cycles for `irq_router` to record this as the active source.

4. Verify in the testbench:

   - `irq_int_active` is 1.
   - `irq_int_slot` equals 2.

### Action

- Perform a single I/O read cycle with `irq_vec_cycle = 1` (vector read), using any address (e.g. `0x00000000`).
- Sample `cs_n` and `sel_slot`.

### Expected Result

- `cs_n` has slot 2 asserted active-low (the active interrupt slot).
- `sel_slot` equals 2.

Even though the decode window points at slot 1, the vector cycle must override this and talk to slot 2.

If the decoder still selects slot 1 or any other slot, the test fails.

---

## Test C — Vector Read With No Active Interrupt

**Goal:** If there is no active interrupt, a “vector read” cycle (`irq_vec_cycle = 1`) must **not** override the window. The decoder should behave like a normal I/O cycle and select the configured slot (slot 1).

### Setup

1. Deassert the interrupt from slot 2:

   - Set `tile_int_req[int_idx(2, 0)] = 0`.
   - Wait enough cycles for `irq_router` to clear its active state.

2. Confirm:

   - `irq_int_active` is 0.

3. Keep the window 0 configuration as in Test A/B (any I/O → slot 1).

### Action

- Perform a single I/O read cycle with:

  - Some address (e.g. `0xDEADBEEF`).
  - `irq_vec_cycle = 1`.

- Sample `cs_n` and `sel_slot`.

### Expected Result

- `cs_n` has slot 1 asserted active-low (the normal decode slot).
- `sel_slot` equals 1.

With no active interrupt, `irq_vec_cycle` must not change the selected slot. If the override is applied when `irq_int_active = 0`, the test fails.

---

## Success Criteria

The integration testbench should:

1. Run through Tests A, B, and C in sequence.
2. For each test, compare the observed `cs_n` and `sel_slot` against the expectations above.
3. On any mismatch, print a clear error message and terminate the simulation with a failure (e.g. `$fatal`).
4. If all tests pass, print a success message and call `$finish`.

These tests collectively verify:

- Correct baseline I/O window decode.
- Proper export of the active interrupt source from `irq_router`.
- Correct override of slot selection during Mode-2 vector reads.
- No override when no active interrupt is present.
---
## Test D — Vector Read to Unmapped Address

**Goal:** When a maskable interrupt is active and the vector read targets an 
unmapped address, the decoder must still assert /CS to the interrupting slot.

### Setup

1. Reconfigure all windows to NOT match address 0x0000_0000:
   - Each window maps a distinct high address range (e.g., 0x1000_0000 + offset)
   - Use exact-match masks (0xFFFF_FFFF)

2. Configure `irq_router` so that:
   - Slot 2, channel 0 is routed to a CPU INT pin

3. Assert a maskable interrupt from slot 2:
   - Set `tile_int_req[int_idx(2, 0)] = 1`
   - Verify `irq_int_active = 1` and `irq_int_slot = 2`

### Action

- Perform an I/O read cycle with `irq_vec_cycle = 1` at address 0x0000_0000
- This address does NOT match any configured window
- Sample `cs_n` and `sel_slot`

### Expected Result

- `cs_n` has slot 2 asserted active-low (the active interrupt slot)
- `sel_slot` equals 2

The override logic must force `win_valid = 1` and route to the interrupting 
slot even when the address is unmapped. Without this behavior, the vector 
read would return 0xFF instead of the device's vector index.