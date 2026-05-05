@echo off
setlocal enabledelayedexpansion

rem Список исходных файлов (добавьте/удалите по необходимости)
@REM set SOURCES=async_fifo_fwft_reg_gem.v async_fifo_fwft_xilinx_style.v async_fifo_fwft_high_fmax.v AXIS_master_FIFO_rd\AXIS_master_FIFO_rd.v simple_FIFO_wr_check\simple_FIFO_wr_check.v AXIS_master_FIFO_rd_TB.v Simple_tready_gen\Simple_tready_gen.v simple_tdata_checker\simple_tdata_checker.v
set SOURCES=simple_avalonst_axis_checker\simple_avalonst_axis_checker.v axis_to_avalon_st_skid2\axis_to_avalon_st_skid2.v axis_to_avalon_st_skid\axis_to_avalon_st_skid.v avalon_st_to_axis\avalon_st_to_axis.v avalon_st_to_axis_4word_fifo\avalon_st_to_axis_4word_fifo.v simple_avalon_st_generator\simple_avalon_st_generator.v Simple_avalon_rdy_gen\Simple_avalon_rdy_gen.v AvalonST_to_AXIS_TB.v

set OUTPUT=simv.exe
set VCD=AvalonST_to_AXIS_TB.vcd

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
