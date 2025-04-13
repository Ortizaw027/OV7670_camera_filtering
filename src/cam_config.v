`timescale 1ns / 1ps

module cam_config #(
    parameter CLK_FREQ = 27000000  // Match your Tang Nano 9K board clock
)(
    input  wire clk,
    input  wire start,
    output wire scl,      // I2C clock line
    output wire sda,      // I2C data line
    output wire done      // Goes high when config is complete
);

    // Internal connections
    wire [7:0]  rom_addr;
    wire [15:0] rom_dout;
    wire [7:0]  sccb_addr;
    wire [7:0]  sccb_data;
    wire        sccb_start;
    wire        sccb_ready;
    wire        scl_oe;
    wire        sda_oe;

    // Assign I2C open-drain signals
    assign scl = scl_oe ? 1'b0 : 1'bZ;
    assign sda = sda_oe ? 1'b0 : 1'bZ;

    // ROM module for camera configuration
    OV7670_config_rom rom_inst (
        .clk(clk),
        .addr(rom_addr),
        .dout(rom_dout)
    );

    // Camera initialization controller
    cam_init #(.CLK_FREQ(CLK_FREQ)) config_inst (
        .clk(clk),
        .sccb_ready(sccb_ready),
        .rom_data(rom_dout),
        .start(start),
        .rom_addr(rom_addr),
        .done(done),
        .sccb_addr(sccb_addr),
        .sccb_data(sccb_data),
        .sccb_start(sccb_start)
    );

    // SCCB (I2C-like) interface
    SCCB_Master #(.CLK_FREQ(CLK_FREQ)) sccb_inst (
        .clk(clk),
        .start(sccb_start),
        .address(sccb_addr),
        .data(sccb_data),
        .ready(sccb_ready),
        .SCL_oe(scl_oe),
        .SDA_oe(sda_oe)
    );

endmodule
