#include "./instruction_commons.h"
#include "../commons.h"

bool instruction_time_passed(Vverilator_test_wrapper* top,
    unsigned int cycle_delay, unsigned int state) {
  for (unsigned int i = 0; i < cycle_delay; ++i) {
    if (top->v->processor->v->state == state) {
      printf("State %u reached at cycle %u instead of %u\n", state, i, cycle_delay);
      return false;
    }
    delay(top, 2);
  }
  if (top->v->processor->v->state == state) {
    return true;
  } else {
    printf("State %u not reached after %u cycles\n", state, cycle_delay);
    return false;
  }
}

unsigned char calculate_common_flags(unsigned int value) {
  unsigned char flags = 0;
  if (value | 1 << 7) {
    flags |= FLAG_N;
  }
  if (value % 256 == 0x00) {
    flags |= FLAG_Z;
  }
  if (value > 0xFF) {
    flags |= FLAG_C;
  }
  return flags;
}

unsigned int crosses_page(unsigned short a, unsigned char b) {
  if (((a + b) & 1 << 8) ^ (a & 1 << 8)) {
    return 1;
  } else {
    return 0;
  }
}

void setup_verify_instr(void) {
  //TODO
  assert(false);
}
