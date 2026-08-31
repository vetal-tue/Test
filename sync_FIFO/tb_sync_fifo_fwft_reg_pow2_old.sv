`timescale 1ns / 1ps

module tb_sync_fifo_fwft_reg_pow2;

  // Параметры
  localparam DATA_W = 16;
  localparam ADDR_W = 4;
  localparam DEPTH = 1 << ADDR_W;

  // Сигналы
  logic clk = 0;
  logic rst = 0;
  logic wr_en = 0;
  logic [DATA_W-1:0] wr_data = 0;
  logic wr_full, wr_almost_full;
  logic [ADDR_W:0] usedw;

  logic rd_en = 0;
  logic [DATA_W-1:0] rd_data;
  logic rd_empty, rd_almost_empty;

  // Очередь для проверки данных (Reference Model)
  logic [DATA_W-1:0] ref_q[$];

  // Генерация клока
  always #5 clk = ~clk;

  // DUT
  sync_fifo_fwft_reg_pow2_GEM #(
      .DATA_W(DATA_W),
      .ADDR_W(ADDR_W)
  ) dut (
      .clk(clk),
      .rst(rst),
      .wr_en(wr_en),
      .wr_data(wr_data),
      .wr_full(wr_full),
      .wr_almost_full(wr_almost_full),
      .usedw(usedw),
      .rd_en(rd_en),
      .rd_data(rd_data),
      .rd_empty(rd_empty),
      .rd_almost_empty(rd_almost_empty)
  );

  initial begin
    $display("=== STARTING FWFT FIFO TESTBENCH ===");

    test_1_reset_and_init();
    test_2_fwft_specifics();
    test_3_boundary_conditions();
    test_4_concurrent_ops();
    test_5_specific_timings();

    $display("=== ALL TESTS PASSED SUCCESSFULLY ===");
    $finish;
  end

  initial begin
    $dumpfile("sync_FIFO_TB.vcd");
    $dumpvars(0, tb_sync_fifo_fwft_reg_pow2);
  end

  // ---------------------------------------------------------
  // Вспомогательные таски
  // ---------------------------------------------------------
  task apply_reset();
    @(posedge clk);
    rst   <= 1;
    wr_en <= 0;
    rd_en <= 0;
    ref_q.delete();
    @(posedge clk);
    rst <= 0;
    @(posedge clk);
  endtask

  task write_word(input logic [DATA_W-1:0] data);
    wr_en   <= 1;
    wr_data <= data;
    if (!wr_full) ref_q.push_back(data);
    @(posedge clk);
    wr_en <= 0;
  endtask

  task read_word();
    rd_en <= 1;
    @(posedge clk);
    rd_en <= 0;
    // #1; // Даем симулятору защелкнуть новые флаги
  endtask

  // ---------------------------------------------------------
  // 1. Базовые проверки и сброс
  // ---------------------------------------------------------
  task test_1_reset_and_init();
    $display("[TEST 1] Reset & Initialization...");
    apply_reset();

    if (rd_empty !== 1 || wr_full !== 0) $error("T1: Flags wrong after reset!");

    // Запись мусора без wr_en
    wr_data <= 16'hDEAD;
    @(posedge clk);
    if (rd_empty !== 1) $error("T1: Garbage written without wr_en!");
  endtask

  // ---------------------------------------------------------
  // 2. Специфика FWFT
  // ---------------------------------------------------------
  task test_2_fwft_specifics();
    $display("[TEST 2] FWFT Specifics (Fall-through)...");
    apply_reset();

    write_word(16'hA5A5);
    // Ждем проваливания (обычно 1 такт для FWFT)
    @(posedge clk);

    if (rd_empty) $error("T2: rd_empty should be 0 after fall-through!");
    if (rd_data !== 16'hA5A5) $error("T2: Data mismatch on fall-through!");

    read_word();
    // На следующем такте должно стать пустым

    // <<< ДОБАВЛЕНА ДЕЛЬТА-ЗАДЕРЖКА >>>
        #1;
    if (!rd_empty) $error("T2: rd_empty should be 1 after reading the last word!");
  endtask

  // ---------------------------------------------------------
  // 3. Граничные условия (Empty / Full)
  // ---------------------------------------------------------
  // task test_3_boundary_conditions();
  //   $display("[TEST 3] Boundary Conditions...");
  //   apply_reset();

  //   // Запись до заполнения
  //   for (int i = 0; i < DEPTH; i++) begin
  //     write_word(16'h1000 + i);
  //   end
  //   @(posedge clk);
  //   if (!wr_full) $error("T3: wr_full not asserted after %0d writes!", DEPTH);

  //   // Проверка overflow
  //   write_word(16'hEEEE);  // Should be ignored

  //   // Чтение до опустошения
  //   for (int i = 0; i < DEPTH; i++) begin
  //     logic [DATA_W-1:0] exp_data = ref_q.pop_front();
  //     if (rd_data !== exp_data) $error("T3: Read data mismatch!");
  //     read_word();
  //   end

  //   // <<< ДОБАВЛЕНА ДЕЛЬТА-ЗАДЕРЖКА >>>
  //   #1;

  //   if (!rd_empty) $error("T3: rd_empty not asserted after reading all words!");

  //   // Проверка underflow
  //   read_word();  // Should not break pointers
  //   write_word(16'hBEEF);  // New valid write
  //   @(posedge clk);
  //   if (rd_data !== 16'hBEEF) $error("T3: Pointers broken after underflow!");
  // endtask
// ---------------------------------------------------------
    // // 3. Граничные условия (Empty / Full)
    // // ---------------------------------------------------------
    // task test_3_boundary_conditions();
    //     $display("[TEST 3] Boundary Conditions...");
    //     apply_reset();
        
    //     // Запись до полного заполнения
    //     for (int i = 0; i < DEPTH; i++) begin
    //         write_word(16'h1000 + i);
    //     end
        
    //     // Даем 1 такт на защелкивание флага wr_full и первого слова на rd_data
    //     #1;
    //     if (!wr_full) $error("T3: wr_full not asserted after %0d writes!", DEPTH);
        
    //     // Проверка защиты от переполнения (overflow)
    //     write_word(16'hEEEE); // Запись должна проигнорироваться
    //     #1;

    //     // Чтение всех записанных данных
    //     for (int i = 0; i < DEPTH; i++) begin
    //         logic [DATA_W-1:0] exp_data;
    //         exp_data = ref_q.pop_front();
            
    //         // 1. Проверяем текущие данные на выходе (они уже провалились на rd_data)
    //         if (rd_data !== exp_data) begin
    //             $error("T3: Read data mismatch at index %0d! Expected: 0x%0h, Got: 0x%0h", 
    //                    i, exp_data, rd_data);
    //         end
            
    //         // 2. Подаем подтверждение rd_en для продвижения очереди
    //         rd_en <= 1;
    //         @(posedge clk);
    //         rd_en <= 0;
    //         #1; // Дельта-задержка для обновления rd_data симулятором
    //     end
        
    //     if (!rd_empty) $error("T3: rd_empty not asserted after reading all words!");
        
    //     // Проверка защиты от чтения пустого буфера (underflow)
    //     rd_en <= 1;
    //     @(posedge clk);
    //     rd_en <= 0;
    //     #1; // Попытка чтения из пустого FIFO не должна сломать указатели
        
    //     // Проверяем, что запись после underflow работает корректно
    //     write_word(16'hBEEF);
    //     @(posedge clk); // Ждем fall-through на выход
    //     #1;
        
    //     if (rd_data !== 16'hBEEF) $error("T3: Pointers broken after underflow! Got: 0x%0h", rd_data);
    // endtask
// ---------------------------------------------------------
    // 3. Граничные условия (Empty / Full)
    // ---------------------------------------------------------
    task test_3_boundary_conditions();
        $display("[TEST 3] Boundary Conditions...");
        apply_reset();
        
        // 1. Непрерывная запись до полного заполнения (wr_en держится непрерывно)
        wr_en <= 1;
        for (int i = 0; i < DEPTH; i++) begin
            wr_data <= 16'h1000 + i;
            ref_q.push_back(16'h1000 + i);
            @(posedge clk);
        end
        wr_en <= 0;
        #1;
        
        if (!wr_full) $error("T3: wr_full not asserted after %0d writes!", DEPTH);
        
        // Проверка защиты от переполнения (overflow)
        write_word(16'hEEEE); // Одиночная запись, должна проигнорироваться
        #1;

        // 2. Непрерывное чтение всех записанных данных (rd_en держится 1 НЕПРЕРЫВНО)
        rd_en <= 1;
        for (int i = 0; i < DEPTH; i++) begin
            logic [DATA_W-1:0] exp_data;
            exp_data = ref_q.pop_front();
            
            // Проверяем текущее значение на выходе rd_data
            if (rd_data !== exp_data) begin
                $error("T3: Read data mismatch at index %0d! Expected: 0x%0h, Got: 0x%0h", 
                       i, exp_data, rd_data);
            end
            
            @(posedge clk);
            #1; // Дельта-задержка для защелкивания следующих данных в FWFT
        end
        rd_en <= 0; // Снимаем rd_en только ПОСЛЕ прохождения всего массива
        
        if (!rd_empty) $error("T3: rd_empty not asserted after reading all words!");
        
        // Проверка защиты от чтения пустого буфера (underflow)
        rd_en <= 1;
        @(posedge clk);
        rd_en <= 0;
        #1;
        
        // Проверяем, что запись после underflow работает корректно
        write_word(16'hBEEF);
        @(posedge clk); // Ждем fall-through
        #1;
        
        if (rd_data !== 16'hBEEF) $error("T3: Pointers broken after underflow! Got: 0x%0h", rd_data);
    endtask

  // ---------------------------------------------------------
  // 4. Конкурентные операции
  // ---------------------------------------------------------
  task test_4_concurrent_ops();
    $display("[TEST 4] Concurrent Read & Write...");
    apply_reset();

    // Частичное заполнение
    write_word(16'hC001);
    write_word(16'hC002);
    @(posedge clk);

    // Одновременное чтение и запись
    wr_en   <= 1;
    wr_data <= 16'hC003;
    rd_en   <= 1;
    @(posedge clk);
    wr_en <= 0;
    rd_en <= 0;

    // Запись и чтение при пустом буфере
    apply_reset();
    wr_en   <= 1;
    wr_data <= 16'hEEEE;
    rd_en   <= 1;  // Должно игнорироваться
    @(posedge clk);
    wr_en <= 0;
    rd_en <= 0;
    @(posedge clk);  // Ждем fall-through
    if (rd_data !== 16'hEEEE || rd_empty) $error("T4: Read during Empty broke Write fall-through!");
  endtask

  // ---------------------------------------------------------
  // 5. Специфические тайминги
  // ---------------------------------------------------------
  // task test_5_specific_timings();
  //   $display("[TEST 5] Specific Timings & Bubble Test...");
  //   apply_reset();

  //   // Back-to-back throughput
  //   $display("   -> Back-to-back testing");
  //   fork
  //     // Поток записи
  //     begin
  //       for (int i = 0; i < DEPTH * 2; i++) begin
  //         wr_en   <= 1;
  //         wr_data <= i;
  //         @(posedge clk);
  //       end
  //       wr_en <= 0;
  //     end
  //     // Поток чтения (ждет появления данных)
  //     begin
  //       for (int i = 0; i < DEPTH * 2; i++) begin
  //         wait (!rd_empty);
  //         rd_en <= 1;
  //         @(posedge clk);
  //         rd_en <= 0;
  //       end
  //     end
  //   join

  //   if (wr_full) $error("T5: FIFO should not become full during throughput test!");

  //   // Сброс на лету
  //   $display("   -> On-the-fly reset");
  //   for (int i = 0; i < DEPTH / 2; i++) write_word(16'h1111 * i);
  //   rst <= 1; // Асинхронный/синхронный сброс во время работы
  //   @(posedge clk);
  //   if (rd_empty !== 1 || wr_full !== 0) $error("T5: Flags did not clear immediately on reset!");
  //   rst <= 0;
  // endtask
// ---------------------------------------------------------
    // 5. Специфические тайминги
    // ---------------------------------------------------------
    task test_5_specific_timings();
        $display("[TEST 5] Specific Timings & Bubble Test...");
        apply_reset();
        
        // Back-to-back throughput
        $display("   -> Back-to-back testing");
        fork
            // Поток записи
            begin
                for (int i = 0; i < DEPTH * 2; i++) begin
                    wr_en <= 1; wr_data <= i;
                    @(posedge clk);
                end
                wr_en <= 0;
            end
            // Поток чтения (ждет появления данных)
            begin
                for (int i = 0; i < DEPTH * 2; i++) begin
                    wait (!rd_empty);
                    rd_en <= 1;
                    @(posedge clk);
                    rd_en <= 0;
                    #1; // Даем симулятору обновить rd_empty
                end
            end
        join
        
        #1;
        if (wr_full) $error("T5: FIFO should not become full during throughput test!");

        // Сброс на лету
        $display("   -> On-the-fly reset");
        for (int i = 0; i < DEPTH/2; i++) begin
            write_word(16'h1111 * i);
        end
        
        // Подаем сброс
        rst <= 1;
        @(posedge clk); // Регистры сбрасываются по этому фронту
        #1;             // <<< ДЕЛЬТА-ЗАДЕРЖКА: даем симулятору обновить сигналы
        
        if (rd_empty !== 1 || wr_full !== 0) begin
            $error("T5: Flags did not clear immediately on reset! rd_empty=%b, wr_full=%b", 
                   rd_empty, wr_full);
        end
        
        rst <= 0;
        @(posedge clk);
    endtask

endmodule
