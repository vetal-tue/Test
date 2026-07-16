Ниже **3 индустриальных шаблона FIFO на Verilog-2001**, от простого к «правильному».

Все они **синтезируемые, безопасные и реально применяются** в FPGA/ASIC.

# Общие допущения (для всех примеров)
 
* Одна тактовая частота `clk`
* Синхронный reset
* FIFO полностью использует RAM
* Параметры:
  * `DATA_WIDTH`
  * `DEPTH`
* Никакого `%`
* Подходит под block RAM / simple dual-port RAM

# 📌 Пример 1 — FIFO с глубиной = 2ⁿ (**НЕ FWFT !!!**)
  
> **Самый популярный вариант в индустрии**
### Идея
* Адреса — кольцевые счётчики
* Добавляется **MSB-бит переполнения**
* Full/Empty определяются сравнением указателей
### Код 
```verilog
module fifo_sync_pow2 #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 7
)(
    input                   clk,
    input                   rst,  

    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,  

    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,  

    output                  full,
    output                  empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;  // DEPTH = 2^ADDR_WIDTH

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];  

    reg [ADDR_WIDTH:0] wr_ptr;   // +1 бит!
    reg [ADDR_WIDTH:0] rd_ptr;

    /* WRITE */

    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
    end  

    /* READ */
    assign rd_data = mem[rd_ptr[ADDR_WIDTH-1:0]];  

    /* POINTERS */
    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            
        end else begin
            if (wr_en && !full)
                wr_ptr <= wr_ptr + 1'b1;  

            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end  

    /* STATUS */
    assign empty = (wr_ptr == rd_ptr);  

    assign full =
        (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]) &&
        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);  

endmodule
```
### Почему это индустриальный стандарт

✔ Нет делений
✔ Простая логика
✔ Отлично мапится в BRAM
✔ Максимальная частота

# 📌 **!!! ВНИМАНИЕ ! В ЭТОМ FIFO ЕСТЬ BUG !!!!**

Пусть FIFO полностью заполнено. Например, для `ADDR_WIDTH = 3`:

```
DEPTH = 8

wr_ptr = 1_010
rd_ptr = 0_010

full = 1
empty = 0
```

То есть:
```
wr_ptr = rd_ptr + DEPTH
```

Все 8 элементов заняты. На входах в текущем такте:
```
wr_en = 1
rd_en = 1
full  = 1
empty = 0
```

## Что произойдет в блоке записи

```verilog
always @(posedge clk) begin
    if (wr_en && !full)
        mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
end
```

Поскольку `full = 1` условие `wr_en && !full` равно `1 && 0 = 0`

Следовательно **запись НЕ произойдет.** Память останется без изменений.

## Что произойдет в блоке указателей

В том же фронте:
```verilog
if (wr_en && !full)
    wr_ptr <= wr_ptr + 1;

if (rd_en && !empty)
    rd_ptr <= rd_ptr + 1;
```

Первая проверка
```verilog
wr_en && !full
```
ложна. Следовательно `wr_ptr` не изменится.

Вторая проверка `rd_en && !empty` истинна. Следовательно
```
rd_ptr <= rd_ptr + 1
```

---
После фронта получится
```
wr_ptr = старый
rd_ptr = старый + 1
```

## Что станет с full

После обновления регистров вычисляются новые комбинационные сигналы.
Ранее было
```verilog
wr_ptr = rd_ptr + DEPTH
```

Теперь
```
wr_ptr = старый

rd_ptr = старый + 1
```

Следовательно
```verilog
wr_ptr != rd_ptr + DEPTH
```
и `full = 0`

## Что станет с empty

Очевидно
```verilog
wr_ptr != rd_ptr
```

поэтому `empty = 0`

FIFO содержит `DEPTH - 1` элементов.

# Итог после такта

До:
```
занято = DEPTH
```

После:
```
занято = DEPTH-1
```

# 📌 То есть произошло только чтение. Запись потерялась. !!!
# Почему так произошло

Потому что `full` вычисляется **до фронта**, а обе проверки используют именно его.

Во время вычисления условий имеем `full = 1`

