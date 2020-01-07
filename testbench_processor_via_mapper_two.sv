module testbench_processor_via_mapper_two();

timeunit 10ns;
timeprecision 1ns;

logic clock;

/* active low */
logic reset;
logic reset_ah;
logic reset_delayed;
assign reset_ah = ~reset;

logic cpu_read_write;
logic[15:0] cpu_address;
logic[7:0] cpu_data_in;
logic[7:0] cpu_data_out;

logic ppu_read;
logic ppu_write;
logic[13:0] ppu_address;
logic[7:0] ppu_data_in;
logic[7:0] ppu_data_out;

wire[15:0] sram_data;
logic[19:0] sram_address;

shift_register #(.width(8)) delay_reset_gen(.clock(clock), .in(reset), .out(reset_delayed));

logic sram_we, sram_oe;
logic[15:0] sram_data_out;
nes_mapper_zero #(
  .ram_option(2'b10), .prg_bank_count(4'd1)
) mapper(
  .reset(~reset_delayed), .dual_clock(clock), .cpu_read_write(cpu_read_write),
  .cpu_address(cpu_address), .cpu_data_in(cpu_data_in),
  .cpu_data_out(cpu_data_out), .ppu_read(ppu_read), .ppu_write(ppu_write),
  .ppu_address(ppu_address), .ppu_data_in(ppu_data_in),
  .ppu_data_out(ppu_data_out), .IRQ(), .sram_address(sram_address),
  .sram_data_in(sram_data), .sram_data_out(sram_data_out),
  .sram_write_enable(sram_we), .sram_read_enable(sram_oe)
);

logic cpu_clock;
processor_6502 processor(.master_clock(clock), .reset(reset_delayed),
  .reset_clock(~reset), .NMI(1'b1),
  .interrupt_request(1'b1), .memory_address(cpu_address),
  .memory_data_in(cpu_data_in), .memory_data_out(cpu_data_out),
  .read_write(cpu_read_write), .controller_out(), .controller_oe(),
  .debug_red_leds(), .cpu_clock(cpu_clock));

assign sram_data = sram_we == 1'b0 ? sram_data_out : 16'hz;

initial begin : CLOCK_INIT
  clock = 1'b0;
end

always begin : CLOCK_GEN
  #2 clock = ~clock;
end

test_memory #(
  .size(20'd32768), .init_external(1)
) test_memory_inst (.Clk(clock), .Reset(~reset_delayed), .I_O(sram_data),
  .A(sram_address), .CE(1'b0), .UB(1'b0), .LB(1'b0), .OE(sram_oe),
  .WE(sram_we));

int cpu_cycle;
int scanline;
/* [0,340], 341 cycles */
int scanline_cycle;
int file;
string display_value;
task run_suite();
  cpu_cycle = 0;
  scanline = 0;
  scanline_cycle = 0;
  file = $fopen("/tmp/tmp.txt", "w");
  while (processor.state !== processor.state_dont_care
      && processor.state !== processor.halted
      && processor.PC !== 16'hEC5B) begin
    #48;
    if (processor.state === processor.fetch_two_and_decode) begin
      /* Close enough to the Nintendulator spec, we don't process it the
        same way software does anyway. Also CYC stands for CPU cycles */
      display_value = $sformatf("%4h  %2h %2h %2h  ???                                     A:%2h X:%2h Y:%2h P:%2h SP:%2h PPU:%3d,%3d CYC:%d",
        processor.PC - 1'b1,
        test_memory_inst.mem_array[mapper.prg_bank_start + processor.PC + 20'h0][7:0],
        test_memory_inst.mem_array[mapper.prg_bank_start + processor.PC + 20'h1][7:0],
        test_memory_inst.mem_array[mapper.prg_bank_start + processor.PC + 20'h2][7:0],
        processor.reg_a,
        processor.reg_x,
        processor.reg_y,
        { processor.reg_status[5:4], 2'b10, processor.reg_status[3:0] },
        processor.reg_stack,
        scanline_cycle,
        scanline,
        cpu_cycle + 7);
      $display("%s %t ps", display_value, $time);
      $fwrite(file, "%s\n", display_value);
    end
    ++cpu_cycle;
  end
  $fclose(file);
endtask

int error_count;

initial begin : TEST_VECTORS

error_count = 0;

ppu_read = 1'b1;
ppu_write = 1'b1;

reset = 1'b0;
#100 reset = 1'b1;
#48;
$deposit(processor.PC, 16'hC000);
$deposit(processor.state, processor.fetch);
//#20000 ;

run_suite();

if (processor.state !== processor.state_dont_care && processor.state !== processor.halted) begin
  $display("Ended in valid state. The first step towards success");
end else begin
  $display("Failure: ended in INVALID state");
end

/*if (error_count == 0) begin
  $display("Success with all tests");
end else begin
  $display("Failed %d tests", error_count);
end*/

$stop();

end

endmodule
