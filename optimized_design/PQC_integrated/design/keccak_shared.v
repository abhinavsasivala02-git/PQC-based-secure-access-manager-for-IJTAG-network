`timescale 1ns / 1ps

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

// One Keccak-f[1600] shared by every hash user: ML-KEM (H, G, PRF, SampleNTT),
// ML-DSA verification and the TDO stream cipher never run at the same time.
//
// Each user keeps its own sponge state and asks for a permutation. req[i] is
// latched, din[i] must hold until done[i] pulses, and dout then carries the
// result. Fixed priority, user 0 first; a grant costs one cycle so the state
// mux settles before the core starts.
module keccak_shared #(
    parameter integer N = 6          // number of users (<= 8)
)(
    input  wire                clk,
    input  wire                rst_n,

    input  wire [N-1:0]        req,
    input  wire [N*1600-1:0]   din,      // user i at [i*1600 +: 1600]
    output reg  [N-1:0]        busy,
    output reg  [N-1:0]        done,
    output wire [1599:0]       dout
);

    localparam SEL_W = 3;

    reg  [N-1:0]     pend;
    reg              active;         // core running for user sel
    reg              granting;       // sel chosen, start issued next cycle
    reg  [SEL_W-1:0] sel;
    reg              core_start;

    wire             core_busy, core_done;
    wire [1599:0]    core_din = din[sel*1600 +: 1600];

    keccak_f1600 u_core (
        .clk       (clk),
        .rst_n     (rst_n),
        .start     (core_start),
        .state_in  (core_din),
        .state_out (dout),
        .busy      (core_busy),
        .done      (core_done)
    );

    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend       <= {N{1'b0}};
            active     <= 1'b0;
            granting   <= 1'b0;
            sel        <= {SEL_W{1'b0}};
            core_start <= 1'b0;
            done       <= {N{1'b0}};
        end else begin
            core_start <= 1'b0;
            done       <= {N{1'b0}};

            if (granting) begin
                core_start <= 1'b1;
                active     <= 1'b1;
                granting   <= 1'b0;
                pend[sel]  <= 1'b0;
            end else if (active) begin
                if (core_done) begin
                    active    <= 1'b0;
                    done[sel] <= 1'b1;
                end
            end else begin
                for (i = N-1; i >= 0; i = i - 1)
                    if (pend[i] || req[i]) begin
                        sel      <= i[SEL_W-1:0];
                        granting <= 1'b1;
                    end
            end

            // latch requests last so one arriving during a grant is kept
            for (i = 0; i < N; i = i + 1)
                if (req[i]) pend[i] <= 1'b1;
        end
    end

    always @(*) begin
        for (i = 0; i < N; i = i + 1)
            busy[i] = pend[i] | (((active | granting) & (sel == i[SEL_W-1:0])) ? 1'b1 : 1'b0);
    end

endmodule
