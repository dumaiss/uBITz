// Submodule: addressdecode_irq
// Purpose: interrupt routing and Mode-2 acknowledge resolution.
module addressdecode_irq #(
    parameter integer NUM_IRQ_SLOTS = 4
)(
    input                           clk,
    input                           rst_n,

    // Slot-side interrupt lines (active-low)
    input  [NUM_IRQ_SLOTS-1:0][1:0] slot_int_n, // INT_CH0..1 only
    input  [NUM_IRQ_SLOTS-1:0][0:0] slot_nmi_n, // NMI_CH0 only

    // CPU side
    input  [1:0]                    cpu_ack_n,   // ACK0/ACK1 only
    input                           int_ack_mode_en,
    output logic [3:0]              cpu_int_n,   // INT2/INT3 tied high
    output logic [1:0]              cpu_nmi_n,   // NMI0/NMI1 share the same source

    // Slot-side INT_ACK
    output logic [NUM_IRQ_SLOTS-1:0][1:0] slot_int_ack_n,

    // Ack resolution outputs
    output logic                    ack_cycle,
    output logic [0:0]              ack_chan,
    output logic [2:0]              ack_slot,
    output logic                    ack_slot_valid
);

    localparam integer HOST_INT_LINES = 4;
    localparam integer HOST_NMI_LINES = 2;
    localparam integer HOST_ACK_LINES = 2;
    localparam integer SLOT_INT_LINES = 2;
    localparam integer SLOT_NMI_LINES = 1;
    localparam integer SLOT_ACK_LINES = 2;

    // Unpack packed array ports into unpacked views for easier iteration.
    wire [SLOT_INT_LINES-1:0] slot_int_n_arr   [0:NUM_IRQ_SLOTS-1];
    wire [SLOT_NMI_LINES-1:0] slot_nmi_n_arr   [0:NUM_IRQ_SLOTS-1];
    logic [SLOT_ACK_LINES-1:0] slot_int_ack_n_arr [0:NUM_IRQ_SLOTS-1];

    generate
        genvar si;
        for (si = 0; si < NUM_IRQ_SLOTS; si = si + 1) begin : unpack_ports
            assign slot_int_n_arr[si]   = slot_int_n[si];
            assign slot_nmi_n_arr[si]   = slot_nmi_n[si];
            assign slot_int_ack_n[si]   = slot_int_ack_n_arr[si];
        end
    endgenerate

    // CPU INT/NMI open-drain OR (active-low -> reduction AND)
    generate
        genvar ch;
        for (ch = 0; ch < HOST_INT_LINES; ch = ch + 1) begin : gen_cpu_irq
            integer s;
            always @* begin
                cpu_int_n[ch] = 1'b1;
                for (s = 0; s < NUM_IRQ_SLOTS; s = s + 1) begin
                    if (ch < SLOT_INT_LINES)
                        cpu_int_n[ch] = cpu_int_n[ch] & slot_int_n_arr[s][ch];
                end
            end
        end
    endgenerate

    // NMI aggregation: only NMI_CH0 is implemented; drive both CPU NMI lines with it.
    integer ns;
    always @* begin
        cpu_nmi_n = {HOST_NMI_LINES{1'b1}};
        for (ns = 0; ns < NUM_IRQ_SLOTS; ns = ns + 1) begin
            cpu_nmi_n[0] = cpu_nmi_n[0] & slot_nmi_n_arr[ns][0];
            cpu_nmi_n[1] = cpu_nmi_n[1] & slot_nmi_n_arr[ns][0];
        end
    end

    // Ack channel detection (lowest asserted ack bit wins)
    wire [HOST_ACK_LINES-1:0] ack_req_n = cpu_ack_n;
    logic [0:0] ack_chan_r;
    logic       ack_chan_valid;
    always @* begin
        ack_chan_valid = 1'b0;
        ack_chan_r     = 1'd0;
        if (!ack_req_n[0]) begin
            ack_chan_valid = 1'b1;
            ack_chan_r     = 1'd0;
        end else if (!ack_req_n[1]) begin
            ack_chan_valid = 1'b1;
            ack_chan_r     = 1'd1;
        end
    end

    assign ack_chan  = ack_chan_r;
    assign ack_cycle = int_ack_mode_en & ack_chan_valid;

    // Slot claimant detection for selected ack channel
    logic [NUM_IRQ_SLOTS-1:0] slot_claim;
    integer sc;
    always @* begin
        for (sc = 0; sc < NUM_IRQ_SLOTS; sc = sc + 1) begin
            case (ack_chan_r)
                1'd0: slot_claim[sc] = (slot_int_n_arr[sc][0] == 1'b0);
                1'd1: slot_claim[sc] = (slot_int_n_arr[sc][1] == 1'b0);
                default: slot_claim[sc] = 1'b0;
            endcase
        end
    end

    // Count claimants and pick slot if unique
    always @* begin
        integer count;
        ack_slot_valid = 1'b0;
        ack_slot       = 3'd0;
        count          = 0;

        for (sc = 0; sc < NUM_IRQ_SLOTS; sc = sc + 1) begin
            if (slot_claim[sc]) begin
                count = count + 1;
                ack_slot = sc[2:0];
            end
        end

        if (count == 1)
            ack_slot_valid = 1'b1;
    end

    // Drive INT_ACK to the owning slot/channel when unique.
    generate
        genvar ss, kk;
        for (ss = 0; ss < NUM_IRQ_SLOTS; ss = ss + 1) begin : gen_ack_slot
            for (kk = 0; kk < SLOT_ACK_LINES; kk = kk + 1) begin : gen_ack_chan
                always @* begin
                    slot_int_ack_n_arr[ss][kk] = 1'b1;
                    if (ack_cycle && ack_slot_valid && ack_slot == ss[2:0] && ack_chan_r == kk[0])
                        slot_int_ack_n_arr[ss][kk] = 1'b0;
                end
            end
        end
    endgenerate

endmodule
