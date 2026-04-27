module async_fifo_fwft_high_fmax_1 #
(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,
    // Пороги теперь задаются как "расстояние до края"
    // ALMOST_FULL_OFFSET = 2 означает флаг за 2 слова до FULL
    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 2,
    parameter ALMOST_EMPTY_THRESH = 2
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

    // FULL: Мгновенное сравнение (Грей) с инверсией старших битов
    wire [ADDR_W:0] rd_ptr_gray_sync_inv = {~rd_ptr_gray_s2[ADDR_W:ADDR_W-1], rd_ptr_gray_s2[ADDR_W-2:0]};

    // ALMOST FULL: Конвейеризованный бинарный указатель для разбиения критического пути
    // 1. Преобразуем синхронизированный указатель в бинарный код
    wire [ADDR_W:0] rd_ptr_sync_bin = gray2bin(rd_ptr_gray_s2);
    // 2. Регистрируем бинарный указатель из другого домена!
    // Это добавляет 1 такт пессимизма, но разбивает длинный путь (gray2bin -> sub)
    reg [ADDR_W:0] rd_ptr_sync_bin_pipe;
   

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr <= 0;
            wr_ptr_gray <= 0;
            wr_full <= 0;            
            rd_ptr_sync_bin_pipe <= 0;
            wr_almost_full <= 0;
            wr_cnt <= 0;
        end else begin
            wr_ptr      <= wr_ptr_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            
            // FULL: сравнение с инвертированным указателем чтения
            wr_full <= (wr_ptr_gray_next == rd_ptr_gray_sync_inv);
            
            // 1 такт задержки для бинарного указателя (безопасный пессимизм)
            rd_ptr_sync_bin_pipe <= rd_ptr_sync_bin;
            
            // Конвейеризованный вычет (работает быстро, т.к. разорвана цепь gray2bin -> substract)
            wr_cnt <= wr_ptr_next - rd_ptr_sync_bin_pipe;
            wr_almost_full <= ((wr_ptr_next - rd_ptr_sync_bin_pipe) >= ALMOST_FULL_THRESH);
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

    wire do_read = rd_en && stage1_valid;
    wire [ADDR_W:0] rd_ptr_next = rd_ptr + do_read;
    
    // ALMOST EMPTY: Конвейеризованный бинарный указатель записи
    wire [ADDR_W:0] wr_ptr_sync_bin = gray2bin(wr_ptr_gray_s2);
    reg  [ADDR_W:0] wr_ptr_sync_bin_pipe;

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr <= 0;
            rd_ptr_gray <= 0;
            wr_ptr_sync_bin_pipe <= 0;
            rd_almost_empty <= 1;
        end else begin
            rd_ptr      <= rd_ptr_next;
            rd_ptr_gray <= bin2gray(rd_ptr_next);
            
            // 1 такт задержки
            wr_ptr_sync_bin_pipe <= wr_ptr_sync_bin;
            
            // Правильный подсчет слов в FIFO (включая конвейер)
            // wr_ptr - это общее кол-во записанных, rd_ptr - общее кол-во прочитанных пользователем
            rd_cnt <= wr_ptr_sync_bin_pipe - rd_ptr_next;
            
            // Срабатывает корректно для всего диапазона (<= THRESH)
            rd_almost_empty <= ((wr_ptr_sync_bin_pipe - rd_ptr_next) <= ALMOST_EMPTY_THRESH);
        end
    end


endmodule
