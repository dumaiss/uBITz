µBITz Dock – Address Decoder and IRQ Router Test Suite
======================================================

This document summarizes the Verilog testbenches in this directory and the
behaviour they exercise. It is informational and derived directly from the
`*_tb.v` files; it does not introduce new requirements beyond the platform and
Dock specifications.

Testbenches covered:

- `addr_decoder_tb.v`
- `addr_decoder_worked_example_tb.v`
- `addr_decoder_complex_tb.v`
- `addr_decoder_irq_vec_tb.v`
- `irq_router_tb.v`

Each section below describes:

- DUT configuration (parameters, clocks, widths).
- Stimulus patterns and scenarios.
- Expected behaviour and pass/fail conditions.

---

addr_decoder_tb.v – Basic 8‑bit Decoder and Handshake Tests
-----------------------------------------------------------

**DUT and configuration**

- Module under test: `addr_decoder` with:
  - `ADDR_W = 8`
  - `NUM_WIN = 4`
  - `NUM_SLOTS = 5`
- Clocks:
  - Core clock `clk` toggles every 4 ns.
  - Config clock `cfg_clk` toggles every 5 ns.
- IRQ interface:
  - `irq_int_active = 0`, `irq_int_slot = 0`, `irq_vec_cycle = 0` for all tests
    (vector override path is not exercised here).

**Helpers and checks**

- `cfg_write(addr, data)` – byte‑wide config writer for `addr_decoder_cfg`.
- `check_cs(t_addr, t_iorq_n, exp_cs)`:
  - Sets address and `/IORQ` level.
  - After a clock, checks:
    - `io_r_w_` remains `1` (read) when qualifier is inactive.
    - Internal active‑high `cs` matches the expected chip‑select mask.
    - External active‑low `cs_n` is the bitwise complement of `cs`.
- `run_io_cycle(t_addr, t_read, exp_cs, max_wait_cycles)`:
  - Drives a full I/O cycle:
    - Asserts `/IORQ` low with given address and `r_w_`.
    - Checks entry conditions just after ACTIVE state:
      - `cs == exp_cs`, `ready_n == 0`, `io_r_w_ == expected R/W`.
      - `cs_n == ~exp_cs`.
    - Loops up to `max_wait_cycles`:
      - Ensures `cs` and `io_r_w_` stay stable.
      - Waits for `ready_n` to rise (device ready).
    - Ends the cycle by deasserting `/IORQ`, then verifies return to idle:
      - `cs == 0`, `ready_n == 1`, `io_r_w_ == 1`, `cs_n` all high.

**Window configuration**

- Four windows are programmed via the config bus:
  - `win0`: base `0x10`, mask `0xF0`, slot `1`.
  - `win1`: base `0x20`, mask `0xF0`, slot `2`.
  - `win2`: base `0x30`, mask `0xF0`, slot `3`.
  - `win3`: base `0x00`, mask `0x00` (catch‑all), slot `4`.
- `op_0` (window 0) is later set to `0x01` (read‑only) to exercise op gating.

**Scenarios**

1. **No match when /IORQ is inactive**
   - Call `check_cs(0x10, 1, 5'b00000)`.
   - Confirms that with `/IORQ` high, no chip‑select is asserted even when
     an address matches a configured window.

2. **Basic mapped reads via `run_io_cycle`**
   - `run_io_cycle(0x10, read=1, exp_cs=00010, max_wait=4)` – window 0 → slot 1.
   - `run_io_cycle(0x23, read=1, exp_cs=00100, max_wait=4)` – window 1 → slot 2.
   - `run_io_cycle(0x3F, read=1, exp_cs=01000, max_wait=4)` – window 2 → slot 3.
   - Verifies:
     - Correct base/mask decoding.
     - Single chip‑select asserted per mapped window.
     - Handshake: `ready_n` starts low and eventually returns high.

