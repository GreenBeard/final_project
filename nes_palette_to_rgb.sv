module nes_palette_to_rgb(
  input logic ppu_clock,
  input logic rendering_enabled,
  input logic[5:0] nes_color,
  /* 1'b1 for grayscale */
  input logic grayscale,
  /* RGB */
  input logic[2:0] emphasis,
  output logic[7:0] red,
  output logic[7:0] green,
  output logic[7:0] blue,

  input logic[7:0] x,
  input logic[7:0] y,
  output logic[7:0] x_out,
  output logic[7:0] y_out,

  input logic vga_we,
  output logic vga_we_out,
  input logic vga_swap_buffers,
  output logic vga_swap_buffers_out
);


logic[7:0] red_next;
logic[7:0] green_next;
logic[7:0] blue_next;

/* Data values courtesy of http://www.thealmightyguru.com/Games/Hacking/Wiki/index.php/NES_Palette */
/* The 6 bits represent
  3-0 hue
  5-4 value
*/
const logic[7:0] colors[64][3] = '{
  '{ 8'h7C, 8'h7C, 8'h7C },
  '{ 8'h00, 8'h00, 8'hFC },
  '{ 8'h00, 8'h00, 8'hBC },
  '{ 8'h44, 8'h28, 8'hBC },
  '{ 8'h94, 8'h00, 8'h84 },
  '{ 8'hA8, 8'h00, 8'h20 },
  '{ 8'hA8, 8'h10, 8'h00 },
  '{ 8'h88, 8'h14, 8'h00 },
  '{ 8'h50, 8'h30, 8'h00 },
  '{ 8'h00, 8'h78, 8'h00 },
  '{ 8'h00, 8'h68, 8'h00 },
  '{ 8'h00, 8'h58, 8'h00 },
  '{ 8'h00, 8'h40, 8'h58 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'hBC, 8'hBC, 8'hBC },
  '{ 8'h00, 8'h78, 8'hF8 },
  '{ 8'h00, 8'h58, 8'hF8 },
  '{ 8'h68, 8'h44, 8'hFC },
  '{ 8'hD8, 8'h00, 8'hCC },
  '{ 8'hE4, 8'h00, 8'h58 },
  '{ 8'hF8, 8'h38, 8'h00 },
  '{ 8'hE4, 8'h5C, 8'h10 },
  '{ 8'hAC, 8'h7C, 8'h00 },
  '{ 8'h00, 8'hB8, 8'h00 },
  '{ 8'h00, 8'hA8, 8'h00 },
  '{ 8'h00, 8'hA8, 8'h44 },
  '{ 8'h00, 8'h88, 8'h88 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'hF8, 8'hF8, 8'hF8 },
  '{ 8'h3C, 8'hBC, 8'hFC },
  '{ 8'h68, 8'h88, 8'hFC },
  '{ 8'h98, 8'h78, 8'hF8 },
  '{ 8'hF8, 8'h78, 8'hF8 },
  '{ 8'hF8, 8'h58, 8'h98 },
  '{ 8'hF8, 8'h78, 8'h58 },
  '{ 8'hFC, 8'hA0, 8'h44 },
  '{ 8'hF8, 8'hB8, 8'h00 },
  '{ 8'hB8, 8'hF8, 8'h18 },
  '{ 8'h58, 8'hD8, 8'h54 },
  '{ 8'h58, 8'hF8, 8'h98 },
  '{ 8'h00, 8'hE8, 8'hD8 },
  '{ 8'h78, 8'h78, 8'h78 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'hFC, 8'hFC, 8'hFC },
  '{ 8'hA4, 8'hE4, 8'hFC },
  '{ 8'hB8, 8'hB8, 8'hF8 },
  '{ 8'hD8, 8'hB8, 8'hF8 },
  '{ 8'hF8, 8'hB8, 8'hF8 },
  '{ 8'hF8, 8'hA4, 8'hC0 },
  '{ 8'hF0, 8'hD0, 8'hB0 },
  '{ 8'hFC, 8'hE0, 8'hA8 },
  '{ 8'hF8, 8'hD8, 8'h78 },
  '{ 8'hD8, 8'hF8, 8'h78 },
  '{ 8'hB8, 8'hF8, 8'hB8 },
  '{ 8'hB8, 8'hF8, 8'hD8 },
  '{ 8'h00, 8'hFC, 8'hFC },
  '{ 8'hF8, 8'hD8, 8'hF8 },
  '{ 8'h00, 8'h00, 8'h00 },
  '{ 8'h00, 8'h00, 8'h00 }
};

logic[5:0] processed_nes_color;
logic[7:0] mid_red, mid_green, mid_blue;

always_ff @ (posedge ppu_clock) begin
  red <= red_next;
  green <= green_next;
  blue <= blue_next;

  x_out <= x;
  y_out <= y;

  vga_we_out <= vga_we;
  vga_swap_buffers_out <= vga_swap_buffers;
end

always_comb begin

  if (grayscale == 1'b1) begin
    /* Select grayscale hue. See color format in table */
    processed_nes_color = nes_color & 6'h30;
  end else begin
    processed_nes_color = nes_color;
  end

  mid_red = colors[processed_nes_color][0];
  mid_green = colors[processed_nes_color][1];
  mid_blue = colors[processed_nes_color][2];

  if (rendering_enabled) begin
    /* TODO figure out how this actually works */
    if (emphasis[0] || emphasis[1]) begin
     /* Dim blue */
     blue_next = mid_blue & 8'hC0;
    end else begin
      blue_next = mid_blue;
    end
    if (emphasis[1] || emphasis[2]) begin
      /* Dim red */
      red_next = mid_red & 8'hC0;
    end else begin
      red_next = mid_red;
    end
    if (emphasis[2] || emphasis[0]) begin
      /* Dim green */
      green_next = mid_green & 8'hC0;
    end else begin
      green_next = mid_green;
    end
  end else begin
    red_next = 8'h0;
    green_next = 8'h0;
    blue_next = 8'h0;
  end
end

endmodule
