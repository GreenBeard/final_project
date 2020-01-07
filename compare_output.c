#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

bool read_line(FILE* file, unsigned int* a, unsigned char* b, unsigned char* c,
    unsigned char* d, unsigned char* e, unsigned char* f, unsigned int* g,
    unsigned int* h, unsigned int* i) {
  int status;
  status = fscanf(file, "%x", a);
  if (status != 1) return false;
  for (unsigned int i = 0; i < 43; ++i) {
    getc(file);
  }
  status = fscanf(file,
    " A:%hhx X:%hhx Y:%hhx P:%hhx SP:%hhx PPU:%u,%u CYC:%u",
    b, c, d, e, f,
    g, h, i);
  if (status != 8) return false;
  return true;
}

int main(int argc, char** argv) {
  if (argc != 3) {
    printf("./compare_output expected actual\n");
    printf("- used for stdin\n");
  } else {
    FILE* file_expected;
    FILE* file_actual;
    if (strcmp(argv[1], "-") != 0) {
      file_expected = fopen(argv[1], "r");
    } else {
      file_expected = stdin;
    }
    if (strcmp(argv[2], "-") != 0) {
      file_actual = fopen(argv[2], "r");
    } else {
      file_actual = stdin;
    }
    if (file_expected != NULL && file_actual != NULL) {
      unsigned int line = 1;
      while (true) {
        unsigned int pc;
        unsigned char reg_a, reg_x, reg_y, reg_status, reg_stack;
        unsigned int ppu_cyc_a, ppu_cyc_b, cpu_cycle;

        unsigned int actual_pc;
        unsigned char actual_reg_a, actual_reg_x, actual_reg_y,
          actual_reg_status, actual_reg_stack;
        unsigned int actual_ppu_cyc_a, actual_ppu_cyc_b, actual_cpu_cycle;

        bool success_expected = read_line(file_expected, &pc, &reg_a, &reg_x,
          &reg_y, &reg_status, &reg_stack, &ppu_cyc_a, &ppu_cyc_b, &cpu_cycle);
        bool success_actual = read_line(file_actual, &actual_pc, &actual_reg_a,
          &actual_reg_x, &actual_reg_y, &actual_reg_status, &actual_reg_stack,
          &actual_ppu_cyc_a, &actual_ppu_cyc_b, &actual_cpu_cycle);

        if (success_expected && success_actual) {
          if (reg_a == actual_reg_a
              && reg_x == actual_reg_x
              && reg_y == actual_reg_y
              && reg_status == actual_reg_status
              && reg_stack == actual_reg_stack
              /*&& ppu_cyc_a == actual_ppu_cyc_a
              && ppu_cyc_b == actual_ppu_cyc_b*/
              /*&& cpu_cycle == actual_cpu_cycle*/
              && pc == actual_pc) {
            /* print nothing */
          } else {
            printf("Line mismatch %u\n", line);
          }
        } else {
          printf("Error parsing line %u (probably end of file)\n", line);
          break;
        }
        ++line;
      }
    } else {
      printf("Invalid files\n");
    }
    if (file_expected != NULL) {
      fclose(file_expected);
    }
    if (file_actual != NULL) {
      fclose(file_actual);
    }
  }
}
