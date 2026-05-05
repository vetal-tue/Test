function [axi_tdata, axi_tvalid, axi_tlast, av_ready] = avalon_to_axi( ...
    av_data, av_valid, av_endofpacket, axi_tready, reset_in)

DEPTH = 4;
SAFE_MARGIN = 2;
fm = fimath('OverflowMode','Wrap');

persistent rd_ptr wr_ptr count data_buf last_buf
if isempty(rd_ptr)
    % data_buf  = uint16(zeros(DEPTH,1));
    data_buf  = cast(zeros(DEPTH,1), 'like', av_data);
    last_buf  = false(DEPTH,1);

    rd_ptr = fi(0,0,ceil(log2(DEPTH)),0,fm);
    wr_ptr = fi(0,0,ceil(log2(DEPTH)),0,fm);
    count  = fi(0,0,ceil(log2(DEPTH))+1,0,fm);
end

% =========================
% READY (с запасом)
% =========================
av_ready = (count < (DEPTH - SAFE_MARGIN));

% =========================
% CONTROL
% =========================
write_en = av_valid && (count < DEPTH);
read_en  = (count > 0) && axi_tready;

% =========================
% OUTPUT
% =========================
axi_tvalid = (count > 0);

axi_tdata = data_buf(uint8(rd_ptr)+1);
axi_tlast = last_buf(uint8(rd_ptr)+1);

% =========================
% WRITE
% =========================
if write_en
    data_buf(uint8(wr_ptr)+1)  = av_data;
    last_buf(uint8(wr_ptr)+1)  = av_endofpacket;

    if wr_ptr == DEPTH-1
        % wr_ptr = uint8(1);
        wr_ptr = fi(0,0,wr_ptr.WordLength,0,fm);
    else
        % wr_ptr = wr_ptr + 1;
        wr_ptr = fi(wr_ptr + 1,0,wr_ptr.WordLength,0,fm);
    end
end

% =========================
% READ
% =========================
if read_en

    if rd_ptr == DEPTH-1
        % rd_ptr = uint8(1);
        rd_ptr = fi(0,0,rd_ptr.WordLength,0,fm);
    else
        % rd_ptr = rd_ptr + 1;
        rd_ptr = fi(rd_ptr + 1,0,rd_ptr.WordLength,0,fm);
    end
end

% =========================
% COUNT
% =========================
if (read_en && ~write_en)
    count = fi(count - 1, 0, count.WordLength, 0, fm);
elseif (~read_en && write_en)
    count = fi(count + 1, 0, count.WordLength, 0, fm);
end
%  Both or neither: cnt unchanged.

% sel = bitconcat(fi(write_en,0,1,0,fm), fi(read_en,0,1,0,fm));
% 
% switch uint8(sel)
%     case 2
%         count = fi(count + 1, 0, count.WordLength, 0, fm);
%     case 1
%         count = fi(count - 1, 0, count.WordLength, 0, fm);
%     otherwise
% end

