# Классический безопасный async FIFO

## 1. Два указателя

- `wr_ptr` — в домене `wr_clk`
- `rd_ptr` — в домене `rd_clk`

Они:

- бинарные (для адресации памяти)
- - **Gray-код версия** для передачи в другой домен

---
## 2. Почему Gray code

Потому что меняется **только 1 бит за такт** → минимизация метастабильности при CDC.

---

## 3. Синхронизация

Каждый указатель передаётся в другой домен:

- `wr_ptr_gray` → синхронизируется в `rd_clk`
- `rd_ptr_gray` → синхронизируется в `wr_clk`

через классический:

```verilog
always @(posedge clk) begin  
    sync_ff1 <= async_signal;  
    sync_ff2 <= sync_ff1;  
end
```

## 4. Детектирование состояний

## ❌ FULL (в домене записи)

Сравниваем:

- `wr_ptr_gray_next`
- синхронизированный `rd_ptr_gray_sync`

Условие FULL (важно!):

```verilog
full = (wr_ptr_gray_next == {  
    ~rd_ptr_gray_sync[MSB:MSB-1],  
     rd_ptr_gray_sync[MSB-2:0]  
});
```

это классический “инверсия старших битов”

## ❌ EMPTY (в домене чтения)

```verilog
empty = (rd_ptr_gray == wr_ptr_gray_sync);
```

# Как делают occupancy (если очень надо)

Есть 3 подхода:

## ✅ 1. Через указатели (рекомендуется)

В каждом домене:

1. Синхронизируешь чужой pointer
2. Переводишь Gray → binary
3. Вычитаешь

```verilog
occupancy_wr = wr_ptr_bin - rd_ptr_bin_sync;  
occupancy_rd = wr_ptr_bin_sync - rd_ptr_bin;
```

✔ работает  
✔ безопасно  
❗ но есть задержка (2 такта синхронизации)

## ✅ 2. Approximate (почти всегда достаточно)

Используют:

- `almost_full`
- `almost_empty`

Это стандарт в FPGA/ASIC

## ⚡ 3. Credit-based
Используется в:
- NIC
- NoC
- PCIe

Суть:
- читающая сторона возвращает кредиты
- пишущая уменьшает их
✔ точный контроль  
✔ без CDC pointer-логики  
❗ сложнее FSM

# Что считается best practice

В индустрии (FPGA + ASIC):
✔ **Async FIFO = только через pointers + Gray code**  
✔ FULL/EMPTY — только через pointer comparison  
✔ occupancy — derived, не основной сигнал

# 1. Async FIFO FWFT (industrial-style)

## ✔ особенности

