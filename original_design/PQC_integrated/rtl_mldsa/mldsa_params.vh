// =============================================================================
// mldsa_params.vh — ML-DSA-65 (FIPS 204) Global Parameters (Verilog `define)
//
// Include this file in every module: `include "mldsa_params.vh"
// Compile with: -incdir rtl/pkg
// =============================================================================
`ifndef MLDSA_PARAMS_VH
`define MLDSA_PARAMS_VH

// Core ring parameters
`define MLDSA_Q          8380417
`define MLDSA_QBITS      23
`define MLDSA_N          256
`define MLDSA_LOG2N      8

// ML-DSA-65 specific parameters
`define MLDSA_K          6
`define MLDSA_L          5
`define MLDSA_ETA        4
`define MLDSA_TAU        49
`define MLDSA_BETA_VAL   196
`define MLDSA_GAMMA1     524288
`define MLDSA_GAMMA2     261888
`define MLDSA_OMEGA      55
`define MLDSA_LAMBDA     192
`define MLDSA_D_PARAM    13

// Key / Signature byte sizes
`define MLDSA_SK_BYTES   4032
`define MLDSA_PK_BYTES   1952
`define MLDSA_SIG_BYTES  3309

// Montgomery constants (R = 2^32)
`define MLDSA_MONT_R         4193792
`define MLDSA_MONT_R2        2365951
`define MLDSA_MONT_QINV      58728449
`define MLDSA_MONT_QINV_NEG  32'd4236238847

// NTT parameters
`define MLDSA_ZETA       1753
`define MLDSA_NINV_MONT  41978

`endif
