/*
  2kB, or 4kB of RAM (if present)
  start of PRG banks (if RAM present, 0x01000 otherwise)
  After PRG banks, start of CHR banks

  CPU address space layout:
  0x6000 to 0x7FFF - 2kB, or 4kB of RAM (optional, and mirrored)
  0x8000 to 0xBFFF - 16kB of ROM (fixed mapping)
  0xC000 to 0xFFFF - 16kB of ROM (either duplicate of 0x8000, or separate
    fixed mapping)

  PPU address space layout:
  0x0000 to 0x0FFF 4kB ROM bank (fixed mapping)
  0x1000 to 0x1FFF 4kB ROM bank (fixed mapping)
 */
`include "nes_mapper_base.sv"

module nes_mapper_zero
#(
/* 0 - no RAM
   1 - 2kB of RAM
   2 - 4kB of RAM
   3 - invalid
 */
  parameter ram_option=2'b00,
  /* 8kB of CHR ROM is the only option */
  /*parameter chr_bank_count=,*/
  /* 1, or 2 */
  parameter prg_bank_count=2'd2,
  /*
   0 - vertical mirroring (top, and bottom the same)
   1 - horizontal mirroring
  */
  parameter mirroring=1'b0
)
`mapper_inputs

assign IRQ = 1'b1;

`mapper_signal_header

/* Cartridge RAM */
const logic[19:0] ram_start = `mapper_cartridge_start ;
logic[19:0] chr_bank_start /* verilator public */;
logic[19:0] prg_bank_start /* verilator public */;
always_comb begin
  if (ram_option == 2'b00) begin
    prg_bank_start = ram_start;
  end else if (ram_option == 2'b01) begin
    prg_bank_start = ram_start + 20'h00800;
  end else if (ram_option == 2'b10) begin
    prg_bank_start = ram_start + 20'h01000;
  end else begin
    prg_bank_start = ram_start;
    assert(1'b0 == 1'b1);
  end
  chr_bank_start = 20'h04000 * prg_bank_count + prg_bank_start;
end

`mapper_sram_common

always_comb begin
  `mapper_ppu_comb_header

  if (ppu_address[13] == 1'b0) begin
    ppu_read_enable_next = ppu_read;
    sram_address_ppu_next = chr_bank_start + { 6'b0, 1'b0, ppu_address[12:0] };
  end

  `mapper_ppu_nametable
end

always_comb begin
  `mapper_cpu_comb_header

  `mapper_cpu_internal_ram

  /* PRG RAM bank */
  if (ram_option == 2'b01) begin
    if (cpu_address[15:13] == 3'b011) begin
      sram_address_cpu_next = ram_start + { 9'b0, cpu_address[10:0] };
      cpu_write_enable_next = cpu_read_write;
      cpu_read_enable_next = ~cpu_read_write;
    end
  end
  if (ram_option == 2'b10) begin
    if (cpu_address[15:13] == 3'b011) begin
      sram_address_cpu_next = ram_start + { 8'b0, cpu_address[11:0] };
      cpu_write_enable_next = cpu_read_write;
      cpu_read_enable_next = ~cpu_read_write;
    end
  end
  /* PRG ROM banks */
  if (prg_bank_count == 2'd1) begin
    if (cpu_address[15] == 1'b1) begin
      cpu_write_enable_next = 1'b1;
      cpu_read_enable_next = ~cpu_read_write;
      sram_address_cpu_next = prg_bank_start + { 6'b0, cpu_address[13:0] };
    end
  end
  if (prg_bank_count == 2'd2) begin
    if (cpu_address[15] == 1'b1) begin
      cpu_write_enable_next = 1'b1;
      cpu_read_enable_next = ~cpu_read_write;
      sram_address_cpu_next = prg_bank_start + { 5'b0, cpu_address[14:0] };
    end
  end

  `mapper_cpu_io_ppu
end

endmodule
