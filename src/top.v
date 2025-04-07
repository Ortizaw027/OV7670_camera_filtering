`timescale 1ns / 1ps
`default_nettype none

/**
 * Top Module - Tang Nano 9K Camera to HDMI
 *
 * This module interfaces an OV2640/OV7670 camera with HDMI output
 * using the provided SVO HDMI core and Gowin FPGA components.
 * 
 * Features:
 * - Camera initialization via I2C
 * - Camera data capture and downscaling
 * - Frame buffering with clock domain crossing
 * - HDMI output via SVO core
 */
module top (
    // System signals
    input  wire       clk,               // 27MHz system clock
    input  wire       resetn,            // Active-low reset button
    
    // HDMI outputs
    output wire       tmds_clk_n,        // HDMI clock negative
    output wire       tmds_clk_p,        // HDMI clock positive
    output wire [2:0] tmds_d_n,          // HDMI data negative
    output wire [2:0] tmds_d_p,          // HDMI data positive
    
    // Camera interface pins (can be connected to actual camera)
    inout  wire       cam_siod,          // Camera I2C data (SDA) - bidirectional
    output wire       cam_sioc,          // Camera I2C clock (SCL)
    input  wire       cam_pclk,          // Camera pixel clock
    input  wire       cam_vsync,         // Camera vertical sync
    input  wire       cam_href,          // Camera horizontal reference
    input  wire [7:0] cam_data,          // Camera 8-bit data
    output wire       cam_xclk,          // Camera system clock
    output wire       cam_reset,         // Camera reset
    output wire       cam_pwdn,          // Camera power down

    // Debug outputs (optional)
    output wire       frame_ready,       // Frame ready indicator
    output wire       buffer_sel,        // Buffer selection indicator
    output wire       init_done          // Camera initialization done
);

    // Parameters
    localparam CAM_WIDTH  = 640;         // Camera capture width
    localparam CAM_HEIGHT = 480;         // Camera capture height
    localparam OUT_WIDTH  = 320;         // Output width (downscaled)
    localparam OUT_HEIGHT = 240;         // Output height (downscaled)
    localparam PIXEL_BITS = 12;          // RGB444 = 12 bits per pixel
    localparam I2C_FREQ   = 100_000;     // I2C bus frequency (100 kHz)

    // Internal signals
    wire        clk_p;                   // Pixel clock
    wire        clk_p5;                  // 5x pixel clock for SerDes
    wire        pll_lock;                // PLL lock signal
    wire        sys_resetn;              // Synchronized reset signal
    wire [11:0] frame_data;              // Frame data from buffer (RGB444)
    wire [9:0]  read_x;                  // Pixel X coordinate to read
    wire [8:0]  read_y;                  // Pixel Y coordinate to read
    wire        read_req;                // Read request from HDMI module
    wire        cam_init_start;          // Camera initialization start signal

    // Bidirectional I2C data pin handling
    wire        siod_oe;                 // I2C data output enable
    wire        siod_out;                // I2C data output
    
    // Assign bidirectional SDA line
    assign cam_siod = siod_oe ? siod_out : 1'bz;
    
    // Generate camera initialization start signal
    // Start initialization after PLL is locked and reset is released
    reg [7:0] init_counter = 0;
    reg       init_start_reg = 0;
    
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            init_counter <= 0;
            init_start_reg <= 0;
        end else if (pll_lock && init_counter < 100) begin
            init_counter <= init_counter + 1;
            init_start_reg <= (init_counter == 99); // Start init after delay
        end else begin
            init_start_reg <= 0;
        end
    end
    
    assign cam_init_start = init_start_reg;

    // PLL for generating pixel clock and 5x pixel clock
    Gowin_rPLL u_pll (
        .clkin(clk),              // 27MHz input clock
        .clkout(clk_p5),          // 5x pixel clock output
        .lock(pll_lock)           // PLL lock signal
    );

    // Clock divider to generate pixel clock from 5x pixel clock
    Gowin_CLKDIV u_div_5 (
        .clkout(clk_p),           // Pixel clock
        .hclkin(clk_p5),          // 5x pixel clock
        .resetn(pll_lock)         // Reset when PLL is not locked
    );

    // Reset synchronizer
    Reset_Sync u_Reset_Sync (
        .resetn(sys_resetn),      // Synchronized reset output
        .ext_reset(resetn & pll_lock), // Combined external reset and PLL lock
        .clk(clk_p)               // Clock domain for synchronization
    );
    
    // Camera interface module
    camera_interface #(
        .CAM_WIDTH(CAM_WIDTH),
        .CAM_HEIGHT(CAM_HEIGHT),
        .OUT_WIDTH(OUT_WIDTH),
        .OUT_HEIGHT(OUT_HEIGHT),
        .PIXEL_BITS(12),          // Using RGB444 for camera capture
        .CLK_F(27_000_000),       // 27 MHz system clock
        .I2C_F(I2C_FREQ)          // 100 kHz I2C clock
    ) camera_if (
        // System signals
        .i_clk(clk),              // System clock
        .i_rstn(sys_resetn),      // Synchronized reset
        .i_cam_init_start(cam_init_start), // Camera initialization start
        
        // Camera interface signals
        .i_pclk(cam_pclk),        // Camera pixel clock
        .i_vsync(cam_vsync),      // Camera vertical sync
        .i_href(cam_href),        // Camera horizontal reference
        .i_cam_data(cam_data),    // Camera 8-bit data
        .o_sioc(cam_sioc),        // Camera I2C clock (SCL)
        .o_siod(siod_out),        // Camera I2C data output
        .o_xclk(cam_xclk),        // Camera system clock
        .o_reset(cam_reset),      // Camera reset
        .o_pwdn(cam_pwdn),        // Camera power down
        
        // Frame buffer interface signals for HDMI module
        .i_hdmi_clk(clk_p),       // HDMI pixel clock
        .i_read_req(read_req),    // Read request from HDMI module
        .i_read_x(read_x),        // Pixel X coordinate to read
        .i_read_y(read_y),        // Pixel Y coordinate to read
        .o_read_data(frame_data), // RGB444 pixel data for HDMI
        
        // Status signals
        .o_cam_init_done(init_done), // Camera initialization complete
        .o_frame_ready(frame_ready), // Frame is ready to be read
        .o_buffer_sel(buffer_sel)    // Current buffer selection (for debugging)
    );
    
    // SVO HDMI module
    svo_hdmi #(
        .SVO_MODE("320x240R"),    // Video mode
        .SVO_FRAMERATE(60),       // Frame rate in Hz
        .SVO_BITS_PER_PIXEL(12),  // 12-bit RGB
        .SVO_BITS_PER_RED(4),     // 4 bits for red
        .SVO_BITS_PER_GREEN(4),   // 4 bits for green
        .SVO_BITS_PER_BLUE(4)     // 4 bits for blue
    ) svo_hdmi_inst (
        .clk(clk_p),              // Pixel clock
        .resetn(sys_resetn),      // Active-low reset
        
        // Video clocks
        .clk_pixel(clk_p),        // Pixel clock
        .clk_5x_pixel(clk_p5),    // 5x pixel clock for SerDes
        .locked(pll_lock),        // PLL lock signal
        
        // HDMI output signals
        .tmds_clk_n(tmds_clk_n),  // HDMI clock negative
        .tmds_clk_p(tmds_clk_p),  // HDMI clock positive
        .tmds_d_n(tmds_d_n),      // HDMI data negative
        .tmds_d_p(tmds_d_p)       // HDMI data positive
    );
    

endmodule
module Reset_Sync (
    input wire clk,
    input wire ext_reset,
    output wire resetn
);


        reg [3:0] reset_cnt = 0;
 
        always @(posedge clk or negedge ext_reset) begin
            if (~ext_reset)
                reset_cnt <= 4'b0;
            else
                reset_cnt <= reset_cnt + !resetn;
    end
 
        assign resetn = &reset_cnt;


    endmodule