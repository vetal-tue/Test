function [s_ready, m_valid, m_data, m_last] = axi_skid2_buffer(s_valid, s_data, s_last, m_ready)
%#codegen

persistent v0 d0 l0
persistent v1 d1 l1

if isempty(v0)
    v0 = false; d0 = uint16(0); l0 = false;
    v1 = false; d1 = uint16(0); l1 = false;
end

% Текущие выходы
m_valid = v1;
m_data  = d1;
m_last  = l1;
s_ready = ~v0 || ~v1;

% Инициализируем переменные следующего состояния текущими значениями
v0_next = v0; d0_next = d0; l0_next = l0;
v1_next = v1; d1_next = d1; l1_next = l1;

% 1. Логика продвижения/освобождения выхода
if (m_ready || ~v1)
    v1_next = v0;
    d1_next = d0;
    l1_next = l0;
    v0_next = false; % v0 освободился, так как его содержимое ушло в v1
end

% 2. Логика приема входных данных (использует v0_next и v1_next)
if (s_valid && s_ready)
    % Если после шага 1 выходной регистр оказался пуст, пишем сразу туда (транзит)
    if (~v1_next)
        v1_next = true;
        d1_next = s_data;
        l1_next = s_last;
    else
        % Если выход занят, кладем в буфер stage 0
        v0_next = true;
        d0_next = s_data;
        l0_next = s_last;
    end
end

% Синхронное обновление регистров (в Verilog это превратится в один блок always @posedge)
v0 = v0_next; d0 = d0_next; l0 = l0_next;
v1 = v1_next; d1 = d1_next; l1 = l1_next;

end
