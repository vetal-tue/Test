module sync_fifo_fwft_bram_D #(
    parameter DATA_W = 16,
    parameter ADDR_W = 12,
    parameter ALMOST_FULL_THRESH  = (1 << ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
) (
    input                    clk,
    input                    rst,
    input                    wr_en,
    input       [DATA_W-1:0] wr_data,
    output reg               wr_full,
    output reg               wr_almost_full,
    output reg  [  ADDR_W:0] usedw,
    input                    rd_en,
    output      [DATA_W-1:0] rd_data,
    output reg               rd_empty,
    output reg               rd_almost_empty
);

  localparam DEPTH    = 1 << ADDR_W;
  localparam MEM_BITS = DEPTH * DATA_W;

  localparam RAM_STYLE = (MEM_BITS >= 4096) ? "block" : "distributed";
  (* ram_style = RAM_STYLE *) reg [DATA_W-1:0] ram[0:DEPTH-1];

  reg [ADDR_W-1:0] wr_ptr, rd_ptr;
  reg [DATA_W-1:0] rd_data_bram;   // выделенный выходной регистр BRAM
  reg [DATA_W-1:0] first_word;     // bypass-регистр
  reg              first_word_valid;

  wire do_pop  = rd_en && !rd_empty;
  wire do_push = wr_en && (!wr_full || do_pop);

  // Prefetch: при pop читаем следующий элемент
  wire [ADDR_W-1:0] rd_addr = do_pop ? (rd_ptr + 1'b1) : rd_ptr;

  // usedw_next (как раньше)
  reg [ADDR_W:0] usedw_next;
  always @(*) begin
    case ({do_push, do_pop})
      2'b10:   usedw_next = usedw + 1'b1;
      2'b01:   usedw_next = usedw - 1'b1;
      default: usedw_next = usedw;
    endcase
  end

  // ---- BRAM write ----
  always @(posedge clk) begin
    if (do_push) ram[wr_ptr] <= wr_data;
  end

  // ---- BRAM read (чистый шаблон — infer BRAM) ----
  always @(posedge clk) begin
    rd_data_bram <= ram[rd_addr];
  end

  // ---- First-word bypass (эмулирует WRITE_FIRST для RTL-симуляции) ----
  always @(posedge clk) begin
    if (rst) begin
      first_word_valid <= 1'b0;
    end else if (do_push && (usedw == 0)) begin
      // Запись в пустое FIFO — новое слово становится головой
      first_word       <= wr_data;
      first_word_valid <= 1'b1;
    end else if (do_push && do_pop && first_word_valid && (usedw == 1)) begin
      // push+pop при одном элементе — новый push становится новой головой
      first_word       <= wr_data;
      first_word_valid <= 1'b1;
    end else if (do_pop && first_word_valid) begin
      // Голова прочитана — префетч из BRAM её уже подхватил
      first_word_valid <= 1'b0;
    end
  end

  assign rd_data = first_word_valid ? first_word : rd_data_bram;

  // ---- Указатели и флаги ----
  always @(posedge clk) begin
    if (rst) begin
      wr_ptr          <= {ADDR_W{1'b0}};
      rd_ptr          <= {ADDR_W{1'b0}};
      rd_empty        <= 1'b1;
      wr_full         <= 1'b0;
      wr_almost_full  <= 1'b0;
      rd_almost_empty <= 1'b1;
      usedw           <= {(ADDR_W + 1){1'b0}};
    end else begin
      if (do_pop)  rd_ptr <= rd_ptr + 1'b1;
      if (do_push) wr_ptr <= wr_ptr + 1'b1;

      usedw           <= usedw_next;
      rd_empty        <= (usedw_next == 0);
      wr_full         <= (usedw_next == DEPTH);
      wr_almost_full  <= (usedw_next >= ALMOST_FULL_THRESH);
      rd_almost_empty <= (usedw_next <= ALMOST_EMPTY_THRESH);
    end
  end

endmodule