@echo off
setlocal enabledelayedexpansion

rem Список исходных файлов (добавьте/удалите по необходимости)
set SOURCES=async_fifo_fwft_reg_gem.v async_fifo_fwft_xilinx_style.v async_fifo_fwft_high_fmax.v AXIS_master_FIFO_rd\AXIS_master_FIFO_rd.v simple_FIFO_wr_check\simple_FIFO_wr_check.v AXIS_master_FIFO_rd_TB.v Simple_tready_gen\Simple_tready_gen.v

set OUTPUT=simv.exe
set VCD=AXIS_master_FIFO_rd_TB.vcd

echo Compiling...
iverilog -g2012 -o %OUTPUT% %SOURCES%
if errorlevel 1 (
    echo Error compilation!
    pause
    exit /b 1
)

echo Starting simulation...
vvp %OUTPUT%
if errorlevel 1 (
    echo Error execution simulation!
    pause
    exit /b 1
)

if exist %VCD% (
    echo VCD-file created: %VCD%
) else (
    echo Warning: no VCD-file found.
)

pause