Есть N AXIS-master и один AXIS-slave. Пусть N=2. Вот как на схеме ниже:

```
                  ┌──────────────────────┐
AXIS MASTER 0 ───►│                      │
                  │                      │
                  │  2x AXIS comparator  ├──► AXIS OUT
                  │                      │
AXIS MASTER 1 ───►│                      │
                  └──────────────────────┘
```

Надо разработать Verilog-модуль, который будет передавать данные в AXIS-slave с того master, который выбирается входным портом select, но при этом каждое слово должен сравнивать со словом от другого master и если они не равны - прерывать выдачу на AXIS-slave, корректно завершить ее через tlast. Далее дождаться завершения кадра от AXIS-master'ов и далее в IDLE быть готовым к новому кадру. Разрядность данных должна быть параметризуемая через  "parameter DATA_WIDTH". Скорости AXIS-master'ов могут быть разные.


---

- **Двухуровневая регистрация выхода (Alex Forencich Pattern)**: Использование основного регистра (`m_axis_*_reg`) и временного регистра (`temp_m_axis_*_reg`). Это полностью рвет комбинационные пути с входов на выходы, поддерживает максимальную пропускную способность (1 слово/такт) и корректно обрабатывает противодавление (`m_tready = 0`).

- **Фиксация `select` на время кадра**: Вход `select` опрашивается и сохраняется в `select_reg` при приеме первого слова кадра (`frame_reg == 0`). Пока кадр не завершится по `tlast` (или не упрется в аварийную очистку FLUSH), изменения на входе `select` полностью игнорируются.

```Verilog
`default_nettype none
`timescale 1ns / 1ps

module axis_comparator #(
    parameter DATA_WIDTH = 32
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   select, // 0 - Master 0, 1 - Master 1

    // AXIS Slave 0 (вход от Master 0)
    input  wire [DATA_WIDTH-1:0]  s0_tdata,
    input  wire                   s0_tvalid,
    output wire                   s0_tready,
    input  wire                   s0_tlast,

    // AXIS Slave 1 (вход от Master 1)
    input  wire [DATA_WIDTH-1:0]  s1_tdata,
    input  wire                   s1_tvalid,
    output wire                   s1_tready,
    input  wire                   s1_tlast,

    // AXIS Master (выход на Slave)
    output wire [DATA_WIDTH-1:0]  m_tdata,
    output wire                   m_tvalid,
    input  wire                   m_tready,
    output wire                   m_tlast
);

    localparam STATE_PASS  = 1'b0;
    localparam STATE_FLUSH = 1'b1;

    reg state_reg, state_next;

    // Логика захвата select на время кадра
    reg select_reg;
    reg frame_reg; // 1 - находимся внутри передачи кадра
    wire current_select = frame_reg ? select_reg : select;

    // Флаги ожидания завершения кадров (tlast) при аварийном сбросе
    reg flush_s0_reg, flush_s0_next;
    reg flush_s1_reg, flush_s1_next;

    // Внутренний AXIS-интерфейс перед выходом в output datapath
    reg [DATA_WIDTH-1:0] int_tdata;
    reg                  int_tvalid;
    wire                 int_tready;
    reg                  int_tlast;

    // --------------------------------------------------------------------
    // Регистры выходного пути
    // --------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                  m_axis_tlast_reg = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg                  temp_m_axis_tlast_reg = 1'b0;

    // Управляющие сигналы пересылки между регистрами
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    // Выходы модуля
    assign m_tdata  = m_axis_tdata_reg;
    assign m_tvalid = m_axis_tvalid_reg;
    assign m_tlast  = m_axis_tlast_reg;

    // --------------------------------------------------------------------
    // Сравнение и управляющий автомат (FSM)
    // --------------------------------------------------------------------
    wire both_valid = s0_tvalid & s1_tvalid;
    wire data_match = (s0_tdata == s1_tdata);

    // Входные ready-сигналы
    assign s0_tready = (state_reg == STATE_PASS) ? (both_valid && int_tready) : flush_s0_reg;
    assign s1_tready = (state_reg == STATE_PASS) ? (both_valid && int_tready) : flush_s1_reg;

    always @(*) begin
        state_next    = state_reg;
        flush_s0_next = flush_s0_reg;
        flush_s1_next = flush_s1_reg;

        int_tvalid = 1'b0;
        int_tdata  = current_select ? s1_tdata : s0_tdata;
        int_tlast  = 1'b0;

        case (state_reg)
            STATE_PASS: begin
                if (both_valid) begin
                    int_tvalid = 1'b1;
                    // Прерываем кадр (выдаем tlast=1), если данные 
                    // не совпали или один из кадров завершился раньше
                    int_tlast  = (!data_match) || s0_tlast || s1_tlast;

                    if (int_tready) begin
                        // При расхождении или раннем tlast 
                        // переходим в режим FLUSH
                        if (!data_match || s0_tlast || s1_tlast) begin
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
                int_tvalid = 1'b0; // В режиме сброса ничего 
						           // не пишем на выход

                if (flush_s0_reg && s0_tvalid && s0_tlast) begin
                    flush_s0_next = 1'b0;
                end

                if (flush_s1_reg && s1_tvalid && s1_tlast) begin
                    flush_s1_next = 1'b0;
                end

                // Как только оба мастера выдали tlast — возвращаемся в PASS
                if (!flush_s0_next && !flush_s1_next) begin
                    state_next = STATE_PASS;
                end
            end
        endcase
    end

    // Регистры автомата, фиксации select и состояния кадра
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
                    // Фиксируем select на первом слове кадра
                    if (!frame_reg) begin
                        select_reg <= select;
                    end
                    // Удерживаем frame_reg до тех пор, 
                    // пока не встретим tlast
                    frame_reg <= !int_tlast;
                end
            end else begin
                frame_reg <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------------------
    // Логика двухступенчатого выходного буфера
    // --------------------------------------------------------------------
    assign int_tready = store_axis_int_to_output || store_axis_int_to_temp;

    always @(*) begin
        store_axis_int_to_output   = 1'b0;
        store_axis_int_to_temp     = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_tready) begin
            if (temp_m_axis_tvalid_reg) begin
                store_axis_temp_to_output = 1'b1;
                store_axis_int_to_temp     = 1'b1;
            end else begin
                store_axis_int_to_output   = 1'b1;
            end
        end else begin
            if (m_axis_tvalid_reg) begin
                if (!temp_m_axis_tvalid_reg) begin
                    store_axis_int_to_temp = 1'b1;
                end
            end else begin
                store_axis_int_to_output   = 1'b1;
            end
        end
    end

    always @(*) begin
        m_axis_tvalid_next      = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        if (store_axis_temp_to_output) begin
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        end else if (store_axis_int_to_output) begin
            m_axis_tvalid_next = int_tvalid;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tvalid_next = int_tvalid;
        end else if (store_axis_temp_to_output) begin
            temp_m_axis_tvalid_next = 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid_reg      <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end else begin
            m_axis_tvalid_reg      <= m_axis_tvalid_next;
            temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;
        end
    end

    always @(posedge clk) begin
        if (store_axis_int_to_output) begin
            m_axis_tdata_reg <= int_tdata;
            m_axis_tlast_reg <= int_tlast;
        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tdata_reg <= int_tdata;
            temp_m_axis_tlast_reg <= int_tlast;
        end
    end

endmodule
`resetall

