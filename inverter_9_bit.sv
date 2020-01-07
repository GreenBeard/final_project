module inverter_9_bit(
  input logic[8:0] in,
  output logic[8:0] out
);

always_comb begin
  out = ~in;
end

endmodule