- dual-clock
- Gray pointers
- 2FF sync
- FWFT (данные “падают” сами)
- без пузырей
## 📦 Модуль
```verilog
module async_fifo_fwft #
(
    parameter DATA_W = 32,
    parameter ADDR_W = 4,
    parameter ALMOST_FULL_THRESH  = (1<<ADDR_W) - 2,
    parameter ALMOST_EMPTY_THRESH = 2
)
(
    // write side
    input                  wr_clk,
    input                  wr_rst,
    input                  wr_en,
    input  [DATA_W-1:0]    wr_data,
    output                 wr_full,
    output                 wr_almost_full,
    output [ADDR_W:0]      wr_cnt,

    // read side
    input                  rd_clk,
    input                  rd_rst,
    input                  rd_en,
    output [DATA_W-1:0]    rd_data,
    output                 rd_empty,
    output                 rd_almost_empty,
    output [ADDR_W:0]      rd_cnt
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
reg [PTR_W:0] wr_ptr_bin,  wr_ptr_gray;

reg [PTR_W:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
wire [PTR_W:0] rd_ptr_gray_sync = rd_ptr_gray_sync2;

// sync read pointer
always @(posedge wr_clk) begin
    rd_ptr_gray_sync1 <= rd_ptr_gray;
    rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
end

// convert to binary (SAFE after sync)
wire [PTR_W:0] rd_ptr_bin_sync = gray2bin(rd_ptr_gray_sync);

// next pointer
wire [PTR_W:0] wr_ptr_bin_next  = wr_ptr_bin + 1;
wire [PTR_W:0] wr_ptr_gray_next = bin2gray(wr_ptr_bin_next);

// FULL
assign wr_full =
    (wr_ptr_gray_next == {
        ~rd_ptr_gray_sync[PTR_W:PTR_W-1],
         rd_ptr_gray_sync[PTR_W-2:0]
    });

// OCCUPANCY (safe)
assign wr_cnt = wr_ptr_bin - rd_ptr_bin_sync;

// ALMOST FULL
assign wr_almost_full = (wr_cnt >= ALMOST_FULL_THRESH);

// write
always @(posedge wr_clk) begin
    if (wr_rst) begin
        wr_ptr_bin  <= 0;
        wr_ptr_gray <= 0;
    end else if (wr_en && !wr_full) begin
        mem[wr_ptr_bin[ADDR_W-1:0]] <= wr_data;
        wr_ptr_bin  <= wr_ptr_bin_next;
        wr_ptr_gray <= wr_ptr_gray_next;
    end
end


// ============================================================
// READ DOMAIN (FWFT)
// ============================================================
reg [PTR_W:0] rd_ptr_bin, rd_ptr_gray;

reg [PTR_W:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
wire [PTR_W:0] wr_ptr_gray_sync = wr_ptr_gray_sync2;

// sync write pointer
always @(posedge rd_clk) begin
    wr_ptr_gray_sync1 <= wr_ptr_gray;
    wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
end

// convert to binary
wire [PTR_W:0] wr_ptr_bin_sync = gray2bin(wr_ptr_gray_sync);

// EMPTY (memory)
wire mem_empty = (rd_ptr_gray == wr_ptr_gray_sync);

// OCCUPANCY (safe)
assign rd_cnt = wr_ptr_bin_sync - rd_ptr_bin;

// ALMOST EMPTY
assign rd_almost_empty = (rd_cnt <= ALMOST_EMPTY_THRESH);


// =========================
// FWFT datapath
// =========================
reg [DATA_W-1:0] rd_data_reg;
reg              rd_valid;

assign rd_data  = rd_data_reg;
assign rd_empty = !rd_valid;


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

        // preload
        if (!rd_valid && !mem_empty) begin
            rd_data_reg <= mem[rd_ptr_bin[ADDR_W-1:0]];
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            rd_valid    <= 1;
        end

        // consume
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

endmodule
```

# Почему такие пороги almost_*

### Базовые значения в коде
```verilog
ALMOST_FULL_THRESH  = DEPTH - 2;  
ALMOST_EMPTY_THRESH = 2;
```

Это **минимально безопасные** значения при идеальных условиях:

- синхронизация = 2 FF
- логика быстрая
- нет длинных критических путей
- потребитель/производитель реагируют мгновенно

смысл:
- запас = ~2 слова (компенсация CDC latency)

### Почему на практике ставят 4 (или больше)
```verilog
ALMOST_FULL_THRESH  = DEPTH - 4;  
ALMOST_EMPTY_THRESH = 4;
```

Потому что в реальном дизайне появляется:

## 🔻 1. CDC latency

- 2 FF синхронизации = **2 такта**
- - 1 такт на decode (gray→bin)
- - 1 такт на использование

уже **3–4 слова рассинхронизации**

## 🔻 2. Pipeline вокруг FIFO

Типичный случай:

```
producer → pipeline → FIFO  
FIFO → pipeline → consumer
```

между решением “стоп писать” и фактической остановкой может пройти 2–3 такта

## 🔻 3. Fmax / timing closure

Если ты:
- регистрируешь `wr_cnt`
- пайплайнишь comparator

ещё +1 такт

# Вывод

| Сценарий            | Рекомендуемый запас |
| ------------------- | ------------------- |
| идеальный           | 2                   |
| обычный FPGA        | 4                   |
| high-speed pipeline | 6–8                 |

правило:

`margin >= CDC latency + pipeline latency`

# 2. Credit-based FIFO (NIC style)

Здесь **нет FULL comparator**.  
Flow control = кредиты.

## ✔ особенности
- точный контроль заполнения
- write side не знает pointers
- read side возвращает кредиты
- CDC через toggle/pulse sync

