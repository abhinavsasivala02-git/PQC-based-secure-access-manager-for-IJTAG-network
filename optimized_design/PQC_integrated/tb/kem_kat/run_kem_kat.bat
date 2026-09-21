@echo off
rem Runs the 3-vector FIPS 203 KAT for PQC_integrated/rtl_mlkem with Icarus.
rem Checks both the 1088-byte ciphertext and the 32-byte shared secret K.
rem The shared Keccak-f[1600] core (design/keccak_shared.v + the rtl_mldsa
rem permutation) is pulled in because the ML-KEM hash users no longer own one.
cd /d "%~dp0"
iverilog -g2012 -I ..\..\rtl_mlkem -o kem_kat.vvp tb_kem_kat3.v ^
  ..\..\rtl_mlkem\*.v ^
  ..\..\design\keccak_shared.v ^
  ..\..\rtl_mldsa\keccak_f1600.v ^
  ..\..\rtl_mldsa\keccak_round.v
if errorlevel 1 exit /b 1
vvp -n kem_kat.vvp
