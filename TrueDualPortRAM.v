// ============================================================================
//  Параметризуемый True Dual Port RAM
//  - WIDTH      : разрядность данных (должна быть кратна BYTE_SIZE)
//  - DEPTH      : глубина (число слов)
//  - BYTE_SIZE  : размер "байта" для byte-write (8 или 9)
//  - WRITE_MODE : "WRITE_FIRST" | "READ_FIRST" | "NO_CHANGE"
//  - MEM_STYLE  : "block" | "distributed" | "ultra" | "auto"
//  - OUT_REG_A/B: 0 - без выходного регистра, 1 - с регистром (read latency 1)
//  - ADDR_WIDTH : вычисляется автоматически как clog2(DEPTH)
// ============================================================================
module TrueDualPortRAM #(
    parameter integer WIDTH      = 36,
    // parameter integer DEPTH      = 16384,
    parameter integer ADDR_WIDTH = 14,
    parameter integer BYTE_SIZE  = 9,
    parameter         WRITE_MODE = "READ_FIRST",
    parameter         MEM_STYLE  = "block",
    parameter integer OUT_REG_A  = 1,
    parameter integer OUT_REG_B  = 1
) (
    // -------------------- Порт A --------------------
    input  wire                  clka,
    input  wire                  ena,
    input  wire [  WE_WIDTH-1:0] wea,
    input  wire [ADDR_WIDTH-1:0] addra,
    input  wire [     WIDTH-1:0] dina,
    output reg  [     WIDTH-1:0] douta,

    // -------------------- Порт B --------------------
    input  wire                  clkb,
    input  wire                  enb,
    input  wire [  WE_WIDTH-1:0] web,
    input  wire [ADDR_WIDTH-1:0] addrb,
    input  wire [     WIDTH-1:0] dinb,
    output reg  [     WIDTH-1:0] doutb
);

//   // Функция вычисления разрядности адреса
//   function integer clog2;
//     input integer value;
//     integer i;
//     begin
//       clog2 = 1;
//       for (i = 0; (2 ** i) < value; i = i + 1) clog2 = i + 1;
//     end
//   endfunction

  // ------------------------------------------------------------------
  //  Производные параметры
  // ------------------------------------------------------------------
  // localparam integer ADDR_WIDTH = clog2(DEPTH);       // ширина адреса
  localparam integer DEPTH    = 1 << ADDR_WIDTH;    // глубина
  localparam integer WE_WIDTH = WIDTH / BYTE_SIZE;  // число байт в слове

  // ------------------------------------------------------------------
  //  Массив памяти
  // ------------------------------------------------------------------
  (* ram_style = MEM_STYLE *)
  reg [WIDTH-1:0] ram[0:DEPTH-1];

  // ------------------------------------------------------------------
  //  Промежуточные регистры для варианта "без выходного регистра"
  // ------------------------------------------------------------------
  reg [WIDTH-1:0] mem_out_a;
  reg [WIDTH-1:0] mem_out_b;

  integer i;

  // ------------------------------------------------------------------
  //  Порт A
  // ------------------------------------------------------------------
  always @(posedge clka) begin
    if (ena) begin

      // -------- Запись по байтам --------
      for (i = 0; i < WE_WIDTH; i = i + 1) begin
        if (wea[i]) ram[addra][i*BYTE_SIZE+:BYTE_SIZE] <= dina[i*BYTE_SIZE+:BYTE_SIZE];
      end

      // -------- Чтение с учётом режима записи --------
      case (WRITE_MODE)
        "WRITE_FIRST": mem_out_a <= ram[addra];  // новые данные видны сразу
        "READ_FIRST":  mem_out_a <= ram[addra];  // старые данные (для асинхр.)
        "NO_CHANGE": begin
          if (wea == {WE_WIDTH{1'b0}}) mem_out_a <= ram[addra];
          // иначе mem_out_a сохраняет прежнее значение
        end
        default:       mem_out_a <= ram[addra];
      endcase
    end
  end

  // ------------------------------------------------------------------
  //  Порт B
  // ------------------------------------------------------------------
  always @(posedge clkb) begin
    if (enb) begin

      for (i = 0; i < WE_WIDTH; i = i + 1) begin
        if (web[i]) ram[addrb][i*BYTE_SIZE+:BYTE_SIZE] <= dinb[i*BYTE_SIZE+:BYTE_SIZE];
      end

      case (WRITE_MODE)
        "WRITE_FIRST": mem_out_b <= ram[addrb];
        "READ_FIRST":  mem_out_b <= ram[addrb];
        "NO_CHANGE": begin
          if (web == {WE_WIDTH{1'b0}}) mem_out_b <= ram[addrb];
        end
        default:       mem_out_b <= ram[addrb];
      endcase
    end
  end

  // ------------------------------------------------------------------
  //  Выходной регистр (опционально)
  // ------------------------------------------------------------------
  generate
    if (OUT_REG_A == 1) begin : g_outreg_a
      always @(posedge clka) begin
        if (ena) douta <= mem_out_a;
      end
    end else begin : g_noreg_a
      always @(*) douta = mem_out_a;
    end
  endgenerate

  generate
    if (OUT_REG_B == 1) begin : g_outreg_b
      always @(posedge clkb) begin
        if (enb) doutb <= mem_out_b;
      end
    end else begin : g_noreg_b
      always @(*) doutb = mem_out_b;
    end
  endgenerate

endmodule
