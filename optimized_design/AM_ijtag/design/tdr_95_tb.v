`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.07.2025 14:33:02
// Design Name: 
// Module Name: tdr_95_tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module tdr_95_tb;

  reg clk;
  reg rst;
  reg shift_en;
  reg tdi;

  wire [31:0] key_out;
  wire [31:0] instruction_out;
  wire [30:0] data_out;
  wire        full;

  // Instantiate the DUT (Device Under Test)
  TDR_95 dut (
    .clk(clk),
    .rst(rst),
    .shift_en(shift_en),
    .tdi(tdi),
    .key_out(key_out),
    .instruction_out(instruction_out),
    .data_out(data_out),
    .full(full)
  );

  // Test vector (95 bits): [KEY|INSTR|DATA]
  // KEY         = 32'hA5A5A5A5
  // INSTRUCTION = 32'h5A5A5A5A
  // DATA        = 31'h12345678 (only lower 31 bits)
  reg [94:0] test_vector = {
    32'hA5A5A5A5,        // key
    32'h5A5A5A5A,        // instruction
    31'b0001001000110100010101100111100   // data
  };

  integer i;

  // Clock generation
  always #5 clk = ~clk;  // 100 MHz

  initial begin
    $display("Starting testbench...");
    clk = 0;
    rst = 1;
    shift_en = 0;
    tdi = 0;

    // Reset the design
    #10 rst = 0;

    // Shift in 95 bits from MSB to LSB
    for (i = 94; i >= 0; i = i - 1) begin
      @(negedge clk);
      tdi = test_vector[i];
      shift_en = 1;
    end

    // Finish shifting
    @(negedge clk);
    shift_en = 0;

    // Wait for outputs
    @(posedge full);
    #1;

    $finish;
  end

endmodule

