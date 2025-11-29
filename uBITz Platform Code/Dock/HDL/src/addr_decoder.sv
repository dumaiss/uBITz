//--------------------------------------------------------------------
// µBITz Dock - Address Decoder / Bus Arbiter
//--------------------------------------------------------------------
// Responsibilities:
//   • Decode up to NUM_WIN I/O windows based on BASE/MASK registers.
//   • Select a target slot (0..NUM_SLOTS-1) and assert its /CS_n line.
//   • Implement the /READY handshake with per-slot DEV_READY_N inputs.
//   • Control Host<->Tile data transceivers (enable + direction).
//   • Drive a constant 0xFF value onto the Host data bus for unmapped
//     I/O read cycles (via FF_OE_N).
//
// Walkthrough:
//   1) addr_decoder_cfg flattens BASE/MASK/SLOT/OP config regs into
//      wide buses (base_flat/mask_flat/slot_flat/op_flat).
//   2) addr_decoder_match compares addr/r_w_/iorq_n against those tables,
//      producing decoded hit info: is_read_sig/is_write_sig, win_valid_sig,
//      win_index_sig, and sel_slot_sig.
//   3) A small mux can override sel_slot and win_valid during a Mode-2
//      vector fetch (irq_vec_cycle + irq_int_active), steering /CS to the
//      active interrupt slot even if the address is otherwise unmapped.
//   4) addr_decoder_fsm consumes win_valid_mux/sel_slot_mux with dev_ready_n
//      to generate per-slot cs signals and the ready_n handshake.
//   5) addr_decoder_datapath uses win_valid_mux/is_read_sig/is_write_sig to
//      drive transceiver enables (data_oe_n/data_dir) and the 0xFF filler
//      driver (ff_oe_n), plus a qualified io_r_w_.
//
// Notes:
//   - DATA bus itself does NOT pass through this module; only the
//     control signals for external transceivers are generated here.
//   - All logic is synchronous to 'clk' except for configuration writes
//     on 'cfg_clk' and purely combinational decode paths.
//   - Compatible with legacy 8-bit, 4-window map: ADDR_W=8, NUM_WIN=4
//     yields the original config layout 0x00..0x0F.
//--------------------------------------------------------------------
module addr_decoder #(
    parameter ADDR_W    = 32, // address bus width (up to 32)
    parameter NUM_WIN   = 16, // number of decode windows (up to 16)
    parameter NUM_SLOTS = 5,  // number of chip-select outputs (slots)
    parameter integer SLOT_IDX_WIDTH  = (NUM_SLOTS <= 1) ? 1 : $clog2(NUM_SLOTS)
)(
    input  [ADDR_W-1:0] addr,
    input               iorq_n,

    input               clk,
    input               rst_n,

    input               r_w_,    // 1 = read, 0 = write

    // Per-slot device ready signals (active-low: 0 = busy, 1 = ready)
    input  [NUM_SLOTS-1:0] dev_ready_n,

    // From irq_router / interrupt front-end
    input               irq_int_active,      // 1 = a maskable INT is currently active
    input  [SLOT_IDX_WIDTH-1:0] irq_int_slot, // slot index for that active INT
    input               irq_vec_cycle,      // 1 = this I/O cycle is the Mode-2 vector read

    input               cfg_clk,
    input               cfg_we,
    input  [7:0]        cfg_addr,
    input  [7:0]        cfg_wdata,

    output reg              ready_n,
    output                  io_r_w_,  // 1 = read, 0 = write (qualified by /IORQ)

    // Data bus control for Dock transceivers
    output                  data_oe_n,   // active-low enable for Host<->Tiles data transceivers
    output                  data_dir,    // 1 = Tiles->Host (read), 0 = Host->Tiles (write)
    output                  ff_oe_n,     // active-low enable for constant-0xFF driver onto Host bus

    output reg                    win_valid,
    output reg [3:0]              win_index,
    output reg [2:0]              sel_slot,
    output      [NUM_SLOTS-1:0]   cs_n
);

    localparam integer WIN_INDEX_W = 4; // supports NUM_WIN <= 16
    // Width needed to index NUM_SLOTS slots (matches irq_router)
    localparam integer SLOT_IDX_WIDTH = (NUM_SLOTS <= 1) ? 1 : $clog2(NUM_SLOTS);

    // Flattened config tables for module interconnect (from addr_decoder_cfg)
    logic [NUM_WIN*ADDR_W-1:0] base_flat; // concatenated BASE registers
    logic [NUM_WIN*ADDR_W-1:0] mask_flat; // concatenated MASK registers
    logic [NUM_WIN*3-1:0]      slot_flat; // concatenated SLOT selects
    logic [NUM_WIN*8-1:0]      op_flat;   // concatenated OP gating fields

    // Handshake / CS (active-high internal view)
    logic [NUM_SLOTS-1:0] cs;

    // Match outputs (raw decode from addr_decoder_match)
    logic                  is_read_sig;      // 1 when current cycle is a read
    logic                  is_write_sig;     // 1 when current cycle is a write
    logic [WIN_INDEX_W-1:0] win_index_sig;   // index of matched window
    logic [2:0]            sel_slot_sig;     // slot chosen by window match
    logic                  win_valid_sig;    // decode hit (qualified by /IORQ)
    // Slot actually used for /CS generation (may be overridden for vector reads)
    logic [2:0]            sel_slot_mux;     // final slot after vector override
    // Muxed view for FSM/datapath (may be overridden during vector cycles)
    logic                  win_valid_mux;    // final win_valid after override

    // Ready signal from FSM
    logic ready_n_sig; // internal ready_n before output mapping

    // -----------------------------------------------------------------
    // Submodules
    // -----------------------------------------------------------------
    addr_decoder_cfg #(
        .ADDR_W (ADDR_W),
        .NUM_WIN(NUM_WIN)
    ) u_cfg (
        .rst_n    (rst_n),
        .cfg_clk   (cfg_clk),
        .cfg_we    (cfg_we),
        .cfg_addr  (cfg_addr),
        .cfg_wdata (cfg_wdata),
        .base_flat (base_flat),
        .mask_flat (mask_flat),
        .slot_flat (slot_flat),
        .op_flat   (op_flat)
    );

    addr_decoder_match #(
        .ADDR_W     (ADDR_W),
        .NUM_WIN    (NUM_WIN),
        .WIN_INDEX_W(WIN_INDEX_W)
    ) u_match (
        .addr      (addr),
        .iorq_n    (iorq_n),
        .r_w_      (r_w_),
        .base_flat (base_flat),
        .mask_flat (mask_flat),
        .slot_flat (slot_flat),
        .op_flat   (op_flat),
        .is_read   (is_read_sig),
        .is_write  (is_write_sig),
        .win_valid (win_valid_sig),
        .win_index (win_index_sig),
        .sel_slot  (sel_slot_sig)
    );

    // -----------------------------------------------------------------
    // Slot selection + win_valid override for Mode-2 vector read cycles
    // -----------------------------------------------------------------
    always_comb begin
        // Defaults: use decoded values from the match logic
        sel_slot_mux  = sel_slot_sig;
        win_valid_mux = win_valid_sig;

        // If this cycle has been tagged as the Mode-2 vector read
        // *and* there is an active maskable INT, override the slot
        // with the one reported by irq_router.
        //
        // NOTE:
        //  - This module does not decide when irq_vec_cycle is 1.
        //    That is the CPU/host's responsibility.
        //  - If irq_vec_cycle=1 but irq_int_active=0, we leave the decoded slot in place.
        if (irq_vec_cycle && irq_int_active) begin
            if (irq_int_slot < NUM_SLOTS) begin
                sel_slot_mux  = {{(3-SLOT_IDX_WIDTH){1'b0}}, irq_int_slot};
                win_valid_mux = 1'b1;
            end
        end
    end

    addr_decoder_fsm #(
        .NUM_SLOTS(NUM_SLOTS)
    ) u_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .iorq_n      (iorq_n),
        .win_valid   (win_valid_mux),
        .sel_slot    (sel_slot_mux),
        .dev_ready_n (dev_ready_n),
        .cs          (cs),
        .ready_n     (ready_n_sig)
    );

    addr_decoder_datapath u_dp (
        .iorq_n    (iorq_n),
        .is_read   (is_read_sig),
        .is_write  (is_write_sig),
        .win_valid (win_valid_mux),
        .data_oe_n (data_oe_n),
        .data_dir  (data_dir),
        .ff_oe_n   (ff_oe_n),
        .io_r_w_   (io_r_w_)
    );

    // -----------------------------------------------------------------
    // Output mapping
    // -----------------------------------------------------------------
    assign cs_n = ~cs;

    always_comb begin
        ready_n  = ready_n_sig;
        win_valid = win_valid_mux;
        win_index = win_index_sig;
        sel_slot  = sel_slot_mux;
    end

endmodule
