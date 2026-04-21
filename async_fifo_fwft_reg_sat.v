module async_fifo_fwft_reg_sat #
(
    parameter DATA_W = 16,
    parameter ADDR_W = 4,
    // parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 4,
    // parameter ALMOST_EMPTY_THRESH = 4
    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 1,
    parameter ALMOST_EMPTY_THRESH = 1
)
(
    // write side
    input                  wr_clk,
    input                  wr_rst,
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output reg             wr_full,
    output reg             wr_almost_full,
    output reg [ADDR_W:0]  wr_cnt,

    // read side
    input                  rd_clk,
    input                  rd_rst,
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output reg             rd_empty,
    output reg             rd_almost_empty,
    output reg [ADDR_W:0]  rd_cnt
);

localparam PTR_W = ADDR_W;
localparam DEPTH = (1<<ADDR_W);

// =========================
// memory
// =========================
reg [DATA_W-1:0] mem [0:DEPTH-1];


// =========================
// Gray functions
// =========================
function [PTR_W:0] bin2gray;
    input [PTR_W:0] b;
    bin2gray = (b >> 1) ^ b;
endfunction

function [PTR_W:0] gray2bin;
    input [PTR_W:0] g;
    integer i;
    begin
        gray2bin[PTR_W] = g[PTR_W];
        for (i = PTR_W-1; i >= 0; i = i-1)
            gray2bin[i] = gray2bin[i+1] ^ g[i];
    end
endfunction


// ============================================================
// WRITE DOMAIN
// ============================================================
reg [PTR_W:0] wr_ptr_bin,  wr_ptr_gray, rd_ptr_gray; 

reg [PTR_W:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
reg rd_valid_sync1, rd_valid_sync2;
wire [PTR_W:0] rd_ptr_gray_sync = rd_ptr_gray_sync2;

reg              rd_valid;

// sync read pointer
always @(posedge wr_clk) begin
    if (wr_rst) begin
        rd_ptr_gray_sync1 <= 0;
        rd_ptr_gray_sync2 <= 0;
        rd_valid_sync1    <= 0;
        rd_valid_sync2    <= 0;

    end else begin
        rd_ptr_gray_sync1 <= rd_ptr_gray;
        rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

        rd_valid_sync1 <= rd_valid;
        rd_valid_sync2 <= rd_valid_sync1;
        
    end
    // rd_ptr_gray_sync1 <= rd_ptr_gray;
    // rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;

    // rd_valid_sync1 <= rd_valid;
    // rd_valid_sync2 <= rd_valid_sync1;
end
wire rd_valid_wr = rd_valid_sync2;

// gray -> bin (pipeline для timing)
reg [PTR_W:0] rd_ptr_bin_sync_r;
always @(posedge wr_clk)
    if (wr_rst)
        rd_ptr_bin_sync_r  <= 0;
    else
        rd_ptr_bin_sync_r <= gray2bin(rd_ptr_gray_sync);

// next pointer
wire [PTR_W:0] wr_ptr_bin_next  = wr_ptr_bin + 1;
wire [PTR_W:0] wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);

// FULL (combinational internal)
wire wr_full_int =
    (wr_ptr_gray_next == {
        ~rd_ptr_gray_sync[PTR_W:PTR_W-1],
         rd_ptr_gray_sync[PTR_W-2:0]
    });

// occupancy (combinational)
wire [PTR_W:0] wr_cnt_raw = wr_ptr_bin - rd_ptr_bin_sync_r;
wire [PTR_W:0] wr_cnt_total = wr_cnt_raw + rd_valid_wr;

// saturation
wire [PTR_W:0] wr_cnt_sat =
    // (wr_cnt_raw > DEPTH) ? DEPTH :
    // wr_cnt_raw;
    (wr_cnt_total > DEPTH) ? DEPTH :
    wr_cnt_total;

// almost
wire wr_almost_full_int = (wr_cnt_sat >= ALMOST_FULL_THRESH);

