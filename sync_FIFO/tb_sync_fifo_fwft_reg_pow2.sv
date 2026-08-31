`timescale 1ns/1ps

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

    // Простой статический массив вместо динамической очереди ref_q[$]
    // Это полностью предотвращает ошибку vthread.cc в Icarus Verilog
    
    // Было: 
    // logic [DATA_W-1:0] ref_mem [0:DEPTH*4-1];
    
    // Стало (запас на 1024 транзакции):
    logic [DATA_W-1:0] ref_mem [0:1023];

    int ref_wr_ptr = 0;
    int ref_rd_ptr = 0;
    int err_count  = 0;
    
    // Генерация клока
    always #5 clk = ~clk;

    // DUT
    sync_fifo_fwft_reg_pow2_GEM #(
    // sync_fifo_fwft_reg_pow2_OBF #(        
        .DATA_W(DATA_W),
        .ADDR_W(ADDR_W)
    ) dut (
        .clk(clk), .rst(rst),
        .wr_en(wr_en), .wr_data(wr_data), .wr_full(wr_full), .wr_almost_full(wr_almost_full), .usedw(usedw),
        .rd_en(rd_en), .rd_data(rd_data), .rd_empty(rd_empty), .rd_almost_empty(rd_almost_empty)
    );

    initial begin
        $display("=== STARTING FWFT FIFO TESTBENCH ===");
        
        test_1_reset_and_init();
        test_2_fwft_specifics();
        test_3_boundary_conditions();
        test_4_concurrent_ops();
        test_5_specific_timings();
        
        // $display("=== ALL TESTS PASSED SUCCESSFULLY ===");
        // $finish;
        $display("----------------------------------------");
        if (err_count == 0) begin
            $display("=== ALL TESTS PASSED SUCCESSFULLY ===");
            $finish(0); // Код успешного завершения
        end else begin
            $display("=== TESTBENCH FAILED with %0d ERROR(S) ===", err_count);
            $fatal(1, "Stopping execution due to errors."); // Завершение с ошибкой
        end
    end

    initial begin
      // $dumpfile("sync_FIFO_TB.vcd");
      $dumpfile("sync_FIFO_TB.fst");
      $dumpvars(0, tb_sync_fifo_fwft_reg_pow2);
    end


    // ---------------------------------------------------------
    // Вспомогательные таски
    // ---------------------------------------------------------
    task reset_ref_fifo();
        ref_wr_ptr = 0;
        ref_rd_ptr = 0;
    endtask;

    task apply_reset();
        @(posedge clk);
        rst <= 1; wr_en <= 0; rd_en <= 0; 
        reset_ref_fifo();
        @(posedge clk);
        rst <= 0;
        @(posedge clk);
    endtask

    task write_word(input logic [DATA_W-1:0] data);
        wr_en <= 1; wr_data <= data;
        if (!wr_full) begin
            ref_mem[ref_wr_ptr] = data;
            ref_wr_ptr++;
        end
        @(posedge clk);
        wr_en <= 0;
    endtask

    // ---------------------------------------------------------
    // 1. Базовые проверки и сброс
    // ---------------------------------------------------------
    task test_1_reset_and_init();
        $display("[TEST 1] Reset & Initialization...");
        apply_reset();
        
        // if (rd_empty !== 1 || wr_full !== 0) $error("T1: Flags wrong after reset!");
        if (rd_empty !== 1 || wr_full !== 0) begin
            $display("ERROR [T1]: Flags wrong after reset! rd_empty=%b, wr_full=%b", rd_empty, wr_full);
            err_count++;
        end

        
        wr_data <= 16'hDEAD;
        @(posedge clk);
        if (rd_empty !== 1) begin
            // $error("T1: Garbage written without wr_en!");
            $display("ERROR [T1]: Garbage written without wr_en!");
            err_count++;
        end
    endtask

    // ---------------------------------------------------------
    // 2. Специфика FWFT
    // ---------------------------------------------------------
    task test_2_fwft_specifics();
        $display("[TEST 2] FWFT Specifics (Fall-through)...");
        apply_reset();
        
        write_word(16'hA5A5);
        @(posedge clk); 
        #1;
        
        if (rd_empty) begin
            // $error("T2: rd_empty should be 0 after fall-through!");
            $display("ERROR [T2]: rd_empty should be 0 after fall-through!");
            err_count++;
        end
        
        if (rd_data !== 16'hA5A5) begin
            // $error("T2: Data mismatch on fall-through!");
            $display("ERROR [T2]: Data mismatch on fall-through!");
            err_count++;
        end

        rd_en <= 1;
        @(posedge clk);
        rd_en <= 0;
        #1;
        
        if (!rd_empty) begin
            // $error("T2: rd_empty should be 1 after reading the last word!");
            $display("ERROR [T2]: rd_empty should be 1 after reading the last word!");
            err_count++;
        end
    endtask

    // ---------------------------------------------------------
    // 3. Граничные условия (Empty / Full)
    // ---------------------------------------------------------
    task test_3_boundary_conditions();
        logic [DATA_W-1:0] exp_data;
        $display("[TEST 3] Boundary Conditions...");
        apply_reset();
        
        // 1. Непрерывная запись до полного заполнения
        wr_en <= 1;
        for (int i = 0; i < DEPTH; i++) begin
            wr_data <= 16'h1000 + i;
            ref_mem[ref_wr_ptr] = 16'h1000 + i;
            ref_wr_ptr++;
            @(posedge clk);
        end
        wr_en <= 0;
        #1;
        
        if (!wr_full) begin
            // $error("T3: wr_full not asserted after %0d writes!", DEPTH);
            $display("ERROR [T3]: wr_full not asserted after %0d writes!", DEPTH);
            err_count++;
        end
        
        // Проверка overflow
        write_word(16'hEEEE);
        #1;

        // 2. Непрерывное чтение
        rd_en <= 1;
        for (int i = 0; i < DEPTH; i++) begin
            exp_data = ref_mem[ref_rd_ptr];
            ref_rd_ptr++;
            
            if (rd_data !== exp_data) begin
                // $error("T3: Read data mismatch at index %0d! Expected: 0x%0h, Got: 0x%0h", 
                //        i, exp_data, rd_data);
                $display("ERROR [T3]: Read data mismatch at index %0d! Expected: 0x%0h, Got: 0x%0h", 
                       i, exp_data, rd_data);
                err_count++;
            end
            
            @(posedge clk);
            #1;
        end
        rd_en <= 0;
        
        if (!rd_empty) begin
            // $error("T3: rd_empty not asserted after reading all words!");
            $display("ERROR [T3]: rd_empty not asserted after reading all words!");
            err_count++;
        end
        
        // Проверка underflow
        rd_en <= 1;
        @(posedge clk);
        rd_en <= 0;
        #1;
        
        write_word(16'hBEEF);
        @(posedge clk);
        #1;
        
        if (rd_data !== 16'hBEEF) begin
            // $error("T3: Pointers broken after underflow! Got: 0x%0h", rd_data);
            $display("ERROR [T3]: Pointers broken after underflow! Got: 0x%0h", rd_data);
            err_count++;
        end
    endtask

    // ---------------------------------------------------------
    // 4. Конкурентные операции
    // ---------------------------------------------------------
    task test_4_concurrent_ops();
        $display("[TEST 4] Concurrent Read & Write...");
        apply_reset();
        
        write_word(16'hC001);
        write_word(16'hC002);
        @(posedge clk);
        #1;
        
        wr_en <= 1; wr_data <= 16'hC003;
        rd_en <= 1;
        @(posedge clk);
        wr_en <= 0; rd_en <= 0;
        #1;
        
        apply_reset();
        
        wr_en <= 1; wr_data <= 16'hEEEE;
        rd_en <= 1;
        @(posedge clk);
        wr_en <= 0; rd_en <= 0;
        
        @(posedge clk);
        #1;
        if (rd_data !== 16'hEEEE || rd_empty) begin
            // $error("T4: Read during Empty broke Write fall-through! rd_data=0x%0h, rd_empty=%b", 
            //        rd_data, rd_empty);
            $display("ERROR [T4]: Read during Empty broke Write fall-through! rd_data=0x%0h, rd_empty=%b", 
                   rd_data, rd_empty);
            err_count++;
        end
    endtask

// ---------------------------------------------------------
    // 5. Специфические тайминги
    // ---------------------------------------------------------
    // task test_5_specific_timings();
    //     $display("[TEST 5] Specific Timings & Bubble Test...");
    //     apply_reset();
        
    //     $display("   -> Back-to-back testing");
        
    //     // 1. Предзапись первого слова, чтобы данные «провалились» на rd_data (FWFT)
    //     // и сбросился флаг rd_empty
    //     write_word(16'hA000);
    //     #1;
        
    //     // 2. Непрерывный параллельный поток записи и чтения
    //     fork
    //         // Поток непрерывной записи (wr_en держится 1 без сбросов)
    //         begin
    //             wr_en <= 1;
    //             for (int i = 1; i < DEPTH * 2; i++) begin
    //                 wr_data <= 16'hA000 + i;
    //                 @(posedge clk);
    //             end
    //             wr_en <= 0;
    //         end
            
    //         // Поток непрерывного чтения (rd_en держится 1 без сбросов)
    //         begin
    //             wait (!rd_empty);
    //             rd_en <= 1; // Поднимаем rd_en единожды
    //             for (int i = 0; i < DEPTH * 2; i++) begin
    //                 @(posedge clk);
    //                 #1; // Дельта-задержка для обновления сигналов
    //             end
    //             rd_en <= 0; // Опускаем rd_en только после прохождения всего потока
    //         end
    //     join
        
    //     #1;
    //     if (wr_full) begin
    //         // $error("T5: FIFO should not become full during throughput test!");
    //         $display("ERROR [T5]: FIFO should not become full during throughput test!");
    //         err_count++;
    //     end

    //     // 3. Сброс на лету
    //     $display("   -> On-the-fly reset");
    //     for (int i = 0; i < DEPTH/2; i++) begin
    //         write_word(16'h1111 * i);
    //     end
        
    //     rst <= 1;
    //     @(posedge clk);
    //     #1;
        
    //     if (rd_empty !== 1 || wr_full !== 0) begin
    //         // $error("T5: Flags did not clear immediately on reset! rd_empty=%b, wr_full=%b", 
    //         //        rd_empty, wr_full);
    //         $display("ERROR [T5]: Flags did not clear immediately on reset! rd_empty=%b, wr_full=%b", 
    //                rd_empty, wr_full);
    //         err_count++;
    //     end
        
    //     rst <= 0;
    //     @(posedge clk);
    // endtask
// ---------------------------------------------------------
    // 5. Жесткий Bubble Test (Random Stalls & Timing Pressure)
    // ---------------------------------------------------------
    // task test_5_specific_timings();
    //     int write_cnt = 0;
    //     int read_cnt = 0;
    //     localparam TEST_WORDS = 200; // Прогоняем 200 случайных транзакций
        
    //     $display("[TEST 5] Advanced Bubble Test with Random Stalls...");
    //     apply_reset();

    //     fork

    //         // --- ПОТОК ЗАПИСИ (Учитывает одновременные Read + Write при wr_full) ---
    //         begin
    //             while (write_cnt < TEST_WORDS) begin
    //                 // 70% вероятность попытки записи
    //                 if ($urandom_range(0, 99) < 70) begin
    //                     wr_en   <= 1;
    //                     wr_data <= 16'hA000 + write_cnt;
                        
    //                     #2; // Считываем текущее состояние сигналов
                        
    //                     // Запись успешна, если:
    //                     // 1) FIFO не полное (!wr_full)
    //                     // 2) ИЛИ FIFO полное, но прямо сейчас идет успешное чтение (rd_en && !rd_empty),
    //                     //    которое освобождает 1 ячейку
    //                     if (!wr_full || (rd_en && !rd_empty)) begin
    //                         ref_mem[ref_wr_ptr] = 16'hA000 + write_cnt;
    //                         ref_wr_ptr++;
    //                         write_cnt++;
    //                     end
    //                     // Если FIFO полно и чтения не было — запись игнорируется, 
    //                     // write_cnt не растет, слово повторится на следующем такте.
    //                 end else begin
    //                     wr_en   <= 0; // Пузырь на стороне записи
    //                     wr_data <= 16'hXXXX;
    //                 end
    //                 @(posedge clk);
    //             end
    //             wr_en <= 0;
    //         end

    //         // --- ПОТОК ЧТЕНИЯ (Случайные пузыри) ---
    //         begin
    //             while (read_cnt < TEST_WORDS) begin
    //                 #1; // Проверяем флаг rd_empty на текущем такте
    //                 // 60% вероятность попытки чтения, если FIFO не пустое
    //                 if (!rd_empty && ($urandom_range(0, 99) < 60)) begin
    //                     // Сверяем данные на выходе перед выставлением rd_en
    //                     if (rd_data !== ref_mem[ref_rd_ptr]) begin
    //                         // $display("ERROR [T5 Bubble]: Data mismatch at item %0d! Exp: 0x%0h, Got: 0x%0h",
    //                         //          read_cnt, ref_mem[ref_rd_ptr], rd_data);
    //                         $display("ERROR [T5 Bubble at %0t]: Data mismatch at item %0d! Exp: 0x%0h, Got: 0x%0h",
    //                              $time, read_cnt, ref_mem[ref_rd_ptr], rd_data);
    //                         err_count++;
    //                     end
                        
    //                     rd_en <= 1;
    //                     ref_rd_ptr++;
    //                     read_cnt++;
    //                 end else begin
    //                     rd_en <= 0; // Пузырь на стороне чтения (пауза в потреблении)
    //                 end
    //                 @(posedge clk);
    //             end
    //             rd_en <= 0;
    //         end
    //     join

    //     #1;
    //     // Ожидаем опустошения буфера, если остаток данных не был дочитан
    //     while (!rd_empty) begin
    //         if (rd_data !== ref_mem[ref_rd_ptr]) begin
    //             // $display("ERROR [T5 Drain]: Data mismatch during final drain!");
    //             $display("ERROR [T5 Drain at %0t]: Data mismatch during final drain! Exp: 0x%0h, Got: 0x%0h",
    //                  $time, ref_mem[ref_rd_ptr], rd_data);
    //             err_count++;
    //         end
    //         rd_en <= 1;
    //         ref_rd_ptr++;
    //         @(posedge clk);
    //         #1;
    //     end
    //     rd_en <= 0;

    //     // --- СБРОС НА ЛЕТУ ---
    //     $display("   -> On-the-fly reset test");
    //     for (int i = 0; i < DEPTH/2; i++) begin
    //         write_word(16'h1111 * i);
    //     end
        
    //     rst <= 1;
    //     @(posedge clk);
    //     #1;
        
    //     if (rd_empty !== 1 || wr_full !== 0) begin
    //         $display("ERROR [T5 Reset]: Flags did not clear immediately on reset! rd_empty=%b, wr_full=%b", 
    //                  rd_empty, wr_full);
    //         err_count++;
    //     end
        
    //     rst <= 0;
    //     @(posedge clk);
    // endtask
    // ---------------------------------------------------------
    // 5. Жесткий Bubble Test (Архитектурный подход - Разделение монитора и стимулов)
    // ---------------------------------------------------------
    task test_5_specific_timings();
        localparam TEST_WORDS = 200; // Прогоняем 200 случайных транзакций
        
        $display("[TEST 5] Advanced Bubble Test (Alternative Arch: Separated Stimulus & Monitor)...");
        apply_reset();

        // Запускаем параллельно 3 независимых процесса:
        // 1. Генератор стимулов записи (Write Driver)
        // 2. Генератор стимулов чтения (Read Driver)
        // 3. Синхронный монитор и эталонная модель (Monitor / Checker)
        fork
            // --- 1. ПОТОК СТИМУЛОВ ЗАПИСИ (Write Driver) ---
            begin
                int stim_wr_cnt; // = 0;
                stim_wr_cnt = 0;
                while (stim_wr_cnt < TEST_WORDS) begin
                    // Выставляем сигналы на текущий такт
                    if ($urandom_range(0, 99) < 70) begin
                        wr_en   <= 1;
                        wr_data <= 16'hA000 + stim_wr_cnt;
                    end else begin
                        wr_en   <= 0;
                        wr_data <= 16'hXXXX;
                    end
                    
                    @(posedge clk); // Ждем фронта
                    
                    // ДО изменения сигналов проверяем, прошла ли транзакция на этом фронте
                    if (wr_en && (!wr_full || (rd_en && !rd_empty))) begin
                        stim_wr_cnt++; // Транзакция успешна, переходим к следующему слову
                    end
                end
                wr_en <= 0;
            end

            // --- 2. ПОТОК СТИМУЛОВ ЧТЕНИЯ (Read Driver) ---
            begin
                int stim_rd_cnt; // = 0;
                stim_rd_cnt = 0;
                while (stim_rd_cnt < TEST_WORDS) begin
                    // Разрешаем чтение со случайной вероятностью (только если FIFO не пусто)
                    if (!rd_empty && ($urandom_range(0, 99) < 60)) begin
                        rd_en <= 1;
                    end else begin
                        rd_en <= 0;
                    end
                    
                    @(posedge clk); // Ждем фронта
                    
                    // Проверяем, было ли чтение успешным
                    if (rd_en && !rd_empty) begin
                        stim_rd_cnt++;
                    end
                end
                rd_en <= 0;
            end

            // --- 3. ПОТОК МОНИТОРИНГА И ПРОВЕРКИ (Эталонная модель) ---
            // Этот процесс пассивно наблюдает за шинами строго по фронту клока.
            // Он обновляет память и сравнивает данные. Никаких внутритактовых задержек!
            begin
                int mon_wr_cnt; // = 0;
                int mon_rd_cnt; //= 0;
                
                mon_wr_cnt = 0;                
                mon_rd_cnt = 0;
                
                // Ждем, пока обе операции (запись и чтение) не достигнут лимита
                while (mon_rd_cnt < TEST_WORDS || mon_wr_cnt < TEST_WORDS) begin
                    @(posedge clk); // Оцениваем состояние строго в момент фронта
                    
                    // Логика проверки чтения (FWFT - проверяем ДО снятия флага rd_empty)
                    if (rd_en && !rd_empty) begin
                        if (rd_data !== ref_mem[ref_rd_ptr]) begin
                            $display("ERROR [T5 Monitor at %0t]: Data mismatch at item %0d! Exp: 0x%0h, Got: 0x%0h",
                                     $time, mon_rd_cnt, ref_mem[ref_rd_ptr], rd_data);
                            err_count++;
                        end
                        ref_rd_ptr++;
                        mon_rd_cnt++;
                    end
                    
                    // Логика обновления эталонной памяти при записи
                    if (wr_en && (!wr_full || (rd_en && !rd_empty))) begin
                        ref_mem[ref_wr_ptr] = wr_data;
                        ref_wr_ptr++;
                        mon_wr_cnt++;
                    end
                end
            end
        join

        // --- ОПУСТОШЕНИЕ БУФЕРА (Drain) ---
        // Гарантированно вычищаем все остатки из FIFO без гонок
        rd_en <= 0;
        @(posedge clk); 
        
        while (!rd_empty) begin
            // Проверяем данные (в FWFT они готовы заранее)
            if (rd_data !== ref_mem[ref_rd_ptr]) begin
                $display("ERROR [T5 Drain at %0t]: Data mismatch! Exp: 0x%0h, Got: 0x%0h",
                     $time, ref_mem[ref_rd_ptr], rd_data);
                err_count++;
            end
            
            // Запрашиваем чтение на 1 такт
            rd_en <= 1;
            @(posedge clk);
            
            // Снимаем чтение и даем 1 пустой такт на обновление fall-through логики FIFO
            rd_en <= 0;
            ref_rd_ptr++;
            @(posedge clk); 
        end

        // --- СБРОС НА ЛЕТУ ---
        $display("   -> On-the-fly reset test");
        for (int i = 0; i < DEPTH/2; i++) begin
            write_word(16'h1111 * i);
        end
        
        rst <= 1;
        @(posedge clk); 
        @(posedge clk); // Даем 1 такт, чтобы синхронный сброс внутри DUT отработал
        
        // Проверяем, что флаги очистились (строго на фронте)
        if (rd_empty !== 1 || wr_full !== 0) begin
            $display("ERROR [T5 Reset]: Flags did not clear immediately on reset! rd_empty=%b, wr_full=%b", 
                     rd_empty, wr_full);
            err_count++;
        end
        
        rst <= 0;
        @(posedge clk);
    endtask

endmodule
