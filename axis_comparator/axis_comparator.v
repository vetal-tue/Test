`timescale 1ns / 1ps

module axis_comparator #(
    parameter DATA_WIDTH  = 32,
    parameter KEEP_WIDTH  = DATA_WIDTH / 8,
    parameter KEEP_ENABLE = 1
) (
    input wire clk,
    input wire rst_n,

    input wire select,  // 0 - Master 0, 1 - Master 1

    // AXIS Slave 0 (вход от Master 0)
    input  wire [DATA_WIDTH-1:0] s0_tdata,
    input  wire [KEEP_WIDTH-1:0] s0_tkeep,
    input  wire                  s0_tvalid,
    input  wire                  s0_tuser,
    output wire                  s0_tready,
    input  wire                  s0_tlast,

    // AXIS Slave 1 (вход от Master 1)
    input  wire [DATA_WIDTH-1:0] s1_tdata,
    input  wire [KEEP_WIDTH-1:0] s1_tkeep,
    input  wire                  s1_tvalid,
    input  wire                  s1_tuser,
    output wire                  s1_tready,
    input  wire                  s1_tlast,

    // AXIS Master (выход на Slave)
    output wire [DATA_WIDTH-1:0] m_tdata,
    output wire [KEEP_WIDTH-1:0] m_tkeep,
    output wire                  m_tvalid,
    input  wire                  m_tready,
    output wire                  m_tlast,
    output wire                  m_tuser
);

  localparam STATE_PASS  = 1'b0;
  localparam STATE_FLUSH = 1'b1;

  reg state_reg, state_next;

  // Логика захвата select на время кадра
  reg  select_reg;
  reg  frame_reg;  // 1 - находимся внутри передачи кадра
  wire current_select = frame_reg ? select_reg : select;

  // Флаги ожидания завершения кадров (tlast) при аварийном сбросе
  reg flush_s0_reg, flush_s0_next;
  reg flush_s1_reg, flush_s1_next;

  // Внутренний AXIS-интерфейс между FSM и Alex Forencich Output Buffer
  reg [DATA_WIDTH-1:0] int_tdata;
  reg [KEEP_WIDTH-1:0] int_tkeep;
  reg int_tvalid;
  wire                 int_tready; // Зарегистрированный сигнал ready для внутренней логики
  reg int_tlast;
  reg int_tuser;

  // --------------------------------------------------------------------
  // Регистры выходного пути
  // --------------------------------------------------------------------
  reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
  reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg = {KEEP_WIDTH{1'b1}};
  reg m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
  reg                  m_axis_tlast_reg = 1'b0;
  reg                  m_axis_tuser_reg = 1'b0;

  reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
  reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg = {KEEP_WIDTH{1'b1}};
  reg temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
  reg  temp_m_axis_tlast_reg = 1'b0;
  reg  temp_m_axis_tuser_reg = 1'b0;

  // Зарегистрированный и опережающий (early) сигналы ready для входной части буфера
  reg  int_tready_reg = 1'b0;
  wire int_tready_early;

  // Управляющие сигналы пересылки между регистрами
  reg  store_axis_int_to_output;
  reg  store_axis_int_to_temp;
  reg  store_axis_temp_to_output;

  // Выходы модуля
  assign m_tdata = m_axis_tdata_reg;
  assign m_tkeep = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
  assign m_tvalid = m_axis_tvalid_reg;
  assign m_tlast = m_axis_tlast_reg;
  assign m_tuser = m_axis_tuser_reg;

  assign int_tready = int_tready_reg;

  // --------------------------------------------------------------------
  // Сравнение и управляющий автомат (FSM)
  // --------------------------------------------------------------------
  wire both_valid = s0_tvalid & s1_tvalid;

  // Проверка совпадения данных и tkeep
  wire data_match = (s0_tdata == s1_tdata);
  wire keep_match = KEEP_ENABLE ? (s0_tkeep == s1_tkeep) : 1'b1;
  wire match = data_match && keep_match && !(s0_tuser || s1_tuser);

  // Входные ready-сигналы определяются триггером int_tready_reg
  // (нет связи с m_tready!)
  assign s0_tready = (state_reg == STATE_PASS) ? (s1_tvalid && int_tready) : flush_s0_reg;
  assign s1_tready = (state_reg == STATE_PASS) ? (s0_tvalid && int_tready) : flush_s1_reg;

  always @(*) begin
    state_next    = state_reg;
    flush_s0_next = flush_s0_reg;
    flush_s1_next = flush_s1_reg;

    int_tvalid = 1'b0;
    int_tdata  = current_select ? s1_tdata : s0_tdata;
    int_tkeep  = KEEP_ENABLE ? (current_select ? s1_tkeep : s0_tkeep) : {KEEP_WIDTH{1'b1}};
    int_tlast  = 1'b0;
    int_tuser  = 1'b0;

    case (state_reg)
      STATE_PASS: begin
        if (both_valid) begin
          int_tvalid = 1'b1;
          int_tlast  = (!match) || s0_tlast || s1_tlast;
          int_tuser  = !match;

          if (int_tready) begin
            if (!match || s0_tlast || s1_tlast) begin
              if (!s0_tlast) flush_s0_next = 1'b1;
              if (!s1_tlast) flush_s1_next = 1'b1;

              if (!s0_tlast || !s1_tlast) begin
                state_next = STATE_FLUSH;
              end
            end
          end
        end
      end

      STATE_FLUSH: begin
        int_tvalid = 1'b0;

        if (flush_s0_reg && s0_tvalid && s0_tlast) flush_s0_next = 1'b0;

        if (flush_s1_reg && s1_tvalid && s1_tlast) flush_s1_next = 1'b0;

        if (!flush_s0_next && !flush_s1_next) state_next = STATE_PASS;
      end
    endcase
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_reg    <= STATE_PASS;
      flush_s0_reg <= 1'b0;
      flush_s1_reg <= 1'b0;
      select_reg   <= 1'b0;
      frame_reg    <= 1'b0;
    end else begin
      state_reg    <= state_next;
      flush_s0_reg <= flush_s0_next;
      flush_s1_reg <= flush_s1_next;

      if (state_reg == STATE_PASS) begin
        if (both_valid && int_tready) begin
          if (!frame_reg) begin
            select_reg <= select;
          end
          frame_reg <= !int_tlast;
        end
      end else begin
        frame_reg <= 1'b0;
      end
    end
  end

  // --------------------------------------------------------------------
  // Точная реализация Skid Buffer (Alex Forencich)
  // --------------------------------------------------------------------
  // Разрешение на прием данных в следующем такте:
  // если выход готов ИЛИ временный регистр не заполнится на следующем такте
  assign int_tready_early = m_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !int_tvalid));

  always @(*) begin
    m_axis_tvalid_next        = m_axis_tvalid_reg;
    temp_m_axis_tvalid_next   = temp_m_axis_tvalid_reg;

    store_axis_int_to_output  = 1'b0;
    store_axis_int_to_temp    = 1'b0;
    store_axis_temp_to_output = 1'b0;

    if (int_tready_reg) begin
      if (m_tready || !m_axis_tvalid_reg) begin
        m_axis_tvalid_next       = int_tvalid;
        store_axis_int_to_output = 1'b1;
      end else begin
        temp_m_axis_tvalid_next = int_tvalid;
        store_axis_int_to_temp  = 1'b1;
      end
    end else if (m_tready) begin
      m_axis_tvalid_next        = temp_m_axis_tvalid_reg;
      temp_m_axis_tvalid_next   = 1'b0;
      store_axis_temp_to_output = 1'b1;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      m_axis_tvalid_reg      <= 1'b0;
      temp_m_axis_tvalid_reg <= 1'b0;
      temp_m_axis_tvalid_reg <= 1'b0;
      int_tready_reg         <= 1'b0;
    end else begin
      m_axis_tvalid_reg      <= m_axis_tvalid_next;
      temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;
      int_tready_reg         <= int_tready_early;
    end
  end

  always @(posedge clk) begin
    if (store_axis_int_to_output) begin
      m_axis_tdata_reg <= int_tdata;
      m_axis_tkeep_reg <= int_tkeep;
      m_axis_tlast_reg <= int_tlast;
      m_axis_tuser_reg <= int_tuser;
    end else if (store_axis_temp_to_output) begin
      m_axis_tdata_reg <= temp_m_axis_tdata_reg;
      m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
      m_axis_tlast_reg <= temp_m_axis_tlast_reg;
      m_axis_tuser_reg <= temp_m_axis_tuser_reg;
    end

    if (store_axis_int_to_temp) begin
      temp_m_axis_tdata_reg <= int_tdata;
      temp_m_axis_tkeep_reg <= int_tkeep;
      temp_m_axis_tlast_reg <= int_tlast;
      temp_m_axis_tuser_reg <= int_tuser;
    end
  end

endmodule
