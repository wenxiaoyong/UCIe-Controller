module ucie_controller #(
    parameter PACKAGE_TYPE = "ADVANCED",    // STANDARD, ADVANCED, UCIe_3D
    parameter MODULE_WIDTH = 64,            // 8, 16, 32, 64
    parameter NUM_MODULES = 1,              // 1-4
    parameter MAX_SPEED = 128,              // 4, 8, 12, 16, 24, 32, 64, 128 GT/s
    parameter SIGNALING_MODE = "PAM4",      // NRZ, PAM4 (PAM4 required for >64 GT/s)
    parameter POWER_OPTIMIZATION = 1,       // 0=Standard, 1=Ultra-low power mode
    parameter MODULE_ID = 0,                // This module's ID (0-3)
    parameter ENABLE_ML_OPTIMIZATION = 1,   // Enable ML-enhanced features
    parameter ENABLE_ADVANCED_FEATURES = 1  // Enable advanced architectural features
) (
    // Application Layer Interfaces
    input  logic        app_clk,
    input  logic        app_resetn,
    ucie_rdi_if.device  rdi,
    ucie_fdi_if.device  fdi,
    
    // Physical Interface
    ucie_phy_if.controller phy,
    
    // Configuration and Control
    ucie_config_if.device config,
    ucie_debug_if.device  debug,
    
    // Multi-Module Coordination (when NUM_MODULES > 1)
    input  logic [NUM_MODULES-1:0] module_sync_clk,
    input  logic [NUM_MODULES-1:0] module_sync_reset_n,
    output logic                   module_coord_valid,
    output logic [31:0]           module_coord_data,
    input  logic [NUM_MODULES-1:0] module_coord_ready,
    
    // Enhanced Clock Domains for 128 Gbps
    input  logic        clk_symbol_64g,     // 64 GHz symbol clock
    input  logic        clk_quarter_16g,    // 16 GHz quarter-rate clock
    input  logic        clk_sideband_800m,  // 800 MHz sideband clock
    input  logic        clk_app,            // Application clock domain
    
    // Multi-Domain Power Management
    input  logic        power_domain_0v6_en,  // 0.6V domain enable
    input  logic        power_domain_0v8_en,  // 0.8V domain enable  
    input  logic        power_domain_1v0_en,  // 1.0V domain enable
    output logic [2:0]  power_domain_status,  // Power domain status
    
    // Advanced System Signals
    input  logic [7:0]  die_temperature,     // Die temperature for thermal management
    output logic        thermal_throttle,    // Thermal throttling active
    output logic [15:0] system_performance,  // System performance metrics
    output logic        ml_optimization_active // ML optimization status
);

import ucie_pkg::*;

// ============================================================================
// Internal Signal Declarations
// ============================================================================

// Clock Domain Crossing Signals
logic rst_symbol_n, rst_quarter_n, rst_sideband_n;

// Interface Adapter to Protocol Layer Signals
logic [FLIT_WIDTH-1:0] ul_tx_flit [4-1:0];
logic [4-1:0]         ul_tx_valid;
logic [4-1:0]         ul_tx_ready;
logic [7:0]           ul_tx_vc [4-1:0];

logic [FLIT_WIDTH-1:0] ul_rx_flit [4-1:0];
logic [4-1:0]         ul_rx_valid;
logic [4-1:0]         ul_rx_ready;
logic [7:0]           ul_rx_vc [4-1:0];

// Protocol Layer Signals
logic [FLIT_WIDTH-1:0] protocol_to_d2d_flit;
logic                  protocol_to_d2d_valid;
logic                  protocol_to_d2d_ready;
logic [3:0]           protocol_to_d2d_protocol_id;
logic [7:0]           protocol_to_d2d_vc;

logic [FLIT_WIDTH-1:0] d2d_to_protocol_flit;
logic                  d2d_to_protocol_valid;
logic                  d2d_to_protocol_ready;
logic [3:0]           d2d_to_protocol_protocol_id;
logic [7:0]           d2d_to_protocol_vc;

// D2D Adapter Signals
logic [FLIT_WIDTH-1:0] d2d_to_phy_flit;
logic                  d2d_to_phy_valid;
logic                  d2d_to_phy_ready;
logic                  d2d_link_up;
logic [7:0]           d2d_link_status;

logic [FLIT_WIDTH-1:0] phy_to_d2d_flit;
logic                  phy_to_d2d_valid;
logic                  phy_to_d2d_ready;

// Physical Layer Signals
logic                  phy_link_trained;
logic [MODULE_WIDTH-1:0] phy_lanes_active;
logic [7:0]           phy_link_speed;
logic                  phy_pam4_mode;

