// Submodule: addr_decoder_fsm
// Purpose: /READY handshake and /CS generation with per-slot ready sync.
// Walkthrough:
//   - Synchronizes dev_ready_n into clk domain (two flops).
//   - IDLE: waits for a qualified window hit (win_valid=1, /IORQ low); latches
//     sel_slot into active_slot, asserts corresponding cs, drives ready_n low.
//   - ACTIVE: holds cs for active_slot while /IORQ is low; ready_n reflects
//     dev_ready_sync[active_slot]; deasserts cs and returns to IDLE when /IORQ rises.
module addr_decoder_fsm #(
    parameter integer NUM_SLOTS = 5
)(
    input  logic              clk,
    input  logic              rst_n,

    input  logic              iorq_n,
    input  logic              win_valid,
    input  logic [2:0]        sel_slot,

    input  logic [NUM_SLOTS-1:0] dev_ready_n,

    output logic [NUM_SLOTS-1:0] cs,
    output logic                  ready_n
);

    // Synchronizer for dev_ready_n into clk domain
    logic [NUM_SLOTS-1:0] dev_ready_meta; // stage 1
    logic [NUM_SLOTS-1:0] dev_ready_sync; // stage 2, used internally

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dev_ready_meta <= {NUM_SLOTS{1'b1}};
            dev_ready_sync <= {NUM_SLOTS{1'b1}};
        end else begin
            dev_ready_meta <= dev_ready_n;
            dev_ready_sync <= dev_ready_meta;
        end
    end

    localparam logic S_IDLE   = 1'b0; // waiting for /IORQ hit
    localparam logic S_ACTIVE = 1'b1; // servicing an active /IORQ

    logic       state;       // FSM state
    logic [2:0] active_slot; // latched slot during ACTIVE

    // Guarded ready selection (default ready when out of range)
    wire sel_dev_ready_n = (active_slot < NUM_SLOTS) ? dev_ready_sync[active_slot] : 1'b1;

    function [NUM_SLOTS-1:0] slot_to_cs(input logic [2:0] slot_sel);
        logic [NUM_SLOTS-1:0] tmp;
        begin
            tmp = '0;
            if (slot_sel < NUM_SLOTS)
                tmp[slot_sel] = 1'b1;
            slot_to_cs = tmp;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            active_slot <= 3'd0;
            cs          <= {NUM_SLOTS{1'b0}};
            ready_n     <= 1'b1;
        end else begin
            case (state)
                S_IDLE: begin
                    cs      <= {NUM_SLOTS{1'b0}};
                    ready_n <= 1'b1;

                    if (!iorq_n && win_valid) begin
                        active_slot <= sel_slot;
                        state       <= S_ACTIVE;
                        cs          <= slot_to_cs(sel_slot);
                        ready_n     <= 1'b0;
                    end else if (!iorq_n && !win_valid) begin
                        cs      <= {NUM_SLOTS{1'b0}};
                        ready_n <= 1'b1;
                    end
                end
                S_ACTIVE: begin
                    cs <= slot_to_cs(active_slot);

                    if (sel_dev_ready_n) begin
                        ready_n <= 1'b1;
                    end else begin
                        ready_n <= 1'b0;
                    end

                    if (iorq_n) begin
                        cs      <= {NUM_SLOTS{1'b0}};
                        state   <= S_IDLE;
                        // ready_n will be driven high in S_IDLE
                    end
                end
            endcase
        end
    end

endmodule
