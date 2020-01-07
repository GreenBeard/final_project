module verilator_test_wrapper(
  /* 50 MHz clock */
  input logic master_clock,

  /* Debug signals */
  input logic[3:0] keys,
  input [17:0] switches,
  output logic[6:0] HEX0,
  output logic[6:0] HEX1,
  output logic[6:0] HEX2,
  output logic[6:0] HEX3,
  output logic[6:0] HEX4,
  output logic[6:0] HEX5,
  output logic[6:0] HEX6,
  output logic[6:0] HEX7,
  output logic[7:0] leds_green,
  output logic[15:0] leds_red,

  /* PS2 Keyboard */
  input logic ps2_clock,
  input logic ps2_data,

  /* SRAM */
  output logic sram_ce,
  output logic sram_ub,
  output logic sram_lb,
  output logic sram_oe,
  output logic sram_we,
  output logic [19:0] sram_addr,
  /* Mimic the way Verilator will hopefully eventually do it */
  input wire[15:0] sram_data_in,
  output wire[15:0] sram_data_out
);

/* active high */
logic reset;
logic reset_delayed;

initial reset = 1'b0;

always @ (posedge master_clock) begin
  reset <= ~keys[0];
end

logic reset_delayed_in;
logic pll_locked;
assign pll_locked = 1'b1;
shift_register #(.width(128)) delay_reset_gen(.clock(master_clock), .in(reset_delayed_in), .out(reset_delayed));

always_comb begin
  reset_delayed_in = reset | ~pll_locked;
end