## 📦 Модуль
```verilog

module async_fifo_credit #  
(  
    parameter DATA_W = 32,  
    parameter ADDR_W = 4  
)  
(  
    // write side  
    input                  wr_clk,  
    input                  wr_rst,  
    input                  wr_en,  
    input  [DATA_W-1:0]    wr_data,  
    output                 wr_ready,   // = credits > 0  
  
    // read side  
    input                  rd_clk,  
    input                  rd_rst,  
    input                  rd_en,  
    output [DATA_W-1:0]    rd_data,  
    output                 rd_valid  
);  
  
localparam DEPTH = (1<<ADDR_W);  
  
// memory  
reg [DATA_W-1:0] mem [0:DEPTH-1];  
  
  
// =========================  
// pointers (local only)  
// =========================  
reg [ADDR_W-1:0] wr_ptr;  
reg [ADDR_W-1:0] rd_ptr;  
  
  
// =========================  
// WRITE DOMAIN (credits)  
// =========================  
reg [ADDR_W:0] credits;  
  
// credit return sync  
reg credit_toggle_rd;  
reg credit_sync1, credit_sync2;  
  
wire credit_pulse_wr = credit_sync1 ^ credit_sync2;  
  
// sync toggle from read domain  
always @(posedge wr_clk) begin  
    credit_sync1 <= credit_toggle_rd;  
    credit_sync2 <= credit_sync1;  
end  
  
assign wr_ready = (credits != 0);  
  
always @(posedge wr_clk) begin  
    if (wr_rst) begin  
        wr_ptr  <= 0;  
        credits <= DEPTH;  
    end else begin  
  
        // credit return  
        if (credit_pulse_wr)  
            credits <= credits + 1;  
  
        // write  
        if (wr_en && wr_ready) begin  
            mem[wr_ptr] <= wr_data;  
            wr_ptr      <= wr_ptr + 1;  
            credits     <= credits - 1;  
        end  
    end  
end  
  
  
// =========================  
// READ DOMAIN  
// =========================  
reg [ADDR_W:0] occupancy;  
  
reg credit_toggle;  
  
// sync write events (optional: можно через FIFO/Gray)  
reg wr_event_toggle;  
reg wr_sync1, wr_sync2;  
  
wire wr_event_rd = wr_sync1 ^ wr_sync2;  
  
always @(posedge rd_clk) begin  
    wr_sync1 <= wr_event_toggle;  
    wr_sync2 <= wr_sync1;  
end  
  
  
// write event generation  
always @(posedge wr_clk) begin  
    if (wr_en && wr_ready)  
        wr_event_toggle <= ~wr_event_toggle;  
end  
  
  
assign rd_valid = (occupancy != 0);  
assign rd_data  = mem[rd_ptr];  
  
always @(posedge rd_clk) begin  
    if (rd_rst) begin  
        rd_ptr    <= 0;  
        occupancy <= 0;  
        credit_toggle <= 0;  
    end else begin  
  
        // new data arrived  
        if (wr_event_rd)  
            occupancy <= occupancy + 1;  
  
        // read  
        if (rd_en && rd_valid) begin  
            rd_ptr    <= rd_ptr + 1;  
            occupancy <= occupancy - 1;  
  
            // send credit back  
            credit_toggle <= ~credit_toggle;  
        end  
  
    end  
end  
  
endmodule
```

# ⚠️ Важный комментарий про credit FIFO

Этот вариант:

✔ демонстрирует архитектуру  
❗ но в реальном ASIC/NIC делают чуть сложнее:

### обычно:
- credit возвращают **через маленький async FIFO**, а не toggle
- write events тоже через FIFO или pointer
- добавляют protection от:
    - lost toggle
    - metastability edge cases

# 🧠 Когда что использовать

## FWFT FIFO (практически всегда)

✔ проще  
✔ стандарт  
✔ FPGA-friendly  
✔ легко верифицировать

## Credit-based

✔ когда:
- у тебя **pipeline / NoC / NIC**
- нужна **точная backpressure модель**
- много стадий

# Интеграция с AXI-Stream (без пузырей)

Цель:  
**tvalid/tready без stall между словами**

## 📦 AXI-Stream mapping

### Write side (producer → FIFO)

```verilog
assign s_axis_tready = !wr_afull;  
assign wr_en         = s_axis_tvalid && s_axis_tready;  
assign wr_data       = s_axis_tdata;
```

✔ стандарт  
✔ без пузырей

## 📦 Read side (FIFO → consumer, FWFT!)

## ❌ Неправильно (частая ошибка)

```verilog
m_axis_tvalid = !rd_empty;  
rd_en = m_axis_tready;
```

👉 это даёт пузырь!

## ✅ Правильно (FWFT-aware)
```verilog
assign m_axis_tvalid = !rd_empty;  
assign rd_en         = m_axis_tvalid && m_axis_tready;  
assign m_axis_tdata  = rd_data;
```

