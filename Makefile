# UCIe Controller Makefile
# Supports Verilator compilation and simulation

# Project configuration
PROJECT_ROOT := $(shell pwd)
RTL_DIR := $(PROJECT_ROOT)/rtl
TB_DIR := $(RTL_DIR)/tb
BUILD_DIR := $(PROJECT_ROOT)/build
SCRIPTS_DIR := $(PROJECT_ROOT)/scripts

# Verilator configuration
VERILATOR := verilator
VERILATOR_FLAGS := --cc --exe --build --trace --trace-depth 5 --timing
VERILATOR_FLAGS += -Wall -Wno-PINMISSING -Wno-UNUSED -Wno-UNOPTFLAT
VERILATOR_FLAGS += --top-module ucie_controller_tb
VERILATOR_FLAGS += --Mdir $(BUILD_DIR)/obj_dir

# RTL source files (for synthesis/lint)
RTL_SOURCES_SYNTH := \
	$(RTL_DIR)/ucie_pkg.sv \
	$(RTL_DIR)/common/ucie_common_pkg.sv \
	$(RTL_DIR)/interfaces/ucie_fdi_if.sv \
	$(RTL_DIR)/interfaces/ucie_rdi_if.sv \
	$(RTL_DIR)/interfaces/ucie_sideband_if.sv \
	$(RTL_DIR)/interfaces/ucie_phy_if.sv \
	$(RTL_DIR)/interfaces/ucie_config_if.sv \
	$(RTL_DIR)/interfaces/ucie_debug_if.sv \
	$(RTL_DIR)/common/ucie_interface_adapter.sv \
	$(RTL_DIR)/d2d_adapter/ucie_crc_retry_engine.sv \
	$(RTL_DIR)/d2d_adapter/ucie_stack_multiplexer.sv \
	$(RTL_DIR)/d2d_adapter/ucie_param_exchange.sv \
	$(RTL_DIR)/d2d_adapter/ucie_link_manager.sv \
	$(RTL_DIR)/physical/ucie_lane_manager.sv \
	$(RTL_DIR)/physical/ucie_sideband_engine.sv \
	$(RTL_DIR)/physical/ucie_link_training_fsm.sv \
	$(RTL_DIR)/protocol/ucie_protocol_layer.sv \
	$(RTL_DIR)/ucie_controller_top.sv

# RTL source files (including testbench for simulation)
RTL_SOURCES := \
	$(RTL_SOURCES_SYNTH) \
	$(TB_DIR)/ucie_controller_tb.sv

# C++ testbench wrapper
CPP_TB := $(BUILD_DIR)/tb_main.cpp

# Output executable
EXECUTABLE := $(BUILD_DIR)/obj_dir/Vucie_controller_tb

# VCD output file
VCD_FILE := $(BUILD_DIR)/ucie_controller_sim.vcd

# Default target
.PHONY: all
all: compile

# Check if Verilator is installed
.PHONY: check-verilator
check-verilator:
	@which $(VERILATOR) > /dev/null || (echo "ERROR: Verilator not found. Install with: brew install verilator" && exit 1)
	@echo "Verilator found: $$($(VERILATOR) --version)"

# Create build directories
$(BUILD_DIR):
	@echo "Creating build directory..."
	@mkdir -p $(BUILD_DIR)/obj_dir
	@mkdir -p $(BUILD_DIR)/logs

# Create C++ testbench wrapper
$(CPP_TB): $(BUILD_DIR)
	@echo "Creating C++ testbench wrapper..."
	@echo '#include <verilated.h>' > $(CPP_TB)
	@echo '#include <verilated_vcd_c.h>' >> $(CPP_TB)
	@echo '#include "Vucie_controller_tb.h"' >> $(CPP_TB)
	@echo '' >> $(CPP_TB)
	@echo 'int main(int argc, char** argv) {' >> $(CPP_TB)
	@echo '    Verilated::commandArgs(argc, argv);' >> $(CPP_TB)
	@echo '    Vucie_controller_tb* tb = new Vucie_controller_tb;' >> $(CPP_TB)
	@echo '    Verilated::traceEverOn(true);' >> $(CPP_TB)
	@echo '    VerilatedVcdC* tfp = new VerilatedVcdC;' >> $(CPP_TB)
	@echo '    tb->trace(tfp, 99);' >> $(CPP_TB)
	@echo '    tfp->open("ucie_controller_sim.vcd");' >> $(CPP_TB)
	@echo '    vluint64_t sim_time = 0;' >> $(CPP_TB)
	@echo '    const vluint64_t sim_time_max = 100000000;' >> $(CPP_TB)
	@echo '    printf("Starting UCIe Controller simulation...\\n");' >> $(CPP_TB)
	@echo '    while (sim_time < sim_time_max && !Verilated::gotFinish()) {' >> $(CPP_TB)
	@echo '        tb->eval();' >> $(CPP_TB)
	@echo '        tfp->dump(sim_time);' >> $(CPP_TB)
	@echo '        sim_time++;' >> $(CPP_TB)
	@echo '    }' >> $(CPP_TB)
	@echo '    tfp->close();' >> $(CPP_TB)
	@echo '    delete tb;' >> $(CPP_TB)
	@echo '    delete tfp;' >> $(CPP_TB)
	@echo '    printf("Simulation completed. VCD file: ucie_controller_sim.vcd\\n");' >> $(CPP_TB)
	@echo '    return 0;' >> $(CPP_TB)
	@echo '}' >> $(CPP_TB)

