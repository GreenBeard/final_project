module ppu_to_vga(
  input logic main_clk,
  /* active high */
  input logic reset,

  /* this input must originate directly from a register */
  input logic nes_we,
  input logic nes_buffer_swap,
  input logic vga_clk,
  input logic ppu_clk,
  input logic[9:0] vga_x, vga_y,
  input logic[7:0] nes_draw_x, nes_draw_y,
  input logic[7:0] nes_red, nes_green, nes_blue,
  output logic[7:0] vga_red, vga_green, vga_blue
);

/* NES outputs 256 by 240 image, we will scale it to 512 by 480 */
/* VGA displays an output of 640 by 480 visible. */

logic nes_buffer /* verilator public */, nes_buffer_next;

logic write_enable[2];
logic[15:0] addresses[2];
logic[15:0] nes_address;
logic[15:0] vga_address;

logic[7:0] nes_colors[3];
logic[7:0] vga_colors[2][3];

generate
genvar i;
for (i = 0; i < 3; i = i + 1) begin : bram_colors
  bram_color bram_zero(.clock(main_clk),
    .write_enable(write_enable[0]),
    .data_in(nes_colors[i]),
    .data_out(vga_colors[0][i]),
    .address(addresses[0]));
  bram_color bram_one(.clock(main_clk),
    .write_enable(write_enable[1]),
    .data_in(nes_colors[i]),
    .data_out(vga_colors[1][i]),
    .address(addresses[1]));
end
endgenerate


/* For now I ought to use a double buffered output (one written by NES, one
  read by PPU) */

logic vga_display_enabled;
always_ff @ (posedge vga_clk) begin
  if (vga_display_enabled == 1'b1) begin
    vga_red <= vga_colors[~nes_buffer][0];
    vga_green <= vga_colors[~nes_buffer][1];
    vga_blue <= vga_colors[~nes_buffer][2];
  end else begin
    vga_red <= 8'h0;
    vga_green <= 8'h0;
    vga_blue <= 8'h0;
  end
end

logic last_swapped;
always_ff @ (posedge main_clk) begin
  if (reset == 1'b1) begin
    nes_buffer <= 1'b1;
  end else begin
    nes_buffer <= nes_buffer_next;
    last_swapped <= nes_buffer_swap;
  end
end

always_comb begin
  nes_address = { nes_draw_y, nes_draw_x };
  vga_address = { vga_y[8:1], vga_x[8:1] };
  if ((vga_x[9:1] < 9'd256) && (vga_y[9:1] < 9'd224)) begin
    vga_display_enabled = 1'b1;
  end else begin
    vga_display_enabled = 1'b0;
  end
  if (nes_buffer == 1'b0) begin
    addresses[0] = nes_address;
    addresses[1] = vga_address;
  end else begin
    addresses[1] = nes_address;
    addresses[0] = vga_address;
  end
  nes_colors[0] = nes_red;
  nes_colors[1] = nes_green;
  nes_colors[2] = nes_blue;
  write_enable[0] = (nes_we == 1'b1) & (nes_buffer == 1'b0);
  write_enable[1] = (nes_we == 1'b1) & (nes_buffer == 1'b1);
  if (nes_buffer_swap == 1'b1 && last_swapped == 1'b0) begin
    nes_buffer_next = ~nes_buffer;
  end else begin
    nes_buffer_next = nes_buffer;
  end
end

endmodule
