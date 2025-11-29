// Submodule: addr_decoder_cfg
// Purpose: configuration storage for BASE/MASK/SLOT/OP tables.
// Walkthrough:
//   - Flattened config arrays (base_flat/mask_flat/slot_flat/op_flat) hold all
//     window entries back-to-back.
//   - CFG layout (byte addressed):
//       * BASE bytes  : BASE_OFF + w*CFG_BYTES + byte
//       * MASK bytes  : MASK_OFF + w*CFG_BYTES + byte
//       * SLOT (3b)   : SLOT_OFF + w
//       * OP (8b)     : OP_OFF   + w
//   - cfg_we strobes in a single byte on cfg_clk. No readback path here; users
//     should track writes externally or probe the flattened outputs.
module addr_decoder_cfg #(
    parameter integer ADDR_W  = 32,
    parameter integer NUM_WIN = 16
)(
    input  logic        cfg_clk,
    input  logic        cfg_we,
    input  logic [7:0]  cfg_addr,
    input  logic [7:0]  cfg_wdata,

    output logic [NUM_WIN*ADDR_W-1:0] base_flat,
    output logic [NUM_WIN*ADDR_W-1:0] mask_flat,
    output logic [NUM_WIN*3-1:0]      slot_flat,
    output logic [NUM_WIN*8-1:0]      op_flat
);

    // Number of bytes needed to represent the ADDR_W-bit BASE/MASK fields.
    localparam integer CFG_BYTES = (ADDR_W + 7) / 8;

    // Config layout byte offsets
    localparam integer BASE_OFF = 0;
    localparam integer MASK_OFF = BASE_OFF + (NUM_WIN * CFG_BYTES);
    localparam integer SLOT_OFF = MASK_OFF + (NUM_WIN * CFG_BYTES);
    localparam integer OP_OFF   = SLOT_OFF + NUM_WIN;

    logic [NUM_WIN*ADDR_W-1:0] base_flat = '0;
    logic [NUM_WIN*ADDR_W-1:0] mask_flat = '0;
    logic [NUM_WIN*3-1:0]      slot_flat = '0;
    logic [NUM_WIN*8-1:0]      op_flat   = {NUM_WIN*8{1'b1}}; // all ones = 0xFF per byte

    // Byte-wise config writes, with explicit region decode
	always_ff @(posedge cfg_clk) begin
        if (cfg_we) begin
            // BASE bytes
            for (int w = 0; w < NUM_WIN; w++) begin
                for (int b = 0; b < CFG_BYTES; b++) begin
                    if (cfg_addr == (BASE_OFF + w*CFG_BYTES + b))
                        base_flat[w*ADDR_W + 8*b +: 8] <= cfg_wdata;
                end
            end
            // MASK bytes
            for (int w = 0; w < NUM_WIN; w++) begin
                for (int b = 0; b < CFG_BYTES; b++) begin
                    if (cfg_addr == (MASK_OFF + w*CFG_BYTES + b))
                        mask_flat[w*ADDR_W + 8*b +: 8] <= cfg_wdata;
                end
            end
            // SLOT regs
            for (int w = 0; w < NUM_WIN; w++) begin
                if (cfg_addr == (SLOT_OFF + w))
                    slot_flat[w*3 +: 3] <= cfg_wdata[2:0];
            end
            // OP regs
            for (int w = 0; w < NUM_WIN; w++) begin
                if (cfg_addr == (OP_OFF + w))
                    op_flat[w*8 +: 8] <= cfg_wdata;
            end
        end
    end

endmodule
