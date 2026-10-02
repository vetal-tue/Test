module pack_x_to_2x #(
    parameter integer DATA_W = 8
) (
    input wire clk,
    input wire rst,

    input wire [DATA_W-1:0] data_in,
    input wire              valid_in,

    output reg [2*DATA_W-1:0] data_out,
    output reg                valid_out
);

  reg [DATA_W-1:0] data_lo;
  reg              half_full;

  always @(posedge clk) begin
    if (rst) begin
      half_full <= 1'b0;
      valid_out <= 1'b0;
    end else begin
      valid_out <= 1'b0;

      if (valid_in) begin

        if (!half_full) begin
          data_lo   <= data_in;
          half_full <= 1'b1;
        end else begin
          data_out  <= {data_in, data_lo};
          valid_out <= 1'b1;
          half_full <= 1'b0;
        end

      end
    end
  end

endmodule