👉 потому что:
- данные уже предзагружены (FWFT)
- `rd_en` = consume

## 🔥 Почему это без пузырей

Сценарий:

```
clk:     ↑   ↑   ↑   ↑  
valid:   1   1   1   1  
ready:   1   1   1   1  
data:   D0  D1  D2  D3
```

👉 каждый такт:
- `rd_en = 1`
- FIFO сразу подаёт следующий word

✔ throughput = 1/clk  
✔ latency = минимальный

# Важный нюанс FWFT + AXI

`rd_empty` — это **!rd_valid**, а не mem_empty.

значит:
- `tvalid` отражает **наличие данных на выходе**
- а не состояние памяти
✔ это идеально совпадает с AXI semantics

# Итог
### Почему разные almost thresholds:
- 2 → теоретический минимум
- 4 → реальный FPGA safe margin

### AXI-stream интеграция:
- write: стандарт
- read: FWFT = zero bubble
- `rd_en = tvalid && tready`

---

Сделаем:

## ✅ Что меняем

1. **Регистрируем выходы**
    - `wr_full`, `wr_almost_full`, `wr_cnt`
    - `rd_empty`, `rd_almost_empty`, `rd_cnt`
2. **Добавляем saturation для счетчиков**
    - `wr_cnt ∈ [0, DEPTH]`
    - `rd_cnt ∈ [0, DEPTH]`
3. ⚠️ Важно:
    - FULL/EMPTY теперь **с задержкой 1 такт**
    - безопасность остаётся, т.к. внутренняя логика использует _не зарегистрированные_ версии

---
# 🚀 Обновлённый модуль

```verilog
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

(* ASYNC_REG = "TRUE" *) reg [PTR_W:0] rd_ptr_gray_sync1, rd_ptr_gray_sync2;
(* ASYNC_REG = "TRUE" *) reg rd_valid_sync1, rd_valid_sync2;
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
// Это условие FULL проверяет состояние ПОСЛЕ следующей записи
// wr_full_int говорит:
// "если я СЕЙЧАС запишу → достигну состояния, где FIFO станет полным"
wire wr_full_int =
    (wr_ptr_gray_next == {
        ~rd_ptr_gray_sync[PTR_W:PTR_W-1],
         rd_ptr_gray_sync[PTR_W-2:0]
    });
// это эквивалент:
// wr_ptr_bin_next == rd_ptr_bin + DEPTH

// Почему инверсия 2 бит?
// Потому что:
// * Gray код меняет 1 бит за шаг
// * при переходе через половину кольца меняются 2 старших бита

// current occupancy (combinational)
wire [PTR_W:0] wr_cnt_raw = wr_ptr_bin - rd_ptr_bin_sync_r;
wire [PTR_W:0] wr_cnt_total = wr_cnt_raw + rd_valid_wr;

// saturation
wire [PTR_W:0] wr_cnt_sat = (wr_cnt_total > DEPTH) ? DEPTH : wr_cnt_total;

// look-ahead
wire wr_push = wr_en && !wr_full_int;
wire [PTR_W:0] wr_cnt_next = wr_cnt_sat + (wr_push ? 1 : 0);
wire [PTR_W:0] wr_cnt_next_sat = (wr_cnt_next > DEPTH) ? DEPTH : wr_cnt_next;

// almost full NEXT !
wire wr_almost_full_next = (wr_cnt_next_sat >= ALMOST_FULL_THRESH);

// статусный full
wire wr_full_next = (wr_cnt_next_sat == DEPTH);

// // almost full CURRENT !
// wire wr_almost_full_int = (wr_cnt_sat >= ALMOST_FULL_THRESH);

// write
always @(posedge wr_clk) begin
    if (wr_rst) begin
        wr_ptr_bin  <= 0;
        wr_ptr_gray <= 0;
    // end else if (wr_en && !wr_full_int) begin
    end else if (wr_push) begin
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
        // wr_full        <= wr_full_int;
        // wr_almost_full <= wr_almost_full_int;
        // wr_cnt         <= wr_cnt_sat;
        wr_full        <= wr_full_next;
        wr_almost_full <= wr_almost_full_next;
        wr_cnt         <= wr_cnt_next_sat;
    end
end


// ============================================================
// READ DOMAIN (FWFT)
// ============================================================
// reg [PTR_W:0] rd_ptr_bin, rd_ptr_gray;
reg [PTR_W:0] rd_ptr_bin;

(* ASYNC_REG = "TRUE" *) reg [PTR_W:0] wr_ptr_gray_sync1, wr_ptr_gray_sync2;
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

// saturation ( rd_cnt_sat = min(rd_cnt_total, DEPTH) )
wire [PTR_W:0] rd_cnt_sat = (rd_cnt_total > DEPTH) ? DEPTH : rd_cnt_total;

// almost empty
// wire rd_almost_empty_int = (rd_cnt_sat <= ALMOST_EMPTY_THRESH);

// wire [PTR_W:0] rd_cnt_next = rd_cnt_sat - (rd_valid && rd_en ? 1 : 0);

// Чтобы не уйти в underflow:
wire [PTR_W:0] rd_cnt_next =
    (rd_cnt_sat > 0 && rd_valid && rd_en) ? (rd_cnt_sat - 1) : rd_cnt_sat;

wire rd_almost_empty_int = (rd_cnt_next <= ALMOST_EMPTY_THRESH);

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
        // rd_empty    <= 1'b1; // 23.04.2026
    end else begin

        if (!rd_valid && !mem_empty) begin
            rd_data_reg <= mem[rd_ptr_bin[ADDR_W-1:0]];
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            rd_valid    <= 1;
            // rd_empty    <= 1'b0; // 23.04.2026
        end
        else if (rd_en && rd_valid) begin
            if (!mem_empty) begin
                rd_data_reg <= mem[rd_ptr_bin[ADDR_W-1:0]];
                rd_ptr_bin  <= rd_ptr_bin_next;
                rd_ptr_gray <= rd_ptr_gray_next;
                rd_valid    <= 1;
                // rd_empty    <= 1'b0; // 23.04.2026
            end else begin
                rd_valid <= 0;
                // rd_empty <= 1'b1; // 23.04.2026
            end
        end

    end
end

wire will_empty = rd_valid && rd_en && mem_empty; // 23.04.2026

// registered outputs
always @(posedge rd_clk) begin
    if (rd_rst) begin
        rd_empty        <= 1'b1;
        rd_almost_empty <= 1'b1;
        rd_cnt          <= 0;
    end else begin
        // rd_empty        <= !rd_valid;
        rd_empty <= !rd_valid || will_empty; // 23.04.2026
        rd_almost_empty <= rd_almost_empty_int;
        // rd_cnt          <= rd_cnt_sat;
        rd_cnt          <= rd_cnt_next;
    end
end

endmodule
```

