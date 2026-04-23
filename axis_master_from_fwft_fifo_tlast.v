module axis_master_from_fwft_fifo_tlast #
(
    parameter DATA_WIDTH = 16,
    parameter N = 8
)
(
    input  wire                     clk,
    input  wire                     rst,

    // FIFO
    input  wire [DATA_WIDTH-1:0]    fifo_data,
    input  wire                     fifo_empty,
    output wire                     fifo_rd_en,

    // AXIS
    output wire [DATA_WIDTH-1:0]    m_axis_tdata,
    output wire                     m_axis_tvalid,
    input  wire                     m_axis_tready,
    output wire                     m_axis_tlast
);

    // ============================================================
    // Skid buffer
    // ============================================================

    reg v0, v1;
    reg [DATA_WIDTH-1:0] d0, d1;
    reg last0, last1;

    // ============================================================
    // Counters
    // ============================================================

    reg [$clog2(N):0] cnt_words;     // считает FIFO слова
    reg [DATA_WIDTH-1:0] pkt_cnt;    // номер пакета
    // reg sending_cnt_phase;           // 0 = FIFO, 1 = CNT

    // ============================================================
    // Control
    // ============================================================

    // AXI handshake:
    wire take1 = v1 && m_axis_tready;

    // stage1 can move if empty or being consumed:
    wire move  = !v1 || take1; // stage1 can accept data

    // stage0 gives data when it has valid and stage1 can accept:
    wire take0 = v0 && move; // stage0 -> stage1 transfer



    wire insert_pkt_cnt_now = (cnt_words == N-1);
    // ============================================================
    // Stage 1
    // ============================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            v1    <= 0;
            d1    <= 0;
            last1 <= 0;
        end else if (move) begin
            v1    <= v0;
            d1    <= d0;
            last1 <= last0;
        end
    end

    // ============================================================
    // Stage 0 (выбор данных)
    // ============================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            v0    <= 0;
            d0    <= 0;
            last0 <= 0;
        end else if (!v0 || take0) begin

            // приоритет: вставка pkt_cnt после N FIFO слов
            if (v0 && insert_pkt_cnt_now && take0) begin
                // вставляем счетчик
                v0    <= 1'b1;
                d0    <= pkt_cnt;
                last0 <= 1'b1;

            end else if (!fifo_empty) begin
                // берём FIFO
                v0    <= 1'b1;
                d0    <= fifo_data;
                last0 <= 1'b0;

            end else begin
                v0 <= 1'b0;
            end
        end
    end

    // ============================================================
    // Counters (строго по take0)
    // ============================================================

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            cnt_words <= 0;
            pkt_cnt   <= 0;
        end else if (take0) begin

            if (v0 && insert_pkt_cnt_now) begin
                // только что отправили N-е FIFO слово
                cnt_words <= 0;
                pkt_cnt   <= pkt_cnt + 1;

            end else if (v0 && !last0) begin
                // обычное FIFO слово
                cnt_words <= cnt_words + 1;
            end
        end
    end

    // ============================================================
    // FIFO read
    // ============================================================

    assign fifo_rd_en =
        (!v0 || take0) &&
        !fifo_empty &&
        !(v0 && insert_pkt_cnt_now); // не читаем, если сейчас последний FIFO


    // ============================================================
    // AXIS
    // ============================================================

    assign m_axis_tvalid = v1;
    assign m_axis_tdata  = d1;
    assign m_axis_tlast  = last1;

endmodule
