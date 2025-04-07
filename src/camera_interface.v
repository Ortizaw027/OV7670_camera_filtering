`timescale 1ns / 1ps
`default_nettype none

/*
 *  Camera Interface - Top Module
 *
 *  This module handles the complete camera pipeline:
 *  1. Camera initialization via I2C
 *  2. Camera data capture
 *  3. Writing to the frame buffer
 */

module camera_interface #(
    parameter CAM_WIDTH = 640,           // Camera capture width
    parameter CAM_HEIGHT = 480,          // Camera capture height
    parameter OUT_WIDTH = 320,           // Output width (downscaled)
    parameter OUT_HEIGHT = 240,          // Output height (downscaled)
    parameter PIXEL_BITS = 12,           // RGB444 = 12 bits per pixel
    parameter CLK_F = 27_000_000,        // System clock frequency (27 MHz)
    parameter I2C_F = 100_000            // I2C clock frequency (100 kHz)
) (
    // System signals
    input  wire        i_clk,            // System clock (27 MHz)
    input  wire        i_rstn,           // Active-low reset
    input  wire        i_cam_init_start, // Start camera initialization
    
    // Camera interface signals
    input  wire        i_pclk,           // Pixel clock from camera
    input  wire        i_vsync,          // Vertical sync from camera
    input  wire        i_href,           // Horizontal reference (data valid)
    input  wire [7:0]  i_cam_data,       // 8-bit data from camera
    output wire        o_sioc,           // Camera I2C clock (SCL)
    output wire        o_siod,           // Camera I2C data (SDA)
    output wire        o_xclk,           // Camera system clock
    output wire        o_reset,          // Camera reset
    output wire        o_pwdn,           // Camera power down
    
    // Frame buffer interface signals for HDMI module
    input  wire        i_hdmi_clk,       // HDMI clock domain
    input  wire        i_read_req,       // Read request from HDMI module
    input  wire [9:0]  i_read_x,         // Pixel X coordinate to read
    input  wire [8:0]  i_read_y,         // Pixel Y coordinate to read
    output wire [11:0] o_read_data,      // RGB444 pixel data for HDMI
    
    // Status signals
    output wire        o_cam_init_done,  // Camera initialization complete
    output wire        o_frame_ready,    // Frame is ready to be read
    output wire        o_buffer_sel      // Current buffer selection (for debugging)
);

    // Internal signals
    wire        w_pixel_valid;           // Pixel data is valid
    wire [15:0] w_pixel_data;            // 16-bit RGB pixel data
    wire [9:0]  w_pixel_x;               // Pixel X coordinate
    wire [8:0]  w_pixel_y;               // Pixel Y coordinate
    wire        w_frame_done;            // Frame capture complete

    // Camera control signals
    assign o_xclk = i_clk;               // Provide system clock to camera
    assign o_reset = i_rstn;             // Camera reset is active low
    assign o_pwdn = 1'b0;                // Camera power down is active high, so keep it enabled
    
    // Camera initialization module
    cam_init #(
        .CLK_F(CLK_F),                   // 27 MHz clock
        .I2C_F(I2C_F)                    // I2C clock frequency
    ) camera_initializer (
        .i_clk(i_clk),                   // System clock
        .i_rstn(i_rstn),                 // Active-low reset
        .i_cam_init_start(i_cam_init_start), // Start camera initialization
        .o_siod(o_siod),                 // I2C data line (SDA)
        .o_sioc(o_sioc),                 // I2C clock line (SCL)
        .o_cam_init_done(o_cam_init_done) // Camera initialization done signal
    );
    
    // Camera capture module
    cam_capture #(
        .IMG_WIDTH(CAM_WIDTH),           // Image width in pixels
        .IMG_HEIGHT(CAM_HEIGHT),         // Image height in pixels
        .CLK_F(CLK_F)                    // System clock frequency
    ) camera_capturer (
        .i_clk(i_clk),                   // System clock
        .i_rstn(i_rstn),                 // Active-low reset
        .i_cam_init_done(o_cam_init_done), // Camera initialization done signal
        .i_pclk(i_pclk),                 // Pixel clock from camera
        .i_vsync(i_vsync),               // Vertical sync from camera
        .i_href(i_href),                 // Horizontal reference (data valid)
        .i_cam_data(i_cam_data),         // 8-bit data from camera
        .o_pixel_data(w_pixel_data),     // 16-bit RGB pixel data
        .o_pixel_valid(w_pixel_valid),   // Pixel data is valid
        .o_pixel_x(w_pixel_x),           // Pixel X coordinate
        .o_pixel_y(w_pixel_y),           // Pixel Y coordinate
        .o_frame_done(w_frame_done)      // Frame capture complete
    );
    
    // Frame buffer module
    frame_buffer #(
        .CAM_WIDTH(CAM_WIDTH),           // Camera capture width
        .CAM_HEIGHT(CAM_HEIGHT),         // Camera capture height
        .OUT_WIDTH(OUT_WIDTH),           // Output width (downscaled)
        .OUT_HEIGHT(OUT_HEIGHT),         // Output height (downscaled)
        .PIXEL_BITS(PIXEL_BITS)          // RGB444 = 12 bits per pixel
    ) fb (
        .i_clk(i_clk),                   // System clock
        .i_rstn(i_rstn),                 // Active-low reset
        .i_cam_pclk(i_pclk),             // Pixel clock from camera
        .i_pixel_valid(w_pixel_valid),   // Pixel data is valid
        .i_pixel_data(w_pixel_data),     // 16-bit pixel data
        .i_pixel_x(w_pixel_x),           // Pixel X coordinate
        .i_pixel_y(w_pixel_y),           // Pixel Y coordinate
        .i_frame_done(w_frame_done),     // Frame capture complete
        .i_hdmi_clk(i_hdmi_clk),         // HDMI clock
        .i_read_req(i_read_req),         // Read request from HDMI module
        .i_read_x(i_read_x),             // Pixel X coordinate to read
        .i_read_y(i_read_y),             // Pixel Y coordinate to read
        .o_read_data(o_read_data),       // RGB444 pixel data for HDMI
        .o_frame_ready(o_frame_ready),   // Frame is ready to be read
        .o_buffer_sel(o_buffer_sel)      // Current buffer selection (for debugging)
    );

endmodule