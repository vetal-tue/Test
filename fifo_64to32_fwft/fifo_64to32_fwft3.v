module fifo_64to32_fwft3 (
    input  wire         clk,
    input  wire         rst,

    // 64-битная запись
    input  wire [63:0]  wr_data,
    input  wire         wr_en,
    output wire         full,

    // 32-битное чтение
    output reg  [31:0]  rd_data,
    input  wire         rd_en,
    output wire         empty
);

    // -------------------------------
    // Внутренний 64-битный FWFT FIFO
    // Предполагается:
    //  - если fifo_empty=0, fifo_rd_data валиден
    //  - после fifo_rd_en данные обновляются не раньше следующего такта
    // -------------------------------
    wire [63:0] fifo_rd_data;
    wire        fifo_empty;
    wire        fifo_full;
    reg         fifo_rd_en;

    fwft_fifo #(
        .DATA_WIDTH (64),
        .DEPTH      (/* depth */)
    ) fifo_inst (
        .clk      (clk),
        .rst      (rst),
        .wr_data  (wr_data),
        .wr_en    (wr_en),
        .full     (fifo_full),
        .rd_data  (fifo_rd_data),
        .rd_en    (fifo_rd_en),
        .empty    (fifo_empty)
    );

    assign full = fifo_full;

    // -------------------------------
    // Двухстадийный буфер
    // -------------------------------
    reg [63:0] buff;         // текущее слово (на выдачу)
    reg        buf_valid;

    reg [63:0] next_buf;    // предвыбранное слово
    reg        next_valid;

    reg        half;        // 0: low[31:0], 1: high[63:32]

    // Есть ли хотя бы одно 32-битное слово на выход
    assign empty = !buf_valid;

    // Удобные сигналы
    wire consume = rd_en && buf_valid &&  half; // съедаем старшую половину → слово закончено
    
    // Нужен ли нам префетч в этом такте
    // Держим next_buf заполненным, если:
    //  - он сейчас пуст, И
    //  - есть что читать из FIFO, И
    //  - мы не перетаскиваем next_buf → buff в этом же такте (освобождаем слот)
    wire will_shift   = (!buf_valid && next_valid) || (consume && next_valid);
    wire need_prefetch = (!next_valid) && (!fifo_empty) && (!will_shift);

    // -------------------------------
    // Основной always-блок
    // Порядок: consume → shift → prefetch
    // -------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buff <= 64'd0;
            buf_valid  <= 1'b0;
            next_buf   <= 64'd0;
            next_valid <= 1'b0;
            half       <= 1'b0;
            rd_data    <= 32'd0;
            fifo_rd_en <= 1'b0;
        end else begin
            fifo_rd_en <= 1'b0;

            // -----------------------
            // 1) Выдача данных (только из buff)
            // -----------------------
            if (rd_en && buf_valid) begin
                // if (!half) begin
                //     rd_data <= buff[31:0];
                //     half    <= 1'b1;
                // end else begin
                //     rd_data <= buff[63:32];
                //     half    <= 1'b0;
                // end
                rd_data <= (half) ? buff[63:32] : buff[31:0];
                half    <= ~half;
            end

            // -----------------------
            // 2) Завершили слово? (consume)
            // -----------------------
            if (consume) begin
                if (next_valid) begin
                    // Берём уже предвыбранное
                    buff        <= next_buf;
                    buf_valid  <= 1'b1;
                    next_valid <= 1'b0;
                end else begin
                    // Нечего подхватить
                    buf_valid <= 1'b0;
                end
            end

            // -----------------------
            // 3) Если buff пуст — пробуем заполнить из next_buf
            // -----------------------
            if (!buf_valid && next_valid) begin
                buff        <= next_buf;
                buf_valid  <= 1'b1;
                next_valid <= 1'b0;
                half       <= 1'b0;
            end

            // -----------------------
            // 4) Prefetch из FIFO → next_buf
            // (без прямого использования на выход)
            // -----------------------
            if (need_prefetch) begin
                fifo_rd_en <= 1'b1;
            end

            // Захват данных после fifo_rd_en (1-тактная латентность)
            // Используем прошлое значение fifo_rd_en
            if (fifo_rd_en) begin
                next_buf   <= fifo_rd_data;
                next_valid <= 1'b1;
            end
        end
    end

endmodule