module fifo_64to32_fwft5 #(
    parameter DEPTH = 16
) (
    input wire clk,
    input wire rst,

    //========================================================
    // 64-bit write side
    //========================================================

    input  wire [63:0] wr_data,
    input  wire        wr_en,
    output wire        full,

    //========================================================
    // 32-bit FWFT read side
    //========================================================

    output wire [31:0] rd_data,
    input  wire        rd_en,
    output wire        empty
);

  //========================================================
  // Underlying 64-bit FWFT FIFO
  //========================================================

  wire [63:0] fifo_rd_data;
  wire        fifo_empty;
  wire        fifo_full;

  reg         fifo_rd_en;

  fwft_fifo #(
      .DATA_WIDTH(64),
      .DEPTH     (DEPTH)
  ) fifo_inst (
      .clk(clk),
      .rst(rst),

      .wr_data(wr_data),
      .wr_en  (wr_en),
      .full   (fifo_full),

      .rd_data(fifo_rd_data),
      .rd_en  (fifo_rd_en),
      .empty  (fifo_empty)
  );

  assign full = fifo_full;

  //========================================================
  // 32-bit FWFT output stage
  //========================================================
  //
  // out_valid = на выходе есть валидное 32-битное слово
  //
  // out_sel:
  //   0 -> выводим low32
  //   1 -> выводим high32
  //
  // current64 хранит текущее 64-битное слово
  //
  //========================================================

  reg [63:0] current64;
  reg        out_sel;
  reg        out_valid;

  assign rd_data = (!out_sel) ? current64[31:0] : current64[63:32];

  assign empty   = !out_valid;

  //========================================================
  // Control
  //========================================================

  always @(posedge clk or posedge rst) begin
    if (rst) begin

      current64  <= 64'd0;
      out_sel    <= 1'b0;
      out_valid  <= 1'b0;
      fifo_rd_en <= 1'b0;

    end else begin

      fifo_rd_en <= 1'b0;

      //================================================
      // PREFETCH
      //
      // Если выход пуст,
      // а в нижнем FIFO есть слово —
      // автоматически загружаем его.
      //
      // Это и обеспечивает FWFT.
      //================================================

      if (!out_valid && !fifo_empty) begin

        current64 <= fifo_rd_data;
        out_sel <= 1'b0;
        out_valid <= 1'b1;

        fifo_rd_en <= 1'b1;
      end  //================================================
           // READ
           //================================================

      else if (rd_en && out_valid) begin

        //--------------------------------------------
        // LOW32 consumed
        //--------------------------------------------

        if (!out_sel) begin

          // переключаемся на HIGH32
          out_sel <= 1'b1;
        end  //--------------------------------------------
             // HIGH32 consumed
             //--------------------------------------------

        else begin

          //----------------------------------------
          // Есть следующее 64-битное слово —
          // сразу preload следующего LOW32
          //----------------------------------------

          if (!fifo_empty) begin

            current64 <= fifo_rd_data;

            out_sel <= 1'b0;
            out_valid <= 1'b1;

            fifo_rd_en <= 1'b1;
          end  //----------------------------------------
               // FIFO пустеет
               //----------------------------------------

          else begin

            out_valid <= 1'b0;
            out_sel   <= 1'b0;
          end
        end
      end
    end
  end

endmodule