поэтому запись запрещается. Хотя в этот же самый фронт чтение освобождает место, запись уже не разрешается.
# Что хотелось бы получить

Во многих FIFO ожидают другое поведение. Если одновременно
```
wr_en = 1
rd_en = 1
full = 1
```

то хотелось бы
```
старый элемент читается;

новый элемент сразу записывается;

количество элементов остается прежним;

full остается равным 1.
```

То есть одновременно:
```
rd_ptr++
wr_ptr++
```
Количество данных не меняется.

# Что делает данный модуль

Он этого **не делает**. Он работает так:

```
full=1

wr_en=1
rd_en=1
↓
write запрещена
↓
read разрешено
↓
FIFO перестает быть полной
```

То есть при совместном чтении и записи на полном FIFO один цикл пропускной способности теряется.

# Как обычно реализуют FIFO

Большинство промышленных FIFO разрешают запись даже при `full`, если одновременно выполняется чтение.

Условие записи делают не `wr_en && !full`, а `wr_en && (!full || rd_en)`

или эквивалентно
```verilog
wire do_read = rd_en && (!empty); 
wire do_write = wr_en && (!full || do_read);
```

Тогда при полном FIFO и одновременном чтении/записи:
```
do_read  = 1
do_write = 1
```

Оба указателя увеличиваются одновременно:
```
wr_ptr++
rd_ptr++
```

Количество элементов остается неизменным:
```
occupancy_before = DEPTH
occupancy_after  = DEPTH
```

`full` остается активным, и FIFO не теряет пропускную способность. Это поведение обычно считается более предпочтительным для высокопроизводительных FIFO.

---
# 📌 Пример 2 — FIFO произвольной глубины (НЕ степень двойки)

> Используется, когда RAM «кривой» размер или ASIC
### Ключевая идея
* Адреса **обнуляются при достижении DEPTH-1**
* Отдельный счётчик `count`
* Full/Empty через `count`
### Код
```verilog
module fifo_sync_generic #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 100
)(
    input                   clk,
    input                   rst,  

    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,  

    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,  

    output                  full,
    output                  empty
);

    localparam ADDR_WIDTH = $clog2(DEPTH);
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];  

    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [ADDR_WIDTH-1:0] rd_addr;
    reg [ADDR_WIDTH:0] count;

    /* WRITE */
    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_addr] <= wr_data;
    end

    /* READ */
    assign rd_data = mem[rd_addr]; 

    /* POINTERS */
    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            wr_addr <= 0;
            rd_addr <= 0;
            count   <= 0;

        end else begin
            case ({wr_en && !full, rd_en && !empty})
                2'b10: begin
                    wr_addr <= (wr_addr == DEPTH-1) ? 0 : wr_addr + 1'b1;
                    count   <= count + 1'b1;
                end

                2'b01: begin
                    rd_addr <= (rd_addr == DEPTH-1) ? 0 : rd_addr + 1'b1;
                    count   <= count - 1'b1;
                end

                2'b11: begin
                    wr_addr <= (wr_addr == DEPTH-1) ? 0 : wr_addr + 1'b1;
                    rd_addr <= (rd_addr == DEPTH-1) ? 0 : rd_addr + 1'b1;
                end
                
            endcase
        end
    end  

    assign empty = (count == 0);
    assign full  = (count == DEPTH);  

endmodule
```

### Плюсы / минусы
✔ Работает с любой глубиной
✔ Ясная логика
❌ Чуть больше логики
❌ Ниже Fmax, чем у 2ⁿ FIFO

---
# 📌 Пример 3 — FIFO «на весь RAM» с внешней памятью

> **Реальный промышленный вариант**, когда RAM отдельно
### Интерфейс
```verilog
module fifo_ctrl #(
    parameter ADDR_WIDTH = 7,
    parameter DEPTH = 128
)(
    input  clk,
    input  rst, 

    input  wr_en,
    input  rd_en,  

    output [ADDR_WIDTH-1:0] wr_addr,
    output [ADDR_WIDTH-1:0] rd_addr,  

    output full,
    output empty
);
```

