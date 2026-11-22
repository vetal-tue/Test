module fwft_fifo #(
    parameter DATA_W = 8,
    parameter ADDR_W = 3   // Глубина = 8 слов
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              wr_en,
    input  wire [DATA_W-1:0] din,
    output wire              full,
    input  wire              rd_en,
    output wire [DATA_W-1:0] dout,
    output wire              empty
);

  localparam DEPTH = (1 << ADDR_W);

  reg [DATA_W-1:0] mem[0:DEPTH-1];
  reg [ADDR_W:0] wr_ptr;
  reg [ADDR_W:0] rd_ptr;

  wire [ADDR_W:0] fill_count = wr_ptr - rd_ptr;

  assign empty = (fill_count == 0);
  assign full  = (fill_count == DEPTH);
  // В FWFT данные всегда видны на выходе по текущему указателю чтения
  assign dout  = mem[rd_ptr[ADDR_W-1:0]];

  // wire do_write = wr_en && !full;
  // wire do_read  = rd_en && !empty;
  wire do_read = rd_en && !empty;
  wire do_write = wr_en && (!full || do_read);

  always @(posedge clk) begin
    if (rst) begin
      wr_ptr <= 0;
      rd_ptr <= 0;
    end else begin
      if (do_write) begin
        mem[wr_ptr[ADDR_W-1:0]] <= din;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (do_read) begin
        rd_ptr <= rd_ptr + 1'b1;
      end
    end
  end

