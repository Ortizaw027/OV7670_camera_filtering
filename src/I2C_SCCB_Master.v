`timescale 1ns / 1ps
`default_nettype none
//I2C master that is compatible with SCCB protocol
module i2c_sccb_master (
  input wire i_clk,
  input wire i_rst,
  input wire [6:0] i_addr,
  input wire [7:0] i_din,
  input wire i_enable,
  input wire i_rd_wr,
  
  output reg [7:0] o_dout,
  output wire o_ready,
  
  inout wire io_sda,
  inout wire io_scl
);
  // States for the state machine
  parameter IDLE = 0;
  parameter START = 1;
  parameter ADDRESS = 2;
  parameter READ_ACK = 3;
  parameter WRITE_DATA = 4;
  parameter WRITE_ACK = 5;
  parameter READ_DATA = 6;
  parameter READ_DONE = 7;  // Modified: No ACK required for SCCB read operations
  parameter STOP = 8;
  
  // Clock divider parameter - adjust based on required SCCB frequency (typically 100-400 kHz)
  // For a 27MHz system clock and 100kHz SCCB, div_const would be around 270
  parameter div_const = 270;
  
  reg [7:0] state;
  reg [7:0] temp_addr;
  reg [7:0] temp_data;
  reg [7:0] counter1 = 0;
  reg [7:0] counter2 = 0;
  reg wr_enable;
  reg sda_out;
  reg i2c_clk = 0;
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

  // SCL control - Standard I2C/SCCB SCL output
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

  // State machine logic
  always @(posedge i2c_clk, posedge i_rst) begin
    if (i_rst == 1) begin
      state <= IDLE;
    end else begin
      case (state)
        IDLE:
          begin
            if (i_enable) begin
              state <= START;
              temp_addr <= {i_addr, i_rd_wr};
              temp_data <= i_din;
            end
          end

        START:
          begin
            counter2 <= 7;
            state <= ADDRESS;
          end

        ADDRESS:
          begin
            if (counter2 == 0) begin
              state <= READ_ACK;
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
              end else if (temp_addr[0] == 1) begin
                state <= READ_DATA;
              end else begin
                state <= STOP;
              end
            end else begin
              // NACK received - handle error or retry
              state <= STOP;
            end
          end

        WRITE_DATA:
          begin
            if (counter2 == 0) begin
              state <= READ_ACK;
            end else begin
              counter2 <= counter2 - 1;
            end
          end

        READ_DATA:
          begin
            o_dout[counter2] <= io_sda;
            if (counter2 == 0) begin
              // For SCCB: no ACK needed after read operations
              state <= READ_DONE;
            end else begin
              counter2 <= counter2 - 1;
            end
          end
          
        READ_DONE:
          begin
            // Skip sending ACK for SCCB - go directly to STOP
            state <= STOP;
          end

        WRITE_ACK:
          begin
            state <= STOP;
          end

        STOP:
          begin
            state <= IDLE;
          end
          
        default:
          begin
            state <= IDLE;
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
        IDLE:
          begin
            wr_enable <= 1;
            sda_out <= 1;
          end
          
        START:
          begin
            wr_enable <= 1;
            sda_out <= 0;
          end

        ADDRESS:
          begin
            wr_enable <= 1;
            sda_out <= temp_addr[counter2];
          end

        READ_ACK:
          begin
            wr_enable <= 0;  // Release SDA to read ACK
          end

        WRITE_DATA:
          begin
            wr_enable <= 1;
            sda_out <= temp_data[counter2];
          end

        READ_DATA:
          begin
            wr_enable <= 0;  // Release SDA to read data
          end
          
        READ_DONE:
          begin
            wr_enable <= 1;  // Take control of SDA for STOP
            sda_out <= 1;    // Prepare for STOP condition
          end

        WRITE_ACK:
          begin
            wr_enable <= 1;
            sda_out <= 0;    // Send ACK (pull SDA low)
          end

        STOP:
          begin
            wr_enable <= 1;
            sda_out <= 1;    // STOP condition: SDA goes high while SCL is high
          end
          
        default:
          begin
            wr_enable <= 1;
            sda_out <= 1;
          end
      endcase
    end
  end

  // SDA line control
  assign io_sda = (wr_enable == 1) ? sda_out : 1'bz;

  // Ready signal logic
  assign o_ready = ((i_rst == 0) && (state == IDLE)) ? 1 : 0;

endmodule