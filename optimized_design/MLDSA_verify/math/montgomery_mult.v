// =============================================================================
// montgomery_mult.v — 4-stage pipelined Montgomery multiplier
//
// Computes: result = A * B * R^{-1} mod Q
//           where R = 2^32, Q = 8,380,417
//
// Algorithm (addition form — always positive intermediate):
//   Stage 1: product   = A * B                       (46-bit)
//   Stage 2: m         = product[31:0] * QINV_NEG    (lower 32 bits)
//   Stage 3: v         = m * Q                       (55-bit)
//   Stage 4: u         = (product + v) >> 32          (24-bit)
//            result    = (u >= Q) ? u - Q : u         (23-bit)
//
// Latency  : 4 clock cycles
// Throughput: 1 result per clock (fully pipelined)
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module montgomery_mult (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      vld_in,
    input  wire [`MLDSA_QBITS-1:0]  a,
    input  wire [`MLDSA_QBITS-1:0]  b,
    output reg  [`MLDSA_QBITS-1:0]  result,
    output reg                       vld_out
);

    // ---- Stage 1: product = A * B ----
    reg             s1_vld;
    reg  [45:0]     s1_prod;

    always @(posedge clk) begin
        if (!rst_n) begin
            s1_vld  <= 1'b0;
            s1_prod <= 46'd0;
        end else begin
            s1_vld  <= vld_in;
            s1_prod <= {23'b0, a} * {23'b0, b};
        end
    end

    // ---- Stage 2: m = lower32(product) * QINV_NEG ----
    reg             s2_vld;
    reg  [31:0]     s2_m;
    reg  [45:0]     s2_prod;

    wire [63:0] s2_m_full;
    assign s2_m_full = {32'b0, s1_prod[31:0]} * {32'b0, `MLDSA_MONT_QINV_NEG};

    always @(posedge clk) begin
        if (!rst_n) begin
            s2_vld  <= 1'b0;
            s2_m    <= 32'd0;
            s2_prod <= 46'd0;
        end else begin
            s2_vld  <= s1_vld;
            s2_m    <= s2_m_full[31:0];
            s2_prod <= s1_prod;
        end
    end

    // ---- Stage 3: v = m * Q ----
    reg             s3_vld;
    reg  [54:0]     s3_v;
    reg  [45:0]     s3_prod;

    always @(posedge clk) begin
        if (!rst_n) begin
            s3_vld  <= 1'b0;
            s3_v    <= 55'd0;
            s3_prod <= 46'd0;
        end else begin
            s3_vld  <= s2_vld;
            s3_v    <= {23'b0, s2_m} * {32'b0, 23'd`MLDSA_Q};
            s3_prod <= s2_prod;
        end
    end

    // ---- Stage 4: u = (product + v) >> 32, conditional sub Q ----
    wire [56:0] s4_sum;
    wire [23:0] s4_raw;

    assign s4_sum = {11'b0, s3_prod} + {2'b0, s3_v};
    assign s4_raw = s4_sum[55:32];

    always @(posedge clk) begin
        if (!rst_n) begin
            vld_out <= 1'b0;
            result  <= {`MLDSA_QBITS{1'b0}};
        end else begin
            vld_out <= s3_vld;
            if (s4_raw >= `MLDSA_Q)
                result <= s4_raw[`MLDSA_QBITS-1:0] - `MLDSA_Q;
            else
                result <= s4_raw[`MLDSA_QBITS-1:0];
        end
    end

endmodule
