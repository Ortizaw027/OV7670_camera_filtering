`timescale 1ns / 1ps
`default_nettype none
/*
*  Ran this on EDA Playground using the Icarus Verilog 12 option with
*  the I2C_master which resulted in a correct output
*/
module i2c_master_tb();

  // Parameters
  parameter CLK_PERIOD = 10; // 100MHz clock
  parameter I2C_SLAVE_ADDR = 7'h27;  // Example slave address
  
  // Testbench signals
  reg tb_clk = 0;
  reg tb_rst = 0;
  reg [6:0] tb_addr = 0;
  reg [7:0] tb_din = 0;
  reg tb_enable = 0;
  reg tb_rd_wr = 0;
  
  wire [7:0] tb_dout;
  wire tb_ready;
  
  // Bidirectional signals for I2C
  wire tb_sda;
  wire tb_scl;
  
  // Tri-state control for simulating slave device
  reg slave_sda_enable = 0;
  reg slave_sda_out = 1;
  
  // Assign bidirectional signals with pullups
  assign tb_sda = slave_sda_enable ? slave_sda_out : 1'bz;
  assign tb_scl = 1'bz;  // Let the DUT drive this
  
  // Instantiate the Device Under Test (DUT)
  i2c_master #(
    .div_const(4)  // Use same divider constant as module
  ) DUT (
    .i_clk(tb_clk),
    .i_rst(tb_rst),
    .i_addr(tb_addr),
    .i_din(tb_din),
    .i_enable(tb_enable),
    .i_rd_wr(tb_rd_wr),
    .o_dout(tb_dout),
    .o_ready(tb_ready),
    .io_sda(tb_sda),
    .io_scl(tb_scl)
  );
  
  // Clock generator
  always begin
    #(CLK_PERIOD/2) tb_clk = ~tb_clk;
  end
  
  // Simple slave ACK generator
  always @(negedge tb_scl) begin
    if (DUT.state == 3 || DUT.state == 7) begin // READ_ACK or READ_ACK_2
      #2; // Small delay
      slave_sda_enable = 1;
      slave_sda_out = 0; // ACK
      $display("Time %0t: Slave providing ACK in state %0d", $time, DUT.state);
    end else if (DUT.state == 6) begin // READ_DATA
      slave_sda_enable = 1;
      // Just output alternating bits for read data
      slave_sda_out = DUT.counter2[0];
    end else begin
      slave_sda_enable = 0;
    end
  end

  // Test sequence
  initial begin
    // Initialize testbench signals
    tb_rst = 1;
    tb_enable = 0;
    tb_addr = I2C_SLAVE_ADDR;
    tb_din = 8'h00;
    tb_rd_wr = 0;
    
    // Apply reset
    #(CLK_PERIOD*10);
    tb_rst = 0;
    #(CLK_PERIOD*10);
    
    // Wait for the module to be ready
    wait(tb_ready === 1);
    $display("Time %0t: I2C Master ready", $time);

    // TEST CASE 1: Write Operation
    $display("\n=== TEST CASE 1: Write Operation ===");
    tb_addr = I2C_SLAVE_ADDR;
    tb_din = 8'hA5;  // Test data
    tb_rd_wr = 0;    // Write operation
    
    // Enable the master and start transaction
    tb_enable = 1;
    
    // Wait for state to change from IDLE
    fork
      begin
        // Set timeout to detect stalled simulation
        #50000; // 50us timeout
        $display("ERROR: Timeout waiting for state to change from IDLE");
        $finish;
      end
      begin
        wait(DUT.state !== 0);
        $display("Time %0t: State changed to %0d", $time, DUT.state);
        disable fork; // Cancel the timeout
      end
    join
    
    // Wait for operation to complete (back to IDLE with ready=1)
    fork
      begin
        // Set timeout to detect stalled operation
        #500000; // 500us timeout
        $display("ERROR: Timeout waiting for operation to complete");
        $finish;
      end
      begin
        wait(tb_ready === 1 && DUT.state === 0);
        $display("Time %0t: Write operation completed", $time);
        disable fork; // Cancel the timeout
      end
    join
    
    // Deassert enable
    tb_enable = 0;
    
    // Wait between operations
    #(CLK_PERIOD*50);
    
    // TEST CASE 2: Read Operation
    $display("\n=== TEST CASE 2: Read Operation ===");
    tb_addr = I2C_SLAVE_ADDR;
    tb_rd_wr = 1;    // Read operation
    
    // Enable the master and start transaction
    tb_enable = 1;
    
    // Wait for state to change from IDLE
    fork
      begin
        // Set timeout to detect stalled simulation
        #50000; // 50us timeout
        $display("ERROR: Timeout waiting for state to change from IDLE");
        $finish;
      end
      begin
        wait(DUT.state !== 0);
        $display("Time %0t: State changed to %0d", $time, DUT.state);
        disable fork; // Cancel the timeout
      end
    join
    
    // Wait for operation to complete (back to IDLE with ready=1)
    fork
      begin
        // Set timeout to detect stalled operation
        #500000; // 500us timeout
        $display("ERROR: Timeout waiting for operation to complete");
        $finish;
      end
      begin
        wait(tb_ready === 1 && DUT.state === 0);
        $display("Time %0t: Read operation completed", $time);
        $display("Time %0t: Data read: 0x%h", $time, tb_dout);
        disable fork; // Cancel the timeout
      end
    join
    
    // Deassert enable
    tb_enable = 0;
    
    // End simulation
    #(CLK_PERIOD*100);
    $display("\n=== All tests completed ===");
    $finish;
  end
  
  // Debug monitor
  initial begin
    $display("Time\tState\ti2c_clk\tSCL\tSDA\tTemp_Addr\tCounter2\twr_en\tsda_out\tReady");
    $monitor("%0t\t%0d\t%b\t%b\t%b\t%h\t%0d\t%b\t%b\t%b", 
             $time, DUT.state, DUT.i2c_clk, tb_scl, tb_sda, 
             DUT.temp_addr, DUT.counter2, DUT.wr_enable, DUT.sda_out, tb_ready);
  end

endmodule
