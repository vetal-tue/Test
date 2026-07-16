module sync_fifo_fwft_reg_pow2_GEM #(
    parameter DATA_W = 16,
    parameter ADDR_W = 3,
    parameter ALMOST_FULL_THRESH = (1 << ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
) (
    input                   clk,
    input                   rst,
    // write side
    input                   wr_en,
    input      [DATA_W-1:0] wr_data,
    output reg              wr_full,
    output reg              wr_almost_full,
    output reg [  ADDR_W:0] usedw,
    // read side
    input                   rd_en,
    output reg [DATA_W-1:0] rd_data,
    output reg              rd_empty,
    output reg              rd_almost_empty
);

  // Указатели для записи и чтения из RAM
  reg [ADDR_W-1:0] wr_ptr;
  reg [ADDR_W-1:0] rd_ptr;

  // Двухпортовая память
  // Локальные параметры и объявление памяти
  localparam DEPTH = 1 << ADDR_W;

  // Для Xilinx/AMD Vivado:
  (* ram_style = "block" *) reg [DATA_W-1:0] ram[0:DEPTH-1];

  // // Для Intel/Altera Quartus:
  // (* ramstyle = "M20K" *) reg [DATA_W-1:0] ram[0:DEPTH-1];

  // Сигналы успешной транзакции
  wire do_pop = rd_en && !rd_empty;

  // Разрешаем запись, если FIFO не заполнено, ИЛИ если оно заполнено, но сейчас читается
  wire do_push = wr_en && (!wr_full || do_pop);

  // Логика обхода RAM
  wire bypass_to_rd_data = do_push && (rd_empty || (wr_ptr == rd_ptr && do_pop));
  wire load_from_ram = do_pop && (wr_ptr != rd_ptr);
  wire ram_write_en = do_push && !bypass_to_rd_data;

  // Предвычисление следующего состояния счетчика usedw
  reg [ADDR_W:0] usedw_next;
  always @(*) begin
    case ({
      do_push, do_pop
    })
      2'b10: usedw_next = usedw + 1'b1;  // Только запись
      2'b01: usedw_next = usedw - 1'b1;  // Только чтение
      default:
      usedw_next = usedw;  // Нет транзакций или R+W одновременно
    endcase
  end

  // Основной синхронный процесс управления
  always @(posedge clk) begin
    if (rst) begin
      wr_ptr          <= {ADDR_W{1'b0}};
      rd_ptr          <= {ADDR_W{1'b0}};
      rd_data         <= {DATA_W{1'b0}};
      rd_empty        <= 1'b1;
      wr_full         <= 1'b0;
      wr_almost_full  <= 1'b0;
      rd_almost_empty <= 1'b1;
      usedw           <= {(ADDR_W + 1) {1'b0}};
    end else begin
      // 1. Управление выходным регистром данных и указателем чтения
      if (bypass_to_rd_data) begin
        rd_data <= wr_data;
      end else if (load_from_ram) begin
        rd_data <= ram[rd_ptr];
        rd_ptr  <= rd_ptr + 1'b1;
      end

      // 2. Запись в RAM и обновление указателя записи
      if (ram_write_en) begin
        ram[wr_ptr] <= wr_data;
        wr_ptr      <= wr_ptr + 1'b1;
      end

      // 3. Синхронное обновление счетчика и статусных флагов
      usedw           <= usedw_next;
      rd_empty        <= (usedw_next == 0);
      wr_full         <= (usedw_next == (1 << ADDR_W));
      wr_almost_full  <= (usedw_next >= ALMOST_FULL_THRESH);
      rd_almost_empty <= (usedw_next <= ALMOST_EMPTY_THRESH);
    end
  end

endmodule
