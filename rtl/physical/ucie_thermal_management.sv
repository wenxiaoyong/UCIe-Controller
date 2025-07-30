// Thermal Management System for 128 Gbps UCIe Controller
// Provides comprehensive thermal monitoring, prediction, and control
// Integrates with power management for optimal thermal-aware operation

module ucie_thermal_management
    import ucie_pkg::*;
#(
    parameter NUM_THERMAL_ZONES = 8,     // Number of thermal monitoring zones
    parameter ENABLE_THERMAL_MODELING = 1, // Enable thermal modeling
    parameter ENABLE_ML_PREDICTION = 1,  // ML-based thermal prediction
    parameter ENABLE_ADAPTIVE_COOLING = 1 // Adaptive cooling control
) (
    // Clock and Reset
    input  logic                clk_main,          // Main 800 MHz clock
    input  logic                clk_quarter_rate,  // 16 GHz monitoring clock
    input  logic                rst_n,
    
    // Temperature Sensor Inputs
    input  logic [7:0]          temp_sensors_c [NUM_THERMAL_ZONES], // Temperature sensors
    input  logic [NUM_THERMAL_ZONES-1:0] sensor_valid,
    input  logic [7:0]          ambient_temp_c,    // Ambient temperature
    input  logic                temp_sensor_enable,
    
    // Power Interface (from power management)
    input  logic [15:0]         current_power_mw,  // Current power consumption
    input  logic [15:0]         power_density [NUM_THERMAL_ZONES], // Power per zone
    input  logic [7:0]          power_activity,    // Activity-based power factor
    
    // Thermal Control Outputs
    output logic                thermal_warning,   // 85°C warning threshold
    output logic                thermal_critical,  // 100°C critical threshold
    output logic                thermal_emergency, // 110°C emergency shutdown
    output logic [7:0]          thermal_throttle_level, // 0-255 throttle level
    
    // Cooling Control Interface
    output logic [7:0]          fan_speed_request, // Fan speed 0-255
    output logic                cooling_enable,    // Enable active cooling
    output logic [3:0]          cooling_mode,      // Cooling strategy
    input  logic [7:0]          fan_speed_actual,  // Actual fan speed feedback
    input  logic                cooling_ready,     // Cooling system ready
    
    // Thermal Throttling Interface  
    output logic                freq_throttle_req, // Request frequency throttling
    output logic [7:0]          freq_throttle_percent, // Throttle percentage
    output logic                power_throttle_req, // Request power throttling
    output logic [7:0]          power_throttle_percent, // Power throttle level
    
    // ML-Enhanced Thermal Prediction
    input  logic                ml_enable,
    input  logic [7:0]          ml_parameters [8],
    output logic [7:0]          ml_thermal_metrics [6],
    input  logic [15:0]         ml_prediction_horizon, // Prediction time horizon
    
    // Junction Temperature Interface
    output logic [7:0]          junction_temp_c,   // Estimated junction temperature
    output logic [7:0]          max_zone_temp_c,   // Hottest zone temperature
    output logic [3:0]          hottest_zone_id,   // ID of hottest zone
    output logic [7:0]          thermal_margin_c,  // Margin to critical temp
    
    // Thermal History and Analytics
    output logic [7:0]          temp_trend,        // Temperature trend (+/- rate)
    output logic [15:0]         thermal_cycles,    // Thermal stress cycles
    output logic [31:0]         thermal_budget_used, // Thermal budget consumed
    
    // Configuration and Control
    input  logic [7:0]          warning_threshold_c,   // Warning temperature
    input  logic [7:0]          critical_threshold_c,  // Critical temperature
    input  logic [7:0]          emergency_threshold_c, // Emergency temperature
    input  logic [3:0]          thermal_hysteresis_c,  // Hysteresis margin
    
    // Status and Debug
    output logic [31:0]         thermal_status,
    output logic [15:0]         debug_thermal_metrics [8]
);

    // Thermal Management State Machine
    typedef enum logic [3:0] {
        TM_RESET,
        TM_INIT,
        TM_MONITORING,
        TM_WARNING,
        TM_CRITICAL,
        TM_EMERGENCY,
        TM_COOLING,
        TM_THROTTLING,
        TM_RECOVERY,
        TM_CALIBRATION
    } thermal_state_t;
    
    thermal_state_t current_state, next_state;
    
    // Thermal Zone Management
    typedef struct packed {
        logic [7:0] current_temp;
        logic [7:0] max_temp;
        logic [7:0] min_temp;
        logic [7:0] avg_temp;
        logic [7:0] temp_rate;          // Rate of change
        logic [15:0] power_density;
        logic       critical_zone;
        logic       throttle_active;
    } thermal_zone_t;
    
    thermal_zone_t thermal_zones [NUM_THERMAL_ZONES];
    
    // Temperature History for Trend Analysis
    logic [7:0] temp_history [NUM_THERMAL_ZONES][16]; // 16-sample history per zone
    logic [3:0] history_ptr [NUM_THERMAL_ZONES];
    logic [7:0] temp_moving_avg [NUM_THERMAL_ZONES];
    
    // Thermal Modeling Variables
    logic [15:0] thermal_resistance [NUM_THERMAL_ZONES]; // °C/W thermal resistance
    logic [15:0] thermal_capacitance [NUM_THERMAL_ZONES]; // J/°C thermal mass
    logic [7:0]  heat_spreading_factor [NUM_THERMAL_ZONES]; // Heat spreading
    
    // ML-Enhanced Thermal Prediction
    logic [7:0]  ml_temp_predictor [NUM_THERMAL_ZONES];
    logic [7:0]  ml_power_correlator;
    logic [7:0]  ml_cooling_optimizer;
    logic [7:0]  ml_throttle_predictor;
    logic [15:0] ml_prediction_accuracy;
    logic [7:0]  ml_learning_rate;
    
    // Thermal Control Variables
    logic [7:0]  current_throttle_level;
    logic [7:0]  target_throttle_level;
    logic [15:0] throttle_ramp_counter;
    logic [7:0]  cooling_request_level;
    logic [15:0] cooling_response_delay;
    
    // Performance and Reliability Tracking
    logic [31:0] thermal_stress_accumulator;
    logic [15:0] thermal_cycle_counter;
    logic [15:0] over_temp_duration [NUM_THERMAL_ZONES];
    logic [7:0]  reliability_factor;
    
    // Adaptive Cooling Control
    logic [7:0]  adaptive_fan_curve [16];        // Temperature-based fan curve
    logic [3:0]  cooling_strategy;
    logic [7:0]  cooling_efficiency_factor;
    logic [15:0] cooling_effectiveness_history [8];
    
    // State Machine
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= TM_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            TM_RESET: begin
                if (temp_sensor_enable) begin
                    next_state = TM_INIT;
                end
            end
            
            TM_INIT: begin
                if (|sensor_valid) begin
                    next_state = TM_MONITORING;
                end
            end
            
            TM_MONITORING: begin
                if (junction_temp_c >= emergency_threshold_c) begin
                    next_state = TM_EMERGENCY;
                end else if (junction_temp_c >= critical_threshold_c) begin
                    next_state = TM_CRITICAL;
                end else if (junction_temp_c >= warning_threshold_c) begin
                    next_state = TM_WARNING;
                end
            end
            
            TM_WARNING: begin
                if (junction_temp_c >= emergency_threshold_c) begin
                    next_state = TM_EMERGENCY;
                end else if (junction_temp_c >= critical_threshold_c) begin
                    next_state = TM_CRITICAL;
                end else if (junction_temp_c < (warning_threshold_c - thermal_hysteresis_c)) begin
                    next_state = TM_RECOVERY;
                end else if (current_throttle_level > 8'd0) begin
                    next_state = TM_THROTTLING;
                end else if (cooling_request_level > 8'd50) begin
                    next_state = TM_COOLING;
                end
            end
            
            TM_CRITICAL: begin
                if (junction_temp_c >= emergency_threshold_c) begin
                    next_state = TM_EMERGENCY;
                end else if (junction_temp_c < (critical_threshold_c - thermal_hysteresis_c)) begin
                    next_state = TM_WARNING;
                end else begin
                    next_state = TM_THROTTLING; // Force throttling in critical state
                end
            end
            
            TM_EMERGENCY: begin
                if (junction_temp_c < (emergency_threshold_c - thermal_hysteresis_c)) begin
                    next_state = TM_CRITICAL;
                end
                // Stay in emergency until temperature drops significantly
            end
            
            TM_COOLING: begin
                if (junction_temp_c >= critical_threshold_c) begin
                    next_state = TM_CRITICAL;
                end else if (junction_temp_c < (warning_threshold_c - thermal_hysteresis_c)) begin
                    next_state = TM_RECOVERY;
                end else if (cooling_effectiveness_history[0] < 16'd100) begin
                    next_state = TM_THROTTLING; // Cooling not effective, try throttling
                end
            end
            
            TM_THROTTLING: begin
                if (junction_temp_c >= emergency_threshold_c) begin
                    next_state = TM_EMERGENCY;
                end else if (junction_temp_c < (warning_threshold_c - thermal_hysteresis_c)) begin
                    next_state = TM_RECOVERY;
                end
            end
            
            TM_RECOVERY: begin
                if (junction_temp_c >= warning_threshold_c) begin
                    next_state = TM_WARNING;
                end else if (current_throttle_level == 8'd0 && cooling_request_level < 8'd25) begin
                    next_state = TM_MONITORING;
                end
            end
            
            TM_CALIBRATION: begin
                next_state = TM_MONITORING;
            end
            
            default: begin
                next_state = TM_RESET;
            end
        endcase
    end
    
    // Temperature Sensor Processing and Zone Management
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_THERMAL_ZONES; i++) begin
                thermal_zones[i] <= '0;
                history_ptr[i] <= 4'h0;
                for (int j = 0; j < 16; j++) begin
                    temp_history[i][j] <= 8'd25; // 25°C initial
                end
                temp_moving_avg[i] <= 8'd25;
                over_temp_duration[i] <= 16'h0;
            end
        end else begin
            for (int i = 0; i < NUM_THERMAL_ZONES; i++) begin
                if (sensor_valid[i]) begin
                    // Update current temperature
                    thermal_zones[i].current_temp <= temp_sensors_c[i];
                    thermal_zones[i].power_density <= power_density[i];
                    
                    // Update temperature history
                    temp_history[i][history_ptr[i]] <= temp_sensors_c[i];
                    history_ptr[i] <= history_ptr[i] + 1;
                    
                    // Calculate moving average
                    logic [11:0] temp_sum;
                    temp_sum = 12'h0;
                    for (int j = 0; j < 16; j++) begin
                        temp_sum = temp_sum + {4'h0, temp_history[i][j]};
                    end
                    temp_moving_avg[i] <= temp_sum[11:4]; // Divide by 16
                    thermal_zones[i].avg_temp <= temp_sum[11:4];
                    
                    // Update min/max temperatures
                    if (temp_sensors_c[i] > thermal_zones[i].max_temp) begin
                        thermal_zones[i].max_temp <= temp_sensors_c[i];
                    end
                    if (temp_sensors_c[i] < thermal_zones[i].min_temp || 
                        thermal_zones[i].min_temp == 8'h0) begin
                        thermal_zones[i].min_temp <= temp_sensors_c[i];
                    end
                    
                    // Calculate temperature rate of change
                    logic [7:0] temp_delta;
                    temp_delta = (temp_sensors_c[i] > temp_history[i][(history_ptr[i]-4) & 4'hF]) ?
                                (temp_sensors_c[i] - temp_history[i][(history_ptr[i]-4) & 4'hF]) :
                                (temp_history[i][(history_ptr[i]-4) & 4'hF] - temp_sensors_c[i]);
                    thermal_zones[i].temp_rate <= temp_delta;
                    
                    // Track critical zones
                    thermal_zones[i].critical_zone <= (temp_sensors_c[i] >= critical_threshold_c);
                    
                    // Track over-temperature duration
                    if (temp_sensors_c[i] > warning_threshold_c) begin
                        if (over_temp_duration[i] < 16'hFFFF) begin
                            over_temp_duration[i] <= over_temp_duration[i] + 1;
                        end
                    end else begin
                        over_temp_duration[i] <= 16'h0;
                    end
                end
            end
        end
    end
    
    // Junction Temperature Estimation
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            junction_temp_c <= 8'd25;
            max_zone_temp_c <= 8'd25;
            hottest_zone_id <= 4'h0;
        end else begin
            // Find hottest zone
            logic [7:0] max_temp;
            logic [3:0] max_zone;
            max_temp = 8'h0;
            max_zone = 4'h0;
            
            for (int i = 0; i < NUM_THERMAL_ZONES; i++) begin
                if (thermal_zones[i].current_temp > max_temp) begin
                    max_temp = thermal_zones[i].current_temp;
                    max_zone = i[3:0];
                end
            end
            
            max_zone_temp_c <= max_temp;
            hottest_zone_id <= max_zone;
            
            // Estimate junction temperature with thermal modeling
            if (ENABLE_THERMAL_MODELING) begin
                // Simple thermal model: Tj = Tambient + (Power * Rth) + hotspot_factor
                logic [15:0] thermal_rise;
                logic [7:0] hotspot_factor;
                
                thermal_rise = (current_power_mw * 16'd100) >> 8; // Simplified Rth calculation
                hotspot_factor = (max_temp > ambient_temp_c) ? 
                               (max_temp - ambient_temp_c) : 8'd0;
                
                junction_temp_c <= ambient_temp_c + thermal_rise[7:0] + hotspot_factor;
            end else begin
                // Simple approach: use hottest zone temperature
                junction_temp_c <= max_temp;
            end
        end
    end
    
    // Thermal Throttling Control
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            current_throttle_level <= 8'h0;
            target_throttle_level <= 8'h0;
            throttle_ramp_counter <= 16'h0;
        end else begin
            // Determine target throttle level based on state and temperature
            case (current_state)
                TM_MONITORING: begin
                    target_throttle_level <= 8'h0; // No throttling
                end
                
                TM_WARNING: begin
                    // Light throttling based on temperature excess
                    logic [7:0] temp_excess;
                    temp_excess = (junction_temp_c > warning_threshold_c) ?
                                 (junction_temp_c - warning_threshold_c) : 8'h0;
                    target_throttle_level <= temp_excess << 2; // 4x multiplier
                end
                
                TM_CRITICAL: begin
                    // Moderate throttling
                    logic [7:0] temp_excess;
                    temp_excess = (junction_temp_c > critical_threshold_c) ?
                                 (junction_temp_c - critical_threshold_c) : 8'h0;
                    target_throttle_level <= 8'd100 + (temp_excess << 3); // Base + 8x
                end
                
                TM_EMERGENCY: begin
                    // Maximum throttling
                    target_throttle_level <= 8'd200; // 78% throttling
                end
                
                TM_THROTTLING: begin
                    // Adaptive throttling based on effectiveness
                    if (junction_temp_c > critical_threshold_c) begin
                        target_throttle_level <= (target_throttle_level < 8'd240) ?
                                               target_throttle_level + 8'd10 : 8'd240;
                    end else if (junction_temp_c < warning_threshold_c) begin
                        target_throttle_level <= (target_throttle_level > 8'd10) ?
                                               target_throttle_level - 8'd5 : 8'd0;
                    end
                end
                
                TM_RECOVERY: begin
                    // Gradual throttle release
                    target_throttle_level <= (current_throttle_level > 8'd5) ?
                                           current_throttle_level - 8'd5 : 8'd0;
                end
                
                default: begin
                    target_throttle_level <= 8'h0;
                end
            endcase
            
            // Ramp current throttle level to target
            if (current_throttle_level != target_throttle_level) begin
                throttle_ramp_counter <= throttle_ramp_counter + 1;
                if (throttle_ramp_counter > 16'd100) begin // 100 cycle ramp time
                    if (current_throttle_level < target_throttle_level) begin
                        current_throttle_level <= current_throttle_level + 1;
                    end else begin
                        current_throttle_level <= current_throttle_level - 1;
                    end
                    throttle_ramp_counter <= 16'h0;
                end
            end
        end
    end
    
    // Adaptive Cooling Control
    generate
        if (ENABLE_ADAPTIVE_COOLING) begin : gen_adaptive_cooling
            always_ff @(posedge clk_main or negedge rst_n) begin
                if (!rst_n) begin
                    cooling_request_level <= 8'd25;    // 25% baseline
                    cooling_strategy <= 4'h0;
                    cooling_efficiency_factor <= 8'd100; // 100% efficiency
                    for (int i = 0; i < 8; i++) begin
                        cooling_effectiveness_history[i] <= 16'h8000; // 50% baseline
                    end
                    // Initialize adaptive fan curve
                    for (int i = 0; i < 16; i++) begin
                        adaptive_fan_curve[i] <= 8'd25 + (i * 8'd15); // Linear curve
                    end
                end else begin
                    // Update cooling request based on thermal state
                    case (current_state)
                        TM_MONITORING: begin
                            cooling_request_level <= 8'd25; // Baseline cooling
                        end
                        
                        TM_WARNING: begin
                            // Increase cooling proportional to temperature excess
                            logic [7:0] temp_excess;
                            temp_excess = (junction_temp_c > warning_threshold_c) ?
                                         (junction_temp_c - warning_threshold_c) : 8'h0;
                            cooling_request_level <= 8'd50 + (temp_excess << 2);
                        end
                        
                        TM_CRITICAL, TM_EMERGENCY: begin
                            cooling_request_level <= 8'd255; // Maximum cooling
                        end
                        
                        TM_COOLING: begin
                            // Adaptive cooling strategy
                            if (cooling_effectiveness_history[0] < 16'd200) begin
                                // Low effectiveness, try different strategy
                                cooling_strategy <= cooling_strategy + 1;
                                cooling_request_level <= 8'd200;
                            end else begin
                                // Maintain current strategy
                                cooling_request_level <= 8'd150;
                            end
                        end
                        
                        TM_RECOVERY: begin
                            // Gradual cooling reduction
                            cooling_request_level <= (cooling_request_level > 8'd30) ?
                                                    cooling_request_level - 8'd5 : 8'd25;
                        end
                        
                        default: begin
                            cooling_request_level <= 8'd25;
                        end
                    endcase
                    
                    // Update adaptive fan curve based on effectiveness
                    logic [3:0] temp_index;
                    temp_index = (junction_temp_c > 8'd120) ? 4'hF : junction_temp_c[7:4];
                    
                    if (junction_temp_c > warning_threshold_c && fan_speed_actual > 0) begin
                        // Learn from cooling effectiveness
                        logic [7:0] temp_delta;
                        temp_delta = temp_history[hottest_zone_id][(history_ptr[hottest_zone_id]-1) & 4'hF] -
                                    thermal_zones[hottest_zone_id].current_temp;
                        
                        if (temp_delta > 8'd2) begin // Good cooling
                            if (adaptive_fan_curve[temp_index] < 8'd240) begin
                                adaptive_fan_curve[temp_index] <= adaptive_fan_curve[temp_index] + 8'd5;
                            end
                        end else if (temp_delta == 8'd0) begin // Poor cooling
                            if (adaptive_fan_curve[temp_index] > 8'd30) begin
                                adaptive_fan_curve[temp_index] <= adaptive_fan_curve[temp_index] - 8'd2;
                            end
                        end
                    end
                    
                    // Track cooling effectiveness
                    logic [15:0] effectiveness;
                    effectiveness = (fan_speed_actual > 0) ? 
                                   (16'd1000 * temp_history[hottest_zone_id][(history_ptr[hottest_zone_id]-1) & 4'hF]) /
                                   (junction_temp_c + 1) : 16'h0;
                    
                    // Shift effectiveness history
                    for (int i = 7; i > 0; i--) begin
                        cooling_effectiveness_history[i] <= cooling_effectiveness_history[i-1];
                    end
                    cooling_effectiveness_history[0] <= effectiveness;
                end
            end
        end else begin : gen_no_adaptive_cooling
            always_comb begin
                cooling_request_level = (junction_temp_c > warning_threshold_c) ? 8'd200 : 8'd50;
                cooling_strategy = 4'h0;
                cooling_efficiency_factor = 8'd100;
            end
        end
    endgenerate
    
    // ML-Enhanced Thermal Prediction
    generate
        if (ENABLE_ML_PREDICTION) begin : gen_ml_thermal
            always_ff @(posedge clk_main or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < NUM_THERMAL_ZONES; i++) begin
                        ml_temp_predictor[i] <= 8'd25;
                    end
                    ml_power_correlator <= 8'h80;
                    ml_cooling_optimizer <= 8'h80;
                    ml_throttle_predictor <= 8'h0;
                    ml_prediction_accuracy <= 16'h8000;
                    ml_learning_rate <= 8'd4;
                end else if (ml_enable) begin
                    // Simple ML temperature prediction based on power and history
                    for (int i = 0; i < NUM_THERMAL_ZONES; i++) begin
                        logic [7:0] predicted_temp;
                        // Linear prediction: T_next = T_current + α*(Power_factor - Cooling_factor)
                        logic [7:0] power_factor;
                        logic [7:0] cooling_factor;
                        
                        power_factor = (power_density[i][15:8] > 8'd50) ? 8'd10 : 8'd2;
                        cooling_factor = (fan_speed_actual >> 4); // Fan contribution
                        
                        predicted_temp = thermal_zones[i].current_temp + 
                                        power_factor - cooling_factor;
                        
                        ml_temp_predictor[i] <= predicted_temp;
                    end
                    
                    // Power-temperature correlation learning
                    logic [7:0] power_temp_correlation;
                    power_temp_correlation = (current_power_mw[15:8] + junction_temp_c) >> 1;
                    
                    if (power_temp_correlation > ml_power_correlator) begin
                        ml_power_correlator <= ml_power_correlator + ml_learning_rate;
                    end else if (ml_power_correlator > power_temp_correlation) begin
                        ml_power_correlator <= ml_power_correlator - ml_learning_rate;
                    end
                    
                    // Cooling effectiveness optimization
                    logic [7:0] cooling_effectiveness;
                    cooling_effectiveness = (cooling_effectiveness_history[0][15:8] + 
                                           cooling_effectiveness_history[1][15:8]) >> 1;
                    
                    if (cooling_effectiveness > 8'd100) begin
                        ml_cooling_optimizer <= ml_cooling_optimizer + 1;
                    end else if (ml_cooling_optimizer > 0) begin
                        ml_cooling_optimizer <= ml_cooling_optimizer - 1;
                    end
                    
                    // Throttle prediction
                    if (junction_temp_c > warning_threshold_c) begin
                        ml_throttle_predictor <= ml_throttle_predictor + 2;
                    end else if (ml_throttle_predictor > 0) begin
                        ml_throttle_predictor <= ml_throttle_predictor - 1;
                    end
                    
                    // Update prediction accuracy
                    logic [7:0] prediction_error;
                    prediction_error = (ml_temp_predictor[hottest_zone_id] > junction_temp_c) ?
                                      (ml_temp_predictor[hottest_zone_id] - junction_temp_c) :
                                      (junction_temp_c - ml_temp_predictor[hottest_zone_id]);
                    
                    if (prediction_error < 8'd3) begin // Good prediction (within 3°C)
                        if (ml_prediction_accuracy < 16'hF000) begin
                            ml_prediction_accuracy <= ml_prediction_accuracy + 16'd64;
                        end
                    end else begin // Poor prediction
                        if (ml_prediction_accuracy > 16'd64) begin
                            ml_prediction_accuracy <= ml_prediction_accuracy - 16'd32;
                        end
                        // Adapt learning rate
                        if (ml_learning_rate < 8'd10) begin
                            ml_learning_rate <= ml_learning_rate + 1;
                        end
                    end
                end
            end
        end else begin : gen_no_ml_thermal
            always_comb begin
                ml_temp_predictor = '{default: 8'd25};
                ml_power_correlator = 8'h80;
                ml_cooling_optimizer = 8'h80;
                ml_throttle_predictor = 8'h0;
                ml_prediction_accuracy = 16'h8000;
            end
        end
    endgenerate
    
    // Thermal Stress and Reliability Tracking
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            thermal_stress_accumulator <= 32'h0;
            thermal_cycle_counter <= 16'h0;
            reliability_factor <= 8'd100; // 100% reliability
        end else begin
            // Accumulate thermal stress (simplified Arrhenius model)
            logic [7:0] stress_factor;
            if (junction_temp_c > 8'd85) begin
                stress_factor = junction_temp_c - 8'd85; // Stress above 85°C
                if (thermal_stress_accumulator < 32'hFFFFFFF0) begin
                    thermal_stress_accumulator <= thermal_stress_accumulator + 
                                                 {24'h0, stress_factor};
                end
            end
            
            // Count thermal cycles (temperature swings > 10°C)
            logic [7:0] temp_swing;
            temp_swing = thermal_zones[hottest_zone_id].max_temp - 
                        thermal_zones[hottest_zone_id].min_temp;
            
            if (temp_swing > 8'd10) begin
                if (thermal_cycle_counter < 16'hFFFF) begin
                    thermal_cycle_counter <= thermal_cycle_counter + 1;
                end
            end
            
            // Update reliability factor based on stress
            if (thermal_stress_accumulator > 32'h100000) begin
                reliability_factor <= 8'd95; // 5% degradation
            end else if (thermal_stress_accumulator > 32'h10000) begin
                reliability_factor <= 8'd98; // 2% degradation
            end
        end
    end
    
    // Output Generation
    assign thermal_warning = (junction_temp_c >= warning_threshold_c) ||
                            (current_state == TM_WARNING) ||
                            (current_state == TM_CRITICAL) ||
                            (current_state == TM_EMERGENCY);
    
    assign thermal_critical = (junction_temp_c >= critical_threshold_c) ||
                             (current_state == TM_CRITICAL) ||
                             (current_state == TM_EMERGENCY);
    
    assign thermal_emergency = (junction_temp_c >= emergency_threshold_c) ||
                               (current_state == TM_EMERGENCY);
    
    assign thermal_throttle_level = current_throttle_level;
    
    // Cooling Control Outputs
    assign fan_speed_request = (ENABLE_ADAPTIVE_COOLING) ? 
                              adaptive_fan_curve[junction_temp_c[7:4]] : 
                              cooling_request_level;
    assign cooling_enable = cooling_request_level > 8'd25;
    assign cooling_mode = cooling_strategy;
    
    // Throttling Control Outputs  
    assign freq_throttle_req = current_throttle_level > 8'd10;
    assign freq_throttle_percent = current_throttle_level;
    assign power_throttle_req = current_throttle_level > 8'd50;
    assign power_throttle_percent = (current_throttle_level > 8'd50) ? 
                                   (current_throttle_level - 8'd50) : 8'd0;
    
    // Temperature and Margin Outputs
    assign thermal_margin_c = (emergency_threshold_c > junction_temp_c) ?
                             (emergency_threshold_c - junction_temp_c) : 8'd0;
    
    // Trend Calculation
    logic [7:0] temp_trend_calc;
    always_comb begin
        if (thermal_zones[hottest_zone_id].temp_rate > 8'd128) begin
            temp_trend_calc = thermal_zones[hottest_zone_id].temp_rate - 8'd128;
        end else begin
            temp_trend_calc = 8'd128 - thermal_zones[hottest_zone_id].temp_rate;
        end
    end
    assign temp_trend = temp_trend_calc;
    
    // Performance Outputs
    assign thermal_cycles = thermal_cycle_counter;
    assign thermal_budget_used = thermal_stress_accumulator;
    
    // ML Metrics
    assign ml_thermal_metrics[0] = ml_temp_predictor[hottest_zone_id];
    assign ml_thermal_metrics[1] = ml_power_correlator;
    assign ml_thermal_metrics[2] = ml_cooling_optimizer;
    assign ml_thermal_metrics[3] = ml_throttle_predictor;
    assign ml_thermal_metrics[4] = ml_prediction_accuracy[15:8];
    assign ml_thermal_metrics[5] = reliability_factor;
    
    // Status Register
    assign thermal_status = {
        current_state,              // [31:28]
        hottest_zone_id,            // [27:24]
        thermal_warning,            // [23]
        thermal_critical,           // [22]
        thermal_emergency,          // [21]
        cooling_enable,             // [20]
        freq_throttle_req,          // [19]
        power_throttle_req,         // [18]
        2'b0,                      // [17:16] Reserved
        junction_temp_c,            // [15:8]
        current_throttle_level      // [7:0]
    };
    
    // Debug Metrics
    assign debug_thermal_metrics[0] = {8'h0, junction_temp_c};
    assign debug_thermal_metrics[1] = {8'h0, max_zone_temp_c};
    assign debug_thermal_metrics[2] = {8'h0, thermal_margin_c};
    assign debug_thermal_metrics[3] = {8'h0, current_throttle_level};
    assign debug_thermal_metrics[4] = {8'h0, cooling_request_level};
    assign debug_thermal_metrics[5] = {8'h0, fan_speed_actual};
    assign debug_thermal_metrics[6] = thermal_cycle_counter;
    assign debug_thermal_metrics[7] = ml_prediction_accuracy;

endmodule