//============================================================================
// Barrett Reduction mod q = 3329
// Input:  signed 16-bit value a (may be in [-q, 2q) range)
// Output: a mod q in [0, q-1]
//
// Algorithm:
//   t = round(a * v / 2^26)  where v = 20159
//   r = a - t * q
//   if (r >= q) r -= q
//   if (r < 0)  r += q
//============================================================================
module barrett_reduce (
    input  wire signed [15:0] a,
    output wire        [11:0] result
);

    // ---- Parameters (inlined from mlkem_params.vh) ----
    localparam MLKEM_Q         = 13'd3329;
    localparam MLKEM_BARRETT_V = 16'd20159;
    localparam MLKEM_BARRETT_S = 5'd26;
    // ---------------------------------------------------
    // Internal wires
    (* use_dsp = "no" *) wire signed [31:0] product;
    (* use_dsp = "no" *) wire signed [15:0] t;
    wire signed [15:0] r;
    wire signed [15:0] r_corrected;

    // Step 1: t = ((a * v) + 2^25) >> 26
    assign product = $signed(a) * $signed({1'b0, MLKEM_BARRETT_V});
    assign t       = (product + 32'sd33554432) >>> 26;  // 2^25 = 33554432

    // Step 2: r = a - t * q
    assign r = a - t * $signed({1'b0, MLKEM_Q[12:0]});

    // Step 3: Conditional correction to [0, q-1]
    assign r_corrected = (r >= $signed({1'b0, MLKEM_Q[12:0]})) ? (r - $signed({1'b0, MLKEM_Q[12:0]})) :
                         (r < 0)                                 ? (r + $signed({1'b0, MLKEM_Q[12:0]})) :
                         r;

    assign result = r_corrected[11:0];

endmodule