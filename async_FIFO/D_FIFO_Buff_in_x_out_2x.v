`timescale 1 ps / 1 ps

module D_FIFO_Buff_in_x_out_2x #(
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
    output wire [2*FIFO_WIDTH-1:0] D_FIFO_rd_data,
    output wire                    D_FIFO_wrfull,
    output wire                    D_FIFO_wrafull,
    output wire                    D_FIFO_rd_empty,
    output wire [ FIFO_ADDR_W-1:0] D_FIFO_rd_cnt_out
);

  localparam integer OUT_WIDTH = 2 * FIFO_WIDTH;

  // ───────── аккумулятор на стороне ЗАПИСИ: 2 × FIFO_WIDTH → OUT_WIDTH ─────────
  reg  [ FIFO_WIDTH-1:0] wr_acc;  // один «отложенный» слог
  reg                    wr_half;  // 1'b0 — пусто, 1'b1 — ждёт пары

  wire                   fifo_wr_full;
  wire                   fifo_wr_almost_full;
  wire [FIFO_ADDR_W-1:0] fifo_rd_cnt;
  wire [FIFO_ADDR_W-1:0] fifo_wr_cnt;

  // Слово собирается из D_FIFO_wrdata (старшая половина) и wr_acc (младшая)
  wire [  OUT_WIDTH-1:0] fifo_wr_data = {D_FIFO_wrdata, wr_acc};
  wire                   push_word = wr_half && D_FIFO_wr_en && !fifo_wr_full;
  assign D_FIFO_wrcnt = {fifo_wr_cnt, 1'b0} + wr_half;

  always @(posedge wrclk or posedge wr_rst) begin
    if (wr_rst) begin
      wr_acc  <= {FIFO_WIDTH{1'b0}};
      wr_half <= 1'b0;
    end else if (D_FIFO_wr_en) begin
      if (wr_half) begin
        if (!fifo_wr_full) wr_half <= 1'b0;  // пара ушла в FIFO
      end else begin
        wr_acc  <= D_FIFO_wrdata;
        wr_half <= 1'b1;
      end
    end
  end

  // ───────── внутренняя FIFO теперь OUT_WIDTH-битная ─────────
  async_fifo_fwft_xilinx_style #(
      .DATA_W(OUT_WIDTH),
      .ADDR_W(FIFO_ADDR_W - 1)
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
      .wr_cnt         (fifo_wr_cnt  /*D_FIFO_wrcnt*/),
      .rd_cnt         (fifo_rd_cnt),
      .wr_almost_full (fifo_wr_almost_full),
      .rd_almost_empty()
  );

  // ───────── флаги/счётчики ─────────
  // full: FIFO полна И в аккумуляторе уже лежит непарный слог
  assign D_FIFO_wrfull     = fifo_wr_full && wr_half;
  assign D_FIFO_wrafull    = fifo_wr_almost_full;
  // assign D_FIFO_rd_cnt_out = fifo_rd_cnt[FIFO_ADDR_W-1:0];
  assign D_FIFO_rd_cnt_out = fifo_rd_cnt;

endmodule
