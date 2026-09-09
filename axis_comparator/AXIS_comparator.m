function [s0_axis_tready, s1_axis_tready, m_axis_tdata, m_axis_tvalid, m_axis_tlast, m_axis_tuser, state, m_axis_tkeep]= AXIS_comparator(s0_axis_tdata, s0_axis_tvalid, s0_axis_tlast, s0_axis_tuser, s0_axis_tkeep, m_axis_tready, s1_axis_tdata, s1_axis_tvalid, s1_axis_tlast, s1_axis_tuser, s1_axis_tkeep, select_in)

fm = fimath('OverflowMode','Wrap');

if isa(s0_axis_tdata,'integer')==0
    SIZE = s0_axis_tdata.WordLength;
elseif isa(s0_axis_tdata, 'uint8')
    SIZE = 8;
elseif isa(s0_axis_tdata, 'uint16')
    SIZE = 16;
elseif isa(s0_axis_tdata, 'uint32')
    SIZE = 32;
elseif isa(s0_axis_tdata, 'uint64')
    SIZE = 64;
else
    error('Unsupported data type: %s', class(s0_axis_tdata));
end


KEEP_WIDTH = SIZE/8; % s0_axis_tdata.WordLength/8; 
KEEP_ENABLE = 1;

% AXIS_nt = numerictype(0,SIZE,0);

persistent m_axis_tdata_reg m_axis_tkeep_reg m_axis_tvalid_reg m_axis_tlast_reg m_axis_tuser_reg
if isempty(m_axis_tdata_reg)
    m_axis_tdata_reg = fi(0, 0, SIZE, 0, fm);
    m_axis_tkeep_reg = fi(0, 0, KEEP_WIDTH, 0, fm);
    m_axis_tvalid_reg = false;
    m_axis_tlast_reg = false;
    m_axis_tuser_reg = false;
end
persistent m_axis_tready_int_reg;
if isempty(m_axis_tready_int_reg)
    m_axis_tready_int_reg = false;
end
persistent temp_m_axis_tdata_reg temp_m_axis_tvalid_reg temp_m_axis_tlast_reg ...
    temp_m_axis_tuser_reg temp_m_axis_tkeep_reg
if isempty(temp_m_axis_tdata_reg)
    temp_m_axis_tdata_reg = fi(0, 0, SIZE, 0, fm);
    temp_m_axis_tvalid_reg = false;
    temp_m_axis_tlast_reg = false;
    temp_m_axis_tuser_reg = false;
    temp_m_axis_tkeep_reg = fi(0, 0, KEEP_WIDTH, 0, fm);
end

persistent state_reg;
if isempty(state_reg)
    state_reg = fi(0,0,2,0,fm);
end
persistent flush_s0_reg flush_s1_reg
if isempty(flush_s0_reg)
    flush_s0_reg = false;
    flush_s1_reg = false;
end
persistent select_reg frame_reg
if isempty(select_reg)
    select_reg = false;
    frame_reg = false; % 1 - находимся внутри передачи кадра
end

state = state_reg;
STATE_PASS  = 0;
STATE_FLUSH = 1;

m_axis_tdata = m_axis_tdata_reg;
m_axis_tkeep = m_axis_tkeep_reg;
m_axis_tvalid = m_axis_tvalid_reg;
m_axis_tlast = m_axis_tlast_reg;
m_axis_tuser = m_axis_tuser_reg;


% current_select = frame_reg ? select_reg : select;
if (frame_reg)    
    current_select = select_reg;
else
    current_select = select_in;
end

m_axis_tvalid_int = false;
m_axis_tlast_int = false;
m_axis_tuser_int = false; 

if (current_select)
    % int_tdata  = current_select ? s1_tdata : s0_tdata;
    m_axis_tdata_int  = fi(s1_axis_tdata,0,SIZE,0,fm);
    selected_keep = s1_axis_tkeep;
else
    m_axis_tdata_int  = fi(s0_axis_tdata,0,SIZE,0,fm);
    selected_keep = s0_axis_tkeep;
