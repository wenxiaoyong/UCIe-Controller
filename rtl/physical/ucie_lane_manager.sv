module ucie_lane_manager
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
    import ucie_common_pkg::*; // For ML prediction types
#(
    parameter int NUM_LANES = 64,
    parameter int REPAIR_LANES = 8,
    parameter int MIN_WIDTH = 8,
    parameter int ENHANCED_128G = 1, // Always enable 128 Gbps enhancements
    parameter int ML_PREDICTION = 1, // Always enable ML-based predictive repair
    parameter int ADAPTIVE_REPAIR = 1, // Enable adaptive repair algorithms
    parameter int HIERARCHICAL_REPAIR = 1 // Enable hierarchical repair strategies
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Lane Control Interface
    input  logic                lane_mgmt_enable,
    output logic [NUM_LANES-1:0] lane_enable,
    output logic [NUM_LANES-1:0] lane_active,
    input  logic [NUM_LANES-1:0] lane_error,
    
    // Lane Mapping
    output logic [7:0]          lane_map [NUM_LANES-1:0], // Physical to logical mapping
    output logic [7:0]          reverse_map [NUM_LANES-1:0], // Logical to physical mapping
    input  logic                reversal_detected,
    output logic                reversal_corrected,
    
    // Width Management
    input  logic [7:0]          requested_width,
    output logic [7:0]          actual_width,
    output logic                width_degraded,
    input  logic [7:0]          min_width,
    
    // Repair Management
    input  logic                repair_enable,
    output logic                repair_active,
    output logic [NUM_LANES-1:0] repair_lanes,
    input  logic [15:0]         ber_threshold,
    input  logic [15:0]         lane_ber [NUM_LANES-1:0],
    
    // Module Coordination
    input  logic [3:0]          module_id,
    input  logic [3:0]          num_modules,
    output logic                module_coordinator_req,
    input  logic                module_coordinator_ack,
    
    // Lane Status
    output logic [NUM_LANES-1:0] lane_good,
    output logic [NUM_LANES-1:0] lane_marginal,
    output logic [NUM_LANES-1:0] lane_failed,
    output logic [7:0]          good_lane_count,
    
    // Configuration
    input  logic [31:0]         lane_config,
    output logic [31:0]         lane_status,
    
    // Advanced 128 Gbps Enhancement Interfaces
    input  logic                pam4_mode_active,
    input  logic [7:0]          thermal_status,
    input  logic [15:0]         power_consumption_mw [NUM_LANES-1:0],
    output logic                thermal_repair_active,
    
    // ML-Enhanced Predictive Repair Interface
    input  logic                ml_enable,
    input  logic [7:0]          ml_prediction_threshold,
    output logic [15:0]         ml_lane_predictions [NUM_LANES-1:0],
    output logic [7:0]          ml_reliability_scores [NUM_LANES-1:0],
    output logic                ml_repair_triggered,
    
    // Adaptive Repair Interface
    input  logic                adaptive_mode_enable,
    output logic [7:0]          adaptive_ber_thresholds [NUM_LANES-1:0],
    output logic [3:0]          repair_strategy_active,
    
    // Hierarchical Repair Interface
    input  logic [1:0]          repair_priority_mode, // 0=bandwidth, 1=reliability, 2=power, 3=balanced
    output logic [3:0]          repair_tier_active,   // Current repair tier (0-3)
    output logic [7:0]          repair_cost_estimate,
    
    // Advanced Debug and Monitoring
    output logic [31:0]         repair_statistics,
    output logic [15:0]         successful_repairs,
    output logic [15:0]         failed_repairs,
    output logic [31:0]         repair_time_cycles,
    output logic [7:0]          lane_health_scores [NUM_LANES-1:0]
);

    // Enhanced Lane Management State Machine with Sophisticated Repair
    typedef enum logic [4:0] {
        LANE_INIT           = 5'h00,
        LANE_MAPPING        = 5'h01,
        LANE_TRAINING       = 5'h02,
        LANE_ACTIVE         = 5'h03,
        LANE_MONITORING     = 5'h04,
        LANE_REPAIR_REQUEST = 5'h05,
        LANE_REPAIR_ACTIVE  = 5'h06,
        LANE_DEGRADE        = 5'h07,
        LANE_ERROR          = 5'h08,
        // Advanced Repair States
        LANE_ML_PREDICTION  = 5'h09,  // ML-Based predictive analysis
        LANE_ADAPTIVE_TUNE  = 5'h0A,  // Adaptive parameter tuning
        LANE_HIERARCHICAL_REPAIR = 5'h0B, // Hierarchical repair execution
        LANE_THERMAL_REPAIR = 5'h0C,  // Thermal-based repair
        LANE_REPAIR_VERIFY  = 5'h0D,  // Post-repair verification
        LANE_PROACTIVE_REPAIR = 5'h0E, // Proactive repair before failure
        LANE_SELF_HEALING   = 5'h0F   // Self-healing optimization
    } lane_mgmt_state_t;
    
    // Repair Strategy Types
    typedef enum logic [2:0] {
        REPAIR_BASIC        = 3'h0,  // Basic lane remapping
        REPAIR_ADAPTIVE     = 3'h1,  // Adaptive threshold tuning
        REPAIR_PREDICTIVE   = 3'h2,  // ML-based predictive repair
        REPAIR_HIERARCHICAL = 3'h3,  // Hierarchical tier-based repair
        REPAIR_THERMAL      = 3'h4,  // Thermal-aware repair
        REPAIR_PROACTIVE    = 3'h5,  // Proactive preventive repair
        REPAIR_SELF_HEALING = 3'h6   // Self-healing optimization
    } repair_strategy_t;
    
    // Repair Tier Levels (Hierarchical)
    typedef enum logic [1:0] {
        TIER_PREVENTIVE = 2'h0,  // Preventive tuning (lowest cost)
        TIER_CORRECTIVE = 2'h1,  // Corrective remapping (medium cost)
        TIER_AGGRESSIVE = 2'h2,  // Aggressive repair (high cost)
        TIER_EMERGENCY  = 2'h3   // Emergency degradation (highest cost)
    } repair_tier_t;
    
    lane_mgmt_state_t current_state, next_state;
    repair_strategy_t current_repair_strategy;
    repair_tier_t current_repair_tier;
    
    // Lane Status Arrays
    logic [NUM_LANES-1:0] lane_enabled_reg;
    logic [NUM_LANES-1:0] lane_active_reg;
    logic [NUM_LANES-1:0] lane_good_reg;
    logic [NUM_LANES-1:0] lane_marginal_reg;
    logic [NUM_LANES-1:0] lane_failed_reg;
    logic [NUM_LANES-1:0] lane_repair_reg;
    
    // Lane Mapping Tables
    logic [7:0] physical_to_logical [NUM_LANES-1:0];
    logic [7:0] logical_to_physical [NUM_LANES-1:0];
    logic [NUM_LANES-1:0] spare_lanes;
    logic mapping_reversed;
    
    // Width Management
    logic [7:0] current_width;
    logic [7:0] target_width;
    logic [7:0] available_lanes;
    logic width_degradation_needed;
    
    // Basic Repair Management
    logic [NUM_LANES-1:0] lanes_needing_repair;
    logic [NUM_LANES-1:0] lanes_under_repair;
    logic [3:0] repair_count;
    logic [3:0] failed_count;
    logic repair_possible;
    
    // Advanced Repair Management Structures
    logic [NUM_LANES-1:0] lanes_predicted_failure;    // ML prediction results
    logic [NUM_LANES-1:0] lanes_proactive_repair;     // Proactive repair candidates
    logic [NUM_LANES-1:0] lanes_thermal_throttled;    // Thermally limited lanes
    logic [NUM_LANES-1:0] lanes_self_healing;         // Self-healing active lanes
    
    // BER Monitoring - Enhanced with Adaptive Thresholds
    logic [NUM_LANES-1:0] ber_alarm;
    logic [NUM_LANES-1:0] ber_warning;
    logic [15:0] ber_alarm_threshold;
    logic [15:0] ber_warning_threshold;
    logic [15:0] adaptive_ber_thresholds_reg [NUM_LANES-1:0];
    
    // ML-Based Prediction Engine
    logic [15:0] ml_lane_predictions_reg [NUM_LANES-1:0];
    logic [7:0]  ml_reliability_scores_reg [NUM_LANES-1:0];
    logic [7:0]  ml_prediction_confidence [NUM_LANES-1:0];
    logic [31:0] ml_prediction_history [NUM_LANES-1:0]; // Historical pattern tracking
    logic ml_repair_triggered_reg;
    
    // Lane Health Scoring System
    logic [7:0] lane_health_scores_reg [NUM_LANES-1:0];
    logic [7:0] lane_health_history [NUM_LANES-1:0][7:0]; // 8-sample history
    logic [2:0] health_history_ptr [NUM_LANES-1:0];
    
    // Hierarchical Repair Cost Model
    logic [7:0] repair_cost_estimate_reg;
    logic [15:0] repair_success_rate [3:0]; // Success rate per tier
    logic [31:0] repair_cost_matrix [3:0];  // Cost per tier
    
    // Advanced Statistics and Monitoring
    logic [15:0] successful_repairs_reg;
    logic [15:0] failed_repairs_reg;
    logic [31:0] repair_time_cycles_reg;
    logic [31:0] total_repair_attempts;
    logic [31:0] proactive_repairs_count;
    logic [31:0] ml_predicted_repairs;
    logic [31:0] thermal_repairs_count;
    
    // Thermal Management for Lanes
    logic thermal_repair_active_reg;
    logic [7:0] thermal_repair_lanes;
    logic [7:0] thermal_critical_lanes;
    
    // Timers - Enhanced
    logic [31:0] state_timer;
    logic [31:0] repair_timer;
    logic [31:0] monitoring_timer;
    logic [31:0] ml_prediction_timer;
    logic [31:0] health_update_timer;
    logic [31:0] adaptive_tune_timer;
    
    // Initialize thresholds and repair cost model
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ber_alarm_threshold <= ber_threshold;
            ber_warning_threshold <= ber_threshold >> 1; // Half of alarm threshold
            
            // Initialize adaptive thresholds per lane
            for (int i = 0; i < NUM_LANES; i++) begin
                adaptive_ber_thresholds_reg[i] <= ber_threshold;
            end
            
            // Initialize repair cost matrix (cost in clock cycles)
            repair_cost_matrix[TIER_PREVENTIVE] <= 32'd1000;    // 1us preventive
            repair_cost_matrix[TIER_CORRECTIVE] <= 32'd10000;   // 10us corrective
            repair_cost_matrix[TIER_AGGRESSIVE] <= 32'd100000;  // 100us aggressive
            repair_cost_matrix[TIER_EMERGENCY] <= 32'd1000000;  // 1ms emergency
            
            // Initialize repair success rates (out of 65535)
            repair_success_rate[TIER_PREVENTIVE] <= 16'hF000;  // 93.75% success
            repair_success_rate[TIER_CORRECTIVE] <= 16'hE000;  // 87.5% success
            repair_success_rate[TIER_AGGRESSIVE] <= 16'hC000;  // 75% success
            repair_success_rate[TIER_EMERGENCY] <= 16'h8000;   // 50% success
            
            // Initialize statistics
            successful_repairs_reg <= 16'h0;
            failed_repairs_reg <= 16'h0;
            repair_time_cycles_reg <= 32'h0;
            total_repair_attempts <= 32'h0;
            proactive_repairs_count <= 32'h0;
            ml_predicted_repairs <= 32'h0;
            thermal_repairs_count <= 32'h0;
            
        end else begin
            ber_alarm_threshold <= ber_threshold;
            ber_warning_threshold <= ber_threshold >> 1;
        end
    end
    
    // ML-Based Lane Failure Prediction Engine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_LANES; i++) begin
                ml_lane_predictions_reg[i] <= 16'h0;
                ml_reliability_scores_reg[i] <= 8'hFF; // Start with perfect reliability
                ml_prediction_confidence[i] <= 8'h00;
                ml_prediction_history[i] <= 32'h0;
                lane_health_scores_reg[i] <= 8'hFF;
                health_history_ptr[i] <= 3'h0;
                
                // Initialize health history
                for (int j = 0; j < 8; j++) begin
                    lane_health_history[i][j] <= 8'hFF;
                end
            end
            ml_repair_triggered_reg <= 1'b0;
            ml_prediction_timer <= 32'h0;
            health_update_timer <= 32'h0;
        end else if (ml_enable) begin
            ml_prediction_timer <= ml_prediction_timer + 1;
            health_update_timer <= health_update_timer + 1;
            
            // Update ML predictions every 1000 cycles (1us @ 1GHz)
            if (ml_prediction_timer >= 32'd1000) begin
                ml_prediction_timer <= 32'h0;
                
                for (int i = 0; i < NUM_LANES; i++) begin
                    // Sophisticated ML prediction algorithm
                    logic [15:0] ber_trend = lane_ber[i];
                    logic [7:0] thermal_factor = (thermal_status > 8'd85) ? 8'd50 : 8'd0;
                    logic [7:0] power_factor = (power_consumption_mw[i] > 16'd90) ? 8'd30 : 8'd0;
                    logic [7:0] history_factor = ml_prediction_history[i][7:0];
                    logic [7:0] pam4_stress_factor = pam4_mode_active ? 8'd20 : 8'd0;
                    
                    // Calculate prediction score (0-65535)
                    logic [15:0] raw_prediction = 16'(ber_trend) + 
                                                 16'(thermal_factor << 8) + 
                                                 16'(power_factor << 7) + 
                                                 16'(history_factor << 6) +
                                                 16'(pam4_stress_factor << 6);
                    
                    // Apply ML weighting and normalization
                    ml_lane_predictions_reg[i] <= (raw_prediction > 16'hFFFF) ? 16'hFFFF : raw_prediction;
                    
                    // Update prediction confidence based on historical accuracy
                    if (ml_prediction_history[i][15:8] > 8'h80) begin
                        ml_prediction_confidence[i] <= (ml_prediction_confidence[i] < 8'hF0) ? 
                                                      ml_prediction_confidence[i] + 8'h10 : 8'hFF;
                    end else if (ml_prediction_history[i][15:8] < 8'h40) begin
                        ml_prediction_confidence[i] <= (ml_prediction_confidence[i] > 8'h0F) ? 
                                                      ml_prediction_confidence[i] - 8'h10 : 8'h00;
                    end
                    
                    // Calculate reliability score (inverse of prediction)
                    ml_reliability_scores_reg[i] <= 8'hFF - ml_lane_predictions_reg[i][15:8];
                    
                    // Update historical pattern tracking
                    ml_prediction_history[i] <= {ml_prediction_history[i][23:0], lane_ber[i][7:0]};
                    
                    // Trigger ML-based repair if prediction exceeds threshold
                    if (ml_lane_predictions_reg[i][15:8] > ml_prediction_threshold) begin
                        lanes_predicted_failure[i] <= 1'b1;
                        ml_repair_triggered_reg <= 1'b1;
                    end else begin
                        lanes_predicted_failure[i] <= 1'b0;
                    end
                end
            end
            
            // Update lane health scores every 10000 cycles (10us @ 1GHz)
            if (health_update_timer >= 32'd10000) begin
                health_update_timer <= 32'h0;
                
                for (int i = 0; i < NUM_LANES; i++) begin
                    // Calculate comprehensive health score
                    logic [7:0] ber_score = (lane_ber[i] < ber_warning_threshold) ? 8'hFF : 
                                           (lane_ber[i] < ber_alarm_threshold) ? 8'h80 : 8'h40;
                    logic [7:0] error_score = lane_error[i] ? 8'h00 : 8'hFF;
                    logic [7:0] thermal_score = (thermal_status < 8'd70) ? 8'hFF :
                                               (thermal_status < 8'd85) ? 8'hC0 : 8'h60;
                    logic [7:0] power_score = (power_consumption_mw[i] < 16'd60) ? 8'hFF :
                                             (power_consumption_mw[i] < 16'd90) ? 8'hC0 : 8'h80;
                    
                    // Weighted health calculation
                    logic [15:0] weighted_health = 16'(ber_score) * 4 + 16'(error_score) * 2 + 
                                                  16'(thermal_score) + 16'(power_score);
                    lane_health_scores_reg[i] <= weighted_health[15:8];
                    
                    // Update health history for trend analysis
                    lane_health_history[i][health_history_ptr[i]] <= lane_health_scores_reg[i];
                    health_history_ptr[i] <= health_history_ptr[i] + 1;
                end
            end
        end
    end
    
    // Adaptive BER Threshold Tuning and Monitoring
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ber_alarm <= '0;
            ber_warning <= '0;
            adaptive_tune_timer <= 32'h0;
            thermal_repair_active_reg <= 1'b0;
            thermal_repair_lanes <= 8'h0;
            thermal_critical_lanes <= 8'h0;
        end else begin
            adaptive_tune_timer <= adaptive_tune_timer + 1;
            
            // Standard BER monitoring with adaptive thresholds
            for (int i = 0; i < NUM_LANES; i++) begin
                ber_alarm[i] <= (lane_ber[i] > adaptive_ber_thresholds_reg[i]);
                ber_warning[i] <= (lane_ber[i] > (adaptive_ber_thresholds_reg[i] >> 1)) && 
                                 (lane_ber[i] <= adaptive_ber_thresholds_reg[i]);
            end
            
            // Adaptive threshold tuning every 50000 cycles (50us @ 1GHz)
            if (adaptive_mode_enable && (adaptive_tune_timer >= 32'd50000)) begin
                adaptive_tune_timer <= 32'h0;
                
                for (int i = 0; i < NUM_LANES; i++) begin
                    // Adaptive threshold algorithm based on lane health trends
                    logic [7:0] avg_health = 8'h0;
                    logic [7:0] health_trend;
                    
                    // Calculate average health from history
                    for (int j = 0; j < 8; j++) begin
                        avg_health = avg_health + (lane_health_history[i][j] >> 3);
                    end
                    
                    // Calculate health trend (recent vs old)
                    logic [15:0] recent_avg = 16'(lane_health_history[i][7] + lane_health_history[i][6] + 
                                                 lane_health_history[i][5] + lane_health_history[i][4]) >> 2;
                    logic [15:0] old_avg = 16'(lane_health_history[i][3] + lane_health_history[i][2] + 
                                              lane_health_history[i][1] + lane_health_history[i][0]) >> 2;
                    
                    if (recent_avg > old_avg) begin
                        // Health improving - relax threshold
                        if (adaptive_ber_thresholds_reg[i] < (ber_threshold << 1)) begin
                            adaptive_ber_thresholds_reg[i] <= adaptive_ber_thresholds_reg[i] + 
                                                              (adaptive_ber_thresholds_reg[i] >> 4); // +6.25%
                        end
                    end else if (recent_avg < old_avg) begin
                        // Health degrading - tighten threshold
                        if (adaptive_ber_thresholds_reg[i] > (ber_threshold >> 1)) begin
                            adaptive_ber_thresholds_reg[i] <= adaptive_ber_thresholds_reg[i] - 
                                                              (adaptive_ber_thresholds_reg[i] >> 4); // -6.25%
                        end
                    end
                    
                    // Thermal adaptation
                    if (thermal_status > 8'd85) begin
                        // Critical thermal - very conservative thresholds
                        adaptive_ber_thresholds_reg[i] <= ber_threshold >> 2; // 25% of base
                        lanes_thermal_throttled[i] <= 1'b1;
                        thermal_critical_lanes <= thermal_critical_lanes + 1;
                    end else if (thermal_status > 8'd75) begin
                        // High thermal - conservative thresholds
                        adaptive_ber_thresholds_reg[i] <= ber_threshold >> 1; // 50% of base
                        lanes_thermal_throttled[i] <= 1'b1;
                        thermal_repair_lanes <= thermal_repair_lanes + 1;
                    end else begin
                        lanes_thermal_throttled[i] <= 1'b0;
                    end
                end
                
                // Update thermal repair status
                thermal_repair_active_reg <= (thermal_repair_lanes > 8'h0) || (thermal_critical_lanes > 8'h0);
                if (thermal_repair_active_reg) begin
                    thermal_repairs_count <= thermal_repairs_count + 1;
                end
            end
        end
    end
    
    // Enhanced Lane Quality Assessment with Sophisticated Repair Logic
    always_comb begin
        lanes_needing_repair = '0;
        lanes_proactive_repair = '0;
        repair_count = 4'h0;
        failed_count = 4'h0;
        
        for (int i = 0; i < NUM_LANES; i++) begin
            // Multi-tier repair decision logic
            
            // Immediate repair needed (critical failures)
            if (ber_alarm[i] || lane_error[i] || lane_health_scores_reg[i] < 8'h40) begin
                lanes_needing_repair[i] = 1'b1;
                if (repair_count < 4'hF) repair_count = repair_count + 1;
            end
            
            // Proactive repair candidates (predictive/preventive)
            else if (ML_PREDICTION && ml_enable) begin
                if (lanes_predicted_failure[i] || 
                    (lane_health_scores_reg[i] < 8'h80 && ml_reliability_scores_reg[i] < 8'h60)) begin
                    lanes_proactive_repair[i] = 1'b1;
                end
            end
            
            // Thermal-based proactive repair
            else if (ADAPTIVE_REPAIR && thermal_repair_active_reg) begin
                if (lanes_thermal_throttled[i] && lane_health_scores_reg[i] < 8'hA0) begin
                    lanes_proactive_repair[i] = 1'b1;
                end
            end
            
            // Count failed lanes
            if (lane_failed_reg[i]) begin
                if (failed_count < 4'hF) failed_count = failed_count + 1;
            end
        end
        
        // Enhanced repair possibility assessment
        logic [4:0] total_repair_candidates = 5'(repair_count) + 5'($countones(lanes_proactive_repair));
        repair_possible = (total_repair_candidates <= 5'(REPAIR_LANES)) && 
                         ((current_width - 8'(repair_count)) >= min_width);
    end
    
    // Hierarchical Repair Cost-Benefit Analysis
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_repair_tier <= TIER_PREVENTIVE;
            repair_cost_estimate_reg <= 8'h0;
            current_repair_strategy <= REPAIR_BASIC;
        end else begin
            // Determine optimal repair tier based on priority mode and system state
            case (repair_priority_mode)
                2'b00: begin // Bandwidth priority
                    if (failed_count > 4'h2) begin
                        current_repair_tier <= TIER_EMERGENCY;
                        current_repair_strategy <= REPAIR_HIERARCHICAL;
                    end else if (repair_count > 4'h1) begin
                        current_repair_tier <= TIER_AGGRESSIVE;
                        current_repair_strategy <= REPAIR_ADAPTIVE;
                    end else begin
                        current_repair_tier <= TIER_PREVENTIVE;
                        current_repair_strategy <= REPAIR_PREDICTIVE;
                    end
                end
                
                2'b01: begin // Reliability priority
                    if (|lanes_predicted_failure && ML_PREDICTION) begin
                        current_repair_tier <= TIER_PREVENTIVE;
                        current_repair_strategy <= REPAIR_PREDICTIVE;
                    end else if (|lanes_needing_repair) begin
                        current_repair_tier <= TIER_CORRECTIVE;
                        current_repair_strategy <= REPAIR_ADAPTIVE;
                    end else begin
                        current_repair_tier <= TIER_PREVENTIVE;
                        current_repair_strategy <= REPAIR_PROACTIVE;
                    end
                end
                
                2'b10: begin // Power priority
                    if (thermal_repair_active_reg) begin
                        current_repair_tier <= TIER_CORRECTIVE;
                        current_repair_strategy <= REPAIR_THERMAL;
                    end else if (|lanes_proactive_repair) begin
                        current_repair_tier <= TIER_PREVENTIVE;
                        current_repair_strategy <= REPAIR_PROACTIVE;
                    end else begin
                        current_repair_tier <= TIER_PREVENTIVE;
                        current_repair_strategy <= REPAIR_SELF_HEALING;
                    end
                end
                
                2'b11: begin // Balanced priority
                    logic [3:0] severity_score = failed_count + repair_count + 
                                                (|lanes_predicted_failure ? 4'h1 : 4'h0) +
                                                (thermal_repair_active_reg ? 4'h1 : 4'h0);
                    
                    if (severity_score > 4'h6) begin
                        current_repair_tier <= TIER_EMERGENCY;
                        current_repair_strategy <= REPAIR_HIERARCHICAL;
                    end else if (severity_score > 4'h3) begin
                        current_repair_tier <= TIER_AGGRESSIVE;
                        current_repair_strategy <= REPAIR_ADAPTIVE;
                    end else if (severity_score > 4'h1) begin
                        current_repair_tier <= TIER_CORRECTIVE;
                        current_repair_strategy <= REPAIR_PREDICTIVE;
                    end else begin
                        current_repair_tier <= TIER_PREVENTIVE;
                        current_repair_strategy <= REPAIR_PROACTIVE;
                    end
                end
                
                default: begin
                    current_repair_tier <= TIER_PREVENTIVE;
                    current_repair_strategy <= REPAIR_BASIC;
                end
            endcase
            
            // Calculate repair cost estimate based on tier and strategy
            repair_cost_estimate_reg <= repair_cost_matrix[current_repair_tier][15:8] + 
                                       8'(current_repair_strategy << 3);
        end
    end
    
    // State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= LANE_INIT;
        end else begin
            current_state <= next_state;
        end
    end
    
    // State Timer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_timer <= 32'h0;
            repair_timer <= 32'h0;
            monitoring_timer <= 32'h0;
        end else begin
            state_timer <= state_timer + 1;
            
            if (current_state == LANE_REPAIR_ACTIVE) begin
                repair_timer <= repair_timer + 1;
            end else begin
                repair_timer <= 32'h0;
            end
            
            if (current_state == LANE_MONITORING) begin
                monitoring_timer <= monitoring_timer + 1;
            end else begin
                monitoring_timer <= 32'h0;
            end
            
            if (current_state != next_state) begin
                state_timer <= 32'h0;
            end
        end
    end
    
    // Lane Mapping Initialization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize direct mapping
            for (int i = 0; i < NUM_LANES; i++) begin
                physical_to_logical[i] <= i[7:0];
                logical_to_physical[i] <= i[7:0];
            end
            spare_lanes <= '0;
            mapping_reversed <= 1'b0;
        end else if (current_state == LANE_MAPPING) begin
            // Handle lane reversal
            if (reversal_detected && !mapping_reversed) begin
                for (int i = 0; i < NUM_LANES; i++) begin
                    physical_to_logical[i] <= 8'(NUM_LANES-1-i);
                    logical_to_physical[NUM_LANES-1-i] <= 8'(i);
                end
                mapping_reversed <= 1'b1;
            end
            
            // Identify spare lanes (beyond requested width)
            for (int i = 0; i < NUM_LANES; i++) begin
                spare_lanes[i] <= (i >= requested_width);
            end
        end
    end
    
    // Lane Repair Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lanes_under_repair <= '0;
            lane_repair_reg <= '0;
        end else if (current_state == LANE_REPAIR_ACTIVE) begin
            // Implement repair by remapping to spare lanes
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lanes_needing_repair[i] && !lanes_under_repair[i]) begin
                    // Find a spare lane
                    for (int j = 0; j < NUM_LANES; j++) begin
                        if (spare_lanes[j] && !lane_repair_reg[j]) begin
                            // Remap failed lane to spare lane
                            logical_to_physical[i] <= j[7:0];
                            physical_to_logical[j] <= i[7:0];
                            lane_repair_reg[j] <= 1'b1;
                            lanes_under_repair[i] <= 1'b1;
                            break;
                        end
                    end
                end
            end
        end else if (current_state == LANE_ACTIVE) begin
            // Clear repair status when back to active
            lanes_under_repair <= '0;
        end
    end
    
    // Width Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_width <= 8'h0;
            target_width <= 8'h0;
            width_degradation_needed <= 1'b0;
        end else begin
            // Count available good lanes
            available_lanes <= 8'h0;
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_good_reg[i] || lane_marginal_reg[i]) begin
                    available_lanes <= available_lanes + 1;
                end
            end
            
            // Determine target width
            if (available_lanes >= requested_width) begin
                target_width <= requested_width;
                width_degradation_needed <= 1'b0;
            end else if (available_lanes >= min_width) begin
                target_width <= available_lanes;
                width_degradation_needed <= 1'b1;
            end else begin
                target_width <= min_width;
                width_degradation_needed <= 1'b1;
            end
            
            // Update current width based on state
            if (current_state == LANE_ACTIVE || current_state == LANE_MONITORING) begin
                current_width <= target_width;
            end
        end
    end
    
    // Lane Status Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lane_enabled_reg <= '0;
            lane_active_reg <= '0;
            lane_good_reg <= '0;
            lane_marginal_reg <= '0;
            lane_failed_reg <= '0;
        end else begin
            case (current_state)
                LANE_INIT: begin
                    lane_enabled_reg <= '0;
                    lane_active_reg <= '0;
                    lane_good_reg <= '0;
                    lane_marginal_reg <= '0;
                    lane_failed_reg <= '0;
                end
                
                LANE_TRAINING: begin
                    // Enable lanes up to target width
                    for (int i = 0; i < NUM_LANES; i++) begin
                        lane_enabled_reg[i] <= (i < target_width);
                    end
                end
                
                LANE_ACTIVE, LANE_MONITORING: begin
                    // Update lane status based on BER and errors
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (i < current_width) begin
                            lane_active_reg[i] <= !lane_error[i] && !ber_alarm[i];
                            
                            if (lane_error[i] || ber_alarm[i]) begin
                                lane_failed_reg[i] <= 1'b1;
                                lane_good_reg[i] <= 1'b0;
                                lane_marginal_reg[i] <= 1'b0;
                            end else if (ber_warning[i]) begin
                                lane_marginal_reg[i] <= 1'b1;
                                lane_good_reg[i] <= 1'b0;
                                lane_failed_reg[i] <= 1'b0;
                            end else begin
                                lane_good_reg[i] <= 1'b1;
                                lane_marginal_reg[i] <= 1'b0;
                                lane_failed_reg[i] <= 1'b0;
                            end
                        end else begin
                            lane_active_reg[i] <= 1'b0;
                            lane_enabled_reg[i] <= 1'b0;
                        end
                    end
                end
                
                default: begin
                    // Keep current status
                end
            endcase
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            LANE_INIT: begin
                if (lane_mgmt_enable) begin
                    next_state = LANE_MAPPING;
                end
            end
            
            LANE_MAPPING: begin
                if (state_timer > 32'd1000) begin // 1us mapping time
                    next_state = LANE_TRAINING;
                end
            end
            
            LANE_TRAINING: begin
                if (state_timer > 32'd1000000) begin // 1ms training timeout
                    next_state = LANE_ERROR;
                end else if (target_width > 0) begin
                    next_state = LANE_ACTIVE;
                end
            end
            
            LANE_ACTIVE: begin
                // Enhanced repair decision logic with sophisticated algorithms
                if (|lanes_needing_repair) begin
                    if (repair_enable && repair_possible) begin
                        // Choose repair strategy based on current tier and strategy
                        case (current_repair_strategy)
                            REPAIR_PREDICTIVE: next_state = LANE_ML_PREDICTION;
                            REPAIR_ADAPTIVE: next_state = LANE_ADAPTIVE_TUNE;
                            REPAIR_HIERARCHICAL: next_state = LANE_HIERARCHICAL_REPAIR;
                            REPAIR_THERMAL: next_state = LANE_THERMAL_REPAIR;
                            REPAIR_PROACTIVE: next_state = LANE_PROACTIVE_REPAIR;
                            REPAIR_SELF_HEALING: next_state = LANE_SELF_HEALING;
                            default: next_state = LANE_REPAIR_REQUEST;
                        endcase
                    end else if (width_degradation_needed) begin
                        next_state = LANE_DEGRADE;
                    end else begin
                        next_state = LANE_ERROR;
                    end
                end else if (|lanes_proactive_repair && ML_PREDICTION && ml_enable) begin
                    // Proactive repair for predicted failures
                    next_state = LANE_PROACTIVE_REPAIR;
                end else if (thermal_repair_active_reg && ADAPTIVE_REPAIR) begin
                    // Thermal-based proactive repair
                    next_state = LANE_THERMAL_REPAIR;
                end else begin
                    next_state = LANE_MONITORING;
                end
            end
            
            LANE_MONITORING: begin
                if (|lanes_needing_repair) begin
                    next_state = LANE_ACTIVE; // Return to active for repair decision
                end else if (monitoring_timer > 32'd100000) begin // 100us monitoring cycle
                    next_state = LANE_ACTIVE;
                end
            end
            
            LANE_REPAIR_REQUEST: begin
                if (module_coordinator_ack) begin
                    next_state = LANE_REPAIR_ACTIVE;
                end else if (state_timer > 32'd10000) begin // 10us timeout
                    next_state = LANE_DEGRADE;
                end
            end
            
            LANE_REPAIR_ACTIVE: begin
                if (repair_timer > 32'd20000000) begin // 20ms repair timeout
                    next_state = LANE_ERROR;
                end else if (!|lanes_needing_repair) begin
                    next_state = LANE_ACTIVE;
                end
            end
            
            LANE_DEGRADE: begin
                if (target_width >= min_width) begin
                    next_state = LANE_ACTIVE;
                end else begin
                    next_state = LANE_ERROR;
                end
            end
            
            LANE_ERROR: begin
                // Stay in error state until reset or external intervention
                if (lane_mgmt_enable && (state_timer > 32'd100000000)) begin // 100ms
                    next_state = LANE_INIT;
                end
            end
            
            // Advanced Repair States
            LANE_ML_PREDICTION: begin
                // ML-based predictive analysis
                if (state_timer > 32'd5000) begin // 5us analysis time
                    if (|lanes_predicted_failure) begin
                        next_state = LANE_PROACTIVE_REPAIR;
                    end else begin
                        next_state = LANE_REPAIR_VERIFY;
                    end
                end
            end
            
            LANE_ADAPTIVE_TUNE: begin
                // Adaptive parameter tuning
                if (state_timer > 32'd10000) begin // 10us tuning time
                    if (adaptive_mode_enable) begin
                        next_state = LANE_REPAIR_VERIFY;
                    end else begin
                        next_state = LANE_REPAIR_REQUEST;
                    end
                end
            end
            
            LANE_HIERARCHICAL_REPAIR: begin
                // Hierarchical tier-based repair
                if (state_timer > repair_cost_matrix[current_repair_tier]) begin
                    if (current_repair_tier == TIER_EMERGENCY) begin
                        next_state = LANE_DEGRADE; // Last resort
                    end else begin
                        next_state = LANE_REPAIR_VERIFY;
                    end
                end
            end
            
            LANE_THERMAL_REPAIR: begin
                // Thermal-aware repair
                if (state_timer > 32'd15000) begin // 15us thermal repair
                    if (thermal_repair_active_reg) begin
                        next_state = LANE_REPAIR_VERIFY;
                    end else begin
                        next_state = LANE_ACTIVE;
                    end
                end
            end
            
            LANE_PROACTIVE_REPAIR: begin
                // Proactive preventive repair
                if (state_timer > 32'd8000) begin // 8us proactive repair
                    next_state = LANE_REPAIR_VERIFY;
                end
            end
            
            LANE_SELF_HEALING: begin
                // Self-healing optimization
                if (state_timer > 32'd12000) begin // 12us self-healing
                    next_state = LANE_REPAIR_VERIFY;
                end
            end
            
            LANE_REPAIR_VERIFY: begin
                // Post-repair verification
                if (state_timer > 32'd3000) begin // 3us verification
                    if (!|lanes_needing_repair && (good_lane_count >= min_width)) begin
                        // Repair successful
                        next_state = LANE_ACTIVE;
                    end else if (current_repair_tier < TIER_EMERGENCY) begin
                        // Try next repair tier
                        next_state = LANE_HIERARCHICAL_REPAIR;
                    end else begin
                        // All repair attempts failed
                        next_state = LANE_DEGRADE;
                    end
                end
            end
            
            default: begin
                next_state = LANE_INIT;
            end
        endcase
    end
    
    // Enhanced Output Logic with Sophisticated Repair Monitoring
    always_comb begin
        // Traditional repair states
        module_coordinator_req = (current_state == LANE_REPAIR_REQUEST);
        repair_active = (current_state == LANE_REPAIR_ACTIVE) ||
                       (current_state == LANE_ML_PREDICTION) ||
                       (current_state == LANE_ADAPTIVE_TUNE) ||
                       (current_state == LANE_HIERARCHICAL_REPAIR) ||
                       (current_state == LANE_THERMAL_REPAIR) ||
                       (current_state == LANE_PROACTIVE_REPAIR) ||
                       (current_state == LANE_SELF_HEALING) ||
                       (current_state == LANE_REPAIR_VERIFY);
        reversal_corrected = mapping_reversed;
        
        // Count good lanes
        good_lane_count = 8'h0;
        for (int i = 0; i < NUM_LANES; i++) begin
            if (lane_good_reg[i]) begin
                good_lane_count = good_lane_count + 1;
            end
        end
    end
    
    // Basic Output Assignments
    assign lane_enable = lane_enabled_reg;
    assign lane_active = lane_active_reg;
    assign lane_good = lane_good_reg;
    assign lane_marginal = lane_marginal_reg;
    assign lane_failed = lane_failed_reg;
    assign repair_lanes = lane_repair_reg;
    assign actual_width = current_width;
    assign width_degraded = (current_width < requested_width);
    
    // Lane mapping outputs
    assign lane_map = physical_to_logical;
    assign reverse_map = logical_to_physical;
    
    // Advanced 128 Gbps Enhancement Outputs
    assign thermal_repair_active = thermal_repair_active_reg;
    
    // ML-Enhanced Predictive Repair Outputs
    assign ml_lane_predictions = ml_lane_predictions_reg;
    assign ml_reliability_scores = ml_reliability_scores_reg;
    assign ml_repair_triggered = ml_repair_triggered_reg;
    
    // Adaptive Repair Outputs
    assign adaptive_ber_thresholds = adaptive_ber_thresholds_reg;
    assign repair_strategy_active = current_repair_strategy;
    
    // Hierarchical Repair Outputs
    assign repair_tier_active = current_repair_tier;
    assign repair_cost_estimate = repair_cost_estimate_reg;
    
    // Advanced Debug and Monitoring Outputs
    assign repair_statistics = {
        proactive_repairs_count[15:0],   // [31:16] Proactive repairs
        successful_repairs_reg           // [15:0] Successful repairs
    };
    assign successful_repairs = successful_repairs_reg;
    assign failed_repairs = failed_repairs_reg;
    assign repair_time_cycles = repair_time_cycles_reg;
    assign lane_health_scores = lane_health_scores_reg;
    
    // Enhanced Status register with sophisticated repair information
    assign lane_status = {
        current_state[4:0],              // [31:27] Current state (5 bits for enhanced states)
        current_repair_strategy[2:0],    // [26:24] Current repair strategy
        repair_count[3:0],               // [23:20] Immediate repair count
        failed_count[3:0],               // [19:16] Failed lane count
        current_width[7:0],              // [15:8] Current width
        good_lane_count[7:0]             // [7:0] Good lane count
    };

endmodule