```

### Архитектурные особенности решения:

1. **Отсутствие комбинированных задержек на выходе**: Все сигналы интерфейса `m_*` (`tdata`, `tvalid`, `tlast`) являются непосредственными выходами триггеров (`m_axis_*_reg`).

2. **Захват порта `select`**: Сигнал `current_select` выбирает значение с входного порта `select`, когда мы находимся вне кадра (`frame_reg == 0`). В момент рукопожатия первого слова кадра значения `select` перезаписывается в `select_reg`, а `frame_reg` поднимается в `1`. Со второго слова используется значение `select_reg`.

3. **Бесшовный буфер `temp_m_axis`**: Если _downstream_ приемник снизу сбрасывает `m_tready = 0`, текущее слово из автомата оседает во временном регистре `temp_m_axis_*_reg`, а `s0_tready`/`s1_tready` отключаются только тогда, когда заполнены и основной, и временный регистры.

---

Если количество входных мастеров N хочется задать через параметр `parameter PORTS = 2;`, то код будет такой:

```Verilog
`default_nettype none
`timescale 1ns / 1ps

module axis_comparator #(
    parameter PORTS      = 2,
    parameter DATA_WIDTH = 32
)(
    input  wire                               clk,
    input  wire                               rst_n,

    // Определяем ширину шины select на основе количества портов
    input  wire [((PORTS > 1) ? $clog2(PORTS) - 1 : 0):0] select,

    // AXIS Slaves (входы от N Master'ов, объединенные в плоские шины)
    input  wire [PORTS*DATA_WIDTH-1:0]        s_tdata,
    input  wire [PORTS-1:0]                   s_tvalid,
    output wire [PORTS-1:0]                   s_tready,
    input  wire [PORTS-1:0]                   s_tlast,

    // AXIS Master (выход на Slave)
    output wire [DATA_WIDTH-1:0]              m_tdata,
    output wire                               m_tvalid,
    input  wire                               m_tready,
    output wire                               m_tlast
);

    localparam SELECT_WIDTH = (PORTS > 1) ? $clog2(PORTS) : 1;

    localparam STATE_PASS  = 1'b0;
    localparam STATE_FLUSH = 1'b1;

    reg state_reg, state_next;

    // Логика захвата select на время кадра
    reg [SELECT_WIDTH-1:0] select_reg;
    reg                    frame_reg; // 1 - находимся внутри передачи кадра
    wire [SELECT_WIDTH-1:0] current_select = frame_reg ? select_reg : select;

    // Флаги ожидания завершения кадров (tlast) при аварийном сбросе
    reg  [PORTS-1:0] flush_reg, flush_next;

    // Внутренний AXIS-интерфейс перед выходом
    reg [DATA_WIDTH-1:0] int_tdata;
    reg                  int_tvalid;
    wire                 int_tready;
    reg                  int_tlast;

    // --------------------------------------------------------------------
    // Выходные регистры (Alex Forencich Output Register Pattern)
    // --------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                  m_axis_tlast_reg = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg                  temp_m_axis_tlast_reg = 1'b0;

    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    assign m_tdata  = m_axis_tdata_reg;
    assign m_tvalid = m_axis_tvalid_reg;
    assign m_tlast  = m_axis_tlast_reg;

    // --------------------------------------------------------------------
    // Сравнение N портов и управляющий автомат
    // --------------------------------------------------------------------
    wire all_valid = &s_tvalid;
    wire any_tlast = |s_tlast;
    wire all_tlast = &s_tlast;

    reg data_match;
    integer i;

    // Сравниваем данные со всех портов с нулевым портом
    always @(*) begin
        data_match = 1'b1;
        for (i = 1; i < PORTS; i = i + 1) begin
            if (s_tdata[i*DATA_WIDTH +: DATA_WIDTH] != s_tdata[0 +: DATA_WIDTH]) begin
                data_match = 1'b0;
            end
        end
    end

    // Входные ready-сигналы для каждого порта
    genvar j;
    generate
        for (j = 0; j < PORTS; j = j + 1) begin : gen_ready
            assign s_tready[j] = (state_reg == STATE_PASS) ? (all_valid && int_tready) : flush_reg[j];
        end
    endgenerate

    always @(*) begin
        state_next = state_reg;
        flush_next = flush_reg;

        int_tvalid = 1'b0;
        
        // Мультиплексирование выбранного канала
        if (current_select < PORTS) begin
            int_tdata = s_tdata[current_select * DATA_WIDTH +: DATA_WIDTH];
        end else begin
            int_tdata = {DATA_WIDTH{1'b0}}; // Защита от выхода за пределы
        end
        
        int_tlast  = 1'b0;

        case (state_reg)
            STATE_PASS: begin
                if (all_valid) begin
                    int_tvalid = 1'b1;
                    // Прерываем кадр, если данные не совпали или 
                    // ХОТЯ БЫ один из кадров завершился
                    int_tlast  = (!data_match) || any_tlast;

                    if (int_tready) begin
                        // Переход во FLUSH, если есть несовпадение 
                        // данных или не все кадры завершились синхронно
                        if (!data_match || !all_tlast) begin
                            state_next = STATE_FLUSH;
                            for (i = 0; i < PORTS; i = i + 1) begin
                                flush_next[i] = !s_tlast[i];
                            end
                        end
                    end
                end
            end

            STATE_FLUSH: begin
                int_tvalid = 1'b0;

                for (i = 0; i < PORTS; i = i + 1) begin
                    if (flush_reg[i] && s_tvalid[i] && s_tlast[i]) begin
                        flush_next[i] = 1'b0;
                    end
                end

                if (flush_next == {PORTS{1'b0}}) begin
                    state_next = STATE_PASS;
                end
            end
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg  <= STATE_PASS;
            flush_reg  <= {PORTS{1'b0}};
            select_reg <= {SELECT_WIDTH{1'b0}};
            frame_reg  <= 1'b0;
        end else begin
            state_reg <= state_next;
            flush_reg <= flush_next;

            if (state_reg == STATE_PASS) begin
                if (all_valid && int_tready) begin
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
    // Логика двухступенчатого выходного буфера
    // --------------------------------------------------------------------
    assign int_tready = store_axis_int_to_output || store_axis_int_to_temp;

    always @(*) begin
        store_axis_int_to_output  = 1'b0;
        store_axis_int_to_temp    = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_tready) begin
            if (temp_m_axis_tvalid_reg) begin
                store_axis_temp_to_output = 1'b1;
                store_axis_int_to_temp    = 1'b1;
            end else begin
                store_axis_int_to_output  = 1'b1;
            end
        end else begin
            if (m_axis_tvalid_reg) begin
                if (!temp_m_axis_tvalid_reg) begin
                    store_axis_int_to_temp = 1'b1;
                end
            end else begin
                store_axis_int_to_output  = 1'b1;
            end
        end
    end

    always @(*) begin
        m_axis_tvalid_next      = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        if (store_axis_temp_to_output) begin
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        end else if (store_axis_int_to_output) begin
            m_axis_tvalid_next = int_tvalid;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tvalid_next = int_tvalid;
        end else if (store_axis_temp_to_output) begin
            temp_m_axis_tvalid_next = 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid_reg      <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end else begin
            m_axis_tvalid_reg      <= m_axis_tvalid_next;
            temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;
        end
    end

    always @(posedge clk) begin
        if (store_axis_int_to_output) begin
            m_axis_tdata_reg <= int_tdata;
            m_axis_tlast_reg <= int_tlast;
        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tdata_reg <= int_tdata;
            temp_m_axis_tlast_reg <= int_tlast;
        end
    end

endmodule
`resetall

```

---

версия Verilog-модуля на 2 AXIS-master'а с поддержкой `tkeep`, параметром `KEEP_ENABLE` и двухступенчатой регистрацией выходов.

В логику добавлены следующие изменения:

1. **Сравнение данных и `tkeep`**: При `KEEP_ENABLE = 1` проверяется не только равенство `tdata`, но и совпадение байтовых масок `tkeep`. При разной структуре байт кадр прерывается через `tlast`.

2. **Параметрический сброс**: Если `KEEP_ENABLE = 0`, сигнал `m_tkeep` заполняется всеми единицами (`1'b1`), а входы `s0_tkeep` / `s1_tkeep` игнорируются при сравнении.

```Verilog
`default_nettype none
`timescale 1ns / 1ps

module axis_comparator #(
    parameter DATA_WIDTH  = 32,
    parameter KEEP_WIDTH  = DATA_WIDTH / 8,
    parameter KEEP_ENABLE = 1
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   select, // 0 - Master 0, 1 - Master 1

    // AXIS Slave 0 (вход от Master 0)
    input  wire [DATA_WIDTH-1:0]  s0_tdata,
    input  wire [KEEP_WIDTH-1:0]  s0_tkeep,
    input  wire                   s0_tvalid,
    output wire                   s0_tready,
    input  wire                   s0_tlast,

    // AXIS Slave 1 (вход от Master 1)
    input  wire [DATA_WIDTH-1:0]  s1_tdata,
    input  wire [KEEP_WIDTH-1:0]  s1_tkeep,
    input  wire                   s1_tvalid,
    output wire                   s1_tready,
    input  wire                   s1_tlast,

    // AXIS Master (выход на Slave)
    output wire [DATA_WIDTH-1:0]  m_tdata,
    output wire [KEEP_WIDTH-1:0]  m_tkeep,
    output wire                   m_tvalid,
    input  wire                   m_tready,
    output wire                   m_tlast
);

    localparam STATE_PASS  = 1'b0;
    localparam STATE_FLUSH = 1'b1;

    reg state_reg, state_next;

    // Логика захвата select на время кадра
    reg select_reg;
    reg frame_reg; // 1 - находимся внутри передачи кадра
    wire current_select = frame_reg ? select_reg : select;

    // Флаги ожидания завершения кадров (tlast) при аварийном сбросе
    reg flush_s0_reg, flush_s0_next;
    reg flush_s1_reg, flush_s1_next;

    // Внутренний AXIS-интерфейс перед выходом в output datapath
    reg [DATA_WIDTH-1:0] int_tdata;
    reg [KEEP_WIDTH-1:0] int_tkeep;
    reg                  int_tvalid;
    wire                 int_tready;
    reg                  int_tlast;

    // --------------------------------------------------------------------
    // Регистры выходного пути
    // --------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg = {KEEP_WIDTH{1'b1}};
    reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                  m_axis_tlast_reg  = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg = {KEEP_WIDTH{1'b1}};
    reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg                  temp_m_axis_tlast_reg  = 1'b0;

    // Управляющие сигналы пересылки между регистрами
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    // Выходы модуля
    assign m_tdata  = m_axis_tdata_reg;
    assign m_tkeep  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_tvalid = m_axis_tvalid_reg;
    assign m_tlast  = m_axis_tlast_reg;

    // --------------------------------------------------------------------
    // Сравнение и управляющий автомат (FSM)
    // --------------------------------------------------------------------
    wire both_valid = s0_tvalid & s1_tvalid;
    
    // Проверка совпадения данных и tkeep (если tkeep включен)
    wire data_match = (s0_tdata == s1_tdata);
    wire keep_match = KEEP_ENABLE ? (s0_tkeep == s1_tkeep) : 1'b1;
    wire match      = data_match && keep_match;

    // Входные ready-сигналы
    assign s0_tready = (state_reg == STATE_PASS) ? (both_valid && int_tready) : flush_s0_reg;
    assign s1_tready = (state_reg == STATE_PASS) ? (both_valid && int_tready) : flush_s1_reg;

    always @(*) begin
        state_next    = state_reg;
        flush_s0_next = flush_s0_reg;
        flush_s1_next = flush_s1_reg;

        int_tvalid = 1'b0;
        int_tdata  = current_select ? s1_tdata : s0_tdata;
        int_tkeep  = KEEP_ENABLE ? (current_select ? s1_tkeep : s0_tkeep) : {KEEP_WIDTH{1'b1}};
        int_tlast  = 1'b0;

        case (state_reg)
            STATE_PASS: begin
                if (both_valid) begin
                    int_tvalid = 1'b1;
                    // Прерываем кадр (выдаем tlast=1), если данные/tkeep
                    // не совпали или хотя бы один кадр закончился
                    int_tlast  = (!match) || s0_tlast || s1_tlast;

                    if (int_tready) begin
                        // При расхождении или раннем tlast переходим 
                        // в режим FLUSH
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
                int_tvalid = 1'b0; // В режиме сброса ничего 
					               //не пишем на выход

                if (flush_s0_reg && s0_tvalid && s0_tlast) begin
                    flush_s0_next = 1'b0;
                end

                if (flush_s1_reg && s1_tvalid && s1_tlast) begin
                    flush_s1_next = 1'b0;
                end

                // Как только оба мастера выдали tlast — возвращаемся в PASS
                if (!flush_s0_next && !flush_s1_next) begin
                    state_next = STATE_PASS;
                end
            end
        endcase
    end

    // Регистры автомата, фиксации select и состояния кадра
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
                    // Фиксируем select на первом слове кадра
                    if (!frame_reg) begin
                        select_reg <= select;
                    end
                    // Удерживаем frame_reg до тех пор, пока 
                    // не встретим tlast
                    frame_reg <= !int_tlast;
                end
            end else begin
                frame_reg <= 1'b0;
            end
        end
    end

    // --------------------------------------------------------------------
    // Логика двухступенчатого выходного буфера
    // --------------------------------------------------------------------
    assign int_tready = store_axis_int_to_output || store_axis_int_to_temp;

    always @(*) begin
        store_axis_int_to_output   = 1'b0;
        store_axis_int_to_temp     = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (m_tready) begin
            if (temp_m_axis_tvalid_reg) begin
                store_axis_temp_to_output = 1'b1;
                store_axis_int_to_temp     = 1'b1;
            end else begin
                store_axis_int_to_output   = 1'b1;
            end
        end else begin
            if (m_axis_tvalid_reg) begin
                if (!temp_m_axis_tvalid_reg) begin
                    store_axis_int_to_temp = 1'b1;
                end
            end else begin
                store_axis_int_to_output   = 1'b1;
            end
        end
    end

    always @(*) begin
        m_axis_tvalid_next      = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        if (store_axis_temp_to_output) begin
            m_axis_tvalid_next = temp_m_axis_tvalid_reg;
        end else if (store_axis_int_to_output) begin
            m_axis_tvalid_next = int_tvalid;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tvalid_next = int_tvalid;
        end else if (store_axis_temp_to_output) begin
            temp_m_axis_tvalid_next = 1'b0;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid_reg      <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
        end else begin
            m_axis_tvalid_reg      <= m_axis_tvalid_next;
            temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;
        end
    end

    always @(posedge clk) begin
        if (store_axis_int_to_output) begin
            m_axis_tdata_reg <= int_tdata;
            m_axis_tkeep_reg <= int_tkeep;
            m_axis_tlast_reg <= int_tlast;
        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tdata_reg <= int_tdata;
            temp_m_axis_tkeep_reg <= int_tkeep;
            temp_m_axis_tlast_reg <= int_tlast;
        end
    end

endmodule
`resetall

```

В коде выше сделано не так, как Alex Forencich. **НЕ разорван регистрами m_tready и s_tready**

Главное отличие заключается в **комбинационных путях сигнала обратного давления (backpressure/tready)**.

### 1. Реализация Alex Forencich: Разрыв пути в обе стороны (Полная изоляция)

Код Forencich проектировался для достижения максимальных тактовых частот (Fmax) на FPGA. Он разрывает комбинационные пути не только вперед (`tdata`, `tvalid`), но и назад (`tready`).

Сигнал готовности, который отдается мастеру (внутренней логике) — это выход триггера:

```Verilog
always @(posedge clk) begin
    m_axis_tready_int_reg <= m_axis_tready_int_early; // <-- Это триггер!
```

Логика работает в два четких этапа, образуя классический Skid Buffer:

- **Торможение:** Если `m_axis_tready` (приемник) падает в `0`, внутренний мастер все еще видит `1` на один такт (т.к. это регистр). Он отправляет слово, которое «докатывается» (skid) и сохраняется во временный регистр `temp_m_axis`. В этот момент `m_axis_tready_int_early` оценивается в `0`, и на следующем такте мастер останавливается.

- **Возобновление (Цена изоляции):** Когда приемник снова выставляет `m_axis_tready = 1`, автомат Forencich перекладывает данные из `temp` в `output`. В этот конкретный такт внутренний мастер **все еще видит `0`** на своем `ready`, потому что триггер `m_axis_tready_int_reg` обновится только по фронту клока. Возникает 1 такт простоя (bubble) на входе при выходе из паузы. Это осознанный компромисс ради идеального физического синтеза.


### 2. Предыдущая реализация: Комбинационный путь tready

прямой путь (`tdata`, `tvalid`) разорван регистрами, но **сигнал `tready` проброшен комбинационно**:
```Verilog
// int_tready зависит от store_axis_int_to_temp, который комбинационно зависит от m_tready
assign int_tready = store_axis_int_to_output || store_axis_int_to_temp; 

always @(*) begin
    ...
    if (m_tready) begin
        if (temp_m_axis_tvalid_reg) begin
            store_axis_temp_to_output = 1'b1;
            store_axis_int_to_temp    = 1'b1; // <-- m_tready напрямую вызывает готовность входа!
        end
    ...
```

В этой реализации была попытка избежать "пузыря" в 1 такт при возобновлении передачи:

- Когда `m_tready` поднимается в `1`, а в `temp_reg` лежат данные, логика **в тот же такт** перекладывает `temp` на выход и одновременно дает разрешение (`int_tready = 1`) внутреннему мастеру записать новое слово в освобождающийся `temp_reg`.

- С точки зрения пропускной способности это работает без задержек. Но физически образуется длинный комбинационный путь: `m_tready` (вход модуля) -> `store_axis_int_to_temp` -> `int_tready` -> логика FSM автомата -> `s0_tready` (выход модуля).


### Итог и влияние на синтез

| **Характеристика**                 | **Alex Forencich**             | **предыдущий код**               |
| ---------------------------------- | ------------------------------ | -------------------------------- |
| **Путь `tdata`/`tvalid` (Вперед)** | Разорван регистрами            | Разорван регистрами              |
| **Путь `tready` (Назад)**          | **Разорван регистром**         | **Сплошной комбинационный путь** |
| **Выход из stall (паузы)**         | Задержка в 1 такт для upstream | Без задержек (в тот же такт)     |
| **Частотный потенциал (Fmax)**     | Максимальный                   | Снижен из-за комбинационной цепи |

Для высокопроизводительных архитектур (таких как Artix-7 или Cyclone 10 GX), где задержки трассировки сигналов управления между модулями могут стать "узким горлышком", подход Alex Forencich является эталонным. Оставление комбинационного пути от `m_tready` до `s_tready` *сводит на нет половину преимуществ буферизации выходов, так как синтезатор не сможет оптимизировать критический путь противодавления*.

Вот исправленная версия модуля `axis_comparator`. В ней выходной Skid Buffer полностью переведен на шаблон Alex Forencich: введен регистр `int_tready_reg` (`m_axis_tready_int_reg`), который **полностью разрывает комбинационный путь между `m_tready` и входными `s0_tready`/`s1_tready`**.

```Verilog
`timescale 1ns / 1ps

module axis_comparator #(
    parameter DATA_WIDTH  = 32,
    parameter KEEP_WIDTH  = DATA_WIDTH / 8,
    parameter KEEP_ENABLE = 1
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   select, // 0 - Master 0, 1 - Master 1

    // AXIS Slave 0 (вход от Master 0)
    input  wire [DATA_WIDTH-1:0]  s0_tdata,
    input  wire [KEEP_WIDTH-1:0]  s0_tkeep,
    input  wire                   s0_tvalid,
    output wire                   s0_tready,
    input  wire                   s0_tlast,

    // AXIS Slave 1 (вход от Master 1)
    input  wire [DATA_WIDTH-1:0]  s1_tdata,
    input  wire [KEEP_WIDTH-1:0]  s1_tkeep,
    input  wire                   s1_tvalid,
    output wire                   s1_tready,
    input  wire                   s1_tlast,

    // AXIS Master (выход на Slave)
    output wire [DATA_WIDTH-1:0]  m_tdata,
    output wire [KEEP_WIDTH-1:0]  m_tkeep,
    output wire                   m_tvalid,
    input  wire                   m_tready,
    output wire                   m_tlast
);

    localparam STATE_PASS  = 1'b0;
    localparam STATE_FLUSH = 1'b1;

    reg state_reg, state_next;

    // Логика захвата select на время кадра
    reg select_reg;
    reg frame_reg; // 1 - находимся внутри передачи кадра
    wire current_select = frame_reg ? select_reg : select;

    // Флаги ожидания завершения кадров (tlast) при аварийном сбросе
    reg flush_s0_reg, flush_s0_next;
    reg flush_s1_reg, flush_s1_next;

    // Внутренний AXIS-интерфейс между FSM и Alex Forencich Output Buffer
    reg [DATA_WIDTH-1:0] int_tdata;
    reg [KEEP_WIDTH-1:0] int_tkeep;
    reg                  int_tvalid;
    wire                 int_tready; // Зарегистрированный сигнал ready для внутренней логики
    reg                  int_tlast;

    // --------------------------------------------------------------------
    // Регистры выходного пути
    // --------------------------------------------------------------------
    reg [DATA_WIDTH-1:0] m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] m_axis_tkeep_reg = {KEEP_WIDTH{1'b1}};
    reg                  m_axis_tvalid_reg = 1'b0, m_axis_tvalid_next;
    reg                  m_axis_tlast_reg  = 1'b0;

    reg [DATA_WIDTH-1:0] temp_m_axis_tdata_reg = {DATA_WIDTH{1'b0}};
    reg [KEEP_WIDTH-1:0] temp_m_axis_tkeep_reg = {KEEP_WIDTH{1'b1}};
    reg                  temp_m_axis_tvalid_reg = 1'b0, temp_m_axis_tvalid_next;
    reg                  temp_m_axis_tlast_reg  = 1'b0;

    // Зарегистрированный и опережающий (early) сигналы ready для входной части буфера
    reg  int_tready_reg = 1'b0;
    wire int_tready_early;

    // Управляющие сигналы пересылки между регистрами
    reg store_axis_int_to_output;
    reg store_axis_int_to_temp;
    reg store_axis_temp_to_output;

    // Выходы модуля
    assign m_tdata  = m_axis_tdata_reg;
    assign m_tkeep  = KEEP_ENABLE ? m_axis_tkeep_reg : {KEEP_WIDTH{1'b1}};
    assign m_tvalid = m_axis_tvalid_reg;
    assign m_tlast  = m_axis_tlast_reg;

    assign int_tready = int_tready_reg;

    // --------------------------------------------------------------------
    // Сравнение и управляющий автомат (FSM)
    // --------------------------------------------------------------------
    wire both_valid = s0_tvalid & s1_tvalid;
    
    // Проверка совпадения данных и tkeep
    wire data_match = (s0_tdata == s1_tdata);
    wire keep_match = KEEP_ENABLE ? (s0_tkeep == s1_tkeep) : 1'b1;
    wire match      = data_match && keep_match;

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

        case (state_reg)
            STATE_PASS: begin
                if (both_valid) begin
                    int_tvalid = 1'b1;
                    int_tlast  = (!match) || s0_tlast || s1_tlast;

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

                if (flush_s0_reg && s0_tvalid && s0_tlast) begin
                    flush_s0_next = 1'b0;
                end

                if (flush_s1_reg && s1_tvalid && s1_tlast) begin
                    flush_s1_next = 1'b0;
                end

                if (!flush_s0_next && !flush_s1_next) begin
                    state_next = STATE_PASS;
                end
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
        m_axis_tvalid_next      = m_axis_tvalid_reg;
        temp_m_axis_tvalid_next = temp_m_axis_tvalid_reg;

        store_axis_int_to_output   = 1'b0;
        store_axis_int_to_temp     = 1'b0;
        store_axis_temp_to_output = 1'b0;

        if (int_tready_reg) begin
            if (m_tready || !m_axis_tvalid_reg) begin
                m_axis_tvalid_next       = int_tvalid;
                store_axis_int_to_output = 1'b1;
            end else begin
                temp_m_axis_tvalid_next = int_tvalid;
                store_axis_int_to_temp   = 1'b1;
            end
        end else if (m_tready) begin
            m_axis_tvalid_next      = temp_m_axis_tvalid_reg;
            temp_m_axis_tvalid_next = 1'b0;
            store_axis_temp_to_output = 1'b1;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tvalid_reg      <= 1'b0;
            temp_m_axis_tvalid_reg <= 1'b0;
            int_tready_reg         <= 1'b0;
        end else begin
            m_axis_tvalid_reg      <= m_axis_tvalid_next;
            temp_m_axis_tvalid_reg <= temp_m_axis_tvalid_next;
            int_tready_reg         <= int_tready_early; // Сможем ли мы принять новое слово на ВХОД в СЛЕДУЮЩЕМ такте
        end
    end

    always @(posedge clk) begin
        if (store_axis_int_to_output) begin
            m_axis_tdata_reg <= int_tdata;
            m_axis_tkeep_reg <= int_tkeep;
            m_axis_tlast_reg <= int_tlast;
        end else if (store_axis_temp_to_output) begin
            m_axis_tdata_reg <= temp_m_axis_tdata_reg;
            m_axis_tkeep_reg <= temp_m_axis_tkeep_reg;
            m_axis_tlast_reg <= temp_m_axis_tlast_reg;
        end

        if (store_axis_int_to_temp) begin
            temp_m_axis_tdata_reg <= int_tdata;
            temp_m_axis_tkeep_reg <= int_tkeep;
            temp_m_axis_tlast_reg <= int_tlast;
        end
    end

endmodule
```

### Главные изменения относительно предыдущей версии:

1. **Зарегистрированный `int_tready_reg`**: Готовность входа теперь выдается через триггер `int_tready_reg`. Никакие комбинационные цепочки от `m_tready` больше не проходят на `s0_tready` или `s1_tready`.

2. **Расчет `int_tready_early`**: Применен оригинальный механизм спрединга/торможения `int_tready_early = m_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !int_tvalid))`

3. **Безопасная запись во временный буфер**: При пропадании `m_tready` передаваемый такт без потерь сохраняется в `temp_m_axis_*_reg`, а `int_tready_reg` на следующий такт падает в `0`, останавливая входные мастера.


---

###  Подробный разбор логики `int_tready_early`

Сигнал `int_tready_early` рассчитывается комбинационно на текущем такте и **записывается в триггер `int_tready_reg` по фронту клока**. Он отвечает на вопрос: *«Сможем ли мы принять новое слово на ВХОД в СЛЕДУЮЩЕМ такте?»*

Выражение состоит из двух основных условий, объединенных логическим **ИЛИ (`||`)**:

```verilog
assign int_tready_early = m_tready || (!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !int_tvalid));

```

#### Условие 1: `m_tready == 1` (Выход готов к приему)

Если приемник на выходе модуля готов принимать данные (`m_tready = 1`), то конвейер движется:

* Если во временном регистре `temp` что-то лежало, оно уходит в основной регистр `m_axis`.
* Если `temp` был пуст, данные со входа идут напрямую в `m_axis`.

В обоих случаях в Skid Buffer освобождается минимум одно место, поэтому модуль будет готов принять данные на следующем такте (`int_tready_early = 1`).

---

#### Условие 2: `!temp_m_axis_tvalid_reg && (!m_axis_tvalid_reg || !int_tvalid)` (Выход ЗАБЛОКИРОВАН, `m_tready == 0`)

Если приемник не готов (`m_tready = 0`), данные на выходе «застряли». Однако мы все еще можем выставить `int_tready_early = 1` на следующий такт, **если гарантированно не переполнится временный регистр `temp*`.

Для этого должны совпасть два суб-условия:

1. **`!temp_m_axis_tvalid_reg`** — Временный регистр пуст *прямо сейчас*.
2. **`(!m_axis_tvalid_reg || !int_tvalid)`** — Временный регистр *не заполнится* по текущему фронту клока:
* **`!m_axis_tvalid_reg`**: Основной выходной регистр пуст. Если на вход придет новое валидное слово, оно улетит в основной регистр, а `temp` останется пустым.
* **`!int_tvalid`**: На входе прямо сейчас НЕТ валидных данных. Даже если основной регистр занят, записывать в `temp` нечего.



---

### Сводная таблица состояний для `int_tready_early`

| `m_tready` | `temp_valid` | `main_valid` | `int_tvalid` | `int_tready_early` | Пояснение                                                                                           |
| ---------- | ------------ | ------------ | ------------ | ------------------ | --------------------------------------------------------------------------------------------------- |
| **1**      | X            | X            | X            | **1**              | Выход готов, конвейер продвигается.                                                                 |
| **0**      | **0**        | **0**        | X            | **1**              | Выход занят, но `main` пуст. Входное слово пойдет в `main`, место в `temp` сохранится.              |
| **0**      | **0**        | 1            | **0**        | **1**              | Выход и `main` заняты, но данных на входе нет. `temp` останется пустым.                             |
| **0**      | **0**        | 1            | 1            | **0**              | Выход и `main` заняты, и со входа идет слово. Оно заполнит `temp`. На следующий такт тормозим вход! |
| **0**      | 1            | X            | X            | **0**              | `temp` уже забит. Принимать новые данные нельзя.                                                    |

---
еще у тебя в коде:
```Verilog
  assign s0_tready = (state_reg == STATE_PASS) ? (s1_tvalid && int_tready) : flush_s0_reg;
  assign s1_tready = (state_reg == STATE_PASS) ? (s0_tvalid && int_tready) : flush_s1_reg;
```

```
Почему s0_tready  зависит от s1_tvalid, а не от s0_tvalid (для s1_tready аналогично) ? 
```

Это ключевой механизм **синхронизации (выравнивания) двух независимых потоков.** Поскольку скорости AXIS-мастеров могут отличаться, модуль должен гарантировать, что слова из обоих интерфейсов "съедаются" (потребляются) строго одновременно парами.

По стандарту AXI-Stream транзакция (передача слова) завершается только в тот такт, когда на фронте частоты одновременно `tvalid == 1` и `tready == 1`.

Если бы сигнал готовности канала 0 не зависел от наличия данных в канале 1, произошла бы рассинхронизация:

- **Сценарий провала:** Допустим, Master 0 быстрый и уже выставил данные (`s0_tvalid = 1`), а Master 1 задерживается (`s1_tvalid = 0`).

- Если бы `s0_tready` просто равнялся `int_tready`, то в следующий же такт произошло бы рукопожатие на интерфейсе s0. Модуль "съел" бы слово от Master 0, хотя сравнивать его еще не с чем. Это слово безвозвратно исчезло бы из потока, и весь дальнейший кадр сместился бы (съехал).


**Как работает перекрестная зависимость (Cross-Coupling):**

- **`s0_tready` зависит от `s1_tvalid`:** Канал s0 разрешает передачу (говорит «я готов») **только тогда**, когда на параллельном интерфейсе s1 тоже появилось валидное слово (и при этом выходной буфер `int_tready` не заполнен).

- **`s1_tready` зависит от `s0_tvalid`:** Аналогично, канал s1 искусственно тормозится и не принимает слово, пока Master 0 не выставит свои данные.


**Потактовая механика выравнивания:**

1. **Master 0 опережает:** Master 0 выставляет `s0_tvalid = 1`. Master 1 молчит (`s1_tvalid = 0`).

2. **Торможение:** Из-за зависимости от `s1_tvalid`, сигнал `s0_tready` остается равен `0`. Протокол AXI-Stream обязывает Master 0 удерживать свои данные и ждать.

3. **Master 1 догоняет:** Master 1 наконец выставляет `s1_tvalid = 1`.

4. **Синхронное разрешение:** В эту же наносекунду комбинационно поднимаются оба сигнала `s0_tready = 1` и `s1_tready = 1` (при условии `int_tready == 1`).

5. **Захват:** По следующему фронту тактового сигнала происходит одновременное рукопожатие на обоих интерфейсах. Внутренний автомат считывает сразу оба слова, сравнивает их и отправляет в буфер.


**Почему в уравнении `s0_tready` нет `s0_tvalid`?** По спецификации AMBA AXI-Stream разрешается (и поощряется) выставлять сигнал готовности `tready` заранее, не дожидаясь появления `tvalid`, чтобы избежать взаимных блокировок (deadlocks).

Интерфейс s0 как бы говорит: _"Я буду готов принять твои данные в любой момент, когда приедут данные от соседа, независимо от того, выставил ты их уже или нет"_. Если Master 0 еще не выставил данные (`s0_tvalid = 0`), транзакция всё равно не произойдет, так как для нее нужны обе единицы.

Во время `STATE_FLUSH` эта связка разрывается: каналы перестают ждать друг друга и начинают независимо "сливать" остатки своих кадров на максимальной скорости (`s0_tready = flush_s0_reg`), пока каждый не встретит свой `tlast`.