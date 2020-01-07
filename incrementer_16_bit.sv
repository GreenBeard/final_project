module incrementer_16_bit(
  input logic[15:0] in,
  output logic[15:0] out
);

always_comb begin
  out = in + 16'h1;
end

endmodule
