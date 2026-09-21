`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.07.2025 14:31:35
// Design Name: 
// Module Name: TDR_95
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 95-bit Test Data Register: shifts in a 32-bit key,
//              32-bit instruction, and 31-bit data field from tdi (in that
//              order), asserting full once all 95 bits have been shifted.
//              Early prototype of the unlock-frame register later
//              generalized as TDR.v / used for the PQC unlock frame.
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

module TDR_95(
  input  wire        clk,
  input  wire        rst,
  input  wire        shift_en,
  input  wire        tdi,
  output reg  [31:0] key_out,
  output reg  [31:0] instruction_out,
  output reg  [30:0] data_out,
  output reg         full
);

  reg [94:0] shift_reg;
  reg [6:0]  bit_count;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      shift_reg       <= 95'd0;
      bit_count       <= 7'd0;
      key_out         <= 32'd0;
      instruction_out <= 32'd0;
      data_out        <= 31'd0;
      full            <= 1'b0;
    end else begin
      full <= 1'b0; // default

      if (shift_en) begin
        shift_reg <= {shift_reg[93:0], tdi};
        bit_count <= bit_count + 1;

        // Delay extraction by 1 cycle after full data has been shifted in
        if (bit_count == 7'd94) begin
          full <= 1'b1;
        end
      end

      if (bit_count == 7'd95) begin
        // Extract after full 95 bits have entered
        key_out         <= shift_reg[94:63];
        instruction_out <= shift_reg[62:31];
        data_out        <= shift_reg[30:0];
      end
    end
  end

endmodule


