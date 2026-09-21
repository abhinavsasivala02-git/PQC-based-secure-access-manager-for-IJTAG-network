//============================================================================
// Testbench for ML-KEM Encapsulation
// ML-KEM-768 with K=3, ETA2=2, DU=10, DV=4
//============================================================================
`timescale 1ns/1ps

module tb_mlkem_encaps;

    // DUT ports
    reg         clk;
    reg         rst_n;
    reg         start;
    wire        done;
    wire        busy;
    reg  [255:0] m_seed;
    reg  [255:0] r_seed;
    wire [12:0] ek_addr;
    wire [7:0]  ek_rdata;
    wire        ct_valid;
    wire [7:0]  ct_data;
    wire [12:0] ct_addr;

    //=========================================================================
    // Instantiate DUT
    //=========================================================================
    mlkem_encaps_top #(
        .K(3), .ETA2(2), .DU(10), .DV(4)
    ) u_dut (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (start),
        .done     (done),
        .busy     (busy),
        .m_seed   (m_seed),
        .r_seed   (r_seed),
        .ek_addr  (ek_addr),
        .ek_rdata (ek_rdata),
        .ct_valid (ct_valid),
        .ct_data  (ct_data),
        .ct_addr  (ct_addr)
    );

    //=========================================================================
    // Mock encapsulation key ROM (EK_BYTES = 1184 for K=3)
    // ek = t_hat_bytes (1152 bytes) || rho (32 bytes)
    // rho at addresses 1152-1183
    //=========================================================================
    reg [7:0] ek_mem [0:1183];
    integer i;

    assign ek_rdata = ek_mem[ek_addr];

    //=========================================================================
    // Ciphertext capture
    //=========================================================================
    reg [7:0] ct_mem [0:1087];  // CT_BYTES for K=3 = 1088
    integer ct_count;

    always @(posedge clk) begin
        if (ct_valid) begin
            ct_mem[ct_addr] <= ct_data;
            ct_count <= ct_count + 1;
        end
    end

    //=========================================================================
    // Clock generation: 10ns period (100 MHz)
    //=========================================================================
    initial clk = 0;
    always #5 clk = ~clk;

    //=========================================================================
    // Test sequence
    //=========================================================================
    reg [255:0] expected_ct [0:3]; // 4 x 32-byte chunks for comparison

    task wait_cycles;
        input [31:0] n;
        repeat(n) @(posedge clk);
    endtask

    // The FSM raises hash_init with hash_cfg_rate/digit set. The hash engine
    // then has latency before it becomes not busy and then starts absorbing.
    // The FSM waits for hash_absorb_ready in ST_WAIT_PRF_R.
    // The hash f1600 engine has 24 rounds. Each round takes 1 cycle.
    // So typical SHAKE init + absorb then squeeze takes hundreds of cycles.

    // For ML-KEM-768: K=3, N=256, DU=10, DV=4
    // Expected CT size = K * 32 * DU / 8 + 32 * DV / 8 = 3*320 + 128 = 1088 bytes

    initial begin
        $display("=========================================");
        $display("ML-KEM-768 Encapsulation Testbench");
        $display("=========================================");

        ct_count = 0;

        // Initialize ek memory with random-like data
        for (i = 0; i < 1184; i = i + 1)
            ek_mem[i] = i[7:0] ^ 8'hA5;

        // Test vectors (arbitrary)
        m_seed = 256'hCAFE_1234_5678_9ABC_DEF0_0123_4567_89AB_CDEF_FEDC_BA98_7654_3210_0123_4567_89AB;
        r_seed = 256'hDEAD_BEEF_0000_1111_2222_3333_4444_5555_6666_7777_8888_9999_AAAA_BBBB_CCCC_DDDD;

        // Reset
        rst_n = 0;
        start = 0;
        #100;
        rst_n = 1;
        wait_cycles(10);

        // Start encapsulation
        $display("Starting encapsulation at time %0t", $time);
        @(posedge clk);
        start = 1;
        @(posedge clk);
        start = 0;

        // Wait for done
        wait(done == 1);
        $display("Encapsulation DONE at time %0t", $time);
        $display("CT bytes captured: %0d", ct_count);

        // Print captured ciphertext
        $display("-----------------------------------------");
        $display("Ciphertext (first 64 bytes):");
        for (i = 0; i < 64; i = i + 1) begin
            if (i % 16 == 0) $write("\n  %03d: ", i);
            $write("%02x ", ct_mem[i]);
        end
        $display("\n");

        $display("=========================================");
        $display("Testbench completed");
        $display("=========================================");
        #100;
        $finish;
    end

    //=========================================================================
    // Timeout
    //=========================================================================
    initial begin
        #10000000;  // 10ms timeout
        $display("TIMEOUT reached!");
        $finish;
    end

endmodule
