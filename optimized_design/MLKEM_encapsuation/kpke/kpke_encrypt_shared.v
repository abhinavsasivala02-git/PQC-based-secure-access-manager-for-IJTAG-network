//============================================================================
// K-PKE.Encrypt — RESOURCE-SHARED VERSION (FIPS 203 Algorithm 13)
// Input:  ek (encapsulation key), m (32-byte msg), r (32-byte seed)
// Output: CT = Compress_du(u) || Compress_dv(v)
//
// FIPS 203 K-PKE.Encrypt(ek, m, r):
//   t_hat = ByteDecode_12(ek[0 : 384K]);  rho = ek[384K : 384K+32]
//   r_hat = NTT(r)
//   u = INTT( sum_j A[i][j] . r_hat[j] ) + e1
//   v = INTT( sum_j t_hat[j] . r_hat[j] ) + e2 + mu   (mu = Decompress_1(m))
//   c = ByteEncode_du(Compress_du(u)) || ByteEncode_dv(Compress_dv(v))
//
// Plain (FIPS 203 / Go) convention: ek stores t_hat in the NTT domain
// directly, so no re-NTT is applied to the decoded t_hat. The plain INTT
// (final scale f = 3303) returns coefficients in [0,q), so no FROMMONT pass
// is needed before compress/encode.
//
// All heavy resources (hash, NTT, basemul, arith) are external ports.
// Lightweight resources (RAMs, sample_ntt_ext, sample_cbd, byte_decode,
// compress, byte_encode) instantiated internally.
//============================================================================
`timescale 1ns/1ps

module kpke_encrypt_shared #(
    parameter K    = 3,
    parameter ETA2 = 2,
    parameter DU   = 10,
    parameter DV   = 4
)(
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,

    input  wire [255:0]  m_in,      // 32-byte message
    input  wire [255:0]  r_seed,    // 32-byte randomness

    // Encapsulation key (byte-addressed, read-only)
    output reg  [12:0]   ek_addr,
    input  wire [7:0]    ek_rdata,

    // Ciphertext output
    output reg           ct_valid,
    output reg  [7:0]    ct_data,
    output reg  [12:0]   ct_addr,

    output reg           done,
    output reg           busy,

    // === External hash engine ===
    output reg  [7:0]    hash_cfg_rate,
    output reg  [7:0]    hash_cfg_domain,
    output reg           hash_init,
    output reg           hash_absorb_valid,
    output reg  [7:0]    hash_absorb_data,
    input  wire          hash_absorb_ready,
    output reg           hash_absorb_last,
    input  wire          hash_squeeze_valid,
    input  wire [7:0]    hash_squeeze_data,
    output reg           hash_squeeze_next,
    input  wire          hash_busy,

    // === External NTT ===
    output reg           ntt_start,
    output reg           ntt_mode,
    input  wire          ntt_done,
    input  wire          ntt_busy,
    input  wire          ntt_ram_wen,
    input  wire [7:0]    ntt_ram_addr_a,
    input  wire [11:0]   ntt_ram_wdata_a,
    output wire [11:0]   ntt_ram_rdata_a,
    input  wire [7:0]    ntt_ram_addr_b,
    output wire [11:0]   ntt_ram_rdata_b,

    // === External basemul ===
    output reg           bmul_start,
    input  wire          bmul_done,
    input  wire          bmul_busy,
    input  wire [7:0]    bmul_a_addr,
    output wire [11:0]   bmul_a_rdata,
    input  wire [7:0]    bmul_b_addr,
    output wire [11:0]   bmul_b_rdata,
    input  wire          bmul_c_wen,
    input  wire [7:0]    bmul_c_addr,
    input  wire [11:0]   bmul_c_wdata,

    // === External arith ===
    output reg           arith_start,
    output reg  [1:0]    arith_mode,
    input  wire          arith_done,
    input  wire          arith_busy,
    input  wire [7:0]    arith_a_addr,
    output wire [11:0]   arith_a_rdata,
    input  wire [7:0]    arith_b_addr,
    output wire [11:0]   arith_b_rdata,
    input  wire          arith_c_wen,
    input  wire [7:0]    arith_c_addr,
    input  wire [11:0]   arith_c_wdata
);

    // =========================================================================
    // FSM States
    // =========================================================================
    localparam [5:0]
        ST_IDLE        = 6'd0,
        ST_READ_RHO    = 6'd1,   // Read rho from end of ek
        ST_DEC_T       = 6'd2,   // Decode t_hat = ByteDecode_12(ek[0:384K])
        ST_DEC_T_W     = 6'd3,
        ST_PRF_R       = 6'd6,   // SHAKE-256(r, N) for r_vec sampling
        ST_WAIT_PRF_R  = 6'd7,
        ST_CBD_R       = 6'd8,
        ST_WAIT_CBD_R  = 6'd9,
        ST_NTT_R       = 6'd10,  // NTT(r_vec[i])
        ST_WAIT_NTT_R  = 6'd11,
        ST_PRF_E1      = 6'd12,  // SHAKE-256(r, N) for e1 sampling
        ST_WAIT_PRF_E1 = 6'd13,
        ST_CBD_E1      = 6'd14,
        ST_WAIT_CBD_E1 = 6'd15,
        ST_CLR_U       = 6'd16,  // Clear u accumulator
        ST_GEN_A       = 6'd17,  // ExpandA row i, col j
        ST_WAIT_SNTT   = 6'd18,
        ST_BMUL_U      = 6'd19,  // A[i][j] * r_hat[j] -> ram6 (product)
        ST_WAIT_MUL_U  = 6'd20,
        ST_ADD_U       = 6'd21,  // u[i] += product
        ST_WAIT_ADD_U  = 6'd22,
        ST_INTT_U      = 6'd23,  // INTT(u[i])
        ST_WAIT_INTT_U = 6'd24,
        ST_ADD_E1      = 6'd25,  // u[i] += e1[i]
        ST_WAIT_ADD_E1 = 6'd26,
        ST_COMP_U      = 6'd27,  // Compress u[i]
        ST_WAIT_COMP_U = 6'd28,
        ST_ENC_U       = 6'd29,  // ByteEncode u[i]
        ST_WAIT_ENC_U  = 6'd30,
        ST_PRF_E2      = 6'd31,  // SHAKE-256(r, 2K) for e2
        ST_WAIT_PRF_E2 = 6'd32,
        ST_CBD_E2      = 6'd33,
        ST_WAIT_CBD_E2 = 6'd34,
        ST_MU_RD       = 6'd35,  // ram6[i] += mu[i] (e2 -> e2+mu)
        ST_MU_WR       = 6'd36,
        ST_CLR_V       = 6'd37,  // Clear v accumulator
        ST_BMUL_V      = 6'd38,  // t_hat[j] * r_hat[j] -> ram0 (product)
        ST_WAIT_MUL_V  = 6'd39,
        ST_ADD_V       = 6'd40,  // v += product
        ST_WAIT_ADD_V  = 6'd41,
        ST_INTT_V      = 6'd42,  // INTT(v)
        ST_WAIT_INTT_V = 6'd43,
        ST_ADD_W       = 6'd44,  // v += (e2+mu)
        ST_WAIT_ADD_W  = 6'd45,
        ST_COMP_V      = 6'd46,  // Compress v
        ST_WAIT_COMP_V = 6'd47,
        ST_ENC_V       = 6'd48,  // ByteEncode v
        ST_WAIT_ENC_V  = 6'd49;

    // Hash constants
    localparam [7:0] SHAKE128_RATE = 8'd168;
    localparam [7:0] SHAKE256_RATE = 8'd136;
    localparam [7:0] SHAKE_DOMAIN  = 8'h1F;

    localparam [11:0] Q = 12'd3329;
    localparam [11:0] MU_HIGH = 12'd1665;  // Decompress_1(1) = round(q/2)
    localparam [7:0]  E2_INDEX = 2 * K;    // PRF counter for e2 sampling

    reg [5:0] state;

    reg [3:0] i_cnt, j_cnt;
    reg [7:0] n_cnt;
    reg [5:0] seed_feed_cnt;
    reg [4:0] rho_byte_cnt;
    reg [8:0] clr_idx;
    reg [8:0] mu_idx;
    reg [255:0] rho, r, m;

    // NTT RAM select: 0=ram1(r), 1=ram2(u), 2=ram3(v), 3=ram4(t_hat)
    reg [1:0] ntt_ram_sel;

    // =========================================================================
    // Internal RAMs
    // ram0: A[i][j] / v basemul product scratch (256 x 12-bit)
    // ram1: r_hat[K x 256 x 12-bit]
    // ram2: u accumulator [K x 256 x 12-bit]
    // ram3: v accumulator [256 x 12-bit]
    // ram4: t_hat [K x 256 x 12-bit]
    // ram5: e1 [K x 256 x 12-bit]
    // ram6: product scratch / e2+mu / compressed temp [256 x 12-bit]
    // =========================================================================
    wire [11:0] ram0_ra, ram0_rb; reg ram0_we; reg [7:0] ram0_aa, ram0_ab; reg [11:0] ram0_wd;
    wire [11:0] ram1_ra, ram1_rb; reg ram1_we; reg [9:0] ram1_aa, ram1_ab; reg [11:0] ram1_wd;
    wire [11:0] ram2_ra, ram2_rb; reg ram2_we; reg [9:0] ram2_aa, ram2_ab; reg [11:0] ram2_wd;
    wire [11:0] ram3_ra, ram3_rb; reg ram3_we; reg [7:0] ram3_aa, ram3_ab; reg [11:0] ram3_wd;
    wire [11:0] ram4_ra, ram4_rb; reg ram4_we; reg [9:0] ram4_aa, ram4_ab; reg [11:0] ram4_wd;
    wire [11:0] ram5_ra, ram5_rb; reg ram5_we; reg [9:0] ram5_aa, ram5_ab; reg [11:0] ram5_wd;
    wire [11:0] ram6_ra, ram6_rb; reg ram6_we; reg [7:0] ram6_aa, ram6_ab; reg [11:0] ram6_wd;

    mlkem_poly_ram u_ram0(.clk(clk),.a_wen(ram0_we),.a_addr(ram0_aa),.a_wdata(ram0_wd),.a_rdata(ram0_ra),.b_addr(ram0_ab),.b_rdata(ram0_rb));
    mlkem_poly_ram #(.DEPTH(768),.ADDR_W(10)) u_ram1(.clk(clk),.a_wen(ram1_we),.a_addr(ram1_aa),.a_wdata(ram1_wd),.a_rdata(ram1_ra),.b_addr(ram1_ab),.b_rdata(ram1_rb));
    mlkem_poly_ram #(.DEPTH(768),.ADDR_W(10)) u_ram2(.clk(clk),.a_wen(ram2_we),.a_addr(ram2_aa),.a_wdata(ram2_wd),.a_rdata(ram2_ra),.b_addr(ram2_ab),.b_rdata(ram2_rb));
    mlkem_poly_ram u_ram3(.clk(clk),.a_wen(ram3_we),.a_addr(ram3_aa),.a_wdata(ram3_wd),.a_rdata(ram3_ra),.b_addr(ram3_ab),.b_rdata(ram3_rb));
    mlkem_poly_ram #(.DEPTH(768),.ADDR_W(10)) u_ram4(.clk(clk),.a_wen(ram4_we),.a_addr(ram4_aa),.a_wdata(ram4_wd),.a_rdata(ram4_ra),.b_addr(ram4_ab),.b_rdata(ram4_rb));
    mlkem_poly_ram #(.DEPTH(768),.ADDR_W(10)) u_ram5(.clk(clk),.a_wen(ram5_we),.a_addr(ram5_aa),.a_wdata(ram5_wd),.a_rdata(ram5_ra),.b_addr(ram5_ab),.b_rdata(ram5_rb));
    mlkem_poly_ram u_ram6(.clk(clk),.a_wen(ram6_we),.a_addr(ram6_aa),.a_wdata(ram6_wd),.a_rdata(ram6_ra),.b_addr(ram6_ab),.b_rdata(ram6_rb));

    // =========================================================================
    // SampleNTT (external hash)
    // =========================================================================
    reg sntt_start;
    wire sntt_done, sntt_busy, sntt_wen;
    wire [7:0]  sntt_addr;
    wire [11:0] sntt_wdata;
    wire sntt_hash_init, sntt_hash_av, sntt_hash_al, sntt_hash_sn;
    wire [7:0] sntt_hash_ad;

    sample_ntt_ext u_sntt(
        .clk(clk), .rst_n(rst_n), .start(sntt_start),
        .seed(rho), .idx_i({4'd0,j_cnt}), .idx_j({4'd0,i_cnt}),
        .done(sntt_done), .busy(sntt_busy),
        .poly_wen(sntt_wen), .poly_addr(sntt_addr), .poly_wdata(sntt_wdata),
        .hash_init(sntt_hash_init),
        .hash_absorb_valid(sntt_hash_av), .hash_absorb_data(sntt_hash_ad),
        .hash_absorb_ready(hash_absorb_ready), .hash_absorb_last(sntt_hash_al),
        .hash_squeeze_valid(hash_squeeze_valid), .hash_squeeze_data(hash_squeeze_data),
        .hash_squeeze_next(sntt_hash_sn), .hash_busy(hash_busy)
    );

    // =========================================================================
    // SampleCBD
    // =========================================================================
    reg cbd_start;
    wire cbd_done, cbd_busy, cbd_wen, cbd_prf_req;
    wire [7:0]  cbd_addr;
    wire [11:0] cbd_wdata;

    sample_cbd #(.ETA(ETA2)) u_cbd(
        .clk(clk), .rst_n(rst_n), .start(cbd_start),
        .done(cbd_done), .busy(cbd_busy),
        .prf_valid(hash_squeeze_valid), .prf_data(hash_squeeze_data),
        .prf_req(cbd_prf_req),
        .poly_wen(cbd_wen), .poly_addr(cbd_addr), .poly_wdata(cbd_wdata)
    );

    // =========================================================================
    // ByteDecode_12 (for t = ByteDecode_12(ek[0:384K]))
    // =========================================================================
    reg        dec_start;
    reg        dec_byte_ok;
    reg [7:0]  dec_byte;
    reg        dec_fed;
    wire       dec_done, dec_busy, dec_byte_req;
    wire       dec_poly_wen;
    wire [7:0] dec_poly_addr;
    wire [11:0] dec_poly_wdata;

    byte_decode #(.D(12)) u_dec(
        .clk(clk), .rst_n(rst_n), .start(dec_start),
        .done(dec_done), .busy(dec_busy),
        .byte_valid(dec_byte_ok), .byte_data(dec_byte), .byte_req(dec_byte_req),
        .poly_wen(dec_poly_wen), .poly_addr(dec_poly_addr), .poly_wdata(dec_poly_wdata)
    );

    // =========================================================================
    // Compress_DU (for u)
    // =========================================================================
    reg        comp_u_start;
    wire       comp_u_done, comp_u_busy, comp_u_out_wen;
    wire [7:0] comp_u_in_addr, comp_u_out_addr;
    wire [11:0] comp_u_out_wdata;

    compress #(.D(DU)) u_comp_u(
        .clk(clk), .rst_n(rst_n), .start(comp_u_start),
        .done(comp_u_done), .busy(comp_u_busy),
        .in_addr(comp_u_in_addr), .in_rdata(ram2_ra),
        .out_wen(comp_u_out_wen), .out_addr(comp_u_out_addr), .out_wdata(comp_u_out_wdata)
    );

    // =========================================================================
    // Compress_DV (for v)
    // =========================================================================
    reg        comp_v_start;
    wire       comp_v_done, comp_v_busy, comp_v_out_wen;
    wire [7:0] comp_v_in_addr, comp_v_out_addr;
    wire [11:0] comp_v_out_wdata;

    compress #(.D(DV)) u_comp_v(
        .clk(clk), .rst_n(rst_n), .start(comp_v_start),
        .done(comp_v_done), .busy(comp_v_busy),
        .in_addr(comp_v_in_addr), .in_rdata(ram3_ra),
        .out_wen(comp_v_out_wen), .out_addr(comp_v_out_addr), .out_wdata(comp_v_out_wdata)
    );

    // =========================================================================
    // ByteEncode_DU (for u output)
    // =========================================================================
    reg         enc_u_start;
    wire        enc_u_done, enc_u_busy, enc_u_bvalid;
    wire [7:0]  enc_u_poly_addr, enc_u_bdata;
    wire [10:0] enc_u_baddr;

    byte_encode #(.D(DU)) u_enc_u(
        .clk(clk), .rst_n(rst_n), .start(enc_u_start),
        .done(enc_u_done), .busy(enc_u_busy),
        .poly_addr(enc_u_poly_addr), .poly_rdata(ram6_ra),
        .byte_valid(enc_u_bvalid), .byte_data(enc_u_bdata), .byte_addr(enc_u_baddr)
    );

    // =========================================================================
    // ByteEncode_DV (for v output)
    // =========================================================================
    reg         enc_v_start;
    wire        enc_v_done, enc_v_busy, enc_v_bvalid;
    wire [7:0]  enc_v_poly_addr, enc_v_bdata;
    wire [10:0] enc_v_baddr;

    byte_encode #(.D(DV)) u_enc_v(
        .clk(clk), .rst_n(rst_n), .start(enc_v_start),
        .done(enc_v_done), .busy(enc_v_busy),
        .poly_addr(enc_v_poly_addr), .poly_rdata(ram6_ra),
        .byte_valid(enc_v_bvalid), .byte_data(enc_v_bdata), .byte_addr(enc_v_baddr)
    );

    // =========================================================================
    // NTT RAM routing
    // r_hat in ram1, u in ram2, v in ram3, t_hat in ram4
    // =========================================================================
    assign ntt_ram_rdata_a = (ntt_ram_sel==2'd0) ? ram1_ra :
                             (ntt_ram_sel==2'd1) ? ram2_ra :
                             (ntt_ram_sel==2'd2) ? ram3_ra : ram4_ra;
    assign ntt_ram_rdata_b = (ntt_ram_sel==2'd0) ? ram1_rb :
                             (ntt_ram_sel==2'd1) ? ram2_rb :
                             (ntt_ram_sel==2'd2) ? ram3_rb : ram4_rb;

    // Basemul: A(ram0) or t_hat(ram4) * r_hat(ram1)
    reg bmul_use_t;
    assign bmul_a_rdata = bmul_use_t ? ram4_ra : ram0_ra;
    assign bmul_b_rdata = ram1_ra;

    // Arith inputs (routed per operation)
    assign arith_a_rdata =
        (state==ST_ADD_V || state==ST_WAIT_ADD_V ||
         state==ST_ADD_W || state==ST_WAIT_ADD_W) ? ram3_ra : ram2_ra;
    assign arith_b_rdata =
        (state==ST_ADD_U  || state==ST_WAIT_ADD_U) ? ram6_ra :   // product
        (state==ST_ADD_E1 || state==ST_WAIT_ADD_E1) ? ram5_ra :  // e1
        (state==ST_ADD_V  || state==ST_WAIT_ADD_V) ? ram0_ra :   // v product
        (state==ST_ADD_W  || state==ST_WAIT_ADD_W) ? ram6_ra :   // e2+mu
        ram2_ra;

    // =========================================================================
    // Hash Mux: 0=FSM, 1=sntt, 2=CBD
    // =========================================================================
    reg [1:0] hmux;
    reg fhi, fhav, fhal, fhsn; reg [7:0] fhad;

    always @(*) begin
        case (hmux)
            2'd1: begin hash_init=sntt_hash_init; hash_absorb_valid=sntt_hash_av;
                        hash_absorb_data=sntt_hash_ad; hash_absorb_last=sntt_hash_al;
                        hash_squeeze_next=sntt_hash_sn; end
            2'd2: begin hash_init=fhi; hash_absorb_valid=fhav;
                        hash_absorb_data=fhad; hash_absorb_last=fhal;
                        hash_squeeze_next=cbd_prf_req; end
            default: begin hash_init=fhi; hash_absorb_valid=fhav;
                           hash_absorb_data=fhad; hash_absorb_last=fhal;
                           hash_squeeze_next=fhsn; end
        endcase
    end

    // mu addend (Decompress_1 of message bit)
    wire [11:0] mu_addend   = m[mu_idx[7:0]] ? MU_HIGH : 12'd0;
    wire [12:0] mu_sum      = {1'b0, ram6_ra} + {1'b0, mu_addend};
    wire [11:0] mu_reduced  = (mu_sum >= {1'b0,Q}) ? mu_sum[11:0] - Q : mu_sum[11:0];

    // =========================================================================
    // RAM combinational mux
    // =========================================================================
    always @(*) begin
        ram0_we=0; ram0_aa=0; ram0_ab=0; ram0_wd=0;
        ram1_we=0; ram1_aa=0; ram1_ab=0; ram1_wd=0;
        ram2_we=0; ram2_aa=0; ram2_ab=0; ram2_wd=0;
        ram3_we=0; ram3_aa=0; ram3_ab=0; ram3_wd=0;
        ram4_we=0; ram4_aa=0; ram4_ab=0; ram4_wd=0;
        ram5_we=0; ram5_aa=0; ram5_ab=0; ram5_wd=0;
        ram6_we=0; ram6_aa=0; ram6_ab=0; ram6_wd=0;

        case (state)
            ST_WAIT_CBD_R: begin
                ram1_we=cbd_wen; ram1_aa={i_cnt[1:0],cbd_addr}; ram1_wd=cbd_wdata;
            end
            ST_NTT_R, ST_WAIT_NTT_R: begin
                // ntt on r_hat (ram1)
                ram1_we=ntt_ram_wen; ram1_aa={i_cnt[1:0],ntt_ram_addr_a};
                ram1_wd=ntt_ram_wdata_a; ram1_ab={i_cnt[1:0],ntt_ram_addr_b};
            end
            ST_WAIT_CBD_E1: begin
                ram5_we=cbd_wen; ram5_aa={i_cnt[1:0],cbd_addr}; ram5_wd=cbd_wdata;
            end
            ST_DEC_T_W: begin
                ram4_we=dec_poly_wen; ram4_aa={i_cnt[1:0],dec_poly_addr}; ram4_wd=dec_poly_wdata;
            end
            ST_CLR_U: begin
                ram2_we=1; ram2_aa={i_cnt[1:0],clr_idx[7:0]}; ram2_wd=0;
            end
            ST_WAIT_SNTT: begin
                ram0_we=sntt_wen; ram0_aa=sntt_addr; ram0_wd=sntt_wdata;
            end
            ST_BMUL_U, ST_WAIT_MUL_U: begin
                ram0_aa=bmul_a_addr; ram1_aa={j_cnt[1:0],bmul_b_addr};
                ram6_we=bmul_c_wen; ram6_aa=bmul_c_addr; ram6_wd=bmul_c_wdata;
            end
            ST_ADD_U, ST_WAIT_ADD_U: begin
                ram2_aa={i_cnt[1:0],arith_a_addr};
                ram6_aa=arith_b_addr;
                ram2_we=arith_c_wen; ram2_wd=arith_c_wdata;
            end
            ST_INTT_U, ST_WAIT_INTT_U: begin
                ram2_we=ntt_ram_wen; ram2_aa={i_cnt[1:0],ntt_ram_addr_a};
                ram2_wd=ntt_ram_wdata_a; ram2_ab={i_cnt[1:0],ntt_ram_addr_b};
            end
            ST_ADD_E1, ST_WAIT_ADD_E1: begin
                ram2_aa={i_cnt[1:0],arith_a_addr}; ram5_aa={i_cnt[1:0],arith_b_addr};
                ram2_we=arith_c_wen; ram2_wd=arith_c_wdata;
            end
            ST_COMP_U, ST_WAIT_COMP_U: begin
                ram2_aa={i_cnt[1:0],comp_u_in_addr};
                ram6_we=comp_u_out_wen; ram6_aa=comp_u_out_addr; ram6_wd=comp_u_out_wdata;
            end
            ST_ENC_U, ST_WAIT_ENC_U: begin
                ram6_aa=enc_u_poly_addr;
            end
            ST_WAIT_CBD_E2: begin
                ram6_we=cbd_wen; ram6_aa=cbd_addr; ram6_wd=cbd_wdata;
            end
            ST_MU_RD: begin
                ram6_aa=mu_idx[7:0];
            end
            ST_MU_WR: begin
                ram6_we=1; ram6_aa=mu_idx[7:0]; ram6_wd=mu_reduced;
            end
            ST_CLR_V: begin
                ram3_we=1; ram3_aa=clr_idx[7:0]; ram3_wd=0;
            end
            ST_BMUL_V, ST_WAIT_MUL_V: begin
                ram4_aa={j_cnt[1:0],bmul_a_addr}; ram1_aa={j_cnt[1:0],bmul_b_addr};
                ram0_we=bmul_c_wen; ram0_aa=bmul_c_addr; ram0_wd=bmul_c_wdata;
            end
            ST_ADD_V, ST_WAIT_ADD_V: begin
                ram3_aa=arith_a_addr; ram0_aa=arith_b_addr;
                ram3_we=arith_c_wen; ram3_wd=arith_c_wdata;
            end
            ST_INTT_V, ST_WAIT_INTT_V: begin
                ram3_we=ntt_ram_wen; ram3_aa=ntt_ram_addr_a;
                ram3_wd=ntt_ram_wdata_a; ram3_ab=ntt_ram_addr_b;
            end
            ST_ADD_W, ST_WAIT_ADD_W: begin
                ram3_aa=arith_a_addr; ram6_aa=arith_b_addr;
                ram3_we=arith_c_wen; ram3_wd=arith_c_wdata;
            end
            ST_COMP_V, ST_WAIT_COMP_V: begin
                ram3_aa=comp_v_in_addr;
                ram6_we=comp_v_out_wen; ram6_aa=comp_v_out_addr; ram6_wd=comp_v_out_wdata;
            end
            ST_ENC_V, ST_WAIT_ENC_V: begin
                ram6_aa=enc_v_poly_addr;
            end
            default: ;
        endcase
    end

    // =========================================================================
    // FSM
    // =========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=ST_IDLE;
            done<=0; busy<=0; ct_valid<=0; ct_data<=0; ct_addr<=0;
            fhi<=0; fhav<=0; fhad<=0; fhal<=0; fhsn<=0;
            hash_cfg_rate<=0; hash_cfg_domain<=0; hmux<=0;
            sntt_start<=0; cbd_start<=0;
            ntt_start<=0; ntt_mode<=0; ntt_ram_sel<=0;
            bmul_start<=0; bmul_use_t<=0;
            arith_start<=0; arith_mode<=0;
            comp_u_start<=0; comp_v_start<=0;
            enc_u_start<=0; enc_v_start<=0;
            dec_start<=0; dec_byte_ok<=0; dec_byte<=0; dec_fed<=0;
            i_cnt<=0; j_cnt<=0; n_cnt<=0;
            rho<=0; r<=0; m<=0;
            seed_feed_cnt<=0; rho_byte_cnt<=0; clr_idx<=0; mu_idx<=0;
            ek_addr<=0;
        end else begin
            fhi<=0; fhav<=0; fhal<=0; fhsn<=0;
            sntt_start<=0; cbd_start<=0;
            ntt_start<=0; bmul_start<=0; arith_start<=0;
            comp_u_start<=0; comp_v_start<=0;
            enc_u_start<=0; enc_v_start<=0;
            dec_start<=0; dec_byte_ok<=0;
            done<=0; ct_valid<=0;

            case (state)

                ST_IDLE: begin
                    busy<=0;
                    if (start) begin
                        busy<=1; m<=m_in; r<=r_seed;
                        // rho is at ek[384*K .. 384*K+31]
                        ek_addr <= 13'd384 * K[12:0];
                        rho_byte_cnt<=0; state<=ST_READ_RHO;
                    end
                end

                ST_READ_RHO: begin
                    rho[rho_byte_cnt*8 +: 8] <= ek_rdata;
                    ek_addr <= ek_addr + 1;
                    if (rho_byte_cnt==5'd31) begin
                        i_cnt<=0; ek_addr<=13'd0; dec_fed<=0; state<=ST_DEC_T;
                    end else rho_byte_cnt<=rho_byte_cnt+1;
                end

                // --- Decode t_hat (NTT domain) directly into ram4 ---
                ST_DEC_T: begin
                    dec_start<=1; dec_fed<=0; state<=ST_DEC_T_W;
                end
                ST_DEC_T_W: begin
                    if (dec_done) begin
                        if (i_cnt<K-1) begin i_cnt<=i_cnt+1; state<=ST_DEC_T; end
                        else begin i_cnt<=0; n_cnt<=0; state<=ST_PRF_R; end
                    end else if (dec_byte_req && !dec_fed) begin
                        dec_byte_ok<=1; dec_byte<=ek_rdata;
                        ek_addr<=ek_addr+1; dec_fed<=1;
                    end else if (!dec_byte_req) begin
                        dec_fed<=0;
                    end
                end

                // --- Sample r_vec ---
                ST_PRF_R: begin
                    hash_cfg_rate<=SHAKE256_RATE; hash_cfg_domain<=SHAKE_DOMAIN;
                    fhi<=1; hmux<=2'd0; seed_feed_cnt<=0;
                    state<=ST_WAIT_PRF_R;
                end
                ST_WAIT_PRF_R: begin
                    if (hash_absorb_ready) begin
                        fhav<=1;
                        if (seed_feed_cnt<6'd32) begin
                            fhad<=r[seed_feed_cnt*8+:8]; seed_feed_cnt<=seed_feed_cnt+1;
                        end else begin
                            fhad<=n_cnt; fhal<=1; n_cnt<=n_cnt+1;
                            hmux<=2'd2; state<=ST_CBD_R;
                        end
                    end
                end
                ST_CBD_R: begin cbd_start<=1; state<=ST_WAIT_CBD_R; end
                ST_WAIT_CBD_R: begin
                    if (cbd_done) begin
                        ntt_start<=1; ntt_mode<=0; ntt_ram_sel<=2'd0; state<=ST_NTT_R;
                    end
                end
                ST_NTT_R: state<=ST_WAIT_NTT_R;
                ST_WAIT_NTT_R: begin
                    if (ntt_done) begin
                        if (i_cnt<K-1) begin i_cnt<=i_cnt+1; state<=ST_PRF_R; end
                        else begin i_cnt<=0; state<=ST_PRF_E1; end
                    end
                end

                // --- Sample e1 ---
                ST_PRF_E1: begin
                    hash_cfg_rate<=SHAKE256_RATE; hash_cfg_domain<=SHAKE_DOMAIN;
                    fhi<=1; hmux<=2'd0; seed_feed_cnt<=0; state<=ST_WAIT_PRF_E1;
                end
                ST_WAIT_PRF_E1: begin
                    if (hash_absorb_ready) begin
                        fhav<=1;
                        if (seed_feed_cnt<6'd32) begin
                            fhad<=r[seed_feed_cnt*8+:8]; seed_feed_cnt<=seed_feed_cnt+1;
                        end else begin
                            fhad<=n_cnt; fhal<=1; n_cnt<=n_cnt+1; hmux<=2'd2; state<=ST_CBD_E1;
                        end
                    end
                end
                ST_CBD_E1: begin cbd_start<=1; state<=ST_WAIT_CBD_E1; end
                ST_WAIT_CBD_E1: begin
                    if (cbd_done) begin
                        if (i_cnt<K-1) begin i_cnt<=i_cnt+1; state<=ST_PRF_E1; end
                        else begin i_cnt<=0; clr_idx<=0; j_cnt<=0; state<=ST_CLR_U; end
                    end
                end

                // --- Compute u = INTT(sum_j A[i][j].r_hat[j]) + e1 ---
                ST_CLR_U: begin
                    if (clr_idx==9'd255) begin
                        j_cnt<=0; state<=ST_GEN_A;
                    end else clr_idx<=clr_idx+1;
                end
                ST_GEN_A: begin
                    hash_cfg_rate<=SHAKE128_RATE; hash_cfg_domain<=SHAKE_DOMAIN;
                    hmux<=2'd1; sntt_start<=1; state<=ST_WAIT_SNTT;
                end
                ST_WAIT_SNTT: begin
                    if (sntt_done) begin
                        hmux<=2'd0; bmul_use_t<=0; bmul_start<=1; state<=ST_BMUL_U;
                    end
                end
                ST_BMUL_U: state<=ST_WAIT_MUL_U;
                ST_WAIT_MUL_U: begin
                    if (bmul_done) begin arith_mode<=2'b00; arith_start<=1; state<=ST_ADD_U; end
                end
                ST_ADD_U: state<=ST_WAIT_ADD_U;
                ST_WAIT_ADD_U: begin
                    if (arith_done) begin
                        if (j_cnt<K-1) begin
                            j_cnt<=j_cnt+1;
                            hash_cfg_rate<=SHAKE128_RATE; hash_cfg_domain<=SHAKE_DOMAIN;
                            hmux<=2'd1; sntt_start<=1; state<=ST_GEN_A;
                        end
                        else begin ntt_start<=1; ntt_mode<=1; ntt_ram_sel<=2'd1; state<=ST_INTT_U; end
                    end
                end
                ST_INTT_U: state<=ST_WAIT_INTT_U;
                ST_WAIT_INTT_U: begin
                    if (ntt_done) begin arith_mode<=2'b00; arith_start<=1; state<=ST_ADD_E1; end
                end
                ST_ADD_E1: state<=ST_WAIT_ADD_E1;
                ST_WAIT_ADD_E1: begin
                    if (arith_done) begin
                        comp_u_start<=1; state<=ST_COMP_U;
                    end
                end
                ST_COMP_U: state<=ST_WAIT_COMP_U;
                ST_WAIT_COMP_U: begin
                    if (comp_u_done) begin enc_u_start<=1; state<=ST_ENC_U; end
                end
                ST_ENC_U: state<=ST_WAIT_ENC_U;
                ST_WAIT_ENC_U: begin
                    ct_valid <= enc_u_bvalid;
                    ct_data  <= enc_u_bdata;
                    ct_addr  <= {2'd0,enc_u_baddr} + {9'd0,i_cnt}*13'd320;
                    if (enc_u_done) begin
                        if (i_cnt<K-1) begin
                            i_cnt<=i_cnt+1; j_cnt<=0; clr_idx<=0; state<=ST_CLR_U;
                        end else begin
                            seed_feed_cnt<=0; state<=ST_PRF_E2;
                        end
                    end
                end

                // --- Sample e2 (reuse SHAKE-256(r, 2K)) ---
                ST_PRF_E2: begin
                    hash_cfg_rate<=SHAKE256_RATE; hash_cfg_domain<=SHAKE_DOMAIN;
                    fhi<=1; hmux<=2'd0; seed_feed_cnt<=0; state<=ST_WAIT_PRF_E2;
                end
                ST_WAIT_PRF_E2: begin
                    if (hash_absorb_ready) begin
                        fhav<=1;
                        if (seed_feed_cnt<6'd32) begin
                            fhad<=r[seed_feed_cnt*8+:8]; seed_feed_cnt<=seed_feed_cnt+1;
                        end else begin
                            fhad<=E2_INDEX; fhal<=1; hmux<=2'd2; state<=ST_CBD_E2;
                        end
                    end
                end
                ST_CBD_E2: begin cbd_start<=1; state<=ST_WAIT_CBD_E2; end
                ST_WAIT_CBD_E2: begin
                    if (cbd_done) begin mu_idx<=0; state<=ST_MU_RD; end
                end

                // --- mu loop: ram6 (e2) += mu[i]  ->  w = e2 + mu ---
                ST_MU_RD: state<=ST_MU_WR;
                ST_MU_WR: begin
                    if (mu_idx==9'd255) begin clr_idx<=0; j_cnt<=0; state<=ST_CLR_V; end
                    else begin mu_idx<=mu_idx+1; state<=ST_MU_RD; end
                end

                // --- Compute v = INTT(sum_j t_hat[j].r_hat[j]) + e2 + mu ---
                ST_CLR_V: begin
                    if (clr_idx==9'd255) begin
                        j_cnt<=0; bmul_use_t<=1; bmul_start<=1; state<=ST_BMUL_V;
                    end else clr_idx<=clr_idx+1;
                end
                ST_BMUL_V: state<=ST_WAIT_MUL_V;
                ST_WAIT_MUL_V: begin
                    if (bmul_done) begin arith_mode<=2'b00; arith_start<=1; state<=ST_ADD_V; end
                end
                ST_ADD_V: state<=ST_WAIT_ADD_V;
                ST_WAIT_ADD_V: begin
                    if (arith_done) begin
                        if (j_cnt<K-1) begin
                            j_cnt<=j_cnt+1; bmul_start<=1; state<=ST_BMUL_V;
                        end
                        else begin ntt_start<=1; ntt_mode<=1; ntt_ram_sel<=2'd2; state<=ST_INTT_V; end
                    end
                end
                ST_INTT_V: state<=ST_WAIT_INTT_V;
                ST_WAIT_INTT_V: begin
                    if (ntt_done) begin arith_mode<=2'b00; arith_start<=1; state<=ST_ADD_W; end
                end
                ST_ADD_W: state<=ST_WAIT_ADD_W;
                ST_WAIT_ADD_W: begin
                    if (arith_done) begin comp_v_start<=1; state<=ST_COMP_V; end
                end
                ST_COMP_V: state<=ST_WAIT_COMP_V;
                ST_WAIT_COMP_V: begin
                    if (comp_v_done) begin enc_v_start<=1; state<=ST_ENC_V; end
                end
                ST_ENC_V: state<=ST_WAIT_ENC_V;
                ST_WAIT_ENC_V: begin
                    ct_valid <= enc_v_bvalid;
                    ct_data  <= enc_v_bdata;
                    ct_addr  <= 13'd320*K[12:0] + {2'd0,enc_v_baddr};
                    if (enc_v_done) begin
                        done<=1; busy<=0; state<=ST_IDLE;
                    end
                end

                default: state<=ST_IDLE;
            endcase
        end
    end

endmodule