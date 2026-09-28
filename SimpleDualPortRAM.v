module SimpleDualPortRAM #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
) (
    input clk,

    // Write port
    input [  ADDR_WIDTH-1:0] wr_addr,
    input [DATA_WIDTH/8-1:0] wr_byteenable,
    input [  DATA_WIDTH-1:0] wr_data,
    input                    wr_en,

    // Read port
    input  [ADDR_WIDTH-1:0] rd_addr,
    // output reg [DATA_WIDTH-1:0] rd_data
    output [DATA_WIDTH-1:0] rd_data // Изменено с reg на wire (по умолчанию)
);

  localparam BYTE_COUNT = DATA_WIDTH / 8;
  localparam DEPTH      = 1 << ADDR_WIDTH;

  //   (* ram_style = "block" *) reg [DATA_WIDTH-1:0] mem[0:DEPTH-1];

  // integer i;

  // always @(posedge clk) begin
  //     // Write
  //     if (wr_en) begin
  //         for (i = 0; i < BYTE_COUNT; i = i + 1) begin
  //             if (wr_byteenable[i]) begin
  //                 mem[wr_addr][i*8 +: 8] <= wr_data[i*8 +: 8];
  //             end
  //         end
  //     end

  //     // Synchronous read
  //     rd_data <= mem[rd_addr];
  // end

  localparam BYTE_WIDTH = 8;


  //   localparam BYTES_PER_WORD = DATA_WIDTH / BYTE_WIDTH;
  //   integer i;

  //   // Процесс записи с byte enable
  //   always @(posedge clk) begin
  //     if (wr_en) begin
  //       for (i = 0; i < BYTES_PER_WORD; i = i + 1) begin
  //         if (wr_byteenable[i])
  //           mem[wr_addr][i*BYTE_WIDTH+:BYTE_WIDTH] <= wr_data[i*BYTE_WIDTH+:BYTE_WIDTH];
  //       end
  //     end
  //   end

  //   always @(posedge clk) rd_data <= mem[rd_addr];



  genvar i;
  generate
    for (i = 0; i < BYTE_COUNT; i = i + 1) begin : byte_lanes
      // Создаем отдельный 8-битный массив памяти для каждого байта
      (* ram_style = "block" *) reg [7:0] mem[0:DEPTH-1];
      reg [7:0] rd_data_reg;

      always @(posedge clk) begin
        // Синтезатор видит это как обычный сигнал write enable для 8-битной RAM
        if (wr_en && wr_byteenable[i]) begin
          mem[wr_addr] <= wr_data[i*8+:8];
        end

        // Синхронное чтение
        rd_data_reg <= mem[rd_addr];
      end

      // Собираем прочитанные байты в общую выходную шину
      assign rd_data[i*8+:8] = rd_data_reg;
    end
  endgenerate

endmodule
