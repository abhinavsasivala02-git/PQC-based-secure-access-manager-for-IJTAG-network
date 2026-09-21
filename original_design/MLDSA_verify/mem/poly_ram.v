// =============================================================================
// poly_ram.v — Single-port SRAM model (256 x 24-bit)
//
// Port A: read/write, synchronous, 1-cycle read latency
// Port B: read-only, synchronous
//
// For ASIC: replace with foundry SRAM compiler macro.
// =============================================================================
`timescale 1ns/1ps

module poly_ram #(
    parameter DEPTH = 256,
    parameter WIDTH = 24
) (
    input  wire                       clk,
    // Port A: read/write
    input  wire                       wea,
    input  wire [$clog2(DEPTH)-1:0]   addra,
    input  wire [WIDTH-1:0]           dina,
    output reg  [WIDTH-1:0]           douta,
    // Port B: read-only
    input  wire [$clog2(DEPTH)-1:0]   addrb,
    output reg  [WIDTH-1:0]           doutb
);

    (* ram_style = "auto" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Port A
    always @(posedge clk) begin
        if (wea)
            mem[addra] <= dina;
        douta <= mem[addra];
    end

    // Port B
    always @(posedge clk) begin
        doutb <= mem[addrb];
    end

    // Simulation-only init
    // pragma translate_off
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1)
            mem[i] = {WIDTH{1'bx}};
    end
    // pragma translate_on

endmodule
