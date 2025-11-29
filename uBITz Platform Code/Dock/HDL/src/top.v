//--------------------------------------------------------------------
// uBITz Dock - Top-Level Integration
//--------------------------------------------------------------------
// Combines the address decoder and interrupt router into a single
// instantiation point. The irq_router's active interrupt metadata
// (irq_int_active/irq_int_slot) feeds the addr_decoder to steer
// Mode-2 vector fetches. A shared cfg_clk drives both config buses.
//
// Note: irq_vec_cycle and irq_ack originate from the same external
// /CPU_ACK pin; they remain separate inputs here so external logic
// can shape the pulse/tagging as needed.
//--------------------------------------------------------------------
module top #(
    parameter integer ADDR_W           = 32,
    parameter integer NUM_WIN          = 16,
    parameter integer NUM_SLOTS        = 5,
    parameter integer NUM_CPU_INT      = 4,
    parameter integer NUM_CPU_NMI      = 2,
    parameter integer NUM_TILE_INT_CH  = 2,
    parameter integer CFG_ADDR_WIDTH   = 8,
    // Shared 8-bit config bus: below IRQ_CFG_BASE -> addr_decoder,
    // at/above IRQ_CFG_BASE -> irq_router (offset by this base).
    parameter [CFG_ADDR_WIDTH-1:0] IRQ_CFG_BASE = 8'hC0,
    parameter integer SLOT_IDX_WIDTH   = (NUM_SLOTS <= 1) ? 1 : $clog2(NUM_SLOTS)
)(
    input  wire                         clk,
    input  wire                         rst_n,

    // CPU bus interface
    input  wire [ADDR_W-1:0]            addr,
    input  wire                         iorq_n,
    input  wire                         r_w_,
    input  wire                         irq_vec_cycle,
    input  wire                         irq_ack,

    output wire                         ready_n,
    output wire                         io_r_w_,
    output wire                         data_oe_n,
    output wire                         data_dir,
    output wire                         ff_oe_n,
    output wire [NUM_SLOTS-1:0]         cs_n,

    // CPU interrupt outputs
    output wire [NUM_CPU_INT-1:0]       cpu_int,
    output wire [NUM_CPU_NMI-1:0]       cpu_nmi,

    // Tile / device side
    input  wire [NUM_SLOTS-1:0]         dev_ready_n,
    input  wire [NUM_SLOTS*NUM_TILE_INT_CH-1:0] tile_int_req,
    input  wire [NUM_SLOTS-1:0]         tile_nmi_req,
    output wire [NUM_SLOTS-1:0]         slot_ack,

    // Configuration interfaces
    input  wire                         cfg_clk,
    input  wire                         cfg_we,
    input  wire [7:0]                   cfg_addr,
    input  wire [7:0]                   cfg_wdata
);

    // Wires bridging irq_router to addr_decoder for Mode-2 steering.
    wire irq_int_active_sig;
    wire [SLOT_IDX_WIDTH-1:0] irq_int_slot_sig;

    // Shared 8-bit config bus split: low range to addr_decoder, high range to irq_router.
    wire        dec_cfg_we   = cfg_we && (cfg_addr < IRQ_CFG_BASE[7:0]);
    wire        irq_cfg_we   = cfg_we && (cfg_addr >= IRQ_CFG_BASE[7:0]);
    wire [7:0]  dec_cfg_addr = cfg_addr;
    wire [CFG_ADDR_WIDTH-1:0] irq_cfg_addr = cfg_addr - IRQ_CFG_BASE[7:0];

    irq_router #(
        .NUM_SLOTS       (NUM_SLOTS),
        .NUM_CPU_INT     (NUM_CPU_INT),
        .NUM_CPU_NMI     (NUM_CPU_NMI),
        .NUM_TILE_INT_CH (NUM_TILE_INT_CH),
        .CFG_ADDR_WIDTH  (CFG_ADDR_WIDTH),
        .SLOT_IDX_WIDTH  (SLOT_IDX_WIDTH)
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
        .irq_int_active(irq_int_active_sig),
        .irq_int_slot  (irq_int_slot_sig),
        .cfg_wr_en     (irq_cfg_we),
        .cfg_rd_en     (1'b0),
        .cfg_addr      (irq_cfg_addr),
        .cfg_wdata     (cfg_wdata)
    );

    addr_decoder #(
        .ADDR_W        (ADDR_W),
        .NUM_WIN       (NUM_WIN),
        .NUM_SLOTS     (NUM_SLOTS),
        .SLOT_IDX_WIDTH(SLOT_IDX_WIDTH)
    ) u_addr_decoder (
        .addr           (addr),
        .iorq_n         (iorq_n),
        .clk            (clk),
        .rst_n          (rst_n),
        .r_w_           (r_w_),
        .dev_ready_n    (dev_ready_n),
        .irq_int_active (irq_int_active_sig),
        .irq_int_slot   (irq_int_slot_sig),
        .irq_vec_cycle  (irq_vec_cycle),
        .cfg_clk        (cfg_clk),
        .cfg_we         (dec_cfg_we),
        .cfg_addr       (dec_cfg_addr),
        .cfg_wdata      (cfg_wdata),
        .ready_n        (ready_n),
        .io_r_w_        (io_r_w_),
        .data_oe_n      (data_oe_n),
        .data_dir       (data_dir),
        .ff_oe_n        (ff_oe_n),
        .cs_n           (cs_n)
    );

endmodule
