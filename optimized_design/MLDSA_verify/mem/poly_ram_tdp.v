// =============================================================================
// poly_ram_tdp.v — True Dual-Port SRAM (256 x 24-bit)
//
// Both Port A and Port B support independent read and write.
// Used by NTT core for in-place butterfly computation.
//
// For ASIC: replace with foundry TDP SRAM compiler macro.
// =============================================================================
`timescale 1ns/1ps

module poly_ram_tdp #(
    parameter DEPTH = 256,
    parameter WIDTH = 24
) (
    input  wire                       clk,
    // Port A: read + write
    input  wire                       wea,
    input  wire [$clog2(DEPTH)-1:0]   addra,
    input  wire [WIDTH-1:0]           dina,
    output reg  [WIDTH-1:0]           douta,
    // Port B: read + write
    input  wire                       web,
    input  wire [$clog2(DEPTH)-1:0]   addrb,
    input  wire [WIDTH-1:0]           dinb,
    output reg  [WIDTH-1:0]           doutb
);

    (* ram_style = "auto" *)
    reg [WIDTH-1:0] mem [0:DEPTH-1];

    // Port A
    always @(posedge clk) begin
        if (wea) mem[addra] <= dina;
        douta <= mem[addra];
    end

    // Port B
    always @(posedge clk) begin
        if (web) mem[addrb] <= dinb;
        doutb <= mem[addrb];
    end

    // Simulation-only init
    // pragma translate_off
    integer i;
    initial begin
        for (i = 0; i < DEPTH; i = i + 1) mem[i] = {WIDTH{1'b0}};
    end
    // pragma translate_on

endmodule
