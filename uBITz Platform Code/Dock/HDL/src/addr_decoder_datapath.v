// Submodule: addr_decoder_datapath
// Purpose: control data transceivers and 0xFF filler driver.
// Walkthrough:
//   - Qualify current cycle with /IORQ to get io_cycle.
//   - win_valid marks mapped I/O; unmapped cycles drive the 0xFF filler on reads.
//   - data_oe_n gates transceivers, data_dir selects direction, io_r_w_ hands
//     the CPU read/write intent to tiles during active cycles.
module addr_decoder_datapath (
    input  logic iorq_n,
    input  logic is_read,
    input  logic is_write,
    input  logic win_valid,

    output logic data_oe_n,
    output logic data_dir,
    output logic ff_oe_n,
    output logic io_r_w_
);

    // Cycle qualifiers
    logic io_cycle;      // 1 when /IORQ is asserted
    logic mapped_io;     // 1 when I/O cycle hits a configured window
    logic unmapped_io;   // 1 when I/O cycle misses all windows
    logic mapped_read;   // mapped and read direction
    logic mapped_write;  // mapped and write direction
    logic unmapped_read; // unmapped read (used to gate filler driver)

    assign io_cycle     = ~iorq_n;
    assign mapped_io    = io_cycle & win_valid;
    assign unmapped_io  = io_cycle & ~win_valid;
    assign mapped_read  = mapped_io   & is_read;
    assign mapped_write = mapped_io   & is_write;
    assign unmapped_read= unmapped_io & is_read;

    assign data_oe_n = ~(mapped_read | mapped_write);
    assign data_dir  = is_read;
    assign ff_oe_n   = ~unmapped_read;

    // Qualified R/W_ for tiles: during I/O cycles pass through CPU's R/W_,
    // otherwise default to 'read'.
    assign io_r_w_ = iorq_n ? 1'b1 : is_read;

endmodule
