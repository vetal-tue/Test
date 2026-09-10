`timescale 1ns / 1ps

module tb_axis_comparator_GE ();

  parameter DATA_WIDTH = 32;
  parameter KEEP_WIDTH = DATA_WIDTH / 8;

  logic                  clk = 0;
  logic                  rst_n = 0;
  logic                  select = 0;

  logic [DATA_WIDTH-1:0] s0_tdata = 0;
  logic [KEEP_WIDTH-1:0] s0_tkeep = '1;
  logic                  s0_tvalid = 0;
  logic                  s0_tuser = 0;
  logic                  s0_tready;
  logic                  s0_tlast = 0;

  logic [DATA_WIDTH-1:0] s1_tdata = 0;
  logic [KEEP_WIDTH-1:0] s1_tkeep = '1;
  logic                  s1_tvalid = 0;
  logic                  s1_tuser = 0;
  logic                  s1_tready;
  logic                  s1_tlast = 0;

  logic [DATA_WIDTH-1:0] m_tdata;
  logic [KEEP_WIDTH-1:0] m_tkeep;
  logic                  m_tvalid;
  logic                  m_tready = 0;
  logic                  m_tlast;
  logic                  m_tuser;

  axis_comparator #(
      .DATA_WIDTH (DATA_WIDTH),
      .KEEP_WIDTH (KEEP_WIDTH),
      .KEEP_ENABLE(1)
  ) dut (
      .*
  );

  always #5 clk = ~clk;

  // Очереди
  logic [DATA_WIDTH-1:0] exp_data_q      [$];
  logic                  exp_last_q      [$];
  logic                  exp_user_q      [$];

  // ДОБАВЛЕНО: Явный счетчик для Icarus Verilog
  int                    pending_tx = 0;
  int                    error_count = 0;

  // ================================================================
  // Waveform dump
  // ================================================================

  initial begin
    $dumpfile("tb_axis_comparator_GE");
    $dumpvars(0, tb_axis_comparator_GE);
  end

  // Монитор
  initial begin
    forever begin
      @(posedge clk);
      if (m_tvalid && m_tready && rst_n) begin
        // ИСПОЛЬЗУЕМ СЧЕТЧИК вместо вызова .size()
        if (pending_tx > 0) begin
          logic [DATA_WIDTH-1:0] exp_data;
          logic                  exp_last;
          logic                  exp_user;

          exp_data = exp_data_q.pop_front();
          exp_last = exp_last_q.pop_front();
          exp_user = exp_user_q.pop_front();

          // ДОБАВЛЕНО: Уменьшаем счетчик при вычитывании эталона
          pending_tx--;

          if (m_tdata !== exp_data || m_tlast !== exp_last || m_tuser !== exp_user) begin
            $error(
                "[ОШИБКА] Время: %0t | Ожидалось: Data=%h Last=%b User=%b | Получено: Data=%h Last=%b User=%b",
                $time, exp_data, exp_last, exp_user, m_tdata, m_tlast, m_tuser);
            error_count++;
          end else begin
            $display("[ОК] Время: %0t | Data=%h Last=%b User=%b", $time, m_tdata, m_tlast,
                     m_tuser);
          end
        end else begin
          $error(
              "[ОШИБКА] Время: %0t | Неожиданные данные на выходе! Data=%h Last=%b User=%b",
              $time, m_tdata, m_tlast, m_tuser);
          error_count++;
        end
      end
    end
  end

  // Драйвер
  task send_word(input logic [DATA_WIDTH-1:0] d0, input logic l0, input logic [DATA_WIDTH-1:0] d1,
                 input logic l1, input logic expect_out, input logic exp_last,
                 input logic exp_user);
    begin
      if (expect_out) begin
        exp_data_q.push_back(select ? d1 : d0);
        exp_last_q.push_back(exp_last);
        exp_user_q.push_back(exp_user);

        // ДОБАВЛЕНО: Увеличиваем счетчик при добавлении
        pending_tx++;
      end

      s0_tdata  = d0;
      s0_tlast  = l0;
      s0_tvalid = 1;
      s1_tdata  = d1;
      s1_tlast  = l1;
      s1_tvalid = 1;

      fork
        begin
          do begin
            @(posedge clk);
          end while (!(s0_tready && s0_tvalid));
          s0_tvalid = 0;
        end
        begin
          do begin
            @(posedge clk);
          end while (!(s1_tready && s1_tvalid));
          s1_tvalid = 0;
        end
      join
    end
  endtask

  // Сценарии
  initial begin
    rst_n = 0;
    select = 0;
    m_tready = 1;

    #25 rst_n = 1;
    @(posedge clk);

    $display("--- Тест 1: Успешная передача кадра ---");
    select = 0;
    send_word(32'hAA, 0, 32'hAA, 0, 1, 0, 0);
    send_word(32'hBB, 0, 32'hBB, 0, 1, 0, 0);
    send_word(32'hCC, 1, 32'hCC, 1, 1, 1, 0);

    // ИЗМЕНЕНО: Синхронизация по явному счетчику транзакций
    wait (pending_tx == 0);
    #30;

    $display(
        "--- Тест 2: Разрыв кадра из-за несовпадения (STATE_FLUSH) ---");
    select = 1;

    send_word(32'h11, 0, 32'h11, 0, 1, 0, 0);
    send_word(32'h22, 0, 32'hFF, 0, 1, 1, 1);

    send_word(32'h33, 0, 32'h33, 0, 0, 0, 0);
    send_word(32'h44, 1, 32'h44, 1, 0, 0, 0);

    // ИЗМЕНЕНО
    wait (pending_tx == 0);
    #30;

    $display(
        "--- Тест 3: Разная скорость интерфейсов и Skid Buffer ---");
    select = 0;

    fork
      begin
        send_word(32'h55, 0, 32'h55, 0, 1, 0, 0);
        send_word(32'h66, 1, 32'h66, 1, 1, 1, 0);
      end
      begin
        m_tready = 0;
        #45 m_tready = 1;
        #10 m_tready = 0;
        #20 m_tready = 1;
      end
    join

    // ИЗМЕНЕНО
    wait (pending_tx == 0);
    #50;

    $display("========================================");
    if (error_count == 0) begin
      $display("УСПЕХ! Симуляция пройдена без ошибок.");
    end else begin
      $display("ПРОВАЛ! Найдено %0d ошибок.", error_count);
    end
    $display("========================================");

    $finish;
  end

endmodule

// `timescale 1ns / 1ps