# 🔒 Важные нюансы

## ⚠️ 1. FULL/EMPTY теперь с latency 1 такт

👉 но:
```verilog
if (wr_en && !wr_full_int) // используем internal!
```

✔ безопасность не нарушена

## ⚠️ 2. Saturation — защита от transient

Иногда при CDC можно получить:

- временно `wr_cnt_raw > DEPTH`

👉 saturation гарантирует:

`0 ≤ wr_cnt ≤ DEPTH`

## ⚠️ 3. rd_empty — это FWFT empty
```verilog
rd_empty = !rd_valid;
```

✔ корректно для AXI-stream

# В итоге:
✔ timing-friendly FIFO  
✔ нет длинных комбинаторных путей на выходах  
✔ стабильные счетчики  
✔ готов к high-Fmax

---
# constraints для async FIFO 

Для асинхронного FIFO (с независимыми `wr_clk` и `rd_clk`, Gray-кодами и синхронизаторами) constraints — это не “для красоты”, а критически важная часть. Без них STA попытается анализировать невозможные тайминги между доменами и либо зафейлит сборку, либо, хуже, “оптимизирует” синхронизаторы.

Что реально нужно в индустрии для Intel Quartus и Xilinx Vivado.

# 1. Базовая идея constraints для async FIFO

Есть 3 ключевых вещи:
### 1) Разорвать тайминги между доменами
`wr_clk` ↔ `rd_clk` — **асинхронные**
### 2) Защитить CDC-синхронизаторы
двухтактные регистры (`*_sync1`, `*_sync2`)
### 3) (желательно) ограничить задержку Gray-шины
чтобы биты Gray приходили “почти одновременно”

---

# 2. Xilinx (Vivado) — XDC

## 2.1 Асинхронные клоки

```tcl
set_clock_groups -asynchronous \  
    -group [get_clocks wr_clk] \  
    -group [get_clocks rd_clk]
```
Это **обязательно**.  
Альтернатива (хуже читается):
```tcl
set_false_path -from [get_clocks wr_clk] -to [get_clocks rd_clk]  
set_false_path -from [get_clocks rd_clk] -to [get_clocks wr_clk]
```

