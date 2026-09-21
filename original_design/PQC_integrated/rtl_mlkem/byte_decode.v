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
// ByteDecode_d — Algorithm 6 of FIPS 203
// Decodes 32*d bytes into 256 d-bit integers
//
// Inverse of ByteEncode: unpacks bytes into polynomial coefficients
// For d < 12, output values are naturally in [0, 2^d - 1]
// For d = 12, output values are reduced mod q
module byte_decode #(
    parameter D = 12     // Bit-width per coefficient (1..12)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    output reg         done,
    output reg         busy,
    // Input byte stream
    input  wire        byte_valid,
    input  wire [7:0]  byte_data,
    output reg         byte_req,

    // Output polynomial RAM — write interface
    output reg         poly_wen,
    output reg  [7:0]  poly_addr,
    output reg  [11:0] poly_wdata
);

    `include "mlkem_params.vh"

    localparam TOTAL_BYTES = 32 * D;

    // One byte requested per cycle (the source answers a cycle later) and one
    // coefficient written as soon as D bits are buffered.
    localparam S_IDLE = 2'd0;
    localparam S_RUN  = 2'd1;
    localparam S_DONE = 2'd2;

    reg [1:0]  state;
    reg [39:0] bit_acc;
    reg [5:0]  bit_cnt;
    reg [8:0]  coeff_idx;      // 0..256
    reg [10:0] in_byte_cnt;    // bytes requested so far

    // Extracted coefficient (before mod q)
    wire [11:0] raw_coeff;
    wire [11:0] reduced_coeff;
    assign raw_coeff = bit_acc[D-1:0];
    // For d=12, reduce mod q; for d<12, no reduction needed
    assign reduced_coeff = (D == 12 && raw_coeff >= MLKEM_Q[11:0]) ?
                           raw_coeff - MLKEM_Q[11:0] : raw_coeff;

    reg [39:0] nxt_acc;
    reg [5:0]  nxt_cnt;
    reg        wr_now;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            done        <= 1'b0;
            busy        <= 1'b0;
            poly_wen    <= 1'b0;
            poly_addr   <= 8'd0;
            poly_wdata  <= 12'd0;
            byte_req    <= 1'b0;
            bit_acc     <= 40'd0;
            bit_cnt     <= 6'd0;
            coeff_idx   <= 9'd0;
            in_byte_cnt <= 11'd0;
        end else begin
            poly_wen <= 1'b0;
            done     <= 1'b0;
            byte_req <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy        <= 1'b1;
                        coeff_idx   <= 9'd0;
                        bit_acc     <= 40'd0;
                        bit_cnt     <= 6'd0;
                        in_byte_cnt <= 11'd1;
                        byte_req    <= 1'b1;
                        state       <= S_RUN;
                    end
                end

                S_RUN: begin
                    // emit a coefficient if enough bits are buffered
                    wr_now  = (bit_cnt >= D) && (coeff_idx < 9'd256);
                    nxt_acc = bit_acc;
                    nxt_cnt = bit_cnt;
                    if (wr_now) begin
                        poly_wen   <= 1'b1;
                        poly_addr  <= coeff_idx[7:0];
                        poly_wdata <= reduced_coeff;
                        coeff_idx  <= coeff_idx + 9'd1;
                        nxt_acc    = bit_acc >> D;
                        nxt_cnt    = bit_cnt - D;
                    end
                    // absorb the byte arriving this cycle
                    if (byte_valid) begin
                        nxt_acc = nxt_acc | ({32'd0, byte_data} << nxt_cnt);
                        nxt_cnt = nxt_cnt + 6'd8;
                    end
                    bit_acc <= nxt_acc;
                    bit_cnt <= nxt_cnt;

                    // keep requesting while there is room
                    if (in_byte_cnt < TOTAL_BYTES && nxt_cnt <= 6'd20) begin
                        byte_req    <= 1'b1;
                        in_byte_cnt <= in_byte_cnt + 11'd1;
                    end

                    if (wr_now && coeff_idx == 9'd255)
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
