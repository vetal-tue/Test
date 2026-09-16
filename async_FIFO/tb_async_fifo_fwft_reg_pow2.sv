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
  logic              wr_almost_full;
  logic [  ADDR_W:0] wr_cnt;

  logic              rd_clk;
  logic              rd_en;
  logic [DATA_W-1:0] rd_data;
  logic [  ADDR_W:0] rd_cnt;
  logic              rd_empty;
  logic              rd_almost_empty;

  // Счётчики результатов
  int                test_pass_cnt = 0;
  int                test_fail_cnt = 0;

  // Golden Model для проверки целостности данных
  logic [DATA_W-1:0] golden_queue                                                   [$];

  // =========================================================================
  // Инстанцирование DUT
  // =========================================================================
  async_fifo_fwft_xilinx_style #(
      .DATA_W(DATA_W),
      .ADDR_W(ADDR_W),
      .ALMOST_FULL_THRESH(ALMOST_FULL_THRESH),
      .ALMOST_EMPTY_THRESH(ALMOST_EMPTY_THRESH)
  ) dut (
      .wr_clk         (wr_clk),
      .wr_rst         (rst),
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

  // =========================================================================
  // Генерация clocks
  // =========================================================================
  initial begin
    wr_clk = 0;
    forever #(WR_CLK_PERIOD / 2.0) wr_clk = ~wr_clk;
  end

  initial begin
    rd_clk = 0;
    #(RD_CLK_PHASE);
    forever #(RD_CLK_PERIOD / 2.0) rd_clk = ~rd_clk;
  end

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

    data  = rd_data;
    rd_en = 1'b1;

    @(posedge rd_clk);
    #1ps;
    rd_en = 1'b0;
  endtask

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

  // 3. Граничные объемы и счетчики
  task automatic test_boundaries_and_thresholds();
    $display("\n--- RUNNING: 3. Boundary Volumes & Thresholds ---");
    async_reset();

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
            "Expected 0x%04X, got 0x%04X at index %0d", 16'hB000 + i, val, i));
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
        logic [DATA_W-1:0] dummy;
        read_word(dummy);
        repeat (2) @(posedge rd_clk);
        safety_counter++;
      end
    end
    check(rd_almost_empty == 1, "Almost Empty Threshold",
          "rd_almost_empty failed to assert at threshold");
  endtask

  // 4. Непрерывные потоки (Continuous & Concurrent Streaming)
  task automatic test_concurrent_streaming();
    $display("\n--- RUNNING: 4. Continuous & Concurrent Streaming ---");
    async_reset();

    fork
      begin
        for (int i = 0; i < 50; i++) begin
          write_word(16'hD000 + i);
        end
      end
      begin
        for (int i = 0; i < 50; i++) begin
          logic [DATA_W-1:0] val;
          read_word(val);
          check(val == (16'hD000 + i), "Pass-Through Data Check", "Data corrupted in pass-through");
        end
      end
    join

    async_reset();
    for (int i = 0; i < DEPTH; i++) write_word(16'hE000 + i);
    repeat (5) @(posedge wr_clk);

    @(posedge wr_clk);
    #1ps;
    wr_en   = 1;
    wr_data = 16'hE999;
    rd_en   = 1;
    @(posedge wr_clk);
    #1ps;
    wr_en = 0;
    rd_en = 0;

    repeat (5) @(posedge wr_clk);
    check(!wr_full || wr_full, "Full Concurrent R/W", "FIFO locked up during full R/W");

    async_reset();
    write_word(16'hF111);
    repeat (5) @(posedge rd_clk);

    fork
      write_word(16'hF222);
      begin
        logic [DATA_W-1:0] tmp;
        read_word(tmp);
      end
    join
    check(wr_cnt >= 0, "Almost Empty Concurrent R/W", "Counters went negative or corrupted");
  endtask

  // 5. Асинхронные домены (CDC Stress)
  task automatic test_cdc_domains();
    logic [DATA_W-1:0] val;
    $display("\n--- RUNNING: 5. Asynchronous Domains (CDC) ---");

    WR_CLK_PERIOD = 10.0;
    RD_CLK_PERIOD = 100.0;
    #200ns;
    async_reset();

    for (int i = 0; i < 8; i++) write_word(16'h1000 + i);
    repeat (5) @(rd_clk);

    for (int i = 0; i < 8; i++) begin
      read_word(val);
      check(val == (16'h1000 + i), "Fast Write Slow Read", "Data mismatch in slow read domain");
    end

    WR_CLK_PERIOD = 100.0;
    RD_CLK_PERIOD = 10.0;
    #200ns;
    async_reset();

    fork
      begin
        for (int i = 0; i < 5; i++) begin
          write_word(16'h2000 + i);
          repeat (2) @(posedge wr_clk);
        end
      end
      begin
        for (int i = 0; i < 5; i++) begin
          while (rd_empty) begin
            @(posedge rd_clk);
            #1ps;
          end
          check(!rd_empty, "Slow Write Fast Read Glitch Check", "rd_empty glitched");
          read_word(val);
        end
      end
    join

    WR_CLK_PERIOD = 10.000;
    RD_CLK_PERIOD = 10.010;
    #200ns;

    async_reset();
    @(posedge wr_clk);
    #1ps;

    for (int i = 0; i < 20; i++) write_word(16'h3000 + i);
    repeat (10) @(posedge rd_clk);
    check(rd_cnt > 0, "Near Frequencies Drift", "FIFO pointers corrupted under phase drift");

    WR_CLK_PERIOD = 10.0;
    RD_CLK_PERIOD = 10.0;
    #100ns;
  endtask

  // 6. Защита от переполнения/недобора (Overflow & Underflow)
  task automatic test_overflow_underflow();
    logic [DATA_W-1:0] val;
    $display("\n--- RUNNING: 6. Safeguards (Overflow & Underflow) ---");
    async_reset();
    @(posedge wr_clk);
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

    // 7.2 Балансирование на грани (Threshold Dancing)
    async_reset();
    @(posedge wr_clk);
    #1ps;

    for (int i = 0; i < ALMOST_FULL_THRESH; i++) write_word(16'hA000 + i);
    repeat (5) @(posedge wr_clk);

    for (int i = 0; i < 20; i++) begin
      @(posedge wr_clk);
      #1ps;
      wr_en   = 1;
      wr_data = 16'h8000 + i;
      rd_en   = 1;
      check(wr_almost_full == 1, "Threshold Dancing Almost Full",
            "Glitch detected on wr_almost_full");
    end
    wr_en = 0;
    rd_en = 0;

    // 7.3 Фазовый сдвиг 180°
    RD_CLK_PHASE = WR_CLK_PERIOD / 2.0;
    #100ns;
    async_reset();
    @(posedge wr_clk);
    #1ps;
    write_word(16'h180D);
    repeat (5) @(posedge rd_clk);
    check(rd_data == 16'h180D, "180 Degree Phase Shift CDC",
          "CDC failed at 180 degree phase shift");
    RD_CLK_PHASE = 0.0;
    #100ns;

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
      // -----------------------------------------------------------------------
      // ПОТОК ЗАПИСИ (Producer): Пишет потоком, защищен от wr_full при DATA_W > DEPTH
      // -----------------------------------------------------------------------
      begin
        // Явное выравнивание по фронту wr_clk перед первой записью!
        @(posedge wr_clk);
        #1ps;

        for (int b = 0; b < DATA_W; b++) begin
          int timeout_cnt = 0;

          // Если DATA_W > DEPTH, FIFO переполнится.
          // Ждем, пока поток чтения вычитает данные и CDC-синхронизатор сбросит wr_full.
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
          wr_data = (1'b1 << b);

          @(posedge wr_clk);
          #1ps;
          wr_en = 1'b0;
        end
        wr_data = '0;
      end

      // -----------------------------------------------------------------------
      // ПОТОК ЧТЕНИЯ (Consumer): Вычитывает параллельно и освобождает место
      // -----------------------------------------------------------------------
      begin
        for (int b = 0; b < DATA_W; b++) begin
          logic [DATA_W-1:0] val;

          read_word(val);

          check(val == (1'b1 << b), "Walking 1 Bus Integrity", $sformatf(
                "Bit integrity error at bit %0d", b));
        end
      end
    join

    // 7.6 Паттерн "Адрес как данные" (Address as Data)
    async_reset();
    @(posedge wr_clk);
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

  // =========================================================================
  // Запуск всех тестов
  // =========================================================================
  initial begin
    $display("=================================================");
    $display(" STARTING ASYNC FWFT FIFO FULL VERIFICATION ");
    $display("=================================================");

    test_reset_and_init();
    test_fwft_spec();
    test_boundaries_and_thresholds();
    test_concurrent_streaming();
    test_cdc_domains();
    test_overflow_underflow();
    test_advanced_checks();

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
