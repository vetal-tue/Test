// Skid-буфер на 1 слово с рукопожатием valid/ready (Verilog-2001).
// Особенности:
// 1. Полная пропускная способность: 1 слово/такт при незаблокированном выходе.
// 2. Нет комбинаторного пути out_ready -> in_ready (удобно для таймингов и цепочек).
// 3. При out_valid && !out_ready выход out_data строго стабилен.

module valid_ready_skid_buf #(
    parameter WIDTH = 32
) (
    input  wire             clk,
    input  wire             rst,        // синхронный активный 1

    input  wire             in_valid,
    output wire             in_ready,
    input  wire [WIDTH-1:0] in_data,

    output reg              out_valid,
    input  wire             out_ready,
    output reg  [WIDTH-1:0] out_data
);

    reg             skid_valid;
    reg [WIDTH-1:0] skid_data;

    // Принимаем новое слово с входа, только когда запасной слот свободен.
    // Важно: не завязываем in_ready комбинаторно на out_ready.
    assign in_ready = ~skid_valid;

    // Удобные флаги транзакций на текущем такте
    wire in_fire  = in_valid  & in_ready;
    wire out_fire = out_valid & out_ready;

    always @(posedge clk) begin
        if (rst) begin
            out_valid  <= 1'b0;
            out_data   <= {WIDTH{1'b0}};
            skid_valid <= 1'b0;
            skid_data  <= {WIDTH{1'b0}};
        end else begin
            // 1. Управление основным выходом (out_valid, out_data)
            if (out_fire) begin
			// Потребитель забрал текущее слово на этом такте.
			// Если в запасном буфере есть отложенное слово — 
			// сразу выдвигаем его на выход.
                if (skid_valid) begin
                    out_valid <= 1'b1;
                    out_data  <= skid_data;
                end else if (in_fire) begin
			// Запасной пуст, но на входе прямо сейчас есть 
			// новое слово — отдаём его.
                    out_valid <= 1'b1;
                    out_data  <= in_data;
                end else begin
			// Больше брать нечего — выход освобождается.
                    out_valid <= 1'b0;
                end
            end else if (!out_valid) begin
			// Выход был пуст, и не было отдачи — если пришло 
			// слово со входа, забираем его.
                if (in_fire) begin
                    out_valid <= 1'b1;
                    out_data  <= in_data;
                end
            end
            // Если out_valid && !out_ready: потребитель держит
            // backpressure — out_valid и out_data НЕ меняем, 
            // слово ждёт на выходе.

            // 2. Управление запасным слотом (skid_valid, skid_data) 
            if (skid_valid) begin
			// Если запасной слот был занят и на этом такте его
			// содержимое переехало в out_data (а out_data ушло 
			// по out_fire), освобождаем skid.
                if (out_fire) begin
                    skid_valid <= 1'b0;
                end
			// Иначе skid_valid остаётся 1, in_ready остаётся 0, 
			// данные сохраняются.
            end else begin
			// Запасной слот был свободен.
			// Сюда кладём входное слово только в случае, если на 
			// этом такте пришло новое слово (in_fire), а выход при
			// этом был занят и НЕ освободился
                // (out_valid && !out_fire).
                if (in_fire && out_valid && !out_fire) begin
                    skid_valid <= 1'b1;
                    skid_data  <= in_data;
                end
            end
        end
    end

endmodule