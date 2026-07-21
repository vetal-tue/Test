module sync_fifo_fwft_reg_pow2_GEM_nobypass #
(
parameter DATA_W = 16,
parameter ADDR_W = 4,
parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 1,
parameter ALMOST_EMPTY_THRESH = 1
)
(
input                     clk,
input                     rst,
// write side
input                     wr_en,
input      [DATA_W-1:0]   wr_data,
output reg                wr_full,
output reg                wr_almost_full,
output reg [ADDR_W:0]     usedw,
// read side
input                     rd_en,
output reg [DATA_W-1:0]   rd_data,
output reg                rd_empty,
output reg                rd_almost_empty
);

  // Указатели адресов RAM
  reg [ADDR_W-1:0] wr_ptr;
  reg [ADDR_W-1:0] rd_ptr;
  
  // Счетчик слов, находящихся конкретно внутри массива RAM (не включая rd_data)
  reg [ADDR_W:0]   ram_count;

  // Двухпортовая память
  // Локальные параметры и объявление памяти
  localparam DEPTH = 1 << ADDR_W;
  localparam MEM_BITS = DEPTH * DATA_W;

  // Для Xilinx/AMD Vivado:    
  localparam RAM_STYLE = (MEM_BITS >= 4096) ? "block" : "distributed";  
  (* ram_style = RAM_STYLE *) reg [DATA_W-1:0] ram[0:DEPTH-1];


  // // Для Intel/Altera Quartus:
  // localparam RAM_STYLE = (MEM_BITS >= 4096) ? "M20K" : "MLAB";
  // (* ramstyle = RAM_STYLE *) reg [DATA_W-1:0] ram[0:DEPTH-1];

  // Сигналы успешной транзакции
  wire do_pop       = rd_en && !rd_empty;
  
  // КЛЮЧЕВОЕ ИЗМЕНЕНИЕ:
  // Разрешаем запись в RAM, если FIFO не заполнено, ИЛИ если оно заполнено, но сейчас читается.
  wire do_ram_write = wr_en && (!wr_full || do_pop);
  
  // Чтение из RAM в rd_data инициируется, если в RAM есть данные, и выходной регистр пуст ИЛИ читается
  wire ram_re       = (ram_count > 0) && (rd_empty || rd_en);

  // Предвычисление счетчика элементов внутри RAM
  reg [ADDR_W:0] ram_count_next;
  always @(*) begin
    case ({do_ram_write, ram_re})
      2'b10:   ram_count_next = ram_count + 1'b1;
      2'b01:   ram_count_next = ram_count - 1'b1;
      default: ram_count_next = ram_count; // При одновременном R+W счетчик RAM не меняется
    endcase
  end

  // Предвычисление состояния флага rd_empty
  reg rd_empty_next;
  always @(*) begin
    rd_empty_next = rd_empty;
    if (ram_re) begin
      rd_empty_next = 1'b0; // Новые данные гарантированно придут в rd_data на следующем такте
    end else if (rd_en && !rd_empty) begin
      rd_empty_next = 1'b1; // Текущие данные вычитали, а из RAM подставить нечего
    end
  end

  // Общее количество слов в FIFO (в RAM + в выходном регистре)
  wire [ADDR_W:0] usedw_next = ram_count_next + (rd_empty_next ? 1'b0 : 1'b1);

  // Синхронный блок
  always @(posedge clk) begin
    if (rst) begin
      wr_ptr          <= {ADDR_W{1'b0}};
      rd_ptr          <= {ADDR_W{1'b0}};
      ram_count       <= {(ADDR_W+1){1'b0}};
      rd_empty        <= 1'b1;
      wr_full         <= 1'b0;
      wr_almost_full  <= 1'b0;
      rd_almost_empty <= 1'b1;
      usedw           <= {(ADDR_W+1){1'b0}};
      rd_data         <= {DATA_W{1'b0}};
    end else begin
      // Запись в память (синхронная) - идет напрямую на входной порт BRAM
      if (do_ram_write) begin
        ram[wr_ptr] <= wr_data;
        wr_ptr      <= wr_ptr + 1'b1;
      end

      // Чтение из памяти (синхронное) - идет напрямую с выходного порта BRAM
      if (ram_re) begin
        rd_data     <= ram[rd_ptr];
        rd_ptr      <= rd_ptr + 1'b1;
      end

      // Обновление управляющих регистров
      ram_count       <= ram_count_next;
      rd_empty        <= rd_empty_next;
      usedw           <= usedw_next;
      
      // Вычисление флагов
      wr_full         <= (usedw_next == (1 << ADDR_W));
      wr_almost_full  <= (usedw_next >= ALMOST_FULL_THRESH);
      rd_almost_empty <= (usedw_next <= ALMOST_EMPTY_THRESH);
    end
  end

endmodule
