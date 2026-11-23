module rr_arbiter #(
    parameter N = 8
) (
    input  wire         clk,
    input  wire         rst,
    input  wire [N-1:0] req,
    output reg  [N-1:0] gnt
);

  // Указатель приоритета (маска каналов, которые еще не обслуживались в текущем круге)
  reg  [N-1:0] mask;

  wire [N-1:0] masked_req = req & mask;

  // Выделение младшего единичного бита (Fixed Priority) для маскированных и обычных запросов
  wire [N-1:0] masked_gnt = masked_req & (~masked_req + 1'b1);
  wire [N-1:0] raw_gnt = req & (~req + 1'b1);

  // Если среди приоритетных (маскированных) есть запросы — берем их, иначе идем по новому кругу
  wire [N-1:0] next_gnt = (|masked_req) ? masked_gnt : raw_gnt;

  always @(posedge clk) begin
    if (rst) begin
      gnt <= {N{1'b0}};
      mask <= {N{1'b1}}; // На старте все каналы имеют равный приоритет
    end else begin
      gnt <= next_gnt;
      if (|next_gnt) begin
        // Сбрасываем в маске выданный бит и все младшие биты,
        // передавая приоритет старшим каналам на следующем такте
        mask <= ~((next_gnt - 1'b1) | next_gnt);
      end
    end
  end

`ifdef FORMAL
  reg f_past_valid = 0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(*) begin
    if (!f_past_valid) assume (rst);
  end

  // =========================================================================
  // 1. ВЗАИМНОЕ ИСКЛЮЧЕНИЕ (Mutex / One-Hot-0)
  // =========================================================================
  always @(posedge clk) begin
    if (f_past_valid) begin
      // В векторе gnt всегда установлен максимум ОДИН бит (после первого такта сброса)
      assert ((gnt & (gnt - 1'b1)) == {N{1'b0}});
    end
  end

  // =========================================================================
  // 2. КОРРЕКТНОСТЬ ВЫДАЧИ И ОТСУТСТВИЕ ПРОСТОЕВ (Work-Conserving)
  // =========================================================================
  always @(posedge clk) begin
    if (f_past_valid) begin
      if ($past(rst)) begin
        // После сброса грантов быть не должно
        assert (gnt == {N{1'b0}});
      end else begin
        // Нельзя выдать грант каналу, который не выставлял запрос
        assert ((gnt & ~$past(req)) == {N{1'b0}});

        // Если был хотя бы один запрос, обязан быть выдан ровно один грант
        if (|$past(req)) begin
          assert (|gnt);
        end else begin
          assert (gnt == {N{1'b0}});
        end
      end
    end
  end

// =========================================================================
// 3. ЧЕСТНОСТЬ / ОТСУТСТВИЕ ГОЛОДАНИЯ (Fairness)
// =========================================================================

// Ширина счетчика ожидания.
// Необходимо представлять значения от 0 до N включительно.
localparam WAIT_W = (N <= 1) ? 1 : $clog2(N + 1);

// Выбираем произвольный канал для проверки.
localparam IDX_W = (N <= 1) ? 1 : $clog2(N);

(* anyconst *) wire [IDX_W-1:0] f_watch_ch;

always @(posedge clk) begin
    assume(f_watch_ch < N);
end

reg [WAIT_W-1:0] f_wait_cnt = 0;

always @(posedge clk) begin

    if (!f_past_valid || rst) begin
        f_wait_cnt <= 0;
    end
    else if ($past(rst)) begin
        // После сброса начинаем отсчет заново.
        f_wait_cnt <= 0;
    end
    else begin

        // Сравниваем запрос предыдущего такта
        // с текущим зарегистрированным грантом.
        if ($past(req[f_watch_ch]) &&
            !gnt[f_watch_ch]) begin

            if (f_wait_cnt < N)
                f_wait_cnt <= f_wait_cnt + 1'b1;

        end
        else begin
            // Запрос отсутствует или канал получил грант.
            f_wait_cnt <= 0;
        end

    end
end

always @(posedge clk) begin

    if (f_past_valid && !rst && !$past(rst)) begin

        // Не должно быть N последовательных пропущенных
        // возможностей получить грант.
        assert(f_wait_cnt < N);

    end

end
  // =========================================================================
  // 4. ПРОВЕРКА ДОСТИЖИМОСТИ (COVER)
  // =========================================================================
  always @(posedge clk) begin
    if (f_past_valid && !rst) begin
  //     // Убеждаемся, что при одновременном запросе всех 8 каналов каждый может получить грант
  //     cover ((req == 8'hFF) && gnt[0]);
  //     cover ((req == 8'hFF) && gnt[7]);
      // Убеждаемся, что при снятии всех запросов выход корректно обнуляется
        cover ((req ==  {N{1'b0}}) && (gnt ==  {N{1'b0}}) && ($past(gnt) !=  {N{1'b0}}));
    end
  end

genvar i;

generate
    for (i = 0; i < N; i = i + 1) begin : GEN_COVER

        always @(posedge clk) begin
            if (f_past_valid && !rst && !$past(rst)) begin

                // Все каналы запрашивали обслуживание,
                // выбранный канал получил грант.
                cover(
                    ($past(req) == {N{1'b1}}) &&
                    gnt[i]
                );

            end
        end

    end
endgenerate

reg [N-1:0] f_seen_gnt;
always @(posedge clk) begin
    if (rst) begin
        f_seen_gnt <= 0;
    end
    else if (f_past_valid && !$past(rst)) begin
        if ($past(req) == {N{1'b1}})
            f_seen_gnt <= f_seen_gnt | gnt;
        else
            f_seen_gnt <= 0;
        cover(&f_seen_gnt);
    end
end

`endif

endmodule
