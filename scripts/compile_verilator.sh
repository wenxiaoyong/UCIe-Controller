#!/bin/bash

# UCIe Controller Verilator Compilation Script
# This script compiles the UCIe RTL design using Verilator

set -e  # Exit on any error

# Configuration
PROJECT_ROOT="/Users/xiaoyongwen/UCIe"
RTL_DIR="${PROJECT_ROOT}/rtl"
TB_DIR="${RTL_DIR}/tb"
BUILD_DIR="${PROJECT_ROOT}/build"
SCRIPTS_DIR="${PROJECT_ROOT}/scripts"

# Verilator options
VERILATOR_OPTS=""
VERILATOR_OPTS+=" --cc"                    # Generate C++ output
VERILATOR_OPTS+=" --exe"                   # Generate executable
VERILATOR_OPTS+=" --build"                 # Build the executable
VERILATOR_OPTS+=" --trace"                 # Enable VCD tracing
VERILATOR_OPTS+=" --trace-depth 5"         # Trace depth
VERILATOR_OPTS+=" --timing"                # Enable timing simulation
VERILATOR_OPTS+=" -Wall"                   # Enable all warnings
VERILATOR_OPTS+=" -Wno-PINMISSING"         # Suppress pin missing warnings
VERILATOR_OPTS+=" -Wno-UNUSED"             # Suppress unused signal warnings
VERILATOR_OPTS+=" -Wno-UNOPTFLAT"          # Suppress optimization warnings
VERILATOR_OPTS+=" --top-module ucie_controller_tb"  # Top module
VERILATOR_OPTS+=" --Mdir ${BUILD_DIR}/obj_dir"      # Output directory

# Create build directory
echo "Creating build directory..."
mkdir -p "${BUILD_DIR}/obj_dir"
mkdir -p "${BUILD_DIR}/logs"

# Print configuration
echo "===== Verilator Compilation Configuration ====="
echo "Project Root: ${PROJECT_ROOT}"
echo "RTL Directory: ${RTL_DIR}"
echo "Build Directory: ${BUILD_DIR}"
echo "Verilator Options: ${VERILATOR_OPTS}"
echo "================================================"

# Check if Verilator is installed
if ! command -v verilator &> /dev/null; then
    echo "ERROR: Verilator not found. Please install Verilator first."
    echo "On macOS: brew install verilator"
    echo "On Ubuntu: sudo apt-get install verilator"
    exit 1
fi

echo "Verilator version: $(verilator --version)"

# List all RTL files to compile
RTL_FILES=""
RTL_FILES+=" ${RTL_DIR}/ucie_pkg.sv"
RTL_FILES+=" ${RTL_DIR}/d2d_adapter/ucie_crc_retry_engine.sv"
RTL_FILES+=" ${RTL_DIR}/d2d_adapter/ucie_stack_multiplexer.sv"
RTL_FILES+=" ${RTL_DIR}/d2d_adapter/ucie_param_exchange.sv"
RTL_FILES+=" ${RTL_DIR}/physical/ucie_lane_manager.sv"
RTL_FILES+=" ${RTL_DIR}/physical/ucie_sideband_engine.sv"
RTL_FILES+=" ${RTL_DIR}/protocol/ucie_protocol_layer.sv"
RTL_FILES+=" ${RTL_DIR}/ucie_controller_top.sv"
RTL_FILES+=" ${TB_DIR}/ucie_controller_tb.sv"

# Check if all RTL files exist
echo "Checking RTL files..."
for file in ${RTL_FILES}; do
    if [[ ! -f "$file" ]]; then
        echo "ERROR: RTL file not found: $file"
        exit 1
    else
        echo "  Found: $file"
    fi
done

# Create a simple C++ wrapper for the testbench
echo "Creating C++ testbench wrapper..."
cat > "${BUILD_DIR}/tb_main.cpp" << 'EOF'
#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vucie_controller_tb.h"

int main(int argc, char** argv) {
    // Initialize Verilator
    Verilated::commandArgs(argc, argv);
    
    // Create instance of our module under test
    Vucie_controller_tb* tb = new Vucie_controller_tb;
    
    // Enable tracing
    Verilated::traceEverOn(true);
    VerilatedVcdC* tfp = new VerilatedVcdC;
    tb->trace(tfp, 99);
    tfp->open("ucie_controller_sim.vcd");
    
    // Initialize simulation inputs
    vluint64_t sim_time = 0;
    const vluint64_t sim_time_max = 100000000; // 100ms simulation time
    
    printf("Starting UCIe Controller simulation...\n");
    
    // Run simulation
    while (sim_time < sim_time_max && !Verilated::gotFinish()) {
        // Evaluate model
        tb->eval();
        
        // Dump trace data
        tfp->dump(sim_time);
        
        // Increment time
        sim_time++;
    }
    
    // Close trace file
    tfp->close();
    
    // Cleanup
    delete tb;
    delete tfp;
    
    printf("Simulation completed. VCD file: ucie_controller_sim.vcd\n");
    
    return 0;
}
EOF

# Run Verilator compilation
echo "Starting Verilator compilation..."
echo "Command: verilator ${VERILATOR_OPTS} ${RTL_FILES} ${BUILD_DIR}/tb_main.cpp"

cd "${BUILD_DIR}"

# Run Verilator with error logging
if verilator ${VERILATOR_OPTS} ${RTL_FILES} tb_main.cpp 2>&1 | tee logs/verilator_compile.log; then
    echo "SUCCESS: Verilator compilation completed successfully!"
    echo "Executable created: ${BUILD_DIR}/obj_dir/Vucie_controller_tb"
    echo "Log file: ${BUILD_DIR}/logs/verilator_compile.log"
    
    # Check if executable was created
    if [[ -f "${BUILD_DIR}/obj_dir/Vucie_controller_tb" ]]; then
        echo "Executable verification: PASSED"
        echo ""
        echo "To run the simulation:"
        echo "  cd ${BUILD_DIR}"
        echo "  ./obj_dir/Vucie_controller_tb"
        echo ""
        echo "VCD waveform will be generated as: ucie_controller_sim.vcd"
    else
        echo "WARNING: Executable not found after compilation"
    fi
else
    echo "ERROR: Verilator compilation failed!"
    echo "Check the log file: ${BUILD_DIR}/logs/verilator_compile.log"
    exit 1
fi

echo "Compilation process completed."