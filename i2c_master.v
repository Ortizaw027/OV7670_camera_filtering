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
  
  reg[7:0] state;
  reg[7:0] temp_addr;
  reg[7:0] temp_data;
  reg[7:0] counter1 = 0;
  reg[7:0] counter2 = 0;
  reg wr_enable;
  reg sda_out;
  reg i2c_clk;
  reg i2c_scl_enable = 0;
  
  //logic for clock generation
  always @(posedge i_clk)
    begin
      if(counter1 == (div_const/2) -1)
        begin
          i2c_clk = ~i2c_clk;
          counter1 = 0;
        end
      else
        counter1 = counter1 + 1;
    end
  //Gives clk to scl when enable is 1
  assign io_scl = (i2c_scl_enable == 0)? 1: i2c_clk;
  
  //Logic for i2c scl enable
  always @(posedge i2c_clk, posedge i_rst)
    begin
      if(i_rst == 1)
        i2c_scl_enable <= 0;
      else if(state = IDLE || state == START || state ==  STOP)
        i2c_scl_enable <= 0;
      else
        i2c_scl_enable <= 1;
    end
  
  //State machine logic
  always @(posedge i2c_clk, posedge i_rst)
    begin
      case(state)
        IDLE:
          begin
            if(i_enable)
              begin
                state <= START;
                temp_addr <= {i_addr,i_rd_wr};
                temp_data <= i_din;
              end
            else
              state <= IDLE;
          end
        
        START:
          begin
            counter2 <= 7;
            state <= ADDRESS;
          end
        
        ADDRESS:
          begin
            if(counter2 == 0)
              begin
                state <= READ_ACK;
              end
            else
              counter2 <= counter2 - 1;
          end
        
        READ_ACK:
          begin
            if(io_sda == 0)
                counter2 <= 7;
                if(temp_addr[0] == 0)
                  state <= WRITE_DATA;
                else if (temp_addr[0] == 1)
                  state <= READ_DATA;
                else
                  state <= STOP;
          end
        
        WRITE_DATA:
          begin
            if(counter2 == 0)
              begin
                state <= READ_ACK_2;
              end
            else
              counter2 <= counter2 - 1;
          end
        
        READ_ACK_2:
          begin
            if((io_sda == 0) && i_enbable == 1)
              state <= IDLE;
            else
              state <= STOP;
          end
        
        READ_DATA:
          begin
            o_dout[counter2] <= io_sda;
            if (counter2 == 0)
              state <= WRITE_ACK;
            else
              counter2 <= counter2 - 1;
          end
        
        WRITE_ACK:
          begin
            state <= STOP;
          end
        
        STOP:
          begin
            state <= IDLE;
          end
        
        
      endcase
      
    end
  
  //Logic for generating output
  always @(posedge i2c_clk, posedge i_rst)
    begin
      if(i_rst == 1)
        begin
          wr_enable <= 1;
          sda_out <= 1;
        end
      else 
        begin
          case(state)
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
            
            //READ_ACK_2 no output logic needed
            
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
  
 //Logic for SDA line
  
  assign io_sda = (wr_enable == 1) ? sda_out : 'bz;
  
 //Logic for ready signal
  
  assign o_ready = ((rst == 0) && (state == IDLE)) ? 1 : 0;
  
          
endmodule
