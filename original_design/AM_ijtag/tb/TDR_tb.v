// Simple Testbench for TDR IJTAG with Inverter Instrument
// Send 8 bits through TDI and observe inverted output through TDO



module TDR_tb;

    // Parameters
    parameter DATA_WIDTH = 8;
    parameter CLK_PERIOD = 10;
    
    // Signals
    reg                    clk;
    reg                    tck;
    reg                    rst_n;
    reg                    trst_n;
    reg                    tdi;
    wire                   tdo;
    reg                    shift_dr;
    reg                    update_dr;
    
    // Interface between TDR and Inverter
    wire [DATA_WIDTH-1:0]  tdr_to_inv;
    wire [DATA_WIDTH-1:0]  inv_to_tdr;
    wire                   tdr_valid;
    
    // Select enable control - set high to enable TDR operation
    reg                    select_enable;
    
    // Test data
    reg [DATA_WIDTH-1:0] tdo_data = 0;
    reg [DATA_WIDTH-1:0] input_data = 8'hA5;  // Test pattern
    integer i;
    wire output_mode;
    // Instantiate TDR module
    TDR #(
        .DATA_WIDTH(DATA_WIDTH),
        .RESET_VALUE(8'h00)
    ) tdr (
        .tck(tck),
        .trst_n(trst_n),
        .tdi(tdi),
        .tdo(tdo),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
        .inst_data_out(tdr_to_inv),
        .inst_data_in(inv_to_tdr),
        .inst_valid(tdr_valid),
        .select_en(select_enable),
        .output_mode(output_mode)
    );
    
    // Instantiate Inverter Instrument
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    always #(CLK_PERIOD*2) tck = ~tck;
    
    // Test sequence
    initial begin
        // Initialize
        clk = 0; tck = 0; rst_n = 1; trst_n = 1;
        tdi = 0; shift_dr = 0; update_dr = 0;
        select_enable = 0;  // Start with TDR disabled
        
        $display("=== TDR with Inverter Test ===");
        $display("Input:  0x%02X (%08b)", input_data, input_data);
        $display("Expected: 0x%02X (%08b)", ~input_data, ~input_data);
        
        // Reset
        #50 rst_n = 0; trst_n = 0;
        #20;
        
        // Enable TDR operation
        select_enable = 1;
        $display("\nTDR Enabled (select_en = 1)");
        #20;
        
        // Send data through TDI
        $display("\nSending data through TDI...");
        shift_dr = 1;
        for (i = DATA_WIDTH-1; i >= 0; i = i-1) begin
            tdi = input_data[i];
            #(CLK_PERIOD*4);
        end
        shift_dr = 0; tdi = 0;
        #20;
        
        // Update to send to instrument
        update_dr = 1;
        #(CLK_PERIOD*4);
        update_dr = 0;
        #80;  // Wait longer for instrument processing and capture_next cycle
        
        // Read output serially from TDO
        $display("Reading inverted data from TDO...");
        shift_dr = 1;
        
        
        for (i = 0; i < DATA_WIDTH; i = i+1) begin
            tdo_data[i] = tdo;  // Capture TDO (LSB first)
            $display("TDO bit %0d: %b", i, tdo);
            #(CLK_PERIOD*4);  // Clock to shift next bit
        end
        shift_dr = 0;
        #20;
        
        // Display results
        $display("\nResults:");
        $display("Input:         0x%02X (%08b)", input_data, input_data);
        $display("Instrument in: 0x%02X (%08b)", tdr_to_inv, tdr_to_inv);
        $display("Instrument out:0x%02X (%08b)", inv_to_tdr, inv_to_tdr);
        $display("Expected:      0x%02X (%08b)", ~input_data, ~input_data);
        $display("TDO output:    0x%02X (%08b)", tdo_data, tdo_data);
        $display("Select Enable: %b", select_enable);
        
        if (tdo_data == ~input_data)
            $display("✓ PASS: TDR and Inverter working correctly!");
        else
            $display("✗ FAIL: Expected 0x%02X, got 0x%02X", ~input_data, tdo_data);
            
        $finish;
    end

endmodule
