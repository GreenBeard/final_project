#include <inttypes.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>

#include "Vverilator_test_wrapper.h"
#include "Vverilator_test_wrapper_verilator_test_wrapper.h"
#include "Vverilator_test_wrapper_processor_6502.h"
#include "Vverilator_test_wrapper_nes_mapper_zero__R2_M1.h"
#include "Vverilator_test_wrapper_nes_ppu.h"
#include "Vverilator_test_wrapper_ppu_to_vga.h"
#include "Vverilator_test_wrapper_bram_color.h"
#include "verilated.h"
#include "verilated_vcd_c.h"

#include "./commons.h"
#include "./test_sram.h"

//#define enable_tracing
//#define trace_all
//#define trace_ps2

#define output_frames

void initialize_sram(FILE* file) {
  unsigned int address = 0;
  uint16_t word;
  while (fscanf(file, " @%x %hx", &address, &word) == 2) {
    assert(address <= (1 << 20));
    update_test_sram(address, word, NULL, true, false);
  }
  printf("Last address written %u\n", address);
}

FILE* ppm_file = NULL;
void start_ppm_output(unsigned int frame, unsigned int width,
    unsigned int height, unsigned short color_max) {
  char file_name[256];
  snprintf(file_name, 255, "./frames/frame%u.ppm", frame);
  ppm_file = fopen(file_name, "w");
  assert(ppm_file != NULL);
  fprintf(ppm_file, "P6 %u %u %u\n", width, height, color_max);
}

/* Assumes one byte output for now */
void add_ppm_output(unsigned char red, unsigned char green,
    unsigned char blue) {
  fwrite(&red, 1, 1, ppm_file);
  fwrite(&green, 1, 1, ppm_file);
  fwrite(&blue, 1, 1, ppm_file);
}

void finish_ppm_output() {
  fclose(ppm_file);
}

unsigned int ps2_clock_count = 0;
void send_ps2_keycode(Vverilator_test_wrapper* wrapper, VerilatedVcdC* trace,
    unsigned char keycode) {
  /* In case the ps2_clock was incorrect */
  #ifdef trace_ps2
  trace->dump(ps2_clock_count);
  ++ps2_clock_count;
  #endif
  wrapper->ps2_clock = 1;
  wrapper->eval();
  #ifdef trace_ps2
  trace->dump(ps2_clock_count);
  ++ps2_clock_count;
  #endif

  unsigned char parity = 1;
  unsigned char keycode_copy = keycode;
  while (keycode_copy > 0) {
    parity ^= keycode_copy & 0x01;
    keycode_copy >>= 1;
  }

  unsigned char data[11] = {
    0,
    (unsigned char) ((keycode & 0x01) >> 0),
    (unsigned char) ((keycode & 0x02) >> 1),
    (unsigned char) ((keycode & 0x04) >> 2),
    (unsigned char) ((keycode & 0x08) >> 3),
    (unsigned char) ((keycode & 0x10) >> 4),
    (unsigned char) ((keycode & 0x20) >> 5),
    (unsigned char) ((keycode & 0x40) >> 6),
    (unsigned char) ((keycode & 0x80) >> 7),
    parity,
    1
  };

  for (unsigned int i = 0; i < 11; ++i) {
    #ifdef trace_ps2
    trace->dump(ps2_clock_count);
    ++ps2_clock_count;
    #endif
    wrapper->ps2_data = data[i];
    wrapper->eval();
    #ifdef trace_ps2
    trace->dump(ps2_clock_count);
    ++ps2_clock_count;
    #endif
    wrapper->ps2_clock = 0;
    wrapper->eval();
    #ifdef trace_ps2
    trace->dump(ps2_clock_count);
    ++ps2_clock_count;
    #endif
    wrapper->ps2_clock = 1;
    wrapper->eval();
    #ifdef trace_ps2
    trace->dump(ps2_clock_count);
    ++ps2_clock_count;
    #endif
  }
}

