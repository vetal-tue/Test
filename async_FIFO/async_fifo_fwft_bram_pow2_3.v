module async_fifo_fwft_bram_pow2_3 #(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,
    parameter ALMOST_FULL_THRESH = (1 << ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
) (
    input                   wr_clk,
    input                   rst,
    // write side
    input                   wr_en,
    input      [DATA_W-1:0] wr_data,
    output reg              wr_full,
    output reg              wr_almost_full,
    output reg [  ADDR_W:0] wr_cnt,
    // read side
    input                   rd_clk,
    input                   rd_en,
    output reg [DATA_W-1:0] rd_data,
    output reg [  ADDR_W:0] rd_cnt,
    output reg              rd_empty,
    output reg              rd_almost_empty
);

  // Внутренняя память (Атрибут подсказывает синтезатору использовать BRAM)
  // (* ram_style = "block" *) // Для Vivado можно добавить (* ram_style = "block" *)
  reg [DATA_W-1:0] mem[0:(1<<ADDR_W)-1];

  // Указатели для домена записи
  reg [ADDR_W:0] wr_bin;
  reg [ADDR_W:0] wr_gray;
  wire [ADDR_W:0] wr_bin_next;
  wire [ADDR_W:0] wr_gray_next;

  // Указатели для домена чтения (указывают на адрес в BRAM)
  reg [ADDR_W:0] rd_bin;
  reg [ADDR_W:0] rd_gray;
  wire [ADDR_W:0] rd_bin_next;
  wire [ADDR_W:0] rd_gray_next;

  // Регистры синхронизаторов
  reg [ADDR_W:0] wr_gray_sync1, wr_gray_sync2;
  reg [ADDR_W:0] rd_gray_sync1, rd_gray_sync2;

  // -------------------------------------------------------------------------
  // Домен записи (wr_clk)
  // -------------------------------------------------------------------------

  assign wr_bin_next  = wr_bin + (wr_en & ~wr_full);
  assign wr_gray_next = wr_bin_next ^ (wr_bin_next >> 1);

  always @(posedge wr_clk or posedge rst) begin
    if (rst) begin
      wr_bin  <= 0;
      wr_gray <= 0;
    end else begin
      wr_bin  <= wr_bin_next;
      wr_gray <= wr_gray_next;
    end
  end

  // Синхронная запись в BRAM
  always @(posedge wr_clk) begin
    if (wr_en && !wr_full) begin
      mem[wr_bin[ADDR_W-1:0]] <= wr_data;
    end
  end

  // Синхронизация указателя чтения
  always @(posedge wr_clk or posedge rst) begin
    if (rst) begin
      rd_gray_sync1 <= 0;
      rd_gray_sync2 <= 0;
    end else begin
      rd_gray_sync1 <= rd_gray;
      rd_gray_sync2 <= rd_gray_sync1;
    end
  end

  wire [ADDR_W:0] wr_rd_bin_sync = gray2bin(rd_gray_sync2);
  wire [ADDR_W:0] wr_cnt_val = wr_bin_next - wr_rd_bin_sync;

  always @(posedge wr_clk or posedge rst) begin
    if (rst) begin
      wr_full        <= 1'b0;
      wr_cnt         <= 0;
      wr_almost_full <= 1'b0;
    end else begin
      wr_full <= (wr_gray_next == {~rd_gray_sync2[ADDR_W:ADDR_W-1], rd_gray_sync2[ADDR_W-2:0]});
      wr_cnt <= wr_cnt_val;
      wr_almost_full <= (wr_cnt_val >= ALMOST_FULL_THRESH);
    end
  end

  // -------------------------------------------------------------------------
  // Домен чтения (rd_clk)
  // -------------------------------------------------------------------------

  // Синхронизация указателя записи
  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      wr_gray_sync1 <= 0;
      wr_gray_sync2 <= 0;
    end else begin
      wr_gray_sync1 <= wr_gray;
      wr_gray_sync2 <= wr_gray_sync1;
    end
  end

  // Флаг пустоты "внутреннего" FIFO (самой памяти)
  reg core_empty;
  always @(posedge rd_clk or posedge rst) begin
    if (rst) core_empty <= 1'b1;
    else core_empty <= (rd_gray_next == wr_gray_sync2);
  end

  // === Логика предвыборки (FWFT Prefetch Logic) ===

  wire user_rd       = rd_en && !rd_empty; // Фактическое чтение пользователем
  reg  mem_valid;                          // 1, если в mem_rd_data есть готовое непрочитанное слово
  reg [DATA_W-1:0] mem_rd_data;  // Буферный регистр выхода BRAM

  // Условия движения конвейера
  wire shift_to_dout = mem_valid && (rd_empty || user_rd); // Перенос из буфера BRAM на выход
  wire mem_ready     = !mem_valid || shift_to_dout;        // BRAM буфер готов принять новое слово
  wire core_rd_en = !core_empty && mem_ready;  // Читаем из BRAM

  // Обновление указателей чтения из BRAM
  assign rd_bin_next  = rd_bin + core_rd_en;
  assign rd_gray_next = rd_bin_next ^ (rd_bin_next >> 1);

  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      rd_bin  <= 0;
      rd_gray <= 0;
    end else begin
      rd_bin  <= rd_bin_next;
      rd_gray <= rd_gray_next;
    end
  end

  // State Machine флагов конвейера
  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      mem_valid <= 1'b0;
      rd_empty  <= 1'b1;
    end else begin
      // Флаг буфера BRAM
      if (core_rd_en && !shift_to_dout) mem_valid <= 1'b1;
      else if (!core_rd_en && shift_to_dout) mem_valid <= 1'b0;

      // Флаг выхода rd_empty (инвертированная валидность rd_data)
      if (shift_to_dout && !user_rd) rd_empty <= 1'b0;
      else if (!shift_to_dout && user_rd) rd_empty <= 1'b1;
    end
  end

  // Продвижение данных (Data Pipeline). 
  // Без сброса (rst), чтобы маппинг в BRAM был идеальным.
  always @(posedge rd_clk) begin
    if (core_rd_en) mem_rd_data <= mem[rd_bin[ADDR_W-1:0]];

    if (shift_to_dout) rd_data <= mem_rd_data;
  end

  // === Подсчет доступных слов для чтения (rd_cnt) ===

  wire [ADDR_W:0] rd_wr_bin_sync = gray2bin(wr_gray_sync2);

  // Предрасчет следующих состояний флагов для точного rd_cnt без задержек
  wire mem_valid_next = (core_rd_en && !shift_to_dout) ? 1'b1 :
                          (!core_rd_en && shift_to_dout) ? 1'b0 : mem_valid;

  wire rd_empty_next  = (shift_to_dout && !user_rd) ? 1'b0 :
                          (!shift_to_dout && user_rd) ? 1'b1 : rd_empty;

// Всего слов = (Слова в BRAM) + (1 если есть в mem_rd_data) + (1 если есть на выходе)
//   wire [ADDR_W:0] rd_cnt_val = (rd_wr_bin_sync - rd_bin_next) + mem_valid_next + (!rd_empty_next);
    wire [ADDR_W:0] rd_cnt_val = (rd_wr_bin_sync - rd_bin_next);

  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      rd_cnt          <= 0;
      rd_almost_empty <= 1'b1;
    end else begin
      rd_cnt          <= rd_cnt_val;
      rd_almost_empty <= (rd_cnt_val <= ALMOST_EMPTY_THRESH);
    end
  end

  // -------------------------------------------------------------------------
  // Вспомогательная функция: Конвертация Gray -> Binary
  // -------------------------------------------------------------------------
  function [ADDR_W:0] gray2bin;
    input [ADDR_W:0] gray;
    integer i;
    begin
      gray2bin[ADDR_W] = gray[ADDR_W];
      for (i = ADDR_W - 1; i >= 0; i = i - 1) begin
        gray2bin[i] = gray2bin[i+1] ^ gray[i];
      end
    end
  endfunction

endmodule
