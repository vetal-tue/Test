function [av_data, av_valid, av_startofpacket, av_endofpacket, axi_tready] = axis_to_avalon_skid2( ...
    axi_tdata, axi_tvalid, axi_tlast, av_ready)

persistent data0 valid0 last0;
persistent data1 valid1 last1;
persistent in_packet;

if isempty(valid0)
    data0 = cast(0, 'like', axi_tdata); valid0 = false; last0 = false;
    data1 = cast(0, 'like', axi_tdata); valid1 = false; last1 = false;
    in_packet = false;
end

% =========================
% OUTPUT LOGIC (stage0)
% =========================
av_valid = valid0;
av_data  = data0;

av_startofpacket = valid0 && ~in_packet;
av_endofpacket   = valid0 && last0;

% =========================
% AXI READY
% =========================
% можем принимать, если есть место хотя бы в одном регистре
axi_tready = ~valid1;

% =========================
% NEXT STATE (локальные копии)
% =========================
next_data0 = data0; next_valid0 = valid0; next_last0 = last0;
next_data1 = data1; next_valid1 = valid1; next_last1 = last1;
% next_in_packet = in_packet;

% =========================
% 1. Выдача в Avalon
% =========================
if valid0 && av_ready
    next_valid0 = false;

    if last0
        in_packet = false;
    else
        in_packet = true;
    end
end

% =========================
% 2. Перемещение stage1 -> stage0
% =========================
if (~next_valid0) && valid1
    next_data0  = data1;
    next_valid0 = true;
    next_last0  = last1;

    next_valid1 = false;
end

% =========================
% 3. Прием AXI
% =========================
if axi_tready && axi_tvalid
    if ~next_valid0
        % сразу в stage0
        next_data0  = axi_tdata;
        next_valid0 = true;
        next_last0  = axi_tlast;
    else
        % в skid (stage1)
        next_data1  = axi_tdata;
        next_valid1 = true;
        next_last1  = axi_tlast;
    end
end

% =========================
% COMMIT
% =========================
data0 = next_data0; valid0 = next_valid0; last0 = next_last0;
data1 = next_data1; valid1 = next_valid1; last1 = next_last1;
% in_packet = next_in_packet;
