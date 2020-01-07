module bram
#(
  parameter size=64
)
(
  input clock,
  input write_enable,
  input logic[7:0] data_in,
  output logic[7:0] data_out,
  input logic[$clog2(size)-1:0] address
);

reg[7:0] mem[size-1:0] /* synthesis ramstyle = M9K */;

always_ff @ (posedge clock) begin
  if (write_enable == 1'b1) begin
    mem[address] <= data_in;
  end
  data_out <= mem[address];
end

endmodule
