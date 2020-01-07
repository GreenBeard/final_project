module ppu_shift_reg(
  input clock,
  input logic shift,
  input logic load,
  input logic[7:0] data_in,
  input logic shift_in,
  output logic[7:0] data_out,
  output logic shift_out
);

logic[7:0] data, data_next;

always_ff @ (posedge clock) begin
  data <= data_next;
end

always_comb begin
  shift_out = data[7];
  data_out = data;

  data_next = data;
  if (load == 1'b1) begin
    data_next = data_in;
  end else if (shift == 1'b1) begin
    data_next = { data[6:0], shift_in };
  end
end

endmodule
