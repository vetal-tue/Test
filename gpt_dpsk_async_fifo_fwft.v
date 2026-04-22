module gpt_dpsk_async_fifo_fwft #(
    parameter DATA_W              = 8,
    parameter ADDR_W              = 4,
    parameter ALMOST_FULL_THRESH  = 2,
    parameter ALMOST_EMPTY_THRESH = 2
) (
    // WRITE DOMAIN
    input                  wr_clk,
    input                  wr_rst,
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output reg             wr_full,
    output reg             wr_almost_full,
    output reg [ADDR_W:0]  wr_cnt,

    // READ DOMAIN
    input                  rd_clk,
    input                  rd_rst,
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output reg             rd_empty,
    output reg             rd_almost_empty,
    output reg [ADDR_W:0]  rd_cnt
);

    localparam DEPTH     = 1 << ADDR_W;
    localparam PTR_WIDTH = ADDR_W + 1;

    // =========================================================================
    // Gray functions
    // =========================================================================
    function [PTR_WIDTH-1:0] bin2gray (input [PTR_WIDTH-1:0] bin);
        bin2gray = bin ^ (bin >> 1);
    endfunction

    function [PTR_WIDTH-1:0] gray2bin (input [PTR_WIDTH-1:0] gray);
        integer i;
        reg [PTR_WIDTH-1:0] bin;
        begin
            bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                bin[i] = bin[i+1] ^ gray[i];
            gray2bin = bin;
        end
    endfunction

    // =========================================================================
    // MEMORY (sync read, BRAM-friendly)
    // =========================================================================
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // =========================================================================
    // WRITE DOMAIN
    // =========================================================================
    reg  [PTR_WIDTH-1:0] wr_ptr_bin, wr_ptr_gray;
    wire [PTR_WIDTH-1:0] wr_ptr_bin_next, wr_ptr_gray_next;

    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync1_wr, rd_ptr_gray_sync2_wr;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_sync_wr;

    assign wr_ptr_bin_next  = wr_ptr_bin + (wr_en & ~wr_full);
    assign wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    // sync read pointer into write domain
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_ptr_gray_sync1_wr <= 0;
            rd_ptr_gray_sync2_wr <= 0;
        end else begin
            rd_ptr_gray_sync1_wr <= rd_ptr_gray;
            rd_ptr_gray_sync2_wr <= rd_ptr_gray_sync1_wr;
        end
    end

    assign rd_ptr_bin_sync_wr = gray2bin(rd_ptr_gray_sync2_wr);

    // ---- occupancy (no mask)
    wire [PTR_WIDTH-1:0] wr_cnt_int;
    assign wr_cnt_int = wr_ptr_bin - rd_ptr_bin_sync_wr;

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst)
            wr_cnt <= 0;
        else
            wr_cnt <= wr_cnt_int;
    end

    // ---- flags
    wire wr_full_comb;
    assign wr_full_comb = (wr_ptr_gray_next ==
        {~rd_ptr_gray_sync2_wr[PTR_WIDTH-1:PTR_WIDTH-2],
          rd_ptr_gray_sync2_wr[PTR_WIDTH-3:0]});

    wire wr_almost_full_comb;
//    assign wr_almost_full_comb = ((DEPTH - wr_cnt_int) <= ALMOST_FULL_THRESH);
    assign wr_almost_full_comb = (wr_cnt_int >= (DEPTH - ALMOST_FULL_THRESH));

    // // lookahead pointer (на K вперёд)
    // wire [PTR_WIDTH-1:0] wr_ptr_bin_af;
    // wire [PTR_WIDTH-1:0] wr_ptr_gray_af;
    
    // assign wr_ptr_bin_af  = wr_ptr_bin + ALMOST_FULL_THRESH;
    // assign wr_ptr_gray_af = bin2gray(wr_ptr_bin_af);
    
    // // almost_full через ту же логику, что и full
    // assign wr_almost_full_comb = (wr_ptr_gray_af ==
    //     {~rd_ptr_gray_sync2_wr[PTR_WIDTH-1:PTR_WIDTH-2],
    //      rd_ptr_gray_sync2_wr[PTR_WIDTH-3:0]});

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_full        <= 0;
            wr_almost_full <= 0;
        end else begin
            wr_full        <= wr_full_comb;
            wr_almost_full <= wr_almost_full_comb;
        end
    end

    // ---- write memory
    always @(posedge wr_clk) begin
        if (wr_en & ~wr_full)
            mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
    end

    // =========================================================================
    // READ DOMAIN (FWFT via PREFETCH)
    // =========================================================================
    reg  [PTR_WIDTH-1:0] rd_ptr_bin, rd_ptr_gray;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next, rd_ptr_gray_next;

    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync1_rd, wr_ptr_gray_sync2_rd;
    wire [PTR_WIDTH-1:0] wr_ptr_bin_sync_rd;

    // sync write pointer into read domain
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            wr_ptr_gray_sync1_rd <= 0;
            wr_ptr_gray_sync2_rd <= 0;
        end else begin
            wr_ptr_gray_sync1_rd <= wr_ptr_gray;
            wr_ptr_gray_sync2_rd <= wr_ptr_gray_sync1_rd;
        end
    end

    assign wr_ptr_bin_sync_rd = gray2bin(wr_ptr_gray_sync2_rd);

    // ---- occupancy (no mask)
    wire [PTR_WIDTH-1:0] rd_cnt_int;
    assign rd_cnt_int = wr_ptr_bin_sync_rd - rd_ptr_bin;

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_cnt <= 0;
        else
            rd_cnt <= rd_cnt_int;
    end

    // =========================================================================
    // PREFETCH (FWFT)
    // =========================================================================
    reg [DATA_W-1:0] rd_data_reg;
    reg              prefetch_valid;

    assign rd_data = rd_data_reg;

    wire fifo_has_data = (rd_ptr_gray != wr_ptr_gray_sync2_rd);

    // advance pointer:
    wire rd_advance =
        (rd_en & prefetch_valid) |
        (~prefetch_valid & fifo_has_data);

    assign rd_ptr_bin_next  = rd_ptr_bin + rd_advance;
    assign rd_ptr_gray_next = bin2gray(rd_ptr_bin_next);

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    // ---- synchronous read from memory
    reg [DATA_W-1:0] mem_rd_data_reg;

    always @(posedge rd_clk) begin
        mem_rd_data_reg <= mem[rd_ptr_bin[ADDR_W-1:0]];
    end

    // ---- prefetch buffer
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            prefetch_valid <= 0;
            rd_data_reg    <= 0;
        end else begin
            if (rd_advance) begin
                rd_data_reg    <= mem_rd_data_reg;
                prefetch_valid <= fifo_has_data;
            end
        end
    end

    // =========================================================================
    // FLAGS (read domain)
    // =========================================================================
    wire rd_empty_comb = ~prefetch_valid;
    wire rd_almost_empty_comb = (rd_cnt_int <= ALMOST_EMPTY_THRESH);

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_empty        <= 1;
            rd_almost_empty <= 1;
        end else begin
            rd_empty        <= rd_empty_comb;
            rd_almost_empty <= rd_almost_empty_comb;
        end
    end

endmodule
