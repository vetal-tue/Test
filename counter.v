module counter #(
    parameter WIDTH = 4
) (
    input  wire             clk,
    input  wire             rst,
    input  wire             en,
    output reg  [WIDTH-1:0] count
);

    always @(posedge clk) begin
        if (rst)
            count <= 0;
        else if (en)
            count <= count + 1'b1;
    end

`ifdef FORMAL
    // 1. Отслеживаем наличие предыдущего такта
    reg f_past_valid = 0;
    always @(posedge clk)
        f_past_valid <= 1'b1;

    // 2. На нулевом такте принудительно подаем сброс
    always @(*) begin
        if (!f_past_valid)
            assume(rst == 1'b1);
    end

    // 3. Основные проверки (ASSERT)
    always @(posedge clk) begin
        if (f_past_valid) begin
            if ($past(rst)) begin
                // После такта со сбросом счетчик обязан быть в нуле
                assert(count == 0);
            end else if ($past(en)) begin
                // Если не было сброса и был en, значение увеличилось на 1
                assert(count == $past(count) + 1'b1);
            end else begin
                // Если не было ни сброса, ни en, значение сохранилось
                assert(count == $past(count));
            end
        end
    end

    // 4. Проверка достижимости (COVER)
    // Убеждаемся, что счетчик способен досчитать до максимального значения и переполниться
    always @(posedge clk) begin
        if (f_past_valid && !rst) begin
            cover(count == {WIDTH{1'b1}});
            cover($past(count) == {WIDTH{1'b1}} && count == 0);
        end
    end
`endif

endmodule