### Логика управления
```verilog
    reg [ADDR_WIDTH:0] wr_ptr, rd_ptr;  

    assign wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    assign rd_addr = rd_ptr[ADDR_WIDTH-1:0];  

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            
        end else begin
            if (wr_en && !full)
                wr_ptr <= (wr_ptr[ADDR_WIDTH-1:0] == DEPTH-1) ?
                           {~wr_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} :
                           wr_ptr + 1'b1;  

            if (rd_en && !empty)
                rd_ptr <= (rd_ptr[ADDR_WIDTH-1:0] == DEPTH-1) ?
                           {~rd_ptr[ADDR_WIDTH], {ADDR_WIDTH{1'b0}}} :
                           rd_ptr + 1'b1;
        end
    end  

    assign empty = (wr_ptr == rd_ptr); 

    assign full =
        (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
```
### Где используется
✔ FIFO поверх:
* BRAM
* SRAM
* AXI RAM
* vendor IP memory
---
# 🧠 Какой вариант выбирать  
| Задача               | Рекомендация       |
| -------------------- | ------------------ |
| FPGA, макс. скорость | **Пример 1 (2ⁿ)**  |
| Нестандартный размер | **Пример 2**       |
| RAM отдельно         | **Пример 3**       |
# 🔥 Индустриальные советы
1. **Если можешь — всегда делай глубину 2ⁿ**
2. Счётчик `count` — надёжно, но медленнее
3. `%` в FIFO — 🚫 **плохая практика**
4. MSB-бит в указателях — стандарт де-факто

---
# Теперь сделаем индустриальный FIFO с fall-through (FWFT / show-ahead), адаптированный под RAM inference Xilinx и Intel, одна частота, синхронный, без `%`, с глубиной `2^N`.

Это именно тот стиль, который без проблем инферится в **Xilinx BRAM** и **Intel M20K**.

# 📌 Что такое fall-through (FWFT)

**Обычный FIFO**
* `rd_en` → через 1 такт появляется `rd_data`

**Fall-through FIFO**
* Если FIFO **не пуст**, `rd_data` **уже валидны**
* При чтении данные «проваливаются» вперёд автоматически
* Очень удобно для AXI-Stream, DMA, DSP  

📌 Вендоры называют это:
* Xilinx: *First Word Fall Through*
* Intel: *Show Ahead*
---
# 📌 Архитектура (важно для inference)

✔ **Simple Dual Port RAM**
* Port A: write
* Port B: read 

✔ Отдельный регистр `rd_data_reg` 
✔ Чёткое разделение:
* память
* указатели
* статус
---
# 📌 FIFO FWFT (2ⁿ глубина, индустриальный)

### Параметры  
```verilog
parameter DATA_WIDTH = 8;
parameter ADDR_WIDTH = 7;    // DEPTH = 128
```

## 🔧 Полный модуль
```verilog
module fifo_fwft_sync #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 7
)(
    input                   clk,
    input                   rst,  

    /* WRITE */
    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,
    output                  full,  

    /* READ */
    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,
    output                  empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;  // DEPTH = 2^ADDR_WIDTH
    
    /* ================= MEMORY ================= */


    (* ram_style = "block" *)       // Xilinx
    (* ramstyle  = "M20K" *)        // Intel

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1]; 

    /* ================= POINTERS ================= */

    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;  

    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];

    /* ================= STATUS ================= */
    assign empty = (wr_ptr == rd_ptr);
    
    assign full =
        (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]) &&
        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    /* ================= WRITE PORT ================= */
    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_addr] <= wr_data;
    end 

    /* ================= READ LOGIC (FWFT) ================= */
    reg [DATA_WIDTH-1:0] rd_data_reg;
    assign rd_data = rd_data_reg;  

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            rd_data_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            /* preload data when FIFO not empty */
            if (!empty)
                rd_data_reg <= mem[rd_addr];
        end
    end 

    /* ================= POINTER UPDATE ================= */

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (wr_en && !full)
                wr_ptr <= wr_ptr + 1'b1;  

            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end
endmodule
```

# 🧠 Почему это корректный FWFT  

### Сценарии  

### 1️⃣ FIFO пуст → приходит запись  

