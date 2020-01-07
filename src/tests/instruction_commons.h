#ifndef INSTRUCTION_COMMONS
#define INSTRUCTION_COMMONS

#include "Vverilator_test_wrapper.h"
#include "verilated.h"

#define FLAG_N (1 << 5)
#define FLAG_V (1 << 4)
#define FLAG_D (1 << 3)
#define FLAG_I (1 << 2)
#define FLAG_Z (1 << 1)
#define FLAG_C (1 << 0)

/* Instruction struct */
struct instr {
  unsigned char size;
  unsigned char instruction[3];
};

bool instruction_time_passed(Vverilator_test_wrapper* top,
    unsigned int cycle_delay, unsigned int state);

/* Calculates NZC */
unsigned char calculate_common_flags(unsigned int value);

/* Little endian */
#define short_to_char(s) (s & 0xFF), (s >> 8 & 0xFF)

/* Returns 1 if crosses page, 0 otherwise */
unsigned int crosses_page(unsigned short a, unsigned char b);

/* Sets the next instruction to be executed at 0x200
  mind the 6502's prefetching of instructions...
  Also resets the CPU. */
void setup_verify_instr(void);

#endif
