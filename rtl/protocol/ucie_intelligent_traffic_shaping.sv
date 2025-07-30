module ucie_intelligent_traffic_shaping
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter NUM_PROTOCOLS = 4,            // PCIe, CXL.io, CXL.cache, CXL.mem
    parameter NUM_VIRTUAL_CHANNELS = 8,     // Virtual channels per protocol
    parameter FLIT_WIDTH = 256,             // Flit width in bits
    parameter BUFFER_DEPTH = 64,            // Buffer depth per VC
    parameter ENHANCED_128G = 1,            // Enable 128 Gbps optimizations
    parameter RL_LEARNING_DEPTH = 16,       // Reinforcement learning history depth
    parameter TRAFFIC_CLASSES = 16          // QoS traffic classes
) (
    // Clock and Reset
    input  logic                clk_quarter_rate,    // 16 GHz quarter-rate
    input  logic                clk_management,      // 200 MHz management clock
    input  logic                rst_n,
    
    // Configuration
    input  logic                its_global_enable,
    input  logic                rl_enable,
    input  logic [7:0]          bandwidth_target_percent,  // Target bandwidth utilization
    input  logic [15:0]         latency_target_ns,         // Target latency in nanoseconds
    input  logic [1:0]          optimization_policy,       // 00=Latency, 01=Throughput, 10=Balanced, 11=Power
    input  logic [7:0]          fairness_weight,           // Inter-protocol fairness
    
    // Input Traffic Interfaces (per protocol)
    input  logic [FLIT_WIDTH-1:0]    protocol_flit_in [NUM_PROTOCOLS],
    input  ucie_flit_header_t         protocol_header_in [NUM_PROTOCOLS],
    input  logic [NUM_PROTOCOLS-1:0] protocol_valid_in,
    input  logic [2:0]                protocol_priority [NUM_PROTOCOLS],    // 0=lowest, 7=highest
    output logic [NUM_PROTOCOLS-1:0] protocol_ready_out,
    
    // Output Shaped Traffic
    output logic [FLIT_WIDTH-1:0]    shaped_flit_out,
    output ucie_flit_header_t         shaped_header_out,
    output logic                      shaped_valid_out,
    output logic [2:0]                shaped_protocol_id,
    input  logic                      shaped_ready_in,
    
    // Reinforcement Learning Interface
    input  logic [15:0]         rl_reward_signal,          // External reward signal
    input  logic [31:0]         application_context [4],   // Application-specific context
    output logic [15:0]         rl_action_value [NUM_PROTOCOLS],
    output logic [7:0]          rl_learning_progress,
    
    // Traffic Analytics
    output logic [31:0]         protocol_bandwidth_mbps [NUM_PROTOCOLS],
    output logic [15:0]         protocol_latency_ns [NUM_PROTOCOLS],
    output logic [7:0]          protocol_utilization [NUM_PROTOCOLS],
    output logic [15:0]         congestion_score [NUM_PROTOCOLS],
    
    // Quality of Service
    input  logic [3:0]          qos_class [NUM_PROTOCOLS], // QoS class per protocol
    input  logic [15:0]         qos_weight [TRAFFIC_CLASSES],
    output logic [7:0]          qos_satisfaction_score [TRAFFIC_CLASSES],
    output logic [NUM_PROTOCOLS-1:0] qos_violation_alert,
    
    // Advanced Shaping Control
    output logic [7:0]          shaping_rate [NUM_PROTOCOLS],      // Rate limit per protocol
    output logic [15:0]         burst_allowance [NUM_PROTOCOLS],   // Burst capacity
    output logic [7:0]          smoothing_factor [NUM_PROTOCOLS],  // Traffic smoothing
    
    // Machine Learning State
    output logic [31:0]         ml_state_vector [8],       // ML internal state
    output logic [15:0]         prediction_accuracy,       // ML prediction accuracy
    output logic [31:0]         learning_iterations,
    
    // Performance Monitoring
    output logic [31:0]         total_flits_shaped,
    output logic [31:0]         shaping_decisions_made,
    output logic [15:0]         average_shaping_latency_ns,
    output logic [7:0]          bandwidth_efficiency_score,
    
    // Debug and Status
    output logic [31:0]         its_status,
    output logic [15:0]         error_count,
    output logic [7:0]          thermal_throttle_level
);

    // Traffic Shaping State Machine
    typedef enum logic [2:0] {
        SHAPE_IDLE          = 3'b000,
        SHAPE_ANALYZE       = 3'b001,
        SHAPE_CLASSIFY      = 3'b010,
        SHAPE_RL_DECIDE     = 3'b011,
        SHAPE_APPLY         = 3'b100,
        SHAPE_MONITOR       = 3'b101,
        SHAPE_COMPLETE      = 3'b110
    } shaping_state_t;
    
    // Per-Protocol Traffic Buffer
    typedef struct packed {
        logic [FLIT_WIDTH-1:0]  flit_data;
        ucie_flit_header_t      header;
        logic [31:0]            arrival_timestamp;
        logic [2:0]             priority;
        logic [3:0]             qos_class;
        logic [7:0]             estimated_latency;
        logic                   valid;
    } traffic_buffer_entry_t;
    
    // Reinforcement Learning State
    typedef struct packed {
        logic [15:0] q_values [NUM_PROTOCOLS];     // Q-values for protocol selection
        logic [15:0] state_features [8];           // Current state features
        logic [15:0] reward_history [RL_LEARNING_DEPTH];
        logic [7:0]  exploration_rate;             // Epsilon for epsilon-greedy
        logic [31:0] learning_cycles;
        logic [15:0] prediction_errors [NUM_PROTOCOLS];
        logic        converged;
    } rl_state_t;
    
    // Traffic Analytics Structure
    typedef struct packed {
        logic [31:0] packet_count;
        logic [31:0] byte_count;
        logic [31:0] bandwidth_accumulator;
        logic [15:0] latency_accumulator;
        logic [15:0] latency_samples;
        logic [7:0]  utilization_percent;
        logic [15:0] congestion_level;
        logic [31:0] last_measurement_time;
    } traffic_analytics_t;
    
    // QoS Management Structure
    typedef struct packed {
        logic [15:0] allocated_bandwidth;
        logic [15:0] consumed_bandwidth;
        logic [7:0]  satisfaction_level;
        logic [15:0] violations_count;
        logic [31:0] service_time_accumulator;
        logic        sla_violated;
    } qos_state_t;
    
    // Per-Protocol Storage Arrays
    traffic_buffer_entry_t traffic_buffers [NUM_PROTOCOLS][BUFFER_DEPTH];
    logic [5:0] buffer_wr_ptr [NUM_PROTOCOLS];
    logic [5:0] buffer_rd_ptr [NUM_PROTOCOLS];
    logic [5:0] buffer_occupancy [NUM_PROTOCOLS];
    
    // RL and Analytics State
    rl_state_t rl_engine;
    traffic_analytics_t protocol_analytics [NUM_PROTOCOLS];
    qos_state_t qos_management [TRAFFIC_CLASSES];
    
    // State Machine and Control
    shaping_state_t shaping_state;
    logic [2:0] selected_protocol;
    logic [31:0] global_cycle_counter;
    logic [31:0] shaping_cycle_counter;
    
    // Working Variables
    logic [15:0] protocol_scores [NUM_PROTOCOLS];
    logic [7:0] congestion_levels [NUM_PROTOCOLS];
    logic [15:0] predicted_latencies [NUM_PROTOCOLS];
    logic [NUM_PROTOCOLS-1:0] eligible_protocols;
    
    // ML Feature Extraction
    logic [15:0] current_features [8];
    logic [15:0] feature_bandwidth_util;
    logic [15:0] feature_avg_latency;
    logic [15:0] feature_congestion;
    logic [15:0] feature_qos_violations;
    
    // Global Cycle Counter
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            global_cycle_counter <= 32'h0;
        end else begin
            global_cycle_counter <= global_cycle_counter + 1;
        end
    end
    
    // Input Traffic Buffering (per protocol)
    genvar prot_idx;
    generate
        for (prot_idx = 0; prot_idx < NUM_PROTOCOLS; prot_idx++) begin : gen_protocol_buffers
            
            always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
                if (!rst_n) begin
                    buffer_wr_ptr[prot_idx] <= 6'h0;
                    buffer_occupancy[prot_idx] <= 6'h0;
                    protocol_ready_out[prot_idx] <= 1'b0;
                end else if (its_global_enable) begin
                    
                    // Calculate buffer occupancy
                    buffer_occupancy[prot_idx] <= (buffer_wr_ptr[prot_idx] >= buffer_rd_ptr[prot_idx]) ?
                        (buffer_wr_ptr[prot_idx] - buffer_rd_ptr[prot_idx]) :
                        (BUFFER_DEPTH - buffer_rd_ptr[prot_idx] + buffer_wr_ptr[prot_idx]);
                    
                    // Ready when buffer has space
                    protocol_ready_out[prot_idx] <= (buffer_occupancy[prot_idx] < (BUFFER_DEPTH - 2));
                    
                    // Buffer incoming traffic
                    if (protocol_valid_in[prot_idx] && protocol_ready_out[prot_idx]) begin
                        traffic_buffers[prot_idx][buffer_wr_ptr[prot_idx]].flit_data <= protocol_flit_in[prot_idx];
                        traffic_buffers[prot_idx][buffer_wr_ptr[prot_idx]].header <= protocol_header_in[prot_idx];
                        traffic_buffers[prot_idx][buffer_wr_ptr[prot_idx]].arrival_timestamp <= global_cycle_counter;
                        traffic_buffers[prot_idx][buffer_wr_ptr[prot_idx]].priority <= protocol_priority[prot_idx];
                        traffic_buffers[prot_idx][buffer_wr_ptr[prot_idx]].qos_class <= qos_class[prot_idx];
                        traffic_buffers[prot_idx][buffer_wr_ptr[prot_idx]].valid <= 1'b1;
                        
                        buffer_wr_ptr[prot_idx] <= (buffer_wr_ptr[prot_idx] == (BUFFER_DEPTH-1)) ? 
                            6'h0 : buffer_wr_ptr[prot_idx] + 1;
                        
                        // Update analytics
                        protocol_analytics[prot_idx].packet_count <= protocol_analytics[prot_idx].packet_count + 1;
                        protocol_analytics[prot_idx].byte_count <= 
                            protocol_analytics[prot_idx].byte_count + (FLIT_WIDTH / 8);
                    end
                end
            end
        end
    endgenerate
    
    // Main Traffic Shaping State Machine
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            shaping_state <= SHAPE_IDLE;
            selected_protocol <= 3'h0;
            shaped_valid_out <= 1'b0;
            shaping_cycle_counter <= 32'h0;
        end else if (its_global_enable) begin
            
            case (shaping_state)
                SHAPE_IDLE: begin
                    // Check for any buffered traffic
                    logic any_traffic = 1'b0;
                    for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                        if (buffer_occupancy[i] > 0) begin
                            any_traffic = 1'b1;
                        end
                    end
                    
                    if (any_traffic && shaped_ready_in) begin
                        shaping_state <= SHAPE_ANALYZE;
                        shaping_cycle_counter <= shaping_cycle_counter + 1;
                    end
                end
                
                SHAPE_ANALYZE: begin
                    // Analyze current traffic conditions
                    for (int prot = 0; prot < NUM_PROTOCOLS; prot++) begin
                        // Update utilization
                        protocol_analytics[prot].utilization_percent <= 
                            (buffer_occupancy[prot] * 8'd100) / BUFFER_DEPTH[5:0];
                        
                        // Calculate congestion score
                        congestion_levels[prot] <= 
                            (buffer_occupancy[prot] > (BUFFER_DEPTH/2)) ? 8'hFF : 
                            (buffer_occupancy[prot] * 8'd255) / BUFFER_DEPTH[5:0];
                        
                        // Estimate latency based on buffer depth and drain rate
                        predicted_latencies[prot] <= buffer_occupancy[prot] * 16'd4; // Simplified
                        
                        // Mark eligible protocols (have traffic)
                        eligible_protocols[prot] <= (buffer_occupancy[prot] > 0);
                    end
                    
                    shaping_state <= SHAPE_CLASSIFY;
                end
                
                SHAPE_CLASSIFY: begin
                    // Extract ML features for RL decision
                    feature_bandwidth_util <= 16'h0;
                    feature_avg_latency <= 16'h0;
                    feature_congestion <= 16'h0;
                    feature_qos_violations <= 16'h0;
                    
                    for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                        feature_bandwidth_util <= feature_bandwidth_util + 
                            {8'h0, protocol_analytics[i].utilization_percent};
                        feature_avg_latency <= feature_avg_latency + predicted_latencies[i];
                        feature_congestion <= feature_congestion + {8'h0, congestion_levels[i]};
                    end
                    
                    // Average the features
                    current_features[0] <= feature_bandwidth_util >> 2; // /4 protocols
                    current_features[1] <= feature_avg_latency >> 2;
                    current_features[2] <= feature_congestion >> 2;
                    current_features[3] <= feature_qos_violations;
                    current_features[4] <= bandwidth_target_percent << 8;
                    current_features[5] <= latency_target_ns;
                    current_features[6] <= {8'h0, optimization_policy, 6'h0};
                    current_features[7] <= global_cycle_counter[15:0];
                    
                    shaping_state <= SHAPE_RL_DECIDE;
                end
                
                SHAPE_RL_DECIDE: begin
                    if (rl_enable) begin
                        // Reinforcement Learning Decision Making
                        
                        // Calculate Q-values for each protocol using simplified neural network
                        for (int prot = 0; prot < NUM_PROTOCOLS; prot++) begin
                            if (eligible_protocols[prot]) begin
                                
                                // Simplified Q-value calculation (linear combination of features)
                                logic [31:0] q_value_calc = 32'h0;
                                
                                // Weight factors based on optimization policy
                                case (optimization_policy)
                                    2'b00: begin // Latency-optimized
                                        q_value_calc = 32'd1000 - {16'h0, predicted_latencies[prot]};
                                        q_value_calc = q_value_calc + ({16'h0, protocol_priority[prot]} * 32'd200);
                                    end
                                    2'b01: begin // Throughput-optimized
                                        q_value_calc = {16'h0, protocol_analytics[prot].utilization_percent} * 32'd10;
                                        q_value_calc = q_value_calc + (32'd1000 - {24'h0, congestion_levels[prot]});
                                    end
                                    2'b10: begin // Balanced
                                        q_value_calc = 32'd500 - ({16'h0, predicted_latencies[prot]} >> 1);
                                        q_value_calc = q_value_calc + ({24'h0, protocol_analytics[prot].utilization_percent} * 32'd5);
                                        q_value_calc = q_value_calc + ({16'h0, protocol_priority[prot]} * 32'd100);
                                    end
                                    2'b11: begin // Power-optimized
                                        q_value_calc = 32'd800 - ({24'h0, protocol_analytics[prot].utilization_percent} * 32'd3);
                                        q_value_calc = q_value_calc + (32'd200 - {24'h0, congestion_levels[prot]});
                                    end
                                endcase
                                
                                // Add exploration bonus (epsilon-greedy)
                                if (rl_engine.exploration_rate > 8'h0) begin
                                    logic [15:0] random_bonus = global_cycle_counter[15:0] ^ (prot << 8);
                                    q_value_calc = q_value_calc + {16'h0, random_bonus};
                                end
                                
                                rl_engine.q_values[prot] <= q_value_calc[15:0];
                                protocol_scores[prot] <= q_value_calc[15:0];
                            end else begin
                                rl_engine.q_values[prot] <= 16'h0;
                                protocol_scores[prot] <= 16'h0;
                            end
                        end
                        
                        // Select protocol with highest Q-value
                        logic [15:0] max_q_value = 16'h0;
                        logic [2:0] best_protocol = 3'h0;
                        
                        for (int prot = 0; prot < NUM_PROTOCOLS; prot++) begin
                            if (eligible_protocols[prot] && (rl_engine.q_values[prot] > max_q_value)) begin
                                max_q_value = rl_engine.q_values[prot];
                                best_protocol = prot[2:0];
                            end
                        end
                        
                        selected_protocol <= best_protocol;
                        
                        // Update RL state
                        rl_engine.learning_cycles <= rl_engine.learning_cycles + 1;
                        for (int i = 0; i < 8; i++) begin
                            rl_engine.state_features[i] <= current_features[i];
                        end
                        
                        // Decrease exploration rate over time
                        if (rl_engine.exploration_rate > 8'h10 && (rl_engine.learning_cycles[11:0] == 12'hFFF)) begin
                            rl_engine.exploration_rate <= rl_engine.exploration_rate - 1;
                        end
                        
                    end else begin
                        // Simple priority-based scheduling when RL is disabled
                        logic [2:0] highest_priority = 3'h0;
                        logic [2:0] best_protocol = 3'h0;
                        
                        for (int prot = 0; prot < NUM_PROTOCOLS; prot++) begin
                            if (eligible_protocols[prot] && (protocol_priority[prot] > highest_priority)) begin
                                highest_priority = protocol_priority[prot];
                                best_protocol = prot[2:0];
                            end
                        end
                        
                        selected_protocol <= best_protocol;
                    end
                    
                    shaping_state <= SHAPE_APPLY;
                end
                
                SHAPE_APPLY: begin
                    // Apply shaping decision - output selected protocol's traffic
                    if (buffer_occupancy[selected_protocol] > 0) begin
                        logic [5:0] read_ptr = buffer_rd_ptr[selected_protocol];
                        
                        shaped_flit_out <= traffic_buffers[selected_protocol][read_ptr].flit_data;
                        shaped_header_out <= traffic_buffers[selected_protocol][read_ptr].header;
                        shaped_protocol_id <= selected_protocol;
                        shaped_valid_out <= 1'b1;
                        
                        // Update buffer read pointer
                        buffer_rd_ptr[selected_protocol] <= (read_ptr == (BUFFER_DEPTH-1)) ? 
                            6'h0 : read_ptr + 1;
                        
                        // Calculate actual latency for analytics
                        logic [31:0] latency_cycles = global_cycle_counter - 
                            traffic_buffers[selected_protocol][read_ptr].arrival_timestamp;
                        
                        protocol_analytics[selected_protocol].latency_accumulator <= 
                            protocol_analytics[selected_protocol].latency_accumulator + latency_cycles[15:0];
                        protocol_analytics[selected_protocol].latency_samples <= 
                            protocol_analytics[selected_protocol].latency_samples + 1;
                        
                        shaping_state <= SHAPE_MONITOR;
                    end else begin
                        shaped_valid_out <= 1'b0;
                        shaping_state <= SHAPE_IDLE;
                    end
                end
                
                SHAPE_MONITOR: begin
                    if (shaped_ready_in) begin
                        shaped_valid_out <= 1'b0;
                        
                        // Update performance counters
                        if (rl_enable) begin
                            // Calculate reward signal for RL
                            logic signed [15:0] calculated_reward = 16'sd0;
                            
                            case (optimization_policy)
                                2'b00: begin // Latency reward (negative latency)
                                    calculated_reward = 16'sd1000 - $signed(predicted_latencies[selected_protocol]);
                                end
                                2'b01: begin // Throughput reward
                                    calculated_reward = $signed({8'h0, protocol_analytics[selected_protocol].utilization_percent});
                                end
                                2'b10: begin // Balanced reward
                                    calculated_reward = 16'sd500 - ($signed(predicted_latencies[selected_protocol]) >>> 1);
                                    calculated_reward = calculated_reward + 
                                        ($signed({8'h0, protocol_analytics[selected_protocol].utilization_percent}) >>> 1);
                                end
                                2'b11: begin // Power reward (negative utilization)
                                    calculated_reward = 16'sd200 - $signed({8'h0, protocol_analytics[selected_protocol].utilization_percent});
                                end
                            endcase
                            
                            // Add external reward signal
                            calculated_reward = calculated_reward + $signed(rl_reward_signal);
                            
                            // Update reward history
                            for (int i = RL_LEARNING_DEPTH-1; i > 0; i--) begin
                                rl_engine.reward_history[i] <= rl_engine.reward_history[i-1];
                            end
                            rl_engine.reward_history[0] <= calculated_reward;
                            
                            // Simple Q-learning update (simplified)
                            logic signed [15:0] td_error = calculated_reward - $signed(rl_engine.q_values[selected_protocol]);
                            logic signed [15:0] learning_rate = 16'sd128; // 0.5 in fixed point
                            logic signed [31:0] q_update = $signed(rl_engine.q_values[selected_protocol]) + 
                                                          ((td_error * learning_rate) >>> 8);
                            
                            rl_engine.q_values[selected_protocol] <= q_update[15:0];
                            
                            // Track prediction error for accuracy
                            rl_engine.prediction_errors[selected_protocol] <= 
                                (td_error[15]) ? (~td_error + 1) : td_error; // Absolute value
                        end
                        
                        shaping_state <= SHAPE_COMPLETE;
                    end
                end
                
                SHAPE_COMPLETE: begin
                    // Update analytics and QoS metrics
                    logic [3:0] qos_cls = traffic_buffers[selected_protocol][buffer_rd_ptr[selected_protocol]].qos_class;
                    if (qos_cls < TRAFFIC_CLASSES) begin
                        qos_management[qos_cls].consumed_bandwidth <= 
                            qos_management[qos_cls].consumed_bandwidth + (FLIT_WIDTH / 8);
                        
                        // Check QoS satisfaction
                        if (qos_management[qos_cls].consumed_bandwidth > qos_management[qos_cls].allocated_bandwidth) begin
                            qos_management[qos_cls].violations_count <= qos_management[qos_cls].violations_count + 1;
                            qos_management[qos_cls].sla_violated <= 1'b1;
                        end
                    end
                    
                    shaping_state <= SHAPE_IDLE;
                end
            endcase
        end
    end
    
    // Performance Analytics Update
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                protocol_analytics[i] <= '0;
            end
            for (int i = 0; i < TRAFFIC_CLASSES; i++) begin
                qos_management[i] <= '0;
                qos_management[i].allocated_bandwidth <= qos_weight[i];
            end
        end else if (its_global_enable) begin
            
            // Update bandwidth calculations every 1000 cycles
            if (global_cycle_counter[9:0] == 10'h3FF) begin
                for (int prot = 0; prot < NUM_PROTOCOLS; prot++) begin
                    // Calculate bandwidth in Mbps (simplified)
                    protocol_analytics[prot].bandwidth_accumulator <= 
                        protocol_analytics[prot].byte_count * 32'd8; // bits
                    
                    // Reset counters
                    if (global_cycle_counter[19:0] == 20'hFFFFF) begin
                        protocol_analytics[prot].packet_count <= 32'h0;
                        protocol_analytics[prot].byte_count <= 32'h0;
                    end
                end
            end
            
            // Update QoS satisfaction scores
            for (int cls = 0; cls < TRAFFIC_CLASSES; cls++) begin
                if (qos_management[cls].allocated_bandwidth > 0) begin
                    logic [15:0] satisfaction_ratio = 
                        (qos_management[cls].consumed_bandwidth * 16'd100) / qos_management[cls].allocated_bandwidth;
                    
                    if (satisfaction_ratio > 16'd80) begin
                        qos_management[cls].satisfaction_level <= 8'hFF; // High satisfaction
                    end else if (satisfaction_ratio > 16'd50) begin
                        qos_management[cls].satisfaction_level <= 8'hC0; // Medium satisfaction
                    end else begin
                        qos_management[cls].satisfaction_level <= 8'h40; // Low satisfaction
                    end
                end
            end
        end
    end
    
    // Output Assignments
    for (genvar i = 0; i < NUM_PROTOCOLS; i++) begin
        assign protocol_bandwidth_mbps[i] = protocol_analytics[i].bandwidth_accumulator;
        assign protocol_latency_ns[i] = (protocol_analytics[i].latency_samples > 0) ?
            (protocol_analytics[i].latency_accumulator / protocol_analytics[i].latency_samples) : 16'h0;
        assign protocol_utilization[i] = protocol_analytics[i].utilization_percent;
        assign congestion_score[i] = {8'h0, congestion_levels[i]};
        assign rl_action_value[i] = rl_engine.q_values[i];
        assign shaping_rate[i] = (protocol_analytics[i].utilization_percent > 8'd80) ? 8'h80 : 8'hFF;
        assign burst_allowance[i] = {10'h0, buffer_occupancy[i]};
        assign smoothing_factor[i] = (congestion_levels[i] > 8'h80) ? 8'h40 : 8'h80;
    end
    
    for (genvar i = 0; i < TRAFFIC_CLASSES; i++) begin
        assign qos_satisfaction_score[i] = qos_management[i].satisfaction_level;
        assign qos_violation_alert[i] = qos_management[i].sla_violated;
    end
    
    for (genvar i = 0; i < 8; i++) begin
        assign ml_state_vector[i] = {16'h0, rl_engine.state_features[i]};
    end
    
    // Calculate ML prediction accuracy
    logic [31:0] total_prediction_error = 32'h0;
    for (int i = 0; i < NUM_PROTOCOLS; i++) begin
        total_prediction_error = total_prediction_error + rl_engine.prediction_errors[i];
    end
    assign prediction_accuracy = 16'd10000 - ((total_prediction_error[15:0] * 16'd100) / NUM_PROTOCOLS[15:0]);
    
    assign rl_learning_progress = rl_engine.exploration_rate;
    assign learning_iterations = rl_engine.learning_cycles;
    
    assign total_flits_shaped = shaping_cycle_counter;
    assign shaping_decisions_made = shaping_cycle_counter;
    assign average_shaping_latency_ns = 16'd8; // Estimated shaping overhead
    assign bandwidth_efficiency_score = (feature_bandwidth_util > 16'd8000) ? 8'hFF : 
                                       feature_bandwidth_util[15:8];
    
    assign its_status = {
        its_global_enable,              // [31] Global enable
        rl_enable,                      // [30] RL enabled
        optimization_policy,            // [29:28] Optimization policy
        3'(selected_protocol),          // [27:25] Current selected protocol
        5'(popcount(eligible_protocols)), // [24:20] Active protocols
        rl_engine.exploration_rate,     // [19:12] Exploration rate
        bandwidth_target_percent[3:0]   // [11:8] Bandwidth target
    };
    
    assign error_count = {8'h0, congestion_levels[0]};
    assign thermal_throttle_level = (feature_bandwidth_util[15:8] > 8'hC0) ? 8'h80 : 8'h00;

endmodule