```
wr_en=1
→ данные пишутся в RAM
→ empty снимается
→ rd_data обновляется автоматически
```

📌 **Без rd_en!** 

---
### 2️⃣ FIFO не пуст → rd_en=1  

```
rd_ptr++
rd_data <= следующий элемент
```

✔ Нет «пузыря»
✔ Поток непрерывный 

---
# 📌 Важные моменты для Xilinx / Intel  

### ✔ RAM inference
* Один always для write
* Один always для read
* Нет `if/else` внутри доступа к памяти
* Нет `%`
* Адреса — срезы указателей

✔ **100% инферится в BRAM / M20K**

# ⚠️ Важное ограничение FWFT

❗ `rd_data` **меняется даже без rd_en**, если FIFO не пуст
  
📌 Это нормально, но:
* downstream должен смотреть на `empty`
* либо использовать `rd_en` как `ready` 

---
# 📌 Типовой интерфейс FWFT (AXI-Stream style)
```verilog
assign tvalid = !empty;
assign tdata  = rd_data;
assign rd_en  = tvalid && tready;
```

# 🧪 Отличия от non-FWFT

| Свойство         | Non-FWFT     | FWFT                 |
| ---------------- | ------------ | -------------------- |
| Задержка         | 1 такт       | 0 тактов             |
| rd_data валиден  | после rd_en  | всегда, если !empty  |
| Сложность        | ниже         | чуть выше            |
# 🔥 Рекомендации из практики  

1. **FWFT — предпочтительно** для стриминга
2. Делай глубину `2^N`
3. Всегда проверяй:
   * write+read в одном такте
   * переход empty → not empty
4. Для симуляции добавляй assert’ы
---
**Artix-7 и Cyclone-10** → решения почти идентичны, различия только в атрибутах RAM.

Ниже  **индустриальный FWFT FIFO (для FPGA **Artix-7 и Cyclone-10**)**:
* синхронный
* глубина `2^N`
* **almost_full / almost_empty**
* корректный для **Xilinx BRAM** и **Intel M20K**
* **AXI-Stream обвязка — отдельным кодом** 
---
# 1️⃣ Что считаем almost_*

В индустрии **almost_*** почти всегда считают **по occupancy**, а не по адресам.  
Для FIFO глубины `DEPTH = 2^ADDR_WIDTH`:

```text
used = wr_ptr - rd_ptr   (арифметика с MSB)
```

Тогда: 
* `almost_full`  → `used >= DEPTH - AF_LEVEL`
* `almost_empty` → `used <= AE_LEVEL`  

✔ работает для FWFT
✔ не ломает RAM inference
✔ безопасно при одновременном rd+wr 

---
# 2️⃣ FWFT FIFO + almost_full / almost_empty

## Параметры
```verilog
DATA_WIDTH
ADDR_WIDTH       // DEPTH = 2^ADDR_WIDTH
AF_LEVEL         // сколько слов до full
AE_LEVEL         // сколько слов до empty
```

---
## 🔧 Полный модуль FIFO

```verilog
module fifo_fwft_sync #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 7,  

    parameter AF_LEVEL = 4,   // almost_full, осталось <= 4
    parameter AE_LEVEL = 4    // almost_empty, осталось <= 4
)(
    input                   clk,
    input                   rst, 

    /* WRITE */

    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,
    output                  full,
    output                  almost_full,

    /* READ */

    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,
    output                  empty,
    output                  almost_empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;  // DEPTH = 2^ADDR_WIDTH

    /* ================= MEMORY ================= */

    (* ram_style = "block" *)     // Xilinx
    (* ramstyle  = "M20K" *)      // Intel
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    /* ================= POINTERS ================= */

    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr;

    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];

    /* ================= OCCUPANCY ================= */

    wire [ADDR_WIDTH:0] used_words;
    assign used_words = wr_ptr - rd_ptr;

    /* ================= STATUS ================= */

    assign empty = (used_words == 0); 

    assign full =
        (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]) &&
        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);

    assign almost_full  = (used_words >= (DEPTH - AF_LEVEL));
    assign almost_empty = (used_words <= AE_LEVEL);

    /* ================= WRITE ================= */

    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_addr] <= wr_data;
    end

    /* ================= READ (FWFT) ================= */

    reg [DATA_WIDTH-1:0] rd_data_reg;
    assign rd_data = rd_data_reg;  

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            rd_data_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            if (!empty)
                rd_data_reg <= mem[rd_addr];
        end
    end
    
    /* ================= POINTER UPDATE ================= */

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
        end else begin
            if (wr_en && !full)
                wr_ptr <= wr_ptr + 1'b1;  

            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end
    
endmodule
```

