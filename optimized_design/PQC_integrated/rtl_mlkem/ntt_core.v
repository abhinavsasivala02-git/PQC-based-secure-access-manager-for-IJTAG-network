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
// Unified NTT Core - Handles both forward NTT and inverse NTT
// Single butterfly unit shared between CT (forward) and GS (inverse) modes
//
// mode = 0: Forward NTT (Cooley-Tukey)
// mode = 1: Inverse NTT (Gentleman-Sande) with final f=1441 scaling
//
// Operands stream in on read-only port B (lo then hi) while results go back
// on port A, so a butterfly issues every 2 cycles. The pipeline drains at each
// layer boundary so a layer never reads a coefficient still in flight.
//============================================================================
module mlkem_ntt_core (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire        mode,       // 0=forward NTT, 1=inverse NTT
    output reg         done,
    output reg         busy,

    // Polynomial RAM interface - Port A (read/write)
    output reg         ram_wen,
    output reg  [7:0]  ram_addr_a,
    output reg  [11:0] ram_wdata_a,
    input  wire [11:0] ram_rdata_a,

    // Polynomial RAM interface - Port B (read-only)
    output reg  [7:0]  ram_addr_b,
    input  wire [11:0] ram_rdata_b
);

    localparam MLKEM_INTT_F = 16'd512;

    localparam S_IDLE  = 2'd0;
    localparam S_BFLY  = 2'd1;
    localparam S_SCALE = 2'd2;
    localparam S_DONE  = 2'd3;

    reg [1:0] state;
    reg       mode_reg;
    reg [2:0] layer;         // 0..6
    reg [7:0] b_idx;         // butterfly index within the layer, 0..128
    reg       phase;         // 0: issue lo read, 1: issue hi read
    reg [7:0] outstanding;   // issued butterflies with the hi result still due
    reg [6:0] k;
    reg [8:0] sc_idx;

    // forward: len = 128 >> layer, k = 2^layer + blk
    // inverse: len =   2 << layer, k = (127 >> layer) - blk
    wire [3:0] lg    = mode_reg ? ({1'b0, layer} + 4'd1) : (4'd7 - {1'b0, layer});
    wire [7:0] len   = 8'd1 << lg;
    wire [7:0] blk   = b_idx >> lg;
    wire [7:0] lo    = ((b_idx >> lg) << (lg + 4'd1)) | (b_idx & (len - 8'd1));
    wire [7:0] hi    = lo + len;
    wire [6:0] k_fwd = (7'd1 << layer) + blk[6:0];
    wire [6:0] k_inv = (7'd127 >> layer) - blk[6:0];

    // Read pipeline (port B data valid 2 cycles after the address is issued)
    reg        p1_v, p1_hi, p2_v, p2_hi;
    reg [7:0]  p1_addr, p2_addr;
    reg [11:0] lo_data;
    reg [7:0]  lo_addr_q;

    // Butterfly I/O
    reg                bfly_valid_in;
    wire signed [15:0] bfly_a_out, bfly_b_out;
    wire               bfly_valid_out;
    reg  signed [15:0] bfly_a_in, bfly_b_in;
    reg  signed [15:0] zeta_q;
    reg  [7:0]         bf_lo, bf_hi, w_lo, w_hi;

    // Second write-back slot (hi result)
    reg                wr2;
    reg  [11:0]        hold_b;
    reg  [7:0]         hold_hi;

    // INTT scaling pipeline
    reg        s1_v, s2_v;
    reg [7:0]  s1_i, s2_i;

    // Zeta ROM (registered output)
    wire signed [15:0] zeta_val;
    ntt_rom u_zeta_rom (
        .clk  (clk),
        .addr (k),
        .zeta (zeta_val)
    );

    // Montgomery multiply for INTT final scaling
    (* use_dsp = "no" *) wire signed [31:0] scale_product;
    wire [11:0] scale_result;
    assign scale_product = $signed({4'b0, ram_rdata_b}) * $signed(MLKEM_INTT_F);

    montgomery_reduce u_mont_scale (
        .a      (scale_product),
        .result (scale_result)
    );

    // mode selects CT (forward) vs GS (inverse)
    ntt_butterfly u_butterfly (
        .clk       (clk),
        .rst_n     (rst_n),
        .valid_in  (bfly_valid_in),
        .mode      (mode_reg),
        .a_in      (bfly_a_in),
        .b_in      (bfly_b_in),
        .zeta      (zeta_q),
        .a_out     (bfly_a_out),
        .b_out     (bfly_b_out),
        .valid_out (bfly_valid_out)
    );

    wire issue_lo = (state == S_BFLY) && (b_idx != 8'd128) && !phase;
    wire wb_hi    = (state == S_BFLY) && !bfly_valid_out && wr2;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_IDLE;
            done          <= 1'b0;
            busy          <= 1'b0;
            ram_wen       <= 1'b0;
            ram_addr_a    <= 8'd0;
            ram_addr_b    <= 8'd0;
            ram_wdata_a   <= 12'd0;
            mode_reg      <= 1'b0;
            layer         <= 3'd0;
            b_idx         <= 8'd0;
            phase         <= 1'b0;
            outstanding   <= 8'd0;
            k             <= 7'd0;
            sc_idx        <= 9'd0;
            p1_v <= 1'b0; p1_hi <= 1'b0; p1_addr <= 8'd0;
            p2_v <= 1'b0; p2_hi <= 1'b0; p2_addr <= 8'd0;
            lo_data       <= 12'd0;
            lo_addr_q     <= 8'd0;
            bfly_valid_in <= 1'b0;
            bfly_a_in     <= 16'sd0;
            bfly_b_in     <= 16'sd0;
            zeta_q        <= 16'sd0;
            bf_lo <= 8'd0; bf_hi <= 8'd0; w_lo <= 8'd0; w_hi <= 8'd0;
            wr2           <= 1'b0;
            hold_b        <= 12'd0;
            hold_hi       <= 8'd0;
            s1_v <= 1'b0; s2_v <= 1'b0; s1_i <= 8'd0; s2_i <= 8'd0;
        end else begin
            ram_wen       <= 1'b0;
            bfly_valid_in <= 1'b0;
            done          <= 1'b0;

            // read / address pipelines advance every cycle
            p1_v    <= 1'b0;
            p2_v    <= p1_v;
            p2_hi   <= p1_hi;
            p2_addr <= p1_addr;
            w_lo    <= bf_lo;
            w_hi    <= bf_hi;
            s1_v    <= 1'b0;
            s2_v    <= s1_v;
            s2_i    <= s1_i;

            outstanding <= outstanding + {7'd0, issue_lo} - {7'd0, wb_hi};

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy     <= 1'b1;
                        mode_reg <= mode;
                        layer    <= 3'd0;
                        b_idx    <= 8'd0;
                        phase    <= 1'b0;
                        wr2      <= 1'b0;
                        state    <= S_BFLY;
                    end
                end

                S_BFLY: begin
                    // issue lo then hi on port B
                    if (b_idx != 8'd128) begin
                        if (!phase) begin
                            ram_addr_b <= lo;
                            k          <= mode_reg ? k_inv : k_fwd;
                            p1_v <= 1'b1; p1_hi <= 1'b0; p1_addr <= lo;
                            phase      <= 1'b1;
                        end else begin
                            ram_addr_b <= hi;
                            p1_v <= 1'b1; p1_hi <= 1'b1; p1_addr <= hi;
                            phase      <= 1'b0;
                            b_idx      <= b_idx + 8'd1;
                        end
                    end else if (outstanding == 8'd0) begin

                        b_idx <= 8'd0;
                        phase <= 1'b0;
                        if (layer == 3'd6) begin
                            if (mode_reg) begin
                                sc_idx <= 9'd0;
                                state  <= S_SCALE;
                            end else begin
                                state  <= S_DONE;
                            end
                        end else begin
                            layer <= layer + 3'd1;
                        end
                    end

                    // capture operands
                    if (p2_v && !p2_hi) begin
                        lo_data   <= ram_rdata_b;
                        lo_addr_q <= p2_addr;
                    end
                    if (p2_v && p2_hi) begin
                        bfly_a_in     <= $signed({4'b0, lo_data});
                        bfly_b_in     <= $signed({4'b0, ram_rdata_b});
                        zeta_q        <= zeta_val;
                        bfly_valid_in <= 1'b1;
                        bf_lo         <= lo_addr_q;
                        bf_hi         <= p2_addr;
                    end

                    // write back lo, then hi
                    if (bfly_valid_out) begin
                        ram_wen     <= 1'b1;
                        ram_addr_a  <= w_lo;
                        ram_wdata_a <= bfly_a_out[11:0];
                        hold_b      <= bfly_b_out[11:0];
                        hold_hi     <= w_hi;
                        wr2         <= 1'b1;
                    end else if (wr2) begin
                        ram_wen     <= 1'b1;
                        ram_addr_a  <= hold_hi;
                        ram_wdata_a <= hold_b;
                        wr2         <= 1'b0;
                    end
                end

                // INTT final scaling by f, port B -> port A
                S_SCALE: begin
                    if (sc_idx != 9'd256) begin
                        ram_addr_b <= sc_idx[7:0];
                        s1_v       <= 1'b1;
                        s1_i       <= sc_idx[7:0];
                        sc_idx     <= sc_idx + 9'd1;
                    end else if (!s1_v && !s2_v) begin
                        state <= S_DONE;
                    end
                    if (s2_v) begin
                        ram_wen     <= 1'b1;
                        ram_addr_a  <= s2_i;
                        ram_wdata_a <= scale_result;
                    end
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule
