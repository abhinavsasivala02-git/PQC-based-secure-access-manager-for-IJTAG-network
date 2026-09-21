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
// ByteEncode_d — Algorithm 5 of FIPS 203
// Encodes 256 d-bit integers into 32*d bytes
//
// Bit-packing: takes coefficients from RAM and packs them bit-by-bit
// into output bytes (LSB first within each coefficient)
//============================================================================
module byte_encode #(
    parameter D = 12     // Bit-width per coefficient (1..12)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         done,
    output reg         busy,

    // Input polynomial RAM — read interface
    output reg  [7:0]  poly_addr,
    input  wire [11:0] poly_rdata,

    // Output byte stream
    output reg         byte_valid,
    output reg  [7:0]  byte_data,
    output reg  [10:0] byte_addr     // Address in output buffer (0..32*D-1)
);

    `include "mlkem_params.vh"

    localparam TOTAL_BYTES = 32 * D;

    // One coefficient read and one byte emitted per cycle.
    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0]  state;
    reg [39:0] bit_acc;
    reg [5:0]  bit_cnt;
    reg [8:0]  coeff_idx;    // coefficients issued (0..256)
    reg [10:0] out_byte_cnt;
    reg        v1, v2;

    reg [39:0] nxt_acc;
    reg [5:0]  nxt_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            done         <= 1'b0;
            busy         <= 1'b0;
            byte_valid   <= 1'b0;
            byte_data    <= 8'd0;
            byte_addr    <= 11'd0;
            poly_addr    <= 8'd0;
            bit_acc      <= 40'd0;
            bit_cnt      <= 6'd0;
            coeff_idx    <= 9'd0;
            out_byte_cnt <= 11'd0;
            v1 <= 1'b0; v2 <= 1'b0;
        end else begin
            byte_valid <= 1'b0;
            done       <= 1'b0;
            v1         <= 1'b0;
            v2         <= v1;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy         <= 1'b1;
                        coeff_idx    <= 9'd0;
                        bit_acc      <= 40'd0;
                        bit_cnt      <= 6'd0;
                        out_byte_cnt <= 11'd0;
                        state        <= S_RUN;
                    end
                end

                S_RUN: begin
                    // read while the accumulator has room
                    if (coeff_idx != 9'd256 && bit_cnt <= 6'd16) begin
                        poly_addr <= coeff_idx[7:0];
                        v1        <= 1'b1;
                        coeff_idx <= coeff_idx + 9'd1;
                    end

                    // emit a byte, then absorb the coefficient arriving now
                    nxt_acc = bit_acc;
                    nxt_cnt = bit_cnt;
                    if (bit_cnt >= 6'd8 ||
                        (bit_cnt > 6'd0 && coeff_idx == 9'd256 && !v1 && !v2)) begin
                        byte_valid   <= 1'b1;
                        byte_data    <= bit_acc[7:0];
                        byte_addr    <= out_byte_cnt;
                        out_byte_cnt <= out_byte_cnt + 11'd1;
                        if (bit_cnt >= 6'd8) begin
                            nxt_acc = bit_acc >> 8;
                            nxt_cnt = bit_cnt - 6'd8;
                        end else begin
                            nxt_acc = 40'd0;
                            nxt_cnt = 6'd0;
                        end
                    end
                    if (v2) begin
                        nxt_acc = nxt_acc | ({28'd0, poly_rdata[D-1:0]} << nxt_cnt);
                        nxt_cnt = nxt_cnt + D;
                    end
                    bit_acc <= nxt_acc;
                    bit_cnt <= nxt_cnt;

                    if (coeff_idx == 9'd256 && !v1 && !v2 && nxt_cnt == 6'd0 &&
                        out_byte_cnt >= TOTAL_BYTES)
                        state <= S_DONE;
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
