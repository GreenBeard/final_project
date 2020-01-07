	component final_project_soc is
		port (
			clk_clk            : in  std_logic                     := 'X';             -- clk
			nes_clk_clk        : out std_logic;                                        -- clk
			reset_reset_n      : in  std_logic                     := 'X';             -- reset_n
			sdram_clk_clk      : out std_logic;                                        -- clk
			vga_clk_clk        : out std_logic;                                        -- clk
			plll_locked_export : out std_logic;                                        -- export
			slave_read         : in  std_logic                     := 'X';             -- read
			slave_write        : in  std_logic                     := 'X';             -- write
			slave_address      : in  std_logic_vector(1 downto 0)  := (others => 'X'); -- address
			slave_readdata     : out std_logic_vector(31 downto 0);                    -- readdata
			slave_writedata    : in  std_logic_vector(31 downto 0) := (others => 'X')  -- writedata
		);
	end component final_project_soc;

	u0 : component final_project_soc
		port map (
			clk_clk            => CONNECTED_TO_clk_clk,            --         clk.clk
			nes_clk_clk        => CONNECTED_TO_nes_clk_clk,        --     nes_clk.clk
			reset_reset_n      => CONNECTED_TO_reset_reset_n,      --       reset.reset_n
			sdram_clk_clk      => CONNECTED_TO_sdram_clk_clk,      --   sdram_clk.clk
			vga_clk_clk        => CONNECTED_TO_vga_clk_clk,        --     vga_clk.clk
			plll_locked_export => CONNECTED_TO_plll_locked_export, -- plll_locked.export
			slave_read         => CONNECTED_TO_slave_read,         --       slave.read
			slave_write        => CONNECTED_TO_slave_write,        --            .write
			slave_address      => CONNECTED_TO_slave_address,      --            .address
			slave_readdata     => CONNECTED_TO_slave_readdata,     --            .readdata
			slave_writedata    => CONNECTED_TO_slave_writedata     --            .writedata
		);

