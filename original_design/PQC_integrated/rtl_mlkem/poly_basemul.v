/*
 * Copyright (C) 2026
 * Author: Abhinav S <abhinavsasivala02@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 */

//============================================================================
// Polynomial Base Multiplication in NTT Domain - Algorithm 11 of FIPS 203
// Multiplies two NTT-domain polynomials coefficient-pair-wise
//
// In the NTT domain, a 256-coeff polynomial becomes 128 pairs (a0,a1).
// BaseMul for pair i:
//   c0 = a0*b0 + a1*b1*gamma_i
//   c1 = a0*b1 + a1*b0
// where gamma_i = zeta^(2*BitRev7(i)+1) is the pair twiddle factor.
//
// All multiplications use Montgomery reduction.
//============================================================================
module poly_basemul (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         done,
    output reg         busy,
    output reg  [7:0]  a_addr,
    input  wire [11:0] a_rdata,
    output reg  [7:0]  b_addr,
    input  wire [11:0] b_rdata,
    output reg         c_wen,
    output reg  [7:0]  c_addr,
    output reg  [11:0] c_wdata
);
    // Coefficients are read one per cycle. Even ones (a0,b0) are latched; each
    // odd one launches the pair down a 3-stage pipeline, and c0/c1 are written
    // on consecutive cycles - one coefficient per cycle overall.
    // A must be read on a different port from the one C is written on.
    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0] state;
    reg [8:0] idx;                       // 0..256
    reg       v1, v2;
    reg [7:0] i1, i2;
    reg signed [15:0] a0, b0;

    wire signed [15:0] gamma_val;
    reg  [6:0] gamma_addr;
    ntt_rom u_gamma_rom (
        .clk  (clk),
        .addr (gamma_addr),
        .zeta (gamma_val)
    );

    // stage 1: the four products (a1,b1 come straight from RAM)
    wire signed [15:0] a1 = $signed({4'b0, a_rdata});
    wire signed [15:0] b1 = $signed({4'b0, b_rdata});
    (* use_dsp = "no" *) wire signed [31:0] prod_a0b0 = a0 * b0;
    (* use_dsp = "no" *) wire signed [31:0] prod_a1b1 = a1 * b1;
    (* use_dsp = "no" *) wire signed [31:0] prod_a0b1 = a0 * b1;
    (* use_dsp = "no" *) wire signed [31:0] prod_a1b0 = a1 * b0;
    wire [11:0] m_a0b0, m_a1b1_raw, m_a0b1, m_a1b0;
    montgomery_reduce u_mont_a0b0 (.a(prod_a0b0), .result(m_a0b0));
    montgomery_reduce u_mont_a1b1 (.a(prod_a1b1), .result(m_a1b1_raw));
    montgomery_reduce u_mont_a0b1 (.a(prod_a0b1), .result(m_a0b1));
    montgomery_reduce u_mont_a1b0 (.a(prod_a1b0), .result(m_a1b0));
    // gamma is negated for odd pairs
    wire signed [15:0] gamma_sign = i2[1] ? -gamma_val : gamma_val;

    reg        s1_v;
    reg [6:0]  s1_pair;
    reg [11:0] s1_a0b0, s1_a1b1, s1_a0b1, s1_a1b0;
    reg signed [15:0] s1_g;

    // stage 2: gamma term and the c0/c1 sums
    (* use_dsp = "no" *) wire signed [31:0] prod_a1b1g = $signed({4'b0, s1_a1b1}) * s1_g;
    wire [11:0] m_a1b1g;
    montgomery_reduce u_mont_a1b1g (.a(prod_a1b1g), .result(m_a1b1g));

    reg        s2_v;
    reg [6:0]  s2_pair;
    reg signed [15:0] s2_c0, s2_c1;

    // stage 3: Montgomery conversion
    (* use_dsp = "no" *) wire signed [31:0] prod_c0_conv = s2_c0 * 16'sd1353;
    (* use_dsp = "no" *) wire signed [31:0] prod_c1_conv = s2_c1 * 16'sd1353;
    wire [11:0] m_c0, m_c1;
    montgomery_reduce u_mont_c0 (.a(prod_c0_conv), .result(m_c0));
    montgomery_reduce u_mont_c1 (.a(prod_c1_conv), .result(m_c1));

    reg        s3_v;
    reg [6:0]  s3_pair;
    reg [11:0] s3_c0, s3_c1;
    reg        wr2;
    reg [6:0]  hold_pair;
    reg [11:0] hold_c1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            done       <= 1'b0;
            busy       <= 1'b0;
            c_wen      <= 1'b0;
            a_addr     <= 8'd0;
            b_addr     <= 8'd0;
            c_addr     <= 8'd0;
            c_wdata    <= 12'd0;
            idx        <= 9'd0;
            v1 <= 1'b0; v2 <= 1'b0; i1 <= 8'd0; i2 <= 8'd0;
            a0 <= 16'sd0; b0 <= 16'sd0;
            gamma_addr <= 7'd0;
            s1_v <= 1'b0; s1_pair <= 7'd0; s1_g <= 16'sd0;
            s1_a0b0 <= 12'd0; s1_a1b1 <= 12'd0; s1_a0b1 <= 12'd0; s1_a1b0 <= 12'd0;
            s2_v <= 1'b0; s2_pair <= 7'd0; s2_c0 <= 16'sd0; s2_c1 <= 16'sd0;
            s3_v <= 1'b0; s3_pair <= 7'd0; s3_c0 <= 12'd0; s3_c1 <= 12'd0;
            wr2  <= 1'b0; hold_pair <= 7'd0; hold_c1 <= 12'd0;
        end else begin
            c_wen <= 1'b0;
            done  <= 1'b0;
            v1    <= 1'b0;
            v2    <= v1;
            i2    <= i1;
            s1_v  <= 1'b0;
            s2_v  <= s1_v;
            s2_pair <= s1_pair;
            s3_v  <= s2_v;
            s3_pair <= s2_pair;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        idx   <= 9'd0;
                        wr2   <= 1'b0;
                        state <= S_RUN;
                    end
                end

                S_RUN: begin
                    // issue reads
                    if (idx != 9'd256) begin
                        a_addr <= idx[7:0];
                        b_addr <= idx[7:0];
                        if (!idx[0])
                            gamma_addr <= 7'd64 + {1'b0, idx[7:2]};
                        v1  <= 1'b1;
                        i1  <= idx[7:0];
                        idx <= idx + 9'd1;
                    end else if (!v1 && !v2 && !s1_v && !s2_v && !s3_v && !wr2) begin
                        state <= S_DONE;
                    end

                    // latch the even coefficient, launch the pair on the odd one
                    if (v2 && !i2[0]) begin
                        a0 <= $signed({4'b0, a_rdata});
                        b0 <= $signed({4'b0, b_rdata});
                    end
                    if (v2 && i2[0]) begin
                        s1_v    <= 1'b1;
                        s1_pair <= i2[7:1];
                        s1_a0b0 <= m_a0b0;
                        s1_a1b1 <= m_a1b1_raw;
                        s1_a0b1 <= m_a0b1;
                        s1_a1b0 <= m_a1b0;
                        s1_g    <= gamma_sign;
                    end

                    // stage 2
                    s2_c0 <= $signed({1'b0, s1_a0b0}) + $signed({1'b0, m_a1b1g});
                    s2_c1 <= $signed({1'b0, s1_a0b1}) + $signed({1'b0, s1_a1b0});

                    // stage 3
                    s3_c0 <= m_c0;
                    s3_c1 <= m_c1;

                    // write c0 then c1
                    if (s3_v) begin
                        c_wen   <= 1'b1;
                        c_addr  <= {s3_pair, 1'b0};
                        c_wdata <= s3_c0;
                        hold_c1   <= s3_c1;
                        hold_pair <= s3_pair;
                        wr2     <= 1'b1;
                    end else if (wr2) begin
                        c_wen   <= 1'b1;
                        c_addr  <= {hold_pair, 1'b1};
                        c_wdata <= hold_c1;
                        wr2     <= 1'b0;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
