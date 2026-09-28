module TrueDualPortRAM_BE #(
    parameter DATA_WIDTH = 32,
    parameter ADDR_WIDTH = 10
) (
    input clk,

    input [  ADDR_WIDTH-1:0] addr_a, addr_b,
    input [DATA_WIDTH/8-1:0] wr_byteenable_a, wr_byteenable_b,
    input [  DATA_WIDTH-1:0] wr_data_a, wr_data_b,
    input                    wr_en_a, wr_en_b,
    output [DATA_WIDTH-1:0] rd_data_a, rd_data_b
);

  localparam BYTE_COUNT = DATA_WIDTH / 8;
  localparam DEPTH      = 1 << ADDR_WIDTH;


genvar i;
  generate
    for (i = 0; i < BYTE_COUNT; i = i + 1) begin : byte_lanes
      (* ram_style = "block" *) reg [7:0] mem[0:DEPTH-1];

      reg [7:0] rd_data_reg_A;
      reg [7:0] rd_data_reg_B;

      // Оба порта обслуживаются в одном синхронном процессе
      always @(posedge clk) begin
        // Port A
        if (wr_en_a && wr_byteenable_a[i]) begin
          mem[addr_a] <= wr_data_a[i*8+:8];
        end
        rd_data_reg_A <= mem[addr_a];

        // Port B
        if (wr_en_b && wr_byteenable_b[i]) begin
          mem[addr_b] <= wr_data_b[i*8+:8];
        end
        rd_data_reg_B <= mem[addr_b];
      end

      assign rd_data_a[i*8+:8] = rd_data_reg_A;
      assign rd_data_b[i*8+:8] = rd_data_reg_B;

    end
  endgenerate

endmodule
