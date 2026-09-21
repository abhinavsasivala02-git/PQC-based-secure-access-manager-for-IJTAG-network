//============================================================================
// KAT testbench for ML-KEM-768 K-PKE.Encrypt against NIST vector (count=0)
//
//   m = kat_msg.mem (32 bytes)
//   r = kat_r.mem   (32 bytes, = G(m || H(ek)) first half)
//   ek = kat_pk.mem (1184 bytes: ByteEncode_12(t)||rho)
//   expected ct = kat_ct.mem (1088 bytes)
//
// Checks the ciphertext produced by mlkem_encaps_top against the NIST
// expected ciphertext byte-for-byte.
//============================================================================
`timescale 1ns/1ps

module tb_kem_kat;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg       rst_n, start;
    reg [255:0] m_seed, r_seed;

    // KAT vectors
    reg [7:0] pk   [0:1183];
    reg [7:0] msg  [0:31];
    reg [7:0] rvec [0:31];
    reg [7:0] exp_ct [0:1087];

    // ek ROM
    reg [7:0] ek_rom[0:1183];
    integer   k;

    // Captured ciphertext
    reg [7:0]  got_ct[0:1087];
    reg [10:0] got_cnt;

    // DUT
    wire        dut_done, dut_busy, dut_ct_valid;
    wire [7:0]  dut_ct_data;
    wire [12:0] dut_ct_addr, dut_ek_addr;

    mlkem_encaps_top #(.K(3), .ETA2(2), .DU(10), .DV(4)) u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .done     (dut_done),
        .busy     (dut_busy),
        .m_seed   (m_seed),
        .r_seed   (r_seed),
        .ek_addr  (dut_ek_addr),
        .ek_rdata (ek_rom[dut_ek_addr]),
        .ct_valid (dut_ct_valid),
        .ct_data  (dut_ct_data),
        .ct_addr  (dut_ct_addr)
    );

    always @(posedge clk)
        if (dut_ct_valid) begin
            got_ct[got_cnt] <= dut_ct_data;
            got_cnt         <= got_cnt + 11'd1;
        end

    integer ci;
    integer ct_bad, first_ct;
    integer sim_cycles;

    initial begin
        $display("KAT: start t=%0t", $time);
        $readmemh("kat_pk.mem",  pk);
        $readmemh("kat_msg.mem", msg);
        $readmemh("kat_r.mem",   rvec);
        $readmemh("kat_ct.mem",  exp_ct);
        $display("KAT: pk[0]=%02h pk[1]=%02h msg[0]=%02h r[0]=%02h exp_ct[0]=%02h exp_ct[1087]=%02h",
                 pk[0], pk[1], msg[0], rvec[0], exp_ct[0], exp_ct[1087]);

        for (k = 0; k < 1184; k = k + 1) ek_rom[k] = pk[k];
        for (k = 0; k < 32; k = k + 1) begin
            m_seed[k*8 +: 8] = msg[k];
            r_seed[k*8 +: 8] = rvec[k];
        end

        rst_n = 0; start = 0; got_cnt = 0;
        #100 rst_n = 1;
        #50;
        start = 1;
        #20 start = 0;

        wait (dut_done);

        $display("KAT: encaps done t=%0t ct_bytes=%0d", $time, got_cnt);

        ct_bad = 0; first_ct = -1;
        for (ci = 0; ci < 1088; ci = ci + 1)
            if (got_ct[ci] !== exp_ct[ci]) begin
                if (ct_bad == 0) first_ct = ci;
                ct_bad = ct_bad + 1;
            end

        begin
            integer fg;
            fg = $fopen("kat_got_ct.mem", "w");
            for (ci = 0; ci < 1088; ci = ci + 1)
                $fwrite(fg, "%02h\n", got_ct[ci]);
            $fclose(fg);
        end

        if (ct_bad == 0)
            $display("KEM-KAT PASS: ciphertext (1088B) matches NIST vector");
        else begin
            $display("KEM-KAT FAIL: %0d bytes mismatch (first@%0d)", ct_bad, first_ct);
            $write("got: "); for (ci=0;ci<32;ci=ci+1) $write("%02h", got_ct[ci]); $write("\n");
            $write("exp: "); for (ci=0;ci<32;ci=ci+1) $write("%02h", exp_ct[ci]); $write("\n");
            if (first_ct >= 0)
                $display("  first ct byte @%0d: got=%02h exp=%02h", first_ct, got_ct[first_ct], exp_ct[first_ct]);
            // print u-region mismatch count and v-region mismatch count
            $display("  u-region (0..959) bad=%0d  v-region (960..1087) bad=%0d",
                     ct_region_bad(0,959), ct_region_bad(960,1087));
        end
        $finish;
    end

    function integer ct_region_bad;
        input integer lo, hi;
        integer c;
        begin
            ct_region_bad = 0;
            for (c = lo; c <= hi; c = c + 1)
                if (got_ct[c] !== exp_ct[c]) ct_region_bad = ct_region_bad + 1;
        end
    endfunction

    always @(posedge clk) sim_cycles = sim_cycles + 1;

    integer pn;
    initial pn = 0;
    always @(posedge clk) begin
        if (dut_ct_valid) begin
            if (pn < 6)
                $display("CT t=%0t state=%0d icnt=%0d addr=%0d data=%02h",
                         $time, u_dut.u_encaps.state, u_dut.u_encaps.i_cnt, dut_ct_addr, dut_ct_data);
            pn = pn + 1;
        end
        if (u_dut.u_encaps.state == 6'd29)
            $display("UENC t=%0t icnt=%0d enc_u_bvalid=%0b enc_u_done=%0b",
                     $time, u_dut.u_encaps.i_cnt, u_dut.u_encaps.enc_u_bvalid, u_dut.u_encaps.enc_u_done);
        if (u_dut.u_encaps.state == 6'd28 && u_dut.u_encaps.u_comp_u.done)
            $display("UCOMPDONE t=%0t icnt=%0d", $time, u_dut.u_encaps.i_cnt);
        if (u_dut.u_encaps.ntt_done || u_dut.u_encaps.arith_done || u_dut.u_encaps.enc_u_done || u_dut.u_encaps.bmul_done)
            $display("DONE t=%0t st=%0d icnt=%0d ntt=%0b arith=%0b enc=%0b bmul=%0b",
                     $time, u_dut.u_encaps.state, u_dut.u_encaps.i_cnt,
                     u_dut.u_encaps.ntt_done, u_dut.u_encaps.arith_done,
                     u_dut.u_encaps.enc_u_done, u_dut.u_encaps.bmul_done);
    end

    initial #200_000_000 begin
        $display("KEM-KAT TIMEOUT (no done)");
        $finish;
    end

endmodule