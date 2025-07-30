module ucie_adaptive_system_controller
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter NUM_LANES = 64,
    parameter NUM_PROTOCOLS = 8,
    parameter NUM_ADAPTATION_MODES = 8,     // Different adaptation strategies
    parameter ADAPTATION_WINDOW = 1024,    // Cycles for adaptation decisions
    parameter RESPONSE_TIME_CYCLES = 256,  // Maximum response time for adaptations
    parameter ENHANCED_128G = 1,           // Enable 128 Gbps enhancements
    parameter ML_INTEGRATION = 1           // Enable ML-driven adaptations
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // System Configuration
    input  logic                adaptive_control_enable,
    input  logic [2:0]          adaptation_aggressiveness,  // 0=conservative, 7=aggressive
    input  logic [15:0]         performance_targets [7:0], // Various performance targets
    input  logic                emergency_mode,
    
    // ML Prediction Inputs
    input  logic [15:0]         ml_lane_quality_prediction [NUM_LANES-1:0],
    input  logic [15:0]         ml_lane_failure_probability [NUM_LANES-1:0],
    input  logic [31:0]         ml_throughput_prediction,
    input  logic [15:0]         ml_latency_prediction,
    input  logic [7:0]          ml_congestion_prediction [NUM_PROTOCOLS-1:0],
    input  logic [15:0]         ml_optimization_confidence,
    input  logic [7:0]          ml_model_accuracy,
    
    // Real-time System Status
    input  logic [NUM_LANES-1:0] lane_active,
    input  logic [7:0]          lane_quality [NUM_LANES-1:0],
    input  temperature_t        lane_temperature [NUM_LANES-1:0],
    input  logic [NUM_LANES-1:0] thermal_throttle,
    input  logic [31:0]         current_throughput,
    input  logic [15:0]         current_latency,
    input  logic [7:0]          current_congestion [NUM_PROTOCOLS-1:0],
    
    // Protocol Performance
    input  logic [NUM_PROTOCOLS-1:0] protocol_active,
    input  logic [15:0]         protocol_bandwidth [NUM_PROTOCOLS-1:0],
    input  logic [7:0]          protocol_priority [NUM_PROTOCOLS-1:0],
    input  logic [15:0]         protocol_latency [NUM_PROTOCOLS-1:0],
    
    // Power and Thermal Status
    input  logic [15:0]         total_power_consumption,
    input  logic [7:0]          thermal_margin,
    input  temperature_t        ambient_temperature,
    input  logic                system_thermal_alarm,
    
    // Adaptive Control Outputs
    output logic [7:0]          adaptive_lane_config [NUM_LANES-1:0],
    output logic [NUM_LANES-1:0] adaptive_lane_enable,
    output logic [NUM_LANES-1:0] adaptive_lane_disable,
    output logic [3:0]          adaptive_data_rate,
    output signaling_mode_t     adaptive_signaling_mode,
    
    // Protocol Adaptation
    output logic [7:0]          adaptive_protocol_weights [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] adaptive_protocol_enable,
    output logic [7:0]          adaptive_flow_control [NUM_PROTOCOLS-1:0],
    output logic [15:0]         adaptive_bandwidth_allocation [NUM_PROTOCOLS-1:0],
    
    // Power Management Adaptations
    output logic [7:0]          adaptive_power_scale [NUM_LANES-1:0],
    output logic [3:0]          adaptive_voltage_scale [NUM_LANES-1:0],
    output logic [3:0]          adaptive_frequency_scale [NUM_LANES-1:0],
    output logic                adaptive_power_gating_enable,
    
    // Advanced 128 Gbps Adaptations
    output logic [3:0]          adaptive_equalization [NUM_LANES-1:0],
    output logic [7:0]          adaptive_pam4_optimization,
    output logic [3:0]          adaptive_parallel_lanes,
    output logic                adaptive_zero_latency_bypass,
    
    // Quality of Service Adaptations
    output logic [3:0]          adaptive_qos_class [NUM_PROTOCOLS-1:0],
    output logic [15:0]         adaptive_latency_targets [NUM_PROTOCOLS-1:0],
    output logic [7:0]          adaptive_bandwidth_guarantee [NUM_PROTOCOLS-1:0],
    
    // Learning and Feedback
    input  logic [15:0]         adaptation_feedback_score,
    input  logic [7:0]          adaptation_success_rate,
    output logic [15:0]         adaptation_effectiveness,
    output logic [31:0]         adaptation_history,
    
    // Status and Monitoring
    output logic [31:0]         adaptive_status,
    output logic [15:0]         adaptations_performed,
    output logic [7:0]          current_adaptation_mode,
    output logic [15:0]         performance_improvement,
    output logic [31:0]         debug_adaptation_state
);

    // Internal Type Definitions
    typedef enum logic [2:0] {
        ADAPT_CONSERVATIVE   = 3'h0,    // Minimal changes, high confidence required
        ADAPT_BALANCED      = 3'h1,     // Moderate changes based on trends
        ADAPT_AGGRESSIVE    = 3'h2,     // Quick adaptations to optimize performance
        ADAPT_PREDICTIVE    = 3'h3,     // ML-driven predictive adaptations
        ADAPT_EMERGENCY     = 3'h4,     // Emergency response mode
        ADAPT_LEARNING      = 3'h5,     // Learning mode with exploration
        ADAPT_POWER_SAVE    = 3'h6,     // Power optimization priority
        ADAPT_PERFORMANCE   = 3'h7      // Maximum performance priority
    } adaptation_mode_t;
    
    typedef struct packed {
        logic [15:0]             target_value;
        logic [15:0]             current_value;
        logic [15:0]             predicted_value;
        logic [7:0]              confidence_level;
        logic [7:0]              priority_weight;
        logic [31:0]             last_adaptation_cycle;
        logic [7:0]              adaptation_count;
        logic                    target_met;
        logic                    needs_adaptation;
    } performance_metric_t;
    
    typedef struct packed {
        logic [7:0]              lane_id;
        logic [7:0]              adaptation_type;    // Type of adaptation applied
        logic [15:0]             old_value;
        logic [15:0]             new_value;
        logic [31:0]             timestamp;
        logic [7:0]              confidence_score;
        logic [15:0]             expected_improvement;
        logic [15:0]             actual_improvement;
        logic                    successful;
        logic                    valid;
    } adaptation_record_t;
    
    typedef struct packed {
        logic [15:0]             effectiveness_score;
        logic [7:0]              success_count;
        logic [7:0]              failure_count;
        logic [31:0]             total_adaptations;
        logic [15:0]             average_improvement;
        logic [7:0]              convergence_indicator;
        logic                    learning_complete;
    } adaptation_learning_t;
    
    // System State
    adaptation_mode_t current_mode, next_mode;
    performance_metric_t performance_metrics [8];  // Track multiple performance aspects
    adaptation_record_t adaptation_history_buffer [32];  // Circular buffer of adaptations
    adaptation_learning_t learning_state;
    
    // Adaptation Control State
    logic [31:0] global_cycle_counter;
    logic [31:0] adaptation_cycle_counter;
    logic [4:0] history_write_ptr;
    logic [15:0] total_adaptations_count;
    logic [7:0] pending_adaptations;
    
    // Performance Tracking
    logic [15:0] baseline_throughput;
    logic [15:0] baseline_latency;
    logic [15:0] performance_delta;
    logic [31:0] performance_monitoring_window;
    
    // ML Integration State
    logic [7:0] ml_confidence_threshold;
    logic [15:0] ml_prediction_accuracy;
    logic [31:0] ml_adaptation_cycles;
    
    // Adaptation Decision State
    logic [NUM_LANES-1:0] lane_adaptation_pending;
    logic [NUM_PROTOCOLS-1:0] protocol_adaptation_pending;
    logic power_adaptation_pending;
    logic qos_adaptation_pending;
    
    // 128 Gbps Enhanced State
    logic [7:0] pam4_adaptation_score;
    logic [3:0] parallel_lane_optimization;
    logic [15:0] enhanced_performance_metrics;
    
    // Initialize performance metrics
    initial begin
        // Set default performance targets
        performance_metrics[0].target_value = 16'h8000;  // Throughput target
        performance_metrics[1].target_value = 16'h1000;  // Latency target (lower is better)
        performance_metrics[2].target_value = 16'h4000;  // Quality target
        performance_metrics[3].target_value = 16'h2000;  // Power target (lower is better)
        performance_metrics[4].target_value = 16'h6000;  // Thermal target
        performance_metrics[5].target_value = 16'h8000;  // Reliability target
        performance_metrics[6].target_value = 16'h7000;  // Congestion target (lower is better)
        performance_metrics[7].target_value = 16'h9000;  // Overall efficiency target
        
        ml_confidence_threshold = 8'h80;  // 50% confidence threshold
    end
    
    // Performance Metrics Monitoring
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 8; i++) begin
                performance_metrics[i].current_value <= 16'h4000;
                performance_metrics[i].predicted_value <= 16'h4000;
                performance_metrics[i].confidence_level <= 8'h40;
                performance_metrics[i].priority_weight <= 8'h80;
                performance_metrics[i].last_adaptation_cycle <= 32'h0;
                performance_metrics[i].adaptation_count <= 8'h0;
                performance_metrics[i].target_met <= 1'b0;
                performance_metrics[i].needs_adaptation <= 1'b0;
            end
            
            baseline_throughput <= 16'h4000;
            baseline_latency <= 16'h2000;
            performance_delta <= 16'h0;
        end else if (adaptive_control_enable) begin
            // Update current performance metrics
            performance_metrics[0].current_value <= current_throughput[15:0];  // Throughput
            performance_metrics[1].current_value <= current_latency;           // Latency
            performance_metrics[7].current_value <= 16'h8000;                 // Overall efficiency
            
            // Calculate average lane quality
            logic [15:0] quality_sum = 16'h0;
            logic [7:0] quality_count = 8'h0;
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_active[i]) begin
                    quality_sum = quality_sum + {8'h0, lane_quality[i]};
                    quality_count = quality_count + 1;
                end
            end
            
            if (quality_count > 0) begin
                performance_metrics[2].current_value <= quality_sum / quality_count;  // Quality
            end
            
            performance_metrics[3].current_value <= total_power_consumption;          // Power
            performance_metrics[4].current_value <= {8'h0, thermal_margin};         // Thermal
            
            // Calculate reliability score
            logic [15:0] reliability_sum = 16'h0;
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_active[i]) begin
                    reliability_sum = reliability_sum + (16'hFFFF - ml_lane_failure_probability[i]);
                end
            end
            performance_metrics[5].current_value <= (quality_count > 0) ? 
                                                   (reliability_sum / quality_count) : 16'h8000;
            
            // Calculate average congestion
            logic [15:0] congestion_sum = 16'h0;
            logic [7:0] protocol_count = 8'h0;
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                if (protocol_active[i]) begin
                    congestion_sum = congestion_sum + {8'h0, current_congestion[i]};
                    protocol_count = protocol_count + 1;
                end
            end
            performance_metrics[6].current_value <= (protocol_count > 0) ? 
                                                   (congestion_sum / protocol_count) : 16'h4000;
            
            // Update ML predictions
            if (ML_INTEGRATION && (ml_optimization_confidence > {8'h0, ml_confidence_threshold})) begin
                performance_metrics[0].predicted_value <= ml_throughput_prediction[15:0];
                performance_metrics[1].predicted_value <= ml_latency_prediction;
                performance_metrics[0].confidence_level <= ml_model_accuracy;
                performance_metrics[1].confidence_level <= ml_model_accuracy;
                
                // Update lane quality predictions
                for (int i = 0; i < NUM_LANES; i++) begin
                    if (lane_active[i]) begin
                        // Use ML predictions to update expected quality
                        performance_metrics[2].predicted_value <= 
                            (performance_metrics[2].predicted_value + ml_lane_quality_prediction[i]) >> 1;
                    end
                end
            end
            
            // Determine if adaptations are needed
            for (int i = 0; i < 8; i++) begin
                logic [15:0] target = (i < 8) ? performance_targets[i] : performance_metrics[i].target_value;
                logic [15:0] current = performance_metrics[i].current_value;
                logic [15:0] threshold = target >> 3;  // 12.5% threshold
                
                // For metrics where lower is better (latency, power, congestion)
                if (i == 1 || i == 3 || i == 6) begin
                    performance_metrics[i].target_met <= (current <= target);
                    performance_metrics[i].needs_adaptation <= (current > (target + threshold));
                end else begin
                    // For metrics where higher is better
                    performance_metrics[i].target_met <= (current >= target);
                    performance_metrics[i].needs_adaptation <= (current < (target - threshold));
                end
            end
        end
    end
    
    // Adaptation Mode Selection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_mode <= ADAPT_BALANCED;
            adaptation_cycle_counter <= 32'h0;
        end else if (adaptive_control_enable) begin
            current_mode <= next_mode;
            adaptation_cycle_counter <= adaptation_cycle_counter + 1;
        end
    end
    
    // Adaptation Mode Logic
    always_comb begin
        next_mode = current_mode;
        
        // Emergency mode override
        if (emergency_mode || system_thermal_alarm) begin
            next_mode = ADAPT_EMERGENCY;
        end else begin
            // Mode selection based on aggressiveness and system state
            case (adaptation_aggressiveness)
                3'h0, 3'h1: begin  // Conservative
                    if (ML_INTEGRATION && (ml_model_accuracy > 8'hE0)) begin
                        next_mode = ADAPT_PREDICTIVE;
                    end else begin
                        next_mode = ADAPT_CONSERVATIVE;
                    end
                end
                
                3'h2, 3'h3: begin  // Balanced
                    if (learning_state.learning_complete) begin
                        next_mode = ADAPT_BALANCED;
                    end else begin
                        next_mode = ADAPT_LEARNING;
                    end
                end
                
                3'h4, 3'h5: begin  // Aggressive
                    if (thermal_margin < 8'h40) begin
                        next_mode = ADAPT_POWER_SAVE;
                    end else begin
                        next_mode = ADAPT_AGGRESSIVE;
                    end
                end
                
                3'h6, 3'h7: begin  // Maximum performance
                    next_mode = ADAPT_PERFORMANCE;
                end
                
                default: next_mode = ADAPT_BALANCED;
            endcase
        end
    end
    
    // Lane Adaptation Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_LANES; i++) begin
                adaptive_lane_config[i] <= 8'h80;
                adaptive_lane_enable[i] <= 1'b0;
                adaptive_lane_disable[i] <= 1'b0;
                adaptive_power_scale[i] <= 8'hFF;
                adaptive_voltage_scale[i] <= 4'h8;
                adaptive_frequency_scale[i] <= 4'h1;
                
                if (ENHANCED_128G) begin
                    adaptive_equalization[i] <= 4'h8;
                end
            end
            
            lane_adaptation_pending <= '0;
        end else if (adaptive_control_enable && 
                    (adaptation_cycle_counter % ADAPTATION_WINDOW == 0)) begin
            
            // Lane-by-lane adaptation decisions
            for (int i = 0; i < NUM_LANES; i++) begin
                logic should_adapt = 1'b0;
                logic [7:0] new_config = adaptive_lane_config[i];
                logic [7:0] new_power_scale = adaptive_power_scale[i];
                logic [3:0] new_voltage = adaptive_voltage_scale[i];
                logic [3:0] new_frequency = adaptive_frequency_scale[i];
                
                // Determine if lane needs adaptation
                if (ML_INTEGRATION && ml_lane_failure_probability[i] > 16'hC000) begin
                    // High failure probability - disable or reduce power
                    should_adapt = 1'b1;
                    new_config = 8'h40;
                    new_power_scale = 8'h80;
                    adaptive_lane_disable[i] <= 1'b1;
                end else if (lane_active[i] && lane_quality[i] < 8'h40) begin
                    // Poor quality - try to improve
                    should_adapt = 1'b1;
                    new_config = 8'h60;
                    new_power_scale = 8'hC0;
                    new_voltage = 4'h9;
                end else if (lane_active[i] && lane_quality[i] > 8'hE0) begin
                    // Excellent quality - can optimize for power
                    if (current_mode == ADAPT_POWER_SAVE) begin
                        should_adapt = 1'b1;
                        new_power_scale = 8'hA0;
                        new_voltage = 4'h7;
                    end else if (current_mode == ADAPT_PERFORMANCE) begin
                        should_adapt = 1'b1;
                        new_config = 8'hFF;
                        new_power_scale = 8'hFF;
                        new_voltage = 4'hA;
                        adaptive_lane_enable[i] <= 1'b1;
                    end
                end else if (thermal_throttle[i]) begin
                    // Thermal throttling - reduce power immediately
                    should_adapt = 1'b1;
                    new_power_scale = 8'h60;
                    new_voltage = 4'h6;
                    new_frequency = 4'h2;
                end
                
                // Enhanced 128 Gbps adaptations
                if (ENHANCED_128G && should_adapt) begin
                    logic [3:0] new_eq = adaptive_equalization[i];
                    
                    if (lane_quality[i] < 8'h80 && ml_lane_quality_prediction[i] < 16'h8000) begin
                        // Increase equalization for poor quality
                        new_eq = (new_eq < 4'hE) ? new_eq + 1 : 4'hF;
                    end else if (lane_quality[i] > 8'hD0) begin
                        // Can reduce equalization for excellent quality
                        new_eq = (new_eq > 4'h4) ? new_eq - 1 : 4'h4;
                    end
                    
                    adaptive_equalization[i] <= new_eq;
                end
                
                // Apply adaptations
                if (should_adapt) begin
                    adaptive_lane_config[i] <= new_config;
                    adaptive_power_scale[i] <= new_power_scale;
                    adaptive_voltage_scale[i] <= new_voltage;
                    adaptive_frequency_scale[i] <= new_frequency;
                    lane_adaptation_pending[i] <= 1'b1;
                    
                    // Record adaptation
                    if (history_write_ptr < 5'd31) begin
                        adaptation_history_buffer[history_write_ptr] <= '{
                            lane_id: i,
                            adaptation_type: 8'h01,  // Lane configuration
                            old_value: {8'h0, adaptive_lane_config[i]},
                            new_value: {8'h0, new_config},
                            timestamp: global_cycle_counter,
                            confidence_score: ml_model_accuracy,
                            expected_improvement: 16'h1000,
                            actual_improvement: 16'h0,
                            successful: 1'b0,
                            valid: 1'b1
                        };
                    end
                end else begin
                    adaptive_lane_enable[i] <= 1'b0;
                    adaptive_lane_disable[i] <= 1'b0;
                    lane_adaptation_pending[i] <= 1'b0;
                end
            end
        end
    end
    
    // Protocol Adaptation Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                adaptive_protocol_weights[i] <= 8'h80;
                adaptive_protocol_enable[i] <= 1'b1;
                adaptive_flow_control[i] <= 8'h80;
                adaptive_bandwidth_allocation[i] <= 16'h4000;
                adaptive_qos_class[i] <= 4'h4;
                adaptive_latency_targets[i] <= 16'h1000;
                adaptive_bandwidth_guarantee[i] <= 8'h40;
            end
            
            protocol_adaptation_pending <= '0;
        end else if (adaptive_control_enable && 
                    (adaptation_cycle_counter % (ADAPTATION_WINDOW * 2) == 0)) begin
            
            // Protocol-level adaptations
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                if (protocol_active[i]) begin
                    logic should_adapt_protocol = 1'b0;
                    
                    // Congestion-based adaptation
                    if (current_congestion[i] > 8'hC0) begin  // High congestion
                        should_adapt_protocol = 1'b1;
                        adaptive_flow_control[i] <= 8'hFF;  // Maximum flow control
                        adaptive_bandwidth_allocation[i] <= adaptive_bandwidth_allocation[i] >> 1; // Reduce bandwidth
                        adaptive_qos_class[i] <= 4'h2;     // Lower QoS class
                    end else if (current_congestion[i] < 8'h40) begin  // Low congestion
                        should_adapt_protocol = 1'b1;
                        adaptive_flow_control[i] <= 8'h60;  // Relaxed flow control
                        adaptive_bandwidth_allocation[i] <= (adaptive_bandwidth_allocation[i] < 16'hC000) ?
                                                          adaptive_bandwidth_allocation[i] + 16'h1000 : 16'hFFFF;
                        adaptive_qos_class[i] <= (adaptive_qos_class[i] < 4'hE) ? 
                                                adaptive_qos_class[i] + 1 : 4'hF;
                    end
                    
                    // Priority-based adaptation
                    if (protocol_priority[i] > 8'hC0) begin  // High priority protocol
                        adaptive_protocol_weights[i] <= 8'hFF;
                        adaptive_bandwidth_guarantee[i] <= 8'hC0;
                        adaptive_latency_targets[i] <= 16'h800;  // Lower latency target
                    end else if (protocol_priority[i] < 8'h40) begin  // Low priority
                        adaptive_protocol_weights[i] <= 8'h40;
                        adaptive_bandwidth_guarantee[i] <= 8'h20;
                        adaptive_latency_targets[i] <= 16'h2000; // Higher latency acceptable
                    end
                    
                    // ML-driven protocol optimization
                    if (ML_INTEGRATION && ml_congestion_prediction[i] > 8'h80) begin
                        // Predicted congestion - preemptive adaptation
                        should_adapt_protocol = 1'b1;
                        adaptive_flow_control[i] <= 8'hE0;
                        adaptive_qos_class[i] <= 4'h6;
                    end
                    
                    if (should_adapt_protocol) begin
                        protocol_adaptation_pending[i] <= 1'b1;
                    end
                end else begin
                    adaptive_protocol_enable[i] <= 1'b0;
                end
            end
        end
    end
    
    // System-Level Adaptations
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adaptive_data_rate <= 4'h8;
            adaptive_signaling_mode <= SIG_NRZ;
            adaptive_power_gating_enable <= 1'b0;
            adaptive_pam4_optimization <= 8'h80;
            adaptive_parallel_lanes <= 4'h4;
            adaptive_zero_latency_bypass <= 1'b0;
        end else if (adaptive_control_enable && 
                    (adaptation_cycle_counter % (ADAPTATION_WINDOW * 4) == 0)) begin
            
            // Data rate adaptation based on performance and quality
            logic [15:0] avg_quality = performance_metrics[2].current_value;
            logic [15:0] throughput_gap = (performance_metrics[0].current_value < performance_metrics[0].target_value) ?
                                        (performance_metrics[0].target_value - performance_metrics[0].current_value) : 16'h0;
            
            case (current_mode)
                ADAPT_PERFORMANCE: begin
                    if (avg_quality > 16'hE000) begin
                        adaptive_data_rate <= 4'hF;  // 32 GT/s for 128 Gbps
                        if (ENHANCED_128G) begin
                            adaptive_signaling_mode <= SIG_PAM4;
                            adaptive_pam4_optimization <= 8'hFF;
                            adaptive_parallel_lanes <= 4'hF;
                        end
                    end else if (avg_quality > 16'hC000) begin
                        adaptive_data_rate <= 4'hC;  // 24 GT/s
                    end
                end
                
                ADAPT_POWER_SAVE: begin
                    if (thermal_margin < 8'h60) begin
                        adaptive_data_rate <= 4'h4;  // 8 GT/s
                        adaptive_power_gating_enable <= 1'b1;
                        adaptive_signaling_mode <= SIG_NRZ;
                    end else begin
                        adaptive_data_rate <= 4'h8;  // 16 GT/s
                    end
                end
                
                ADAPT_EMERGENCY: begin
                    adaptive_data_rate <= 4'h4;      // Minimum data rate
                    adaptive_power_gating_enable <= 1'b1;
                    adaptive_signaling_mode <= SIG_NRZ;
                    adaptive_parallel_lanes <= 4'h1;
                end
                
                ADAPT_PREDICTIVE: begin
                    if (ML_INTEGRATION && ml_optimization_confidence > 16'hC000) begin
                        // Use ML predictions for optimal settings
                        if (ml_throughput_prediction > current_throughput) begin
                            adaptive_data_rate <= (adaptive_data_rate < 4'hE) ? 
                                                 adaptive_data_rate + 1 : 4'hF;
                        end else if (ml_throughput_prediction < (current_throughput - 32'h10000)) begin
                            adaptive_data_rate <= (adaptive_data_rate > 4'h4) ? 
                                                 adaptive_data_rate - 1 : 4'h4;
                        end
                        
                        if (ENHANCED_128G && avg_quality > 16'hC000) begin
                            adaptive_signaling_mode <= SIG_PAM4;
                            adaptive_pam4_optimization <= 8'hE0;
                        end
                    end
                end
                
                default: begin
                    // Balanced mode
                    if (throughput_gap > 16'h8000) begin  // Large gap
                        adaptive_data_rate <= (adaptive_data_rate < 4'hE) ? 
                                             adaptive_data_rate + 1 : 4'hF;
                    end else if (throughput_gap == 16'h0 && thermal_margin > 8'h80) begin
                        // Can potentially reduce for power savings
                        if (avg_quality > 16'hA000) begin
                            adaptive_data_rate <= (adaptive_data_rate > 4'h6) ? 
                                                 adaptive_data_rate - 1 : 4'h6;
                        end
                    end
                end
            endcase
            
            // Zero-latency bypass adaptation
            if (ENHANCED_128G) begin
                logic [15:0] latency_critical = performance_metrics[1].current_value;
                adaptive_zero_latency_bypass <= (latency_critical < 16'h800) && 
                                              (current_mode == ADAPT_PERFORMANCE);
            end
        end
    end
    
    // Learning and Effectiveness Tracking
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            learning_state <= '0;
            history_write_ptr <= 5'h0;
            total_adaptations_count <= 16'h0;
            ml_prediction_accuracy <= 16'h8000;
        end else if (adaptive_control_enable) begin
            // Update adaptation history pointer
            if (|lane_adaptation_pending || |protocol_adaptation_pending) begin
                history_write_ptr <= (history_write_ptr < 5'd31) ? 
                                   history_write_ptr + 1 : 5'h0;
                total_adaptations_count <= total_adaptations_count + 1;
            end
            
            // Evaluate adaptation effectiveness
            if (adaptation_cycle_counter % (ADAPTATION_WINDOW * 8) == 0) begin
                logic [15:0] success_sum = 16'h0;
                logic [7:0] valid_adaptations = 8'h0;
                logic [15:0] improvement_sum = 16'h0;
                
                // Analyze recent adaptation history
                for (int i = 0; i < 32; i++) begin
                    if (adaptation_history_buffer[i].valid) begin
                        valid_adaptations = valid_adaptations + 1;
                        
                        // Measure actual improvement vs expected
                        logic [15:0] current_perf = performance_metrics[0].current_value;
                        logic [15:0] baseline_perf = baseline_throughput;
                        
                        if (current_perf > baseline_perf) begin
                            adaptation_history_buffer[i].actual_improvement = current_perf - baseline_perf;
                            adaptation_history_buffer[i].successful = 1'b1;
                            success_sum = success_sum + 1;
                            improvement_sum = improvement_sum + adaptation_history_buffer[i].actual_improvement;
                        end
                    end
                end
                
                // Update learning metrics
                if (valid_adaptations > 0) begin
                    learning_state.success_count <= success_sum[7:0];
                    learning_state.failure_count <= valid_adaptations - success_sum[7:0];
                    learning_state.total_adaptations <= {24'h0, valid_adaptations};
                    learning_state.average_improvement <= improvement_sum / valid_adaptations;
                    learning_state.effectiveness_score <= (success_sum * 16'hFFFF) / valid_adaptations;
                    
                    // Check learning convergence
                    logic [7:0] success_rate = (success_sum * 8'd100) / valid_adaptations;
                    learning_state.convergence_indicator <= success_rate;
                    learning_state.learning_complete <= (success_rate > 8'd85) && 
                                                       (valid_adaptations > 8'd20);
                end
                
                // Update baseline for next evaluation
                baseline_throughput <= performance_metrics[0].current_value;
                baseline_latency <= performance_metrics[1].current_value;
            end
            
            // Track ML prediction accuracy
            if (ML_INTEGRATION) begin
                logic [15:0] throughput_error = (ml_throughput_prediction > current_throughput) ?
                                              (ml_throughput_prediction - current_throughput) :
                                              (current_throughput - ml_throughput_prediction);
                logic [15:0] latency_error = (ml_latency_prediction > current_latency) ?
                                           (ml_latency_prediction - current_latency) :
                                           (current_latency - ml_latency_prediction);
                
                // Update prediction accuracy (simplified)
                logic [15:0] total_error = (throughput_error >> 8) + latency_error;
                if (total_error < 16'h1000) begin
                    ml_prediction_accuracy <= (ml_prediction_accuracy < 16'hF000) ?
                                            ml_prediction_accuracy + 16'h100 : 16'hFFFF;
                end else if (total_error > 16'h4000) begin
                    ml_prediction_accuracy <= (ml_prediction_accuracy > 16'h1000) ?
                                            ml_prediction_accuracy - 16'h100 : 16'h1000;
                end
            end
        end
    end
    
    // Global Counters and Status
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_cycle_counter <= 32'h0;
            performance_monitoring_window <= 32'h0;
            pam4_adaptation_score <= 8'h80;
            parallel_lane_optimization <= 4'h8;
            enhanced_performance_metrics <= 16'h8000;
        end else begin
            global_cycle_counter <= global_cycle_counter + 1;
            performance_monitoring_window <= performance_monitoring_window + 1;
            
            if (ENHANCED_128G) begin
                // Update enhanced metrics
                logic [15:0] enhanced_quality = 16'h0;
                logic [7:0] pam4_capable_lanes = 8'h0;
                
                for (int i = 0; i < NUM_LANES; i++) begin
                    if (lane_active[i] && (adaptive_signaling_mode == SIG_PAM4)) begin
                        enhanced_quality = enhanced_quality + {8'h0, lane_quality[i]};
                        pam4_capable_lanes = pam4_capable_lanes + 1;
                    end
                end
                
                if (pam4_capable_lanes > 0) begin
                    enhanced_quality = enhanced_quality / pam4_capable_lanes;
                    pam4_adaptation_score <= enhanced_quality[7:0];
                    parallel_lane_optimization <= pam4_capable_lanes[3:0];
                end
                
                enhanced_performance_metrics <= enhanced_quality;
            end
        end
    end
    
    // Output Assignments
    assign adaptations_performed = total_adaptations_count;
    assign current_adaptation_mode = {5'h0, current_mode};
    assign adaptation_effectiveness = learning_state.effectiveness_score;
    assign adaptation_history = learning_state.total_adaptations;
    
    assign performance_improvement = (performance_metrics[0].current_value > baseline_throughput) ?
                                   (performance_metrics[0].current_value - baseline_throughput) : 16'h0;
    
    assign adaptive_status = {
        adaptive_control_enable,           // [31] Adaptive control enabled
        emergency_mode,                    // [30] Emergency mode active
        learning_state.learning_complete,  // [29] Learning complete
        ML_INTEGRATION[0],                 // [28] ML integration enabled
        current_mode,                      // [27:25] Current adaptation mode
        learning_state.convergence_indicator, // [24:17] Learning convergence
        popcount(lane_adaptation_pending), // [16:9] Pending lane adaptations
        popcount(protocol_adaptation_pending) // [8:1] Pending protocol adaptations
    };
    
    assign debug_adaptation_state = {
        adaptation_aggressiveness,         // [31:29] Aggressiveness level
        5'b0,                             // [28:24] Reserved
        ml_prediction_accuracy[7:0],       // [23:16] ML prediction accuracy
        performance_delta[15:0]            // [15:0] Performance delta
    };

endmodule