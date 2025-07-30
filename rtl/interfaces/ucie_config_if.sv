interface ucie_config_if #(
    parameter NUM_PROTOCOLS = 4,
    parameter NUM_MODULES = 4,
    parameter MAX_LANES = 64
) (
    input logic clk,
    input logic resetn
);

    import ucie_pkg::*;
    
    // Protocol Configuration
    logic [NUM_PROTOCOLS-1:0]   protocol_enable;
    logic [7:0]                protocol_priority [NUM_PROTOCOLS-1:0];
    logic [NUM_PROTOCOLS-1:0]   protocol_active;
    
    // Physical Configuration
    data_rate_t                target_speed;
    logic [7:0]                target_width;
    package_type_t             package_type;
    signaling_mode_t           signaling_mode;
    
    // Current Status (read-only)
    logic                      link_up;
    logic [7:0]                current_speed;
    logic [MAX_LANES-1:0]      active_lanes;
    logic                      pam4_active;
    logic                      thermal_throttle;
    
    // Buffer Configuration
    logic [15:0]               buffer_depth [NUM_PROTOCOLS-1:0];
    logic [7:0]                buffer_status [NUM_PROTOCOLS-1:0];
    
    // Power Management Configuration
    power_state_t              power_state_req;
    power_state_t              power_state_current;
    micro_power_state_t        micro_power_state;
    logic [7:0]                power_budget_percent;
    
    // Multi-Module Configuration
    logic [NUM_MODULES-1:0]    module_enable;
    logic [1:0]                module_id;
    logic                      multi_module_active;
    
    // Advanced Features Configuration
    logic                      ml_optimization_enable;
    logic                      thermal_management_enable;
    logic                      advanced_eq_enable;
    logic                      lane_repair_enable;
    
    // Debug and Monitoring
    logic [31:0]               debug_control;
    logic [31:0]               debug_status;
    logic [15:0]               performance_counters [7:0];
    
    // Error Configuration
    logic                      error_injection_enable;
    logic [3:0]                error_injection_type;
    logic [7:0]                error_threshold;

    modport device (
        input  clk, resetn, protocol_enable, protocol_priority, target_speed,
               target_width, package_type, signaling_mode, buffer_depth,
               power_state_req, power_budget_percent, module_enable, module_id,
               ml_optimization_enable, thermal_management_enable, advanced_eq_enable,
               lane_repair_enable, debug_control, error_injection_enable,
               error_injection_type, error_threshold,
        output protocol_active, link_up, current_speed, active_lanes, pam4_active,
               thermal_throttle, buffer_status, power_state_current, micro_power_state,
               multi_module_active, debug_status, performance_counters
    );
    
    modport controller (
        input  clk, resetn,
        output protocol_enable, protocol_priority, target_speed, target_width,
               package_type, signaling_mode, buffer_depth, power_state_req,
               power_budget_percent, module_enable, module_id, ml_optimization_enable,
               thermal_management_enable, advanced_eq_enable, lane_repair_enable,
               debug_control, error_injection_enable, error_injection_type, error_threshold,
        input  protocol_active, link_up, current_speed, active_lanes, pam4_active,
               thermal_throttle, buffer_status, power_state_current, micro_power_state,
               multi_module_active, debug_status, performance_counters
    );

endinterface