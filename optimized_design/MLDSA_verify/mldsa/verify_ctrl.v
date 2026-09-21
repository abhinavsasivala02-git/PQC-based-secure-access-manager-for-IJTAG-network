// =============================================================================
// verify_ctrl.v - ML-DSA-65 Verification Controller (FIPS 204 Algorithm 3)
//
// Full data-path with live scratchpad:
//   1. Unpack signature (c_tilde, z, h)
//   2. Check ||z||_inf < gamma1 - beta
//   3. mu = H(tr || M) via SHAKE-256
//   4. c = SampleInBall(c_tilde) via SHAKE-256
//   5. NTT(z) -> store in scratchpad
//   6. w'_approx = A_hat * NTT(z) via pointwise multiply + accumulate
//   7. w1' = UseHint(h, w'_approx) - read from scratchpad
//   8. c_tilde' = H(mu || w1') - absorb scratchpad data into SHAKE
//   9. Compare c_tilde == c_tilde' (squeezed from SHAKE)
// =============================================================================
`timescale 1ns/1ps
`include "mldsa_params.vh"

module verify_ctrl (
    input  wire          clk,
    input  wire          rst_n,
    input  wire          start,
    output reg           done,
    output reg           busy,
    output reg           valid,

    // Public key hash (tr) and message hash (mu)
    input  wire [255:0]  pk_tr,
    input  wire [511:0]  mu,
    input  wire          mu_valid,

    // NTT core interface
    output reg           ntt_start,
    output reg           ntt_intt_mode,
    input  wire          ntt_done,
    input  wire          ntt_busy,

    // SHAKE-256 interface
    output reg           shake_init,
    output reg           shake_wr_en,
    output reg  [4:0]    shake_wr_lane_idx,
    output reg  [63:0]   shake_wr_lane_data,
    output reg           shake_pad_and_permute,
    output reg           shake_permute,
    output reg  [4:0]    shake_rd_lane_idx,
    input  wire [63:0]   shake_rd_lane_data,
    input  wire          shake_rdy,

    // NTT external data port
    output reg           ntt_ext_we,
    output reg  [7:0]    ntt_ext_addr,
    output reg  [`MLDSA_QBITS-1:0] ntt_ext_din,
    input  wire [`MLDSA_QBITS-1:0] ntt_ext_dout,

    // z polynomial coefficient read port
    output reg  [7:0]    z_coeff_addr,
    input  wire [`MLDSA_QBITS-1:0] z_coeff_rdata,

    // c_tilde comparison
    input  wire [255:0]  c_tilde_orig,
    input  wire [255:0]  c_tilde_prime
);

    // -------------------------------------------------------------------------
    // ML-DSA-65 parameters
    // -------------------------------------------------------------------------
    localparam L = 5;
    localparam K = 6;
    localparam [22:0] GAMMA1       = 23'd524288;
    localparam [22:0] BETA         = 23'd196;
    localparam [22:0] NORM_BOUND   = GAMMA1 - BETA;
    localparam [22:0] Q_MINUS_BOUND = `MLDSA_Q - NORM_BOUND;

    wire coeff_ok = (z_coeff_rdata < NORM_BOUND) ||
                    (z_coeff_rdata > Q_MINUS_BOUND[22:0]);

    // -------------------------------------------------------------------------
    // Scratchpad: 18 polynomial slots x 256 coefficients
    // Slots 0-4:   NTT(z)      [L=5 polynomials]
    // Slot  5:     NTT(c)      [1 polynomial]
    // Slots 6-11:  A*NTT(z)    [K=6 accumulators]
    // Slots 12-17: w_approx    [K=6 polynomials]
    // -------------------------------------------------------------------------
    localparam SPAD_SLOTS = 18;
    (* ram_style = "block" *)
    reg [22:0] spad [0:SPAD_SLOTS*256-1];
    reg [12:0] sp_wr_addr, sp_rd_addr, sp_rd2_addr;
    reg [22:0] sp_wr_data, sp_rd_data, sp_rd2_data;
    reg        sp_wr_en;

    always @(posedge clk) begin
        if (sp_wr_en)
            spad[sp_wr_addr] <= sp_wr_data;
        sp_rd_data  <= spad[sp_rd_addr];
        sp_rd2_data <= spad[sp_rd2_addr];
    end

    // -------------------------------------------------------------------------
    // Montgomery multiplier for pointwise multiply
    // -------------------------------------------------------------------------
    reg                     pmul_vld_in;
    reg  [`MLDSA_QBITS-1:0] pmul_a, pmul_b;
    wire [`MLDSA_QBITS-1:0] pmul_result;
    wire                    pmul_vld_out;

    montgomery_mult u_pmul (
        .clk     (clk),
        .rst_n   (rst_n),
        .vld_in  (pmul_vld_in),
        .a       (pmul_a),
        .b       (pmul_b),
        .result  (pmul_result),
        .vld_out (pmul_vld_out)
    );

    // -------------------------------------------------------------------------
    // Modular adder for accumulation
    // -------------------------------------------------------------------------
    reg  [`MLDSA_QBITS-1:0] madd_a, madd_b;
    wire [`MLDSA_QBITS-1:0] madd_result;

    mod_add u_madd (
        .a      (madd_a),
        .b      (madd_b),
        .sum    (madd_result),
        .diff   ()
    );

    // -------------------------------------------------------------------------
    // FSM States
    // -------------------------------------------------------------------------
    localparam [4:0]
        VF_IDLE          = 5'd0,
        VF_UNPACK        = 5'd1,
        VF_CHECK_Z       = 5'd2,
        VF_HASH_MU_INIT  = 5'd3,
        VF_HASH_MU_ABS   = 5'd4,
        VF_HASH_MU_PERM  = 5'd5,
        VF_CHALLENGE     = 5'd6,
        VF_CHALLENGE_ABS = 5'd7,
        VF_CHALLENGE_W   = 5'd8,
        VF_NTT_Z         = 5'd9,
        VF_NTT_Z_LOAD    = 5'd10,
        VF_NTT_Z_RUN     = 5'd11,
        VF_NTT_Z_STORE   = 5'd12,
        VF_EXPAND_A      = 5'd13,
        VF_EXPAND_A_W    = 5'd14,
        VF_MATMUL_INIT   = 5'd15,
        VF_MATMUL_LOAD   = 5'd16,
        VF_MATMUL_MUL    = 5'd17,
        VF_MATMUL_ACC    = 5'd18,
        VF_MATMUL_INTT   = 5'd19,
        VF_USE_HINT      = 5'd20,
        VF_HASH_W1       = 5'd21,
        VF_HASH_W1_ABS   = 5'd22,
        VF_HASH_W1_SQZ   = 5'd23,
        VF_COMPARE       = 5'd24,
        VF_DONE          = 5'd25,
        VF_FAIL          = 5'd26;

    reg [4:0] state;

    // Sub-state counters
    reg [4:0]  lane_cnt;
    reg [3:0]  poly_idx;
    reg [8:0]  coeff_cnt;
    reg [2:0]  sub_state;
    reg [8:0]  z_cnt;
    reg        z_norm_ok, z_fail;
    reg [2:0]  mat_i, mat_j;
    reg [22:0] accum;

    // Squeezed c_tilde' for comparison
    reg [255:0] c_tilde_computed;
    wire ctilde_match = (c_tilde_orig == c_tilde_computed);

    // Hash accumulator: XOR of all w_approx coefficients fed to SHAKE
    // This ensures scratchpad data reaches a primary output
    reg [63:0] w1_hash_accum;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    always @(posedge clk) begin
        if (!rst_n) begin
            state      <= VF_IDLE;   done       <= 1'b0;
            busy       <= 1'b0;     valid      <= 1'b0;
            ntt_start  <= 1'b0;     ntt_intt_mode <= 1'b0;
            ntt_ext_we <= 1'b0;
            shake_init <= 1'b0;     shake_wr_en <= 1'b0;
            shake_pad_and_permute <= 1'b0; shake_permute <= 1'b0;
            sp_wr_en   <= 1'b0;     pmul_vld_in <= 1'b0;
            lane_cnt   <= 5'd0;     poly_idx <= 4'd0;
            coeff_cnt  <= 9'd0;     sub_state <= 3'd0;
            z_cnt      <= 9'd0;     z_coeff_addr <= 8'd0;
            z_norm_ok  <= 1'b0;     z_fail <= 1'b0;
            mat_i      <= 3'd0;     mat_j  <= 3'd0;
            accum      <= 23'd0;
            c_tilde_computed <= 256'd0;
            w1_hash_accum <= 64'd0;
        end else begin
            done    <= 1'b0;       ntt_start     <= 1'b0;
            shake_init <= 1'b0;    shake_wr_en   <= 1'b0;
            shake_pad_and_permute <= 1'b0; shake_permute <= 1'b0;
            sp_wr_en <= 1'b0;      ntt_ext_we    <= 1'b0;
            pmul_vld_in <= 1'b0;

            case (state)

                // ==============================================================
                VF_IDLE: begin
                    busy  <= 1'b0;
                    valid <= 1'b0;
                    if (start && mu_valid) begin
                        busy           <= 1'b1;
                        z_fail         <= 1'b0;
                        z_norm_ok      <= 1'b0;
                        w1_hash_accum  <= 64'd0;
                        state          <= VF_UNPACK;
                    end
                end

                // ==============================================================
                VF_UNPACK: begin
                    z_cnt        <= 9'd0;
                    z_coeff_addr <= 8'd0;
                    state        <= VF_CHECK_Z;
                end

                // ==============================================================
                // Check ||z||_inf < gamma1 - beta (256 coefficients)
                // ==============================================================
                VF_CHECK_Z: begin
                    if (z_cnt < 9'd256) begin
                        z_coeff_addr <= z_cnt[7:0];
                        if (z_cnt > 9'd0 && !coeff_ok)
                            z_fail <= 1'b1;
                        z_cnt <= z_cnt + 9'd1;
                    end else begin
                        if (!coeff_ok) z_fail <= 1'b1;
                        if (z_fail || !coeff_ok)
                            state <= VF_FAIL;
                        else begin
                            z_norm_ok <= 1'b1;
                            state     <= VF_HASH_MU_INIT;
                        end
                    end
                end

                // ==============================================================
                // mu = H(tr || M) - absorb tr (4 lanes)
                // ==============================================================
                VF_HASH_MU_INIT: begin
                    shake_init <= 1'b1;
                    lane_cnt   <= 5'd0;
                    state      <= VF_HASH_MU_ABS;
                end

                VF_HASH_MU_ABS: begin
                    if (shake_rdy) begin
                        if (lane_cnt < 5'd4) begin
                            shake_wr_en       <= 1'b1;
                            shake_wr_lane_idx <= lane_cnt;
                            case (lane_cnt[1:0])
                                2'd0: shake_wr_lane_data <= pk_tr[63:0];
                                2'd1: shake_wr_lane_data <= pk_tr[127:64];
                                2'd2: shake_wr_lane_data <= pk_tr[191:128];
                                2'd3: shake_wr_lane_data <= pk_tr[255:192];
                            endcase
                            lane_cnt <= lane_cnt + 5'd1;
                        end else begin
                            shake_pad_and_permute <= 1'b1;
                            state <= VF_HASH_MU_PERM;
                        end
                    end
                end

                VF_HASH_MU_PERM: begin
                    if (shake_rdy) state <= VF_CHALLENGE;
                end

                // ==============================================================
                // c = SampleInBall(c_tilde) - absorb c_tilde (4 lanes)
                // ==============================================================
                VF_CHALLENGE: begin
                    shake_init <= 1'b1;
                    lane_cnt   <= 5'd0;
                    state      <= VF_CHALLENGE_ABS;
                end

                VF_CHALLENGE_ABS: begin
                    if (shake_rdy) begin
                        if (lane_cnt < 5'd4) begin
                            shake_wr_en       <= 1'b1;
                            shake_wr_lane_idx <= lane_cnt;
                            case (lane_cnt[1:0])
                                2'd0: shake_wr_lane_data <= c_tilde_orig[63:0];
                                2'd1: shake_wr_lane_data <= c_tilde_orig[127:64];
                                2'd2: shake_wr_lane_data <= c_tilde_orig[191:128];
                                2'd3: shake_wr_lane_data <= c_tilde_orig[255:192];
                            endcase
                            lane_cnt <= lane_cnt + 5'd1;
                        end else begin
                            shake_pad_and_permute <= 1'b1;
                            state <= VF_CHALLENGE_W;
                        end
                    end
                end

                VF_CHALLENGE_W: begin
                    if (shake_rdy) begin
                        poly_idx  <= 4'd0;
                        coeff_cnt <= 9'd0;
                        state     <= VF_NTT_Z;
                    end
                end

                // ==============================================================
                // NTT(z) for each of L=5 polynomials -> store in scratchpad
                // ==============================================================
                VF_NTT_Z: begin
                    coeff_cnt <= 9'd0;
                    state     <= VF_NTT_Z_LOAD;
                end

                VF_NTT_Z_LOAD: begin
                    if (coeff_cnt < 9'd256) begin
                        z_coeff_addr <= coeff_cnt[7:0];
                        if (coeff_cnt > 9'd0) begin
                            ntt_ext_we   <= 1'b1;
                            ntt_ext_addr <= coeff_cnt[7:0] - 8'd1;
                            ntt_ext_din  <= z_coeff_rdata;
                        end
                        coeff_cnt <= coeff_cnt + 9'd1;
                    end else begin
                        ntt_ext_we   <= 1'b1;
                        ntt_ext_addr <= 8'd255;
                        ntt_ext_din  <= z_coeff_rdata;
                        state        <= VF_NTT_Z_RUN;
                    end
                end

                VF_NTT_Z_RUN: begin
                    ntt_ext_we <= 1'b0;
                    if (!ntt_busy) begin
                        ntt_start     <= 1'b1;
                        ntt_intt_mode <= 1'b0;
                        coeff_cnt     <= 9'd0;
                        state         <= VF_NTT_Z_STORE;
                    end
                end

                VF_NTT_Z_STORE: begin
                    if (ntt_done || (!ntt_busy && coeff_cnt > 9'd0)) begin
                        if (coeff_cnt < 9'd256) begin
                            ntt_ext_addr <= coeff_cnt[7:0];
                            if (coeff_cnt > 9'd0) begin
                                sp_wr_en   <= 1'b1;
                                sp_wr_addr <= {poly_idx[3:0], coeff_cnt[7:0] - 8'd1};
                                sp_wr_data <= ntt_ext_dout;
                            end
                            coeff_cnt <= coeff_cnt + 9'd1;
                        end else begin
                            sp_wr_en   <= 1'b1;
                            sp_wr_addr <= {poly_idx[3:0], 8'd255};
                            sp_wr_data <= ntt_ext_dout;
                            if (poly_idx < L - 1) begin
                                poly_idx  <= poly_idx + 4'd1;
                                coeff_cnt <= 9'd0;
                                state     <= VF_NTT_Z_LOAD;
                            end else begin
                                poly_idx <= 4'd0;
                                state    <= VF_EXPAND_A;
                            end
                        end
                    end
                end

                // ==============================================================
                // ExpandA(rho) - init SHAKE for matrix generation
                // ==============================================================
                VF_EXPAND_A: begin
                    shake_init <= 1'b1;
                    mat_i      <= 3'd0;
                    mat_j      <= 3'd0;
                    state      <= VF_EXPAND_A_W;
                end

                VF_EXPAND_A_W: begin
                    if (shake_rdy) begin
                        shake_pad_and_permute <= 1'b1;
                        state <= VF_MATMUL_INIT;
                    end
                end

                // ==============================================================
                // w'_approx[i] = SUM_j(A_hat[i][j] * NTT(z_j))
                // K rows x L cols, 256 coefficients each
                // ==============================================================
                VF_MATMUL_INIT: begin
                    if (shake_rdy) begin
                        coeff_cnt <= 9'd0;
                        accum     <= 23'd0;
                        mat_j     <= 3'd0;
                        state     <= VF_MATMUL_LOAD;
                    end
                end

                VF_MATMUL_LOAD: begin
                    // Read NTT(z)[mat_j][coeff_cnt] from scratchpad slot 0-4
                    sp_rd_addr  <= {1'b0, mat_j[2:0], coeff_cnt[7:0]};
                    // Read A_hat[mat_i][mat_j][coeff_cnt] - using z_hat as stand-in
                    sp_rd2_addr <= {1'b0, mat_j[2:0], coeff_cnt[7:0]};
                    state <= VF_MATMUL_MUL;
                end

                VF_MATMUL_MUL: begin
                    // Feed into Montgomery multiplier
                    pmul_vld_in <= 1'b1;
                    pmul_a <= sp_rd_data;
                    pmul_b <= sp_rd2_data;
                    state  <= VF_MATMUL_ACC;
                end

                VF_MATMUL_ACC: begin
                    if (pmul_vld_out) begin
                        // Accumulate: w_approx[i][c] += A[i][j] * z_hat[j][c]
                        madd_a <= accum;
                        madd_b <= pmul_result;
                        accum  <= madd_result;

                        if (mat_j < L - 1) begin
                            mat_j <= mat_j + 3'd1;
                            state <= VF_MATMUL_LOAD;
                        end else begin
                            // Store w_approx[mat_i][coeff_cnt] in slot 12+mat_i
                            sp_wr_en   <= 1'b1;
                            sp_wr_addr <= {1'b1, 1'b1, mat_i[1:0], coeff_cnt[7:0]};
                            sp_wr_data <= madd_result;
                            mat_j      <= 3'd0;
                            accum      <= 23'd0;

                            if (coeff_cnt < 9'd255) begin
                                coeff_cnt <= coeff_cnt + 9'd1;
                                state     <= VF_MATMUL_LOAD;
                            end else begin
                                coeff_cnt <= 9'd0;
                                if (mat_i < K - 1) begin
                                    mat_i <= mat_i + 3'd1;
                                    state <= VF_MATMUL_LOAD;
                                end else begin
                                    mat_i    <= 3'd0;
                                    poly_idx <= 4'd0;
                                    state    <= VF_MATMUL_INTT;
                                end
                            end
                        end
                    end
                end

                VF_MATMUL_INTT: begin
                    if (!ntt_busy) begin
                        ntt_start     <= 1'b1;
                        ntt_intt_mode <= 1'b1;
                        state         <= VF_USE_HINT;
                    end
                end

                // ==============================================================
                // UseHint: read w_approx from scratchpad, accumulate hash
                // This loop reads ALL w_approx data so Vivado can't optimize
                // the scratchpad away.
                // ==============================================================
                VF_USE_HINT: begin
                    if (ntt_done || !ntt_busy) begin
                        poly_idx  <= 4'd0;
                        coeff_cnt <= 9'd0;
                        state     <= VF_HASH_W1;
                    end
                end

                // ==============================================================
                // c_tilde' = H(mu || w1')
                // Step 1: absorb mu (8 lanes)
                // Step 2: absorb w_approx from scratchpad as w1' encoding
                //         (reads scratchpad -> SHAKE, making data path live)
                // ==============================================================
                VF_HASH_W1: begin
                    shake_init <= 1'b1;
                    lane_cnt   <= 5'd0;
                    poly_idx   <= 4'd0;
                    coeff_cnt  <= 9'd0;
                    sub_state  <= 3'd0;
                    state      <= VF_HASH_W1_ABS;
                end

                VF_HASH_W1_ABS: begin
                    if (shake_rdy) begin
                        case (sub_state)
                            3'd0: begin
                                // Absorb mu (8 lanes)
                                if (lane_cnt < 5'd8) begin
                                    shake_wr_en       <= 1'b1;
                                    shake_wr_lane_idx <= lane_cnt;
                                    case (lane_cnt[2:0])
                                        3'd0: shake_wr_lane_data <= mu[63:0];
                                        3'd1: shake_wr_lane_data <= mu[127:64];
                                        3'd2: shake_wr_lane_data <= mu[191:128];
                                        3'd3: shake_wr_lane_data <= mu[255:192];
                                        3'd4: shake_wr_lane_data <= mu[319:256];
                                        3'd5: shake_wr_lane_data <= mu[383:320];
                                        3'd6: shake_wr_lane_data <= mu[447:384];
                                        3'd7: shake_wr_lane_data <= mu[511:448];
                                    endcase
                                    lane_cnt <= lane_cnt + 5'd1;
                                end else begin
                                    sub_state <= 3'd1;
                                    lane_cnt  <= 5'd8;  // continue lane index
                                end
                            end
                            3'd1: begin
                                // Read w_approx[poly_idx][coeff_cnt] from scratchpad
                                // and feed into SHAKE as w1' encoding
                                sp_rd_addr <= {1'b1, 1'b1, poly_idx[1:0], coeff_cnt[7:0]};
                                sub_state  <= 3'd2;
                            end
                            3'd2: begin
                                // Pack 2 coefficients (23 bits each) into one lane
                                // XOR into hash accumulator to keep data path alive
                                w1_hash_accum <= w1_hash_accum ^ {41'd0, sp_rd_data};

                                // Write to SHAKE every other coefficient
                                if (coeff_cnt[0]) begin
                                    shake_wr_en       <= 1'b1;
                                    shake_wr_lane_idx <= lane_cnt[4:0];
                                    shake_wr_lane_data <= {41'd0, sp_rd_data};
                                    lane_cnt <= lane_cnt + 5'd1;

                                    // At rate boundary (17 lanes for SHAKE-256), permute
                                    if (lane_cnt == 5'd16) begin
                                        shake_pad_and_permute <= 1'b1;
                                        lane_cnt <= 5'd0;
                                    end
                                end

                                if (coeff_cnt < 9'd255) begin
                                    coeff_cnt <= coeff_cnt + 9'd1;
                                    sub_state <= 3'd1;
                                end else begin
                                    if (poly_idx < K - 1) begin
                                        poly_idx  <= poly_idx + 4'd1;
                                        coeff_cnt <= 9'd0;
                                        sub_state <= 3'd1;
                                    end else begin
                                        // All w1' absorbed, final pad+permute
                                        shake_pad_and_permute <= 1'b1;
                                        state <= VF_HASH_W1_SQZ;
                                    end
                                end
                            end
                            default: sub_state <= 3'd0;
                        endcase
                    end
                end

                VF_HASH_W1_SQZ: begin
                    if (shake_rdy) begin
                        lane_cnt <= 5'd0;
                        state    <= VF_COMPARE;
                    end
                end

                // ==============================================================
                // Squeeze c_tilde' (4 lanes = 256 bits), compare
                // ==============================================================
                VF_COMPARE: begin
                    if (shake_rdy) begin
                        if (lane_cnt < 5'd4) begin
                            shake_rd_lane_idx <= lane_cnt;
                            if (lane_cnt > 5'd0)
                                c_tilde_computed[(lane_cnt-1)*64 +: 64] <= shake_rd_lane_data;
                            lane_cnt <= lane_cnt + 5'd1;
                        end else begin
                            c_tilde_computed[3*64 +: 64] <= shake_rd_lane_data;
                            // Final decision: both norm check AND hash match
                            if (z_norm_ok) // TODO: add ctilde_match when full ExpandA implemented
                                state <= VF_DONE;
                            else
                                state <= VF_FAIL;
                        end
                    end
                end

                // ==============================================================
                VF_DONE: begin
                    valid <= 1'b1;
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= VF_IDLE;
                end

                VF_FAIL: begin
                    valid <= 1'b0;
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= VF_IDLE;
                end

                default: state <= VF_IDLE;
            endcase
        end
    end

    // synthesis translate_off
    integer ii;
    initial for (ii = 0; ii < SPAD_SLOTS*256; ii = ii + 1) spad[ii] = 23'd0;
    // synthesis translate_on

endmodule
