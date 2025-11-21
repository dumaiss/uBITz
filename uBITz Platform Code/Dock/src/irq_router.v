// irq_router: Dock-side interrupt router with configurable slot→CPU mapping.
// - Supports NUM_SLOTS tiles, each with 2 maskable INT channels and 1 NMI.
// - Routes to up to 4 CPU INT pins and 2 CPU NMI pins (active-high internally).
// - Tracks exactly one active interrupt at a time; additional requests are
//   held in pending masks until the active request deasserts.
// - A single CPU ack pulse is forwarded to the owning slot as a one-cycle
//   slot_ack pulse; ack does not clear the active interrupt.
// - Configuration is through a simple MCU-driven config bus:
//     * Maskable INT routing entry at cfg_addr = slot * NUM_TILE_INT_CH + channel
//     * NMI routing entry at cfg_addr = NUM_SLOTS*NUM_TILE_INT_CH + slot
//     * Write cfg_wdata[7:0] with {enable, idx[3:0]} (others reserved = 0)
//     * Disabled entries (bit7=0) ignore the corresponding request.
module irq_router #(
    parameter integer NUM_SLOTS        = 5,
    parameter integer NUM_CPU_INT      = 4,
    parameter integer NUM_CPU_NMI      = 2,
    parameter integer NUM_TILE_INT_CH  = 2,
    parameter integer CFG_ADDR_WIDTH   = 8
)(
    input  wire                         clk,
    input  wire                         rst_n,   // synchronous active-low reset
    input  wire                         cfg_clk, // config bus clock

    // Tile -> Dock interrupt request inputs (internal active-high levels)
    input  wire [NUM_SLOTS*NUM_TILE_INT_CH-1:0] tile_int_req, // maskable channels
    input  wire [NUM_SLOTS-1:0]                 tile_nmi_req, // non-maskable

    // CPU -> Dock acknowledge (decoded elsewhere)
    input  wire                         irq_ack,   // 1-clock-wide pulse = "CPU did an IRQ ack cycle"

    // CPU-side interrupt outputs (internal active-high)
    output reg  [NUM_CPU_INT-1:0]       cpu_int,   // to CPU INT pins
    output reg  [NUM_CPU_NMI-1:0]       cpu_nmi,   // to CPU NMI pins

    // Dock -> Tile per-slot acknowledge outputs (internal active-high)
    output reg  [NUM_SLOTS-1:0]         slot_ack,  // 1-clock pulse, per slot

    // Simple config bus for routing/enable control
    input  wire                         cfg_wr_en,
    input  wire                         cfg_rd_en,
    input  wire [CFG_ADDR_WIDTH-1:0]    cfg_addr,
    input  wire [31:0]                  cfg_wdata,
    output reg  [31:0]                  cfg_rdata
);

    // ------------------------------------------------------------------
    // Routing tables
    // ------------------------------------------------------------------
    // Maskable INT routing: enable + CPU INT index
    reg [7:0] int_route_slot_ch [0:NUM_SLOTS-1][0:NUM_TILE_INT_CH-1];
    // NMI routing: enable + CPU NMI index
    reg [7:0] nmi_route_slot [0:NUM_SLOTS-1];

    // ------------------------------------------------------------------
    // Active interrupt tracking
    // ------------------------------------------------------------------
    reg        active_valid;
    reg        active_is_nmi;
    reg [7:0]  active_slot;
    reg [7:0]  active_ch;       // channel for maskable; 0 for NMI
    reg [7:0]  active_cpu_idx;  // full route entry (bit7 = enable, [3:0] = index)

    // Pending sets
    reg [NUM_SLOTS*NUM_TILE_INT_CH-1:0] pending_int;
    reg [NUM_SLOTS-1:0]                 pending_nmi;

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    // Flattened index helper for maskable pending bits
    function automatic integer int_idx(input integer slot, input integer ch);
        begin
            int_idx = slot*NUM_TILE_INT_CH + ch;
        end
    endfunction

    // ------------------------------------------------------------------
    // Combinational next-state computation
    // ------------------------------------------------------------------
    reg [NUM_SLOTS*NUM_TILE_INT_CH-1:0] pending_int_next;
    reg [NUM_SLOTS-1:0]                 pending_nmi_next;
    reg        active_valid_next;
    reg        active_is_nmi_next;
    reg [7:0]  active_slot_next;
    reg [7:0]  active_ch_next;
    reg [7:0]  active_cpu_idx_next;

    integer s, c;
    reg [7:0] route_entry;
    reg       route_en;

    always @* begin
        // Default next-state mirrors current
        pending_int_next    = pending_int;
        pending_nmi_next    = pending_nmi;
        active_valid_next   = active_valid;
        active_is_nmi_next  = active_is_nmi;
        active_slot_next    = active_slot;
        active_ch_next      = active_ch;
        active_cpu_idx_next = active_cpu_idx;

        // Pending = masked view of raw lines (no queuing)
        // - Only routed sources are considered
        // - If the line drops, pending drops too
        for (s = 0; s < NUM_SLOTS; s = s + 1) begin
            for (c = 0; c < NUM_TILE_INT_CH; c = c + 1) begin
                route_entry = int_route_slot_ch[s][c];

                if (route_entry[7]) begin
                    // Routed: follow current line level
                    pending_int_next[int_idx(s,c)] = tile_int_req[int_idx(s,c)];
                end else begin
                    // Unrouted: completely ignored
                    pending_int_next[int_idx(s,c)] = 1'b0;
                end
            end

            if (nmi_route_slot[s][7]) begin
                pending_nmi_next[s] = tile_nmi_req[s];
            end else begin
                pending_nmi_next[s] = 1'b0;
            end
        end

        // Clear active when the underlying request deasserts
        if (active_valid) begin
            if (active_is_nmi) begin
                if (!tile_nmi_req[active_slot]) begin
                    active_valid_next = 1'b0;
                end
            end else begin
                if (!tile_int_req[int_idx(active_slot, active_ch)]) begin
                    active_valid_next = 1'b0;
                end
            end
        end

        // Selection when idle
        if (!active_valid_next) begin
            // Candidate defaults
            active_valid_next   = 1'b0;
            active_is_nmi_next  = 1'b0;
            active_slot_next    = 8'd0;
            active_ch_next      = 8'd0;
            active_cpu_idx_next = 8'd0;

            // First, NMIs
            for (s = 0; s < NUM_SLOTS; s = s + 1) begin
                if (!active_valid_next && pending_nmi_next[s]) begin
                    route_entry = nmi_route_slot[s];
                    active_valid_next   = 1'b1;
                    active_is_nmi_next  = 1'b1;
                    active_slot_next    = s[7:0];
                    active_ch_next      = 8'd0;
                    active_cpu_idx_next = route_entry;
                end
            end

            // Then maskable INTs
            if (!active_valid_next) begin
                for (s = 0; s < NUM_SLOTS; s = s + 1) begin
                    for (c = 0; c < NUM_TILE_INT_CH; c = c + 1) begin
                        if (!active_valid_next && pending_int_next[int_idx(s,c)]) begin
                            route_entry = int_route_slot_ch[s][c];
                            active_valid_next   = 1'b1;
                            active_is_nmi_next  = 1'b0;
                            active_slot_next    = s[7:0];
                            active_ch_next      = c[7:0];
                            active_cpu_idx_next = route_entry;
                        end
                    end
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Sequential state updates
    // ------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            pending_int    <= {NUM_SLOTS*NUM_TILE_INT_CH{1'b0}};
            pending_nmi    <= {NUM_SLOTS{1'b0}};
            active_valid   <= 1'b0;
            active_is_nmi  <= 1'b0;
            active_slot    <= 8'd0;
            active_ch      <= 8'd0;
            active_cpu_idx <= 8'd0;
            cfg_rdata      <= 32'h0000_0000;

        end else begin
            pending_int    <= pending_int_next;
            pending_nmi    <= pending_nmi_next;
            active_valid   <= active_valid_next;
            active_is_nmi  <= active_is_nmi_next;
            active_slot    <= active_slot_next;
            active_ch      <= active_ch_next;
            active_cpu_idx <= active_cpu_idx_next;
        end
    end

    // Config domain: route table access synchronized to cfg_clk
    always @(posedge cfg_clk or negedge rst_n) begin
        if (!rst_n) begin
            cfg_rdata <= 32'h0000_0000;
            for (s = 0; s < NUM_SLOTS; s = s + 1) begin
                nmi_route_slot[s] <= 8'h00;
                for (c = 0; c < NUM_TILE_INT_CH; c = c + 1)
                    int_route_slot_ch[s][c] <= 8'h00;
            end
        end else begin
            cfg_rdata <= 32'h0000_0000;
            // Config writes
            if (cfg_wr_en) begin
                integer idx;
                integer slot_sel;
                integer ch_sel;
                idx = cfg_addr;
                if (idx < (NUM_SLOTS*NUM_TILE_INT_CH)) begin
                    slot_sel = idx / NUM_TILE_INT_CH;
                    ch_sel   = idx % NUM_TILE_INT_CH;
                    int_route_slot_ch[slot_sel][ch_sel] <= cfg_wdata[7:0];
                end else if (idx < (NUM_SLOTS*NUM_TILE_INT_CH + NUM_SLOTS)) begin
                    slot_sel = idx - (NUM_SLOTS*NUM_TILE_INT_CH);
                    nmi_route_slot[slot_sel] <= cfg_wdata[7:0];
                end
            end
        end
    end

    // ------------------------------------------------------------------
    // Combinational outputs
    // ------------------------------------------------------------------
    always @* begin
        cpu_int = {NUM_CPU_INT{1'b0}};
        cpu_nmi = {NUM_CPU_NMI{1'b0}};

        if (active_valid && !active_is_nmi && active_cpu_idx[7]) begin
            if (active_cpu_idx[3:0] < NUM_CPU_INT)
                cpu_int[active_cpu_idx[3:0]] = 1'b1;
        end

        if (active_valid && active_is_nmi && active_cpu_idx[7]) begin
            if (active_cpu_idx[3:0] < NUM_CPU_NMI)
                cpu_nmi[active_cpu_idx[3:0]] = 1'b1;
        end
    end

    always @* begin
        slot_ack = {NUM_SLOTS{1'b0}};
        if (irq_ack && active_valid && !active_is_nmi) begin
            if (active_slot < NUM_SLOTS)
                slot_ack[active_slot] = 1'b1;
        end
    end

endmodule
