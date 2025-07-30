interface ucie_debug_if #(
    parameter NUM_LANES = 64,
    parameter NUM_PROTOCOLS = 4
) (
    input logic clk,
    input logic resetn
);

    import ucie_pkg::*;
    
    // Link State Debug
    link_state_t               link_state;
    training_state_t           training_state;
    power_state_t              power_state;
    micro_power_state_t        micro_power_state;
    
    // Lane Debug Information
    logic [NUM_LANES-1:0]      lane_status;
    logic [NUM_LANES-1:0]      lane_errors;
    logic [7:0]                lane_ber_count [NUM_LANES-1:0];
    logic [NUM_LANES-1:0]      lane_repair_active;
    
    // Protocol Debug
    logic [NUM_PROTOCOLS-1:0]  protocol_active;
    logic [15:0]              protocol_tx_count [NUM_PROTOCOLS-1:0];
    logic [15:0]              protocol_rx_count [NUM_PROTOCOLS-1:0];
    logic [7:0]               protocol_errors [NUM_PROTOCOLS-1:0];
    
    // Performance Counters
    logic [31:0]              performance_counters [15:0];
    logic [15:0]              bandwidth_utilization;
    logic [15:0]              latency_measurements [7:0];
    
    // Thermal Debug
    logic [7:0]               thermal_status;
    logic [7:0]               die_temperature;
    logic                     thermal_throttle_active;
    logic [NUM_LANES-1:0]     lane_thermal_status;
    
    // Power Debug
    logic [15:0]              power_consumption_mw;
    logic [7:0]               power_domain_status;
    logic                     power_budget_alarm;
    logic [7:0]               voltage_levels [2:0];
    logic [7:0]               frequency_levels [2:0];
    
    // ML Optimization Debug
    logic                     ml_active;
    logic [7:0]               ml_prediction_accuracy;
    logic [7:0]               ml_bandwidth_prediction;
    logic [3:0]               ml_optimization_level;
    
    // Multi-Module Debug
    logic                     multi_module_active;
    logic [3:0]               module_coordination_state;
    logic [7:0]               module_status_vector;
    logic [7:0]               bandwidth_sharing [3:0];
    
    // Error Debug
    logic [15:0]              total_error_count;
    logic [7:0]               crc_error_count;
    logic [7:0]               sequence_error_count;
    logic [7:0]               timeout_error_count;
    logic                     error_recovery_active;
    
    // Training Debug
    logic [31:0]              training_statistics;
    logic [15:0]              successful_trainings;
    logic [15:0]              failed_trainings;
    logic [15:0]              training_time_cycles;
    
    // Sideband Debug
    logic [15:0]              sideband_tx_count;
    logic [15:0]              sideband_rx_count;
    logic [7:0]               sideband_error_count;
    logic                     sideband_link_active;
    
    // Advanced Debug Features
    logic [31:0]              debug_trigger_mask;
    logic                     debug_capture_enable;
    logic [31:0]              debug_timestamp;
    logic [63:0]              debug_trace_buffer [255:0];
    logic [7:0]               debug_trace_ptr;
    
    // Real-time Monitoring
    logic [15:0]              realtime_bandwidth_mbps;
    logic [15:0]              realtime_latency_ns;
    logic [7:0]               realtime_error_rate;
    logic [7:0]               realtime_temperature_c;

    modport device (
        input  clk, resetn, debug_trigger_mask, debug_capture_enable,
        output link_state, training_state, power_state, micro_power_state,
               lane_status, lane_errors, lane_ber_count, lane_repair_active,
               protocol_active, protocol_tx_count, protocol_rx_count, protocol_errors,
               performance_counters, bandwidth_utilization, latency_measurements,
               thermal_status, die_temperature, thermal_throttle_active, lane_thermal_status,
               power_consumption_mw, power_domain_status, power_budget_alarm,
               voltage_levels, frequency_levels, ml_active, ml_prediction_accuracy,
               ml_bandwidth_prediction, ml_optimization_level, multi_module_active,
               module_coordination_state, module_status_vector, bandwidth_sharing,
               total_error_count, crc_error_count, sequence_error_count,
               timeout_error_count, error_recovery_active, training_statistics,
               successful_trainings, failed_trainings, training_time_cycles,
               sideband_tx_count, sideband_rx_count, sideband_error_count,
               sideband_link_active, debug_timestamp, debug_trace_buffer,
               debug_trace_ptr, realtime_bandwidth_mbps, realtime_latency_ns,
               realtime_error_rate, realtime_temperature_c
    );
    
    modport controller (
        input  clk, resetn, link_state, training_state, power_state, micro_power_state,
               lane_status, lane_errors, lane_ber_count, lane_repair_active,
               protocol_active, protocol_tx_count, protocol_rx_count, protocol_errors,
               performance_counters, bandwidth_utilization, latency_measurements,
               thermal_status, die_temperature, thermal_throttle_active, lane_thermal_status,
               power_consumption_mw, power_domain_status, power_budget_alarm,
               voltage_levels, frequency_levels, ml_active, ml_prediction_accuracy,
               ml_bandwidth_prediction, ml_optimization_level, multi_module_active,
               module_coordination_state, module_status_vector, bandwidth_sharing,
               total_error_count, crc_error_count, sequence_error_count,
               timeout_error_count, error_recovery_active, training_statistics,
               successful_trainings, failed_trainings, training_time_cycles,
               sideband_tx_count, sideband_rx_count, sideband_error_count,
               sideband_link_active, debug_timestamp, debug_trace_buffer,
               debug_trace_ptr, realtime_bandwidth_mbps, realtime_latency_ns,
               realtime_error_rate, realtime_temperature_c,
        output debug_trigger_mask, debug_capture_enable
    );

endinterface