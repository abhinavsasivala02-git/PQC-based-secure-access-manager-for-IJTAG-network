`timescale 1ns/1ps
`include "mldsa_params.vh"

module verify_tb;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;

    reg        start = 1'b0;
    wire       done, busy, valid;
    reg [255:0] pk_tr = 256'h0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef;
    reg [511:0] mu    = 512'h0;
    reg        mu_valid = 1'b1;
    reg [255:0] c_tilde_orig = 256'h0;
    reg [255:0] c_tilde_prime = 256'h0;

    // NTT core
    wire        ntt_start, ntt_intt_mode, ntt_done, ntt_busy;
    wire        ntt_ext_we;
    wire [7:0]  ntt_ext_addr;
    wire [`MLDSA_QBITS-1:0] ntt_ext_din, ntt_ext_dout;

    // SHAKE-256 (channel A)
    wire        shake_init, shake_wr_en, shake_pad_and_permute, shake_permute;
    wire [4:0]  shake_wr_lane_idx, shake_rd_lane_idx;
    wire [63:0] shake_wr_lane_data, shake_rd_lane_data;
    wire        shake_rdy;

    // z polynomial RAM
    wire [7:0] z_coeff_addr;
    wire [`MLDSA_QBITS-1:0] z_coeff_rdata;

    // ---------------------------------------------------------------------
    // Device Under Test
    // ---------------------------------------------------------------------
    verify_ctrl u_verify (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .start                 (start),
        .done                  (done),
        .busy                  (busy),
        .valid                 (valid),
        .pk_tr                 (pk_tr),
        .mu                    (mu),
        .mu_valid              (mu_valid),
        .ntt_start             (ntt_start),
        .ntt_intt_mode         (ntt_intt_mode),
        .ntt_done              (ntt_done),
        .ntt_busy              (ntt_busy),
        .shake_init            (shake_init),
        .shake_wr_en           (shake_wr_en),
        .shake_wr_lane_idx     (shake_wr_lane_idx),
        .shake_wr_lane_data    (shake_wr_lane_data),
        .shake_pad_and_permute (shake_pad_and_permute),
        .shake_permute         (shake_permute),
        .shake_rd_lane_idx     (shake_rd_lane_idx),
        .shake_rd_lane_data    (shake_rd_lane_data),
        .shake_rdy             (shake_rdy),
        .ntt_ext_we            (ntt_ext_we),
        .ntt_ext_addr          (ntt_ext_addr),
        .ntt_ext_din           (ntt_ext_din),
        .ntt_ext_dout          (ntt_ext_dout),
        .z_coeff_addr          (z_coeff_addr),
        .z_coeff_rdata         (z_coeff_rdata),
        .c_tilde_orig          (c_tilde_orig),
        .c_tilde_prime         (c_tilde_prime)
    );

    // ---------------------------------------------------------------------
    // NTT core + memory
    // ---------------------------------------------------------------------
    ntt_core u_ntt (
        .clk         (clk),
        .rst_n       (rst_n),
        .start       (ntt_start),
        .intt_mode   (ntt_intt_mode),
        .busy        (ntt_busy),
        .done        (ntt_done),
        .ext_we      (ntt_ext_we),
        .ext_addr    (ntt_ext_addr),
        .ext_din     (ntt_ext_din),
        .ext_dout    (ntt_ext_dout)
    );

    // z polynomial source RAM (all-zero => norm check passes)
    poly_ram_tdp #(.DEPTH(256), .WIDTH(`MLDSA_QBITS)) u_zram (
        .clk   (clk),
        .wea   (1'b0),  .addra (z_coeff_addr), .dina (0), .douta (z_coeff_rdata),
        .web   (1'b0),  .addrb (8'd0),          .dinb (0), .doutb ()
    );

    // ---------------------------------------------------------------------
    // SHAKE-256 (channel A of unified core)
    // ---------------------------------------------------------------------
    shake_unified u_shake (
        .clk               (clk),          .rst_n             (rst_n),
        .a_init            (shake_init),   .a_wr_en           (shake_wr_en),
        .a_wr_lane_idx     (shake_wr_lane_idx),
        .a_wr_lane_data    (shake_wr_lane_data),
        .a_pad_and_permute (shake_pad_and_permute),
        .a_permute         (shake_permute),
        .a_rd_lane_idx     (shake_rd_lane_idx),
        .a_rd_lane_data    (shake_rd_lane_data),
        .a_busy            (),             .a_rdy             (shake_rdy),
        .b_init            (1'b0),         .b_wr_en           (1'b0),
        .b_wr_lane_idx     (5'd0),         .b_wr_lane_data    (64'd0),
        .b_pad_and_permute (1'b0),         .b_permute         (1'b0),
        .b_rd_lane_idx     (5'd0),         .b_rd_lane_data    (),
        .b_busy            (),             .b_rdy             ()
    );

    // ---------------------------------------------------------------------
    // Test control
    // ---------------------------------------------------------------------
    integer cycle_cnt = 0;

    initial begin
        rst_n = 1'b0;
        #40;
        rst_n = 1'b1;
        #20;

        // Load z polynomial (all zeros -> in-range), start verify
        start = 1'b1;
        #10;
        start = 1'b0;

        // Monitor until done
        while (!done) begin
            #10;
            cycle_cnt = cycle_cnt + 1;
            if (cycle_cnt > 2000000) begin
                $display("TIMEOUT: verify did not finish (cycle_cnt=%0d, busy=%b)", cycle_cnt, busy);
                $finish;
            end
        end

        $display("======================================================");
        $display("VERIFY COMPLETED: done=%b valid=%b (sig %s)",
                 done, valid, (valid ? "ACCEPTED" : "REJECTED"));
        $display("cycle_cnt = %0d", cycle_cnt);
        $display("======================================================");

        if (valid === 1'b1)
            $display("PASS: valid signature accepted");
        else
            $display("FAIL: signature rejected");

        $finish;
    end

    // Waveform dump
    initial begin
        $dumpfile("verify_tb.vcd");
        $dumpvars(0, verify_tb);
    end

endmodule
