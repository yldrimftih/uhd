`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////

module u1plus
  (input CLK_FPGA_P, input CLK_FPGA_N,  // Diff
   output [2:0] debug_led, output [31:0] debug, output [1:0] debug_clk,
   output FPGA_TXD, input FPGA_RXD,

   // GPIF
   inout [15:0] GPIF_D, input [3:0] GPIF_CTL, output [3:0] GPIF_RDY,
   input FX2_PA7_FLAGD, input FX2_PA6_PKTEND, input FX2_PA2_SLOE,
   input IFCLK,
   
   inout SDA_FPGA, inout SCL_FPGA, // I2C

   output SCLK_TX_DB, output SEN_TX_DB, output MOSI_TX_DB, input MISO_TX_DB,   // DB TX SPI
   output SCLK_RX_DB, output SEN_RX_DB, output MOSI_RX_DB, input MISO_RX_DB,   // DB TX SPI
   output SCLK_CODEC, output SEN_CODEC, output MOSI_CODEC, input MISO_CODEC,   // AD9862 main SPI

   input cgen_st_status, input cgen_st_ld, input cgen_st_refmon, output cgen_sync_b, output cgen_ref_sel,
   
   inout [15:0] io_tx, inout [15:0] io_rx,

   output [13:0] dac, output TXSYNC, output TXBLANK,
   input [11:0] adc, input RXSYNC,
  
   input PPS_IN
   );

   // /////////////////////////////////////////////////////////////////////////
   // Clocking
   wire  clk_fpga, clk_fpga_in, reset;
   
   IBUFGDS #(.IOSTANDARD("LVDS_33"), .DIFF_TERM("TRUE")) 
   clk_fpga_pin (.O(clk_fpga_in),.I(CLK_FPGA_P),.IB(CLK_FPGA_N));

   BUFG clk_fpga_BUFG (.I(clk_fpga_in), .O(clk_fpga));
   
   reset_sync reset_sync(.clk(clk_fpga), .reset_in(~reset_n), .reset_out(reset));
   
   // /////////////////////////////////////////////////////////////////////////
   // SPI
   wire  mosi, sclk, miso;
   assign { SCLK_TX_DB, MOSI_TX_DB } = ~SEN_TX_DB ? {sclk,mosi} : 2'b0;
   assign { SCLK_RX_DB, MOSI_RX_DB } = ~SEN_RX_DB ? {sclk,mosi} : 2'b0;
   assign { SCLK_CODEC, MOSI_CODEC } = ~SEN_CODEC ? {sclk,mosi} : 2'b0;
   assign miso = (~SEN_TX_DB & MISO_TX_DB) | (~SEN_RX_DB & MISO_RX_DB) |
		 (~SEN_CODEC & MISO_CODEC);

   // /////////////////////////////////////////////////////////////////////////
   // TX DAC -- handle the interleaved data bus to DAC, with clock doubling DLL

   assign TXBLANK = 0;
   wire [13:0] tx_i, tx_q;

   genvar i;
   generate
      for(i=0;i<14;i=i+1)
	begin : gen_dacout
	   ODDR2 #(.DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1" 
		   .INIT(1'b0),            // Sets initial state of the Q output to 1'b0 or 1'b1
		   .SRTYPE("SYNC"))        // Specifies "SYNC" or "ASYNC" set/reset
	   ODDR2_inst (.Q(dac[i]),      // 1-bit DDR output data
		       .C0(clk_fpga),  // 1-bit clock input
		       .C1(~clk_fpga), // 1-bit clock input
		       .CE(1'b1),      // 1-bit clock enable input
		       .D0(tx_i[i]),   // 1-bit data input (associated with C0)
		       .D1(tx_q[i]),   // 1-bit data input (associated with C1)
		       .R(1'b0),       // 1-bit reset input
		       .S(1'b0));      // 1-bit set input
	end // block: gen_dacout
      endgenerate
   ODDR2 #(.DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1" 
	   .INIT(1'b0),            // Sets initial state of the Q output to 1'b0 or 1'b1
	   .SRTYPE("SYNC"))        // Specifies "SYNC" or "ASYNC" set/reset
   ODDR2_txsnc (.Q(TXSYNC),      // 1-bit DDR output data
		.C0(clk_fpga),  // 1-bit clock input
		.C1(~clk_fpga), // 1-bit clock input
		.CE(1'b1),      // 1-bit clock enable input
		.D0(1'b0),   // 1-bit data input (associated with C0)
		.D1(1'b1),   // 1-bit data input (associated with C1)
		.R(1'b0),       // 1-bit reset input
		.S(1'b0));      // 1-bit set input

   // /////////////////////////////////////////////////////////////////////////
   // RX ADC -- handles deinterleaving

   reg [11:0] rx_i, rx_q;
   wire [11:0] rx_a, rx_b;
   
   genvar      j;
   generate
      for(j=0;j<12;j=j+1)
	begin : gen_adcin
	   IDDR2 #(.DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1"
		   .INIT_Q0(1'b0),         // Sets initial state of the Q0 output to 1’b0 or 1’b1
		   .INIT_Q1(1'b0),         // Sets initial state of the Q1 output to 1’b0 or 1’b1
		   .SRTYPE("SYNC"))        // Specifies "SYNC" or "ASYNC" set/reset
	   IDDR2_inst (.Q0(rx_a[j]),      // 1-bit output captured with C0 clock
		       .Q1(rx_b[j]),      // 1-bit output captured with C1 clock
		       .C0(clk_fpga),     // 1-bit clock input
		       .C1(~clk_fpga),    // 1-bit clock input
		       .CE(1'b1),         // 1-bit clock enable input
		       .D(adc[j]),        // 1-bit DDR data input
		       .R(1'b0),          // 1-bit reset input
		       .S(1'b0));         // 1-bit set input
	end // block: gen_adcin
   endgenerate
   
   IDDR2 #(.DDR_ALIGNMENT("NONE"), // Sets output alignment to "NONE", "C0" or "C1"
	   .INIT_Q0(1'b0),         // Sets initial state of the Q0 output to 1’b0 or 1’b1
	   .INIT_Q1(1'b0),         // Sets initial state of the Q1 output to 1’b0 or 1’b1
	   .SRTYPE("SYNC"))        // Specifies "SYNC" or "ASYNC" set/reset
   IDDR2_sync (.Q0(rxsync_0),      // 1-bit output captured with C0 clock
	       .Q1(rxsync_1),      // 1-bit output captured with C1 clock
	       .C0(clk_fpga),     // 1-bit clock input
	       .C1(~clk_fpga),    // 1-bit clock input
	       .CE(1'b1),         // 1-bit clock enable input
	       .D(RXSYNC),        // 1-bit DDR data input
	       .R(1'b0),          // 1-bit reset input
	       .S(1'b0));         // 1-bit set input

   always @(posedge clk_fpga)
     if(rxsync_0)
       begin
	  rx_i <= rx_a;
	  rx_q <= rx_b;
       end
     else
       begin
	  rx_i <= rx_b;
	  rx_q <= rx_a;
       end
   
   // /////////////////////////////////////////////////////////////////////////
   // Main U1E Core
   u1plus_core u1p_c(.clk_fpga(clk_fpga), .rst_fpga(reset),
		     .debug_led(debug_led), .debug(debug), .debug_clk(debug_clk),
		     .debug_txd(FPGA_TXD), .debug_rxd(FPGA_RXD),
		     .gpif_d(GPIF_D), .gpif_ctl(GPIF_CTL), .gpif_rdy(GPIF_RDY),
		     .gpif_misc({FX2_PA7_FLAGD,FX_PA6_PKTEND,FX2_PA2_SLOE}),
		     .gpif_clk(IFCLK),

		     .db_sda(db_sda), .db_scl(db_scl),
		     .sclk(sclk), .sen({SEN_CODEC,SEN_TX_DB,SEN_RX_DB}), .mosi(mosi), .miso(miso),
		     .cgen_st_status(cgen_st_status), .cgen_st_ld(cgen_st_ld),.cgen_st_refmon(cgen_st_refmon), 
		     .cgen_sync_b(cgen_sync_b), .cgen_ref_sel(cgen_ref_sel),
		     .io_tx(io_tx), .io_rx(io_rx),
		     .tx_i(tx_i), .tx_q(tx_q), 
		     .rx_i(rx_i), .rx_q(rx_q),
		     .pps_in(PPS_IN) );

endmodule // u1plus
