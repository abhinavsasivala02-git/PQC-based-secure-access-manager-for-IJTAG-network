#!/bin/sh
# =============================================================================
# run_xrun.sh - Compile & simulate the PQC-secured IJTAG integration
#
# Xcelium (xrun) single-library flow mirroring the Vivado xsim compile list
# in ../../run_xsim.bat:
#   - ML-DSA-65 verify datapath from rtl_mldsa/
#   - ML-KEM-768 encaps datapath from rtl_mlkem/ (modules mlkem_-prefixed to
#     avoid name collisions with the ML-DSA tree)
#   - PQC_integrated design + AM_ijtag blocks + testbench
#
# The testbench reads its .mem vectors from ../tb/, so run it from here:
#   sh run_xrun.sh
# Set XCELIUM_HOME if Xcelium is installed elsewhere.
# =============================================================================
set -e

TOP=../..

XCELIUM_HOME=${XCELIUM_HOME:-/opt/cadence/installs/XCELIUM}
XH=$XCELIUM_HOME/tools.lnx86/bin/xrun

rm -rf xrun_work *.log cds.lib hdl.var

# cds.lib with a single library
cat > cds.lib <<EOF
INCLUDE $XCELIUM_HOME/tools/inca/files/cds.lib
DEFINE top_lib ./top_lib
EOF

# ---------------------------------------------------------------------------
# Single top_lib compile - file order matches the validated run_xsim.bat list.
# ---------------------------------------------------------------------------
xrun -q -libname top_lib \
    -incdir $TOP/PQC_integrated/rtl_mldsa \
    -incdir $TOP/PQC_integrated/rtl_mlkem \
    $TOP/PQC_integrated/rtl_mldsa/keccak_round.v \
    $TOP/PQC_integrated/rtl_mldsa/keccak_f1600.v \
    $TOP/PQC_integrated/rtl_mldsa/shake_unified.v \
    $TOP/PQC_integrated/rtl_mldsa/poly_ram_tdp.v \
    $TOP/PQC_integrated/rtl_mldsa/montgomery_mult.v \
    $TOP/PQC_integrated/rtl_mldsa/mod_add.v \
    $TOP/PQC_integrated/rtl_mldsa/butterfly_unit.v \
    $TOP/PQC_integrated/rtl_mldsa/ntt_core.v \
    $TOP/PQC_integrated/rtl_mldsa/zeta_rom.v \
    $TOP/PQC_integrated/rtl_mldsa/decompose.v \
    $TOP/PQC_integrated/rtl_mldsa/use_hint.v \
    $TOP/PQC_integrated/rtl_mldsa/verify_ctrl.v \
    $TOP/PQC_integrated/rtl_mlkem/keccak_round.v \
    $TOP/PQC_integrated/rtl_mlkem/keccak_f1600.v \
    $TOP/PQC_integrated/rtl_mlkem/mlkem_hash_engine.v \
    $TOP/PQC_integrated/rtl_mlkem/sha3_256.v \
    $TOP/PQC_integrated/rtl_mlkem/sha3_512.v \
    $TOP/PQC_integrated/rtl_mlkem/shake128.v \
    $TOP/PQC_integrated/rtl_mlkem/shake256.v \
    $TOP/PQC_integrated/rtl_mlkem/poly_ram.v \
    $TOP/PQC_integrated/rtl_mlkem/montgomery_reduce.v \
    $TOP/PQC_integrated/rtl_mlkem/barrett_reduce.v \
    $TOP/PQC_integrated/rtl_mlkem/modular_arith.v \
    $TOP/PQC_integrated/rtl_mlkem/ntt_butterfly.v \
    $TOP/PQC_integrated/rtl_mlkem/ntt_core.v \
    $TOP/PQC_integrated/rtl_mlkem/ntt_rom.v \
    $TOP/PQC_integrated/rtl_mlkem/poly_basemul.v \
    $TOP/PQC_integrated/rtl_mlkem/poly_arith.v \
    $TOP/PQC_integrated/rtl_mlkem/sample_cbd.v \
    $TOP/PQC_integrated/rtl_mlkem/sample_ntt.v \
    $TOP/PQC_integrated/rtl_mlkem/byte_decode.v \
    $TOP/PQC_integrated/rtl_mlkem/byte_encode.v \
    $TOP/PQC_integrated/rtl_mlkem/compress.v \
    $TOP/PQC_integrated/rtl_mlkem/kpke_encrypt.v \
    $TOP/PQC_integrated/rtl_mlkem/mlkem_encaps.v \
    $TOP/PQC_integrated/design/keccak_shared.v \
    $TOP/PQC_integrated/design/otp.v \
    $TOP/PQC_integrated/design/ext_sipo.v \
    $TOP/PQC_integrated/design/j_trng.v \
    $TOP/PQC_integrated/design/shake_stream.v \
    $TOP/PQC_integrated/design/inst_priority_decoder.v \
    $TOP/PQC_integrated/design/mldsa_verify_block.v \
    $TOP/PQC_integrated/design/mlkem_encaps_wrapper.v \
    $TOP/PQC_integrated/design/am_pqc.v \
    $TOP/PQC_integrated/design/integrated_top.v \
    $TOP/AM_ijtag/design/mux21.v \
    $TOP/AM_ijtag/design/MSIB.v \
    $TOP/AM_ijtag/design/SiB.v \
    $TOP/AM_ijtag/design/TDR.v \
    $TOP/PQC_integrated/tb/integrated_top_tb.v \
    -access +rwc \
    -timescale 1ns/1ps \
    -top integrated_top_tb

echo "=== xrun completed OK ==="