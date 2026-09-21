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

// Per-instrument priority decoder: high-priority instrument outputs are
// encrypted (SHAKE-256 keystream XOR), low-priority outputs stay unencrypted.
module inst_priority_decoder(
  input  wire [1:0]  clus_sel,
  input  wire        emit_phase,
  input  wire [5:0]  priority,
  input  wire [5:0]  inst_done,
  input  wire        unlocked,
  input  wire        shift_dr,
  output wire [2:0]  inst_idx,
  output wire        high_pri,
  output wire        enc_elig
);

  // A cluster's two TDRs sit in series: the TDO-near one emits first.
  assign inst_idx = {clus_sel, ~emit_phase};

  assign high_pri = priority[inst_idx];

  assign enc_elig = unlocked & shift_dr & inst_done[inst_idx] & high_pri;

endmodule