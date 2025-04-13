`timescale 1ns / 1ps

module cam_capture (
    input  wire        p_clock,      // Pixel clock from camera
    input  wire        vsync,        // Frame sync (active high)
    input  wire        href,         // Line sync (active high)
    input  wire [7:0]  p_data,       // Pixel data input (8 bits at a time)
    output reg  [15:0] pixel_data = 0, // Output pixel (RGB565 or raw)
    output reg         pixel_valid = 0, // Goes high when a full pixel is ready
    output reg         frame_done = 0   // One-cycle pulse at end of frame
);

    reg [1:0] FSM_state = 0;
    reg       pixel_half = 0;  // Toggles between capturing lower and upper byte

    localparam WAIT_FRAME_START = 0;
    localparam ROW_CAPTURE      = 1;

    always @(posedge p_clock) begin
        case (FSM_state)

            WAIT_FRAME_START: begin
                FSM_state   <= (!vsync) ? ROW_CAPTURE : WAIT_FRAME_START;
                frame_done  <= 0;
                pixel_half  <= 0;
            end

            ROW_CAPTURE: begin
                FSM_state   <= vsync ? WAIT_FRAME_START : ROW_CAPTURE;
                frame_done  <= vsync ? 1 : 0;

                // When href is high, data is active
                if (href) begin
                    pixel_half <= ~pixel_half;

                    if (pixel_half)
                        pixel_data[7:0]  <= p_data;  // First half
                    else
                        pixel_data[15:8] <= p_data;  // Second half

                    pixel_valid <= (pixel_half) ? 1 : 0; // Valid only when full pixel is captured
                end else begin
                    pixel_valid <= 0;
                end
            end

        endcase
    end

endmodule