3. **Catch‑all window behaviour**
   - `run_io_cycle(0x70, read=1, exp_cs=10000, max_wait=4)`.
   - Confirms that addresses not covered by windows 0–2 route to window 3,
     which acts as a catch‑all mapping to slot 4.

4. **Window priority for overlapping ranges**
   - Reprogram window 1 to overlap window 0 (`base1 = 0x10`, `mask1 = 0xF0`).
   - `run_io_cycle(0x12, read=1, exp_cs=00010, max_wait=4)`.
   - Expects window 0 (index 0) to win over window 1, validating the
     lowest‑index priority encoder in `addr_decoder_match`.
   - Window 1 is then restored to its original range for later tests.

5. **Operation (OP) gating for read‑only mapping**
   - `op_0` is programmed as `0x01` (read‑only).
   - `run_io_cycle(0x10, read=0, exp_cs=10000, max_wait=4)`:
     - Write to window 0 falls through to the catch‑all window, asserting slot 4.
   - `run_io_cycle(0x10, read=1, exp_cs=00010, max_wait=4)`:
     - Read still selects window 0 (slot 1).

6. **Wait‑state stretching via `dev_ready_n`**
   - Slot 1 (`dev_ready_n[1]`) is forced busy (`0`) while an I/O read to
     window 1 is in progress.
   - A forked process waits two `clk` edges then sets `dev_ready_n[1]` high,
     while the main thread:
     - Calls `run_io_cycle(0x23, read=1, exp_cs=00100, max_wait=8)`.
     - Verifies `ready_n` remains low until the device reports ready, then
       eventually releases.

The test ends with `All addr_decoder tests passed.` and calls `$finish` only
after all checks succeed.

---

addr_decoder_worked_example_tb.v – Worked Behavioural Example
-------------------------------------------------------------

**DUT and configuration**

- Module under test: `addr_decoder` with:
  - `ADDR_W = 8`
  - `NUM_WIN = 4`
  - `NUM_SLOTS = 5`
- Clocks:
  - Core `clk` at 100 MHz (10 ns period).
  - Config `cfg_clk` at a different rate (period 14 ns).
- IRQ interface is held inactive (`irq_int_active = 0`, `irq_vec_cycle = 0`).

**Helpers**

- `cfg_write(a, d)` – byte‑wide config writer.
- `io_write(a)` – simple I/O write sequence.
- `io_read(a)` – simple I/O read sequence.

**Window configuration (illustrative mapping)**

- Window 0 (e.g., UART):
  - `base = 0x10`, `mask = 0xFF`, `slot = 0`, `op = 0xFF` (read/write).
- Window 1 (e.g., VDP control/status):
  - `base = 0x20`, `mask = 0xF0`, `slot = 1`, `op = 0x00` (write‑only).
- Window 2 (e.g., VDP status/readback):
  - `base = 0x30`, `mask = 0xF0`, `slot = 1`, `op = 0x01` (read‑only).
- Window 3:
  - `mask = 0xFF`, `slot = 0`, `op = 0xFF` to avoid being a broad catch‑all.

**Scenarios**

1. **Mapped UART write to window 0**
   - Address `0x10`, write cycle.
   - Checks after `/IORQ` asserted:
     - `win_valid == 1`, `win_index == 0`, `sel_slot == 0`.
     - `cs_n[0] == 0` (slot 0 selected).
     - `data_oe_n == 0`, `data_dir == 0` (Host→Tiles), `ff_oe_n == 1`.

2. **VDP status read with explicit wait‑state stretching**
   - Slot 1 is forced busy by setting `dev_ready_n[1] = 0`.
   - Read from an address in window 2 (e.g., `0x31`):
     - During the busy phase:
       - `cs_n[1] == 0` (slot 1 selected and held).
       - `ready_n == 0` (bus held waiting for device).
       - `data_oe_n == 0`, `data_dir == 1` (Tiles→Host), `ff_oe_n == 1`.
   - After `dev_ready_n[1]` returns to `1`:
     - Loops for up to 5 cycles to observe `ready_n` rising to `1`.
     - Ensures `cs_n[1]` stays asserted until `/IORQ` deasserts, then
       checks that `cs_n[1]` eventually returns high after `/IORQ` is high.

