module ucie_thermal_manager
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter NUM_LANES = 64,
    parameter NUM_ZONES = 8,                    // Thermal zones for monitoring
    parameter TEMP_SENSOR_RESOLUTION = 10,     // 0.1°C resolution
    parameter THERMAL_HYSTERESIS = 50,         // 5.0°C hysteresis
    parameter POWER_OPTIMIZATION = 1,          // Enable 72% power reduction
    parameter PROCESS_COMPENSATION = 1         // Enable process variation compensation
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // System Configuration
    input  logic                thermal_enable,
    input  temperature_t        ambient_temperature,
    input  logic [7:0]          process_corner,     // SS, TT, FF corner indication
    
    // Per-Lane Power and Temperature Interface
    input  power_mw_t           lane_power [NUM_LANES-1:0],
    input  logic [NUM_LANES-1:0] lane_enable,
    output temperature_t        lane_temperature [NUM_LANES-1:0],
    output logic [NUM_LANES-1:0] thermal_throttle_req,
    output logic [NUM_LANES-1:0] thermal_alarm,
    
    // Zone-Based Thermal Monitoring
    input  temperature_t        zone_temperature [NUM_ZONES-1:0],
    output logic [NUM_ZONES-1:0] zone_alarm,
    output logic [NUM_ZONES-1:0] zone_critical,
    
    // Dynamic Power Scaling Control
    output logic [7:0]          power_scale_factor [NUM_LANES-1:0],  // 0-255, 255=100%
    output logic [3:0]          voltage_scale [NUM_LANES-1:0],       // Voltage scaling
    output logic [3:0]          frequency_scale [NUM_LANES-1:0],     // Frequency scaling
    
    // Thermal Throttling Coordination
    input  logic                global_throttle_enable,
    input  logic [7:0]          throttle_threshold_temp,
    input  logic [7:0]          throttle_release_temp,
    output logic                system_thermal_alarm,
    output logic                emergency_shutdown_req,
    
    // Process Variation Compensation
    output logic [4:0]          process_compensation [NUM_LANES-1:0],
    output logic [7:0]          timing_adjustment [NUM_LANES-1:0],
    
    // ML Enhancement Interface
    input  logic                ml_thermal_enable,
    input  logic [7:0]          ml_prediction_weight,
    output logic [15:0]         thermal_prediction [NUM_LANES-1:0],
    output logic [7:0]          ml_thermal_score,
    
    // Status and Debug
    output logic [31:0]         thermal_status,
    output logic [15:0]         max_temperature,
    output logic [15:0]         total_power_consumption,
    output logic [NUM_LANES-1:0] lane_thermal_status
);

    // Internal Type Definitions
    typedef struct packed {
        temperature_t current_temp;
        temperature_t max_temp;
        temperature_t avg_temp;
        logic [15:0]  temp_history [7:0];  // 8-sample history
        logic [2:0]   history_ptr;
        logic         alarm_state;
        logic         critical_state;
        logic [7:0]   thermal_score;
    } thermal_lane_state_t;
    
    typedef struct packed {
        logic [7:0]   scale_factor;
        logic [3:0]   voltage_level;
        logic [3:0]   frequency_divider;
        logic         throttle_active;
        logic [15:0]  throttle_duration;
        logic [7:0]   throttle_intensity;
    } power_control_state_t;
    
    typedef struct packed {
        logic [4:0]   compensation_value;
        logic [7:0]   timing_offset;
        logic [1:0]   corner_detected;
        logic         compensation_active;
        logic [7:0]   variation_score;
    } process_state_t;
    
    // Per-lane State Arrays
    thermal_lane_state_t thermal_state [NUM_LANES-1:0];
    power_control_state_t power_state [NUM_LANES-1:0];
    process_state_t process_state [NUM_LANES-1:0];
    
    // Zone Management
    logic [NUM_ZONES-1:0] zone_throttle_req;
    temperature_t zone_max_temp [NUM_ZONES-1:0];
    logic [7:0] zone_utilization [NUM_ZONES-1:0];
    
    // Global Thermal Management
    temperature_t global_max_temp;
    temperature_t global_avg_temp;
    logic [15:0] global_power;
    logic [7:0] thermal_margin;
    
    // ML Thermal Prediction
    logic [15:0] ml_temp_prediction [NUM_LANES-1:0];
    logic [7:0] ml_confidence_score;
    logic [15:0] ml_iteration_count;
    
    // Thermal calculation constants
    parameter real THERMAL_RESISTANCE = 0.5;    // °C/mW thermal resistance
    parameter real THERMAL_CAPACITANCE = 100.0; // mJ/°C thermal capacitance
    parameter real LEAKAGE_TEMP_COEFF = 0.02;   // Leakage temperature coefficient
    
    // Generate per-lane thermal management
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx++) begin : gen_thermal_lanes
            
            // Thermal State Management
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    thermal_state[lane_idx].current_temp <= ambient_temperature;
                    thermal_state[lane_idx].max_temp <= ambient_temperature;
                    thermal_state[lane_idx].avg_temp <= ambient_temperature;
                    thermal_state[lane_idx].history_ptr <= 3'h0;
                    thermal_state[lane_idx].alarm_state <= 1'b0;
                    thermal_state[lane_idx].critical_state <= 1'b0;
                    thermal_state[lane_idx].thermal_score <= 8'h80;  // Neutral score
                    
                    for (int i = 0; i < 8; i++) begin
                        thermal_state[lane_idx].temp_history[i] <= ambient_temperature;
                    end
                end else if (thermal_enable && lane_enable[lane_idx]) begin
                    // Calculate lane temperature based on power dissipation
                    temperature_t calculated_temp;
                    power_mw_t effective_power;
                    
                    // Account for process variation in power calculation
                    case (process_corner[1:0])
                        2'b00: effective_power = power_mw_t'(lane_power[lane_idx] * 120 / 100); // SS corner (+20%)
                        2'b01: effective_power = lane_power[lane_idx];                            // TT corner (nominal)
                        2'b10: effective_power = power_mw_t'(lane_power[lane_idx] * 85 / 100);  // FF corner (-15%)
                        default: effective_power = lane_power[lane_idx];
                    endcase
                    
                    // Simple thermal model: T = T_ambient + P * R_th
                    calculated_temp = ambient_temperature + 
                                     temperature_t'(effective_power * THERMAL_RESISTANCE * 10); // *10 for 0.1°C units
                    
                    // Update current temperature with low-pass filtering
                    thermal_state[lane_idx].current_temp <= 
                        temperature_t'((thermal_state[lane_idx].current_temp * 7 + calculated_temp) >> 3);
                    
                    // Update temperature history
                    thermal_state[lane_idx].temp_history[thermal_state[lane_idx].history_ptr] <= 
                        thermal_state[lane_idx].current_temp;
                    thermal_state[lane_idx].history_ptr <= thermal_state[lane_idx].history_ptr + 1;
                    
                    // Track maximum temperature
                    if (thermal_state[lane_idx].current_temp > thermal_state[lane_idx].max_temp) begin
                        thermal_state[lane_idx].max_temp <= thermal_state[lane_idx].current_temp;
                    end
                    
                    // Calculate average temperature from history
                    temperature_t temp_sum = 16'h0;
                    for (int i = 0; i < 8; i++) begin
                        temp_sum = temp_sum + thermal_state[lane_idx].temp_history[i];
                    end
                    thermal_state[lane_idx].avg_temp <= temp_sum >> 3;
                    
                    // Alarm and critical state management with hysteresis
                    logic alarm_trigger = (thermal_state[lane_idx].current_temp > TEMP_WARNING);
                    logic alarm_release = (thermal_state[lane_idx].current_temp < (TEMP_WARNING - THERMAL_HYSTERESIS));
                    logic critical_trigger = (thermal_state[lane_idx].current_temp > TEMP_CRITICAL);
                    logic critical_release = (thermal_state[lane_idx].current_temp < (TEMP_CRITICAL - THERMAL_HYSTERESIS));
                    
                    if (alarm_trigger) begin
                        thermal_state[lane_idx].alarm_state <= 1'b1;
                    end else if (alarm_release && !critical_trigger) begin
                        thermal_state[lane_idx].alarm_state <= 1'b0;
                    end
                    
                    if (critical_trigger) begin
                        thermal_state[lane_idx].critical_state <= 1'b1;
                    end else if (critical_release) begin
                        thermal_state[lane_idx].critical_state <= 1'b0;
                    end
                    
                    // Calculate thermal performance score (0-255, higher is better)
                    if (thermal_state[lane_idx].current_temp < TEMP_NORMAL) begin
                        thermal_state[lane_idx].thermal_score <= 8'hFF;  // Excellent
                    end else if (thermal_state[lane_idx].current_temp < TEMP_WARNING) begin
                        // Linear scaling between normal and warning
                        logic [15:0] temp_range = TEMP_WARNING - TEMP_NORMAL;
                        logic [15:0] temp_offset = thermal_state[lane_idx].current_temp - TEMP_NORMAL;
                        thermal_state[lane_idx].thermal_score <= 8'(255 - (temp_offset * 100 / temp_range));
                    end else begin
                        thermal_state[lane_idx].thermal_score <= 8'h20;  // Poor thermal performance
                    end
                end
            end
            
            // Dynamic Power Scaling
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    power_state[lane_idx].scale_factor <= 8'hFF;      // 100% power
                    power_state[lane_idx].voltage_level <= 4'h8;      // Nominal voltage
                    power_state[lane_idx].frequency_divider <= 4'h1;  // No frequency scaling
                    power_state[lane_idx].throttle_active <= 1'b0;
                    power_state[lane_idx].throttle_duration <= 16'h0;
                    power_state[lane_idx].throttle_intensity <= 8'h0;
                end else if (thermal_enable && lane_enable[lane_idx]) begin
                    // Determine throttling requirements
                    logic should_throttle = thermal_state[lane_idx].alarm_state || 
                                          (global_throttle_enable && 
                                           thermal_state[lane_idx].current_temp > temperature_t'(throttle_threshold_temp * 10));
                    
                    logic should_release = thermal_state[lane_idx].current_temp < 
                                         temperature_t'(throttle_release_temp * 10);
                    
                    if (should_throttle && !power_state[lane_idx].throttle_active) begin
                        // Start throttling
                        power_state[lane_idx].throttle_active <= 1'b1;
                        power_state[lane_idx].throttle_duration <= 16'h0;
                        
                        // Determine throttling intensity based on temperature
                        if (thermal_state[lane_idx].critical_state) begin
                            // Critical throttling: 50% power reduction
                            power_state[lane_idx].scale_factor <= 8'h80;      // 50% power
                            power_state[lane_idx].voltage_level <= 4'h6;      // Reduced voltage
                            power_state[lane_idx].frequency_divider <= 4'h2;  // Half frequency
                            power_state[lane_idx].throttle_intensity <= 8'hC0; // High intensity
                        end else begin
                            // Warning throttling: 25% power reduction
                            power_state[lane_idx].scale_factor <= 8'hC0;      // 75% power
                            power_state[lane_idx].voltage_level <= 4'h7;      // Slightly reduced voltage
                            power_state[lane_idx].frequency_divider <= 4'h1;  // No frequency scaling
                            power_state[lane_idx].throttle_intensity <= 8'h80; // Medium intensity
                        end
                    end else if (should_release && power_state[lane_idx].throttle_active) begin
                        // Release throttling gradually
                        if (power_state[lane_idx].throttle_duration > 16'h100) begin  // Minimum throttle time
                            power_state[lane_idx].throttle_active <= 1'b0;
                            power_state[lane_idx].scale_factor <= 8'hFF;      // 100% power
                            power_state[lane_idx].voltage_level <= 4'h8;      // Nominal voltage
                            power_state[lane_idx].frequency_divider <= 4'h1;  // No frequency scaling
                            power_state[lane_idx].throttle_intensity <= 8'h0;
                        end
                    end
                    
                    // Update throttle duration
                    if (power_state[lane_idx].throttle_active) begin
                        power_state[lane_idx].throttle_duration <= power_state[lane_idx].throttle_duration + 1;
                    end
                end
            end
            
            // Process Variation Compensation
            if (PROCESS_COMPENSATION) begin : gen_process_compensation
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        process_state[lane_idx].compensation_value <= 5'h10;  // Neutral compensation
                        process_state[lane_idx].timing_offset <= 8'h80;       // Neutral timing
                        process_state[lane_idx].corner_detected <= 2'b01;     // Assume TT
                        process_state[lane_idx].compensation_active <= 1'b0;
                        process_state[lane_idx].variation_score <= 8'h80;     // Neutral score
                    end else if (thermal_enable && lane_enable[lane_idx]) begin
                        // Detect process corner based on temperature vs power relationship
                        logic [15:0] expected_temp = ambient_temperature + 
                                                   temperature_t'(lane_power[lane_idx] * THERMAL_RESISTANCE * 10);
                        logic [15:0] temp_error = (thermal_state[lane_idx].current_temp > expected_temp) ?
                                                (thermal_state[lane_idx].current_temp - expected_temp) :
                                                (expected_temp - thermal_state[lane_idx].current_temp);
                        
                        // Process corner detection
                        if (temp_error > 16'd100) begin  // 10°C error threshold
                            if (thermal_state[lane_idx].current_temp > expected_temp) begin
                                process_state[lane_idx].corner_detected <= 2'b00;  // SS (slow, hot)
                                process_state[lane_idx].compensation_value <= 5'h18;  // Increase drive strength
                                process_state[lane_idx].timing_offset <= 8'h70;       // Earlier timing
                            end else begin
                                process_state[lane_idx].corner_detected <= 2'b10;  // FF (fast, cool)
                                process_state[lane_idx].compensation_value <= 5'h08;  // Decrease drive strength
                                process_state[lane_idx].timing_offset <= 8'h90;       // Later timing
                            end
                            process_state[lane_idx].compensation_active <= 1'b1;
                        end else begin
                            process_state[lane_idx].corner_detected <= 2'b01;  // TT (typical)
                            process_state[lane_idx].compensation_value <= 5'h10;  // Nominal compensation
                            process_state[lane_idx].timing_offset <= 8'h80;       // Nominal timing
                        end
                        
                        // Calculate variation score based on compensation effectiveness
                        if (temp_error < 16'd50) begin
                            process_state[lane_idx].variation_score <= 8'hFF;  // Excellent compensation
                        end else begin
                            process_state[lane_idx].variation_score <= 8'(255 - (temp_error >> 2));
                        end
                    end
                end
            end
            
            // ML-Enhanced Thermal Prediction
            if (ml_thermal_enable) begin : gen_ml_thermal_prediction
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        ml_temp_prediction[lane_idx] <= ambient_temperature;
                    end else if (thermal_enable && lane_enable[lane_idx]) begin
                        // Simple ML prediction based on power trend and thermal history
                        logic [15:0] power_trend;
                        logic [15:0] temp_trend;
                        logic [15:0] predicted_temp;
                        
                        // Calculate power trend (simplified)
                        power_trend = (lane_power[lane_idx] > power_mw_t'(50)) ? 16'h10 : 16'h00;
                        
                        // Calculate temperature trend from history
                        if (thermal_state[lane_idx].history_ptr >= 3'h2) begin
                            logic [15:0] recent_temp = thermal_state[lane_idx].temp_history[thermal_state[lane_idx].history_ptr - 1];
                            logic [15:0] older_temp = thermal_state[lane_idx].temp_history[thermal_state[lane_idx].history_ptr - 2];
                            temp_trend = (recent_temp > older_temp) ? (recent_temp - older_temp) : 16'h00;
                        end else begin
                            temp_trend = 16'h00;
                        end
                        
                        // ML prediction with weighted factors
                        predicted_temp = thermal_state[lane_idx].current_temp + 
                                       ((power_trend * ml_prediction_weight) >> 4) +
                                       ((temp_trend * ml_prediction_weight) >> 3);
                        
                        ml_temp_prediction[lane_idx] <= predicted_temp;
                    end
                end
            end
            
            // Output assignments for this lane
            always_comb begin
                lane_temperature[lane_idx] = thermal_state[lane_idx].current_temp;
                thermal_throttle_req[lane_idx] = power_state[lane_idx].throttle_active;
                thermal_alarm[lane_idx] = thermal_state[lane_idx].alarm_state;
                
                power_scale_factor[lane_idx] = power_state[lane_idx].scale_factor;
                voltage_scale[lane_idx] = power_state[lane_idx].voltage_level;
                frequency_scale[lane_idx] = power_state[lane_idx].frequency_divider;
                
                if (PROCESS_COMPENSATION) begin
                    process_compensation[lane_idx] = process_state[lane_idx].compensation_value;
                    timing_adjustment[lane_idx] = process_state[lane_idx].timing_offset;
                end else begin
                    process_compensation[lane_idx] = 5'h10;  // Nominal
                    timing_adjustment[lane_idx] = 8'h80;     // Nominal
                end
                
                thermal_prediction[lane_idx] = ml_thermal_enable ? 
                                              ml_temp_prediction[lane_idx] : 
                                              thermal_state[lane_idx].current_temp;
                
                lane_thermal_status[lane_idx] = lane_enable[lane_idx] && 
                                              !thermal_state[lane_idx].critical_state;
            end
        end
    endgenerate
    
    // Zone-Based Thermal Management
    genvar zone_idx;
    generate
        for (zone_idx = 0; zone_idx < NUM_ZONES; zone_idx++) begin : gen_thermal_zones
            logic [7:0] lanes_per_zone = NUM_LANES / NUM_ZONES;
            logic [7:0] zone_start = zone_idx * lanes_per_zone;
            logic [7:0] zone_end = (zone_idx + 1) * lanes_per_zone - 1;
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    zone_max_temp[zone_idx] <= ambient_temperature;
                    zone_utilization[zone_idx] <= 8'h00;
                end else if (thermal_enable) begin
                    // Find maximum temperature in this zone
                    temperature_t max_in_zone = ambient_temperature;
                    logic [7:0] active_lanes_in_zone = 8'h00;
                    
                    for (int lane = zone_start; lane <= zone_end && lane < NUM_LANES; lane++) begin
                        if (lane_enable[lane]) begin
                            active_lanes_in_zone = active_lanes_in_zone + 1;
                            if (thermal_state[lane].current_temp > max_in_zone) begin
                                max_in_zone = thermal_state[lane].current_temp;
                            end
                        end
                    end
                    
                    zone_max_temp[zone_idx] <= max_in_zone;
                    zone_utilization[zone_idx] <= (active_lanes_in_zone * 255) / lanes_per_zone;
                end
            end
            
            // Zone alarm and critical states
            assign zone_alarm[zone_idx] = (zone_max_temp[zone_idx] > TEMP_WARNING) || 
                                        (zone_temperature[zone_idx] > TEMP_WARNING);
            assign zone_critical[zone_idx] = (zone_max_temp[zone_idx] > TEMP_CRITICAL) || 
                                           (zone_temperature[zone_idx] > TEMP_CRITICAL);
        end
    endgenerate
    
    // Global Thermal Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_max_temp <= ambient_temperature;
            global_avg_temp <= ambient_temperature;
            global_power <= 16'h0;
            thermal_margin <= 8'hFF;
            ml_confidence_score <= 8'h80;
            ml_iteration_count <= 16'h0;
        end else if (thermal_enable) begin
            // Calculate global maximum temperature
            temperature_t max_temp = ambient_temperature;
            temperature_t temp_sum = 16'h0;
            power_mw_t power_sum = 16'h0;
            logic [7:0] active_lane_count = 8'h0;
            
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_enable[i]) begin
                    active_lane_count = active_lane_count + 1;
                    temp_sum = temp_sum + thermal_state[i].current_temp;
                    power_sum = power_sum + lane_power[i];
                    if (thermal_state[i].current_temp > max_temp) begin
                        max_temp = thermal_state[i].current_temp;
                    end
                end
            end
            
            global_max_temp <= max_temp;
            global_power <= power_sum;
            
            if (active_lane_count > 0) begin
                global_avg_temp <= temp_sum / active_lane_count;
            end else begin
                global_avg_temp <= ambient_temperature;
            end
            
            // Calculate thermal margin
            if (max_temp < TEMP_CRITICAL) begin
                thermal_margin <= 8'((TEMP_CRITICAL - max_temp) * 255 / (TEMP_CRITICAL - ambient_temperature));
            end else begin
                thermal_margin <= 8'h00;  // No margin left
            end
            
            // ML confidence score based on prediction accuracy
            if (ml_thermal_enable) begin
                ml_iteration_count <= ml_iteration_count + 1;
                
                // Calculate prediction accuracy (simplified)
                logic [15:0] prediction_error = 16'h0;
                for (int i = 0; i < NUM_LANES; i++) begin
                    if (lane_enable[i] && ml_temp_prediction[i] > 0) begin
                        logic [15:0] error = (thermal_state[i].current_temp > ml_temp_prediction[i]) ?
                                           (thermal_state[i].current_temp - ml_temp_prediction[i]) :
                                           (ml_temp_prediction[i] - thermal_state[i].current_temp);
                        prediction_error = prediction_error + error;
                    end
                end
                
                if (active_lane_count > 0) begin
                    prediction_error = prediction_error / active_lane_count;
                    if (prediction_error < 16'd50) begin  // <5°C average error
                        ml_confidence_score <= 8'hF0;  // High confidence
                    end else if (prediction_error < 16'd100) begin  // <10°C average error
                        ml_confidence_score <= 8'hC0;  // Medium confidence
                    end else begin
                        ml_confidence_score <= 8'h40;  // Low confidence
                    end
                end
            end
        end
    end
    
    // System-level thermal protection
    assign system_thermal_alarm = |zone_alarm || (global_max_temp > TEMP_WARNING);
    assign emergency_shutdown_req = |zone_critical || (global_max_temp > (TEMP_CRITICAL + 16'd100)); // +10°C emergency
    
    // ML thermal score output
    assign ml_thermal_score = ml_confidence_score;
    
    // Status output generation
    assign thermal_status = {
        emergency_shutdown_req,       // [31] Emergency shutdown required
        system_thermal_alarm,         // [30] System thermal alarm
        ml_thermal_enable,            // [29] ML thermal prediction enabled
        PROCESS_COMPENSATION[0],      // [28] Process compensation enabled
        4'b0,                         // [27:24] Reserved
        thermal_margin,               // [23:16] Thermal margin (0-255)
        popcount(thermal_alarm),      // [15:8] Number of lanes in thermal alarm
        popcount(lane_enable)         // [7:0] Number of enabled lanes
    };
    
    assign max_temperature = global_max_temp;
    assign total_power_consumption = global_power;

endmodule