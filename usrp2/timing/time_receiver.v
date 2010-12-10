
module time_receiver
  (input clk, input rst,
   output reg [63:0] vita_time,
   output reg sync_rcvd,
   input exp_time_in);

   wire       code_err, disp_err, dispout, complete_word;
   reg 	      disp_reg;
   reg [9:0]  shiftreg;
   reg [3:0]  bit_count;
   wire [8:0] dataout;
   reg [8:0]  dataout_reg;
 	      
   always @(posedge clk)
     shiftreg <= {exp_time_in, shiftreg[9:1]};

   localparam COMMA_0 = 10'h283;
   localparam COMMA_1 = 10'h17c;
   
   wire       found_comma = (shiftreg == COMMA_0) | (shiftreg == COMMA_1);
   wire       set_disp = (shiftreg == COMMA_1);

   always @(posedge clk)
     if(rst)
       bit_count <= 0;
     else if(found_comma | complete_word)
       bit_count <= 0;
     else 
       bit_count <= bit_count + 1;
   assign     complete_word = (bit_count == 9);

   always @(posedge clk)
     if(set_disp)
       disp_reg <= 1;
     else if(complete_word)
       disp_reg <= dispout;

   always @(posedge clk)
     if(complete_word)
       dataout_reg <= dataout;
     
   decode_8b10b decode_8b10b 
     (.datain(shiftreg),.dispin(disp_reg),
      .dataout(dataout),.dispout(dispout),
      .code_err(code_err),.disp_err(disp_err) );

   reg 	      error;
   always @(posedge clk)
     if(complete_word)
       error <= code_err | disp_err;
   
   localparam STATE_IDLE = 0;
   localparam STATE_T0 = 1;
   localparam STATE_T1 = 2;
   localparam STATE_T2 = 3;
   localparam STATE_T3 = 4;
   localparam STATE_T4 = 5;
   localparam STATE_T5 = 6;
   localparam STATE_T6 = 7;
   localparam STATE_T7 = 8;
   localparam STATE_TAIL = 9;
   
   localparam HEAD = 9'h13c;   
   localparam TAIL = 9'h1F7;
   
   reg [3:0]  state;
   
   always @(posedge clk)
     if(rst)
       state <= STATE_IDLE;
     else if(complete_word)
       if(code_err | disp_err)
	 state <= STATE_IDLE;
       else
	 case(state)
	   STATE_IDLE :
	     if(dataout_reg == HEAD)
	       state <= STATE_T0;
	   STATE_T0 :
	     begin
		vita_time[63:56] <= dataout_reg[7:0];
		state <= STATE_T1;
	     end
	   STATE_T1 :
	     begin
		vita_time[55:48] <= dataout_reg[7:0];
		state <= STATE_T2;
	     end
	   STATE_T2 :
	     begin
		vita_time[47:40] <= dataout_reg[7:0];
		state <= STATE_T3;
	     end
	   STATE_T3 :
	     begin
		vita_time[39:32] <= dataout_reg[7:0];
		state <= STATE_T4;
	     end
	   STATE_T4 :
	     begin
		vita_time[31:24] <= dataout_reg[7:0];
		state <= STATE_T5;
	     end
	   STATE_T5 :
	     begin
		vita_time[23:16] <= dataout_reg[7:0];
		state <= STATE_T6;
	     end
	   STATE_T6 :
	     begin
		vita_time[15:8] <= dataout_reg[7:0];
		state <= STATE_T7;
	     end
	   STATE_T7 :
	     begin
		vita_time[7:0] <= dataout_reg[7:0];
		state <= STATE_TAIL;
	     end
	   STATE_TAIL :
	     state <= STATE_IDLE;
	 endcase // case(state)
   
   always @(posedge clk)
     if(rst)
       sync_rcvd <= 0;
     else
       sync_rcvd <= (complete_word & (state == STATE_TAIL) & (dataout_reg[8:0] == TAIL));
   
endmodule // time_sender
