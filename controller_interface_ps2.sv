module controller_interface_ps2(
  input logic clock,
  /* Using scan code set 2 (the usual) */
  input logic[7:0] ps2_keycode,
  input logic ps2_pressed,
  /* Input from bit 0 of 0x4016 */
  input logic strobe,
  /* If controller { a, b } has been read last cycle. Active low */
  input logic[1:0] shift,
  output logic[7:0] lower_reg,
  output logic[7:0] lower_reg_active,
  output logic[7:0] upper_reg,
  output logic[7:0] upper_reg_active,
  output logic[15:0] debug_red_leds
);

/* Shift registers with bit 0 being the next keypress to return */
logic[7:0] controller_a;
logic[7:0] controller_b;

logic[7:0] controller_a_saved;
logic[7:0] controller_b_saved;
logic[7:0] controller_a_saved_next;
logic[7:0] controller_b_saved_next;

assign debug_red_leds = { 8'h0, controller_a_saved };

assign lower_reg = { 5'bxxxxx, 2'b0, controller_a[0] };
assign lower_reg_active = { 5'b0, 3'b1 };
assign upper_reg = { 3'bxxx, 4'b0, controller_b[0] };
assign upper_reg_active = { 3'b0, 5'b1 };

always_ff @ (posedge clock) begin
  controller_a_saved <= controller_a_saved_next;
  controller_b_saved <= controller_b_saved_next;
  if (strobe == 1'b1) begin
    controller_a <= controller_a_saved;
    controller_b <= controller_b_saved;
  end else begin
    if (shift[0] == 1'b0) begin
      controller_a <= { 1'b1, controller_a[7:1] };
    end
    if (shift[1] == 1'b0) begin
      controller_b <= { 1'b1, controller_b[7:1] };
    end
  end
end

/* TODO extend the PS2 driver to support extended keycodes for the arrow keys,
  sigh... */
always_comb begin
  controller_a_saved_next = controller_a_saved;
  controller_b_saved_next = controller_b_saved;
  case (ps2_keycode)
    default: ;
    /* Button A */
    8'h34: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h1;
      else controller_a_saved_next &= ~8'h1;
    end
    8'h52: begin
      if (ps2_pressed) controller_b_saved_next |= 8'h1;
      else controller_b_saved_next &= ~8'h1;
    end
    /* Button B */
    8'h2b: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h2;
      else controller_a_saved_next &= ~8'h2;
    end
    8'h4c: begin
      if (ps2_pressed) controller_b_saved_next |= 8'h2;
      else controller_b_saved_next &= ~8'h2;
    end
    /* Button Select */
    8'h2a: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h4;
      else controller_a_saved_next &= ~8'h4;
    end
    /* Controller two originally had no select button on the Famicon */
    /*if (1'b0 != 1'b0) begin
      if (ps2_pressed) controller_b_saved_next |= 8'h4;
      else controller_b_saved_next &= ~8'h4;
    end*/
    /* Button Start */
    8'h32: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h8;
      else controller_a_saved_next &= ~8'h8;
    end
    /* Controller two originally had no start button on the Famicon */
    /*if (1'b0 != 1'b0) begin
      if (ps2_pressed) controller_b_saved_next |= 8'h8;
      else controller_b_saved_next &= ~8'h8;
    end*/
    /* Button Up */
    8'h1d: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h10;
      else controller_a_saved_next &= ~8'h10;
    end
    /*if (ps2_keycode == ) begin
      if (ps2_pressed) controller_b_saved_next |= 8'h10;
      else controller_b_saved_next &= ~8'h10;
    end*/
    /* Button Down */
    8'h1b: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h20;
      else controller_a_saved_next &= ~8'h20;
    end
    /*if (ps2_keycode == ) begin
      if (ps2_pressed) controller_b_saved_next |= 8'h20;
      else controller_b_saved_next &= ~8'h20;
    end*/
    /* Button Left */
    8'h1c: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h40;
      else controller_a_saved_next &= ~8'h40;
    end
    /*if (ps2_keycode == ) begin
      if (ps2_pressed) controller_b_saved_next |= 8'h40;
      else controller_b_saved_next &= ~8'h40;
    end*/
    /* Button Right */
    8'h23: begin
      if (ps2_pressed) controller_a_saved_next |= 8'h80;
      else controller_a_saved_next &= ~8'h80;
    end
    /*if (ps2_keycode == ) begin
      if (ps2_pressed) controller_b_saved_next |= 8'h80;
      else controller_b_saved_next &= ~8'h80;
    end*/
  endcase
end

endmodule
