interface ucie_debug_if #(
    parameter NUM_LANES = 64,
    parameter NUM_PROTOCOLS = 4,
    parameter DEBUG_BUS_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);

    import ucie_pkg::*;
    
    // ========================================================================
    // Link State Debug
    // ========================================================================
    
    // Link Training State
    logic [3:0]                    link_state;           // Current link training state
    logic [3:0]                    power_state;          // Current power state
    logic [7:0]                    thermal_status;       // Thermal management status
    logic [15:0]                   performance_counters; // Real-time performance metrics
    logic                          ml_active;            // ML optimization status
    logic                          multi_module_active;  // Multi-module coordination status
    
    // Protocol Layer Debug
    logic [NUM_PROTOCOLS-1:0]      protocol_active;      // Active protocols
    logic [NUM_PROTOCOLS-1:0][7:0] protocol_utilization; // Protocol bandwidth utilization
    logic [NUM_PROTOCOLS-1:0][15:0] protocol_errors;     // Protocol-specific error counts
    
    // ========================================================================
    // Physical Layer Debug (128 Gbps Enhanced)
    // ========================================================================
    
    // Lane Status Debug
    logic [NUM_LANES-1:0]          lane_active;          // Per-lane active status
    logic [NUM_LANES-1:0]          lane_trained;         // Per-lane training status
    logic [NUM_LANES-1:0]          lane_error;           // Per-lane error status
    logic [NUM_LANES-1:0][7:0]     lane_ber_status;      // Per-lane BER status
    
    // PAM4 and Equalization Debug
    logic [NUM_LANES-1:0]          pam4_active;          // PAM4 mode per lane
    logic [NUM_LANES-1:0][7:0]     dfe_status;           // DFE status per lane
    logic [NUM_LANES-1:0][7:0]     ffe_status;           // FFE status per lane
    logic [NUM_LANES-1:0][7:0]     eye_height;           // Eye height per lane
    logic [NUM_LANES-1:0][7:0]     eye_width;            // Eye width per lane
    
    // Signal Integrity Debug
    logic [NUM_LANES-1:0][15:0]    signal_quality;       // Per-lane signal quality
    logic [NUM_LANES-1:0]          signal_alarm;         // Per-lane signal quality alarm
    logic [NUM_LANES-1:0][7:0]     crosstalk_level;      // Crosstalk level per lane
    
    // ========================================================================
    // Advanced Debug Features (128 Gbps)
    // ========================================================================
    
    // Thermal Debug (64 Sensors)
    logic [63:0][7:0]             thermal_sensor_data;   // Individual sensor readings
    logic [7:0]                   thermal_zone_status;   // 8-zone thermal status
    logic [1:0]                   thermal_throttle_level; // Current throttle level
    
    // Power Domain Debug
    logic [2:0]                   power_domain_status;   // 0.6V/0.8V/1.0V domain status
    logic [7:0]                   power_consumption;     // Current power consumption
    logic [7:0]                   power_efficiency;      // Power efficiency metric
    
    // ML Optimization Debug
    logic [7:0]                   ml_prediction_accuracy; // ML prediction accuracy
    logic [7:0]                   ml_bandwidth_prediction; // Bandwidth prediction
    logic [7:0]                   ml_adaptation_rate;     // Adaptation rate
    logic                         ml_learning_active;     // Learning process active
    
    // ========================================================================
    // Debug Control and Configuration
    // ========================================================================
    
    // Debug Mode Control
    logic                         debug_enable;          // Master debug enable
    logic [3:0]                   debug_mode;            // Debug mode selection
    logic [7:0]                   debug_target_select;   // Target selection for debug
    logic                         compliance_mode;       // Compliance test mode
    
    // ========================================================================
    // Observability and Monitoring
    // ========================================================================
    
    // Debug Bus and Multiplexing
    logic [DEBUG_BUS_WIDTH-1:0]   debug_bus;             // Main debug output bus
    logic [7:0]                   debug_bus_select;      // Debug bus multiplexer select
    logic                         debug_bus_valid;       // Debug bus data valid
    
    // Performance Monitoring
    logic [31:0]                  bandwidth_utilization; // Total bandwidth utilization
    logic [31:0]                  packet_count_tx;       // TX packet counter
    logic [31:0]                  packet_count_rx;       // RX packet counter
    logic [31:0]                  cycle_count;           // Cycle counter
    logic [31:0]                  idle_count;            // Idle cycle counter
    
    // Error and Event Counters
    logic [31:0]                  total_error_count;     // Total error counter
    logic [31:0]                  correctable_error_count; // Correctable error counter
    logic [31:0]                  uncorrectable_error_count; // Uncorrectable error counter
    logic [31:0]                  training_event_count;  // Training event counter
    logic [31:0]                  power_event_count;     // Power state change counter
    
    // ========================================================================
    // Real-Time Debug Data Streaming
    // ========================================================================
    
    // Debug Data Streaming Interface
    logic                         stream_enable;         // Enable debug streaming
    logic [31:0]                  stream_data;           // Streaming debug data
    logic                         stream_valid;          // Stream data valid
    logic                         stream_ready;          // Stream ready (backpressure)
    logic [3:0]                   stream_type;           // Stream data type identifier
    
    // Time Stamping
    logic [63:0]                  timestamp;             // High-resolution timestamp
    logic                         timestamp_valid;       // Timestamp valid

    // ========================================================================
    // Modport Definitions
    // ========================================================================
    
    modport device (
        input  clk, rst_n,
               debug_enable, debug_mode, debug_target_select, compliance_mode,
               debug_bus_select, stream_ready,
               
        output link_state, power_state, thermal_status, performance_counters,
               ml_active, multi_module_active, protocol_active,
               protocol_utilization, protocol_errors, lane_active, lane_trained,
               lane_error, lane_ber_status, pam4_active, dfe_status, ffe_status,
               eye_height, eye_width, signal_quality, signal_alarm,
               crosstalk_level, thermal_sensor_data, thermal_zone_status,
               thermal_throttle_level, power_domain_status, power_consumption,
               power_efficiency, ml_prediction_accuracy, ml_bandwidth_prediction,
               ml_adaptation_rate, ml_learning_active, debug_bus, debug_bus_valid,
               bandwidth_utilization, packet_count_tx, packet_count_rx,
               cycle_count, idle_count, total_error_count,
               correctable_error_count, uncorrectable_error_count,
               training_event_count, power_event_count,
               stream_data, stream_valid, stream_type, timestamp, timestamp_valid
    );
    
    modport controller (
        input  clk, rst_n,
               link_state, power_state, thermal_status, performance_counters,
               ml_active, multi_module_active, protocol_active,
               protocol_utilization, protocol_errors, lane_active, lane_trained,
               lane_error, lane_ber_status, pam4_active, dfe_status, ffe_status,
               eye_height, eye_width, signal_quality, signal_alarm,
               crosstalk_level, thermal_sensor_data, thermal_zone_status,
               thermal_throttle_level, power_domain_status, power_consumption,
               power_efficiency, ml_prediction_accuracy, ml_bandwidth_prediction,
               ml_adaptation_rate, ml_learning_active, debug_bus, debug_bus_valid,
               bandwidth_utilization, packet_count_tx, packet_count_rx,
               cycle_count, idle_count, total_error_count,
               correctable_error_count, uncorrectable_error_count,
               training_event_count, power_event_count,
               stream_data, stream_valid, stream_type, timestamp, timestamp_valid,
               stream_ready,
               
        output debug_enable, debug_mode, debug_target_select, compliance_mode,
               debug_bus_select, stream_enable
    );
    
    modport testbench (
        input  clk, rst_n,
        inout  debug_enable, debug_mode, compliance_mode, link_state,
               power_state, lane_active, lane_trained, pam4_active,
               ml_active, thermal_status, debug_bus, stream_enable,
               bandwidth_utilization, total_error_count
    );
    
    modport monitor (
        input  clk, rst_n,
               link_state, power_state, thermal_status, performance_counters,
               protocol_active, lane_active, lane_trained, signal_quality,
               thermal_sensor_data, power_consumption, debug_bus,
               bandwidth_utilization, packet_count_tx, packet_count_rx,
               total_error_count, stream_data, stream_valid, timestamp
    );

endinterface
