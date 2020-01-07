module ripple_adder_8(
  input logic[7:0] A, B,
  output logic[7:0] Sum,
  input logic c_in,
  output logic c_out
);

`ifndef verilator
logic[8:0] carries;

assign carries[0] = c_in;
assign c_out = carries[8];

genvar i;
generate
for (i = 0; i < 8; ++i) begin : adders
  full_adder adder(.a(A[i]), .b(B[i]), .sum(Sum[i]), .c_in(carries[i]), .c_out(carries[i + 1]));
end
endgenerate
`else
assign { c_out, Sum } = { 1'b0, A } + { 1'b0, B } + { 8'b0, c_in };
`endif

endmodule
