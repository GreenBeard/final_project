module testbench_mapper_one();

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

logic sram_cpu_clock;
clock_divider #(.divisor(2)) master_to_cpu_sram(.reset(~reset_delayed), .in_clk(clock), .out_clk(sram_cpu_clock));

logic sram_we, sram_oe;
logic[15:0] sram_data_out;
nes_mapper_one #(
  .ram_option(1'b1), .chr_bank_count(5'd2), .prg_bank_count(4'd2)
) mapper(
  .reset(~reset), .cpu_turn_clock(sram_cpu_clock),
  .ppu_turn_clock(~sram_cpu_clock), .cpu_read_write(cpu_read_write),
  .cpu_address(cpu_address), .cpu_data_in(cpu_data_in),
  .cpu_data_out(cpu_data_out), .ppu_read(ppu_read), .ppu_write(ppu_write),
  .ppu_address(ppu_address), .ppu_data_in(ppu_data_in),
  .ppu_data_out(ppu_data_out), .IRQ(), .sram_address(sram_address),
  .sram_data_in(sram_data), .sram_data_out(sram_data_out),
  .sram_write_enable(sram_we), .sram_read_enable(sram_oe)
);

assign sram_data = sram_we == 1'b0 ? sram_data_out : 16'hz;

initial begin : CLOCK_INIT
  clock = 1'b0;
end

always begin : CLOCK_GEN
  #2 clock = ~clock;
end

test_memory test_memory_inst(.Clk(clock), .Reset(reset_ah), .I_O(sram_data),
  .A(sram_address), .CE(1'b0), .UB(1'b0), .LB(1'b0), .OE(sram_oe),
  .WE(sram_we));

int error_count;

task wait_for_cpu_turn();
  while (sram_cpu_clock != 1'b0) begin
    #2 ;
  end
endtask

initial begin : TEST_VECTORS

error_count = 0;
cpu_data_out = 8'hx;
cpu_read_write = 1'b1;

reset = 1'b0;
#100 reset = 1'b1;
#100;

cpu_address = 16'h2;
#10;
wait_for_cpu_turn();
if (sram_address !== 20'h00002 || sram_oe != 1'b0 || sram_we != 1'b1) begin
  ++error_count;
  $display("Error with CPU internal address %t", $time);
end

cpu_address = 16'h0802;
#10;
wait_for_cpu_turn();
if (sram_address !== 20'h00002 || sram_oe != 1'b0 || sram_we != 1'b1) begin
  ++error_count;
  $display("Error with CPU internal address %t", $time);
end

cpu_address = 16'h1802;
#10;
wait_for_cpu_turn();
if (sram_address !== 20'h00002 || sram_oe != 1'b0 || sram_we != 1'b1) begin
  ++error_count;
  $display("Error with CPU internal address %t", $time);
end

cpu_address = 16'h1802;
cpu_read_write = 1'b0;
#10;
wait_for_cpu_turn();
if (sram_address !== 20'h00002 || sram_oe != 1'b1 || sram_we != 1'b0) begin
  ++error_count;
  $display("Error with read/write CPU internal address %t", $time);
end
cpu_read_write = 1'b1;

cpu_address = 16'h6113;
#10;
wait_for_cpu_turn();
if (sram_address !== 20'h01113 || sram_oe != 1'b0 || sram_we != 1'b1) begin
  ++error_count;
  $display("Error with PRG RAM address %t", $time);
end

cpu_address = 16'h8003;
#10;
wait_for_cpu_turn();
/* In mode 3 with bank 0 selected */
if (sram_address !== 20'h05003 || sram_oe != 1'b0 || sram_we != 1'b1) begin
  ++error_count;
  $display("Error with PRG ROM lower bank (mode 3) address %t", $time);
end

cpu_address = 16'hC003;
#10;
wait_for_cpu_turn();
/* In mode 3 with last bank (0) selected */
if (sram_address !== 20'h09003 || sram_oe != 1'b0 || sram_we != 1'b1) begin
  ++error_count;
  $display("Error with PRG ROM upper bank (mode 3) address %t", $time);
end

cpu_address = 16'hC003;
cpu_read_write = 1'b0;
#10;
wait_for_cpu_turn();
/* In mode 3 with last bank (0) selected */
if (sram_address !== 20'h09003 || sram_we != 1'b1) begin
  ++error_count;
  $display("Error with read/write PRG ROM upper bank (mode 3) address %t", $time);
end
cpu_read_write = 1'b1;


#20 ;

if (error_count == 0) begin
  $display("Success with all tests");
end else begin
  $display("Failed %d tests", error_count);
end

$stop();

end

endmodule
