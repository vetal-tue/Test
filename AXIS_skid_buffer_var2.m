function [s_ready, m_valid, m_data, m_last] = axi_skid_buffer( ...
    s_valid, s_data, s_last, m_ready)
%#codegen

% DATA_T = uint16;

% Основной регистр (output stage)
persistent out_valid out_data out_last

% Skid buffer (backup)
persistent skid_valid skid_data skid_last

if isempty(out_valid)
    out_valid  = false;
    out_data   = uint16(0);
    out_last   = false;
    
    skid_valid = false;
    skid_data  = uint16(0);
    skid_last  = false;
end

%% =========================
% OUTPUT (AXI master side)
%% =========================
m_valid = out_valid;
m_data  = out_data;
m_last  = out_last;

%% =========================
% READY (AXI slave side)
%% =========================

% можем принимать, если:
% - есть место в skid buffer
% - или downstream готов
s_ready = ~skid_valid;

%% =========================
% Основная логика
%% =========================

% if reset
%     out_valid  = false;
%     skid_valid = false;

% else
    
    % =====================
    % CASE 1: downstream готов
    % =====================
    if m_ready
        
        if skid_valid
            % сначала выгружаем skid buffer
            out_valid = true;
            out_data  = skid_data;
            out_last  = skid_last;
            skid_valid = false;
            
        elseif s_valid
            % напрямую пропускаем вход
            out_valid = true;
            out_data  = s_data; % обработка
            out_last  = s_last;
            
        else
            out_valid = false;
        end
        
    % =====================
    % CASE 2: downstream НЕ готов (backpressure)
    % =====================
    else
        
        if s_valid && ~skid_valid
            % сохраняем во временный буфер
            skid_valid = true;
            skid_data  = s_data;
            skid_last  = s_last;
        end
        
        % удерживаем текущий output
        % out_valid = out_valid;
    end
    
% end

end