module fifo_64to32_fwft4 #(
    parameter DEPTH = 16
) (
    input  wire        clk,
    input  wire        rst,
    input  wire [63:0] wr_data,
    input  wire        wr_en,
    output wire        full,
    output reg  [31:0] rd_data,
    input  wire        rd_en,
    output wire        empty
);

  wire [63:0] fifo_rd_data;
  wire        fifo_empty;
  reg         fifo_rd_en;

  fwft_fifo #(
      .DATA_WIDTH(64),
      .DEPTH(DEPTH)
  ) fifo_inst (
      .clk    (clk),
      .rst    (rst),
      .wr_data(wr_data),
      .wr_en  (wr_en),
      .full   (full),
      .rd_data(fifo_rd_data),
      .rd_en  (fifo_rd_en),
      .empty  (fifo_empty)
  );

  // ─── состояние ─────────────────────────────────────────────
  // state=0: нет данных (empty=1)
  // state=1: LOW_READY  — rd_data=low half, buf_high сохранён
  // state=2: HIGH_READY — rd_data=buf_high
  reg [ 1:0] state;
  reg [31:0] buf_high;

  localparam S_EMPTY = 2'd0, S_LOW = 2'd1, S_HIGH = 2'd2;

  assign empty = (state == S_EMPTY);

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state      <= S_EMPTY;
      rd_data    <= 32'd0;
      buf_high   <= 32'd0;
      fifo_rd_en <= 1'b0;
    end else begin
      fifo_rd_en <= 1'b0;  // default

      case (state)

        // ── EMPTY: ждём слова от FIFO ──────────────────
        S_EMPTY: begin
          // FWFT: как только FIFO выставил слово, берём его
          // без всякого rd_en от потребителя
          if (!fifo_empty) begin
            rd_data    <= fifo_rd_data[31:0];
            buf_high   <= fifo_rd_data[63:32];
            fifo_rd_en <= 1'b1;  // продвигаем FIFO
            state      <= S_LOW;
          end
        end

        // ── LOW_READY: потребитель читает младшую половину ─
        S_LOW: begin
          if (rd_en) begin
            // Отдаём low (уже на rd_data), переходим к high
            rd_data <= buf_high;
            state   <= S_HIGH;
          end
        end

        // ── HIGH_READY: потребитель читает старшую половину ─
        S_HIGH: begin
          if (rd_en) begin
            if (!fifo_empty) begin
              // Следующее 64-битное слово уже готово
              rd_data    <= fifo_rd_data[31:0];
              buf_high   <= fifo_rd_data[63:32];
              fifo_rd_en <= 1'b1;
              state      <= S_LOW;
            end else begin
              // Больше слов нет — уходим в EMPTY
              rd_data <= 32'd0;
              state   <= S_EMPTY;
            end
          end
        end

      endcase
    end
  end

endmodule
