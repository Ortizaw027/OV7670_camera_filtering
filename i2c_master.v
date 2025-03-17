`timescale 1ns / 1ps
`default_nettype none

module i2c_master (
  input i_clk,
  input i_rst,
  input [6:0] i_addr,
  input [7:0] i_din,
  input i_enable,
  input i_rd_wr,
  
  output reg [7:0] o_dout,
  output wire o_ready,
  
  inout io_sda,
  inout io_scl
);
  
  parameter IDLE = 0;
  parameter START = 1;
  parameter ADDRESS = 2;
  parameter READ_ACK = 3;
  parameter WRITE_DATA = 4;
  parameter WRITE_ACK = 5;
  parameter READ_DATA = 6;
  parameter READ_ACK_2 = 7;
  parameter STOP = 8;
  parameter div_const = 4;
  
  reg [7:0] state;
  reg [7:0] temp_addr;
  reg [7:0] temp_data;
  reg [7:0] counter1 = 0;
  reg [7:0] counter2 = 0;
  reg wr_enable;
  reg sda_out;
  reg i2c_clk = 0;  // Initialize i2c_clk to 0
  reg i2c_scl_enable = 0;
  
  // Clock generation logic
  always @(posedge i_clk) begin
    if (counter1 == (div_const / 2) - 1) begin
      i2c_clk <= ~i2c_clk;
      counter1 <= 0;
    end else begin
      counter1 <= counter1 + 1;
    end
  end

  // SCL control
  assign io_scl = (i2c_scl_enable == 0) ? 1 : i2c_clk;

  // SCL enable logic
  always @(posedge i2c_clk, posedge i_rst) begin
    if (i_rst == 1) begin
      i2c_scl_enable <= 0;
    end else if (state == IDLE || state == START || state == STOP) begin
      i2c_scl_enable <= 0;
    end else begin
      i2c_scl_enable <= 1;
    end
  end

  // State machine logic with debug output
  always @(posedge i2c_clk, posedge i_rst) begin
    if (i_rst == 1) begin
      state <= IDLE;
      $display("DEBUG: Reset activated, moving to IDLE.");
    end else begin
      case (state)
        IDLE:
          begin
            if (i_enable) begin
              state <= START;
              temp_addr <= {i_addr, i_rd_wr};
              temp_data <= i_din;
              $display("DEBUG: Entering START state.");
            end
          end

        START:
          begin
            counter2 <= 7;
            state <= ADDRESS;
            $display("DEBUG: Entering ADDRESS state.");
          end

        ADDRESS:
          begin
            if (counter2 == 0) begin
              state <= READ_ACK;
              $display("DEBUG: Entering READ_ACK state.");
            end else begin
              counter2 <= counter2 - 1;
            end
          end

        READ_ACK:
          begin
            if (io_sda == 0) begin
              counter2 <= 7;
              if (temp_addr[0] == 0) begin
                state <= WRITE_DATA;
                $display("DEBUG: ACK received, entering WRITE_DATA state.");
              end else if (temp_addr[0] == 1) begin
                state <= READ_DATA;
                $display("DEBUG: ACK received, entering READ_DATA state.");
              end else begin
                state <= STOP;
              end
            end
          end

        WRITE_DATA:
          begin
            if (counter2 == 0) begin
              state <= READ_ACK_2;
              $display("DEBUG: Entering READ_ACK_2 state.");
            end else begin
              counter2 <= counter2 - 1;
            end
          end

        READ_ACK_2:
          begin
            if ((io_sda == 0) && (i_enable == 1)) begin
              state <= IDLE;
              $display("DEBUG: READ_ACK_2 complete, returning to IDLE.");
            end else begin
              state <= STOP;
            end
          end

        READ_DATA:
          begin
            o_dout[counter2] <= io_sda;
            if (counter2 == 0) begin
              state <= WRITE_ACK;
              $display("DEBUG: Read complete, entering WRITE_ACK state.");
            end else begin
              counter2 <= counter2 - 1;
            end
          end

        WRITE_ACK:
          begin
            state <= STOP;
            $display("DEBUG: Write ACK complete, entering STOP state.");
          end

        STOP:
          begin
            state <= IDLE;
            $display("DEBUG: STOP condition met, returning to IDLE.");
          end
      endcase
    end
  end

  // Output logic
  always @(posedge i2c_clk, posedge i_rst) begin
    if (i_rst == 1) begin
      wr_enable <= 1;
      sda_out <= 1;
    end else begin
      case (state)
        START:
          begin
            wr_enable <= 1;
            sda_out <= 0;
          end

        ADDRESS:
          begin
            sda_out <= temp_addr[counter2];
          end

        READ_ACK:
          begin
            wr_enable <= 0;
          end

        WRITE_DATA:
          begin
            wr_enable <= 1;
            sda_out <= temp_data[counter2];
          end

        READ_DATA:
          begin
            wr_enable <= 0;
          end

        WRITE_ACK:
          begin
            wr_enable <= 1;
            sda_out <= 0;
          end

        STOP:
          begin
            wr_enable <= 1;
            sda_out <= 1;
          end
      endcase
    end
  end

  // SDA line control
  assign io_sda = (wr_enable == 1) ? sda_out : 'bz;

  // Ready signal logic
  assign o_ready = ((i_rst == 0) && (state == IDLE)) ? 1 : 0;

endmodule
