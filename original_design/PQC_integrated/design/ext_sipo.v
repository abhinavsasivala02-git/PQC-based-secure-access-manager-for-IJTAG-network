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

// 26,567-bit SIPO capture register for the unlock frame:
//   [26566:95]   sig_out          ML-DSA-65 signature sigma
//   [94:63]      key_out          unlock key
//   [62:31]      instruction_out  unlock instruction
//   [30:0]       data_out         unlock data
module ext_sipo(
  input  wire           clk,
  input  wire           rst,
  input  wire           shift_en,
  input  wire           tdi,
  output wire [26471:0] sig_out,
  output wire [31:0]    key_out,
  output wire [31:0]    instruction_out,
  output wire [30:0]    data_out,
  output reg            full
);

  localparam integer DEPTH = 26567;

  reg [DEPTH-1:0] shift_reg;
  reg [14:0]      bit_count;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      shift_reg <= {(DEPTH){1'b0}};
      bit_count <= 15'd0;
      full      <= 1'b0;
    end else begin
      full <= 1'b0;

      if (shift_en) begin
        shift_reg <= {shift_reg[DEPTH-2:0], tdi};
        bit_count <= bit_count + 15'd1;

        if (bit_count == 15'd26566)
          full <= 1'b1;
      end
    end
  end

  assign sig_out         = shift_reg[DEPTH-1:95];
  assign key_out         = shift_reg[94:63];
  assign instruction_out = shift_reg[62:31];
  assign data_out        = shift_reg[30:0];

endmodule