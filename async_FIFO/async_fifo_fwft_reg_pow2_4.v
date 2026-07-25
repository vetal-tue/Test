module async_fifo_fwft_reg_pow2_4 #(
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

  localparam DEPTH = 1 << ADDR_W;

  // Внутренняя память (Атрибут подсказывает синтезатору использовать BRAM)
  // (* ram_style = "block" *) // Для Vivado можно добавить (* ram_style = "block" *)
  (* ram_style = "block" *) reg [DATA_W-1:0] mem[0:DEPTH-1];

  // -------------------------------------------------------------------------
  // Указатели
  // -------------------------------------------------------------------------
  // Домен записи
  reg [ADDR_W:0] wr_bin;
  reg [ADDR_W:0] wr_gray;
  wire [ADDR_W:0] wr_bin_next;
  wire [ADDR_W:0] wr_gray_next;

  // Домен чтения: Внутреннее чтение из BRAM
  reg [ADDR_W:0] rd_mem_bin;

  // Домен чтения: Пользовательский указатель (фактический вычитка)
  reg [ADDR_W:0] rd_user_bin;
  reg [ADDR_W:0] rd_user_gray;
  wire [ADDR_W:0] rd_user_bin_next;
  wire [ADDR_W:0] rd_user_gray_next;

  // Синхронизаторы (CDC)
  reg [ADDR_W:0] wr_gray_sync1, wr_gray_sync2;
  reg [ADDR_W:0] rd_user_gray_sync1, rd_user_gray_sync2;

  // -------------------------------------------------------------------------
  // Домен записи (wr_clk)
  // -------------------------------------------------------------------------
  assign wr_bin_next  = wr_bin + (wr_en && !wr_full);
  assign wr_gray_next = gray_encode(wr_bin_next);

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

  // Синхронизация пользовательского указателя чтения в домен записи
  always @(posedge wr_clk or posedge rst) begin
    if (rst) begin
      rd_user_gray_sync1 <= 0;
      rd_user_gray_sync2 <= 0;
    end else begin
      rd_user_gray_sync1 <= rd_user_gray;
      rd_user_gray_sync2 <= rd_user_gray_sync1;
    end
  end

  // Расчет статусов стороны записи
  wire [ADDR_W:0] wr_rd_user_bin_sync = gray2bin(rd_user_gray_sync2);
  wire [ADDR_W:0] wr_cnt_val = wr_bin_next - wr_rd_user_bin_sync;

  always @(posedge wr_clk or posedge rst) begin
    if (rst) begin
      wr_full        <= 1'b0;
      wr_cnt         <= 0;
      wr_almost_full <= 1'b0;
    end else begin
      wr_full        <= (wr_cnt_val == DEPTH);
      wr_cnt         <= wr_cnt_val;
      wr_almost_full <= (wr_cnt_val >= ALMOST_FULL_THRESH);
    end
  end

  // -------------------------------------------------------------------------
  // Домен чтения (rd_clk)
  // -------------------------------------------------------------------------

  // Синхронизация указателя записи в домен чтения
  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      wr_gray_sync1 <= 0;
      wr_gray_sync2 <= 0;
    end else begin
      wr_gray_sync1 <= wr_gray;
      wr_gray_sync2 <= wr_gray_sync1;
    end
  end

  wire [  ADDR_W:0] rd_wr_bin_sync = gray2bin(wr_gray_sync2);

  // === Конвейер предвыборки (FWFT) ===
  wire              user_rd = rd_en && !rd_empty;
  reg               mem_valid;
  reg  [DATA_W-1:0] mem_rd_data;

  wire              shift_to_dout = mem_valid && (rd_empty || user_rd);
  wire              mem_ready = !mem_valid || shift_to_dout;

  // BRAM содержит непрочитанные предвыборкой данные?
  wire              core_has_data = (rd_mem_bin != rd_wr_bin_sync);
  wire              core_rd_en = core_has_data && mem_ready;

  // Указатель чтения памяти BRAM
  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      rd_mem_bin <= 0;
    end else if (core_rd_en) begin
      rd_mem_bin <= rd_mem_bin + 1'b1;
    end
  end

  // Чтение BRAM (Чистый always-блок без reset для правильного инференса BRAM)
  always @(posedge rd_clk) begin
    if (core_rd_en) begin
      mem_rd_data <= mem[rd_mem_bin[ADDR_W-1:0]];
    end
  end

  // Управление валидностью конвейера и флагом rd_empty
  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      mem_valid <= 1'b0;
      rd_empty  <= 1'b1;
    end else begin
      if (core_rd_en && !shift_to_dout) mem_valid <= 1'b1;
      else if (!core_rd_en && shift_to_dout) mem_valid <= 1'b0;

      if (shift_to_dout && !user_rd) rd_empty <= 1'b0;
      else if (!shift_to_dout && user_rd) rd_empty <= 1'b1;
    end
  end

  // Перенос данных на выходной порт
  always @(posedge rd_clk) begin
    if (shift_to_dout) begin
      rd_data <= mem_rd_data;
    end
  end

  // === Пользовательский указатель чтения ===
  assign rd_user_bin_next  = rd_user_bin + user_rd;
  assign rd_user_gray_next = gray_encode(rd_user_bin_next);

  always @(posedge rd_clk or posedge rst) begin
    if (rst) begin
      rd_user_bin  <= 0;
      rd_user_gray <= 0;
    end else begin
      rd_user_bin  <= rd_user_bin_next;
      rd_user_gray <= rd_user_gray_next;
    end
  end

  // === Подсчет счетчиков со стороны чтения ===
  wire [ADDR_W:0] rd_cnt_val = rd_wr_bin_sync - rd_user_bin_next;

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
  // Вспомогательные функции
  // -------------------------------------------------------------------------
  function [ADDR_W:0] gray_encode(input [ADDR_W:0] bin);
    gray_encode = bin ^ (bin >> 1);
  endfunction

  function [ADDR_W:0] gray2bin(input [ADDR_W:0] gray);
    integer i;
    begin
      gray2bin[ADDR_W] = gray[ADDR_W];
      for (i = ADDR_W - 1; i >= 0; i = i - 1) begin
        gray2bin[i] = gray2bin[i+1] ^ gray[i];
      end
    end
  endfunction

endmodule
