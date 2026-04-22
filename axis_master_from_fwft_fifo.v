module axis_master_from_fwft_fifo #
(
    parameter DATA_WIDTH = 16
)
(
    input  wire                     clk,
    input  wire                     rst,

    // FWFT FIFO interface
    input  wire [DATA_WIDTH-1:0]    fifo_data,
    input  wire                     fifo_empty,
    output wire                     fifo_rd_en,

    // AXI Stream Master
    output wire [DATA_WIDTH-1:0]    m_axis_tdata,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready
);

    // ============================================================
    // Skid buffer (2-stage elastic buffer)
    // ============================================================

    reg                    v0;   // stage0 valid
    reg                    v1;   // stage1 valid
    reg [DATA_WIDTH-1:0]   d0;
    reg [DATA_WIDTH-1:0]   d1;
    // FIFO → d0 → d1 → AXI

    // ------------------------------------------------------------
    // Control signals
    // ------------------------------------------------------------

    wire take1;   // AXI handshake
    wire move;    // stage1 can accept data
    wire take0;   // stage0 -> stage1 transfer

    assign take1 = v1 && m_axis_tready;

    // stage1 can move if empty or being consumed
    assign move  = !v1 || take1;

    // stage0 gives data when it has valid and stage1 can accept
    assign take0 = v0 && move;

    // ------------------------------------------------------------
    // Sequential logic
    // ------------------------------------------------------------

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            v0 <= 1'b0;
            v1 <= 1'b0;
        end else begin

            // -------------------------
            // Stage 1 (AXI side)
            // -------------------------
            if (move) begin
                v1 <= v0;
                d1 <= d0;
            end

            // -------------------------
            // Stage 0 (FIFO side)
            // -------------------------
            if (!v0 || take0) begin
                if (!fifo_empty) begin
                    v0 <= 1'b1;
                    d0 <= fifo_data;
                end else begin
                    v0 <= 1'b0;
                end
            end

        end
    end

    // ------------------------------------------------------------
    // FIFO read enable
    // ------------------------------------------------------------

    assign fifo_rd_en = (!v0 || take0) && !fifo_empty;

    // ------------------------------------------------------------
    // AXI outputs
    // ------------------------------------------------------------

    assign m_axis_tvalid = v1;
    assign m_axis_tdata  = d1;

endmodule