// write
always @(posedge wr_clk) begin
    if (wr_rst) begin
        wr_ptr_bin  <= 0;
        wr_ptr_gray <= 0;
    end else if (wr_en && !wr_full_int) begin
        mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
        wr_ptr_bin  <= wr_ptr_bin_next;
        wr_ptr_gray <= wr_ptr_gray_next;
    end
end

// registered outputs
always @(posedge wr_clk) begin
    if (wr_rst) begin
        wr_full        <= 1'b0;
        wr_almost_full <= 1'b0;
        wr_cnt         <= 0;
    end else begin
        wr_full        <= wr_full_int;
        wr_almost_full <= wr_almost_full_int;
        wr_cnt         <= wr_cnt_sat;
    end
end


// ============================================================
// READ DOMAIN (FWFT)
// ============================================================
// reg [PTR_W:0] rd_ptr_bin, rd_ptr_gray;
reg [PTR_W:0] rd_ptr_bin;

reg [PTR_W:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
wire [PTR_W:0] wr_ptr_gray_sync = wr_ptr_gray_sync2;

// sync write pointer
always @(posedge rd_clk) begin
    wr_ptr_gray_sync1 <= wr_ptr_gray;
    wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
end

// gray -> bin (pipeline)
reg [PTR_W:0] wr_ptr_bin_sync_r;
always @(posedge rd_clk)
    if (rd_rst)
        wr_ptr_bin_sync_r <= 0;
    else
        wr_ptr_bin_sync_r <= gray2bin(wr_ptr_gray_sync);

// EMPTY (memory)
wire mem_empty = (rd_ptr_gray == wr_ptr_gray_sync);

// occupancy
wire [PTR_W:0] rd_cnt_raw = wr_ptr_bin_sync_r - rd_ptr_bin;
wire [PTR_W:0] rd_cnt_total = rd_cnt_raw + rd_valid;

// saturation
wire [PTR_W:0] rd_cnt_sat =
    // (rd_cnt_raw > DEPTH) ? DEPTH :
    // rd_cnt_raw;
    (rd_cnt_total > DEPTH) ? DEPTH :
    rd_cnt_total;

// almost empty
wire rd_almost_empty_int = (rd_cnt_sat <= ALMOST_EMPTY_THRESH);


// =========================
// FWFT datapath
// =========================
reg [DATA_W-1:0] rd_data_reg;
// reg              rd_valid;

assign rd_data = rd_data_reg;

// next pointer
wire [PTR_W:0] rd_ptr_bin_next  = rd_ptr_bin + 1;
wire [PTR_W:0] rd_ptr_gray_next = bin2gray(rd_ptr_bin_next);


// read logic
always @(posedge rd_clk) begin
    if (rd_rst) begin
        rd_ptr_bin  <= 0;
        rd_ptr_gray <= 0;
        rd_valid    <= 0;
    end else begin

        if (!rd_valid && !mem_empty) begin
            rd_data_reg <= mem[rd_ptr_bin[ADDR_W-1:0]];
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            rd_valid    <= 1;
        end
        else if (rd_en && rd_valid) begin
            if (!mem_empty) begin
                rd_data_reg <= mem[rd_ptr_bin[ADDR_W-1:0]];
                rd_ptr_bin  <= rd_ptr_bin_next;
                rd_ptr_gray <= rd_ptr_gray_next;
                rd_valid    <= 1;
            end else begin
                rd_valid <= 0;
            end
        end

    end
end

// registered outputs
always @(posedge rd_clk) begin
    if (rd_rst) begin
        rd_empty        <= 1'b1;
        rd_almost_empty <= 1'b1;
        rd_cnt          <= 0;
    end else begin
        rd_empty        <= !rd_valid;
        rd_almost_empty <= rd_almost_empty_int;
        rd_cnt          <= rd_cnt_sat;
    end
end

endmodule
