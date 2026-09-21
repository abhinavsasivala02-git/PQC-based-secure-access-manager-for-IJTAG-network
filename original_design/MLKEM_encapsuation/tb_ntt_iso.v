`timescale 1ns/1ps

// Isolated NTT core test: preload ram with f[i] = i mod 7, run forward NTT,
// dump full input and output to compare vs Python reference.
module tb_ntt_iso;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n, start, mode;
    wire busy, done;
    wire [11:0] ram_rdata_a, ram_rdata_b;
    reg  ram_wen;
    reg [7:0] ram_addr_a, ram_addr_b;
    reg [11:0] ram_wdata_a;

    mlkem_ntt_core u_ntt (
        .clk(clk), .rst_n(rst_n),
        .start(start), .mode(mode), .done(done), .busy(busy),
        .ram_wen(ram_wen), .ram_addr_a(ram_addr_a), .ram_wdata_a(ram_wdata_a),
        .ram_rdata_a(ram_rdata_a), .ram_addr_b(ram_addr_b), .ram_rdata_b(ram_rdata_b)
    );

    mlkem_poly_ram u_ram (
        .clk(clk), .a_wen(ram_wen), .a_addr(ram_addr_a), .a_wdata(ram_wdata_a),
        .a_rdata(ram_rdata_a), .b_addr(ram_addr_b), .b_rdata(ram_rdata_b)
    );

    integer i;
    integer bfl_cnt = 0;

    // Probe the first butterflies of the FIRST run (forward mode)
    always @(posedge clk) begin
        if (u_ntt.state == 4'd4 && bfl_cnt < 12) begin
            $display("BFLY k=%0d z=%0d aaddr=%0d baddr=%0d a=%0d b=%0d t=%0d aout=%0d bout=%0d",
                     u_ntt.k, u_ntt.zeta_val,
                     u_ntt.ram_addr_a, u_ntt.ram_addr_b,
                     u_ntt.bfly_a_in, u_ntt.bfly_b_in,
                     u_ntt.ct_t,
                     u_ntt.bfly_a_out, u_ntt.bfly_b_out);
            bfl_cnt = bfl_cnt + 1;
        end
    end

    initial begin
        rst_n = 0; start = 0; mode = 0;
        #100 rst_n = 1;
        #50;
        for (i = 0; i < 256; i = i + 1) begin
            u_ram.mem[i] = i % 7;
        end
        $display("INPUT:");
        for (i = 0; i < 256; i = i + 1)
            $write("%03h ", u_ram.mem[i]);
        $write("\n");
        start = 1; #20 start = 0;
        wait (done);
        $display("OUTPUT:");
        for (i = 0; i < 256; i = i + 1)
            $write("%03h ", u_ram.mem[i]);
        $write("\n");
        // Inverse NTT round-trip
        mode = 1;
        start = 1; #20 start = 0;
        wait (done);
        $display("ROUNDTRIP:");
        for (i = 0; i < 256; i = i + 1)
            $write("%03h ", u_ram.mem[i]);
        $write("\n");
        $finish;
    end

endmodule