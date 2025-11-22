// Submodule: addr_decoder_match
// Purpose: window match, priority select, and slot selection.
// Walkthrough:
//   - Unpacks flattened BASE/MASK/SLOT/OP tables into arrays.
//   - For each window: compute masked address equality, apply OP gating
//     (any/read-only/write-only), and qualify with /IORQ low to form win_active.
//   - Priority encoder picks the lowest-index active window; sel_slot maps that
//     window to its configured slot value.
module addr_decoder_match #(
    parameter integer ADDR_W      = 32,
    parameter integer NUM_WIN     = 16,
    parameter integer WIN_INDEX_W = 4
)(
    input  logic [ADDR_W-1:0] addr,
    input  logic              iorq_n,
    input  logic              r_w_,      // 1 = read, 0 = write

    input  logic [NUM_WIN*ADDR_W-1:0] base_flat,
    input  logic [NUM_WIN*ADDR_W-1:0] mask_flat,
    input  logic [NUM_WIN*3-1:0]      slot_flat,
    input  logic [NUM_WIN*8-1:0]      op_flat,

    output logic              is_read,
    output logic              is_write,

    output logic                   win_valid,
    output logic [WIN_INDEX_W-1:0] win_index,
    output logic [2:0]             sel_slot
);

    // Unpacked config entries per window
    logic [ADDR_W-1:0] base [0:NUM_WIN-1]; // BASE register
    logic [ADDR_W-1:0] mask [0:NUM_WIN-1]; // MASK register
    logic [2:0]        slot [0:NUM_WIN-1]; // SLOT selection
    logic [7:0]        op   [0:NUM_WIN-1]; // OP gating

    // Per-window match helpers
    logic [ADDR_W-1:0] masked_equal [0:NUM_WIN-1]; // ~(addr ^ base)
    logic [ADDR_W-1:0] bit_match    [0:NUM_WIN-1]; // (~mask) | masked_equal
    logic [NUM_WIN-1:0] op_ok;                     // OP gating satisfied
    logic [NUM_WIN-1:0] raw_hit;                   // address match (unqualified)
    logic [NUM_WIN-1:0] hit;                       // address + op gating
    logic [NUM_WIN-1:0] win_active;                // hit qualified by /IORQ low

    // Unpack flattened config tables
    generate
        for (genvar uw = 0; uw < NUM_WIN; uw++) begin : unpack_cfg
            assign base[uw] = base_flat[uw*ADDR_W +: ADDR_W];
            assign mask[uw] = mask_flat[uw*ADDR_W +: ADDR_W];
            assign slot[uw] = slot_flat[uw*3 +: 3];
            assign op[uw]   = op_flat[uw*8 +: 8];
        end
    endgenerate

    assign is_read  =  r_w_;
    assign is_write = ~r_w_;

    genvar gw;
    generate
        for (gw = 0; gw < NUM_WIN; gw++) begin : gen_win
            assign masked_equal[gw] = ~(addr ^ base[gw]);
            assign bit_match[gw]    = (~mask[gw]) | masked_equal[gw];

            assign op_ok[gw] =
                (op[gw] == 8'hFF) ||
                (op[gw] == 8'h01 && is_read) ||
                (op[gw] == 8'h00 && is_write);

            assign raw_hit[gw]    = &bit_match[gw];
            assign hit[gw]        = raw_hit[gw] & op_ok[gw];
            assign win_active[gw] = hit[gw] & ~iorq_n;
        end
    endgenerate

    // Priority encoder: lowest index wins
    always_comb begin
        win_valid = 1'b0;
        win_index = '0;
        for (int wi = 0; wi < NUM_WIN; wi++) begin
            if (win_active[wi] && !win_valid) begin
                win_valid = 1'b1;
                win_index = wi[WIN_INDEX_W-1:0];
            end
        end
    end

    // Map window index to slot
    always_comb begin
        sel_slot = 3'b000;
        if (win_valid)
            sel_slot = slot[win_index];
    end

endmodule
