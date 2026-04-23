module sync_fifo_fwft_reg_pow2_hifmax # 
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
    // RAM (BRAM-friendly)
    // -------------------------------------------------
    (* ram_style = "block" *)
    reg [DATA_W-1:0] mem [0:DEPTH-1];

    reg [ADDR_W-1:0] wr_ptr;
    reg [ADDR_W-1:0] rd_ptr;

    reg [DATA_W-1:0] mem_rd_data;

    always @(posedge clk)
        mem_rd_data <= mem[rd_ptr];

    always @(posedge clk)
        if (wr_en && !wr_full)
            mem[wr_ptr] <= wr_data;

    // -------------------------------------------------
    // FWFT output register
    // -------------------------------------------------
    reg [DATA_W-1:0] rd_data_reg;
    reg              rd_valid;

    assign rd_data = rd_data_reg;

    // -------------------------------------------------
    // Stage 1: RAM accounting (быстрый)
    // -------------------------------------------------
    reg [ADDR_W:0] ram_cnt;

    wire do_write = wr_en && !wr_full;
    wire do_read  = rd_en && rd_valid;

    wire ram_empty = (ram_cnt == 0);

    wire need_load =
        (!rd_valid && !ram_empty) ||
        (rd_en && rd_valid && !ram_empty);

    wire rd_from_ram = need_load;

    wire [ADDR_W:0] ram_cnt_next =
        ram_cnt + (do_write ? 1 : 0)
                - (rd_from_ram ? 1 : 0);

    // -------------------------------------------------
    // Stage 2: usedw pipeline
    // -------------------------------------------------
    reg [ADDR_W:0] usedw_next_r;
    reg            rd_valid_next_r;

    wire rd_valid_next =
        (rd_valid && !do_read) || need_load;

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
    // Stage 1 registers
    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ram_cnt <= 0;
        end else begin
            ram_cnt <= ram_cnt_next;
        end
    end

    // -------------------------------------------------
    // FWFT data path (отдельно, короткий путь)
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
    // Stage 2 registers (usedw)
    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            usedw_next_r     <= 0;
            rd_valid_next_r  <= 0;
            usedw            <= 0;
        end else begin
            usedw_next_r    <= usedw_next;
            rd_valid_next_r <= rd_valid_next;

            usedw <= usedw_next_r;
        end
    end

    // -------------------------------------------------
    // Stage 3: flags (ещё один pipeline)
    // -------------------------------------------------
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            wr_full          <= 0;
            wr_almost_full   <= 0;
            rd_empty         <= 1;
            rd_almost_empty  <= 1;
        end else begin
            wr_full        <= (usedw == DEPTH);
            wr_almost_full <= (usedw >= ALMOST_FULL_THRESH);

            rd_empty        <= (usedw == 0);
            rd_almost_empty <= (usedw <= ALMOST_EMPTY_THRESH);
        end
    end

endmodule
