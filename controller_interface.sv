module controller_interface(
  input logic clock,
  input logic[5:0][7:0] usb_keycode,
  /* Input from bit 0 of 0x4016 */
  input logic strobe,
  /* If controller { a, b } has been read last cycle */
  input logic[1:0] shift,
  output logic[7:0] lower_reg,
  output logic[7:0] lower_reg_active,
  output logic[7:0] upper_reg,
  output logic[7:0] upper_reg_active
);

/* Shift registers with bit 0 being the next keypress to return */
logic[7:0] controller_a;
logic[7:0] controller_b;

assign lower_reg = { 5'bxxxxx, 2'b0, controller_a[0] };
assign lower_reg_active = { 5'b0, 3'b1 };
assign upper_reg = { 3'bxxx, 4'b0, controller_b[0] };
assign upper_reg_active = { 3'b0, 5'b1 };

logic[7:0] next_controller_a;
logic[7:0] next_controller_b;

always_ff @ (negedge clock) begin
  if (strobe == 1'b1) begin
    controller_a <= next_controller_a;
    controller_b <= next_controller_b;
  end else begin
    if (shift[0] == 1'b1) begin
      controller_a <= { 1'b1, controller_a[7:1] };
    end
    if (shift[1] == 1'b1) begin
      controller_b <= { 1'b1, controller_b[7:1] };
    end
  end
end

always_comb begin
  next_controller_a = 8'b0;
  next_controller_b = 8'b0;
  /* Horrendous code, yet I refuse to touch the NIOS II "c" compiler as it is
    the most finicky piece of shit I have ever used. Bugs of not following
    the c standard. Also can't easily be emulated. Has issues with bitwise
    operations. Also PIOs don't natively allow for byte-level read/writes.
    Although other Avalon devices do. */
  for (int i = 0; i < 6; ++i) begin
    /* Button A */
    if (usb_keycode[i] == 8'd10) begin
      next_controller_a |= 8'h1;
    end
    if (usb_keycode[i] == 8'd52) begin
      next_controller_b |= 8'h1;
    end
    /* Button B */
    if (usb_keycode[i] == 8'd9) begin
      next_controller_a |= 8'h2;
    end
    if (usb_keycode[i] == 8'd51) begin
      next_controller_b |= 8'h2;
    end
    /* Button Select */
    if (usb_keycode[i] == 8'd25) begin
      next_controller_a |= 8'h4;
    end
    /* Controller two originally had no select button on the Famicon */
    /*if (1'b0 != 1'b0) begin
      next_controller_b |= 8'h4;
    end*/
    /* Button Start */
    if (usb_keycode[i] == 8'd5) begin
      next_controller_a |= 8'h8;
    end
    /* Controller two originally had no start button on the Famicon */
    /*if (1'b0 != 1'b0) begin
      next_controller_b |= 8'h8;
    end*/
    /* Button Up */
    if (usb_keycode[i] == 8'd26) begin
      next_controller_a |= 8'h10;
    end
    if (usb_keycode[i] == 8'd82) begin
      next_controller_b |= 8'h10;
    end
    /* Button Down */
    if (usb_keycode[i] == 8'd22) begin
      next_controller_a |= 8'h20;
    end
    if (usb_keycode[i] == 8'd81) begin
      next_controller_b |= 8'h20;
    end
    /* Button Left */
    if (usb_keycode[i] == 8'd4) begin
      next_controller_a |= 8'h40;
    end
    if (usb_keycode[i] == 8'd80) begin
      next_controller_b |= 8'h40;
    end
    /* Button Right */
    if (usb_keycode[i] == 8'd7) begin
      next_controller_a |= 8'h80;
    end
    if (usb_keycode[i] == 8'd79) begin
      next_controller_b |= 8'h80;
    end
  end
end

endmodule