// module tb_axis_comparator_GE ();

//   // Параметры
//   parameter DATA_WIDTH = 32;
//   parameter KEEP_WIDTH = DATA_WIDTH / 8;

//   // Сигналы
//   reg                   clk;
//   reg                   rst_n;
//   reg                   select;

//   // Интерфейс Slave 0
//   reg  [DATA_WIDTH-1:0] s0_tdata;
//   reg  [KEEP_WIDTH-1:0] s0_tkeep;
//   reg                   s0_tvalid;
//   reg                   s0_tuser;
//   wire                  s0_tready;
//   reg                   s0_tlast;

//   // Интерфейс Slave 1
//   reg  [DATA_WIDTH-1:0] s1_tdata;
//   reg  [KEEP_WIDTH-1:0] s1_tkeep;
//   reg                   s1_tvalid;
//   reg                   s1_tuser;
//   wire                  s1_tready;
//   reg                   s1_tlast;

//   // Интерфейс Master
//   wire [DATA_WIDTH-1:0] m_tdata;
//   wire [KEEP_WIDTH-1:0] m_tkeep;
//   wire                  m_tvalid;
//   reg                   m_tready;
//   wire                  m_tlast;
//   wire                  m_tuser;

//   // Инстанцирование тестируемого модуля
//   axis_comparator #(
//       .DATA_WIDTH (DATA_WIDTH),
//       .KEEP_WIDTH (KEEP_WIDTH),
//       .KEEP_ENABLE(1)
//   ) dut (
//       .clk(clk),
//       .rst_n(rst_n),
//       .select(select),
//       .s0_tdata(s0_tdata),
//       .s0_tkeep(s0_tkeep),
//       .s0_tvalid(s0_tvalid),
//       .s0_tuser(s0_tuser),
//       .s0_tready(s0_tready),
//       .s0_tlast(s0_tlast),
//       .s1_tdata(s1_tdata),
//       .s1_tkeep(s1_tkeep),
//       .s1_tvalid(s1_tvalid),
//       .s1_tuser(s1_tuser),
//       .s1_tready(s1_tready),
//       .s1_tlast(s1_tlast),
//       .m_tdata(m_tdata),
//       .m_tkeep(m_tkeep),
//       .m_tvalid(m_tvalid),
//       .m_tready(m_tready),
//       .m_tlast(m_tlast),
//       .m_tuser(m_tuser)
//   );

