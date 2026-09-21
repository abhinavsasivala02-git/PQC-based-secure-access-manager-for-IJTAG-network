`timescale 1ns/1ps
// 3-vector FIPS 203 KAT for rtl_mlkem/mlkem_encaps: CT and shared secret K.
// The four ML-KEM hash users (H, G, PRF, SampleNTT) share one Keccak-f[1600]
// core through keccak_shared, exactly as they do in integrated_top.
module tb_kem_kat3;
  reg clk = 0; always #5 clk = ~clk;
  reg rst_n = 0, start = 0;
  reg [255:0] m, exp_ss;
  reg [7:0] pk [0:1183]; reg [7:0] msg [0:31]; reg [7:0] exp_ct [0:1087]; reg [7:0] ssb [0:31];
  reg [7:0] got [0:1087];
  wire done, busy, ct_wen, ss_valid; wire [12:0] ek_raddr, ct_addr; wire [7:0] ct_wdata; wire [255:0] ss;

  // shared Keccak: users {sntt, prf, g, h}
  wire [3:0]      kreq, kbusy, kdone;
  wire [4*1600-1:0] kdin;
  wire [1599:0]   kdout;
  wire h_req, g_req, prf_req, sntt_req;
  wire [1599:0] h_din, g_din, prf_din, sntt_din;
  assign kreq = {sntt_req, prf_req, g_req, h_req};
  assign kdin = {sntt_din, prf_din, g_din, h_din};

  keccak_shared #(.N(4)) u_kec (
    .clk(clk), .rst_n(rst_n), .req(kreq), .din(kdin),
    .busy(kbusy), .done(kdone), .dout(kdout)
  );

  mlkem_encaps #(.K(3),.ETA1(2),.ETA2(2),.DU(10),.DV(4)) dut(
    .clk(clk),.rst_n(rst_n),.start(start),.m_random(m),
    .done(done),.busy(busy),.ek_rdata(pk[ek_raddr]),.ek_raddr(ek_raddr),
    .ct_wen(ct_wen),.ct_addr(ct_addr),.ct_wdata(ct_wdata),
    .ss_valid(ss_valid),.shared_secret(ss),
    .h_kec_req(h_req),       .h_kec_din(h_din),
    .h_kec_busy(kbusy[0]),   .h_kec_done(kdone[0]),   .h_kec_dout(kdout),
    .g_kec_req(g_req),       .g_kec_din(g_din),
    .g_kec_busy(kbusy[1]),   .g_kec_done(kdone[1]),   .g_kec_dout(kdout),
    .prf_kec_req(prf_req),   .prf_kec_din(prf_din),
    .prf_kec_busy(kbusy[2]), .prf_kec_done(kdone[2]), .prf_kec_dout(kdout),
    .sntt_kec_req(sntt_req), .sntt_kec_din(sntt_din),
    .sntt_kec_busy(kbusy[3]),.sntt_kec_done(kdone[3]),.sntt_kec_dout(kdout)
  );

  always @(posedge clk) if (ct_wen) got[ct_addr] <= ct_wdata;
  integer v, i, bad, fails = 0, t0;
  initial begin
    for (v = 0; v < 3; v = v + 1) begin
      case (v)
        0: begin $readmemh("kat_pk0.mem", pk); $readmemh("kat_msg0.mem", msg); $readmemh("kat_ct0.mem", exp_ct); $readmemh("kat_ss0.mem", ssb); end
        1: begin $readmemh("kat_pk1.mem", pk); $readmemh("kat_msg1.mem", msg); $readmemh("kat_ct1.mem", exp_ct); $readmemh("kat_ss1.mem", ssb); end
        2: begin $readmemh("kat_pk2.mem", pk); $readmemh("kat_msg2.mem", msg); $readmemh("kat_ct2.mem", exp_ct); $readmemh("kat_ss2.mem", ssb); end
      endcase
      for (i = 0; i < 32; i = i + 1) begin m[i*8 +: 8] = msg[i]; exp_ss[i*8 +: 8] = ssb[i]; end
      rst_n = 0; repeat (5) @(posedge clk); rst_n = 1; @(posedge clk);
      start = 1; t0 = $time; @(posedge clk); start = 0;
      wait (done); @(posedge clk);
      bad = 0;
      for (i = 0; i < 1088; i = i + 1) if (got[i] !== exp_ct[i]) bad = bad + 1;
      if (ss !== exp_ss) bad = bad + 1000;
      $display("vec %0d: cycles=%0d ct_bad=%0d ss_ok=%0d", v, ($time - t0) / 10, bad % 1000, ss === exp_ss);
      if (bad) fails = fails + 1;
    end
    if (fails == 0) $display("RTL-KEM-KAT3 PASS: 3/3 vectors (CT + K) match FIPS 203 reference");
    else            $display("RTL-KEM-KAT3 FAIL: %0d/3 vectors", fails);
    $finish;
  end
endmodule
