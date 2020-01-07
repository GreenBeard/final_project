module processor_6502(
  input logic master_clock,
  /* active low */
  input logic reset,
  /* active high */
  input logic reset_clock,
  /* active low, non-maskable interrupt */
  input logic NMI,
  /* active low, maskable interrupt */
  input logic interrupt_request,

  output logic[15:0] memory_address,
  input logic[7:0] memory_data_in,
  output logic[7:0] memory_data_out,

  /* write is low, read is high */
  output logic read_write,
  /* Pin zero is used for controller strobe, low 3 bits of write to 0x4016 */
  output logic[2:0] controller_out,
  /* Low for the controller to write its data to the bus, high otherwise. */
  output logic[1:0] controller_oe,

  /* active low */
  output logic ppu_chip_select,

  /* We don't support audio out for now */
  /* output ???[1:0] audio_out, */
  output logic[15:0] debug_hexes,
  output logic[7:0] debug_green_leds,
  output logic cpu_clock
);
/* todo check controller reads signaltap $4016 https://wiki.nesdev.com/w/index.php/Standard_controller
otherwise load a simple test cartridge */
logic[2:0] controller_out_next;

/* Program counter */
logic[15:0] PC /* verilator public */, PC_next;
/* Accumulator */
logic[7:0] reg_a /* verilator public */, reg_a_next;
/* Index register X */
logic[7:0] reg_x /* verilator public */, reg_x_next;
/* Index register Y */
logic[7:0] reg_y /* verilator public */, reg_y_next;
/* NVDIZC, on stack it is NV-BDIZC, - is 1 */
logic[5:0] reg_status /* verilator public */, reg_status_next;
/* Stack pointer (0x01FF down to 0x0100) */
logic[7:0] reg_stack /* verilator public */, reg_stack_next;

logic[7:0] partial_ir, partial_ir_next; /* The IR is fetched bit by bit, and
  handled as needed */
logic[7:0] reg_extra, reg_extra_next; /* Used with partial_ir for absolute
  indexing */
logic[7:0] reg_third, reg_third_next; /* Used for read, modify, write
  instructions. The INC, DEC, and shift/rotate instructions. */

/* 1'b1 if the active BR instruction matches the status register, 1'b0
  otherwise, either if not in BR instruction. */
logic branch_active, branch_active_next;

/* 1'b1 to add, 1'b0 to not */
logic add_index_slow, add_index_slow_next;

enum logic[7:0] {
  reset_0, reset_1,

  fetch,
  fetch_two_and_decode,

  oam_state_read, oam_state_write,

  or_operation,
  and_operation,
  xor_operation,
  /* add, and sub with carry */
  add_operation,
  sub_operation,
  cmp_a_operation,
  cmp_x_operation,
  cmp_y_operation,
  load_a_operation,
  load_x_operation,
  load_y_operation,
  shift_left_0, shift_left_1, shift_left_2,
  shift_right_0, shift_right_1, shift_right_2,
  rotate_left_0, rotate_left_1, rotate_left_2,
  rotate_right_0, rotate_right_1, rotate_right_2,
  dec_0, dec_1, dec_2,
  inc_0, inc_1, inc_2,
  shift_left_accum,
  rotate_left_accum,
  shift_right_accum,
  rotate_right_accum,
  store_a_operation,
  store_x_operation,
  store_y_operation,

  /* As in the BIT instruction */
  bit_operation,

  break_0, break_1, break_2, break_3, break_4,

  jsr_0, jsr_1, jsr_2, jsr_3,
  rti_0, rti_1, rti_2, rti_3,
  ret_0, ret_1, ret_2, ret_3,

  branch_0, branch_1,

  push_status,
  pull_status_0, pull_status_1,
  push_accum,
  pull_accum_0, pull_accum_1,

  clear_carry, set_carry,
  clear_interrupt, set_interrupt,
  clear_overflow,
  clear_decimal, set_decimal,

  transfer_xa, transfer_ax,
  transfer_xs, transfer_sx,
  transfer_ya, transfer_ay,

  dec_x, dec_y,
  inc_x, inc_y,

  jmp_abs_0,
  jmp_indirect_0, jmp_indirect_1, jmp_indirect_2,

  /* Addressing modes */
  abs_index_0, abs_index_1,
  address_abs_index_0,
  abs_index_x_0, abs_index_x_1, abs_index_x_2,
  abs_index_y_0, abs_index_y_1, abs_index_y_2,
  address_abs_index_slow_x_0, address_abs_index_slow_x_1,
  address_abs_index_slow_y_0, address_abs_index_slow_y_1,

  zero_page_0,
  zero_page_x_0, zero_page_x_1,
  address_zero_page_x_0,
  zero_page_y_0, zero_page_y_1,
  address_zero_page_y_0,

  indirect_index_x_0, indirect_index_x_1, indirect_index_x_2,
    indirect_index_x_3,
  address_indirect_index_x_0, address_indirect_index_x_1,
    address_indirect_index_x_2,
  indirect_index_y_0, indirect_index_y_1, indirect_index_y_2,
    indirect_index_y_3,
  address_indirect_index_slow_y_0, address_indirect_index_slow_y_1,
    address_indirect_index_slow_y_2,
  /* Used to stop if games use unimplemented instructions */
  halted = 8'hFF,
  state_dont_care = 8'hx
} state /* syn_encoding = "compact" */ /* verilator public */, next_state,
  continue_state, continue_state_next;

