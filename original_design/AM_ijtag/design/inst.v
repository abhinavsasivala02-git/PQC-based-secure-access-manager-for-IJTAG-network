// Simple Inverter Instrument for TDR Testing
// This module represents an inverter instrument that inverts all input bits

module inst #(
    parameter DATA_WIDTH = 8
) (
    
    input  wire [DATA_WIDTH-1:0]   data_in,   
    output wire [DATA_WIDTH-1:0]   data_out    
);

    // Combinational inverter - immediate response
    assign data_out = ~data_in;

endmodule
