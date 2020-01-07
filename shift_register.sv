module shift_register #(width=8) (
  input logic clock,
  input logic in,
  output logic out
);

logic[width-1:0] shift_reg;

`ifdef MODEL_TECH
`else
initial shift_reg = {width{1'b0}};
`endif

always_comb begin
  out = shift_reg[0];
end

always_ff @ (posedge clock) begin
  shift_reg <= { in, shift_reg[width-1:1] };
end

endmodule
