

module TDR #(
    parameter DATA_WIDTH = 32,          // Width of parallel data to/from instrument
    parameter RESET_VALUE = 0           // Reset value for the register
) (
    // JTAG Interface
    input  wire                    tck,         // Test Clock
    input  wire                    trst_n,      // Test Reset (active low)
    input  wire                    tdi,         // Test Data Input (serial)
    output reg                     tdo,         // Test Data Output (serial)
    input  wire                    shift_dr,    // Shift Data Register
    input  wire                    update_dr,   // Update Data Register

    output reg                     inst_valid,     // Data valid signal to instrument
    input  wire                    select_en,      // Select enable signal (input control)
    output reg output_mode,
    output reg  [DATA_WIDTH-1:0]   inst_data_out,  // Parallel data to instrument
    input  wire [DATA_WIDTH-1:0]   inst_data_in    // Parallel data from instrument
);

    // Internal registers (sequential elements)
    reg [DATA_WIDTH-1:0] shift_reg;
    reg [DATA_WIDTH-1:0] update_reg;
    reg [DATA_WIDTH-1:0] output_shift_reg;
    reg [$clog2(DATA_WIDTH):0] bit_counter;
    reg shift_complete;
    //reg output_mode;
    reg capture_next;
    
    // Combinational signals
    reg shift_complete_next;
    reg output_mode_next;
    reg capture_next_next;
    reg inst_valid_next;
    reg [DATA_WIDTH-1:0] shift_reg_next;
    reg [DATA_WIDTH-1:0] update_reg_next;
    reg [DATA_WIDTH-1:0] output_shift_reg_next;
    reg [DATA_WIDTH-1:0] inst_data_out_next;
    reg [$clog2(DATA_WIDTH):0] bit_counter_next;
    reg tdo_next;

    // ========================================================================
    // COMBINATIONAL LOGIC BLOCK
    // ========================================================================
    always @(*) begin
        // Default assignments
        shift_reg_next = shift_reg;
        update_reg_next = update_reg;
        output_shift_reg_next = output_shift_reg;
        bit_counter_next = bit_counter;
        inst_data_out_next = inst_data_out;
        inst_valid_next = 1'b0;
        shift_complete_next = 1'b0;
        output_mode_next = output_mode;
        capture_next_next = capture_next;
        
        // TDO output logic
        tdo_next = output_mode ? output_shift_reg[0] : tdi;
        
        // Only perform operations when select_en is high
        if (select_en) begin
            if (shift_dr) begin
                // Shift phase: Separate input and output operations
                if (output_mode) begin
                    // Shift out captured data from instrument
                    output_shift_reg_next = {1'b0, output_shift_reg[DATA_WIDTH-1:1]};  // Shift output (LSB first)
                end else begin
                    // Shift in new data for instrument
                    shift_reg_next = {tdi, shift_reg[DATA_WIDTH-1:1]};  // Shift input (MSB first)
                end
                
                // Increment bit counter
                if (bit_counter < DATA_WIDTH) begin
                    bit_counter_next = bit_counter + 1;
                end
                
                // Check if we've shifted a complete word
                if (bit_counter == DATA_WIDTH - 1) begin
                    shift_complete_next = 1'b1;
                    bit_counter_next = 0;
                    if (output_mode) begin
                        output_mode_next = 1'b0;  // Done shifting out, return to input mode
                    end
                end
            end 
            else if (update_dr) begin
                // Update phase: Transfer shift register to update register,
                // send to instrument, and set flag to capture response next cycle
                update_reg_next = shift_reg;
                inst_data_out_next = shift_reg;
                inst_valid_next = 1'b1;
                capture_next_next = 1'b1;  // Flag to capture instrument data next cycle
            end else if (capture_next) begin
                // Capture instrument response after it has time to process new input
                output_shift_reg_next = inst_data_in;
                output_mode_next = 1'b1;  // Switch to output mode for next shift
                bit_counter_next = 0;  // Reset counter for output shifting
                capture_next_next = 1'b0;  // Clear the flag
            end
        end
    end

    // ========================================================================
    // SEQUENTIAL LOGIC BLOCK
    // ========================================================================
    always @(posedge tck or posedge trst_n) begin
        if (trst_n) begin
            // Reset all registers and counters
            shift_reg <= RESET_VALUE;
            update_reg <= RESET_VALUE;
            output_shift_reg <= {DATA_WIDTH{1'b0}};
            bit_counter <= 0;
            inst_data_out <= RESET_VALUE;
            inst_valid <= 1'b0;
            shift_complete <= 1'b0;
            output_mode <= 1'b0;
            capture_next <= 1'b0;
            tdo <= 1'b0;
        end else begin
            // Update all registers with combinational logic outputs
            shift_reg <= shift_reg_next;
            update_reg <= update_reg_next;
            output_shift_reg <= output_shift_reg_next;
            bit_counter <= bit_counter_next;
            inst_data_out <= inst_data_out_next;
            inst_valid <= inst_valid_next;
            shift_complete <= shift_complete_next;
            output_mode <= output_mode_next;
            capture_next <= capture_next_next;
            tdo <= tdo_next;
        end
    end

endmodule
