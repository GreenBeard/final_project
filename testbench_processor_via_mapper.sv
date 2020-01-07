module testbench_processor_via_mapper();

/* Using instr_test_v5 from Blargg's test suites */

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
nes_mapper_one #(
  .ram_option(1'b1), .chr_bank_count(6'd0), .prg_bank_count(5'd16)
)
mapper(
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
  .size(20'h43000), .init_external(1)
) test_memory_inst (.Clk(clock), .Reset(~reset_delayed), .I_O(sram_data),
  .A(sram_address), .CE(1'b0), .UB(1'b0), .LB(1'b0), .OE(sram_oe),
  .WE(sram_we));

logic[7:0] test_status;
assign test_status = test_memory_inst.mem_array[20'h33000 + 20'h6000][7:0];
logic[2:0][7:0] test_check;
assign test_check = {
  test_memory_inst.mem_array[20'h33000 + 20'h6001][7:0],
  test_memory_inst.mem_array[20'h33000 + 20'h6002][7:0],
  test_memory_inst.mem_array[20'h33000 + 20'h6003][7:0]
};

logic[2:0][7:0] test_check_done;
assign test_check_done = { 8'hDE, 8'hB0, 8'h61 };

int test_count;
task run_suite();
  test_count = 0;
  while (processor.state !== processor.state_dont_care
      && processor.state !== processor.halted
      && processor.PC !== 16'hEC5B) begin
    if (test_check === test_check_done) begin
      $display("Test %d? finished with status %d %t", test_count, test_status,
        $time);
      #100 ;
      ++test_count;
    end
    /* This isn't supposed to happen in this test suite */
    if (processor.PC <= 16'h0100) begin
      $display("Invalid PC");
      $stop();
    end
    #4;
  end
endtask

int error_count;

initial begin : TEST_VECTORS

error_count = 0;

ppu_read = 1'b1;
ppu_write = 1'b1;

reset = 1'b0;
#100 reset = 1'b1;
#100;

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