// Power Management Signals
power_state_t         current_power_state;
micro_power_state_t   current_micro_state;
logic                 power_transition_req;
logic                 power_transition_ack;

// Multi-Module Coordination Signals
logic [NUM_MODULES-1:0] module_sync_valid;
logic [31:0]           module_sync_data [NUM_MODULES-1:0];
logic                  multi_module_active;

// Advanced Feature Signals
logic                  ml_prediction_valid;
logic [7:0]           ml_bandwidth_prediction;
logic                  thermal_management_active;
logic [15:0]          performance_counters;

// ============================================================================
// Clock Domain Crossing and Reset Synchronization
// ============================================================================

// Reset synchronizers for each clock domain
ucie_reset_synchronizer u_rst_sync_symbol (
    .clk        (clk_symbol_64g),
    .async_rst_n(app_resetn),
    .sync_rst_n (rst_symbol_n)
);

ucie_reset_synchronizer u_rst_sync_quarter (
    .clk        (clk_quarter_16g),
    .async_rst_n(app_resetn),
    .sync_rst_n (rst_quarter_n)
);

ucie_reset_synchronizer u_rst_sync_sideband (
    .clk        (clk_sideband_800m),
    .async_rst_n(app_resetn),
    .sync_rst_n (rst_sideband_n)
);

// ============================================================================
// Interface Adapter (RDI/FDI to Protocol Arrays)
// ============================================================================

ucie_interface_adapter #(
    .NUM_PROTOCOLS(4),
    .NUM_VCS(8)
) u_interface_adapter (
    .clk(app_clk),
    .rst_n(app_resetn),
    
    // RDI/FDI Interface Connections
    .rdi(rdi),
    .fdi(fdi),
    
    // Protocol Layer Array Interfaces
    .ul_tx_flit(ul_tx_flit),
    .ul_tx_valid(ul_tx_valid),
    .ul_tx_ready(ul_tx_ready),
    .ul_tx_vc(ul_tx_vc),
    
    .ul_rx_flit(ul_rx_flit),
    .ul_rx_valid(ul_rx_valid),
    .ul_rx_ready(ul_rx_ready),
    .ul_rx_vc(ul_rx_vc),
    
    // Protocol Configuration
    .protocol_enable(config.protocol_enable),
    .protocol_priority(config.protocol_priority)
);

// ============================================================================
// Multi-Domain Clock and Power Management
// ============================================================================

ucie_power_management #(
    .NUM_DOMAINS(3),
    .NUM_LANES(MODULE_WIDTH),
    .ENABLE_AVFS(POWER_OPTIMIZATION),
    .ENABLE_ADAPTIVE_POWER(1)
) u_power_manager (
    .clk                (app_clk),
    .rst_n              (app_resetn),
    
    // Domain Controls
    .domain_0v6_en      (power_domain_0v6_en),
    .domain_0v8_en      (power_domain_0v8_en),
    .domain_1v0_en      (power_domain_1v0_en),
    .domain_status      (power_domain_status),
    
    // Power State Management
    .current_power_state(current_power_state),
    .micro_power_state  (current_micro_state),
    .transition_req     (power_transition_req),
    .transition_ack     (power_transition_ack),
    
    // Thermal Interface
    .die_temperature    (die_temperature),
    .thermal_throttle   (thermal_throttle),
    
    // Performance Feedback
    .system_performance (system_performance)
);

// ============================================================================
// Protocol Layer Instance (Enhanced for 128 Gbps)
// ============================================================================

