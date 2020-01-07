module bram_color(
  input clock,
  input write_enable,
  input logic[7:0] data_in,
  output logic[7:0] data_out,
  input logic[15:0] address
);

reg[7:0] mem[61439:0] /* synthesis ramstyle = M9K */ /* verilator public */;

always_ff @ (posedge clock) begin
  if (write_enable == 1'b1) begin
    mem[address] <= data_in;
  end
  data_out <= mem[address];
end

endmodule