3. **Unmapped read and 0xFF filler behaviour**
   - Read from unmapped `addr = 0x77`:
     - Expects `win_valid == 0`.
     - `data_oe_n == 1` (bridge disabled).
     - `ff_oe_n == 0` (0xFF driver enabled).
     - `ready_n == 1` (no wait‑state insertion on unmapped reads).

The test ends with a message `"All addr_decoder tests completed without fatal errors"` and
then calls `$finish`.

---

addr_decoder_complex_tb.v – 32‑bit, 16‑Window System‑Style Tests
----------------------------------------------------------------

**DUT and configuration**

- Module under test: `addr_decoder` with:
  - `ADDR_W = 32`
  - `NUM_WIN = 16`
  - `NUM_SLOTS = 5`
- Clocks:
  - Core `clk` at 100 MHz (10 ns period).
  - Config `cfg_clk` at 50 MHz (20 ns period).
- All devices initially ready (`dev_ready_n = 5'b11111`).
- IRQ interface is not exercised (`irq_int_active = 0`, `irq_vec_cycle = 0`).

**Helpers**

- `cfg_write(a, d)` – byte‑wide config writer.
- `io_cycle(a, is_read, hold_cycles, busy_mask)`:
  - Asserts `/IORQ` at address `a` with chosen `r_w_`.
  - During `hold_cycles` clock cycles:
    - OR‑accumulates internal chip‑select assertions into `seen_cs`.
    - Samples `cs_n`, `ready_n`, `data_oe_n`, `data_dir`, and `ff_oe_n`.
  - Releases `/IORQ` and returns to idle.
  - `sample_cs_n` contains the effective `cs_n` bits (based on `seen_cs`).
  - `busy_mask` bits indicate which slots are busy (`1` → `dev_ready_n = 0`).

**Window configuration**

The test programs a 16‑entry table representing a more realistic system map:

- Windows 0–3: functions in slot 0 (`win_slot = 0`), with:
  - Mixed read/write, write‑only, and read‑only OP fields.
- Windows 4–7: functions in slot 1 (`win_slot = 1`).
- Windows 8–9: functions in slot 2.
- Windows 10–11: functions in slot 3.
- Windows 12–15: various Dock‑internal functions in slot 4:
  - HID, RTC, power management, debug console, etc.
- All windows use `mask = 0xFFFF_FF00` except where noted, so they match 256‑byte ranges.

**Scenarios**

1. **Test 1 – Mapped write (window 0, slot 0)**
   - `io_cycle(0x1000_0004, is_read=0, hold_cycles=3, busy_mask=0)`.
   - Expects:
     - `sample_cs_n[0] == 0` (slot 0 selected).
     - `sample_data_oe_n == 0`, `sample_data_dir == 0`, `sample_ff_oe_n == 1`.

2. **Test 2 – Write‑only window semantics (window 2)**
   - Mapped write:
     - `io_cycle(0x1000_020A, is_read=0, hold_cycles=3, busy_mask=0)`.
     - Expects `sample_cs_n[0] == 0`.
   - Unmapped read due to `op = write‑only`:
     - `io_cycle(0x1000_020A, is_read=1, hold_cycles=3, busy_mask=0)`.
     - Expects:
       - `cs_n == 5'b11111` (no chip‑select).
       - `sample_data_oe_n == 1`, `sample_ff_oe_n == 0`
         (bridge disabled, 0xFF driver enabled).