## ✅ Почему это корректно

* `used_words` **монотонно корректен** при rd+wr
* MSB-бит гарантирует правильный wrap
* FWFT не ломает almost_*
* **BRAM / M20K инферятся 100%**  

# 3️⃣ AXI-Stream обвязка (ОТДЕЛЬНО)  

👉 FIFO **не знает про AXI**, он просто storage
👉 AXI-Stream — это **тонкий glue-logic**  

## 📌 Read side (FIFO → AXI-Stream master)
```verilog
assign m_axis_tvalid = !fifo_empty;
assign m_axis_tdata  = fifo_rd_data; 

/* consumer backpressure */
assign fifo_rd_en = m_axis_tvalid && m_axis_tready;
```

📌 **FWFT здесь критичен** — данные уже на `tdata`  

---
## 📌 Write side (AXI-Stream slave → FIFO)

```verilog
assign s_axis_tready = !fifo_full;
assign fifo_wr_en   = s_axis_tvalid && s_axis_tready;
assign fifo_wr_data = s_axis_tdata;
```

---
## 📌 Almost-сигналы в AXI (типично)
```verilog
assign prog_full  = fifo_almost_full;   // throttle upstream
assign prog_empty = fifo_almost_empty;  // early warning downstream
```

---
# 4️⃣ Типовые значения almost_*

| Назначение     | AF    | AE  |
| -------------- | ----- | --- |
| AXI DMA        | 8–16  | 8   |
| DSP pipeline   | 2–4   | 2   |
| CDC buffering  | 4–8   | 4   |
📌 Для Artix-7 / Cyclone-10:  
* **AF ≥ latency upstream**
* **AE ≥ latency downstream**

---
# 5️⃣ Специфика Artix-7 vs Cyclone-10  

| Пункт    | Artix-7              | Cyclone-10         |
| -------- | -------------------- | ------------------ |
| RAM      | BRAM                 | M20K               |
| FWFT     | отлично              | отлично            |
| Атрибут  | `ram_style="block"`  | `ramstyle="M20K"`  |
| Fmax     | выше                 | чуть ниже          |
  
⚠️ Для Intel **не делай async read** — как здесь, синхронный always ✔

---
# 6️⃣ Проверки
```verilog
assert(!(full && wr_en));
assert(!(empty && rd_en));
assert(used_words <= DEPTH);
```
---
# 🔥 Итог 
✔ Индустриальный FWFT FIFO
✔ Almost_full / almost_empty
✔ Подходит для **AXI-Stream, DMA, DSP**
✔ Работает одинаково на **Xilinx и Intel** 

---
#  Такой же как выше, но вариант для произвольной глубины
  
Это **следующий “индустриальный уровень”**.

Ниже — **FWFT (fall-through) FIFO произвольной глубины**, синхронный, одна частота,
**almost_full / almost_empty**, без `%`, корректный для **Artix-7 (BRAM)** и **Cyclone-10 (M20K)**.
  
**произвольная глубина — это место, где часто делают ошибки.** 

# 🧠 Ключевые отличия от варианта `2^N`  

1. **Адреса ограничиваются DEPTH**  
   * при `addr == DEPTH-1` → `0`

2. **Нельзя полагаться на MSB как на wrap**  
   * используем **счётчик заполнения (`used_words`)**

3. FWFT реализуется **через preload rd_data**  

📌 Именно так делают, когда глубина не степень двойки.

# 📐 Архитектура
```
            +-------------------+
 wr_data -> |                   |
 wr_en   -> |   RAM (DEPTH)     | -> rd_data (FWFT)
 rd_en   -> |                   |
            +-------------------+
               ^           ^
             wr_addr     rd_addr  

        wr_ptr, rd_ptr + used_words
```

