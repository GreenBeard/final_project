	final_project_soc u0 (
		.clk_clk            (<connected-to-clk_clk>),            //         clk.clk
		.nes_clk_clk        (<connected-to-nes_clk_clk>),        //     nes_clk.clk
		.reset_reset_n      (<connected-to-reset_reset_n>),      //       reset.reset_n
		.sdram_clk_clk      (<connected-to-sdram_clk_clk>),      //   sdram_clk.clk
		.vga_clk_clk        (<connected-to-vga_clk_clk>),        //     vga_clk.clk
		.plll_locked_export (<connected-to-plll_locked_export>), // plll_locked.export
		.slave_read         (<connected-to-slave_read>),         //       slave.read
		.slave_write        (<connected-to-slave_write>),        //            .write
		.slave_address      (<connected-to-slave_address>),      //            .address
		.slave_readdata     (<connected-to-slave_readdata>),     //            .readdata
		.slave_writedata    (<connected-to-slave_writedata>)     //            .writedata
	);

