
`timescale 1ns / 1ps
`default_nettype none

module cam_init_tb;

    // Testbench parameters
    parameter CLK_F = 27_000_000;  // 27 MHz clock (Tang Nano 9k)
    parameter I2C_F = 400_000;     // I2C clock frequency (400 kHz)
    parameter CLK_PERIOD = 37;     // Clock period in ns (27 MHz ≈ 37 ns)

    // Testbench signals
    reg         i_clk;             // System clock
    reg         i_rstn;            // Active-low reset
    reg         i_cam_init_start;  // Start camera initialization
    wire        o_siod;            // I2C data line (SDA)
    wire        o_sioc;            // I2C clock line (SCL)
    wire        o_cam_init_done;   // Camera initialization done signal
    wire        o_data_sent_done;  // Data sent done signal (for debugging)
    wire [7:0]  o_I2C_dout;        // I2C data output (for debugging)

    // Instantiate the cam_init module
    cam_init #(
        .CLK_F(CLK_F),             // 27 MHz clock
        .I2C_F(I2C_F)              // I2C clock frequency (400 kHz)
    ) uut (
        .i_clk(i_clk),             // System clock
        .i_rstn(i_rstn),           // Active-low reset
        .i_cam_init_start(i_cam_init_start), // Start initialization
        .o_siod(o_siod),           // I2C data line (SDA)
        .o_sioc(o_sioc),           // I2C clock line (SCL)
        .o_cam_init_done(o_cam_init_done), // Initialization done signal
        .o_data_sent_done(o_data_sent_done), // Data sent done signal
        .o_I2C_dout(o_I2C_dout)    // I2C data output (for debugging)
    );

    // Clock generation
    initial begin
        i_clk = 0;
        forever #(CLK_PERIOD / 2) i_clk = ~i_clk; // Toggle clock every half period
    end

    // Testbench stimulus
    initial begin
        // Initialize signals
        i_rstn = 0;               // Assert reset (active low)
        i_cam_init_start = 0;     // Deassert start signal
        #100;                     // Wait for 100 ns

        // Release reset
        i_rstn = 1;               // Deassert reset
        #100;                     // Wait for 100 ns

        // Start camera initialization
        i_cam_init_start = 1;     // Assert start signal
        #100;                     // Wait for 100 ns
        i_cam_init_start = 0;     // Deassert start signal

        // Wait for initialization to complete
        wait (o_cam_init_done == 1); // Wait for o_cam_init_done to be asserted
        #1000;                    // Wait for an additional 1 us

        // End simulation
        $display("Simulation complete. Camera initialization done: %b", o_cam_init_done);
        $finish;
    end

    // Monitor signals
    initial begin
        $monitor("Time: %0t | i_rstn: %b | i_cam_init_start: %b | o_cam_init_done: %b | o_siod: %b | o_sioc: %b",
                 $time, i_rstn, i_cam_init_start, o_cam_init_done, o_siod, o_sioc);
    end

endmodule
