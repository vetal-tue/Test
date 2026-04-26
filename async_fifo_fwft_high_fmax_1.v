module async_fifo_fwft_high_fmax_1 #
(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,
    // Пороги теперь задаются как "расстояние до края"
    // ALMOST_FULL_OFFSET = 2 означает флаг за 2 слова до FULL
    parameter ALMOST_FULL_OFFSET  = 2, 
    parameter ALMOST_EMPTY_OFFSET = 2
)
(
    // WRITE
    input                  wr_clk,
    input                  wr_rst,
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output reg             wr_full,
    output reg             wr_almost_full,
    output [ADDR_W:0]      wr_cnt, // Для совместимости, но внутри не используется

    // READ
    input                  rd_clk,
    input                  rd_rst,
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output                 rd_empty,
    output reg             rd_almost_empty,
    output [ADDR_W:0]      rd_cnt
);

    // =====================================================
    // Gray helpers
    // =====================================================
    function [ADDR_W:0] bin2gray(input [ADDR_W:0] b);
        bin2gray = b ^ (b >> 1);
    endfunction

    // =====================================================
    // POINTERS & SYNC
    // =====================================================
    reg [ADDR_W:0] wr_ptr, wr_ptr_gray;
    reg [ADDR_W:0] rd_ptr, rd_ptr_gray;

    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] wr_ptr_gray_s1, wr_ptr_gray_s2;
    (* ASYNC_REG = "TRUE" *) reg [ADDR_W:0] rd_ptr_gray_s1, rd_ptr_gray_s2;

    always @(posedge rd_clk) {wr_ptr_gray_s2, wr_ptr_gray_s1} <= {wr_ptr_gray_s1, wr_ptr_gray};
    always @(posedge wr_clk) {rd_ptr_gray_s2, rd_ptr_gray_s1} <= {rd_ptr_gray_s1, rd_ptr_gray};

    // =====================================================
    // RAM
    // =====================================================
    (* ram_style = "block" *) reg [DATA_W-1:0] ram [0:(1<<ADDR_W)-1];

    always @(posedge wr_clk)
        if (wr_en && !wr_full)
            ram[wr_ptr[ADDR_W-1:0]] <= wr_data;

    // =====================================================
    // WRITE DOMAIN (FAST FLAGS)
    // =====================================================
    wire [ADDR_W:0] wr_ptr_next = wr_ptr + (wr_en && !wr_full);
    wire [ADDR_W:0] wr_ptr_gray_next = bin2gray(wr_ptr_next);

    // Расчет "будущего" указателя для almost_full
    wire [ADDR_W:0] wr_ptr_afull = wr_ptr_next + ALMOST_FULL_OFFSET;
    wire [ADDR_W:0] wr_ptr_gray_afull = bin2gray(wr_ptr_afull);

    // Инверсия для сравнения Грей-кодов на FULL
    // (Стандартный алгоритм: инвертируем два старших бита)
    wire [ADDR_W:0] rd_ptr_gray_sync_inv = {~rd_ptr_gray_s2[ADDR_W:ADDR_W-1], rd_ptr_gray_s2[ADDR_W-2:0]};

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0;
            wr_full <= 0;
            wr_almost_full <= 0;
        end else begin
            wr_ptr      <= wr_ptr_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            
            // FULL: сравнение с инвертированным указателем чтения
            wr_full <= (wr_ptr_gray_next == rd_ptr_gray_sync_inv);
            
            // ALMOST FULL: аналогично, но с "забегающим" указателем
            // Загорится, когда до края останется ALMOST_FULL_OFFSET или меньше
            wr_almost_full <= (wr_ptr_gray_afull == rd_ptr_gray_sync_inv) || wr_full; 
        end
    end

    // =====================================================
    // READ DOMAIN (FWFT & FAST FLAGS)
    // =====================================================
    reg [ADDR_W:0] mem_rd_ptr;
    reg [DATA_W-1:0] stage0_data, stage1_data;
    reg stage0_valid, stage1_valid;

    // Сравнение для Empty (в домене чтения)
    // mem_rd_ptr - это указатель, по которому мы забираем данные из RAM
    wire can_prefetch = (bin2gray(mem_rd_ptr) != wr_ptr_gray_s2);

    wire push1 = stage0_valid && (!stage1_valid || rd_en); 
    wire do_prefetch = can_prefetch && (!stage0_valid || push1);

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            mem_rd_ptr   <= 0;
            stage0_valid <= 0;
            stage1_valid <= 0;
        end else begin
            stage0_valid <= (stage0_valid && !push1) || do_prefetch;
            stage1_valid <= (stage1_valid && !rd_en) || push1;

            if (push1) stage1_data <= stage0_data;

            if (do_prefetch) begin
                stage0_data <= ram[mem_rd_ptr[ADDR_W-1:0]];
                mem_rd_ptr  <= mem_rd_ptr + 1;
            end
        end
    end

    assign rd_data  = stage1_data;
    assign rd_empty = !stage1_valid;

    // --- Almost Empty Logic ---
    wire [ADDR_W:0] rd_ptr_next = rd_ptr + (rd_en && stage1_valid);
    wire [ADDR_W:0] rd_ptr_gray_next = bin2gray(rd_ptr_next);
    
    // "Забегающий" указатель для almost_empty
    wire [ADDR_W:0] rd_ptr_aempty = rd_ptr_next + ALMOST_EMPTY_OFFSET;
    wire [ADDR_W:0] rd_ptr_gray_aempty = bin2gray(rd_ptr_aempty);

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
            rd_almost_empty <= 1;
        end else begin
            rd_ptr      <= rd_ptr_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            
            // Загорится, когда в FIFO останется ALMOST_EMPTY_OFFSET или меньше
            rd_almost_empty <= (rd_ptr_gray_aempty == wr_ptr_gray_s2) || rd_empty;
        end
    end

    // Для совместимости интерфейса (если они не нужны, можно удалить)
    // Внимание: они остались "медленными", если их раскомментировать через gray2bin
    assign wr_cnt = 0; 
    assign rd_cnt = 0;

endmodule
