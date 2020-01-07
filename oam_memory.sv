module oam_memory
#(
  parameter size=0
)
(
  input clock,
  input write_enable,
  input logic[7:0] data_in,
  output logic[3:0][7:0] data_out,
  input logic[$clog2(size)-1+2:0] address
);

reg[7:0] mem[size-1:0][4];

`ifdef MODEL_TECH
initial mem = '{64{'{4{8'h0}}}};
`endif

always @ (posedge clock) begin
  if (write_enable == 1'b1) begin
    mem[address[7:2]][address[1:0]] <= data_in;
  end
end

always_comb begin
  data_out = { mem[address[7:2]][3], mem[address[7:2]][2],
    mem[address[7:2]][1], mem[address[7:2]][0] };
end

endmodule
