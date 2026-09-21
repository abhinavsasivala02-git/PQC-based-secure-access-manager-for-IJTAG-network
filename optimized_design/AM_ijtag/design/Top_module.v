`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 01.07.2025 14:13:27
// Design Name: 
// Module Name: Top_module
// Project Name:
// Target Devices:
// Tool Versions:
// Description: Baseline IJTAG chain top level - wires 3 MSIBs and 6 SiBs
//              into a single scan chain off the standard TAP signals
//              (tap_tdi/tap_select/shift_dr/update_dr), the pre-PQC chain
//              that PQC_integrated/design/integrated_top.v builds on.
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module Top_module(
    input wire tck,trst,
    input wire tap_tdi,tap_select,shift_dr,update_dr,
    output wire tdo
    );

wire temp_msib1_tdo1,temp_msib2_tdo1,temp_msib3_tdo1;
wire temp_msib1_tdi2,temp_msib2_tdi2,temp_msib3_tdi2;
wire msib1_select,msib2_select,msib3_select;
wire sib1_select,sib2_select,sib3_select,sib4_select,sib5_select,sib6_select;
wire temp_sib1_tdo1,temp_sib2_tdo1,temp_sib3_tdo1,temp_sib4_tdo1,temp_sib5_tdo1,temp_sib6_tdo1;
wire temp_sib1_tdi2,temp_sib2_tdi2,temp_sib3_tdi2,temp_sib4_tdi2,temp_sib5_tdi2,temp_sib6_tdi2;
wire temp_tdr1_tdo,temp_tdr2_tdo,temp_tdr3_tdo,temp_tdr4_tdo,temp_tdr5_tdo,temp_tdr6_tdo;
wire [31:0]tdr1_t0_inst1,tdr2_t0_inst2,tdr3_t0_inst3,tdr4_t0_inst4,tdr5_t0_inst5,tdr6_t0_inst6;
wire [31:0]inst1_to_tdr1,inst2_to_tdr2,inst3_to_tdr3,inst4_to_tdr4,inst5_to_tdr5,inst6_to_tdr6;
wire tdr1_valid,tdr2_valid,tdr3_valid,tdr4_valid,tdr5_valid,tdr6_valid;

wire DATA_WIDTH=32;

MSIB msib1(.tck(tck),.rst(trst),.TDI1(tap_tdi),.select_i(tap_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_sib2_tdo1),.TDO1(temp_msib1_tdo1),.to_TDI2(temp_msib1_tdi2),.select_o(msib1_select));
SiB sib1(.tck(tck),.rst(trst),.TDI1(temp_msib1_tdi2),.select_i(msib1_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_tdr1_tdo),.TDO1(temp_sib1_tdo1),.to_TDI2(temp_sib1_tdi2),.select_o(sib1_select));
TDR #(
        .DATA_WIDTH(32),
        .RESET_VALUE(8'h00)
    ) tdr1 (
        .tck(tck),
        .trst_n(trst),
        .tdi(temp_sib1_tdi2),
        .tdo(temp_tdr1_tdo),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
        .inst_data_out(tdr1_t0_inst1),
        .inst_data_in(inst1_to_tdr1),
        .inst_valid(tdr1_valid),
        .select_en(sib1_select)
    );
inst #(.DATA_WIDTH(32)) inv1 (.data_in(tdr1_t0_inst1),.data_out(inst1_to_tdr1));

SiB sib2(.tck(tck),.rst(trst),.TDI1(temp_sib1_tdo1),.select_i(msib1_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_tdr2_tdo),.TDO1(temp_sib2_tdo1),.to_TDI2(temp_sib2_tdi2),.select_o(sib2_select));
TDR #(
        .DATA_WIDTH(32),
        .RESET_VALUE(8'h00)
    ) tdr2 (
        .tck(tck),
        .trst_n(trst),
        .tdi(temp_sib2_tdi2),
        .tdo(temp_tdr2_tdo),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
        .inst_data_out(tdr2_t0_inst2),
        .inst_data_in(inst2_to_tdr2),
        .inst_valid(tdr2_valid),
        .select_en(sib2_select)
    );
inst #(.DATA_WIDTH(32)) inv2 (.data_in(tdr2_t0_inst2),.data_out(inst2_to_tdr2));


MSIB msib2(.tck(tck),.rst(trst),.TDI1(temp_msib1_tdo1),.select_i(tap_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_sib4_tdo1),.TDO1(temp_msib2_tdo1),.to_TDI2(temp_msib2_tdi2),.select_o(msib2_select));
SiB sib3(.tck(tck),.rst(trst),.TDI1(temp_msib2_tdi2),.select_i(msib2_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_tdr3_tdo),.TDO1(temp_sib3_tdo1),.to_TDI2(temp_sib3_tdi2),.select_o(sib3_select));
TDR #(
        .DATA_WIDTH(32),
        .RESET_VALUE(8'h00)
    ) tdr3 (
        .tck(tck),
        .trst_n(trst),
        .tdi(temp_sib3_tdi2),
        .tdo(temp_tdr3_tdo),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
        .inst_data_out(tdr3_t0_inst3),
        .inst_data_in(inst3_to_tdr3),
        .inst_valid(tdr3_valid),
        .select_en(sib3_select)
    );
inst #(.DATA_WIDTH(32)) inv3 (.data_in(tdr3_t0_inst3),.data_out(inst3_to_tdr3));

SiB sib4(.tck(tck),.rst(trst),.TDI1(temp_sib3_tdo1),.select_i(msib2_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_tdr4_tdo),.TDO1(temp_sib4_tdo1),.to_TDI2(temp_sib4_tdi2),.select_o(sib4_select));
TDR #(
        .DATA_WIDTH(32),
        .RESET_VALUE(8'h00)
    ) tdr4 (
        .tck(tck),
        .trst_n(trst),
        .tdi(temp_sib4_tdi2),
        .tdo(temp_tdr4_tdo),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
        .inst_data_out(tdr4_t0_inst4),
        .inst_data_in(inst4_to_tdr4),
        .inst_valid(tdr4_valid),
        .select_en(sib4_select)
    );
inst #(.DATA_WIDTH(32)) inv4 (.data_in(tdr4_t0_inst4),.data_out(inst4_to_tdr4));


MSIB msib3(.tck(tck),.rst(trst),.TDI1(temp_msib2_tdo1),.select_i(tap_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_sib6_tdo1),.TDO1(temp_msib3_tdo1),.to_TDI2(temp_msib3_tdi2),.select_o(msib3_select));
SiB sib5(.tck(tck),.rst(trst),.TDI1(temp_msib3_tdi2),.select_i(msib3_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_tdr5_tdo),.TDO1(temp_sib5_tdo1),.to_TDI2(temp_sib5_tdi2),.select_o(sib5_select));
TDR #(
        .DATA_WIDTH(32),
        .RESET_VALUE(8'h00)
    ) tdr5 (
        .tck(tck),
        .trst_n(trst),
        .tdi(temp_sib5_tdi2),
        .tdo(temp_tdr5_tdo),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
        .inst_data_out(tdr5_t0_inst5),
        .inst_data_in(inst5_to_tdr5),
        .inst_valid(tdr5_valid),
        .select_en(sib5_select)
    );
inst #(.DATA_WIDTH(32)) inv5 (.data_in(tdr5_t0_inst5),.data_out(inst5_to_tdr5));

SiB sib6(.tck(tck),.rst(trst),.TDI1(temp_sib5_tdo1),.select_i(msib3_select),.shiften(shift_dr),.updateen(update_dr),.from_tdo2(temp_tdr6_tdo),.TDO1(temp_sib6_tdo1),.to_TDI2(temp_sib6_tdi2),.select_o(sib6_select));
TDR #(
        .DATA_WIDTH(32),
        .RESET_VALUE(8'h00)
    ) tdr6 (
        .tck(tck),
        .trst_n(trst),
        .tdi(temp_sib6_tdi2),
        .tdo(temp_tdr6_tdo),
        .shift_dr(shift_dr),
        .update_dr(update_dr),
        .inst_data_out(tdr6_t0_inst6),
        .inst_data_in(inst6_to_tdr6),
        .inst_valid(tdr6_valid),
        .select_en(sib6_select)
    );
inst #(.DATA_WIDTH(32)) inv6 (.data_in(tdr6_t0_inst6),.data_out(inst6_to_tdr6));

assign tdo = temp_msib3_tdo1;
endmodule
