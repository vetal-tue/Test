module sync_fifo_fwft_reg_pow2 # 
(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,

    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
)
(
    input                  clk,
    input                  rst, 

    // write side
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output reg             wr_full,
    output reg             wr_almost_full,

    output reg [ADDR_W:0]  usedw, 

    // read side
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output reg             rd_empty,
    output reg             rd_almost_empty
);

    localparam DEPTH = (1 << ADDR_W);

    // -------------------------------------------------
    // RAM (true dual-port style inference)
    // -------------------------------------------------
    (* ram_style = "block" *)
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;

    reg [DATA_W-1:0] mem_rd_data;

    // синхронное чтение (важно для BRAM)
    always @(posedge clk) begin
        mem_rd_data <= mem[rd_ptr];
    end

    // запись
    always @(posedge clk) begin
        if (wr_en && !wr_full)
            mem[wr_ptr] <= wr_data;
    end

    // -------------------------------------------------
    // выходной регистр (FWFT)
    // -------------------------------------------------
    reg [DATA_W-1:0] rd_data_reg;
    reg              rd_valid;

    assign rd_data = rd_data_reg;

    // -------------------------------------------------
    // счетчик RAM (без выходного регистра)
    // -------------------------------------------------
    reg [ADDR_W:0] ram_cnt;

    wire ram_empty = (ram_cnt == 0);
    wire ram_full  = (ram_cnt == DEPTH);

    // -------------------------------------------------
    // управляющие сигналы
    // -------------------------------------------------

    // нужно ли загрузить регистр из RAM
    wire need_load =
        (!rd_valid && !ram_empty) ||   // initial FWFT
        (rd_en && rd_valid && !ram_empty); // refill после чтения

    // будет ли чтение из RAM
    wire rd_from_ram = need_load;

    // -------------------------------------------------
    // next state для счетчиков
    // -------------------------------------------------
    wire do_write = wr_en && !wr_full;
    wire do_read  = rd_en && rd_valid;

    // RAM count update
    wire [ADDR_W:0] ram_cnt_next =
        ram_cnt + (do_write ? 1 : 0)
                - (rd_from_ram ? 1 : 0);

    // valid бит регистра
    wire rd_valid_next =
        (rd_valid && !do_read) ||   // держим
        (need_load);               // загрузка

    // usedw включает регистр
    wire [ADDR_W:0] usedw_next =
        ram_cnt_next + (rd_valid_next ? 1 : 0);

    // -------------------------------------------------
    // pointers
    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (do_write)
                wr_ptr <= wr_ptr + 1;

            if (rd_from_ram)
                rd_ptr <= rd_ptr + 1;
        end
    end

    // -------------------------------------------------
    // RAM counter
    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst)
            ram_cnt <= 0;
        else
            ram_cnt <= ram_cnt_next;
    end

    // -------------------------------------------------
    // выходной регистр (FWFT)
    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            rd_data_reg <= 0;
            rd_valid    <= 0;
        end else begin
            if (need_load)
                rd_data_reg <= mem_rd_data;

            rd_valid <= rd_valid_next;
        end
    end

    // -------------------------------------------------
    // flags + usedw (REGISTERED)
    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            usedw            <= 0;
            wr_full          <= 0;
            wr_almost_full   <= 0;
            rd_empty         <= 1;
            rd_almost_empty  <= 1;
        end else begin
            usedw <= usedw_next;

            wr_full        <= (usedw_next == DEPTH);
            wr_almost_full <= (usedw_next >= ALMOST_FULL_THRESH);

            rd_empty        <= (usedw_next == 0);
            rd_almost_empty <= (usedw_next <= ALMOST_EMPTY_THRESH);
        end
    end

endmodule
