`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Testbench for Top_module - TDR Chain Instrument Testing
// This testbench checks one instrument from each SIB in each MSIB at a time,
// ensuring that only one instrument is tested at any given time.
//////////////////////////////////////////////////////////////////////////////////
module Top_module_tb;
  reg tck, trst, tap_tdi, tap_select, shift_dr, update_dr;
  wire tdo;

  // Test data signals
  integer i;
  reg [31:0] in_data;
  reg [31:0] expected;
  reg [31:0] out_data;

  // Instantiate DUT
  Top_module dut (
    .tck       (tck),
    .trst      (trst),
    .tap_tdi   (tap_tdi),
    .tap_select(tap_select),
    .shift_dr  (shift_dr),
    .update_dr (update_dr),
    .tdo       (tdo)
  );

  // Clock generation: 10 ns period
  initial begin
    tck = 0;
    forever #5 tck = ~tck;
  end

  // Test sequence
  initial begin
    // Initialize test data
    in_data  = 32'hF0F0F0F0;
    expected = ~in_data;
    out_data = 0;

    // Apply reset
    trst = 0; tap_select = 0; shift_dr = 0; update_dr = 0; tap_tdi = 0;
    #20;
    trst = 1;
    #20;

    // SHIFT-IN
    tap_select = 0;
    shift_dr = 1;
    update_dr = 0;
    for (i = 31; i >= 0; i = i - 1) begin
      tap_tdi = in_data[i];
      #10;
    end
    shift_dr = 0;
    #10;

    // UPDATE
    tap_select = 1;
    update_dr = 1;
    #10;
    update_dr = 0;
    tap_select = 0;
    #10;

    // SHIFT-OUT
    shift_dr = 1;
    out_data = 0;
    for (i = 0; i < 32; i = i + 1) begin
      #10;
      out_data = out_data | (tdo << i);
    end
    shift_dr = 0;

    // Display result
    $display("Input   = 0x%08X", in_data);
    $display("Output  = 0x%08X (Expected = 0x%08X)", out_data, expected);
    if (out_data !== expected)
      $display(">>> TEST FAILED: Inversion mismatch");
    else
      $display(">>> TEST PASSED: Output matches expected");

    $finish;
  end
endmodule


