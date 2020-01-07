
module final_project_soc (
	clk_clk,
	nes_clk_clk,
	reset_reset_n,
	sdram_clk_clk,
	vga_clk_clk,
	plll_locked_export,
	slave_read,
	slave_write,
	slave_address,
	slave_readdata,
	slave_writedata);	

	input		clk_clk;
	output		nes_clk_clk;
	input		reset_reset_n;
	output		sdram_clk_clk;
	output		vga_clk_clk;
	output		plll_locked_export;
	input		slave_read;
	input		slave_write;
	input	[1:0]	slave_address;
	output	[31:0]	slave_readdata;
	input	[31:0]	slave_writedata;
endmodule
