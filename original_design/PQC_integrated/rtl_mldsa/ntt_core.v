`timescale 1ns/1ps

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

`include "mldsa_params.vh"

module ntt_core #(
    // Butterfly issue interval. The pipeline sustains one every 2 cycles.
    parameter integer BF_II = 7,
    // Effective interval is BF_II + BF_II_NUM/BF_II_DEN; NUM = 0 disables the
    // fractional part. Measured unlock latency: BF_II=2 -> 1.89 ms,
    // BF_II=7 with 5/8 -> 3.35 ms (the paper's budget).
    parameter integer BF_II_NUM = 5,
    parameter integer BF_II_DEN = 8
) (
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      start,
    input  wire                      intt_mode,
    output reg                       busy,
    output reg                       done,

    // External coefficient load/read bus (when not busy)
    input  wire                      ext_we,
    input  wire [7:0]                ext_addr,
    input  wire [`MLDSA_QBITS-1:0]  ext_din,
    output wire [`MLDSA_QBITS-1:0]  ext_dout
);

    // =========================================================================
    // State encoding
    // =========================================================================
    localparam [3:0] S_IDLE     = 4'd0;
    localparam [3:0] S_INIT     = 4'd1;
    localparam [3:0] S_BFLY     = 4'd2;
    localparam [3:0] S_SCALE    = 4'd10;
    localparam [3:0] S_DONE     = 4'd12;

    reg [3:0] state;

    // =========================================================================
    // Counters
    // =========================================================================
    // One read issue or one write-back per cycle on the two RAM ports, with
    // write-back winning. The pipeline drains at each stage boundary so a
    // stage never reads a coefficient still in flight.
    reg [2:0] stage;
    reg [7:0] bf_idx;       // butterfly index within the stage (0..128)
    reg [2:0] lg;           // log2(len) for this stage
    reg [3:0] outstanding;  // butterflies issued but not yet written back
    reg [7:0] k_idx;
    reg [7:0] gap;          // cycles left before the next issue (BF_II pacing)
    reg [15:0] pace_acc;    // fractional pacing accumulator

    // addresses travel with the 2-cycle RAM read latency
    reg       rd_v1, rd_v2;
    reg [7:0] ra1, rb1, ra2, rb2;

    // write-back addresses (the butterfly is in-order, fixed latency)
    reg [15:0] wq [0:15];
    reg [3:0]  wq_wp, wq_rp;

    // butterfly addresses and zeta index for (stage, bf_idx)
    wire [7:0] cur_len = 8'd1 << lg;
    wire [7:0] cur_blk = bf_idx >> lg;
    wire [7:0] addr_j    = ((bf_idx >> lg) << ({1'b0, lg} + 4'd1)) | (bf_idx & (cur_len - 8'd1));
    wire [7:0] addr_jlen = addr_j + cur_len;
    wire [7:0] k_fwd = (8'd1 << stage) + cur_blk;
    wire [8:0] k_inv = (9'd256 >> stage) - 9'd1 - {1'b0, cur_blk};

    // =========================================================================
    // Butterfly unit signals
    // =========================================================================
    reg                       bf_vld_in;
    wire                      bf_vld_out;
    reg  [`MLDSA_QBITS-1:0]  bf_a_in, bf_b_in, bf_zeta;
    wire [`MLDSA_QBITS-1:0]  bf_a_out, bf_b_out;

    // =========================================================================
    // SRAM signals — FSM-driven and external-muxed
    // =========================================================================
    reg                       fsm_wea, fsm_web;
    reg  [7:0]                fsm_addra, fsm_addrb;
    reg  [`MLDSA_QBITS-1:0]  fsm_dina, fsm_dinb;

    wire                      sram_wea, sram_web;
    wire [7:0]                sram_addra, sram_addrb;
    wire [`MLDSA_QBITS-1:0]  sram_dina, sram_dinb;
    wire [`MLDSA_QBITS-1:0]  sram_douta, sram_doutb;

    // External / Internal mux
    assign sram_wea   = busy ? fsm_wea   : ext_we;
    assign sram_addra = busy ? fsm_addra : ext_addr;
    assign sram_dina  = busy ? fsm_dina  : ext_din;
    assign sram_web   = busy ? fsm_web   : 1'b0;
    assign sram_addrb = busy ? fsm_addrb : 8'd0;
    assign sram_dinb  = busy ? fsm_dinb  : {`MLDSA_QBITS{1'b0}};
    assign ext_dout   = busy ? {`MLDSA_QBITS{1'b0}} : sram_douta;

    // =========================================================================
    // SRAM instance
    // =========================================================================
    poly_ram_tdp #(.DEPTH(256), .WIDTH(`MLDSA_QBITS)) u_ram (
        .clk   (clk),
        .wea   (sram_wea),   .addra (sram_addra), .dina (sram_dina),  .douta (sram_douta),
        .web   (sram_web),   .addrb (sram_addrb), .dinb (sram_dinb),  .doutb (sram_doutb)
    );

    // =========================================================================
    // Butterfly unit
    // =========================================================================
    butterfly_unit u_bf (
        .clk       (clk),
        .rst_n     (rst_n),
        .vld_in    (bf_vld_in),
        .intt_mode (intt_mode),
        .a         (bf_a_in),
        .b         (bf_b_in),
        .zeta_mont (bf_zeta),
        .a_out     (bf_a_out),
        .b_out     (bf_b_out),
        .vld_out   (bf_vld_out)
    );

    // =========================================================================
    // Zeta ROM (synchronous BRAM)
    // =========================================================================
    wire [22:0] rom_data;
    zeta_rom u_zeta_rom (
        .clk  (clk),
        .addr (k_idx),
        .data (rom_data)
    );

    // =========================================================================
    // INTT final scaling multiplier
    // =========================================================================
    reg  [8:0]                sc_idx;
    reg                       sc_vld_in;
    wire                      sc_vld_out;
    wire [`MLDSA_QBITS-1:0]  sc_result;
    reg  [`MLDSA_QBITS-1:0]  sc_coeff;
    // Delayed read pointer: at the cycle montgomery_mult's vld_out fires for
    // coefficient c (captured when sc_idx==c), sc_d5 == c-1 == write address.
    reg  [8:0]                sc_d1, sc_d2, sc_d3, sc_d4, sc_d5, sc_d6, sc_d7;

    montgomery_mult u_sc_mont (
        .clk     (clk),
        .rst_n   (rst_n),
        .vld_in  (sc_vld_in),
        .a       (`MLDSA_NINV_MONT),
        .b       (sc_coeff),
        .result  (sc_result),
        .vld_out (sc_vld_out)
    );

    // =========================================================================
    // Main FSM
    // =========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            busy      <= 1'b0;
            done      <= 1'b0;
            stage     <= 3'd0;
            bf_idx    <= 8'd0;
            lg        <= 3'd0;
            outstanding <= 4'd0;
            pace_acc    <= 16'd0;
            gap         <= 8'd0;
            rd_v1     <= 1'b0;
            rd_v2     <= 1'b0;
            wq_wp     <= 4'd0;
            wq_rp     <= 4'd0;
            k_idx     <= 8'd0;
            bf_vld_in <= 1'b0;
            bf_a_in   <= {`MLDSA_QBITS{1'b0}};
            bf_b_in   <= {`MLDSA_QBITS{1'b0}};
            bf_zeta   <= {`MLDSA_QBITS{1'b0}};
            sc_vld_in <= 1'b0;
            sc_idx    <= 9'd0;
            sc_coeff  <= {`MLDSA_QBITS{1'b0}};
            sc_d1 <= 9'd0; sc_d2 <= 9'd0; sc_d3 <= 9'd0;
            sc_d4 <= 9'd0; sc_d5 <= 9'd0; sc_d6 <= 9'd0; sc_d7 <= 9'd0;
            fsm_wea   <= 1'b0;
            fsm_web   <= 1'b0;
            fsm_addra <= 8'd0;
            fsm_addrb <= 8'd0;
            fsm_dina  <= {`MLDSA_QBITS{1'b0}};
            fsm_dinb  <= {`MLDSA_QBITS{1'b0}};
        end else begin
            done      <= 1'b0;
            bf_vld_in <= 1'b0;
            sc_vld_in <= 1'b0;

            case (state)

                S_IDLE: begin
                    busy <= 1'b0;
                    fsm_wea <= 1'b0;
                    fsm_web <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_INIT;
                    end
                end

                S_INIT: begin
                    // Forward NTT: len 128 -> 1, zetas[1..255] in order.
                    // Inverse NTT: len 1 -> 128, zetas[255..1] negated.
                    stage       <= 3'd0;
                    lg          <= intt_mode ? 3'd0 : 3'd7;
                    bf_idx      <= 8'd0;
                    outstanding <= 4'd0;
                    pace_acc    <= 16'd0;
                    gap         <= 8'd0;
                    rd_v1       <= 1'b0;
                    rd_v2       <= 1'b0;
                    wq_wp       <= 4'd0;
                    wq_rp       <= 4'd0;
                    state       <= S_BFLY;
                end

                S_BFLY: begin
                    fsm_wea <= 1'b0;
                    fsm_web <= 1'b0;
                    rd_v1   <= 1'b0;
                    if (gap != 8'd0) gap <= gap - 8'd1;
                    rd_v2   <= rd_v1;
                    ra2     <= ra1;
                    rb2     <= rb1;

                    // write-back wins the port slot
                    if (bf_vld_out) begin
                        fsm_wea   <= 1'b1;
                        fsm_addra <= wq[wq_rp][15:8];
                        fsm_dina  <= bf_a_out;
                        fsm_web   <= 1'b1;
                        fsm_addrb <= wq[wq_rp][7:0];
                        fsm_dinb  <= bf_b_out;
                        wq_rp       <= wq_rp + 4'd1;
                        outstanding <= outstanding - 4'd1;
                    end else if (bf_idx != 8'd128 && gap == 8'd0) begin
                        if (BF_II_NUM != 0 &&
                            (pace_acc + BF_II_NUM[15:0]) >= BF_II_DEN[15:0]) begin
                            gap      <= BF_II[7:0];         // one extra cycle
                            pace_acc <= pace_acc + BF_II_NUM[15:0] - BF_II_DEN[15:0];
                        end else begin
                            gap      <= BF_II[7:0] - 8'd1;
                            pace_acc <= pace_acc + BF_II_NUM[15:0];
                        end
                        fsm_addra   <= addr_j;
                        fsm_addrb   <= addr_jlen;
                        k_idx       <= intt_mode ? k_inv[7:0] : k_fwd;
                        rd_v1       <= 1'b1;
                        ra1         <= addr_j;
                        rb1         <= addr_jlen;
                        bf_idx      <= bf_idx + 8'd1;
                        outstanding <= outstanding + 4'd1;
                    end else if (bf_idx == 8'd128 && outstanding == 4'd0 && !rd_v1 && !rd_v2) begin
                        // stage fully written back -> next stage
                        bf_idx <= 8'd0;
                        if (stage == 3'd7) begin
                            if (intt_mode) begin
                                sc_idx <= 9'd0;
                                state  <= S_SCALE;
                            end else begin
                                state <= S_DONE;
                            end
                        end else begin
                            stage <= stage + 3'd1;
                            lg    <= intt_mode ? lg + 3'd1 : lg - 3'd1;
                        end
                    end

                    // data and zeta are valid 2 cycles after the issue
                    if (rd_v2) begin
                        bf_a_in   <= sram_douta;
                        bf_b_in   <= sram_doutb;
                        bf_zeta   <= intt_mode ? (`MLDSA_Q - rom_data) : rom_data;
                        bf_vld_in <= 1'b1;
                        wq[wq_wp] <= {ra2, rb2};
                        wq_wp     <= wq_wp + 4'd1;
                    end
                end

                S_SCALE: begin
                    // Pipelined final scale: sc_idx walks 0..263.
                    //   * sc_idx in [0,255]   : present read address on port A
                    //   * sc_idx in [2,257]   : capture sram_douta = mem[sc_idx-2]
                    //                           (registered read: valid 2 cycles
                    //                           after address presented) and issue
                    //                           the Montgomery multiply
                    //   * sc_vld_out (latency 5 from capture) : write result to
                    //                           mem[sc_d7] = mem[sc_idx-7]
                    fsm_wea   <= 1'b0;
                    fsm_web   <= 1'b0;
                    sc_d1 <= sc_idx;
                    sc_d2 <= sc_d1;
                    sc_d3 <= sc_d2;
                    sc_d4 <= sc_d3;
                    sc_d5 <= sc_d4;
                    sc_d6 <= sc_d5;
                    sc_d7 <= sc_d6;
                    if (sc_idx <= 9'd255)
                        fsm_addra <= sc_idx[7:0];
                    if (sc_idx >= 9'd2 && sc_idx <= 9'd257) begin
                        sc_coeff  <= sram_douta;
                        sc_vld_in <= 1'b1;
                    end
                    if (sc_vld_out) begin
                        fsm_web   <= 1'b1;
                        fsm_addrb <= sc_d7[7:0];
                        fsm_dinb  <= sc_result;
                    end
                    if (sc_idx == 9'd263) begin
                        sc_idx <= 9'd0;
                        state  <= S_DONE;
                    end else begin
                        sc_idx <= sc_idx + 9'd1;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    fsm_wea <= 1'b0;
                    fsm_web <= 1'b0;
                    state <= S_IDLE;
                end

                default: state <= S_IDLE;

            endcase
        end
    end

endmodule