logic[15:0] debug_pc;
logic[7:0][3:0] hex_values;
logic[7:0][6:0] HEXES;
assign hex_values = { {4{4'h0}}, debug_pc };
assign { HEX7, HEX6, HEX5, HEX4, HEX3, HEX2, HEX1, HEX0 } = HEXES;
generate
genvar i;
for (i = 0; i < 8; i = i + 1) begin : hex_drivers
  hex_display_driver hex_driver(.value(hex_values[i]), .hex_value(HEXES[i]));
end
endgenerate

/* 240*480*vga_frame_rate Hz (not the technical 21477272.72... Hz) */
/* vga_frame_rate = 25 MHz/(800*525) */
/* vga_clk / nes_clock = 175 / 144 */
//logic master_clock;
/* master_clock / 12 */
logic cpu_clock;
/* master_clock / 4 */
logic ppu_clock;

logic nes_ppu_vga_we;
logic vga_swap_buffers;
logic[9:0] vga_x, vga_y;
logic[9:0] vga_x_next, vga_y_next;
logic[7:0] nes_draw_x, nes_draw_y;
logic[7:0] nes_out_red, nes_out_green, nes_out_blue;
ppu_to_vga ppu_to_vga_inst(
  .main_clk(master_clock),
  .reset(reset_delayed),
  .nes_we(nes_ppu_vga_we),
  .nes_buffer_swap(vga_swap_buffers),
  .vga_clk(1'b0),
  .ppu_clk(ppu_clock),
  .vga_x(vga_x_next), .vga_y(vga_y_next),
  .vga_red(), .vga_green(), .vga_blue(),
  .nes_draw_x(nes_draw_x), .nes_draw_y(nes_draw_y),
  .nes_red(nes_out_red), .nes_green(nes_out_green), .nes_blue(nes_out_blue));

/*logic[5:0] otg_hpi_control;
assign { otg_hpi_reset, otg_hpi_cs, otg_hpi_w, otg_hpi_r, otg_hpi_address } = otg_hpi_control;

logic[31:0] usb_keycodes;

tristate #(16) otg_data_tristate(.output_enable(~otg_hpi_w), .data(otg_data_from_nios), .bus(otg_hpi_data));*/

logic[7:0] ps2_keycode;
logic ps2_pressed;

keyboard ps2_keyboard(.clock(cpu_clock), .ps2_clock(ps2_clock), .ps2_data_port(ps2_data),
  .reset(~reset), .ps2_keycode_out(ps2_keycode), .ps2_pressed(ps2_pressed));

logic[2:0] controller_out;
logic controller_strobe;
assign controller_strobe = controller_out[0];
logic[1:0] controller_oe;
logic[7:0] reg_4016;
logic[7:0] reg_4017;

controller_interface_ps2 controller_interface_inst(
  .clock(cpu_clock),
  .ps2_keycode(ps2_keycode),
  .ps2_pressed(ps2_pressed),
  .strobe(controller_strobe),
  .shift(controller_oe),
  .lower_reg(reg_4016),
  .upper_reg(reg_4017),
  .lower_reg_active(),
  .upper_reg_active(),
  .debug_red_leds(leds_red)
);

/*processor_memory_interface memory_interface_inst(
  .cpu_clock(cpu_clock),
  .sram_turn_clock(sram_cpu_clock),
  .
);*/

logic cpu_irq;
logic cpu_nmi;
logic cpu_read_write;
logic[15:0] cpu_address;
logic[7:0] cpu_data_in;
logic[7:0] cpu_data_out;
/* active low */
logic ppu_chip_select;
/* Technically, not a 6502 as BCD is implemented for the NES */
processor_6502 processor(.master_clock(master_clock), .reset(~reset_delayed),
  .reset_clock(reset), .NMI(cpu_nmi), .interrupt_request(cpu_irq),
  .memory_address(cpu_address), .memory_data_in(cpu_data_in),
  .memory_data_out(cpu_data_out), .read_write(cpu_read_write),
  .controller_out(controller_out), .controller_oe(controller_oe),
  .ppu_chip_select(ppu_chip_select),
  .debug_green_leds(leds_green), .debug_hexes(debug_pc), .cpu_clock(cpu_clock));

logic ppu_read;
logic ppu_write;
logic[13:0] ppu_address;
logic[7:0] ppu_data_in;
logic[7:0] ppu_data_out;
logic[7:0] ppu_cpu_data_out;
nes_ppu ppu (.master_clock(master_clock), .reset(~reset_delayed),
  .reset_clock(reset),
  .cpu_read_write(cpu_read_write),
  .cpu_bus_data_in(cpu_data_out),
  .cpu_bus_data_out(ppu_cpu_data_out),
  .cpu_address_pins(cpu_address[2:0]),
  .cpu_chip_select(ppu_chip_select),
  .cpu_nmi(cpu_nmi),
  .memory_address(ppu_address),
  .memory_data_in(ppu_data_in),
  .memory_data_out(ppu_data_out),
  .read(ppu_read),
  .write(ppu_write),
  .nes_draw_x(nes_draw_x), .nes_draw_y(nes_draw_y),
  .vga_red(nes_out_red), .vga_green(nes_out_green),
  .vga_blue(nes_out_blue), .vga_swap_buffers(vga_swap_buffers),
  .vga_we(nes_ppu_vga_we), .ppu_clock(ppu_clock));

nes_mapper_zero
# (
  .ram_option(2'b10), .prg_bank_count(2'd2), .mirroring(1'b1)
) mapper(.reset(reset_delayed), .dual_clock(master_clock),
  .cpu_read_write(cpu_read_write),
  .cpu_address(cpu_address), .cpu_data_in(cpu_data_in),
  .cpu_data_out(cpu_data_out), .ppu_read(ppu_read), .ppu_write(ppu_write),
  .ppu_address(ppu_address), .ppu_data_in(ppu_data_in),
  .ppu_data_out(ppu_data_out), .IRQ(cpu_irq),
  .sram_address(sram_addr), .sram_data_out(sram_data_out),
  .sram_data_in(sram_data_in), .sram_write_enable(sram_we),
  .sram_read_enable(sram_oe),
  .reg_4016(reg_4016), .reg_4017(reg_4017),
  .controller_oe(controller_oe),
  .ppu_cpu_data_out(ppu_cpu_data_out),
  .ppu_cs(ppu_chip_select));
assign sram_ce = 1'b0;
assign sram_ub = 1'b0;
assign sram_lb = 1'b0;

endmodule
