module pipelined_counter_D1 #(
    parameter integer WIDTH = 64,  // разрядность счётчика
    parameter integer SEG   = 16   // ширина одной секции
) (
    input  wire             clk,
    input  wire             rst,
    output wire [WIDTH-1:0] count_aligned
);

  // Количество секций
  localparam integer N = (WIDTH + SEG - 1) / SEG;

  // Разрядность последней секции (может быть меньше SEG)
  localparam integer LAST_WIDTH = WIDTH - (N - 1) * SEG;

  // Счётчики секций
  reg [SEG-1:0] cnt[0:N-1];

  // Сигналы переноса
  wire [N-1:0] inc;  // разрешение инкремента для секции
  wire [N-1:0] co;  // комбинационный перенос из секции
  reg [N-1:0] co_reg;  // зарегистрированный перенос

  genvar i;

  // Секция 0 всегда инкрементируется.
  // Остальные секции инкрементируются по зарегистрированному переносу предыдущей.
  assign inc[0] = 1'b1;

  generate
    for (i = 0; i < N; i = i + 1) begin : gen_ctrl
      if (i > 0) begin
        assign inc[i] = co_reg[i-1];
      end

      // Не вычисляем перенос для самой старшей секции, чтобы не плодить dead logic
      if (i < N - 1) begin
        assign co[i] = (cnt[i] == {SEG{1'b1}}) && inc[i];
      end else begin
        assign co[i] = 1'b0;
      end
    end
  endgenerate

  // Счётчики и регистры переноса
  integer k;
  always @(posedge clk) begin
    if (rst) begin
      for (k = 0; k < N; k = k + 1) begin
        cnt[k]    <= {SEG{1'b0}};
        co_reg[k] <= 1'b0;
      end
    end else begin
      for (k = 0; k < N; k = k + 1) begin
        if (inc[k]) cnt[k] <= cnt[k] + 1'b1;
        // иначе значение сохраняется
        co_reg[k] <= co[k];
      end
    end
  end

  // Конвейер выравнивания через generate (без избыточных регистров)
  generate
    for (i = 0; i < N; i = i + 1) begin : gen_pipe
      localparam integer DELAY = N - 1 - i;
      localparam integer OUT_WIDTH = (i == N - 1) ? LAST_WIDTH : SEG;

      if (DELAY == 0) begin
        // Старшая секция идет напрямую
        assign count_aligned[i*SEG+:OUT_WIDTH] = cnt[i][OUT_WIDTH-1:0];
      end else begin
        // Точечное выделение сдвигового регистра нужной длины
        reg [SEG-1:0] delay_pipe[0:DELAY-1];
        integer j;

        always @(posedge clk) begin
          if (rst) begin
            for (j = 0; j < DELAY; j = j + 1) delay_pipe[j] <= {SEG{1'b0}};
          end else begin
            delay_pipe[0] <= cnt[i];
            for (j = 1; j < DELAY; j = j + 1) delay_pipe[j] <= delay_pipe[j-1];
          end
        end

        assign count_aligned[i*SEG+:OUT_WIDTH] = delay_pipe[DELAY-1];
      end
    end
  endgenerate

endmodule