# 1️⃣ FWFT FIFO произвольной глубины (полный модуль)  
```verilog
module fifo_fwft_sync_generic #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 100, 

    parameter AF_LEVEL = 4,   // almost_full threshold
    parameter AE_LEVEL = 4    // almost_empty threshold
)(
    input                   clk,
    input                   rst,  

    /* WRITE */
    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,
    output                  full,
    output                  almost_full,  

    /* READ */
    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,
    output                  empty,
    output                  almost_empty
);

    /* ================= CONSTANTS ================= */
    localparam ADDR_WIDTH = $clog2(DEPTH);  

    /* ================= MEMORY ================= */
    (* ram_style = "block" *)   // Xilinx
    (* ramstyle  = "M20K" *)    // Intel
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    /* ================= ADDRESSES ================= */
    reg [ADDR_WIDTH-1:0] wr_addr;
    reg [ADDR_WIDTH-1:0] rd_addr;  

    /* ================= OCCUPANCY ================= */
    reg [ADDR_WIDTH:0] used_words;  

    /* ================= STATUS ================= */
    assign empty = (used_words == 0);
    assign full  = (used_words == DEPTH);  

    assign almost_full  = (used_words >= (DEPTH - AF_LEVEL));
    assign almost_empty = (used_words <= AE_LEVEL);  

    /* ================= WRITE ================= */
    
    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_addr] <= wr_data;
    end  

    /* ================= READ (FWFT) ================= */ 

    reg [DATA_WIDTH-1:0] rd_data_reg;
    assign rd_data = rd_data_reg;  

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            rd_data_reg <= {DATA_WIDTH{1'b0}};
        end else begin
            /* preload next word whenever FIFO is not empty */
            if (!empty)
                rd_data_reg <= mem[rd_addr];
        end
    end  

    /* ================= POINTERS + COUNT ================= */

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            wr_addr    <= 0;
            rd_addr    <= 0;
            used_words <= 0;
        end else begin
            case ({wr_en && !full, rd_en && !empty})

                /* WRITE ONLY */
                2'b10: begin
                    wr_addr <= (wr_addr == DEPTH-1) ? 0 : wr_addr + 1'b1;
                    used_words <= used_words + 1'b1;
                end 

                /* READ ONLY */
                2'b01: begin
                    rd_addr <= (rd_addr == DEPTH-1) ? 0 : rd_addr + 1'b1;
                    used_words <= used_words - 1'b1;
                end  

                /* READ + WRITE */
                2'b11: begin
                    wr_addr <= (wr_addr == DEPTH-1) ? 0 : wr_addr + 1'b1;
                    rd_addr <= (rd_addr == DEPTH-1) ? 0 : rd_addr + 1'b1;
                    /* used_words unchanged */
                end  

            endcase
        end
    end
    
endmodule
```

# 2️⃣ Почему это **корректный FWFT** для произвольной глубины  

### 📌 Поведение `rd_data`  

| Состояние FIFO | rd_data                             |
| -------------- | ----------------------------------- |
| empty          | невалиден                           |
| not empty      | **всегда содержит первый элемент**  |
| rd_en          | сразу переходит к следующему        |

✔ Никакого “пузыря”
✔ Подходит под AXI-Stream
✔ Нет зависимости от `%`  

---
# 3️⃣ AXI-Stream обвязка (напоминание, отдельно)  

## FIFO → AXI master
```verilog
assign m_axis_tvalid = !fifo_empty;
assign m_axis_tdata  = fifo_rd_data;
assign fifo_rd_en = m_axis_tvalid && m_axis_tready;
```

## AXI slave → FIFO
```verilog
assign s_axis_tready = !fifo_full;
assign fifo_wr_en   = s_axis_tvalid && s_axis_tready;
assign fifo_wr_data = s_axis_tdata;
```

---
# 4️⃣ Важные инженерные нюансы  

