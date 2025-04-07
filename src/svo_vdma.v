`timescale 1ns / 1ps
`include "svo_defines.vh"

module svo_vdma #(
    `SVO_DEFAULT_PARAMS,
    parameter MEM_ADDR_WIDTH = 32,
    parameter MEM_DATA_WIDTH = 64,
    parameter MEM_BURST_LEN = 8,
    parameter FIFO_DEPTH = 64,
    parameter FB_WIDTH = 320,      // Frame buffer width
    parameter FB_HEIGHT = 240      // Frame buffer height
) (
    // All signal are synchronous to "clk", except out_axis_* which are synchronous to "oclk".
    input wire clk, 
    input wire oclk, 
    input wire resetn,
    output reg frame_irq,

    // config interface: axi4-lite slave
    input wire            cfg_axi_awvalid,
    output wire           cfg_axi_awready,
    input wire     [7:0]  cfg_axi_awaddr,

    input wire            cfg_axi_wvalid,
    output wire           cfg_axi_wready,
    input wire     [31:0] cfg_axi_wdata,

    output reg            cfg_axi_bvalid,
    input wire            cfg_axi_bready,

    input wire            cfg_axi_arvalid,
    output wire           cfg_axi_arready,
    input wire     [7:0]  cfg_axi_araddr,

    output reg            cfg_axi_rvalid,
    input wire            cfg_axi_rready,
    output reg     [31:0] cfg_axi_rdata,


    // Memory interface (maintained for compatibility but not used)
    output reg [MEM_ADDR_WIDTH-1:0] mem_axi_araddr,
    output wire [7:0]               mem_axi_arlen,
    output wire [2:0]               mem_axi_arsize,
    output wire [2:0]               mem_axi_arprot,
    output wire [1:0]               mem_axi_arburst,
    output reg                      mem_axi_arvalid,
    input wire                      mem_axi_arready,

    input wire  [MEM_DATA_WIDTH-1:0] mem_axi_rdata,
    input wire                       mem_axi_rvalid,
    output reg                       mem_axi_rready,

    // Frame buffer interface (new)
    output reg        fb_read_req,   // Request to read from frame buffer
    output reg [9:0]  fb_read_x,     // X coordinate to read from frame buffer
    output reg [8:0]  fb_read_y,     // Y coordinate to read from frame buffer
    input wire [11:0] fb_read_data,  // RGB444 pixel data from frame buffer
    input wire        fb_frame_ready, // Frame is ready to be read

    // output stream
    output wire                         out_axis_tvalid,
    input wire                          out_axis_tready,
    output wire [SVO_BITS_PER_PIXEL-1:0] out_axis_tdata,
    output wire [0:0]                   out_axis_tuser,

    // terminal output stream
    output reg       term_axis_tvalid,
    input wire       term_axis_tready,
    output reg [7:0] term_axis_tdata
);
    `SVO_DECLS

    // SVO frame dimensions
    localparam NUM_PIXELS = SVO_HOR_PIXELS * SVO_VER_PIXELS;
    localparam NUM_PIXELS_WIDTH = svo_clog2(NUM_PIXELS);
    
    // FIFO parameters for synchronizing between clock domains
    localparam PIXEL_FIFO_ADDR_WIDTH = 4;  // 16 entries deep
    localparam PIXEL_FIFO_PREFILL = 8;     // Start outputting after 8 pixels

    // Reset synchronization
    reg [3:0] oresetn_q, iresetn_q;
    reg oresetn, iresetn;

    // Synchronize oresetn with oclk
    always @(posedge oclk)
        {oresetn, oresetn_q} <= {oresetn_q, resetn};

    // Synchronize iresetn with clk
    always @(posedge clk)
        {iresetn, iresetn_q} <= {iresetn_q, resetn};

    // --------------------------------------------------------------
    // Configuration Interface (maintained for compatibility)
    // --------------------------------------------------------------

    reg [31:0] reg_startaddr;
    reg [31:0] reg_activeframe;
    wire [31:0] reg_resolution;

    assign reg_resolution[31:16] = SVO_VER_PIXELS;
    assign reg_resolution[15:0] = SVO_HOR_PIXELS;

    assign {cfg_axi_awready, cfg_axi_wready} = {2{resetn && cfg_axi_awvalid && cfg_axi_wvalid && (!cfg_axi_bvalid || cfg_axi_bready) && !term_axis_tvalid}};
    assign cfg_axi_arready = resetn && cfg_axi_arvalid && (!cfg_axi_rvalid || cfg_axi_rready);

    always @(posedge clk) begin
        if (!resetn) begin
            reg_startaddr <= 0;
            cfg_axi_bvalid <= 0;
            cfg_axi_rvalid <= 0;
            term_axis_tvalid <= 0;
        end else begin
            if (cfg_axi_bready)
                cfg_axi_bvalid <= 0;

            if (cfg_axi_rready)
                cfg_axi_rvalid <= 0;

            if (term_axis_tready)
                term_axis_tvalid <= 0;

            if (cfg_axi_awready) begin
                cfg_axi_bvalid <= 1;
                case (cfg_axi_awaddr)
                    8'h00: reg_startaddr <= cfg_axi_wdata;
                    8'h0C: begin
                        term_axis_tvalid <= 1;
                        term_axis_tdata <= cfg_axi_wdata;
                    end
                endcase
            end

            if (cfg_axi_arready) begin
                cfg_axi_rvalid <= 1;
                case (cfg_axi_araddr)
                    8'h00: cfg_axi_rdata <= reg_startaddr;
                    8'h04: cfg_axi_rdata <= reg_activeframe;
                    8'h08: cfg_axi_rdata <= reg_resolution;
                    default: cfg_axi_rdata <= 'bx;
                endcase
            end
        end
    end

    // --------------------------------------------------------------
    // Frame Buffer Read Logic and Cross-Clock Domain Synchronization
    // --------------------------------------------------------------
    
    // Frame buffer read state machine
    localparam FB_IDLE = 0;
    localparam FB_READING = 1;
    localparam FB_WAIT = 2;
    
    reg [1:0] fb_state;
    reg [9:0] current_x;
    reg [8:0] current_y;
    reg frame_in_progress;
    reg new_frame_detected;
    reg prev_fb_frame_ready;
    
    // Pixel FIFO signals for clock domain crossing
    reg pixel_fifo_wr_en;
    wire pixel_fifo_rd_en;
    reg [SVO_BITS_PER_PIXEL-1:0] pixel_fifo_wr_data;
    wire [SVO_BITS_PER_PIXEL-1:0] pixel_fifo_rd_data;
    wire pixel_fifo_full;
    wire pixel_fifo_empty;
    wire [PIXEL_FIFO_ADDR_WIDTH:0] pixel_fifo_count;
    
    // Frame sync signals
    reg frame_sync_wr;
    wire frame_sync_rd;
    wire frame_sync_empty;
    wire [0:0] frame_sync_data;
    
    // AXI interface compatibility (these are not used but kept for compatibility)
    assign mem_axi_arlen = MEM_BURST_LEN-1;
    assign mem_axi_arsize = svo_clog2(MEM_DATA_WIDTH/8);
    assign mem_axi_arprot = 0;
    assign mem_axi_arburst = 1;
    
    // Frame buffer read FSM
    always @(posedge clk) begin
        if (!resetn) begin
            fb_state <= FB_IDLE;
            current_x <= 0;
            current_y <= 0;
            fb_read_req <= 0;
            fb_read_x <= 0;
            fb_read_y <= 0;
            frame_in_progress <= 0;
            new_frame_detected <= 0;
            mem_axi_arvalid <= 0;
            mem_axi_araddr <= 0;
            mem_axi_rready <= 0;
            pixel_fifo_wr_en <= 0;
            pixel_fifo_wr_data <= 0;
            frame_sync_wr <= 0;
            prev_fb_frame_ready <= 0;
            frame_irq <= 0;
        end else begin
            // Default values
            fb_read_req <= 0;
            pixel_fifo_wr_en <= 0;
            frame_sync_wr <= 0;
            
            // Detect frame_ready rising edge
            prev_fb_frame_ready <= fb_frame_ready;
            if (fb_frame_ready && !prev_fb_frame_ready) begin
                new_frame_detected <= 1;
                frame_irq <= 1;  // Signal frame start interrupt
            end
            
            case (fb_state)
                FB_IDLE: begin
                    if (new_frame_detected && !pixel_fifo_full) begin
                        // Start reading from a new frame
                        frame_in_progress <= 1;
                        current_x <= 0;
                        current_y <= 0;
                        new_frame_detected <= 0;
                        fb_state <= FB_READING;
                        
                        // Signal new frame to output domain
                        frame_sync_wr <= 1;
                    end
                end
                
                FB_READING: begin
                    // Request a pixel from frame buffer
                    fb_read_req <= 1;
                    fb_read_x <= current_x;
                    fb_read_y <= current_y;
                    fb_state <= FB_WAIT;
                end
                
                FB_WAIT: begin
                    // One-cycle wait for data to be available
                    if (!pixel_fifo_full) begin
                        // Write pixel to FIFO for clock domain crossing
                        pixel_fifo_wr_en <= 1;
                        pixel_fifo_wr_data <= fb_read_data;  // Get RGB444 directly
                        
                        // Move to next pixel
                        if (current_x >= FB_WIDTH-1) begin
                            if (current_y >= FB_HEIGHT-1) begin
                                // End of frame
                                frame_in_progress <= 0;
                                fb_state <= FB_IDLE;
                            end else begin
                                // Next row
                                current_x <= 0;
                                current_y <= current_y + 1;
                                fb_state <= FB_READING;
                            end
                        end else begin
                            // Next pixel
                            current_x <= current_x + 1;
                            fb_state <= FB_READING;
                        end
                    end
                end
            endcase
            
            // Just for compatibility with the memory AXI interface
            if (mem_axi_arready && mem_axi_arvalid)
                mem_axi_arvalid <= 0;
            
            if (new_frame_detected) begin
                mem_axi_araddr <= reg_startaddr;
                reg_activeframe <= reg_startaddr;
            end
        end
    end

    // --------------------------------------------------------------
    // Pixel FIFO for clock domain crossing
    // --------------------------------------------------------------
    
    async_fifo #(
        .DATA_WIDTH(SVO_BITS_PER_PIXEL),
        .ADDR_WIDTH(PIXEL_FIFO_ADDR_WIDTH)
    ) pixel_fifo (
        // Write side (clk domain)
        .i_wr_clk(clk),
        .i_wr_rstn(resetn),
        .i_wr_en(pixel_fifo_wr_en),
        .i_wr_data(pixel_fifo_wr_data),
        .o_wr_full(pixel_fifo_full),
        .o_wr_count(),
        
        // Read side (oclk domain)
        .i_rd_clk(oclk),
        .i_rd_rstn(oresetn),
        .i_rd_en(pixel_fifo_rd_en),
        .o_rd_data(pixel_fifo_rd_data),
        .o_rd_empty(pixel_fifo_empty),
        .o_rd_count(pixel_fifo_count)
    );
    
    // Frame sync FIFO for signaling new frames
    async_fifo #(
        .DATA_WIDTH(1),
        .ADDR_WIDTH(2)  // Small FIFO is sufficient
    ) frame_sync_fifo (
        // Write side (clk domain)
        .i_wr_clk(clk),
        .i_wr_rstn(resetn),
        .i_wr_en(frame_sync_wr),
        .i_wr_data(1'b1),  // 1 indicates new frame
        .o_wr_full(),
        .o_wr_count(),
        
        // Read side (oclk domain)
        .i_rd_clk(oclk),
        .i_rd_rstn(oresetn),
        .i_rd_en(frame_sync_rd),
        .o_rd_data(frame_sync_data),
        .o_rd_empty(frame_sync_empty),
        .o_rd_count()
    );

    // --------------------------------------------------------------
    // Output Stream Logic (in oclk domain)
    // --------------------------------------------------------------

    reg [NUM_PIXELS_WIDTH:0] pixel_count;
    reg start_of_frame;
    reg prefill_done;
    reg output_valid;

    // Frame sync read control
    assign frame_sync_rd = !frame_sync_empty && (pixel_count == 0 || pixel_count >= NUM_PIXELS);
    
    // Pixel FIFO read control
    assign pixel_fifo_rd_en = !pixel_fifo_empty && out_axis_tready && 
                             (prefill_done || pixel_fifo_count >= PIXEL_FIFO_PREFILL);

    always @(posedge oclk) begin
        if (!oresetn) begin
            pixel_count <= 0;
            start_of_frame <= 1;
            prefill_done <= 0;
            output_valid <= 0;
        end else begin
            // Check for new frame sync
            if (frame_sync_rd) begin
                if (frame_sync_data) begin
                    pixel_count <= 0;
                    start_of_frame <= 1;
                    prefill_done <= 0;
                    output_valid <= 0;
                end
            end
            
            // Monitor FIFO prefill status
            if (!prefill_done && pixel_fifo_count >= PIXEL_FIFO_PREFILL)
                prefill_done <= 1;
                
            // Update output valid status
            output_valid <= prefill_done && !pixel_fifo_empty && (pixel_count < NUM_PIXELS);
            
            // Update pixel counter when data is transferred
            if (out_axis_tready && out_axis_tvalid) begin
                if (pixel_count >= NUM_PIXELS-1) begin
                    pixel_count <= 0;
                    start_of_frame <= 1;
                    prefill_done <= 0;
                    output_valid <= 0;
                end else begin
                    pixel_count <= pixel_count + 1;
                    start_of_frame <= 0;
                end
            end
        end
    end

    // Connect to the output AXI stream
    assign out_axis_tvalid = output_valid;
    assign out_axis_tdata = pixel_fifo_rd_data;
    assign out_axis_tuser = start_of_frame;

endmodule