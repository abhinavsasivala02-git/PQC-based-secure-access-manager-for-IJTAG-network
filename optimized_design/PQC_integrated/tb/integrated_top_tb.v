`timescale 1ns / 1ps
// =============================================================================
// integrated_top_tb.v - Comprehensive testbench for the PQC-secured IJTAG top
//
// Covering, per the paper:
//   [Stage 1] Factory OTP provisioning (ek, vksign, cluster key, inst, data)
//             + boot-load + ML-KEM encapsulation (CT shifted out via TDO)
//   [Stage 2] Positive unlock, cluster 0 (key_state=0 phase, cluster key)
//   [Stage 3] SHAKE-256 stream-cipher output encryption of high-priority
//             instruments (cluster 0: both TDRs high-priority)
//   [Stage 4] Cluster 1 mixed-priority: per-instrument DONE priority decoder
//             switches encryption on/off within one session
//   [Stage 5] Cluster 2 all-low-priority: raw (unencrypted) instrument output
//   [Stage 6] Cluster 3 edge (CLUS_SEL=11, no active MSIB)
//   [Stage 7] Per-session TRNG IV -> keystreams never reused (replay resistance)
//   [Stage 8] Negative tests: wrong signature / key / instruction / data,
//             TDO junk-masked while locked, key_state persists across reset
//
// The keystream is verified against an INDEPENDENT SHAKE-256 reference model
// (software Keccak-f[1600]) inside this testbench.
// =============================================================================

module integrated_top_tb;

  reg  tck = 1'b0;
  reg  trst_n = 1'b0;
  reg  tap_tdi = 1'b0;
  reg  tap_select = 1'b0;
  reg  shift_dr = 1'b0;
  reg  update_dr = 1'b0;

  reg [511:0]   mu;

  reg           trng_seed_valid = 1'b0;
  reg [255:0]   trng_seed       = 256'd0;

  // NIST ML-DSA-65 KAT vectors (vector #0)
  reg [7:0]  sig_mem [0:3308];
  reg [7:0]  pk_mem  [0:1951];
  reg [7:0]  mu_mem  [0:63];
  // NIST ML-KEM-768 KAT encapsulation key ek (kat_pk.mem, 1184 B)
  reg [7:0]  ek_mem  [0:1183];
  integer    kk;

  initial begin
`ifdef XSIM
    $readmemh("sig_0.mem", sig_mem);
    $readmemh("pk_0.mem",  pk_mem);
    $readmemh("mu_0.mem",  mu_mem);
    $readmemh("kat_pk.mem", ek_mem);
