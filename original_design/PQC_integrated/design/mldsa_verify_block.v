`timescale 1ns / 1ps
`include "mldsa_params.vh"

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

// ML-DSA-65 signature verification wrapper around the KAT-verified datapath
// (verify_ctrl + ntt_core + shake_unified). Asserts SVAL when verification
// succeeds; SVAL gates the unlock-key comparison in the AM.
module mldsa_verify_block(
  input  wire           clk,
  input  wire           rst_n,

  input  wire           start,
  input  wire [26471:0] sig,
  input  wire [15615:0] pk,
  input  wire [511:0]   mu,

  output reg            sval,
  output reg            busy,
  output reg            done,

    // shared Keccak-f[1600]
    output wire          kec_req,
    output wire [1599:0] kec_din,
    input  wire          kec_busy,
    input  wire          kec_done,
    input  wire [1599:0] kec_dout
);

  // Byte-addressable read ports (byte 0 = MSB of the input vectors)
  wire [11:0] vc_sig_rd_addr;
  wire [10:0] vc_pk_rd_addr;
  wire [7:0]  vc_sig_rd_data = sig[26471 - vc_sig_rd_addr*8 -: 8];
  wire [7:0]  vc_pk_rd_data  = pk[15615 - vc_pk_rd_addr*8 -: 8];

  // KAT convention: rho/mu are fed to SHAKE lanes little-endian; our ports are
  // byte-0-at-MSB, so the bytes are reversed before verify_ctrl.
  wire [255:0] pk_rho;
  wire [511:0] mu_le;
  genvar g;
  generate
    for (g = 0; g < 32; g = g + 1)
      assign pk_rho[g*8 +: 8] = pk[15615 - g*8 -: 8];
    for (g = 0; g < 64; g = g + 1)
      assign mu_le[g*8 +: 8] = mu[511 - g*8 -: 8];
  endgenerate

  // verify_ctrl datapath wiring
  wire        ntt_start, ntt_intt_mode, ntt_done, ntt_busy;
  wire        ntt_ext_we;
  wire [7:0]  ntt_ext_addr;
  wire [`MLDSA_QBITS-1:0] ntt_ext_din, ntt_ext_dout;

  // Channel A = SHAKE-256, Channel B = SHAKE-128 (ExpandA)
  wire        a_init, a_wr_en, a_pad, a_perm, a_rdy, a_busy;
  wire [4:0]  a_wr_lane, a_rd_lane;
  wire [63:0] a_wr_data, a_rd_data;
  wire        b_init, b_wr_en, b_pad, b_perm, b_rdy, b_busy;
  wire [4:0]  b_wr_lane, b_rd_lane;
  wire [63:0] b_wr_data, b_rd_data;

  reg         vc_start;
  wire        vc_done, vc_busy, vc_valid;

  verify_ctrl u_verify (
    .clk                  (clk),
    .rst_n                (rst_n),
    .start                (vc_start),
    .done                 (vc_done),
    .busy                 (vc_busy),
    .valid                (vc_valid),
    .pk_rho               (pk_rho),
    .mu                   (mu_le),
    .mu_valid             (1'b1),
    .sig_rd_addr          (vc_sig_rd_addr),
    .sig_rd_data          (vc_sig_rd_data),
    .pk_rd_addr           (vc_pk_rd_addr),
    .pk_rd_data           (vc_pk_rd_data),
    .ntt_start            (ntt_start),
    .ntt_intt_mode        (ntt_intt_mode),
    .ntt_done             (ntt_done),
    .ntt_busy             (ntt_busy),
    .shake_init           (a_init),
    .shake_wr_en          (a_wr_en),
    .shake_wr_lane_idx    (a_wr_lane),
    .shake_wr_lane_data   (a_wr_data),
    .shake_pad_and_permute(a_pad),
    .shake_permute        (a_perm),
    .shake_rd_lane_idx    (a_rd_lane),
    .shake_rd_lane_data   (a_rd_data),
    .shake_rdy            (a_rdy),
    .shake_busy           (a_busy),
    .s128_init            (b_init),
    .s128_wr_en           (b_wr_en),
    .s128_wr_lane_idx     (b_wr_lane),
    .s128_wr_lane_data    (b_wr_data),
    .s128_pad_and_permute (b_pad),
    .s128_permute         (b_perm),
    .s128_rd_lane_idx     (b_rd_lane),
    .s128_rd_lane_data    (b_rd_data),
    .s128_rdy             (b_rdy),
    .s128_busy            (b_busy),
    .ntt_ext_we           (ntt_ext_we),
    .ntt_ext_addr         (ntt_ext_addr),
    .ntt_ext_din          (ntt_ext_din),
    .ntt_ext_dout         (ntt_ext_dout),
    .c_tilde_orig         (sig[255:0]),
    .c_tilde_prime        (256'd0)
  );

  ntt_core u_ntt (
    .clk        (clk),
    .rst_n      (rst_n),
    .start      (ntt_start),
    .intt_mode  (ntt_intt_mode),
    .busy       (ntt_busy),
    .done       (ntt_done),
    .ext_we     (ntt_ext_we),
    .ext_addr   (ntt_ext_addr),
    .ext_din    (ntt_ext_din),
    .ext_dout   (ntt_ext_dout)
  );

  shake_unified u_shake (
    .clk               (clk),
    .rst_n             (rst_n),
    .kec_req      (kec_req),
    .kec_din      (kec_din),
    .kec_busy     (kec_busy),
    .kec_done     (kec_done),
    .kec_dout     (kec_dout),
    .a_init            (a_init),
    .a_wr_en           (a_wr_en),
    .a_wr_lane_idx     (a_wr_lane),
    .a_wr_lane_data    (a_wr_data),
    .a_pad_and_permute (a_pad),
    .a_permute         (a_perm),
    .a_rd_lane_idx     (a_rd_lane),
    .a_rd_lane_data    (a_rd_data),
    .a_busy            (a_busy),
    .a_rdy             (a_rdy),
    .b_init            (b_init),
    .b_wr_en           (b_wr_en),
    .b_wr_lane_idx     (b_wr_lane),
    .b_wr_lane_data    (b_wr_data),
    .b_pad_and_permute (b_pad),
    .b_permute         (b_perm),
    .b_rd_lane_idx     (b_rd_lane),
    .b_rd_lane_data    (b_rd_data),
    .b_busy            (b_busy),
    .b_rdy             (b_rdy)
  );

  // Launch FSM: single vc_start pulse on rising edge of start
  localparam S_IDLE = 1'b0, S_RUN = 1'b1;
  reg       state;
  reg       start_d;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state   <= S_IDLE;
      vc_start<= 1'b0;
      start_d <= 1'b0;
      sval    <= 1'b0;
      busy    <= 1'b0;
      done    <= 1'b0;
    end else begin
      start_d <= start;
      vc_start <= 1'b0;
      done     <= 1'b0;

      case (state)
        S_IDLE: begin
          busy <= 1'b0;
          if (start && !start_d) begin
            busy     <= 1'b1;
            vc_start <= 1'b1;
            state    <= S_RUN;
          end
        end

        S_RUN: begin
          if (vc_done) begin
            sval  <= vc_valid;
            busy  <= 1'b0;
            done  <= 1'b1;
            state <= S_IDLE;
          end
        end

        default: state <= S_IDLE;
      endcase
    end
  end

endmodule