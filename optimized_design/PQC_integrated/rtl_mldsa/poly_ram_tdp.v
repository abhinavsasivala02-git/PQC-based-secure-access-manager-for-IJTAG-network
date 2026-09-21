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

module poly_ram_tdp #(
    parameter DEPTH = 256,
    parameter WIDTH = 24
) (
    input  wire                       clk,
    // Port A: read + write
    input  wire                       wea,
    input  wire [$clog2(DEPTH)-1:0]   addra,
    input  wire [WIDTH-1:0]           dina,
    output reg  [WIDTH-1:0]           douta,
    // Port B: read + write
    input  wire                       web,
    input  wire [$clog2(DEPTH)-1:0]   addrb,
    input  wire [WIDTH-1:0]           dinb,
    output reg  [WIDTH-1:0]           doutb
);

    (* ram_style = "auto" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Port A
    always @(posedge clk) begin
        if (wea) mem[addra] <= dina;
        douta <= mem[addra];
    end

    // Port B
    always @(posedge clk) begin
        if (web) mem[addrb] <= dinb;
        doutb <= mem[addrb];
    end

    // Simulation-only init
    // pragma translate_off
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WIDTH{1'b0}};
    end
    // pragma translate_on

endmodule
