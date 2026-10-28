module sync_fifo_fwft_bram_D #(
    parameter DATA_W = 16,
    parameter ADDR_W = 12,
    parameter ALMOST_FULL_THRESH = (1 << ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1,
    parameter ENABLE_BYPASS = 0  // 1 = bypass (1 такт латентности, mux на rd_data)
                                 // 0 = two-stage (2 такта латентности, БЕЗ mux)
) (
    input  wire              clk,
    input  wire              rst,
    input  wire              wr_en,
    input  wire [DATA_W-1:0] wr_data,
    output reg               wr_full,
    output reg               wr_almost_full,
    output reg  [  ADDR_W:0] usedw,
    input  wire              rd_en,
    output wire [DATA_W-1:0] rd_data,
    output reg               rd_empty,
    output reg               rd_almost_empty
);

  localparam DEPTH    = 1 << ADDR_W;
  localparam MEM_BITS = DEPTH * DATA_W;
  localparam RAM_STYLE = (MEM_BITS >= 4096) ? "block" : "distributed";
  (* ram_style = RAM_STYLE *) reg [DATA_W-1:0] ram[0:DEPTH-1];

  generate
    // ==================================================================
    // ENABLE_BYPASS = 1 : ОДНОСТУПЕНЧАТЫЙ FWFT с bypass-регистром
    //     латентность первого слова = 1 такт
    //     mux на выходе rd_data (LUT)
    // ==================================================================
    if (ENABLE_BYPASS) begin : g_bypass
      reg [ADDR_W-1:0] wr_ptr, rd_ptr;
      reg [DATA_W-1:0] rd_data_bram, first_word;
      reg               first_word_valid;

      wire              do_pop = rd_en && !rd_empty;
      wire              do_push = wr_en && (!wr_full || do_pop);

      // prefetch: при pop читаем следующий элемент
      wire [ADDR_W-1:0] rd_addr = do_pop ? (rd_ptr + 1'b1) : rd_ptr;

      reg  [  ADDR_W:0] usedw_next;
      always @(*) begin
        case ({
          do_push, do_pop
        })
          2'b10:   usedw_next = usedw + 1'b1;
          2'b01:   usedw_next = usedw - 1'b1;
          default: usedw_next = usedw;
        endcase
      end

      always @(posedge clk) if (do_push) ram[wr_ptr] <= wr_data;
      always @(posedge clk) rd_data_bram <= ram[rd_addr];

      always @(posedge clk) begin
        if (rst) first_word_valid <= 1'b0;
        else if (do_push && (usedw == 0)) begin
          first_word       <= wr_data;
          first_word_valid <= 1'b1;
        end else if (do_push && do_pop && first_word_valid && (usedw == 1)) begin
          first_word       <= wr_data;
          first_word_valid <= 1'b1;
        end else if (do_pop && first_word_valid) begin
          first_word_valid <= 1'b0;
        end
      end

      always @(posedge clk) begin
        if (rst) begin
          wr_ptr          <= {ADDR_W{1'b0}};
          rd_ptr          <= {ADDR_W{1'b0}};
          rd_empty        <= 1'b1;
          wr_full         <= 1'b0;
          wr_almost_full  <= 1'b0;
          rd_almost_empty <= 1'b1;
          usedw           <= {(ADDR_W + 1) {1'b0}};
        end else begin
          if (do_pop) rd_ptr <= rd_ptr + 1'b1;
          if (do_push) wr_ptr <= wr_ptr + 1'b1;
          usedw           <= usedw_next;
          rd_empty        <= (usedw_next == 0);
          wr_full         <= (usedw_next == DEPTH);
          wr_almost_full  <= (usedw_next >= ALMOST_FULL_THRESH);
          rd_almost_empty <= (usedw_next <= ALMOST_EMPTY_THRESH);
        end
      end

      assign rd_data = first_word_valid ? first_word : rd_data_bram;

      // ==================================================================
      // ENABLE_BYPASS = 0 : ДВУХСТУПЕНЧАТЫЙ FWFT
      //     латентность первого слова = 2 такта
      //     rd_data = rd_data_reg (без mux, чистый BRAM-выход)
      // ==================================================================
    end else begin : g_no_bypass
      reg [ADDR_W-1:0] wr_ptr, rd_ptr;
      reg  [  ADDR_W:0] ram_count;  // элементы только в RAM (без rd_data_reg)
      reg  [DATA_W-1:0] rd_data_reg;  // выходной регистр (2-я ступень)

      wire              do_pop = rd_en && !rd_empty;
      wire              do_ram_write = wr_en && (!wr_full || do_pop);
      wire              ram_re = (ram_count > 0) && (rd_empty || rd_en);

      reg  [  ADDR_W:0] ram_count_next;
      always @(*) begin
        case ({
          do_ram_write, ram_re
        })
          2'b10:   ram_count_next = ram_count + 1'b1;
          2'b01:   ram_count_next = ram_count - 1'b1;
          default: ram_count_next = ram_count;
        endcase
      end

      reg rd_empty_next;
      always @(*) begin
        rd_empty_next = rd_empty;
        if (ram_re) rd_empty_next = 1'b0;  // префетч заполнил выход
        else if (rd_en && !rd_empty)
          rd_empty_next = 1'b1;  // прочли, подставлять нечего
      end

      // Полная занятость = RAM + выходной регистр
      wire [ADDR_W:0] usedw_next = ram_count_next + (rd_empty_next ? 1'b0 : 1'b1);

      always @(posedge clk) begin
        if (rst) begin
          wr_ptr          <= {ADDR_W{1'b0}};
          rd_ptr          <= {ADDR_W{1'b0}};
          ram_count       <= {(ADDR_W + 1) {1'b0}};
          rd_data_reg     <= {DATA_W{1'b0}};
          rd_empty        <= 1'b1;
          wr_full         <= 1'b0;
          wr_almost_full  <= 1'b0;
          rd_almost_empty <= 1'b1;
          usedw           <= {(ADDR_W + 1) {1'b0}};
        end else begin
          if (do_ram_write) begin
            ram[wr_ptr] <= wr_data;
            wr_ptr      <= wr_ptr + 1'b1;
          end
          if (ram_re) begin
            rd_data_reg <= ram[rd_ptr];
            rd_ptr      <= rd_ptr + 1'b1;
          end
          ram_count       <= ram_count_next;
          rd_empty        <= rd_empty_next;
          usedw           <= usedw_next;
          wr_full         <= (usedw_next == DEPTH);
          wr_almost_full  <= (usedw_next >= ALMOST_FULL_THRESH);
          rd_almost_empty <= (usedw_next <= ALMOST_EMPTY_THRESH);
        end
      end

      assign rd_data = rd_data_reg;   // БЕЗ mux — прямой провод от регистра
    end
  endgenerate

endmodule
