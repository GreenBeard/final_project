#include "./instruction_commons.h"

void verify_adc_flags(unsigned char a, unsigned char b, unsigned char c,
    bool carry) {
  unsigned char expected_c = a + b + 1;
  bool overflow = (a >> 7 & b >> 7 & ~(expected_c >> 7))
    | (~(a >> 7) & ~(b >> 7) & expected_c >> 7);
  unsigned char expected_flags = calculate_common_flags(a + b + carry);
  if (overflow) {
    expected_flags |= FLAG_V;
  }
  unsigned char flags = (FLAG_N | FLAG_Z | FLAG_C | FLAG_V) & processor_flags();
  if (flags != expected_flags) {
    printf("Unexpected ADC flags result\n");
  }
  if (c != expected_c) {
    printf("Unexpected ADC addition result\n");
  }
}

void verify_adc_fin(Vfinal_project* top, struct instr instr_a,
    struct instr instr_b, struct instr instr_c, bool carry,
    unsigned int cycle_count_a, unsigned int cycle_count_b) {
  write_sram_instr(0x200, instr_a);
  write_sram_instr(0x200 + instr_a.size, instr_b);
  write_sram_instr(0x200 + instr_a.size + instr_b.size, instr_c);

  instruction_time_passed(top, 3, state_decode);
  top->processor->flags = (top->processor->flags & ~CARRY_FLAG)
    | (carry ? CARRY_FLAG : 0);
  instruction_time_passed(top, cycle_count_a, state_decode);
  instruction_time_passed(top, cycle_count_b, state_decode);
}

void verify_adc_immediate(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    2, { 0x69, a }
  };
  struct instr instr_c = {
    2, { 0x69, b }
  };

  verify_adc_fin(top, instr_a, instr_b, instr_c, carry, 2, 2);
}

void verify_adc_zeropage(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    2, { 0x65, a }
  };
  struct instr instr_c = {
    2, { 0x65, b }
  };

  verify_adc_fin(top, instr_a, instr_b, instr_c, carry, 3, 3);
}

void verify_adc_zeropage_x(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    2, { 0x75, a }
  };
  struct instr instr_c = {
    2, { 0x75, b }
  };

  verify_adc_fin(top, instr_a, instr_b, instr_c, carry, 4, 4);
}

void verify_adc_absolute(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    2, { 0x6D, a }
  };
  struct instr instr_c = {
    2, { 0x6D, b }
  };

  verify_adc_fin(top, instr_a, instr_b, instr_c, carry, 4, 4);
}

void verify_adc_absolute_x(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    2, { 0x7D, a }
  };
  struct instr instr_c = {
    2, { 0x7D, b }
  };

  unsigned int cycle_count_a = 4 + crosses_page(a, top->processor->reg_x);
  unsigned int cycle_count_b = 4 + crosses_page(b, top->processor->reg_X);
  verify_adc_fin(top, instr_a, instr_b, instr_c, carry,
    cycle_count_a, cycle_count_b);
}

void verify_adc_absolute_x(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    3, { 0x79, short_to_char(a) }
  };
  struct instr instr_c = {
    3, { 0x79, short_to_char(b) }
  };

  unsigned int cycle_count_a = 4 + crosses_page(a, top->processor->reg_y);
  unsigned int cycle_count_b = 4 + crosses_page(b, top->processor->reg_y);
  verify_adc_fin(top, instr_a, instr_b, instr_c, carry,
    cycle_count_a, cycle_count_b);
}

void verify_adc_indirect_x(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    3, { 0x61, short_to_char(a) }
  };
  struct instr instr_c = {
    3, { 0x61, short_to_char(b) }
  };

  verify_adc_fin(top, instr_a, instr_b, instr_c, carry, 6, 6);
}

void verify_adc_indirect_y(Vfinal_project* top, unsigned short a,
    unsigned short b, bool carry) {
  /* Clear A */
  struct instr instr_a = {
    2, { 0x29, 0x00 }
  };
  struct instr instr_b = {
    2, { 0x71, a }
  };
  struct instr instr_c = {
    2, { 0x71, b }
  };

  unsigned int cycle_count_a = 4 + crosses_page(memory_at(a),
    top->processor->reg_y);
  unsigned int cycle_count_b = 4 + crosses_page(memory_at(b),
    top->processor->reg_y);
  verify_adc_fin(top, instr_a, instr_b, instr_c, carry,
    cycle_count_a, cycle_count_b);
}

void verify_adc(Vfinal_project* top) {
  unsigned char a = 0x34;
  unsigned char b = 0xDE;

  unsigned char a_zero = 0x0;
  unsigned char b_zero = 0x1;

  unsigned char a_zero_pointer = 0x2;
  unsigned char b_zero_pointer = 0x3;

  write_test_sram(a_zero, a);
  write_test_sram(b_zero, b);

  write_test_sram(a_zero_pointer, a_zero);
  write_test_sram(b_zero_pointer, b_zero);

  unsigned short arg_a[] = { a, a_zero, a_zero, a_zero, a_zero_pointer,
    a_zero_pointer, a_zero_pointer, a_zero, a_zero
    };
  unsigned short arg_b[] = { b, b_zero, b_zero, b_zero, b_zero_pointer,
    b_zero_pointer, b_zero_pointer, b_zero, b_zero
    };
  void (*adc_functions)(Vfinal_project*, unsigned short,
    unsigned short, bool)* = { verify_adc_immediate,
    verify_adc_zeropage, verify_adc_zeropage_x, verify_adc_zeropage_y,
    verify_adc_absolute, verify_adc_absolute_x, verify_adc_absolute_y,
    verify_indirect_x, verify_indirect_y
    };

  for (unsigned int i = 0; i < sizeof(arg_a) / sizeof(arg_a[0]); ++i) {
    /* carry off */
    setup_verify_instr();
    adc_functions[i](top, arg_a[i], arg_b[i], false);
    verify_adc_flags(top, a, b, top->processor->reg_a);
    /* carry on */
    setup_verify_instr();
    adc_functions[i](top, arg_a[i], arg_b[i], true);
    verify_adc_flags(top, a, b, top->processor->reg_a);
  }
}
