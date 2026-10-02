`timescale 1 ps / 1 ps

module D_FIFO_Buff_in_x_out_4x #(
    parameter integer FIFO_WIDTH  = 16,
    parameter integer FIFO_ADDR_W = 8
) (
    input  wire                    wrclk,
    input  wire                    rdclk,
    input  wire                    wr_rst,
    input  wire                    rd_rst,
    input  wire                    D_FIFO_wr_en,
    input  wire [  FIFO_WIDTH-1:0] D_FIFO_wrdata,
    output wire [   FIFO_ADDR_W:0] D_FIFO_wrcnt,
    input  wire                    D_FIFO_rd_en,
    output wire [4*FIFO_WIDTH-1:0] D_FIFO_rd_data,
    output wire                    D_FIFO_wrfull,
    output wire                    D_FIFO_wrafull,
    output wire                    D_FIFO_rd_empty,
    output wire [ FIFO_ADDR_W-2:0] D_FIFO_rd_cnt_out
);

  localparam integer OUT_WIDTH = 4 * FIFO_WIDTH;

  // ───────── аккумулятор на стороне ЗАПИСИ: 4 × FIFO_WIDTH → OUT_WIDTH ─────────
  // reg  [OUT_WIDTH-1:0] wr_acc;
  reg  [3*FIFO_WIDTH-1:0] wr_acc;  // только 3 отложенных слога
  reg  [             1:0] wr_fill;  // 0..3 накопленных полуслов

  wire                    fifo_wr_full;
  wire                    fifo_wr_almost_full;
  wire [ FIFO_ADDR_W-2:0] fifo_rd_cnt;
  wire [ FIFO_ADDR_W-2:0] fifo_wr_cnt;

  // Слово собирается из D_FIFO_wrdata (4-й слог) и уже накопленных 3 слогов
  wire [   OUT_WIDTH-1:0] fifo_wr_data = {D_FIFO_wrdata, wr_acc};
  wire                    push_word = (wr_fill == 2'd3) && D_FIFO_wr_en && !fifo_wr_full;

  assign D_FIFO_wrcnt = {fifo_wr_cnt, 2'b00} + wr_fill;

  always @(posedge wrclk or posedge wr_rst) begin
    if (wr_rst) begin
      // wr_acc  <= {OUT_WIDTH{1'b0}};
      wr_acc  <= {(3 * FIFO_WIDTH) {1'b0}};
      wr_fill <= 2'd0;
    end else if (D_FIFO_wr_en) begin
      if (wr_fill == 2'd3) begin
        if (!fifo_wr_full) wr_fill <= 2'd0;  // слово ушло в FIFO
      end else begin
        wr_acc[wr_fill*FIFO_WIDTH+:FIFO_WIDTH] <= D_FIFO_wrdata;
        wr_fill                                <= wr_fill + 1'b1;
      end
    end
  end

  // ───────── внутренняя FIFO теперь OUT_WIDTH-битная ─────────
  async_fifo_fwft_xilinx_style #(
      .DATA_W(OUT_WIDTH),
      .ADDR_W(FIFO_ADDR_W - 2)
  ) DATA_FIFO (
      .wr_clk         (wrclk),
      .wr_rst         (wr_rst),
      .wr_en          (push_word),
      .wr_data        (fifo_wr_data),
      .wr_full        (fifo_wr_full),
      .rd_clk         (rdclk),
      .rd_rst         (rd_rst),
      .rd_en          (D_FIFO_rd_en),
      .rd_data        (D_FIFO_rd_data),
      .rd_empty       (D_FIFO_rd_empty),
      .wr_cnt         (fifo_wr_cnt),
      .rd_cnt         (fifo_rd_cnt),
      .wr_almost_full (fifo_wr_almost_full),
      .rd_almost_empty()
  );

  // ───────── флаги/счётчики ─────────
  // «Жёсткий» full: FIFO полна И аккумулятор уже набрал 3 слога
  assign D_FIFO_wrfull    = fifo_wr_full && (wr_fill == 2'd3);
  // assign D_FIFO_wrafull   = fifo_wr_almost_full;
  // assign D_FIFO_wrafull   = fifo_wr_almost_full && (wr_fill >= 2'd2);
  assign D_FIFO_wrafull = (D_FIFO_wrcnt >= 1 << FIFO_ADDR_W - 1);
  assign D_FIFO_rd_cnt_out = fifo_rd_cnt;

endmodule
