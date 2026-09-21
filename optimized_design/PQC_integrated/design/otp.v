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

// Write-once OTP model: stores ek, vksign, unlock instructions, data patterns
// and the key_state one-time flag. Two combinational read ports.
module otp #(
  parameter DEPTH  = 4096,
  parameter ADDR_W = 12
)(
  input  wire              clk,
  input  wire              rst_n,

  // Provisioning (write-once) port
  input  wire              prog_we,
  input  wire [ADDR_W-1:0] prog_addr,
  input  wire [7:0]        prog_data,
  input  wire              prog_lock,
  output reg               programmed,

  // Read port A (ML-KEM ek)
  input  wire [ADDR_W-1:0] rd_addr_a,
  output wire [7:0]        rd_data_a,

  // Read port B (boot-load of vksign / patterns)
  input  wire [ADDR_W-1:0] rd_addr_b,
  output wire [7:0]        rd_data_b,

  // key_state one-time flag
  input  wire              set_key_state,
  output reg               key_state
);

  reg [7:0] mem [0:DEPTH-1];
  integer   k;

  initial begin
    programmed = 1'b0;
    key_state  = 1'b0;
    for (k = 0; k < DEPTH; k = k + 1)
      mem[k] = 8'h00;
  end

  assign rd_data_a = mem[rd_addr_a];
  assign rd_data_b = mem[rd_addr_b];

  // Writes only before the OTP is locked; programmed state survives reset.
  always @(posedge clk) begin
    if (prog_lock)
      programmed <= 1'b1;
    else if (prog_we && !programmed)
      mem[prog_addr] <= prog_data;
  end

  // key_state: set-only, irrevocable.
  always @(posedge clk) begin
    if (set_key_state)
      key_state <= 1'b1;
  end

endmodule