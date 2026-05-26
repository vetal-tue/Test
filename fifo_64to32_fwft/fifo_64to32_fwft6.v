module fifo_64to32_fwft6 #(
    parameter DEPTH = 16
) (
    input wire clk,
    input wire rst,

    input  wire [63:0] wr_data,
    input  wire        wr_en,
    output wire        full,

    output wire [31:0] rd_data,
    input  wire        rd_en,
    output wire        empty
);

  wire [63:0] fifo_rd_data;
  wire        fifo_empty;
  wire        fifo_full;
  reg         fifo_rd_en;

  fwft_fifo #(
      .DATA_WIDTH(64),
      .DEPTH     (DEPTH)
  ) fifo_inst (
      .clk    (clk),
      .rst    (rst),
      .wr_data(wr_data),
      .wr_en  (wr_en),
      .full   (fifo_full),
      .rd_data(fifo_rd_data),
      .rd_en  (fifo_rd_en),
      .empty  (fifo_empty)
  );

  assign full = fifo_full;

  reg [31:0] buf_high;
  reg        buf_valid;

  // Голова 32-битного потока:
  //   если в буфере лежит старшая половина – отдаём её,
  //   иначе берём младшую половину с FWFT-выхода FIFO.
  assign rd_data = buf_valid ? buf_high : fifo_rd_data[31:0];

  // Пусто, только если буфер пуст И FIFO пуст
  assign empty   = !(buf_valid || !fifo_empty);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      buf_high   <= 32'd0;
      buf_valid  <= 1'b0;
      fifo_rd_en <= 1'b0;
    end else begin
      fifo_rd_en <= 1'b0;  // по умолчанию

      if (rd_en && !empty) begin
        if (buf_valid) begin
          // Читаем старшую половину – она сейчас на rd_data.
          // После чтения переходим к младшей половине следующего 64-бит слова
          // (оно уже ждёт на выходе FIFO, потому что FIFO продвинули раньше).
          buf_valid <= 1'b0;
          // fifo_rd_en не нужен
        end else begin
          // buf_valid == 0: читаем младшую половину прямо с FIFO.
          // Сохраняем старшую половину в буфер, продвигаем FIFO.
          buf_high   <= fifo_rd_data[63:32];
          buf_valid  <= 1'b1;
          fifo_rd_en <= 1'b1;  // съедаем 64-битное слово
        end
      end
    end
  end

endmodule
