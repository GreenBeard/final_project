set_time_format -unit ns -decimal_places 3

create_clock -name {main_clk_50} -period 20.000 -waveform { 0.000 10.000 } [get_ports {clock}]

create_clock -name {ps2_clock} -period 50000.000 -waveform { 0.000 25000.000 } [get_ports {ps2_clock}]

derive_clock_uncertainty

create_generated_clock -name master_clock -source [get_ports {clock}] -divide_by 1050 -multiply_by 450 [get_pins {nios_soc|sdram_pll|sd1|pll7|clk[3]}]
create_generated_clock -name vga_clock -source [get_ports {clock}] -divide_by 2 -multiply_by 1 [get_pins {nios_soc|sdram_pll|sd1|pll7|clk[2]}]

create_generated_clock -name {sram_clock} -source [get_pins {nios_soc|sdram_pll|sd1|pll7|clk[3]}] -master_clock {master_clock} -divide_by 2 -multiply_by 1 -duty_cycle 50 [get_registers {mapper|cpu_turn}]

create_generated_clock -name cpu_clock -source nios_soc|sdram_pll|sd1|pll7|clk[3] -divide_by 12 -multiply_by 1 [get_registers processor|master_to_cpu|out_clk]

create_generated_clock -name ppu_clock -source nios_soc|sdram_pll|sd1|pll7|clk[3] -divide_by 4 -multiply_by 1 [get_registers ppu|master_to_ppu|out_clk]

# Constrain the input I/O path
set_input_delay -clock main_clk_50 -max 3 [all_inputs]
set_input_delay -clock main_clk_50 -min 1 [all_inputs]

# Constrain the output I/O path
set_output_delay -clock main_clk_50 -max 3 [all_outputs]
set_output_delay -clock main_clk_50 -min 1 [all_outputs]

# Constrain the SRAM outputs, and inputs
set_output_delay -clock sram_clock -max 42 [get_ports {sram_ce}]
set_output_delay -clock sram_clock -min 1 [get_ports {sram_ce}]
set_output_delay -clock sram_clock -max 42 [get_ports {sram_ub}]
set_output_delay -clock sram_clock -min 1 [get_ports {sram_ub}]
set_output_delay -clock sram_clock -max 42 [get_ports {sram_lb}]
set_output_delay -clock sram_clock -min 1 [get_ports {sram_lb}]
set_output_delay -clock sram_clock -max 42 [get_ports {sram_oe}]
set_output_delay -clock sram_clock -min 1 [get_ports {sram_oe}]
set_output_delay -clock sram_clock -max 42 [get_ports {sram_we}]
set_output_delay -clock sram_clock -min 1 [get_ports {sram_we}]
set_output_delay -clock sram_clock -max 42 [get_ports {sram_addr[*]}]
set_output_delay -clock sram_clock -min 1 [get_ports {sram_addr[*]}]

set_output_delay -clock sram_clock -max 42 [get_ports {sram_data[*]}]
set_output_delay -clock sram_clock -min 1 [get_ports {sram_data[*]}]
set_input_delay -clock sram_clock -max 15 [get_ports {sram_data[*]}]
set_input_delay -clock sram_clock -min 0 [get_ports {sram_data[*]}]
