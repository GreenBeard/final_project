module status_calc(
  input logic[8:0] result,
  input logic input_a_high,
  input logic input_b_high,
  output logic[3:0] out
);

/* Calculates NVZC (in that order) */
always_comb begin
  out[3] = result[7];
  out[2] = input_a_high & input_b_high & ~result[7]
    | ~input_a_high & ~input_b_high & result[7];
  out[1] = ~(| result[7:0]);
  out[0] = result[8];
end

endmodule
