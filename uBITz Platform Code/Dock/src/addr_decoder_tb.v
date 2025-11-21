// Simple testbench for addr_decoder: exercises masking, priority, and gating.

`timescale 1ns/1ps

module addr_decoder_tb;
    reg        clk;
    reg  [7:0] addr;
    reg        iorq_n;
    reg        rst_n;
    reg        r_w_;

    reg        cfg_clk;
    reg        cfg_we;
    reg  [7:0] cfg_addr;
    reg  [7:0] cfg_wdata;

    wire [4:0] cs_n;
    wire [4:0] cs = ~cs_n; // derived active-high view for checks
    wire       win_valid;
    wire [3:0] win_index;
    wire [2:0] sel_slot;
    wire       ready_n;
    wire       io_r_w_;
    wire       data_oe_n;
    wire       data_dir;
    wire       ff_oe_n;
    reg  [4:0] dev_ready_n;

    // Simple cfg write helper.
    task cfg_write;
        input [7:0] t_addr;
        input [7:0] t_data;
        begin
            cfg_addr  = t_addr;
            cfg_wdata = t_data;
            cfg_we    <= 1'b1;
            @(posedge cfg_clk);
            cfg_we    <= 1'b0;
            @(posedge cfg_clk);
        end
    endtask

    // Check expected cs for a given address and iorq_n.
    task check_cs;
        input [7:0] t_addr;
        input       t_iorq_n;
        input [4:0] exp_cs;
        begin
            addr   = t_addr;
            iorq_n = t_iorq_n;
            @(posedge clk);
            #1;

            if (io_r_w_ !== 1'b1) begin
                $display("FAIL: addr=%02h qualifier inactive expects io_r_w_=1 got %b", addr, io_r_w_);
                $fatal;
            end

            if (cs !== exp_cs) begin
                $display("FAIL: addr=%02h iorq_n=%b cs=%05b exp=%05b (win_valid=%b idx=%0d slot=%0d)",
                         addr, iorq_n, cs, exp_cs, win_valid, win_index, sel_slot);
                $fatal;
            end

            if (cs_n !== ~exp_cs) begin
                $display("FAIL: addr=%02h cs_n mismatch cs_n=%05b exp=%05b", addr, cs_n, ~exp_cs);
                $fatal;
            end
        end
    endtask

    // Run a single I/O cycle and verify cs/ready_n sequencing.
    task run_io_cycle;
        input [7:0] t_addr;
        input       t_read;   // 1 = read, 0 = write
        input [4:0] exp_cs;
        input integer max_wait_cycles;
        integer i;
        reg ready_seen;
        reg exp_r_w_;
        begin
            addr   = t_addr;
            r_w_   = t_read;
            iorq_n = 1'b1;
            @(posedge clk);

            exp_r_w_ = t_read;

            // Assert IORQ low to start the cycle (provide setup before clk edge).
            @(negedge clk);
            iorq_n = 1'b0;
            @(posedge clk); // entry to ACTIVE after setup
            #1;
            if (cs !== exp_cs || ready_n !== 1'b0 || io_r_w_ !== exp_r_w_) begin
                $display("FAIL entry: addr=%02h iorq_n=%b cs=%05b exp=%05b ready_n=%b io_r_w_=%b (exp %b) win_valid=%b idx=%0d slot=%0d",
                         addr, iorq_n, cs, exp_cs, ready_n, io_r_w_, exp_r_w_,
                         win_valid, win_index, sel_slot);
                $fatal;
            end
            if (cs_n !== ~exp_cs) begin
                $display("FAIL entry cs_n: addr=%02h cs_n=%05b exp=%05b", addr, cs_n, ~exp_cs);
                $fatal;
            end

            ready_seen = 1'b0;
            begin : wait_loop
                for (i = 0; i < max_wait_cycles; i = i + 1) begin
                    @(posedge clk);
                    #1;
                    if (cs !== exp_cs || io_r_w_ !== exp_r_w_) begin
                        $display("FAIL active: addr=%02h iorq_n=%b cs=%05b exp=%05b ready_n=%b io_r_w_=%b (exp %b)",
                                 addr, iorq_n, cs, exp_cs, ready_n, io_r_w_, exp_r_w_);
                        $fatal;
                    end
                    if (cs_n !== ~exp_cs) begin
                        $display("FAIL active cs_n: addr=%02h cs_n=%05b exp=%05b", addr, cs_n, ~exp_cs);
                        $fatal;
                    end
                    if (ready_n === 1'b1) begin
                        ready_seen = 1'b1;
                        disable wait_loop;
                    end else if (ready_n !== 1'b0) begin
                        $display("FAIL active ready_n unknown: addr=%02h ready_n=%b", addr, ready_n);
                        $fatal;
                    end
                end
            end

            if (!ready_seen) begin
                $display("FAIL: addr=%02h did not see ready_n asserted within %0d cycles", addr, max_wait_cycles);
                $fatal;
            end

            // End the cycle.
            @(negedge clk);
            iorq_n = 1'b1;
            @(posedge clk);
            #1;
            if (cs !== 5'b00000 || ready_n !== 1'b1 || io_r_w_ !== 1'b1) begin
                $display("FAIL tail: addr=%02h cs=%05b ready_n=%b io_r_w_=%b", addr, cs, ready_n, io_r_w_);
                $fatal;
            end
            if (cs_n !== ~5'b00000) begin
                $display("FAIL tail cs_n: addr=%02h cs_n=%05b exp=%05b", addr, cs_n, ~5'b00000);
                $fatal;
            end
        end
    endtask

    addr_decoder #(
        .ADDR_W(8),
        .NUM_WIN(4),
        .NUM_SLOTS(5)
    ) dut (
        .clk(clk),
        .addr(addr),
        .iorq_n(iorq_n),
        .rst_n(rst_n),
        .r_w_(r_w_),
        .cfg_clk(cfg_clk),
        .cfg_we(cfg_we),
        .cfg_addr(cfg_addr),
        .cfg_wdata(cfg_wdata),
        .cs_n(cs_n),
        .ready_n(ready_n), .io_r_w_(io_r_w_),
        .data_oe_n(data_oe_n), .data_dir(data_dir), .ff_oe_n(ff_oe_n),
        .dev_ready_n(dev_ready_n),
        .win_valid(win_valid), .win_index(win_index), .sel_slot(sel_slot)
    );

    initial begin
        // Waveform dump for GTKWave.
        $dumpfile("addr_decoder_tb.vcd");
        $dumpvars(0, addr_decoder_tb);

        clk      = 1'b0;
        cfg_clk  = 1'b0;
        cfg_we   = 1'b0;
        cfg_addr = 6'h00;
        cfg_wdata = 8'h00;
        addr     = 8'h00;
        iorq_n   = 1'b1;
        rst_n    = 1'b0;
        r_w_     = 1'b1; // default to read
        dev_ready_n = 5'b11111; // default: all devices ready

        // Default programmed windows via config bus.
        cfg_write(6'h00, 8'h10); cfg_write(6'h04, 8'hF0); cfg_write(6'h08, {5'b00000, 3'd1}); // slot_0 => cs[1]
        cfg_write(6'h01, 8'h20); cfg_write(6'h05, 8'hF0); cfg_write(6'h09, {5'b00000, 3'd2}); // slot_1 => cs[2]
        cfg_write(6'h02, 8'h30); cfg_write(6'h06, 8'hF0); cfg_write(6'h0A, {5'b00000, 3'd3}); // slot_2 => cs[3]
        cfg_write(6'h03, 8'h00); cfg_write(6'h07, 8'h00); cfg_write(6'h0B, {5'b00000, 3'd4}); // catch-all => cs[4]
        // Program op_0 as read-only to test op gating later.
        cfg_write(6'h0C, 8'h01);

        // Release reset after a couple of clocks.
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        // No match when qualifier inactive (/IORQ high).
        check_cs(8'h10, 1'b1, 5'b00000);

        // Base window hits (qualified).
        run_io_cycle(8'h10, 1'b1, 5'b00010, 4); // slot_0 => cs[1], read
        run_io_cycle(8'h23, 1'b1, 5'b00100, 4); // slot_1 => cs[2]
        run_io_cycle(8'h3F, 1'b1, 5'b01000, 4); // slot_2 => cs[3]

        // Catch-all window when none of the above match.
        run_io_cycle(8'h70, 1'b1, 5'b10000, 4); // slot_3 => cs[4]

        // Priority: make window1 overlap window0 and ensure window0 wins.
        cfg_write(6'h01, 8'h10); cfg_write(6'h05, 8'hF0); cfg_write(6'h09, {5'b00000, 3'd0}); // now same range
        run_io_cycle(8'h12, 1'b1, 5'b00010, 4); // still chooses window0 (slot_0)

        // Restore window1 to its original range to avoid overlap in later checks.
        cfg_write(6'h01, 8'h20); cfg_write(6'h05, 8'hF0); cfg_write(6'h09, {5'b00000, 3'd2});

        // Op gating: slot_0 is read-only (op_0 = 0x01). Write should fall through to catch-all.
        run_io_cycle(8'h10, 1'b0, 5'b10000, 4); // write -> catch-all (slot_3)
        run_io_cycle(8'h10, 1'b1, 5'b00010, 4); // read -> slot_0 hit

        // Wait-state stretching: hold device not ready for one extra cycle on slot_1.
        dev_ready_n[1] = 1'b0; // slot_1 not ready
        fork
            begin
                // After two clk edges, mark ready.
                repeat (2) @(posedge clk);
                dev_ready_n[1] = 1'b1;
            end
            begin
                run_io_cycle(8'h23, 1'b1, 5'b00100, 8); // slot_1 => cs[2], should stretch
            end
        join
        dev_ready_n[1] = 1'b1;

        $display("All addr_decoder tests passed.");
        $finish;
    end

    // Main clocks.
    always #5 cfg_clk = ~cfg_clk;
    always #4 clk = ~clk;
endmodule
