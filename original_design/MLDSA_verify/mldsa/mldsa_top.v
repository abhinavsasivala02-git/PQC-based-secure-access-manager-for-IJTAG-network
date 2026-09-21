// =============================================================================
// mldsa_top.v - ML-DSA-65 Top Level with AXI4-Lite Slave Interface  [v3]
//
// Added:
//   - SHAKE-128 instance for ExpandA (keygen matrix generation)
//   - Updated keygen_ctrl wiring with SHAKE-128 ports
//   - Full bus arbitration for all shared resources
//
// Register / Memory map (byte-addressed):
//   0x0000  CTRL     [0]=start_keygen [1]=start_sign [2]=start_verify
//   0x0004  STATUS   [0]=busy [1]=done [2]=sig_valid
//   0x0010-0x002C  seed_xi    (256-bit, 8 words)
//   0x0030-0x004C  sk_rho     (256-bit, 8 words)
//   0x0050-0x006C  sk_K       (256-bit, 8 words)
//   0x0070-0x008C  sk_tr      (256-bit, 8 words)
//   0x0090-0x00AC  rnd        (256-bit, 8 words)
//   0x00B0-0x00CC  c_tilde    (256-bit, 8 words)
//   0x00D0-0x00EC  mu_lo      (mu[255:0],   8 words)
//   0x00F0-0x010C  mu_hi      (mu[511:256], 8 words)
//   0x1000-0x13FC  poly_z_ram  (256 coefficients, 1 word each)
//   0x1400-0x17FC  poly_r0_ram (256 coefficients, 1 word each)
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module mldsa_top (
    input  wire          ACLK,
    input  wire          ARESETn,

    input  wire          AWVALID,
    output reg           AWREADY,
    input  wire [15:0]   AWADDR,
    input  wire [2:0]    AWPROT,

    input  wire          WVALID,
    output reg           WREADY,
    input  wire [31:0]   WDATA,
    input  wire [3:0]    WSTRB,

    output reg           BVALID,
    input  wire          BREADY,
    output reg  [1:0]    BRESP,

    input  wire          ARVALID,
    output reg           ARREADY,
    input  wire [15:0]   ARADDR,
    input  wire [2:0]    ARPROT,

    output reg           RVALID,
    input  wire          RREADY,
    output reg  [31:0]   RDATA,
    output reg  [1:0]    RRESP
);

    wire clk   = ACLK;
    wire rst_n = ARESETn;

    // =========================================================================
    // AXI-mapped configuration registers
    // =========================================================================
    reg [31:0] ctrl_reg;
    reg [31:0] seed_reg   [0:7];
    reg [31:0] rho_reg    [0:7];
    reg [31:0] K_reg      [0:7];
    reg [31:0] tr_reg     [0:7];
    reg [31:0] rnd_reg    [0:7];
    reg [31:0] ctilde_reg [0:7];
    reg [31:0] mu_lo_reg  [0:7];
    reg [31:0] mu_hi_reg  [0:7];

    // =========================================================================
    // Polynomial RAMs - AXI write port, controller read port
    // =========================================================================
    reg [31:0] poly_z_ram  [0:255];
    reg [31:0] poly_r0_ram [0:255];

    // =========================================================================
    // PK/SK RAMs - written by keygen_ctrl, read via AXI
    // =========================================================================
    reg [7:0]  pk_ram [0:1951];  // 1952 bytes: rho(32) + t1(1920)
    reg [7:0]  sk_ram [0:4031];  // 4032 bytes: rho(32)+K(32)+tr(64)+s1(1280)+s2(1536)+t0(704)

    // Forward declarations for keygen write signals (instantiated later)
    wire        kg_pk_we_w, kg_sk_we_w;
    wire [10:0] kg_pk_addr_w;
    wire [11:0] kg_sk_addr_w;
    wire [7:0]  kg_pk_wdata_w, kg_sk_wdata_w;

    // =========================================================================
    // Connect keygen pk/sk write signals to PK/SK RAMs
    // =========================================================================
    always @(posedge clk) begin
        if (kg_pk_we_w)
            pk_ram[kg_pk_addr_w] <= kg_pk_wdata_w;
        if (kg_sk_we_w)
            sk_ram[kg_sk_addr_w] <= kg_sk_wdata_w;
    end

    // Simulation-only init to prevent X
    // pragma translate_off
    integer ram_init_i;
    initial begin
        for (ram_init_i = 0; ram_init_i < 256; ram_init_i = ram_init_i + 1) begin
            poly_z_ram [ram_init_i] = 32'd0;
            poly_r0_ram[ram_init_i] = 32'd0;
        end
        for (ram_init_i = 0; ram_init_i < 1952; ram_init_i = ram_init_i + 1)
            pk_ram[ram_init_i] = 8'd0;
        for (ram_init_i = 0; ram_init_i < 4032; ram_init_i = ram_init_i + 1)
            sk_ram[ram_init_i] = 8'd0;
    end
    // pragma translate_on

    // Aggregate wide buses
    wire [255:0] seed_xi = {seed_reg[7],seed_reg[6],seed_reg[5],seed_reg[4],
                             seed_reg[3],seed_reg[2],seed_reg[1],seed_reg[0]};
    wire [255:0] sk_rho  = {rho_reg[7],rho_reg[6],rho_reg[5],rho_reg[4],
                             rho_reg[3],rho_reg[2],rho_reg[1],rho_reg[0]};
    wire [255:0] sk_K    = {K_reg[7],K_reg[6],K_reg[5],K_reg[4],
                             K_reg[3],K_reg[2],K_reg[1],K_reg[0]};
    wire [255:0] sk_tr   = {tr_reg[7],tr_reg[6],tr_reg[5],tr_reg[4],
                             tr_reg[3],tr_reg[2],tr_reg[1],tr_reg[0]};
    wire [255:0] rnd_w   = {rnd_reg[7],rnd_reg[6],rnd_reg[5],rnd_reg[4],
                             rnd_reg[3],rnd_reg[2],rnd_reg[1],rnd_reg[0]};
    wire [255:0] c_tilde_orig_w =
                            {ctilde_reg[7],ctilde_reg[6],ctilde_reg[5],ctilde_reg[4],
                             ctilde_reg[3],ctilde_reg[2],ctilde_reg[1],ctilde_reg[0]};
    wire [511:0] mu_w    = {mu_hi_reg[7],mu_hi_reg[6],mu_hi_reg[5],mu_hi_reg[4],
                             mu_hi_reg[3],mu_hi_reg[2],mu_hi_reg[1],mu_hi_reg[0],
                             mu_lo_reg[7],mu_lo_reg[6],mu_lo_reg[5],mu_lo_reg[4],
                             mu_lo_reg[3],mu_lo_reg[2],mu_lo_reg[1],mu_lo_reg[0]};

    // =========================================================================
    // One-cycle start pulses
    // =========================================================================
    reg start_keygen, start_sign, start_verify;
    always @(posedge clk) begin
        if (!rst_n) begin
            start_keygen <= 1'b0;
            start_sign   <= 1'b0;
            start_verify <= 1'b0;
        end else begin
            start_keygen <= ctrl_reg[0];
            start_sign   <= ctrl_reg[1];
            start_verify <= ctrl_reg[2];
        end
    end

    // =========================================================================
    // NTT Core
    // =========================================================================
    wire                      ntt_start_w, ntt_intt_mode_w;
    wire                      ntt_busy_w,  ntt_done_w;
    wire                      ntt_ext_we_w;
    wire [7:0]                ntt_ext_addr_w;
    wire [`MLDSA_QBITS-1:0]  ntt_ext_din_w, ntt_ext_dout_w;

    (* DONT_TOUCH = "TRUE" *)
    ntt_core u_ntt (
        .clk       (clk),        .rst_n     (rst_n),
        .start     (ntt_start_w),.intt_mode (ntt_intt_mode_w),
        .busy      (ntt_busy_w), .done      (ntt_done_w),
        .ext_we    (ntt_ext_we_w),
        .ext_addr  (ntt_ext_addr_w),
        .ext_din   (ntt_ext_din_w),
        .ext_dout  (ntt_ext_dout_w)
    );

    // =========================================================================
    // Unified SHAKE-256/128 (shared Keccak-f[1600] core)
    // Channel A = SHAKE-256, Channel B = SHAKE-128
    // =========================================================================
    wire        shake_init_w, shake_wr_en_w;
    wire [4:0]  shake_wr_lane_idx_w, shake_rd_lane_idx_w;
    wire [63:0] shake_wr_lane_data_w, shake_rd_lane_data_w;
    wire        shake_pad_and_permute_w, shake_permute_w;
    wire        shake_busy_w, shake_rdy_w;

    wire        s128_init_w, s128_wr_en_w;
    wire [4:0]  s128_wr_lane_idx_w, s128_rd_lane_idx_w;
    wire [63:0] s128_wr_lane_data_w, s128_rd_lane_data_w;
    wire        s128_pad_and_permute_w, s128_permute_w;
    wire        s128_busy_w, s128_rdy_w;

    shake_unified u_shake (
        .clk               (clk),              .rst_n             (rst_n),
        // Channel A (SHAKE-256)
        .a_init            (shake_init_w),      .a_wr_en           (shake_wr_en_w),
        .a_wr_lane_idx     (shake_wr_lane_idx_w),
        .a_wr_lane_data    (shake_wr_lane_data_w),
        .a_pad_and_permute (shake_pad_and_permute_w),
        .a_permute         (shake_permute_w),
        .a_rd_lane_idx     (shake_rd_lane_idx_w),
        .a_rd_lane_data    (shake_rd_lane_data_w),
        .a_busy            (shake_busy_w),      .a_rdy             (shake_rdy_w),
        // Channel B (SHAKE-128)
        .b_init            (s128_init_w),       .b_wr_en           (s128_wr_en_w),
        .b_wr_lane_idx     (s128_wr_lane_idx_w),
        .b_wr_lane_data    (s128_wr_lane_data_w),
        .b_pad_and_permute (s128_pad_and_permute_w),
        .b_permute         (s128_permute_w),
        .b_rd_lane_idx     (s128_rd_lane_idx_w),
        .b_rd_lane_data    (s128_rd_lane_data_w),
        .b_busy            (s128_busy_w),       .b_rdy             (s128_rdy_w)
    );

    // =========================================================================
    // KEYGEN Controller
    // =========================================================================
    wire kg_done_w, kg_busy_w;
    wire kg_ntt_start_w, kg_ntt_intt_w, kg_ntt_ext_we_w;
    wire [7:0]               kg_ntt_ext_addr_w;
    wire [`MLDSA_QBITS-1:0] kg_ntt_ext_din_w;
    wire kg_shake_init_w, kg_shake_wr_en_w, kg_shake_permute_w, kg_shake_pap_w;
    wire [4:0]  kg_shake_wr_idx_w, kg_shake_rd_idx_w;
    wire [63:0] kg_shake_wr_data_w;
    // (keygen write wires forward-declared above)

    // SHAKE-128 signals from keygen
    wire        kg_s128_init_w, kg_s128_wr_en_w;
    wire [4:0]  kg_s128_wr_idx_w, kg_s128_rd_idx_w;
    wire [63:0] kg_s128_wr_data_w;
    wire        kg_s128_pap_w, kg_s128_permute_w;

    (* DONT_TOUCH = "TRUE" *)
    keygen_ctrl u_keygen (
        .clk                   (clk),          .rst_n               (rst_n),
        .start                 (start_keygen), .done                (kg_done_w),
        .busy                  (kg_busy_w),    .seed_xi             (seed_xi),
        .seed_valid            (1'b1),
        // NTT
        .ntt_start             (kg_ntt_start_w),
        .ntt_intt_mode         (kg_ntt_intt_w),
        .ntt_done              (ntt_done_w),   .ntt_busy            (ntt_busy_w),
        .ntt_ext_we            (kg_ntt_ext_we_w),
        .ntt_ext_addr          (kg_ntt_ext_addr_w),
        .ntt_ext_din           (kg_ntt_ext_din_w),
        .ntt_ext_dout          (ntt_ext_dout_w),
        // SHAKE-256
        .shake_init            (kg_shake_init_w),
        .shake_wr_en           (kg_shake_wr_en_w),
        .shake_wr_lane_idx     (kg_shake_wr_idx_w),
        .shake_wr_lane_data    (kg_shake_wr_data_w),
        .shake_permute         (kg_shake_permute_w),
        .shake_pad_and_permute (kg_shake_pap_w),
        .shake_rd_lane_data    (shake_rd_lane_data_w),
        .shake_rd_lane_idx     (kg_shake_rd_idx_w),
        .shake_busy            (shake_busy_w), .shake_rdy           (shake_rdy_w),
        // SHAKE-128
        .s128_init             (kg_s128_init_w),
        .s128_wr_en            (kg_s128_wr_en_w),
        .s128_wr_lane_idx      (kg_s128_wr_idx_w),
        .s128_wr_lane_data     (kg_s128_wr_data_w),
        .s128_pad_and_permute  (kg_s128_pap_w),
        .s128_permute          (kg_s128_permute_w),
        .s128_rd_lane_data     (s128_rd_lane_data_w),
        .s128_rd_lane_idx      (kg_s128_rd_idx_w),
        .s128_busy             (s128_busy_w),  .s128_rdy            (s128_rdy_w),
        // Output
        .pk_we                 (kg_pk_we_w),   .pk_addr             (kg_pk_addr_w),
        .pk_wdata              (kg_pk_wdata_w),.sk_we               (kg_sk_we_w),
        .sk_addr               (kg_sk_addr_w), .sk_wdata            (kg_sk_wdata_w)
    );

    // =========================================================================
    // SIGN Controller
    // =========================================================================
    wire sg_done_w, sg_busy_w, sg_sigvalid_w;
    wire sg_ntt_start_w, sg_ntt_intt_w;
    wire sg_shake_init_w, sg_shake_pap_w, sg_shake_permute_w;
    wire sg_shake_wr_en_w;
    wire [4:0]  sg_shake_wr_idx_w, sg_shake_rd_idx_w;
    wire [63:0] sg_shake_wr_data_w;
    wire sg_ntt_ext_we_w;
    wire [7:0]  sg_ntt_ext_addr_w;
    wire [`MLDSA_QBITS-1:0] sg_ntt_ext_din_w;
    wire [15:0] sg_kappa_w;
    wire [7:0]  sg_z_addr_w, sg_r0_addr_w;

    wire [`MLDSA_QBITS-1:0] sg_z_rdata  = poly_z_ram [sg_z_addr_w][`MLDSA_QBITS-1:0];
    wire [`MLDSA_QBITS-1:0] sg_r0_rdata = poly_r0_ram[sg_r0_addr_w][`MLDSA_QBITS-1:0];

    sign_ctrl u_sign (
        .clk                   (clk),          .rst_n               (rst_n),
        .start                 (start_sign),   .done                (sg_done_w),
        .busy                  (sg_busy_w),    .sk_rho              (sk_rho),
        .sk_K                  (sk_K),         .sk_tr               (sk_tr),
        .mu                    (mu_w),         .mu_valid            (1'b1),
        .rnd                   (rnd_w),
        .ntt_start             (sg_ntt_start_w),
        .ntt_intt_mode         (sg_ntt_intt_w),
        .ntt_done              (ntt_done_w),   .ntt_busy            (ntt_busy_w),
        .shake_init            (sg_shake_init_w),
        .shake_wr_en           (sg_shake_wr_en_w),
        .shake_wr_lane_idx     (sg_shake_wr_idx_w),
        .shake_wr_lane_data    (sg_shake_wr_data_w),
        .shake_pad_and_permute (sg_shake_pap_w),
        .shake_permute         (sg_shake_permute_w),
        .shake_rd_lane_idx     (sg_shake_rd_idx_w),
        .shake_rd_lane_data    (shake_rd_lane_data_w),
        .shake_rdy             (shake_rdy_w),
        .ntt_ext_we            (sg_ntt_ext_we_w),
        .ntt_ext_addr          (sg_ntt_ext_addr_w),
        .ntt_ext_din           (sg_ntt_ext_din_w),
        .ntt_ext_dout          (ntt_ext_dout_w),
        .z_coeff_addr          (sg_z_addr_w),  .z_coeff_rdata       (sg_z_rdata),
        .r0_coeff_addr         (sg_r0_addr_w), .r0_coeff_rdata      (sg_r0_rdata),
        .sig_valid             (sg_sigvalid_w),.kappa_out           (sg_kappa_w)
    );

    // =========================================================================
    // VERIFY Controller
    // =========================================================================
    wire vf_done_w, vf_busy_w, vf_valid_w;
    wire vf_ntt_start_w, vf_ntt_intt_w;
    wire vf_shake_init_w, vf_shake_pap_w, vf_shake_permute_w;
    wire vf_shake_wr_en_w;
    wire [4:0]  vf_shake_wr_idx_w, vf_shake_rd_idx_w;
    wire [63:0] vf_shake_wr_data_w;
    wire vf_ntt_ext_we_w;
    wire [7:0]  vf_ntt_ext_addr_w;
    wire [`MLDSA_QBITS-1:0] vf_ntt_ext_din_w;
    wire [7:0] vf_z_addr_w;

    wire [`MLDSA_QBITS-1:0] vf_z_rdata = poly_z_ram[vf_z_addr_w][`MLDSA_QBITS-1:0];

    verify_ctrl u_verify (
        .clk                   (clk),          .rst_n               (rst_n),
        .start                 (start_verify), .done                (vf_done_w),
        .busy                  (vf_busy_w),    .valid               (vf_valid_w),
        .pk_tr                 (sk_tr),        .mu                  (mu_w),
        .mu_valid              (1'b1),
        .ntt_start             (vf_ntt_start_w),
        .ntt_intt_mode         (vf_ntt_intt_w),
        .ntt_done              (ntt_done_w),   .ntt_busy            (ntt_busy_w),
        .shake_init            (vf_shake_init_w),
        .shake_wr_en           (vf_shake_wr_en_w),
        .shake_wr_lane_idx     (vf_shake_wr_idx_w),
        .shake_wr_lane_data    (vf_shake_wr_data_w),
        .shake_pad_and_permute (vf_shake_pap_w),
        .shake_permute         (vf_shake_permute_w),
        .shake_rd_lane_idx     (vf_shake_rd_idx_w),
        .shake_rd_lane_data    (shake_rd_lane_data_w),
        .shake_rdy             (shake_rdy_w),
        .ntt_ext_we            (vf_ntt_ext_we_w),
        .ntt_ext_addr          (vf_ntt_ext_addr_w),
        .ntt_ext_din           (vf_ntt_ext_din_w),
        .ntt_ext_dout          (ntt_ext_dout_w),
        .z_coeff_addr          (vf_z_addr_w),  .z_coeff_rdata       (vf_z_rdata),
        .c_tilde_orig          (c_tilde_orig_w),
        .c_tilde_prime         (256'd0)
    );

    // =========================================================================
    // NTT / SHAKE-256 / SHAKE-128 bus arbitration
    // OR-mux is safe: ctrl_reg is one-hot and auto-clears so only
    // one controller is ever active at a time.
    // =========================================================================
    // NTT arbitration
    assign ntt_start_w            = kg_ntt_start_w  | sg_ntt_start_w  | vf_ntt_start_w;
    assign ntt_intt_mode_w        = kg_ntt_intt_w   | sg_ntt_intt_w   | vf_ntt_intt_w;
    assign ntt_ext_we_w           = kg_ntt_ext_we_w | sg_ntt_ext_we_w | vf_ntt_ext_we_w;
    assign ntt_ext_addr_w         = kg_busy_w ? kg_ntt_ext_addr_w :
                                    sg_busy_w ? sg_ntt_ext_addr_w : vf_ntt_ext_addr_w;
    assign ntt_ext_din_w          = kg_busy_w ? kg_ntt_ext_din_w :
                                    sg_busy_w ? sg_ntt_ext_din_w  : vf_ntt_ext_din_w;

    // SHAKE-256 arbitration
    assign shake_init_w           = kg_shake_init_w | sg_shake_init_w | vf_shake_init_w;
    assign shake_wr_en_w          = kg_shake_wr_en_w | sg_shake_wr_en_w | vf_shake_wr_en_w;
    assign shake_wr_lane_idx_w    = kg_busy_w ? kg_shake_wr_idx_w :
                                    sg_busy_w ? sg_shake_wr_idx_w : vf_shake_wr_idx_w;
    assign shake_wr_lane_data_w   = kg_busy_w ? kg_shake_wr_data_w :
                                    sg_busy_w ? sg_shake_wr_data_w : vf_shake_wr_data_w;
    assign shake_pad_and_permute_w= kg_shake_pap_w  | sg_shake_pap_w  | vf_shake_pap_w;
    assign shake_permute_w        = kg_shake_permute_w | sg_shake_permute_w | vf_shake_permute_w;
    assign shake_rd_lane_idx_w    = kg_busy_w ? kg_shake_rd_idx_w :
                                    sg_busy_w ? sg_shake_rd_idx_w : vf_shake_rd_idx_w;

    // SHAKE-128 arbitration (currently only keygen uses it)
    assign s128_init_w            = kg_s128_init_w;
    assign s128_wr_en_w           = kg_s128_wr_en_w;
    assign s128_wr_lane_idx_w     = kg_s128_wr_idx_w;
    assign s128_wr_lane_data_w    = kg_s128_wr_data_w;
    assign s128_pad_and_permute_w = kg_s128_pap_w;
    assign s128_permute_w         = kg_s128_permute_w;
    assign s128_rd_lane_idx_w     = kg_s128_rd_idx_w;

    // =========================================================================
    // Status
    // =========================================================================
    wire core_busy   = kg_busy_w   | sg_busy_w   | vf_busy_w;
    wire core_done   = kg_done_w   | sg_done_w   | vf_done_w;
    wire sig_valid_w = sg_sigvalid_w | vf_valid_w;

    // Sticky done flag
    reg done_sticky;
    reg valid_sticky;
    always @(posedge clk) begin
        if (!rst_n) begin
            done_sticky  <= 1'b0;
            valid_sticky <= 1'b0;
        end else if (core_done) begin
            done_sticky  <= 1'b1;
            valid_sticky <= sig_valid_w;
        end else if (ctrl_reg[0] || ctrl_reg[1] || ctrl_reg[2]) begin
            done_sticky  <= 1'b0;
            valid_sticky <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Write Channel
    // =========================================================================
    reg aw_done, w_done;
    reg [15:0] aw_addr_lat;

    wire wr_poly_z  = (aw_addr_lat[15:10] == 6'b000100); // 0x1000-0x13FC
    wire wr_poly_r0 = (aw_addr_lat[15:10] == 6'b000101); // 0x1400-0x17FC
    wire [7:0] poly_wr_idx = aw_addr_lat[9:2];

    always @(posedge clk) begin
        if (!rst_n) begin
            AWREADY <= 1'b0; WREADY <= 1'b0; BVALID <= 1'b0;
            BRESP   <= 2'b00; aw_done <= 1'b0; w_done <= 1'b0;
            aw_addr_lat <= 16'd0; ctrl_reg <= 32'd0;
        end else begin
            if (BVALID && BREADY)   BVALID <= 1'b0;

            if (AWVALID && !aw_done) begin
                AWREADY <= 1'b1; aw_addr_lat <= AWADDR; aw_done <= 1'b1;
            end else AWREADY <= 1'b0;

            if (WVALID && !w_done) begin
                WREADY <= 1'b1; w_done <= 1'b1;
            end else WREADY <= 1'b0;

            if (aw_done && w_done) begin
                aw_done <= 1'b0; w_done <= 1'b0;
                BVALID  <= 1'b1; BRESP  <= 2'b00;

                if      (wr_poly_z)  poly_z_ram [poly_wr_idx] <= WDATA;
                else if (wr_poly_r0) poly_r0_ram[poly_wr_idx] <= WDATA;
                else case (aw_addr_lat[7:0])
                    8'h00: ctrl_reg      <= WDATA;
                    // seed_xi
                    8'h10: seed_reg[0]   <= WDATA; 8'h14: seed_reg[1] <= WDATA;
                    8'h18: seed_reg[2]   <= WDATA; 8'h1C: seed_reg[3] <= WDATA;
                    8'h20: seed_reg[4]   <= WDATA; 8'h24: seed_reg[5] <= WDATA;
                    8'h28: seed_reg[6]   <= WDATA; 8'h2C: seed_reg[7] <= WDATA;
                    // sk_rho
                    8'h30: rho_reg[0]    <= WDATA; 8'h34: rho_reg[1]  <= WDATA;
                    8'h38: rho_reg[2]    <= WDATA; 8'h3C: rho_reg[3]  <= WDATA;
                    8'h40: rho_reg[4]    <= WDATA; 8'h44: rho_reg[5]  <= WDATA;
                    8'h48: rho_reg[6]    <= WDATA; 8'h4C: rho_reg[7]  <= WDATA;
                    // sk_K
                    8'h50: K_reg[0]      <= WDATA; 8'h54: K_reg[1]    <= WDATA;
                    8'h58: K_reg[2]      <= WDATA; 8'h5C: K_reg[3]    <= WDATA;
                    8'h60: K_reg[4]      <= WDATA; 8'h64: K_reg[5]    <= WDATA;
                    8'h68: K_reg[6]      <= WDATA; 8'h6C: K_reg[7]    <= WDATA;
                    // sk_tr
                    8'h70: tr_reg[0]     <= WDATA; 8'h74: tr_reg[1]   <= WDATA;
                    8'h78: tr_reg[2]     <= WDATA; 8'h7C: tr_reg[3]   <= WDATA;
                    8'h80: tr_reg[4]     <= WDATA; 8'h84: tr_reg[5]   <= WDATA;
                    8'h88: tr_reg[6]     <= WDATA; 8'h8C: tr_reg[7]   <= WDATA;
                    // rnd
                    8'h90: rnd_reg[0]    <= WDATA; 8'h94: rnd_reg[1]  <= WDATA;
                    8'h98: rnd_reg[2]    <= WDATA; 8'h9C: rnd_reg[3]  <= WDATA;
                    8'hA0: rnd_reg[4]    <= WDATA; 8'hA4: rnd_reg[5]  <= WDATA;
                    8'hA8: rnd_reg[6]    <= WDATA; 8'hAC: rnd_reg[7]  <= WDATA;
                    // c_tilde_orig
                    8'hB0: ctilde_reg[0] <= WDATA; 8'hB4: ctilde_reg[1] <= WDATA;
                    8'hB8: ctilde_reg[2] <= WDATA; 8'hBC: ctilde_reg[3] <= WDATA;
                    8'hC0: ctilde_reg[4] <= WDATA; 8'hC4: ctilde_reg[5] <= WDATA;
                    8'hC8: ctilde_reg[6] <= WDATA; 8'hCC: ctilde_reg[7] <= WDATA;
                    // mu[255:0]
                    8'hD0: mu_lo_reg[0]  <= WDATA; 8'hD4: mu_lo_reg[1] <= WDATA;
                    8'hD8: mu_lo_reg[2]  <= WDATA; 8'hDC: mu_lo_reg[3] <= WDATA;
                    8'hE0: mu_lo_reg[4]  <= WDATA; 8'hE4: mu_lo_reg[5] <= WDATA;
                    8'hE8: mu_lo_reg[6]  <= WDATA; 8'hEC: mu_lo_reg[7] <= WDATA;
                    // mu[511:256]
                    8'hF0: mu_hi_reg[0]  <= WDATA; 8'hF4: mu_hi_reg[1] <= WDATA;
                    8'hF8: mu_hi_reg[2]  <= WDATA; 8'hFC: mu_hi_reg[3] <= WDATA;
                    default: ;
                endcase
            end

            if (ctrl_reg[0]) ctrl_reg[0] <= 1'b0;
            if (ctrl_reg[1]) ctrl_reg[1] <= 1'b0;
            if (ctrl_reg[2]) ctrl_reg[2] <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Read Channel
    // =========================================================================
    // Status register: [0]=busy, [1]=done_sticky, [2]=sig_valid
    wire [31:0] status_word = {29'd0, valid_sticky, done_sticky, core_busy};

    wire       rd_poly_z   = (ARADDR[15:10] == 6'b000100);  // 0x1000-0x13FC
    wire       rd_poly_r0  = (ARADDR[15:10] == 6'b000101);  // 0x1400-0x17FC
    wire       rd_pk       = (ARADDR[15:12] == 4'b0000) && (ARADDR[11:10] == 2'b10);  // 0x0800-0x0BFF
    wire       rd_sk       = (ARADDR[15:12] == 4'b0000) && (ARADDR[11:10] == 2'b11);  // 0x0C00-0x0FFF
    wire [7:0] poly_rd_idx = ARADDR[9:2];
    wire [10:0] pk_rd_idx  = ARADDR[10:2];
    wire [11:0] sk_rd_idx  = ARADDR[11:2];

    // Pack 4 bytes from PK RAM into 32-bit word
    reg [31:0] pk_word_buf;
    always @(posedge clk) begin
        if (rd_pk)
            pk_word_buf <= {pk_ram[ARADDR[10:2]+3], pk_ram[ARADDR[10:2]+2],
                            pk_ram[ARADDR[10:2]+1], pk_ram[ARADDR[10:2]+0]};
    end

    // Pack 4 bytes from SK RAM into 32-bit word
    reg [31:0] sk_word_buf;
    always @(posedge clk) begin
        if (rd_sk)
            sk_word_buf <= {sk_ram[ARADDR[11:2]+3], sk_ram[ARADDR[11:2]+2],
                            sk_ram[ARADDR[11:2]+1], sk_ram[ARADDR[11:2]+0]};
    end

    always @(posedge clk) begin
        if (!rst_n) begin
            ARREADY <= 1'b0; RVALID <= 1'b0; RDATA <= 32'd0; RRESP <= 2'b00;
        end else begin
            if (RVALID && RREADY) RVALID <= 1'b0;

            if (ARVALID && !RVALID) begin
                ARREADY <= 1'b1; RVALID <= 1'b1; RRESP <= 2'b00;
                if      (rd_poly_z)  RDATA <= poly_z_ram [poly_rd_idx];
                else if (rd_poly_r0) RDATA <= poly_r0_ram[poly_rd_idx];
                else if (rd_pk)      RDATA <= pk_word_buf;
                else if (rd_sk)      RDATA <= sk_word_buf;
                else case (ARADDR[7:0])
                    8'h00:  RDATA <= ctrl_reg;
                    8'h04:  RDATA <= status_word;
                    8'h10:  RDATA <= seed_reg[0]; 8'h14: RDATA <= seed_reg[1];
                    8'h18:  RDATA <= seed_reg[2]; 8'h1C: RDATA <= seed_reg[3];
                    8'h20:  RDATA <= seed_reg[4]; 8'h24: RDATA <= seed_reg[5];
                    8'h28:  RDATA <= seed_reg[6]; 8'h2C: RDATA <= seed_reg[7];
                    default: RDATA <= 32'hDEAD_BEEF;
                endcase
            end else ARREADY <= 1'b0;
        end
    end

endmodule