---
## 2.2 Пометка CDC-регистров

Очень важно — иначе Vivado может сломать цепочку.
```tcl
set_property ASYNC_REG TRUE [get_cells -hier *rd_ptr_gray_sync1*]  
set_property ASYNC_REG TRUE [get_cells -hier *rd_ptr_gray_sync2*]  
  
set_property ASYNC_REG TRUE [get_cells -hier *wr_ptr_gray_sync1*]  
set_property ASYNC_REG TRUE [get_cells -hier *wr_ptr_gray_sync2*]  
  
set_property ASYNC_REG TRUE [get_cells -hier *rd_valid_sync1*]  
set_property ASYNC_REG TRUE [get_cells -hier *rd_valid_sync2*]
```
💡 Лучше ещё:
```tcl
set_property DONT_TOUCH TRUE [get_cells -hier *sync1*]
```

## 2.3 Ограничение на Gray bus (очень рекомендуется)

Чтобы избежать ситуации, когда разные биты приходят в разные такты:
```tcl
set_max_delay -from [get_pins *wr_ptr_gray_reg*/Q] \  
              -to   [get_pins *wr_ptr_gray_sync1*/D] \  
              2.0
```

И аналогично для обратного направления:
```tcl
set_max_delay -from [get_pins *rd_ptr_gray_reg*/Q] \  
              -to   [get_pins *rd_ptr_gray_sync1*/D] \  
              2.0
```
(значение подбирается ≈ 1 период быстрого клока)

## 2.4 (Опционально) placement constraint

Чтобы синхронизаторы были рядом:
```tcl
set_property SHREG_EXTRACT NO [get_cells *sync*]
```

# 3. Intel (Quartus) — SDC

В Intel Quartus всё то же, но синтаксис другой.

## 3.1 Асинхронные клоки
```tcl
set_clock_groups -asynchronous -group {wr_clk} -group {rd_clk}
```

ИЛИ:

```tcl
set_false_path -from [get_clocks {wr_clk}] -to [get_clocks {rd_clk}]  
set_false_path -from [get_clocks {rd_clk}] -to [get_clocks {wr_clk}]
```

## 3.2 CDC-регистры (очень важно!)

Quartus любит “оптимизировать”:
```tcl
set_instance_assignment -name ASYNCHRONOUS_REG TRUE -to rd_ptr_gray_sync1  
set_instance_assignment -name ASYNCHRONOUS_REG TRUE -to rd_ptr_gray_sync2  
  
set_instance_assignment -name ASYNCHRONOUS_REG TRUE -to wr_ptr_gray_sync1  
set_instance_assignment -name ASYNCHRONOUS_REG TRUE -to wr_ptr_gray_sync2
```

И для valid:
```tcl
set_instance_assignment -name ASYNCHRONOUS_REG TRUE -to rd_valid_sync1  
set_instance_assignment -name ASYNCHRONOUS_REG TRUE -to rd_valid_sync2
```

## 3.3 Запрет оптимизации
```tcl
set_instance_assignment -name PRESERVE_REGISTER ON -to *sync1*  
set_instance_assignment -name PRESERVE_REGISTER ON -to *sync2*
```

## 3.4 Gray bus delay constraint
```tcl
set_max_delay 2.0 \  
    -from [get_registers {*wr_ptr_gray[*]}] \  
    -to   [get_registers {*wr_ptr_gray_sync1[*]}]
```
И обратно:
```tcl
set_max_delay 2.0 \  
    -from [get_registers {*rd_ptr_gray[*]}] \  
    -to   [get_registers {*rd_ptr_gray_sync1[*]}]
```
---

# 4. Что НЕ нужно делать (частые ошибки)

❌ Не оставлять без `set_clock_groups`  
→ получите фейковые violations

❌ Не ставить `false_path` на всё подряд  
→ можно скрыть реальные ошибки

❌ Не игнорировать ASYNC_REG  
→ синхронизатор может развалиться

❌ Не ограничивать Gray bus  
→ возможны редкие “призрачные” баги

---

# 5. Минимальный “production-ready” набор

Если коротко, индустриальный минимум:

## Vivado:
- `set_clock_groups`
- `ASYNC_REG` на sync-регистры

