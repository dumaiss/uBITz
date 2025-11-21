// Submodule: addr_decoder_datapath
// Purpose: control data transceivers and 0xFF filler driver.
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

    logic io_cycle;
    logic mapped_io;
    logic unmapped_io;
    logic mapped_read;
    logic mapped_write;
    logic unmapped_read;

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
