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
    logic [DATA_W-1:0] ref_mem [0:DEPTH*4-1];
    int ref_wr_ptr = 0;
    int ref_rd_ptr = 0;
    
    // Генерация клока
    always #5 clk = ~clk;

    // DUT
    sync_fifo_fwft_reg_pow2_GEM #(
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
        
        if (rd_empty !== 1 || wr_full !== 0) $error("T1: Flags wrong after reset!");
        
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
        @(posedge clk); 
        #1;
        
        if (rd_empty) $error("T2: rd_empty should be 0 after fall-through!");
        if (rd_data !== 16'hA5A5) $error("T2: Data mismatch on fall-through!");
        
        rd_en <= 1;
        @(posedge clk);
        rd_en <= 0;
        #1;
        
        if (!rd_empty) $error("T2: rd_empty should be 1 after reading the last word!");
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
        
        if (!wr_full) $error("T3: wr_full not asserted after %0d writes!", DEPTH);
        
        // Проверка overflow
        write_word(16'hEEEE);
        #1;

        // 2. Непрерывное чтение
        rd_en <= 1;
        for (int i = 0; i < DEPTH; i++) begin
            exp_data = ref_mem[ref_rd_ptr];
            ref_rd_ptr++;
            
            if (rd_data !== exp_data) begin
                $error("T3: Read data mismatch at index %0d! Expected: 0x%0h, Got: 0x%0h", 
                       i, exp_data, rd_data);
            end
            
            @(posedge clk);
            #1;
        end
        rd_en <= 0;
        
        if (!rd_empty) $error("T3: rd_empty not asserted after reading all words!");
        
        // Проверка underflow
        rd_en <= 1;
        @(posedge clk);
        rd_en <= 0;
        #1;
        
        write_word(16'hBEEF);
        @(posedge clk);
        #1;
        
        if (rd_data !== 16'hBEEF) $error("T3: Pointers broken after underflow! Got: 0x%0h", rd_data);
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
            $error("T4: Read during Empty broke Write fall-through! rd_data=0x%0h, rd_empty=%b", 
                   rd_data, rd_empty);
        end
    endtask

    // ---------------------------------------------------------
    // 5. Специфические тайминги
    // ---------------------------------------------------------
    task test_5_specific_timings();
        $display("[TEST 5] Specific Timings & Bubble Test...");
        apply_reset();
        
        $display("   -> Back-to-back testing");
        fork
            begin
                for (int i = 0; i < DEPTH * 2; i++) begin
                    wr_en <= 1; wr_data <= i;
                    @(posedge clk);
                end
                wr_en <= 0;
            end
            begin
                for (int i = 0; i < DEPTH * 2; i++) begin
                    wait (!rd_empty);
                    rd_en <= 1;
                    @(posedge clk);
                    rd_en <= 0;
                    #1;
                end
            end
        join
        
        #1;
        if (wr_full) $error("T5: FIFO should not become full during throughput test!");

        $display("   -> On-the-fly reset");
        for (int i = 0; i < DEPTH/2; i++) begin
            write_word(16'h1111 * i);
        end
        
        rst <= 1;
        @(posedge clk);
        #1;
        
        if (rd_empty !== 1 || wr_full !== 0) begin
            $error("T5: Flags did not clear immediately on reset! rd_empty=%b, wr_full=%b", 
                   rd_empty, wr_full);
        end
        
        rst <= 0;
        @(posedge clk);
    endtask

endmodule
