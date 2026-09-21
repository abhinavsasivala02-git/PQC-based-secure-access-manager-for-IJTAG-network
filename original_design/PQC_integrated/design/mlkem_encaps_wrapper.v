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

// ML-KEM-768 encapsulation wrapper: m_random from the TRNG, ek served from the
// on-chip OTP. The KDF stream key is an 80-bit slice of the shared secret K;
// ciphertext bytes are serialized out via ct_tdo.
module mlkem_encaps_wrapper(
  input  wire         clk,
  input  wire         rst_n,
  input  wire         start,

  input  wire [255:0] m_seed,

  output wire         done,
  output wire         busy,

  output wire [12:0]  ek_addr,
  input  wire [7:0]   ek_rdata,
  output wire [79:0]  kdf_key,
  output wire         ct_valid,
  output wire [7:0]   ct_data,
  output wire [12:0]  ct_addr,
  output reg          ct_tdo,

  // shared Keccak-f[1600]
  output wire          h_kec_req,
  output wire [1599:0] h_kec_din,
  input  wire          h_kec_busy,
  input  wire          h_kec_done,
  input  wire [1599:0] h_kec_dout,

  output wire          g_kec_req,
  output wire [1599:0] g_kec_din,
  input  wire          g_kec_busy,
  input  wire          g_kec_done,
  input  wire [1599:0] g_kec_dout,

  output wire          prf_kec_req,
  output wire [1599:0] prf_kec_din,
  input  wire          prf_kec_busy,
  input  wire          prf_kec_done,
  input  wire [1599:0] prf_kec_dout,

  output wire          sntt_kec_req,
  output wire [1599:0] sntt_kec_din,
  input  wire          sntt_kec_busy,
  input  wire          sntt_kec_done,
  input  wire [1599:0] sntt_kec_dout
);

  wire [12:0] ek_rd_addr;

  wire        enc_done, enc_busy;
  wire        enc_ct_wen, enc_ss_valid;
  wire [12:0] enc_ct_addr;
  wire [7:0]  enc_ct_wdata;
  wire [255:0] shared_secret;

  mlkem_encaps #(
    .K(3), .ETA1(2), .ETA2(2), .DU(10), .DV(4)
  ) u_encaps (
    .clk            (clk),
    .rst_n          (rst_n),
    .h_kec_req      (h_kec_req),
    .h_kec_din      (h_kec_din),
    .h_kec_busy     (h_kec_busy),
    .h_kec_done     (h_kec_done),
    .h_kec_dout     (h_kec_dout),
    .g_kec_req      (g_kec_req),
    .g_kec_din      (g_kec_din),
    .g_kec_busy     (g_kec_busy),
    .g_kec_done     (g_kec_done),
    .g_kec_dout     (g_kec_dout),
    .prf_kec_req      (prf_kec_req),
    .prf_kec_din      (prf_kec_din),
    .prf_kec_busy     (prf_kec_busy),
    .prf_kec_done     (prf_kec_done),
    .prf_kec_dout     (prf_kec_dout),
    .sntt_kec_req      (sntt_kec_req),
    .sntt_kec_din      (sntt_kec_din),
    .sntt_kec_busy     (sntt_kec_busy),
    .sntt_kec_done     (sntt_kec_done),
    .sntt_kec_dout     (sntt_kec_dout),
    .start          (start),
    .m_random       (m_seed),
    .done           (enc_done),
    .busy           (enc_busy),
    .ek_rdata       (ek_rdata),
    .ek_raddr       (ek_rd_addr),
    .ct_wen         (enc_ct_wen),
    .ct_addr        (enc_ct_addr),
    .ct_wdata       (enc_ct_wdata),
    .ss_valid       (enc_ss_valid),
    .shared_secret  (shared_secret)
  );

  assign ek_addr   = ek_rd_addr;
  assign done      = enc_done;
  assign busy      = enc_busy;
  assign ct_valid  = enc_ct_wen;
  assign ct_data   = enc_ct_wdata;
  assign ct_addr   = enc_ct_addr;

  // 80-bit KDF stream key = slice of the shared secret K
  assign kdf_key   = shared_secret[79:0];

  // CT -> TDO serializer (byte valid pulses, LSB-first)
  reg [2:0]  bit_cnt;
  reg [7:0]  ct_hold;
  reg        byte_done;

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ct_tdo    <= 1'b0;
      bit_cnt   <= 3'd0;
      ct_hold   <= 8'd0;
      byte_done <= 1'b0;
    end else begin
      byte_done <= 1'b0;
      if (enc_ct_wen) begin
        ct_hold   <= enc_ct_wdata;
        bit_cnt   <= 3'd1;
        ct_tdo    <= enc_ct_wdata[0];
      end else if (bit_cnt != 3'd0) begin
        ct_tdo    <= ct_hold[bit_cnt];
        bit_cnt   <= bit_cnt + 3'd1;
        if (bit_cnt == 3'd7)
          byte_done <= 1'b1;
      end
    end
  end

endmodule