int main(int argc, char** argv) {
  // Initialize Verilators variables
  Verilated::commandArgs(argc, argv);

  // Create an instance of our module under test
  Vverilator_test_wrapper* wrapper = new Vverilator_test_wrapper();

  unsigned int error_count = 0;
  unsigned int tests_run = 0;

  printf("Initializing SRAM\n");
  init_test_sram();
  FILE* file = fopen("./memory_contents.dat", "r");
  assert(file != NULL);
  initialize_sram(file);
  fclose(file);
  printf("SRAM initialized\n");

  #ifdef enable_tracing
  Verilated::traceEverOn(true);
  VerilatedVcdC* trace = new VerilatedVcdC();
  wrapper->trace(trace, 99);
  trace->open("trace.vcd");
  #endif

  wrapper->master_clock = 0;
  wrapper->keys = 0xF;
  delay(wrapper, 100 * 2 * 48);
  wrapper->keys = 0xE;
  delay(wrapper, 100 * 2 * 48);
  wrapper->keys = 0xF;

  // Tick the clock until we are done
  unsigned int state_halted = 0xFF;
  unsigned int state_fetch_two_and_decode = 0x3;
  unsigned int last_pc = 0;
  unsigned int last_vblank_val = 0;

  unsigned long master_clock_count = 0;
  unsigned int frame = 0;
  while (wrapper->v->processor->state != state_halted || master_clock_count <= 400) {
    /*if (wrapper->v->processor->state == state_fetch_two_and_decode &&
        last_pc != wrapper->v->processor->PC) {
      last_pc = wrapper->v->processor->PC;
      printf("%4x  xx xx xx  ???"
        "          A:%2x X:%2x Y:%2x P:%2x SP:%2x PPU:%3d,%3d CYC:%d\n",
        wrapper->v->processor->PC - 1,
        wrapper->v->processor->reg_a,
        wrapper->v->processor->reg_x,
        wrapper->v->processor->reg_y,
        0,
        wrapper->v->processor->reg_stack,
        0, 0, 0);
    }*/
    wrapper->master_clock = 0;
    wrapper->eval();
    update_test_sram(wrapper->sram_addr, wrapper->sram_data_out,
      &wrapper->sram_data_in, !wrapper->sram_we,
      !wrapper->sram_oe);
    wrapper->eval();
    #ifdef trace_all
    trace->dump(2 * master_clock_count);
    #endif
    wrapper->master_clock = 1;
    wrapper->eval();
    update_test_sram(wrapper->sram_addr, wrapper->sram_data_out,
      &wrapper->sram_data_in, !wrapper->sram_we,
      !wrapper->sram_oe);
    wrapper->eval();
    #ifdef trace_all
    trace->dump(2 * master_clock_count + 1);
    #endif

    if (wrapper->v->ppu->vblank_active == 1 && last_vblank_val == 0) {
      /* Render screen to file */

      #ifdef output_frames
      start_ppm_output(frame, 256, 240, 255);
      #endif
      unsigned char red;
      unsigned char green;
      unsigned char blue;
      for (unsigned int i = 0; i < 240; ++i) {
        for (unsigned int j = 0; j < 256; ++j) {
          Vverilator_test_wrapper_bram_color* red_instance;
          Vverilator_test_wrapper_bram_color* green_instance;
          Vverilator_test_wrapper_bram_color* blue_instance;
          if (wrapper->v->ppu_to_vga_inst->nes_buffer == 1) {
            red_instance = wrapper->v->ppu_to_vga_inst->bram_colors__BRA__0__KET____DOT__bram_zero;
            green_instance = wrapper->v->ppu_to_vga_inst->bram_colors__BRA__1__KET____DOT__bram_zero;
            blue_instance = wrapper->v->ppu_to_vga_inst->bram_colors__BRA__2__KET____DOT__bram_zero;
          } else {
            red_instance = wrapper->v->ppu_to_vga_inst->bram_colors__BRA__0__KET____DOT__bram_one;
            green_instance = wrapper->v->ppu_to_vga_inst->bram_colors__BRA__1__KET____DOT__bram_one;
            blue_instance = wrapper->v->ppu_to_vga_inst->bram_colors__BRA__2__KET____DOT__bram_one;
          }
          red = red_instance->mem[i * 256 + j];
          green = green_instance->mem[i * 256 + j];
          blue = blue_instance->mem[i * 256 + j];
          #ifdef output_frames
          add_ppm_output(red, green, blue);
          #endif
        }
      }
      #ifdef output_frames
      finish_ppm_output();
      #endif
      printf("\rFrame number #%-10u", frame);
      fflush(stdout);
      ++frame;
      if (frame == 120) {
        break;
      }
    }
    last_vblank_val = wrapper->v->ppu->vblank_active;

    /*if (master_clock_count > 35 * 357368 && master_clock_count < 36 * 357368) {
      send_ps2_keycode(wrapper, trace, 0x2B);
    }
    if (master_clock_count > 36 * 357368 && master_clock_count < 37 * 357368) {
      send_ps2_keycode(wrapper, trace, 0xF0);
      send_ps2_keycode(wrapper, trace, 0x2B);
    }*/
    /*if (master_clock_count > 3 * 1000000 && master_clock_count < 3 * 1000000 + 10000) {
      send_ps2_keycode(wrapper, trace, 0x32);
    }
    if (master_clock_count > 4 * 1000000 && master_clock_count < 4 * 1000000 + 10000) {
      send_ps2_keycode(wrapper, trace, 0xF0);
      send_ps2_keycode(wrapper, trace, 0x32);
    }*/

    ++master_clock_count;
  }

  ++tests_run;
  if (wrapper->v->processor->state == state_halted) {
    ++error_count;
  }

  #ifdef enable_tracing
  trace->close();
  #endif

  if (error_count == 0) {
    printf("Success!\n");
  } else {
    printf("%d error(s) of %d test(s) run detected. Testbench unsuccessful.\n",
      error_count, tests_run);
  }

  wrapper->final();

  free_test_sram();
  delete wrapper;
  return 0;
}
