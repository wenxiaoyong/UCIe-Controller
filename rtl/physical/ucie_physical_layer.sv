module ucie_physical_layer_enhanced #(
    parameter NUM_LANES             = 64,
    parameter MAX_SPEED_GBPS        = 128,
    parameter SIGNALING_MODE        = "PAM4",
    parameter ENABLE_PAM4           = 1,
    parameter ENABLE_ADVANCED_EQ    = 1,
    parameter ENABLE_THERMAL_MGMT   = 1,
    parameter POWER_OPTIMIZATION    = 1,
    parameter PACKAGE_TYPE          = "ADVANCED"
) (
    // ========================================================================
    // Clock and Reset Domains
    // ========================================================================
    
    // Primary Clock Domains
    input  logic        clk,                // Application clock domain
    input  logic        rst_n,              // Application reset
    
    // Enhanced Clock Domains for 128 Gbps
    input  logic        clk_symbol,         // High-speed symbol clock (64 GHz)
    input  logic        clk_quarter,        // Quarter-rate clock (16 GHz) 
    input  logic        clk_sideband,       // Sideband clock (800 MHz)
    input  logic        rst_symbol_n,       // Symbol domain reset
    input  logic        rst_quarter_n,      // Quarter-rate domain reset
    input  logic        rst_sideband_n,     // Sideband domain reset
    
    // ========================================================================
    // D2D Adapter Interface
    // ========================================================================
    
    // D2D to Physical (TX Path)
    input  logic [255:0]            d2d_tx_flit,
    input  logic                    d2d_tx_valid,
    output logic                    d2d_tx_ready,
    
    // Physical to D2D (RX Path)  
    output logic [255:0]            d2d_rx_flit,
    output logic                    d2d_rx_valid,
    input  logic                    d2d_rx_ready,
    
    // ========================================================================
    // Physical Interface (Enhanced for 128 Gbps PAM4)
    // ========================================================================
    
    ucie_phy_if.phy                 phy,
    
    // ========================================================================
    // Link Status and Training
    // ========================================================================
    
    // Link Training Status
    output logic                    link_trained,
    output logic [NUM_LANES-1:0]    lanes_active,
    output logic [7:0]              link_speed,
    output logic                    pam4_mode,
    
    // Training Control
    input  logic                    training_enable,
    input  logic [1:0]              training_pattern,
    output logic                    training_complete,
    output logic                    training_error,
    
    // ========================================================================
    // Thermal Management Interface (128 Gbps Enhanced)
    // ========================================================================
    
    input  logic [7:0]              die_temperature,
    output logic                    thermal_throttle,
    
    // Enhanced Thermal Features
    output logic [63:0][7:0]        thermal_sensor_data,
    output logic [7:0]              thermal_zone_status,
    output logic [1:0]              thermal_throttle_level,
    
    // ========================================================================
    // Configuration Interface
    // ========================================================================
    
    input  logic [7:0]              target_speed,        // Target link speed
    input  logic [7:0]              target_width,        // Target link width  
    input  logic [1:0]              package_type,        // Package type config
    
    // Advanced Configuration
    input  logic                    ml_prediction_enable,
    input  logic [7:0]              ml_signal_quality_pred,
    input  logic                    adaptive_eq_enable,
    input  logic                    thermal_mgmt_enable,
    
    // ========================================================================
    // Debug and Monitoring Interface
    // ========================================================================
    
    output logic [31:0]             debug_status,
    output logic [15:0]             performance_metrics,
    input  logic [7:0]              debug_select
);

    import ucie_pkg::*;
    import ucie_common_pkg::*;

    // ========================================================================
    // Internal Signal Declarations
    // ========================================================================
    
    // Lane Management Signals
    logic [NUM_LANES-1:0]           lane_enable_int;
    logic [NUM_LANES-1:0]           lane_active_int;
    logic [NUM_LANES-1:0]           lane_trained_int;
    logic [NUM_LANES-1:0]           lane_error_int;
    logic [NUM_LANES-1:0][7:0]      lane_mapping;
    logic                           lane_reversal_detected;
    
    // Link Training Signals
    training_state_t                current_training_state;
    logic [7:0]                     training_attempts;
    logic                           parameter_exchange_complete;
    logic [63:0]                    local_parameters;
    logic [63:0]                    remote_parameters;
    
    // PAM4 and Equalization Signals
    logic [NUM_LANES-1:0]           pam4_mode_per_lane;
    logic [NUM_LANES-1:0][31:0][7:0] dfe_coeffs;
    logic [NUM_LANES-1:0][15:0][7:0] ffe_coeffs;
    logic [NUM_LANES-1:0][3:0]      ctle_settings;
    logic [NUM_LANES-1:0]           eq_converged;
    
    // Signal Integrity Monitoring
    logic [NUM_LANES-1:0][15:0]     signal_quality_metric;
    logic [NUM_LANES-1:0][7:0]      eye_height_measurement;
    logic [NUM_LANES-1:0][7:0]      eye_width_measurement;
    logic [NUM_LANES-1:0]           signal_integrity_alarm;
    
    // Thermal Management Signals
    logic [63:0]                    thermal_sensors_valid;
    logic [7:0]                     avg_die_temperature;
    logic                           thermal_emergency;
    logic [2:0]                     thermal_zone_alarms;
    
    // Power Management Signals
    logic [2:0]                     power_domain_status;
    logic [NUM_LANES-1:0][1:0]      lane_power_state;
    logic                           adaptive_power_active;
    logic [7:0]                     power_efficiency_metric;
    
    // ML Enhancement Signals
    logic                           ml_adaptation_active;
    logic [7:0]                     ml_prediction_accuracy;
    logic [NUM_LANES-1:0]           ml_lane_failure_pred;
    
    // Performance Monitoring
    logic [31:0]                    symbol_count;
    logic [31:0]                    error_count;
    logic [15:0]                    bandwidth_utilization;
    logic [15:0]                    latency_measurement;
    
    // Data Path Signals
    logic [NUM_LANES-1:0][1:0]      tx_pam4_symbols;
    logic [NUM_LANES-1:0][1:0]      rx_pam4_symbols;
    logic [NUM_LANES-1:0]           tx_symbol_valid;
    logic [NUM_LANES-1:0]           rx_symbol_valid;
    
    // Sideband Signals
    logic                           sb_tx_valid;
    logic [63:0]                    sb_tx_data;
    logic                           sb_rx_valid;
    logic [63:0]                    sb_rx_data;
    logic                           sb_ready;
    
    // ========================================================================
    // Advanced Lane Manager (Enhanced for 128 Gbps)
    // ========================================================================
    
    ucie_advanced_lane_manager #(
        .NUM_LANES              (NUM_LANES),
        .MAX_SPEED_GBPS         (MAX_SPEED_GBPS),
        .ENABLE_REPAIR          (1),
        .ENABLE_REVERSAL        (1),
        .ENABLE_ML_PREDICTION   (1),
        .ENABLE_DYNAMIC_MAPPING (1)
    ) u_lane_manager (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .clk_symbol             (clk_symbol),
        .rst_symbol_n           (rst_symbol_n),
        
        // Lane Control
        .lane_enable            (lane_enable_int),
        .lane_active            (lane_active_int),  
        .lane_trained           (lane_trained_int),
        .lane_error             (lane_error_int),
        .lane_mapping           (lane_mapping),
        .lane_reversal_detected (lane_reversal_detected),
        
        // Physical Interface
        .phy_lane_enable        (phy.lane_enable),
        .phy_lane_active        (phy.lane_active),
        .phy_lane_trained       (phy.lane_trained),
        .phy_lane_error         (phy.lane_error),
        .phy_lane_mapping       (phy.lane_mapping),
        .phy_lane_reversal_enable(phy.lane_reversal_enable),
        
        // Signal Quality
        .signal_quality         (signal_quality_metric),
        .eye_height             (eye_height_measurement),
        .eye_width              (eye_width_measurement),
        .signal_alarm           (signal_integrity_alarm),
        
        // ML Enhancement
        .ml_prediction_enable   (ml_prediction_enable),
        .ml_lane_failure_pred   (ml_lane_failure_pred),
        .ml_adaptation_active   (ml_adaptation_active),
        
        // Configuration
        .target_width           (target_width),
        .package_type           (package_type),
        
        // Status
        .lanes_active           (lanes_active),
        .link_trained           (link_trained)
    );
    
    // ========================================================================
    // Link Training FSM (Enhanced for 128 Gbps)
    // ========================================================================
    
    ucie_link_training_fsm #(
        .MAX_SPEED_GBPS         (MAX_SPEED_GBPS),
        .ENABLE_FAST_TRAINING   (MAX_SPEED_GBPS >= 64),
        .ENABLE_PARALLEL_TRAIN  (MAX_SPEED_GBPS >= 128), 
        .ENABLE_ML_TRAIN        (1),
        .TRAINING_TIMEOUT       (100000)
    ) u_training_fsm (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .clk_sideband           (clk_sideband),
        .rst_sideband_n         (rst_sideband_n),
        
        // Training Control
        .training_enable        (training_enable),
        .training_pattern       (training_pattern),
        .training_complete      (training_complete),
        .training_error         (training_error),
        .training_state         (current_training_state),
        .training_attempts      (training_attempts),
        
        // Physical Layer Interface
        .phy_training_enable    (phy.training_enable),
        .phy_training_pattern   (phy.training_pattern),
        .phy_training_complete  (phy.training_complete),
        .phy_training_error     (phy.training_error),
        .phy_training_state     (phy.training_state),
        .phy_pattern_lock       (phy.pattern_lock),
        
        // Parameter Exchange
        .local_parameters       (local_parameters),
        .remote_parameters      (remote_parameters),
        .param_exchange_complete(parameter_exchange_complete),
        .phy_local_parameters   (phy.local_parameters),
        .phy_remote_parameters  (phy.remote_parameters),
        .phy_param_exchange_complete(phy.param_exchange_complete),
        
        // Lane Status
        .lanes_active           (lane_active_int),
        .lanes_trained          (lane_trained_int),
        
        // Configuration
        .target_speed           (target_speed),
        .signaling_mode         (SIGNALING_MODE),
        
        // ML Enhancement
        .ml_prediction_enable   (ml_prediction_enable),
        .ml_signal_quality_pred (ml_signal_quality_pred),
        
        // Status
        .link_speed             (link_speed),
        .pam4_mode              (pam4_mode)
    );
    
    // ========================================================================
    // PAM4 PHY with Enhanced Equalization (128 Gbps)
    // ========================================================================
    
    ucie_pam4_phy #(
        .NUM_LANES              (NUM_LANES),
        .SYMBOL_RATE_GBPS       (MAX_SPEED_GBPS / 2),  // PAM4 halves symbol rate
        .ENABLE_ADVANCED_EQ     (ENABLE_ADVANCED_EQ),
        .NUM_DFE_TAPS           (32),
        .NUM_FFE_TAPS           (16),
        .ENABLE_ADAPTATION      (1),
        .ENABLE_CROSSTALK_CANCEL(1)
    ) u_pam4_phy (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .clk_symbol             (clk_symbol),
        .clk_quarter            (clk_quarter),
        .rst_symbol_n           (rst_symbol_n),
        .rst_quarter_n          (rst_quarter_n),
        
        // Data Interface
        .tx_data                (d2d_tx_flit),
        .tx_valid               (d2d_tx_valid),
        .tx_ready               (d2d_tx_ready),
        
        .rx_data                (d2d_rx_flit),  
        .rx_valid               (d2d_rx_valid),
        .rx_ready               (d2d_rx_ready),
        
        // Physical Signals
        .phy_tx_p               (phy.tx_data_p),
        .phy_tx_n               (phy.tx_data_n),
        .phy_rx_p               (phy.rx_data_p),
        .phy_rx_n               (phy.rx_data_n),
        
        // PAM4 Control
        .pam4_mode_enable       (pam4_mode_per_lane),
        .tx_pam4_levels         (tx_pam4_symbols),
        .rx_pam4_levels         (rx_pam4_symbols),
        .pam4_tx_symbol_valid   (tx_symbol_valid),
        .pam4_rx_symbol_valid   (rx_symbol_valid),
        
        // Physical Interface
        .phy_pam4_mode_en       (phy.pam4_mode_en),
        .phy_tx_pam4_level      (phy.tx_pam4_level),
        .phy_rx_pam4_level      (phy.rx_pam4_level),
        
        // Equalization
        .dfe_coefficients       (dfe_coeffs),
        .ffe_coefficients       (ffe_coeffs),
        .ctle_settings          (ctle_settings),
        .eq_converged           (eq_converged),
        
        // Physical EQ Interface
        .phy_dfe_coefficients   (phy.dfe_coefficients),
        .phy_dfe_enable         (phy.dfe_enable),
        .phy_dfe_adapt_enable   (phy.dfe_adapt_enable),
        .phy_ffe_coefficients   (phy.ffe_coefficients),
        .phy_ffe_enable         (phy.ffe_enable),
        .phy_ffe_adapt_enable   (phy.ffe_adapt_enable),
        .phy_ctle_gain          (phy.ctle_gain),
        .phy_ctle_peak_freq     (phy.ctle_peak_freq),
        
        // Lane Configuration
        .lane_enable            (lane_enable_int),
        .lane_active            (lane_active_int),
        .lane_power_state       (lane_power_state),
        
        // ML Enhancement
        .ml_adaptation_enable   (ml_prediction_enable),
        .ml_prediction_accuracy (ml_prediction_accuracy),
        
        // Performance
        .symbol_count           (symbol_count),
        .error_count            (error_count)
    );
    
    // ========================================================================
    // Signal Integrity Monitor (128 Gbps Enhanced)
    // ========================================================================
    
    ucie_signal_integrity_monitor #(
        .NUM_LANES              (NUM_LANES),
        .ENABLE_EYE_MONITOR     (1),
        .ENABLE_JITTER_MONITOR  (1),
        .ENABLE_BER_MONITOR     (1),
        .MEASUREMENT_PERIOD     (1024)
    ) u_signal_monitor (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .clk_symbol             (clk_symbol),
        .rst_symbol_n           (rst_symbol_n),
        
        // Physical Monitoring
        .rx_data_p              (phy.rx_data_p),
        .rx_data_n              (phy.rx_data_n),
        .rx_pam4_levels         (rx_pam4_symbols),
        .rx_symbol_valid        (rx_symbol_valid),
        
        // Signal Quality Outputs
        .signal_quality         (signal_quality_metric),
        .eye_height             (eye_height_measurement),
        .eye_width              (eye_width_measurement),
        .signal_alarm           (signal_integrity_alarm),
        
        // Physical Interface
        .phy_signal_quality     (phy.signal_integrity_metric),
        .phy_signal_alarm       (phy.signal_quality_alarm),
        .phy_lane_ber_count     (phy.lane_ber_count),
        .phy_lane_eye_height    (phy.lane_eye_height),
        .phy_lane_eye_width     (phy.lane_eye_width),
        
        // Configuration
        .lane_active            (lane_active_int),
        .pam4_mode              (pam4_mode_per_lane),
        
        // Performance Metrics
        .bandwidth_utilization  (bandwidth_utilization),
        .latency_measurement    (latency_measurement)
    );
    
    // ========================================================================
    // Enhanced Thermal Management (64 Sensors)
    // ========================================================================
    
    ucie_thermal_manager #(
        .NUM_SENSORS            (64),
        .NUM_ZONES              (8),
        .ENABLE_PREDICTIVE      (1),
        .ENABLE_DYNAMIC_THROTTLE(1),
        .TEMP_RESOLUTION        (8)  // 0.1°C resolution
    ) u_thermal_manager (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Temperature Inputs
        .die_temperature        (die_temperature),
        .sensor_data            (thermal_sensor_data),
        .sensor_valid           (thermal_sensors_valid),
        
        // Thermal Control
        .thermal_mgmt_enable    (thermal_mgmt_enable),
        .thermal_throttle       (thermal_throttle),
        .thermal_throttle_level (thermal_throttle_level),
        .thermal_emergency      (thermal_emergency),
        
        // Zone Management
        .zone_temperatures      (thermal_zone_status),
        .zone_alarms            (thermal_zone_alarms),
        
        // Physical Interface
        .phy_thermal_sensor_data(phy.thermal_sensor_data),
        .phy_thermal_sensor_valid(phy.thermal_sensor_valid),
        .phy_die_temperature_avg(phy.die_temperature_avg),
        .phy_thermal_throttle_active(phy.thermal_throttle_active),
        .phy_thermal_throttle_level(phy.thermal_throttle_level),
        .phy_thermal_zone_status(phy.thermal_zone_status),
        
        // Lane Thermal Management
        .lane_active            (lane_active_int),
        .lane_power_state       (lane_power_state),
        
        // Performance Impact
        .avg_die_temperature    (avg_die_temperature),
        .power_efficiency       (power_efficiency_metric)
    );
    
    // ========================================================================
    // Multi-Domain Power Management 
    // ========================================================================
    
    ucie_power_management #(
        .NUM_DOMAINS            (3),  // 0.6V, 0.8V, 1.0V
        .NUM_LANES              (NUM_LANES),
        .ENABLE_AVFS            (POWER_OPTIMIZATION),
        .ENABLE_ADAPTIVE_POWER  (1)
    ) u_power_manager (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Power Domain Controls
        .domain_0v6_active      (phy.power_domain_0v6_active),
        .domain_0v8_active      (phy.power_domain_0v8_active),
        .domain_1v0_active      (phy.power_domain_1v0_active),
        .power_domain_status    (power_domain_status),
        
        // Lane Power Management
        .lane_active            (lane_active_int),
        .lane_power_state       (lane_power_state),
        .phy_lane_power_state   (phy.lane_power_state),
        
        // Adaptive Power Features
        .adaptive_power_enable  (phy.adaptive_power_enable),
        .power_budget           (phy.power_budget),
        .adaptive_power_active  (adaptive_power_active),
        
        // Thermal Integration
        .die_temperature        (avg_die_temperature),
        .thermal_throttle       (thermal_throttle),
        
        // Performance Integration
        .bandwidth_utilization  (bandwidth_utilization),
        .power_efficiency       (power_efficiency_metric),
        
        // Status
        .global_power_good      (phy.global_power_good)
    );
    
    // ========================================================================
    // Sideband Engine (800 MHz Always-On)
    // ========================================================================
    
    ucie_sideband_engine #(
        .SIDEBAND_FREQ_MHZ      (800),
        .ENABLE_REDUNDANT       (PACKAGE_TYPE == "ADVANCED"),
        .PACKET_BUFFER_DEPTH    (16)
    ) u_sideband_engine (
        .clk_sideband           (clk_sideband),
        .rst_sideband_n         (rst_sideband_n),
        .clk_app                (clk),
        .rst_app_n              (rst_n),
        
        // Sideband Protocol Interface
        .sb_tx_valid            (sb_tx_valid),
        .sb_tx_data             (sb_tx_data),
        .sb_tx_ready            (sb_ready),
        
        .sb_rx_valid            (sb_rx_valid),
        .sb_rx_data             (sb_rx_data),
        .sb_rx_ready            (1'b1),
        
        // Parameter Exchange Support
        .local_parameters       (local_parameters),
        .remote_parameters      (remote_parameters),
        .param_exchange_complete(parameter_exchange_complete),
        
        // Training Support
        .training_state         (current_training_state),
        .training_enable        (training_enable),
        
        // Link State
        .link_trained           (link_trained),
        .lanes_active           (lanes_active)
    );
    
    // ========================================================================
    // ML Enhancement Engine (Optional)
    // ========================================================================
    
    generate
    if (MAX_SPEED_GBPS >= 128) begin : gen_ml_enhancement
        
        ucie_advanced_ml_equalization #(
            .NUM_LANES          (NUM_LANES),
            .PREDICTION_DEPTH   (16),
            .LEARNING_RATE      (8),
            .ENABLE_PREDICTION  (1)
        ) u_ml_eq_engine (
            .clk                (clk),
            .rst_n              (rst_n),
            
            // Signal Quality Inputs
            .signal_quality     (signal_quality_metric),
            .eye_measurements   ({eye_height_measurement, eye_width_measurement}),
            .error_count        (error_count),
            
            // Equalization Control
            .dfe_coeffs_in      (dfe_coeffs),
            .ffe_coeffs_in      (ffe_coeffs),
            .dfe_coeffs_out     (), // Connect to PHY if needed
            .ffe_coeffs_out     (), // Connect to PHY if needed
            
            // ML Interface
            .ml_enable          (ml_prediction_enable),
            .ml_prediction_accuracy(ml_prediction_accuracy),
            .ml_lane_failure_pred(ml_lane_failure_pred),
            .ml_adaptation_active(ml_adaptation_active),
            
            // Physical Interface
            .phy_ml_prediction_enable(phy.ml_prediction_enable),
            .phy_ml_signal_quality_pred(phy.ml_signal_quality_pred),
            .phy_ml_lane_failure_prob(phy.ml_lane_failure_prob),
            .phy_ml_adaptation_request(phy.ml_adaptation_request)
        );
        
    end else begin : gen_no_ml
        assign ml_prediction_accuracy = 8'h0;
        assign ml_lane_failure_pred = '0;
        assign ml_adaptation_active = 1'b0;
    end
    endgenerate
    
    // ========================================================================
    // Control Logic and State Management
    // ========================================================================
    
    always_comb begin
        // Lane enable logic based on target width and training state
        for (int i = 0; i < NUM_LANES; i++) begin
            lane_enable_int[i] = (i < target_width) && 
                               (current_training_state != TRAINING_DISABLED);
        end
        
        // PAM4 mode per lane based on speed requirement
        pam4_mode_per_lane = (target_speed > 64) ? {NUM_LANES{1'b1}} : {NUM_LANES{1'b0}};
        
        // Parameter exchange data
        local_parameters = {
            8'(MAX_SPEED_GBPS),     // [63:56] Max speed capability
            8'(NUM_LANES),          // [55:48] Lane count
            8'(SIGNALING_MODE == "PAM4" ? 1 : 0), // [47:40] Signaling mode
            8'(PACKAGE_TYPE == "ADVANCED" ? 1 : 0), // [39:32] Package type
            32'h12345678            // [31:0] Device ID and capabilities
        };
        
        // Sideband transmission control
        sb_tx_valid = parameter_exchange_complete ? 1'b0 : 
                     (current_training_state == TRAINING_PARAM_EXCHANGE);
        sb_tx_data = local_parameters;
    end
    
    // ========================================================================
    // Performance Monitoring and Statistics
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            performance_metrics <= 16'h0;
        end else begin
            // Update performance metrics
            performance_metrics <= {bandwidth_utilization[7:0], power_efficiency_metric};
        end
    end
    
    // ========================================================================
    // Debug Interface
    // ========================================================================
    
    always_comb begin
        case (debug_select[7:4])
            4'h0: debug_status = {link_speed, target_speed, current_training_state, 8'h0};
            4'h1: debug_status = symbol_count;
            4'h2: debug_status = error_count;
            4'h3: debug_status = {bandwidth_utilization, latency_measurement};
            4'h4: debug_status = {avg_die_temperature, thermal_throttle_level, 
                                 thermal_zone_status, 16'h0};
            4'h5: debug_status = {power_domain_status, power_efficiency_metric, 21'h0};
            4'h6: debug_status = {ml_prediction_accuracy, training_attempts, 16'h0};
            4'h7: debug_status = {lanes_active[31:0]};
            default: debug_status = 32'hDEADBEEF;
        endcase
    end

endmodule