//   // Генерация тактового сигнала
//   initial begin
//     clk = 0;
//     forever #5 clk = ~clk;
//   end

//   // Задача для параллельной отправки слов в оба Slave-интерфейса
//   task send_word(input [DATA_WIDTH-1:0] d0, input l0, input [DATA_WIDTH-1:0] d1, input l1);
//     begin
//       s0_tdata  = d0;
//       s0_tkeep  = 4'hF;
//       s0_tuser  = 0;
//       s0_tlast  = l0;
//       s0_tvalid = 1;
//       s1_tdata  = d1;
//       s1_tkeep  = 4'hF;
//       s1_tuser  = 0;
//       s1_tlast  = l1;
//       s1_tvalid = 1;

//       fork
//         // Поток для Slave 0
//         begin
//           wait (s0_tready && s0_tvalid);
//           @(posedge clk);
//           s0_tvalid = 0;
//         end
//         // Поток для Slave 1
//         begin
//           wait (s1_tready && s1_tvalid);
//           @(posedge clk);
//           s1_tvalid = 0;
//         end
//       join
//     end
//   endtask

//   // Основной блок тестирования
//   initial begin
//     // Инициализация
//     rst_n = 0;
//     select = 0;
//     s0_tvalid = 0;
//     s1_tvalid = 0;
//     m_tready = 1;  // Master всегда готов принимать данные

//     #20 rst_n = 1;
//     @(posedge clk);

//     $display(
//         "--- Тест 1: Успешная передача кадра (Слова совпадают) ---");
//     select = 0;  // Выбираем Master 0 для передачи на выход
//     send_word(32'hAA, 0, 32'hAA, 0);
//     send_word(32'hBB, 0, 32'hBB, 0);
//     send_word(32'hCC, 1, 32'hCC, 1);
//     #30;

//     $display(
//         "--- Тест 2: Ошибка в середине кадра (tuser = 1, tlast = 1) ---");
//     select = 1;  // Выбираем Master 1
//     send_word(32'h11, 0, 32'h11, 0);

//     // Отправляем несовпадающие данные, ожидаем что модуль установит tuser и tlast
//     send_word(32'h22, 0, 32'hFF, 0);

//     // Следующие слова должны игнорироваться модулем (состояние FLUSH), пока не придет tlast
//     send_word(32'h33, 0, 32'h33, 0);
//     send_word(32'h44, 1, 32'h44, 1);
//     #30;

//     $display("--- Тест 3: Разная скорость интерфейсов ---");
//     m_tready = 0;  // Имитация задержки на приемнике
//     #20 m_tready = 1;

//     send_word(32'h55, 0, 32'h55, 0);
//     send_word(32'h66, 1, 32'h66, 1);
//     #50;

//     $display("Симуляция завершена.");
//     $finish;
//   end


//   // ================================================================
//   // Waveform dump
//   // ================================================================

//   initial begin
//     $dumpfile("tb_axis_comparator_GE");
//     $dumpvars(0, tb_axis_comparator_GE);
//   end

// endmodule
