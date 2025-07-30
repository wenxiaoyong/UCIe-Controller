#!/bin/bash

# Simple compilation check for UCIe project
echo "Checking UCIe SystemVerilog compilation..."

# Try to compile all modules together
echo "Attempting compilation with all modules..."

iverilog -g2012 -I./rtl \
    rtl/ucie_pkg.sv \
    rtl/interfaces/ucie_rdi_if.sv \
    rtl/interfaces/ucie_fdi_if.sv \
    rtl/interfaces/ucie_sideband_if.sv \
    rtl/protocol/ucie_protocol_layer.sv \
    rtl/d2d_adapter/ucie_crc_retry_engine.sv \
    rtl/d2d_adapter/ucie_param_exchange.sv \
    rtl/d2d_adapter/ucie_link_manager.sv \
    rtl/d2d_adapter/ucie_stack_multiplexer.sv \
    rtl/physical/ucie_lane_manager.sv \
    rtl/physical/ucie_sideband_engine.sv \
    rtl/physical/ucie_link_training_fsm.sv \
    rtl/ucie_controller_top.sv \
    -o ucie_compile_test 2>&1

echo "Compilation check completed."