`ifdef FORMAL
  reg f_past_valid = 0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) begin
    if (!f_past_valid) assume (rst);
  end

  // --- Базовые проверки указателей и флагов ---
  always @(posedge clk) begin
    if (!rst) begin
      // Количество элементов не может превышать глубину
      assert (fill_count <= DEPTH);
      // Одновременно full и empty быть не могут
      assert (!(full && empty));
    end
  end

  // --- Контракт целостности данных (2 произвольных слова подряд) ---
  (* anyconst *)wire [DATA_W-1:0] f_first_data;
  (* anyconst *)wire [DATA_W-1:0] f_second_data;

  // Адреса, по которым запишутся наши контрольные слова
  (* anyconst *)wire [  ADDR_W:0] f_first_addr;
  wire [  ADDR_W:0] f_second_addr = f_first_addr + 1'b1;

  // Флаги состояния отслеживания (изначально оба слова не записаны)
  reg               f_first_in_fifo = 0;
  reg               f_second_in_fifo = 0;

  always @(posedge clk) begin
    if (rst) begin
      f_first_in_fifo  <= 0;
      f_second_in_fifo <= 0;
    end else begin
      // Отслеживаем запись ПЕРВОГО слова
      if (do_write && (wr_ptr == f_first_addr) && (din == f_first_data) && !f_first_in_fifo && !f_second_in_fifo) begin
        f_first_in_fifo <= 1'b1;
      end else if (do_read && (rd_ptr == f_first_addr) && f_first_in_fifo) begin
        f_first_in_fifo <= 1'b0;  // Первое слово прочитано
      end

      // Отслеживаем запись ВТОРОГО слова (строго после записи первого)
      if (do_write && (wr_ptr == f_second_addr) && (din == f_second_data) && f_first_in_fifo && !f_second_in_fifo) begin
        f_second_in_fifo <= 1'b1;
      end else if (do_read && (rd_ptr == f_second_addr) && f_second_in_fifo) begin
        f_second_in_fifo <= 1'b0;  // Второе слово прочитано
      end
    end
  end

  // Утверждения и инварианты для отслеживаемых слов
  // Явные (ADDR_W+1)-битные разности (защита от 32-битного расширения в Verilog!)
  wire [ADDR_W:0] f_dist_wr_1 = wr_ptr - f_first_addr;
  wire [ADDR_W:0] f_dist_1_rd = f_first_addr - rd_ptr;
  wire [ADDR_W:0] f_dist_wr_2 = wr_ptr - f_second_addr;
  wire [ADDR_W:0] f_dist_2_rd = f_second_addr - rd_ptr;
  localparam [ADDR_W:0] DEPTH_W = DEPTH[ADDR_W:0];

  always @(*) begin
    if (!rst) begin
      // --- ИНВАРИАНТЫ ДЛЯ ИНДУКЦИИ ---
      if (f_first_in_fifo && !f_second_in_fifo) begin
        assert (f_dist_wr_1 >= 1);
        assert (f_dist_wr_1 <= DEPTH_W);
        assert (f_dist_1_rd < DEPTH_W);
      end

      if (f_second_in_fifo) begin
        assert (f_dist_wr_2 >= 1);
        assert (f_dist_wr_2 <= DEPTH_W);

        if (f_first_in_fifo) begin
          assert (f_dist_1_rd < DEPTH_W);
          assert (f_dist_2_rd < DEPTH_W);
        end else begin
          assert (rd_ptr == f_second_addr);
        end
      end

      // --- ОСНОВНЫЕ ПРОВЕРКИ ЦЕЛОСТНОСТИ ДАННЫХ ---
      if (f_first_in_fifo) begin
        assert (!empty);
        assert (mem[f_first_addr[ADDR_W-1:0]] == f_first_data);
        if (rd_ptr == f_first_addr) assert (dout == f_first_data);
      end

      if (f_second_in_fifo) begin
        assert (!empty);
        assert (mem[f_second_addr[ADDR_W-1:0]] == f_second_data);
        if (!f_first_in_fifo) begin
          assert (dout == f_second_data);
        end
      end
    end
  end

  //   always @(*) begin
  //     if (!rst) begin
  //       // --- ИНВАРИАНТЫ ДЛЯ ИНДУКЦИИ ---
  //       // 1. Второе слово не может появиться без первого, если оно еще не прочитано,
  //       //    а если оба внутри — расстояние между указателями должно их вмещать.
  //       if (f_first_in_fifo && !f_second_in_fifo) begin
  //         // Первое слово записано, значит wr_ptr как минимум на 1 шаг впереди f_first_addr
  //         assert ((wr_ptr - f_first_addr) >= 1);
  //         assert ((wr_ptr - f_first_addr) <= DEPTH);
  //         // И rd_ptr еще не дошел до следующего адреса
  //         assert ((f_first_addr - rd_ptr) < DEPTH);
  //       end

  //       if (f_second_in_fifo) begin
  //         // Второе слово записано, значит wr_ptr как минимум на 1 шаг впереди f_second_addr
  //         assert ((wr_ptr - f_second_addr) >= 1);
  //         assert ((wr_ptr - f_second_addr) <= DEPTH);

  //         if (f_first_in_fifo) begin
  //           // Оба слова в FIFO: первое обязано стоять в очереди раньше второго
  //           assert ((f_first_addr - rd_ptr) < DEPTH);
  //           assert ((f_second_addr - rd_ptr) < DEPTH);
  //         end else begin
  //           // Первое уже прочитано, второе еще нет -> rd_ptr ОБЯЗАН указывать на второе!
  //           assert (rd_ptr == f_second_addr);
  //         end
  //       end

  //       // --- ОСНОВНЫЕ ПРОВЕРКИ ЦЕЛОСТНОСТИ ДАННЫХ ---
  //       if (f_first_in_fifo) begin
  //         assert (!empty);
  //         assert (mem[f_first_addr[ADDR_W-1:0]] == f_first_data);
  //         if (rd_ptr == f_first_addr) assert (dout == f_first_data);
  //       end

  //       if (f_second_in_fifo) begin
  //         assert (!empty);
  //         assert (mem[f_second_addr[ADDR_W-1:0]] == f_second_data);
  //         if (!f_first_in_fifo) begin
  //           assert (dout == f_second_data);
  //         end
  //       end
  //     end
  //   end

  always @(posedge clk) begin
    if (f_past_valid && !rst && $past(!rst)) begin
      // Если на прошлом такте было полно и пришли оба запроса:
      if ($past(full && wr_en && rd_en)) begin
        // 1. Оба указателя обязаны сдвинуться на 1
        assert (wr_ptr == $past(wr_ptr) + 1'b1);
        assert (rd_ptr == $past(rd_ptr) + 1'b1);
        // 2. Буфер должен остаться полным (данные не потеряны)
        assert (full);
      end
    end
  end

  // --- Проверка достижимости (COVER) ---
  always @(posedge clk) begin
    if (f_past_valid && !rst) begin
      // Проверяем, что FIFO можно заполнить до отказа
      cover (full);
      // Проверяем, что оба наших контрольных слова успешно прошли через FIFO
      cover ($past(f_second_in_fifo) && !f_second_in_fifo);
    end
  end


  // Флаг, фиксирующий, что f_first_data было записано ИМЕННО в момент full && rd_en
  reg f_written_when_full = 0;

  always @(posedge clk) begin
    if (rst) begin
      f_written_when_full <= 0;
    end else if (do_write && (wr_ptr == f_first_addr) && (din == f_first_data) && full && rd_en) begin
      f_written_when_full <= 1'b1;
    end
  end

  always @(posedge clk) begin
    if (f_past_valid && !rst) begin
      // 1. Проверяем, что ситуация full + wr_en + rd_en вообще возможна
      cover (full && wr_en && rd_en);

      // 2. Проверяем полный цикл: слово записали в ПОЛНОЕ FIFO при одновременном чтении, а затем успешно прочитали его на выходе без потерь!
      cover (f_written_when_full && $past(f_first_in_fifo) && !f_first_in_fifo);
    end
  end

`endif

endmodule
