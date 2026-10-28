module dc_RAM #(
    parameter DATA_WIDTH = 32,        // Общая ширина данных
    parameter BYTE_WIDTH = 8,         // Ширина одного байта
    parameter ADDR_WIDTH = 10,        // Ширина адресной шины
    parameter REGISTERED_OUTPUT = 1,   // 1 - регистрировать выход, 0 - прямой доступ
    parameter RAM_STYLE_ = "M20K"
) (
    // Порт записи
    input wire wr_clk,
    input wire wr_en,
    input wire [ADDR_WIDTH-1:0] wr_addr,
    input wire [DATA_WIDTH-1:0] wr_data,
    input wire [(DATA_WIDTH/BYTE_WIDTH)-1:0] wr_byte_en,
    
    // Порт чтения
    input wire rd_clk,
    input wire [ADDR_WIDTH-1:0] rd_addr,
    output reg [DATA_WIDTH-1:0] rd_data
);

localparam BYTES_PER_WORD = DATA_WIDTH / BYTE_WIDTH;
(* ramstyle  = RAM_STYLE_ *) reg [DATA_WIDTH-1:0] mem [0:(2**ADDR_WIDTH)-1];
integer i;

// Процесс записи с byte enable
always @(posedge wr_clk) begin
    if (wr_en) begin
        for (i = 0; i < BYTES_PER_WORD; i = i + 1) begin
            if (wr_byte_en[i])
                mem[wr_addr][i*BYTE_WIDTH +: BYTE_WIDTH] <= wr_data[i*BYTE_WIDTH +: BYTE_WIDTH];
        end
    end
end

// Условная генерация логики чтения
generate
    if (REGISTERED_OUTPUT) begin
        // Регистрированный выход (по умолчанию)
        always @(posedge rd_clk)
            rd_data <= mem[rd_addr];

    end else begin
        // Прямой асинхронный доступ
        always @(*)
            rd_data = mem[rd_addr];
    end
endgenerate

endmodule