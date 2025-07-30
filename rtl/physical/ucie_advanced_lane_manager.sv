module ucie_advanced_lane_manager
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter NUM_LANES = 64,
    parameter MAX_LANE_GROUPS = 8,        // Support for lane grouping
    parameter ENHANCED_128G = 1,          // Enable 128 Gbps enhancements
    parameter ML_LANE_OPTIMIZATION = 1,   // Enable ML-based lane optimization
    parameter DYNAMIC_REMAPPING = 1,      // Enable dynamic lane remapping
    parameter REDUNDANCY_SUPPORT = 1      // Enable redundant lane support
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // System Configuration
    input  logic                lane_mgmt_enable,
    input  logic [7:0]          target_lane_count,
    input  logic [7:0]          min_lane_count,
    input  signaling_mode_t     signaling_mode,
    input  data_rate_t          data_rate,
    
    // Physical Lane Interface
    input  logic [NUM_LANES-1:0] phy_lane_ready,
    input  logic [NUM_LANES-1:0] phy_lane_error,
    input  logic [NUM_LANES-1:0] phy_lane_trained,
    input  logic [7:0]          phy_signal_quality [NUM_LANES-1:0],
    input  logic [15:0]         phy_error_count [NUM_LANES-1:0],
    output logic [NUM_LANES-1:0] phy_lane_enable,
    output logic [NUM_LANES-1:0] phy_lane_reset,
    
    // Lane Mapping and Configuration
    input  logic                lane_reversal_enable,
    input  logic [NUM_LANES-1:0] lane_polarity_invert,
    input  logic [7:0]          lane_group_config [MAX_LANE_GROUPS-1:0],
    output logic [7:0]          active_lane_map [NUM_LANES-1:0],
    output logic [7:0]          logical_to_physical_map [NUM_LANES-1:0],
    output logic [NUM_LANES-1:0] lane_group_boundaries,
    
    // Lane Repair and Recovery
    input  logic                repair_enable,
    input  logic [7:0]          repair_threshold_errors,
    input  logic [15:0]         repair_timeout_cycles,
    output logic [NUM_LANES-1:0] lane_repair_active,
    output logic [NUM_LANES-1:0] lane_repaired,
    output logic [15:0]         repair_operation_count,
    
    // Redundancy Management
    input  logic [NUM_LANES-1:0] redundant_lane_available,
    input  logic [7:0]          redundancy_ratio,    // Percentage of redundant lanes
    output logic [NUM_LANES-1:0] redundant_lane_active,
    output logic [7:0]          redundancy_utilization,
    
    // Performance Monitoring
    input  logic [15:0]         ber_threshold,
    input  logic [7:0]          quality_threshold,
    output logic [7:0]          lane_quality_score [NUM_LANES-1:0],
    output logic [15:0]         lane_ber_estimate [NUM_LANES-1:0],
    output logic [NUM_LANES-1:0] lane_degraded,
    output logic [NUM_LANES-1:0] lane_marginal,
    
    // ML Enhancement Interface
    input  logic                ml_enable,
    input  logic [7:0]          ml_prediction_confidence,
    input  logic [15:0]         ml_lane_prediction [NUM_LANES-1:0],
    output logic [7:0]          ml_optimization_score,
    output logic [15:0]         ml_lane_recommendation [NUM_LANES-1:0],
    
    // 128 Gbps Advanced Features
    input  logic                pam4_mode,
    input  logic [3:0]          parallel_lane_groups,
    input  logic                adaptive_equalization,
    output logic [3:0]          active_lane_groups,
    output logic [7:0]          group_balance_score,
    
    // Thermal Management Interface
    input  temperature_t        lane_temperature [NUM_LANES-1:0],
    input  logic [NUM_LANES-1:0] thermal_throttle,
    output logic [NUM_LANES-1:0] thermal_lane_disable,
    
    // Status and Debug
    output logic [31:0]         lane_mgmt_status,
    output logic [7:0]          active_lane_count,
    output logic [7:0]          failed_lane_count,
    output logic [7:0]          training_success_rate,
    output logic [15:0]         lane_transition_count,
    output logic                link_degradation_alarm
);

    // Internal Type Definitions
    typedef enum logic [2:0] {
        LANE_DISABLED     = 3'h0,
        LANE_TRAINING     = 3'h1,
        LANE_ACTIVE       = 3'h2,
        LANE_ERROR        = 3'h3,
        LANE_REPAIR       = 3'h4,
        LANE_REDUNDANT    = 3'h5,
        LANE_MARGINAL     = 3'h6,
        LANE_THERMAL_OFF  = 3'h7
    } lane_state_t;
    
    typedef struct packed {
        lane_state_t      state;
        lane_state_t      prev_state;
        logic [15:0]      error_count;
        logic [15:0]      success_count;
        logic [7:0]       quality_score;
        logic [7:0]       training_attempts;
        logic [31:0]      last_error_time;
        logic [31:0]      active_time;
        logic [7:0]       repair_attempts;
        logic [7:0]       group_id;
        logic [7:0]       logical_id;
        logic [7:0]       physical_id;
        logic             reversal_applied;
        logic             polarity_inverted;
    } lane_info_t;
    
    typedef struct packed {
        logic [7:0]       member_count;
        logic [7:0]       active_count;
        logic [7:0]       target_count;
        logic [7:0]       quality_average;
        logic [15:0]      group_ber;
        logic             balanced;
        logic             operational;
        logic [NUM_LANES-1:0] member_mask;
    } lane_group_info_t;
    
    // Per-Lane State Management
    lane_info_t lane_info [NUM_LANES-1:0];
    lane_group_info_t group_info [MAX_LANE_GROUPS-1:0];
    
    // Lane Assignment and Mapping
    logic [7:0] physical_to_logical_map [NUM_LANES-1:0];
    logic [NUM_LANES-1:0] lane_assignment_valid;
    logic [NUM_LANES-1:0] lane_training_mask;
    logic [NUM_LANES-1:0] lane_active_mask;
    
    // Repair and Recovery State
    logic [NUM_LANES-1:0] repair_in_progress;
    logic [NUM_LANES-1:0] repair_success;
    logic [15:0] repair_timer [NUM_LANES-1:0];
    logic [15:0] global_repair_count;
    
    // Redundancy Management
    logic [NUM_LANES-1:0] primary_lanes;
    logic [NUM_LANES-1:0] spare_lanes;
    logic [7:0] redundancy_pool_size;
    logic [7:0] redundancy_used;
    
    // ML Optimization State
    logic [7:0] ml_lane_scores [NUM_LANES-1:0];
    logic [15:0] ml_confidence_scores [NUM_LANES-1:0];
    logic [7:0] ml_global_optimization_score;
    logic [31:0] ml_iteration_count;
    
    // Performance Tracking
    logic [31:0] global_cycle_counter;
    logic [15:0] lane_state_transitions;
    logic [7:0] training_success_count;
    logic [7:0] training_attempt_count;
    
    // Lane Grouping for 128 Gbps
    logic [3:0] group_assignment [NUM_LANES-1:0];
    logic [7:0] lanes_per_group;
    logic [MAX_LANE_GROUPS-1:0] group_active;
    
    // Initialize lane configuration
    initial begin
        lanes_per_group = NUM_LANES / MAX_LANE_GROUPS;
        
        for (int i = 0; i < NUM_LANES; i++) begin
            group_assignment[i] = i / lanes_per_group;
        end
    end
    
    // Per-Lane State Machine
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx++) begin : gen_lane_management
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    lane_info[lane_idx].state <= LANE_DISABLED;
                    lane_info[lane_idx].prev_state <= LANE_DISABLED;
                    lane_info[lane_idx].error_count <= '0;
                    lane_info[lane_idx].success_count <= '0;
                    lane_info[lane_idx].quality_score <= 8'h80;
                    lane_info[lane_idx].training_attempts <= '0;
                    lane_info[lane_idx].last_error_time <= '0;
                    lane_info[lane_idx].active_time <= '0;
                    lane_info[lane_idx].repair_attempts <= '0;
                    lane_info[lane_idx].group_id <= group_assignment[lane_idx];
                    lane_info[lane_idx].logical_id <= lane_idx;
                    lane_info[lane_idx].physical_id <= lane_idx;
                    lane_info[lane_idx].reversal_applied <= 1'b0;
                    lane_info[lane_idx].polarity_inverted <= lane_polarity_invert[lane_idx];
                    repair_timer[lane_idx] <= '0;
                end else if (lane_mgmt_enable) begin
                    // Update previous state
                    lane_info[lane_idx].prev_state <= lane_info[lane_idx].state;
                    
                    // State transition logic
                    case (lane_info[lane_idx].state)
                        LANE_DISABLED: begin
                            if (lane_idx < target_lane_count) begin
                                lane_info[lane_idx].state <= LANE_TRAINING;
                                lane_info[lane_idx].training_attempts <= lane_info[lane_idx].training_attempts + 1;
                            end
                        end
                        
                        LANE_TRAINING: begin
                            if (phy_lane_trained[lane_idx] && phy_lane_ready[lane_idx]) begin
                                lane_info[lane_idx].state <= LANE_ACTIVE;
                                lane_info[lane_idx].success_count <= lane_info[lane_idx].success_count + 1;
                                lane_info[lane_idx].active_time <= global_cycle_counter;
                            end else if (phy_lane_error[lane_idx]) begin
                                lane_info[lane_idx].state <= LANE_ERROR;
                                lane_info[lane_idx].error_count <= lane_info[lane_idx].error_count + 1;
                                lane_info[lane_idx].last_error_time <= global_cycle_counter;
                            end else if (lane_info[lane_idx].training_attempts > 8'd10) begin
                                // Training failed after multiple attempts
                                lane_info[lane_idx].state <= LANE_ERROR;
                            end
                        end
                        
                        LANE_ACTIVE: begin
                            // Monitor for errors and quality degradation
                            if (phy_lane_error[lane_idx]) begin
                                lane_info[lane_idx].state <= LANE_ERROR;
                                lane_info[lane_idx].error_count <= lane_info[lane_idx].error_count + 1;
                                lane_info[lane_idx].last_error_time <= global_cycle_counter;
                            end else if (thermal_throttle[lane_idx] || 
                                       lane_temperature[lane_idx] > TEMP_CRITICAL) begin
                                lane_info[lane_idx].state <= LANE_THERMAL_OFF;
                            end else if (phy_signal_quality[lane_idx] < quality_threshold) begin
                                lane_info[lane_idx].state <= LANE_MARGINAL;
                            end else if (phy_error_count[lane_idx] > repair_threshold_errors) begin
                                if (repair_enable) begin
                                    lane_info[lane_idx].state <= LANE_REPAIR;
                                    lane_info[lane_idx].repair_attempts <= lane_info[lane_idx].repair_attempts + 1;
                                    repair_timer[lane_idx] <= repair_timeout_cycles;
                                end else begin
                                    lane_info[lane_idx].state <= LANE_ERROR;
                                end
                            end
                        end
                        
                        LANE_ERROR: begin
                            if (repair_enable && (lane_info[lane_idx].repair_attempts < 8'd5)) begin
                                lane_info[lane_idx].state <= LANE_REPAIR;
                                lane_info[lane_idx].repair_attempts <= lane_info[lane_idx].repair_attempts + 1;
                                repair_timer[lane_idx] <= repair_timeout_cycles;
                            end else if (REDUNDANCY_SUPPORT && redundant_lane_available[lane_idx]) begin
                                lane_info[lane_idx].state <= LANE_REDUNDANT;
                            end else begin
                                lane_info[lane_idx].state <= LANE_DISABLED;
                            end
                        end
                        
                        LANE_REPAIR: begin
                            if (repair_timer[lane_idx] > 0) begin
                                repair_timer[lane_idx] <= repair_timer[lane_idx] - 1;
                            end else begin
                                // Repair timeout - check if successful
                                if (phy_lane_ready[lane_idx] && !phy_lane_error[lane_idx]) begin
                                    lane_info[lane_idx].state <= LANE_TRAINING;
                                    repair_success[lane_idx] <= 1'b1;
                                end else begin
                                    lane_info[lane_idx].state <= LANE_ERROR;
                                    repair_success[lane_idx] <= 1'b0;
                                end
                            end
                        end
                        
                        LANE_REDUNDANT: begin
                            // Activate redundant lane
                            if (phy_lane_ready[lane_idx] && !phy_lane_error[lane_idx]) begin
                                lane_info[lane_idx].state <= LANE_ACTIVE;
                            end else begin
                                lane_info[lane_idx].state <= LANE_DISABLED;
                            end
                        end
                        
                        LANE_MARGINAL: begin
                            if (phy_signal_quality[lane_idx] > (quality_threshold + 8'd20)) begin
                                // Quality improved
                                lane_info[lane_idx].state <= LANE_ACTIVE;
                            end else if (phy_lane_error[lane_idx] || 
                                       phy_error_count[lane_idx] > repair_threshold_errors) begin
                                lane_info[lane_idx].state <= LANE_ERROR;
                            end
                        end
                        
                        LANE_THERMAL_OFF: begin
                            if (!thermal_throttle[lane_idx] && 
                                lane_temperature[lane_idx] < TEMP_NORMAL) begin
                                lane_info[lane_idx].state <= LANE_TRAINING;
                            end
                        end
                        
                        default: lane_info[lane_idx].state <= LANE_DISABLED;
                    endcase
                    
                    // Update quality score based on signal quality and error rate
                    if (phy_signal_quality[lane_idx] > 8'd200 && phy_error_count[lane_idx] < 16'd10) begin
                        lane_info[lane_idx].quality_score <= 8'hFF; // Excellent
                    end else if (phy_signal_quality[lane_idx] > 8'd150) begin
                        lane_info[lane_idx].quality_score <= 8'hC0; // Good
                    end else if (phy_signal_quality[lane_idx] > quality_threshold) begin
                        lane_info[lane_idx].quality_score <= 8'h80; // Acceptable
                    end else begin
                        lane_info[lane_idx].quality_score <= 8'h40; // Poor
                    end
                end
            end
            
            // Lane control outputs
            always_comb begin
                phy_lane_enable[lane_idx] = (lane_info[lane_idx].state == LANE_TRAINING) ||
                                          (lane_info[lane_idx].state == LANE_ACTIVE) ||
                                          (lane_info[lane_idx].state == LANE_REPAIR) ||
                                          (lane_info[lane_idx].state == LANE_REDUNDANT) ||
                                          (lane_info[lane_idx].state == LANE_MARGINAL);
                
                phy_lane_reset[lane_idx] = (lane_info[lane_idx].state == LANE_REPAIR) ||
                                         (lane_info[lane_idx].prev_state != lane_info[lane_idx].state &&
                                          lane_info[lane_idx].state == LANE_TRAINING);
                
                lane_repair_active[lane_idx] = (lane_info[lane_idx].state == LANE_REPAIR);
                lane_repaired[lane_idx] = repair_success[lane_idx];
                
                lane_quality_score[lane_idx] = lane_info[lane_idx].quality_score;
                lane_ber_estimate[lane_idx] = phy_error_count[lane_idx];
                
                lane_degraded[lane_idx] = (lane_info[lane_idx].state == LANE_ERROR) ||
                                        (lane_info[lane_idx].state == LANE_MARGINAL);
                lane_marginal[lane_idx] = (lane_info[lane_idx].state == LANE_MARGINAL);
                
                thermal_lane_disable[lane_idx] = (lane_info[lane_idx].state == LANE_THERMAL_OFF);
                
                active_lane_map[lane_idx] = lane_info[lane_idx].logical_id;
                logical_to_physical_map[lane_idx] = lane_info[lane_idx].physical_id;
            end
        end
    endgenerate
    
    // Lane Reversal and Polarity Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_LANES; i++) begin
                physical_to_logical_map[i] <= i;
            end
        end else if (lane_reversal_enable && DYNAMIC_REMAPPING) begin
            // Implement lane reversal logic
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_reversal_enable) begin
                    // Reverse the lane mapping
                    physical_to_logical_map[i] <= NUM_LANES - 1 - i;
                    lane_info[i].reversal_applied <= 1'b1;
                end else begin
                    physical_to_logical_map[i] <= i;
                    lane_info[i].reversal_applied <= 1'b0;
                end
            end
        end
    end
    
    // Lane Group Management for 128 Gbps
    genvar group_idx;
    generate
        for (group_idx = 0; group_idx < MAX_LANE_GROUPS; group_idx++) begin : gen_group_management
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    group_info[group_idx].member_count <= lanes_per_group;
                    group_info[group_idx].active_count <= '0;
                    group_info[group_idx].target_count <= lane_group_config[group_idx];
                    group_info[group_idx].quality_average <= 8'h80;
                    group_info[group_idx].group_ber <= '0;
                    group_info[group_idx].balanced <= 1'b0;
                    group_info[group_idx].operational <= 1'b0;
                    group_info[group_idx].member_mask <= '0;
                end else if (ENHANCED_128G && pam4_mode) begin
                    // Update group statistics
                    logic [7:0] active_in_group = '0;
                    logic [15:0] quality_sum = '0;
                    logic [23:0] ber_sum = '0;
                    logic [NUM_LANES-1:0] group_mask = '0;
                    
                    for (int lane = 0; lane < NUM_LANES; lane++) begin
                        if (lane_info[lane].group_id == group_idx) begin
                            group_mask[lane] = 1'b1;
                            
                            if (lane_info[lane].state == LANE_ACTIVE) begin
                                active_in_group = active_in_group + 1;
                                quality_sum = quality_sum + lane_info[lane].quality_score;
                                ber_sum = ber_sum + phy_error_count[lane];
                            end
                        end
                    end
                    
                    group_info[group_idx].member_mask <= group_mask;
                    group_info[group_idx].active_count <= active_in_group;
                    
                    if (active_in_group > 0) begin
                        group_info[group_idx].quality_average <= quality_sum / active_in_group;
                        group_info[group_idx].group_ber <= ber_sum / active_in_group;
                    end
                    
                    // Check if group is balanced (active count close to target)
                    logic [7:0] target = group_info[group_idx].target_count;
                    group_info[group_idx].balanced <= (active_in_group >= (target * 3 / 4));
                    group_info[group_idx].operational <= (active_in_group >= (target / 2));
                end
            end
            
            assign group_active[group_idx] = group_info[group_idx].operational;
        end
    endgenerate
    
    // Redundancy Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            redundancy_pool_size <= '0;
            redundancy_used <= '0;
            primary_lanes <= '0;
            spare_lanes <= '0;
        end else if (REDUNDANCY_SUPPORT) begin
            // Calculate redundancy pool
            redundancy_pool_size <= popcount(redundant_lane_available);
            redundancy_used <= popcount(redundant_lane_active);
            
            // Assign primary and spare lanes
            logic [7:0] primary_count = (target_lane_count * (100 - redundancy_ratio)) / 100;
            
            for (int i = 0; i < NUM_LANES; i++) begin
                if (i < primary_count) begin
                    primary_lanes[i] <= 1'b1;
                    spare_lanes[i] <= 1'b0;
                end else if (redundant_lane_available[i]) begin
                    primary_lanes[i] <= 1'b0;
                    spare_lanes[i] <= 1'b1;
                end else begin
                    primary_lanes[i] <= 1'b0;
                    spare_lanes[i] <= 1'b0;
                end
            end
            
            // Activate redundant lanes when primary lanes fail
            for (int i = 0; i < NUM_LANES; i++) begin
                if (primary_lanes[i] && (lane_info[i].state == LANE_ERROR)) begin
                    // Find available spare lane
                    for (int j = 0; j < NUM_LANES; j++) begin
                        if (spare_lanes[j] && (lane_info[j].state == LANE_DISABLED)) begin
                            redundant_lane_active[j] <= 1'b1;
                            lane_info[j].state <= LANE_REDUNDANT;
                            break;
                        end
                    end
                end
            end
        end
    end
    
    // ML-Based Lane Optimization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ml_global_optimization_score <= 8'h80;
            ml_iteration_count <= '0;
            
            for (int i = 0; i < NUM_LANES; i++) begin
                ml_lane_scores[i] <= 8'h80;
                ml_confidence_scores[i] <= '0;
            end
        end else if (ML_LANE_OPTIMIZATION && ml_enable) begin
            ml_iteration_count <= ml_iteration_count + 1;
            
            // ML optimization for each lane
            for (int i = 0; i < NUM_LANES; i++) begin
                // Combine multiple factors for ML scoring
                logic [7:0] quality_factor = lane_info[i].quality_score;
                logic [7:0] reliability_factor = (lane_info[i].error_count < 16'd10) ? 8'hFF : 
                                               8'(255 - lane_info[i].error_count[7:0]);
                logic [7:0] thermal_factor = (lane_temperature[i] < TEMP_WARNING) ? 8'hFF : 8'h40;
                logic [7:0] prediction_factor = ml_lane_prediction[i][7:0];
                
                // Weighted ML score calculation
                ml_lane_scores[i] <= (quality_factor + reliability_factor + 
                                    thermal_factor + prediction_factor) >> 2;
                
                // Update confidence based on prediction accuracy
                if (ml_lane_prediction[i][15:8] > 8'h80) begin // High confidence prediction
                    logic prediction_accurate = (lane_info[i].state == LANE_ACTIVE) == 
                                               (prediction_factor > 8'h80);
                    if (prediction_accurate) begin
                        ml_confidence_scores[i] <= (ml_confidence_scores[i] < 16'hF000) ?
                                                 ml_confidence_scores[i] + 16'h100 : 16'hFFFF;
                    end else begin
                        ml_confidence_scores[i] <= (ml_confidence_scores[i] > 16'h100) ?
                                                 ml_confidence_scores[i] - 16'h100 : 16'h0000;
                    end
                end
                
                // Generate ML recommendations
                if (ml_lane_scores[i] > 8'hC0) begin
                    ml_lane_recommendation[i] <= 16'h8000; // Recommend as primary
                end else if (ml_lane_scores[i] > 8'h80) begin
                    ml_lane_recommendation[i] <= 16'h4000; // Recommend as backup
                end else begin
                    ml_lane_recommendation[i] <= 16'h2000; // Recommend disable
                end
            end
            
            // Global optimization score
            logic [15:0] total_score = '0;
            logic [7:0] active_count = '0;
            
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_info[i].state == LANE_ACTIVE) begin
                    total_score = total_score + ml_lane_scores[i];
                    active_count = active_count + 1;
                end
            end
            
            if (active_count > 0) begin
                ml_global_optimization_score <= total_score / active_count;
            end
        end
    end
    
    // Performance Monitoring and Statistics
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_cycle_counter <= '0;
            lane_state_transitions <= '0;
            training_success_count <= '0;
            training_attempt_count <= '0;
            global_repair_count <= '0;
        end else begin
            global_cycle_counter <= global_cycle_counter + 1;
            
            // Count state transitions
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_info[i].state != lane_info[i].prev_state) begin
                    lane_state_transitions <= lane_state_transitions + 1;
                    
                    // Count training statistics
                    if (lane_info[i].state == LANE_TRAINING) begin
                        training_attempt_count <= training_attempt_count + 1;
                    end else if (lane_info[i].prev_state == LANE_TRAINING && 
                               lane_info[i].state == LANE_ACTIVE) begin
                        training_success_count <= training_success_count + 1;
                    end
                    
                    // Count repair operations
                    if (lane_info[i].state == LANE_REPAIR) begin
                        global_repair_count <= global_repair_count + 1;
                    end
                end
            end
        end
    end
    
    // Output Assignments
    logic [7:0] active_lanes_total;
    logic [7:0] failed_lanes_total;
    logic [7:0] group_balance_total;
    
    always_comb begin
        active_lanes_total = '0;
        failed_lanes_total = '0;
        group_balance_total = '0;
        
        for (int i = 0; i < NUM_LANES; i++) begin
            if (lane_info[i].state == LANE_ACTIVE) begin
                active_lanes_total = active_lanes_total + 1;
            end
            if (lane_info[i].state == LANE_ERROR || lane_info[i].state == LANE_DISABLED) begin
                failed_lanes_total = failed_lanes_total + 1;
            end
        end
        
        // Calculate group balance score
        for (int g = 0; g < MAX_LANE_GROUPS; g++) begin
            if (group_info[g].balanced) begin
                group_balance_total = group_balance_total + (255 / MAX_LANE_GROUPS);
            end
        end
    end
    
    assign active_lane_count = active_lanes_total;
    assign failed_lane_count = failed_lanes_total;
    assign active_lane_groups = popcount(group_active);
    assign group_balance_score = group_balance_total;
    
    assign training_success_rate = (training_attempt_count > 0) ?
                                  8'((training_success_count * 100) / training_attempt_count) : 8'h00;
    
    assign lane_transition_count = lane_state_transitions;
    assign repair_operation_count = global_repair_count;
    
    assign redundancy_utilization = REDUNDANCY_SUPPORT ? 
                                   8'((redundancy_used * 100) / redundancy_pool_size) : 8'h00;
    
    assign link_degradation_alarm = (active_lanes_total < min_lane_count) ||
                                   (failed_lanes_total > (target_lane_count >> 2));
    
    assign ml_optimization_score = ml_global_optimization_score;
    
    // Lane group boundary detection
    always_comb begin
        lane_group_boundaries = '0;
        for (int i = 0; i < NUM_LANES-1; i++) begin
            if (lane_info[i].group_id != lane_info[i+1].group_id) begin
                lane_group_boundaries[i] = 1'b1;
            end
        end
    end
    
    assign lane_mgmt_status = {
        ENHANCED_128G[0],               // [31] 128G enhanced mode
        ML_LANE_OPTIMIZATION[0],        // [30] ML optimization enabled
        REDUNDANCY_SUPPORT[0],          // [29] Redundancy support enabled
        lane_reversal_enable,           // [28] Lane reversal enabled
        active_lane_groups,             // [27:24] Active lane groups
        training_success_rate,          // [23:16] Training success rate
        active_lane_count,              // [15:8] Active lane count
        failed_lane_count               // [7:0] Failed lane count
    };

endmodule