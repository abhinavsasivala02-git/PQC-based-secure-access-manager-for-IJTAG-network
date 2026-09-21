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

// PQC-secured IJTAG top level:
//   TAP -> AM (SIPO + FSM) -> ML-DSA-65 signature verify -> ML-KEM encaps
//   -> CLUS_SEL[1:0] DEMUX to 3 MSIB clusters. TDO is junk-masked until
//   unlock; high-priority instrument outputs are then encrypted.
module integrated_top #(
  parameter [5:0] INST_PRIORITY = 6'b000111   // TDR1-3 high, TDR4-6 low
)(
  input  wire tck,
  input  wire trst_n,
  input  wire tap_tdi,
  input  wire tap_select,
  input  wire shift_dr,
  input  wire update_dr,
  output wire tdo,

  input  wire [511:0] mu,

  input  wire         trng_seed_valid,
  input  wire [255:0] trng_seed,

  // OTP provisioning port (factory step)
  input  wire        otp_prog_we,
  input  wire [11:0] otp_prog_addr,
  input  wire [7:0]  otp_prog_data,
  input  wire        otp_prog_lock,

  // Testbench observability
  output wire         unlocked_obs,
  output wire [31:0]  key_expect_obs,
  output wire [1:0]   clus_sel_obs,
  output wire         sig_start_obs,
  output wire         kem_done_obs,
  output wire         kem_busy_obs,
  output wire         otp_programmed_obs,
  output wire         otp_key_state_obs,
  output wire [79:0]  enc_key_obs,
  output wire [79:0]  enc_iv_obs,
  output wire         enc_elig_obs,
  output wire [2:0]   inst_idx_obs,
  output wire         high_pri_obs,
  output wire [5:0]   inst_done_obs,
  output wire [5:0]   inst_priority_obs,
  output wire [7:0]   ks_byte_obs,
  output wire         ks_valid_obs,
  output wire [7:0]   enc_byte_idx_obs,
  output wire [2:0]   enc_bit_cnt_obs,
  output wire         shake_busy_obs,
  output wire         chain_tdo_obs
);

  wire rst = ~trst_n;

  // Shared Keccak-f[1600]: ML-KEM (H, G, PRF, SampleNTT), ML-DSA verification
  // and the TDO stream cipher never run at the same time, so one permutation
  // core serves all six (see keccak_shared.v).
  localparam KEC_N = 6;
  wire [KEC_N-1:0]      kec_req, kec_busy, kec_done;
  wire [KEC_N*1600-1:0] kec_din;
  wire [1599:0]         kec_dout;

  wire          dsa_kec_req,  dsa_kec_busy,  dsa_kec_done;
  wire [1599:0] dsa_kec_din;
  wire          h_kec_req,    h_kec_busy,    h_kec_done;
  wire [1599:0] h_kec_din;
  wire          g_kec_req,    g_kec_busy,    g_kec_done;
  wire [1599:0] g_kec_din;
  wire          prf_kec_req,  prf_kec_busy,  prf_kec_done;
  wire [1599:0] prf_kec_din;
  wire          sntt_kec_req, sntt_kec_busy, sntt_kec_done;
  wire [1599:0] sntt_kec_din;
  wire          str_kec_req,  str_kec_busy,  str_kec_done;
  wire [1599:0] str_kec_din;

  assign kec_req = {str_kec_req, sntt_kec_req, prf_kec_req,
                    g_kec_req,   h_kec_req,    dsa_kec_req};
  assign kec_din = {str_kec_din, sntt_kec_din, prf_kec_din,
                    g_kec_din,   h_kec_din,    dsa_kec_din};
  assign {str_kec_busy, sntt_kec_busy, prf_kec_busy,
          g_kec_busy,   h_kec_busy,    dsa_kec_busy} = kec_busy;
  assign {str_kec_done, sntt_kec_done, prf_kec_done,
          g_kec_done,   h_kec_done,    dsa_kec_done} = kec_done;

  keccak_shared #(.N(KEC_N)) u_keccak_shared (
    .clk   (tck),
    .rst_n (trst_n),
    .req   (kec_req),
    .din   (kec_din),
    .busy  (kec_busy),
    .done  (kec_done),
    .dout  (kec_dout)
  );


  // Junk TRNG (masks TDO until unlock)
  wire [31:0] j_data;
  wire        j_bit;
  j_trng u_jtrng(.clk(tck), .rst_n(trst_n),
                 .seed_valid(trng_seed_valid), .seed_in(trng_seed[31:0]),
                 .j_data(j_data), .j_bit(j_bit));

  reg [255:0] ent_word;
  reg         ent_valid;
  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      ent_valid <= 1'b0;
      ent_word  <= 256'd0;
    end else if (trng_seed_valid === 1'b1) begin
      ent_valid <= 1'b1;
      ent_word  <= trng_seed;
    end
  end

  // On-chip OTP (write-once, provisioned at the factory)
  //   Address map:
  //     0x000 - 0x49F   ML-KEM encapsulation key ek     (1184 B)
  //     0x800 - 0xF9F   ML-DSA verification key vksign  (1952 B)
  //     0xFA0 - 0xFA3   cluster key                     (4 B)
  //     0xFA4 - 0xFB3   cluster unlock instructions     (4 x 32 b)
  //     0xFB4 - 0xFC3   valid data patterns             (4 x 31 b + pad)
  localparam [11:0] OTP_EK_BASE   = 12'h000;
  localparam [11:0] OTP_PK_BASE   = 12'h800;
  localparam [11:0] OTP_KEYS_BASE = 12'hFA0;

  wire        otp_programmed, otp_key_state;
  wire [11:0] otp_bl_addr;
  wire [7:0]  otp_rd_data_a, otp_rd_data_b;
  wire        am_set_key_state;

  otp u_otp(
    .clk          (tck),
    .rst_n        (trst_n),
    .prog_we      (otp_prog_we),
    .prog_addr    (otp_prog_addr),
    .prog_data    (otp_prog_data),
    .prog_lock    (otp_prog_lock),
    .programmed   (otp_programmed),
    .rd_addr_a    (ek_addr[11:0]),
    .rd_data_a    (otp_rd_data_a),
    .rd_addr_b    (otp_bl_addr),
    .rd_data_b    (otp_rd_data_b),
    .set_key_state(am_set_key_state),
    .key_state    (otp_key_state)
  );

  // Boot-load FSM: after provisioning, latches vksign into pk_reg and the
  // cluster key / unlock instructions / data patterns into registers.
  reg [1:0]        bl_state;
  reg [10:0]       pk_cnt;
  reg [5:0]        k_cnt;
  reg [11:0]       otp_bl_addr_r;
  reg [15615:0]    pk_reg;
  reg [287:0]      load_buf;
  reg [31:0]       cluster_key;
  reg [127:0]      otp_inst;
  reg [127:0]      otp_data;
  reg              loaded;

  localparam BL_IDLE  = 2'd0,
             BL_LOADPK = 2'd1,
             BL_LOADKEY = 2'd2,
             BL_DONE   = 2'd3;

  assign otp_bl_addr = otp_bl_addr_r;

  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      bl_state     <= BL_IDLE;
      pk_cnt       <= 11'd0;
      k_cnt        <= 6'd0;
      otp_bl_addr_r<= OTP_PK_BASE;
      pk_reg       <= {15616{1'b0}};
      load_buf     <= 288'd0;
      cluster_key  <= 32'd0;
      otp_inst     <= 128'd0;
      otp_data     <= 128'd0;
      loaded       <= 1'b0;
    end else begin
      case (bl_state)
        BL_IDLE: begin
          if (otp_programmed && !loaded)
            bl_state <= BL_LOADPK;
        end

        BL_LOADPK: begin
          // otp_rd_data_b = mem[otp_bl_addr_r] (presented one cycle earlier)
          if (pk_cnt > 11'd0)
            pk_reg[15615 - (pk_cnt - 11'd1)*8 -: 8] <= otp_rd_data_b;
          if (pk_cnt == 11'd1952) begin
            bl_state      <= BL_LOADKEY;
            k_cnt         <= 6'd0;
            otp_bl_addr_r <= OTP_KEYS_BASE;
          end else begin
            otp_bl_addr_r <= OTP_PK_BASE + pk_cnt;
            pk_cnt        <= pk_cnt + 11'd1;
          end
        end

        BL_LOADKEY: begin
          if (k_cnt > 6'd0)
            load_buf[287 - (k_cnt - 6'd1)*8 -: 8] <= otp_rd_data_b;
          if (k_cnt == 6'd36) begin
            cluster_key  <= load_buf[287:256];
            otp_inst     <= load_buf[255:128];
            otp_data     <= load_buf[127:0];
            loaded       <= 1'b1;
            bl_state     <= BL_DONE;
          end else begin
            otp_bl_addr_r <= OTP_KEYS_BASE + k_cnt;
            k_cnt         <= k_cnt + 6'd1;
          end
        end

        BL_DONE: bl_state <= BL_DONE;
        default: bl_state <= BL_IDLE;
      endcase
    end
  end

  // ML-KEM encapsulation (power-up) + KDF stream key; ek read from OTP
  reg  kstart;
  reg  kstart_d;
  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      kstart   <= 1'b0;
      kstart_d <= 1'b0;
    end else begin
      kstart_d <= trst_n;
      kstart   <= trst_n & ~kstart_d;  // pulse on first cycle after reset
    end
  end

  wire        kdone, kbusy;
  wire [255:0] m_seed = ent_valid ? ent_word : {8{j_data}};
  wire [12:0] ek_addr;
  wire [79:0] kdf_key;
  wire        ct_valid;
  wire [7:0]  ct_data;
  wire [12:0] ct_addr;
  wire        ct_tdo;

  mlkem_encaps_wrapper u_kem(
    .clk      (tck),
    .rst_n    (trst_n),
    .start    (kstart),
    .m_seed   (m_seed),
    .done     (kdone),
    .busy     (kbusy),
    .ek_addr  (ek_addr),
    .ek_rdata (otp_rd_data_a),
    .kdf_key  (kdf_key),
    .ct_valid (ct_valid),
    .ct_data  (ct_data),
    .ct_addr  (ct_addr),
    .ct_tdo   (ct_tdo),
    .h_kec_req  (h_kec_req),   .h_kec_din  (h_kec_din),
    .h_kec_busy (h_kec_busy),  .h_kec_done (h_kec_done),  .h_kec_dout (kec_dout),
    .g_kec_req  (g_kec_req),   .g_kec_din  (g_kec_din),
    .g_kec_busy (g_kec_busy),  .g_kec_done (g_kec_done),  .g_kec_dout (kec_dout),
    .prf_kec_req  (prf_kec_req),   .prf_kec_din  (prf_kec_din),
    .prf_kec_busy (prf_kec_busy),  .prf_kec_done (prf_kec_done),  .prf_kec_dout (kec_dout),
    .sntt_kec_req  (sntt_kec_req),  .sntt_kec_din  (sntt_kec_din),
    .sntt_kec_busy (sntt_kec_busy), .sntt_kec_done (sntt_kec_done), .sntt_kec_dout (kec_dout)
  );

  // Access Manager: SIPO + 6-state FSM
  wire [26471:0] am_sig;
  wire           am_sval, am_sig_start, am_sig_busy;
  wire [31:0]    am_key;
  wire [1:0]     clus_sel;
  wire           clus_sel_21;
  wire           am_tdi_out;
  wire           unlocked;


  wire           vdone;
  mldsa_verify_block u_mldsa(
    .clk      (tck),
    .rst_n    (trst_n),
    .start    (am_sig_start),
    .sig      (am_sig),
    .pk       (pk_reg),
    .mu       (mu),
    .sval     (am_sval),
    .busy     (am_sig_busy),
    .done     (vdone),
    .kec_req  (dsa_kec_req),
    .kec_din  (dsa_kec_din),
    .kec_busy (dsa_kec_busy),
    .kec_done (dsa_kec_done),
    .kec_dout (kec_dout)
  );

  // Active key: cluster key on first reset (key_state=0), KDF key afterwards
  assign am_key = otp_key_state ? kdf_key[31:0] : cluster_key;

  am_pqc u_am(
    .clk       (tck),
    .reset     (rst),
    .TDI       (tap_tdi),
    .shift_en  (shift_dr & tap_select),
    .sval      (am_sval),
    .sig_done  (vdone),
    .sig_start (am_sig_start),
    .sig_busy  (am_sig_busy),
    .kdf_key   (kdf_key[31:0]),
    .otp_cluster_key (cluster_key),
    .otp_key_state   (otp_key_state),
    .otp_inst        (otp_inst),
    .otp_data        (otp_data),
    .set_key_state   (am_set_key_state),
    .mux_sel   (clus_sel),
    .mux_sel_21(clus_sel_21),
    .DVAL      (),
    .TDI_out   (am_tdi_out),
    .unlocked  (unlocked),
    .sig_out   (am_sig)
  );

  // MSIB cluster network - DEMUX on CLUS_SEL[1:0]
  wire msib1_tdo1, msib2_tdo1, msib3_tdo1;
  wire msib1_tdi2, msib2_tdi2, msib3_tdi2;
  wire sib1_tdo1, sib2_tdo1, sib3_tdo1, sib4_tdo1, sib5_tdo1, sib6_tdo1;
  wire sib1_tdi2, sib2_tdi2, sib3_tdi2, sib4_tdi2, sib5_tdi2, sib6_tdi2;
  wire tdr1_tdo, tdr2_tdo, tdr3_tdo, tdr4_tdo, tdr5_tdo, tdr6_tdo;
  wire sib1_sel, sib2_sel, sib3_sel, sib4_sel, sib5_sel, sib6_sel;
  wire msib1_sel_in, msib2_sel_in, msib3_sel_in;
  wire msib1_sel, msib2_sel, msib3_sel;

  // Cluster active only when unlocked AND clus_sel matches
  assign msib1_sel_in = tap_select & unlocked & (clus_sel == 2'b00);
  assign msib2_sel_in = tap_select & unlocked & (clus_sel == 2'b01);
  assign msib3_sel_in = tap_select & unlocked & (clus_sel == 2'b10);

  // Chain TDI: pass through the AM once unlocked
  wire chain_tdi = unlocked ? tap_tdi : 1'b0;

  MSIB u_msib1(.tck(tck),.rst(rst),.TDI1(chain_tdi),.select_i(msib1_sel_in),
               .shiften(shift_dr),.updateen(update_dr),.from_tdo2(sib2_tdo1),
               .TDO1(msib1_tdo1),.to_TDI2(msib1_tdi2),.select_o(msib1_sel));

  SiB u_sib1(.tck(tck),.rst(rst),.TDI1(msib1_tdi2),.select_i(msib1_sel),
             .shiften(shift_dr),.updateen(update_dr),.from_tdo2(tdr1_tdo),
             .TDO1(sib1_tdo1),.to_TDI2(sib1_tdi2),.select_o(sib1_sel));

  TDR #(.DATA_WIDTH(32),.RESET_VALUE(8'h00)) u_tdr1(
    .tck(tck),.trst_n(rst),.tdi(sib1_tdi2),.tdo(tdr1_tdo),
    .shift_dr(shift_dr),.update_dr(update_dr),
    .inst_data_out(),.inst_data_in(32'h00000000),.inst_valid(),
    .select_en(sib1_sel));

  SiB u_sib2(.tck(tck),.rst(rst),.TDI1(sib1_tdo1),.select_i(msib1_sel),
             .shiften(shift_dr),.updateen(update_dr),.from_tdo2(tdr2_tdo),
             .TDO1(sib2_tdo1),.to_TDI2(sib2_tdi2),.select_o(sib2_sel));

  TDR #(.DATA_WIDTH(32),.RESET_VALUE(8'h00)) u_tdr2(
    .tck(tck),.trst_n(rst),.tdi(sib2_tdi2),.tdo(tdr2_tdo),
    .shift_dr(shift_dr),.update_dr(update_dr),
    .inst_data_out(),.inst_data_in(32'h00000000),.inst_valid(),
    .select_en(sib2_sel));

  MSIB u_msib2(.tck(tck),.rst(rst),.TDI1(msib1_tdo1),.select_i(msib2_sel_in),
               .shiften(shift_dr),.updateen(update_dr),.from_tdo2(sib4_tdo1),
               .TDO1(msib2_tdo1),.to_TDI2(msib2_tdi2),.select_o(msib2_sel));

  SiB u_sib3(.tck(tck),.rst(rst),.TDI1(msib2_tdi2),.select_i(msib2_sel),
             .shiften(shift_dr),.updateen(update_dr),.from_tdo2(tdr3_tdo),
             .TDO1(sib3_tdo1),.to_TDI2(sib3_tdi2),.select_o(sib3_sel));

  TDR #(.DATA_WIDTH(32),.RESET_VALUE(8'h00)) u_tdr3(
    .tck(tck),.trst_n(rst),.tdi(sib3_tdi2),.tdo(tdr3_tdo),
    .shift_dr(shift_dr),.update_dr(update_dr),
    .inst_data_out(),.inst_data_in(32'h00000000),.inst_valid(),
    .select_en(sib3_sel));

  SiB u_sib4(.tck(tck),.rst(rst),.TDI1(sib3_tdo1),.select_i(msib2_sel),
             .shiften(shift_dr),.updateen(update_dr),.from_tdo2(tdr4_tdo),
             .TDO1(sib4_tdo1),.to_TDI2(sib4_tdi2),.select_o(sib4_sel));

  TDR #(.DATA_WIDTH(32),.RESET_VALUE(8'h00)) u_tdr4(
    .tck(tck),.trst_n(rst),.tdi(sib4_tdi2),.tdo(tdr4_tdo),
    .shift_dr(shift_dr),.update_dr(update_dr),
    .inst_data_out(),.inst_data_in(32'h00000000),.inst_valid(),
    .select_en(sib4_sel));

  MSIB u_msib3(.tck(tck),.rst(rst),.TDI1(msib2_tdo1),.select_i(msib3_sel_in),
               .shiften(shift_dr),.updateen(update_dr),.from_tdo2(sib6_tdo1),
               .TDO1(msib3_tdo1),.to_TDI2(msib3_tdi2),.select_o(msib3_sel));

  SiB u_sib5(.tck(tck),.rst(rst),.TDI1(msib3_tdi2),.select_i(msib3_sel),
             .shiften(shift_dr),.updateen(update_dr),.from_tdo2(tdr5_tdo),
             .TDO1(sib5_tdo1),.to_TDI2(sib5_tdi2),.select_o(sib5_sel));

  TDR #(.DATA_WIDTH(32),.RESET_VALUE(8'h00)) u_tdr5(
    .tck(tck),.trst_n(rst),.tdi(sib5_tdi2),.tdo(tdr5_tdo),
    .shift_dr(shift_dr),.update_dr(update_dr),
    .inst_data_out(),.inst_data_in(32'h00000000),.inst_valid(),
    .select_en(sib5_sel));

  SiB u_sib6(.tck(tck),.rst(rst),.TDI1(sib5_tdo1),.select_i(msib3_sel),
             .shiften(shift_dr),.updateen(update_dr),.from_tdo2(tdr6_tdo),
             .TDO1(sib6_tdo1),.to_TDI2(sib6_tdi2),.select_o(sib6_sel));

  TDR #(.DATA_WIDTH(32),.RESET_VALUE(8'h00)) u_tdr6(
    .tck(tck),.trst_n(rst),.tdi(sib6_tdi2),.tdo(tdr6_tdo),
    .shift_dr(shift_dr),.update_dr(update_dr),
    .inst_data_out(),.inst_data_in(32'h00000000),.inst_valid(),
    .select_en(sib6_sel));

  // Chain output
  wire chain_tdo = msib3_tdo1;

  // Per-instrument priority decoder + SHAKE-256 stream-cipher output encryption:
  // high-priority outputs are XORed with the keystream, low-priority pass raw.
  wire [5:0] inst_done =
    {6{unlocked & shift_dr}} &
    ((clus_sel == 2'b00) ? 6'b000011 :   // TDR1, TDR2
     (clus_sel == 2'b01) ? 6'b001100 :   // TDR3, TDR4
     (clus_sel == 2'b10) ? 6'b110000 :   // TDR5, TDR6
                          6'b000000);

  // Emit-phase: which of the cluster's two TDRs is at the TDO end of the chain
  reg [5:0] emit_cnt;
  always @(posedge tck or negedge trst_n) begin
    if (!trst_n)
      emit_cnt <= 6'd0;
    else if (unlocked & shift_dr)
      emit_cnt <= emit_cnt + 6'd1;
  end
  wire emit_phase = emit_cnt[5];

  wire [2:0] inst_idx;
  wire       high_pri, enc_elig;
  inst_priority_decoder u_pri(
    .clus_sel   (clus_sel),
    .emit_phase (emit_phase),
    .priority   (INST_PRIORITY),
    .inst_done  (inst_done),
    .unlocked   (unlocked),
    .shift_dr   (shift_dr),
    .inst_idx   (inst_idx),
    .high_pri   (high_pri),
    .enc_elig   (enc_elig)
  );

  // Per-session TRNG IV latched one cycle after UNLOCK
  reg        unlocked_d, unlocked_d2;
  reg [79:0] enc_iv;
  reg [79:0] iv_shift;
  wire       enc_iv_latch = unlocked_d && !unlocked_d2;
  reg        enc_iv_latch_d;

  // Free-running LFSR (not reset by trst_n) so every unlock session latches a
  // different IV => fresh keystream per session (replay resistance).
  localparam [31:0] IV_SEED = 32'h5A3C9E71;
  reg [31:0] iv_lfsr;
  initial iv_lfsr = IV_SEED;
  always @(posedge tck) begin
    if (trng_seed_valid === 1'b1)
      iv_lfsr <= (trng_seed[63:32] == 32'd0) ? IV_SEED : trng_seed[63:32];
    else
      iv_lfsr <= {iv_lfsr[30:0], iv_lfsr[31] ^ iv_lfsr[29] ^ iv_lfsr[25] ^ iv_lfsr[24]};
  end
  wire iv_trng_bit = iv_lfsr[0];

  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      unlocked_d   <= 1'b0;
      unlocked_d2  <= 1'b0;
      enc_iv       <= 80'd0;
      iv_shift     <= 80'd0;
      enc_iv_latch_d <= 1'b0;
    end else begin
      unlocked_d   <= unlocked;
      unlocked_d2  <= unlocked_d;
      iv_shift     <= {iv_shift[78:0], iv_trng_bit};
      enc_iv_latch_d <= enc_iv_latch;
      if (enc_iv_latch)
        enc_iv <= iv_shift;
    end
  end

  // SHAKE-256 stream cipher: key = 80-bit slice of K, IV = session TRNG value
  wire       ks_valid, shake_busy;
  wire [7:0] ks_byte;
  reg  [2:0] enc_bit_cnt;
  reg  [7:0] enc_byte_idx;
  // Consume keystream only when valid; counters re-zero at every unlock
  wire       enc_active = enc_elig & ks_valid;
  wire       enc_next_byte = enc_active & (enc_bit_cnt == 3'd7);

  shake_stream u_shake(
    .clk       (tck),
    .rst_n     (trst_n),
    .init      (enc_iv_latch_d),
    .key       (kdf_key),
    .iv        (enc_iv),
    .next_byte (enc_next_byte),
    .ks_byte   (ks_byte),
    .ks_valid  (ks_valid),
    .busy      (shake_busy),
    .kec_req   (str_kec_req),
    .kec_din   (str_kec_din),
    .kec_busy  (str_kec_busy),
    .kec_done  (str_kec_done),
    .kec_dout  (kec_dout)
  );

  always @(posedge tck or negedge trst_n) begin
    if (!trst_n) begin
      enc_bit_cnt  <= 3'd0;
      enc_byte_idx <= 8'd0;
    end else if (enc_iv_latch_d) begin
      enc_bit_cnt  <= 3'd0;
      enc_byte_idx <= 8'd0;
    end else if (enc_active) begin
      enc_bit_cnt  <= (enc_bit_cnt == 3'd7) ? 3'd0 : enc_bit_cnt + 3'd1;
      enc_byte_idx <= (enc_bit_cnt == 3'd7) ? enc_byte_idx + 8'd1 : enc_byte_idx;
    end
  end

  wire enc_bit = enc_active ? ks_byte[enc_bit_cnt] : 1'b0;

  assign tdo = (ct_valid) ? ct_tdo      :   // CT shifted out via TDO
               (unlocked) ? (chain_tdo ^ enc_bit) : j_bit;

  // Testbench observability
  assign unlocked_obs        = unlocked;
  assign key_expect_obs      = am_key;
  assign clus_sel_obs        = clus_sel;
  assign sig_start_obs       = am_sig_start;
  assign kem_done_obs        = kdone;
  assign kem_busy_obs        = kbusy;
  assign otp_programmed_obs  = otp_programmed;
  assign otp_key_state_obs   = otp_key_state;
  assign enc_key_obs         = kdf_key;
  assign enc_iv_obs          = enc_iv;
  assign enc_elig_obs        = enc_elig;
  assign inst_idx_obs        = inst_idx;
  assign high_pri_obs        = high_pri;
  assign inst_done_obs       = inst_done;
  assign inst_priority_obs   = INST_PRIORITY;
  assign ks_byte_obs         = ks_byte;
  assign ks_valid_obs        = ks_valid;
  assign enc_byte_idx_obs    = enc_byte_idx;
  assign enc_bit_cnt_obs     = enc_bit_cnt;
  assign shake_busy_obs      = shake_busy;
  assign chain_tdo_obs       = chain_tdo;

endmodule