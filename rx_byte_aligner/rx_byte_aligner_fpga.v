// ============================================================================
// rx_byte_aligner_fpga (FPGA-friendly версия)
//
// Изменения относительно первой версии, направленные на синтез:
//   1) Barrel-shift сделан явным case'ом со СТАТИЧЕСКИМИ битовыми срезами
//      вместо вычисляемого part-select'а (32-8*shift_now)+:32.
//      Это гарантированно ложится в чистый 4:1 mux на входе регистра,
//      без риска, что синтезатор развернёт это в что-то более тяжёлое.
//   2) Детект comma+one-hot проверка объединены в один case по вектору
//      {comma3,comma2,comma1,comma0} - это компактный LUT-декодер,
//      вместо сумматора (comma0+comma1+comma2+comma3==1).
//   3) Синхронный сброс (active-high, по фронту clk) - рекомендуемая практика
//      для FPGA: ложится в штатный SR-вход триггера без отдельного
//      async-дерева сброса и без recovery/removal timing путей.
//   4) Data-path регистры (rx_data_d, rx_data_o) сброшены "мягко" (в 0,
//      но это не обязательно - см. комментарий ниже), сброс нужен только
//      для control-регистров (shift_r, have_prev, rx_aligned).
// ============================================================================
module rx_byte_aligner_fpga #(
    parameter [7:0] COMMA_BYTE = 8'hBC
)(
    input  wire        clk,
    input  wire        rst,       // синхронный сброс, active-high
    input  wire        align_en,

    input  wire [31:0] rx_data,
    input  wire [3:0]  rx_ctrl,

    output reg  [31:0] rx_data_o,
    output reg  [3:0]  rx_ctrl_o,
    output reg          rx_aligned
);

    // -------- байты текущего (сырого) слова --------
    wire [7:0] b0 = rx_data[7:0];
    wire [7:0] b1 = rx_data[15:8];
    wire [7:0] b2 = rx_data[23:16];
    wire [7:0] b3 = rx_data[31:24];

    wire comma0 = rx_ctrl[0] & (b0 == COMMA_BYTE);
    wire comma1 = rx_ctrl[1] & (b1 == COMMA_BYTE);
    wire comma2 = rx_ctrl[2] & (b2 == COMMA_BYTE);
    wire comma3 = rx_ctrl[3] & (b3 == COMMA_BYTE);

    // -------- one-hot декодер: и позиция, и валидность одним case'ом --------
    reg [1:0] s_detect;
    reg       comma_ok;
    always @* begin
        case ({comma3, comma2, comma1, comma0})
            4'b0001: begin comma_ok = 1'b1; s_detect = 2'd0; end
            4'b0010: begin comma_ok = 1'b1; s_detect = 2'd3; end
            4'b0100: begin comma_ok = 1'b1; s_detect = 2'd2; end
            4'b1000: begin comma_ok = 1'b1; s_detect = 2'd1; end
            default: begin comma_ok = 1'b0; s_detect = 2'd0; end // 0000 или >1 бита - игнор
        endcase
    end

    reg [31:0] rx_data_d;
    reg [3:0]  rx_ctrl_d;
    reg        have_prev;
    reg [1:0]  shift_r;

    wire update_shift = align_en & comma_ok;
    wire [1:0] shift_now = update_shift ? s_detect : shift_r;

    always @(posedge clk) begin
        if (rst) begin
            rx_data_d  <= 32'd0;
            rx_ctrl_d  <= 4'd0;
            have_prev  <= 1'b0;
            shift_r    <= 2'd0;
            rx_aligned <= 1'b0;
            rx_data_o  <= 32'd0;
            rx_ctrl_o  <= 4'd0;
        end else begin
            // регистр "предыдущего" слова
            rx_data_d <= rx_data;
            rx_ctrl_d <= rx_ctrl;
            have_prev <= 1'b1;

            // фиксация сдвига
            if (update_shift)
                shift_r <= s_detect;

            if (update_shift && have_prev)
                rx_aligned <= 1'b1;

            // -------- явный 4:1 mux со статическими срезами --------
            case (shift_now)
                2'd0: begin
                    rx_data_o <= rx_data;
                    rx_ctrl_o <= rx_ctrl;
                end
                2'd1: begin
                    rx_data_o <= {rx_data[23:0], rx_data_d[31:24]};
                    rx_ctrl_o <= {rx_ctrl[2:0],  rx_ctrl_d[3]};
                end
                2'd2: begin
                    rx_data_o <= {rx_data[15:0], rx_data_d[31:16]};
                    rx_ctrl_o <= {rx_ctrl[1:0],  rx_ctrl_d[3:2]};
                end
                2'd3: begin
                    rx_data_o <= {rx_data[7:0],  rx_data_d[31:8]};
                    rx_ctrl_o <= {rx_ctrl[0],    rx_ctrl_d[3:1]};
                end
            endcase
        end
    end

endmodule
