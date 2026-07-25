function [s_ready, m_valid, m_data, m_keep, m_last] = AXIS_skid_buffer( ...
    s_valid, s_data, s_keep, s_last, m_ready)
%#codegen

DATA_T = uint16;
KEEP_T = uint8;

persistent full
persistent data_r keep_r last_r

if isempty(full)
    full   = false;
    data_r = DATA_T(0);
    keep_r = KEEP_T(0);
    last_r = false;
end

% output
m_valid = full || s_valid;

if full
    m_data = data_r;
    m_keep = keep_r;
    m_last = last_r;
else
    m_data = s_data;
    m_keep = s_keep;
    m_last = s_last;
end

% ready назад
s_ready = ~full;

% === state update ===
if m_ready
    if full
        % отдали буфер
        full = false;
    elseif s_valid
        % passthrough, ничего не буферим
    end
else
    if s_valid && ~full
        % захватываем в буфер
        full   = true;
        data_r = s_data;
        keep_r = s_keep;
        last_r = s_last;
    end
end

end
