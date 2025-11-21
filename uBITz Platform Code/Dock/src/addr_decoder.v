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
    parameter NUM_SLOTS = 5   // number of chip-select outputs (slots)
)(
    input  [ADDR_W-1:0] addr,
    input               iorq_n,

    input               clk,
    input               rst_n,

    input               r_w_,    // 1 = read, 0 = write

    // Per-slot device ready signals (active-low: 0 = busy, 1 = ready)
    input  [NUM_SLOTS-1:0] dev_ready_n,

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

    // Flattened config tables for module interconnect
    logic [NUM_WIN*ADDR_W-1:0] base_flat;
    logic [NUM_WIN*ADDR_W-1:0] mask_flat;
    logic [NUM_WIN*3-1:0]      slot_flat;
    logic [NUM_WIN*8-1:0]      op_flat;

    // Handshake / CS
    logic [NUM_SLOTS-1:0] cs;

    // Match outputs
    logic                  is_read_sig;
    logic                  is_write_sig;
    logic [WIN_INDEX_W-1:0] win_index_sig;
    logic [2:0]            sel_slot_sig;
    logic                  win_valid_sig;

    // Ready signal from FSM
    logic ready_n_sig;

    // -----------------------------------------------------------------
    // Submodules
    // -----------------------------------------------------------------
    addressdecode_cfg #(
        .ADDR_W (ADDR_W),
        .NUM_WIN(NUM_WIN)
    ) u_cfg (
        .cfg_clk   (cfg_clk),
        .cfg_we    (cfg_we),
        .cfg_addr  (cfg_addr),
        .cfg_wdata (cfg_wdata),
        .base_flat (base_flat),
        .mask_flat (mask_flat),
        .slot_flat (slot_flat),
        .op_flat   (op_flat)
    );

    addressdecode_match #(
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

    addressdecode_fsm #(
        .NUM_SLOTS(NUM_SLOTS)
    ) u_fsm (
        .clk         (clk),
        .rst_n       (rst_n),
        .iorq_n      (iorq_n),
        .win_valid   (win_valid_sig),
        .sel_slot    (sel_slot_sig),
        .dev_ready_n (dev_ready_n),
        .cs          (cs),
        .ready_n     (ready_n_sig)
    );

    addressdecode_datapath u_dp (
        .iorq_n    (iorq_n),
        .is_read   (is_read_sig),
        .is_write  (is_write_sig),
        .win_valid (win_valid_sig),
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
        win_valid = win_valid_sig;
        win_index = win_index_sig;
        sel_slot  = sel_slot_sig;
    end

endmodule
