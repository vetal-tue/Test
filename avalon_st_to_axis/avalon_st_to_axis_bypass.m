function [axi_tdata, axi_tvalid, axi_tlast, av_ready] = avalon_to_axi_timing( ...
    av_data, av_valid, av_last, axi_tready, reset_in)

DEPTH = 4;
SAFE_MARGIN = 2;
fm = fimath('OverflowMode','Wrap');

persistent rd_ptr wr_ptr count data_buf last_buf
persistent hold_valid hold_data hold_last

% output register (ключ к timing)
persistent out_valid out_data out_last

if isempty(rd_ptr)
    data_buf  = uint16(zeros(DEPTH,1));
    last_buf  = false(DEPTH,1);

    rd_ptr = fi(0,0,ceil(log2(DEPTH)),0,fm);
    wr_ptr = fi(0,0,ceil(log2(DEPTH)),0,fm);
    count  = fi(0,0,ceil(log2(DEPTH))+1,0,fm);

    hold_valid = false;
    hold_data  = uint16(0);
    hold_last  = false;

    out_valid = false;
    out_data  = uint16(0);
    out_last  = false;
end

fifo_empty = (count == 0);

% =========================
% READY
% =========================
av_ready = (count < (DEPTH - SAFE_MARGIN));

% =========================
% SOURCE SELECT (до регистрации)
% =========================
use_hold = hold_valid;
use_fifo = ~fifo_empty;

if use_hold
    sel_valid = true;
    sel_data  = hold_data;
    sel_last  = hold_last;

elseif use_fifo
    sel_valid = true;
    sel_data  = data_buf(uint8(rd_ptr)+1);
    sel_last  = last_buf(uint8(rd_ptr)+1);

else
    sel_valid = av_valid;
    sel_data  = av_data;
    sel_last  = av_last;
end


% =========================
% OUTPUT REGISTER (timing fix)
% =========================
if axi_tready || ~out_valid
    out_valid = sel_valid;
    out_data  = sel_data;
    out_last  = sel_last;
end

axi_tvalid = out_valid;
axi_tdata  = out_data;
axi_tlast  = out_last;

axi_fire = axi_tvalid && axi_tready;

% =========================
% HOLD
% =========================
if ~axi_tready && fifo_empty && av_valid && ~hold_valid
    hold_valid = true;
    hold_data  = av_data;
    hold_last  = av_last;

elseif axi_tready && hold_valid
    hold_valid = false;
end

% =========================
% CONTROL FIFO
% =========================
bypass = fifo_empty && av_valid && axi_tready && ~hold_valid;

write_en = av_valid && (count < DEPTH) && ~bypass;
read_en  = (count > 0) && axi_fire && ~hold_valid;

% =========================
% WRITE
% =========================
if write_en
    data_buf(uint8(wr_ptr)+1) = av_data;
    last_buf(uint8(wr_ptr)+1) = av_last;

    if wr_ptr == DEPTH-1
        wr_ptr = fi(0,0,wr_ptr.WordLength,0,fm);
    else
        wr_ptr = fi(wr_ptr + 1,0,wr_ptr.WordLength,0,fm);
    end
end

% =========================
% READ
% =========================
if read_en
    if rd_ptr == DEPTH-1
        rd_ptr = fi(0,0,rd_ptr.WordLength,0,fm);
    else
        rd_ptr = fi(rd_ptr + 1,0,rd_ptr.WordLength,0,fm);
    end
end

% =========================
% COUNT
% =========================
sel = bitconcat(fi(write_en,0,1,0,fm), fi(read_en,0,1,0,fm));

switch uint8(sel)
    case 2
        count = fi(count + 1, 0, count.WordLength, 0, fm);
    case 1
        count = fi(count - 1, 0, count.WordLength, 0, fm);
end
