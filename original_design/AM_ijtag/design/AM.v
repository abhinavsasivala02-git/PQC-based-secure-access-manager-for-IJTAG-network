`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07.07.2025 12:26:21
// Design Name: 
// Module Name: AM
// Project Name:
// Target Devices:
// Tool Versions:
// Description: Baseline (pre-PQC) IJTAG Access Manager. Shifts TDI through
//              the SiB/MSIB chain on shift_en, selects which cluster mux
//              (mux_sel/mux_sel_21) is active, and asserts DVAL once the
//              scan operation completes.
//
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////
module AM(
input clk,
input reset,
input TDI, shift_en,
output reg TDI_out,
output reg[1:0] mux_sel,
output reg mux_sel_21,
output reg DVAL
);

   wire  [31:0] key_out;
   wire  [31:0] inst_out;
   wire  [30:0] data_out;
   wire         full;
   
   reg LVAL, IVAL;
   wire [31:0] TRNG ;
   wire [31:0] expected_key[3:0] , expected_inst[3:0];
   wire [30:0] expected_data[3:0] ;
   reg key_state;
   
   assign TRNG = 32'h0EDCBA00;
   assign expected_key[0] = 32'hf7b3d581;// valid is 32'hf7b3d581
   assign expected_key[1] = 32'hf7b3d581;
   assign expected_key[2] = 32'hf7b3d581;
   assign expected_key[3] = 32'hf7b3d581; 
   
   assign expected_inst[0] = 32'hef67ab01;// valid is 32'hef67ab01 this is for char/eval
   assign expected_inst[1] = 32'hef67ab02;// prod
   assign expected_inst[2] = 32'hef67ab02;//inf
   assign expected_inst[3] = 32'hef67ab02;//soft emb
   
   assign expected_data[0] = 31'h77b3d500;// valid is 31'h77b3d500 this is for char/eval
   assign expected_data[1] = 31'h77b3d500;// production
   assign expected_data[2] = 31'h77b3d500;// infield
   assign expected_data[3] = 31'h77b3d500;// software embedded
   
   
   
TDR_95 TDR(.clk(clk), .rst(reset), .shift_en(shift_en), .tdi(TDI), 
           .key_out(key_out), .instruction_out(inst_out), .data_out(data_out), .full(full));

localparam [2:0] LOCK = 3'b000 , STORE = 3'b001 , KEY_COMP = 3'b010 , INST_COMP = 3'b011 , DATA_COMP = 3'b100 , UNLOCK = 3'b101 ;

reg [2:0] state_reg , next_state ;

// Sequential block for state register
always@(posedge clk, posedge reset)begin 
    if(reset)
        state_reg <= LOCK ;
    else 
        state_reg <= next_state;
end

// Sequential block for mux_sel register - holds value across states
always@(posedge clk, posedge reset)begin 
    if(reset)begin
        mux_sel <= 2'b00;
        mux_sel_21<=1'b0;
        end
    else if(state_reg == INST_COMP) begin
        if(expected_inst[0] == inst_out)begin
            mux_sel <= 2'b00;
            mux_sel_21<=1'b1;
            end
        else if(expected_inst[1] == inst_out)begin
            mux_sel <= 2'b01;
            mux_sel_21<=1'b0;
            end
        else if(expected_inst[2] == inst_out)begin
            mux_sel <= 2'b10;
            mux_sel_21<=1'b0;
            end
        else if(expected_inst[3] == inst_out)begin
            mux_sel <= 2'b11;
            mux_sel_21<=1'b0;
            end
    end
    // mux_sel retains its value in all other states
end

always@(*) begin
    next_state =  state_reg;
    TDI_out = 0;
    key_state = 0;
    IVAL = 0;        // Default assignment to prevent latch
    DVAL = 0;        // Default assignment to prevent latch
    LVAL = 0;        // Default assignment to prevent latch
    
    case(state_reg)
        LOCK: begin
                IVAL = 0;        // Default assignment to prevent latch
                DVAL = 0;        // Default assignment to prevent latch
                LVAL = 0;
                next_state = STORE;
                end
        STORE: begin 
               if(full)
                    next_state = KEY_COMP;
               else 
                    next_state = STORE; 
               end
        KEY_COMP: begin
                  if(key_state)begin
                    if(key_out == TRNG)begin
                        LVAL = 1;
                        next_state =  INST_COMP;
                        end  
                    else 
                        next_state = LOCK;
                  end
   
                  else begin
                        if ((expected_key[0] == key_out)|(expected_key[1] == key_out)|(expected_key[2] == key_out)|(expected_key[3] == key_out))begin
                            LVAL = 1;
                            next_state =  INST_COMP;
                        end
                        else 
                            next_state = LOCK;    
                   end
                 end             
        INST_COMP:begin  
                    if(expected_inst[0] == inst_out)begin
                        IVAL = 1;
                        next_state =  DATA_COMP;
                    end
                    else if(expected_inst[1] == inst_out)begin   
                        IVAL = 1;
                        next_state =  DATA_COMP;
                    end
                    else if(expected_inst[2] == inst_out)begin  
                        IVAL = 1;
                        next_state =  DATA_COMP;
                    end   
                    else if(expected_inst[3] == inst_out)begin  
                        IVAL = 1;
                        next_state =  DATA_COMP;
                    end       
                    else 
                        next_state = LOCK;    
                  end
         DATA_COMP:begin
                        case(mux_sel)
                            2'b00: DVAL = (expected_data[0] == data_out);
                            2'b01: DVAL = (expected_data[1] == data_out);
                            2'b10: DVAL = (expected_data[2] == data_out);
                            2'b11: DVAL = (expected_data[3] == data_out);
                        endcase
                       if(DVAL)
                            next_state = UNLOCK;
                        else
                            next_state = LOCK;
                   end
         UNLOCK:begin
                TDI_out = TDI;
                DVAL=1;
                next_state = UNLOCK; // Stay in UNLOCK state
                end                
         default: next_state = LOCK;           
       endcase
   end           
endmodule