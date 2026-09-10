`timescale 1ns / 1ps

// ============================================================================
// Testbench for axis_comparator
//
// Important TB timing convention:
//
//   All stimulus is changed AFTER posedge clk using #1.
//
// This gives:
//
//       posedge
//          |
//          +---- DUT samples signals
//          |
//          +---- DUT NBA updates
//          |
//        #1 ns
//          |
//          +---- TB changes/checks signals
//
// Therefore there is no negedge stimulus and no race with DUT NBA logic.
//
// ============================================================================

module tb_axis_comparator_GT;

    localparam DATA_WIDTH  = 32;
    localparam KEEP_WIDTH  = DATA_WIDTH / 8;
    localparam KEEP_ENABLE = 1;

    localparam CLK_PERIOD = 10;

    // ------------------------------------------------------------------------
    // Clock / reset
    // ------------------------------------------------------------------------

    reg clk;
    reg rst_n;

    integer   test_number;

    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end

  initial begin

    $dumpfile("tb_axis_comparator_GT");
    $dumpvars(0, tb_axis_comparator_GT);
  end

    // ------------------------------------------------------------------------
    // DUT inputs
    // ------------------------------------------------------------------------

    reg select;

    reg [DATA_WIDTH-1:0] s0_tdata;
    reg [KEEP_WIDTH-1:0] s0_tkeep;
    reg                  s0_tvalid;
    reg                  s0_tuser;
    wire                 s0_tready;
    reg                  s0_tlast;

    reg [DATA_WIDTH-1:0] s1_tdata;
    reg [KEEP_WIDTH-1:0] s1_tkeep;
    reg                  s1_tvalid;
    reg                  s1_tuser;
    wire                 s1_tready;
    reg                  s1_tlast;

    // ------------------------------------------------------------------------
    // DUT output
    // ------------------------------------------------------------------------

    wire [DATA_WIDTH-1:0] m_tdata;
    wire [KEEP_WIDTH-1:0] m_tkeep;
    wire                  m_tvalid;
    reg                   m_tready;
    wire                  m_tlast;
    wire                  m_tuser;

    // ------------------------------------------------------------------------
    // DUT
    // ------------------------------------------------------------------------

    axis_comparator #(
        .DATA_WIDTH  (DATA_WIDTH),
        .KEEP_WIDTH  (KEEP_WIDTH),
        .KEEP_ENABLE (KEEP_ENABLE)
    )
    dut (
        .clk       (clk),
        .rst_n     (rst_n),

        .select    (select),

        .s0_tdata  (s0_tdata),
        .s0_tkeep  (s0_tkeep),
        .s0_tvalid (s0_tvalid),
        .s0_tuser  (s0_tuser),
        .s0_tready  (s0_tready),
        .s0_tlast  (s0_tlast),

        .s1_tdata  (s1_tdata),
        .s1_tkeep  (s1_tkeep),
        .s1_tvalid (s1_tvalid),
        .s1_tuser  (s1_tuser),
        .s1_tready  (s1_tready),
        .s1_tlast  (s1_tlast),

        .m_tdata   (m_tdata),
        .m_tkeep   (m_tkeep),
        .m_tvalid  (m_tvalid),
        .m_tready  (m_tready),
        .m_tlast   (m_tlast),
        .m_tuser   (m_tuser)
    );

    // =========================================================================
    // Scoreboard
    // =========================================================================

    localparam MAX_EXPECTED = 4096;

    reg [DATA_WIDTH-1:0] exp_data [0:MAX_EXPECTED-1];
    reg [KEEP_WIDTH-1:0] exp_keep [0:MAX_EXPECTED-1];
    reg                  exp_last [0:MAX_EXPECTED-1];
    reg                  exp_user [0:MAX_EXPECTED-1];

    integer exp_wr_ptr;
    integer exp_rd_ptr;

    integer error_count;
    integer output_count;

    task clear_scoreboard;
    begin
        exp_wr_ptr   = 0;
        exp_rd_ptr   = 0;
        output_count = 0;
    end
    endtask

    task expect_beat;
        input [DATA_WIDTH-1:0] data;
        input [KEEP_WIDTH-1:0] keep;
        input                  last;
        input                  user;
    begin
        if (exp_wr_ptr >= MAX_EXPECTED) begin
            $display("[%0t] FATAL: scoreboard overflow", $time);
            $finish;
        end

        exp_data[exp_wr_ptr] = data;
        exp_keep[exp_wr_ptr] = keep;
        exp_last[exp_wr_ptr] = last;
        exp_user[exp_wr_ptr] = user;

        exp_wr_ptr = exp_wr_ptr + 1;
    end
    endtask

// =========================================================================
    // Output scoreboard monitor
    //
    // ИЗМЕНЕНО: Задержка #1 удалена. Выборка происходит строго по фронту 
    // до того, как триггеры DUT обновят свои значения.
    // =========================================================================

    always @(posedge clk) begin
        if (m_tvalid && m_tready) begin

            output_count = output_count + 1;

            if (exp_rd_ptr >= exp_wr_ptr) begin
                $display("[%0t] ERROR: unexpected output beat", $time);
                error_count = error_count + 1;
            end
            else begin

                if (m_tdata !== exp_data[exp_rd_ptr]) begin
                    $display("[%0t] ERROR: DATA mismatch", $time);
                    $display("         expected = %08h", exp_data[exp_rd_ptr]);
                    $display("         actual   = %08h", m_tdata);
                    error_count = error_count + 1;
                end

                if (m_tkeep !== exp_keep[exp_rd_ptr]) begin
                    $display("[%0t] ERROR: KEEP mismatch", $time);
                    $display("         expected = %0h", exp_keep[exp_rd_ptr]);
                    $display("         actual   = %0h", m_tkeep);
                    error_count = error_count + 1;
                end

                if (m_tlast !== exp_last[exp_rd_ptr]) begin
                    $display("[%0t] ERROR: TLAST mismatch", $time);
                    $display("         expected = %0d", exp_last[exp_rd_ptr]);
                    $display("         actual   = %0d", m_tlast);
                    error_count = error_count + 1;
                end

                if (m_tuser !== exp_user[exp_rd_ptr]) begin
                    $display("[%0t] ERROR: TUSER mismatch", $time);
                    $display("         expected = %0d", exp_user[exp_rd_ptr]);
                    $display("         actual   = %0d", m_tuser);
                    error_count = error_count + 1;
                end
            end

            exp_rd_ptr = exp_rd_ptr + 1;
        end
    end

    // // =========================================================================
    // // Output scoreboard monitor
    // //
    // // IMPORTANT:
    // // This monitor runs AFTER DUT NBA using #1.
    // // =========================================================================

    // always @(posedge clk) begin
    //     #1;

    //     if (m_tvalid && m_tready) begin

    //         output_count = output_count + 1;

    //         if (exp_rd_ptr >= exp_wr_ptr) begin
    //             $display("[%0t] ERROR: unexpected output beat", $time);
    //             error_count = error_count + 1;
    //         end
    //         else begin

    //             if (m_tdata !== exp_data[exp_rd_ptr]) begin
    //                 $display("[%0t] ERROR: DATA mismatch", $time);
    //                 $display("         expected = %08h", exp_data[exp_rd_ptr]);
    //                 $display("         actual   = %08h", m_tdata);
    //                 error_count = error_count + 1;
    //             end

    //             if (m_tkeep !== exp_keep[exp_rd_ptr]) begin
    //                 $display("[%0t] ERROR: KEEP mismatch", $time);
    //                 $display("         expected = %0h", exp_keep[exp_rd_ptr]);
    //                 $display("         actual   = %0h", m_tkeep);
    //                 error_count = error_count + 1;
    //             end

    //             if (m_tlast !== exp_last[exp_rd_ptr]) begin
    //                 $display("[%0t] ERROR: TLAST mismatch", $time);
    //                 $display("         expected = %0d", exp_last[exp_rd_ptr]);
    //                 $display("         actual   = %0d", m_tlast);
    //                 error_count = error_count + 1;
    //             end

    //             if (m_tuser !== exp_user[exp_rd_ptr]) begin
    //                 $display("[%0t] ERROR: TUSER mismatch", $time);
    //                 $display("         expected = %0d", exp_user[exp_rd_ptr]);
    //                 $display("         actual   = %0d", m_tuser);
    //                 error_count = error_count + 1;
    //             end
    //         end

    //         exp_rd_ptr = exp_rd_ptr + 1;
    //     end
    // end

// =========================================================================
    // Output AXIS stall monitor
    //
    // ИЗМЕНЕНО: Задержка #1 удалена. Выборка происходит строго по фронту clk.
    // Если на предыдущем такте VALID=1 и READY=0, сигналы текущего такта 
    // не должны измениться.
    // =========================================================================

    reg                  prev_m_valid;
    reg                  prev_m_ready;
    reg [DATA_WIDTH-1:0] prev_m_data;
    reg [KEEP_WIDTH-1:0] prev_m_keep;
    reg                  prev_m_last;
    reg                  prev_m_user;

    always @(posedge clk) begin
        if (rst_n) begin
            if (prev_m_valid && !prev_m_ready) begin

                if (!m_tvalid) begin
                    $display("[%0t] ERROR: m_tvalid dropped while stalled", $time);
                    error_count = error_count + 1;
                end

                if (m_tdata !== prev_m_data) begin
                    $display("[%0t] ERROR: m_tdata changed while stalled", $time);
                    $display("         previous = %08h", prev_m_data);
                    $display("         current  = %08h", m_tdata);
                    error_count = error_count + 1;
                end

                if (m_tkeep !== prev_m_keep) begin
                    $display("[%0t] ERROR: m_tkeep changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (m_tlast !== prev_m_last) begin
                    $display("[%0t] ERROR: m_tlast changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (m_tuser !== prev_m_user) begin
                    $display("[%0t] ERROR: m_tuser changed while stalled", $time);
                    error_count = error_count + 1;
                end
            end
        end

        // Сохраняем значения текущего такта для проверки на следующем
        prev_m_valid <= m_tvalid;
        prev_m_ready <= m_tready;
        prev_m_data  <= m_tdata;
        prev_m_keep  <= m_tkeep;
        prev_m_last  <= m_tlast;
        prev_m_user  <= m_tuser;
    end

    // // =========================================================================
    // // Output AXIS stall monitor
    // //
    // // If VALID && !READY at cycle N, all output payload must remain identical
    // // at cycle N+1.
    // //
    // // Sampling is performed after #1 so DUT NBA is complete.
    // // =========================================================================

    // reg                  prev_m_valid;
    // reg                  prev_m_ready;
    // reg [DATA_WIDTH-1:0] prev_m_data;
    // reg [KEEP_WIDTH-1:0] prev_m_keep;
    // reg                  prev_m_last;
    // reg                  prev_m_user;

    // always @(posedge clk) begin
    //     #1;

    //     if (prev_m_valid && !prev_m_ready) begin

    //         if (!m_tvalid) begin
    //             $display("[%0t] ERROR: m_tvalid dropped while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (m_tdata !== prev_m_data) begin
    //             $display("[%0t] ERROR: m_tdata changed while stalled",
    //                      $time);
    //             $display("         previous = %08h", prev_m_data);
    //             $display("         current  = %08h", m_tdata);
    //             error_count = error_count + 1;
    //         end

    //         if (m_tkeep !== prev_m_keep) begin
    //             $display("[%0t] ERROR: m_tkeep changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (m_tlast !== prev_m_last) begin
    //             $display("[%0t] ERROR: m_tlast changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (m_tuser !== prev_m_user) begin
    //             $display("[%0t] ERROR: m_tuser changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end
    //     end

    //     prev_m_valid = m_tvalid;
    //     prev_m_ready = m_tready;
    //     prev_m_data  = m_tdata;
    //     prev_m_keep  = m_tkeep;
    //     prev_m_last  = m_tlast;
    //     prev_m_user  = m_tuser;
    // end

// =========================================================================
    // Input AXIS protocol monitor
    //
    // ИЗМЕНЕНО: Задержка #1 удалена. Монитор проверяет соблюдение спецификации
    // AXI Stream источниками (S0 и S1) строго в момент фронта clk.
    // =========================================================================

    reg                  prev_s0_valid;
    reg                  prev_s0_ready;
    reg [DATA_WIDTH-1:0] prev_s0_data;
    reg [KEEP_WIDTH-1:0] prev_s0_keep;
    reg                  prev_s0_last;
    reg                  prev_s0_user;

    reg                  prev_s1_valid;
    reg                  prev_s1_ready;
    reg [DATA_WIDTH-1:0] prev_s1_data;
    reg [KEEP_WIDTH-1:0] prev_s1_keep;
    reg                  prev_s1_last;
    reg                  prev_s1_user;

    always @(posedge clk) begin
        if (rst_n) begin
            // ------------------------------
            // S0
            // ------------------------------
            if (prev_s0_valid && !prev_s0_ready) begin

                if (!s0_tvalid) begin
                    $display("[%0t] ERROR: s0_tvalid dropped while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s0_tdata !== prev_s0_data) begin
                    $display("[%0t] ERROR: s0_tdata changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s0_tkeep !== prev_s0_keep) begin
                    $display("[%0t] ERROR: s0_tkeep changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s0_tlast !== prev_s0_last) begin
                    $display("[%0t] ERROR: s0_tlast changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s0_tuser !== prev_s0_user) begin
                    $display("[%0t] ERROR: s0_tuser changed while stalled", $time);
                    error_count = error_count + 1;
                end
            end

            // ------------------------------
            // S1
            // ------------------------------
            if (prev_s1_valid && !prev_s1_ready) begin

                if (!s1_tvalid) begin
                    $display("[%0t] ERROR: s1_tvalid dropped while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s1_tdata !== prev_s1_data) begin
                    $display("[%0t] ERROR: s1_tdata changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s1_tkeep !== prev_s1_keep) begin
                    $display("[%0t] ERROR: s1_tkeep changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s1_tlast !== prev_s1_last) begin
                    $display("[%0t] ERROR: s1_tlast changed while stalled", $time);
                    error_count = error_count + 1;
                end

                if (s1_tuser !== prev_s1_user) begin
                    $display("[%0t] ERROR: s1_tuser changed while stalled", $time);
                    error_count = error_count + 1;
                end
            end
        end

        // Сохранение состояний
        prev_s0_valid <= s0_tvalid;
        prev_s0_ready <= s0_tready;
        prev_s0_data  <= s0_tdata;
        prev_s0_keep  <= s0_tkeep;
        prev_s0_last  <= s0_tlast;
        prev_s0_user  <= s0_tuser;

        prev_s1_valid <= s1_tvalid;
        prev_s1_ready <= s1_tready;
        prev_s1_data  <= s1_tdata;
        prev_s1_keep  <= s1_tkeep;
        prev_s1_last  <= s1_tlast;
        prev_s1_user  <= s1_tuser;
    end
    // // =========================================================================
    // // Input AXIS protocol monitor
    // //
    // // Masters must hold VALID + payload while READY=0.
    // // =========================================================================

    // reg                  prev_s0_valid;
    // reg                  prev_s0_ready;
    // reg [DATA_WIDTH-1:0] prev_s0_data;
    // reg [KEEP_WIDTH-1:0] prev_s0_keep;
    // reg                  prev_s0_last;
    // reg                  prev_s0_user;

    // reg                  prev_s1_valid;
    // reg                  prev_s1_ready;
    // reg [DATA_WIDTH-1:0] prev_s1_data;
    // reg [KEEP_WIDTH-1:0] prev_s1_keep;
    // reg                  prev_s1_last;
    // reg                  prev_s1_user;

    // always @(posedge clk) begin
    //     #1;

    //     // ------------------------------
    //     // S0
    //     // ------------------------------

    //     if (prev_s0_valid && !prev_s0_ready) begin

    //         if (!s0_tvalid) begin
    //             $display("[%0t] ERROR: s0_tvalid dropped while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s0_tdata !== prev_s0_data) begin
    //             $display("[%0t] ERROR: s0_tdata changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s0_tkeep !== prev_s0_keep) begin
    //             $display("[%0t] ERROR: s0_tkeep changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s0_tlast !== prev_s0_last) begin
    //             $display("[%0t] ERROR: s0_tlast changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s0_tuser !== prev_s0_user) begin
    //             $display("[%0t] ERROR: s0_tuser changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end
    //     end

    //     // ------------------------------
    //     // S1
    //     // ------------------------------

    //     if (prev_s1_valid && !prev_s1_ready) begin

    //         if (!s1_tvalid) begin
    //             $display("[%0t] ERROR: s1_tvalid dropped while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s1_tdata !== prev_s1_data) begin
    //             $display("[%0t] ERROR: s1_tdata changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s1_tkeep !== prev_s1_keep) begin
    //             $display("[%0t] ERROR: s1_tkeep changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s1_tlast !== prev_s1_last) begin
    //             $display("[%0t] ERROR: s1_tlast changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end

    //         if (s1_tuser !== prev_s1_user) begin
    //             $display("[%0t] ERROR: s1_tuser changed while stalled",
    //                      $time);
    //             error_count = error_count + 1;
    //         end
    //     end

    //     prev_s0_valid = s0_tvalid;
    //     prev_s0_ready = s0_tready;
    //     prev_s0_data  = s0_tdata;
    //     prev_s0_keep  = s0_tkeep;
    //     prev_s0_last  = s0_tlast;
    //     prev_s0_user  = s0_tuser;

    //     prev_s1_valid = s1_tvalid;
    //     prev_s1_ready = s1_tready;
    //     prev_s1_data  = s1_tdata;
    //     prev_s1_keep  = s1_tkeep;
    //     prev_s1_last  = s1_tlast;
    //     prev_s1_user  = s1_tuser;
    // end

    // =========================================================================
    // Reset
    // =========================================================================

    task reset_dut;
    begin

        s0_tvalid = 1'b0;
        s0_tdata  = {DATA_WIDTH{1'b0}};
        s0_tkeep  = {KEEP_WIDTH{1'b1}};
        s0_tlast  = 1'b0;
        s0_tuser  = 1'b0;

        s1_tvalid = 1'b0;
        s1_tdata  = {DATA_WIDTH{1'b0}};
        s1_tkeep  = {KEEP_WIDTH{1'b1}};
        s1_tlast  = 1'b0;
        s1_tuser  = 1'b0;

        select    = 1'b0;
        m_tready  = 1'b0;

        @(posedge clk);
        #1;
        rst_n = 1'b0;

        @(posedge clk);
        #1;
        rst_n = 1'b0;

        @(posedge clk);
        #1;
        rst_n = 1'b1;

        // Give DUT one clean clock after reset release.
        @(posedge clk);
        #1;

        prev_m_valid = 1'b0;
        prev_m_ready = 1'b0;

        prev_s0_valid = 1'b0;
        prev_s0_ready = 1'b0;

        prev_s1_valid = 1'b0;
        prev_s1_ready = 1'b0;
    end
    endtask

    // =========================================================================
    // Wait until both inputs are ready.
    //
    // This task is mostly useful for debugging.
    // =========================================================================

    task wait_both_ready;
    begin
        while (!(s0_tready && s1_tready)) begin
            @(posedge clk);
            #1;
        end
    end
    endtask

    // =========================================================================
    // Send ONE beat from S0.
    //
    // The task sets VALID/DATA after posedge and holds everything until
    // handshake occurs.
    //
    // gap_before:
    //   number of idle clock cycles before asserting VALID.
    // =========================================================================

    task s0_send_beat;
        input [DATA_WIDTH-1:0] data;
        input [KEEP_WIDTH-1:0] keep;
        input                  last;
        input                  user;
        input integer          gap_before;

        integer i;
        reg beat_done;
    begin

        // Idle gap
        s0_tvalid = 1'b0;
        beat_done = 0;

        for (i = 0; i < gap_before; i = i + 1) begin
            @(posedge clk);
            #1;
        end

        // Present beat
        s0_tdata  = data;
        s0_tkeep  = keep;
        s0_tlast  = last;
        s0_tuser  = user;
        s0_tvalid = 1'b1;

        // Hold until handshake
        // while (1) begin
        //     @(posedge clk);
        //     #1;

        //     if (s0_tvalid && s0_tready) begin
        //         s0_tvalid = 1'b0;
        //         break;
        //     end
        // end

        // while (1) begin
        //     @(posedge clk);
        //     // 1. Проверяем состояние ДО того, как DUT изменит выходы
        //     if (s0_tvalid && s0_tready) begin
        //         #1; // 2. Ждем завершения NBA-присваиваний
        //         s0_tvalid = 1'b0;
        //         break;
        //     end else begin
        //         #1; // Просто сдвигаем симуляцию для удержания сигналов
        //     end
        // end

        while (!beat_done) begin
            @(posedge clk);
            // 1. Проверяем рукопожатие строго на фронте
            if (s0_tvalid && s0_tready) begin
                #1; // Ждем завершения NBA-присваиваний
                s0_tvalid = 1'b0;
                beat_done = 1'b1; // Флаг завершения цикла вместо break
            end else begin
                #1; // Удерживаем сигналы
            end
        end
    end
    endtask

    // =========================================================================
    // Send ONE beat from S1.
    // =========================================================================

    task s1_send_beat;
        input [DATA_WIDTH-1:0] data;
        input [KEEP_WIDTH-1:0] keep;
        input                  last;
        input                  user;
        input integer          gap_before;

        integer i;
        reg beat_done;
    begin

        s1_tvalid = 1'b0;
        beat_done = 0;

        for (i = 0; i < gap_before; i = i + 1) begin
            @(posedge clk);
            #1;
        end

        s1_tdata  = data;
        s1_tkeep  = keep;
        s1_tlast  = last;
        s1_tuser  = user;
        s1_tvalid = 1'b1;

        // while (1) begin
        //     @(posedge clk);
        //     #1;

        //     if (s1_tvalid && s1_tready) begin
        //         s1_tvalid = 1'b0;
        //         break;
        //     end
        // end

        // while (1) begin
        //     @(posedge clk);
        //     // 1. Проверяем состояние ДО того, как DUT изменит выходы
        //     if (s1_tvalid && s1_tready) begin
        //         #1; // 2. Ждем завершения NBA-присваиваний
        //         s1_tvalid = 1'b0;
        //         break;
        //     end else begin
        //         #1; // Просто сдвигаем симуляцию для удержания сигналов
        //     end
        // end

        while (!beat_done) begin
            @(posedge clk);
            // 1. Проверяем рукопожатие строго на фронте
            if (s1_tvalid && s1_tready) begin
                #1; // Ждем завершения NBA-присваиваний
                s1_tvalid = 1'b0;
                beat_done = 1'b1; // Флаг завершения цикла вместо break
            end else begin
                #1; // Удерживаем сигналы
            end
        end
    end
    endtask

    // =========================================================================
    // Parallel frame generators
    //
    // Verilog-2001 does not have convenient task array arguments, so these
    // generate deterministic test frames from parameters.
    // =========================================================================

    integer frame_len;

    integer mismatch_beat_s0;
    integer mismatch_beat_s1;

    integer user_beat_s0;
    integer user_beat_s1;

    integer keep_bad_beat_s0;
    integer keep_bad_beat_s1;

    integer s0_gap;
    integer s1_gap;

    reg [DATA_WIDTH-1:0] base_data;

    // ------------------------------------------------------------------------
    // S0 frame process
    // ------------------------------------------------------------------------

    task start_s0_frame;
        input integer length;
        input [DATA_WIDTH-1:0] start_data;
        input integer gap;
        input integer mismatch_beat;
        input integer user_beat;
        input integer keep_bad_beat;
    begin
        fork
            begin : S0_FRAME_THREAD

                integer i;
                reg [DATA_WIDTH-1:0] d;
                reg [KEEP_WIDTH-1:0] k;
                reg l;
                reg u;

                for (i = 0; i < length; i = i + 1) begin

                    d = start_data + i;

                    k = {KEEP_WIDTH{1'b1}};

                    if (keep_bad_beat == i)
                        k = {{(KEEP_WIDTH-1){1'b1}},1'b0};

                    u = (user_beat == i);
                    l = (i == length-1);

                    s0_send_beat(
                        d,
                        k,
                        l,
                        u,
                        (i == 0) ? gap : gap
                    );
                end
            end
        join_none
    end
    endtask

    // ------------------------------------------------------------------------
    // S1 frame process
    // ------------------------------------------------------------------------

    task start_s1_frame;
        input integer length;
        input [DATA_WIDTH-1:0] start_data;
        input integer gap;
        input integer mismatch_beat;
        input integer user_beat;
        input integer keep_bad_beat;
    begin
        fork
            begin : S1_FRAME_THREAD

                integer i;
                reg [DATA_WIDTH-1:0] d;
                reg [KEEP_WIDTH-1:0] k;
                reg l;
                reg u;

                for (i = 0; i < length; i = i + 1) begin

                    d = start_data + i;

                    k = {KEEP_WIDTH{1'b1}};

                    if (keep_bad_beat == i)
                        k = {{(KEEP_WIDTH-1){1'b1}},1'b0};

                    u = (user_beat == i);
                    l = (i == length-1);

                    s1_send_beat(
                        d,
                        k,
                        l,
                        u,
                        gap
                    );
                end
            end
        join_none
    end
    endtask

    // =========================================================================
    // TEST 1
    //
    // Equal frames
    // select = 0
    //
    // S0 is fast, S1 is slower.
    //
    // Expected output = S0.
    // =========================================================================

    task test1_equal_select0;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 1: EQUAL FRAMES, SELECT=0");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        // Expected output
        expect_beat(32'h10000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h10000001, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h10000002, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h10000003, 4'hF, 1'b1, 1'b0);

        // S0 fast
        fork
            begin
                integer i;
                for (i = 0; i < 4; i = i + 1) begin
                    s0_send_beat(
                        32'h10000000 + i,
                        4'hF,
                        (i == 3),
                        1'b0,
                        0
                    );
                end
            end

            // S1 slower
            begin
                integer j;
                for (j = 0; j < 4; j = j + 1) begin
                    s1_send_beat(
                        32'h10000000 + j,
                        4'hF,
                        (j == 3),
                        1'b0,
                        (j == 0) ? 2 : 1
                    );
                end
            end
        join

        // Allow output pipeline / flush state to settle.
        repeat (10) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 1 scoreboard not empty", $time);
            $display("         expected beats = %0d", exp_wr_ptr);
            $display("         received beats = %0d", exp_rd_ptr);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 1 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 2
    //
    // Equal frames
    // select = 1
    // =========================================================================

    task test2_equal_select1;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 2: EQUAL FRAMES, SELECT=1");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b1;
        m_tready = 1'b1;

        expect_beat(32'h20000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h20000001, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h20000002, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h20000003, 4'hF, 1'b1, 1'b0);

        fork
            begin
                integer i;
                for (i = 0; i < 4; i = i + 1) begin
                    s0_send_beat(
                        32'h20000000 + i,
                        4'hF,
                        (i == 3),
                        1'b0,
                        1
                    );
                end
            end

            begin
                integer j;
                for (j = 0; j < 4; j = j + 1) begin
                    s1_send_beat(
                        32'h20000000 + j,
                        4'hF,
                        (j == 3),
                        1'b0,
                        0
                    );
                end
            end
        join

        repeat (10) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 2 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 2 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 3
    //
    // Data mismatch in the middle of frame.
    //
    // select = 0
    //
    // Beat 2:
    //   S0 = 30000002
    //   S1 = DEAD0002
    //
    // Output must be S0 data, TLAST=1, TUSER=1.
    // Then DUT enters FLUSH.
    // =========================================================================

    task test3_data_mismatch;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 3: DATA MISMATCH");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        expect_beat(32'h30000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h30000001, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h30000002, 4'hF, 1'b1, 1'b1);

        fork
            begin
                s0_send_beat(32'h30000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h30000001, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h30000002, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h30000003, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'h30000000, 4'hF, 1'b0, 1'b0, 1);
                s1_send_beat(32'h30000001, 4'hF, 1'b0, 1'b0, 1);
                s1_send_beat(32'hDEAD0002, 4'hF, 1'b0, 1'b0, 1);
                s1_send_beat(32'h30000003, 4'hF, 1'b1, 1'b0, 1);
            end
        join

        repeat (15) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 3 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 3 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 4
    //
    // TUSER asserted on one input.
    // This is a mismatch condition.
    // =========================================================================

    task test4_user_mismatch;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 4: TUSER MISMATCH");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        expect_beat(32'h40000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h40000001, 4'hF, 1'b1, 1'b1);

        fork
            begin
                s0_send_beat(32'h40000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h40000001, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h40000002, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'h40000000, 4'hF, 1'b0, 1'b0, 1);
                s1_send_beat(32'h40000001, 4'hF, 1'b0, 1'b1, 1);
                s1_send_beat(32'h40000002, 4'hF, 1'b1, 1'b0, 1);
            end
        join

        repeat (15) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 4 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 4 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 5
    //
    // TKEEP mismatch.
    // =========================================================================

    task test5_keep_mismatch;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 5: TKEEP MISMATCH");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        expect_beat(32'h50000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h50000001, 4'hF, 1'b1, 1'b1);

        fork
            begin
                s0_send_beat(32'h50000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h50000001, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h50000002, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'h50000000, 4'hF, 1'b0, 1'b0, 1);
                s1_send_beat(32'h50000001, 4'h7, 1'b0, 1'b0, 1);
                s1_send_beat(32'h50000002, 4'hF, 1'b1, 1'b0, 1);
            end
        join

        repeat (15) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 5 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 5 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 6
    //
    // One side reaches TLAST first while data still matches.
    //
    // S0 TLAST at beat 1.
    // S1 continues.
    //
    // Output beat 1 must terminate the transfer without mismatch.
    // =========================================================================

    task test6_early_tlast;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 6: EARLY TLAST");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        expect_beat(32'h60000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h60000001, 4'hF, 1'b1, 1'b0);

        fork
            begin
                s0_send_beat(32'h60000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h60000001, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'h60000000, 4'hF, 1'b0, 1'b0, 1);
                s1_send_beat(32'h60000001, 4'hF, 1'b0, 1'b0, 1);
                s1_send_beat(32'h60000002, 4'hF, 1'b1, 1'b0, 1);
            end
        join

        repeat (15) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 6 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 6 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 7
    //
    // Backpressure.
    //
    // This is important for checking the internal two-entry output buffering.
    //
    // m_tready is intentionally toggled.
    // =========================================================================

    task test7_backpressure;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 7: OUTPUT BACKPRESSURE");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select = 1'b0;

        expect_beat(32'h70000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h70000001, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h70000002, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h70000003, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h70000004, 4'hF, 1'b1, 1'b0);

        fork

            // S0
            begin
                s0_send_beat(32'h70000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h70000001, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h70000002, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h70000003, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h70000004, 4'hF, 1'b1, 1'b0, 0);
            end

            // S1
            begin
                s1_send_beat(32'h70000000, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h70000001, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h70000002, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h70000003, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h70000004, 4'hF, 1'b1, 1'b0, 0);
            end

            // Backpressure generator
            begin
                m_tready = 1'b0;

                repeat (8) begin
                    @(posedge clk);
                    #1;
                end

                m_tready = 1'b1;

                repeat (2) begin
                    @(posedge clk);
                    #1;
                end

                m_tready = 1'b0;

                repeat (5) begin
                    @(posedge clk);
                    #1;
                end

                m_tready = 1'b1;
            end

        join

        repeat (20) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 7 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 7 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 8
    //
    // select must remain locked during frame.
    //
    // Start with select=0.
    // Change select=1 in the middle of the frame.
    //
    // Output must still come from S0.
    // =========================================================================

    task test8_select_locked;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 8: SELECT LOCKED DURING FRAME");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        expect_beat(32'h80000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h80000001, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h80000002, 4'hF, 1'b1, 1'b0);

        fork

            begin
                s0_send_beat(32'h80000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h80000001, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h80000002, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'h80000000, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h80000001, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h80000002, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                // Change select while frame is active.
                repeat (3) begin
                    @(posedge clk);
                    #1;
                end

                select = 1'b1;
            end

        join

        repeat (10) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 8 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 8 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 9
    //
    // New frame after FLUSH.
    //
    // First frame mismatches.
    // Then a completely new frame must work.
    // =========================================================================

    task test9_flush_then_new_frame;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 9: FLUSH THEN NEW FRAME");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        // First frame
        expect_beat(32'h90000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h90000001, 4'hF, 1'b1, 1'b1);

        fork
            begin
                s0_send_beat(32'h90000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h90000001, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h90000002, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'h90000000, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'hBAD00001, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h90000002, 4'hF, 1'b1, 1'b0, 0);
            end
        join

        // Wait for flush to complete.
        repeat (15) begin
            @(posedge clk);
            #1;
        end

        // Second frame
        expect_beat(32'h91000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'h91000001, 4'hF, 1'b1, 1'b0);

        fork
            begin
                s0_send_beat(32'h91000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'h91000001, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'h91000000, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'h91000001, 4'hF, 1'b1, 1'b0, 0);
            end
        join

        repeat (10) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 9 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 9 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // TEST 10
    //
    // Mismatch on final beat.
    //
    // Both sides assert TLAST.
    // Therefore mismatch is reported but no FLUSH is required.
    // =========================================================================

    task test10_mismatch_final_beat;
    begin

        $display("");
        $display("============================================================");
        $display("TEST 10: MISMATCH ON FINAL BEAT");
        // $display("============================================================");

        reset_dut;
        clear_scoreboard;

        select   = 1'b0;
        m_tready = 1'b1;

        expect_beat(32'hA0000000, 4'hF, 1'b0, 1'b0);
        expect_beat(32'hA0000001, 4'hF, 1'b1, 1'b1);

        fork
            begin
                s0_send_beat(32'hA0000000, 4'hF, 1'b0, 1'b0, 0);
                s0_send_beat(32'hA0000001, 4'hF, 1'b1, 1'b0, 0);
            end

            begin
                s1_send_beat(32'hA0000000, 4'hF, 1'b0, 1'b0, 0);
                s1_send_beat(32'hBBBB0001, 4'hF, 1'b1, 1'b0, 0);
            end
        join

        repeat (10) begin
            @(posedge clk);
            #1;
        end

        if (exp_rd_ptr != exp_wr_ptr) begin
            $display("[%0t] ERROR: TEST 10 scoreboard not empty", $time);
            error_count = error_count + 1;
        end
        else begin
            $display("[%0t] TEST 10 PASS", $time);
        end
    end
    endtask

    // =========================================================================
    // Main
    // =========================================================================

    initial begin

        rst_n = 1'b0;

        select   = 1'b0;
        m_tready = 1'b0;

        s0_tvalid = 1'b0;
        s0_tdata  = 0;
        s0_tkeep  = {KEEP_WIDTH{1'b1}};
        s0_tlast  = 1'b0;
        s0_tuser  = 1'b0;

        s1_tvalid = 1'b0;
        s1_tdata  = 0;
        s1_tkeep  = {KEEP_WIDTH{1'b1}};
        s1_tlast  = 1'b0;
        s1_tuser  = 1'b0;

        error_count = 0;

        exp_wr_ptr = 0;
        exp_rd_ptr = 0;

        prev_m_valid = 0;
        prev_m_ready = 0;

        prev_s0_valid = 0;
        prev_s0_ready = 0;

        prev_s1_valid = 0;
        prev_s1_ready = 0;

        // ------------------------------------------------------------
        // Tests
        // ------------------------------------------------------------
        test_number = 1;
        test1_equal_select0;
        test_number = 2;
        test2_equal_select1;
        test_number = 3;
        test3_data_mismatch;
        test_number = 4;
        test4_user_mismatch;
        test_number = 5;
        test5_keep_mismatch;
        test_number = 6;
        test6_early_tlast;
        test_number = 7;
        test7_backpressure;
        test_number = 8;
        test8_select_locked;
        test_number = 9;
        test9_flush_then_new_frame;
        test_number = 10;
        test10_mismatch_final_beat;

        // ------------------------------------------------------------
        // Final result
        // ------------------------------------------------------------

        $display("");
        $display("============================================================");
        $display("FINAL TEST RESULT:");
        $display("");
        // $display("============================================================");

        if (error_count == 0) begin
            $display("ALL TESTS PASSED, error_count = %0d", error_count);
        end
        else begin
            $display("TEST FAILED: %0d errors", error_count);
        end

        $display("============================================================");
        $display("");

        #100;
        $finish;
    end

endmodule
