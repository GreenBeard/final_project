module testbench_alu();

logic mode;
logic a;
logic b;

alu_6502 alu_inst(.mode(mode),.input_a(a),.input_b(b),.result());

initial begin : test_vectors
#2;
#200;
$stop();
end
