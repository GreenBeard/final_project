/*
  CPU address space layout:
  0x6000 to 0x7FFF - 8kB of RAM (optional)
  0x8000 to 0xBFFF - 16kB of ROM (remappable)
  0xC000 to 0xFFFF - 16kB of ROM (remappable)

  PPU address space layout:
  0x0000 to 0x0FFF 4kB RAM, or ROM bank (remappable)
  0x1000 to 0x1FFF 4kB RAM, or ROM bank (remappable)

  If the INES header says 0 chr rom banks that means 2 chr ram banks
 */
module nes_mapper_one
#(
  parameter prg_ram_option=1'b0,
  parameter chr_bank_count=6'd2,
  parameter prg_bank_count=5'd2,
  parameter mirroring=1'b0
)
`mapper_inputs

const logic[4:0] unused_untruncated_prg_bank_last = prg_bank_count - 5'b1;
const logic[3:0] prg_bank_last = unused_untruncated_prg_bank_last[3:0];
always_comb begin
  assert(chr_bank_count <= 32);
  assert(prg_bank_count <= 16);
end

assign IRQ = 1'b1;

const logic[19:0] prg_bank_start /* verilator public */ = `mapper_cartridge_start + (prg_ram_option == 1'b1 ? 20'h02000 : 20'h0);
const logic[19:0] chr_bank_start /* verilator public */ = 20'h04000 * prg_bank_count + prg_bank_start;

`mapper_signal_header

`mapper_sram_common

logic[4:0] input_register, input_register_next;
/*
  Control register CPPMM
    C - 0: Select 8kB of ROM from CHR bank 0 register (ignore low bit)
        1: Select two 4kB of ROM from CHR bank 0, and bank 1
   PP - 0, 1: Select 32kB of ROM ignoring low bit of PRG bank
        2: Fix 0x8000 to first bank, 0xC000 to selected 16kB of ROM
        3: Fix 0xC000 to last bank, 0x8000 to selected 16kB of ROM
   MM - Mirroring mode
        0: one screen, lower bank
        1: one screen, upper bank
        2: vertical
        3: horizontal

  CHR bank 0
  CHR bank 1
  PRG bank
    highest bit enables RAM when high (defaults to high, or low depending
    upon exact mapper mode).
 */
logic[4:0] registers[4];

logic reg_load_next;
logic[1:0] reg_next;
logic[4:0] reg_value_next;

always_ff @ (posedge dual_clock) begin
  if (reset == 1'b1) begin
    /* Assuming MMC1B, many values set for test mapper */
    registers <= '{ 5'b11110, 5'b0, 5'b0, 5'b00000 };
    input_register <= 5'b10000;
  end else begin
    if (reg_load_next == 1'b1) begin
      registers[reg_next] <= reg_value_next;
    end
  end
  input_register <= input_register_next;
end

always_comb begin
  `mapper_ppu_comb_header

  /* TODO finish PPU section */

  `mapper_ppu_nametable
end

always_comb begin
  /* Used for control register handling */
  /* TODO check if last access was a write */
  input_register_next = input_register;
  reg_load_next = 1'b0;
  reg_value_next = 5'bx;
  reg_next = 2'bx;
  if (cpu_address[15] == 1'b1 && cpu_read_write == 1'b0) begin
    if (cpu_data_out[7] == 1'b1) begin
      input_register_next = 5'b10000;
    end else begin
      if (input_register[0] == 1'b1) begin
        reg_load_next = 1'b1;
        reg_next = cpu_address[14:13];
        reg_value_next = { cpu_data_out[0], input_register[4:1] };
        input_register_next = 5'b10000;
      end else begin
        input_register_next = { cpu_data_out[0], input_register[4:1] };
      end
    end
  end

  `mapper_cpu_comb_header

  `mapper_cpu_internal_ram

  /* PRG RAM bank */
  if (cpu_address[15:13] == 3'b011 && registers[3][4] == 1'b0 && prg_ram_option == 1'b1) begin
    sram_address_cpu_next = 20'h01000 + { 7'b0, cpu_address[12:0] };
    cpu_write_enable_next = cpu_read_write;
    cpu_read_enable_next = ~cpu_read_write;
  end
  /* Lower PRG ROM bank */
  if (cpu_address[15:14] == 2'b10) begin
    cpu_write_enable_next = 1'b1;
    cpu_read_enable_next = ~cpu_read_write;
    case (registers[0][3:2])
      2'b00, 2'b01: sram_address_cpu_next = prg_bank_start + { 6'b0, cpu_address[13:0] } + { 2'b0, registers[3][3:1], 1'b0, 14'b0 };
      2'b10: sram_address_cpu_next = prg_bank_start + { 6'b0, cpu_address[13:0] } + { 2'b0, 4'b0, 14'b0 };
      2'b11: sram_address_cpu_next = prg_bank_start + { 6'b0, cpu_address[13:0] } + { 2'b0, registers[3][3:0], 14'b0 };
    endcase
  end
  /* Upper PRG ROM bank */
  if (cpu_address[15:14] == 2'b11) begin
    cpu_write_enable_next = 1'b1;
    cpu_read_enable_next = ~cpu_read_write;
    case (registers[0][3:2])
      2'b00, 2'b01: sram_address_cpu_next = prg_bank_start + { 6'b0, cpu_address[13:0] } + { 2'b0, registers[3][3:1], 1'b1, 14'b0 };
      2'b10: sram_address_cpu_next = prg_bank_start + { 6'b0, cpu_address[13:0] } + { 2'b0, registers[3][3:0], 14'b0 };
      2'b11: sram_address_cpu_next = prg_bank_start + { 6'b0, cpu_address[13:0] } + { 2'b0, prg_bank_last, 14'b0 };
    endcase
  end

  `mapper_cpu_io_ppu
end

endmodule