ucie_protocol_layer #(
    .NUM_PROTOCOLS          (4),
    .BUFFER_DEPTH          (16384),  // 4x deeper for 128 Gbps
    .NUM_VCS               (8),
    .ENABLE_PARALLEL_ENGINES(MAX_SPEED >= 64),
    .ENABLE_ML_OPTIMIZATION (ENABLE_ML_OPTIMIZATION)
) u_protocol_layer (
    .clk                (app_clk),
    .rst_n              (app_resetn),
    
    // Enhanced Clock Domains
    .clk_quarter_rate   (clk_quarter_16g),
    .clk_symbol_rate    (clk_symbol_64g),
    .quarter_rate_enable(MAX_SPEED >= 64),
    
    // Upper Layer Interfaces (from Interface Adapter)
    .ul_tx_flit         (ul_tx_flit),
    .ul_tx_valid        (ul_tx_valid),
    .ul_tx_ready        (ul_tx_ready),
    .ul_tx_vc           (ul_tx_vc),
    
    .ul_rx_flit         (ul_rx_flit),
    .ul_rx_valid        (ul_rx_valid),
    .ul_rx_ready        (ul_rx_ready),
    .ul_rx_vc           (ul_rx_vc),
    
    // D2D Adapter Interface
    .d2d_tx_flit        (protocol_to_d2d_flit),
    .d2d_tx_valid       (protocol_to_d2d_valid),
    .d2d_tx_ready       (protocol_to_d2d_ready),
    .d2d_tx_protocol_id (protocol_to_d2d_protocol_id),
    .d2d_tx_vc          (protocol_to_d2d_vc),
    
    .d2d_rx_flit        (d2d_to_protocol_flit),
    .d2d_rx_valid       (d2d_to_protocol_valid),
    .d2d_rx_ready       (d2d_to_protocol_ready),
    .d2d_rx_protocol_id (d2d_to_protocol_protocol_id),
    .d2d_rx_vc          (d2d_to_protocol_vc),
    
    // Configuration
    .protocol_enable    (config.protocol_enable),
    .protocol_priority  (config.protocol_priority),
    .protocol_active    (config.protocol_active),
    
    // ML Optimization Interface
    .ml_prediction_valid(ml_prediction_valid),
    .ml_bandwidth_pred  (ml_bandwidth_prediction),
    
    // Performance Monitoring
    .performance_stats  (performance_counters)
);

// ============================================================================
// D2D Adapter Instance (Enhanced with Advanced Features)
// ============================================================================

ucie_d2d_adapter_enhanced #(
    .FLIT_WIDTH            (FLIT_WIDTH),
    .NUM_VCS               (8),
    .RETRY_BUFFER_DEPTH    (128),  // Enhanced retry buffering
    .ENABLE_ADVANCED_CRC   (1),    // 4x parallel CRC engines
    .ENABLE_LANE_REPAIR    (1),    // Advanced lane repair
    .ENABLE_MULTI_MODULE   (NUM_MODULES > 1)
) u_d2d_adapter (
    .clk                (app_clk),
    .rst_n              (app_resetn),
    .clk_sideband       (clk_sideband_800m),
    .rst_sideband_n     (rst_sideband_n),
    
    // Protocol Layer Interface
    .protocol_tx_flit   (protocol_to_d2d_flit),
    .protocol_tx_valid  (protocol_to_d2d_valid),
    .protocol_tx_ready  (protocol_to_d2d_ready),
    .protocol_tx_protocol_id(protocol_to_d2d_protocol_id),
    .protocol_tx_vc     (protocol_to_d2d_vc),
    
    .protocol_rx_flit   (d2d_to_protocol_flit),
    .protocol_rx_valid  (d2d_to_protocol_valid),
    .protocol_rx_ready  (d2d_to_protocol_ready),
    .protocol_rx_protocol_id(d2d_to_protocol_protocol_id),
    .protocol_rx_vc     (d2d_to_protocol_vc),
    
    // Physical Layer Interface
    .phy_tx_flit        (d2d_to_phy_flit),
    .phy_tx_valid       (d2d_to_phy_valid),
    .phy_tx_ready       (d2d_to_phy_ready),
    
    .phy_rx_flit        (phy_to_d2d_flit),
    .phy_rx_valid       (phy_to_d2d_valid),
    .phy_rx_ready       (phy_to_d2d_ready),
    
    // Link Status
    .link_up            (d2d_link_up),
    .link_status        (d2d_link_status),
    
    // Multi-Module Coordination
    .module_id          (MODULE_ID),
    .num_modules        (NUM_MODULES),
    .module_coord_valid (module_coord_valid),
    .module_coord_data  (module_coord_data),
    .module_coord_ready (module_coord_ready),
    
    // Power Management
    .power_state        (current_power_state),
    .power_transition_req(power_transition_req),
    .power_transition_ack(power_transition_ack)
);

// ============================================================================
// Physical Layer Instance (128 Gbps PAM4 Enhanced)
// ============================================================================

