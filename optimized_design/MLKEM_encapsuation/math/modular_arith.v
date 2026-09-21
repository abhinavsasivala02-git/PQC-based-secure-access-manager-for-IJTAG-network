//============================================================================
// Modular Arithmetic: Addition and Subtraction mod q = 3329
// All inputs/outputs are unsigned in [0, q-1]
//============================================================================
module modular_arith (
    input  wire [11:0] a,
    input  wire [11:0] b,
    input  wire        op,    // 0 = add, 1 = subtract
    output wire [11:0] result
);

    `include "mlkem_params.vh"

    wire [12:0] sum;
    wire [12:0] diff;
    wire [11:0] add_result;
    wire [11:0] sub_result;

    // --- Addition: (a + b) mod q ---
    assign sum = {1'b0, a} + {1'b0, b};
    assign add_result = (sum >= {1'b0, MLKEM_Q[11:0]}) ? sum[11:0] - MLKEM_Q[11:0] : sum[11:0];

    // --- Subtraction: (a - b + q) mod q ---
    assign diff = {1'b0, a} - {1'b0, b};
    assign sub_result = diff[12] ? diff[11:0] + MLKEM_Q[11:0] : diff[11:0];  // if borrow, add q

    // --- Output mux ---
    assign result = op ? sub_result : add_result;

endmodule
