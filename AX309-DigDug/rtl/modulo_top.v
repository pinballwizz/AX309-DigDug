//--------------------------------- AX309-DigDug -------------------------------------
`timescale 1 ps / 1 ps

module digdug_top (
	input  wire clk50mhz,
	input  wire BTN_nRESET,
	output wire [3:0] red,
	output wire [3:0] green,
	output wire [3:0] blue,
	output wire hsync,
	output wire vsync,
	output wire audio_l,
	output wire audio_r,
	input  wire SW_LEFT,
	input  wire SW_RIGHT,
	input  wire SW_UP,
	input  wire SW_DOWN,
	input  wire SW_FIRE,
	output wire [7:0] hex,
	input  wire [3:0] key_in
);
//-----------------------------------------------------------------------------
	wire pllclk0;
	wire clkfbout;
	wire reset;
  
  BUFG pclkbufg (.I(pllclk0), .O(clk_48M));

  //////////////////////////////////////////////////////////////////
  // 10x pclk is used to drive IOCLK network so a bit rate reference
  // can be used by OSERDES2
  //////////////////////////////////////////////////////////////////
  PLL_BASE # (
    .CLKIN_PERIOD(20),
    .CLKFBOUT_MULT(20),  //Multiplica el Reloj de entrada para todos
    .CLKOUT0_DIVIDE(20.3468),  //20.3468 Mister -  20.83 Mist //Divide el valor multiplicado para OUT0
    .COMPENSATION("INTERNAL")
  ) PLL_OSERDES (
    .CLKFBOUT(clkfbout),
    .CLKOUT0(pllclk0),
    .CLKOUT1(),
    .CLKOUT2(),
    .CLKOUT3(),
    .CLKOUT4(),
    .CLKOUT5(),
    .LOCKED(pll_lckd),
    .CLKFBIN(clkfbout),
    .CLKIN(clk50mhz),
    .RST(1'b0)
  );
//---------------------------------------
// clocks
	reg [2:0] clkdiv;
	always @( posedge clk_48M ) clkdiv <= clkdiv+1;
	wire VCLKx8 = clk_48M;
	wire VCLKx4 = clkdiv[0];
	wire VCLKx2 = clkdiv[1];
	wire VCLK   = clkdiv[2];  
//----------------------------------------------------------------------------
	reg [7:0] delay_count;
	reg pm_reset;
	wire ena_12;
	wire ena_24;
	wire ena_x;  
//----------------------------------------------------------------------------  
  always @ (posedge clk_48M or negedge pll_lckd) begin
    if (!pll_lckd) begin
      delay_count <= 8'd0;
      pm_reset <= 1'b1;
    end else begin
      delay_count <= delay_count + 1'b1;
      if (delay_count == 8'hff)
        pm_reset <= 1'b0;        
    end
  end
//----------------------------------------------------------------------------    
	assign ena_x = delay_count[5];
	assign ena_24 = delay_count[0];
	assign ena_12 = delay_count[0] & ~delay_count[1];
	wire resetKey, master_reset, resetHW;
	assign resetHW = resetKey | !BTN_nRESET;
	wire bCabinet = 1'b1;
	wire iRST  = resetHW | pm_reset;
	wire ext_rst;
	wire [3:0]M_VIDEO_R, M_VIDEO_G, M_VIDEO_B;
	wire [3:0]X_VIDEO_R, X_VIDEO_G, X_VIDEO_B;
	wire M_HSYNC,M_VSYNC,M_AUDIO;
	wire X_HSYNC,X_VSYNC;
	assign red = X_VIDEO_R;
	assign green = X_VIDEO_G;
	assign blue =  X_VIDEO_B;
	assign hsync = X_HSYNC;
	assign vsync = X_VSYNC;
	assign hex = 8'b11111111;
	assign audio_l = M_AUDIO;
	assign audio_r = M_AUDIO;
	wire			PCLK;
	wire  [8:0] HPOS,VPOS;
	wire [11:0] POUT;
	wire [15:0] AOUT;
//--------------------------------------------------------------------------
HVGEN hvgen
(
	.HPOS(HPOS),.VPOS(VPOS),.PCLK(PCLK),.iRGB(POUT),
	.oRGB({M_VIDEO_B,M_VIDEO_G,M_VIDEO_R}),.HBLK(),.VBLK(),.HSYN(M_HSYNC),.VSYN(M_VSYNC)
);
//--------------------------------------------------------------------------
//                  LIFE   EXMD   COINB
	wire  [7:0] DSW0 = {2'b10,3'b111,3'b001};
//                  COIA  FRZE DSND CONT CABI DIFIC
	wire  [7:0] DSW1 = {2'b00,1'b1,1'b1,1'b1,1'b1,2'b00};
//                  SERVICE, 1'b0,m_coin2,m_coin1,m_start2,m_start1,m_pump2,m_pump1
	wire  [7:0] INP0 = {1'b0, 1'b0, key_in[3], key_in[0], key_in[2], key_in[1], SW_FIRE, SW_FIRE };
//                    left2   down2    right2    up2   left1     down1    right1    up1
	wire  [7:0] INP1 = {SW_LEFT, SW_DOWN, SW_RIGHT, SW_UP, SW_LEFT, SW_DOWN, SW_RIGHT, SW_UP };

	wire  [7:0] oPIX;
	wire  [7:0] oSND;
//----------------------------------------------------------------------------
FPGA_DIGDUG GameCore ( 
	.RESET(iRST),.MCLK(clk_48M),
	.INP0(INP0),.INP1(INP1),.DSW0(DSW0),.DSW1(DSW1),
	.PH(HPOS),.PV(VPOS),.PCLK(PCLK),.POUT(oPIX),
	.SOUT(oSND)
);
//----------------------------------------------------------------------------
	assign POUT = {oPIX[7:6],2'b00,oPIX[5:3],1'b0,oPIX[2:0],1'b0};
	assign AOUT = {oSND,8'h0};
//----------------------------------------------------------------------------
sigma_delta_dac #(15) dac
(
	.CLK(VCLK),
	.RESET(iRST),
	.DACin({~AOUT[15], AOUT[14:0]}),
	.DACout(M_AUDIO)
);
//------------------------------------------------------------------------------
  scandoubler sd (
	.clk_sys(VCLKx4),
	.video_r_in(M_VIDEO_R[3:0]),
	.video_g_in(M_VIDEO_G[3:0]),
	.video_b_in(M_VIDEO_B[3:0]),
	.hs_in(~M_HSYNC),
	.vs_in(~M_VSYNC),
	.video_r_out(X_VIDEO_R),
	.video_g_out(X_VIDEO_G),
	.video_b_out(X_VIDEO_B),
	.hs_out(X_HSYNC),
	.vs_out(X_VSYNC),
	.en_vid(PCLK),
	.scanlines(1'b0)
   );
//----------------------------------------------------------------------------
endmodule