3. **Test 3 – Read‑only window semantics (window 3)**
   - Mapped read:
     - `io_cycle(0x1000_0300, is_read=1, hold_cycles=3, busy_mask=0)`.
     - Expects mapped read to slot 0:
       - `sample_cs_n[0] == 0`, `sample_data_oe_n == 0`,
         `sample_data_dir == 1`.
   - Unmapped write (due to read‑only OP):
     - `io_cycle(0x1000_0300, is_read=0, hold_cycles=3, busy_mask=0)`.
     - Expects no chip‑select and bridge disabled:
       - `cs_n == 5'b11111`, `sample_data_oe_n == 1`, `sample_ff_oe_n == 1`.

4. **Test 4 – Sound tile with wait states (slot 1)**

   - `io_cycle(0x2000_0000, is_read=0, hold_cycles=5, busy_mask=5'b00010)`:
     - Slot 1 is marked busy (`dev_ready_n[1] = 0`).
   - Expects:
     - `sample_cs_n[1] == 0` (slot 1 selected).
     - Optional note: `ready_n` should exhibit a stretch while the device is busy.

5. **Test 5 – Dock‑internal slot 4 functions**

   - HID read: `io_cycle(0xF000_0000, is_read=1, hold_cycles=3, busy_mask=0)`.
   - RTC write: `io_cycle(0xF000_0104, is_read=0, hold_cycles=3, busy_mask=0)`.
   - Power‑management window:
     - Mapped write: `io_cycle(0xF000_0200, is_read=0, ...)` → slot 4 selected.
     - Unmapped read (write‑only window): `io_cycle(0xF000_0200, is_read=1, ...)`:
       - Expects `sample_cs_n == 5'b11111` and `sample_ff_oe_n == 0`.
   - Debug console: `io_cycle(0xF000_0308, is_read=1, ...)`:
     - Expects slot 4 chip‑select.

6. **Test 6 – Completely unmapped I/O**

   - `io_cycle(0xDEAD_BEEF, is_read=1, hold_cycles=3, busy_mask=0)`.
   - Expects:
     - `cs_n == 5'b11111` (no chip‑select).
     - `sample_data_oe_n == 1`, `sample_ff_oe_n == 0`
       (bridge disabled, 0xFF driver enabled).

Test completion is indicated by
`"TEST PASSED: addr_decoder_tb_32bit completed without fatal errors."`.

---

addr_decoder_irq_vec_tb.v – Mode‑2 Vector Override Integration
--------------------------------------------------------------

**DUT and configuration**

- DUTs:
  - `addr_decoder` with:
    - `ADDR_W = 32`, `NUM_WIN = 4`, `NUM_SLOTS = 4`.
  - `irq_router` with:
    - `NUM_SLOTS = 4`, `NUM_TILE_INT_CH = 2`,
      `NUM_CPU_INT = 4`, `NUM_CPU_NMI = 1`.
- Clock:
  - Single `clk` at 100 MHz drives both logic and configuration (`cfg_clk = clk`).
- All slots initially ready (`dev_ready_n` all high).

**Helpers**

- `int_idx(slot, ch)` – helper to index `tile_int_req` for a given slot/channel.
- `cfg_write(a, d)` – byte‑wide config for `addr_decoder`.
- `program_window0_to_slot(slot_id)`:
  - Programs window 0 to match all addresses (BASE=0, MASK=0) and route to
    `slot_id` with `op = 0xFF`.
- `program_irq_route(slot, ch, enable, cpu_idx)`:
  - Writes one `irq_router` maskable routing entry at
    `cfg_addr = slot * NUM_TILE_INT_CH + ch` with `{enable, idx[3:0]}`.
- `io_read_cycle(A, vec_cycle, cs_n_sample, sel_slot_sample)`:
  - Performs an I/O read at address `A`:
    - Drives `addr`, `r_w_ = 1`, asserts `iorq_n = 0`.
    - Sets `irq_vec_cycle = vec_cycle`.
    - Waits a few clocks for FSM to assert `cs_n`.
    - Samples `cs_n` and `sel_slot`.
    - Deasserts `/IORQ` and clears `irq_vec_cycle`.

