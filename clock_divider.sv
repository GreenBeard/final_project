module clock_divider #(parameter divisor=1, parameter width=$clog2(divisor)) (
  input logic reset,
  input logic in_clk,
  output logic out_clk
);

logic next_out_clk;

logic[width-1:0] counter;
logic[width-1:0] next_counter;

always_ff @ (posedge in_clk) begin
  counter <= next_counter;
  out_clk <= next_out_clk;
end

always_comb begin
  /* verilator lint_off WIDTH */
  /* Only supports even divison currently */
  assert(divisor == (divisor / 2) * 2);

  if (reset) begin
    next_counter = {width{1'b0}};
  end else begin
    if (counter == divisor - 'b1) begin
      next_counter = {width{1'b0}};
    end else begin
      next_counter = counter + {{width-1{1'b0}}, {1'b1}};
    end
  end
  if (next_counter < divisor / 2) begin
    next_out_clk = 1'b0;
  end else begin
    next_out_clk = 1'b1;
  end
  /* verilator lint_on WIDTH */
end

endmodule
