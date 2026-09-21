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

// Access Manager: LOCK -> SIG_VERIFY -> KEY_COMP -> INSTN_COMP -> DATA_COMP
// -> UNLOCK. Any failure returns to LOCK. Two-phase key protocol: cluster key
// when key_state=0, TRNG-derived KDF key when key_state=1.
module am_pqc(
  input  wire        clk,
  input  wire        reset,
  input  wire        TDI,
  input  wire        shift_en,

  // ML-DSA signature verification handshake
  input  wire        sval,
  input  wire        sig_done,
  output reg         sig_start,
  input  wire        sig_busy,

  // Two-phase key protocol
  input  wire [31:0] kdf_key,
  input  wire [31:0] otp_cluster_key,
  input  wire        otp_key_state,
  input  wire [127:0] otp_inst,
  input  wire [127:0] otp_data,
  output reg         set_key_state,

  output reg  [1:0] mux_sel,
  output reg        mux_sel_21,
  output reg        DVAL,
  output reg        TDI_out,
  output reg        unlocked,
  output wire [26471:0] sig_out
);

  wire [31:0] key_out;
  wire [31:0] inst_out;
  wire [30:0] data_out;
  wire        full;

  ext_sipo u_sipo(
    .clk             (clk),
    .rst             (reset),
    .shift_en        (shift_en),
    .tdi             (TDI),
    .sig_out         (sig_out),
    .key_out         (key_out),
    .instruction_out (inst_out),
    .data_out        (data_out),
    .full            (full)
  );

  localparam [2:0] LOCK       = 3'b000,
                   SIG_VERIFY = 3'b001,
                   KEY_COMP   = 3'b010,
                   INSTN_COMP = 3'b011,
                   DATA_COMP  = 3'b100,
                   UNLOCK     = 3'b101;

  reg [2:0] state_reg, next_state;

  always @(posedge clk, posedge reset) begin
    if (reset)
      state_reg <= LOCK;
    else
      state_reg <= next_state;
  end

  // Unpacked OTP words (word 0 at the MSBs)
  wire [31:0] otp_inst0 = otp_inst[127:96];
  wire [31:0] otp_inst1 = otp_inst[95:64];
  wire [31:0] otp_inst2 = otp_inst[63:32];
  wire [31:0] otp_inst3 = otp_inst[31:0];
  wire [31:0] otp_data_sel = otp_data[127 - mux_sel*32 -: 32];

  always @(posedge clk, posedge reset) begin
    if (reset) begin
      mux_sel   <= 2'b00;
      mux_sel_21<= 1'b0;
      DVAL      <= 1'b0;
      TDI_out   <= 1'b0;
      unlocked  <= 1'b0;
    end else if (state_reg == INSTN_COMP) begin
      case (inst_out)
        otp_inst0: begin mux_sel <= 2'b00; mux_sel_21 <= 1'b1; end
        otp_inst1: begin mux_sel <= 2'b01; mux_sel_21 <= 1'b0; end
        otp_inst2: begin mux_sel <= 2'b10; mux_sel_21 <= 1'b0; end
        otp_inst3: begin mux_sel <= 2'b11; mux_sel_21 <= 1'b0; end
        default:      begin mux_sel <= mux_sel; mux_sel_21 <= mux_sel_21; end
      endcase
    end
  end

  always @(*) begin
    next_state = state_reg;
    sig_start  = 1'b0;
    set_key_state = 1'b0;

    case (state_reg)
      LOCK: begin
        if (full)
          next_state = SIG_VERIFY;
      end

      SIG_VERIFY: begin
        sig_start = 1'b1;
        if (sig_done) begin
          if (sval)
            next_state = KEY_COMP;
          else
            next_state = LOCK;
        end
      end

      KEY_COMP: begin
        if (key_out == (otp_key_state ? kdf_key : otp_cluster_key))
          next_state = INSTN_COMP;
        else
          next_state = LOCK;
      end

      INSTN_COMP: begin
        if (inst_out == otp_inst0 || inst_out == otp_inst1 ||
            inst_out == otp_inst2 || inst_out == otp_inst3)
          next_state = DATA_COMP;
        else
          next_state = LOCK;
      end

      DATA_COMP: begin
        DVAL = (data_out == otp_data_sel[30:0]);
        if (DVAL) begin
          set_key_state = 1'b1;
          next_state = UNLOCK;
        end else
          next_state = LOCK;
      end

      UNLOCK: begin
        TDI_out  = TDI;
        DVAL     = 1'b1;
        unlocked = 1'b1;
        next_state = UNLOCK;
      end

      default: next_state = LOCK;
    endcase
  end

endmodule