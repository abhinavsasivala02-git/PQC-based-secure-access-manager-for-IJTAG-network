@echo off
REM =============================================================================
REM ML-KEM Encapsulation - Vivado xsim behavioral simulation
REM =============================================================================
setlocal EnableDelayedExpansion

set PROJECT_ROOT=%~dp0
set WORK_DIR=%PROJECT_ROOT%xsim_work
set VIVADO_BIN=D:\Vivado\2023.2\bin

if not exist "%WORK_DIR%" mkdir "%WORK_DIR%"
pushd "%WORK_DIR%"

echo === xvlog: compiling RTL + testbench ===
"%VIVADO_BIN%\xvlog.bat" --incr ^
  -i "%PROJECT_ROOT%\pkg" ^
  "%PROJECT_ROOT%\pkg\ntt_rom.v" ^
  "%PROJECT_ROOT%\keccak\keccak_round.v" ^
  "%PROJECT_ROOT%\keccak\keccak_f1600.v" ^
  "%PROJECT_ROOT%\keccak\mlkem_hash_engine_cfg.v" ^
  "%PROJECT_ROOT%\math\montgomery_reduce.v" ^
  "%PROJECT_ROOT%\math\barrett_reduce.v" ^
  "%PROJECT_ROOT%\math\fq_reduce.v" ^
  "%PROJECT_ROOT%\math\modular_arith.v" ^
  "%PROJECT_ROOT%\encode\byte_encode.v" ^
  "%PROJECT_ROOT%\encode\byte_decode.v" ^
  "%PROJECT_ROOT%\encode\compress.v" ^
  "%PROJECT_ROOT%\encode\decompress.v" ^
  "%PROJECT_ROOT%\sample\sample_cbd.v" ^
  "%PROJECT_ROOT%\sample\sample_ntt_ext.v" ^
  "%PROJECT_ROOT%\mem\poly_ram.v" ^
  "%PROJECT_ROOT%\math\ntt_core.v" ^
  "%PROJECT_ROOT%\math\poly_basemul.v" ^
  "%PROJECT_ROOT%\math\poly_arith.v" ^
  "%PROJECT_ROOT%\kpke\kpke_encrypt_shared.v" ^
  "%PROJECT_ROOT%\mlkem\mlkem_encaps_top.v" ^
  "%PROJECT_ROOT%\tb_mlkem_encaps.v"
if errorlevel 1 (
    echo ERROR: xvlog failed
    popd
    exit /b 1
)

echo === xelab: elaborating ===
"%VIVADO_BIN%\xelab.bat" tb_mlkem_encaps -s snap_mlkem -debug typical -timescale 1ns/1ps
if errorlevel 1 (
    echo ERROR: xelab failed
    popd
    exit /b 1
)

echo === xsim: running simulation ===
"%VIVADO_BIN%\xsim.bat" snap_mlkem -runall
if errorlevel 1 (
    echo ERROR: xsim failed
    popd
    exit /b 1
)

popd
echo === DONE ===
