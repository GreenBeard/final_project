module full_adder(
  input logic a, b,
  output logic sum,
  input logic c_in,
  output logic c_out
);

always_comb begin
  sum = a ^ b ^ c_in;
  c_out = (a & b) | (b & c_in) | (c_in & a);
end

endmodule
