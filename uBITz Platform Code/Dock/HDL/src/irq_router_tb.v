`timescale 1ns/1ps

// Directed tests for irq_router pending semantics and routing.
module irq_router_tb;
    localparam int NUM_SLOTS       = 3;
    localparam int NUM_CPU_INT     = 2;
    localparam int NUM_CPU_NMI     = 1;
    localparam int NUM_TILE_INT_CH = 2;
    localparam int SLOT_IDX_WIDTH  = (NUM_SLOTS <= 1) ? 1 : $clog2(NUM_SLOTS);

    logic clk, rst_n;
    logic [NUM_SLOTS*NUM_TILE_INT_CH-1:0] tile_int_req;
    logic [NUM_SLOTS-1:0]                 tile_nmi_req;
    logic                                 irq_ack;
    logic [NUM_CPU_INT-1:0]               cpu_int;
    logic [NUM_CPU_NMI-1:0]               cpu_nmi;
    logic [NUM_SLOTS-1:0]                 slot_ack;
    logic                                 irq_int_active;
    logic [SLOT_IDX_WIDTH-1:0]            irq_int_slot;
    logic                                 cfg_wr_en;
    logic [7:0]                           cfg_addr;
    logic [7:0]                           cfg_wdata;

    // Device under test
    irq_router #(
        .NUM_SLOTS       (NUM_SLOTS),
        .NUM_CPU_INT     (NUM_CPU_INT),
        .NUM_CPU_NMI     (NUM_CPU_NMI),
        .NUM_TILE_INT_CH (NUM_TILE_INT_CH),
        .CFG_ADDR_WIDTH  (8)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cfg_clk    (clk),
        .tile_int_req(tile_int_req),
        .tile_nmi_req(tile_nmi_req),
        .irq_ack    (irq_ack),
        .cpu_int    (cpu_int),
        .cpu_nmi    (cpu_nmi),
        .slot_ack   (slot_ack),
        .irq_int_active(irq_int_active),
        .irq_int_slot(irq_int_slot),
        .cfg_wr_en  (cfg_wr_en),
        .cfg_rd_en  (1'b0),
        .cfg_addr   (cfg_addr),
        .cfg_wdata  (cfg_wdata)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100 MHz
    end

    // Reset and defaults
    initial begin
        rst_n       = 0;
        cfg_wr_en   = 0;
        irq_ack     = 0;
        cfg_addr    = 0;
        cfg_wdata   = 0;
        tile_int_req = '0;
        tile_nmi_req = '0;
        repeat (5) @(posedge clk);
        rst_n = 1;
    end

    // Helper: flattened index for maskable ints
    function automatic int int_idx(input int slot, input int ch);
        int_idx = slot*NUM_TILE_INT_CH + ch;
    endfunction

    // Config helpers
    task automatic cfg_write(input byte addr, input byte data);
    begin
        @(posedge clk);
        cfg_addr  <= addr;
        cfg_wdata <= data;
        cfg_wr_en <= 1;
        @(posedge clk);
        cfg_wr_en <= 0;
    end
    endtask

    task automatic route_int(input int slot, input int ch, input bit enable, input int cpu_idx);
        byte entry;
    begin
        entry = (enable ? 8'h80 : 8'h00) | (cpu_idx[3:0]);
        cfg_write(slot*NUM_TILE_INT_CH + ch, entry);
    end
    endtask

    task automatic route_nmi(input int slot, input bit enable, input int cpu_idx);
        byte entry;
    begin
        entry = (enable ? 8'h80 : 8'h00) | (cpu_idx[3:0]);
        cfg_write(NUM_SLOTS*NUM_TILE_INT_CH + slot, entry);
    end
    endtask

    task automatic pulse_irq_ack;
    begin
        @(posedge clk);
        irq_ack <= 1;
        @(posedge clk);
        irq_ack <= 0;
    end
    endtask

    // Stimulus
    initial begin : tests
        // Wait for reset release
        @(posedge rst_n);
        @(posedge clk);

        // Test 0: reset defaults
        if (cpu_int !== '0 || cpu_nmi !== '0 || slot_ack !== '0) begin
            $fatal(1, "Test0 fail: outputs not idle after reset cpu_int=%b cpu_nmi=%b slot_ack=%b", cpu_int, cpu_nmi, slot_ack);
        end

        // Test 1: basic INT route and deassert
        route_int(0, 0, 1, 0);
        tile_int_req = '0;
        tile_nmi_req = '0;
        @(posedge clk);
        tile_int_req[int_idx(0,0)] <= 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b01 || cpu_nmi !== '0)
            $fatal(1, "Test1 fail: cpu_int=%b cpu_nmi=%b", cpu_int, cpu_nmi);
        tile_int_req[int_idx(0,0)] <= 1'b0;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b00)
            $fatal(1, "Test1 fail: cpu_int did not clear");

        // Test 2: no queuing
        route_int(1, 0, 1, 1);
        tile_int_req = '0;
        @(posedge clk);
        tile_int_req[int_idx(0,0)] <= 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b01) $fatal(1, "Test2 fail: expected INT0 active");
        // pulse slot1,ch0 while slot0 active
        tile_int_req[int_idx(1,0)] <= 1'b1;
        @(posedge clk);
        tile_int_req[int_idx(1,0)] <= 1'b0;
        @(posedge clk);
        tile_int_req[int_idx(0,0)] <= 1'b0; // clear active
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b00)
            $fatal(1, "Test2 fail: queued INT appeared cpu_int=%b", cpu_int);

        // Test 3: unrouted ignored
        route_int(1, 0, 0, 0); // disable slot1,ch0
        tile_int_req = '0;
        tile_int_req[int_idx(1,0)] <= 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b00 || slot_ack !== '0)
            $fatal(1, "Test3 fail: unrouted IRQ affected outputs cpu_int=%b slot_ack=%b", cpu_int, slot_ack);
        // ensure routing not blocked
        route_int(0, 0, 1, 0);
        tile_int_req[int_idx(0,0)] <= 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b01)
            $fatal(1, "Test3 fail: routed IRQ did not assert after unrouted");
        tile_int_req[int_idx(0,0)] <= 1'b0;
        tile_int_req[int_idx(1,0)] <= 1'b0;
        @(posedge clk);

        // Test 4: NMI priority over INT
        route_nmi(1, 1, 0);
        tile_int_req = '0;
        tile_nmi_req = '0;
        route_int(0, 0, 1, 0);
        tile_int_req[int_idx(0,0)] <= 1'b1;
        tile_nmi_req[1]            <= 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_nmi !== 1'b1 || cpu_int !== 2'b00)
            $fatal(1, "Test4 fail: NMI not prioritized cpu_int=%b cpu_nmi=%b", cpu_int, cpu_nmi);
        tile_nmi_req[1] <= 1'b0;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b01)
            $fatal(1, "Test4 fail: INT not promoted after NMI cleared cpu_int=%b", cpu_int);
        tile_int_req[int_idx(0,0)] <= 1'b0;
        @(posedge clk);

        // Test 5: only one active at a time, two INTs
        route_int(1, 0, 1, 1);
        tile_int_req[int_idx(0,0)] <= 1'b1;
        tile_int_req[int_idx(1,0)] <= 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b01)
            $fatal(1, "Test5 fail: expected slot0 first cpu_int=%b", cpu_int);
        tile_int_req[int_idx(0,0)] <= 1'b0;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b10)
            $fatal(1, "Test5 fail: expected slot1 promoted cpu_int=%b", cpu_int);
        tile_int_req[int_idx(1,0)] <= 1'b0;
        @(posedge clk);

        // Test 6: ack routing and does not clear
        tile_int_req = '0;
        route_int(0, 0, 1, 0);
        tile_int_req[int_idx(0,0)] <= 1'b1;
        repeat (2) @(posedge clk);
        pulse_irq_ack();
        if (slot_ack !== 3'b001)
            $fatal(1, "Test6 fail: slot_ack=%b expected pulse on slot0", slot_ack);
        if (cpu_int !== 2'b01)
            $fatal(1, "Test6 fail: cpu_int cleared after ack cpu_int=%b", cpu_int);
        tile_int_req[int_idx(0,0)] <= 1'b0;
        repeat (2) @(posedge clk);

        // Test 7: ack when idle
        pulse_irq_ack();
        if (slot_ack !== 3'b000)
            $fatal(1, "Test7 fail: slot_ack pulsed while idle slot_ack=%b", slot_ack);

        // Test 8: reconfig disable while pending but not active
        // Keep slot0 active to block selection.
        route_int(0, 0, 1, 0);
        route_int(1, 0, 1, 1);
        tile_int_req[int_idx(0,0)] <= 1'b1;
        @(posedge clk); // slot0 active
        tile_int_req[int_idx(1,0)] <= 1'b1; // pending slot1
        @(posedge clk);
        // Disable slot1 before slot0 clears
        route_int(1, 0, 0, 0);
        @(posedge clk);
        tile_int_req[int_idx(0,0)] <= 1'b0; // clear active
        tile_int_req[int_idx(1,0)] <= 1'b0;
        repeat (3) @(posedge clk);
        if (cpu_int !== 2'b00)
            $fatal(1, "Test8 fail: disabled pending IRQ became active cpu_int=%b", cpu_int);
        tile_int_req = '0;
        tile_nmi_req = '0;
        @(posedge clk);

        // Test 9: out-of-range CPU index should not drive pins but still ack/block
        route_int(0, 0, 1, 3); // idx=3 out of range (NUM_CPU_INT=2)
        tile_int_req[int_idx(0,0)] <= 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b00)
            $fatal(1, "Test9 fail: out-of-range route drove cpu_int=%b", cpu_int);
        pulse_irq_ack();
        if (slot_ack !== 3'b001)
            $fatal(1, "Test9 fail: slot_ack not pulsed for active out-of-range irq slot_ack=%b", slot_ack);
        tile_int_req[int_idx(0,0)] <= 1'b0;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b00)
            $fatal(1, "Test9 fail: cpu_int not zero after clearing out-of-range route cpu_int=%b", cpu_int);

        $display("All irq_router tests passed.");
        $finish;
    end

endmodule
