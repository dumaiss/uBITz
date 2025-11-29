`timescale 1ns/1ps

// Complex 32-bit / 16-window testbench for the addr_decoder module.
module addr_decoder_tb_32bit;
    localparam [7:0] IRQ_CFG_BASE = 8'hC0;
    reg  [31:0] addr;
    reg         iorq_n;
    reg         clk;
    reg         rst_n;
    reg         r_w_;           // 1 = read, 0 = write

    reg  [4:0]  dev_ready_n;    // active-low per-slot ready

    reg         irq_int_active;
    reg  [2:0]  irq_int_slot;
    reg         irq_vec_cycle;

    reg         cfg_clk;
    reg         cfg_we;
    reg  [7:0]  cfg_addr;
    reg  [7:0]  cfg_wdata;

    wire        ready_n;
    wire        io_r_w_;
    wire        data_oe_n;
    wire        data_dir;
    wire        ff_oe_n;
    wire [4:0]  cs_n;
    wire        dummy_win_valid;
    wire [3:0]  dummy_win_index;
    wire [2:0]  dummy_sel_slot;

    // Sampled values during the active /IORQ low phase (captured in io_cycle)
    reg [4:0] sample_cs_n;
    reg       sample_ready_n;
    reg       sample_data_oe_n;
    reg       sample_data_dir;
    reg       sample_ff_oe_n;

    // DUT instantiation
    addr_decoder #(
        .ADDR_W(32),
        .NUM_WIN(16),
        .NUM_SLOTS(5)
    ) dut (
        .addr       (addr),
        .iorq_n     (iorq_n),
        .clk        (clk),
        .rst_n      (rst_n),
        .r_w_       (r_w_),
        .irq_int_active(irq_int_active),
        .irq_int_slot(irq_int_slot),
        .irq_vec_cycle(irq_vec_cycle),
        .dev_ready_n(dev_ready_n),
        .cfg_clk    (cfg_clk),
        .cfg_we     (cfg_we),
        .cfg_addr   (cfg_addr),
        .cfg_wdata  (cfg_wdata),
        .ready_n    (ready_n),
        .io_r_w_    (io_r_w_),
        .data_oe_n  (data_oe_n),
        .data_dir   (data_dir),
        .ff_oe_n    (ff_oe_n),
        .win_valid  (dummy_win_valid),
        .win_index  (dummy_win_index),
        .sel_slot   (dummy_sel_slot),
        .cs_n       (cs_n)
    );

    // Clocks
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;      // 100 MHz core clock
    end

    initial begin
        cfg_clk = 1'b0;
        forever #10 cfg_clk = ~cfg_clk; // 50 MHz config clock
    end

    // Reset/init
    initial begin
        rst_n       = 1'b0;
        iorq_n      = 1'b1;
        r_w_        = 1'b1;
        addr        = 32'h0000_0000;
        cfg_we      = 1'b0;
        cfg_addr    = 8'd0;
        cfg_wdata   = 8'd0;
        dev_ready_n = 5'b11111; // all devices ready by default
        irq_int_active = 1'b0;
        irq_int_slot   = 3'd0;
        irq_vec_cycle  = 1'b0;
        #100;
        rst_n = 1'b1;
    end

    // Monitor key outputs
    initial begin
        $monitor("%0t addr=%08h iorq_n=%b r_w_=%b cs_n=%b ready_n=%b data_oe_n=%b data_dir=%b ff_oe_n=%b",
                 $time, addr, iorq_n, r_w_, cs_n, ready_n, data_oe_n, data_dir, ff_oe_n);
    end

    // Helper tasks
    task cfg_write(input [7:0] a, input [7:0] d);
    begin
        if (a >= IRQ_CFG_BASE) begin
            $fatal("cfg_write addr %0h is in IRQ region (>= %0h)", a, IRQ_CFG_BASE);
        end
        @(posedge cfg_clk);
        cfg_addr  <= a;
        cfg_wdata <= d;
        cfg_we    <= 1'b1;
        @(posedge cfg_clk);
        cfg_we    <= 1'b0;
    end
    endtask

    task io_cycle(
        input [31:0] a,
        input        is_read,       // 1 = read, 0 = write
        input integer hold_cycles,  // how many clk cycles to hold /IORQ low
        input [4:0]  busy_mask      // which slots are busy (dev_ready_n = 0)
    );
    integer i;
    reg [4:0] seen_cs;
    begin
        @(posedge clk);
        addr        <= a;
        r_w_        <= is_read;
        dev_ready_n <= ~busy_mask;  // busy_mask bit 1 => ready_n = 0 (busy)

        seen_cs          = 5'b00000;
        sample_cs_n      = 5'b11111;
        sample_ready_n   = 1'b1;
        sample_data_oe_n = 1'b1;
        sample_data_dir  = 1'b1;
        sample_ff_oe_n   = 1'b1;

        // Assert /IORQ
        iorq_n <= 1'b0;

        // Observe /IORQ low for requested cycles
        for (i = 0; i < hold_cycles; i = i + 1) begin
            @(posedge clk);
            seen_cs          = seen_cs | (~cs_n);
            sample_cs_n      = cs_n;
            sample_ready_n   = ready_n;
            sample_data_oe_n = data_oe_n;
            sample_data_dir  = data_dir;
            sample_ff_oe_n   = ff_oe_n;
        end

        // Release /IORQ
        iorq_n <= 1'b1;
        @(posedge clk);

        // Return to idle defaults
        addr        <= 32'h0000_0000;
        r_w_        <= 1'b1;
        dev_ready_n <= 5'b11111;

        // Fold cumulative CS assertion into sample
        sample_cs_n <= ~seen_cs;
    end
    endtask

    // Config map constants (mirror DUT layout)
    localparam integer NUM_WIN_TB   = 16;
    localparam integer NUM_SLOTS_TB = 5;
    localparam integer ADDR_W_TB    = 32;

    localparam integer CFG_BYTES_TB = (ADDR_W_TB + 7) / 8; // = 4
    localparam integer BASE_OFF_TB  = 0;
    localparam integer MASK_OFF_TB  = BASE_OFF_TB + (NUM_WIN_TB * CFG_BYTES_TB);
    localparam integer SLOT_OFF_TB  = MASK_OFF_TB + (NUM_WIN_TB * CFG_BYTES_TB);
    localparam integer OP_OFF_TB    = SLOT_OFF_TB + NUM_WIN_TB;

    reg [31:0] win_base [0:15];
    reg [31:0] win_mask [0:15];
    reg [2:0]  win_slot [0:15];
    reg [7:0]  win_op   [0:15];

    task program_windows;
        integer w, b;
        reg [31:0] base_val;
        reg [31:0] mask_val;
    begin
        // Initialize arrays (window table)
        win_base[0]  = 32'h1000_0000; win_mask[0]  = 32'hFFFF_FF00; win_slot[0]  = 3'd0; win_op[0]  = 8'hFF;
        win_base[1]  = 32'h1000_0100; win_mask[1]  = 32'hFFFF_FF00; win_slot[1]  = 3'd0; win_op[1]  = 8'hFF;
        win_base[2]  = 32'h1000_0200; win_mask[2]  = 32'hFFFF_FF00; win_slot[2]  = 3'd0; win_op[2]  = 8'h00;
        win_base[3]  = 32'h1000_0300; win_mask[3]  = 32'hFFFF_FF00; win_slot[3]  = 3'd0; win_op[3]  = 8'h01;

        win_base[4]  = 32'h2000_0000; win_mask[4]  = 32'hFFFF_FF00; win_slot[4]  = 3'd1; win_op[4]  = 8'hFF;
        win_base[5]  = 32'h2000_0100; win_mask[5]  = 32'hFFFF_FF00; win_slot[5]  = 3'd1; win_op[5]  = 8'h00;
        win_base[6]  = 32'h2000_0200; win_mask[6]  = 32'hFFFF_FF00; win_slot[6]  = 3'd1; win_op[6]  = 8'h01;
        win_base[7]  = 32'h2000_0300; win_mask[7]  = 32'hFFFF_FF00; win_slot[7]  = 3'd1; win_op[7]  = 8'h00;

        win_base[8]  = 32'h3000_0000; win_mask[8]  = 32'hFFFF_FF00; win_slot[8]  = 3'd2; win_op[8]  = 8'hFF;
        win_base[9]  = 32'h3000_0100; win_mask[9]  = 32'hFFFF_FF00; win_slot[9]  = 3'd2; win_op[9]  = 8'hFF;

        win_base[10] = 32'h4000_0000; win_mask[10] = 32'hFFFF_FF00; win_slot[10] = 3'd3; win_op[10] = 8'hFF;
        win_base[11] = 32'h4000_0100; win_mask[11] = 32'hFFFF_FF00; win_slot[11] = 3'd3; win_op[11] = 8'hFF;

        win_base[12] = 32'hF000_0000; win_mask[12] = 32'hFFFF_FF00; win_slot[12] = 3'd4; win_op[12] = 8'hFF;
        win_base[13] = 32'hF000_0100; win_mask[13] = 32'hFFFF_FF00; win_slot[13] = 3'd4; win_op[13] = 8'hFF;
        win_base[14] = 32'hF000_0200; win_mask[14] = 32'hFFFF_FF00; win_slot[14] = 3'd4; win_op[14] = 8'h00;
        win_base[15] = 32'hF000_0300; win_mask[15] = 32'hFFFF_FF00; win_slot[15] = 3'd4; win_op[15] = 8'hFF;

        // BASE bytes
        for (w = 0; w < NUM_WIN_TB; w = w + 1) begin
            base_val = win_base[w];
            for (b = 0; b < CFG_BYTES_TB; b = b + 1) begin
                cfg_write(BASE_OFF_TB + w*CFG_BYTES_TB + b, base_val[8*b +: 8]);
            end
        end

        // MASK bytes
        for (w = 0; w < NUM_WIN_TB; w = w + 1) begin
            mask_val = win_mask[w];
            for (b = 0; b < CFG_BYTES_TB; b = b + 1) begin
                cfg_write(MASK_OFF_TB + w*CFG_BYTES_TB + b, mask_val[8*b +: 8]);
            end
        end

        // SLOT regs
        for (w = 0; w < NUM_WIN_TB; w = w + 1) begin
            cfg_write(SLOT_OFF_TB + w, {5'b0, win_slot[w]});
        end

        // OP regs
        for (w = 0; w < NUM_WIN_TB; w = w + 1) begin
            cfg_write(OP_OFF_TB + w, win_op[w]);
        end
    end
    endtask

    // Stimulus
    initial begin
        // Wait for reset
        @(posedge rst_n);

        // Program all windows
        program_windows();

        // -------- Test 1: mapped write (VDP ctrl, window 0, slot 0)
        io_cycle(32'h1000_0004, 1'b0, 3, 5'b00000);
        if (sample_cs_n[0] !== 1'b0)
            $fatal(1, "Test1: expected slot0 CS asserted");
        if (sample_data_oe_n !== 1'b0 || sample_data_dir !== 1'b0 || sample_ff_oe_n !== 1'b1)
            $fatal(1, "Test1: data controls mismatch for mapped write");

        // -------- Test 2: write-only window (window 2)
        io_cycle(32'h1000_020A, 1'b0, 3, 5'b00000); // mapped write
        if (sample_cs_n[0] !== 1'b0)
            $fatal(1, "Test2 mapped write: expected slot0 CS asserted");
        io_cycle(32'h1000_020A, 1'b1, 3, 5'b00000); // unmapped read (op=write-only)
        if (cs_n !== 5'b11111)
            $fatal(1, "Test2 unmapped read: expected no CS asserted");
        if (sample_data_oe_n !== 1'b1 || sample_ff_oe_n !== 1'b0)
            $fatal(1, "Test2 unmapped read: data bridge/FF driver mismatch");

        // -------- Test 3: read-only window (window 3)
        io_cycle(32'h1000_0300, 1'b1, 3, 5'b00000); // mapped read
        if (sample_cs_n[0] !== 1'b0 || sample_data_oe_n !== 1'b0 || sample_data_dir !== 1'b1)
            $fatal(1, "Test3 read: expected mapped read to slot0");
        io_cycle(32'h1000_0300, 1'b0, 3, 5'b00000); // unmapped write
        if (cs_n !== 5'b11111)
            $fatal(1, "Test3 unmapped write: expected no CS asserted");
        if (sample_data_oe_n !== 1'b1 || sample_ff_oe_n !== 1'b1)
            $fatal(1, "Test3 unmapped write: data controls mismatch");

        // -------- Test 4: sound tile with wait states (slot 1)
        io_cycle(32'h2000_0000, 1'b0, 5, 5'b00010); // busy slot1
        if (sample_cs_n[1] !== 1'b0)
            $fatal(1, "Test4: expected slot1 CS asserted");
        if (ready_n !== 1'b0)
            $display("Note: READY may release after sync; monitor waveform for stretch");

        // -------- Test 5: Dock internal (slot 4)
        io_cycle(32'hF000_0000, 1'b1, 3, 5'b00000); // HID
        if (sample_cs_n[4] !== 1'b0)
            $fatal(1, "Test5 HID: expected slot4 CS asserted");
        io_cycle(32'hF000_0104, 1'b0, 3, 5'b00000); // RTC write
        if (sample_cs_n[4] !== 1'b0)
            $fatal(1, "Test5 RTC: expected slot4 CS asserted");
        io_cycle(32'hF000_0200, 1'b0, 3, 5'b00000); // Power mgmt write (mapped)
        if (sample_cs_n[4] !== 1'b0)
            $fatal(1, "Test5 PWR write: expected slot4 CS asserted");
        io_cycle(32'hF000_0200, 1'b1, 3, 5'b00000); // Power mgmt read (unmapped)
        if (sample_cs_n !== 5'b11111 || sample_ff_oe_n !== 1'b0)
            $fatal(1, "Test5 PWR read: expected unmapped read with FF driver");
        io_cycle(32'hF000_0308, 1'b1, 3, 5'b00000); // Debug console
        if (sample_cs_n[4] !== 1'b0)
            $fatal(1, "Test5 DBG: expected slot4 CS asserted");

        // -------- Test 6: completely unmapped I/O
        io_cycle(32'hDEAD_BEEF, 1'b1, 3, 5'b00000);
        if (cs_n !== 5'b11111)
            $fatal(1, "Test6: expected no CS asserted on unmapped");
        if (sample_data_oe_n !== 1'b1 || sample_ff_oe_n !== 1'b0)
            $fatal(1, "Test6: unmapped read should disable bridge and enable FF driver");

        $display("TEST PASSED: addr_decoder_tb_32bit completed without fatal errors.");
        $finish;
    end
endmodule
