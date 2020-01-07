// Pinout copied from RP 2C02
module nes_ppu (
  /* NES's master clock */
  input logic master_clock,
  /* Input from the CPU's read_write signal (used for interchip
    communication) */
  /* write on low, read on high */
  input logic cpu_read_write,
  input logic[7:0] cpu_bus_data_in,
  output logic[7:0] cpu_bus_data_out,
  /* Used to communicate register usage */
  input logic[2:0] cpu_address_pins,
  input logic cpu_chip_select,
  /* Allows for a secondary PPU, currently unimplemented */
  /* inout wire ppu_extension[3:0], */
  /* CPU's nonmaskable interrupt, active low */
  output logic cpu_nmi /* verilator public */,
  /* Appears to be necessary for some mappers to read the latched bottom
    eight bits of the PPU address. */
  /* output logic address_latch_enable, */

  /* We will not follow the real pinout for the RAM access */
  output logic[13:0] memory_address,
  input logic[7:0] memory_data_in,
  output logic[7:0] memory_data_out,

  /* Read, and write are active low */
  output logic read,
  output logic write,
  /* Active low */
  input logic reset,
  /* active high */
  input logic reset_clock,
  /* On the real NES there is a single video out for composite, we are using
    VGA instead of composite */
  /* UNUSED output logic video_out */
  /* The following VGA signals aren't on the real NES. They utilize the NES's
    VIRTUAL screen size of 341 by 262 (only 256 by 240 are actually rendered of
    which only 256 by 224 are considered "safe", and used for nonglitchy
    rendering by most games). Technically there is one pixel fewer every other
    frame, but it doesn't matter and later versions of the NES PPU don't even
    do this. */
  output logic[7:0] nes_draw_x,
  output logic[7:0] nes_draw_y,
  output logic[7:0] vga_red, vga_green, vga_blue,
  output logic ppu_clock,
  output logic vga_swap_buffers,
  output logic vga_we
);

const logic[2:0] nametable_fetch = 3'b000;
const logic[2:0] attribute_table_fetch = 3'b001;
const logic[2:0] pattern_table_low_fetch = 3'b010;
const logic[2:0] pattern_table_high_fetch = 3'b011;
const logic[2:0] no_fetch = 3'b100;
/* Pretty much an enum */
logic[2:0] active_fetch_type /* verilator isolate_assignments */;

enum logic[2:0] {
  fetch_group_sprites,
  fetch_group_backgrounds,
  fetch_group_backgrounds_end,
  fetch_group_none
} fetch_group_type /* verilator isolate_assignments */;

enum logic[2:0] {
  clear_sprite_state,
  eval_sprite_state,
  nothing_sprite_state
} scanline_sprite_state /* verilator isolate_assignments */;

clock_divider #(.divisor(4)) master_to_ppu(.reset(reset_clock), .in_clk(master_clock), .out_clk(ppu_clock));

/* [0, 261] used */
logic[8:0] ppu_scanline, ppu_scanline_next;
/* [0, 340] used */
logic[8:0] ppu_column, ppu_column_next;

/* Top left VRAM position of view box */
logic[1:0] nametable_corner_table, nametable_corner_table_next;
logic[4:0] reg_corner_coarse_x, reg_corner_coarse_x_next;
logic[4:0] reg_corner_coarse_y, reg_corner_coarse_y_next;
/* Used for 8 subpixel positions */
logic[2:0] reg_corner_fine_x, reg_corner_fine_x_next;
logic[2:0] reg_corner_fine_y, reg_corner_fine_y_next;

/* The current VRAM position of view box */
logic[1:0] nametable_table, nametable_table_next;
logic[1:0] nametable_table_next_one, nametable_table_next_two;
logic[4:0] reg_coarse_x, reg_coarse_x_next;
logic[4:0] reg_coarse_x_next_one, reg_coarse_x_next_two;
logic[4:0] reg_coarse_y, reg_coarse_y_next;
logic[4:0] reg_coarse_y_next_one, reg_coarse_y_next_two;
/* Used for 8 subpixel positions */
/* Only one copy of fine x scroll as it doesn't change while rendering */
logic[2:0] reg_fine_y, reg_fine_y_next;
logic[2:0] reg_fine_y_next_one, reg_fine_y_next_two;

logic vga_swap_buffers_next;

/* START Control registers/values */

logic tall_sprites;
logic generate_nmi;

logic[2:0] emphasize_rgb;
/* High for true */
logic render_sprites;
logic render_background;

logic vblank_active /* verilator public */, vblank_active_next;
logic vblank_clear_tmp, vblank_clear_tmp_next;
logic sprite_zero_hit, sprite_zero_hit_next;
logic sprite_zero_hit_possible;
logic sprite_overflow;
/* TODO actually calculate sprite overflow */
assign sprite_overflow = 1'b0;

logic pattern_table_table;

logic cpu_nmi_next;

/* One is for rendering periods
  Two is for vblanks, and other nonrendering periods */
logic[7:0] oam_address /* verilator isolate_assignments */;
logic oam_write;
/* Used to store the sprite data for rendering. Written by the CPU. Doesn't
  exist in our SRAM. */
logic[3:0][7:0] oam_data_out;
logic[7:0] oam_data_in;
oam_memory #(.size(64)) oam_bram (.clock(ppu_clock), .write_enable(oam_write),
  .address(oam_address), .data_in(oam_data_in), .data_out(oam_data_out));

/* stored in registers */
logic[5:0] default_color, default_color_next;
/* 8 palettes (4 sprite, 4 background) each with 4 colors. Each color is
  represented by 6 bits. Only 3 colors are used as color 0 is the default_color
  for every palette. TODO support background palette color hack (requires 4
  colors?). */
logic[7:0][2:0][5:0] palettes, palettes_next;

/* Active high unless noted otherwise */

/* Used to keep track of first, or second write to control registers */
logic reg_write_toggle, reg_write_toggle_next;

