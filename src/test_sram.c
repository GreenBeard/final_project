#include <assert.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "./test_sram.h"

uint16_t* sram_data;

/* Courtesy of the Linux Kernel's developers */
#define BUILD_ASSERT(condition) ((void)sizeof(char[1 - 2*!!(condition)]))

void init_test_sram() {
  /* Allocate the 2MB of memory */
  size_t sram_data_size = sizeof(uint16_t) * (2 * 1024 * 1024);
  sram_data = malloc(sram_data_size);
  memset(sram_data, 0, sram_data_size);
}

void free_test_sram() {
  free(sram_data);
}

/* write_enable, and read_enable are active high */
void update_test_sram(unsigned int address, uint16_t data_in,
    uint16_t* data_out, bool write_enable,
    bool read_enable) {
  if (write_enable && read_enable) {
    printf("Warning: Both write_enable, and read_enable are set\n");
    assert(false);
  }
  if (read_enable) {
    *data_out = sram_data[address];
  }
  if (write_enable) {
    sram_data[address] = data_in;
  }
}
