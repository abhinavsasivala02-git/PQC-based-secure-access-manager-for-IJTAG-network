// =============================================================================
// use_hint.v — UseHint function (FIPS 204 Algorithm 39)
//
// If hint=0: return HighBits(r)
// If hint=1: adjust r1 by +/-1 depending on r0 sign
// Used during verification to recover w1.
// Combinational.
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module use_hint (
    input  wire                      hint,
    input  wire [`MLDSA_QBITS-1:0]  r,
    output reg  [`MLDSA_QBITS-1:0]  r1_out
);

    localparam GAMMA2   = `MLDSA_GAMMA2;
    localparam M        = (`MLDSA_Q - 1) / (2 * GAMMA2);  // number of high values

    wire [`MLDSA_QBITS-1:0] r1, r0;

    decompose u_dec (
        .r  (r),
        .r1 (r1),
        .r0 (r0)
    );

    // Check if r0 > 0 (i.e., positive side)
    wire r0_positive;
    assign r0_positive = (r0 != {`MLDSA_QBITS{1'b0}} && r0 < GAMMA2);

    always @(*) begin
        if (!hint) begin
            r1_out = r1;
        end else begin
            if (r0_positive) begin
                // r1 + 1 mod M
                if (r1 + 1 >= M)
                    r1_out = {`MLDSA_QBITS{1'b0}};
                else
                    r1_out = r1 + 1;
            end else begin
                // r1 - 1 mod M
                if (r1 == {`MLDSA_QBITS{1'b0}})
                    r1_out = M - 1;
                else
                    r1_out = r1 - 1;
            end
        end
    end

endmodule
