function [cnt_out, c0, c1, c2]= counter

N = 4; % разрядность сегмента (<=16)

fm = fimath('OverflowMode','Wrap');

persistent cnt0 cnt1 cnt2 cnt3
persistent cnt0_d1 cnt0_d2 cnt0_d3
persistent cnt1_d1 cnt1_d2
persistent cnt2_d1
persistent c0_reg c1_reg c2_reg
if isempty(cnt0)
    cnt0 = fi(0,0,N,0,fm);
    cnt1 = fi(0,0,N,0,fm);
    cnt2 = fi(0,0,N,0,fm);
    cnt3 = fi(0,0,N,0,fm);
    cnt0_d1 = fi(0,0,cnt0.WordLength,0,fm);
    cnt0_d2 = fi(0,0,cnt0.WordLength,0,fm);
    cnt0_d3 = fi(0,0,cnt0.WordLength,0,fm);
    cnt1_d1 = fi(0,0,cnt1.WordLength,0,fm);
    cnt1_d2 = fi(0,0,cnt1.WordLength,0,fm);
    cnt2_d1 = fi(0,0,cnt2.WordLength,0,fm);
    c0_reg = false;
    c1_reg = false;
    c2_reg = false;
end


cnt_out = bitconcat(cnt3, cnt2_d1, cnt1_d2, cnt0_d3);
c0 = c0_reg;
c1 = c1_reg;
c2 = c2_reg;

%% --- Выравнивающий конвейер (Aligning Pipeline) ---

% Задержка Секции 0 на 3 такта
cnt0_d3 = cnt0_d2;
cnt0_d2 = cnt0_d1;
cnt0_d1 = cnt0;

% Задержка Секции 1 на 2 такта
cnt1_d2 = cnt1_d1;
cnt1_d1 = cnt1;

% Задержка Секции 2 на 1 такт
cnt2_d1 = cnt2;

%% --- Счетчики ---
if (c2_reg)
    cnt3 = fi(cnt3 + 1, 0, cnt3.WordLength, 0, fm);
end

c2_reg = cnt2 == 2^cnt2.WordLength-1 && c1_reg;
if (c1_reg)
    cnt2 = fi(cnt2 + 1, 0, cnt2.WordLength, 0, fm);
end

c1_reg = cnt1 == 2^cnt1.WordLength-1 && c0_reg;
if (c0_reg)
    cnt1 = fi(cnt1 + 1, 0, cnt1.WordLength, 0, fm);
end


c0_reg = cnt0 == 2^cnt0.WordLength-1;
cnt0 = fi(cnt0 + 1, 0, cnt0.WordLength, 0, fm);


