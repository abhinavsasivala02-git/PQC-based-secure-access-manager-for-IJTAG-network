//============================================================================
// ML-KEM Encapsulation Top Level for Vivado Synthesis
// Target: Artix-7 7a35tcpg236-1
//============================================================================
`timescale 1ns/1ps

module mlkem_encaps_top #(
    parameter K    = 3,
    parameter ETA2 = 2,
    parameter DU   = 10,
    parameter DV   = 4
)(
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    output wire         done,
    output wire         busy,
    input  wire [255:0] m_seed,    // 32-byte random message from TRNG
    input  wire [255:0] r_seed,    // 32-byte randomness H(m||H(ek))
    output wire [12:0]  ek_addr,
    input  wire [7:0]   ek_rdata,
    output wire         ct_valid,
    output wire [7:0]   ct_data,
    output wire [12:0]  ct_addr
);

    //=========================================================================
    // Shared Hash Engine
    //=========================================================================
    wire [7:0]  hash_cfg_rate, hash_cfg_domain;
    wire        hash_init, hash_absorb_valid, hash_absorb_ready;
    wire [7:0]  hash_absorb_data;
    wire        hash_absorb_last, hash_squeeze_valid;
    wire [7:0]  hash_squeeze_data;
    wire        hash_squeeze_next, hash_busy;

    mlkem_hash_engine_cfg u_hash (
        .clk            (clk),
        .rst_n          (rst_n),
        .cfg_rate_bytes (hash_cfg_rate),
        .cfg_domain_sep (hash_cfg_domain),
        .init           (hash_init),
        .absorb_valid   (hash_absorb_valid),
        .absorb_data    (hash_absorb_data),
        .absorb_ready   (hash_absorb_ready),
        .absorb_last    (hash_absorb_last),
        .squeeze_valid  (hash_squeeze_valid),
        .squeeze_data   (hash_squeeze_data),
        .squeeze_next   (hash_squeeze_next),
        .busy           (hash_busy)
    );

    //=========================================================================
    // Shared NTT Core
    //=========================================================================
    wire        ntt_start, ntt_mode, ntt_done, ntt_busy;
    wire        ntt_ram_wen;
    wire [7:0]  ntt_ram_addr_a, ntt_ram_addr_b;
    wire [11:0] ntt_ram_wdata_a, ntt_ram_rdata_a, ntt_ram_rdata_b;

    mlkem_ntt_core u_ntt (
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (ntt_start),
        .mode       (ntt_mode),
        .done       (ntt_done),
        .busy       (ntt_busy),
        .ram_wen    (ntt_ram_wen),
        .ram_addr_a (ntt_ram_addr_a),
        .ram_wdata_a(ntt_ram_wdata_a),
        .ram_rdata_a(ntt_ram_rdata_a),
        .ram_addr_b (ntt_ram_addr_b),
        .ram_rdata_b(ntt_ram_rdata_b)
    );

    //=========================================================================
    // Shared Poly Basemul
    //=========================================================================
    wire        bmul_start, bmul_done, bmul_busy;
    wire [7:0]  bmul_a_addr, bmul_b_addr, bmul_c_addr;
    wire [11:0] bmul_a_rdata, bmul_b_rdata;
    wire        bmul_c_wen;
    wire [11:0] bmul_c_wdata;

    poly_basemul u_basemul (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (bmul_start),
        .done   (bmul_done),
        .busy   (bmul_busy),
        .a_addr (bmul_a_addr),
        .a_rdata(bmul_a_rdata),
        .b_addr (bmul_b_addr),
        .b_rdata(bmul_b_rdata),
        .c_wen  (bmul_c_wen),
        .c_addr (bmul_c_addr),
        .c_wdata(bmul_c_wdata)
    );

    //=========================================================================
    // Shared Poly Arith
    //=========================================================================
    wire        arith_start, arith_done, arith_busy;
    wire [1:0]  arith_mode;
    wire [7:0]  arith_a_addr, arith_b_addr, arith_c_addr;
    wire [11:0] arith_a_rdata, arith_b_rdata;
    wire        arith_c_wen;
    wire [11:0] arith_c_wdata;

    mlkem_poly_arith u_arith (
        .clk    (clk),
        .rst_n  (rst_n),
        .start  (arith_start),
        .mode   (arith_mode),
        .done   (arith_done),
        .busy   (arith_busy),
        .a_addr (arith_a_addr),
        .a_rdata(arith_a_rdata),
        .b_addr (arith_b_addr),
        .b_rdata(arith_b_rdata),
        .c_wen  (arith_c_wen),
        .c_addr (arith_c_addr),
        .c_wdata(arith_c_wdata)
    );

    //=========================================================================
    // K-PKE Encrypt Core
    //=========================================================================
    kpke_encrypt_shared #(
        .K(K), .ETA2(ETA2), .DU(DU), .DV(DV)
    ) u_encaps (
        .clk               (clk),
        .rst_n             (rst_n),
        .start             (start),
        .m_in              (m_seed),
        .r_seed            (r_seed),
        .ek_addr           (ek_addr),
        .ek_rdata          (ek_rdata),
        .ct_valid          (ct_valid),
        .ct_data           (ct_data),
        .ct_addr           (ct_addr),
        .done              (done),
        .busy              (busy),
        .hash_cfg_rate     (hash_cfg_rate),
        .hash_cfg_domain   (hash_cfg_domain),
        .hash_init         (hash_init),
        .hash_absorb_valid (hash_absorb_valid),
        .hash_absorb_data  (hash_absorb_data),
        .hash_absorb_ready (hash_absorb_ready),
        .hash_absorb_last  (hash_absorb_last),
        .hash_squeeze_valid(hash_squeeze_valid),
        .hash_squeeze_data (hash_squeeze_data),
        .hash_squeeze_next (hash_squeeze_next),
        .hash_busy         (hash_busy),
        .ntt_start         (ntt_start),
        .ntt_mode          (ntt_mode),
        .ntt_done          (ntt_done),
        .ntt_busy          (ntt_busy),
        .ntt_ram_wen       (ntt_ram_wen),
        .ntt_ram_addr_a    (ntt_ram_addr_a),
        .ntt_ram_wdata_a   (ntt_ram_wdata_a),
        .ntt_ram_rdata_a   (ntt_ram_rdata_a),
        .ntt_ram_addr_b    (ntt_ram_addr_b),
        .ntt_ram_rdata_b   (ntt_ram_rdata_b),
        .bmul_start        (bmul_start),
        .bmul_done         (bmul_done),
        .bmul_busy         (bmul_busy),
        .bmul_a_addr       (bmul_a_addr),
        .bmul_a_rdata      (bmul_a_rdata),
        .bmul_b_addr       (bmul_b_addr),
        .bmul_b_rdata      (bmul_b_rdata),
        .bmul_c_wen        (bmul_c_wen),
        .bmul_c_addr       (bmul_c_addr),
        .bmul_c_wdata      (bmul_c_wdata),
        .arith_start       (arith_start),
        .arith_mode        (arith_mode),
        .arith_done        (arith_done),
        .arith_busy        (arith_busy),
        .arith_a_addr      (arith_a_addr),
        .arith_a_rdata     (arith_a_rdata),
        .arith_b_addr      (arith_b_addr),
        .arith_b_rdata     (arith_b_rdata),
        .arith_c_wen       (arith_c_wen),
        .arith_c_addr      (arith_c_addr),
        .arith_c_wdata     (arith_c_wdata)
    );

endmodule
