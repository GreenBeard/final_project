#ifndef TEST_RAM_H
#define TEST_RAM_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#include <stdint.h>

void init_test_sram();

void free_test_sram();

void update_test_sram(unsigned int address, uint16_t data_in,
    uint16_t* data_out, bool write_enable,
    bool read_enable);

/*void write_test_sram(unsigned short address, uint8_t data);

void read_test_sram(unsigned short address, uint8_t data);*/

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif
