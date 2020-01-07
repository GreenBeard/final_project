CC:=gcc
CXX:=g++
LD:=ld

# Disable default make rules
.SUFFIXES:

VERILATOR_DIR:=obj_dir
VDIR_GENERIC:=/usr/share/verilator

EXE:="obj_dir/final_project"
CFLAGS:=-Wall -std=c99 -pedantic -g
CXXFLAGS:=-Wall -std=c++11 -pedantic -Wno-long-long -g -O2
INC:=-Iobj_dir/ $(shell pkg-config --cflags verilator)

C_SRC:=test_sram.c
CXX_SRC:=verilator_main.cpp commons.cpp

OBJECTS:=$(patsubst %.c,obj/c/%.o,$(C_SRC)) $(patsubst %.cpp,obj/cxx/%.o,$(CXX_SRC))
VOBJECTS_GENERIC:=obj/verilated/verilated.o
VOBJECTS:=$(wildcard obj_dir/Vverilator_test_wrapper__ALL*.o)
ALL_OBJECTS:=$(OBJECTS) $(VOBJECTS) $(VOBJECTS_GENERIC)

help:
	@printf "Type \"make build\", \"make clean\", \"make nes_to_dat\", or \"make compare_output\"\n"

build: v_objs $(VOBJECTS_GENERIC) $(OBJECTS)
	$(MAKE) real_build

real_build:
	$(CXX) -o $(EXE) $(ALL_OBJECTS) /usr/share/verilator/include/verilated_vcd_c.cpp

clean:
	$(RM) -r obj_dir/ obj/ nes_to_dat compare_output

v_objs:
	verilator --cc --compiler gcc -Ips2_driver/ --l2-name v --trace -CFLAGS "-Wall -g -O2" --stats verilator_test_wrapper.sv
	$(MAKE) -C $(VERILATOR_DIR) -f Vverilator_test_wrapper.mk

obj/cxx/%.o: src/%.cpp v_objs
	mkdir -p $(@D)
	$(CXX) $(INC) $(CXXFLAGS) -c $< -o $@

obj/c/%.o: src/%.c v_objs
	mkdir -p $(@D)
	$(CC) $(INC) $(CFLAGS) -c $< -o $@

obj/verilated/%.o: $(VDIR_GENERIC)/include/%.cpp v_objs
	mkdir -p $(@D)
	$(CXX) $(INC) $(CXXFLAGS) -w -c $< -o $@

nes_to_dat:
	$(CC) -std=c99 -g -pedantic -Wall nes_to_dat.c -o nes_to_dat

compare_output:
	$(CC) -std=c99 -g -pedantic -Wall compare_output.c -o compare_output

.PHONY: help build clean v_objs nes_to_dat compare_output
