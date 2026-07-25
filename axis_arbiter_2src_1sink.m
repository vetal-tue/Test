function [s0_ready, s1_ready, ...
          m_valid, m_data, m_keep, m_last] = axi_arbiter( ...
    s0_valid, s0_data, s0_keep, s0_last, ...
    s1_valid, s1_data, s1_keep, s1_last, ...
    m_ready)
%#codegen

% DATA_T = uint16;
% KEEP_T = uint8;

persistent sel
persistent in_packet

if isempty(sel)
    sel = false; % 0 → s0, 1 → s1
end
if isempty(in_packet)
    in_packet = false;
end

% default outputs
m_valid = false;
m_data  = uint16(0);
m_keep  = uint8(0);
m_last  = false;

s0_ready = false;
s1_ready = false;

% if reset
%     sel = false;
% else

    if sel == 0
        % ===== SELECT S0 =====
        if s0_valid
            m_valid = true;
            m_data  = s0_data;
            m_keep  = s0_keep;
            m_last  = s0_last;

            s0_ready = m_ready;

            % мы в пакете
            in_packet = true;

            % переключаемся ТОЛЬКО в конце пакета
            if m_ready && s0_last
                in_packet = false;
                sel = ~sel; % можно переключаться
            end

        else
            % ВАЖНО: если мы в пакете — НЕЛЬЗЯ переключаться
            if ~in_packet && s1_valid
                sel = ~sel;
            end
        end

    else
        % ===== SELECT S1 =====
        if s1_valid
            m_valid = true;
            m_data  = s1_data;
            m_keep  = s1_keep;
            m_last  = s1_last;

            s1_ready = m_ready;
            in_packet = true;

            if m_ready && s1_last
                in_packet = false;
                sel = ~sel;
            end

        else
            if ~in_packet && s0_valid
                sel = ~sel;
            end
        end
    end

% end
% 
% end