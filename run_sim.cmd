@echo off
setlocal enabledelayedexpansion

rem Список исходных файлов (добавьте/удалите по необходимости)
set SOURCES=async_fifo_fwft_reg_sat.v async_fifo_fwft_reg_gem.v async_fifo_fwft_xilinx_style.v async_fifo_fwft_high_fmax.v simple_FIFO_wr_check.v simple_FIFO_rd_check.v async_FIFO_TB.v

set OUTPUT=simv.exe
set VCD=async_FIFO_TB.vcd

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
    @REM echo Для просмотра выполните: gtkwave %VCD%
) else (
    echo Warning: no VCD-file found.
)

pause