end
% int_tkeep  = KEEP_ENABLE ? (current_select ? s1_tkeep : s0_tkeep) : {KEEP_WIDTH{1'b1}};
if (KEEP_ENABLE)
    % m_axis_tkeep_int  = fi(selected_keep,0,s0_axis_tkeep.WordLength,0,fm);
    m_axis_tkeep_int  = fi(selected_keep,0,KEEP_WIDTH,0,fm);
else
    % m_axis_tkeep_int  = fi(2^KEEP_WIDTH-1,0,s0_axis_tkeep.WordLength,0,fm);
    m_axis_tkeep_int  = fi(2^KEEP_WIDTH-1,0,KEEP_WIDTH,0,fm);
end


%------------------------------------------------------------------------
% Сравнение и управляющий автомат (FSM)
% ------------------------------------------------------------------------
both_valid = s0_axis_tvalid && s1_axis_tvalid;

 % Проверка совпадения данных и tkeep (если tkeep включен)
data_match = s0_axis_tdata == s1_axis_tdata;
keep_match = KEEP_ENABLE==0 || (s0_axis_tkeep == s1_axis_tkeep);
match = data_match && keep_match && ~(s0_axis_tuser || s1_axis_tuser);


% Входные ready-сигналы
% assign s0_tready = (state_reg == STATE_PASS) ? (s1_tvalid && int_tready) : flush_s0_reg;
% assign s1_tready = (state_reg == STATE_PASS) ? (s0_tvalid && int_tready) : flush_s1_reg;
if (state_reg == STATE_PASS)
    s0_axis_tready = s1_axis_tvalid && m_axis_tready_int_reg;
    s1_axis_tready = s0_axis_tvalid && m_axis_tready_int_reg;
else
    s0_axis_tready = flush_s0_reg;
    s1_axis_tready = flush_s1_reg;
end

flush_s0_next = flush_s0_reg;
flush_s1_next = flush_s1_reg;

switch uint8(state_reg)

    case STATE_PASS
        if (both_valid)
            m_axis_tvalid_int = true;
            % Прерываем кадр (выдаем tlast=1), если данные/tkeep не совпали или хотя бы один кадр закончился
            m_axis_tlast_int = ~match || s0_axis_tlast || s1_axis_tlast;
            m_axis_tuser_int = ~match;

          if (m_axis_tready_int_reg)
              
              % При расхождении или раннем tlast переходим в режим FLUSH
              if (~match || s0_axis_tlast || s1_axis_tlast)
                  if (~s0_axis_tlast)
                      % flush_s0_reg = true;
                      flush_s0_next = true;
                  end
                  if (~s1_axis_tlast)
                      % flush_s1_reg = true;
                      flush_s1_next = true;
                  end
    
                  if (~s0_axis_tlast || ~s1_axis_tlast)
                      state_reg(1) = STATE_FLUSH;
                  end
              end

              % Фиксируем select на первом слове кадра
              if (~frame_reg)
                  select_reg = select_in;
              end
              % Удерживаем frame_reg до тех пор, пока не встретим tlast
              frame_reg = ~m_axis_tlast_int;
          end
        end
              

    % case STATE_FLUSH
    otherwise

        m_axis_tvalid_int = false; % В режиме сброса ничего не пишем на выход
        frame_reg = false;

        if (flush_s0_reg && s0_axis_tvalid && s0_axis_tlast)
            flush_s0_next = false;
        end

        if (flush_s1_reg && s1_axis_tvalid && s1_axis_tlast)
            flush_s1_next = false;
        end

        % Как только оба мастера выдали tlast — возвращаемся в PASS
        if (~flush_s0_next && ~flush_s1_next)
            state_reg(1) = STATE_PASS;
            % state_next(1) = STATE_PASS;
        end
end

flush_s0_reg = flush_s0_next;
flush_s1_reg = flush_s1_next;


% Разрешение на прием данных в следующем такте:
% если выход готов ИЛИ временный регистр не заполнится на следующем такте
m_axis_tready_int_early = m_axis_tready || (~temp_m_axis_tvalid_reg && (~m_axis_tvalid_reg || ~m_axis_tvalid_int));


store_axis_int_to_output = false;
store_axis_int_to_temp = false;
store_axis_temp_to_output = false;

if (m_axis_tready_int_reg)
    % input is ready
    if (m_axis_tready || ~m_axis_tvalid_reg)
        % output is ready or currently not valid, transfer data to output
        % m_axis_tvalid_next = m_axis_tvalid_int; % m_axis_tvalid_reg = m_axis_tvalid_int;
        m_axis_tvalid_reg = m_axis_tvalid_int;
        store_axis_int_to_output = true;
    else
        % output is not ready, store input in temp
        % temp_m_axis_tvalid_next = m_axis_tvalid_int; % temp_m_axis_tvalid_reg = m_axis_tvalid_int;
        temp_m_axis_tvalid_reg = m_axis_tvalid_int;
        store_axis_int_to_temp = true;
    end
elseif (m_axis_tready)
    % input is not ready, but output is ready
    % m_axis_tvalid_next = temp_m_axis_tvalid_reg; % m_axis_tvalid_reg = temp_m_axis_tvalid_reg;
    m_axis_tvalid_reg = temp_m_axis_tvalid_reg;

    temp_m_axis_tvalid_reg = false;
    store_axis_temp_to_output = true;
end


m_axis_tready_int_reg = m_axis_tready_int_early;

if (store_axis_int_to_output)
    m_axis_tdata_reg = m_axis_tdata_int;
    m_axis_tkeep_reg = m_axis_tkeep_int;
    m_axis_tlast_reg = m_axis_tlast_int;
    m_axis_tuser_reg = m_axis_tuser_int;
elseif (store_axis_temp_to_output)
    m_axis_tdata_reg = temp_m_axis_tdata_reg;
    m_axis_tkeep_reg = temp_m_axis_tkeep_reg;
    m_axis_tlast_reg = temp_m_axis_tlast_reg;
    m_axis_tuser_reg = temp_m_axis_tuser_reg;
end

if (store_axis_int_to_temp)
    temp_m_axis_tdata_reg = m_axis_tdata_int;
    temp_m_axis_tkeep_reg = m_axis_tkeep_int;
    temp_m_axis_tlast_reg = m_axis_tlast_int;
    temp_m_axis_tuser_reg = m_axis_tuser_int;
end

end
