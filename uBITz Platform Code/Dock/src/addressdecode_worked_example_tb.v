`timescale 1ns/1ps

// Behavioral testbench for the addressdecode module.
module tb_addressdecode;
    reg  [7:0] addr;
    reg        iorq_n;
    reg        clk;
    reg        rst_n;
    reg        r_w_;

    reg  [4:0] dev_ready_n;

    reg        cfg_clk;
    reg        cfg_we;
    reg  [7:0] cfg_addr;
    reg  [7:0] cfg_wdata;

    wire       ready_n;
    wire       io_r_w_;

    wire       data_oe_n;
    wire       data_dir;
    wire       ff_oe_n;

    wire       win_valid;
    wire [3:0] win_index;
    wire [2:0] sel_slot;
    wire [4:0] cs_n;

    // DUT instantiation
    addressdecode #(
        .ADDR_W(8),
        .NUM_WIN(4),
        .NUM_SLOTS(5)
    ) dut (
        .addr(addr),
        .iorq_n(iorq_n),
        .clk(clk),
        .rst_n(rst_n),
        .r_w_(r_w_),
        .dev_ready_n(dev_ready_n),
        .cfg_clk(cfg_clk),
        .cfg_we(cfg_we),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .ready_n(ready_n),
        .io_r_w_(io_r_w_),
        .data_oe_n(data_oe_n),
        .data_dir(data_dir),
        .ff_oe_n(ff_oe_n),
        .win_valid(win_valid),
        .win_index(win_index),
        .sel_slot(sel_slot),
        .cs_n(cs_n)
    );

    // Clocks
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;      // 100 MHz
    end

    initial begin
        cfg_clk = 1'b0;
        forever #7 cfg_clk = ~cfg_clk; // config clock
    end

    // Reset/init
    initial begin
        rst_n       = 1'b0;
        iorq_n      = 1'b1;
        r_w_        = 1'b1;
        addr        = 8'h00;
        cfg_we      = 1'b0;
        cfg_addr    = 6'd0;
        cfg_wdata   = 8'd0;
        dev_ready_n = 5'b11111;
        #50;
        rst_n = 1'b1;
    end

    // Optional monitor
    initial begin
        $monitor("%t addr=%h iorq_n=%b r_w_=%b win_valid=%b win_index=%0d sel_slot=%0d cs_n=%b ready_n=%b data_oe_n=%b data_dir=%b ff_oe_n=%b",
                 $time, addr, iorq_n, r_w_, win_valid, win_index, sel_slot, cs_n, ready_n, data_oe_n, data_dir, ff_oe_n);
    end

    // Tasks
    task cfg_write(input [7:0] a, input [7:0] d);
    begin
        @(posedge cfg_clk);
        cfg_addr  <= a;
        cfg_wdata <= d;
        cfg_we    <= 1'b1;
        @(posedge cfg_clk);
        cfg_we    <= 1'b0;
    end
    endtask

    task io_write(input [7:0] a);
    begin
        @(posedge clk);
        addr   <= a;
        r_w_   <= 1'b0;   // write
        iorq_n <= 1'b1;
        @(posedge clk);
        iorq_n <= 1'b0;   // assert /IORQ
        @(posedge clk);
        iorq_n <= 1'b1;   // deassert /IORQ
        @(posedge clk);
    end
    endtask

    task io_read(input [7:0] a);
    begin
        @(posedge clk);
        addr   <= a;
        r_w_   <= 1'b1;   // read
        iorq_n <= 1'b1;
        @(posedge clk);
        iorq_n <= 1'b0;   // assert /IORQ
        @(posedge clk);
        iorq_n <= 1'b1;   // deassert /IORQ
        @(posedge clk);
    end
    endtask

    // Main stimulus
    initial begin : stimulus
        // Wait for reset release
        @(posedge rst_n);

        // Configure windows for ADDR_W=8 layout
        cfg_write(6'h00, 8'h10); // base[0]
        cfg_write(6'h04, 8'hFF); // mask[0]
        cfg_write(6'h08, 8'h00); // slot[0]
        cfg_write(6'h0C, 8'hFF); // op[0] any

        cfg_write(6'h01, 8'h20); // base[1]
        cfg_write(6'h05, 8'hF0); // mask[1]
        cfg_write(6'h09, 8'h01); // slot[1]
        cfg_write(6'h0D, 8'h00); // op[1] write-only

        cfg_write(6'h02, 8'h30); // base[2]
        cfg_write(6'h06, 8'hF0); // mask[2]
        cfg_write(6'h0A, 8'h01); // slot[2]
        cfg_write(6'h0E, 8'h01); // op[2] read-only

        // Tame window3 so it doesn't act as a catch-all for this test.
        cfg_write(6'h07, 8'hFF); // mask[3] = 0xFF
        cfg_write(6'h0B, 8'h00); // slot[3] = 0
        cfg_write(6'h0F, 8'hFF); // op[3] = any (address must match base)

        // -------- Test 1: mapped UART write (0x10 -> slot 0)
        dev_ready_n = 5'b11111;
        @(posedge clk);
        addr   <= 8'h10;
        r_w_   <= 1'b0;
        iorq_n <= 1'b1;
        @(posedge clk);
        iorq_n <= 1'b0; // assert /IORQ
        @(posedge clk);
        #1;
        if (!win_valid || win_index !== 2'd0 || sel_slot !== 3'd0)
            $fatal(1, "UART window decode failed for addr 0x10");
        if (cs_n[0] !== 1'b0)
            $fatal(1, "CS_n[0] should assert during UART write");
        if (data_oe_n !== 1'b0 || data_dir !== 1'b0 || ff_oe_n !== 1'b1)
            $fatal(1, "Data control signals incorrect for mapped UART write");
        @(posedge clk);
        iorq_n <= 1'b1;
        @(posedge clk);

        // -------- Test 2: mapped VDP status read with wait-state stretching
        dev_ready_n = 5'b11111;
        @(posedge clk);
        dev_ready_n[1] = 1'b0; // slot 1 busy
        addr   <= 8'h31;
        r_w_   <= 1'b1;
        iorq_n <= 1'b1;
        @(posedge clk);
        iorq_n <= 1'b0; // start I/O
        // hold busy for a few cycles
        repeat (3) begin
            @(posedge clk);
            #1;
            if (cs_n[1] !== 1'b0)
                $fatal(1, "CS_n[1] must stay asserted for active VDP slot");
            if (ready_n !== 1'b0)
                $fatal(1, "READY should be low while VDP (slot 1) is busy");
            if (data_oe_n !== 1'b0 || data_dir !== 1'b1 || ff_oe_n !== 1'b1)
                $fatal(1, "Data control incorrect during VDP busy read");
        end
        // mark ready and expect READY to release
        dev_ready_n[1] = 1'b1;
        begin : wait_ready
            integer k;
            reg ready_seen;
            ready_seen = 1'b0;
            for (k = 0; k < 5; k = k + 1) begin
                @(posedge clk);
                #1;
                if (ready_n === 1'b1) begin
                    ready_seen = 1'b1;
                    disable wait_ready;
                end
            end
            if (!ready_seen)
                $fatal(1, "READY must be released when VDP reports ready");
        end
        if (cs_n[1] !== 1'b0)
            $fatal(1, "CS_n[1] should remain active until /IORQ deasserts");
        // Finish the cycle
        @(posedge clk);
        iorq_n <= 1'b1;
        begin : wait_cs_deassert
            integer m;
            reg deasserted;
            deasserted = 1'b0;
            for (m = 0; m < 4; m = m + 1) begin
                @(posedge clk);
                #1;
                if (cs_n[1] === 1'b1) begin
                    deasserted = 1'b1;
                    disable wait_cs_deassert;
                end
            end
            if (!deasserted)
                $fatal(1, "CS_n[1] should deassert after /IORQ high");
        end

        // -------- Test 3: unmapped read (0x77 -> 0xFF driver)
        dev_ready_n = 5'b11111;
        @(posedge clk);
        addr   <= 8'h77;
        r_w_   <= 1'b1;
        iorq_n <= 1'b1;
        @(posedge clk);
        iorq_n <= 1'b0; // assert /IORQ
        @(posedge clk);
        #1;
        if (win_valid)
            $fatal(1, "Unmapped address 0x77 should not hit any window");
        if (data_oe_n !== 1'b1 || ff_oe_n !== 1'b0)
            $fatal(1, "Unmapped read should disable data bridge and enable 0xFF driver");
        if (ready_n !== 1'b1)
            $fatal(1, "READY should not be pulled low on unmapped read");
        @(posedge clk);
        iorq_n <= 1'b1;
        @(posedge clk);

        $display("All addressdecode tests completed without fatal errors.");
        $finish;
    end
endmodule