/* Eight memory-mapped registers exposed to the CPU */

/* PPU Control Register ($2000) - write */
/* The low 2 bits of the register are in nametable_table */
logic[5:0] ppu_ctrl, ppu_ctrl_next;
assign tall_sprites = ppu_ctrl[3];
assign generate_nmi = ppu_ctrl[5];

/* PPU Mask Register ($2001) - write */
/*
  0 - grayscale
  1, 2 - show background, sprites respectively for first 8 pixels of scanlines
  3, 4 - show background, sprites respectively
  5, 6, 7 - emphasize red, green, and/or blue respectively
 */
logic[7:0] ppu_mask, ppu_mask_next;
always_comb begin
  for (int i = 0; i < 3; i = i + 1) begin
    emphasize_rgb[i] = ppu_mask[7 - i];
  end
end

/* PPU Status Register ($2002) - read */
logic[7:0] ppu_status;
assign ppu_status = { vblank_active, sprite_zero_hit, sprite_overflow, 5'b0 };

/* OAM Address Port ($2003) - write */
logic[7:0] oam_addr, oam_addr_next;

/* OAM Data Port ($2004) - read/write */
//logic[7:0] oam_data;

/* PPU Scrolling Position Register ($2005) - write Twice */
//logic[7:0] ppu_scroll;

/* PPU Address Register ($2006) - write Twice */
logic[14:0] ppu_addr;
assign ppu_addr = { reg_fine_y, nametable_table, reg_coarse_y, reg_coarse_x };
logic[5:0] ppu_addr_incr;
assign ppu_addr_incr = ppu_ctrl[0] ? 6'd32 : 6'd1;

/* PPU Data Register ($2007) - read/write */
logic[7:0] ppu_data, ppu_data_next;
logic[7:0] ppu_saved_data;

logic[7:0] oam_address_one /* verilator isolate_assignments */,
  oam_address_two /* verilator isolate_assignments */;
logic[13:0] memory_address_one, memory_address_two;
logic read_one, read_two;
logic write_one, write_two;
logic oam_write_two;
logic memory_select;
always_comb begin
  oam_write = oam_write_two;
  if (memory_select == 1'b0) begin
    memory_address = memory_address_one;
    read = read_one;
    write = write_one;
    oam_address = oam_address_one;

    nametable_table_next = nametable_table_next_one;
    reg_coarse_x_next = reg_coarse_x_next_one;
    reg_coarse_y_next = reg_coarse_y_next_one;
    reg_fine_y_next = reg_fine_y_next_one;
  end else begin
    memory_address = memory_address_two;
    read = read_two;
    write = write_two;
    oam_address = oam_address_two;

    nametable_table_next = nametable_table_next_two;
    reg_coarse_x_next = reg_coarse_x_next_two;
    reg_coarse_y_next = reg_coarse_y_next_two;
    reg_fine_y_next = reg_fine_y_next_two;
  end
end

logic ppu_wrote_last, ppu_wrote_last_next;
always_comb begin
  ppu_ctrl_next = ppu_ctrl;
  ppu_mask_next = ppu_mask;
  oam_addr_next = oam_addr;
  ppu_data_next = ppu_data;

  nametable_corner_table_next = nametable_corner_table;
  reg_corner_coarse_x_next = reg_corner_coarse_x;
  reg_corner_coarse_y_next = reg_corner_coarse_y;
  reg_corner_fine_x_next = reg_corner_fine_x;
  reg_corner_fine_y_next = reg_corner_fine_y;

  nametable_table_next_two = nametable_table;
  reg_coarse_x_next_two = reg_coarse_x;
  reg_coarse_y_next_two = reg_coarse_y;
  reg_fine_y_next_two = reg_fine_y;

  reg_write_toggle_next = reg_write_toggle;

  cpu_bus_data_out = 8'hx;

  memory_data_out = 8'hx;
  memory_address_two = 14'hx;
  read_two = 1'b1;
  write_two = 1'b1;

  oam_address_two = 8'hx;
  oam_data_in = 8'hx;
  oam_write_two = 1'b0;

  default_color_next = default_color;
  palettes_next = palettes;

  ppu_wrote_last_next = 1'b0;
  vblank_active_next = vblank_active;
  vblank_clear_tmp_next = 1'b0;
  if (cpu_chip_select == 1'b1 && vblank_clear_tmp == 1'b1) begin
    vblank_active_next = 1'b0;
  end
  if (cpu_chip_select == 1'b0) begin
    ppu_wrote_last_next = 1'b1;
  end
  if (cpu_chip_select == 1'b0) begin
    if (cpu_read_write == 1'b0) begin
      if (ppu_wrote_last == 1'b0) begin
        case (cpu_address_pins)
          3'h0: begin
            ppu_ctrl_next = cpu_bus_data_in[7:2];
            nametable_corner_table_next = cpu_bus_data_in[1:0];
          end
          3'h1: begin
            ppu_mask_next = cpu_bus_data_in;
          end
          3'h2: begin
            /* ignore */
            /* TODO Check if writing clears vblank (need a real NES) */
          end
          3'h3: begin
            oam_addr_next = cpu_bus_data_in;
          end
          3'h4: begin
            oam_write_two = 1'b1;
            oam_data_in = cpu_bus_data_in;
            oam_address_two = oam_addr;
            oam_addr_next = oam_addr + 8'h1;
          end
          3'h5: begin
            if (reg_write_toggle == 1'b0) begin
              reg_corner_fine_x_next = { cpu_bus_data_in[2:0] };
              reg_corner_coarse_x_next = { cpu_bus_data_in[7:3] };
            end else begin
              reg_corner_fine_y_next = { cpu_bus_data_in[2:0] };
              reg_corner_coarse_y_next = { cpu_bus_data_in[7:3] };
            end
            reg_write_toggle_next = ~reg_write_toggle;
          end
          3'h6: begin
            if (reg_write_toggle == 1'b0) begin
              nametable_corner_table_next = cpu_bus_data_in[3:2];
              reg_corner_fine_y_next = { 1'b0, cpu_bus_data_in[5:4] };
              reg_corner_coarse_y_next = { cpu_bus_data_in[1:0],
                reg_corner_coarse_y[2:0] };
            end else begin
              reg_corner_coarse_y_next = { reg_corner_coarse_y[4:3],
                cpu_bus_data_in[7:5] };
              reg_corner_coarse_x_next = cpu_bus_data_in[4:0];
              { reg_fine_y_next_two, nametable_table_next_two, reg_coarse_y_next_two, reg_coarse_x_next_two } =
              {
                reg_corner_fine_y, nametable_corner_table, reg_corner_coarse_y_next, reg_corner_coarse_x_next
              };
            end
            reg_write_toggle_next = ~reg_write_toggle;
          end
          3'h7: begin
            write_two = 1'b0;
            memory_data_out = cpu_bus_data_in;
            memory_address_two = ppu_addr[13:0];
            /* verilator lint_off WIDTH */
            { reg_fine_y_next_two, nametable_table_next_two,
              reg_coarse_y_next_two, reg_coarse_x_next_two }
              = ppu_addr + ppu_addr_incr;
            /* verilator lint_on WIDTH */

            /* Write to palettes */
            if (ppu_addr[13:5] == 9'h1F8) begin
              write_two = 1'b1;
              if (ppu_addr[4:0] == 5'h0 || ppu_addr[4:0] == 5'h10) begin
                default_color_next = cpu_bus_data_in[5:0];
              end
              if (ppu_addr[1:0] != 2'b0) begin
                palettes_next[ppu_addr[5:2]][ppu_addr[1:0] - 1]
                  = cpu_bus_data_in[5:0];
              end
            end
          end
        endcase
      end
    end else begin
      case (cpu_address_pins)
        3'h0: begin
          /* Do nothing */
        end
        3'h1: begin
          /* Do nothing */
        end
        3'h2: begin
          cpu_bus_data_out = ppu_status;
          reg_write_toggle_next = 1'b0;
          vblank_clear_tmp_next = 1'b1;
        end
        3'h3: begin
          /* Do nothing */
        end
        3'h4: begin
          cpu_bus_data_out = oam_data_out[oam_addr[1:0]];
          oam_address_two = oam_addr;
        end
        3'h5: begin
          /* Do nothing */
        end
        3'h6: begin
          /* Do nothing */
        end
        3'h7: begin
          read_two = 1'b0;
          cpu_bus_data_out = ppu_saved_data;
          if (ppu_wrote_last == 1'b0) begin
            memory_address_two = ppu_addr[13:0];
            ppu_data_next = memory_data_in;
            /* verilator lint_off WIDTH */
            { reg_fine_y_next_two, nametable_table_next_two,
              reg_coarse_y_next_two, reg_coarse_x_next_two }
              = ppu_addr + ppu_addr_incr;
            /* verilator lint_on WIDTH */
          end
        end
      endcase
    end
  end
  if (ppu_scanline == 9'd241 && ppu_column == 9'd0) begin
    vblank_active_next = 1'b1;
  end
  if (ppu_scanline == 9'd261 && ppu_column == 9'd0) begin
    vblank_active_next = 1'b0;
  end
end

always_ff @ (posedge ppu_clock) begin
  if (reset == 1'b1) begin
    ppu_wrote_last <= ppu_wrote_last_next;
    ppu_ctrl <= ppu_ctrl_next;
    ppu_mask <= ppu_mask_next;
    oam_addr <= oam_addr_next;
    ppu_data <= ppu_data_next;
    if (ppu_wrote_last == 1'b0) begin
      ppu_saved_data <= ppu_data;
    end

    nametable_corner_table <= nametable_corner_table_next;
    reg_corner_coarse_x <= reg_corner_coarse_x_next;
    reg_corner_coarse_y <= reg_corner_coarse_y_next;
    reg_corner_fine_x <= reg_corner_fine_x_next;
    reg_corner_fine_y <= reg_corner_fine_y_next;

    nametable_table <= nametable_table_next;
    reg_coarse_x <= reg_coarse_x_next;
    reg_coarse_y <= reg_coarse_y_next;
    reg_fine_y <= reg_fine_y_next;

    reg_write_toggle <= reg_write_toggle_next;
  end else begin
    ppu_wrote_last <= 1'b0;
    ppu_ctrl <= 6'h0;
    nametable_corner_table <= 2'h0;
    ppu_mask <= 8'h0;
    oam_addr <= 8'h0;
    ppu_data <= 8'h0;

    reg_corner_coarse_x <= 5'h0;
    reg_corner_coarse_y <= 5'h0;
    reg_corner_fine_x <= 3'h0;
    reg_corner_fine_y <= 3'h0;

    nametable_table <= 2'h0;
    reg_coarse_x <= 5'h0;
    reg_coarse_y <= 5'h0;
    reg_fine_y <= 3'h0;

    reg_write_toggle <= 1'b0;
  end
end

/* END Control registers/values */

logic[5:0] nes_color;

logic vga_we_tmp;
logic vga_rendering_enabled;
nes_palette_to_rgb converter(.ppu_clock(ppu_clock),
  .rendering_enabled(vga_rendering_enabled),
  .nes_color(nes_color), .grayscale(ppu_mask[0]), .emphasis(emphasize_rgb),
  .red(vga_red), .green(vga_green), .blue(vga_blue),
  .x(ppu_column[7:0]), .y(ppu_scanline[7:0]),
  .x_out(nes_draw_x), .y_out(nes_draw_y),
  .vga_we(vga_we_tmp), .vga_we_out(vga_we),
  .vga_swap_buffers(vga_swap_buffers_next),
  .vga_swap_buffers_out(vga_swap_buffers));
always_comb begin
  if (ppu_column < 9'd256 && ppu_scanline < 9'd240) begin
    vga_we_tmp = 1'b1;
  end else begin
    vga_we_tmp = 1'b0;
  end
end
/* DEBUG CODE START */
/*assign vga_red = nes_draw_x[7:0];
assign vga_green = nes_draw_y[7:0];
assign vga_blue = 8'h0;*/
/* DEBUG CODE END */

/* High for true */
logic rendering_disabled;
assign rendering_disabled = ppu_mask[4] == 1'b0 && ppu_mask[3] == 1'b0;

/* Three of each register are needed as two are for the currently available
  pixels to read (two, not one, are needed to handle reg_fine_x). The last is
  the currently begin fetched background tile. This explains the two prefetched
  tiles at the end of each scanline. Represents shifting the *whole* of each of
  the three registers. */
logic bg_shift_nametable;
logic bg_shift_palettes_0, bg_shift_palettes_1;

/* Selects which of the 256 tiles to use */
logic[7:0] nametable_byte[3];
logic[7:0] nametable_byte_next;
/* Selects which of the 4 color sets to use. Each color set itself contains
  4 colors. They can be found at 0x3F00 to 0x3F1F.
  All tiles (background, and sprites) share a background color (palette index
  0). This color is at 0x3F00. Each palette is then 3 bytes at 0x3F01, 0x3F02,
  0x3F03; 0x3F05, 0x3F06, 0x2F07; etc. The first 4 color sets are for the
  background, while the second 4 color sets are for the sprites (0x3F00 to
  0x3F0F, and 0x3F10 to 0x3F1F respectively).
  The attribute_byte holds 4 selections of color sets (each being a 2 bit
  selection) for a total of 8 bits. This byte cooresponds to 4 8x8 tile
  regions. */
logic[1:0] bg_palette[3];
logic[1:0] bg_palette_next;

/* A.k.a. sprite shape, and color selection from attribute table palette. The
  pattern table is used for both the foreground, and background sprites. The
  active background sprite is specified by the nametable_byte.
  The matching bits (e.g. pattern_table_low_byte[0], and
  pattern_table_high_byte[0]) are used together to create a 2 bit (or 4 option)
  color set selection for each pixel from the active color set. (A.k.a. we pick
  one of the four colors from the already selected color set which is one of
  four possible sets.) */
logic[1:0] bg_pattern_table_cur;
/* reg 1, 2 */
logic[7:0] bg_pattern_table_load_val[6];
logic[7:0] bg_pattern_table_val[6];
logic bg_pattern_table_load[6];
/* reg 0, 1 (same value) */
logic bg_pattern_table_shift;
/* reg 1 -> 0 */
logic bg_pattern_table_shift_in[2];

generate
genvar i;
for (i = 0; i < 2; i = i + 1) begin : bg_pattern_table_regs
  ppu_shift_reg pattern_table_reg_0(
    .clock(ppu_clock),
    .shift(bg_pattern_table_shift),
    .load(bg_pattern_table_load[i]),
    .data_in(bg_pattern_table_load_val[i]),
    .shift_in(bg_pattern_table_shift_in[i]),
    .data_out(bg_pattern_table_val[i]),
    .shift_out(bg_pattern_table_cur[i])
  );
  ppu_shift_reg pattern_table_reg_1(
    .clock(ppu_clock),
    .shift(bg_pattern_table_shift),
    .load(bg_pattern_table_load[2 + i]),
    .data_in(bg_pattern_table_load_val[2 + i]),
    .shift_in(1'b0),
    .data_out(bg_pattern_table_val[2 + i]),
    .shift_out(bg_pattern_table_shift_in[i])
  );
  ppu_shift_reg pattern_table_reg_2(
    .clock(ppu_clock),
    .shift(1'b0),
    .load(bg_pattern_table_load[4 + i]),
    .data_in(bg_pattern_table_load_val[4 + i]),
    .shift_in(),
    .data_out(bg_pattern_table_val[4 + i]),
    .shift_out()
  );
end
endgenerate

generate
genvar shift_i;
for (shift_i = 0; shift_i < 2; shift_i = shift_i + 1) begin : gen_bg_load_vals
  always_comb begin
    { bg_pattern_table_load_val[0 + shift_i], bg_pattern_table_load_val[2 + shift_i] }
      = { bg_pattern_table_val[0 + shift_i][6:0], bg_pattern_table_val[2 + shift_i][7:0], 1'b0 }
      | ({ 8'h0, bg_pattern_table_val[4 + shift_i] } << (4'b1 + { 1'b0, reg_corner_fine_x}));
  end
end
endgenerate

/* 1'b1 if the current scanline contains sprite zero */
logic sprite_zero_active, sprite_zero_active_next;
/* All of the following are used for active scanline to render sprites. */
logic[7:0] sprite_counter_x[2][8];
logic[7:0] sprite_counter_x_full_next[8];
logic[7:0] sprite_counter_x_next;
/* Both the low [0], and high [1] pattern table bytes */

/* The index within the sprite */
logic[7:0][2:0] sprite_index_y[2];
logic[2:0] sprite_index_y_next;

logic[7:0] sprite_index_y_calc;

/* Used to select which of the sprite color palettes to use. */
logic[7:0][1:0] sprite_pattern_table_cur;
logic[7:0] sprite_pattern_table_load_val;
logic[7:0][1:0] sprite_pattern_table_load;
logic[7:0] sprite_pattern_table_shift;

/* Shift the *whole* register over */
logic sprite_pattern_table_shift_whole;
logic[7:0] sprite_pattern_table_data_1[8][2];

generate
genvar j;
genvar k;
for (j = 0; j < 8; j = j + 1) begin : sprite_pattern_table_regs
  for (k = 0; k < 2; k = k + 1) begin : low_high
    /* TODO aren't this never overlapping in usage meaning they can be combined
     instead of loading reg_1 then moving it to reg_0? */
    ppu_shift_reg pattern_table_reg_0(
      .clock(ppu_clock),
      .shift(sprite_pattern_table_shift[j]),
      .load(sprite_pattern_table_shift_whole),
      .data_in(sprite_pattern_table_data_1[j][k]),
      .shift_in(1'b0),
      .data_out(),
      .shift_out(sprite_pattern_table_cur[j][k])
    );
    ppu_shift_reg pattern_table_reg_1(
      .clock(ppu_clock),
      .shift(1'b0),
      .load(sprite_pattern_table_load[j][k]),
      .data_in(sprite_pattern_table_load_val),
      .shift_in(),
      .data_out(sprite_pattern_table_data_1[j][k]),
      .shift_out()
    );
  end
end
endgenerate

logic sprite_eval_data_we;
logic[2:0] sprite_data_index;

logic sprite_enabled[8];
logic sprite_enabled_next;

/* Used to select nametable of sprite */
logic[7:0][7:0] sprite_nametable[2];
logic[7:0] sprite_nametable_next;

logic[7:0][1:0] sprite_palette[2];
logic[1:0] sprite_palette_next;
/* Used to select whether to show background, or sprite by default:
  1'b0: sprite
  1'b1: background */
logic[7:0] sprite_priority[2];
logic sprite_priority_next;

/* bit 0 - flip horizontally
   bit 1 - flip vertically */
logic[7:0][1:0] sprite_flips[2];
logic[1:0] sprite_flips_next;

logic reverse /* verilator isolate_assignments */;
logic[7:0] reverser_input /* verilator isolate_assignments */;
logic[7:0] reverser_tmp;
logic[7:0] reverser_output /* verilator isolate_assignments */;

always_comb begin
  for (int reverse_int = 0; reverse_int < 8; reverse_int = reverse_int + 1) begin
    reverser_tmp[reverse_int] = reverser_input[7-reverse_int];
  end
  if (reverse == 1'b1) begin
    reverser_output = reverser_tmp;
  end else begin
    reverser_output = reverser_input;
  end
end

logic background_selected;

/* Before lookup in correct color table */
logic[1:0] background_color;
logic[1:0] background_palette;

logic[1:0] active_sprite_color;
logic[1:0] active_sprite_palette;
logic active_sprite_priority;

logic[1:0] selected_color;
logic[2:0] selected_palette;

logic[5:0] eval_active_sprite /* verilator isolate_assignments */;
logic eval_empty_sprite_complete, eval_empty_sprite_complete_next;
logic[2:0] eval_empty_sprite, eval_empty_sprite_next;

/* Only values [0,29] are valid for the row */
logic[4:0] nametable_entry_row;
logic[4:0] nametable_entry_column;

logic pattern_table_bit_plane;
logic[7:0] pattern_table_entry;
logic[2:0] pattern_table_tile_row;

always_ff @ (posedge ppu_clock) begin
  if (reset == 1'b1) begin
    ppu_scanline <= ppu_scanline_next;
    ppu_column <= ppu_column_next;
    cpu_nmi <= cpu_nmi_next;
    vblank_active <= vblank_active_next;
    vblank_clear_tmp <= vblank_clear_tmp_next;
    sprite_zero_hit <= sprite_zero_hit_next;
    sprite_zero_active <= sprite_zero_active_next;

    if (bg_shift_palettes_0) begin
      bg_palette[0] <= bg_palette[1];
    end
    if (bg_shift_palettes_1) begin
      bg_palette[1] <= bg_palette[2];
    end
    if (bg_shift_nametable) begin
      nametable_byte[0] <= nametable_byte[1];
      nametable_byte[1] <= nametable_byte[2];
    end
    nametable_byte[2] <= nametable_byte_next;
    bg_palette[2] <= bg_palette_next;

    palettes <= palettes_next;
    default_color <= default_color_next;

    eval_empty_sprite <= eval_empty_sprite_next;
    eval_empty_sprite_complete <= eval_empty_sprite_complete_next;

    if (sprite_eval_data_we == 1'b1) begin
      sprite_counter_x[1][sprite_data_index] <= sprite_counter_x_next;
      sprite_index_y[1][sprite_data_index] <= sprite_index_y_next;
      sprite_enabled[sprite_data_index] <= sprite_enabled_next;
      sprite_nametable[1][sprite_data_index] <= sprite_nametable_next;
      sprite_palette[1][sprite_data_index] <= sprite_palette_next;
      sprite_priority[1][sprite_data_index] <= sprite_priority_next;
      sprite_flips[1][sprite_data_index] <= sprite_flips_next;
    end

    if (sprite_pattern_table_shift_whole == 1'b1) begin
      sprite_counter_x[0] <= sprite_counter_x[1];
      sprite_index_y[0] <= sprite_index_y[1];
      sprite_nametable[0] <= sprite_nametable[1];
      sprite_palette[0] <= sprite_palette[1];
      sprite_priority[0] <= sprite_priority[1];
      sprite_flips[0] <= sprite_flips[1];
    end else begin
      sprite_counter_x[0] <= sprite_counter_x_full_next;
    end
  end else begin
    ppu_scanline <= 9'b0;
    ppu_column <= 9'b0;
    cpu_nmi <= 1'b1;
    vblank_active <= 1'b0;
    vblank_clear_tmp <= 1'b0;
    sprite_zero_hit <= 1'b0;
    sprite_zero_active <= 1'b0;

    bg_palette[0] <= 2'hx;
    bg_palette[1] <= 2'hx;
    bg_palette[2] <= 2'bx;

    nametable_byte[0] <= 8'hx;
    nametable_byte[1] <= 8'hx;
    nametable_byte[2] <= 8'bx;

    palettes <= {24{6'h0}};
    default_color <= 6'h0;

    eval_empty_sprite <= 3'b0;
    eval_empty_sprite_complete <= 1'b0;
  end
end

always_comb begin
  /* FSM logic start */

  vga_swap_buffers_next = 1'b0;
  if (generate_nmi == 1'b1 && ppu_column == 9'd0
      && ppu_scanline == 9'd241) begin
    cpu_nmi_next = 1'b0;
  end else begin
    cpu_nmi_next = 1'b1;
  end
  sprite_zero_hit_next = sprite_zero_hit;
  if (ppu_scanline == 9'd261 && ppu_column == 9'd0) begin
    sprite_zero_hit_next = 1'b0;
  end
  if (ppu_column == 9'd340) begin
    ppu_column_next = 9'd0;
    if (ppu_scanline == 9'd261) begin
      ppu_scanline_next = 9'd0;
      vga_swap_buffers_next = 1'b1;
    end else begin
      ppu_scanline_next = ppu_scanline + 9'b1;
    end
  end else begin
    ppu_column_next = ppu_column + 9'b1;
    ppu_scanline_next = ppu_scanline;
  end

  active_fetch_type = no_fetch;
  fetch_group_type = fetch_group_none;
  bg_shift_nametable = 1'b0;
  bg_shift_palettes_0 = 1'b0;
  bg_shift_palettes_1 = 1'b0;
  sprite_pattern_table_shift_whole = 1'b0;

  nametable_table_next_one = nametable_table;
  reg_coarse_x_next_one = reg_coarse_x;
  reg_coarse_y_next_one = reg_coarse_y;
  reg_fine_y_next_one = reg_fine_y;
  /* Todo be brave and set to X */
  eval_empty_sprite_next = 3'h0;
  eval_empty_sprite_complete_next = eval_empty_sprite_complete;
  if (ppu_scanline < 9'd240 || ppu_scanline == 9'd261) begin
    if (ppu_column == 9'd63) begin
      eval_empty_sprite_next = 3'b0;
      eval_empty_sprite_complete_next = 1'b0;
    end
    if (ppu_column < 9'd64) begin
      scanline_sprite_state = clear_sprite_state;
    end else if (ppu_column < 9'd256) begin
      scanline_sprite_state = eval_sprite_state;
    end else begin
      scanline_sprite_state = nothing_sprite_state;
    end

    /* Do the 4 types of fetches in order (each 2 cycles long). The first 256
     cycles of fetches (or 128 fetches) are for the background sprite to be
     rendered. The next 64 cycles of fetchs (or 32 fetches) are for the sprite
     lookups (only the two pattern fetches are actually used). The last 20
     cycles (or 10 fetches) are used to fetch the 2 first background tiles for
     the next scanline (the last two fetches of the 10 are useless).
     TODO mimic real hardware's last two fetches. */
    active_fetch_type = { 1'b0, ppu_column[2:1] };

    if (ppu_column < 9'd256) begin
      fetch_group_type = fetch_group_backgrounds;
    end else if (ppu_column < 9'd320) begin
      fetch_group_type = fetch_group_sprites;
    end else if (ppu_column < 9'd336) begin
      fetch_group_type = fetch_group_backgrounds_end;
    end else begin
      fetch_group_type = fetch_group_none;
    end

    if (fetch_group_type == fetch_group_backgrounds
        || fetch_group_type == fetch_group_backgrounds_end) begin
      if (ppu_column[2:0] == 3'h7) begin
        /* Increment horizontally */
        { nametable_table_next_one[0], reg_coarse_x_next_one } =
          { nametable_table[0], reg_coarse_x } + 6'b1;
      end
      if (ppu_column[2:0] == 3'h0) begin
        bg_shift_nametable = 1'b1;
      end
      if (ppu_column[2:0] == 3'h7 - reg_corner_fine_x) begin
        bg_shift_palettes_0 = 1'b1;
      end
      if (ppu_column[2:0] == 3'h7) begin
        bg_shift_palettes_1 = 1'b1;
      end
    end
    if (ppu_column == 9'd255) begin
      /* Increment vertically */
      if ({ reg_coarse_y, reg_fine_y } < 8'd239) begin
        { nametable_table_next_one[1], reg_coarse_y_next_one,
          reg_fine_y_next_one } =
          { nametable_table[1], reg_coarse_y, reg_fine_y } + 9'b1;
      end else begin
        { nametable_table_next_one[1], reg_coarse_y_next_one,
          reg_fine_y_next_one } =
          { ~nametable_table[1], 5'h0, 3'h0 };
      end
    end
    if (ppu_column == 9'd320) begin
      sprite_pattern_table_shift_whole = 1'b1;
    end
    if (ppu_column == 9'd256) begin
      /* Reset horizontally */
      { nametable_table_next_one[0], reg_coarse_x_next_one } =
        { nametable_corner_table[0], reg_corner_coarse_x };
    end
    if (ppu_scanline == 9'd261 && ppu_column == 9'd280) begin
      /* TODO mimic exact hardware */
      /* Reset vertically */
      { nametable_table_next_one[1], reg_coarse_y_next_one,
        reg_fine_y_next_one } =
        { nametable_corner_table[1], reg_corner_coarse_y, reg_corner_fine_y };
    end
  end else begin
    scanline_sprite_state = nothing_sprite_state;
  end

  /* FSM logic end */

  vga_rendering_enabled = rendering_disabled == 1'b0 && ppu_scanline < 9'd240
    && ppu_column < 9'd256;
  read_one = 1'b0;
  write_one = 1'b1;
  if (rendering_disabled == 1'b0 && (ppu_scanline < 9'd240
      || ppu_scanline == 9'd261)) begin
    memory_select = 1'b0;
  end else begin
    memory_select = 1'b1;
  end

  if (ppu_column < 9'h8) begin
    render_sprites = ppu_mask[2] & ppu_mask[4];
    render_background = ppu_mask[1] & ppu_mask[3];
  end else begin
    render_sprites = ppu_mask[4];
    render_background = ppu_mask[3];
  end

  active_sprite_palette = 2'bx;
  active_sprite_color = 2'b0;
  active_sprite_priority = 1'bx;
  sprite_pattern_table_shift = 8'h0;
  sprite_zero_hit_possible = 1'b0;
  if (fetch_group_type == fetch_group_backgrounds) begin
    for (int i = 7; i >= 0; i = i - 1) begin
      if (sprite_counter_x[0][i] == 8'h0) begin
        sprite_pattern_table_shift[i] = 1'b1;
        if (sprite_pattern_table_cur[i] != 2'b0) begin
          active_sprite_palette = sprite_palette[0][i];
          active_sprite_color = sprite_pattern_table_cur[i];
          active_sprite_priority = sprite_priority[0][i];
          if (i == 0 && sprite_zero_active == 1'b1) begin
            sprite_zero_hit_possible = 1'b1;
          end
        end
      end
    end
  end

  background_palette = bg_palette[0];
  background_color = bg_pattern_table_cur;

  if (render_sprites == 1'b0) begin
    background_selected = 1'b1;
  end else if (render_background == 1'b0) begin
    background_selected = 1'b0;
  end else begin
    if (active_sprite_color == 2'b0 && background_color == 2'b0) begin
      background_selected = 1'bx;
    end if (active_sprite_color == 2'b0) begin
      background_selected = 1'b1;
    end else if (background_color == 2'b0) begin
      background_selected = 1'b0;
    end else begin
      if (sprite_zero_hit_possible) begin
        sprite_zero_hit_next = 1'b1;
      end
      background_selected = active_sprite_priority;
    end
  end

  if (background_selected == 1'b1) begin
    selected_color = background_color;
    selected_palette = 3'b000 | { 1'b0, background_palette };
  end else begin
    selected_color = active_sprite_color;
    selected_palette = 3'b100 | { 1'b0, active_sprite_palette };
  end

  if (selected_color == 2'b0
      || render_sprites == 1'b0 && render_background == 1'b0) begin
    nes_color = default_color;
  end else begin
    nes_color = palettes[selected_palette][selected_color - 2'b1];
  end

  /* Sprite scanline section start */
  sprite_eval_data_we = 1'b0;
  sprite_data_index = 3'hx;
  sprite_enabled_next = 1'bx;
  sprite_nametable_next = 8'hx;
  sprite_palette_next = 2'hx;
  sprite_priority_next = 1'hx;
  sprite_flips_next = 2'hx;
  sprite_counter_x_next = 8'hx;
  sprite_index_y_next = 3'hx;
  sprite_pattern_table_load_val = 8'hx;
  sprite_pattern_table_load = 16'h0;

  sprite_zero_active_next = sprite_zero_active;
  if (scanline_sprite_state == clear_sprite_state) begin
    /* Only runs the first 8 cycles */
    sprite_eval_data_we = 1'b1;
    sprite_data_index = ppu_column[2:0];
    sprite_enabled_next = 1'b0;
    sprite_nametable_next = 8'h0;
    sprite_palette_next = 2'h0;
    sprite_priority_next = 1'h0;
    sprite_flips_next = 2'h0;
    /* TODO be brave and delete this */
    sprite_counter_x_next = 8'h0;
    sprite_pattern_table_load_val = 8'h0;
    sprite_pattern_table_load = 16'hFFFF;

    sprite_zero_active_next = 1'b0;
  end

  eval_active_sprite = ppu_column[5:0];
  oam_address_one = 8'hx;
  sprite_index_y_calc = 8'hx;
  if (scanline_sprite_state == eval_sprite_state) begin
    oam_address_one = { eval_active_sprite, 2'b0 };
    eval_empty_sprite_next = eval_empty_sprite;
    if (oam_data_out[0][7:4] == 4'hF) begin
      /* Out of bounds, but it is so negative it would work without a check */
      sprite_index_y_calc = 8'hFF;
    end else begin
      sprite_index_y_calc = ppu_scanline[7:0] - oam_data_out[0];
    end
    if (tall_sprites == 1'b1) begin
      /* 8x16 (tall sprites) Unsupported for now */
      if (sprite_index_y_calc < 8'h10
          && eval_empty_sprite_complete == 1'b0) begin
        //
      end
    end else begin
      /* 8x8 sprites */
      if (sprite_index_y_calc < 8'h08
          && eval_empty_sprite_complete == 1'b0) begin
        if (eval_empty_sprite == 3'h7) begin
          eval_empty_sprite_complete_next = 1'b1;
        end
        if (eval_active_sprite == 6'h0) begin
          sprite_zero_active_next = 1'b1;
        end
		  /* TODO handle the fact that sprite evaluation for the next line, and rendering for
		    the current line occur at the same time. */
        sprite_eval_data_we = 1'b1;
        sprite_data_index = eval_empty_sprite;
        sprite_enabled_next = 1'b1;
        sprite_nametable_next = oam_data_out[1];
        sprite_palette_next = oam_data_out[2][1:0];
        sprite_priority_next = oam_data_out[2][5];
        sprite_flips_next = oam_data_out[2][7:6];
        sprite_counter_x_next = oam_data_out[3];
        if (sprite_flips_next[1] == 1'b1) begin
          /* sprite_index_y_next = 3'h7 - sprite_index_y_calc[2:0]; */
          sprite_index_y_next = ~sprite_index_y_calc[2:0];
        end else begin
          sprite_index_y_next = sprite_index_y_calc[2:0];
        end

        eval_empty_sprite_next = eval_empty_sprite + 3'h1;
      end
    end
    if (eval_active_sprite == 6'h3F) begin
      eval_empty_sprite_complete_next = 1'b1;
    end
  end


  pattern_table_bit_plane = 1'bx;
  if (active_fetch_type == pattern_table_low_fetch) begin
    pattern_table_bit_plane = 1'b0;
  end
  if (active_fetch_type == pattern_table_high_fetch) begin
    pattern_table_bit_plane = 1'b1;
  end

  if (fetch_group_type == fetch_group_backgrounds) begin
    for (int sprite_index = 0; sprite_index < 8;
        sprite_index = sprite_index + 1) begin
      if (sprite_counter_x[0][sprite_index] != 8'h0) begin
        sprite_counter_x_full_next[sprite_index]
          = sprite_counter_x[0][sprite_index] - 1'b1;
      end else begin
        sprite_counter_x_full_next[sprite_index]
          = sprite_counter_x[0][sprite_index];
      end
    end
  end else begin
    sprite_counter_x_full_next = sprite_counter_x[0];
  end

  nametable_entry_row = 5'hx;
  nametable_entry_column = 5'hx;
  pattern_table_table = 1'bx;
  pattern_table_entry = 8'bx;
  pattern_table_tile_row = 3'bx;
  reverser_input = 8'hx;
  reverse = 1'bx;
  if (fetch_group_type == fetch_group_sprites) begin
    if (active_fetch_type == nametable_fetch
        || active_fetch_type == attribute_table_fetch) begin
      nametable_entry_row = 5'hx;
      nametable_entry_column = 5'hx;
    end
    if (active_fetch_type == pattern_table_low_fetch
        || active_fetch_type == pattern_table_high_fetch) begin
      if (tall_sprites == 1'b1) begin
      end else begin
        pattern_table_table = ppu_ctrl[1];
        pattern_table_entry = sprite_nametable[1][ppu_column[5:3]];
        pattern_table_tile_row = sprite_index_y[1][ppu_column[5:3]];
      end
      reverser_input = memory_data_in;
      reverse = (sprite_flips[1][ppu_column[5:3]][0] == 1'b1);
      if (sprite_enabled[ppu_column[5:3]] == 1'b1) begin
        sprite_pattern_table_load_val = reverser_output;
      end else begin
        sprite_pattern_table_load_val = 8'h0;
      end
      sprite_pattern_table_load[ppu_column[5:3]][pattern_table_bit_plane] = 1'b1;
    end
  end

  /* Sprite scanline section end */

  /* Background I/O logic start */

  nametable_byte_next = nametable_byte[2];
  bg_palette_next = bg_palette[2];
  bg_pattern_table_load[0] = bg_shift_nametable;
  bg_pattern_table_load[1] = bg_shift_nametable;
  bg_pattern_table_load[2] = bg_shift_nametable;
  bg_pattern_table_load[3] = bg_shift_nametable;
  bg_pattern_table_load[4] = 1'b0;
  bg_pattern_table_load[5] = 1'b0;
  bg_pattern_table_load_val[4] = 8'hx;
  bg_pattern_table_load_val[5] = 8'hx;
  if (fetch_group_type == fetch_group_backgrounds
      || fetch_group_type == fetch_group_backgrounds_end) begin
    bg_pattern_table_shift = 1'b1;
  end else begin
    bg_pattern_table_shift = 1'b0;
  end
  if (fetch_group_type == fetch_group_backgrounds
      || fetch_group_type == fetch_group_backgrounds_end) begin
    if (active_fetch_type == nametable_fetch
        || active_fetch_type == attribute_table_fetch) begin
      nametable_entry_row = reg_coarse_y;
      nametable_entry_column = reg_coarse_x;
    end
    if (active_fetch_type == nametable_fetch) begin
      nametable_byte_next = memory_data_in;
    end
    if (active_fetch_type == attribute_table_fetch) begin
      case ({ nametable_entry_row[1], nametable_entry_column[1] })
      2'b00: bg_palette_next = memory_data_in[1:0];
      2'b01: bg_palette_next = memory_data_in[3:2];
      2'b10: bg_palette_next = memory_data_in[5:4];
      2'b11: bg_palette_next = memory_data_in[7:6];
      endcase
    end
    if (active_fetch_type == pattern_table_low_fetch
        || active_fetch_type == pattern_table_high_fetch) begin
      pattern_table_table = ppu_ctrl[2];
      pattern_table_entry = nametable_byte[2];
      pattern_table_tile_row = reg_fine_y;

      bg_pattern_table_load_val[4] = memory_data_in;
      bg_pattern_table_load_val[5] = memory_data_in;
      bg_pattern_table_load[4 + { 1'b0, pattern_table_bit_plane }] = 1'b1;
    end
  end
  /* Background I/O logic end */


  /* I/O logic section start */

  memory_address_one = 14'bx;
  if (active_fetch_type == nametable_fetch) begin
    /* There are 4 nametables each with 30 rows, and 32 columns. */
    memory_address_one = { 2'b10, nametable_table, nametable_entry_row,
      nametable_entry_column };
  end
  if (active_fetch_type == attribute_table_fetch) begin
    /* Read from nametable/attribute table section, then past the nametable
      (there are four name tables and only the first 30 rows of each are
      valid). Each attribute table entry (of which there are 4 in each byte)
      controls a 2 by 2 section of tiles (meaning a 16 by 16 pixel area). */
    memory_address_one = { 2'b10, nametable_table, 4'b1111,
      nametable_entry_row[4:2], nametable_entry_column[4:2] };
  end
  /* Each entry is two bytes meaning two fetches */
  /* pattern_table_bit_plane set above */
  if (active_fetch_type == pattern_table_low_fetch
      || active_fetch_type == pattern_table_high_fetch) begin
    /* There are 2 pattern tables (selected by a control register) the entry
      is then specified by the nametable value (256 choices). The bit plane
      is the high, or low byte of an entry. There are the 8 rows (3 bits) to
      select the proper row from the 8 by 8 tile/pattern table entry. */
    memory_address_one = { 1'b0, pattern_table_table, pattern_table_entry,
      pattern_table_bit_plane, pattern_table_tile_row };
  end
  /* I/O logic section end */

end

endmodule
