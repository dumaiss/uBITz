µBITz Dock – CPLD External Signals
=================================

This document lists the external signals of the Dock CPLD as exposed by the two
main HDL blocks in this directory:

- `addr_decoder.v` – address decoder / bus arbiter.
- `irq_router.v` – interrupt router.

Internal helper/status signals that are not normally routed off the CPLD (for
example `win_valid`, `win_index`, `sel_slot`, `irq_int_active`,
`irq_int_slot`) are noted as such. The focus here is on signals that connect
the CPLD to:

- the CPU board (`CPU`),
- the Dock microcontroller/config bus (`Dock MCU`), and
- the peripheral Tiles/devices on the Dock backplane (`Device`).

> Note: On the CPU board there is a single physical `/CPU_ACK` line. Inside the
> CPLD this is seen as:
> - `irq_vec_cycle` into `addr_decoder`, and
> - `irq_ack` into `irq_router`.
> Both are active-high HDL signals derived from the same active-low `/CPU_ACK`
> pin.

---

addr_decoder – External Signals
-------------------------------

Top-level module: `addr_decoder`

### CPU bus interface

| Name                | Direction (CPLD) | Devices involved | Spec Reference Signal        | Description |
| ------------------- | ---------------- | ---------------- | ---------------------------- | ----------- |
| `addr[ADDR_W-1:0]`  | Input            | CPU              | `A[AddressBusWidth-1:0]`     | Host address bus for I/O cycles. Used only for window decode inside the CPLD; not driven out to Devices. |
| `iorq_n`            | Input            | CPU              | `/IORQ`                      | Active-low I/O request qualifier from the CPU bus. Low during an I/O cycle; used to qualify window hits and the /READY FSM. |
| `r_w_`              | Input            | CPU              | `R/W_`                       | CPU read/write indicator (`1` = read, `0` = write). Used to derive `is_read` / `is_write`, OP gating, and `io_r_w_`. |
| `ready_n`           | Output           | CPU              | `/READY`                     | Active-low /READY handshake back to the CPU. Low while the selected slot is busy; high when the cycle may complete. |
| `data_oe_n`         | Output           | CPU, Device      |                              | Active-low enable for Host↔Tile data transceivers. Low during mapped I/O cycles so the data bus connects CPU and Device; high otherwise. |
| `data_dir`          | Output           | CPU, Device      |                              | Data transceiver direction: `1` = Tiles→Host for reads, `0` = Host→Tiles for writes. |
| `ff_oe_n`           | Output           | CPU              |                              | Active-low enable for a constant 0xFF driver onto the Host data bus. Low only during unmapped I/O reads so CPU sees 0xFF. |
| `irq_vec_cycle`     | Input            | CPU              | `/CPU_ACK`                   | Active-high tag for a Mode-2 vector read I/O cycle. Internally, this is derived from the CPU’s `/CPU_ACK` line and is asserted only for the vector read; used together with `irq_int_active/irq_int_slot` to override slot selection. |
| `clk`               | Input            | CPU / Dock MCU   |                              | Core synchronous clock for the address decoder FSM and datapath. Provided by the Dock board (e.g., clock generator or CPU-side clock). |
| `rst_n`             | Input            | CPU / Dock MCU   | `/RESET`                     | Active-low synchronous reset for the addr_decoder logic, typically tied to the system `/RESET` distributed from the CPU/Dock. |

### Dock MCU configuration interface

| Name         | Direction (CPLD) | Devices involved | Spec Reference Signal | Description |
| ------------ | ---------------- | ---------------- | --------------------- | ----------- |
| `cfg_clk`    | Input            | Dock MCU         |                       | Configuration clock from the Dock MCU. Clocks byte-wide writes into the flattened BASE/MASK/SLOT/OP tables. |
| `cfg_we`     | Input            | Dock MCU         |                       | Active-high write strobe from the Dock MCU for the config bus. Affects one byte in the config space on each rising edge of `cfg_clk` while asserted. |
| `cfg_addr`   | Input            | Dock MCU         |                       | 8-bit configuration byte address. Selects which BASE/MASK/SLOT/OP byte is updated when `cfg_we` is asserted. |
| `cfg_wdata`  | Input            | Dock MCU         |                       | 8-bit configuration data written into the selected config byte when `cfg_we` is asserted. |

### Device / Tile-side interface

| Name                         | Direction (CPLD) | Devices involved | Spec Reference Signal | Description |
| ---------------------------- | ---------------- | ---------------- | --------------------- | ----------- |
| `dev_ready_n[NUM_SLOTS-1:0]` | Input            | Device           | `/READY`              | Per-slot device ready signals, active-low (`0` = busy, `1` = ready). Sampled and synchronized into the core clock domain; used by the FSM to stretch /READY. |
| `io_r_w_`                    | Output           | Device           | `R/W_`                | Qualified read/write signal driven toward Tiles during I/O cycles (`1` = read, `0` = write). Outside I/O cycles this defaults to “read” (`1`). |
| `cs_n[NUM_SLOTS-1:0]`        | Output           | Device           | `/CS[Slot#-1:0]`      | Active-low chip-selects for each Dock slot. Exactly one bit is asserted low during a mapped I/O cycle (after any Mode-2 override), or all bits high when no slot is selected. |

### Internal/status exports (optional / debug)

