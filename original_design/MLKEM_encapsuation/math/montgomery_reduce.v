//============================================================================
// Montgomery Reduction
// Input:  signed 32-bit value a (product of two 16-bit values)
// Output: a * R^{-1} mod q, where R = 2^16
//
// Algorithm:
//   t = (int16_t)(a * QINV)       // low 16 bits
//   r = (a - t * q) >> 16
//   if (r < 0) r += q
//   if (r >= q) r -= q
//
// QINV = 62209 (= -3327 mod 2^16) such that q * QINV == 1 (mod 2^16)
    // Montgomery: t = (a*QINV) low 16 bits; r = (a - t*q) >> 16 == a*R^-1 mod q
//============================================================================
module montgomery_reduce (
    input  wire signed [31:0] a,
    output wire        [11:0] result
);

    // ---- Parameters (inlined from mlkem_params.vh) ----
    localparam MLKEM_Q    = 13'd3329;
    localparam MLKEM_QINV = 16'd62209;
    // ---------------------------------------------------
    (* use_dsp = "no" *) wire signed [15:0] t;
    (* use_dsp = "no" *) wire signed [31:0] u;
    wire signed [15:0] r;
    wire signed [15:0] r_corrected;

    // Step 1: t = (int16)(a * QINV)  - keep only low 16 bits
    assign t = a[15:0] * MLKEM_QINV;

    // Step 2: u = t * q  (sign-extend t, multiply by q)
    assign u = $signed(t) * $signed({1'b0, MLKEM_Q[12:0]});

    // Step 3: r = (a - u) >> 16  - exact division by R
    assign r = (a - u) >>> 16;

    // Step 4: Conditional correction to [0, q-1]
    assign r_corrected = (r < 0)                                 ? (r + $signed({1'b0, MLKEM_Q[12:0]})) :
                         (r >= $signed({1'b0, MLKEM_Q[12:0]}))   ? (r - $signed({1'b0, MLKEM_Q[12:0]})) :
                         r;

    assign result = r_corrected[11:0];

endmodule