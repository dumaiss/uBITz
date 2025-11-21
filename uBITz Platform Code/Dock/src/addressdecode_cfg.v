// Submodule: addressdecode_cfg
// Purpose: configuration storage for BASE/MASK/SLOT/OP tables.
module addressdecode_cfg #(
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

    // Config layout
    localparam integer BASE_OFF = 0;
    localparam integer MASK_OFF = BASE_OFF + (NUM_WIN * CFG_BYTES);
    localparam integer SLOT_OFF = MASK_OFF + (NUM_WIN * CFG_BYTES);
    localparam integer OP_OFF   = SLOT_OFF + NUM_WIN;

    // Defaults
    initial begin
        for (int i = 0; i < NUM_WIN; i++) begin
            base_flat[i*ADDR_W +: ADDR_W] = '0;
            mask_flat[i*ADDR_W +: ADDR_W] = '0;
            slot_flat[i*3 +: 3]           = 3'b000;
            op_flat[i*8 +: 8]             = 8'hFF;
        end
    end

    // Byte-wise config writes
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
