`timescale 1 ps / 1 ps

module D_FIFO_Buff_in_4x_out_x #(
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
    output wire [ FIFO_ADDR_W+2:0] D_FIFO_rd_cnt_out,
    output wire                    D_FIFO_wrfull,
    output wire                    D_FIFO_wrafull,
    output wire                    D_FIFO_rd_empty
);

  // ==============================================================================

  localparam OUT_WIDTH = FIFO_WIDTH / 4;

  // Состояния:
  //
  // S_EMPTY : нет подготовленного данных
  // S_Q0    : наружу доступна четверть  [OUT_WIDTH-1 : 0]
  // S_Q1    : наружу доступна четверть  [2*OUT_WIDTH-1 : OUT_WIDTH]
  // S_Q2    : наружу доступна четверть  [3*OUT_WIDTH-1 : 2*OUT_WIDTH]
  // S_Q3    : наружу доступна четверть  [FIFO_WIDTH-1 : 3*OUT_WIDTH]
  //
  // Для FIFO_WIDTH=64:
  //
  // S_Q0 -> [15:0]
  // S_Q1 -> [31:16]
  // S_Q2 -> [47:32]
  // S_Q3 -> [63:48]

  localparam S_EMPTY = 3'd0;
  localparam S_Q1    = 3'd1;
  localparam S_Q2    = 3'd2;
  localparam S_Q3    = 3'd3;
  localparam S_Q4    = 3'd4;

  // =========================================================================
  // Внутренний async FWFT FIFO
  // =========================================================================

  wire [FIFO_WIDTH-1:0] fifo_rd_data;
  wire                  fifo_rd_empty;
  reg                   fifo_rd_en;
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
      .rd_en          (fifo_rd_en),
      .rd_data        (fifo_rd_data),
      .rd_empty       (fifo_rd_empty),
      .wr_cnt         (D_FIFO_wrcnt),
      .rd_cnt         (fifo_rd_cnt),
      .wr_almost_full (D_FIFO_wrafull),
      .rd_almost_empty()
  );

  // =========================================================================
  // Буфер одного полного слова FIFO
  // =========================================================================

  reg [FIFO_WIDTH-1:0] buf_word;
  reg [ OUT_WIDTH-1:0] rd_data;
  reg [           2:0] state;



  // =========================================================================
  // Выходы
  // =========================================================================

  assign D_FIFO_rd_empty = (state == S_EMPTY);
  assign D_FIFO_rd_data  = rd_data;

//   reg [FIFO_ADDR_W+2:0] D_FIFO_rdcnt_local;
  //   always @* begin
  //     case (state)

  //       S_EMPTY: D_FIFO_rdcnt_local = {fifo_rd_cnt, 2'b00};

  //       S_Q1: D_FIFO_rdcnt_local = {fifo_rd_cnt, 2'b00} + 4;

  //       S_Q2: D_FIFO_rdcnt_local = {fifo_rd_cnt, 2'b00} + 3;

  //       S_Q3: D_FIFO_rdcnt = {fifo_rd_cnt, 2'b00} + 2;

  //       S_Q4: D_FIFO_rdcnt_local = {fifo_rd_cnt, 2'b00} + 1;

  //       default: D_FIFO_rdcnt_local = {fifo_rd_cnt, 2'b00};

  //     endcase
  //   end
  //    assign D_FIFO_rdcnt = D_FIFO_rdcnt_local;


  // ─── сколько subword'ов уже лежит в локальном буфере ────────────────────
  reg [2:0] subword_buf_cnt;
  always @(*) begin
    case (state)
      S_EMPTY: subword_buf_cnt = 3'd0;
      S_Q1: subword_buf_cnt = 3'd4;
      S_Q2: subword_buf_cnt = 3'd3;
      S_Q3: subword_buf_cnt = 3'd2;
      S_Q4: subword_buf_cnt = 3'd1;
      default: subword_buf_cnt = 3'd0;
    endcase
  end
  // ─── 64-битных слов в FIFO → 16-битных слов снаружи ─────────────────────
  // rd_cnt_FIFO * 4 = {fifo_rd_cnt, 2'b00}
  assign D_FIFO_rd_cnt_out = {fifo_rd_cnt, 2'b00} + subword_buf_cnt;

  // =========================================================================
  // Разбор 64 -> 16
  // =========================================================================
  //
  // Важный момент:
  //
  // FWFT FIFO уже содержит валидное fifo_rd_data, когда !fifo_rd_empty.
  //
  // В состоянии S_EMPTY мы:
  //   1. забираем fifo_rd_data во внутренний buf_word;
  //   2. сразу выдаём младшие 16 бит;
  //   3. делаем fifo_rd_en = 1, чтобы продвинуть FIFO к следующему слову.
  //
  // После этого четыре части текущего слова выдаются последовательно.
  //
  // Доступ к следующему 64-битному слову происходит в момент чтения
  // последней, четвёртой части текущего слова. Поэтому дополнительного
  // такта простоя между словами нет.
  //

  always @(posedge rdclk or posedge rd_rst) begin
    if (rd_rst) begin

      state      <= S_EMPTY;
      buf_word   <= {FIFO_WIDTH{1'b0}};
      rd_data    <= {OUT_WIDTH{1'b0}};
      fifo_rd_en <= 1'b0;

    end else begin

      // По умолчанию FIFO не читаем.
      fifo_rd_en <= 1'b0;

      case (state)

        // ── EMPTY: ждём 64-битное слово от FIFO ─────────────
        S_EMPTY: begin

          if (!fifo_rd_empty) begin

            // Сохраняем всё 64-битное слово
            buf_word <= fifo_rd_data;

            // Сразу выдаём младшую четверть
            rd_data <= fifo_rd_data[OUT_WIDTH-1:0];

            // Продвигаем FWFT FIFO
            fifo_rd_en <= 1'b1;

            // Следующая четверть будет [31:16]
            state <= S_Q1;
          end
        end


        // ── S_Q1: потребитель читает первый subword ─────────
        S_Q1: begin
          if (D_FIFO_rd_en) begin
            rd_data <= buf_word[(2*OUT_WIDTH)-1 : OUT_WIDTH];
            state   <= S_Q2;
          end
        end


        // ── S_Q2: потребитель читает второй subword ─────────
        S_Q2: begin
          if (D_FIFO_rd_en) begin
            rd_data <= buf_word[(3*OUT_WIDTH)-1 : (2*OUT_WIDTH)];
            state   <= S_Q3;
          end
        end


        // ── S_Q3: потребитель читает третий subword ─────────
        S_Q3: begin
          if (D_FIFO_rd_en) begin
            rd_data <= buf_word[FIFO_WIDTH-1 : (3*OUT_WIDTH)];
            state   <= S_Q4;
          end
        end


        // =============================================================
        // QUARTER 3:
        // [FIFO_WIDTH-1 : 3*OUT_WIDTH]
        //
        // После чтения последней четверти:
        //
        //   если FIFO уже содержит следующее слово -
        //   сразу загружаем его и выдаём его младшую четверть;
        //
        //   если FIFO пуст - переходим в S_EMPTY.
        // =============================================================

        S_Q4: begin

          if (D_FIFO_rd_en) begin

            if (!fifo_rd_empty) begin

              // Загружаем следующее полное слово
              buf_word <= fifo_rd_data;

              // Сразу выдаём его младшую четверть
              rd_data <= fifo_rd_data[OUT_WIDTH-1:0];

              // Продвигаем FIFO
              fifo_rd_en <= 1'b1;

              // Следующая выдача -- QUARTER 1
              state <= S_Q1;

            end else begin

              // Следующего слова пока нет
              rd_data <= {OUT_WIDTH{1'b0}};
              state   <= S_EMPTY;

            end
          end
        end


        // =============================================================
        // Защита от некорректного состояния
        // =============================================================

        default: begin

          state      <= S_EMPTY;
          buf_word   <= {FIFO_WIDTH{1'b0}};
          rd_data    <= {OUT_WIDTH{1'b0}};
          fifo_rd_en <= 1'b0;

        end

      endcase

    end
  end

endmodule
