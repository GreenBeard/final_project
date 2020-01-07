/*
 Handles interactions between the CPU, SRAM, and memory mapped devices.
*/
module processor_memory_interface(
  input cpu_clock,
  /* Goes high when our data is ready */
  input sram_turn_clock,
  input logic[15:0] address,
  inout wire[7:0] cpu_bus,
  /* active low signals */
  input logic read,
  input logic write,

  input logic[7:0] input_one,
  input logic[7:0] input_two,
  input logic[7:0] input_one_active,
  input logic[7:0] input_two_active,

  input logic[7:0] OAMDMA_reg,
  input logic[7:0] OAMDMA_reg_active,

  input logic[15:0] mapper_output_address,
  output logic[15:0] mapper_input_address,

  output logic sram_oe,
  output logic sram_we,
  output logic[19:0] sram_addr,
  inout wire[7:0] sram_data_bus
);

/* Yes, for some reason the NES can sort of store values in this bus,
  It may be useful to learn about SystemVerilog's signal strength, and
  check if they are synthesizable. */
logic[7:0] stored_bus_value;
logic[7:0] next_bus_value;
/* Used to synchronize output */
logic[7:0] write_bus_value;

logic[19:0] next_sram_addr;

assign sram_data_bus = ~write ? write_bus_value : 8'hZ;
assign cpu_bus = ~read ? stored_bus_value : 8'hZ;

always_ff @ (negedge cpu_clock) begin
  assert(read | write == 1'b1);
  sram_addr <= next_sram_addr;
  sram_oe <= read;
  sram_we <= write;
  write_bus_value <= cpu_bus;
end

always_ff @ (posedge sram_turn_clock) begin
  stored_bus_value <= next_bus_value;
end

/* Not technically correct, though as we aren't using the APU it probably
  doesn't matter. */
logic[31:0][7:0] general_registers;
assign general_registers = { {20{8'h00}}, OAMDMA_reg, 8'h00, input_one,
  input_two, {8{8'h00}} };
/* Which bits are active (as in held not high Z) */
logic[31:0][7:0] general_registers_active;
assign general_registers_active = { {20{8'hFF}}, OAMDMA_reg_active, 8'hFF,
  input_one_active, input_two_active, {8{8'hFF}} };

always_comb begin
  next_sram_addr = 20'hX;
  mapper_input_address = address;
  next_bus_value = 8'hX;
  if (~read && ~write) begin
  end else begin
    if (~read) begin
      if (address < 16'h2000) begin
        /* Internal RAM */
        next_sram_addr = { 8'h0, address[11:0] };
      end else if (address < 16'h4000) begin
        /* PPU registers */
        assert(1'b1 == 1'b0);
        /* TODO
        ??? = address[2:0]; */
      end else if (address < 16'h4020) begin
        /* NES APU, and I/O registers */
        /* Only 0x4014, 0x4016, and 0x4017 are implemented
           for our needs as we don't implement the APU */
        next_bus_value = (~general_registers_active[address[4:0]] & stored_bus_value)
          | (general_registers_active[address[4:0]] & general_registers[address[4:0]]);
      end else if (address >= 16'h4020) begin
        /* Cartridge memory addresses */
        next_sram_addr = mapper_output_address;
        next_bus_value = sram_data_bus;
      end
    end
  end
end

endmodule