## Quartus:
- `set_clock_groups`
- `ASYNCHRONOUS_REG`
- `PRESERVE_REGISTER`

### Рекомендуется в обоих:
- `set_max_delay` для Gray pointers

---
# 1. Зачем вообще нужен `set_max_delay` для Gray bus

Указатели (`wr_ptr_gray`, `rd_ptr_gray`) передаются между разными тактовыми доменами.

Ключевое свойство Gray code:
> за один шаг меняется **ровно 1 бит**

Но это свойство **логическое**, а не физическое.
### Проблема в железе
**разные биты Gray могут прийти с разной задержкой**

То есть в момент захвата `sync1`:
```
бит[3] — уже новый  
бит[2] — ещё старый  
бит[1] — новый  
бит[0] — старый
```

→ получается **некорректный Gray код**  
→ после `gray2bin` → скачок счётчика
Это ломает идею Gray-кода и может дать **некорректное значение указателя**

---

# 2. Что делает `set_max_delay`

Он говорит инструменту (в Xilinx Vivado или Intel Quartus):
> “Сделай так, чтобы сигнал дошёл от точки A до точки B **не дольше чем за X ns**”

# 3. Разбор Xilinx (Vivado)

## Команда
```tcl
set_max_delay -from [get_pins *wr_ptr_gray_reg*/Q] \  
              -to   [get_pins *wr_ptr_gray_sync1*/D] \  
              2.0
```

## 3.1 `set_max_delay`

Формат:
```tcl
set_max_delay <value> -from <A> -to <B>
```

или:
```tcl
set_max_delay -from <A> -to <B> <value>
```

`<value>` = максимальная задержка (в наносекундах)

## 3.2 `get_pins`
```tcl
get_pins *wr_ptr_gray_reg*/Q
```

означает:
- взять **все пины Q** регистров
- имя которых содержит `wr_ptr_gray_reg`

 Это:
```
wr_ptr_gray_reg[0]/Q  
wr_ptr_gray_reg[1]/Q  
...
```

```tcl
get_pins *wr_ptr_gray_sync1*/D
```

- входы (`D`) регистров первого синхронизатора

## 3.3 Что реально ограничивается

Путь:
```
wr_ptr_gray_reg[*] (Q)  
        ↓  
   (routing + logic)  
        ↓  
wr_ptr_gray_sync1[*] (D)
```

## 3.4 Что означает `2.0`

Это значит:
> любой бит Gray-шины должен прийти ≤ 2.0 ns

---

## 3.5 Важный момент

Это НЕ про setup/hold между клоками (они асинхронны!)
Это просто **ограничение на физическую задержку**

# 4. Почему это работает

Допустим:
- период быстрого клока = 4 ns

Cтавим:
```tcl
set_max_delay = 2 ns
```
## Почему 2.0 ns?

Это эвристика:

нужно, чтобы ВСЕ биты пришли “почти одновременно”

Обычно берут:
```
~ 1 период быстрого клока  
или  
ещё жёстче (0.5 периода)
```

Тогда:
- все биты приходят “достаточно близко”
- вероятность, что они попадут в разные такты → резко падает

# 5. Обратное направление
```tcl
set_max_delay -from [get_pins *rd_ptr_gray_reg*/Q] \  
              -to   [get_pins *rd_ptr_gray_sync1*/D] \  
              2.0
```

То же самое, но:
```
READ domain → WRITE domain
```

---

# 6. Quartus (Intel) — отличия

В Intel Quartus синтаксис немного проще.

---

## Команда
```tcl
set_max_delay 2.0 \  
    -from [get_registers {*wr_ptr_gray[*]}] \  
    -to   [get_registers {*wr_ptr_gray_sync1[*]}]
```

## 6.1 `get_registers`

В отличие от Vivado:
- выбираются **регистры целиком**, а не пины

👉 Quartus сам понимает:
```
Q → D
```

## 6.2 `{*wr_ptr_gray[*]}`

Это шаблон:
- `*` — любой префикс
- `[*]` — все биты вектора

Пример:
```
wr_ptr_gray[0]  
wr_ptr_gray[1]  
...
```

## 6.3 Что ограничивается

То же самое:
```
wr_ptr_gray[*] → wr_ptr_gray_sync1[*]
```

# 7. Важный нюанс: это НЕ skew constraint

Многие думают:
> “это делает все биты одинаково быстрыми”

❌ Нет
Это просто ограничивает **максимальную задержку каждого бита**

