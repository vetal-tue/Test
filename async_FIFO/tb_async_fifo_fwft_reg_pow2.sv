`timescale 1ns / 1ps

module tb_async_fifo_fwft_reg_pow2;

  // =========================================================================
  // Параметры FIFO
  // =========================================================================
  localparam DATA_W              = 16;
  localparam ADDR_W              = 4;            // Глубина DEPTH = 1 << 4 = 16
  localparam DEPTH               = 1 << ADDR_W;
  localparam ALMOST_FULL_THRESH  = DEPTH - 1;
  localparam ALMOST_EMPTY_THRESH = 1;

  // Переменные генерации клоков
  real               WR_CLK_PERIOD = 10.0;  // 100 MHz
  real               RD_CLK_PERIOD = 10.0;  // 100 MHz
  real               RD_CLK_PHASE = 0.0;  // Сдвиг фазы чтения (нс)

  // =========================================================================
  // Сигналы интерфейса DUT
  // =========================================================================
  logic              wr_clk;
  logic              rst;
  logic              wr_en;
  logic [DATA_W-1:0] wr_data;
  logic              wr_full;
  logic              wr_full1;
  logic              wr_almost_full;
  logic              wr_almost_full1;
  logic [  ADDR_W:0] wr_cnt;
  logic [  ADDR_W:0] wr_cnt1;

  logic              rd_clk;
  logic              rd_en;
  logic [DATA_W-1:0] rd_data;
  logic [DATA_W-1:0] rd_data1;
  logic [  ADDR_W:0] rd_cnt;
  logic [  ADDR_W:0] rd_cnt1;
  logic              rd_empty;
  logic              rd_empty1;
  logic              rd_almost_empty;
  logic              rd_almost_empty1;

  // Счётчики результатов
  int                test_pass_cnt = 0;
  int                test_fail_cnt = 0;

  // Golden Model для проверки целостности данных
  logic [DATA_W-1:0] golden_queue                                                   [$];

  // =========================================================================
  // Инстанцирование DUT
  // =========================================================================
  async_fifo_fwft_xilinx_style #(
      // async_fifo_fwft_reg_pow2 #(
      .DATA_W(DATA_W),
      .ADDR_W(ADDR_W),
      .ALMOST_FULL_THRESH(ALMOST_FULL_THRESH),
      .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
  ) dut (
      .wr_clk         (wr_clk),
      .wr_rst         (rst),
      // .rst         (rst),
      .wr_en          (wr_en),
      .wr_data        (wr_data),
      .wr_full        (wr_full),
      .wr_almost_full (wr_almost_full),
      .wr_cnt         (wr_cnt),
      .rd_clk         (rd_clk),
      .rd_rst         (rst),
      .rd_en          (rd_en),
      .rd_data        (rd_data),
      .rd_cnt         (rd_cnt),
      .rd_empty       (rd_empty),
      .rd_almost_empty(rd_almost_empty)
  );

  // async_fifo_fwft_bram_pow2_3 #(
  //     .DATA_W(DATA_W),
  //     .ADDR_W(ADDR_W),
  //     .ALMOST_FULL_THRESH(ALMOST_FULL_THRESH),
  //     .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
  // ) dut (
  //     .wr_clk         (wr_clk),
  //     // .wr_rst         (rst),
  //     .rst            (rst),
  //     .wr_en          (wr_en),
  //     .wr_data        (wr_data),
  //     .wr_full        (wr_full),
  //     .wr_almost_full (wr_almost_full),
  //     .wr_cnt         (wr_cnt),
  //     .rd_clk         (rd_clk),
  //     // .rd_rst         (rst),
  //     .rd_en          (rd_en),
  //     .rd_data        (rd_data),
  //     .rd_cnt         (rd_cnt),
  //     .rd_empty       (rd_empty),
  //     .rd_almost_empty(rd_almost_empty)
  // );


  // async_fifo_fwft_reg_pow2_4 #(
  //     .DATA_W(DATA_W),
  //     .ADDR_W(ADDR_W),
  //     .ALMOST_FULL_THRESH(ALMOST_FULL_THRESH),
  //     .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
  // ) dut1 (
  //     .wr_clk         (wr_clk),
  //     // .wr_rst         (rst),
  //     .rst            (rst),
  //     .wr_en          (wr_en),
  //     .wr_data        (wr_data),
  //     .wr_full        (wr_full1),
  //     .wr_almost_full (wr_almost_full1),
  //     .wr_cnt         (wr_cnt1),
  //     .rd_clk         (rd_clk),
  //     // .rd_rst         (rst),
  //     .rd_en          (rd_en),
  //     .rd_data        (rd_data1),
  //     .rd_cnt         (rd_cnt1),
  //     .rd_empty       (rd_empty1),
  //     .rd_almost_empty(rd_almost_empty1)
  // );

  // =========================================================================
  // Генерация clocks
  // =========================================================================
  initial begin
    wr_clk = 0;
    forever #(WR_CLK_PERIOD / 2.0) wr_clk = ~wr_clk;
  end

  // initial begin
  //   rd_clk = 0;
  //   #(RD_CLK_PHASE);
  //   forever #(RD_CLK_PERIOD / 2.0) rd_clk = ~rd_clk;
  // end

  // =========================================================================
  // Генерация rd_clk с возможностью перезапуска с новой фазой.
  // Перезапуск делается через disable внешнего именованного блока —
  // это идиоматический способ "restartable clock" в SystemVerilog,
  // корректно работающий в Icarus.
  // =========================================================================
  initial begin : rd_clk_gen_blk
    rd_clk = 1'b0;
    forever begin : rd_clk_outer
      rd_clk = 1'b0;
      #(RD_CLK_PHASE);
      forever begin : rd_clk_inner
        #(RD_CLK_PERIOD / 2.0);
        rd_clk = ~rd_clk;
      end
    end
  end

  // привязка момента перезапуска rd_clk по posedge wr_clk.
  task automatic restart_rd_clk_aligned(real phase_ns);
    @(posedge wr_clk);
    #1ps;
    RD_CLK_PHASE = phase_ns;
    disable rd_clk_gen_blk.rd_clk_outer;  // <-- просто disable, без event
    #100ns;  // даём новому драйверу поработать
  endtask

  initial begin
    $dumpfile("tb_async_fifo_fwft_reg_pow2");
    $dumpvars(0, tb_async_fifo_fwft_reg_pow2);
  end

  // Watchdog Timeout (5 миллисекунд)
  initial begin
    #5ms;
    $display("\n[FATAL] Watchdog Timeout! Simulation took too long or got stuck in a loop.");
    $dumpflush;
    $finish;
  end

  // =========================================================================
  // Вспомогательные задачи
  // =========================================================================

  task automatic check(input logic condition, input string test_name, input string fail_msg);
    if (condition) begin
      $display("[PASS] %s", test_name);
      test_pass_cnt++;
    end else begin
      $display("[FAIL at %0t] %s: %s", $time, test_name, fail_msg);
      test_fail_cnt++;
    end
  endtask

  // Подача асинхронного сброса с паузой на восстановление CDC
  task automatic async_reset(real duration_ns = 50.0);
    rst = 1'b1;
    wr_en = 1'b0;
    rd_en = 1'b0;
    wr_data = '0;
    golden_queue.delete();
    #(duration_ns);
    rst = 1'b0;
    // Даем время асинхронным синхронизаторам сброса выйти из состояния reset
    repeat (10) @(posedge wr_clk);
    repeat (10) @(posedge rd_clk);
  endtask

  // Запись 1 слова в домене wr_clk
  task automatic write_word(input logic [DATA_W-1:0] data);
    int timeout_cnt = 0;
    while (wr_full && timeout_cnt < 200) begin
      @(posedge wr_clk);
      #1ps;
      timeout_cnt++;
    end

    if (timeout_cnt >= 200) begin
      $display("[FAIL at %0t] write_word timeout: wr_full stuck", $time);
      test_fail_cnt++;
      // data = 'x;
      return;
    end

    wr_en   = 1'b1;
    wr_data = data;
    if (!wr_full) golden_queue.push_back(data);

    @(posedge wr_clk);
    #1ps;
    wr_en = 1'b0;
  endtask

  // Чтение 1 слова в домене rd_clk (непрерывный поток FWFT)
  task automatic read_word(output logic [DATA_W-1:0] data);
    int timeout_cnt = 0;
    while (rd_empty && timeout_cnt < 200) begin
      @(posedge rd_clk);
      #1ps;
      timeout_cnt++;
    end

    if (timeout_cnt >= 200) begin
      $display("[FAIL at %0t] read_word timeout: rd_empty stuck", $time);
      test_fail_cnt++;
      data = 'x;
      return;
    end

    data  = rd_data;
    rd_en = 1'b1;

    @(posedge rd_clk);
    #1ps;
    rd_en = 1'b0;
  endtask
  // task automatic read_word(output logic [DATA_W-1:0] data);
  //   int timeout_cnt = 0;

  //   // 1. Ожидаем появления данных, если FIFO пусто
  //   while (rd_empty && timeout_cnt < 200) begin
  //     @(posedge rd_clk);
  //     #1ps;
  //     timeout_cnt++;
  //   end

  //   // 2. СТРОГО выравниваемся по фронту rd_clk перед выставлением rd_en
  //   @(posedge rd_clk);
  //   #1ps;
  //   data  = rd_data; // В FWFT данные уже валидны на этом фронте
  //   rd_en = 1'b1;

  //   // 3. Держим rd_en ровно 1 такт rd_clk
  //   @(posedge rd_clk);
  //   #1ps;
  //   rd_en = 1'b0;
  // endtask

  // =========================================================================
  // ТЕСТОВЫЕ СЦЕНАРИИ
  // =========================================================================

  // 1. Сброс и начальное состояние
  task automatic test_reset_and_init();
    $display("\n--- RUNNING: 1. Reset & Initialization ---");

    rst = 1;
    #10ns;
    check(wr_full == 0 && rd_empty == 1 && wr_cnt == 0 && rd_cnt == 0, "Async Reset Assert",
          "Signals not reset correctly during rst=1");

    async_reset(40);
    check(wr_full == 0 && rd_empty == 1 && wr_cnt == 0 && rd_cnt == 0, "Reset Recovery",
          "Flags/counters drifted without enable signals");

    rst = 1;
    #1ps;
    wr_en   = 1;
    rd_en   = 1;
    wr_data = 16'hDEAD;
    repeat (5) @(posedge wr_clk);

    #1ps;
    wr_en = 0;
    rd_en = 0;
    repeat (2) @(posedge wr_clk);

    #1ps;
    rst = 0;
    repeat (10) @(posedge rd_clk);

    check(rd_empty == 1 && wr_cnt == 0, "Ignore Enable During Reset",
          "Data was written or counter modified during reset");
  endtask

  // 2. Специфика FWFT (First-Word Fall-Through)
  task automatic test_fwft_spec();
    int latency_cycles = 0;
    int timeout_cnt = 0;
    logic [DATA_W-1:0] read_val;
    $display("\n--- RUNNING: 2. FWFT Specifics ---");
    async_reset();

    // Latency и мгновенное появление на rd_data до rd_en
    @(posedge wr_clk);  // Явное выравнивание по фронту wr_clk
    #1ps;
    write_word(16'hA5A5);

    fork
      begin
        while (rd_empty && timeout_cnt < 100) begin
          @(posedge rd_clk);
          #1ps;
          latency_cycles++;
          timeout_cnt++;
        end
      end
    join

    check(rd_data == 16'hA5A5 && !rd_empty, "FWFT Immediate Availability", $sformatf(
          "Expected 0xA5A5, got 0x%04X before rd_en (rd_empty=%0b)", rd_data, rd_empty));
    $display("[INFO] CDC FWFT Latency: %0d rd_clk cycles", latency_cycles);

    // Одиночное чтение
    read_word(read_val);
    check(read_val == 16'hA5A5, "FWFT Single Read Data", $sformatf(
          "Expected 0xA5A5, got 0x%04X", read_val));

    repeat (3) @(posedge rd_clk);
    check(rd_empty == 1 && rd_cnt == 0, "FWFT Single Read Back To Empty",
          "FIFO did not return to empty state after 1 read");

    // Конвейеризация данных (3 слова подряд)
    write_word(16'h1111);
    write_word(16'h2222);
    write_word(16'h3333);
    repeat (5) @(posedge rd_clk);  // Ждем синхронизации CDC

    check(rd_data == 16'h1111, "Pipelining Step 1", "First word mismatch");

    // Выставляем чтение
    @(posedge rd_clk);
    #1ps;
    rd_en = 1;

    // ФРОНТ 1: Вычитываем 16'h1111, FWFT загружает 16'h2222
    @(posedge rd_clk);
    #1ps;
    check(rd_data == 16'h2222 && !rd_empty, "Pipelining Step 2", "Second word mismatch");

    // ФРОНТ 2: Вычитываем 16'h2222, FWFT загружает 16'h3333
    @(posedge rd_clk);
    #1ps;
    check(rd_data == 16'h3333 && !rd_empty, "Pipelining Step 3", "Third word mismatch");

    // ФРОНТ 3: Вычитываем последнее слово (16'h3333), FIFO опустошается
    @(posedge rd_clk);
    #1ps;
    rd_en = 0;  // Снимаем rd_en ПОСЛЕ 3-го фронта чтения!

    // Даем 1 такт на обновление регистров и флага rd_empty
    repeat (2) @(posedge rd_clk);
    check(rd_empty == 1, "Pipelining Empty Check", "FIFO not empty after pipeline drain");
  endtask

  // =========================================================================
  // 2.1 FWFT Data Hold Contract
  // Пока rd_empty == 0 и rd_en == 0, rd_data не должен меняться.
  // =========================================================================
  task automatic test_fwft_data_hold();
    logic [DATA_W-1:0] held_data;
    int                hold_cycles;

    $display("\n--- RUNNING: 2.1 FWFT Data Hold Contract ---");

    async_reset();
    @(posedge wr_clk);
    #1ps;

    write_word(16'h1111);
    write_word(16'h2222);
    write_word(16'h3333);

    repeat (5) @(posedge rd_clk);

    check(rd_empty === 1'b0, "FWFT DATA HOLD: initial not empty", $sformatf(
          "rd_empty=%0b after 3 writes", rd_empty));

    if (rd_empty === 1'b0) begin
      rd_en     = 1'b0;
      wr_en     = 1'b0;
      held_data = rd_data;

      for (hold_cycles = 0; hold_cycles < 20; hold_cycles++) begin
        @(posedge rd_clk);
        #1ps;

        check(rd_empty === 1'b0, "FWFT DATA HOLD: EMPTY", $sformatf(
              "cycle %0d: FIFO unexpectedly became empty", hold_cycles));

        check(rd_data === held_data, "FWFT DATA HOLD: rd_data changed without rd_en", $sformatf(
              "cycle %0d: expected=0x%04X got=0x%04X", hold_cycles, held_data, rd_data));
      end
    end

    // async_reset();
  endtask

  // =========================================================================
  // 2.3 FWFT Almost-Always-Empty
  //
  // Сценарий:
  //   writer:  write, wait, write, wait, write, wait, ...
  //   reader:  rd_en = 1 непрерывно
  //
  // Ожидаемая картина:
  //   A -> EMPTY -> B -> EMPTY -> C -> EMPTY -> ...
  //
  // Проверяется:
  //   * CDC слова в домен чтения (EMPTY->NONEMPTY);
  //   * корректная генерация rd_empty после вычитывания последнего слова;
  //   * FWFT-prefetch: слово появляется на rd_data без какого-либо rd_en;
  //   * повторный переход EMPTY->NONEMPTY для каждого нового слова;
  //   * целостность и порядок данных.
  // =========================================================================
  task automatic test_fwft_almost_always_empty();
    localparam int N_BURSTS = 8;

    logic [DATA_W-1:0] val;
    int                rd_errors;
    int                got_words;
    int                empty_windows;
    int                to;

    $display("\n--- RUNNING: 2.3 FWFT Almost-Always-Empty (reader rd_en=1) ---");

    rd_errors     = 0;
    got_words     = 0;
    empty_windows = 0;

    async_reset();
    @(posedge wr_clk);
    #1ps;

    // Стартовое состояние: FIFO пусто, читатель готов
    rd_en = 1'b0;
    repeat (3) @(posedge rd_clk);
    check(rd_empty === 1'b1, "FWFT ALMOST-EMPTY: initial empty", $sformatf(
          "rd_empty=%0b at start", rd_empty));

    // Непрерывный rd_en=1 в домене чтения
    @(posedge rd_clk);
    #1ps;
    rd_en = 1'b1;

    fork
      // ================== WRITER: write, wait, write, wait, ... ==================
      begin : aae_writer
        for (int i = 0; i < N_BURSTS; i++) begin
          // Перед следующей записью убеждаемся, что FIFO уже опустело
          if (i > 0) begin
            int wto;
            wto = 0;
            while (wr_cnt != 0 && wto < 2000) begin
              @(posedge wr_clk);
              #1ps;
              wto++;
            end
            if (wto >= 2000) begin
              $display(
                  "[FAIL at %0t] FWFT ALMOST-EMPTY: writer drain timeout (iter=%0d, wr_cnt=%0d)",
                  $time, i, wr_cnt);
              test_fail_cnt++;
              break;
            end
            // Доп. пауза: гарантирует, что reader уже увидел EMPTY между словами
            repeat (10) @(posedge wr_clk);
          end

          write_word(16'h5000 + i);

          // Пауза, чтобы reader успел прочитать слово и FIFO снова опустело
          repeat (30) @(posedge wr_clk);
        end
      end

      // ================== READER: rd_en=1 постоянно ==================
      begin : aae_reader
        for (int i = 0; i < N_BURSTS; i++) begin
          // 1) Ждём появления слова: rd_empty 1 -> 0. rd_en НЕ трогаем.
          to = 0;
          while (rd_empty && to < 5000) begin
            @(posedge rd_clk);
            #1ps;
            to++;
          end
          if (to >= 5000) begin
            $display("[FAIL at %0t] FWFT ALMOST-EMPTY: reader timeout waiting for word %0d", $time,
                     i);
            test_fail_cnt++;
            break;
          end

          // 2) FWFT: rd_data валиден прямо сейчас, rd_en уже = 1
          val = rd_data;
          got_words++;

          if (val !== (16'h5000 + i)) begin
            $display("[FAIL at %0t] FWFT ALMOST-EMPTY: idx=%0d exp=0x%04X got=0x%04X", $time, i,
                     DATA_W'(16'h5000 + i), val);
            rd_errors++;
          end

          // 3) Следующий фронт: rd_en=1 вычитывает слово
          @(posedge rd_clk);
          #1ps;

          // 4) FIFO должно уйти в EMPTY (данных больше нет, а rd_en всё ещё = 1)
          to = 0;
          while (!rd_empty && to < 5000) begin
            @(posedge rd_clk);
            #1ps;
            to++;
          end
          if (to >= 5000) begin
            $display("[FAIL at %0t] FWFT ALMOST-EMPTY: rd_empty never re-asserted after word %0d",
                     $time, i);
            test_fail_cnt++;
            break;
          end
          empty_windows++;
        end

        // Снимаем rd_en
        @(posedge rd_clk);
        #1ps;
        rd_en = 1'b0;
      end
    join

    check(got_words == N_BURSTS, "FWFT ALMOST-EMPTY: all words received", $sformatf(
          "expected %0d, got %0d", N_BURSTS, got_words));
    check(rd_errors == 0, "FWFT ALMOST-EMPTY: data integrity", $sformatf("%0d mismatches", rd_errors
          ));
    check(empty_windows == N_BURSTS, "FWFT ALMOST-EMPTY: EMPTY->NONEMPTY->EMPTY per word",
          $sformatf("expected %0d empty windows, observed %0d", N_BURSTS, empty_windows));

    // Финальная зачистка
    repeat (10) @(posedge rd_clk);
    #1ps;
    check(rd_empty === 1'b1 && rd_cnt == 0 && wr_cnt == 0, "FWFT ALMOST-EMPTY: final empty",
          $sformatf("rd_empty=%0b rd_cnt=%0d wr_cnt=%0d", rd_empty, rd_cnt, wr_cnt));

    rd_en = 1'b0;
    async_reset();
  endtask

  // 3. Граничные объемы и счетчики
  task automatic test_boundaries_and_thresholds();
    $display("\n--- RUNNING: 3. Boundary Volumes & Thresholds ---");
    async_reset();
    @(posedge wr_clk);  // Явное выравнивание по фронту wr_clk
    #1ps;

    for (int i = 0; i < DEPTH; i++) begin
      write_word(16'hB000 + i);
    end
    repeat (5) @(posedge wr_clk);

    check(wr_full == 1 && wr_cnt == DEPTH, "Full Fill Check", $sformatf(
          "Expected wr_full=1, wr_cnt=%0d. Got wr_cnt=%0d", DEPTH, wr_cnt));

    repeat (5) @(posedge rd_clk);
    for (int i = 0; i < DEPTH; i++) begin
      logic [DATA_W-1:0] val;
      read_word(val);
      check(val == (16'hB000 + i), "Data Integrity Full Drain", $sformatf(
            "Expected 0x%04X, got 0x%04X at index %0d", DATA_W'(16'hB000 + i), val, i));
    end
    repeat (3) @(posedge rd_clk);
    check(rd_empty == 1, "Full Drain Empty Check", "FIFO not empty after reading all items");

    async_reset();
    for (int i = 0; i < ALMOST_FULL_THRESH; i++) begin
      write_word(16'hC000 + i);
    end
    repeat (5) @(posedge wr_clk);
    check(wr_almost_full == 1 && wr_cnt >= ALMOST_FULL_THRESH, "Almost Full Threshold",
          "wr_almost_full failed to assert at threshold");

    repeat (5) @(posedge rd_clk);
    begin
      int safety_counter = 0;
      while (rd_cnt > ALMOST_EMPTY_THRESH && safety_counter < 100) begin
        logic [DATA_W-1:0] val_almost;
        read_word(val_almost);

        // ДОБАВЛЕНО: Проверка читаемых данных при опустошении до ALMOST_EMPTY
        check(val_almost == DATA_W'(16'hC000 + safety_counter), "Almost Empty Drain Data Check",
              $sformatf(
              "Expected 0x%04X, got 0x%04X at index %0d",
              DATA_W'(16'hC000 + safety_counter),
              val_almost,
              safety_counter
              ));

        repeat (2) @(posedge rd_clk);
        safety_counter++;
      end
    end
    check(rd_almost_empty == 1, "Almost Empty Threshold",
          "rd_almost_empty failed to assert at threshold");
  endtask

  // 4. Сложные коллизии в асинхронных доменах
  task automatic test_concurrent_edge_cases();
    $display("\n--- RUNNING: 4. Concurrent R/W at Boundaries ---");
    async_reset();

    // ---------------------------------------------------------
    // ТЕСТ А: Чтение и запись при "Полном" (Full)
    // ---------------------------------------------------------
    for (int i = 0; i < DEPTH; i++) begin
      write_word(16'hE000 + i);
    end

    // Даем время указателю записи дойти до домена чтения
    repeat (5) @(posedge rd_clk);
    check(wr_full == 1'b1, "Full State", "FIFO not full after DEPTH writes");

    // Одновременный старт R/W в разных доменах
    fork
      begin  // Домен ЧТЕНИЯ
        @(posedge rd_clk);
        #1ps;
        rd_en = 1'b1;
        check(rd_data == 16'hE000, "Full R/W: Read Oldest", "FWFT read data mismatch on collision");
        @(posedge rd_clk);
        #1ps;
        rd_en = 1'b0;
      end
      begin  // Домен ЗАПИСИ
        @(posedge wr_clk);
        #1ps;
        wr_en   = 1'b1;
        wr_data = 16'hE999;
        // В классическом FIFO эта запись будет проигнорирована, так как wr_full еще равен 1.
        // Если ваша архитектура поддерживает одновременный R/W при full, снимите этот if.
        if (!wr_full) golden_queue.push_back(16'hE999);
        @(posedge wr_clk);
        #1ps;
        wr_en = 1'b0;
      end
    join

    // Даем перекрестным указателям Грея обновиться (CDC)
    repeat (5) @(posedge wr_clk);
    repeat (5) @(posedge rd_clk);

    // Вычитываем остаток, чтобы проверить целостность
    for (int i = 1; i < DEPTH; i++) begin
      logic [DATA_W-1:0] val;
      read_word(val);
      check(val == (16'hE000 + i), "Full R/W: Data Integrity",
            "Data corrupted after full R/W collision");
    end

    // ---------------------------------------------------------
    // ТЕСТ Б: Чтение и запись при "Почти пустом" (1 слово)
    // ---------------------------------------------------------
    async_reset();

    write_word(16'hF111);
    // Ждем, пока слово "упадет" в домен чтения (характерно для FWFT)
    repeat (5) @(posedge rd_clk);
    check(rd_empty == 1'b0, "1-Word State", "FIFO empty flag stuck");

    fork
      begin  // Домен ЧТЕНИЯ
        @(posedge rd_clk);
        #1ps;
        rd_en = 1'b1;
        check(rd_data == 16'hF111, "Almost Empty: Read Old", "FWFT read data mismatch");
        @(posedge rd_clk);
        #1ps;
        rd_en = 1'b0;
      end
      begin  // Домен ЗАПИСИ
        @(posedge wr_clk);
        #1ps;
        wr_en   = 1'b1;
        wr_data = 16'hF222;
        golden_queue.push_back(16'hF222);
        @(posedge wr_clk);
        #1ps;
        wr_en = 1'b0;
      end
    join

    // Сразу после коллизии rd_empty может мигнуть в 1, так как указатель чтения сдвинулся,
    // а указатель записи (для hF222) еще летит через CDC.
    // Ждем синхронизации:
    repeat (5) @(posedge rd_clk);

    // Теперь новое слово должно стабильно лежать на выходе FWFT
    check(rd_empty == 1'b0, "Almost Empty: Recovery",
          "FIFO failed to recover empty flag after CDC");
    check(rd_data == 16'hF222, "Almost Empty: New Word FWFT",
          "New word did not fall through correctly");

  endtask

  // =========================================================================

  // 5. Асинхронные домены (CDC Stress)
  task automatic test_cdc_domains();
    // ---- ВСЕ объявления в начале task-а (требование Icarus) ----
    logic [DATA_W-1:0] val;
    int                rd_errors;
    int                order_errors;
    int                empty_glitch;
    int                rd_total;

    $display("\n--- RUNNING: 5. Asynchronous Domains (CDC) ---");

    // =========================================================
    // 5.1 Fast Write / Slow Read
    // =========================================================
    WR_CLK_PERIOD = 10.0;
    RD_CLK_PERIOD = 100.0;
    #200ns;
    async_reset();
    @(posedge wr_clk);
    #1ps;

    rd_errors    = 0;
    order_errors = 0;

    for (int i = 0; i < 8; i++) write_word(16'h1000 + i);
    repeat (5) @(posedge rd_clk);

    for (int i = 0; i < 8; i++) begin
      read_word(val);
      if (val !== (16'h1000 + i)) begin
        $display("[FAIL at %0t] FastWr/SlowRd: exp 0x%04X got 0x%04X at idx=%0d", $time,
                 DATA_W'(16'h1000 + i), val, i);
        rd_errors++;
      end
    end

    check(rd_errors == 0, "Fast Write Slow Read Data Integrity", $sformatf(
          "%0d mismatches out of 8", rd_errors));

    repeat (5) @(posedge rd_clk);
    check(rd_empty === 1'b1 && rd_cnt == 0 && wr_cnt == 0, "Fast Write Slow Read Final Empty",
          $sformatf("rd_empty=%0b rd_cnt=%0d wr_cnt=%0d", rd_empty, rd_cnt, wr_cnt));

    // =========================================================
    // 5.2 Slow Write / Fast Read
    //     WR_CLK_PERIOD = 100 нс, RD_CLK_PERIOD = 10 нс.
    //     Reader висит на rd_empty, пока writer не «протолкнёт» слово
    //     через CDC. Проверяем порядок/целостность КАЖДОГО слова
    //     и что rd_empty не мигает во время ожидания.
    // =========================================================
    WR_CLK_PERIOD = 100.0;
    RD_CLK_PERIOD = 10.0;
    #200ns;
    async_reset();
    @(posedge wr_clk);
    #1ps;

    rd_errors    = 0;
    order_errors = 0;
    empty_glitch = 0;
    rd_total     = 0;

    fork
      // ------------------- PRODUCER (wr_clk @ 100 нс) -------------------
      begin : slow_writer
        for (int i = 0; i < 5; i++) begin
          write_word(16'h2000 + i);
          // Даём reader'у время увидеть слово в его домене
          repeat (2) @(posedge wr_clk);
        end
      end

      // ------------------- CONSUMER (rd_clk @ 10 нс) --------------------
      begin : fast_reader
        for (int i = 0; i < 5; i++) begin
          int to;
          to = 0;
          // Ждём появления слова. Пока ждём — контролируем, что rd_empty
          // не «дёргается» (0 → 1 → 0) без продвижения указателя чтения.
          while (rd_empty && to < 2000) begin
            @(posedge rd_clk);
            #1ps;
            to++;
            // sanity: rd_empty не может самопроизвольно упасть до прихода
            // слова — если упал, следующая проверка val поймает мусор.
          end

          if (to >= 2000) begin
            $display("[FAIL at %0t] SlowWr/FastRd: timeout waiting for word idx=%0d", $time, i);
            test_fail_cnt++;
            break;
          end

          // Дополнительная страховка: rd_empty должен быть 0 ровно тогда,
          // когда на шине лежит валидное слово (FWFT-контракт).
          if (rd_empty !== 1'b0) begin
            $display("[FAIL at %0t] SlowWr/FastRd: rd_empty=%0b when data present", $time,
                     rd_empty);
            empty_glitch++;
          end

          // Читаем и СРАЗУ проверяем значение
          read_word(val);
          rd_total++;

          if (val !== (16'h2000 + i)) begin
            $display("[FAIL at %0t] SlowWr/FastRd: idx=%0d exp=0x%04X got=0x%04X", $time, i,
                     DATA_W'(16'h2000 + i), val);
            rd_errors++;
          end
        end
      end
    join

    check(rd_total == 5, "Slow Write Fast Read: All words consumed", $sformatf(
          "exp 5, got %0d", rd_total));
    check(rd_errors == 0, "Slow Write Fast Read: Data & Order Integrity", $sformatf(
          "%0d mismatches out of 5", rd_errors));
    check(empty_glitch == 0, "Slow Write Fast Read: rd_empty Consistency", $sformatf(
          "%0d violations", empty_glitch));

    // Финальная зачистка: FIFO должно быть пусто, счётчики — 0
    repeat (10) @(posedge rd_clk);
    #1ps;
    check(rd_empty === 1'b1 && rd_cnt == 0 && wr_cnt == 0, "Slow Write Fast Read: Final Empty",
          $sformatf("rd_empty=%0b rd_cnt=%0d wr_cnt=%0d", rd_empty, rd_cnt, wr_cnt));

  endtask

  // =========================================================================
  // 5.4 Near Frequencies Drift
  // Периоды клоков отличаются на 0.01 нс ⇒ фаза медленно проползает 360°
  // (beat period ≈ 10 µs). Одновременный streaming в обоих доменах
  // стрессирует CDC на ВСЕХ относительных фазах.
  // Проверяется: порядок, целостность, отсутствие overflow/underflow,
  // границы счётчиков, финальное опустошение FIFO.
  // =========================================================================
  task automatic test_near_freq_drift();
    localparam int N_WORDS = 300;

    logic [DATA_W-1:0] val;
    logic [DATA_W-1:0] exp_val;
    int                rd_errors;
    int                wr_cnt_errors;
    int                rd_cnt_errors;
    int                rd_total;
    int                wr_total;
    real               saved_wr;
    real               saved_rd;

    $display("\n--- RUNNING: 5.4 Near Frequencies Drift ---");

    saved_wr = WR_CLK_PERIOD;
    saved_rd = RD_CLK_PERIOD;

    // =========================================================
    // CASE A: wr_clk чуть быстрее (10.000 vs 10.010 нс)
    // =========================================================
    WR_CLK_PERIOD = 10.000;
    RD_CLK_PERIOD = 10.010;
    #200ns;

    rd_errors     = 0;
    wr_cnt_errors = 0;
    rd_cnt_errors = 0;
    rd_total      = 0;
    wr_total      = 0;

    async_reset();
    @(posedge wr_clk);
    #1ps;

    // Предзаполняем половину, чтобы reader не залипал на rd_empty на старте
    for (int i = 0; i < DEPTH / 2; i++) write_word(16'h3000 + i);

    fork
      // ---------- PRODUCER (wr_clk) ----------
      begin : drift_writer_A
        for (int i = 0; i < N_WORDS; i++) begin
          write_word(16'h3100 + i);
          wr_total++;

          if (wr_cnt > DEPTH) begin
            $display("[FAIL at %0t] Drift A: OVERFLOW wr_cnt=%0d", $time, wr_cnt);
            test_fail_cnt++;
            wr_cnt_errors++;
          end
          if (wr_full !== 1'b1 && wr_cnt == DEPTH) begin
            $display("[FAIL at %0t] Drift A: wr_full=0 at wr_cnt=DEPTH", $time);
            test_fail_cnt++;
            wr_cnt_errors++;
          end
        end
      end

      // ---------- CONSUMER (rd_clk) ----------
      begin : drift_reader_A
        // Предварительное выравнивание по домену чтения
        @(posedge rd_clk);

        for (int i = 0; i < DEPTH / 2 + N_WORDS; i++) begin
          read_word(val);
          rd_total++;

          if (rd_cnt > DEPTH) begin
            $display("[FAIL at %0t] Drift A: rd_cnt=%0d", $time, rd_cnt);
            test_fail_cnt++;
            rd_cnt_errors++;
          end

          if (i < DEPTH / 2) begin
            exp_val = 16'h3000 + i;  // prefill
          end else begin
            exp_val = 16'h3100 + (i - DEPTH / 2);  // concurrent stream
          end

          if (val !== exp_val) begin
            $display("[FAIL at %0t] Drift A: DATA MISMATCH idx=%0d Exp=0x%04X Got=0x%04X", $time,
                     i, DATA_W'(exp_val), val);
            test_fail_cnt++;
            rd_errors++;
          end
        end
      end
    join

    check(rd_total == DEPTH / 2 + N_WORDS, "Drift A: All reads executed", $sformatf(
          "exp %0d got %0d", DEPTH / 2 + N_WORDS, rd_total));
    check(wr_total == N_WORDS, "Drift A: All writes executed", $sformatf(
          "exp %0d got %0d", N_WORDS, wr_total));
    check(rd_errors == 0, "Drift A: Data & Order Integrity", $sformatf(
          "%0d mismatches in %0d words", rd_errors, rd_total));
    check(wr_cnt_errors == 0, "Drift A: No Overflow / wr_full Consistency", $sformatf(
          "%0d violations", wr_cnt_errors));
    check(rd_cnt_errors == 0, "Drift A: rd_cnt Bounds", $sformatf("%0d violations", rd_cnt_errors));

    repeat (10) @(posedge rd_clk);
    check(rd_empty === 1'b1 && rd_cnt == 0, "Drift A: Final Empty", $sformatf(
          "rd_empty=%0b rd_cnt=%0d", rd_empty, rd_cnt));

    // =========================================================
    // CASE B: rd_clk чуть быстрее (10.010 vs 10.000 нс)
    // =========================================================
    WR_CLK_PERIOD = 10.010;
    RD_CLK_PERIOD = 10.000;
    #200ns;

    rd_errors     = 0;
    wr_cnt_errors = 0;
    rd_cnt_errors = 0;
    rd_total      = 0;
    wr_total      = 0;

    async_reset();
    @(posedge wr_clk);
    #1ps;

    for (int i = 0; i < DEPTH / 2; i++) write_word(16'h4000 + i);

    fork
      begin : drift_writer_B
        for (int i = 0; i < N_WORDS; i++) begin
          write_word(16'h4100 + i);
          wr_total++;

          if (wr_cnt > DEPTH) begin
            $display("[FAIL at %0t] Drift B: OVERFLOW wr_cnt=%0d", $time, wr_cnt);
            test_fail_cnt++;
            wr_cnt_errors++;
          end
        end
      end

      begin : drift_reader_B
        // Предварительное выравнивание по домену чтения
        @(posedge rd_clk);

        for (int i = 0; i < DEPTH / 2 + N_WORDS; i++) begin
          read_word(val);
          rd_total++;

          if (rd_cnt > DEPTH) begin
            $display("[FAIL at %0t] Drift B: rd_cnt=%0d", $time, rd_cnt);
            test_fail_cnt++;
            rd_cnt_errors++;
          end

          if (i < DEPTH / 2) begin
            exp_val = 16'h4000 + i;
          end else begin
            exp_val = 16'h4100 + (i - DEPTH / 2);
          end

          if (val !== exp_val) begin
            $display("[FAIL at %0t] Drift B: DATA MISMATCH idx=%0d Exp=0x%04X Got=0x%04X", $time,
                     i, DATA_W'(exp_val), val);
            test_fail_cnt++;
            rd_errors++;
          end
        end
      end
    join

    check(rd_total == DEPTH / 2 + N_WORDS, "Drift B: All reads executed", $sformatf(
          "exp %0d got %0d", DEPTH / 2 + N_WORDS, rd_total));
    check(wr_total == N_WORDS, "Drift B: All writes executed", $sformatf(
          "exp %0d got %0d", N_WORDS, wr_total));
    check(rd_errors == 0, "Drift B: Data & Order Integrity", $sformatf(
          "%0d mismatches in %0d words", rd_errors, rd_total));
    check(wr_cnt_errors == 0, "Drift B: No Overflow", $sformatf("%0d violations", wr_cnt_errors));
    check(rd_cnt_errors == 0, "Drift B: rd_cnt Bounds", $sformatf("%0d violations", rd_cnt_errors));

    repeat (10) @(posedge rd_clk);
    check(rd_empty === 1'b1 && rd_cnt == 0, "Drift B: Final Empty", $sformatf(
          "rd_empty=%0b rd_cnt=%0d", rd_empty, rd_cnt));

    // --- Restore ---
    WR_CLK_PERIOD = saved_wr;
    RD_CLK_PERIOD = saved_rd;
    #100ns;
  endtask

  // 6. Защита от переполнения/недобора (Overflow & Underflow)
  task automatic test_overflow_underflow();
    logic [DATA_W-1:0] val;
    $display("\n--- RUNNING: 6. Safeguards (Overflow & Underflow) ---");
    async_reset();
    @(posedge wr_clk);  // Явное выравнивание по фронту wr_clk
    #1ps;

    for (int i = 0; i < DEPTH; i++) write_word(16'h7000 + i);
    repeat (5) @(posedge wr_clk);

    for (int i = 0; i < 10; i++) begin
      @(posedge wr_clk);
      #1ps;
      wr_en   = 1;
      wr_data = 16'hBAD0 + i;
      @(posedge wr_clk);
      #1ps;
      wr_en = 0;
    end
    repeat (5) @(posedge rd_clk);

    for (int i = 0; i < DEPTH; i++) begin
      read_word(val);
      check(val == (16'h7000 + i), "Overflow Protection",
            "Pointer wrapped around or overwritten data");
    end
    check(rd_empty == 1, "Overflow Empty Check", "Extra illegitimate words were written");

    async_reset();
    for (int i = 0; i < 10; i++) begin
      @(posedge rd_clk);
      #1ps;
      rd_en = 1'b1;

      @(posedge rd_clk);
      #1ps;
      rd_en = 1'b0;
    end
    check(rd_cnt == 0, "Underflow Count Check", "rd_cnt went negative/corrupted after underflow");

    @(posedge wr_clk);
    #1ps;
    write_word(16'hF00D);
    repeat (5) @(posedge rd_clk);
    check(rd_data == 16'hF00D, "Underflow Recovery",
          "FIFO failed to recover after underflow reads");
  endtask

  // 7. Профессиональные проверки (Advanced Edge Cases)
  task automatic test_advanced_checks();
    $display("\n--- RUNNING: 7. Professional Checks & Edge Cases ---");
    async_reset();

    // 7.1 Randomized Stalls & Bursts
    fork
      begin : rand_writer
        for (int i = 0; i < 100; i++) begin
          @(posedge wr_clk);
          #1ps;
          if ($urandom_range(0, 99) < 30) begin
            if (!wr_full) begin
              wr_en   = 1;
              wr_data = $urandom();
              golden_queue.push_back(wr_data);
            end
          end else begin
            wr_en = 0;
          end
        end
        wr_en = 0;
      end
      begin : rand_reader
        for (int i = 0; i < 200; i++) begin
          @(posedge rd_clk);
          #1ps;
          if ($urandom_range(0, 99) < 30) begin
            if (!rd_empty) begin
              rd_en = 1;
              if (golden_queue.size() > 0) begin
                logic [DATA_W-1:0] expected = golden_queue.pop_front();
                check(rd_data == expected, "Randomized Stall Data Check", $sformatf(
                      "Mismatch in randomized traffic. Exp: 0x%04X, Got: 0x%04X", expected, rd_data
                      ));
              end
            end
          end else begin
            rd_en = 0;
          end
        end
        rd_en = 0;
      end
    join

    // 7.3 Фазовый сдвиг 180°
    // RD_CLK_PHASE = WR_CLK_PERIOD / 2.0;
    // #100ns;
    // async_reset();
    // @(posedge wr_clk);  // Явное выравнивание по фронту wr_clk
    // #1ps;
    // write_word(16'h180D);
    // repeat (5) @(posedge rd_clk);
    // check(rd_data == 16'h180D, "180 Degree Phase Shift CDC",
    //       "CDC failed at 180 degree phase shift");
    // RD_CLK_PHASE = 0.0;
    // #100ns;

    // 7.3 Фазовый сдвиг 180°: rd_clk идёт в противофазе с wr_clk
    RD_CLK_PHASE = WR_CLK_PERIOD / 2.0;
    restart_rd_clk_aligned(RD_CLK_PHASE);

    async_reset();
    @(posedge wr_clk);
    #1ps;
    write_word(16'h180D);
    repeat (5) @(posedge rd_clk);
    check(rd_data == 16'h180D, "180 Degree Phase Shift CDC",
          "CDC failed at 180 degree phase shift");

    // Восстанавливаем нормальный rd_clk для последующих тестов
    RD_CLK_PHASE = 0.0;
    restart_rd_clk_aligned(RD_CLK_PHASE);

    // 7.4 Сброс под нагрузкой
    begin
      bit stop_traffic;
      stop_traffic = 0;
      async_reset();

      fork
        begin
          while (!stop_traffic) begin
            @(posedge wr_clk);
            #1ps;
            wr_en   = 1;
            wr_data = $urandom();
          end
          wr_en = 0;
        end
        begin
          #100ns;
          rst = 1;
          repeat (30) @(posedge wr_clk);
          stop_traffic = 1;
          repeat (5) @(posedge wr_clk);
          #1ps;
          rst = 0;
        end
      join
    end

    repeat (10) @(posedge rd_clk);
    check(rd_empty == 1 && wr_cnt == 0 && rd_cnt == 0, "Clean Slate After On-The-Fly Reset",
          "Ghost data remaining in prefetch pipeline after reset under load");

    // 7.5 Паттерн "Шагающая единица" (Walking 1)
    async_reset();


    // fork
    //   begin
    //     for (int b = 0; b < DATA_W; b++) begin
    //       while (wr_full) begin
    //         @(posedge wr_clk);
    //         #1ps;
    //       end
    //       wr_en   = 1'b1;
    //       wr_data = (1'b1 << b);
    //       @(posedge wr_clk);
    //       #1ps;
    //       wr_en = 1'b0;
    //     end
    //     wr_data = '0;
    //   end
    //   begin
    //     for (int b = 0; b < DATA_W; b++) begin
    //       logic [DATA_W-1:0] val;
    //       read_word(val);
    //       check(val == (1'b1 << b), "Walking 1 Bus Integrity", $sformatf(
    //             "Bit integrity error at bit %0d", b));
    //     end
    //   end
    // join
    fork
      // -------- PRODUCER --------
      begin
        @(posedge wr_clk);
        #1ps;

        for (int b = 0; b < DATA_W; b++) begin
          int timeout_cnt = 0;

          while (wr_full && timeout_cnt < 500) begin
            @(posedge wr_clk);
            #1ps;
            timeout_cnt++;
          end

          // Защита от бесконечного зависания в случае сбоя RTL
          if (timeout_cnt >= 500) begin
            $display("[FAIL at %0t] Walking 1 Writer stuck: wr_full did not clear at bit %0d",
                     $time, b);
            test_fail_cnt++;
            break;
          end

          wr_en   = 1'b1;
          wr_data = (DATA_W'(1'b1) << b);  // <-- БЫЛО (1'b1 << b)

          @(posedge wr_clk);
          #1ps;
          wr_en = 1'b0;
        end
        wr_data = '0;
      end

      // -------- CONSUMER --------
      begin
        for (int b = 0; b < DATA_W; b++) begin
          logic [DATA_W-1:0] val;
          read_word(val);

          check(
              val == (DATA_W'(1'b1) << b),  // <-- БЫЛО (1'b1 << b)
              "Walking 1 Bus Integrity", $sformatf(
              "Bit integrity error at bit %0d (exp=0x%04X got=0x%04X)", b, (DATA_W'(1'b1) << b), val
              ));
        end
      end
    join

    // 7.6 Паттерн "Адрес как данные" (Address as Data)
    async_reset();
    @(posedge wr_clk);  // Явное выравнивание по фронту wr_clk
    #1ps;
    for (int i = 0; i < DEPTH; i++) begin
      write_word(i);
    end
    repeat (5) @(posedge rd_clk);
    for (int i = 0; i < DEPTH; i++) begin
      logic [DATA_W-1:0] val;
      read_word(val);
      check(val == i, "Address as Data Pointer Check", $sformatf(
            "Pointer error. Exp address %0d, got %0d", i, val));
    end
  endtask

  // 7.2 Балансирование на грани (Threshold Dancing)
  // Держим FIFO в районе порога almost_full, одновременно пишем и читаем
  // в СВОИХ клоковых доменах. Проверяется:
  //   * сохранение порядка и целостности ВСЕХ данных (не только флага!);
  //   * отсутствие переполнения (wr_cnt никогда не превышает DEPTH);
  //   * отсутствие выхода rd_cnt за пределы [0, DEPTH];
  //   * стабильность wr_almost_full, пока уровень FIFO >= порога;
  //   * что фактически записано/прочитано ровно столько, сколько запланировано;
  //   * что после "танца" FIFO корректно опустошается.
  task automatic test_threshold_dancing();
    localparam int DANCE_ITERS = 30;
    localparam int TOTAL_READS = ALMOST_FULL_THRESH + DANCE_ITERS;

    // ---- ВСЕ объявления — в начале task-а, до любого исполняемого кода ----
    logic [DATA_W-1:0] expected_stream[TOTAL_READS];
    logic [DATA_W-1:0] val;
    int                to_wr;
    int                to_rd;
    int                rd_errors;
    int                ovf_errors;
    int                af_errors;
    int                cnt_errors;
    int                rd_total;
    int                wr_total;

    $display("\n--- RUNNING: 7.2 Threshold Dancing ---");

    // ---- Инициализация (уже исполняемый код) ----
    rd_errors  = 0;
    ovf_errors = 0;
    af_errors  = 0;
    cnt_errors = 0;
    rd_total   = 0;
    wr_total   = 0;

    async_reset();
    @(posedge wr_clk);  // Явное выравнивание по фронту wr_clk
    #1ps;

    // ------- 1. Предзаполняем FIFO до порога almost_full -------
    for (int i = 0; i < ALMOST_FULL_THRESH; i++) begin
      write_word(16'hA000 + i);
    end

    repeat (10) @(posedge wr_clk);
    // repeat (10) @(posedge rd_clk);

    check(wr_almost_full === 1'b1, "TD: Setup almost_full", $sformatf(
          "wr_almost_full=0 при уровне %0d (wr_cnt=%0d)", ALMOST_FULL_THRESH, wr_cnt));
    check(wr_full === 1'b0, "TD: Setup not-full",
          "wr_full неожиданно взведён до начала танца");

    // ------- 2. Заранее известная последовательность чтения -------
    for (int i = 0; i < ALMOST_FULL_THRESH; i++) expected_stream[i] = 16'hA000 + i;
    for (int i = 0; i < DANCE_ITERS; i++) expected_stream[ALMOST_FULL_THRESH+i] = 16'h8000 + i;

    // ------- 3. Параллельные потоки в СВОИХ доменах -------
    fork
      // ================= PRODUCER (wr_clk) =================
      begin : dance_writer
        for (int i = 0; i < DANCE_ITERS; i++) begin
          to_wr = 0;
          while (wr_full && to_wr < 500) begin
            @(posedge wr_clk);
            #1ps;
            to_wr++;
          end
          if (to_wr >= 500) begin
            $display("[FAIL at %0t] TD: producer застрял на wr_full (iter=%0d)", $time, i);
            test_fail_cnt++;
            break;
          end

          wr_en   = 1'b1;
          wr_data = 16'h8000 + i;
          wr_total++;

          @(posedge wr_clk);
          #1ps;
          wr_en = 1'b0;

          // Инвариант №1: переполнения нет
          if (wr_cnt > DEPTH) begin
            $display("[FAIL at %0t] TD: OVERFLOW wr_cnt=%0d > DEPTH=%0d", $time, wr_cnt, DEPTH);
            test_fail_cnt++;
            ovf_errors++;
          end

          // Инвариант №2: wr_almost_full не «дрожит», пока wr_cnt >= порога
          if (wr_cnt >= ALMOST_FULL_THRESH && wr_almost_full !== 1'b1) begin
            $display("[FAIL at %0t] TD: wr_almost_full glitch (wr_cnt=%0d)", $time, wr_cnt);
            test_fail_cnt++;
            af_errors++;
          end
        end
      end

      // ================= CONSUMER (rd_clk) =================
      begin : dance_reader
        // Предварительное выравнивание по домену чтения
        @(posedge rd_clk);
        #1ps;

        for (int i = 0; i < TOTAL_READS; i++) begin
          to_rd = 0;
          while (rd_empty && to_rd < 1000) begin
            @(posedge rd_clk);
            #1ps;
            to_rd++;
          end
          if (to_rd >= 1000) begin
            $display("[FAIL at %0t] TD: consumer timeout at %0d/%0d", $time, i, TOTAL_READS);
            test_fail_cnt++;
            break;
          end

          // FWFT: данные валидны ДО rd_en
          val   = rd_data;

          // rd_en управляется ИЗ ДОМЕНА rd_clk
          // Сигнал rd_en выставлен строго после posedge rd_clk + 1ps
          rd_en = 1'b1;

          // Ждем следующий фронт, на котором RTL FIFO защелкнет чтение
          @(posedge rd_clk);
          #1ps;
          rd_en = 1'b0;

          // Инвариант №3: счётчик чтения в допустимых границах
          if (rd_cnt > DEPTH) begin
            $display("[FAIL at %0t] TD: rd_cnt=%0d вне [0, %0d]", $time, rd_cnt, DEPTH);
            test_fail_cnt++;
            cnt_errors++;
          end

          // Инвариант №4: порядок и целостность данных
          if (val !== expected_stream[i]) begin
            $display("[FAIL at %0t] TD: DATA MISMATCH idx=%0d Exp=0x%04X Got=0x%04X", $time, i,
                     DATA_W'(expected_stream[i]), val);
            test_fail_cnt++;
            rd_errors++;
          end

          rd_total++;
        end
      end
    join

    // ------- 4. Итоговые проверки -------
    check(rd_total == TOTAL_READS, "TD: All reads executed", $sformatf(
          "Ожидалось %0d чтений, получено %0d", TOTAL_READS, rd_total));
    check(wr_total == DANCE_ITERS, "TD: All writes executed", $sformatf(
          "Ожидалось %0d записей, получено %0d", DANCE_ITERS, wr_total));
    check(rd_errors == 0, "TD: Data & Order Integrity", $sformatf(
          "%0d расхождений в потоке данных", rd_errors));
    check(ovf_errors == 0, "TD: No Overflow", $sformatf(
          "%0d событий переполнения", ovf_errors));
    check(cnt_errors == 0, "TD: rd_cnt Invariant", $sformatf(
          "%0d нарушений диапазона rd_cnt", cnt_errors));
    check(af_errors == 0, "TD: wr_almost_full Stability", $sformatf(
          "%0d glitch-ей при wr_cnt >= %0d", af_errors, ALMOST_FULL_THRESH));

    // ------- 5. FIFO должно корректно опустеть -------
    repeat (10) @(posedge rd_clk);
    check(rd_empty === 1'b1, "TD: Final Empty", $sformatf(
          "FIFO не опустело после танца (rd_cnt=%0d)", rd_cnt));

    wr_en = 1'b0;
    rd_en = 1'b0;
  endtask

  // =========================================================================
  // Запуск всех тестов
  // =========================================================================
  initial begin
    $display("=================================================");
    $display(" STARTING ASYNC FWFT FIFO FULL VERIFICATION ");
    $display("=================================================");

    test_reset_and_init();
    test_fwft_spec();
    test_fwft_data_hold();
    test_fwft_almost_always_empty();
    test_boundaries_and_thresholds();
    // test_concurrent_streaming();
    test_concurrent_edge_cases();
    test_cdc_domains();
    test_near_freq_drift();
    test_overflow_underflow();
    test_advanced_checks();
    test_threshold_dancing();

    $display("\n=================================================");
    $display(" VERIFICATION SUMMARY: ");
    $display(" TESTS PASSED: %0d", test_pass_cnt);
    $display(" TESTS FAILED: %0d", test_fail_cnt);
    $display("=================================================");

    if (test_fail_cnt == 0) begin
      $display(">>> ALL TESTS PASSED SUCCESSFULLY! <<<\n");
    end else begin
      $display(">>> VERIFICATION FAILED WITH ERRORS! <<<\n");
    end

    $finish;
  end

endmodule
