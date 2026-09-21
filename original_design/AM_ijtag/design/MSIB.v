// MSIB.v -- Multi-drop Segment Insertion Bit: a SiB variant where the
// captured update_cell value (update_cell, latched on negedge tck) both
// drives the downstream select_o and passes TDI1 straight through to
// to_TDI2, letting one bit gate a chain of multiple downstream segments.
module MSIB(
    input wire tck,rst,
    input  wire TDI1, select_i, shiften, updateen, from_tdo2,
    output  wire TDO1, to_TDI2, select_o
    );

//wire m_in_1, m_in_2, m_in_3;
reg shift_cell;
reg update_cell;
wire m_out_1,m_out_2,m_out_3;

/*
and a1(m_in_1, captureen, select);
and a2(m_in_2, shiften, select);
and a3(m_in_3, updateen, select); 


assign m_out_1=(select_i)?(from_TDO2):TDI1;
assign m_out_2=(shiften)?(m_out_1):(shift_cell);
assign m_out_3=(updateen)?(shift_cell):(update_cell);
*/

mux21 m1(.a(from_tdo2), .b(TDI1), .s(select_i), .y(m_out_1));
mux21 m2(.a(m_out_1), .b(shift_cell), .s(shiften), .y(m_out_2));
mux21 m3(.a(shift_cell), .b(update_cell), .s(updateen), .y(m_out_3));

always@(posedge tck or posedge rst)
    begin
        if(rst)
            shift_cell<= 0;
        else
            shift_cell<= m_out_2;
    end
    
always@(negedge tck or posedge rst)
    begin
        if(rst)
            update_cell<=0;
        else
            update_cell<=m_out_3;
    end
    

assign TDO1 = shift_cell;
assign to_TDI2 = TDI1;
assign select_o = update_cell;

endmodule