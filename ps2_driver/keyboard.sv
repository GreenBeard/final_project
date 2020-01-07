module keyboard(
  input logic clock,
  input logic ps2_clock,
  input logic ps2_data_port,
  /* active low */
  input logic reset,
  output logic[7:0] ps2_keycode_out,
  output logic ps2_pressed
);

/* Only supports PS2 scan code set 2 */

/* PS2 data is passed bit by bit
  low, data[0:7] (yes lowest bit first), parity, high */
logic[10:0] ps2_data_in, ps2_data_in_next;
logic ps2_data_in_parity;
logic[7:0] ps2_keycode_last, ps2_keycode_last_next;
/* See outputs */
logic[7:0] ps2_keycode, ps2_keycode_next;
logic ps2_pressed_next;

const logic[10:0] ps2_data_reset = { 11'b00000000001 };

/* Approximately 2*50*1000*1000/(10*1000). This means clock must be 50 MHz */
const logic[15:0] reset_msg_count = 16'h4000;
logic[15:0] last_msg_counter, last_msg_counter_next;
logic reset_interface, reset_interface_next;

logic ps2_reset;
assign ps2_reset = reset & reset_interface;

always_comb begin
  if (last_msg_counter == reset_msg_count - 16'h1) begin
    reset_interface_next = 1'b0;
  end else begin
    reset_interface_next = 1'b1;
  end

  if (ps2_clock == 1'b0) begin
    last_msg_counter_next = 16'h0;
  end else begin
    if (last_msg_counter == reset_msg_count) begin
      last_msg_counter_next = last_msg_counter;
    end else begin
      last_msg_counter_next = last_msg_counter + 16'h1;
    end
  end
end

always_ff @ (negedge clock or negedge reset) begin
  if (reset == 1'b0) begin
    last_msg_counter <= 16'h0;
    reset_interface <= 1'b1;
  end else begin
    last_msg_counter <= last_msg_counter_next;
    reset_interface <= reset_interface_next;
  end
end

always_ff @ (negedge ps2_clock or negedge ps2_reset) begin
  if (reset == 1'b0) begin
    ps2_data_in <= ps2_data_reset;
    ps2_keycode_last <= 8'h0;
    ps2_keycode <= 8'h0;
    ps2_pressed <= 1'b0;
  end else begin
    ps2_data_in <= ps2_data_in_next;
    ps2_keycode_last <= ps2_keycode_last_next;
    ps2_keycode <= ps2_keycode_next;
    ps2_pressed <= ps2_pressed_next;
  end
end

integer i;
always_comb begin
  for (i = 0; i < 8; i = i + 1) begin
    ps2_keycode_out[i] = ps2_keycode[7 - i];
  end
end

always_comb begin
  ps2_keycode_next = ps2_keycode;
  ps2_pressed_next = ps2_pressed;

  ps2_data_in_parity = ~(^ ps2_data_in[8:1]);

  if (ps2_data_in[10] == 1'b1) begin
    ps2_data_in_next = ps2_data_reset;
    if (ps2_data_in[9] == 1'b0 && ps2_data_port == 1'b1
        && ps2_data_in[0] == ps2_data_in_parity) begin
      ps2_keycode_last_next = { ps2_data_in[8:1] };
    end else begin
      ps2_keycode_last_next = ps2_keycode_last;
    end

    /* The data is reversed and I don't know how to fix it */
    if (ps2_keycode_last == 8'h07) begin
      /* Unsupported extended keycode */
    end else if (ps2_keycode_last == 8'h0F) begin
      ps2_pressed_next = 1'b0;
      ps2_keycode_next = ps2_keycode_last_next;
    end else begin
      ps2_pressed_next = 1'b1;
      ps2_keycode_next = ps2_keycode_last_next;
    end
  end else begin
    ps2_data_in_next = { ps2_data_in[9:0], ps2_data_port };
    ps2_keycode_last_next = ps2_keycode_last;
  end
end

endmodule
