`timescale 1ns / 1ps
`default_nettype none

/*
 * Asynchronous FIFO
 *
 * This module implements a standard asynchronous FIFO with
 * Gray code pointers for safe clock domain crossing.
 * Binary-to-Gray and Gray-to-Binary conversion functions ensure
 * reliable pointer synchronization between clock domains.
 */

module async_fifo #(
    parameter DATA_WIDTH = 12,           // Width of data bus
    parameter ADDR_WIDTH = 4             // Address width (FIFO depth = 2^ADDR_WIDTH)
) (
    // Write domain
    input  wire                  i_wr_clk,    // Write clock
    input  wire                  i_wr_rstn,   // Write reset (active low)
    input  wire                  i_wr_en,     // Write enable
    input  wire [DATA_WIDTH-1:0] i_wr_data,   // Write data
    output wire                  o_wr_full,   // FIFO full signal
    output wire [ADDR_WIDTH:0]   o_wr_count,  // Write count (optional)
    
    // Read domain
    input  wire                  i_rd_clk,    // Read clock
    input  wire                  i_rd_rstn,   // Read reset (active low)
    input  wire                  i_rd_en,     // Read enable
    output reg  [DATA_WIDTH-1:0] o_rd_data,   // Read data
    output wire                  o_rd_empty,  // FIFO empty signal
    output wire [ADDR_WIDTH:0]   o_rd_count   // Read count (optional)
);

    // FIFO memory
    reg [DATA_WIDTH-1:0] mem [(1<<ADDR_WIDTH)-1:0];
    
    // Write pointer management (in write clock domain)
    reg [ADDR_WIDTH:0] wr_ptr_bin = 0;        // Binary write pointer
    wire [ADDR_WIDTH:0] wr_ptr_gray;          // Gray-coded write pointer
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync1 = 0; // Synchronized read pointer (gray)
    reg [ADDR_WIDTH:0] rd_ptr_gray_sync2 = 0; // Synchronized read pointer (gray)
    wire [ADDR_WIDTH:0] rd_ptr_bin_sync;      // Synchronized read pointer (binary)
    
    // Read pointer management (in read clock domain)
    reg [ADDR_WIDTH:0] rd_ptr_bin = 0;        // Binary read pointer
    wire [ADDR_WIDTH:0] rd_ptr_gray;          // Gray-coded read pointer
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync1 = 0; // Synchronized write pointer (gray)
    reg [ADDR_WIDTH:0] wr_ptr_gray_sync2 = 0; // Synchronized write pointer (gray)
    wire [ADDR_WIDTH:0] wr_ptr_bin_sync;      // Synchronized write pointer (binary)
    
    // Conversion functions
    // Binary to Gray code conversion
    assign wr_ptr_gray = wr_ptr_bin ^ (wr_ptr_bin >> 1);
    assign rd_ptr_gray = rd_ptr_bin ^ (rd_ptr_bin >> 1);
    
    // Gray to Binary conversion
    function [ADDR_WIDTH:0] gray2bin;
        input [ADDR_WIDTH:0] gray;
        reg [ADDR_WIDTH:0] bin;
        integer i;
        begin
            bin = gray;
            for (i = 1; i <= ADDR_WIDTH; i = i + 1)
                bin = bin ^ (gray >> i);
            gray2bin = bin;
        end
    endfunction
    
    // Synchronize read pointer to write clock domain
    always @(posedge i_wr_clk or negedge i_wr_rstn) begin
        if (!i_wr_rstn) begin
            rd_ptr_gray_sync1 <= 0;
            rd_ptr_gray_sync2 <= 0;
        end else begin
            rd_ptr_gray_sync1 <= rd_ptr_gray;
            rd_ptr_gray_sync2 <= rd_ptr_gray_sync1;
        end
    end
    
    // Synchronize write pointer to read clock domain
    always @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            wr_ptr_gray_sync1 <= 0;
            wr_ptr_gray_sync2 <= 0;
        end else begin
            wr_ptr_gray_sync1 <= wr_ptr_gray;
            wr_ptr_gray_sync2 <= wr_ptr_gray_sync1;
        end
    end
    
    // Convert synchronized gray code pointers back to binary
    assign rd_ptr_bin_sync = gray2bin(rd_ptr_gray_sync2);
    assign wr_ptr_bin_sync = gray2bin(wr_ptr_gray_sync2);
    
    // FIFO status signals
    assign o_wr_full = ((wr_ptr_bin[ADDR_WIDTH-1:0] == rd_ptr_bin_sync[ADDR_WIDTH-1:0]) && 
                       (wr_ptr_bin[ADDR_WIDTH] != rd_ptr_bin_sync[ADDR_WIDTH]));
                       
    assign o_rd_empty = (rd_ptr_bin == wr_ptr_bin_sync);
    
    // FIFO counts
    assign o_wr_count = wr_ptr_bin - rd_ptr_bin_sync;
    assign o_rd_count = wr_ptr_bin_sync - rd_ptr_bin;
    
    // Write logic
    always @(posedge i_wr_clk) begin
        if (i_wr_en && !o_wr_full) begin
            mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= i_wr_data;
        end
    end
    
    // Update write pointer
    always @(posedge i_wr_clk or negedge i_wr_rstn) begin
        if (!i_wr_rstn) begin
            wr_ptr_bin <= 0;
        end else if (i_wr_en && !o_wr_full) begin
            wr_ptr_bin <= wr_ptr_bin + 1;
        end
    end
    
    // Read logic
    always @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            o_rd_data <= {DATA_WIDTH{1'b0}};
        end else if (i_rd_en && !o_rd_empty) begin
            o_rd_data <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
        end
    end
    
    // Update read pointer
    always @(posedge i_rd_clk or negedge i_rd_rstn) begin
        if (!i_rd_rstn) begin
            rd_ptr_bin <= 0;
        end else if (i_rd_en && !o_rd_empty) begin
            rd_ptr_bin <= rd_ptr_bin + 1;
        end
    end

endmodule