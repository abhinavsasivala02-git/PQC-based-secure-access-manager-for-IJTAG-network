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
// Polynomial Arithmetic - Coefficient-wise add/sub and toMont
// Operations on 256-coefficient polynomials stored in RAM
//
// Modes:
//   00 = ADD:    c[i] = (a[i] + b[i]) mod q
//   01 = SUB:    c[i] = (a[i] - b[i] + q) mod q
//   10 = TOMONT: c[i] = a[i] * R^2 mod q  (convert to Montgomery domain)
//============================================================================
module mlkem_poly_arith (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [1:0]  mode,      // 00=add, 01=sub, 10=tomont
    output reg         done,
    output reg         busy,

    // Polynomial A RAM - read-only
    output reg  [7:0]  a_addr,
    input  wire [11:0] a_rdata,

    // Polynomial B RAM - read-only (unused for tomont)
    output reg  [7:0]  b_addr,
    input  wire [11:0] b_rdata,

    // Result C RAM - write
    output reg         c_wen,
    output reg  [7:0]  c_addr,
    output reg  [11:0] c_wdata
);

    // ---- Parameters (inlined from mlkem_params.vh) ----
    localparam MLKEM_MONT_RSQ = 16'd1353;
    // ---------------------------------------------------

    // One coefficient per cycle; RAM data lands two cycles after the address.
    // A must be read on a different port from the one C is written on.
    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0] state;
    reg [8:0] idx;   // 0..256
    reg       v1, v2;
    reg [7:0] i1, i2;

    // Arithmetic results
    wire [11:0] add_result;
    wire [11:0] sub_result;

    // toMont: a * R^2 mod q via Montgomery
    (* use_dsp = "no" *) wire signed [31:0] mont_product;
    wire        [11:0] mont_result;

    // Modular add/sub
    modular_arith u_mod_add (
        .a      (a_rdata),
        .b      (b_rdata),
        .op     (1'b0),
        .result (add_result)
    );

    modular_arith u_mod_sub (
        .a      (a_rdata),
        .b      (b_rdata),
        .op     (1'b1),
        .result (sub_result)
    );

    // toMont: multiply by R^2 using Montgomery reduction
    assign mont_product = $signed({4'b0, a_rdata}) * $signed({1'b0, MLKEM_MONT_RSQ});

    montgomery_reduce u_mont (
        .a      (mont_product),
        .result (mont_result)
    );


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            done    <= 1'b0;
            busy    <= 1'b0;
            c_wen   <= 1'b0;
            a_addr  <= 8'd0;
            b_addr  <= 8'd0;
            c_addr  <= 8'd0;
            c_wdata <= 12'd0;
            idx     <= 9'd0;
            v1 <= 1'b0; v2 <= 1'b0; i1 <= 8'd0; i2 <= 8'd0;
        end else begin
            c_wen <= 1'b0;
            done  <= 1'b0;
            v1    <= 1'b0;
            v2    <= v1;
            i2    <= i1;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        idx   <= 9'd0;
                        state <= S_RUN;
                    end
                end

                S_RUN: begin
                    if (idx != 9'd256) begin
                        a_addr <= idx[7:0];
                        b_addr <= idx[7:0];
                        v1     <= 1'b1;
                        i1     <= idx[7:0];
                        idx    <= idx + 9'd1;
                    end else if (!v1 && !v2) begin
                        state <= S_DONE;
                    end
                    if (v2) begin
                        c_wen  <= 1'b1;
                        c_addr <= i2;
                        case (mode)
                            2'b00:   c_wdata <= add_result;
                            2'b01:   c_wdata <= sub_result;
                            2'b10:   c_wdata <= mont_result;
                            default: c_wdata <= 12'd0;
                        endcase
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
