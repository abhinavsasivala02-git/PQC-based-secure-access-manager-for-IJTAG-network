`timescale 1ns/1ps

module tb_debug;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg       rst_n, start;
    reg [255:0] m_seed, r_seed;
    reg [7:0] ek_rom[0:1183];
    wire [7:0] ek_rdata = ek_rom[dut_ek_addr];

    wire       dut_done, dut_busy, dut_ct_valid;
    wire [7:0] dut_ct_data;
    wire [12:0] dut_ct_addr, dut_ek_addr;

    mlkem_encaps_top #(.K(3), .ETA2(2), .DU(10), .DV(4)) u_dut (
        .clk(clk), .rst_n(rst_n), .start(start), .done(dut_done), .busy(dut_busy),
        .m_seed(m_seed), .r_seed(r_seed),
        .ek_addr(dut_ek_addr), .ek_rdata(ek_rdata),
        .ct_valid(dut_ct_valid), .ct_data(dut_ct_data), .ct_addr(dut_ct_addr)
    );

    integer k, i;
    reg [5:0] sp; integer prn;
    integer dd;

    reg probe_arm = 1'b0;
    integer pc_sntt = 0, pc_bmul = 0, pc_add = 0, pc_comp = 0, pc_bread = 0, pc_cbdwr = 0, pc_ntt_dump = 0;
    reg ntt_dump1 = 1'b0;
    reg cbd_raw_dump1 = 1'b0;

    // ------------------------------------------------------------------
    // Stage dumps for u/v pipeline verification (frommont check)
    // ------------------------------------------------------------------
    reg sntt_done_q = 1'b0;
    reg one_u_hat=1'b0, one_u_mont=1'b0, one_u_fm=1'b0, one_u_final=1'b0,
        one_e1=1'b0, one_v_hat=1'b0, one_v_mont=1'b0, one_v_fm=1'b0,
        one_v_final=1'b0, one_e2mu=1'b0, one_rhat=1'b0, one_that=1'b0,
        one_dec=1'b0;
    reg [7:0] prev_a_ij = 8'hFF;


    // Hash/CBD debug
    integer cbd_dump;
    reg [7:0] last_sq_data;
    reg last_sq_valid, last_sq_next, last_cbd_req;
    reg [7:0] hash_cfg_rate_q, hash_cfg_domain_q;
    reg hash_init_q, hash_absorb_valid_q, hash_absorb_last_q, hash_absorb_ready_q;
    reg [7:0] hash_absorb_data_q;
    reg hash_squeeze_valid_q, hash_squeeze_next_q;
    reg [7:0] hash_squeeze_data_q;

    // Reference SHAKE-256(r||0) first bytes for comparison
    reg [7:0] ref_shake[0:127];

    integer f_shake;

    initial begin
        $readmemh("kat_pk.mem", ek_rom);
        for (k = 0; k < 32; k = k + 1) begin
            m_seed[k*8 +: 8] = 8'h00;
            r_seed[k*8 +: 8] = 8'h11;
        end
        rst_n = 0; start = 0; cbd_dump = 0;
        f_shake = $fopen("shake_sq.txt", "w");
        #100 rst_n = 1;
        #50;
        start = 1; #20 start = 0;
        wait (dut_done);
        $fclose(f_shake);
        $display("DONE at %0t", $time);
        $finish;
    end

    // Capture hash/CBD signals
    always @(posedge clk) begin
        // Hash engine config
        if (u_dut.u_hash.cfg_rate_bytes !== hash_cfg_rate_q)
            $display("HASH CFG t=%0t rate=%0d dom=%0d", $time,
                     u_dut.u_hash.cfg_rate_bytes, u_dut.u_hash.cfg_domain_sep);
        hash_cfg_rate_q   <= u_dut.u_hash.cfg_rate_bytes;
        hash_cfg_domain_q <= u_dut.u_hash.cfg_domain_sep;

        // Hash engine absorb
        if (u_dut.u_hash.init !== hash_init_q)
            $display("HASH INIT t=%0t", $time);
        hash_init_q         <= u_dut.u_hash.init;
        hash_absorb_valid_q <= u_dut.u_hash.absorb_valid;
        hash_absorb_ready_q <= u_dut.u_hash.absorb_ready;
        hash_absorb_data_q  <= u_dut.u_hash.absorb_data;
        hash_absorb_last_q  <= u_dut.u_hash.absorb_last;
        hash_squeeze_valid_q<= u_dut.u_hash.squeeze_valid;
        hash_squeeze_data_q <= u_dut.u_hash.squeeze_data;
        hash_squeeze_next_q <= u_dut.u_hash.squeeze_next;

        // CBD req/valid
        if (u_dut.u_encaps.u_cbd.prf_req !== last_cbd_req)
            $display("CBD REQ t=%0t req=%0b", $time, u_dut.u_encaps.u_cbd.prf_req);
        last_cbd_req <= u_dut.u_encaps.u_cbd.prf_req;

        // Squeeze data
        if (u_dut.u_hash.squeeze_valid !== last_sq_valid)
            $display("SQ t=%0t valid=%0b data=%02h next=%0b spos=%0d bpos=%0d state=%0d",
                     $time, u_dut.u_hash.squeeze_valid,
                     u_dut.u_hash.squeeze_data,
                     u_dut.u_hash.squeeze_next,
                     u_dut.u_hash.spos,
                     u_dut.u_hash.bpos,
                     u_dut.u_hash.state);
        last_sq_valid   <= u_dut.u_hash.squeeze_valid;
        last_sq_data    <= u_dut.u_hash.squeeze_data;
        last_sq_next    <= u_dut.u_hash.squeeze_next;

        // Absorb
        if (u_dut.u_hash.absorb_valid)
            $display("ABS t=%0t data=%02h last=%0b ready=%0b bpos=%0d",
                     $time, u_dut.u_hash.absorb_data,
                     u_dut.u_hash.absorb_last,
                     u_dut.u_hash.absorb_ready,
                     u_dut.u_hash.bpos);

        // Print every byte CBD captures (shows if first bytes are X)
        if (u_dut.u_encaps.u_cbd.state==3'd1 && u_dut.u_encaps.u_cbd.prf_valid)
            $display("CBD-CAP t=%0t idx=%0d data=%02h", $time,
                     u_dut.u_encaps.u_cbd.byte_cnt, u_dut.u_encaps.u_cbd.prf_data);

        // Arm probe on first CBD collect entry
        if (!probe_arm && u_dut.u_encaps.u_cbd.state==3'd1 && u_dut.u_encaps.u_cbd.busy)
            probe_arm <= 1;
        if (probe_arm && u_dut.u_encaps.u_cbd.byte_cnt >= 8'd12)
            probe_arm <= 0;

        // Cycle-by-cycle hash/CBD probe during the first squeeze window
        if (probe_arm && u_dut.u_encaps.u_cbd.byte_cnt < 4'd12)
            $display("PROBE t=%0t hstate=%0d valid=%0b data=%02h spos=%0d next=%0b req=%0b cbdst=%0d bcnt=%0d km[bcnt]=%02h",
                     $time,
                     u_dut.u_hash.state,
                     u_dut.u_hash.squeeze_valid,
                     u_dut.u_hash.squeeze_data,
                     u_dut.u_hash.spos,
                     u_dut.u_hash.squeeze_next,
                     u_dut.u_encaps.u_cbd.prf_req,
                     u_dut.u_encaps.u_cbd.state,
                     u_dut.u_encaps.u_cbd.byte_cnt,
                     u_dut.u_hash.kst_mem[u_dut.u_encaps.u_cbd.byte_cnt]);

        // Probe u/v byte-encode stage (state 29=ST_ENC_U, 30=ST_WAIT_ENC_U)
        if (u_dut.u_encaps.ct_valid === 1'b1)
            $display("ENCV t=%0t data=%02h addr=%0d ram6=%03h",
                     $time,
                     u_dut.u_encaps.ct_data,
                     u_dut.u_encaps.ct_addr,
                     u_dut.u_encaps.ram6_ra);

        // Probe CBD datapath at S_WRITE edge (state 3'd3)
        if (u_dut.u_encaps.u_cbd.state==3'd3 && pc_cbdwr<10) begin
            reg [7:0] tb_b0, tb_b1;
            reg [2:0] tb_bp;
            reg [15:0] tb_tb;
            reg [5:0] tb_ext;
            tb_b0 = u_dut.u_encaps.u_cbd.prf_buf[u_dut.u_encaps.u_cbd.bit_offset[10:3]];
            tb_b1 = u_dut.u_encaps.u_cbd.prf_buf[u_dut.u_encaps.u_cbd.bit_offset[10:3] + 1];
            tb_bp = u_dut.u_encaps.u_cbd.bit_offset[2:0];
            tb_tb = {tb_b1, tb_b0};
            tb_ext = (tb_tb >> tb_bp) & 6'd15;
            $display("CBDDW t=%0t off=%0d cp=%0d b0=%02h b1=%02h bit_pos=%0d twob=%04h ext_tb=%06b ext_mod=%06b",
                     $time, u_dut.u_encaps.u_cbd.bit_offset, u_dut.u_encaps.u_cbd.coeff_idx,
                     tb_b0, tb_b1, tb_bp, tb_tb, tb_ext, u_dut.u_encaps.u_cbd.extracted_bits);
            pc_cbdwr = pc_cbdwr + 1;
        end

// Probe CBD poly writes (which half of ram1 they land on)
        if (u_dut.u_encaps.u_cbd.poly_wen && pc_cbdwr<10) begin
            $display("CBDW t=%0t kst=%0d i=%0d addr=%0d data=%03h [raw bcnt=%0d cf=%0d]",
                     $time, u_dut.u_encaps.state, u_dut.u_encaps.i_cnt,
                     u_dut.u_encaps.u_cbd.poly_addr, u_dut.u_encaps.u_cbd.poly_wdata,
                     u_dut.u_encaps.u_cbd.byte_cnt, u_dut.u_encaps.u_cbd.coeff_idx);
            pc_cbdwr = pc_cbdwr + 1;
        end

        // Probe NTT RAM activity on ram1 (r_hat) during ST_NTT_R / ST_WAIT_NTT_R
        if ((u_dut.u_encaps.state==6'd10 || u_dut.u_encaps.state==6'd11) && u_dut.u_encaps.i_cnt==0 && u_dut.u_ntt.ram_wen && pc_ntt_dump<4) begin
            $display("NTTWR t=%0t s=%0d aa=%0d wd=%03h", $time, u_dut.u_encaps.state, u_dut.u_ntt.ram_addr_a, u_dut.u_ntt.ram_wdata_a);
            pc_ntt_dump = pc_ntt_dump + 1;
        end

        // Dump full ram1 (r_hat[0]) after run-1 NTT completes
        if (u_dut.u_encaps.state==6'd11 && u_dut.u_encaps.i_cnt==0 && u_dut.u_ntt.done && !ntt_dump1) begin
            ntt_dump1 = 1;
            $display("NTT1 DONE t=%0t ram1[0..255]:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram1.mem[ci]);
            $write("\n");
        end

        // Probe ExpandA writes to ram0 (ST_WAIT_SNTT=18)
        if (u_dut.u_encaps.state==6'd18 && u_dut.u_encaps.u_sntt.poly_wen && pc_sntt<8) begin
            $display("SNTT t=%0t addr=%0d wdata=%03h", $time, u_dut.u_encaps.u_sntt.poly_addr, u_dut.u_encaps.u_sntt.poly_wdata);
            pc_sntt = pc_sntt + 1;
        end

        // Probe basemul RAM read values (S_WT_A0B0=3, S_WT_A1B1=6)
        if ((u_dut.u_basemul.state==4'd3 || u_dut.u_basemul.state==4'd6) && pc_bread<16) begin
            $display("BREAD t=%0t st=%0d a=%03h b=%03h aaddr=%0d baddr=%0d", $time,
                     u_dut.u_basemul.state,
                     u_dut.u_basemul.a_rdata, u_dut.u_basemul.b_rdata,
                     u_dut.u_basemul.a_addr, u_dut.u_basemul.b_addr);
            pc_bread = pc_bread + 1;
        end

        // Probe basemul writes to ram6 (ST_BMUL_U=19, ST_WAIT_MUL_U=20)
        if ((u_dut.u_encaps.state==6'd19 || u_dut.u_encaps.state==6'd20) && u_dut.u_basemul.c_wen && pc_bmul<8) begin
            $display("BMUL t=%0t addr=%0d wdata=%03h", $time, u_dut.u_basemul.c_addr, u_dut.u_basemul.c_wdata);
            pc_bmul = pc_bmul + 1;
        end

        // Probe arith ADD_U write to ram2 (ST_ADD_U=21, ST_WAIT_ADD_U=22)
        if ((u_dut.u_encaps.state==6'd21 || u_dut.u_encaps.state==6'd22) && u_dut.u_arith.c_wen && pc_add<8) begin
            $display("ADD-AR t=%0t a=%03h b=%03h c=%03h caddr=%0d", $time,
                     u_dut.u_arith.a_rdata, u_dut.u_arith.b_rdata,
                     u_dut.u_arith.c_wdata, u_dut.u_arith.c_addr);
            pc_add = pc_add + 1;
        end

        // Probe compress_u writes to ram6 (ST_COMP_U=27)
        if (u_dut.u_encaps.state==6'd27 && u_dut.u_encaps.u_comp_u.out_wen && pc_comp<8) begin
            $display("COMPU t=%0t in=%03h out=%03h", $time,
                     u_dut.u_encaps.u_comp_u.in_rdata, u_dut.u_encaps.u_comp_u.out_wdata);
            pc_comp = pc_comp + 1;
        end

        // Dump CBD buffer when collection completes
        if (u_dut.u_encaps.u_cbd.state==3'd2 && u_dut.u_encaps.u_cbd.byte_cnt==8'd127 && !cbd_dump) begin
            cbd_dump = 1;
            $write("CBD BUF[0..15] t=%0t: ", $time);
            for (int ci=0; ci<16; ci=ci+1) $write("%02h ", u_dut.u_encaps.u_cbd.prf_buf[ci]);
            $write("\n");
        end

        // CBD output dump when done
        if (u_dut.u_encaps.u_cbd.state==3'd5 && cbd_dump) begin
            cbd_dump = 0;
            if (!cbd_raw_dump1) begin
                cbd_raw_dump1 = 1;
                $display("CBD1 RAW t=%0t poly[0..255]:", $time);
                for (int ci=0; ci<256; ci=ci+1)
                    $write("%03h ", u_dut.u_encaps.u_ram1.mem[ci]);
                $write("\n");
            end
        end

        // =================================================================
        // u/v stage dumps (frommont verification)
        // =================================================================
        // ExpandA output A[i][j] in ram0 (ST_WAIT_SNTT=18, sntt_done rising)
        if (u_dut.u_encaps.state==6'd18) begin
            if (sntt_done_q==1'b0 && u_dut.u_encaps.u_sntt.done==1'b1 &&
                ({u_dut.u_encaps.i_cnt,u_dut.u_encaps.j_cnt} !== prev_a_ij)) begin
                prev_a_ij <= {u_dut.u_encaps.i_cnt,u_dut.u_encaps.j_cnt};
                $display("A_%0d_%0d t=%0t:", u_dut.u_encaps.i_cnt, u_dut.u_encaps.j_cnt, $time);
                for (int ci=0; ci<256; ci=ci+1)
                    $write("%03h ", u_dut.u_encaps.u_ram0.mem[ci]);
                $write("\n");
            end
        end
        sntt_done_q <= u_dut.u_encaps.u_sntt.done;

        // Capture raw SHAKE-128 squeeze bytes during A[0][0] (ST_WAIT_SNTT=18, i=j=0)
        if (u_dut.u_encaps.state==6'd18 && u_dut.u_encaps.i_cnt==4'd0 &&
            u_dut.u_encaps.j_cnt==4'd0 && u_dut.u_hash.squeeze_valid &&
            (u_dut.u_encaps.u_sntt.state==4'd5 || u_dut.u_encaps.u_sntt.state==4'd6 ||
             u_dut.u_encaps.u_sntt.state==4'd7))
            $fwrite(f_shake, "%02h ", u_dut.u_hash.squeeze_data);

        // r_hat rows 0..2 in ram1 (ST_WAIT_NTT_R=11 done for i_cnt==2)
        if (u_dut.u_encaps.state==6'd11 && u_dut.u_encaps.i_cnt==4'd2 &&
            u_dut.u_ntt.done && !one_rhat) begin
            one_rhat = 1;
            $display("RHAT ALL t=%0t:", $time);
            for (int ci=0; ci<768; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram1.mem[ci]);
            $write("\n");
        end

        // t_hat rows 0..2 in ram4 (ST_WAIT_T_NTT=5 done for i_cnt==2)
        if (u_dut.u_encaps.state==6'd5 && u_dut.u_encaps.i_cnt==4'd2 &&
            u_dut.u_ntt.done && !one_that) begin
            one_that = 1;
            $display("THAT ALL t=%0t:", $time);
            for (int ci=0; ci<768; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram4.mem[ci]);
            $write("\n");
        end

        // Decoded t (pre-NTT) in ram4 row 0 (ST_DEC_T_W=3, dec_done, i_cnt==0)
        if (u_dut.u_encaps.state==6'd3 && u_dut.u_encaps.dec_done &&
            u_dut.u_encaps.i_cnt==4'd0 && !one_dec) begin
            one_dec = 1;
            $display("DEC0 t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram4.mem[ci]);
            $write("\n");
        end

        // e1 rows 0..2 in ram5 (dump once at first frommont_u done, i_cnt==0)
        if (u_dut.u_encaps.state==6'd51 && u_dut.u_encaps.arith_done &&
            u_dut.u_encaps.i_cnt==4'd0 && !one_e1) begin
            one_e1 = 1;
            $display("E1 ALL t=%0t:", $time);
            for (int ci=0; ci<768; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram5.mem[ci]);
            $write("\n");
        end

        // u accumulator (ram2) at each stage for i_cnt==0
        if (u_dut.u_encaps.state==6'd22 && u_dut.u_encaps.arith_done &&
            u_dut.u_encaps.i_cnt==4'd0 && u_dut.u_encaps.j_cnt==4'd2 && !one_u_hat) begin
            one_u_hat = 1;
            $display("U_HAT_0 t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram2.mem[ci]);
            $write("\n");
        end
        if (u_dut.u_encaps.state==6'd24 && u_dut.u_ntt.done &&
            u_dut.u_encaps.i_cnt==4'd0 && !one_u_mont) begin
            one_u_mont = 1;
            $display("U_MONT_0 t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram2.mem[ci]);
            $write("\n");
        end
        if (u_dut.u_encaps.state==6'd51 && u_dut.u_encaps.arith_done &&
            u_dut.u_encaps.i_cnt==4'd0 && !one_u_fm) begin
            one_u_fm = 1;
            $display("U_FM_0 t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram2.mem[ci]);
            $write("\n");
        end
        if (u_dut.u_encaps.state==6'd26 && u_dut.u_encaps.arith_done &&
            u_dut.u_encaps.i_cnt==4'd0 && !one_u_final) begin
            one_u_final = 1;
            $display("U_FINAL_0 t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram2.mem[ci]);
            $write("\n");
        end

        // v accumulator (ram3) at each stage
        if (u_dut.u_encaps.state==6'd41 && u_dut.u_encaps.arith_done &&
            u_dut.u_encaps.j_cnt==4'd2 && !one_v_hat) begin
            one_v_hat = 1;
            $display("V_HAT t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram3.mem[ci]);
            $write("\n");
        end
        if (u_dut.u_encaps.state==6'd43 && u_dut.u_ntt.done && !one_v_mont) begin
            one_v_mont = 1;
            $display("V_MONT t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram3.mem[ci]);
            $write("\n");
        end
        if (u_dut.u_encaps.state==6'd53 && u_dut.u_encaps.arith_done && !one_v_fm) begin
            one_v_fm = 1;
            $display("V_FM t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram3.mem[ci]);
            $write("\n");
        end
        if (u_dut.u_encaps.state==6'd45 && u_dut.u_encaps.arith_done && !one_v_final) begin
            one_v_final = 1;
            $display("V_FINAL t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram3.mem[ci]);
            $write("\n");
        end
        // e2+mu in ram6
        if (u_dut.u_encaps.state==6'd53 && u_dut.u_encaps.arith_done && !one_e2mu) begin
            one_e2mu = 1;
            $display("E2MU t=%0t:", $time);
            for (int ci=0; ci<256; ci=ci+1)
                $write("%03h ", u_dut.u_encaps.u_ram6.mem[ci]);
            $write("\n");
        end
    end

    initial #50_000_000 begin $display("TIMEOUT"); $finish; end

endmodule