Но! Если все биты ≤ 2
---
# 1. Что такое skew в этом контексте

Для Gray-шины тебя волнует не абсолютная задержка, а:
> **разница во времени прихода разных битов**

Если один бит пришёл через 0.5 нс, а другой через 3 нс —  
👉 skew = 2.5 нс

Именно это ломает корректность Gray при захвате в `sync1`.

# 2. `set_max_delay` vs `set_max_skew`

### `set_max_delay`
ограничивает:

```
каждый путь отдельно ≤ X
```

но допускает:

```
бит0 = 0.5 ns  
бит1 = 1.9 ns  
бит2 = 0.6 ns
```

skew всё ещё большой

### `set_max_skew`
ограничивает:
```
max(arrival_time) - min(arrival_time) ≤ X
```

именно то, что нужно для Gray

# 3. Vivado (Xilinx) — как правильно

В Xilinx Vivado `set_max_skew` поддерживается и **это recommended practice для CDC buses**.

## ✔ Пример для FIFO
```tcl
set_max_skew 1.0 \  
    -from [get_pins *wr_ptr_gray_reg*/Q] \  
    -to   [get_pins *wr_ptr_gray_sync1*/D]
```

И обратно:
```tcl
set_max_skew 1.0 \  
    -from [get_pins *rd_ptr_gray_reg*/Q] \  
    -to   [get_pins *rd_ptr_gray_sync1*/D]
```


## 🔹 Как это работает

Vivado:

1. берёт ВСЕ пути:
```tcl
    wr_ptr_gray[i] → sync1[i]
```
    
2. считает arrival time каждого
3. проверяет:
```tcl
max - min ≤ 1.0 ns
````

## 🔹 Нужно ли `-datapath_only`?

Обычно да, если есть:

set_clock_groups -asynchronous

лучше писать:
```tcl
set_max_skew 1.0 \  
    -from [get_pins *wr_ptr_gray_reg*/Q] \  
    -to   [get_pins *wr_ptr_gray_sync1*/D] \  
    -datapath_only
```


#  4. Quartus (Intel) — неприятная правда

В Intel Quartus:

 `set_max_skew` либо:
- отсутствует
- либо сильно ограничен
- либо работает не так, как ожидаешь

В индустрии для Intel обычно делают:
**через `set_max_delay`**

##  Эквивалентная стратегия
```tcl
set_max_delay 1.0 \  
    -from [get_registers {*wr_ptr_gray[*]}] \  
    -to   [get_registers {*wr_ptr_gray_sync1[*]}]
```

И обратно:
```tcl
set_max_delay 1.0 \  
    -from [get_registers {*rd_ptr_gray[*]}] \  
    -to   [get_registers {*rd_ptr_gray_sync1[*]}]
```


## Почему это работает

Если задать **жёсткий max_delay**, например:
```
все пути ≤ 1 ns
```

автоматически:
```
skew ≤ 1 ns
```

# 5. Важный практический момент

### ❗ Не переусердствовать !

Если поставить:
```
set_max_skew 0.1 ns
```
 place&route может:
- не закрыться
- начать ломать другие критические пути

## ✔ Типичные значения

|Ситуация|Значение|
|---|---|
|безопасно|1.0–2.0 ns|
|агрессивно|0.5 ns|
|очень жёстко|<0.3 ns|

# 6. Что лучше использовать?

## Для Vivado:

**идеально:**
```
set_max_skew + set_max_delay (опционально)
```

Почему:
- `max_skew` → выравнивает биты
- `max_delay` → ограничивает абсолютную задержку

## Для Quartus:

**де-факто стандарт:**
```
set_max_delay
```

# 7. Комбинированный “best practice” (Vivado)

# ограничение skew  
```tcl
set_max_skew 1.0 \  
    -from [get_pins *wr_ptr_gray_reg*/Q] \  
    -to   [get_pins *wr_ptr_gray_sync1*/D] \  
    -datapath_only  
  
# ограничение абсолютной задержки (опционально)  
set_max_delay 2.0 \  
    -from [get_pins *wr_ptr_gray_reg*/Q] \  
    -to   [get_pins *wr_ptr_gray_sync1*/D] \  
    -datapath_only
```

# Итог

- `set_max_skew` — **самый точный способ защитить Gray bus**
- в Vivado — использовать обязательно (если делаешь серьёзный дизайн)
- в Quartus — заменяется `set_max_delay`
- лучше комбинировать с `-datapath_only`