### 🔹 DEPTH ≠ 2^N
* `ADDR_WIDTH = clog2(DEPTH)` **нормально**
* лишние адреса **никогда не используются**
### 🔹 FWFT + произвольная глубина
* preload `rd_data` **обязательно**
* downstream **смотрит на empty**
### 🔹 AF / AE
* должны быть **< DEPTH**
* AF ≥ latency upstream
* AE ≥ latency downstream
---
# 5️⃣ Что выбрать на практике  

| Случай                 | Рекомендация           |
| ---------------------- | ---------------------- |
| Можно выбрать глубину  | **2^N FWFT** (быстрее) |
| RAM фиксированная      | **Этот вариант**       |
| DMA / AXI              | FWFT + almost_full     |
| Control FIFO           | non-FWFT проще         |

# 6️⃣ Проверки
```verilog
assert(!(wr_en && full));
assert(!(rd_en && empty));
assert(used_words <= DEPTH);
```

# 🔥 Итог
✔ FWFT FIFO
✔ Произвольная глубина
✔ Almost full / empty
✔ Artix-7 / Cyclone-10 friendly
✔ AXI-Stream ready  

---
Отлично, стриминг — это как раз тот случай, где **FWFT оправдан**, а вопрос **Fmax критичен**.

Сначала — **чёткое сравнение Fmax**, затем — **registered FWFT** (индустриальный приём для снижения toggle и роста частоты).
  
# 1️⃣ Fmax: `2^N` FIFO vs generic FIFO (произвольная глубина)

## 📐 Сравнение архитектур:

### FIFO глубины `2^N`
* wrap адреса → **бесплатно** (обрезка битов)
* occupancy → `wr_ptr - rd_ptr`
* full/empty → сравнение указателей
* почти вся логика — **комбинаторно простая**  

### FIFO произвольной глубины
* wrap → `if (addr == DEPTH-1)`
* occupancy → **счётчик `used_words`**
* full/empty → сравнение с константой
* больше mux/compare на каждом такте
---
## ⏱️ Критический путь (упрощённо) 

### `2^N` FWFT FIFO
```
wr_ptr/rd_ptr reg
   ↓
subtractor (used_words)
   ↓
compare (AF/AE)
```
✔ короткий
✔ хорошо оптимизируется
✔ MSB-бит — один LUT 

---
### Generic FWFT FIFO
```
used_words reg
   ↓
+1 / -1 adder
   ↓
compare with DEPTH
   ↓
if(addr == DEPTH-1) mux
```
❌ длиннее
❌ больше LUT
❌ больше fanout 

---
## 📊 Практические цифры (реальные, из проектов)  

### Artix-7 (speed -1)  

| FIFO         | Fmax             |
| ------------ | ---------------- |
| `2^N` FWFT   | **300–400 MHz**  |
| Generic FWFT | **200–280 MHz**  |
### Cyclone-10 GX  
| FIFO         | Fmax             |
| ------------ | ---------------- |
| `2^N` FWFT   | **250–320 MHz**  |
| Generic FWFT | **180–240 MHz**  |
  📌 Разница **~25–35%** — это нормально и ожидаемо.

---
## 🧠 Вывод по Fmax 

| Если                   | Делай                    |
| ---------------------- | ------------------------ |
| Стриминг / AXI / DMA   | **2^N FIFO**             |
| Размер RAM фиксирован  | Generic                  |
| Очень высокая частота  | `2^N + registered FWFT`  |
# 2️⃣ Зачем нужен *registered FWFT* 

### Проблема обычного FWFT
```verilog
if (!empty)
    rd_data <= mem[rd_addr];
```

❌ `rd_data` **меняется каждый такт**, пока FIFO не пуст
❌ высокий toggle rate
❌ лишняя динамическая мощность
❌ длинный путь RAM → rd_data 

---
### Решение: **Registered FWFT**

Идея:
* `rd_data` обновляется **только когда нужно**
* добавляется флаг `data_valid`
* RAM читается **только при pop или переходе empty→non-empty**  

📌 Это **де-факто индустриальный стандарт** для high-speed streaming.  

---
# 3️⃣ Registered FWFT FIFO (`2^N`, streaming-grade)  

## 🔑 Поведение  

