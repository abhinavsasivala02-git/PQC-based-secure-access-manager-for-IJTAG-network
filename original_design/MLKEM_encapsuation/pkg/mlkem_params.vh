//============================================================================
// ML-KEM Parameter Header (FIPS 203)
// Default: ML-KEM-768 (NIST Category 3)
// Fixed: using localparam for pure Verilog-2001 compatibility
//============================================================================

// Ring parameters
localparam [12:0] MLKEM_Q       = 13'd3329;
localparam [8:0]  MLKEM_N       = 9'd256;
localparam [3:0]  MLKEM_QBITS   = 4'd12;
localparam [3:0]  MLKEM_LOGN    = 4'd8;

// Montgomery domain constants
localparam [15:0] MLKEM_MONT_R     = 16'd2285;
localparam [15:0] MLKEM_MONT_RINV  = 16'd169;
localparam [15:0] MLKEM_MONT_RSQ   = 16'd1353;
localparam [15:0] MLKEM_QINV       = 16'd3327;

// Barrett reduction constants
localparam [15:0] MLKEM_BARRETT_V  = 16'd20159;
localparam [4:0]  MLKEM_BARRETT_S  = 5'd26;

// Inverse NTT scaling factor
localparam [15:0] MLKEM_INTT_F     = 16'd1441;

// Security-level parameters (ML-KEM-768 default)
localparam MLKEM_K    = 3;
localparam MLKEM_ETA1 = 2;
localparam MLKEM_ETA2 = 2;
localparam MLKEM_DU   = 10;
localparam MLKEM_DV   = 4;

// Derived sizes (in bytes)
localparam MLKEM_EK_BYTES = 12 * MLKEM_K * (MLKEM_N / 8) + 32;
localparam MLKEM_DK_BYTES = 24 * MLKEM_K * (MLKEM_N / 8) + 96;
localparam MLKEM_CT_BYTES = MLKEM_DU * MLKEM_K * (MLKEM_N / 8) + MLKEM_DV * (MLKEM_N / 8);
localparam MLKEM_SS_BYTES = 32;

// Keccak / SHA3 / SHAKE constants
localparam [4:0]  KECCAK_ROUNDS  = 5'd24;
localparam [10:0] KECCAK_STATE_W = 11'd1600;
localparam [7:0]  SHA3_256_RATE  = 8'd136;
localparam [7:0]  SHA3_512_RATE  = 8'd72;
localparam [7:0]  SHAKE128_RATE  = 8'd168;
localparam [7:0]  SHAKE256_RATE  = 8'd136;

// Domain separators
localparam [7:0]  SHA3_DOMAIN  = 8'h06;
localparam [7:0]  SHAKE_DOMAIN = 8'h1F;
