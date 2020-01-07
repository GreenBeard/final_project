module tristate #(parameter width=16) (
  input logic output_enable,
  input logic[width-1:0] data,
  inout wire[width-1:0] bus
);

assign bus = output_enable ? data : {width{ 1'bZ }};

/*always_comb begin
  if (output_enable) begin
    bus = data;
  end else begin
    bus = {width{ 1'bZ }};
  end
end*/

endmodule