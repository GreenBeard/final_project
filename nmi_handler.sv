module nmi_handler(
  /* active low */
  input logic reset,
  input logic clock,
  input logic cpu_clock,
  input logic NMI,
  input logic clear,
  output logic NMI_saved
);

logic NMI_prev;
logic NMI_saved_next;

logic clear_saved;

always_ff @ (posedge clock) begin
  if (reset) begin
    NMI_prev <= NMI;
    NMI_saved <= NMI_saved_next;
  end else begin
    NMI_prev <= 1'b1;
    NMI_saved <= 1'b1;
  end
end

always_ff @ (posedge cpu_clock) begin
  clear_saved <= clear;
end

always_comb begin
  NMI_saved_next = ~((~clear_saved & ~NMI_saved) | (NMI_prev & ~NMI));
end

endmodule
