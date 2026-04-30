function [axi_tdata, axi_tvalid, axi_tlast, av_ready] = avalon_to_axis( ...
    av_data, av_valid, av_startofpacket, av_endofpacket, axi_tready) %#ok<INUSL>
%AVALON_TO_AXIS  Avalon-ST → AXI4-Stream bridge (registered)

  %                    ┌──────────────────────────────────────────────┐
  %                    │            avalon_to_axis                    │
  %                    │                                              │
  % av_data ──────────►│──┬─── do_bypass ────────┐                    │
  % av_valid ─────────►│  │   (cnt==0 &          │                    │
  % av_endofpacket ───►│  │    out_free)         │                    │
  % av_startofpacket ─►│  │                      ▼                    │
  %                    │  │  ┌────────────┐   ┌──────────┐            │
  %                    │  └─►│ FIFO 4×Dw  │──►│ out_reg  │──►axi_tdata
  %                    │     │            │   │          │──►axi_tvalid
  %                    │     │ cnt>=2:    │   │          │──►axi_tlast
  %                    │     │ av_ready=0 │   └────┬─────┘            │
  %                    │     │            │        │                  │
  %                    │     │ cnt>=4:    │   axi_tready              │
  %                    │     │ stop write │◄───────┘                  │
  %                    │     └────────────┘                           │
  %                    │                                              │
  %                    │  av_ready = (cnt < 2) ─────────────►av_ready │
  %                    └──────────────────────────────────────────────┘

%   Fully registered data path — no combinatorial feedthrough from
%   av_data to axi_tdata or from axi_tready to av_ready.
%
%   Architecture:
%       Avalon-ST → [4-word circular FIFO] → [output register] → AXI4-Stream
%
%   Back-pressure:
%       av_ready deasserts when FIFO occupancy reaches AFULL_THRESH (2).
%       Physical FIFO depth is 4, so 2 free slots remain after deassertion.
%       An upstream source with up to 2 cycles of ready-latency can still
%       push words that will be accepted (the module keeps writing to the
%       FIFO as long as physical space exists, regardless of av_ready).
%
%   Bypass path:
%       When the FIFO is empty and the output register is free, input data
%       loads directly into the output register (still registered — appears
%       on axi_tdata one clock cycle later).  This avoids a 2-cycle bubble
%       on an empty pipeline.
%
fm = fimath('OverflowMode','Wrap');
% ======================= user parameter ==================================
% DATA_WIDTH = 16;            % av_data / axi_tdata width in bits

% ======================= design constants ================================
FIFO_DEPTH   = 4;    % physical depth  (must be power-of-two >= 4)
% FIFO_MASK    = FIFO_DEPTH-1;    % FIFO_DEPTH - 1, for pointer wrap via bitand
AFULL_THRESH = 2;    % av_ready off when cnt >= this
%   FIFO_DEPTH - AFULL_THRESH == 2 → 2-word acceptance margin

% ZERO_DATA = fi(0, 0, DATA_WIDTH, 0);
ZERO_DATA = cast(0, 'like', av_data);

% ======================= persistent state (flip-flops) ===================
persistent fifo_data fifo_last          % FIFO storage arrays
persistent wr_ptr rd_ptr cnt            % FIFO pointers & occupancy
persistent out_data out_last out_valid  % output register

if isempty(out_valid)
    % fifo_data = fi(zeros(1, 4), 0, DATA_WIDTH, 0);
    fifo_data = cast(zeros(1, 4), 'like', av_data);
    fifo_last = false(1, 4);
    % wr_ptr    = uint8(0);   % 0 .. FIFO_DEPTH-1
    % rd_ptr    = uint8(0);
    wr_ptr = fi(0,0,ceil(log2(FIFO_DEPTH)),0,fm);
    rd_ptr = fi(0,0,ceil(log2(FIFO_DEPTH)),0,fm);
    % cnt       = uint8(0);   % 0 .. FIFO_DEPTH
    cnt  = fi(0,0,ceil(log2(FIFO_DEPTH))+1,0,fm);
    out_data  =  cast(0, 'like', av_data);
    out_last  = false;
    out_valid = false;
end

% ======================= drive outputs (purely from registers) ===========
axi_tdata  = out_data;
axi_tvalid = out_valid;
axi_tlast  = out_last;
av_ready   = (cnt < AFULL_THRESH);
%  av_ready depends only on the cnt register — no combinatorial path
%  from axi_tready.

% ======================= combinatorial next-state logic ==================

% -- AXI-side handshake ---------------------------------------------------
out_consumed = out_valid && axi_tready;       % output word accepted by slave
out_free     = ~out_valid || out_consumed;     % output register available

% -- FIFO head read (value gated by do_rd) --------------------------------
% rd_one       = rd_ptr + uint8(1);           % 1-based MATLAB index
fifo_head_d  = fifo_data(uint8(rd_ptr)+1);
fifo_head_l  = fifo_last(uint8(rd_ptr)+1);

% -- Control signals ------------------------------------------------------
%  do_rd     : move FIFO head → output register
%  do_bypass : route input → output register directly (FIFO empty shortcut)
%  do_wr     : write input into FIFO
%
%  do_rd and do_bypass are mutually exclusive (cnt>0 vs cnt==0).

do_rd     = out_free && (cnt > uint8(0));

do_bypass = av_valid && out_free && (cnt == 0);

do_wr     = av_valid && ~do_bypass && (cnt < FIFO_DEPTH);
%  Accepts input even when av_ready==0 — this is the 2-word tolerance:
%  the source may still be pushing after it "sees" the deassertion.

% ======================= update output register ==========================
if (do_rd)
    out_data  = fifo_head_d;
    out_last  = fifo_head_l;
    out_valid = true;
elseif (do_bypass)
    out_data  = av_data;
    out_last  = av_endofpacket;
    out_valid = true;
elseif (out_consumed)
    out_valid = false;
    % out_data  = ZERO_DATA;  % keep bus clean (optional)
    out_last  = false;
end
%  Implicit else: registers hold their values.

% ======================= update FIFO storage =============================
if (do_wr)
    fifo_data(uint8(wr_ptr)+1) = av_data;
    fifo_last(uint8(wr_ptr)+1) = av_endofpacket;
    % wr_ptr = bitand(wr_ptr + uint8(1), FIFO_MASK);
    if wr_ptr == FIFO_DEPTH-1
        wr_ptr = fi(0,0,wr_ptr.WordLength,0,fm);
    else
        wr_ptr = fi(wr_ptr + 1,0,wr_ptr.WordLength,0,fm);
    end
end

if (do_rd)
    % rd_ptr = bitand(rd_ptr + uint8(1), FIFO_MASK);
    if rd_ptr == FIFO_DEPTH-1
        rd_ptr = fi(0,0,rd_ptr.WordLength,0,fm);
    else
        rd_ptr = fi(rd_ptr + 1,0,rd_ptr.WordLength,0,fm);
    end
end

% ======================= update count ====================================
if (do_rd && ~do_wr)
    cnt = fi(cnt - 1, 0, cnt.WordLength, 0, fm);
elseif (~do_rd && do_wr)
    cnt = fi(cnt + 1, 0, cnt.WordLength, 0, fm);
end
%  Both or neither: cnt unchanged.


end