`else
    $readmemh("../tb/sig_0.mem", sig_mem);
    $readmemh("../tb/pk_0.mem",  pk_mem);
    $readmemh("../tb/mu_0.mem",  mu_mem);
    $readmemh("../tb/kat_pk.mem", ek_mem);
`endif
    for (kk = 0; kk < 64; kk = kk + 1)
      mu[511 - kk*8 -: 8] = mu_mem[kk];
  end

  wire tdo;
  wire unlocked_obs;
  wire [31:0] key_expect_obs;
  wire [1:0]  clus_sel_obs;
  wire        sig_start_obs;
  wire        kem_done_obs;
  wire        kem_busy_obs;
  wire        otp_programmed_obs;
  wire        otp_key_state_obs;
  wire [79:0] enc_key_obs;
  wire [79:0] enc_iv_obs;
  wire        enc_elig_obs;
  wire [2:0]  inst_idx_obs;
  wire        high_pri_obs;
  wire [5:0]  inst_done_obs;
  wire [5:0]  inst_priority_obs;
  wire [7:0]  ks_byte_obs;
  wire        ks_valid_obs;
  wire [7:0]  enc_byte_idx_obs;
  wire [2:0]  enc_bit_cnt_obs;
  wire        shake_busy_obs;
  wire        chain_tdo_obs;

  // OTP provisioning port (factory step)
  reg         otp_prog_we;
  reg  [11:0] otp_prog_addr;
  reg  [7:0]  otp_prog_data;
  reg         otp_prog_lock;

  integrated_top dut(
    .tck            (tck),
    .trst_n         (trst_n),
    .tap_tdi        (tap_tdi),
    .tap_select     (tap_select),
    .shift_dr       (shift_dr),
    .update_dr      (update_dr),
    .tdo            (tdo),
    .mu             (mu),
    .trng_seed_valid(trng_seed_valid),
    .trng_seed      (trng_seed),
    .otp_prog_we    (otp_prog_we),
    .otp_prog_addr  (otp_prog_addr),
    .otp_prog_data  (otp_prog_data),
    .otp_prog_lock  (otp_prog_lock),
    .unlocked_obs   (unlocked_obs),
    .key_expect_obs (key_expect_obs),
    .clus_sel_obs   (clus_sel_obs),
    .sig_start_obs  (sig_start_obs),
    .kem_done_obs   (kem_done_obs),
    .kem_busy_obs   (kem_busy_obs),
    .otp_programmed_obs (otp_programmed_obs),
    .otp_key_state_obs  (otp_key_state_obs),
    .enc_key_obs    (enc_key_obs),
    .enc_iv_obs     (enc_iv_obs),
    .enc_elig_obs   (enc_elig_obs),
    .inst_idx_obs   (inst_idx_obs),
    .high_pri_obs   (high_pri_obs),
    .inst_done_obs  (inst_done_obs),
    .inst_priority_obs (inst_priority_obs),
    .ks_byte_obs    (ks_byte_obs),
    .ks_valid_obs   (ks_valid_obs),
    .enc_byte_idx_obs (enc_byte_idx_obs),
    .enc_bit_cnt_obs  (enc_bit_cnt_obs),
    .shake_busy_obs   (shake_busy_obs),
    .chain_tdo_obs    (chain_tdo_obs)
  );

  // 100 MHz clock
  always #5 tck = ~tck;

  // ===========================================================================
  // INDEPENDENT SHAKE-256 REFERENCE MODEL (software Keccak-f[1600])
  // ===========================================================================
  reg [63:0] A [0:24];
  reg [63:0] B [0:24];
  reg [63:0] col_p [0:4];
  reg [63:0] col_d [0:4];
  reg [63:0] RC [0:23];
  reg [5:0]  rho_off [0:4][0:4];
  reg [7:0]  ref_ks [0:135];
  reg [7:0]  ref_m   [0:63];
  reg [7:0]  ref_out [0:135];
  integer    err_cnt;

  function [63:0] rotl64;
    input [63:0] v;
    input [5:0]  n;
    begin
      rotl64 = (n == 6'd0) ? v : ((v << n) | (v >> (7'd64 - {1'b0, n})));
    end
  endfunction

  task keccak_f_ref;
    integer rnd, x, y;
    begin
      for (rnd = 0; rnd < 24; rnd = rnd + 1) begin
        // theta
        for (x = 0; x < 5; x = x + 1)
          col_p[x] = A[x] ^ A[x+5] ^ A[x+10] ^ A[x+15] ^ A[x+20];
        for (x = 0; x < 5; x = x + 1)
          col_d[x] = col_p[(x+4)%5] ^ rotl64(col_p[(x+1)%5], 6'd1);
        for (x = 0; x < 25; x = x + 1)
          A[x] = A[x] ^ col_d[x%5];
        // rho + pi
        for (y = 0; y < 5; y = y + 1)
          for (x = 0; x < 5; x = x + 1)
            B[y + 5*((2*x + 3*y) % 5)] = rotl64(A[x + 5*y], rho_off[x][y]);
        // chi
        for (y = 0; y < 5; y = y + 1)
          for (x = 0; x < 5; x = x + 1)
            A[x + 5*y] = B[x + 5*y] ^ ((~B[((x+1)%5) + 5*y]) & B[((x+2)%5) + 5*y]);
        // iota
        A[0] = A[0] ^ RC[rnd];
      end
    end
  endtask

  task fill_consts;
    begin
      RC[0]  = 64'h0000000000000001; RC[1]  = 64'h0000000000008082;
      RC[2]  = 64'h800000000000808A; RC[3]  = 64'h8000000080008000;
      RC[4]  = 64'h000000000000808B; RC[5]  = 64'h0000000080000001;
      RC[6]  = 64'h8000000080008081; RC[7]  = 64'h8000000000008009;
      RC[8]  = 64'h000000000000008A; RC[9]  = 64'h0000000000000088;
      RC[10] = 64'h0000000080008009; RC[11] = 64'h000000008000000A;
      RC[12] = 64'h000000008000808B; RC[13] = 64'h800000000000008B;
      RC[14] = 64'h8000000000008089; RC[15] = 64'h8000000000008003;
      RC[16] = 64'h8000000000008002; RC[17] = 64'h8000000000000080;
      RC[18] = 64'h000000000000800A; RC[19] = 64'h800000008000000A;
      RC[20] = 64'h8000000080008081; RC[21] = 64'h8000000000008080;
      RC[22] = 64'h0000000080000001; RC[23] = 64'h8000000080008008;
      rho_off[0][0]=0;  rho_off[1][0]=1;  rho_off[2][0]=62; rho_off[3][0]=28; rho_off[4][0]=27;
      rho_off[0][1]=36; rho_off[1][1]=44; rho_off[2][1]=6;  rho_off[3][1]=55; rho_off[4][1]=20;
      rho_off[0][2]=3;  rho_off[1][2]=10; rho_off[2][2]=43; rho_off[3][2]=25; rho_off[4][2]=39;
      rho_off[0][3]=41; rho_off[1][3]=45; rho_off[2][3]=15; rho_off[3][3]=21; rho_off[4][3]=8;
      rho_off[0][4]=18; rho_off[1][4]=2;  rho_off[2][4]=61; rho_off[3][4]=56; rho_off[4][4]=14;
    end
  endtask

  // SHAKE-256(ref_m[0..mlen-1]) squeeze `outlen` bytes into ref_out
  // (single block, mlen <= 64)
  task shake256_squeeze;
    input integer mlen;
    input integer outlen;
    integer i;
    begin
      for (i = 0; i < 25; i = i + 1) A[i] = 64'd0;
      for (i = 0; i < mlen; i = i + 1)
        A[i/8][ (i%8)*8 +: 8 ] = ref_m[i];
      A[mlen/8][ (mlen%8)*8 +: 8 ] = A[mlen/8][ (mlen%8)*8 +: 8 ] | 8'h1F;
      A[135/8][ (135%8)*8 +: 8 ]    = A[135/8][ (135%8)*8 +: 8 ]    | 8'h80;
      keccak_f_ref();
      for (i = 0; i < outlen; i = i + 1)
        ref_out[i] = A[i/8][ (i%8)*8 +: 8 ];
    end
  endtask

  // reference keystream for the on-chip SHAKE-256(key||iv) stream cipher
  task compute_ref_ks;
    input [79:0] key;
    input [79:0] iv;
    integer i;
    begin
      for (i = 0; i < 10; i = i + 1) ref_m[i]    = key[79 - 8*i -: 8];
      for (i = 0; i < 10; i = i + 1) ref_m[10+i] = iv[79 - 8*i -: 8];
      shake256_squeeze(20, 136);
      for (i = 0; i < 136; i = i + 1) ref_ks[i] = ref_out[i];
    end
  endtask

  // Self-check of the reference model against known vectors
  task ref_self_check;
    integer i, ok;
    begin
      // Keccak-f[1600] on the all-zero state
      for (i = 0; i < 25; i = i + 1) A[i] = 64'd0;
      keccak_f_ref();
      ok = 1;
      if (A[0] !== 64'hF1258F7940E1DDE7) ok = 0;
      if (A[1] !== 64'h84D5CCF933C0478A) ok = 0;
      if (A[2] !== 64'hD598261EA65AA9EE) ok = 0;
      if (A[3] !== 64'hBD1547306F80494D) ok = 0;
      if (A[4] !== 64'h8B284E056253D057) ok = 0;
      if (ok)
        $display("TB: PASS - reference Keccak-f[1600](0) matches known vector");
      else begin
        $display("TB: ERROR - reference Keccak-f[1600](0) MISMATCH (A[0]=%016h)", A[0]);
        err_cnt = err_cnt + 1;
      end

      // SHAKE-256("abc", 64 bytes) - NIST vector
      ref_m[0] = 8'h61; ref_m[1] = 8'h62; ref_m[2] = 8'h63;
      shake256_squeeze(3, 64);
      ok = 1;
      begin : abc_chk
        integer j;
        reg [7:0] exp [0:63];
        exp[0]=8'h48; exp[1]=8'h33; exp[2]=8'h66; exp[3]=8'h60; exp[4]=8'h13; exp[5]=8'h60; exp[6]=8'ha8; exp[7]=8'h77;
        exp[8]=8'h1c; exp[9]=8'h68; exp[10]=8'h63; exp[11]=8'h08; exp[12]=8'h0c; exp[13]=8'hc4; exp[14]=8'h11; exp[15]=8'h4d;
        exp[16]=8'h8d; exp[17]=8'hb4; exp[18]=8'h45; exp[19]=8'h30; exp[20]=8'hf8; exp[21]=8'hf1; exp[22]=8'he1; exp[23]=8'hee;
        exp[24]=8'h4f; exp[25]=8'h94; exp[26]=8'hea; exp[27]=8'h37; exp[28]=8'he7; exp[29]=8'h8b; exp[30]=8'h57; exp[31]=8'h39;
        exp[32]=8'hd5; exp[33]=8'ha1; exp[34]=8'h5b; exp[35]=8'hef; exp[36]=8'h18; exp[37]=8'h6a; exp[38]=8'h53; exp[39]=8'h86;
        exp[40]=8'hc7; exp[41]=8'h57; exp[42]=8'h44; exp[43]=8'hc0; exp[44]=8'h52; exp[45]=8'h7e; exp[46]=8'h1f; exp[47]=8'haa;
        exp[48]=8'h9f; exp[49]=8'h87; exp[50]=8'h26; exp[51]=8'he4; exp[52]=8'h62; exp[53]=8'ha1; exp[54]=8'h2a; exp[55]=8'h4f;
        exp[56]=8'heb; exp[57]=8'h06; exp[58]=8'hbd; exp[59]=8'h88; exp[60]=8'h01; exp[61]=8'he7; exp[62]=8'h51; exp[63]=8'he4;
        for (j = 0; j < 64; j = j + 1)
          if (ref_out[j] !== exp[j]) ok = 0;
      end
      if (ok)
        $display("TB: PASS - reference SHAKE-256(\"abc\") matches NIST vector");
      else begin
        $display("TB: ERROR - reference SHAKE-256(\"abc\") MISMATCH (out[0]=%02h out[1]=%02h)", ref_out[0], ref_out[1]);
        err_cnt = err_cnt + 1;
      end
    end
  endtask

  // ===========================================================================
  // STIMULUS HELPERS
  // ===========================================================================
  // Shift in a 26,567-bit unlock frame {sig, key, inst, data}, MSB-first.
  task shift_frame(input [26566:0] frame);
    integer i;
    begin
      @(negedge tck);
      tap_select = 1'b1;
      shift_dr   = 1'b1;
      for (i = 26566; i >= 0; i = i - 1) begin
        tap_tdi = frame[i];
        @(negedge tck);
      end
      shift_dr   = 1'b0;
      tap_select = 1'b0;
      tap_tdi    = 1'b0;
    end
  endtask

  // Build the 26,472-bit signature vector from sig_mem (byte 0 = MSB)
  function [26471:0] make_sig;
    input integer d;
    integer j;
    begin
      make_sig = {26472{1'b0}};
      for (j = 0; j < 3309; j = j + 1)
        make_sig[26471 - j*8 -: 8] = sig_mem[j];
    end
  endfunction

  // OTP provisioned contents (factory step)
  localparam [31:0] CLUSTER_KEY = 32'hCAFEBABE;   // first-reset unlock key
  reg [31:0] OTP_INST [0:3];                      // cluster unlock instructions
  reg [31:0] OTP_DATA [0:3];                      // valid data patterns

  // Factory provisioning: ek, vksign, cluster key, unlock instructions, data.
  task provision_otp;
    integer k;
    integer j;
    begin
      otp_prog_we   = 1'b0;
      otp_prog_lock = 1'b0;
      otp_prog_addr = 12'h000;
      otp_prog_data = 8'h00;

      for (k = 0; k < 1184; k = k + 1) begin
        @(posedge tck);
        otp_prog_we   <= 1'b1;
        otp_prog_addr <= 12'h000 + k;
        otp_prog_data <= ek_mem[k];
      end

      for (k = 0; k < 1952; k = k + 1) begin
        @(posedge tck);
        otp_prog_we   <= 1'b1;
        otp_prog_addr <= 12'h800 + k;
        otp_prog_data <= pk_mem[k];
      end

      for (j = 0; j < 4; j = j + 1) begin
        @(posedge tck);
        otp_prog_we   <= 1'b1;
        otp_prog_addr <= 12'hFA0 + j;
        otp_prog_data <= CLUSTER_KEY[31 - j*8 -: 8];
      end

      for (j = 0; j < 16; j = j + 1) begin
        @(posedge tck);
        otp_prog_we   <= 1'b1;
        otp_prog_addr <= 12'hFA4 + j;
        otp_prog_data <= OTP_INST[j/4][31 - (j%4)*8 -: 8];
      end

      for (j = 0; j < 16; j = j + 1) begin
        @(posedge tck);
        otp_prog_we   <= 1'b1;
        otp_prog_addr <= 12'hFB4 + j;
        otp_prog_data <= OTP_DATA[j/4][31 - (j%4)*8 -: 8];
      end

      @(posedge tck);
      otp_prog_we   <= 1'b0;
      otp_prog_lock <= 1'b1;
      @(posedge tck);
      otp_prog_lock <= 1'b0;
      repeat (2) @(posedge tck);
    end
  endtask

  // Reset the chip (OTP contents / key_state survive; everything else clears)
  task chip_reset;
    begin
      tap_select = 1'b0;
      shift_dr   = 1'b0;
      update_dr  = 1'b0;
      tap_tdi    = 1'b0;
      trst_n     = 1'b0;
      repeat (8) @(posedge tck);
      trst_n     = 1'b1;
    end
  endtask

  // Reset + release + wait for re-boot and ML-KEM encapsulation
  task session_reset;
    begin
      chip_reset();
      repeat (4) @(posedge tck);
      wait (dut.loaded === 1'b1);
      wait (kem_done_obs === 1'b1);
    end
  endtask

  // Build the frame, shift it in, and wait for the AM to reach UNLOCK
  task do_unlock(input [26471:0] sig_in, input [31:0] key_in,
                 input [31:0] inst_in, input [30:0] data_in);
    reg [26566:0] fr;
    begin
      fr = {sig_in, key_in, inst_in, data_in};
      shift_frame(fr);
      wait (unlocked_obs === 1'b1);
    end
  endtask

  // Build + shift an unlock frame
  task fr_build_and_shift(input [26471:0] sig_in, input [31:0] key_in,
                          input [31:0] inst_in, input [30:0] data_in);
    reg [26566:0] fr;
    begin
      fr = {sig_in, key_in, inst_in, data_in};
      shift_frame(fr);
    end
  endtask

  // Shift a short burst while sampling the TDO/encryption metadata; this is
  // the instrument-output access session (pattern shifts through the chain).
  task enc_session;
    input integer mode;     // 0 = all high-priority (expect all encrypted)
                            // 1 = mixed (expect switching)
                            // 2 = all low-priority (expect raw)
    input integer nbits;    // pattern bits to shift (<= 64)
    input [63:0] pattern;   // shift-in pattern, bit nbits-1 first (MSB-first)
    reg [7:0]  tdo_s   [0:127];
    reg [7:0]  chain_s [0:127];
    integer    i, nt, idx_prev;
    integer    mux_bad, ks_bad, elig_bad, togg_hi, togg_lo, enc_diff, dec_bad, chain_ok;
    reg [7:0]  sess_ks [0:135];
    begin
      // reference keystream for this session's key/iv
      compute_ref_ks(enc_key_obs, enc_iv_obs);
      for (i = 0; i < 136; i = i + 1) sess_ks[i] = ref_ks[i];

      mux_bad = 0; ks_bad = 0; elig_bad = 0; togg_hi = 0; togg_lo = 0;
      enc_diff = 0; dec_bad = 0; idx_prev = -1; nt = 0;

      tap_select = 1'b1;
      shift_dr   = 1'b1;
      // the SHAKE-256 init (~28 cycles) runs right after unlock; only sample
      // once the keystream is valid so every sampled bit is encrypted
      wait (ks_valid_obs === 1'b1);
      for (i = nbits-1; i >= 0; i = i - 1) begin
        tap_tdi = pattern[i];
        @(negedge tck);
        @(posedge tck);
        #1;
        tdo_s[nt]   = tdo;
        chain_s[nt] = chain_tdo_obs;
        if (enc_elig_obs) begin
          togg_hi = 1;
          if (tdo !== (chain_tdo_obs ^ ks_byte_obs[enc_bit_cnt_obs])) mux_bad = 1;
          if (tdo != chain_tdo_obs) enc_diff = 1;
          if (enc_byte_idx_obs != idx_prev) begin
            if (ks_byte_obs !== sess_ks[enc_byte_idx_obs]) ks_bad = 1;
            idx_prev = enc_byte_idx_obs;
          end
          if (high_pri_obs !== 1'b1) dec_bad = 1;
          if (mode == 2) elig_bad = 1;
        end else begin
          togg_lo = 1;
          if (tdo !== chain_tdo_obs) mux_bad = 1;
          if (mode == 0) elig_bad = 1;
        end
        // priority decoder: active instrument priority must match the config
        if (high_pri_obs !== dut.INST_PRIORITY[inst_idx_obs]) dec_bad = 1;
        if (inst_done_obs[inst_idx_obs] !== 1'b1) dec_bad = 1;
        nt = nt + 1;
      end
      // drain a few extra cycles so the full pattern appears at chain_tdo
      tap_tdi = 1'b0;
      repeat (8) begin
        @(negedge tck);
        @(posedge tck);
        #1;
        chain_s[nt] = chain_tdo_obs;
        nt = nt + 1;
      end
      shift_dr   = 1'b0;
      tap_select = 1'b0;
      tap_tdi    = 1'b0;

      // ---- checks ----
      if (mode == 0) begin
        if (!elig_bad) $display("TB: PASS - high-priority cluster output encrypted for every sampled bit");
        else begin $display("TB: ERROR - high-priority cluster had an unencrypted sample"); err_cnt = err_cnt + 1; end
        if (enc_diff) $display("TB: PASS - encrypted TDO differs from raw chain output (cipher active)");
        else begin $display("TB: ERROR - encrypted TDO identical to raw chain output"); err_cnt = err_cnt + 1; end
      end else if (mode == 2) begin
        if (!elig_bad) $display("TB: PASS - low-priority cluster output stays raw (no encryption)");
        else begin $display("TB: ERROR - low-priority cluster output was encrypted"); err_cnt = err_cnt + 1; end
      end else begin
        if (togg_lo && togg_hi) $display("TB: PASS - mixed cluster switches encryption by per-instrument priority");
        else begin $display("TB: ERROR - mixed cluster did not switch (lo=%0d hi=%0d)", togg_lo, togg_hi); err_cnt = err_cnt + 1; end
      end

      if (!mux_bad) $display("TB: PASS - TDO mux equation holds (tdo == chain ^ ks_bit when eligible)");
      else begin $display("TB: ERROR - TDO mux equation violated"); err_cnt = err_cnt + 1; end

      if (!ks_bad) $display("TB: PASS - keystream bytes match independent SHAKE-256(key||iv) reference");
      else begin $display("TB: ERROR - keystream bytes do NOT match SHAKE-256 reference"); err_cnt = err_cnt + 1; end

      if (!dec_bad) $display("TB: PASS - priority decoder maps inst_idx -> priority & DONE correctly");
      else begin $display("TB: ERROR - priority decoder mismatch"); err_cnt = err_cnt + 1; end

      // raw chain carries the shifted-in pattern (pipeline-delayed)
      begin : chk_chain
        integer c, j, ok;
        chain_ok = 0;
        for (c = 0; c + nbits - 1 < nt; c = c + 1) begin
          ok = 1;
          for (j = 0; j < nbits; j = j + 1)
            if (chain_s[c+j] !== pattern[nbits-1-j]) ok = 0;
          if (ok) chain_ok = 1;
        end
        if (chain_ok)
          $display("TB: PASS - raw chain carries the shifted pattern (pipeline delay present)");
        else begin
          $display("TB: ERROR - raw chain did NOT carry the shifted pattern (chain broken?)");
          err_cnt = err_cnt + 1;
        end
      end
    end
  endtask

  // Wait for a negative (rejected) frame to settle and check it was rejected
  task neg_check(input [15:0] tag);
    begin
      while (dut.u_mldsa.done !== 1'b1) @(posedge tck);
      repeat (4) @(posedge tck);
      if (unlocked_obs !== 1'b0) begin
        $display("TB: [neg %h] ERROR - unlocked=1 (should be rejected)", tag);
        err_cnt = err_cnt + 1;
      end else
        $display("TB: [neg %h] PASS - rejected (unlocked=0)", tag);
      if (dut.u_am.state_reg !== 3'd0) begin
        $display("TB: [neg %h] ERROR - AM not back in LOCK (state=%0d)", tag, dut.u_am.state_reg);
        err_cnt = err_cnt + 1;
      end else
        $display("TB: [neg %h] PASS - AM back in LOCK", tag);
      begin : mask_chk
        integer n;
        reg [31:0] tdo_sample, jbit_sample;
        tdo_sample  = 32'd0;
        jbit_sample = 32'd0;
        for (n = 0; n < 32; n = n + 1) begin
          @(posedge tck);
          #1;
          tdo_sample[n]  = tdo;
          jbit_sample[n] = dut.u_jtrng.j_bit;
        end
        if (tdo_sample === jbit_sample)
          $display("TB: [neg %h] PASS - TDO junk-masked while locked", tag);
        else begin
          $display("TB: [neg %h] ERROR - TDO not junk-masked (tdo=%08h j=%08h)", tag, tdo_sample, jbit_sample);
          err_cnt = err_cnt + 1;
        end
      end
    end
  endtask

  // ===========================================================================
  // TEST SEQUENCE
  // ===========================================================================
  reg [31:0] used_key;
  reg [26471:0] sig;
  reg [31:0] key, inst;
  reg [30:0] data;
  reg [79:0] iv_s0, iv_s1;
  reg [7:0]  ref0_0, ref0_1;      // first session keystream bytes (for replay check)
  integer i;

  // CT monitor: capture ciphertext bytes shifted out via TDO at power-up
  integer ct_cnt = 0;
  reg     ct_tdo_bad = 1'b0;
  always @(posedge tck) begin
    if (dut.ct_valid) begin
      ct_cnt <= ct_cnt + 1;
      if (tdo !== dut.ct_tdo) ct_tdo_bad <= 1'b1;
    end
  end

  initial begin
    err_cnt = 0;
    fill_consts();
    ref_self_check();

    // OTP unlock patterns to provision
    OTP_INST[0] = 32'hef67ab01; OTP_INST[1] = 32'hef67ab02;
    OTP_INST[2] = 32'hef67ab03; OTP_INST[3] = 32'hef67ab04;
    OTP_DATA[0] = 32'h77b3d500; OTP_DATA[1] = 32'h77b3d500;
    OTP_DATA[2] = 32'h77b3d500; OTP_DATA[3] = 32'h77b3d500;

    // =========================================================================
    // Stage 1: factory provisioning + boot-load + ML-KEM encapsulation
    // =========================================================================
    trst_n = 1'b0;
    repeat (10) @(posedge tck);
    $display("TB: provisioning OTP (ek, vksign, cluster key, inst, data)...");
    provision_otp();

    if (otp_programmed_obs !== 1'b1) begin
      $display("TB: ERROR - OTP not locked after provisioning");
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - OTP provisioned & locked (programmed=1)");

    if (otp_key_state_obs !== 1'b0) begin
      $display("TB: ERROR - key_state must be 0 before first unlock");
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - key_state=0 before first unlock");

    // TC02: OTP contents spot-check
    begin : otp_chk
      integer otp_bad;
      otp_bad = 0;
      if (dut.u_otp.mem[12'h000] !== ek_mem[0])  otp_bad = 1;
      if (dut.u_otp.mem[12'h49F] !== ek_mem[1183]) otp_bad = 1;
      if (dut.u_otp.mem[12'h800] !== pk_mem[0]) otp_bad = 1;
      if (dut.u_otp.mem[12'hF9F] !== pk_mem[1951]) otp_bad = 1;
      for (i = 0; i < 4; i = i + 1)
        if (dut.u_otp.mem[12'hFA0 + i] !== CLUSTER_KEY[31 - i*8 -: 8]) otp_bad = 1;
      for (i = 0; i < 16; i = i + 1)
        if (dut.u_otp.mem[12'hFA4 + i] !== OTP_INST[i/4][31 - (i%4)*8 -: 8]) otp_bad = 1;
      for (i = 0; i < 16; i = i + 1)
        if (dut.u_otp.mem[12'hFB4 + i] !== OTP_DATA[i/4][31 - (i%4)*8 -: 8]) otp_bad = 1;
      if (!otp_bad)
        $display("TB: PASS - OTP contents match provisioned ek/vksign/key/inst/data");
      else begin
        $display("TB: ERROR - OTP contents mismatch");
        err_cnt = err_cnt + 1;
      end
    end

    trst_n = 1'b1;
    $display("TB: reset released, boot-load + ML-KEM encapsulating...");
    wait (dut.loaded === 1'b1);
    $display("TB: boot-load done (pk_reg filled)");
    wait (kem_done_obs === 1'b1);
    $display("TB: ML-KEM encapsulation done at t=%0t", $time);

    // TC03: boot-load registers
    begin : boot_chk
      integer b_bad;
      b_bad = 0;
      if (dut.loaded !== 1'b1) b_bad = 1;
      if (dut.cluster_key !== CLUSTER_KEY) b_bad = 1;
      if (dut.otp_inst !== {OTP_INST[0],OTP_INST[1],OTP_INST[2],OTP_INST[3]}) b_bad = 1;
      if (dut.otp_data !== {OTP_DATA[0],OTP_DATA[1],OTP_DATA[2],OTP_DATA[3]}) b_bad = 1;
      if (dut.pk_reg[15615:15608] !== pk_mem[0]) b_bad = 1;
      if (dut.pk_reg[7:0] !== pk_mem[1951]) b_bad = 1;
      if (!b_bad)
        $display("TB: PASS - boot-load latched vksign/cluster key/inst/data correctly");
      else begin
        $display("TB: ERROR - boot-load register mismatch");
        err_cnt = err_cnt + 1;
      end
    end

    // TC04: KEM encapsulation + CT shifted out via TDO
    if (kem_done_obs === 1'b1 && kem_busy_obs === 1'b0 && enc_key_obs !== 80'd0)
      $display("TB: PASS - ML-KEM encaps completed, KDF key nonzero (%08h...)", enc_key_obs[79:72]);
    else begin
      $display("TB: ERROR - ML-KEM encaps did not complete cleanly");
      err_cnt = err_cnt + 1;
    end
    if (ct_cnt > 0 && !ct_tdo_bad)
      $display("TB: PASS - ciphertext shifted out via TDO (%0d bytes)", ct_cnt);
    else begin
      $display("TB: ERROR - CT did not shift out via TDO (ct_cnt=%0d bad=%b)", ct_cnt, ct_tdo_bad);
      err_cnt = err_cnt + 1;
    end

    // =========================================================================
    // Stage 2: positive unlock, cluster 0 (key_state=0 phase, cluster key)
    // =========================================================================
    sig  = make_sig(0);
    key  = CLUSTER_KEY;
    inst = OTP_INST[0];
    data = OTP_DATA[0][30:0];
    $display("TB: shifting 26,567-bit unlock frame (key=0x%08h, inst=0x%08h, data=0x%07h)", key, inst, data);
    do_unlock(sig, key, inst, data);
    $display("TB: *** UNLOCKED at t=%0t (CLUS_SEL=%02b) ***", $time, clus_sel_obs);

    if (clus_sel_obs != 2'b00) begin
      $display("TB: ERROR - expected CLUS_SEL=00, got %02b", clus_sel_obs);
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - cluster 0 selected (CLUS_SEL=00)");

    if (otp_key_state_obs !== 1'b1) begin
      $display("TB: ERROR - key_state not set to 1 on first unlock");
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - key_state=1 irrevocably set in OTP on first unlock");

    // =========================================================================
    // Stage 3: high-priority instrument output encryption (cluster 0)
    // =========================================================================
    wait (ks_valid_obs === 1'b1);
    $display("TB: SHAKE-256 stream cipher initialized (ks_valid=1, busy=%b)", shake_busy_obs);

    if (enc_iv_obs == 80'd0) begin
      $display("TB: ERROR - per-session TRNG IV is zero");
      err_cnt = err_cnt + 1;
    end else begin
      iv_s0 = enc_iv_obs;
      $display("TB: PASS - per-session TRNG IV latched (%08h...)", enc_iv_obs[79:72]);
    end

    enc_session(0, 40, 64'h8AC0_9F4B_12D3_765E);
    iv_s0 = enc_iv_obs;
    ref0_0 = ref_ks[0]; ref0_1 = ref_ks[1];

    // =========================================================================
    // Stage 4: cluster 1 (mixed priority) - decoder switches encryption
    // =========================================================================
    session_reset();
    if (otp_key_state_obs !== 1'b1) begin
      $display("TB: ERROR - key_state cleared by reset");
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - key_state=1 persists across reset (irrevocable)");

    used_key = key_expect_obs;      // key_state=1 phase: TRNG-derived KDF key
    $display("TB: [cl1] unlock with KDF key 0x%08h", used_key);
    do_unlock(make_sig(0), used_key, OTP_INST[1], OTP_DATA[1][30:0]);
    if (clus_sel_obs != 2'b01) begin
      $display("TB: ERROR - expected CLUS_SEL=01, got %02b", clus_sel_obs);
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - cluster 1 selected (CLUS_SEL=01)");

    wait (ks_valid_obs === 1'b1);
    enc_session(1, 96, 64'hDEAD_BEEF_CAFE_F00D);

    // =========================================================================
    // Stage 5: cluster 2 (all low priority) - raw output
    // =========================================================================
    session_reset();
    used_key = key_expect_obs;
    $display("TB: [cl2] unlock with KDF key 0x%08h", used_key);
    do_unlock(make_sig(0), used_key, OTP_INST[2], OTP_DATA[2][30:0]);
    if (clus_sel_obs != 2'b10) begin
      $display("TB: ERROR - expected CLUS_SEL=10, got %02b", clus_sel_obs);
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - cluster 2 selected (CLUS_SEL=10)");

    wait (ks_valid_obs === 1'b1);
    enc_session(2, 40, 64'h1234_5678_9ABC_DEF0);

    // =========================================================================
    // Stage 6: cluster 3 edge (CLUS_SEL=11, no active MSIB)
    // =========================================================================
    session_reset();
    used_key = key_expect_obs;
    $display("TB: [cl3] unlock with inst[3] (edge CLUS_SEL=11)");
    do_unlock(make_sig(0), used_key, OTP_INST[3], OTP_DATA[3][30:0]);
    if (clus_sel_obs != 2'b11) begin
      $display("TB: ERROR - expected CLUS_SEL=11, got %02b", clus_sel_obs);
      err_cnt = err_cnt + 1;
    end else
      $display("TB: PASS - cluster 3 selected (CLUS_SEL=11, no MSIB active)");
    // no instrument active -> nothing eligible for encryption
    begin : cl3_chk
      integer n;
      reg elig_seen;
      elig_seen = 1'b0;
      tap_select = 1'b1;
      shift_dr   = 1'b1;
      for (n = 0; n < 32; n = n + 1) begin
        tap_tdi = 1'b0;
        @(negedge tck);
        @(posedge tck);
        #1;
        if (enc_elig_obs) elig_seen = 1'b1;
      end
      shift_dr   = 1'b0;
      tap_select = 1'b0;
      tap_tdi    = 1'b0;
      if (!elig_seen)
        $display("TB: PASS - no instrument eligible for encryption at CLUS_SEL=11");
      else begin
        $display("TB: ERROR - encryption eligible with no active instrument");
        err_cnt = err_cnt + 1;
      end
    end

    // =========================================================================
    // Stage 7: per-session IV / keystream uniqueness (replay resistance)
    // =========================================================================
    session_reset();
    used_key = key_expect_obs;
    $display("TB: [replay] re-unlock cluster 0 with a fresh KDF key");
    do_unlock(make_sig(0), used_key, OTP_INST[0], OTP_DATA[0][30:0]);
    wait (ks_valid_obs === 1'b1);
    iv_s1 = enc_iv_obs;
    if (iv_s1 != iv_s0)
      $display("TB: PASS - new unlock session uses a fresh TRNG IV (session replay resistant)");
    else begin
      $display("TB: ERROR - IV reused across sessions (keystream reuse!)");
      err_cnt = err_cnt + 1;
    end
    compute_ref_ks(enc_key_obs, iv_s1);
    if ((ref_ks[0] != ref0_0) || (ref_ks[1] != ref0_1))
      $display("TB: PASS - keystream differs across sessions (no ciphertext reuse)");
    else begin
      $display("TB: ERROR - keystream identical across sessions");
      err_cnt = err_cnt + 1;
    end

    // =========================================================================
    // Stage 8: negative tests (all in key_state=1 phase, KDF key)
    // =========================================================================
    // 8a: wrong signature (c_tilde byte 0 flipped, key correct)
    session_reset();
    used_key = key_expect_obs;
    sig = make_sig(0);
    sig[26471 -: 8] = sig[26471 -: 8] ^ 8'h01;
    fr_build_and_shift(sig, used_key, OTP_INST[0], OTP_DATA[0][30:0]);
    neg_check(16'hA);

    // 8b: wrong key (correct signature, cluster key is wrong in phase 2)
    session_reset();
    used_key = key_expect_obs;
    fr_build_and_shift(make_sig(0), CLUSTER_KEY, OTP_INST[0], OTP_DATA[0][30:0]);
    neg_check(16'hB);

    // 8c: wrong instruction (not in OTP)
    session_reset();
    used_key = key_expect_obs;
    fr_build_and_shift(make_sig(0), used_key, 32'hDEADBEEF, OTP_DATA[0][30:0]);
    neg_check(16'hC);

    // 8d: wrong data pattern
    session_reset();
    used_key = key_expect_obs;
    fr_build_and_shift(make_sig(0), used_key, OTP_INST[0], 31'h0000000);
    neg_check(16'hD);

    // =========================================================================
    // Final summary
    // =========================================================================
    if (err_cnt == 0)
      $display("TB: PASS - ALL TEST CASES PASSED (provision, boot, KEM, unlock x4, encryption, priority decoder, IV replay, negatives)");
    else
      $display("TB: FAIL - %0d error(s)", err_cnt);

    $finish;
  end

  // Global timeout (generous: many KAT verify sessions)
  initial begin
    #300_000_000;
    $display("TB: TIMEOUT - unlocked_obs=%b kem_done=%b mldsa_done=%b shake_busy=%b enc_elig=%b",
             unlocked_obs, kem_done_obs, dut.u_mldsa.done, shake_busy_obs, enc_elig_obs);
    $display("TB: [dbg] AM state=%0d clus_sel=%02b inst_idx=%0d high_pri=%b ks_valid=%b ks=%02h iv=%08h",
             dut.u_am.state_reg, clus_sel_obs, inst_idx_obs, high_pri_obs, ks_valid_obs, ks_byte_obs, enc_iv_obs[79:72]);
    $finish;
  end

  // Monitor AM / ML-DSA progress
  reg [2:0] prev_am_state = 3'b111;
  always @(posedge tck) begin
    if (dut.u_am.state_reg !== prev_am_state) begin
      $display("TB: AM state=%0d sval=%b mldsa_busy=%b mldsa_done=%b vc_state=%0d",
               dut.u_am.state_reg, dut.u_mldsa.sval, dut.u_mldsa.busy, dut.u_mldsa.done,
               dut.u_mldsa.u_verify.state);
      prev_am_state <= dut.u_am.state_reg;
    end
  end

endmodule