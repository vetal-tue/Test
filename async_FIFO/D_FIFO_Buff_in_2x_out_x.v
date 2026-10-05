`timescale 1 ps / 1 ps

module D_FIFO_Buff_in_2x_out_x #(
    parameter FIFO_WIDTH  = 64,
    parameter FIFO_ADDR_W = 8
) (
    input wire wrclk,
    input wire rdclk,
    input wire wr_rst,
    input wire rd_rst,

    input  wire                    D_FIFO_wr_en,
    input  wire [  FIFO_WIDTH-1:0] D_FIFO_wrdata,
    output wire [   FIFO_ADDR_W:0] D_FIFO_wrcnt,
    input  wire                    D_FIFO_rd_en,
    output wire [FIFO_WIDTH/4-1:0] D_FIFO_rd_data,
    output wire [ FIFO_ADDR_W+1:0] D_FIFO_rd_cnt_out,
    output wire                    D_FIFO_wrfull,
    output wire                    D_FIFO_wrafull,
    output wire                    D_FIFO_rd_empty
);

  // ==============================================================================

  wire [FIFO_WIDTH-1:0] fifo_rd_data;
  wire                  fifo_rd_empty;
  wire [ FIFO_ADDR_W:0] fifo_rd_cnt;

  async_fifo_fwft_xilinx_style #(
      .DATA_W(FIFO_WIDTH),
      .ADDR_W(FIFO_ADDR_W)
  ) DATA_FIFO (

      .wr_clk         (wrclk),
      .wr_rst         (wr_rst),
      .wr_en          (D_FIFO_wr_en),
      .wr_data        (D_FIFO_wrdata),
      .wr_full        (D_FIFO_wrfull),
      .rd_clk         (rdclk),
      .rd_rst         (rd_rst),
      .rd_en          (fifo_rd_en  /*D_FIFO_rd_en*/),
      .rd_data        (fifo_rd_data),
      .rd_empty       (fifo_rd_empty),
      .wr_cnt         (D_FIFO_wrcnt),
      .rd_cnt         (fifo_rd_cnt),
      .wr_almost_full (D_FIFO_wrafull),
      .rd_almost_empty()

  );


  // ─── состояние ─────────────────────────────────────────────
  // state=0: нет данных (empty=1)
  // state=1: LOW_READY  — rd_data=low half, buf_high сохранён
  // state=2: HIGH_READY — rd_data=buf_high
  reg [             1:0] state;
  reg [FIFO_WIDTH/2-1:0] buf_high;
  reg                    fifo_rd_en;
  reg [FIFO_WIDTH/2-1:0] rd_data;
  reg [FIFO_ADDR_W+1:0] D_FIFO_rdcnt_local;

  localparam S_EMPTY = 2'd0, S_LOW = 2'd1, S_HIGH = 2'd2;

  assign D_FIFO_rd_empty = (state == S_EMPTY);
  assign D_FIFO_rd_data  = rd_data;
  assign D_FIFO_rd_cnt_out = D_FIFO_rdcnt_local;

  always @* begin
    case (state)

      S_EMPTY: D_FIFO_rdcnt_local = {fifo_rd_cnt, 1'b0};

      S_LOW: D_FIFO_rdcnt_local = {fifo_rd_cnt, 1'b0} + 2;

      S_HIGH: D_FIFO_rdcnt_local = {fifo_rd_cnt, 1'b0} + 1;

      default: D_FIFO_rdcnt_local = {fifo_rd_cnt, 1'b0};

    endcase
  end

  always @(posedge rdclk or posedge rd_rst) begin
    if (rd_rst) begin
      state      <= S_EMPTY;
      rd_data    <= {FIFO_WIDTH / 2{1'b0}};
      buf_high   <= {FIFO_WIDTH / 2{1'b0}};
      fifo_rd_en <= 1'b0;
    end else begin
      fifo_rd_en <= 1'b0;  // default

      case (state)

        // ── EMPTY: ждём слова от FIFO ──────────────────
        S_EMPTY: begin
          // FWFT: как только FIFO выставил слово, берём его
          // без всякого rd_en от потребителя
          if (!fifo_rd_empty) begin
            rd_data    <= fifo_rd_data[FIFO_WIDTH/2-1:0];
            buf_high   <= fifo_rd_data[FIFO_WIDTH-1:FIFO_WIDTH/2];
            fifo_rd_en <= 1'b1;  // продвигаем FIFO
            state      <= S_LOW;
          end
        end

        // ── LOW_READY: потребитель читает младшую половину ─
        S_LOW: begin
          if (D_FIFO_rd_en) begin
            // Отдаём low (уже на rd_data), переходим к high
            rd_data <= buf_high;
            state   <= S_HIGH;
          end
        end

        // ── HIGH_READY: потребитель читает старшую половину ─
        S_HIGH: begin
          if (D_FIFO_rd_en) begin
            if (!fifo_rd_empty) begin
              // Следующее 64-битное слово уже готово
              rd_data    <= fifo_rd_data[FIFO_WIDTH/2-1:0];
              buf_high   <= fifo_rd_data[FIFO_WIDTH-1:FIFO_WIDTH/2];
              fifo_rd_en <= 1'b1;
              state      <= S_LOW;
            end else begin
              // Больше слов нет — уходим в EMPTY
              rd_data <= 32'd0;
              state   <= S_EMPTY;
            end
          end
        end

        // ── Защита от некорректного состояния ───────────
        default: begin
          rd_data    <= {FIFO_WIDTH / 2{1'b0}};
          buf_high   <= {FIFO_WIDTH / 2{1'b0}};
          fifo_rd_en <= 1'b0;
          state      <= S_EMPTY;
        end

      endcase
    end
  end


endmodule
