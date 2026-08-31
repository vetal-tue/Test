@echo off
setlocal enabledelayedexpansion

rem Список исходных файлов (добавьте/удалите по необходимости)
set SOURCES=sync_FIFO\sync_fifo_fwft_reg_pow2_GEM.v sync_FIFO\sync_fifo_fwft_reg_pow2_OBF.v sync_FIFO\sync_fifo_fwft_reg_pow2.sv sync_FIFO\tb_sync_fifo_fwft_reg_pow2.sv

set OUTPUT=simv.exe
@REM set VCD=sync_FIFO_TB.vcd

echo Compiling...
iverilog -g2012 -o %OUTPUT% %SOURCES%
if errorlevel 1 (
    echo Error compilation!
    pause
    exit /b 1
)

echo Starting simulation...
@REM vvp %OUTPUT%
vvp %OUTPUT% -fst
if errorlevel 1 (
    echo Error execution simulation!
    pause
    exit /b 1
)

@REM if exist %VCD% (
@REM     echo VCD-file created: %VCD%
@REM     @REM echo Для просмотра выполните: gtkwave %VCD%
@REM ) else (
@REM     echo Warning: no VCD-file found.
@REM )

pause
