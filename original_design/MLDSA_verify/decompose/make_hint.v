// =============================================================================
// make_hint.v — MakeHint function (FIPS 204 Algorithm 38)
//
// hint = 1 if HighBits(r) != HighBits(r + z)
// Used during signing to compute hint vector h.
// Combinational.
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module make_hint (
    input  wire [`MLDSA_QBITS-1:0]  z,
    input  wire [`MLDSA_QBITS-1:0]  r,
    output wire                      hint
);

    // Decompose r
    wire [`MLDSA_QBITS-1:0] r1_a, r0_a;
    decompose u_dec_r (
        .r  (r),
        .r1 (r1_a),
        .r0 (r0_a)
    );

    // Decompose (r + z) mod Q
    wire [`MLDSA_QBITS-1:0] rz_sum;
    wire [`MLDSA_QBITS-1:0] rz_dummy;

    mod_add u_add (
        .a    (r),
        .b    (z),
        .sum  (rz_sum),
        .diff (rz_dummy)
    );

    wire [`MLDSA_QBITS-1:0] r1_b, r0_b;
    decompose u_dec_rz (
        .r  (rz_sum),
        .r1 (r1_b),
        .r0 (r0_b)
    );

    // hint = 1 if high bits differ
    assign hint = (r1_a != r1_b) ? 1'b1 : 1'b0;

endmodule
