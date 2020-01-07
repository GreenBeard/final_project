#include "./commons.h"

void delay(Vverilator_test_wrapper* top, unsigned int cycles) {
  for (unsigned int i = 0; i < cycles; ++i) {
    top->master_clock = top->master_clock == 0 ? 1 : 0;
    top->eval();
  }
}
