// ============================================================================
// Асинхронное FIFO (First Word Fall Through)
// Параметры:
//   DATA_W               - разрядность данных
//   ADDR_W               - разрядность адреса (глубина = 2**ADDR_W)
//   ALMOST_FULL_THRESH   - порог почти полного (в свободных слотах)
//   ALMOST_EMPTY_THRESH  - порог почти пустого (в занятых слотах)
// ============================================================================

module dpsk_async_fifo_fwft #(
    parameter DATA_W              = 8,
    parameter ADDR_W              = 4,
    parameter ALMOST_FULL_THRESH  = 2,
    parameter ALMOST_EMPTY_THRESH = 2
) (
    // Домен записи
    input                  wr_clk,
    input                  wr_rst,
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output reg             wr_full,
    output reg             wr_almost_full,
    output reg [ADDR_W:0]  wr_cnt,

    // Домен чтения
    input                  rd_clk,
    input                  rd_rst,
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output reg             rd_empty,
    output reg             rd_almost_empty,
    output reg [ADDR_W:0]  rd_cnt
);

    // ------------------------------------------------------------------------
    // Локальные параметры
    // ------------------------------------------------------------------------
    localparam DEPTH     = 1 << ADDR_W;          // глубина FIFO
    localparam PTR_WIDTH = ADDR_W + 1;           // разрядность указателя

    // ------------------------------------------------------------------------
    // Функции преобразования кода Грея
    // ------------------------------------------------------------------------
    function [PTR_WIDTH-1:0] bin2gray (input [PTR_WIDTH-1:0] bin);
        bin2gray = bin ^ (bin >> 1);
    endfunction

    function [PTR_WIDTH-1:0] gray2bin (input [PTR_WIDTH-1:0] gray);
        integer i;
        reg [PTR_WIDTH-1:0] bin;
        begin
            bin[PTR_WIDTH-1] = gray[PTR_WIDTH-1];
            for (i = PTR_WIDTH-2; i >= 0; i = i - 1)
                bin[i] = bin[i+1] ^ gray[i];
            gray2bin = bin;
        end
    endfunction

    // ------------------------------------------------------------------------
    // Память FIFO (синхронная запись, асинхронное чтение)
    // ------------------------------------------------------------------------
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    // ========================================================================
    // ДОМЕН ЗАПИСИ (wr_clk)
    // ========================================================================
    reg [PTR_WIDTH-1:0] wr_ptr_bin;        // бинарный указатель записи
    reg [PTR_WIDTH-1:0] wr_ptr_gray;       // код Грея указателя записи
    wire [PTR_WIDTH-1:0] wr_ptr_bin_next;
    wire [PTR_WIDTH-1:0] wr_ptr_gray_next;

    // Синхронизация указателя чтения из домена чтения
    reg [PTR_WIDTH-1:0] rd_ptr_gray_sync1_wr, rd_ptr_gray_sync2_wr;
    wire [PTR_WIDTH-1:0] rd_ptr_bin_sync_wr;

    // Вычисление следующего значения указателя записи
    assign wr_ptr_bin_next = wr_ptr_bin + {{PTR_WIDTH-1{1'b0}}, (wr_en & ~wr_full)};
    assign wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);

    // Регистры указателей
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_ptr_bin  <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
        end
    end

    // Двухступенчатый синхронизатор rd_ptr_gray -> домен записи
    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            rd_ptr_gray_sync1_wr <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray_sync2_wr <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_ptr_gray_sync1_wr <= rd_ptr_gray;          // вход из домена чтения
            rd_ptr_gray_sync2_wr <= rd_ptr_gray_sync1_wr;
        end
    end

    assign rd_ptr_bin_sync_wr = gray2bin(rd_ptr_gray_sync2_wr);

    // ------------------------------------------------------------------------
    // Счетчик заполнения в домене записи (wr_cnt)
    // ------------------------------------------------------------------------
    wire [PTR_WIDTH-1:0] wr_cnt_int;
    assign wr_cnt_int = (wr_ptr_bin - rd_ptr_bin_sync_wr) & ((1 << PTR_WIDTH) - 1);

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst)
            wr_cnt <= {(ADDR_W+1){1'b0}};
        else
            wr_cnt <= wr_cnt_int;
    end

    // ------------------------------------------------------------------------
    // Флаги в домене записи
    // ------------------------------------------------------------------------
    wire wr_full_comb;
    wire wr_almost_full_comb;

    // full: если следующий указатель Грея записи отличается от синхронизированного
    // указателя чтения старшими двумя битами, а младшие совпадают
    assign wr_full_comb = (wr_ptr_gray_next == 
        {~rd_ptr_gray_sync2_wr[PTR_WIDTH-1:PTR_WIDTH-2], rd_ptr_gray_sync2_wr[PTR_WIDTH-3:0]});

    // almost full: количество свободных мест <= порога
    assign wr_almost_full_comb = ((DEPTH - wr_cnt_int) <= ALMOST_FULL_THRESH) ? 1'b1 : 1'b0;

    always @(posedge wr_clk or posedge wr_rst) begin
        if (wr_rst) begin
            wr_full        <= 1'b0;
            wr_almost_full <= 1'b0;
        end else begin
            wr_full        <= wr_full_comb;
            wr_almost_full <= wr_almost_full_comb;
        end
    end

    // ------------------------------------------------------------------------
    // Запись в память
    // ------------------------------------------------------------------------
    always @(posedge wr_clk) begin
        if (wr_en & ~wr_full)
            mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
    end

    // ========================================================================
    // ДОМЕН ЧТЕНИЯ (rd_clk)
    // ========================================================================
    reg [PTR_WIDTH-1:0] rd_ptr_bin;        // бинарный указатель чтения
    reg [PTR_WIDTH-1:0] rd_ptr_gray;       // код Грея указателя чтения
    wire [PTR_WIDTH-1:0] rd_ptr_bin_next;
    wire [PTR_WIDTH-1:0] rd_ptr_gray_next;

    // Синхронизация указателя записи из домена записи
    reg [PTR_WIDTH-1:0] wr_ptr_gray_sync1_rd, wr_ptr_gray_sync2_rd;
    wire [PTR_WIDTH-1:0] wr_ptr_bin_sync_rd;

    // Данные из памяти (асинхронное чтение)
    wire [DATA_W-1:0] mem_rd_data;
    assign mem_rd_data = mem[rd_ptr_bin[ADDR_W-1:0]];

    // Регистр выходных данных
    reg [DATA_W-1:0] rd_data_reg;
    assign rd_data = rd_data_reg;

    // Логика empty и almost empty
    wire rd_empty_comb;
    wire rd_almost_empty_comb;
    wire [PTR_WIDTH-1:0] rd_cnt_int;

    // Вычисление следующего указателя чтения
    assign rd_ptr_bin_next = rd_ptr_bin + {{PTR_WIDTH-1{1'b0}}, (rd_en & ~rd_empty)};
    assign rd_ptr_gray_next = bin2gray(rd_ptr_bin_next);

    // Регистры указателей чтения
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_ptr_bin  <= {PTR_WIDTH{1'b0}};
            rd_ptr_gray <= {PTR_WIDTH{1'b0}};
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
        end
    end

    // Двухступенчатый синхронизатор wr_ptr_gray -> домен чтения
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            wr_ptr_gray_sync1_rd <= {PTR_WIDTH{1'b0}};
            wr_ptr_gray_sync2_rd <= {PTR_WIDTH{1'b0}};
        end else begin
            wr_ptr_gray_sync1_rd <= wr_ptr_gray;          // вход из домена записи
            wr_ptr_gray_sync2_rd <= wr_ptr_gray_sync1_rd;
        end
    end

    assign wr_ptr_bin_sync_rd = gray2bin(wr_ptr_gray_sync2_rd);

    // ------------------------------------------------------------------------
    // Счетчик заполнения в домене чтения (rd_cnt)
    // ------------------------------------------------------------------------
    assign rd_cnt_int = (wr_ptr_bin_sync_rd - rd_ptr_bin) & ((1 << PTR_WIDTH) - 1);

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_cnt <= {(ADDR_W+1){1'b0}};
        else
            rd_cnt <= rd_cnt_int;
    end

    // ------------------------------------------------------------------------
    // Флаги в домене чтения
    // ------------------------------------------------------------------------
    assign rd_empty_comb = (rd_ptr_gray == wr_ptr_gray_sync2_rd);
    assign rd_almost_empty_comb = (rd_cnt_int <= ALMOST_EMPTY_THRESH) ? 1'b1 : 1'b0;

    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst) begin
            rd_empty        <= 1'b1;
            rd_almost_empty <= 1'b1;
        end else begin
            rd_empty        <= rd_empty_comb;
            rd_almost_empty <= rd_almost_empty_comb;
        end
    end

    // ------------------------------------------------------------------------
    // Регистр выходных данных (FWFT поведение)
    // ------------------------------------------------------------------------
    // При сбросе сбрасываем, иначе:
    //   - если FIFO не пуст, захватываем данные из памяти
    //   - если пуст, сохраняем предыдущее значение (не меняем)
    always @(posedge rd_clk or posedge rd_rst) begin
        if (rd_rst)
            rd_data_reg <= {DATA_W{1'b0}};
        else if (~rd_empty_comb)
            rd_data_reg <= mem_rd_data;
        // если empty, сохраняем текущее значение
    end

endmodule
