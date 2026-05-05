module fifo_64to32_fwft2 (
    input  wire         clk,
    input  wire         rst,

    input  wire [63:0]  wr_data,
    input  wire         wr_en,
    output wire         full,

    output reg  [31:0]  rd_data,
    input  wire         rd_en,
    output wire         empty
);

    // Внутреннее 64-битное FWFT FIFO
    wire [63:0] fifo_rd_data;
    wire        fifo_empty;
    wire        fifo_full;
    reg         fifo_rd_en;

    fwft_fifo #(
        .DATA_WIDTH (64),
        .DEPTH      (/* глубина */)
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

    // Двойной буфер
    reg [63:0] buff;         // текущее расходуемое слово
    reg        buf_valid;   // буфер содержит действительное слово
    reg [63:0] next_buf;    // предвыбранное следующее слово
    reg        next_valid;  // next_buf содержит действительное слово

    reg        half;        // 0 – выдаём младшую половину, 1 – старшую

    // ---------- empty: есть ли хоть одно 32-битное слово ----------
    // Слово доступно, если: текущий буфер валиден, или предвыборка валидна, или FIFO не пуст (FWFT)
    assign empty = !(buf_valid || next_valid || !fifo_empty);

    // ---------- Основной автомат ----------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buff        <= 64'd0;
            buf_valid  <= 1'b0;
            next_buf   <= 64'd0;
            next_valid <= 1'b0;
            half       <= 1'b0;
            rd_data    <= 32'd0;
            fifo_rd_en <= 1'b0;
        end else begin
            fifo_rd_en <= 1'b0;   // по умолчанию

            // ------------------ Предвыборка (prefetch) ------------------
            // Если слот next_buf свободен, а FIFO не пуст – забираем слово заранее
            if (!next_valid && !fifo_empty) begin
                fifo_rd_en  <= 1'b1;
                next_buf    <= fifo_rd_data;
                next_valid  <= 1'b1;
            end

            // ------------------ Заполнение текущего буфера ------------------
            // Если buff пуст, а предвыборка готова – немедленно перекладываем
            if (!buf_valid && next_valid) begin
                buff        <= next_buf;
                buf_valid  <= 1'b1;
                next_valid <= 1'b0;
                half       <= 1'b0;          // начинаем с младшей половины
            end
            // Если buff пуст, предвыборки нет, но FIFO не пусто (FWFT) – взять напрямую
            else if (!buf_valid && !next_valid && !fifo_empty) begin
                // Этот случай срабатывает в первом такте, когда данные только появились
                buff        <= fifo_rd_data;  // сохраняем текущее слово FIFO
                buf_valid  <= 1'b1;
                half       <= 1'b0;
                // FIFO продвигать не надо, т.к. мы используем его текущее выходное слово
            end

            // ------------------ Чтение потребителем ------------------
            if (rd_en && !empty) begin
                if (!buf_valid) begin
                    // Ситуация, когда буфер пуст, но empty=0, значит данные есть
                    // в next_buf или прямо на выходе FIFO. Однако автомат всегда
                    // переносит данные в buff, поэтому эта ветка не должна достигаться.
                    // Оставлена для безопасности.
                    if (next_valid) begin
                        buff       <= next_buf;
                        buf_valid <= 1'b1;
                        next_valid<= 1'b0;
                        half      <= 1'b0;
                        rd_data   <= next_buf[31:0];
                    end else if (!fifo_empty) begin
                        buff       <= fifo_rd_data;
                        buf_valid <= 1'b1;
                        half      <= 1'b0;
                        rd_data   <= fifo_rd_data[31:0];
                    end
                end else begin
                    // buf_valid == 1
                    if (!half) begin
                        // отдаём младшую половину
                        rd_data <= buff[31:0];
                        half    <= 1'b1;
                    end else begin
                        // отдаём старшую половину
                        rd_data <= buff[63:32];
                        half    <= 1'b0;

                        // буфер освобождается – подхватываем next_buf, если есть
                        if (next_valid) begin
                            buff        <= next_buf;
                            buf_valid  <= 1'b1;
                            next_valid <= 1'b0;
                        end else begin
                            buf_valid <= 1'b0;
                        end
                    end
                end
            end
        end
    end

endmodule