ucie_physical_layer_enhanced #(
    .NUM_LANES             (MODULE_WIDTH),
    .MAX_SPEED_GBPS        (MAX_SPEED),
    .SIGNALING_MODE        (SIGNALING_MODE),
    .ENABLE_PAM4           (MAX_SPEED > 64),
    .ENABLE_ADVANCED_EQ    (1),
    .ENABLE_THERMAL_MGMT   (1),
    .POWER_OPTIMIZATION    (POWER_OPTIMIZATION)
) u_physical_layer (
    .clk                (app_clk),
    .rst_n              (app_resetn),
    
    // Enhanced Clock Domains
    .clk_symbol         (clk_symbol_64g),
    .clk_quarter        (clk_quarter_16g),
    .clk_sideband       (clk_sideband_800m),
    .rst_symbol_n       (rst_symbol_n),
    .rst_quarter_n      (rst_quarter_n),
    .rst_sideband_n     (rst_sideband_n),
    
    // D2D Adapter Interface
    .d2d_tx_flit        (d2d_to_phy_flit),
    .d2d_tx_valid       (d2d_to_phy_valid),
    .d2d_tx_ready       (d2d_to_phy_ready),
    
    .d2d_rx_flit        (phy_to_d2d_flit),
    .d2d_rx_valid       (phy_to_d2d_valid),
    .d2d_rx_ready       (phy_to_d2d_ready),
    
    // Physical Interface
    .phy                (phy),
    
    // Link Status
    .link_trained       (phy_link_trained),
    .lanes_active       (phy_lanes_active),
    .link_speed         (phy_link_speed),
    .pam4_mode          (phy_pam4_mode),
    
    // Thermal Management
    .die_temperature    (die_temperature),
    .thermal_throttle   (thermal_management_active),
    
    // Configuration
    .target_speed       (config.target_speed),
    .target_width       (config.target_width),
    .package_type       (config.package_type)
);

// ============================================================================
// ML Optimization Engine (Advanced Feature)
// ============================================================================

generate
if (ENABLE_ML_OPTIMIZATION) begin : gen_ml_engine

ucie_ml_optimization_engine #(
    .PREDICTION_DEPTH   (16),
    .BANDWIDTH_CLASSES  (8),
    .LATENCY_CLASSES    (4)
) u_ml_engine (
    .clk                (app_clk),
    .rst_n              (app_resetn),
    
    // Performance Inputs
    .current_bandwidth  (performance_counters[15:8]),
    .current_latency    (performance_counters[7:0]),
    .buffer_occupancy   (config.buffer_status),
    .thermal_status     (die_temperature),
    
    // ML Predictions
    .prediction_valid   (ml_prediction_valid),
    .bandwidth_prediction(ml_bandwidth_prediction),
    
    // Optimization Controls
    .optimization_active(ml_optimization_active),
    .power_hint         (current_micro_state),
    .throttle_req       (thermal_management_active)
);

end else begin : gen_no_ml
    assign ml_prediction_valid = 1'b0;
    assign ml_bandwidth_prediction = 8'h0;
    assign ml_optimization_active = 1'b0;
end
endgenerate

// ============================================================================
// Multi-Module Coordination Logic
// ============================================================================

generate
if (NUM_MODULES > 1) begin : gen_multi_module

ucie_multi_module_coordinator #(
    .NUM_MODULES        (NUM_MODULES),
    .MODULE_ID          (MODULE_ID)
) u_multi_module_coord (
    .clk                (app_clk),
    .rst_n              (app_resetn),
    
    // Module Synchronization
    .module_sync_clk    (module_sync_clk),
    .module_sync_reset_n(module_sync_reset_n),
    
    // Coordination Signals
    .coord_valid        (module_sync_valid),
    .coord_data         (module_sync_data),
    .multi_module_active(multi_module_active),
    
    // Power Coordination
    .power_state        (current_power_state),
    .power_sync_req     (power_transition_req),
    
    // Performance Coordination
    .bandwidth_share    (performance_counters)
);

end else begin : gen_single_module
    assign multi_module_active = 1'b0;
    assign module_sync_valid = '0;
    assign module_sync_data = '0;
end
endgenerate

// ============================================================================
// Status and Debug Interface Integration
// ============================================================================

always_comb begin
    // Debug interface assignments
    debug.link_state = d2d_link_status;
    debug.power_state = current_power_state;
    debug.thermal_status = die_temperature;
    debug.performance_counters = performance_counters;
    debug.ml_active = ml_optimization_active;
    debug.multi_module_active = multi_module_active;
    
    // Configuration status
    config.link_up = d2d_link_up;
    config.current_speed = phy_link_speed;
    config.active_lanes = phy_lanes_active;
    config.pam4_active = phy_pam4_mode;
    config.thermal_throttle = thermal_throttle;
end

endmodule

// ============================================================================
// Helper Modules
// ============================================================================

// Reset Synchronizer
module ucie_reset_synchronizer (
    input  logic clk,
    input  logic async_rst_n,
    output logic sync_rst_n
);

logic [1:0] rst_sync;

always_ff @(posedge clk or negedge async_rst_n) begin
    if (!async_rst_n) begin
        rst_sync <= 2'b00;
    end else begin
        rst_sync <= {rst_sync[0], 1'b1};
    end
end

assign sync_rst_n = rst_sync[1];

endmodule