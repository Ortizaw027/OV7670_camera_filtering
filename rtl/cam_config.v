`timescale 1ns / 1ps
`default_nettype none

module cam_config #(
    parameter CLK_F = 27_000_000, // 27 MHz clock (Tang Nano 9k)
    parameter CAM_I2C_ADDR = 8'h42 // Camera I2C address (typically 0x42 for OV cameras)
) (
    input wire i_clk,             // System clock
    input wire i_rstn,            // Active-low reset
    input wire i_i2c_ready,       // I2C master ready signal
    input wire i_config_start,    // Start initialization
    input wire [15:0] i_rom_data, // Data from cam_rom ({REG_ADDR, REG_DATA})
    output reg [7:0] o_rom_addr,  // Address for cam_rom
    output reg o_i2c_start,       // Start signal for I2C master
    output reg [7:0] o_i2c_addr,  // I2C slave address
    output reg [7:0] o_i2c_data,  // Data to send via I2C
    output reg o_config_done      // Initialization complete flag
);

    // Timer for delays
    localparam ten_ms_delay = (CLK_F * 10) / 1000; // 10 ms delay
    localparam timer_size   = $clog2(ten_ms_delay);
    reg [timer_size - 1:0] timer;

    // State machine states
    localparam SM_IDLE          = 0; // Wait for start signal
    localparam SM_SEND_ADDR     = 1; // Send register address
    localparam SM_SEND_DATA     = 2; // Send register data
    localparam SM_DELAY         = 3; // Wait for delay
    localparam SM_NEXT_REG      = 4; // Move to next register
    localparam SM_DONE          = 5; // Configuration complete

    reg [2:0] state;              // Current state
    reg [7:0] reg_addr;           // Register address buffer
    reg [7:0] reg_data;           // Register data buffer

    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            // Reset all signals
            o_config_done <= 0;
            o_rom_addr    <= 0;
            o_i2c_addr    <= 0;
            o_i2c_start   <= 0;
            o_i2c_data    <= 0;
            state         <= SM_IDLE;
            timer         <= 0;
            reg_addr      <= 0;
            reg_data      <= 0;
        end else begin
            case (state)
                SM_IDLE: begin
                    // Wait for start signal and reset outputs
                    o_i2c_start <= 0;
                    o_config_done <= 0;
                    
                    if (i_config_start) begin
                        state <= SM_SEND_ADDR;
                        o_rom_addr <= 0; // Start from first ROM address
                    end
                end

                SM_SEND_ADDR: begin
                    // Check if we've reached end of ROM or delay marker
                    if (i_rom_data == 16'hFF_FF) begin
                        // End of ROM reached
                        state <= SM_DONE;
                    end
                    else if (i_rom_data == 16'hFF_F0) begin
                        // Delay marker - implement 10ms delay
                        timer <= ten_ms_delay;
                        state <= SM_DELAY;
                        o_rom_addr <= o_rom_addr + 1; // Move to next ROM entry
                    end
                    else if (i_i2c_ready) begin
                        // Save register address and data
                        reg_addr <= i_rom_data[15:8];
                        reg_data <= i_rom_data[7:0];
                        
                        // Send register address to camera
                        o_i2c_addr <= CAM_I2C_ADDR;
                        o_i2c_data <= i_rom_data[15:8]; // Register address
                        o_i2c_start <= 1;
                        state <= SM_SEND_DATA;
                    end
                end

                SM_SEND_DATA: begin
                    // Clear start signal
                    o_i2c_start <= 0;
                    
                    // Wait for I2C master to be ready again
                    if (i_i2c_ready) begin
                        // Send register data to camera
                        o_i2c_addr <= CAM_I2C_ADDR;
                        o_i2c_data <= reg_data; // Register data
                        o_i2c_start <= 1;
                        state <= SM_NEXT_REG;
                    end
                end

                SM_NEXT_REG: begin
                    // Clear start signal
                    o_i2c_start <= 0;
                    
                    // Wait for I2C master to be ready again
                    if (i_i2c_ready) begin
                        // Move to next ROM entry
                        o_rom_addr <= o_rom_addr + 1;
                        state <= SM_SEND_ADDR;
                    end
                end

                SM_DELAY: begin
                    // Wait for timer to expire
                    if (timer > 0) begin
                        timer <= timer - 1;
                    end else begin
                        state <= SM_SEND_ADDR;
                    end
                end

                SM_DONE: begin
                    // Initialization complete
                    o_config_done <= 1;
                    state <= SM_IDLE;
                end

                default: begin
                    // Safety - go back to idle
                    state <= SM_IDLE;
                end
            endcase
        end
    end

endmodule
