`timescale 1ns / 1ps

module SCCB_Master #(
    parameter CLK_FREQ   = 27000000,   // Main clock frequency (Tang Nano 9K default)
    parameter SCCB_FREQ  = 100000      // I2C/SCCB frequency (100 kHz)
)(
    input  wire clk,
    input  wire start,
    input  wire [7:0] address,
    input  wire [7:0] data,
    output reg  ready,
    output reg  SCL_oe,
    output reg  SDA_oe
);

    // OV7670 8-bit write address
    localparam CAMERA_ADDR = 8'h42;

    // FSM state encoding
    localparam FSM_IDLE            =  0;
    localparam FSM_START_SIGNAL    =  1;
    localparam FSM_LOAD_BYTE       =  2;
    localparam FSM_TX_BYTE_1       =  3;
    localparam FSM_TX_BYTE_2       =  4;
    localparam FSM_TX_BYTE_3       =  5;
    localparam FSM_TX_BYTE_4       =  6;
    localparam FSM_END_SIGNAL_1    =  7;
    localparam FSM_END_SIGNAL_2    =  8;
    localparam FSM_END_SIGNAL_3    =  9;
    localparam FSM_END_SIGNAL_4    = 10;
    localparam FSM_DONE            = 11;
    localparam FSM_TIMER           = 12;

    // Internal registers
    reg [3:0] FSM_state         = FSM_IDLE;
    reg [3:0] FSM_return_state  = FSM_IDLE;
    reg [31:0] timer            = 0;
    reg [7:0] latched_address   = 0;
    reg [7:0] latched_data      = 0;
    reg [1:0] byte_counter      = 0;
    reg [7:0] tx_byte           = 0;
    reg [3:0] byte_index        = 0;

    // Initial reset states
    initial begin
        SCL_oe = 0;
        SDA_oe = 0;
        ready  = 1;
    end

    always @(posedge clk) begin
        case (FSM_state)

            FSM_IDLE: begin
                byte_index   <= 0;
                byte_counter <= 0;
                ready        <= ~start;
                if (start) begin
                    FSM_state        <= FSM_START_SIGNAL;
                    latched_address  <= address;
                    latched_data     <= data;
                end
            end

            FSM_START_SIGNAL: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_LOAD_BYTE;
                timer            <= (CLK_FREQ / (4 * SCCB_FREQ));
                SCL_oe           <= 0;
                SDA_oe           <= 1; // Start condition
            end

            FSM_LOAD_BYTE: begin
                FSM_state    <= (byte_counter == 3) ? FSM_END_SIGNAL_1 : FSM_TX_BYTE_1;
                byte_counter <= byte_counter + 1;
                byte_index   <= 0;
                case (byte_counter)
                    0: tx_byte <= CAMERA_ADDR;
                    1: tx_byte <= latched_address;
                    2: tx_byte <= latched_data;
                    default: tx_byte <= latched_data;
                endcase
            end

            FSM_TX_BYTE_1: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_TX_BYTE_2;
                timer            <= (CLK_FREQ / (4 * SCCB_FREQ));
                SCL_oe           <= 1;
            end

            FSM_TX_BYTE_2: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_TX_BYTE_3;
                timer            <= (CLK_FREQ / (4 * SCCB_FREQ));
                SDA_oe           <= (byte_index == 8) ? 0 : ~tx_byte[7];
            end

            FSM_TX_BYTE_3: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_TX_BYTE_4;
                timer            <= (CLK_FREQ / (2 * SCCB_FREQ));
                SCL_oe           <= 0;
            end

            FSM_TX_BYTE_4: begin
                FSM_state   <= (byte_index == 8) ? FSM_LOAD_BYTE : FSM_TX_BYTE_1;
                tx_byte     <= tx_byte << 1;
                byte_index  <= byte_index + 1;
            end

            FSM_END_SIGNAL_1: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_END_SIGNAL_2;
                timer            <= (CLK_FREQ / (4 * SCCB_FREQ));
                SCL_oe           <= 1;
            end

            FSM_END_SIGNAL_2: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_END_SIGNAL_3;
                timer            <= (CLK_FREQ / (4 * SCCB_FREQ));
                SDA_oe           <= 1;
            end

            FSM_END_SIGNAL_3: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_END_SIGNAL_4;
                timer            <= (CLK_FREQ / (4 * SCCB_FREQ));
                SCL_oe           <= 0;
            end

            FSM_END_SIGNAL_4: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_DONE;
                timer            <= (CLK_FREQ / (4 * SCCB_FREQ));
                SDA_oe           <= 0;
            end

            FSM_DONE: begin
                FSM_state        <= FSM_TIMER;
                FSM_return_state <= FSM_IDLE;
                timer            <= (2 * CLK_FREQ / SCCB_FREQ); // Delay before next start
                byte_counter     <= 0;
            end

            FSM_TIMER: begin
                if (timer == 0)
                    FSM_state <= FSM_return_state;
                else
                    timer <= timer - 1;
            end
        endcase
    end

endmodule
