module fifo_64to32_fwft1 (
    input  wire         clk,
    input  wire         rst,

    input  wire [63:0]  wr_data,
    input  wire         wr_en,
    output wire         full,

    output reg  [31:0]  rd_data,
    input  wire         rd_en,
    output wire         empty
);

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

    reg [31:0] buf_high;
    reg        buf_valid;
  
    // Пусто, только если буфер пуст И FIFO пуст (никаких запасных данных)
    assign empty = !(buf_valid || !fifo_empty);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            buf_high   <= 32'd0;
            buf_valid  <= 1'b0;
            rd_data    <= 32'd0;
            fifo_rd_en <= 1'b0;
        end else begin
            fifo_rd_en <= 1'b0;   // по умолчанию

            if (rd_en && !empty) begin
                if (!buf_valid) begin
                    // Читаем младшую половину с выхода FIFO (FWFT)
                    rd_data   <= fifo_rd_data[31:0];
                    buf_high  <= fifo_rd_data[63:32];
                    buf_valid <= 1'b1;
                    // ★ Сразу продвигаем FIFO, чтобы следующее слово
                    //   появилось к моменту, когда буфер освободится
                    if (!fifo_empty) begin
                        fifo_rd_en <= 1'b1;
                    end
                end else begin
                    // buf_valid == 1
                    // Отдаём старшую половину из буфера
                    rd_data   <= buf_high;
                    buf_valid <= 1'b0;
                    // FIFO уже прочитали заранее, здесь ничего не делаем
                end
            end
        end
    end

endmodule