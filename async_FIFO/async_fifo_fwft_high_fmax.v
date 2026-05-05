module async_fifo_fwft_high_fmax #
(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,
    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 2,
    parameter ALMOST_EMPTY_THRESH = 1
)
(
    // WRITE
    input                  wr_clk,
    input                  wr_rst,
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output reg             wr_full,
    output reg             wr_almost_full,
    output reg [ADDR_W:0]  wr_cnt,

    // READ
    input                  rd_clk,
    input                  rd_rst,
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output                 rd_empty,
    output reg             rd_almost_empty,
    output reg [ADDR_W:0]  rd_cnt
);

    // =====================================================
    // Gray helpers
    // =====================================================
    function [ADDR_W:0] bin2gray(input [ADDR_W:0] b);
        bin2gray = b ^ (b >> 1);
    endfunction

    function [ADDR_W:0] gray2bin(input [ADDR_W:0] g);
        integer i;
        for (i = 0; i <= ADDR_W; i = i + 1)
            gray2bin[i] = ^(g >> i);
    endfunction

    // =====================================================
    // POINTERS
    // =====================================================
    reg [ADDR_W:0] wr_ptr, wr_ptr_gray;
    reg [ADDR_W:0] rd_ptr, rd_ptr_gray;

    reg [ADDR_W:0] wr_ptr_gray_s1, wr_ptr_gray_s2;
    reg [ADDR_W:0] rd_ptr_gray_s1, rd_ptr_gray_s2;

    wire [ADDR_W:0] wr_ptr_sync = gray2bin(wr_ptr_gray_s2);
    wire [ADDR_W:0] rd_ptr_sync = gray2bin(rd_ptr_gray_s2);

    // sync
    always @(posedge rd_clk) begin
        wr_ptr_gray_s1 <= wr_ptr_gray;
        wr_ptr_gray_s2 <= wr_ptr_gray_s1;
    end

    always @(posedge wr_clk) begin
        rd_ptr_gray_s1 <= rd_ptr_gray;
        rd_ptr_gray_s2 <= rd_ptr_gray_s1;
    end

    // =====================================================
    // RAM
    // =====================================================
    (* ram_style = "block" *) reg [DATA_W-1:0] ram [0:(1<<ADDR_W)-1];

    always @(posedge wr_clk)
        if (wr_en && !wr_full)
            ram[wr_ptr[ADDR_W-1:0]] <= wr_data;

    // =====================================================
    // WRITE DOMAIN (NO SUBTRACT IN FLAG PATH)
    // =====================================================

    wire [ADDR_W:0] wr_ptr_next = wr_ptr + (wr_en && !wr_full);
    wire [ADDR_W:0] wr_ptr_gray_next = bin2gray(wr_ptr_next);

    // 🔥 FULL через pointer compare (быстро!)
    wire wr_full_next =
        (wr_ptr_gray_next ==
        {~rd_ptr_gray_s2[ADDR_W:ADDR_W-1],
          rd_ptr_gray_s2[ADDR_W-2:0]});

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0;
            wr_cnt <= 0;
            wr_full <= 0;
            wr_almost_full <= 0;
        end else begin
            wr_ptr <= wr_ptr_next;
            wr_ptr_gray <= wr_ptr_gray_next;

            // fast flag
            wr_full <= wr_full_next;

            // slow path (не критично)
            wr_cnt <= wr_ptr_next - rd_ptr_sync;
            wr_almost_full <= (wr_cnt >= ALMOST_FULL_THRESH);
        end
    end

    // =====================================================
    // READ DOMAIN (FWFT pipeline)
    // =====================================================

    reg [ADDR_W:0] mem_rd_ptr;

    reg [DATA_W-1:0] stage0_data, stage1_data;
    reg stage0_valid, stage1_valid;

    wire can_prefetch = (mem_rd_ptr != wr_ptr_sync);

    wire push1 = stage0_valid && (!stage1_valid || rd_en); // stage0 -> stage1
    wire pop1  = rd_en && stage1_valid;

    wire do_prefetch =
        can_prefetch &&
        (!stage0_valid || push1);

    // next-state (без конфликтов!)
    wire stage1_valid_next =
        (stage1_valid && !pop1) || push1;

    wire stage0_valid_next =
        (stage0_valid && !push1) || do_prefetch;

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            mem_rd_ptr   <= 0;
            stage0_valid <= 0;
            stage1_valid <= 0;
        end else begin
            stage0_valid <= stage0_valid_next;
            stage1_valid <= stage1_valid_next;

            // shift
            if (push1)
                stage1_data <= stage0_data;

            // prefetch
            if (do_prefetch) begin
                stage0_data <= ram[mem_rd_ptr[ADDR_W-1:0]];
                mem_rd_ptr  <= mem_rd_ptr + 1;
            end
        end
    end

    assign rd_data  = stage1_data;
    assign rd_empty = !stage1_valid;

    // =====================================================
    // READ POINTER + COUNT (slow path)
    // =====================================================
    wire do_read = rd_en && stage1_valid;

    wire [ADDR_W:0] rd_ptr_next = rd_ptr + do_read;

    // // учитываем pipeline!
    // wire [ADDR_W:0] pipe_cnt =
    //     stage0_valid + stage1_valid;

    wire [ADDR_W:0] rd_cnt_next =
        (wr_ptr_sync - rd_ptr_next);
        // (wr_ptr_sync - rd_ptr_next) + pipe_cnt;

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
            rd_cnt <= 0;
            rd_almost_empty <= 1;
        end else begin
            rd_ptr <= rd_ptr_next;
            rd_ptr_gray <= bin2gray(rd_ptr_next);

            // slow path
            rd_cnt <= rd_cnt_next;
            rd_almost_empty <= (rd_cnt_next <= ALMOST_EMPTY_THRESH);
        end
    end

endmodule
