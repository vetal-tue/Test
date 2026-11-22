module lock_rr_arbiter #(
    parameter N = 8
) (
    input  wire         clk,
    input  wire         rst,
    input  wire [N-1:0] req,
    output reg  [N-1:0] gnt
);

    reg [N-1:0] mask;

    // Признак того, что текущий владелец шины всё еще удерживает свой запрос
    wire hold_gnt = |(gnt & req);

    wire [N-1:0] masked_req = req & mask;
    wire [N-1:0] masked_gnt = masked_req & (~masked_req + 1'b1);
    wire [N-1:0] raw_gnt    = req & (~req + 1'b1);

    // Новый грант выбирается только если текущий грант не удерживается
    wire [N-1:0] new_gnt = (|masked_req) ? masked_gnt : raw_gnt;

    always @(posedge clk) begin
        if (rst) begin
            gnt  <= {N{1'b0}};
            mask <= {N{1'b1}};
        end else if (hold_gnt) begin
            // Удерживаем текущий грант и не меняем маску приоритетов
            gnt <= gnt;
        end else begin
            // Владелец снял запрос (или гранта не было) -> выдаем новый грант
            gnt <= new_gnt;
            if (|new_gnt) begin
                mask <= ~((new_gnt - 1'b1) | new_gnt);
            end
        end
    end

`ifdef FORMAL
    reg f_past_valid = 0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    always @(*) begin
        if (!f_past_valid)
            assume(rst);
    end

    // =========================================================================
    // 1. ВЗАИМНОЕ ИСКЛЮЧЕНИЕ (One-Hot-0)
    // =========================================================================
    always @(posedge clk) begin
        if (f_past_valid) begin
            assert((gnt & (gnt - 1'b1)) == {N{1'b0}});
        end
    end

    // =========================================================================
    // 2. ПРАВИЛО УДЕРЖАНИЯ ГРАНТА (Locking) И КОРРЕКТНОСТЬ ВЫДАЧИ
    // =========================================================================
    always @(posedge clk) begin
        if (f_past_valid) begin
            if ($past(rst)) begin
                assert(gnt == {N{1'b0}});
            end else begin
                // А. Правило удержания: если грант был выдан и его req не снят -> gnt не меняется
                if (|($past(gnt) & $past(req))) begin
                    assert(gnt == $past(gnt));
                end else begin
                    // Б. Если удержания нет -> грант выдается только по активному запросу
                    assert((gnt & ~$past(req)) == {N{1'b0}});

                    // В. Если есть хотя бы один запрос, грант обязан быть выдан
                    if (|$past(req))
                        assert(|gnt);
                    else
                        assert(gnt == {N{1'b0}});
                end
            end
        end
    end

    // =========================================================================
    // 3. ЧЕСТНОСТЬ / ОТСУТСТВИЕ ГОЛОДАНИЯ (Bounded Fairness)
    // =========================================================================
    // Ограничение окружения (ASSUME): каждый канал, получив грант, обязуется
    // освободить шину (снять req) не позже чем через MAX_HOLD тактов.
    localparam MAX_HOLD = 3;
    reg [2:0] f_hold_cnt = 0;

    always @(posedge clk) begin
        if (rst) begin
            f_hold_cnt <= 0;
        end else if (|(gnt & req)) begin
            f_hold_cnt <= f_hold_cnt + 1'b1;
        end else begin
            f_hold_cnt <= 0;
        end
    end

    always @(*) begin
        // Запрещаем активному владельцу держать req дольше MAX_HOLD тактов
        assume(f_hold_cnt < MAX_HOLD);
    end

    // Следим за любым произвольным каналом f_watch_ch
    (* anyconst *) wire [$clog2(N)-1:0] f_watch_ch;
    always @(*) begin
        assume(f_watch_ch < N);
    end

    reg [5:0] f_wait_cnt = 0;

    always @(posedge clk) begin
        if (rst) begin
            f_wait_cnt <= 0;
        end else if (req[f_watch_ch] && !gnt[f_watch_ch]) begin
            if (f_wait_cnt < 6'd63)
                f_wait_cnt <= f_wait_cnt + 1'b1;
        end else begin
            f_wait_cnt <= 0;
        end
    end

    // Максимальное ожидание любого канала: максимум (N - 1) чужих транзакций
    // по (MAX_HOLD + 1) тактов + 1 такт регистрации
    always @(posedge clk) begin
        if (!rst) begin
            assert(f_wait_cnt <= (N * (MAX_HOLD + 1)));
        end
    end

    // =========================================================================
    // 4. ПРОВЕРКА ДОСТИЖИМОСТИ (COVER)
    // =========================================================================
    always @(posedge clk) begin
        if (f_past_valid && !rst) begin
            // 1. Убеждаемся, что грант реально удерживается минимум 2 такта подряд
            cover((gnt != 0) && (gnt == $past(gnt)) && ($past(gnt) == $past(gnt, 2)));

            // 2. Убеждаемся, что после снятия первого req грант переходит к следующему каналу
            cover(($past(gnt) == 8'b0000_0001) && (gnt == 8'b0000_0010));
        end
    end
`endif

endmodule
