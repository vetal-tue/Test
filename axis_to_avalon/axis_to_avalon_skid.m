function [av_data, av_valid, av_startofpacket, av_endofpacket, axi_tready] = ...
    axis_to_avalon(axi_tdata, axi_tvalid, axi_tlast, av_ready)
%AXIS_TO_AVALON  AXI4-Stream → Avalon-ST bridge (registered, skid buffer)
  %                         ┌─────────────────────────────────┐
  %                         │         axis_to_avalon          │
  %                         │                                 │
  % axi_tdata ──┐   ┌───────┤──► [skid_buf] ──► [out_reg] ──► ├──► av_data
  % axi_tvalid ─┤   │ MUX   │        │              │         ├──► av_valid
  % axi_tlast ──┤   │       │        │              │         ├──► av_startofpacket
  %             │   │       │   skid_valid      out_valid     ├──► av_endofpacket
  %             │   │       │        │                        │
  %             │   │       │    ┌───┴───┐                    │
  %             │   │       │    │  NOT  ├───────────────────►├──► axi_tready
  %             │   │       │    └───────┘                    │
  % av_ready ───┼───┘       │                                 │
  %             │           │   [first_word] — трекинг SOP    │
  %             │           └─────────────────────────────────┘
  %             │
  %             ▼
  %        Нет комбинаторных путей input → output
  %        Латентность: 1 такт
  %        Ресурсы:     2 × DATA_WIDTH + 9 FF
%
%   Все выходы полностью регистровые: нет комбинаторных путей
%   от входных портов к выходным портам. Для поддержки backpressure
%   без потери данных используется skid-буфер глубиной 1.
%
%   Латентность:  1 такт (в установившемся режиме).
%   Пропускная способность: 1 слово/такт (при отсутствии backpressure).
%   Ресурсы:      2 × DATA_WIDTH + 9 flip-flop.


%% ============================================================
%  Регистры
%  ============================================================

% --- Выходной регистр (output stage) ---
persistent out_data out_valid out_sop out_eop

% --- Skid-буфер (промежуточный регистр) ---
persistent skid_data skid_valid skid_sop skid_eop

% --- Отслеживание границ пакетов ---
%     true = следующее принятое слово является первым в пакете
persistent first_word

if isempty(first_word)
    out_data   = cast(0, 'like', axi_tdata);
    out_valid  = false;
    out_sop    = false;
    out_eop    = false;
    skid_data  = cast(0, 'like', axi_tdata);
    skid_valid = false;
    skid_sop   = false;
    skid_eop   = false;
    first_word = true;
end

%% ============================================================
%  Выходы — напрямую из регистров, без комбинаторной логики
%  от входных портов
%  ============================================================

av_data          = out_data;
av_valid         = out_valid;
av_startofpacket = out_sop;
av_endofpacket   = out_eop;
axi_tready       = ~skid_valid;      % зависит ТОЛЬКО от регистра

%% ============================================================
%  Детекция хэндшейков (комбинаторно, но НЕ на выходных портах)
%  ============================================================

%  Входной хэндшейк: AXI-источник передаёт слово
input_accepted = axi_tvalid && (~skid_valid);

%  Выходной хэндшейк: Avalon-приёмник забирает слово
out_consumed = out_valid && av_ready;

%% ============================================================
%  Метаданные принимаемого слова
%  (вычисляются на основе текущего first_word и входов)
%  ============================================================

new_data = axi_tdata;
new_sop  = first_word;          % SOP = первое слово пакета
new_eop  = axi_tlast;           % EOP = tlast от AXI-источника

%% ============================================================
%  Автомат обновления состояния
%  ============================================================
%
%  Инвариант: если skid_valid = true, то out_valid = true
%  (данные попадают в skid только когда выход занят и не потреблён)
%
%  Три основных сценария:
%
%  A) skid занят  → новый вход невозможен (tready = 0)
%       A1) выход потреблён   → skid → output, skid освобождается
%       A2) выход не потреблён → всё сохраняется (stall)
%
%  B) skid пуст   → новый вход возможен (tready = 1)
%       B1) вход принят, выход свободен  → вход → output напрямую
%       B2) вход принят, выход занят     → вход → skid
%       B3) входа нет, выход потреблён   → output освобождается
%       B4) входа нет, выход не потреблён → всё сохраняется

if skid_valid
    % ---- Сценарий A: skid-буфер занят, вход заблокирован ----
    if out_consumed
        % A1: Avalon-приёмник забрал данные — сливаем skid в output
        out_data   = skid_data;
        out_valid  = true;
        out_sop    = skid_sop;
        out_eop    = skid_eop;
        skid_valid = false;
    end
    % A2: Avalon-приёмник не готов — удерживаем всё без изменений

else
    % ---- Сценарий B: skid-буфер пуст, вход доступен ----
    if input_accepted
        if out_consumed || (~out_valid)
            % B1: Выходной слот свободен — вход идёт сразу в output
            out_data  = new_data;
            out_valid = true;
            out_sop   = new_sop;
            out_eop   = new_eop;
        else
            % B2: Выход занят (stall) — вход буферизуется в skid
            skid_data  = new_data;
            skid_valid = true;
            skid_sop   = new_sop;
            skid_eop   = new_eop;
        end

        % Обновление трекинга границ пакетов
        if axi_tlast
            first_word = true;    % конец пакета — следующий = SOP
        else
            first_word = false;   % середина пакета
        end

    else
        % B3/B4: Входных данных нет
        if out_consumed
            % B3: Выходные данные забраны, новых нет
            out_valid = false;
        end
        % B4: Ничего не происходит — удерживаем состояние
    end
end

end
