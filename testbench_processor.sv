module testbench_processor();

timeunit 10ns;
timeprecision 1ns;

logic clock;

/* active low */
logic reset;
logic reset_ah;
logic reset_clock;
assign reset_ah = ~reset;

logic[15:0] mem_addr;
logic[7:0] mem_data_in;
logic[7:0] mem_data_out;
logic read_write;

wire[15:0] sram_data;
logic[19:0] sram_address;

processor_6502 processor(.master_clock(clock), .reset(reset),
  .reset_clock(reset_clock), .NMI(1'b1),
  .interrupt_request(1'b1), .memory_address(mem_addr),
  .memory_data_in(mem_data_in), .memory_data_out(mem_data_out),
  .read_write(read_write), .controller_out(), .controller_oe(),
  .debug_red_leds(), .cpu_clock());

initial begin : CLOCK_INIT
  clock = 1'b0;
end

always begin : CLOCK_GEN
  #2 clock = ~clock;
end

test_memory test_memory_inst(.Clk(clock), .Reset(reset_ah), .I_O(sram_data),
  .A(sram_address), .CE(1'b0), .UB(1'b0), .LB(1'b0), .OE(~read_write),
  .WE(read_write));

assign sram_data = read_write ? 16'hZ : { 8'h0, mem_data_out };
assign mem_data_in = sram_data;

assign sram_address = { 4'b0, mem_addr };

initial begin : TEST_VECTORS

reset = 1'b0;
reset_clock = 1'b1;
#10 reset_clock = 1'b0;
#100 reset = 1'b1;

#2000 ;

$stop();

end

endmodule
