`timescale 1ns / 1ps
`default_nettype none

module cam_config_tb();
    // Clock and reset signals
    reg clk = 0;
    reg rstn = 0;
    
    // Control signals
    reg i2c_ready = 0;
    reg config_start = 0;
    
    // Output signals to monitor
    wire [7:0] rom_addr;
    wire i2c_start;
    wire [7:0] i2c_addr;
    wire [7:0] i2c_data;
    wire config_done;
    
    // ROM data output
    wire [15:0] rom_data;
    
    // Parameters for simulation
    parameter CLK_PERIOD = 37; // ~27MHz (37ns)
    parameter CLK_F = 1_000_000; // Reduced clock frequency for faster simulation
    parameter CAM_I2C_ADDR = 8'h42;
    
    // Instantiate the cam_rom module
    cam_rom rom_inst (
        .i_clk(clk),
        .i_rstn(rstn),
        .i_addr(rom_addr),
        .o_dout(rom_data)
    );
    
    // Instantiate the modified cam_config module
    cam_config #(
        .CLK_F(CLK_F),
        .CAM_I2C_ADDR(CAM_I2C_ADDR)
    ) dut (
        .i_clk(clk),
        .i_rstn(rstn),
        .i_i2c_ready(i2c_ready),
        .i_config_start(config_start),
        .i_rom_data(rom_data),
        .o_rom_addr(rom_addr),
        .o_i2c_start(i2c_start),
        .o_i2c_addr(i2c_addr),
        .o_i2c_data(i2c_data),
        .o_config_done(config_done)
    );
    
    // Clock generation
    always #(CLK_PERIOD/2) clk = ~clk;
    
    // I2C transaction tracking
    integer i2c_transactions = 0;
    integer delay_count = 0;
    
    // Log file for detailed results
    integer log_file;
    
    // Task to simulate I2C ready response
    task respond_to_i2c;
        begin
            @(posedge i2c_start);
            repeat(5) @(posedge clk); // Simulate some I2C transaction delay
            i2c_ready = 0;
            repeat(3) @(posedge clk);
            i2c_ready = 1;
            i2c_transactions = i2c_transactions + 1;
        end
    endtask
    
    // Main test sequence
    initial begin
        // Initialize log file
        log_file = $fopen("cam_config_sim.log", "w");
        if (!log_file) begin
            $display("Error: Could not open log file");
            $finish;
        end
        
        $fdisplay(log_file, "=== Camera Configuration Module Testbench ===");
        $fdisplay(log_file, "Time\tROM_Addr\tROM_Data\tI2C_Start\tI2C_Addr\tI2C_Data\tConfig_Done\tState");
        
        // Reset sequence
        rstn = 0;
        i2c_ready = 1; // I2C is initially ready
        config_start = 0;
        repeat(5) @(posedge clk);
        rstn = 1;
        repeat(5) @(posedge clk);
        
        // Start configuration
        $fdisplay(log_file, "Starting camera configuration...");
        config_start = 1;
        @(posedge clk);
        config_start = 0;
        
        // Monitor I2C transactions and respond to them
        fork
            // Process to log transactions
            begin
                while (!config_done) begin
                    @(posedge clk);
                    $fdisplay(log_file, "%0t\t%0d\t%h\t%b\t%h\t%h\t%b\t%0d", 
                            $time, rom_addr, rom_data, i2c_start, i2c_addr, i2c_data, config_done, dut.state);
                    
                    // Check for delay marker
                    if (rom_data == 16'hFF_F0) begin
                        $fdisplay(log_file, "  Delay marker detected at ROM addr %0d", rom_addr);
                        delay_count = delay_count + 1;
                    end
                end
            end
            
            // Process to respond to I2C transactions
            begin
                forever begin
                    respond_to_i2c;
                end
            end
        join_any
        
        // Configuration complete
        $fdisplay(log_file, "Configuration complete!");
        $fdisplay(log_file, "Total I2C transactions: %0d", i2c_transactions);
        $fdisplay(log_file, "Delay markers encountered: %0d", delay_count);
        
        // Check final status
        if (config_done) begin
            $fdisplay(log_file, "TEST PASSED: Configuration completed successfully");
            $display("TEST PASSED: Configuration completed successfully");
        end else begin
            $fdisplay(log_file, "TEST FAILED: Configuration did not complete");
            $display("TEST FAILED: Configuration did not complete");
        end
        
        // Close log file
        $fclose(log_file);
        
        // Finish simulation
        #1000;
        $finish;
    end
    
    // Timeout to prevent infinite simulation
    initial begin
        #10000000; // 10ms
        $fdisplay(log_file, "TEST FAILED: Simulation timeout");
        $display("TEST FAILED: Simulation timeout");
        $fclose(log_file);
        $finish;
    end
    
    // Add debug monitoring
    initial begin
        $monitor("Time: %0t, ROM Addr: %0d, I2C Start: %b, I2C Addr: %h, I2C Data: %h, Config Done: %b", 
                 $time, rom_addr, i2c_start, i2c_addr, i2c_data, config_done);
    end
    
endmodule
