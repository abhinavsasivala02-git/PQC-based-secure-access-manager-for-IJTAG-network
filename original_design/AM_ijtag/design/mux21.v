`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 30.06.2025 15:40:06
// Design Name: 
// Module Name: mux21
// Project Name:
// Target Devices:
// Tool Versions:
// Description: 2-to-1 mux: y = s ? a : b. Used to select the TDO source
//              between IJTAG chain segments.
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module mux21(
    input wire a, b, s,
    output y
    );
assign y = (s)?a:b;
    
endmodule
