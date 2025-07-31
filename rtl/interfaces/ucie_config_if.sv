interface ucie_config_if #(
    parameter NUM_PROTOCOLS = 4,
    parameter NUM_LANES = 64,
    parameter MAX_SPEED_GBPS = 128
) (
    input logic clk,
    input logic rst_n
);

    import ucie_pkg::*;
    
    // ========================================================================
    // Protocol Configuration
    // ========================================================================
    
    // Protocol Enable Control
    logic [NUM_PROTOCOLS-1:0]      protocol_enable;     // Enable mask for protocols
    logic [NUM_PROTOCOLS-1:0][3:0] protocol_priority;   // Priority per protocol
    logic [NUM_PROTOCOLS-1:0]      protocol_active;     // Active status per protocol
    
    // Protocol-Specific Configuration
    logic [1:0]                    pcie_mode;           // PCIe mode configuration
    logic [2:0]                    cxl_mode;            // CXL stack configuration
    logic [7:0]                    streaming_config;    // Streaming protocol config
    logic [7:0]                    mgmt_transport_cfg;  // Management transport config
    
    // Virtual Channel Configuration
    logic [7:0]                    num_virtual_channels;
    logic [7:0][3:0]              vc_priority;         // Priority per VC
    logic [7:0][15:0]             vc_buffer_size;      // Buffer size per VC
    
    // ========================================================================
    // Physical Layer Configuration
    // ========================================================================
    
    // Speed and Width Configuration
    logic [7:0]                    target_speed;        // Target link speed (GT/s)
    logic [7:0]                    target_width;        // Target link width
    logic [7:0]                    current_speed;       // Current operational speed
    logic [NUM_LANES-1:0]         active_lanes;        // Currently active lanes
    
    // Package Type Configuration
    logic [1:0]                    package_type;        // 0=Standard, 1=Advanced, 2=UCIe-3D
    logic                          supports_advanced;   // Advanced package support
    logic                          supports_3d;         // 3D package support
    
    // Signaling Configuration
    logic                          pam4_enable;         // Enable PAM4 signaling
    logic                          pam4_active;         // PAM4 currently active
    logic [3:0]                    signaling_mode;      // Current signaling mode
    
    // ========================================================================
    // Enhanced 128 Gbps Configuration
    // ========================================================================
    
    // Multi-Domain Power Configuration
    logic                          multi_domain_enable; // Enable multi-domain power
    logic [2:0]                    power_domain_config; // Power domain settings
    logic                          avfs_enable;         // Adaptive voltage/frequency scaling
    logic [7:0]                    power_budget_limit;  // Power budget constraint
    
    // Advanced Pipeline Configuration
    logic                          quarter_rate_enable; // Enable quarter-rate processing
    logic [2:0]                    pipeline_stages;     // Number of pipeline stages
    logic                          zero_latency_bypass; // Enable zero-latency bypass
    
    // ML Optimization Configuration
    logic                          ml_optimization_enable;    // Enable ML features
    logic [3:0]                    ml_prediction_mode;        // ML prediction configuration
    logic                          ml_adaptation_enable;      // Enable ML adaptation
    logic [7:0]                    ml_learning_rate;          // ML learning rate parameter
    
    // ========================================================================
    // Buffer and Flow Control Configuration
    // ========================================================================
    
    // Buffer Configuration
    logic [15:0]                   protocol_buffer_depth; // Protocol layer buffer depth
    logic [15:0]                   d2d_buffer_depth;      // D2D adapter buffer depth
    logic [15:0]                   retry_buffer_depth;    // Retry buffer depth
    
    // Flow Control Configuration
    logic [7:0]                    credit_return_threshold; // Credit return threshold
    logic [15:0]                   flow_control_timeout;    // Flow control timeout
    logic                          adaptive_flow_control;   // Enable adaptive flow control
    
    // Buffer Status (Read-only)
    logic [15:0]                   buffer_status;         // Current buffer occupancy
    logic [7:0]                    buffer_utilization;    // Buffer utilization percentage
    
    // ========================================================================
    // Status and Statistics (Read-Only)
    // ========================================================================
    
    // Link Status
    logic                          link_up;               // Link is operational
    logic [3:0]                    link_state;            // Current link state
    logic [7:0]                    link_quality;          // Link quality metric
    logic [31:0]                   link_uptime;           // Link uptime counter
    
    // Thermal Status
    logic                          thermal_throttle;      // Thermal throttling active
    logic [7:0]                    current_temperature;   // Current die temperature
    logic [7:0]                    thermal_zone_temps[7:0]; // Per-zone temperatures
    
    // Performance Statistics
    logic [31:0]                   bandwidth_utilization; // Bandwidth utilization
    logic [31:0]                   packet_count_tx;       // TX packet counter
    logic [31:0]                   packet_count_rx;       // RX packet counter
    logic [31:0]                   error_count_total;     // Total error counter
    logic [31:0]                   error_count_correctable; // Correctable error counter

    // ========================================================================
    // Modport Definitions
    // ========================================================================
    
    modport device (
        input  clk, rst_n,
        
        // Configuration inputs from system
        input  protocol_enable, protocol_priority, pcie_mode, cxl_mode,
               streaming_config, mgmt_transport_cfg, num_virtual_channels,
               vc_priority, vc_buffer_size,
               target_speed, target_width, package_type,
               pam4_enable, multi_domain_enable, power_domain_config,
               avfs_enable, power_budget_limit, quarter_rate_enable,
               pipeline_stages, zero_latency_bypass, ml_optimization_enable,
               ml_prediction_mode, ml_adaptation_enable, ml_learning_rate,
               protocol_buffer_depth, d2d_buffer_depth, retry_buffer_depth,
               credit_return_threshold, flow_control_timeout, adaptive_flow_control,
               
        // Status outputs to system
        output protocol_active, current_speed, active_lanes, supports_advanced,
               supports_3d, pam4_active, signaling_mode, buffer_status,
               buffer_utilization, link_up, link_state, link_quality, link_uptime,
               thermal_throttle, current_temperature, thermal_zone_temps,
               bandwidth_utilization, packet_count_tx, packet_count_rx,
               error_count_total, error_count_correctable
    );
    
    modport controller (
        input  clk, rst_n,
               protocol_enable, protocol_priority, pcie_mode, cxl_mode,
               streaming_config, mgmt_transport_cfg, num_virtual_channels,
               vc_priority, vc_buffer_size, target_speed, target_width,
               package_type, pam4_enable, multi_domain_enable,
               power_domain_config, avfs_enable, power_budget_limit,
               quarter_rate_enable, pipeline_stages, zero_latency_bypass,
               ml_optimization_enable, ml_prediction_mode, ml_adaptation_enable,
               ml_learning_rate, protocol_buffer_depth, d2d_buffer_depth,
               retry_buffer_depth, credit_return_threshold, flow_control_timeout,
               adaptive_flow_control,
               
        output protocol_active, current_speed, active_lanes, supports_advanced,
               supports_3d, pam4_active, signaling_mode, buffer_status,
               buffer_utilization, link_up, link_state, link_quality, link_uptime,
               thermal_throttle, current_temperature, thermal_zone_temps,
               bandwidth_utilization, packet_count_tx, packet_count_rx,
               error_count_total, error_count_correctable
    );
    
    modport testbench (
        input  clk, rst_n,
        inout  protocol_enable, protocol_priority, protocol_active,
               target_speed, current_speed, active_lanes, pam4_enable,
               pam4_active, ml_optimization_enable, thermal_throttle,
               link_up, link_state, quarter_rate_enable, zero_latency_bypass
    );

endinterface
