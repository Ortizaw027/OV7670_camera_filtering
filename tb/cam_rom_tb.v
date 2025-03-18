`timescale 1ns / 1ps

module tb_cam_rom();

    // Inputs
    reg i_clk;
    reg i_rstn;
    reg [7:0] i_addr;

    // Outputs
    wire [15:0] o_dout;

    // Instantiate the cam_rom module
    cam_rom uut (
        .i_clk(i_clk),
        .i_rstn(i_rstn),
        .i_addr(i_addr),
        .o_dout(o_dout)
    );

    // Clock generation (27 MHz for Tang Nano 9k)
    initial begin
        i_clk = 0;
        forever #18.519 i_clk = ~i_clk; // 27 MHz clock (1/27 MHz ≈ 37.037 ns period)
    end

    // Test sequence
    initial begin
        // Initialize inputs
        i_rstn = 0; // Assert reset
        i_addr = 0;
        #37.037; // Hold reset for one clock cycle

        i_rstn = 1; // Deassert reset
        #37.037;

        // Test ROM reads
        i_addr = 0; // Read address 0
        #37.037;
        $display("ROM[0] = %h", o_dout); // Expected: 12_80

        i_addr = 1; // Read address 1
        #37.037;
        $display("ROM[1] = %h", o_dout); // Expected: FF_F0

        i_addr = 2; // Read address 2
        #37.037;
        $display("ROM[2] = %h", o_dout); // Expected: 12_04

        i_addr = 3; // Read address 3
        #37.037;
        $display("ROM[3] = %h", o_dout); // Expected: 11_00

        i_addr = 4; // Read address 4
        #37.037;
        $display("ROM[4] = %h", o_dout); // Expected: 0C_00

        i_addr = 5; // Read address 5
        #37.037;
        $display("ROM[5] = %h", o_dout); // Expected: 3E_00

        i_addr = 6; // Read address 6
        #37.037;
        $display("ROM[6] = %h", o_dout); // Expected: 04_00

        i_addr = 7; // Read address 7
        #37.037;
        $display("ROM[7] = %h", o_dout); // Expected: 8C_02

        i_addr = 8; // Read address 8
        #37.037;
        $display("ROM[8] = %h", o_dout); // Expected: 40_D0

        i_addr = 9; // Read address 9
        #37.037;
        $display("ROM[9] = %h", o_dout); // Expected: 3A_04

        i_addr = 10; // Read address 10
        #37.037;
        $display("ROM[10] = %h", o_dout); // Expected: 14_18

        // Continue testing other addresses as needed...

        // Test end of ROM marker
        i_addr = 76; // Read address 76 (end of ROM)
        #37.037;
        $display("ROM[76] = %h", o_dout); // Expected: FF_FF

        // End simulation
        $finish;
    end

endmodule
