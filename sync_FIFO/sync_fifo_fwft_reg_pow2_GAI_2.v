// В текущей реализации данные всегда сначала записываются в RAM, 
// а уже на следующем такте автоматически перекачиваются в выходной 
// буфер rd_data.Такая архитектура называется 2-тактовым FWFT (2-cycle fall-through). 
// У неё есть как огромный плюс, так и один минус.
// Как ведет себя текущий код при записи в пустое FIFO:

// Такт 1: FIFO пустое (usedw=0, out_valid=0, mem_count=0). 
// Вы выставляете wr_en=1 и wr_data = D1. Данные D1 записываются во внутреннюю RAM.
// Такт 2: По фронту clk данные D1 оказались в RAM. Теперь mem_count=1. 
// Схема видит, что mem_empty=0 и out_valid=0, поэтому комбинаторный сигнал int_rd 
// мгновенно становится равным 1.
// Такт 3: По следующему фронту clk данные D1 считываются из RAM и защелкиваются 
// в выходной регистр rd_data. Флаг out_valid становится равен 1, а rd_empty падает в 0. 
// Только теперь данные можно забрать.
// Итог: С момента подачи wr_en до появления данных на выходе проходит 2 такта задержки (latency).

module sync_fifo_fwft_reg_pow2_GAI_2 #(
    parameter enable_bypass = 0,
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

  // Локальные параметры и объявление памяти
  localparam DEPTH = 1 << ADDR_W;

  // память FIFO

  // Для Xilinx/AMD Vivado:
  (* ram_style = "block" *) reg [DATA_W-1:0] mem[0:DEPTH-1];

  // // Для Intel/Altera Quartus:
  // (* ramstyle = "M20K" *) reg [DATA_W-1:0] mem[0:DEPTH-1];

  // Указатели для внутренней памяти (Standard FIFO)
  reg [ADDR_W-1:0] wr_ptr;
  reg [ADDR_W-1:0] rd_ptr;

  // Счетчик элементов непосредственно внутри памяти
  reg [ADDR_W:0] mem_count;

  // Выходной регистр занят валидными данными
  reg out_valid;

  // --- КОМБИНАТОРНАЯ ЛОГИКА ДЛЯ ВНУТРЕННИХ СИГНАЛОВ ---
  // Вычисляем комбинаторное (текущее) состояние заполненности памяти и FIFO
  wire mem_empty = (mem_count == 0);
  wire mem_full = (mem_count == DEPTH);

  // Комбинаторный флаг полной заполненности всего FIFO (RAM + выходной регистр)
  wire comb_full = mem_full && out_valid;

  generate
    if (enable_bypass == 1) begin : gen_bypass_enabled  // Bypass / Direct-Through

      // Ровно за 1 такт данные прыгают на выход, если FIFO пустое И пришла запись
      wire bypass_to_out = (usedw == 0) && wr_en;
      // Реальная запись в RAM разрешена, если:
      // 1. Пришел wr_en
      // 2. Это НЕ байпас (при байпасе данные идут сразу на выход, в RAM их дублировать нельзя)
      // 3. FIFO не заполнено, ЛИБО оно заполнено, но параллельно идет чтение (rd_en)
      wire int_wr = wr_en && !bypass_to_out && (!comb_full || rd_en);

      // Модифицированное внутреннее чтение из RAM
      // Теперь мы читаем из RAM, только если там реально что-то есть, 
      // и выход освобождается (или уже пуст, и мы не делаем bypass прямо сейчас)
      wire int_rd = !mem_empty && (!out_valid || rd_en) && !bypass_to_out;
    end else begin : gen_bypass_disabled
      wire do_read = rd_en && (!rd_empty);
      // Внутренняя запись разрешена, если есть wr_en И FIFO не полно,
      // ЛИБО если FIFO полно, но прямо сейчас происходит чтение (rd_en), освобождающее место!
      wire int_wr = wr_en && (!comb_full || do_read);

      // Логика FWFT: читаем из памяти, если в ней есть данные, 
      // и при этом выходной регистр либо пуст, либо из него прямо сейчас читают
      // int_rd — это сигнал внутренней перекачки данных из памяти (RAM) в выходной регистр rd_data.
      wire int_rd = !mem_empty && (!out_valid || rd_en);
    end
  endgenerate




  // --- Запись в память и обновление указателя записи ---
  always @(posedge clk) begin
    if (rst) begin
      wr_ptr <= 0;
    end else if (int_wr) begin
      mem[wr_ptr] <= wr_data;
      wr_ptr      <= wr_ptr + 1'b1;
    end
  end

  // --- Чтение из памяти и обновление указателя чтения ---
  always @(posedge clk) begin
    if (rst) begin
      rd_ptr <= 0;
    end else if (int_rd) begin
      rd_ptr <= rd_ptr + 1'b1;
    end
  end

  // --- УПРАВЛЕНИЕ ВЫХОДНЫМ РЕГИСТРОМ ДАННЫХ (FWFT Stage) ---
  generate
    if (enable_bypass == 1) begin : gen_bypass_enabled  // Bypass / Direct-Through
      // (Истинный FWFT Stage с Bypass)
      always @(posedge clk) begin
        if (rst) begin
          rd_data   <= {DATA_W{1'b0}};
          out_valid <= 1'b0;
        end else begin
          if (bypass_to_out) begin
            rd_data   <= wr_data;  // Данные идут со входа НАПРЯМУЮ в регистр, минуя RAM
            out_valid <= 1'b1;
          end else if (int_rd) begin
            rd_data   <= mem[rd_ptr];  // Данные идут из RAM
            out_valid <= 1'b1;
          end else if (rd_en) begin
            out_valid <= 1'b0;
          end
        end
      end
    end else begin : gen_bypass_disabled
      always @(posedge clk) begin
        if (rst) begin
          rd_data   <= {DATA_W{1'b0}};
          out_valid <= 1'b0;
        end else begin
          if (int_rd) begin
            rd_data   <= mem[rd_ptr];
            out_valid <= 1'b1;
          end else if (rd_en) begin
            out_valid <= 1'b0;
          end
        end
      end
    end
  endgenerate


// --- ПОДСЧЕТ ЭЛЕМЕНТОВ ВНУТРИ RAM ---
  always @(posedge clk) begin
    if (rst) begin
      mem_count <= 0;
    end else begin
      case ({
        int_wr, int_rd
      })
        2'b10:   mem_count <= mem_count + 1'b1;
        2'b01:   mem_count <= mem_count - 1'b1;
        default: mem_count <= mem_count;  // 00 и 11 не меняют счетчик
      endcase
    end
  end



  // --- РАСЧЕТ И РЕГИСТРАЦИЯ ВЫХОДНЫХ ФЛАГОВ ---
  // Предсказываем значение usedw на следующий такт
  reg [ADDR_W:0] next_usedw;

  // Фактический инкремент/декремент общего количества слов в FIFO
  // Реальное чтение из FIFO происходит, только если оно не пустое
  // real_rd — это сигнал окончательного удаления элемента из FIFO внешним потребителем.
  wire real_rd = rd_en && out_valid;
  always @(*) begin
    case ({
      int_wr, real_rd
    })
      2'b10: next_usedw = usedw + 1'b1;
      2'b01: next_usedw = usedw - 1'b1;
      default:
      next_usedw = usedw;  // 00 или 11 (одновременная запись и чтение)
    endcase
  end

  // Регистрируем все выходные порты на триггерах
  always @(posedge clk) begin
    if (rst) begin
      usedw           <= 0;
      rd_empty        <= 1'b1;
      rd_almost_empty <= 1'b1;
      wr_full         <= 1'b0;
      wr_almost_full  <= 1'b0;
    end else begin
      usedw <= next_usedw;

      // Флаги чтения
      rd_empty <= (next_usedw == 0);
      rd_almost_empty <= (next_usedw <= ALMOST_EMPTY_THRESH);

      // Флаги записи
      // wr_full        <= (next_usedw == (DEPTH + 1'b1)); // Память полна (DEPTH) + выходной  регистр (1)
      wr_full        <= (next_usedw >= DEPTH); // считается полным, когда общее кол-во слов достигло ровно DEPTH.
      wr_almost_full <= (next_usedw >= ALMOST_FULL_THRESH);
    end
  end

endmodule
