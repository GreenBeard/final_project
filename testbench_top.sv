module testbench_top();

timeunit 100ns;
timeprecision 1ns;

logic clock;

/* active low */
logic reset;

wire[15:0] sram_data;
logic[19:0] sram_address;

logic sram_we, sram_oe, sram_ce, sram_ub, sram_lb;

logic[3:0] keys;
logic[7:0][6:0] HEXS;
logic[7:0] leds_green;
logic[15:0] leds_red;
assign keys = { {3{1'b1}}, reset };
top_fast_wrapper project(.master_clock(clock), .keys(keys),
  .switches(18'h0),
  .HEX0(HEXS[0]), .HEX1(HEXS[1]), .HEX2(HEXS[2]), .HEX3(HEXS[3]),
  .HEX4(HEXS[4]), .HEX5(HEXS[5]), .HEX6(HEXS[6]), .HEX7(HEXS[7]),
  .leds_green(leds_green), .leds_red(leds_red), .ps2_clock(1'b0),
  .ps2_data(1'b0), .sram_ce(sram_ce), .sram_ub(sram_ub),
  .sram_lb(sram_lb), .sram_oe(sram_oe), .sram_we(sram_we),
  .sram_addr(sram_address), .sram_data(sram_data)
  /* Ignore VGA */);

initial begin : CLOCK_INIT
  clock = 1'b0;
end

always begin : CLOCK_GEN
  #1 clock = ~clock;
end

test_memory #(
  .size(20'd32768), .init_external(1)
) test_memory_inst (.Clk(clock), .Reset(~reset), .I_O(sram_data),
  .A(sram_address), .CE(sram_ce), .UB(sram_ub), .LB(sram_lb), .OE(sram_oe),
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
  while (project.processor.state !== project.processor.state_dont_care
      && project.processor.state !== project.processor.halted
      && project.processor.PC !== 16'hEC5B) begin
    #48;
    if (project.processor.state === project.processor.fetch_two_and_decode) begin
      /* Close enough to the Nintendulator spec, we don't process it the
        same way software does anyway. Also CYC stands for CPU cycles */
      /*display_value = $sformatf("%4h  %2h %2h %2h  ???                                     A:%2h X:%2h Y:%2h P:%2h SP:%2h PPU:%3d,%3d CYC:%d",
        project.processor.PC - 1'b1,
        test_memory_inst.mem_array[project.mapper.prg_bank_start + project.processor.PC + 20'h0][7:0],
        test_memory_inst.mem_array[project.mapper.prg_bank_start + project.processor.PC + 20'h1][7:0],
        test_memory_inst.mem_array[project.mapper.prg_bank_start + project.processor.PC + 20'h2][7:0],
        project.processor.reg_a,
        project.processor.reg_x,
        project.processor.reg_y,
        { project.processor.reg_status[5:4], 2'b10, project.processor.reg_status[3:0] },
        project.processor.reg_stack,
        scanline_cycle,
        scanline,
        cpu_cycle);
      $display("%s %t ps", display_value, $time);
      $fwrite(file, "%s\n", display_value);*/
    end
    ++cpu_cycle;
  end
  $fclose(file);
endtask

int error_count;

initial begin : TEST_VECTORS

error_count = 0;

reset = 1'b0;
#96 reset = 1'b1;
#96;
$deposit(project.ppu.ppu_mask, 8'b00011110);

/* Speed up CPU startup */
#480
force project.ppu.ppu_status=8'h80;
#96;
release project.ppu.ppu_status;
#96;

//wait_for_scanpos();


run_suite();

if (project.processor.state !== project.processor.state_dont_care && project.processor.state !== project.processor.halted) begin
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
