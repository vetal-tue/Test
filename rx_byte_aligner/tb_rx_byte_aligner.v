`timescale 1ns / 1ps
module tb_rx_byte_aligner;
  reg         clk = 0;
  reg         rst_n = 0;
  reg         align_en = 1;
  reg  [31:0] rx_data;
  reg  [ 3:0] rx_ctrl;
  wire [31:0] rx_data_o;
  wire [ 3:0] rx_ctrl_o;
  wire        rx_aligned;

  initial begin
    $dumpfile("tb_rx_byte_aligner.vcd");
    $dumpvars(0, tb_rx_byte_aligner);
  end

  rx_byte_aligner_fpga dut (
      .clk(clk),
      .rst_n(rst_n),
      .align_en(align_en),
      .rx_data(rx_data),
      .rx_ctrl(rx_ctrl),
      .rx_data_o(rx_data_o),
      .rx_ctrl_o(rx_ctrl_o),
      .rx_aligned(rx_aligned)
  );

  always #5 clk = ~clk;

  // ---- вектора: сначала пример из задания (сдвиг=1 байт, случай rx_ctrl=0010) ----
  // затем идут те же ALIGN примитивы ещё раз (имитация непрерывной посылки ALIGN),
  // затем "полезные данные" D0,D1,D2, поток которых физически сдвинут на тот же 1 байт.
  reg [31:0] data_v[0:9];
  reg [3:0] ctrl_v[0:9];

  integer i;
  initial begin
    // k=0: сырые байты потока S1..S4 = 4A,4A,7B,BC (см. вывод в чате)
    data_v[0] = 32'hBC7B4A4A;
    ctrl_v[0] = 4'b1000;
    // k=1: сырые байты потока S5..S8 = 4A,4A,7B,44 (комы здесь уже нет)
    data_v[1] = 32'h447B4A4A;
    ctrl_v[1] = 4'b0000;
    // k=2: данные D0 сдвинутые: S9..S12 = 33,22,11,88
    data_v[2] = 32'h88112233;
    ctrl_v[2] = 4'b0000;
    // k=3: S13..S16 = 77,66,55,CC
    data_v[3] = 32'hCC556677;
    ctrl_v[3] = 4'b0000;
    // k=4: S17..S20 = BB,AA,99, xx(добьём нулём, не важно)
    data_v[4] = 32'h0099AABB;
    ctrl_v[4] = 4'b0000;

    // -- Дополнительно: прямая проверка ВСЕХ 3-х примеров из задания "как есть" --
    // сначала programmatically сброс алгоритма не делаем, просто проверим
    // что каждый из 3 вариантов отдельно (при уже известном сдвиге) даёт корректный
    // результат - это будет 2-й прогон теста ниже (test2).

    rst_n = 0;
    rx_data = 0;
    rx_ctrl = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;

    $display("time  rx_data   rx_ctrl | rx_data_o rx_ctrl_o aligned");
    for (i = 0; i < 5; i = i + 1) begin
      @(negedge clk);
      rx_data = data_v[i];
      rx_ctrl = ctrl_v[i];
      @(posedge clk);
      #1;
      $display("%0t  %h  %b   |  %h   %b       %b", $time, rx_data, rx_ctrl, rx_data_o, rx_ctrl_o,
               rx_aligned);
    end

    $display(
        "--- ожидаем: на k=2 (D0) выход = 11223344/0000, на k=3 (D1) = 55667788/0000, на k=4 (D2 частично) = 99AABBCC-подобное ---");

    $display(
        "\n=== TEST 2: три примера из задания по отдельности (с чистым сбросом) ===");
    test_case(32'h7B4A4ABC, 4'b0001, "уже выровнено");
    test_case(32'h4A4ABC7B, 4'b0010, "сдвиг вариант 1");
    test_case(32'h4ABC7B4A, 4'b0100, "сдвиг вариант 2");

    $finish;
  end

  task test_case(input [31:0] d, input [3:0] c, input [200:0] name);
    begin
      rst_n   = 0;
      rx_data = 0;
      rx_ctrl = 0;
      repeat (3) @(posedge clk);
      rst_n = 1;
      // подаём один и тот же (периодический) misaligned паттерн несколько тактов,
      // т.к. модулю нужно 1 предыдущее слово, чтобы восстановить окно целиком
      @(negedge clk);
      rx_data = d;
      rx_ctrl = c;
      @(posedge clk);
      #1;
      @(negedge clk);
      rx_data = d;
      rx_ctrl = c;
      @(posedge clk);
      #1;
      $display("%s: in=%h/%b -> out=%h/%b aligned=%b (ожидаем 7B4A4ABC/0001)", name, d, c,
               rx_data_o, rx_ctrl_o, rx_aligned);
    end
  endtask

endmodule
