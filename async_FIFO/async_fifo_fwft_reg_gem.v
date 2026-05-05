module async_fifo_fwft_reg_gem #
(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,
    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
)
(
    // write side
    input                  wr_clk,
    input                  wr_rst,
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output reg             wr_full,
    output reg             wr_almost_full,
    output reg [ADDR_W:0]  wr_cnt,

    // read side
    input                  rd_clk,
    input                  rd_rst,
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output reg             rd_empty,
    output reg             rd_almost_empty,
    output reg [ADDR_W:0]  rd_cnt
);

    // =======================================================
    // Функции преобразования кодов
    // =======================================================
    function [ADDR_W:0] bin2gray;
        input [ADDR_W:0] bin;
        begin
            bin2gray = bin ^ (bin >> 1);
        end
    endfunction

    // function [ADDR_W:0] gray2bin;
    //     input [ADDR_W:0] gray;
    //     integer i;
    //     begin
    //         gray2bin[ADDR_W] = gray[ADDR_W];
    //         for (i=ADDR_W-1; i>=0; i=i-1) begin
    //             gray2bin[i] = gray2bin[i+1] ^ gray[i];
    //         end
    //     end
    // endfunction
    function [ADDR_W:0] gray2bin(input [ADDR_W:0] g);
        integer i;
        for (i = 0; i <= ADDR_W; i = i + 1) begin
            gray2bin[i] = ^(g >> i);
        end
    endfunction

    // =======================================================
    // Внутренние регистры и указатели
    // =======================================================
    reg  [ADDR_W:0] wr_ptr, wr_ptr_gray;
    reg  [ADDR_W:0] rd_ptr, rd_ptr_gray;
    reg  [ADDR_W:0] mem_rd_ptr; // Внутренний указатель чтения из RAM

    // Регистры синхронизаторов
    reg  [ADDR_W:0] wr_ptr_gray_s1, wr_ptr_gray_s2;
    reg  [ADDR_W:0] rd_ptr_gray_s1, rd_ptr_gray_s2;

    // Память и выходной регистр
    (* ram_style = "block" *) reg  [DATA_W-1:0] ram [0:(1<<ADDR_W)-1];
    reg  [DATA_W-1:0] rd_data_reg;

    assign rd_data = rd_data_reg;

    // =======================================================
    // Синхронизаторы указателей
    // =======================================================
    // Gray pointer записи -> домен чтения
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            wr_ptr_gray_s1 <= 0;
            wr_ptr_gray_s2 <= 0;
        end else begin
            wr_ptr_gray_s1 <= wr_ptr_gray;
            wr_ptr_gray_s2 <= wr_ptr_gray_s1;
        end
    end
    wire [ADDR_W:0] wr_ptr_sync_bin = gray2bin(wr_ptr_gray_s2);

    // Gray pointer чтения -> домен записи
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_ptr_gray_s1 <= 0;
            rd_ptr_gray_s2 <= 0;
        end else begin
            rd_ptr_gray_s1 <= rd_ptr_gray;
            rd_ptr_gray_s2 <= rd_ptr_gray_s1;
        end
    end
    wire [ADDR_W:0] rd_ptr_sync_bin = gray2bin(rd_ptr_gray_s2);

    // =======================================================
    // Домен записи (Write Side)
    // =======================================================
    wire [ADDR_W:0] wr_ptr_next = wr_ptr + (wr_en && !wr_full);
    wire [ADDR_W:0] wr_cnt_next = wr_ptr_next - rd_ptr_sync_bin;

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr         <= 0;
            wr_ptr_gray    <= 0;
            wr_cnt         <= 0;
            wr_full        <= 1'b0;
            wr_almost_full <= 1'b0;
        end else begin
            wr_ptr         <= wr_ptr_next;
            wr_ptr_gray    <= bin2gray(wr_ptr_next);
            wr_cnt         <= wr_cnt_next;
            // Full наступает, когда разница достигает DEPTH (2^ADDR_W)
            wr_full        <= (wr_cnt_next == (1 << ADDR_W));
            wr_almost_full <= (wr_cnt_next >= ALMOST_FULL_THRESH);
        end
    end

    // Запись в память (Infer Block RAM)
    always @(posedge wr_clk) begin
        if (wr_en && !wr_full) begin
            ram[wr_ptr[ADDR_W-1:0]] <= wr_data;
        end
    end

    // =======================================================
    // Домен чтения (Read Side & FWFT Logic)
    // =======================================================
    
    // Внутреннее чтение памяти доступно, если внутренний указатель не догнал запись
    wire can_read_bram = (mem_rd_ptr != wr_ptr_sync_bin);
    
    // Мы инициируем чтение из BRAM в выходной регистр, если:
    // 1) В памяти есть данные И (Выходной регистр пуст ИЛИ сейчас происходит чтение из него)
    wire read_bram = can_read_bram && (rd_empty || rd_en);

    // Внутренний указатель чтения BRAM
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            mem_rd_ptr <= 0;
        end else if (read_bram) begin
            mem_rd_ptr <= mem_rd_ptr + 1;
        end
    end

    // Инференс выходного регистра Block RAM (FWFT буфер)
    always @(posedge rd_clk) begin
        if (read_bram) begin
            rd_data_reg <= ram[mem_rd_ptr[ADDR_W-1:0]];
        end
    end

    // Логика состояния FWFT (Управление rd_empty)
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_empty <= 1'b1;
        end else begin
            if (read_bram) begin
                // Если мы защелкиваем новые данные из памяти, они будут валидны на след. такте
                rd_empty <= 1'b0;
            end else if (rd_en && !rd_empty) begin
                // Если новые не пришли, а старые прочитали - буфер пуст
                rd_empty <= 1'b1;
            end
        end
    end

    // Внешний счетчик прочитанных слов (обновляется только при реальном чтении)
    wire [ADDR_W:0] rd_ptr_next = rd_ptr + (rd_en && !rd_empty);
    wire [ADDR_W:0] rd_cnt_next = wr_ptr_sync_bin - rd_ptr_next;

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr          <= 0;
            rd_ptr_gray     <= 0;
            rd_cnt          <= 0;
            rd_almost_empty <= 1'b1;
        end else begin
            rd_ptr          <= rd_ptr_next;
            rd_ptr_gray     <= bin2gray(rd_ptr_next);
            rd_cnt          <= rd_cnt_next;
            rd_almost_empty <= (rd_cnt_next <= ALMOST_EMPTY_THRESH);
        end
    end

endmodule
