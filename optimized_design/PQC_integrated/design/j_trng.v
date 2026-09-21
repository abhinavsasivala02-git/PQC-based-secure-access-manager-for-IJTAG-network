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

// Free-running 32-bit LFSR that masks TDO until the AM unlocks.
//
// The LFSR only expands its seed, so pulse seed_valid with entropy from the
// SoC TRNG to make the sequence unpredictable. Left undriven it runs from the
// built-in SEED, which is fine for simulation but is a known constant.
module j_trng #(
  parameter [31:0] SEED = 32'h0EDCBA00
)(
  input  wire        clk,
  input  wire        rst_n,
  input  wire        seed_valid,
  input  wire [31:0] seed_in,
  output wire [31:0] j_data,
  output reg         j_bit
);

  reg [31:0] lfsr;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      lfsr  <= SEED;
      j_bit <= 1'b0;
    end else if (seed_valid === 1'b1) begin
      lfsr  <= (seed_in == 32'd0) ? SEED : seed_in;   // all-zero state sticks
      j_bit <= lfsr[0];
    end else begin
      lfsr <= {lfsr[30:0], lfsr[31] ^ lfsr[29] ^ lfsr[25] ^ lfsr[24]};
      j_bit <= lfsr[0];
    end
  end

  assign j_data = lfsr;

endmodule