**Scenarios (matching Mode‑2‑Interrupt‑Test.md)**

1. **Scenario A – Baseline decode, no active INT**
   - Configure window 0 to map all I/O to slot 1.
   - Ensure `tile_int_req = 0`, `tile_nmi_req = 0`, `irq_vec_cycle = 0`.
   - Perform a plain I/O read:
     - `io_read_cycle(0x1234_5678, vec_cycle=0, ...)`.
   - Expects:
     - `cs_n_sample` has only slot 1 asserted low.
     - `sel_slot_sample == 1`.
   - Confirms normal window‑based decode when there is no active interrupt.

2. **Scenario B – Vector read override to active slot**
   - Program `irq_router` to route slot 2, channel 0 to `CPU_INT[0]`.
   - Assert a maskable request from slot 2:
     - `tile_int_req[int_idx(2,0)] = 1`.
   - Wait a few cycles and check:
     - `irq_int_active == 1`.
     - `irq_int_slot == 2`.
   - Perform a **vector** read:
     - `io_read_cycle(0x0000_0000, vec_cycle=1, ...)`.
   - Expects:
     - `cs_n_sample` asserts slot 2 (active‑low).
     - `sel_slot_sample == 2`.
   - Demonstrates that during vector reads, `addr_decoder` overrides the
     window slot with the interrupting slot from `irq_router`.

3. **Scenario C – Vector read with no active INT**
   - Deassert slot 2 request: `tile_int_req[int_idx(2,0)] = 0`.
   - After a few cycles, check `irq_int_active == 0`.
   - Perform a “vector” read (even though no interrupt is active):
     - `io_read_cycle(0xDEAD_BEEF, vec_cycle=1, ...)`.
   - Expects:
     - `cs_n_sample` asserts slot 1 (as per window 0 config).
     - `sel_slot_sample == 1`.
   - Confirms that `irq_vec_cycle` alone does not override slot selection
     when there is no active interrupt.

4. **Scenario D – Vector fetch asserts /CS even when address unmapped**
   - Reprogram all windows so that **none** match address `0x0000_0000`:
     - For each window `w`:
       - `BASE[w] = 0x1000_0000 + w*0x100`.
       - `MASK[w] = 0xFFFF_FFFF` (exact match).
       - `SLOT[w] = 0`, `OP[w] = 0xFF`.
   - Assert slot 2, channel 0 interrupt again:
     - `tile_int_req[int_idx(2,0)] = 1`.
     - Check `irq_int_active == 1`, `irq_int_slot == 2`.
   - Perform a vector read at address `0x0000_0000`:
     - `io_read_cycle(0x0000_0000, vec_cycle=1, ...)`.
   - Expects:
     - `cs_n_sample` asserts slot 2 (even though the address decodes nowhere).
     - `sel_slot_sample == 2`.

The test completes with `"All addr_decoder + irq_router vector override tests PASSED."`.

---

irq_router_tb.v – Directed Interrupt Routing and Pending Tests
--------------------------------------------------------------

**DUT and configuration**

- Module under test: `irq_router` with:
  - `NUM_SLOTS = 3`
  - `NUM_CPU_INT = 2`
  - `NUM_CPU_NMI = 1`
  - `NUM_TILE_INT_CH = 2`
  - Config address width `CFG_ADDR_WIDTH = 8`.
- Clock: `clk` at 100 MHz; used for both core logic and config (`cfg_clk = clk`).
- All request lines (`tile_int_req`, `tile_nmi_req`) are initially 0.

**Helpers**

- `int_idx(slot, ch)` – flatten slot/channel to bit index in `tile_int_req`.
- `cfg_write(addr, data)` / `cfg_read(addr, data)` – config read/write helpers.
- `route_int(slot, ch, enable, cpu_idx)` – writes an INT route entry at
  `cfg_addr = slot*NUM_TILE_INT_CH + ch`.