# Compile with Verilator
.PHONY: compile
compile: check-verilator $(BUILD_DIR) $(CPP_TB)
	@echo "===== Starting Verilator Compilation ====="
	@echo "RTL Sources:"
	@for file in $(RTL_SOURCES); do echo "  $$file"; done
	@echo "=========================================="
	@cd $(BUILD_DIR) && \
	$(VERILATOR) $(VERILATOR_FLAGS) $(RTL_SOURCES) $(CPP_TB) 2>&1 | tee logs/verilator_compile.log
	@if [ -f $(EXECUTABLE) ]; then \
		echo "SUCCESS: Compilation completed!"; \
		echo "Executable: $(EXECUTABLE)"; \
	else \
		echo "ERROR: Compilation failed!"; \
		echo "Check log: $(BUILD_DIR)/logs/verilator_compile.log"; \
		exit 1; \
	fi

# Run simulation
.PHONY: sim
sim: compile
	@echo "===== Running UCIe Controller Simulation ====="
	@cd $(BUILD_DIR) && ./obj_dir/Vucie_controller_tb
	@if [ -f $(VCD_FILE) ]; then \
		echo "VCD file generated: $(VCD_FILE)"; \
		echo "View with: gtkwave $(VCD_FILE)"; \
	fi

# Run simulation with custom time
.PHONY: sim-time
sim-time: compile
	@echo "===== Running UCIe Controller Simulation (Custom Time) ====="
	@cd $(BUILD_DIR) && timeout 10s ./obj_dir/Vucie_controller_tb || echo "Simulation completed or timed out"

# Lint RTL code only (synthesis)
.PHONY: lint
lint: check-verilator $(BUILD_DIR)
	@echo "===== Linting RTL Code (Synthesis) ====="
	@cd $(BUILD_DIR) && \
	$(VERILATOR) --lint-only --no-timing -Wall $(RTL_SOURCES_SYNTH) 2>&1 | tee logs/verilator_lint.log
	@echo "Lint results saved to: $(BUILD_DIR)/logs/verilator_lint.log"

# Lint testbench and all RTL code
.PHONY: lint-tb
lint-tb: check-verilator $(BUILD_DIR)
	@echo "===== Linting Testbench and RTL Code ====="
	@cd $(BUILD_DIR) && \
	$(VERILATOR) --lint-only --timing -Wall --top ucie_controller_tb $(RTL_SOURCES) 2>&1 | tee logs/verilator_lint_tb.log
	@echo "Testbench lint results saved to: $(BUILD_DIR)/logs/verilator_lint_tb.log"

# Lint all code (synthesis + testbench)
.PHONY: lint-all
lint-all: lint lint-tb
	@echo "===== All Lint Checks Complete ====="

# Clean build artifacts
.PHONY: clean
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR)/obj_dir
	@rm -f $(BUILD_DIR)/*.vcd
	@rm -f $(BUILD_DIR)/tb_main.cpp
	@rm -f $(BUILD_DIR)/logs/*.log

# Deep clean - remove entire build directory
.PHONY: distclean
distclean:
	@echo "Deep cleaning all build artifacts..."
	@rm -rf $(BUILD_DIR)

# Show help
.PHONY: help
help:
	@echo "UCIe Controller Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Default target (same as compile)"
	@echo "  compile      - Compile RTL with Verilator"
	@echo "  sim          - Compile and run simulation"
	@echo "  sim-time     - Run simulation with 10s timeout"
	@echo "  lint         - Lint RTL code only (synthesis)"
	@echo "  lint-tb      - Lint testbench and all RTL code"
	@echo "  lint-all     - Run all lint checks"
	@echo "  clean        - Clean build artifacts"
	@echo "  distclean    - Remove entire build directory"
	@echo "  status       - Show project status"
	@echo "  list-sources - List all RTL source files"
	@echo "  help         - Show this help"
	@echo ""
	@echo "Requirements:"
	@echo "  - Verilator (install with: brew install verilator)"
	@echo "  - C++ compiler (clang/gcc)"
	@echo ""
	@echo "Example usage:"
	@echo "  make compile    # Compile the design"
	@echo "  make sim        # Run full simulation"
	@echo "  make lint       # Check for RTL issues"

# Show project status
.PHONY: status
status:
	@echo "===== Project Status ====="
	@echo "Project Root: $(PROJECT_ROOT)"
	@echo "Build Dir: $(BUILD_DIR)"
	@echo "RTL Sources: $(words $(RTL_SOURCES)) files"
	@echo ""
	@echo "Build Status:"
	@if [ -f $(EXECUTABLE) ]; then \
		echo "  Executable: EXISTS ($(EXECUTABLE))"; \
	else \
		echo "  Executable: NOT FOUND"; \
	fi
	@if [ -f $(VCD_FILE) ]; then \
		echo "  VCD File: EXISTS ($(VCD_FILE))"; \
	else \
		echo "  VCD File: NOT FOUND"; \
	fi
	@echo ""
	@echo "Verilator Status:"
	@which $(VERILATOR) > /dev/null && echo "  Verilator: INSTALLED ($$($(VERILATOR) --version))" || echo "  Verilator: NOT FOUND"

.PHONY: list-sources
list-sources:
	@echo "RTL Source Files:"
	@for file in $(RTL_SOURCES); do \
		if [ -f "$$file" ]; then \
			echo "  ✓ $$file"; \
		else \
			echo "  ✗ $$file (MISSING)"; \
		fi \
	done