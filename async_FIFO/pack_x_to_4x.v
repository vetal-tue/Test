module pack_x_to_4x #(
    parameter integer DATA_W = 8
) (
    input wire clk,
    input wire rst,

    input wire [DATA_W-1:0] data_in,
    input wire              valid_in,

    output reg [4*DATA_W-1:0] data_out,
    output reg                valid_out
);

  localparam OUT_W = 4 * DATA_W;

  reg [OUT_W-1:0] acc;
  reg [      1:0] cnt;

  always @(posedge clk) begin
    if (rst) begin
      cnt       <= 2'd0;
      acc       <= {OUT_W{1'b0}};
    //   data_out  <= {OUT_W{1'b0}};
      valid_out <= 1'b0;
    end else begin
      valid_out <= 1'b0;

      if (valid_in) begin
        case (cnt)
          2'd0: begin
            acc[DATA_W-1:0] <= data_in;
            cnt <= 2'd1;
          end

          2'd1: begin
            acc[2*DATA_W-1:DATA_W] <= data_in;
            cnt <= 2'd2;
          end

          2'd2: begin
            acc[3*DATA_W-1:2*DATA_W] <= data_in;
            cnt <= 2'd3;
          end

          2'd3: begin
            data_out  <= {data_in, acc[3*DATA_W-1:0]};
            valid_out <= 1'b1;
            cnt       <= 2'd0;
          end

          default: cnt <= 2'd0;
        endcase
      end
    end
  end

endmodule
