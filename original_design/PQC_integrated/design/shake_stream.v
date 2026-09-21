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

// SHAKE-256 stream cipher: keystream = SHAKE-256(key || iv), rate 136 bytes.
// 80-bit key from the ML-KEM shared secret, 80-bit IV from the TRNG per session.
module shake_stream(
  input  wire        clk,
  input  wire        rst_n,
  input  wire        init,
  input  wire [79:0] key,
  input  wire [79:0] iv,
  input  wire        next_byte,
  output wire [7:0]  ks_byte,
  output wire        ks_valid,
  output wire        busy,

    // shared Keccak-f[1600]
    output wire          kec_req,
    output wire [1599:0] kec_din,
    input  wire          kec_busy,
    input  wire          kec_done,
    input  wire [1599:0] kec_dout
);

  localparam [2:0] S_IDLE = 3'd0,
                   S_PAD  = 3'd1,
                   S_KF   = 3'd2,
                   S_PERM = 3'd3,
                   S_SQZ  = 3'd4;

  reg [2:0]    fsm;
  reg [1599:0] state;
  reg [7:0]    byte_cnt;

  // Keccak-f[1600] shared core
  wire        kf_busy, kf_done;
  wire [1599:0] kf_state_in;
  wire [1599:0] kf_state_out;

  assign kf_state_in = state;

  assign kec_req      = (fsm == S_KF);
  assign kec_din      = kf_state_in;
  assign kf_busy      = kec_busy;
  assign kf_done      = kec_done;
  assign kf_state_out = kec_dout;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      fsm      <= S_IDLE;
      state    <= {1600{1'b0}};
      byte_cnt <= 8'd0;
    end else begin
      case (fsm)
        S_IDLE: begin
          if (init) begin
            // Load key||iv into bytes 0..19 (byte 0 = key MSB)
            state[1599:160] <= 1440'd0;
            state[159:0]    <= { iv[7:0],  iv[15:8],  iv[23:16], iv[31:24], iv[39:32],
                                 iv[47:40], iv[55:48], iv[63:56], iv[71:64], iv[79:72],
                                 key[7:0],  key[15:8],  key[23:16], key[31:24], key[39:32],
                                 key[47:40], key[55:48], key[63:56], key[71:64], key[79:72] };
            fsm <= S_PAD;
          end
        end

        S_PAD: begin
          // SHAKE domain separation (0x1F) + rate-136 padding
          state[167:160]   <= state[167:160]   | 8'h1F;
          state[1087:1080] <= state[1087:1080] | 8'h80;
          fsm <= S_KF;
        end

        S_KF: begin
          fsm <= S_PERM;
        end

        S_PERM: begin
          if (kf_done) begin
            state    <= kf_state_out;
            byte_cnt <= 8'd0;
            fsm      <= S_SQZ;
          end
        end

        S_SQZ: begin
          if (next_byte) begin
            if (byte_cnt == 8'd135)
              fsm <= S_KF;                 // re-permute for the next block
            else
              byte_cnt <= byte_cnt + 8'd1;
          end
        end

        default: fsm <= S_IDLE;
      endcase
    end
  end

  assign ks_byte  = state[byte_cnt*8 +: 8];
  assign ks_valid = (fsm == S_SQZ);
  assign busy     = (fsm != S_SQZ);

endmodule