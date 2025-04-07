`timescale 1ns / 1ps
`default_nettype none

/*
 *  Asynchronous Frame Buffer Module for Tang Nano 9K
 *
 *  This module implements a frame buffer between the camera
 *  capture module and the HDMI output module using an asynchronous FIFO
 *  for safe clock domain crossing. It downscales the 640x480 
 *  image to 320x240 to fit within the Tang Nano 9K's memory constraints.
 *
 *  Port A: Write port (connected to camera capture, cam_pclk domain)
 *  Port B: Read port (connected to HDMI output, hdmi_clk domain)
 */

module frame_buffer #(
    parameter CAM_WIDTH  = 640,         // Camera capture width
    parameter CAM_HEIGHT = 480,         // Camera capture height
    parameter OUT_WIDTH  = 320,         // Output width (downscaled)
    parameter OUT_HEIGHT = 240,         // Output height (downscaled)
    parameter PIXEL_BITS = 12,          // RGB444 = 12 bits per pixel
    parameter FIFO_ADDR_WIDTH = 5       // 2^5 = 32 entries in the FIFO
) (
    // System signals
    input  wire        i_clk,           // System clock (unused, kept for compatibility)
    input  wire        i_rstn,          // Active-low reset
    
    // Camera capture interface (Port A - Write)
    input  wire        i_cam_pclk,      // Pixel clock from camera
    input  wire        i_pixel_valid,   // Pixel data is valid
    input  wire [15:0] i_pixel_data,    // 16-bit pixel data (RGB444 padded to 16 bits)
    input  wire [9:0]  i_pixel_x,       // Pixel X coordinate
    input  wire [8:0]  i_pixel_y,       // Pixel Y coordinate
    input  wire        i_frame_done,    // Frame capture complete
    
    // HDMI output interface (Port B - Read)
    input  wire        i_hdmi_clk,      // HDMI clock
    input  wire        i_read_req,      // Read request from HDMI module
    input  wire [9:0]  i_read_x,        // Pixel X coordinate to read
    input  wire [8:0]  i_read_y,        // Pixel Y coordinate to read
    output reg  [11:0] o_read_data,     // RGB444 pixel data for HDMI
    
    // Status signals
    output reg         o_frame_ready,   // Frame is ready to be read
    output reg         o_buffer_sel     // Current buffer selection (for debugging)
);

    // Double buffering parameters
    localparam FRAME_SIZE = OUT_WIDTH * OUT_HEIGHT;
    localparam FRAME_ADDR_WIDTH = $clog2(FRAME_SIZE);
    
    // Frame buffers (one for each double buffer)
    reg [PIXEL_BITS-1:0] buffer_0 [0:FRAME_SIZE-1];
    reg [PIXEL_BITS-1:0] buffer_1 [0:FRAME_SIZE-1];
    
    // Buffer control signals
    reg write_buffer;                    // Current write buffer (0 or 1)
    wire read_buffer;                    // Current read buffer (opposite of write_buffer)
    reg [FRAME_ADDR_WIDTH-1:0] write_addr; // Write address
    wire [FRAME_ADDR_WIDTH-1:0] read_addr; // Read address
    
    // Downscaling logic
    wire pixel_in_bounds;                // Pixel is within downscaled bounds
    wire [8:0] scaled_x, scaled_y;       // Scaled coordinates
    reg frame_capture_active;            // Frame capture in progress flag
    
    // FIFO signals for frame sync
    wire frame_sync_fifo_full;
    wire frame_sync_fifo_empty;
    reg frame_sync_wr;                   // Write signal for frame sync
    reg frame_ready_rd;                  // Read signal for frame ready status
    wire [0:0] frame_ready_out;          // Frame ready signal from FIFO
    
    // Line buffer FIFO signals
    reg [PIXEL_BITS-1:0] line_data_in;   // Pixel data to write
    wire [PIXEL_BITS-1:0] line_data_out; // Pixel data read out
    reg line_wr_en;                      // Write enable for line FIFO
    reg line_rd_en;                      // Read enable for line FIFO
    wire line_fifo_full;                 // Line FIFO full signal
    wire line_fifo_empty;                // Line FIFO empty signal
    wire [FIFO_ADDR_WIDTH:0] line_fifo_count; // Number of entries in FIFO
    
    // Compute scaled coordinates and check if we should capture this pixel
    // We're implementing a simple 2:1 downscaling
    assign scaled_x = i_pixel_x[9:1];    // Divide by 2 (X coordinate)
    assign scaled_y = i_pixel_y[8:1];    // Divide by 2 (Y coordinate)
    
    // Make sure the scaled coordinates are within bounds
    assign pixel_in_bounds = (scaled_x < OUT_WIDTH) && (scaled_y < OUT_HEIGHT);
    
    // Calculate read address based on HDMI coordinates
    assign read_addr = (i_read_y * OUT_WIDTH) + i_read_x;
    
    // Read buffer is opposite of write buffer
    assign read_buffer = ~write_buffer;
    
    // Instantiate line buffer FIFO for pixel data
    async_fifo #(
        .DATA_WIDTH(PIXEL_BITS),
        .ADDR_WIDTH(FIFO_ADDR_WIDTH)
    ) line_fifo (
        .i_wr_clk(i_cam_pclk),
        .i_wr_rstn(i_rstn),
        .i_wr_en(line_wr_en),
        .i_wr_data(line_data_in),
        .o_wr_full(line_fifo_full),
        .o_wr_count(),
        
        .i_rd_clk(i_hdmi_clk),
        .i_rd_rstn(i_rstn),
        .i_rd_en(line_rd_en),
        .o_rd_data(line_data_out),
        .o_rd_empty(line_fifo_empty),
        .o_rd_count(line_fifo_count)
    );
    
    // Instantiate frame sync FIFO (1-bit to signal frame ready)
    async_fifo #(
        .DATA_WIDTH(1),
        .ADDR_WIDTH(2)  // Small FIFO is sufficient for sync
    ) frame_sync_fifo (
        .i_wr_clk(i_cam_pclk),
        .i_wr_rstn(i_rstn),
        .i_wr_en(frame_sync_wr),
        .i_wr_data(1'b1),  // Always write '1' to indicate frame ready
        .o_wr_full(frame_sync_fifo_full),
        .o_wr_count(),
        
        .i_rd_clk(i_hdmi_clk),
        .i_rd_rstn(i_rstn),
        .i_rd_en(frame_ready_rd),
        .o_rd_data(frame_ready_out),
        .o_rd_empty(frame_sync_fifo_empty),
        .o_rd_count()
    );
    
    // Camera capture write logic (cam_pclk domain)
    reg prev_frame_done;
    
    always @(posedge i_cam_pclk or negedge i_rstn) begin
        if (!i_rstn) begin
            write_buffer <= 0;
            write_addr <= 0;
            frame_capture_active <= 0;
            frame_sync_wr <= 0;
            line_wr_en <= 0;
            line_data_in <= 0;
            prev_frame_done <= 0;
            o_buffer_sel <= 0;
        end else begin
            // Default values
            frame_sync_wr <= 0;
            line_wr_en <= 0;
            
            // Detect frame completion
            prev_frame_done <= i_frame_done;
            
            // Frame done rising edge detection
            if (i_frame_done && !prev_frame_done) begin
                if (frame_capture_active) begin
                    // Frame completed, switch buffers for next frame and signal ready
                    write_buffer <= ~write_buffer;
                    o_buffer_sel <= ~write_buffer; // Update for debugging
                    frame_sync_wr <= 1; // Signal frame is ready through FIFO
                end
                frame_capture_active <= 1;
            end
            
            // Capture pixel if valid and in bounds for downscaled image
            if (i_pixel_valid && pixel_in_bounds) begin
                // Only take every other pixel in both dimensions for 2:1 downscaling
                if ((i_pixel_x[0] == 0) && (i_pixel_y[0] == 0)) begin
                    // Calculate buffer address
                    write_addr = (scaled_y * OUT_WIDTH) + scaled_x;
                    
                    // Write to current buffer
                    if (write_buffer == 0) begin
                        buffer_0[write_addr] <= i_pixel_data[15:4]; // Extract RGB444 bits
                    end else begin
                        buffer_1[write_addr] <= i_pixel_data[15:4]; // Extract RGB444 bits
                    end
                    
                    // Also write to line FIFO if not full
                    if (!line_fifo_full) begin
                        line_data_in <= i_pixel_data[15:4];
                        line_wr_en <= 1;
                    end
                end
            end
        end
    end
    
    // HDMI read logic (hdmi_clk domain)
    reg prev_frame_ready;
    reg fifo_mode;  // 0 = read from double buffer, 1 = read from FIFO
    
    always @(posedge i_hdmi_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_read_data <= 0;
            o_frame_ready <= 0;
            prev_frame_ready <= 0;
            frame_ready_rd <= 0;
            line_rd_en <= 0;
            fifo_mode <= 1; // Default to FIFO mode
        end else begin
            // Default values
            frame_ready_rd <= 0;
            line_rd_en <= 0;
            
            // Check for new frame ready signal from FIFO
            if (!frame_sync_fifo_empty && !frame_ready_rd) begin
                frame_ready_rd <= 1;
                o_frame_ready <= frame_ready_out;
                prev_frame_ready <= frame_ready_out;
            end
            
            // Read from double buffer or FIFO based on request
            if (i_read_req) begin
                if (fifo_mode) begin
                    // FIFO mode - read from line FIFO if not empty
                    if (!line_fifo_empty) begin
                        line_rd_en <= 1;
                        o_read_data <= line_data_out;
                    end else begin
                        // If FIFO is empty, output black
                        o_read_data <= 12'h000;
                    end
                end else begin
                    // Double buffer mode - read from current read buffer
                    if (i_read_x < OUT_WIDTH && i_read_y < OUT_HEIGHT) begin
                        if (read_buffer == 0) begin
                            o_read_data <= buffer_0[read_addr];
                        end else begin
                            o_read_data <= buffer_1[read_addr];
                        end
                    end else begin
                        // Out of bounds read returns black
                        o_read_data <= 12'h000;
                    end
                end
            end
        end
    end

endmodule