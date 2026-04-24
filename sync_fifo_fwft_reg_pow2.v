module sync_fifo_fwft_reg_pow2 #
(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,

    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
)
(
    input                     clk,
    input                     rst, 

    // write side
    input                     wr_en,
    input      [DATA_W-1:0]   wr_data,
    output reg                wr_full,
    output reg                wr_almost_full,

    output reg [ADDR_W:0]     usedw, 

    // read side
    input                     rd_en,
    output reg [DATA_W-1:0]   rd_data,
    output reg                rd_empty,
    output reg                rd_almost_empty 
);

    // =========================================================================
    // Внутренние сигналы и память
    // =========================================================================
    
    // Массив памяти (инструменты синтеза распознают это как BRAM)
    reg [DATA_W-1:0] mem [0:(1<<ADDR_W)-1];

    // Указатели RAM (на 1 бит шире для удобства вычислений и отладки, 
    // хотя физически RAM никогда не заполнится на все 1<<ADDR_W слов, 
    // так как одно слово всегда "выпадает" в регистр rd_data)
    reg [ADDR_W:0] wr_ptr;
    reg [ADDR_W:0] rd_ptr;

    // Внутренние флаги успешных транзакций
    wire do_write = wr_en && !wr_full;
    wire do_read  = rd_en && !rd_empty;

    // Состояние RAM и логика prefetch
    wire ram_empty = (wr_ptr == rd_ptr);
    
    // Мы читаем из RAM, если там есть данные И (выходной регистр пуст ИЛИ мы прямо сейчас его читаем)
    wire rd_data_valid = !rd_empty;
    wire ram_rd_en = !ram_empty && (!rd_data_valid || do_read);

    // Следующее состояние счетчика usedw
    reg [ADDR_W:0] usedw_next;

    always @(*) begin
        usedw_next = usedw;
        if (do_write && !do_read) begin
            usedw_next = usedw + 1'b1;
        end else if (!do_write && do_read) begin
            usedw_next = usedw - 1'b1;
        end
    end

    // =========================================================================
    // Инференс Block RAM
    // =========================================================================
    
    // Порт записи
    always @(posedge clk) begin
        if (do_write) begin
            mem[wr_ptr[ADDR_W-1:0]] <= wr_data;
        end
    end

    // Синхронный порт чтения с регистровым выходом (мапится в выходной регистр BRAM)
    always @(posedge clk) begin
        if (ram_rd_en) begin
            rd_data <= mem[rd_ptr[ADDR_W-1:0]];
        end
    end

    // =========================================================================
    // Указатели, счетчик и зарегистрированные флаги
    // =========================================================================

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr          <= 0;
            rd_ptr          <= 0;
            usedw           <= 0;
            wr_full         <= 1'b0;
            wr_almost_full  <= 1'b0;
            rd_almost_empty <= 1'b1;
            rd_empty        <= 1'b1;
        end else begin
            // Обновление указателей
            if (do_write)  wr_ptr <= wr_ptr + 1'b1;
            if (ram_rd_en) rd_ptr <= rd_ptr + 1'b1;

            // Обновление точного счетчика
            usedw <= usedw_next;

            // Зарегистрированные флаги (считаются от usedw_next для отсутствия задержек)
            wr_full         <= (usedw_next == (1<<ADDR_W));
            wr_almost_full  <= (usedw_next >= ALMOST_FULL_THRESH);
            rd_almost_empty <= (usedw_next <= ALMOST_EMPTY_THRESH);

            // Логика зарегистрированного флага rd_empty для FWFT
            // Если мы читаем из RAM, данные будут валидны на следующем такте
            if (ram_rd_en) begin
                rd_empty <= 1'b0;
            end 
            // Если мы читаем данные с выхода, а новых из RAM нет, то становимся пустыми
            else if (do_read) begin
                rd_empty <= 1'b1;
            end
        end
    end

endmodule
