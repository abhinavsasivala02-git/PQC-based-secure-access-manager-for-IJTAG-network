//============================================================================
// fq_reduce — Plain Barrett reduction mod q = 3329 (FIPS 203 / Go style)
// Input:  unsigned value a, 0 <= a < 2*q^2  (25-bit max)
//         largest use: gamma * (a1*b1 mod q) where gamma < q
// Output: a mod q in [0, q-1]
//
// Mirrors Go crypto/internal/fips140/mlkem fieldReduce:
//   quotient = (a * 5039) >> 24 ;  r = a - quotient*q ;  reduce once
// (5039 = 2^12 * 2^12 / q, shift 24 = log2(2^12 * 2^12)).
//============================================================================
module fq_reduce (
    input  wire [24:0] a,       // 0 <= a < 2q^2 < 2^25
    output wire [11:0] result
);

    localparam MLKEM_Q         = 13'd3329;
    localparam MLKEM_BARRETT_V = 16'd5039;

    // quotient = (a * v) >> 24   (a*v < 2^25 * 2^13 = 2^38 fits 40 bits)
    wire [39:0] p;
    wire [15:0] quotient;
    assign p        = a * MLKEM_BARRETT_V;
    assign quotient = p[39:24];

    // r = a - quotient*q, in (-q, 2q)
    wire signed [24:0] r;
    assign r = $signed({1'b0, a}) - $signed(quotient) * $signed({1'b0, MLKEM_Q[12:0]});

    // Correct to [0, q-1]
    wire signed [24:0] r1;
    wire signed [24:0] r2;
    assign r1 = (r >= $signed({1'b0, MLKEM_Q[12:0]})) ? r - $signed({1'b0, MLKEM_Q[12:0]}) : r;
    assign r2 = (r1 < 0) ? r1 + $signed({1'b0, MLKEM_Q[12:0]}) : r1;

    assign result = r2[11:0];

endmodule