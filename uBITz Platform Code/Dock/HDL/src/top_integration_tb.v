`timescale 1ns/1ps

// Top-level integration smoke test for shared 8-bit config bus:
// - Programs addr_decoder window tables in the low address range.
// - Programs irq_router route entries in the high address range.
// - Verifies that writes land in the right block by observing cs_n and cpu_int.
module top_integration_tb;
    localparam [7:0] IRQ_CFG_BASE = 8'hC0;

    localparam int ADDR_W          = 8;
    localparam int NUM_WIN         = 4;
    localparam int NUM_SLOTS       = 3;
    localparam int NUM_CPU_INT     = 2;
    localparam int NUM_CPU_NMI     = 1;
    localparam int NUM_TILE_INT_CH = 2;

    reg                          clk;
    reg                          cfg_clk;
    reg                          rst_n;
    reg  [ADDR_W-1:0]            addr;
    reg                          iorq_n;
    reg                          r_w_;
    reg                          irq_vec_cycle;
    reg                          irq_ack;
    reg  [NUM_SLOTS-1:0]         dev_ready_n;
    reg  [NUM_SLOTS*NUM_TILE_INT_CH-1:0] tile_int_req;
    reg  [NUM_SLOTS-1:0]         tile_nmi_req;
    reg                          cfg_we;
    reg  [7:0]                   cfg_addr;
    reg  [7:0]                   cfg_wdata;

    wire                         ready_n;
    wire                         io_r_w_;
    wire                         data_oe_n;
    wire                         data_dir;
    wire                         ff_oe_n;
    wire [NUM_SLOTS-1:0]         cs_n;
    wire [NUM_CPU_INT-1:0]       cpu_int;
    wire [NUM_CPU_NMI-1:0]       cpu_nmi;
    wire [NUM_SLOTS-1:0]         slot_ack;

    // DUT
    top #(
        .ADDR_W         (ADDR_W),
        .NUM_WIN        (NUM_WIN),
        .NUM_SLOTS      (NUM_SLOTS),
        .NUM_CPU_INT    (NUM_CPU_INT),
        .NUM_CPU_NMI    (NUM_CPU_NMI),
        .NUM_TILE_INT_CH(NUM_TILE_INT_CH),
        .IRQ_CFG_BASE   (IRQ_CFG_BASE)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .addr       (addr),
        .iorq_n     (iorq_n),
        .r_w_       (r_w_),
        .irq_vec_cycle(irq_vec_cycle),
        .irq_ack    (irq_ack),
        .ready_n    (ready_n),
        .io_r_w_    (io_r_w_),
        .data_oe_n  (data_oe_n),
        .data_dir   (data_dir),
        .ff_oe_n    (ff_oe_n),
        .cs_n       (cs_n),
        .cpu_int    (cpu_int),
        .cpu_nmi    (cpu_nmi),
        .dev_ready_n(dev_ready_n),
        .tile_int_req(tile_int_req),
        .tile_nmi_req(tile_nmi_req),
        .slot_ack   (slot_ack),
        .cfg_clk    (cfg_clk),
        .cfg_we     (cfg_we),
        .cfg_addr   (cfg_addr),
        .cfg_wdata  (cfg_wdata)
    );

    // Helpers
    function automatic int int_idx(input int slot, input int ch);
        int_idx = slot*NUM_TILE_INT_CH + ch;
    endfunction

    task automatic dec_cfg_write(input [7:0] a, input [7:0] d);
    begin
        if (a >= IRQ_CFG_BASE) $fatal("Decoder cfg addr %0h in IRQ region", a);
        @(posedge cfg_clk);
        cfg_addr  <= a;
        cfg_wdata <= d;
        cfg_we    <= 1'b1;
        @(posedge cfg_clk);
        cfg_we    <= 1'b0;
    end
    endtask

    task automatic irq_cfg_write(input [7:0] idx, input [7:0] d);
    begin
        @(posedge cfg_clk);
        cfg_addr  <= IRQ_CFG_BASE + idx;
        cfg_wdata <= d;
        cfg_we    <= 1'b1;
        @(posedge cfg_clk);
        cfg_we    <= 1'b0;
    end
    endtask

    task automatic io_cycle_expect_slot(input [7:0] a, input int exp_slot);
    begin
        addr    = a;
        r_w_    = 1'b1;
        iorq_n  = 1'b1;
        @(posedge clk);
        @(negedge clk);
        iorq_n  = 1'b0;
        @(posedge clk);
        #1;
        if (cs_n[exp_slot] !== 1'b0) begin
            $fatal("cs_n mismatch at addr %0h: expected slot %0d active, cs_n=%b", a, exp_slot, cs_n);
        end
        @(negedge clk);
        iorq_n = 1'b1;
        @(posedge clk);
        #1;
        if (cs_n !== {NUM_SLOTS{1'b1}}) begin
            $fatal("cs_n did not return idle: cs_n=%b", cs_n);
        end
    end
    endtask

    // Clocks
    always #5 clk = ~clk;
    always #5 cfg_clk = ~cfg_clk;

    initial begin
        // Waveform dump (optional)
        $dumpfile("top_integration_tb.vcd");
        $dumpvars(0, top_integration_tb);

        // Defaults
        clk          = 0;
        cfg_clk      = 0;
        rst_n        = 0;
        addr         = 0;
        iorq_n       = 1'b1;
        r_w_         = 1'b1;
        irq_vec_cycle= 1'b0;
        irq_ack      = 1'b0;
        dev_ready_n  = {NUM_SLOTS{1'b1}};
        tile_int_req = '0;
        tile_nmi_req = '0;
        cfg_we       = 1'b0;
        cfg_addr     = 8'h00;
        cfg_wdata    = 8'h00;

        // Release reset after a few clocks.
        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        // Program decoder window 0: base 0x10, mask 0xF0, slot 1, op any.
        dec_cfg_write(8'h00, 8'h10); // base[0]
        dec_cfg_write(8'h04, 8'hF0); // mask[0]
        dec_cfg_write(8'h08, 8'h01); // slot[0] = 1
        dec_cfg_write(8'h0C, 8'hFF); // op[0] = any

        // Program IRQ route: slot1,ch0 -> CPU INT0 (enable=1, idx=0).
        irq_cfg_write(int_idx(1,0)[7:0], 8'h80);

        // Sanity: decoder responds to low-range config (IRQ range unused).
        io_cycle_expect_slot(8'h10, 1); // expect cs_n[1] asserted low

        // Sanity: irq_router responds to high-range config.
        tile_int_req[int_idx(1,0)] = 1'b1;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b01) begin
            $fatal("cpu_int not asserted for slot1,ch0: cpu_int=%b", cpu_int);
        end
        tile_int_req[int_idx(1,0)] = 1'b0;
        repeat (2) @(posedge clk);
        if (cpu_int !== 2'b00) begin
            $fatal("cpu_int did not clear: cpu_int=%b", cpu_int);
        end

        $display("top_integration_tb passed.");
        $finish;
    end
endmodule
