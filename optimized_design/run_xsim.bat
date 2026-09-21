@echo off
rem =============================================================================
rem run_xsim.bat - Vivado xsim behavioral simulation of integrated_top_tb.
rem Runs xvlog/xelab/xsim (Vivado 2023.2 on D:) from PQC_integrated\tb.
rem NIST .mem vectors are read from the CWD (TB is compiled with -d XSIM).
rem =============================================================================
cd /d "%~dp0PQC_integrated\tb"
call "D:\Vivado\2023.2\settings64.bat"
rem Clean any stale simulation database (prevents kernel crashes from a
rem leftover xsim.dir / wdb of a previous, crashed run)
rd /s /q xsim.dir 2>nul
del /q sim.log 2>nul
set "TOP=%~dp0"
if "%TOP:~-1%"=="\" set "TOP=%TOP:~0,-1%"
set INC=-i %TOP%\PQC_integrated\rtl_mldsa -i %TOP%\PQC_integrated\rtl_mlkem

echo === xvlog: compiling RTL ===
call xvlog %INC% ^
 %TOP%\PQC_integrated\rtl_mldsa\keccak_round.v ^
 %TOP%\PQC_integrated\rtl_mldsa\keccak_f1600.v ^
 %TOP%\PQC_integrated\rtl_mldsa\shake_unified.v ^
 %TOP%\PQC_integrated\rtl_mldsa\poly_ram_tdp.v ^
 %TOP%\PQC_integrated\rtl_mldsa\montgomery_mult.v ^
 %TOP%\PQC_integrated\rtl_mldsa\mod_add.v ^
 %TOP%\PQC_integrated\rtl_mldsa\butterfly_unit.v ^
 %TOP%\PQC_integrated\rtl_mldsa\ntt_core.v ^
 %TOP%\PQC_integrated\rtl_mldsa\zeta_rom.v ^
 %TOP%\PQC_integrated\rtl_mldsa\decompose.v ^
 %TOP%\PQC_integrated\rtl_mldsa\use_hint.v ^
 %TOP%\PQC_integrated\rtl_mldsa\verify_ctrl.v ^
 %TOP%\PQC_integrated\rtl_mlkem\keccak_round.v ^
 %TOP%\PQC_integrated\rtl_mlkem\keccak_f1600.v ^
 %TOP%\PQC_integrated\rtl_mlkem\mlkem_hash_engine.v ^
 %TOP%\PQC_integrated\rtl_mlkem\sha3_256.v ^
 %TOP%\PQC_integrated\rtl_mlkem\sha3_512.v ^
 %TOP%\PQC_integrated\rtl_mlkem\shake128.v ^
 %TOP%\PQC_integrated\rtl_mlkem\shake256.v ^
 %TOP%\PQC_integrated\rtl_mlkem\poly_ram.v ^
 %TOP%\PQC_integrated\rtl_mlkem\montgomery_reduce.v ^
 %TOP%\PQC_integrated\rtl_mlkem\barrett_reduce.v ^
 %TOP%\PQC_integrated\rtl_mlkem\modular_arith.v ^
 %TOP%\PQC_integrated\rtl_mlkem\ntt_butterfly.v ^
 %TOP%\PQC_integrated\rtl_mlkem\ntt_core.v ^
 %TOP%\PQC_integrated\rtl_mlkem\ntt_rom.v ^
 %TOP%\PQC_integrated\rtl_mlkem\poly_basemul.v ^
 %TOP%\PQC_integrated\rtl_mlkem\poly_arith.v ^
 %TOP%\PQC_integrated\rtl_mlkem\sample_cbd.v ^
 %TOP%\PQC_integrated\rtl_mlkem\sample_ntt.v ^
 %TOP%\PQC_integrated\rtl_mlkem\byte_decode.v ^
 %TOP%\PQC_integrated\rtl_mlkem\byte_encode.v ^
 %TOP%\PQC_integrated\rtl_mlkem\compress.v ^
 %TOP%\PQC_integrated\rtl_mlkem\kpke_encrypt.v ^
 %TOP%\PQC_integrated\rtl_mlkem\mlkem_encaps.v ^
 %TOP%\PQC_integrated\design\keccak_shared.v ^
%TOP%\PQC_integrated\design\otp.v ^
 %TOP%\PQC_integrated\design\ext_sipo.v ^
 %TOP%\PQC_integrated\design\j_trng.v ^
 %TOP%\PQC_integrated\design\shake_stream.v ^
 %TOP%\PQC_integrated\design\inst_priority_decoder.v ^
 %TOP%\PQC_integrated\design\mldsa_verify_block.v ^
 %TOP%\PQC_integrated\design\mlkem_encaps_wrapper.v ^
 %TOP%\PQC_integrated\design\am_pqc.v ^
 %TOP%\PQC_integrated\design\integrated_top.v ^
 %TOP%\AM_ijtag\design\mux21.v ^
 %TOP%\AM_ijtag\design\MSIB.v ^
 %TOP%\AM_ijtag\design\SiB.v ^
 %TOP%\AM_ijtag\design\TDR.v
if errorlevel 1 goto :fail

echo === xvlog: compiling TB with -d XSIM ===
call xvlog %INC% -d XSIM %TOP%\PQC_integrated\tb\integrated_top_tb.v
if errorlevel 1 goto :fail

echo === xelab: elaborating ===
call xelab -mt off -s sim -debug typical integrated_top_tb
if errorlevel 1 goto :fail

echo === xsim: running ===
call xsim sim -log sim.log -runall
if errorlevel 1 goto :fail

echo === XSIM COMPLETE ===
goto :eof
:fail
echo === XSIM FAILED ===
exit /b 1
