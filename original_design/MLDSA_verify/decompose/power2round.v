// =============================================================================
// power2round.v — Power2Round decomposition (FIPS 204 Algorithm 35)
//
// Splits coefficient r into (r1, r0) where:
//   r0 = r mod 2^d  (centered, in [-2^(d-1)+1, 2^(d-1)])
//   r1 = (r - r0) / 2^d
// For ML-DSA-65: d = 13
//
// Combinational module — no clock needed.
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module power2round (
    input  wire [`MLDSA_QBITS-1:0]  r,
    output wire [`MLDSA_QBITS-1:0]  r1,     // high bits
    output wire [`MLDSA_QBITS-1:0]  r0      // low bits (centered)
);

    localparam D = `MLDSA_D_PARAM;           // 13
    localparam HALF = (1 << (D - 1));        // 2^12 = 4096

    wire [D-1:0]   r_low;
    wire [`MLDSA_QBITS-1:0] r0_pos;

    // r mod 2^d
    assign r_low = r[D-1:0];

    // Centre: if r_low > 2^(d-1), subtract 2^d
    assign r0_pos = (r_low >= HALF) ?
                    {`MLDSA_QBITS{1'b0}} | ({`MLDSA_QBITS{1'b0}} + r_low - (1 << D) + `MLDSA_Q) :
                    {{(`MLDSA_QBITS-D){1'b0}}, r_low};

    assign r0 = r0_pos;
    assign r1 = (r - r0) >> D;

endmodule
