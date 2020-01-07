#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* End of input */
#define EOI "Error unexpected end of input\n"

/* Line of output file format */
#define O_F "@%05x %04x\n"

struct ines_flags_6 {
  /* 0 - horizontal
     1 - vertical
     four_screen_vram has preference
  */
  unsigned char mirroring_mode : 1;
  /* We don't support batteries either (used for PRG RAM) */
  unsigned char battery : 1;
  /* We don't support this... */
  unsigned char trainer : 1;
  /* We don't support this either */
  unsigned char four_screen_vram : 1;
  unsigned char mapper_id_lower : 4;
};
union ines_flags_6_union {
  unsigned char data;
  struct ines_flags_6 s;
};

struct ines_flags_7 {
  /* More unsupported options including iNES 2 (expect zero) */
  unsigned char unsupported_options : 4;
  unsigned char mapper_id_upper : 4;
};
union ines_flags_7_union {
  unsigned char data;
  struct ines_flags_7 s;
};

/* After magic number start */
struct ines_header {
  /* 16kB units */
  unsigned char prg_rom_size;

  /* 8kB units, zero means it uses ram??? */
  unsigned char chr_rom_size;

  union ines_flags_6_union flags_6;

  union ines_flags_7_union flags_7;
};

/* Reads an INES format file (version 1) and parses it into a .dat file
  for test_memory.sv. (Each line is an address followed by a value) */
int main() {
  FILE* output_file = fopen("./memory_contents.dat", "w");
  FILE* output_raw_file = fopen("./memory_contents.ram", "w");

  char file_name[256];
  FILE* input_file = NULL;
  while (input_file == NULL) {
    printf("Please enter a filename for input: ");
    fflush(stdout);
    int status = scanf("%255s", file_name);
    if (status == 1) {
      input_file = fopen(file_name, "r");
    }
  }

  const char* ines_header_tag = (const char[]) { 0x4E, 0x45, 0x53, 0x1A };
  char file_header[4];
  for (unsigned int i = 0; i < 4; ++i) {
    int status = fscanf(input_file, "%c", &file_header[i]);
    if (status != 1) {
      printf(EOI);
    }
  }

  if (memcmp(ines_header_tag, file_header, 4) == 0) {
    struct ines_header header;
    fscanf(input_file, "%c", &header.prg_rom_size);
    fscanf(input_file, "%c", &header.chr_rom_size);
    fscanf(input_file, "%c", &header.flags_6.data);
    fscanf(input_file, "%c", &header.flags_7.data);
    /* Extra 1 for '\0' */
    unsigned char further_flags[9];
    fscanf(input_file, "%8s", further_flags);
    unsigned char mapper = (header.flags_7.s.mapper_id_upper << 4)
      + header.flags_6.s.mapper_id_lower;
    if (mapper != 0 && mapper != 1) {
      printf("We only handle mappers 0, and 1\n");
    } else if (header.prg_rom_size > 16 || header.chr_rom_size > 8) {
      printf("We don't support large PRG, and CHR spaces (we probably could handle larger without modification though\n");
    } else if (header.flags_6.s.four_screen_vram != 0
        || header.flags_6.s.trainer != 0) {
      printf("No support for four screen VRAM, or trainer\n");
    } else if (header.flags_7.s.unsupported_options != 0) {
      printf("No support for iNES 2 format (or other flag 7 options)\n");
    } else {
      bool no_other_flags = true;
      for (unsigned int i = 0; i < 8; ++i) {
        if (further_flags[i] != 0) {
          printf("Unsupported flag %u value 0x%08x\n", i, further_flags[i]);
          no_other_flags = false;
        }
      }
      unsigned int address = 0;
      if (no_other_flags) {
        /* Fill CPU, and PPU RAM with zeroes */
        while (address < 0x1000) {
          fprintf(output_file, O_F, address, 0);
          unsigned char data[2] = { 0, 0 };
          fwrite(&data, 2, 1, output_raw_file);
          ++address;
        }
        /* Fill 8kB of RAM */
        if (mapper == 1) {
          for (unsigned int i = 0; i < 0x2000; ++i) {
            fprintf(output_file, O_F, address, 0);
            unsigned char data[2] = { 0, 0 };
            fwrite(&data, 2, 1, output_raw_file);
            ++address;
          }
        } else if (mapper == 0) {
          printf("Does this cartridge use 1) 2kB, or 2) 4kB of RAM?\n");
          printf("Select 2 in general if you don't know. \n");
          unsigned int ram_option;
          int status = 0;
          while (status != 1 || ram_option == 0 || ram_option > 2) {
            status = scanf("%u", &ram_option);
          }
          unsigned int ram_size;
          if (ram_option == 1) {
            ram_size = 0x00800;
          } else if (ram_option == 2) {
            ram_size = 0x01000;
          }
          for (unsigned int i = 0; i < ram_size; ++i) {
            fprintf(output_file, O_F, address, 0);
            unsigned char data[2] = { 0, 0 };
            fwrite(&data, 2, 1, output_raw_file);
            ++address;
          }
        }
        /* Write PRG ROM */
        if (mapper == 0 && header.prg_rom_size != 1
            && header.prg_rom_size != 2) {
          printf("Invalid prg_rom_size! Changing from %u to 1\n", header.prg_rom_size);
          header.prg_rom_size = 1;
        }
        for (unsigned int i = 0; i < header.prg_rom_size; ++i) {
          for (unsigned int j = 0; j < 16 * 1024; ++j) {
            unsigned char value;
            int status = fscanf(input_file, "%c", &value);
            if (status != 1) {
              printf(EOI);
            }
            fprintf(output_file, O_F, address, value);
            unsigned char data[2] = { value, 0 };
            fwrite(&data, 2, 1, output_raw_file);
            ++address;
          }
        }
        /* Write CHR ROM */
        if (mapper == 0 && header.chr_rom_size != 1) {
          printf("Invalid chr_rom_size! Changing from %u to 1 (filled with zeros)\n", header.chr_rom_size);
          for (unsigned int i = 0; i < 8 * 1024; ++i) {
            unsigned char value = 0;
            fprintf(output_file, O_F, address, value);
            unsigned char data[2] = { value, 0 };
            fwrite(&data, 2, 1, output_raw_file);
            ++address;
          }
        }
        for (unsigned int i = 0; i < header.chr_rom_size; ++i) {
          for (unsigned int i = 0; i < 8 * 1024; ++i) {
            unsigned char value;
            int status = fscanf(input_file, "%c", &value);
            if (status != 1) {
              printf(EOI);
            }
            fprintf(output_file, O_F, address, value);
            unsigned char data[2] = { value, 0 };
            fwrite(&data, 2, 1, output_raw_file);
            ++address;
          }
        }
        const char* mirroring_msg = header.flags_6.s.mirroring_mode == 1 ?
          "vertical mirroring" :
          "horizontal mirroring";
        printf("Address lines used %u [mapper %u, chr_rom_size %u, prg_rom_size %u] %s\n",
          address, mapper, header.chr_rom_size, header.prg_rom_size,
          mirroring_msg);
      }
    }
  } else {
    printf("Invalid iNes file\n");
    return 1;
  }
  fclose(output_file);
  fclose(output_raw_file);
}
