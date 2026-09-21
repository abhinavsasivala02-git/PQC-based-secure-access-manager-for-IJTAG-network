// =============================================================================
// decompose.v — Decompose function (FIPS 204 Algorithm 36)
//
// For ML-DSA-65 with gamma2 = (Q-1)/32 = 261888:
//   r+ = r mod Q
//   r0 = r+ mod+/- (2*gamma2)
//   if (r+ - r0 == Q-1): r1 = 0, r0 = r0 - 1
//   else: r1 = (r+ - r0) / (2*gamma2)
//
// Combinational module.
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module decompose (
    input  wire [`MLDSA_QBITS-1:0]  r,
    output reg  [`MLDSA_QBITS-1:0]  r1,
    output reg  [`MLDSA_QBITS-1:0]  r0
);

    localparam GAMMA2     = `MLDSA_GAMMA2;         // 261888
    localparam GAMMA2X2   = 2 * GAMMA2;            // 523776
    localparam Q_MINUS_1  = `MLDSA_Q - 1;          // 8380416

    reg [`MLDSA_QBITS:0] r_plus;
    reg [`MLDSA_QBITS:0] r0_tmp;

    always @(*) begin
        r_plus = {1'b0, r};

        // r0 = r+ mod+/- (2*gamma2)
        // Centred modular reduction
        r0_tmp = r_plus % GAMMA2X2;
        if (r0_tmp > GAMMA2)
            r0_tmp = r0_tmp - GAMMA2X2;

        if (r_plus - r0_tmp == Q_MINUS_1) begin
            r1 = {`MLDSA_QBITS{1'b0}};
            // r0 = r0 - 1 (mod Q)
            if (r0_tmp == 0)
                r0 = `MLDSA_Q - 1;
            else
                r0 = r0_tmp[`MLDSA_QBITS-1:0] - 1;
        end else begin
            r1 = (r_plus - r0_tmp) / GAMMA2X2;
            r0 = r0_tmp[`MLDSA_QBITS-1:0];
        end
    end

endmodule
