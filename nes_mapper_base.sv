/*
  SRAM address space layout:
  0x00000 to 0x007FF 2kB of internal CPU RAM
  0x00800 to 0x00FFF 2kB of internal PPU RAM
  (use mapper_cartridge_start macro)
  0x01000 to 0xFFFFF Currently all for cartridge services
 */

/*
 0 - vertical mirroring (top, and bottom the same)
 1 - horizontal mirroring
*/

`define mapper_cartridge_start 20'h01000

`define mapper_inputs \
( \
  /* active high */ \
  input logic reset, \
  \
  /* Not technically used on the real NES */ \
  /* dual_clock runs twice the rate of the other two clocks */ \
  input logic dual_clock, \
  \
  input logic[7:0] reg_4016, \
  input logic[7:0] reg_4017, \
  input logic[1:0] controller_oe, \
  \
  input logic[7:0] ppu_cpu_data_out, \
  input logic ppu_cs, \
  \
  /* read is high, write is low */ \
  input logic cpu_read_write, \
  input logic[15:0] cpu_address, \
  output logic[7:0] cpu_data_in, \
  input logic[7:0] cpu_data_out, \
  \
  /* read, and write are active low */ \
  input logic ppu_read, \
  input logic ppu_write, \
  input logic[13:0] ppu_address, \
  output logic[7:0] ppu_data_in, \
  input logic[7:0] ppu_data_out, \
  /* active low for interrupt */ \
  output logic IRQ, \
  \
  /* SRAM data */ \
  output logic[19:0] sram_address, \
  output logic[15:0] sram_data_out, \
  input logic[15:0] sram_data_in, \
  /* active low */ \
  output logic sram_write_enable, \
  output logic sram_read_enable \
);

`define mapper_signal_header \
const logic[19:0] cpu_internal_ram_start = 20'h00000; \
const logic[19:0] ppu_internal_ram_start = 20'h00800; \
 \
logic[19:0] sram_address_cpu_next; \
logic[19:0] sram_address_ppu_next; \
 \
logic cpu_write_enable_next; \
logic cpu_read_enable_next; \
logic ppu_write_enable_next; \
logic ppu_read_enable_next; \
 \
logic[7:0] data_out_reg; \

`define mapper_sram_common \
/* active high */ \
logic write_enabled; \
/* active high */ \
logic read_enabled; \
 \
`ifdef MODEL_TECH \
`else \
initial write_enabled = 1'b0; \
initial read_enabled = 1'b0; \
`endif \
 \
assign sram_data_out = write_enabled == 1'b1 ? { 8'h0, data_out_reg } : 16'hZ; \
 \
logic cpu_turn; \
always_ff @ (posedge dual_clock) begin \
  /* Uses values immediately before (meaning if cpu_turn_clock is high it */ \
  /* is about to become low). */ \
  if (reset == 1'b1) begin \
    cpu_turn <= 1'b0; \
  end else begin \
    cpu_turn <= ~cpu_turn; \
    sram_address <= cpu_turn == 1'b0 ? sram_address_cpu_next : sram_address_ppu_next; \
    data_out_reg <= cpu_turn == 1'b0 ? cpu_data_out : ppu_data_out; \
    write_enabled <= cpu_turn == 1'b0 ? ~cpu_write_enable_next : ~ppu_write_enable_next; \
    read_enabled <= cpu_turn == 1'b0 ? ~cpu_read_enable_next : ~ppu_read_enable_next; \
  end \
end \
 \
logic[7:0] cpu_data_in_next; \
logic[7:0] ppu_data_in_next; \
always_ff @ (negedge dual_clock) begin \
  /* Inverted as it just flipped on the posedge */ \
  if (cpu_turn == 1'b1) begin \
    cpu_data_in <= cpu_data_in_next; \
  end else begin \
    ppu_data_in <= ppu_data_in_next; \
  end \
end \
 \
assign sram_write_enable = ~write_enabled; \
assign sram_read_enable = ~read_enabled; \

/* The following are intended for use in an always_comb */
`define mapper_ppu_comb_header \
  sram_address_ppu_next = 20'hx; \
  ppu_write_enable_next = 1'b1; \
  ppu_read_enable_next = 1'b1; \
  ppu_data_in_next = sram_data_in[7:0]; \

`define mapper_ppu_nametable \
  if (ppu_address[13] == 1'b1) begin \
    ppu_write_enable_next = ppu_write; \
    ppu_read_enable_next = ppu_read; \
    if (mirroring == 1'b0) begin \
      /* vertical mirroring */ \
      sram_address_ppu_next = ppu_internal_ram_start \
        + { 6'b0, 3'b0, ppu_address[10:0] }; \
    end \
    if (mirroring == 1'b1) begin \
      /* horizontal mirroring */ \
      sram_address_ppu_next = ppu_internal_ram_start \
        + { 6'b0, 3'b0, ppu_address[11], ppu_address[9:0] }; \
    end \
  end \

`define mapper_cpu_comb_header \
  sram_address_cpu_next = 20'hx; \
  cpu_write_enable_next = 1'b1; \
  cpu_read_enable_next = 1'b1; \
  cpu_data_in_next = sram_data_in[7:0]; \

`define mapper_cpu_internal_ram \
  /* Internal NES RAM */ \
  if (cpu_address[15:13] == 3'b000) begin \
    cpu_write_enable_next = cpu_read_write; \
    cpu_read_enable_next = ~cpu_read_write; \
    sram_address_cpu_next = cpu_internal_ram_start \
      + { 9'b0, cpu_address[10:0] }; \
  end \

`define mapper_cpu_io_ppu \
  assert(controller_oe !== 2'b00); \
  if (controller_oe[0] == 1'b0) begin \
    cpu_data_in_next = reg_4016; \
  end \
  if (controller_oe[1] == 1'b0) begin \
    cpu_data_in_next = reg_4017; \
  end \
 \
  if (ppu_cs == 1'b0) begin \
    cpu_data_in_next = ppu_cpu_data_out; \
  end \

/* The end of the alway_comb section */