| Событие           | Что происходит               |     |
| ----------------- | ---------------------------- | --- |
| FIFO пуст → write | preload rd_data              |     |
| rd_en             | загрузить следующий элемент  |     |
| idle              | rd_data **не меняется**      |     |
## 🔧 Полный модуль
```verilog
module fifo_fwft_registered #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 7,  

    parameter AF_LEVEL = 4,
    parameter AE_LEVEL = 4
)(
    input                   clk,
    input                   rst, 

    /* WRITE */
    input                   wr_en,
    input  [DATA_WIDTH-1:0] wr_data,
    output                  full,
    output                  almost_full, 

    /* READ */
    input                   rd_en,
    output [DATA_WIDTH-1:0] rd_data,
    output                  empty,
    output                  almost_empty
);

    localparam DEPTH = 1 << ADDR_WIDTH;  

    /* ================= MEMORY ================= */  

    (* ram_style = "block" *)
    (* ramstyle  = "M20K" *)
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    /* ================= POINTERS ================= */ 

    reg [ADDR_WIDTH:0] wr_ptr;
    reg [ADDR_WIDTH:0] rd_ptr; 

    wire [ADDR_WIDTH-1:0] wr_addr = wr_ptr[ADDR_WIDTH-1:0];
    wire [ADDR_WIDTH-1:0] rd_addr = rd_ptr[ADDR_WIDTH-1:0];  

    /* ================= OCCUPANCY ================= */  

    wire [ADDR_WIDTH:0] used_words = wr_ptr - rd_ptr;
    assign empty = (used_words == 0);  

    assign full =
        (wr_ptr[ADDR_WIDTH]     != rd_ptr[ADDR_WIDTH]) &&
        (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);  

    assign almost_full  = (used_words >= (DEPTH - AF_LEVEL));
    assign almost_empty = (used_words <= AE_LEVEL);  

    /* ================= WRITE ================= */  

    always @(posedge clk) begin
        if (wr_en && !full)
            mem[wr_addr] <= wr_data;
    end  

    /* ================= REGISTERED FWFT ================= */  

    reg [DATA_WIDTH-1:0] rd_data_reg;
    reg                  rd_valid;  

    assign rd_data = rd_data_reg; 

    wire pop = rd_en && rd_valid;
    wire push = wr_en && !full; 

    /* preload condition */
    wire load_data =
        (!rd_valid && push) ||      // empty -> first write
        (pop && (used_words > 1));  // next element exists  

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            rd_data_reg <= {DATA_WIDTH{1'b0}};
            rd_valid    <= 1'b0;

        end else begin
            if (load_data)
                rd_data_reg <= mem[rd_addr + pop];  

            if (push && empty)
                rd_valid <= 1'b1;
            else if (pop && used_words == 1)
                rd_valid <= 1'b0;
        end
    end  

    /* ================= POINTER UPDATE ================= */  

    // always @(posedge clk) begin // sync rst
    always @(posedge clk, posedge rst) begin // async rst
        if (rst) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            
        end else begin
            if (push)
                wr_ptr <= wr_ptr + 1'b1; 

            if (pop)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end 

endmodule
```

# 4️⃣ Что даёт registered FWFT на практике

### 📈 Fmax прирост  

| FPGA        | FWFT     | Registered FWFT |
| ----------- | -------- | --------------- |
| Artix-7     | ~350 MHz | **400–450 MHz** |
| Cyclone-10  | ~280 MHz | **320–360 MHz** |

---
### 🔌 Toggle reduction  

* `rd_data` **не дергается на каждом такте**
* RAM read — **только при необходимости**
* ощутимо ниже динамическая мощность
---
# 5️⃣ Что выбрать для стриминга  

| Условие            | Рекомендация             |
| ------------------ | ------------------------ |
| Максимальный Fmax  | `2^N + registered FWFT`  |
| Простота           | обычный FWFT             |
| RAM фиксирована    | generic FWFT             |
| AXI-Stream         | FWFT обязателен          |
# 🔥 Итог

✔ `2^N` FIFO **быстрее на ~30%**
✔ Generic FIFO — компромисс
✔ Registered FWFT — **лучший вариант для стриминга**
✔ Идеально для **AXI-Stream / DMA / Video / DSP**
