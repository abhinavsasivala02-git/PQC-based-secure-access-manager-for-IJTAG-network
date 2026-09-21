@echo off
rem ===========================================================================
rem run_iverilog.bat - Compile & simulate the PQC-secured IJTAG integration
rem with Icarus Verilog (flat compile, no library support).
rem
rem KAT-verified cores are pulled in directly:
rem   rtl_mldsa  : ML-DSA-65 verify datapath from MLDSA_KAT/MLDSA_work
rem                (verify_ctrl, ntt_core, shake_unified, ...)
rem   rtl_mlkem  : ML-KEM-768 encaps datapath from MLKEM_KAT/MLKEM_work
rem                (mlkem_encaps, kpke_encrypt, ...) with the 5 modules that
rem                collide with the MLDSA tree renamed with an mlkem_ prefix
rem   AM_ijtag/design     : MSIB / SiB / TDR / mux21 chain
rem   PQC_integrated      : ext_sipo, j_trng, wrappers, am_pqc, integrated_top
rem
rem Run:  run_iverilog.bat
rem ===========================================================================
setlocal
set TOP=%CD%\..\..

set INC=-I %TOP%\PQC_integrated\rtl_mldsa -I %TOP%\PQC_integrated\rtl_mlkem

set SRC=^
 %TOP%\PQC_integrated\rtl_mldsa\keccak_round.v^
 %TOP%\PQC_integrated\rtl_mldsa\keccak_f1600.v^
 %TOP%\PQC_integrated\rtl_mldsa\shake_unified.v^
 %TOP%\PQC_integrated\rtl_mldsa\poly_ram_tdp.v^
 %TOP%\PQC_integrated\rtl_mldsa\montgomery_mult.v^
 %TOP%\PQC_integrated\rtl_mldsa\mod_add.v^
 %TOP%\PQC_integrated\rtl_mldsa\butterfly_unit.v^
 %TOP%\PQC_integrated\rtl_mldsa\ntt_core.v^
 %TOP%\PQC_integrated\rtl_mldsa\zeta_rom.v^
 %TOP%\PQC_integrated\rtl_mldsa\decompose.v^
 %TOP%\PQC_integrated\rtl_mldsa\use_hint.v^
 %TOP%\PQC_integrated\rtl_mldsa\verify_ctrl.v^
 %TOP%\PQC_integrated\rtl_mlkem\keccak_round.v^
 %TOP%\PQC_integrated\rtl_mlkem\keccak_f1600.v^
 %TOP%\PQC_integrated\rtl_mlkem\mlkem_hash_engine.v^
 %TOP%\PQC_integrated\rtl_mlkem\sha3_256.v^
 %TOP%\PQC_integrated\rtl_mlkem\sha3_512.v^
 %TOP%\PQC_integrated\rtl_mlkem\shake128.v^
 %TOP%\PQC_integrated\rtl_mlkem\shake256.v^
 %TOP%\PQC_integrated\rtl_mlkem\poly_ram.v^
 %TOP%\PQC_integrated\rtl_mlkem\montgomery_reduce.v^
 %TOP%\PQC_integrated\rtl_mlkem\barrett_reduce.v^
 %TOP%\PQC_integrated\rtl_mlkem\modular_arith.v^
 %TOP%\PQC_integrated\rtl_mlkem\ntt_butterfly.v^
 %TOP%\PQC_integrated\rtl_mlkem\ntt_core.v^
 %TOP%\PQC_integrated\rtl_mlkem\ntt_rom.v^
 %TOP%\PQC_integrated\rtl_mlkem\poly_basemul.v^
 %TOP%\PQC_integrated\rtl_mlkem\poly_arith.v^
 %TOP%\PQC_integrated\rtl_mlkem\sample_cbd.v^
 %TOP%\PQC_integrated\rtl_mlkem\sample_ntt.v^
 %TOP%\PQC_integrated\rtl_mlkem\byte_decode.v^
 %TOP%\PQC_integrated\rtl_mlkem\byte_encode.v^
 %TOP%\PQC_integrated\rtl_mlkem\compress.v^
 %TOP%\PQC_integrated\rtl_mlkem\kpke_encrypt.v^
 %TOP%\PQC_integrated\rtl_mlkem\mlkem_encaps.v^
 %TOP%\PQC_integrated\design\keccak_shared.v^
 %TOP%\PQC_integrated\design\otp.v^
 %TOP%\PQC_integrated\design\ext_sipo.v^
 %TOP%\PQC_integrated\design\j_trng.v^
 %TOP%\PQC_integrated\design\shake_stream.v^
 %TOP%\PQC_integrated\design\inst_priority_decoder.v^
 %TOP%\PQC_integrated\design\mldsa_verify_block.v^
 %TOP%\PQC_integrated\design\mlkem_encaps_wrapper.v^
 %TOP%\PQC_integrated\design\am_pqc.v^
 %TOP%\PQC_integrated\design\integrated_top.v^
 %TOP%\AM_ijtag\design\mux21.v^
 %TOP%\AM_ijtag\design\MSIB.v^
 %TOP%\AM_ijtag\design\SiB.v^
 %TOP%\AM_ijtag\design\TDR.v^
 %TOP%\PQC_integrated\tb\integrated_top_tb.v

echo Compiling integrated PQC design...
iverilog -g2005 -s integrated_top_tb -o integrated_top.vvp %INC% %SRC%
if errorlevel 1 (
  echo COMPILE FAILED
  exit /b 1
)
echo Compile OK.

echo Running simulation...
vvp integrated_top.vvp