These signals are exposed as outputs of `addr_decoder` in the HDL but are
primarily for status/observation. They are not required by the external Dock
spec and may or may not be routed to pins or an MCU in a given implementation.

| Name             | Direction (CPLD) | Devices involved | Spec Reference Signal | Description |
| ---------------- | ---------------- | ---------------- | --------------------- | ----------- |
| `win_valid`      | Output           | (internal/debug) |                       | Indicates that the current I/O cycle hits a configured window after any Mode-2 override has been applied. |
| `win_index[3:0]` | Output           | (internal/debug) |                       | Index of the matched window for the current I/O cycle. |
| `sel_slot[2:0]`  | Output           | (internal/debug) |                       | Selected slot index for the current I/O cycle (after Mode-2 override). Mirrors the slot that drives `cs_n`. |

---

irq_router – External Signals
-----------------------------

Top-level module: `irq_router`

### CPU interrupt and acknowledge interface

| Name                       | Direction (CPLD) | Devices involved | Spec Reference Signal | Description |
| -------------------------- | ---------------- | ---------------- | --------------------- | ----------- |
| `cpu_int[NUM_CPU_INT-1:0]` | Output           | CPU              | `/CPU_INT[3:0]`       | Active-high interrupt request lines toward the CPU (map to CPU `/INT` pins via appropriate polarity/level shifting). Exactly one bit is asserted when a routed maskable INT is active and enabled. |
| `cpu_nmi[NUM_CPU_NMI-1:0]` | Output           | CPU              | `/CPU_NMI[1:0]`       | Active-high NMI request lines toward the CPU (map to CPU `/NMI` pins). Asserted when a routed NMI source is active and enabled. |
| `irq_ack`                  | Input            | CPU              | `/CPU_ACK`            | Active-high one-clock indication that the CPU performed an interrupt acknowledge cycle. Internally derived from the external `/CPU_ACK` line. Used to generate per-slot `slot_ack` pulses; does **not** clear the active interrupt. |
| `clk`                      | Input            | CPU / Dock MCU   |                       | Core clock for interrupt routing state machines and pending masks. Typically shared with other Dock CPLD logic. |
| `rst_n`                    | Input            | CPU / Dock MCU   | `/RESET`              | Active-low reset for the `irq_router` logic, tied to the system reset line. |

### Device / Tile interrupt interface

| Name                                            | Direction (CPLD) | Devices involved | Spec Reference Signal | Description |
| ----------------------------------------------- | ---------------- | ---------------- | --------------------- | ----------- |
| `tile_int_req[NUM_SLOTS*NUM_TILE_INT_CH-1:0]`   | Input            | Device           | `/INT_CH[1:0]`        | Flattened array of per-slot, per-channel maskable interrupt requests from Tiles (internal active-high representation of `INT_CH[1:0]` lines). Each bit corresponds to one (slot, channel) source. |
| `tile_nmi_req[NUM_SLOTS-1:0]`                   | Input            | Device           | `/NMI_CH`             | Per-slot NMI requests from Tiles (internal active-high representation of `NMI_CH` lines). |
| `slot_ack[NUM_SLOTS-1:0]`                       | Output           | Device           | `/INT_ACK`            | Per-slot, active-high acknowledge pulses from Dock to Tiles. A pulse indicates the CPU has performed an IRQ acknowledge cycle for the active maskable interrupt owned by that slot. |

### Dock MCU configuration interface

| Name                       | Direction (CPLD) | Devices involved | Spec Reference Signal | Description |
| -------------------------- | ---------------- | ---------------- | --------------------- | ----------- |
| `cfg_clk`                  | Input            | Dock MCU         |                       | Configuration clock for routing table access. |
| `cfg_wr_en`                | Input            | Dock MCU         |                       | Active-high write enable for INT/NMI route entries. |
| `cfg_rd_en`                | Input            | Dock MCU         |                       | Active-high read enable for route entries. |
| `cfg_addr[CFG_ADDR_WIDTH-1:0]` | Input        | Dock MCU         |                       | Address of the INT or NMI routing entry being accessed. |
| `cfg_wdata[31:0]`          | Input            | Dock MCU         |                       | Write data for route entries; only `cfg_wdata[7:0]` is used by the current implementation. |
| `cfg_rdata[31:0]`          | Output           | Dock MCU         |                       | Readback data for route entries, driven in the `cfg_clk` domain when `cfg_rd_en` is asserted. |

### Internal export to other Dock logic

These signals are intended for use by other Dock logic (not directly by CPU,
Dock MCU, or Tiles). In the current HDL, they are consumed by `addr_decoder`
to steer Mode-2 vector fetches.

| Name                             | Direction (CPLD) | Devices involved | Spec Reference Signal | Description |
| -------------------------------- | ---------------- | ---------------- | --------------------- | ----------- |
| `irq_int_active`                 | Output           | (internal only)  |                       | Indicates that a single, routed maskable interrupt is currently active and eligible for Mode-2 vectoring. High only when a valid maskable INT is selected and its route entry is enabled. |
| `irq_int_slot[SLOT_IDX_WIDTH-1:0]` | Output         | (internal only)  |                       | Encoded slot index of the active maskable interrupt source. Used by `addr_decoder` to override slot selection during Mode-2 vector reads. |
