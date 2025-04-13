`timescale 1ns / 1ps

module cam_init #(
    parameter CLK_FREQ = 27000000  // Adjusted to your board’s clock
)(
    input  wire        clk,
    input  wire        sccb_ready,       // From SCCB_Master
    input  wire [15:0] rom_data,         // From cam_rom
    input  wire        start,            // External start signal
    output reg  [7:0]  rom_addr,         // Address to read from ROM
    output reg         done,             // High when all configuration is complete
    output reg  [7:0]  sccb_addr,        // Register address to write
    output reg  [7:0]  sccb_data,        // Register data to write
    output reg         sccb_start        // Pulse high to begin SCCB write
);

    // FSM States
    localparam FSM_IDLE      = 0;
    localparam FSM_SEND_CMD  = 1;
    localparam FSM_DONE      = 2;
    localparam FSM_TIMER     = 3;

    // Internal state
    reg [2:0] FSM_state        = FSM_IDLE;
    reg [2:0] FSM_return_state = FSM_IDLE;
    reg [31:0] timer           = 0;

    // Initial values
    initial begin
        rom_addr     = 0;
        done         = 0;
        sccb_addr    = 0;
        sccb_data    = 0;
        sccb_start   = 0;
    end

    always @(posedge clk) begin
        case (FSM_state)

            FSM_IDLE: begin
                FSM_state <= start ? FSM_SEND_CMD : FSM_IDLE;
                rom_addr  <= 0;
                done      <= start ? 0 : done;
            end

            FSM_SEND_CMD: begin
                case (rom_data)
                    16'hFFFF: begin
                        // End of ROM
                        FSM_state <= FSM_DONE;
                    end

                    16'hFFF0: begin
                        // Delay instruction (approx 10 ms)
                        timer            <= CLK_FREQ / 100;
                        FSM_return_state <= FSM_SEND_CMD;
                        FSM_state        <= FSM_TIMER;
                        rom_addr         <= rom_addr + 1;
                    end

                    default: begin
                        // Send to SCCB_Master when it's ready
                        if (sccb_ready) begin
                            sccb_addr       <= rom_data[15:8];
                            sccb_data       <= rom_data[7:0];
                            sccb_start      <= 1;
                            timer           <= 0; // Just one-cycle delay
                            FSM_return_state <= FSM_SEND_CMD;
                            FSM_state       <= FSM_TIMER;
                            rom_addr        <= rom_addr + 1;
                        end
                    end
                endcase
            end

            FSM_DONE: begin
                // Configuration complete
                FSM_state <= FSM_IDLE;
                done      <= 1;
            end

            FSM_TIMER: begin
                FSM_state <= (timer == 0) ? FSM_return_state : FSM_TIMER;
                timer     <= (timer == 0) ? 0 : timer - 1;
                sccb_start <= 0;
            end

        endcase
    end

endmodule
