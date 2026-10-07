// ============================================================================
//  V_TrueDualPortRAM — параметризуемая True Dual-Port память
//
//  Выбор вендора FPGA:
//    Раскомментировать РОВНО ОДИН из двух define ниже:
// ============================================================================

// `define FPGA_XILINX       // ← для Vivado (Artix-7, Kintex-7, Zynq-7000 и т.д.)
`define FPGA_INTEL      // ← для Quartus (Cyclone 10 GX, Arria, Stratix и т.д.)


`ifdef FPGA_XILINX
// ============================================================================
//  XILINX: inference блочной памяти (Vivado сам выведет RAMB36E1/RAMB18E1)
// ============================================================================
module V_TrueDualPortRAM #(
    parameter integer WIDTH      = 32,
    // parameter integer DEPTH      = 16384,
    parameter integer ADDR_WIDTH = 14,
    parameter integer BYTE_SIZE  = 8,
    parameter         WRITE_MODE = "READ_FIRST",
    parameter         MEM_STYLE  = "block",
    parameter integer OUT_REG_A  = 1,
    parameter integer OUT_REG_B  = 1
) (
    input  wire                          clka,
    input  wire                          ena,
    input  wire [WIDTH/BYTE_SIZE-1:0]    wea,
    input  wire [$clog2(DEPTH)-1:0]      addra,
    input  wire [WIDTH-1:0]              dina,
    output reg  [WIDTH-1:0]              douta,

    input  wire                          clkb,
    input  wire                          enb,
    input  wire [WIDTH/BYTE_SIZE-1:0]    web,
    input  wire [$clog2(DEPTH)-1:0]      addrb,
    input  wire [WIDTH-1:0]              dinb,
    output reg  [WIDTH-1:0]              doutb
);

    // localparam integer ADDR_WIDTH = $clog2(DEPTH);
    localparam integer DEPTH    = 1 << ADDR_WIDTH;    // глубина
    localparam integer WE_WIDTH   = WIDTH / BYTE_SIZE;

    (* ram_style = MEM_STYLE *)
    reg [WIDTH-1:0] ram [0:DEPTH-1];

    integer i;

    // ---- Порт A ----
    always @(posedge clka) begin
        if (ena) begin

            // -------- Запись по байтам --------
            for (i = 0; i < WE_WIDTH; i = i + 1) begin
                if (wea[i]) ram[addra][i*BYTE_SIZE+:BYTE_SIZE] <= dina[i*BYTE_SIZE+:BYTE_SIZE];
            end

            // -------- Чтение с учётом режима --------
            case (WRITE_MODE)
                "WRITE_FIRST": begin
                    // при записи на выход идут новые данные (bypass)
                    if (wea != {WE_WIDTH{1'b0}})
                        douta <= dina;
                    else
                        douta <= ram[addra];
                end

                "READ_FIRST" : begin
                    // всегда читаем. Non-blocking гарантирует, что
                    // прочитается старое значение (до записи)
                    douta <= ram[addra];
                end

                "NO_CHANGE"  : begin
                    // во время записи выход не меняется вовсе
                    if (wea == {WE_WIDTH{1'b0}})
                        douta <= ram[addra];
                    // иначе douta держит прежнее значение
                end

                default      : douta <= ram[addra];
            endcase
        end
    end

    // ---- Порт B ----
    always @(posedge clkb) begin
        if (enb) begin

            // -------- Запись по байтам --------
            for (i = 0; i < WE_WIDTH; i = i + 1) begin
                if (web[i]) ram[addrb][i*BYTE_SIZE+:BYTE_SIZE] <= dinb[i*BYTE_SIZE+:BYTE_SIZE];
            end

            // -------- Чтение с учётом режима --------
            case (WRITE_MODE)
                "WRITE_FIRST": begin
                    // при записи на выход идут новые данные (bypass)
                    if (web != {WE_WIDTH{1'b0}})
                        doutb <= dinb;
                    else
                        doutb <= ram[addrb];
                end

                "READ_FIRST" : begin
                    // всегда читаем. Non-blocking гарантирует, что
                    // прочитается старое значение (до записи)
                    doutb <= ram[addrb];
                end

                "NO_CHANGE"  : begin
                    // во время записи выход не меняется вовсе
                    if (web == {WE_WIDTH{1'b0}})
                        doutb <= ram[addrb];
                    // иначе doutb держит прежнее значение
                end

                default      : doutb <= ram[addrb];
            endcase
        end
    end

endmodule


`elsif FPGA_INTEL
// ============================================================================
//  INTEL: явное инстанцирование примитива altera_syncram
//         (Quartus сам не выводит TDP с двумя клоками — используем примитив)
// ============================================================================
module V_TrueDualPortRAM #(
    parameter integer WIDTH      = 32,
    // parameter integer DEPTH      = 16384,
    parameter integer ADDR_WIDTH = 14,
    parameter integer BYTE_SIZE  = 8,
    parameter         WRITE_MODE = "READ_FIRST",
    parameter         MEM_STYLE  = "M20K",   // "M20K" / "M10K" / "MLAB"
    parameter integer OUT_REG_A  = 1,
    parameter integer OUT_REG_B  = 1
) (
    input  wire                          clka,
    input  wire                          ena,
    input  wire [WIDTH/BYTE_SIZE-1:0]    wea,
    input  wire [$clog2(DEPTH)-1:0]      addra,
    input  wire [WIDTH-1:0]              dina,
    output wire [WIDTH-1:0]              douta,

    input  wire                          clkb,
    input  wire                          enb,
    input  wire [WIDTH/BYTE_SIZE-1:0]    web,
    input  wire [$clog2(DEPTH)-1:0]      addrb,
    input  wire [WIDTH-1:0]              dinb,
    output wire [WIDTH-1:0]              doutb
);

    // localparam integer ADDR_WIDTH = $clog2(DEPTH);
    localparam integer DEPTH    = 1 << ADDR_WIDTH;    // глубина
    localparam integer WE_WIDTH   = WIDTH / BYTE_SIZE;

// Режим "во время записи"

// В документации Intel указано, что для памяти в режиме bidir_dual_port (True Dual-Port)
// с типом блока M20K аппаратно поддерживаются только два варианта поведения при одновременном чтении и записи в один адрес:

// NEW_DATA_NO_NBE_READ — на выходе появляются новые записываемые данные (аналог WRITE_FIRST)
// DONT_CARE — выходное значение не определено (аналог NO_CHANGE, но без гарантии удержания)
// Режим OLD_DATA (аналог READ_FIRST) для M20K в True Dual-Port не поддерживается на аппаратном уровне.
// Он доступен только для простого двухпортового режима (simple dual-port) или для других типов блоков (например, MLAB)

    localparam RDW_MODE_A = (WRITE_MODE == "WRITE_FIRST") ? "NEW_DATA_NO_NBE_READ" :
                                                        "DONT_CARE";

    // Выходные регистры портов A и B
    localparam OUT_REG_A_STR = (OUT_REG_A == 1) ? "CLOCK0" : "UNREGISTERED";
    localparam OUT_REG_B_STR = (OUT_REG_B == 1) ? "CLOCK1" : "UNREGISTERED";

    altera_syncram #(
        .address_reg_b                    ("CLOCK1"),
        .byteena_reg_b                    ("CLOCK1"),
        .byte_size                        (BYTE_SIZE),
        .clock_enable_input_a             ("BYPASS"),
        .clock_enable_input_b             ("BYPASS"),
        .clock_enable_output_a            ("BYPASS"),
        .clock_enable_output_b            ("BYPASS"),
        .indata_reg_b                     ("CLOCK1"),
        .enable_force_to_zero             ("FALSE"),
        .intended_device_family           ("Cyclone 10 GX"),
        .lpm_type                         ("altera_syncram"),
        .numwords_a                       (DEPTH),
        .numwords_b                       (DEPTH),
        .operation_mode                   ("BIDIR_DUAL_PORT"),
        .outdata_aclr_a                   ("NONE"),
        .outdata_sclr_a                   ("NONE"),
        .outdata_aclr_b                   ("NONE"),
        .outdata_sclr_b                   ("NONE"),
        .outdata_reg_a                    (OUT_REG_A_STR),
        .outdata_reg_b                    (OUT_REG_B_STR),
        .power_up_uninitialized           ("FALSE"),
        .ram_block_type                   (MEM_STYLE),
        .read_during_write_mode_port_a    (RDW_MODE_A),
        .read_during_write_mode_port_b    (RDW_MODE_A),
        .widthad_a                        (ADDR_WIDTH),
        .widthad_b                        (ADDR_WIDTH),
        .width_a                          (WIDTH),
        .width_b                          (WIDTH),
        .width_byteena_a                  (WE_WIDTH),
        .width_byteena_b                  (WE_WIDTH)
    ) altera_syncram_component (
        .address_a       (addra),
        .address_b       (addrb),
        .byteena_a       (wea),
        .byteena_b       (web),
        .clock0          (clka),
        .clock1          (clkb),
        .data_a          (dina),
        .data_b          (dinb),
        .wren_a          (|wea),      // общий write-enable для порта A
        .wren_b          (|web),      // общий write-enable для порта B
        .q_a             (douta),
        .q_b             (doutb),
        .aclr0           (1'b0),
        .aclr1           (1'b0),
        .address2_a      (1'b1),
        .address2_b      (1'b1),
        .addressstall_a  (1'b0),
        .addressstall_b  (1'b0),
        .clocken0        (ena),       // ena/enb работают как clock enable
        .clocken1        (enb),
        .clocken2        (1'b1),
        .clocken3        (1'b1),
        .eccencbypass    (1'b0),
        .eccencparity    (8'b0),
        .eccstatus       (),
        .rden_a          (1'b1),
        .rden_b          (1'b1),
        .sclr            (1'b0)
    );

endmodule


`else
    `error "Не задан вендор FPGA: определите `FPGA_XILINX` или `FPGA_INTEL` в начале файла"
`endif
