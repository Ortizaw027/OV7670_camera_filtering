`timescale 1ns / 1ps
`default_nettype none

/*
 *  Instantiates cam_rom, cam_config, and i2c_sccb_master.
 *  cam_config waits for i_cam_init_start and ready signal 
 *  from i2c_sccb_master in order to send data to i2c_sccb_master.
 *
 *  NOTE:
 *  - cam_config reads from a synchronous ROM.
 *  - w_cam_rom_data = { OV7670 REG ADDR , OV7670 REG DATA }.
 */
module cam_init #(
    parameter CLK_F = 27_000_000,    // 27 MHz clock (Tang Nano 9k)
    parameter I2C_F = 100_000        // I2C clock frequency (100 kHz)
) (
    input  wire        i_clk,              // 27 MHz clock
    input  wire        i_rstn,             // Active-low reset
    input  wire        i_cam_init_start,   // Start camera initialization
    output wire        o_siod,             // I2C data line (SDA)
    output wire        o_sioc,             // I2C clock line (SCL)
    output wire        o_cam_init_done     // Camera initialization done signal
);
    // Internal signals
    wire [7:0]  w_cam_rom_addr;    // Address for cam_rom
    wire [15:0] w_cam_rom_data;    // Data from cam_rom ({REG_ADDR, REG_DATA})
    wire [7:0]  w_send_addr;       // I2C slave address
    wire [7:0]  w_send_data;       // Data to send via I2C
    wire        w_start_i2c;       // Start signal for I2C master
    wire        w_ready_i2c;       // Ready signal from I2C master
    wire [7:0]  w_i2c_dout;        // Data output from i2c_sccb_master (unused)

    // Instantiate cam_rom
    cam_rom OV7670_Registers (
        .i_clk(i_clk),             // 27 MHz clock
        .i_rstn(i_rstn),           // Active-low reset
        .i_addr(w_cam_rom_addr),   // Address input
        .o_dout(w_cam_rom_data)    // Data output ({REG_ADDR, REG_DATA})
    );

    // Instantiate cam_config
    cam_config #(
        .CLK_F(CLK_F),             // 27 MHz clock
        .CAM_I2C_ADDR(8'h42)       // OV7670 I2C address (0x42)
    ) OV7670_config (
        .i_clk(i_clk),             // 27 MHz clock
        .i_rstn(i_rstn),           // Active-low reset
        .i_i2c_ready(w_ready_i2c), // I2C master ready signal
        .i_config_start(i_cam_init_start), // Start initialization
        .i_rom_data(w_cam_rom_data), // Data from cam_rom
        .o_rom_addr(w_cam_rom_addr), // Address for cam_rom
        .o_i2c_start(w_start_i2c), // Start signal for I2C master
        .o_i2c_addr(w_send_addr),  // I2C slave address
        .o_i2c_data(w_send_data),  // Data to send via I2C
        .o_config_done(o_cam_init_done) // Initialization done signal
    );

    // Instantiate i2c_sccb_master
    i2c_sccb_master I2C_SCCB_MASTER (
        .i_clk(i_clk),             // 27 MHz clock
        .i_rst(~i_rstn),           // Active-high reset (inverted i_rstn)
        .i_addr(w_send_addr[6:0]), // 7-bit I2C slave address
        .i_din(w_send_data),       // Data to send
        .i_enable(w_start_i2c),    // Start I2C transaction
        .i_rd_wr(1'b0),            // Write mode (0 = write, 1 = read)
        .o_dout(w_i2c_dout),       // Data received (unused)
        .o_ready(w_ready_i2c),     // I2C master ready signal
        .io_sda(o_siod),           // I2C data line (SDA)
        .io_scl(o_sioc)            // I2C clock line (SCL)
    );

endmodule