`timescale 1ns / 1ps
`default_nettype none

/*
 *  OV7670 Camera Capture Module
 *
 *  This module captures image data from the OV7670 camera.
 *  It synchronizes with VSYNC and HREF signals, captures pixel data,
 *  and stores it in memory for later processing.
 *
 *  The OV7670 is configured in RGB444 mode according to cam_rom settings.
 */

module cam_capture #(
    parameter IMG_WIDTH = 640,          // Image width in pixels
    parameter IMG_HEIGHT = 480,         // Image height in pixels
    parameter CLK_F = 27_000_000        // System clock frequency (27 MHz)
) (
    input wire        i_clk,            // System clock
    input wire        i_rstn,           // Active-low reset
    input wire        i_cam_init_done,  // Camera initialization done signal
    input wire        i_pclk,           // Pixel clock from camera
    input wire        i_vsync,          // Vertical sync from camera
    input wire        i_href,           // Horizontal reference (data valid)
    input wire [7:0]  i_cam_data,       // 8-bit data from camera
    
    output reg [15:0] o_pixel_data,     // 16-bit RGB pixel data
    output reg        o_pixel_valid,    // Pixel data is valid
    output reg [9:0]  o_pixel_x,        // Pixel X coordinate
    output reg [8:0]  o_pixel_y,        // Pixel Y coordinate
    output reg        o_frame_done      // Frame capture complete
);

    // Internal signals
    reg        r_href_last;             // Previous HREF value for edge detection
    reg        r_vsync_last;            // Previous VSYNC value for edge detection
    reg        r_byte_cnt;              // Tracks first/second byte of pixel
    reg [7:0]  r_pixel_data_h;          // First byte of pixel data
    
    // State machine for frame capture
    localparam WAIT_FOR_INIT = 0;       // Wait for camera initialization
    localparam WAIT_FOR_VSYNC = 1;      // Wait for VSYNC signal
    localparam CAPTURE_FRAME = 2;       // Capturing frame data
    localparam FRAME_DONE = 3;          // Frame capture complete
    
    reg [1:0] state;

    // Process camera signals
    always @(posedge i_pclk or negedge i_rstn) begin
        if (!i_rstn) begin
            r_href_last <= 0;
            r_vsync_last <= 0;
            r_byte_cnt <= 0;
            r_pixel_data_h <= 0;
            o_pixel_data <= 0;
            o_pixel_valid <= 0;
            o_pixel_x <= 0;
            o_pixel_y <= 0;
            o_frame_done <= 0;
            state <= WAIT_FOR_INIT;
        end else begin
            // Store previous values for edge detection
            r_href_last <= i_href;
            r_vsync_last <= i_vsync;
            
            // Default values
            o_pixel_valid <= 0;
            o_frame_done <= 0;
            
            case (state)
                WAIT_FOR_INIT: begin
                    // Wait for camera initialization to complete
                    if (i_cam_init_done) begin
                        state <= WAIT_FOR_VSYNC;
                    end
                end
                
                WAIT_FOR_VSYNC: begin
                    // Wait for VSYNC rising edge
                    if (i_vsync && !r_vsync_last) begin
                        // Reset counters on new frame
                        o_pixel_x <= 0;
                        o_pixel_y <= 0;
                        r_byte_cnt <= 0;
                        state <= CAPTURE_FRAME;
                    end
                end
                
                CAPTURE_FRAME: begin
                    // Check for end of frame (VSYNC rising edge)
                    if (i_vsync && !r_vsync_last) begin
                        state <= FRAME_DONE;
                        o_frame_done <= 1;
                    end
                    // If HREF is active, capture data
                    else if (i_href) begin
                        // RGB444 mode - 12 bits per pixel
                        // First byte: [RRRR GGGG]
                        // Second byte: [BBBB 0000]
                        if (r_byte_cnt == 0) begin
                            // First byte contains R and G
                            r_pixel_data_h <= i_cam_data;
                            r_byte_cnt <= 1;
                        end else begin
                            // Second byte contains B
                            // Combine to form RGB444 (stored as RGB444 padded to 16 bits)
                            o_pixel_data <= {r_pixel_data_h, i_cam_data};
                            o_pixel_valid <= 1;
                            r_byte_cnt <= 0;
                            
                            // Update pixel position
                            if (o_pixel_x == IMG_WIDTH - 1) begin
                                o_pixel_x <= 0;
                                if (o_pixel_y == IMG_HEIGHT - 1) begin
                                    o_pixel_y <= 0;
                                end else begin
                                    o_pixel_y <= o_pixel_y + 1;
                                end
                            end else begin
                                o_pixel_x <= o_pixel_x + 1;
                            end
                        end
                    end
                    // End of line (HREF falling edge)
                    else if (!i_href && r_href_last) begin
                        r_byte_cnt <= 0; // Reset byte counter for new line
                    end
                end
                
                FRAME_DONE: begin
                    // Wait for VSYNC to go low before waiting for next frame
                    if (!i_vsync && r_vsync_last) begin
                        state <= WAIT_FOR_VSYNC;
                    end
                end
                
                default: state <= WAIT_FOR_INIT;
            endcase
        end
    end

endmodule