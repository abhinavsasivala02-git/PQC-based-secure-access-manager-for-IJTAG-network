`timescale 1ns / 1ps

module AM_tb();

    // Testbench signals
    reg clk;
    reg reset;
    reg TDI;
    reg shift_en;
    wire TDI_out;
    wire [1:0] mux_sel;
    wire mux_sel_21;
    wire DVAL;
    
    // Instantiate the Unit Under Test (UUT)
    AM uut (
        .clk(clk),
        .reset(reset),
        .TDI(TDI),
        .shift_en(shift_en),
        .TDI_out(TDI_out),
        .mux_sel(mux_sel),
        .mux_sel_21(mux_sel_21),
        .DVAL(DVAL)
    );
    
    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk; // 100MHz clock (10ns period)
    end
    
    // Task to shift in 95 bits of data
    task shift_95_bits;
        input [94:0] data;
        integer i;
        begin
            shift_en = 1;
            for (i = 0; i < 95; i = i + 1) begin
                TDI = data[i];
                #10; // Wait one clock cycle
            end
            shift_en = 0;
        end
    endtask
    
    // Test stimulus
    initial begin
        // Initialize signals
        reset = 1;
        TDI = 0;
        shift_en = 0;
        
        // Wait for a few clock cycles
        #20;
        
        // Release reset
        reset = 0;
        #10;
        
        $display("Starting AM testbench...");
        
        // Test Case 1: Basic reset functionality
        $display("Test 1: Reset functionality");
        reset = 1;
        #20;
        reset = 0;
        #20;
        
        // Test Case 2: Shift in 95-bit test data
        $display("Test 2: Shifting in 95-bit data");
        // Create 95-bit test data: key(32) + inst(32) + data(31)
        // key = 32'h00ABCDEF, inst = 32'h01ABCDEF, data = 31'h01ABCDEF
        shift_95_bits({32'h00ABCDEF, 32'h01ABCDEF,31'h01ABCDEF });
        #40; // Wait for processing
        
        // Test Case 3: Verify UNLOCK state - TDI passthrough
        $display("Test 3: UNLOCK state - TDI passthrough");
        TDI = 0;
        #10;
        TDI = 1;
        #10;
        TDI = 0;
        #10;
        TDI = 1;
        #10;
        TDI = 1;
        #10;
        TDI = 0;
        #10
        TDI = 1;
        #10
        
        // Test Case 4: Test with wrong key
      
        
        $display("Testbench completed successfully!");
        #100;
        $finish;
    end
    
    // Monitor important signals including TDR outputs
    initial begin
        $monitor("Time=%0t | State=%b | TDI=%b | TDI_out=%b | mux_sel=%b | LVAL=%b | IVAL=%b | DVAL=%b | full=%b | key_out=%h | inst_out=%h", 
                 $time, uut.state_reg, TDI, TDI_out, mux_sel, uut.LVAL, uut.IVAL, uut.DVAL, uut.full, uut.key_out, uut.inst_out);
    end


  

endmodule
