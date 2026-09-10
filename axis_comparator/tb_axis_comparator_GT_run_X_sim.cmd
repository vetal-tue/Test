@echo off
setlocal enabledelayedexpansion

REM --- Настройки ---
CALL E:\Xilinx\Vivado\2019.2\.settings64-Vivado.bat
set SOURCES=axis_comparator.v tb_axis_comparator_GT.v
set TOP_MODULE=tb_axis_comparator_GT
set SNAPSHOT_NAME=%TOP_MODULE%_sim

set VCD_FILE=%TOP_MODULE%.vcd
set FST_FILE=%TOP_MODULE%.fst
set TCL_FILE=_dump_vcd_%TOP_MODULE%.tcl

REM --- Компиляция (анализ) исходных файлов ---
echo ===============================
echo Analyzing sources with xvlog...
echo ===============================
call xvlog -sv %SOURCES%
if errorlevel 1 (
    echo Error during analysis!
    pause
    exit /b 1
)

REM --- Элаборация и создание снапшота ---
echo ===============================
echo Elaborating design with xelab...
echo ===============================
@REM  call xelab -debug typical %TOP_MODULE% -s %SNAPSHOT_NAME%
call xelab -debug typical %TOP_MODULE% -s %SNAPSHOT_NAME%
if errorlevel 1 (
    echo Error during elaboration!
    pause
    exit /b 1
)

REM ============================================================
REM  Генерация TCL-скрипта для дампа VCD "на лету"
REM ============================================================
(
    @REM  echo open_vcd %VCD_FILE%
    @REM  echo log_vcd [get_objects -r /%TOP_MODULE%/*]
    echo run all
    @REM  echo close_vcd
    echo quit
) > %TCL_FILE%

REM --- Запуск симуляции ---
echo ===============================
echo Starting simulation with xsim...
echo ===============================
call xsim %SNAPSHOT_NAME% -tclbatch %TCL_FILE%
set SIM_RESULT=%errorlevel%

REM Удаляем временный TCL-файл в любом случае
if exist %TCL_FILE% del /q %TCL_FILE%

if %SIM_RESULT% neq 0 (
    echo Error during simulation!
    pause
    exit /b 1
)

REM ============================================================
REM  Нормализация имени VCD (xsim может создать файл без .vcd)
REM ============================================================
if not exist "%VCD_FILE%" (
    if exist "%TOP_MODULE%" (
        echo Renaming extensionless VCD "%TOP_MODULE%" -^> "%VCD_FILE%"
        ren "%TOP_MODULE%" "%VCD_FILE%"
    )
)

REM ============================================================
REM  5. Конвертация VCD -> FST и удаление VCD
REM ============================================================
@REM  echo [5/5] Converting VCD to FST...
if not exist "%VCD_FILE%" (
    echo Warning: %VCD_FILE% not found, skipping conversion.
    goto :done
)
set VCD2FST=C:\iverilog\gtkwave\bin\vcd2fst.exe
call %VCD2FST% %VCD_FILE% %FST_FILE% --compress
if errorlevel 1 (
    echo Warning: VCD -> FST conversion failed. Keeping %VCD_FILE%.
) else (
    echo Conversion successful. Removing %VCD_FILE%...
    del /q %VCD_FILE%
)

:done
echo.
echo Simulation finished successfully.
echo FST saved as: %FST_FILE%

REM ============================================================
REM  очистка временных файлов xsim
REM ============================================================
if exist xsim.log del /q xsim.log
if exist xsim.jou del /q xsim.jou
@REM  if exist xelab.pb del /q xelab.pb
if exist xelab.log del /q xelab.log
if exist xvlog.log del /q xvlog.log
@REM  if exist xvlog.pb del /q xvlog.pb
if exist x*.pb del /q x*.pb
if exist xsim*.backup.* del /q xsim*.backup.*
if exist webtalk*.* del /q webtalk*.*

if exist %SNAPSHOT_NAME%.wdb del /q %SNAPSHOT_NAME%.wdb
REM Папка со снапшотом
if exist xsim.dir rmdir /s /q xsim.dir

@REM  pause
