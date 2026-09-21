// =============================================================================
// mod_add.v — Modular addition/subtraction mod Q (combinational)
//
// sum  = (a + b) mod Q
// diff = (a - b + Q) mod Q
// Fully combinational, no clock needed.
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module mod_add (
    input  wire [`MLDSA_QBITS-1:0] a,
    input  wire [`MLDSA_QBITS-1:0] b,
    output reg  [`MLDSA_QBITS-1:0] sum,
    output reg  [`MLDSA_QBITS-1:0] diff
);

    reg [`MLDSA_QBITS:0] sum_wide, sum_corr;
    reg [`MLDSA_QBITS:0] diff_wide, diff_corr;

    always @(*) begin
        // Addition: (a + b) mod Q
        sum_wide = {1'b0, a} + {1'b0, b};
        sum_corr = sum_wide - `MLDSA_Q;
        if (sum_corr[`MLDSA_QBITS])
            sum = sum_wide[`MLDSA_QBITS-1:0];   // sum < Q, no correction
        else
            sum = sum_corr[`MLDSA_QBITS-1:0];   // sum >= Q, subtract Q

        // Subtraction: (a - b + Q) mod Q
        diff_wide = {1'b0, a} - {1'b0, b};
        diff_corr = diff_wide + `MLDSA_Q;
        if (diff_wide[`MLDSA_QBITS])
            diff = diff_corr[`MLDSA_QBITS-1:0];  // was negative, add Q
        else
            diff = diff_wide[`MLDSA_QBITS-1:0];  // non-negative, ok
    end

endmodule