`ifdef MODEL_TECH
`else
initial state = halted;
`endif

enum logic[1:0] {
  interrupt_inactive,
  interrupt_NMI,
  interrupt_IRQ,
  interrupt_BRK
} interrupt_status, interrupt_status_next;

logic nmi_request;
logic nmi_request_clear;
nmi_handler nmi_handler_inst(.clock(master_clock), .cpu_clock(cpu_clock),
  .reset(reset), .NMI(NMI),
  .NMI_saved(nmi_request), .clear(nmi_request_clear));

logic[15:0] PC_incr;
incrementer_16_bit pc_incrementer(.in(PC), .out(PC_incr));

clock_divider #(.divisor(12)) master_to_cpu(.reset(reset_clock), .in_clk(master_clock), .out_clk(cpu_clock));

enum logic[2:0] {
  alu_mode_or = 3'b000,
  alu_mode_and = 3'b001,
  alu_mode_xor = 3'b010,
  alu_mode_add = 3'b011,
  alu_mode_shift_l = 3'b100,
  alu_mode_shift_r = 3'b101,
  alu_dont_care = 3'bxxx
} alu_mode /* verilator isolate_assignments */;
logic[8:0] alu_input_a /* verilator isolate_assignments */;
logic[8:0] alu_input_b /* verilator isolate_assignments */;
logic[8:0] alu_output /* verilator isolate_assignments */;
alu_6502 alu(.mode(alu_mode), .input_a(alu_input_a), .input_b(alu_input_b),
  .result(alu_output));

logic[8:0] inverter_input /* verilator isolate_assignments */;
logic[8:0] inverter_output;
inverter_9_bit inverter_inst(.in(inverter_input), .out(inverter_output));

/* Calculates NVZC (in that order) */
logic[3:0] alu_status /* verilator isolate_assignments */;
status_calc status_calc(.result(alu_output),
  .input_a_high(alu_input_a[7]),
  .input_b_high(alu_input_b[7]),
  .out({ alu_status[3:0] }));

logic[7:0] oam_counter, oam_counter_next;

always_ff @ (posedge cpu_clock) begin
  if (reset == 1'b1) begin
    PC <= PC_next;
    reg_a <= reg_a_next;
    reg_x <= reg_x_next;
    reg_y <= reg_y_next;
    reg_status <= reg_status_next;
    reg_stack <= reg_stack_next;
    reg_extra <= reg_extra_next;
    partial_ir <= partial_ir_next;
    reg_third <= reg_third_next;
    interrupt_status <= interrupt_status_next;
    branch_active <= branch_active_next;
    add_index_slow <= add_index_slow_next;
    state <= next_state;
    continue_state <= continue_state_next;
    controller_out <= controller_out_next;
    oam_counter <= oam_counter_next;
  end else begin
    /* This is required as it jumps to the address in 0xFFFD, 0xFFFC */
    state <= reset_0;

    /*PC <= 16'h0000;
    //reg_status <= reg_status | 6'b000100;
    state <= fetch;
    PC <= 16'hC000;*/

    /* In order to help the unfortunate don't care model */
    reg_status <= 6'b000100;
    reg_a <= 8'b0;
    reg_x <= 8'b0;
    reg_y <= 8'b0;
    reg_stack <= 8'hFD;
    reg_extra <= 8'b0;
    interrupt_status <= interrupt_inactive;

    controller_out <= 3'b0;
    oam_counter <= 8'hx;
  end
end

always_comb begin
  /* TODO remove once more of the CPU is complete, read_write must always be specified */
  read_write = 1'b1;

  memory_address = 16'hx;
  alu_input_a = 9'bx;
  alu_input_b = 9'bx;
  alu_mode = alu_dont_care;
  inverter_input = 9'bx;
  memory_data_out = 8'hx;
  next_state = state_dont_care;
  continue_state_next = continue_state;

  debug_hexes = PC;
  debug_green_leds = partial_ir;
  nmi_request_clear = 1'b0;

  PC_next = PC;
  reg_a_next = reg_a;
  reg_x_next = reg_x;
  reg_y_next = reg_y;
  reg_status_next = reg_status;
  reg_stack_next = reg_stack;
  partial_ir_next = partial_ir;
  reg_third_next = reg_third;
  reg_extra_next = reg_extra;
  interrupt_status_next = interrupt_status;
  branch_active_next = branch_active;
  add_index_slow_next = 1'bx;

  case (state)
    default: ;
    halted: begin
      /* To keep from overwriting random data */
      read_write = 1'b1;
    end
    fetch_two_and_decode: begin
      read_write = 1'b1;
      memory_address = PC;
      if (partial_ir[3:0] == 4'h8 || partial_ir[3:0] == 4'hA
          || partial_ir == 8'h00 || partial_ir == 8'h40
          || partial_ir == 8'h60) begin
        /* Added for readability, not needed */
        PC_next = PC;
      end else begin
        PC_next = PC_incr;
      end
      partial_ir_next = memory_data_in;
      reg_extra_next = 8'h0;
    end
    or_operation: begin
      alu_mode = alu_mode_or;
      alu_input_a = { 1'bx, partial_ir };
      alu_input_b = { 1'bx, reg_a };
      reg_a_next = alu_output[7:0];
      reg_status_next = reg_status & ~6'b100010
        | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
    end
    and_operation: begin
      alu_mode = alu_mode_and;
      alu_input_a = { 1'bx, partial_ir };
      alu_input_b = { 1'bx, reg_a };
      reg_a_next = alu_output[7:0];
      reg_status_next = reg_status & ~6'b100010
        | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
    end
    xor_operation: begin
      alu_mode = alu_mode_xor;
      alu_input_a = { 1'bx, partial_ir };
      alu_input_b = { 1'bx, reg_a };
      reg_a_next = alu_output[7:0];
      reg_status_next = reg_status & ~6'b100010
        | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
    end
    add_operation: begin
      alu_mode = alu_mode_add;
      alu_input_a = { reg_status[0], partial_ir };
      alu_input_b = { 1'bx, reg_a };
      reg_a_next = alu_output[7:0];
      reg_status_next = reg_status & ~6'b110011
        | { alu_status[3:2], 2'b0, alu_status[1:0] };
    end
    sub_operation: begin
      alu_mode = alu_mode_add;
      inverter_input = { ~reg_status[0], partial_ir };
      alu_input_a = inverter_output;
      alu_input_b = { 1'bx, reg_a };
      reg_a_next = alu_output[7:0];
      // TODO fix overflow flag?
      reg_status_next = reg_status & ~6'b110011
        | { alu_status[3:2], 2'b0, alu_status[1:0] };
    end
    load_a_operation: begin
      alu_mode = alu_mode_or;
      alu_input_a = { 1'bx, partial_ir };
      alu_input_b = { 1'bx, 8'h00 };
      reg_a_next = alu_output[7:0];
      reg_status_next = reg_status & ~6'b100010
        | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
    end
    load_x_operation: begin
      alu_mode = alu_mode_or;
      alu_input_a = { 1'bx, partial_ir };
      alu_input_b = { 1'bx, 8'h00 };
      reg_x_next = alu_output[7:0];
      reg_status_next = reg_status & ~6'b100010
        | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
    end
    load_y_operation: begin
      alu_mode = alu_mode_or;
      alu_input_a = { 1'bx, partial_ir };
      alu_input_b = { 1'bx, 8'h00 };
      reg_y_next = alu_output[7:0];
      reg_status_next = reg_status & ~6'b100010
        | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
    end
    bit_operation: begin
      alu_mode = alu_mode_and;
      alu_input_a = { 1'bx, partial_ir };
      alu_input_b = { 1'bx, reg_a };
      reg_status_next = reg_status & ~6'b110010
        | { partial_ir[7:6], 2'b0, alu_status[1], 1'b0 };
    end
  endcase

  if (state == cmp_a_operation) begin
    alu_input_b = { 1'bx, reg_a };
  end
  if (state == cmp_x_operation) begin
    alu_input_b = { 1'bx, reg_x };
  end
  if (state == cmp_y_operation) begin
    alu_input_b = { 1'bx, reg_y };
  end
  if (state == cmp_a_operation || state == cmp_x_operation
      || state == cmp_y_operation) begin
    alu_mode = alu_mode_add;
    inverter_input = { 1'b0, partial_ir };
    alu_input_a = inverter_output;
    reg_status_next = reg_status & ~6'b100011
      | { alu_status[3], 3'b0, alu_status[1:0] };
  end

  /* Increment, and decrement */
  if (state == dec_0 || state == inc_0) begin
    /* See shift, and rotate instructions */
  end
  if (state == dec_1) begin
    alu_input_b = { 1'bx, 8'hFF };
  end
  if (state == inc_1) begin
    alu_input_b = { 1'bx, 8'h01 };
  end
  if (state == dec_1 || state == inc_1) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_third };
    reg_third_next = alu_output[7:0];
    reg_status_next = reg_status & ~6'b100010
      | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
  end
  if (state == dec_2 || state == inc_2) begin
    /* See shift, and rotate instructions */
  end
  /* End of increment, and decrement */

  /* Shift, and rotate left, and right */
  if (state == shift_left_0 || state == rotate_left_0
      || state == shift_right_0 || state == rotate_right_0
      || state == dec_0 || state == inc_0) begin
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    reg_third_next = memory_data_in;
  end
  if (state == shift_right_1 || state == shift_left_1) begin
    alu_input_a = { 1'b0, reg_third };
  end
  if (state == rotate_left_1 || state == rotate_right_1) begin
    alu_input_a = { reg_status[0], reg_third };
  end
  if (state == shift_right_accum || state == shift_left_accum) begin
    alu_input_a = { 1'b0, reg_a };
  end
  if (state == rotate_left_accum || state == rotate_right_accum) begin
    alu_input_a = { reg_status[0], reg_a };
  end
  if (state == shift_left_1 || state == rotate_left_1
      || state == shift_left_accum || state == rotate_left_accum) begin
    alu_mode = alu_mode_shift_l;
  end
  if (state == shift_right_1 || state == rotate_right_1
      || state == shift_right_accum || state == rotate_right_accum) begin
    alu_mode = alu_mode_shift_r;
  end
  if (state == shift_right_1 || state == rotate_right_1
      || state == shift_left_1 || state == rotate_left_1) begin
    reg_third_next = alu_output[7:0];
  end
  if (state == shift_left_accum || state == shift_right_accum
      || state == rotate_left_accum || state == rotate_right_accum) begin
    reg_a_next = alu_output[7:0];
  end
  if (state == shift_left_1 || state == rotate_left_1
      || state == shift_right_1 || state == rotate_right_1
      || state == shift_left_accum || state == shift_right_accum
      || state == rotate_left_accum || state == rotate_right_accum) begin
    reg_status_next = reg_status & ~6'b100011
      | { alu_status[3], 3'b0, alu_status[1:0] };
  end
  if (state == shift_left_1 || state == rotate_left_1
      || state == shift_right_1 || state == rotate_right_1
      || state == dec_1 || state == inc_1
      || state == shift_left_2 || state == rotate_left_2
      || state == shift_right_2 || state == rotate_right_2
      || state == dec_2 || state == inc_2) begin
    read_write = 1'b0;
    memory_address = { reg_extra, partial_ir };
    memory_data_out = reg_third;
  end
  /* End shift, and rotate logic */

  if (state == push_status) begin
    memory_data_out = { reg_status[5:4], 2'b11, reg_status[3:0] };
  end
  if (state == push_accum) begin
    memory_data_out = reg_a;
  end
  if (state == push_status || state == push_accum) begin
    read_write = 1'b0;
    memory_address = { 8'h01, reg_stack };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_stack };
    alu_input_b = { 1'bx, 8'hFF };
    reg_stack_next = alu_output[7:0];
  end

  if (state == pull_status_0 || state == pull_accum_0) begin
    read_write = 1'b1;
    memory_address = { 8'h01, reg_stack };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_stack };
    alu_input_b = { 1'bx, 8'h1 };
    reg_stack_next = alu_output[7:0];
  end
  if (state == pull_status_1 || state == pull_accum_1) begin
    read_write = 1'b1;
    memory_address = { 8'h01, reg_stack };
  end
  if (state == pull_status_1) begin
    reg_status_next = { memory_data_in[7:6], memory_data_in[3:0] };
  end
  if (state == pull_accum_1) begin
    reg_a_next = memory_data_in;
    alu_mode = alu_mode_or;
    alu_input_a = { 1'bx, memory_data_in };
    alu_input_b = { 1'bx, 8'h00 };
    reg_status_next = reg_status & ~6'b100010
      | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
  end

  if (state == clear_carry) begin
    reg_status_next = reg_status & ~6'b000001;
  end
  if (state == set_carry) begin
    reg_status_next = reg_status | 6'b000001;
  end
  if (state == clear_interrupt) begin
    reg_status_next = reg_status & ~6'b000100;
  end
  if (state == set_interrupt) begin
    reg_status_next = reg_status | 6'b000100;
  end
  if (state == clear_overflow) begin
    reg_status_next = reg_status & ~6'b010000;
  end
  if (state == clear_decimal) begin
    reg_status_next = reg_status & ~6'b001000;
  end
  if (state == set_decimal) begin
    reg_status_next = reg_status | 6'b001000;
  end

  if (state == store_a_operation
      || state == store_x_operation
      || state == store_y_operation) begin
    memory_address = { reg_extra, partial_ir };
  end
  if (state == store_a_operation) begin
    read_write = 1'b0;
    memory_data_out = reg_a;
  end
  if (state == store_x_operation) begin
    read_write = 1'b0;
    memory_data_out = reg_x;
  end
  if (state == store_y_operation) begin
    read_write = 1'b0;
    memory_data_out = reg_y;
  end

  if (state == transfer_xa) begin
    reg_a_next = reg_x;
    alu_input_a = { 1'bx, reg_x };
  end
  if (state == transfer_ax) begin
    reg_x_next = reg_a;
    alu_input_a = { 1'bx, reg_a };
  end
  if (state == transfer_xs) begin
    reg_stack_next = reg_x;
    /* TXS does not modify flags */
  end
  if (state == transfer_sx) begin
    reg_x_next = reg_stack;
    alu_input_a = { 1'bx, reg_stack };
  end
  if (state == transfer_ay) begin
    reg_y_next = reg_a;
    alu_input_a = { 1'bx, reg_a };
  end
  if (state == transfer_ya) begin
    reg_a_next = reg_y;
    alu_input_a = { 1'bx, reg_y };
  end
  if (state == transfer_xa
      || state == transfer_ax
      /* TXS does not modify flags */
      || state == transfer_sx
      || state == transfer_ay
      || state == transfer_ya) begin
    alu_mode = alu_mode_or;
    alu_input_b = { 1'bx, 8'h00 };
    reg_status_next = reg_status & ~6'b100010
      | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
  end

  if (state == dec_x) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_x };
    alu_input_b = { 1'bx, 8'hFF };
    reg_x_next = alu_output[7:0];
    reg_status_next = reg_status & ~6'b100010
      | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
  end
  if (state == dec_y) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_y };
    alu_input_b = { 1'bx, 8'hFF };
    reg_y_next = alu_output[7:0];
    reg_status_next = reg_status & ~6'b100010
      | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
  end
  if (state == inc_x) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_x };
    alu_input_b = { 1'bx, 8'h01 };
    reg_x_next = alu_output[7:0];
    reg_status_next = reg_status & ~6'b100010
      | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
  end
  if (state == inc_y) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_y };
    alu_input_b = { 1'bx, 8'h01 };
    reg_y_next = alu_output[7:0];
    reg_status_next = reg_status & ~6'b100010
      | { alu_status[3], 3'b0, alu_status[1], 1'b0 };
  end

  if (state == jmp_abs_0) begin
    read_write = 1'b1;
    memory_address = PC;
    PC_next = { memory_data_in, partial_ir };
  end

  if (state == jmp_indirect_0) begin
    read_write = 1'b1;
    memory_address = PC;
    /* Allow for optimizations */
    PC_next = 16'hx;
    reg_extra_next = memory_data_in;
  end
  if (state == jmp_indirect_1) begin
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    PC_next = { 8'hx, memory_data_in };
    alu_mode = alu_mode_add;
    /* Yes, it doesn't properly handle the upper bits ever */
    alu_input_a = { 1'b0, partial_ir };
    alu_input_b = { 1'bx, 8'h1 };
    partial_ir_next = alu_output[7:0];
  end
  if (state == jmp_indirect_2) begin
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    PC_next = { memory_data_in, PC[7:0] };
  end

  if (state == abs_index_0 || state == address_abs_index_0) begin
    /* Absolute indexing step 1 */
    read_write = 1'b1;
    memory_address = PC;
    PC_next = PC_incr;
    reg_extra_next = memory_data_in;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    alu_input_b = { 1'bx, 8'b0 };
    partial_ir_next = alu_output[7:0];
  end
  if (state == abs_index_1) begin
    /* Absolute indexing step 2 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    partial_ir_next = memory_data_in;
  end


  /* Absolute indexing with X, or Y */
  if (state == abs_index_x_0 || state == address_abs_index_slow_x_0) begin
    /* Absolute indexing with X step 1 */
    alu_input_b = { 1'bx, reg_x };
  end
  if (state == abs_index_y_0 || state == address_abs_index_slow_y_0) begin
    /* Absolute indexing with Y step 1 */
    alu_input_b = { 1'bx, reg_y };
  end

  /* Fast indexing version step 1, and step 2 */
  if (state == abs_index_x_0 || state == abs_index_y_0) begin
    /* Absolute indexing with X, or Y step 1 */
    read_write = 1'b1;
    memory_address = PC;
    PC_next = PC_incr;
    reg_extra_next = memory_data_in;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    partial_ir_next = alu_output[7:0];
    /* next_state depends upon alu_output[8] */
  end
  if (state == abs_index_x_1 || state == abs_index_y_1) begin
    /* Absolute indexing with X, or Y step 2 (only runs if necessary) */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_extra };
    alu_input_b = { 1'bx, 8'b1 };
    reg_extra_next = alu_output[7:0];
  end

  /* Slow version of absolute indexing */
  if (state == address_abs_index_slow_x_0
      || state == address_abs_index_slow_y_0) begin
    /* Slow absolute indexing with X, or Y step 1 */
    read_write = 1'b1;
    memory_address = PC;
    PC_next = PC_incr;
    reg_extra_next = memory_data_in;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    partial_ir_next = alu_output[7:0];
    add_index_slow_next = alu_output[8];
  end
  if (state == address_abs_index_slow_x_1
      || state == address_abs_index_slow_y_1) begin
    /* Slow absolute indexing with X, or Y step 2 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_extra };
    alu_input_b = { 1'bx, 7'b0, add_index_slow };
    reg_extra_next = alu_output[7:0];
  end

  if (state == abs_index_x_2 || state == abs_index_y_2) begin
    /* Absolute indexing with X, or Y step 3 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    partial_ir_next = memory_data_in;
  end
  /* End of absolute indexing with X, and Y */

  if (state == zero_page_0) begin
    /* Zero page absolute step 1 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    partial_ir_next = memory_data_in;
  end

  if (state == zero_page_x_0 || state == address_zero_page_x_0) begin
    /* Zero page indexing with X step 1 */
    alu_input_b = { 1'bx, reg_x };
  end
  if (state == zero_page_y_0 || state == address_zero_page_y_0) begin
    /* Zero page indexing with Y step 1 */
    alu_input_b = { 1'bx, reg_y };
  end
  if (state == zero_page_x_0 || state == zero_page_y_0
      || state == address_zero_page_x_0 || state == address_zero_page_y_0) begin
    /* Zero page indexing with X, or Y step 1 */
    read_write = 1'b1;
    /* TODO May technically fetch from PC */
    memory_address = { reg_extra, partial_ir };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    partial_ir_next = alu_output[7:0];
    reg_extra_next = 8'h0;
  end
  if (state == zero_page_x_1 || state == zero_page_y_1) begin
    /* Zero page indexing with X, or Y step 2 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    partial_ir_next = memory_data_in;
  end

  /* ($LL,X) */
  if (state == indirect_index_x_0
      || state == address_indirect_index_x_0) begin
    /* Indirect page indexing with X step 1 */
    read_write = 1'b1;
    /* May technically fetch from PC */
    memory_address = { reg_extra, partial_ir };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    alu_input_b = { 1'bx, reg_x };
    partial_ir_next = alu_output[7:0];
  end
  if (state == indirect_index_x_1
      || state == address_indirect_index_x_1) begin
    /* Indirect page indexing with X step 2 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    alu_input_b = { 1'bx, 8'b1 };
    reg_extra_next = alu_output[7:0];
    partial_ir_next = memory_data_in;
  end
  if (state == indirect_index_x_2
      || state == address_indirect_index_x_2) begin
    /* Indirect page indexing with X step 3 */
    read_write = 1'b1;
    memory_address = { 8'h0, reg_extra };
    reg_extra_next = memory_data_in;
  end
  if (state == indirect_index_x_3) begin
    /* Indirect page indexing with X step 4 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    partial_ir_next = memory_data_in;
  end

  /* Start of indirect index y addressing */
  /* ($LL), Y */
  if (state == indirect_index_y_0
      || state == address_indirect_index_slow_y_0) begin
    /* Indirect page indexing with Y step 1 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    reg_third_next = memory_data_in;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    alu_input_b = { 1'bx, 8'b1 };
    partial_ir_next = alu_output[7:0];
  end

  /* Fast indirect index steps 2, and 3 */
  if (state == indirect_index_y_1) begin
    /* Indirect page indexing with Y step 2 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    reg_extra_next = memory_data_in;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_third };
    alu_input_b = { 1'bx, reg_y };
    partial_ir_next = alu_output[7:0];
    /* next_state is dependent upon alu_output[8] */
  end
  if (state == indirect_index_y_2) begin
    /* Indirect page indexing with Y step 3 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_extra };
    alu_input_b = { 1'bx, 8'b1 };
    reg_extra_next = alu_output[7:0];
  end

  /* Slow indirect index steps 2, and 3 */
  if (state == address_indirect_index_slow_y_1) begin
    /* Indirect page indexing with Y step 2 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    reg_extra_next = memory_data_in;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_third };
    alu_input_b = { 1'bx, reg_y };
    partial_ir_next = alu_output[7:0];
    add_index_slow_next = alu_output[8];
  end
  if (state == address_indirect_index_slow_y_2) begin
    /* Indirect page indexing with Y step 3 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_extra };
    alu_input_b = { 1'bx, 7'b0, add_index_slow };
    reg_extra_next = alu_output[7:0];
  end

  if (state == indirect_index_y_3) begin
    /* Indirect page indexing with Y step 4 */
    read_write = 1'b1;
    memory_address = { reg_extra, partial_ir };
    partial_ir_next = memory_data_in;
  end
  /* End of indirect index y addressing */

  if (state == branch_0) begin
    /* Relative access (only used for branching) step 1 */
    read_write = 1'b1;
    memory_address = PC;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, partial_ir };
    alu_input_b = { 1'bx, PC[7:0] };
    partial_ir_next = memory_data_in;
	 reg_extra_next = partial_ir;
    /* next_state depends upon alu_output[8] */
    if (branch_active == 1'b0) begin
      PC_next = PC_incr;
      next_state = fetch_two_and_decode;
    end else begin
      PC_next = { PC[15:8], alu_output[7:0] };
      /* Over, or underflow as branch offsets are signed */
      if (alu_output[8] == 1'b1 && partial_ir[7] == 1'b0
          || alu_output[8] == 1'b0 && partial_ir[7] == 1'b1) begin
        next_state = branch_1;
      end else begin
        next_state = fetch;
      end
    end
  end
  if (state == branch_1) begin
    /* Relative access step 2 */
    read_write = 1'b1;
    memory_address = PC;
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_extra[7] == 1'b1 ? 8'hFF : 8'h1 };
    alu_input_b = { 1'bx, PC[15:8] };
    assert(branch_active);
    PC_next = { alu_output[7:0], PC[7:0] };
    partial_ir_next = memory_data_in;
    next_state = fetch;
  end

  if (state == reset_0) begin
    read_write = 1'b1;
    memory_address = 16'hFFFC;
    PC_next = { 8'hx, memory_data_in };
  end
  if (state == reset_1) begin
    read_write = 1'b1;
    memory_address = 16'hFFFD;
    PC_next = { memory_data_in, PC[7:0] };
  end

  /* break instruction start */
  if (state == break_0 || state == break_1 || state == break_2) begin
    read_write = 1'b0;
    memory_address = { 8'h01, reg_stack };
    alu_input_a = { 1'b0, reg_stack };
    alu_input_b = { 1'bx, 8'hFF };
    alu_mode = alu_mode_add;
    reg_stack_next = alu_output[7:0];
  end
  if (state == break_0) begin
    memory_data_out = PC[15:8];
  end
  if (state == break_1) begin
    memory_data_out = PC[7:0];
    if (nmi_request == 1'b0) begin
      interrupt_status_next = interrupt_NMI;
    end else if (interrupt_request == 1'b0) begin
      interrupt_status_next = interrupt_IRQ;
    end else begin
      interrupt_status_next = interrupt_BRK;
    end
    nmi_request_clear = 1'b1;
  end
  if (state == break_2) begin
    memory_data_out = { reg_status[5:4], 1'b1,
      interrupt_status == interrupt_BRK, reg_status[3:0] };
  end
  if (state == break_3) begin
    read_write = 1'b1;
    PC_next = { 8'hx, memory_data_in };
    if (interrupt_status == interrupt_NMI) begin
      memory_address = 16'hFFFA;
    end else begin
      /* set interrupt disable flag */
      reg_status_next = reg_status & 6'b000100;
      memory_address = 16'hFFFE;
    end
  end
  if (state == break_4) begin
    read_write = 1'b1;
    memory_address = interrupt_status == interrupt_NMI ? 16'hFFFB : 16'hFFFF;
    PC_next = { memory_data_in, PC[7:0] };
  end
  /* break instruction end */

  if (state == jsr_0 || state == jsr_1 || state == jsr_2) begin
    memory_address = { 8'h01, reg_stack };
  end
  if (state == jsr_1 || state == jsr_2) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_stack };
    alu_input_b = { 1'bx, 8'hFF };
    reg_stack_next = alu_output[7:0];
  end
  if (state == jsr_0) begin
    /* Basically do nothing */
    read_write = 1'b1;
  end
  if (state == jsr_1) begin
    read_write = 1'b0;
    memory_data_out = PC[15:8];
  end
  if (state == jsr_2) begin
    read_write = 1'b0;
    memory_data_out = PC[7:0];
  end
  if (state == jsr_3) begin
    read_write = 1'b1;
    memory_address = PC;
    PC_next = { memory_data_in, partial_ir };
  end

  if (state == rti_0 || state == rti_1 || state == rti_2
      || state == rti_3) begin
    read_write = 1'b1;
    memory_address = { 8'h01, reg_stack };
  end
  if (state == rti_0 || state == rti_1 || state == rti_2) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_stack };
    alu_input_b = { 1'bx, 8'h01 };
    reg_stack_next = alu_output[7:0];
  end
  if (state == rti_1) begin
    reg_status_next = { memory_data_in[7:6], memory_data_in[3:0] };
  end
  if (state == rti_2) begin
    PC_next = { 8'hx, memory_data_in };
  end
  if (state == rti_3) begin
    PC_next = { memory_data_in, PC[7:0] };
  end

  if (state == ret_0 || state == ret_1 || state == ret_2) begin
    read_write = 1'b1;
    memory_address = { 8'h01, reg_stack };
  end
  if (state == ret_0 || state == ret_1) begin
    alu_mode = alu_mode_add;
    alu_input_a = { 1'b0, reg_stack };
    alu_input_b = { 1'bx, 8'h01 };
    reg_stack_next = alu_output[7:0];
  end
  if (state == ret_1) begin
    PC_next = { 8'hx, memory_data_in };
  end
  if (state == ret_2) begin
    PC_next = { memory_data_in, PC[7:0] };
  end
  if (state == ret_3) begin
    read_write = 1'b1;
    memory_address = PC;
    PC_next = PC_incr;
  end

  controller_out_next = controller_out;
  controller_oe = { 1'b1, 1'b1 };
  if (memory_address == 16'h4016 && read_write == 1'b0) begin
    controller_out_next = memory_data_out[2:0];
  end
  if (memory_address == 16'h4016 && read_write == 1'b1) begin
    controller_oe = { 1'b1, 1'b0 };
  end
  if (memory_address == 16'h4017 && read_write == 1'b1) begin
    controller_oe = { 1'b0, 1'b1 };
  end

  if (memory_address[15:13] == 3'b001) begin
    ppu_chip_select = 1'b0;
  end else begin
    ppu_chip_select = 1'b1;
  end

  case (state)
    default: ;
    halted: begin
      /* This isn't supposed to happen */
      next_state = halted;
    end
    fetch: begin
      next_state = fetch_two_and_decode;
    end
    fetch_two_and_decode: begin
      continue_state_next = state_dont_care;
      case (partial_ir)
        /* Pattern is 00, 20, ..., 10, 30, ..., 01, 21, ... */
        8'h00: next_state = break_0;
        8'h20: next_state = jsr_0;
        8'h40: next_state = rti_0;
        8'h60: next_state = ret_0;
        /*8'h80: next_state = ;*/
        8'hA0: next_state = load_y_operation;
        8'hC0: next_state = cmp_y_operation;
        8'hE0: next_state = cmp_x_operation;
        8'h10: begin
          next_state = branch_0;
          branch_active_next = ~reg_status[5];
        end
        8'h30: begin
          next_state = branch_0;
          branch_active_next = reg_status[5];
        end
        8'h50: begin
          next_state = branch_0;
          branch_active_next = ~reg_status[4];
        end
        8'h70: begin
          next_state = branch_0;
          branch_active_next = reg_status[4];
        end
        8'h90: begin
          next_state = branch_0;
          branch_active_next = ~reg_status[0];
        end
        8'hB0: begin
          next_state = branch_0;
          branch_active_next = reg_status[0];
        end
        8'hD0: begin
          next_state = branch_0;
          branch_active_next = ~reg_status[1];
        end
        8'hF0: begin
          next_state = branch_0;
          branch_active_next = reg_status[1];
        end

        8'h01: begin
          next_state = indirect_index_x_0;
          continue_state_next = or_operation;
        end
        8'h21: begin
          next_state = indirect_index_x_0;
          continue_state_next = and_operation;
        end
        8'h41: begin
          next_state = indirect_index_x_0;
          continue_state_next = xor_operation;
        end
        8'h61: begin
          next_state = indirect_index_x_0;
          continue_state_next = add_operation;
        end
        8'h81: begin
          next_state = address_indirect_index_x_0;
          continue_state_next = store_a_operation;
        end
        8'hA1: begin
          next_state = indirect_index_x_0;
          continue_state_next = load_a_operation;
        end
        8'hC1: begin
          next_state = indirect_index_x_0;
          continue_state_next = cmp_a_operation;
        end
        8'hE1: begin
          next_state = indirect_index_x_0;
          continue_state_next = sub_operation;
        end
        8'h11: begin
          next_state = indirect_index_y_0;
          continue_state_next = or_operation;
        end
        8'h31: begin
          next_state = indirect_index_y_0;
          continue_state_next = and_operation;
        end
        8'h51: begin
          next_state = indirect_index_y_0;
          continue_state_next = xor_operation;
        end
        8'h71: begin
          next_state = indirect_index_y_0;
          continue_state_next = add_operation;
        end
        8'h91: begin
          next_state = address_indirect_index_slow_y_0;
          continue_state_next = store_a_operation;
        end
        8'hB1: begin
          next_state = indirect_index_y_0;
          continue_state_next = load_a_operation;
        end
        8'hD1: begin
          next_state = indirect_index_y_0;
          continue_state_next = cmp_a_operation;
        end
        8'hF1: begin
          next_state = indirect_index_y_0;
          continue_state_next = sub_operation;
        end

        /*8'h02: next_state = ;
        8'h22: next_state = ;
        8'h42: next_state = ;
        8'h62: next_state = ;
        8'h82: next_state = ;*/
        8'hA2: next_state = load_x_operation;
        /*8'hC2: next_state = ;
        8'hE2: next_state = ;
        8'h12: next_state = ;
        8'h32: next_state = ;
        8'h52: next_state = ;
        8'h72: next_state = ;
        8'h92: next_state = ;
        8'hB2: next_state = ;
        8'hD2: next_state = ;
        8'hF2: next_state = ;*/

        /*8'h04: next_state = ;*/
        8'h24: begin
          next_state = zero_page_0;
          continue_state_next = bit_operation;
        end
        /*8'h44: next_state = ;
        8'h64: next_state = ;*/
        8'h84: begin
          next_state = store_y_operation;
        end
        8'hA4: begin
          next_state = zero_page_0;
          continue_state_next = load_y_operation;
        end
        8'hC4: begin
          next_state = zero_page_0;
          continue_state_next = cmp_y_operation;
        end
        8'hE4: begin
          next_state = zero_page_0;
          continue_state_next = cmp_x_operation;
        end
        /*8'h14: next_state = ;
        8'h34: next_state = ;
        8'h54: next_state = ;
        8'h74: next_state = ;*/
        8'h94: begin
          next_state = address_zero_page_x_0;
          continue_state_next = store_y_operation;
        end
        8'hB4: begin
          next_state = zero_page_x_0;
          continue_state_next = load_y_operation;
        end
        /*8'hD4: next_state = ;
        8'hF4: next_state = ;*/

        8'h05: begin
          next_state = zero_page_0;
          continue_state_next = or_operation;
        end
        8'h25: begin
          next_state = zero_page_0;
          continue_state_next = and_operation;
        end
        8'h45: begin
          next_state = zero_page_0;
          continue_state_next = xor_operation;
        end
        8'h65: begin
          next_state = zero_page_0;
          continue_state_next = add_operation;
        end
        8'h85: begin
          next_state = store_a_operation;
        end
        8'hA5: begin
          next_state = zero_page_0;
          continue_state_next = load_a_operation;
        end
        8'hC5: begin
          next_state = zero_page_0;
          continue_state_next = cmp_a_operation;
        end
        8'hE5: begin
          next_state = zero_page_0;
          continue_state_next = sub_operation;
        end
        8'h15: begin
          next_state = zero_page_x_0;
          continue_state_next = or_operation;
        end
        8'h35: begin
          next_state = zero_page_x_0;
          continue_state_next = and_operation;
        end
        8'h55: begin
          next_state = zero_page_x_0;
          continue_state_next = xor_operation;
        end
        8'h75: begin
          next_state = zero_page_x_0;
          continue_state_next = add_operation;
        end
        8'h95: begin
          next_state = address_zero_page_x_0;
          continue_state_next = store_a_operation;
        end
        8'hB5: begin
          next_state = zero_page_x_0;
          continue_state_next = load_a_operation;
        end
        8'hD5: begin
          next_state = zero_page_x_0;
          continue_state_next = cmp_a_operation;
        end
        8'hF5: begin
          next_state = zero_page_x_0;
          continue_state_next = sub_operation;
        end

        8'h06: begin
          next_state = shift_left_0;
        end
        8'h26: begin
          next_state = rotate_left_0;
        end
        8'h46: begin
          next_state = shift_right_0;
        end
        8'h66: begin
          next_state = rotate_right_0;
        end
        8'h86: begin
          next_state = store_x_operation;
        end
        8'hA6: begin
          next_state = zero_page_0;
          continue_state_next = load_x_operation;
        end
        8'hC6: begin
          next_state = dec_0;
        end
        8'hE6: begin
          next_state = inc_0;
        end
        8'h16: begin
          next_state = address_zero_page_x_0;
          continue_state_next = shift_left_0;
        end
        8'h36: begin
          next_state = address_zero_page_x_0;
          continue_state_next = rotate_left_0;
        end
        8'h56: begin
          next_state = address_zero_page_x_0;
          continue_state_next = shift_right_0;
        end
        8'h76: begin
          next_state = address_zero_page_x_0;
          continue_state_next = rotate_right_0;
        end
        8'h96: begin
          next_state = address_zero_page_y_0;
          continue_state_next = store_x_operation;
        end
        8'hB6: begin
          next_state = zero_page_y_0;
          continue_state_next = load_x_operation;
        end
        8'hD6: begin
          next_state = address_zero_page_x_0;
          continue_state_next = dec_0;
        end
        8'hF6: begin
          next_state = address_zero_page_x_0;
          continue_state_next = inc_0;
        end

        8'h08: next_state = push_status;
        8'h28: next_state = pull_status_0;
        8'h48: next_state = push_accum;
        8'h68: next_state = pull_accum_0;
        8'h88: next_state = dec_y;
        8'hA8: next_state = transfer_ay;
        8'hC8: next_state = inc_y;
        8'hE8: next_state = inc_x;
        8'h18: next_state = clear_carry;
        8'h38: next_state = set_carry;
        8'h58: next_state = clear_interrupt;
        8'h78: next_state = set_interrupt;
        8'h98: next_state = transfer_ya;
        8'hB8: next_state = clear_overflow;
        8'hD8: next_state = clear_decimal;
        8'hF8: next_state = set_decimal;

        8'h09: begin
          next_state = or_operation;
        end
        8'h29: begin
          next_state = and_operation;
        end
        8'h49: begin
          next_state = xor_operation;
        end
        8'h69: begin
          next_state = add_operation;
        end
        /*8'h89: next_state = ;*/
        8'hA9: begin
          next_state = load_a_operation;
        end
        8'hC9: begin
          next_state = cmp_a_operation;
        end
        8'hE9: begin
          next_state = sub_operation;
        end
        8'h19: begin
          next_state = abs_index_y_0;
          continue_state_next = or_operation;
        end
        8'h39: begin
          next_state = abs_index_y_0;
          continue_state_next = and_operation;
        end
        8'h59: begin
          next_state = abs_index_y_0;
          continue_state_next = xor_operation;
        end
        8'h79: begin
          next_state = abs_index_y_0;
          continue_state_next = add_operation;
        end
        8'h99: begin
          next_state = address_abs_index_slow_y_0;
          continue_state_next = store_a_operation;
        end
        8'hB9: begin
          next_state = abs_index_y_0;
          continue_state_next = load_a_operation;
        end
        8'hD9: begin
          next_state = abs_index_y_0;
          continue_state_next = cmp_a_operation;
        end
        8'hF9: begin
          next_state = abs_index_y_0;
          continue_state_next = sub_operation;
        end

        8'h0A: begin
          next_state = shift_left_accum;
        end
        8'h2A: begin
          next_state = rotate_left_accum;
        end
        8'h4A: begin
          next_state = shift_right_accum;
        end
        8'h6A: begin
          next_state = rotate_right_accum;
        end
        8'h8A: next_state = transfer_xa;
        8'hAA: next_state = transfer_ax;
        8'hCA: next_state = dec_x;
        /* NOOP */
        8'hEA: next_state = fetch;
        /*8'h1A: next_state = ;
        8'h3A: next_state = ;
        8'h5A: next_state = ;
        8'h7A: next_state = ;*/
        8'h9A: next_state = transfer_xs;
        8'hBA: next_state = transfer_sx;
        /*8'hDA: next_state = ;
        8'hFA: next_state = ;*/

        /*8'h0C: next_state = ;*/
        8'h2C: begin
          next_state = abs_index_0;
          continue_state_next = bit_operation;
        end
        8'h4C: begin
          next_state = jmp_abs_0;
        end
        8'h6C: begin
          next_state = jmp_indirect_0;
        end
        8'h8C: begin
          next_state = address_abs_index_0;
          continue_state_next = store_y_operation;
        end
        8'hAC: begin
          next_state = abs_index_0;
          continue_state_next = load_y_operation;
        end
        8'hCC: begin
          next_state = abs_index_0;
          continue_state_next = cmp_y_operation;
        end
        8'hEC: begin
          next_state = abs_index_0;
          continue_state_next = cmp_x_operation;
        end
        /*8'h1C: next_state = ;
        8'h3C: next_state = ;
        8'h5C: next_state = ;
        8'h7C: next_state = ;
        8'h9C: next_state = ;*/
        8'hBC: begin
          next_state = abs_index_x_0;
          continue_state_next = load_y_operation;
        end
        /*8'hDC: next_state = ;
        8'hFC: next_state = ;*/

        8'h0D: begin
          next_state = abs_index_0;
          continue_state_next = or_operation;
        end
        8'h2D: begin
          next_state = abs_index_0;
          continue_state_next = and_operation;
        end
        8'h4D: begin
          next_state = abs_index_0;
          continue_state_next = xor_operation;
        end
        8'h6D: begin
          next_state = abs_index_0;
          continue_state_next = add_operation;
        end
        8'h8D: begin
          next_state = address_abs_index_0;
          continue_state_next = store_a_operation;
        end
        8'hAD: begin
          next_state = abs_index_0;
          continue_state_next = load_a_operation;
        end
        8'hCD: begin
          next_state = abs_index_0;
          continue_state_next = cmp_a_operation;
        end
        8'hED: begin
          next_state = abs_index_0;
          continue_state_next = sub_operation;
        end
        8'h1D: begin
          next_state = abs_index_x_0;
          continue_state_next = or_operation;
        end
        8'h3D: begin
          next_state = abs_index_x_0;
          continue_state_next = and_operation;
        end
        8'h5D: begin
          next_state = abs_index_x_0;
          continue_state_next = xor_operation;
        end
        8'h7D: begin
          next_state = abs_index_x_0;
          continue_state_next = add_operation;
        end
        8'h9D: begin
          next_state = address_abs_index_slow_x_0;
          continue_state_next = store_a_operation;
        end
        8'hBD: begin
          next_state = abs_index_x_0;
          continue_state_next = load_a_operation;
        end
        8'hDD: begin
          next_state = abs_index_x_0;
          continue_state_next = cmp_a_operation;
        end
        8'hFD: begin
          next_state = abs_index_x_0;
          continue_state_next = sub_operation;
        end

        8'h0E: begin
          next_state = address_abs_index_0;
          continue_state_next = shift_left_0;
        end
        8'h2E: begin
          next_state = address_abs_index_0;
          continue_state_next = rotate_left_0;
        end
        8'h4E: begin
          next_state = address_abs_index_0;
          continue_state_next = shift_right_0;
        end
        8'h6E: begin
          next_state = address_abs_index_0;
          continue_state_next = rotate_right_0;
        end
        8'h8E: begin
          next_state = address_abs_index_0;
          continue_state_next = store_x_operation;
        end
        8'hAE: begin
          next_state = abs_index_0;
          continue_state_next = load_x_operation;
        end
        8'hCE: begin
          next_state = address_abs_index_0;
          continue_state_next = dec_0;
        end
        8'hEE: begin
          next_state = address_abs_index_0;
          continue_state_next = inc_0;
        end
        8'h1E: begin
          next_state = address_abs_index_slow_x_0;
          continue_state_next = shift_left_0;
        end
        8'h3E: begin
          next_state = address_abs_index_slow_x_0;
          continue_state_next = rotate_left_0;
        end
        8'h5E: begin
          next_state = address_abs_index_slow_x_0;
          continue_state_next = shift_right_0;
        end
        8'h7E: begin
          next_state = address_abs_index_slow_x_0;
          continue_state_next = rotate_right_0;
        end
        /*8'h9E: next_state = ;*/
        8'hBE: begin
          next_state = abs_index_y_0;
          continue_state_next = load_x_operation;
        end
        8'hDE: begin
          next_state = address_abs_index_slow_x_0;
          continue_state_next = dec_0;
        end
        8'hFE: begin
          next_state = address_abs_index_slow_x_0;
          continue_state_next = inc_0;
        end

        default: next_state = halted;
      endcase
    end

    reset_0: next_state = reset_1;
    reset_1: next_state = fetch;

    /* TODO check all (not just in this list) paths to fetch_two_and_decode
      handle interrupts as required. */
    or_operation,
    and_operation,
    xor_operation,
    add_operation,
    sub_operation,
    cmp_a_operation,
    cmp_x_operation,
    cmp_y_operation,
    load_a_operation,
    load_x_operation,
    load_y_operation,
    shift_left_accum,
    shift_right_accum,
    rotate_left_accum,
    rotate_right_accum,
    clear_carry, set_carry,
    clear_interrupt, set_interrupt,
    clear_overflow,
    clear_decimal, set_decimal,
    transfer_xa, transfer_ax,
    transfer_xs, transfer_sx,
    transfer_ya, transfer_ay,
    dec_x, dec_y,
    inc_x, inc_y,
    bit_operation: next_state = fetch_two_and_decode;

    break_0: next_state = break_1;
    break_1: next_state = break_2;
    break_2: next_state = break_3;
    break_3: next_state = break_4;
    break_4: next_state = fetch;

    jsr_0: next_state = jsr_1;
    jsr_1: next_state = jsr_2;
    jsr_2: next_state = jsr_3;
    jsr_3: next_state = fetch;

    rti_0: next_state = rti_1;
    rti_1: next_state = rti_2;
    rti_2: next_state = rti_3;
    rti_3: next_state = fetch;

    ret_0: next_state = ret_1;
    ret_1: next_state = ret_2;
    ret_2: next_state = ret_3;
    ret_3: next_state = fetch;

    shift_left_0: next_state = shift_left_1;
    shift_left_1: next_state = shift_left_2;
    shift_left_2: next_state = fetch;
    shift_right_0: next_state = shift_right_1;
    shift_right_1: next_state = shift_right_2;
    shift_right_2: next_state = fetch;
    rotate_left_0: next_state = rotate_left_1;
    rotate_left_1: next_state = rotate_left_2;
    rotate_left_2: next_state = fetch;
    rotate_right_0: next_state = rotate_right_1;
    rotate_right_1: next_state = rotate_right_2;
    rotate_right_2: next_state = fetch;

    dec_0: next_state = dec_1;
    dec_1: next_state = dec_2;
    dec_2: next_state = fetch;
    inc_0: next_state = inc_1;
    inc_1: next_state = inc_2;
    inc_2: next_state = fetch;

    store_a_operation,
    store_x_operation,
    store_y_operation: next_state = fetch;

    push_status: next_state = fetch;
    pull_status_0: next_state = pull_status_1;
    pull_status_1: next_state = fetch;
    push_accum: next_state = fetch;
    pull_accum_0: next_state = pull_accum_1;
    pull_accum_1: next_state = fetch;

    jmp_indirect_0: next_state = jmp_indirect_1;
    jmp_indirect_1: next_state = jmp_indirect_2;
    jmp_indirect_2: next_state = fetch;

    jmp_abs_0: next_state = fetch;

    abs_index_0: next_state = abs_index_1;
    abs_index_1: next_state = continue_state;

    address_abs_index_0: next_state = continue_state;

    abs_index_x_0: next_state = alu_output[8] == 1'b1 ? abs_index_x_1 :
      abs_index_x_2;
    abs_index_x_1: next_state = abs_index_x_2;
    abs_index_x_2: next_state = continue_state;

    abs_index_y_0: next_state = alu_output[8] == 1'b1 ? abs_index_y_1 :
      abs_index_y_2;
    abs_index_y_1: next_state = abs_index_y_2;
    abs_index_y_2: next_state = continue_state;

    address_abs_index_slow_x_0: next_state = address_abs_index_slow_x_1;
    address_abs_index_slow_x_1: next_state = continue_state;

    address_abs_index_slow_y_0: next_state = address_abs_index_slow_y_1;
    address_abs_index_slow_y_1: next_state = continue_state;

    zero_page_0: next_state = continue_state;

    zero_page_x_0: next_state = zero_page_x_1;
    zero_page_x_1: next_state = continue_state;

    address_zero_page_x_0: next_state = continue_state;

    zero_page_y_0: next_state = zero_page_y_1;
    zero_page_y_1: next_state = continue_state;

    address_zero_page_y_0: next_state = continue_state;

    indirect_index_x_0: next_state = indirect_index_x_1;
    indirect_index_x_1: next_state = indirect_index_x_2;
    indirect_index_x_2: next_state = indirect_index_x_3;
    indirect_index_x_3: next_state = continue_state;

    address_indirect_index_x_0: next_state = address_indirect_index_x_1;
    address_indirect_index_x_1: next_state = address_indirect_index_x_2;
    address_indirect_index_x_2: next_state = continue_state;

    indirect_index_y_0: next_state = indirect_index_y_1;
    indirect_index_y_1: next_state = alu_output[8] == 1'b1 ?
      indirect_index_y_2 : indirect_index_y_3;
    indirect_index_y_2: next_state = indirect_index_y_3;
    indirect_index_y_3: next_state = continue_state;

    address_indirect_index_slow_y_0:
      next_state = address_indirect_index_slow_y_1;
    address_indirect_index_slow_y_1:
      next_state = address_indirect_index_slow_y_2;
    address_indirect_index_slow_y_2:
      next_state = continue_state;

  endcase

  /* TODO figure out if the real NES pauses, or continues on to fetch afterward.
    Also TODO make OAM cycle accurate (currently off by 1, or 2 cycles).
  */
  oam_counter_next = 8'bx;
  if (read_write == 1'b0 && memory_address == 16'h4014) begin
    continue_state_next = next_state;
    oam_counter_next = 8'h0;
    reg_extra_next = memory_data_out;
    next_state = oam_state_read;
  end
  if (state == oam_state_read) begin
    read_write = 1'b1;
    memory_address = { reg_extra, oam_counter };
    partial_ir_next = memory_data_in;
    oam_counter_next = oam_counter;
    next_state = oam_state_write;
  end
  if (state == oam_state_write) begin
    read_write = 1'b0;
    ppu_chip_select = 1'b0;
    memory_data_out = partial_ir;
    memory_address = 16'h2004;
    oam_counter_next = oam_counter + 8'h1;
    if (oam_counter == 8'hFF) begin
      next_state = continue_state;
    end else begin
      next_state = oam_state_read;
    end
  end

  if (state == fetch
      || state == or_operation
      || state == and_operation
      || state == xor_operation
      || state == add_operation
      || state == sub_operation
      || state == cmp_a_operation
      || state == cmp_x_operation
      || state == cmp_y_operation
      || state == load_a_operation
      || state == load_x_operation
      || state == load_y_operation
      || state == clear_carry
      || state == set_carry
      || state == clear_interrupt
      || state == set_interrupt
      || state == clear_overflow
      || state == clear_decimal
      || state == set_decimal
      || state == transfer_xa
      || state == transfer_ax
      || state == transfer_xs
      || state == transfer_sx
      || state == transfer_ya
      || state == transfer_ay
      || state == dec_x
      || state == dec_y
      || state == inc_x
      || state == inc_y
      || state == shift_left_accum
      || state == rotate_left_accum
      || state == shift_right_accum
      || state == rotate_right_accum
      || state == bit_operation) begin
    read_write = 1'b1;
    memory_address = PC;
    /* TODO fix interrupt_request needs to be buffered */
    if (nmi_request == 1'b1
        && (reg_status[2] == 1'b1 || interrupt_request == 1'b1)) begin
      PC_next = PC_incr;
    end else begin
      next_state = break_0;
    end
    partial_ir_next = memory_data_in;
  end
end

endmodule