- `route_nmi(slot, enable, cpu_idx)` – writes an NMI route entry at
  `cfg_addr = NUM_SLOTS*NUM_TILE_INT_CH + slot`.
- `pulse_irq_ack()` – generates a single‑cycle `irq_ack` pulse.

**Tests**

0. **Reset defaults (Test 0)**
   - After reset, checks:
     - `cpu_int == 0`, `cpu_nmi == 0`, `slot_ack == 0`.
     - `cfg_read(0)` returns `0x00`.

1. **Basic INT route and deassert (Test 1)**
   - Route slot 0, ch 0 to `CPU_INT[0]`.
   - Assert `tile_int_req` for (slot 0, ch 0):
     - Expects `cpu_int == 2'b01`, `cpu_nmi == 0`.
   - Deassert the request:
     - Expects `cpu_int == 2'b00` (interrupt cleared).

2. **No queuing of “overlapping” requests (Test 2)**
   - Route slot 1, ch 0 to `CPU_INT[1]`.
   - Assert slot 0, ch 0 first, making it active.
   - While slot 0 is still active, pulse slot 1, ch 0, then deassert it.
   - Finally clear slot 0’s request.
   - Expects:
     - Only slot 0’s interrupt appears at the CPU (`cpu_int`).
     - The transient request from slot 1 is **not** queued.

3. **Unrouted sources are ignored (Test 3)**
   - Disable routing for slot 1 ch 0.
   - Assert `tile_int_req` for slot 1 ch 0:
     - Expects `cpu_int == 0`, `slot_ack == 0`.
   - Re‑enable routing for slot 0 ch 0 and assert it:
     - Expects `cpu_int == 2'b01`.

4. **NMI priority over INT (Test 4)**
   - Route NMI for slot 1 and INT for slot 0.
   - Assert both:
     - Expects:
       - `cpu_nmi == 1` and `cpu_int == 0` (NMI wins).
   - Clear NMI and keep INT asserted:
     - Expects:
       - `cpu_int == 2'b01` once NMI is gone.

5. **Single active at a time with two INTs (Test 5)**
   - Route INT for slot 0 and slot 1.
   - Assert both slot 0 ch 0 and slot 1 ch 0:
     - Expects:
       - First, slot 0 becomes active (`cpu_int == 2'b01`).
   - Clear slot 0’s request while slot 1 remains asserted:
     - Expects:
       - `cpu_int == 2'b10` (slot 1 promoted).

6. **Ack routing and non‑clearing semantics (Test 6)**
   - Route slot 0 ch 0 to `CPU_INT[0]`.
   - Assert its request, then pulse `irq_ack`:
     - Expects:
       - `slot_ack == 3'b001` (pulse on slot 0 only).
       - `cpu_int` remains asserted (`2'b01`), confirming that ack does *not*
         clear the interrupt.

7. **Ack while idle (Test 7)**
   - With no active interrupt, pulse `irq_ack`:
     - Expects:
       - `slot_ack == 3'b000` (no stray pulse).

8. **Disable pending IRQ before it becomes active (Test 8)**
   - Route slot 0 and slot 1 to INTs.
   - Assert slot 0 first (becomes active), then assert slot 1 (pending).
   - Before clearing slot 0, disable the route for slot 1.
   - Then clear both requests.
   - Expects:
     - After slot 0 clears, `cpu_int` remains `0` (disabled pending IRQ does
       not become active).

9. **Out‑of‑range CPU index: blocked but not driven (Test 9)**
   - Route slot 0 ch 0 with an out‑of‑range CPU index (e.g., index 3 when
     `NUM_CPU_INT = 2`).
   - Assert the interrupt:
     - Expects:
       - `cpu_int == 0` (no drive to invalid pin).
   - Pulse `irq_ack`:
     - Expects:
       - `slot_ack == 3'b001` (slot 0 still sees ack).
   - Clear the request:
     - Expects `cpu_int == 0` throughout.

This testbench ends with `"All irq_router tests passed."` after all checks succeed.

