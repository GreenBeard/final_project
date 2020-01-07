module testbench_clock_divider();

logic clock;
logic clock_out_2;
logic clock_out_4;
logic clock_out_12;
logic reset;

initial begin : clock_init
  clock = 1'b0;
end

always begin : clock_gen
  #1 clock = ~clock;
end

clock_divider #(.divisor(2)) divider_a(.reset(reset), .in_clk(clock), .out_clk(clock_out_2));
clock_divider #(.divisor(4)) divider_b(.reset(reset), .in_clk(clock), .out_clk(clock_out_4));
clock_divider #(.divisor(12)) divider_c(.reset(reset), .in_clk(clock), .out_clk(clock_out_12));

logic a;
assign a = 1'bz;
logic b;
assign b = 1'b1;

logic c;
assign c = a | b;

initial begin : test_vectors

reset = 1'b1;
#2;
reset = 1'b0;
#2;

#200;

$stop();

end

endmodule
