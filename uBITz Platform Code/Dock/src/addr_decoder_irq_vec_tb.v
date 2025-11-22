`timescale 1ns/1ps

module addr_decoder_irq_vec_tb;
    localparam int ADDR_W          = 32;
    localparam int NUM_SLOTS       = 4;
    localparam int NUM_WIN         = 4;
    localparam int NUM_TILE_INT_CH = 2;
    localparam int NUM_CPU_INT     = 4;
    localparam int NUM_CPU_NMI     = 1;
    localparam int IRQ_CFG_AW      = 8;

    localparam int SLOT_IDX_WIDTH = (NUM_SLOTS <= 1) ? 1 : $clog2(NUM_SLOTS);
    localparam int CFG_BYTES      = (ADDR_W + 7) / 8;
    localparam int BASE_OFF       = 0;
    localparam int MASK_OFF       = BASE_OFF + (NUM_WIN * CFG_BYTES);
    localparam int SLOT_OFF       = MASK_OFF + (NUM_WIN * CFG_BYTES);
    localparam int OP_OFF         = SLOT_OFF + NUM_WIN;

    logic clk;
    wire  cfg_clk = clk;
    logic rst_n;

    logic [ADDR_W-1:0] addr;
    logic              iorq_n;
    logic              r_w_;
    logic              irq_vec_cycle;

    logic [NUM_SLOTS-1:0] dev_ready_n;

    logic cfg_we;
    logic [7:0] cfg_addr;
    logic [7:0] cfg_wdata;

    logic [NUM_SLOTS*NUM_TILE_INT_CH-1:0] tile_int_req;
    logic [NUM_SLOTS-1:0]                 tile_nmi_req;
    logic                                 irq_ack;

    logic                                 irq_cfg_wr_en;
    logic                                 irq_cfg_rd_en;
    logic [IRQ_CFG_AW-1:0]                irq_cfg_addr;
    logic [31:0]                          irq_cfg_wdata;

    wire                                  ready_n;
    wire                                  io_r_w_;
    wire                                  data_oe_n;
    wire                                  data_dir;
    wire                                  ff_oe_n;
    wire                                  win_valid;
    wire [3:0]                            win_index;
    wire [2:0]                            sel_slot;
    wire [NUM_SLOTS-1:0]                  cs_n;

    wire [NUM_CPU_INT-1:0]                cpu_int;
    wire [NUM_CPU_NMI-1:0]                cpu_nmi;
    wire [NUM_SLOTS-1:0]                  slot_ack;
    wire                                  irq_int_active;
    wire [SLOT_IDX_WIDTH-1:0]             irq_int_slot;
    wire [31:0]                           irq_cfg_rdata;

    // Clock generation (100 MHz)
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // Simple flattened index helper for tile_int_req
    function automatic int int_idx(input int slot, input int ch);
        int_idx = slot*NUM_TILE_INT_CH + ch;
    endfunction

    // Config write helper for addr_decoder (byte-wide)
    task automatic cfg_write(input [7:0] a, input [7:0] d);
    begin
        @(posedge cfg_clk);
        cfg_addr  <= a;
        cfg_wdata <= d;
        cfg_we    <= 1'b1;
        @(posedge cfg_clk);
        cfg_we    <= 1'b0;
    end
    endtask

    // Program window0 to map all I/O to a chosen slot
    task automatic program_window0_to_slot(input [2:0] slot_id);
        int b;
        reg [31:0] base_val;
        reg [31:0] mask_val;
    begin
        base_val = 32'h0000_0000;
        mask_val = 32'h0000_0000;
        for (b = 0; b < CFG_BYTES; b = b + 1) begin
            cfg_write(BASE_OFF + b, base_val[8*b +: 8]);
            cfg_write(MASK_OFF + b, mask_val[8*b +: 8]);
        end
        cfg_write(SLOT_OFF, {5'b00000, slot_id});
        cfg_write(OP_OFF, 8'hFF);
    end
    endtask

    // Program a maskable INT route entry in irq_router
    task automatic program_irq_route(input int slot, input int ch, input bit enable, input int cpu_idx);
        byte entry;
        byte addr_sel;
    begin
        entry    = (enable ? 8'h80 : 8'h00) | (cpu_idx[3:0]);
        addr_sel = slot*NUM_TILE_INT_CH + ch;

        @(posedge cfg_clk);
        irq_cfg_addr  <= addr_sel[IRQ_CFG_AW-1:0];
        irq_cfg_wdata <= {24'h0, entry};
        irq_cfg_wr_en <= 1'b1;
        @(posedge cfg_clk);
        irq_cfg_wr_en <= 1'b0;
    end
    endtask

    // Perform one I/O read cycle, optionally tagged as a vector read
    task automatic io_read_cycle(
        input  [ADDR_W-1:0]           A,
        input                         vec_cycle,
        output logic [NUM_SLOTS-1:0]  cs_n_sample,
        output logic [2:0]            sel_slot_sample
    );
    begin
        @(posedge clk);
        addr          <= A;
        r_w_          <= 1'b1;
        iorq_n        <= 1'b0;
        irq_vec_cycle <= vec_cycle;

        // Allow FSM to enter active phase and assert CS
        @(posedge clk);
        @(posedge clk);
        cs_n_sample     = cs_n;
        sel_slot_sample = sel_slot;

        // End the cycle
        @(posedge clk);
        iorq_n        <= 1'b1;
        irq_vec_cycle <= 1'b0;
        addr          <= '0;
    end
    endtask

    // DUTs
    addr_decoder #(
        .ADDR_W   (ADDR_W),
        .NUM_WIN  (NUM_WIN),
        .NUM_SLOTS(NUM_SLOTS)
    ) u_addr_decoder (
        .addr          (addr),
        .iorq_n        (iorq_n),
        .clk           (clk),
        .rst_n         (rst_n),
        .r_w_          (r_w_),
        .dev_ready_n   (dev_ready_n),
        .irq_int_active(irq_int_active),
        .irq_int_slot  (irq_int_slot),
        .irq_vec_cycle (irq_vec_cycle),
        .cfg_clk       (cfg_clk),
        .cfg_we        (cfg_we),
        .cfg_addr      (cfg_addr),
        .cfg_wdata     (cfg_wdata),
        .ready_n       (ready_n),
        .io_r_w_       (io_r_w_),
        .data_oe_n     (data_oe_n),
        .data_dir      (data_dir),
        .ff_oe_n       (ff_oe_n),
        .win_valid     (win_valid),
        .win_index     (win_index),
        .sel_slot      (sel_slot),
        .cs_n          (cs_n)
    );

    irq_router #(
        .NUM_SLOTS       (NUM_SLOTS),
        .NUM_CPU_INT     (NUM_CPU_INT),
        .NUM_CPU_NMI     (NUM_CPU_NMI),
        .NUM_TILE_INT_CH (NUM_TILE_INT_CH),
        .CFG_ADDR_WIDTH  (IRQ_CFG_AW)
    ) u_irq_router (
        .clk           (clk),
        .rst_n         (rst_n),
        .cfg_clk       (cfg_clk),
        .tile_int_req  (tile_int_req),
        .tile_nmi_req  (tile_nmi_req),
        .irq_ack       (irq_ack),
        .cpu_int       (cpu_int),
        .cpu_nmi       (cpu_nmi),
        .slot_ack      (slot_ack),
        .irq_int_active(irq_int_active),
        .irq_int_slot  (irq_int_slot),
        .cfg_wr_en     (irq_cfg_wr_en),
        .cfg_rd_en     (irq_cfg_rd_en),
        .cfg_addr      (irq_cfg_addr),
        .cfg_wdata     (irq_cfg_wdata),
        .cfg_rdata     (irq_cfg_rdata)
    );

    // Main stimulus
    initial begin
        logic [NUM_SLOTS-1:0] cs_n_sample;
        logic [2:0]           sel_slot_sample;

        addr          = '0;
        iorq_n        = 1'b1;
        r_w_          = 1'b1;
        irq_vec_cycle = 1'b0;
        dev_ready_n   = {NUM_SLOTS{1'b1}};
        tile_int_req  = '0;
        tile_nmi_req  = '0;
        irq_ack       = 1'b0;
        cfg_we        = 1'b0;
        cfg_addr      = 8'h00;
        cfg_wdata     = 8'h00;
        irq_cfg_wr_en = 1'b0;
        irq_cfg_rd_en = 1'b0;
        irq_cfg_addr  = '0;
        irq_cfg_wdata = 32'h0000_0000;

        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);

        program_window0_to_slot(3'd1);

        // -----------------------------------------------------------------
        // Scenario A: baseline decode, no active INT
        // -----------------------------------------------------------------
        tile_int_req  = '0;
        tile_nmi_req  = '0;
        irq_vec_cycle = 1'b0;

        io_read_cycle(32'h1234_5678, 1'b0, cs_n_sample, sel_slot_sample);
        begin
            logic [NUM_SLOTS-1:0] exp_cs_n;
            exp_cs_n = {NUM_SLOTS{1'b1}};
            exp_cs_n[1] = 1'b0;
            if (cs_n_sample !== exp_cs_n || sel_slot_sample !== 3'd1) begin
                $display("FAIL Scenario A: cs_n=%b sel_slot=%0d exp_cs_n=%b exp_slot=1", cs_n_sample, sel_slot_sample, exp_cs_n);
                $fatal;
            end
        end

        // -----------------------------------------------------------------
        // Scenario B: vector read override to active slot (slot 2)
        // -----------------------------------------------------------------
        program_irq_route(2, 0, 1'b1, 0);
        tile_int_req[int_idx(2,0)] = 1'b1;
        repeat (3) @(posedge clk);
        if (!irq_int_active || irq_int_slot !== 2'd2) begin
            $display("FAIL Scenario B: irq_int_active=%b irq_int_slot=%0d (expected active=1 slot=2)", irq_int_active, irq_int_slot);
            $fatal;
        end

        io_read_cycle(32'h0000_0000, 1'b1, cs_n_sample, sel_slot_sample);
        begin
            logic [NUM_SLOTS-1:0] exp_cs_n;
            exp_cs_n = {NUM_SLOTS{1'b1}};
            exp_cs_n[2] = 1'b0;
            if (cs_n_sample !== exp_cs_n || sel_slot_sample !== 3'd2) begin
                $display("FAIL Scenario B: cs_n=%b sel_slot=%0d exp_cs_n=%b exp_slot=2", cs_n_sample, sel_slot_sample, exp_cs_n);
                $fatal;
            end
        end

        // -----------------------------------------------------------------
        // Scenario C: vector read when no active INT (should stay on slot 1)
        // -----------------------------------------------------------------
        tile_int_req[int_idx(2,0)] = 1'b0;
        repeat (3) @(posedge clk);
        if (irq_int_active !== 1'b0) begin
            $display("FAIL Scenario C: irq_int_active still high");
            $fatal;
        end

        io_read_cycle(32'hDEAD_BEEF, 1'b1, cs_n_sample, sel_slot_sample);
        begin
            logic [NUM_SLOTS-1:0] exp_cs_n;
            exp_cs_n = {NUM_SLOTS{1'b1}};
            exp_cs_n[1] = 1'b0;
            if (cs_n_sample !== exp_cs_n || sel_slot_sample !== 3'd1) begin
                $display("FAIL Scenario C: cs_n=%b sel_slot=%0d exp_cs_n=%b exp_slot=1", cs_n_sample, sel_slot_sample, exp_cs_n);
                $fatal;
            end
        end

        // -----------------------------------------------------------------
        // Scenario D: vector fetch asserts /CS even if address is unmapped
        // -----------------------------------------------------------------
        // Reprogram all windows to *not* match address 0x0000_0000.
        // Each window matches a single address far from zero.
        begin : remap_windows_away_from_zero
            int w, b;
            reg [31:0] base_val;
            reg [31:0] mask_val;
            for (w = 0; w < NUM_WIN; w = w + 1) begin
                base_val = 32'h1000_0000 + (w * 32'h100);
                mask_val = 32'hFFFF_FFFF; // exact match only
                for (b = 0; b < CFG_BYTES; b = b + 1) begin
                    cfg_write(BASE_OFF + w*CFG_BYTES + b, base_val[8*b +: 8]);
                    cfg_write(MASK_OFF + w*CFG_BYTES + b, mask_val[8*b +: 8]);
                end
                cfg_write(SLOT_OFF + w, {5'b0, 3'd0});
                cfg_write(OP_OFF + w, 8'hFF);
            end
        end

        // Make slot2 INT active again.
        tile_int_req[int_idx(2,0)] = 1'b1;
        repeat (3) @(posedge clk);
        if (!irq_int_active || irq_int_slot !== 2'd2) begin
            $display("FAIL Scenario D prep: irq_int_active=%b irq_int_slot=%0d (expected active=1 slot=2)", irq_int_active, irq_int_slot);
            $fatal;
        end

        // Vector fetch at address 0x0000_0000 should still assert cs for slot2.
        io_read_cycle(32'h0000_0000, 1'b1, cs_n_sample, sel_slot_sample);
        begin
            logic [NUM_SLOTS-1:0] exp_cs_n;
            exp_cs_n = {NUM_SLOTS{1'b1}};
            exp_cs_n[2] = 1'b0;
            if (cs_n_sample !== exp_cs_n || sel_slot_sample !== 3'd2) begin
                $display("FAIL Scenario D: cs_n=%b sel_slot=%0d exp_cs_n=%b exp_slot=2", cs_n_sample, sel_slot_sample, exp_cs_n);
                $fatal;
            end
        end

        $display("All addr_decoder + irq_router vector override tests PASSED.");
        $finish;
    end

endmodule
