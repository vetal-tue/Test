module async_fifo_fwft_reg_pow2_1 #
(
    parameter DATA_W              = 16,
    parameter ADDR_W              = 4,
    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
)
(
    input                     wr_clk,
    input                     rst,
    // write side
    input                     wr_en,
    input      [DATA_W-1:0]   wr_data,
    output reg                wr_full,
    output reg                wr_almost_full,
    output reg [ADDR_W:0]     wr_cnt,
    // read side
    input                     rd_clk,
    input                     rd_en,
    output reg [DATA_W-1:0]   rd_data,
    output reg [ADDR_W:0]     rd_cnt,
    output reg                rd_empty,
    output reg                rd_almost_empty
);

    // =========================================================================
    // Память (Dual-Port RAM)
    // =========================================================================
    localparam DEPTH = 1 << ADDR_W;
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // =========================================================================
    // Домен записи (wr_clk)
    // =========================================================================
    reg [ADDR_W:0] wptr_bin;
    reg [ADDR_W:0] wptr_gray;
    reg [ADDR_W:0] rptr_gray_sync_0, rptr_gray_sync_1;
    reg [ADDR_W:0] rptr_bin_wr;

    // Синхронизация rptr_gray в домен wr_clk (2-stage synchronizer)
    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            rptr_gray_sync_0 <= {(ADDR_W+1){1'b0}};
            rptr_gray_sync_1 <= {(ADDR_W+1){1'b0}};
        end else begin
            rptr_gray_sync_0 <= rptr_gray;
            rptr_gray_sync_1 <= rptr_gray_sync_0;
        end
    end

    // Преобразование rptr_gray -> двоичный код в домене записи
    integer i;
    always @(*) begin
        rptr_bin_wr[ADDR_W] = rptr_gray_sync_1[ADDR_W];
        for (i = ADDR_W - 1; i >= 0; i = i - 1) begin
            rptr_bin_wr[i] = rptr_bin_wr[i+1] ^ rptr_gray_sync_1[i];
        end
    end

    // Запись в память и обновление указателей записи
    wire [ADDR_W:0] wptr_bin_next  = wptr_bin + (wr_en && !wr_full);
    wire [ADDR_W:0] wptr_gray_next = wptr_bin_next ^ (wptr_bin_next >> 1);
    wire [ADDR_W:0] wr_cnt_next    = wptr_bin_next - rptr_bin_wr;

    always @(posedge wr_clk) begin
        if (wr_en && !wr_full) begin
            mem[wptr_bin[ADDR_W-1:0]] <= wr_data;
        end
    end

    always @(posedge wr_clk or posedge rst) begin
        if (rst) begin
            wptr_bin       <= {(ADDR_W+1){1'b0}};
            wptr_gray      <= {(ADDR_W+1){1'b0}};
            wr_full        <= 1'b0;
            wr_almost_full <= 1'b0;
            wr_cnt         <= {(ADDR_W+1){1'b0}};
        end else begin
            if (wr_en && !wr_full) begin
                wptr_bin  <= wptr_bin_next;
                wptr_gray <= wptr_gray_next;
            end
            wr_cnt         <= wr_cnt_next;
            wr_full        <= (wr_cnt_next >= DEPTH);
            wr_almost_full <= (wr_cnt_next >= ALMOST_FULL_THRESH);
        end
    end

    // =========================================================================
    // Домен чтения (rd_clk) + Логика FWFT
    // =========================================================================
    reg [ADDR_W:0] rptr_bin;
    reg [ADDR_W:0] rptr_gray;
    reg [ADDR_W:0] wptr_gray_sync_0, wptr_gray_sync_1;
    reg [ADDR_W:0] wptr_bin_rd;

    // Синхронизация wptr_gray в домен rd_clk (2-stage synchronizer)
    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            wptr_gray_sync_0 <= {(ADDR_W+1){1'b0}};
            wptr_gray_sync_1 <= {(ADDR_W+1){1'b0}};
        end else begin
            wptr_gray_sync_0 <= wptr_gray;
            wptr_gray_sync_1 <= wptr_gray_sync_0;
        end
    end

    // Преобразование wptr_gray -> двоичный код в домене чтения
    integer j;
    always @(*) begin
        wptr_bin_rd[ADDR_W] = wptr_gray_sync_1[ADDR_W];
        for (j = ADDR_W - 1; j >= 0; j = j - 1) begin
            wptr_bin_rd[j] = wptr_bin_rd[j+1] ^ wptr_gray_sync_1[j];
        end
    end

    // Асинхронное чтение сырых данных из памяти для предвыборки (Prefetch)
    wire [DATA_W-1:0] ram_dout = mem[rptr_bin[ADDR_W-1:0]];

    // Логика авто-предвыборки для FWFT
    wire ram_has_data  = (wptr_bin_rd != rptr_bin);
    wire do_prefetch   = (rd_empty && ram_has_data) || (!rd_empty && rd_en && ram_has_data);
    wire do_pop_empty  = (!rd_empty && rd_en && !ram_has_data);

    wire [ADDR_W:0] rptr_bin_next  = do_prefetch  ? (rptr_bin + 1'b1) : rptr_bin;
    wire [ADDR_W:0] rptr_gray_next = rptr_bin_next ^ (rptr_bin_next >> 1);
    wire            rd_empty_next  = do_pop_empty ? 1'b1 : (do_prefetch ? 1'b0 : rd_empty);
    wire [ADDR_W:0] rd_cnt_next    = (wptr_bin_rd - rptr_bin_next) + (rd_empty_next ? 1'b0 : 1'b1);

    always @(posedge rd_clk or posedge rst) begin
        if (rst) begin
            rptr_bin        <= {(ADDR_W+1){1'b0}};
            rptr_gray       <= {(ADDR_W+1){1 me{1'b0}}};
            rd_empty        <= 1'b1;
            rd_almost_empty <= 1'b1;
            rd_cnt          <= {(ADDR_W+1){1'b0}};
            rd_data         <= {DATA_W{1'b0}};
        end else begin
            rptr_bin  <= rptr_bin_next;
            rptr_gray <= rptr_gray_next;
            rd_empty  <= rd_empty_next;

            // В FWFT данные считываются в выходной регистр заранее
            if (do_prefetch) begin
                rd_data <= ram_dout;
            end

            rd_cnt          <= rd_cnt_next;
            rd_almost_empty <= (rd_cnt_next <= ALMOST_EMPTY_THRESH);
        end
    end

endmodule