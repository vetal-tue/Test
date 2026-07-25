function [s_ready, m_valid, m_data, m_last] = axi_skid_buffer( ...
    s_valid, s_data, s_last, m_ready)
%#codegen

% Основной регистр (Output stage)
persistent out_valid out_data out_last
% Дополнительный регистр (Skid/Backup stage)
persistent skid_valid skid_data skid_last
% Регистр готовности для ведомого интерфейса (Изоляция входа s_ready)
persistent ready_reg


if isempty(out_valid)
    out_valid  = false;
    out_data   = uint16(0);
    out_last   = false;
    
    skid_valid = false;
    skid_data  = uint16(0);
    skid_last  = false;

    ready_reg  = true; % Изначально мы готовы принимать данные
end

%% ========================================================================
% 1. Логика выходов и готовности (СТРОГО ИЗ РЕГИСТРОВ — идеальный тайминг для Fmax)
%% ========================================================================
m_valid = out_valid;
m_data  = out_data;
m_last  = out_last;
s_ready = ready_reg;

% % Готовы принимать, только если skid-буфер пуст.
% % Это гарантирует, что нам всегда есть куда положить данные (в out или в skid).
% s_ready = ~skid_valid;

%% ========================================================================
% 2. Логика переходов (Тактовая защелка)
%% ========================================================================

% Произошел ли перенос данных на Master-стороне в ЭТОМ такте?
% Так как m_valid — это регистр, мы смотрим на текущие значения выходов.
out_transfer = out_valid && m_ready;

% Произошел ли прием данных на Slave-стороне в ЭТОМ такте?
input_transfer = s_valid && ready_reg;

% Временные переменные для следующего состояния регистров
next_out_valid  = out_valid;
next_out_data   = out_data;
next_out_last   = out_last;

next_skid_valid = skid_valid;
next_skid_data  = skid_data;
next_skid_last  = skid_last;

if (out_transfer)
    % СЛУЧАЙ 1: Потребитель забрал данные из out_stage в этом такте
    if (skid_valid)
        % Если в skid buffer были данные — двигаем их на выход
        next_out_valid = true;
        next_out_data  = skid_data;
        next_out_last  = skid_last;
        
        % Важнейший момент для устранения пузырей:
        % Если ОДНОВРЕМЕННО пришел новый кадр на вход, мы перемещаем его в skid-буфер,
        % так как старые данные из skid-буфера только что ушли в out_stage.
        if (input_transfer)
            next_skid_valid = true;
            next_skid_data  = s_data;
            next_skid_last  = s_last;
        else
            next_skid_valid = false;
        end
    else
        % Если в skid buffer пусто — пишем в out_stage напрямую со входа (если пришло)
        if (input_transfer)
            next_out_valid = true;
            next_out_data  = s_data;
            next_out_last  = s_last;
        else
            next_out_valid = false;
        end
    end
else
    % СЛУЧАЙ 2: Master-выход заблокирован (m_ready == 0 или данных не было)
    if (input_transfer)
        % Если на выходе уже что-то занято (out_valid == true)
        if (out_valid)
            % Данные на выходе стоят, но мы обязаны принять входящие данные,
            % так как в начале этого такта мы выставили ready_reg = true.
            % Отправляем их в skid-буфер.
            next_skid_valid = true;
            next_skid_data  = s_data;
            next_skid_last  = s_last;
        else
            % Если out_stage был пуст (например, первая инициализация),
            % пишем сразу в основной регистр.
            next_out_valid = true;
            next_out_data  = s_data;
            next_out_last  = s_last;
        end
    end
end

%% ========================================================================
% 3. Расчет s_ready для СЛЕДУЮЩЕГО такта (Тоже регистрируется!)
%% ========================================================================
% Мы сможем принять данные в следующем такте, если:
% Выход освобождается (next_out_valid станет false или улетит по m_ready)
% ИЛИ резервный буфер останется пустым (next_skid_valid == false).
ready_reg = ~next_skid_valid;


%% ========================================================================
% 4. Фиксация состояний persistent-переменных
%% ========================================================================
out_valid  = next_out_valid;
out_data   = next_out_data;
out_last   = next_out_last;

skid_valid = next_skid_valid;
skid_data  = next_skid_data;
skid_last  = next_skid_last;
