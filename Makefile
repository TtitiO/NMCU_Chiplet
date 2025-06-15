# Verilator Makefile for NMCU testbench

# Compiler and flags
VERILATOR = verilator
VERILATOR_FLAGS = -Wall --cc --exe --build -j 0 \
		--top-module nmcu_tb \
		--timescale 1ns/1ps \
		--timing \
		-Wno-fatal \
		+incdir+src/include \
		--trace

# Source files
SRC_DIR = src
TB_DIR = tb
INCLUDE_DIR = src/include

# Package files
PKG_FILES = $(INCLUDE_DIR)/nmcu_pkg.sv \
			$(INCLUDE_DIR)/instr_pkg.sv

# DUT files
DUT_FILES = $(SRC_DIR)/chiplets/nmcu.sv \
			$(SRC_DIR)/contol/control_unit_decoder.sv \
			$(SRC_DIR)/pe/pe_array.sv \
			$(SRC_DIR)/pe/pe_array_interface.sv \
			$(SRC_DIR)/cache/cache_system.sv \
			$(SRC_DIR)/mem_ctrl/memory_interface.sv

# Testbench files
TB_FILES = $(TB_DIR)/nmcu_tb.sv \
           $(TB_DIR)/nmcu_tb.cpp

# Verilator output directory
OBJ_DIR = obj_dir

# Default target
all: compile run

# Compile the design
compile:
	$(VERILATOR) $(VERILATOR_FLAGS) \
		-I$(SRC_DIR) \
		-I$(INCLUDE_DIR) \
		$(PKG_FILES) \
		$(DUT_FILES) \
		$(TB_FILES)

# Run the simulation
run:
	./$(OBJ_DIR)/Vnmcu_tb

# Clean build artifacts
clean:
	rm -rf $(OBJ_DIR)
	rm -f *.vcd

.PHONY: all compile run clean
