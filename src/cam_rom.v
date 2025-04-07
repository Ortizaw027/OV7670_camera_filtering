`timescale 1ns / 1ps
`default_nettype none

/*
 *  Synchronous ROM that contains OV7670 reg addr, OV7670 reg data;
 *  End of ROM is marked by o_dout = 16'hFF_FF
 *
 *  NOTE:  
 *  - One clock cycle delay
 *  - Must reset SCCB registers first then include 10 ms delay after
 *    to allow the change to settle
 *  
 */

module cam_rom (
    input wire        i_clk,      // 27 MHz clock
    input wire        i_rstn,     // Active-low reset
    input wire  [7:0] i_addr,     // Address input
    output reg [15:0] o_dout      // Data output (16-bit: {REG_ADDR, REG_DATA})
);

    // Registers for OV7670 for configuration of RGB 444 
    always @(posedge i_clk or negedge i_rstn) begin
        if (!i_rstn) begin
            o_dout <= 16'h0000; // Reset output
        end else begin
            case (i_addr)
                0:  o_dout <= 16'h12_80;  // COM7:        Reset SCCB registers
                1:  o_dout <= 16'hFF_F0;  // Delay
                2:  o_dout <= 16'h12_14;  // COM7,        Set RGB color output
                3:  o_dout <= 16'h11_00;  // CLKRC        Internal PLL matches input clock (24 MHz). 
                4:  o_dout <= 16'h0C_0C;  // COM3,        *Leave as default.
                5:  o_dout <= 16'h3E_00;  // COM14,       *Leave as default. No scaling, normal pclock
                6:  o_dout <= 16'h04_00;  // COM1,        *Leave as default. Disable CCIR656
                7:  o_dout <= 16'h8C_02;  // RGB444       Enable RGB444 mode with xR GB.
                8:  o_dout <= 16'h40_D0;  // COM15,       Output full range for RGB 444. 
                9:  o_dout <= 16'h3A_04;  // TSLB         Set correct output data sequence (magic)
                10: o_dout <= 16'h14_18;  // COM9         MAX AGC value x4
                11: o_dout <= 16'h4F_B3;  // MTX1         All of these are magical matrix coefficients
                12: o_dout <= 16'h50_B3;  // MTX2
                13: o_dout <= 16'h51_00;  // MTX3
                14: o_dout <= 16'h52_3D;  // MTX4
                15: o_dout <= 16'h53_A7;  // MTX5
                16: o_dout <= 16'h54_E4;  // MTX6
                17: o_dout <= 16'h58_9E;  // MTXS
                18: o_dout <= 16'h3D_C0;  // COM13        Sets gamma enable, does not preserve reserved bits, may be wrong?
                19: o_dout <= 16'h17_14;  // HSTART       Start high 8 bits
                20: o_dout <= 16'h18_02;  // HSTOP        Stop high 8 bits // These kill the odd colored line
                21: o_dout <= 16'h32_80;  // HREF         Edge offset
                22: o_dout <= 16'h19_03;  // VSTART       Start high 8 bits
                23: o_dout <= 16'h1A_7B;  // VSTOP        Stop high 8 bits
                24: o_dout <= 16'h03_0A;  // VREF         Vsync edge offset
                25: o_dout <= 16'h0F_41;  // COM6         Reset timings
                26: o_dout <= 16'h1E_00;  // MVFP         Disable mirror / flip // Might have magic value of 03
                27: o_dout <= 16'h33_0B;  // CHLF         Magic value from the internet
                28: o_dout <= 16'h3C_78;  // COM12        No HREF when VSYNC low
                29: o_dout <= 16'h69_00;  // GFIX         Fix gain control
                30: o_dout <= 16'h74_00;  // REG74        Digital gain control
                31: o_dout <= 16'hB0_84;  // RSVD         Magic value from the internet *required* for good color
                32: o_dout <= 16'hB1_0C;  // ABLC1
                33: o_dout <= 16'hB2_0E;  // RSVD         More magic internet values
                34: o_dout <= 16'hB3_80;  // THL_ST
                // Begin mystery scaling numbers
                35: o_dout <= 16'h70_3A;  // SCALING_XSC          *Leave as default. No test pattern output. 
                36: o_dout <= 16'h71_35;  // SCALING_YSC          *Leave as default. No test pattern output.
                37: o_dout <= 16'h72_11;  // SCALING_DCWCTR       *Leave as default. Vertical down sample by 2. Horizontal down sample by 2.
                38: o_dout <= 16'h73_F0;  // SCALING_PCLK_DIV 
                39: o_dout <= 16'hA2_02;  // SCALING_PCLK_DELAY   *Leave as default. 
                // Gamma curve values
                40: o_dout <= 16'h7A_20;  // SLOP
                41: o_dout <= 16'h7B_10;  // GAM1
                42: o_dout <= 16'h7C_1E;  // GAM2
                43: o_dout <= 16'h7D_35;  // GAM3
                44: o_dout <= 16'h7E_5A;  // GAM4
                45: o_dout <= 16'h7F_69;  // GAM5
                46: o_dout <= 16'h80_76;  // GAM6
                47: o_dout <= 16'h81_80;  // GAM7
                48: o_dout <= 16'h82_88;  // GAM8
                49: o_dout <= 16'h83_8F;  // GAM9
                50: o_dout <= 16'h84_96;  // GAM10
                51: o_dout <= 16'h85_A3;  // GAM11
                52: o_dout <= 16'h86_AF;  // GAM12
                53: o_dout <= 16'h87_C4;  // GAM13
                54: o_dout <= 16'h88_D7;  // GAM14
                55: o_dout <= 16'h89_E8;  // GAM15
                // AGC and AEC
                56: o_dout <= 16'h13_E0;  // COM8     Disable AGC / AEC
                57: o_dout <= 16'h00_00;  // Set gain reg to 0 for AGC
                58: o_dout <= 16'h10_00;  // Set ARCJ reg to 0
                59: o_dout <= 16'h0D_40;  // Magic reserved bit for COM4
                60: o_dout <= 16'h14_18;  // COM9, 4x gain + magic bit
                61: o_dout <= 16'hA5_05;  // BD50MAX
                62: o_dout <= 16'hAB_07;  // DB60MAX
                63: o_dout <= 16'h24_95;  // AGC upper limit
                64: o_dout <= 16'h25_33;  // AGC lower limit
                65: o_dout <= 16'h26_E3;  // AGC/AEC fast mode op region
                66: o_dout <= 16'h9F_78;  // HAECC1
                67: o_dout <= 16'hA0_68;  // HAECC2
                68: o_dout <= 16'hA1_03;  // Magic
                69: o_dout <= 16'hA6_D8;  // HAECC3
                70: o_dout <= 16'hA7_D8;  // HAECC4
                71: o_dout <= 16'hA8_F0;  // HAECC5
                72: o_dout <= 16'hA9_90;  // HAECC6
                73: o_dout <= 16'hAA_94;  // HAECC7
                74: o_dout <= 16'h13_A7;  // COM8, enable AGC / AEC
                75: o_dout <= 16'h69_06;     
                default: o_dout <= 16'hFF_FF; // Mark end of ROM
            endcase
        end
    end

endmodule