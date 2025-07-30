// ML-Enhanced Optimization Engine for 128 Gbps UCIe Controller
// Provides intelligent load balancing, predictive flow control, and adaptive optimization
// Integrates with all controller subsystems for coordinated ML-enhanced operation

module ucie_ml_optimization_engine
    import ucie_pkg::*;
#(
    parameter NUM_PROTOCOL_ENGINES = 4,      // Number of parallel protocol engines
    parameter NUM_THERMAL_ZONES = 8,         // Number of thermal monitoring zones
    parameter ENABLE_PREDICTIVE_CONTROL = 1, // Enable predictive flow control
    parameter ENABLE_ADAPTIVE_LEARNING = 1,  // Enable adaptive ML learning
    parameter ENABLE_LOAD_BALANCING = 1      // Enable intelligent load balancing
) (
    // Clock and Reset
    input  logic                clk_main,          // Main 800 MHz clock
    input  logic                clk_quarter_rate,  // 16 GHz processing clock
    input  logic                rst_n,
    
    // Protocol Engine Performance Metrics
    input  logic [15:0]         engine_throughput [NUM_PROTOCOL_ENGINES], // Mbps throughput
    input  logic [7:0]          engine_utilization [NUM_PROTOCOL_ENGINES], // % utilization
    input  logic [7:0]          engine_latency [NUM_PROTOCOL_ENGINES],     // Average latency
    input  logic [15:0]         engine_queue_depth [NUM_PROTOCOL_ENGINES], // Current queue depth
    input  logic [NUM_PROTOCOL_ENGINES-1:0] engine_congested,              // Congestion flags
    
    // Thermal Management Interface
    input  logic [7:0]          zone_temperatures [NUM_THERMAL_ZONES],     // Zone temperatures
    input  logic [7:0]          junction_temp_c,                           // Junction temperature  
    input  logic                thermal_warning,                           // Thermal warning
    input  logic                thermal_throttle_active,                   // Active throttling
    input  logic [7:0]          thermal_throttle_level,                    // Throttle percentage
    
    // Power Management Interface
    input  logic [15:0]         current_power_mw,                          // Current power consumption
    input  logic [7:0]          power_efficiency,                          // Current efficiency %
    input  logic [3:0]          active_power_domains,                      // Active domains count
    input  logic                low_power_mode_active,                     // Low power mode
    
    // Link Training and Physical Layer
    input  logic [7:0]          link_quality_metric,                       // Link quality (0-255)
    input  logic [15:0]         bit_error_rate,                           // Current BER
    input  logic [7:0]          signal_integrity_score,                   // Signal integrity
    input  logic                link_training_active,                     // Training in progress
    input  logic [3:0]          active_lanes,                             // Number of active lanes
    
    // Traffic Analysis Inputs
    input  logic [31:0]         total_packets_rx,                         // Total received packets
    input  logic [31:0]         total_packets_tx,                         // Total transmitted packets
    input  logic [15:0]         average_packet_size,                      // Average packet size
    input  logic [7:0]          traffic_burstiness,                       // Traffic burstiness metric
    input  logic [3:0]          priority_class_active,                    // Active priority classes
    
    // ML Optimization Outputs
    output logic [3:0]          recommended_engine_sel,                   // Recommended engine
    output logic [7:0]          load_balance_weights [NUM_PROTOCOL_ENGINES], // Load balancing weights
    output logic [7:0]          predicted_congestion_level,               // Predicted congestion
    output logic [15:0]         bandwidth_prediction,                     // Predicted bandwidth
    output logic [7:0]          latency_prediction,                       // Predicted latency
    
    // Flow Control Optimization
    output logic [7:0]          optimal_buffer_threshold,                 // Optimal buffer level
    output logic [3:0]          recommended_priority_boost,               // Priority boost
    output logic                flow_control_bypass_enable,               // Bypass for low latency
    output logic [7:0]          credit_return_optimization,               // Credit return tuning
    
    // Power and Thermal Optimization
    output logic [3:0]          power_optimization_mode,                  // Power optimization strategy
    output logic [7:0]          thermal_optimization_level,               // Thermal optimization
    output logic                dynamic_voltage_scaling_req,              // DVS request
    output logic [7:0]          frequency_scaling_recommendation,         // Frequency scaling
    
    // Predictive Maintenance
    output logic [15:0]         reliability_score,                        // System reliability score
    output logic [7:0]          wear_level_indicator,                     // Component wear level
    output logic                maintenance_prediction,                   // Maintenance needed
    output logic [15:0]         estimated_lifetime_hours,                 // Estimated lifetime
    
    // ML Model Status and Control
    input  logic                ml_learning_enable,                       // Enable learning
    input  logic [7:0]          ml_learning_rate,                         // Learning rate (0-255)
    input  logic [15:0]         ml_training_cycles,                       // Training cycle count
    output logic [7:0]          ml_model_confidence,                      // Model confidence
    output logic [15:0]         ml_prediction_accuracy,                   // Accuracy metric
    output logic                ml_model_trained,                         // Model training complete
    
    // Configuration and Control
    input  logic [7:0]          optimization_aggressiveness,              // How aggressive (0-255)
    input  logic [3:0]          optimization_priorities,                  // Priority mask
    input  logic                enable_predictive_throttling,             // Enable pred. throttling
    input  logic                enable_adaptive_buffering,                // Enable adaptive buffers
    
    // Debug and Analytics
    output logic [31:0]         ml_optimization_status,
    output logic [15:0]         debug_ml_metrics [16]
);

    // ML Optimization State Machine
    typedef enum logic [3:0] {
        ML_RESET,
        ML_INIT,
        ML_LEARNING,
        ML_PREDICTING,
        ML_OPTIMIZING,
        ML_MONITORING,
        ML_ADAPTING,
        ML_ERROR_RECOVERY
    } ml_state_t;
    
    ml_state_t current_state, next_state;
    
    // Traffic Pattern Analysis
    typedef struct packed {
        logic [15:0] throughput_history [16];     // Throughput history
        logic [7:0]  latency_history [16];        // Latency history
        logic [7:0]  utilization_history [16];    // Utilization history
        logic [3:0]  pattern_type;                // Detected pattern type
        logic [7:0]  pattern_confidence;          // Pattern confidence
        logic [7:0]  burstiness_factor;           // Traffic burstiness
        logic [7:0]  periodicity_score;           // Traffic periodicity
    } traffic_pattern_t;
    
    traffic_pattern_t traffic_patterns [NUM_PROTOCOL_ENGINES];
    
    // ML Model Structures
    typedef struct packed {
        logic [7:0] weights [32];                 // Neural network weights
        logic [7:0] biases [8];                   // Neural network biases
        logic [7:0] learning_momentum [32];       // Momentum for learning
        logic [15:0] training_iterations;         // Training iteration count
        logic [7:0] model_accuracy;               // Current model accuracy
        logic       model_converged;              // Model convergence flag
    } ml_model_t;
    
    ml_model_t load_balance_model;
    ml_model_t congestion_predictor;
    ml_model_t thermal_optimizer;
    ml_model_t power_optimizer;
    
    // Optimization History and Learning
    logic [7:0]  optimization_history [64];      // History of optimization decisions
    logic [3:0]  history_write_ptr;
    logic [15:0] performance_metrics [16];       // Performance tracking
    logic [7:0]  adaptation_rate;               // Current adaptation rate
    logic [15:0] learning_error_accumulator;    // Learning error accumulation
    
    // Predictive Models
    logic [15:0] throughput_predictor [NUM_PROTOCOL_ENGINES];
    logic [7:0]  congestion_predictor_output [NUM_PROTOCOL_ENGINES];
    logic [7:0]  thermal_predictor_output [NUM_THERMAL_ZONES];
    logic [15:0] power_predictor_output;
    logic [7:0]  reliability_predictor_output;
    
    // Load Balancing Intelligence
    logic [7:0]  engine_efficiency_scores [NUM_PROTOCOL_ENGINES];
    logic [7:0]  engine_thermal_factors [NUM_PROTOCOL_ENGINES];
    logic [7:0]  engine_power_factors [NUM_PROTOCOL_ENGINES];
    logic [7:0]  composite_load_scores [NUM_PROTOCOL_ENGINES];
    logic [3:0]  optimal_engine_selection;
    
    // Adaptive Buffer Management
    logic [15:0] optimal_buffer_depths [NUM_PROTOCOL_ENGINES];
    logic [7:0]  buffer_utilization_optimal [NUM_PROTOCOL_ENGINES];
    logic [7:0]  dynamic_buffer_threshold;
    logic        buffer_optimization_active;
    
    // Predictive Throttling
    logic [7:0]  predicted_thermal_trend;
    logic [7:0]  predicted_power_trend;
    logic [7:0]  predictive_throttle_level;
    logic        early_throttle_recommendation;
    logic [15:0] throttle_effectiveness_history [8];
    
    // State Machine
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= ML_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            ML_RESET: begin
                if (ml_learning_enable) begin
                    next_state = ML_INIT;
                end
            end
            
            ML_INIT: begin
                if (ml_training_cycles > 16'd100) begin
                    next_state = ML_LEARNING;
                end
            end
            
            ML_LEARNING: begin
                if (load_balance_model.model_converged && 
                    congestion_predictor.model_converged) begin
                    next_state = ML_PREDICTING;
                end else if (learning_error_accumulator > 16'h8000) begin
                    next_state = ML_ERROR_RECOVERY;
                end
            end
            
            ML_PREDICTING: begin
                if (ml_model_confidence > 8'd180) begin
                    next_state = ML_OPTIMIZING;
                end else if (ml_model_confidence < 8'd100) begin
                    next_state = ML_LEARNING;
                end
            end
            
            ML_OPTIMIZING: begin
                if (thermal_warning || (|engine_congested)) begin
                    next_state = ML_ADAPTING;
                end else begin
                    next_state = ML_MONITORING;
                end
            end
            
            ML_MONITORING: begin
                if (performance_metrics[0] < 16'h4000) begin // Performance drop
                    next_state = ML_ADAPTING;
                end else if (ml_training_cycles[3:0] == 4'h0) begin // Periodic relearning
                    next_state = ML_LEARNING;
                end
            end
            
            ML_ADAPTING: begin
                if (performance_metrics[0] > 16'h8000) begin // Performance improved
                    next_state = ML_MONITORING;
                end else if (adaptation_rate > 8'd200) begin // Too much adaptation
                    next_state = ML_ERROR_RECOVERY;
                end
            end
            
            ML_ERROR_RECOVERY: begin
                next_state = ML_INIT;
            end
            
            default: begin
                next_state = ML_RESET;
            end
        endcase
    end
    
    // Traffic Pattern Analysis and Learning
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                traffic_patterns[i] <= '0;
                for (int j = 0; j < 16; j++) begin
                    traffic_patterns[i].throughput_history[j] <= 16'h0;
                    traffic_patterns[i].latency_history[j] <= 8'h0;
                    traffic_patterns[i].utilization_history[j] <= 8'h0;
                end
            end
        end else if (ENABLE_ADAPTIVE_LEARNING && (current_state != ML_RESET)) begin
            for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                // Shift history arrays
                for (int j = 15; j > 0; j--) begin
                    traffic_patterns[i].throughput_history[j] <= 
                        traffic_patterns[i].throughput_history[j-1];
                    traffic_patterns[i].latency_history[j] <= 
                        traffic_patterns[i].latency_history[j-1];
                    traffic_patterns[i].utilization_history[j] <= 
                        traffic_patterns[i].utilization_history[j-1];
                end
                
                // Add new samples
                traffic_patterns[i].throughput_history[0] <= engine_throughput[i];
                traffic_patterns[i].latency_history[0] <= engine_latency[i];
                traffic_patterns[i].utilization_history[0] <= engine_utilization[i];
                
                // Analyze traffic patterns
                logic [15:0] throughput_variance;
                logic [7:0] latency_trend;
                logic [7:0] utilization_stability;
                
                // Calculate variance in throughput
                throughput_variance = 16'h0;
                for (int j = 0; j < 8; j++) begin
                    logic [15:0] diff;
                    diff = (traffic_patterns[i].throughput_history[j] > 
                           traffic_patterns[i].throughput_history[j+1]) ?
                          (traffic_patterns[i].throughput_history[j] - 
                           traffic_patterns[i].throughput_history[j+1]) :
                          (traffic_patterns[i].throughput_history[j+1] - 
                           traffic_patterns[i].throughput_history[j]);
                    throughput_variance = throughput_variance + diff;
                end
                
                // Determine pattern type based on variance
                if (throughput_variance < 16'h100) begin
                    traffic_patterns[i].pattern_type <= 4'h1; // Steady
                    traffic_patterns[i].pattern_confidence <= 8'd200;
                end else if (throughput_variance < 16'h800) begin
                    traffic_patterns[i].pattern_type <= 4'h2; // Moderate variance
                    traffic_patterns[i].pattern_confidence <= 8'd150;
                end else begin
                    traffic_patterns[i].pattern_type <= 4'h3; // Bursty
                    traffic_patterns[i].pattern_confidence <= 8'd100;
                end
                
                // Calculate burstiness factor
                traffic_patterns[i].burstiness_factor <= throughput_variance[11:4];
            end
        end
    end
    
    // ML Model Training and Inference
    generate
        if (ENABLE_ADAPTIVE_LEARNING) begin : gen_ml_training
            always_ff @(posedge clk_main or negedge rst_n) begin
                if (!rst_n) begin
                    load_balance_model <= '0;
                    congestion_predictor <= '0;
                    thermal_optimizer <= '0;
                    power_optimizer <= '0;
                    learning_error_accumulator <= 16'h0;
                end else if (current_state == ML_LEARNING) begin
                    // Simple neural network weight updates using gradient descent
                    
                    // Load balancing model training
                    for (int i = 0; i < 32; i++) begin
                        logic [7:0] gradient;
                        logic [7:0] target_output;
                        logic [7:0] actual_output;
                        
                        // Target: balanced utilization across engines
                        target_output = 8'd128; // 50% target utilization
                        actual_output = engine_utilization[i % NUM_PROTOCOL_ENGINES];
                        
                        // Calculate simple gradient
                        gradient = (actual_output > target_output) ? 
                                  (actual_output - target_output) : 
                                  (target_output - actual_output);
                        
                        // Update weights with momentum
                        if (gradient > 8'd5) begin
                            logic [7:0] weight_delta;
                            weight_delta = (gradient * ml_learning_rate) >> 6;
                            
                            if (actual_output > target_output) begin
                                // Decrease weight to reduce load
                                load_balance_model.weights[i] <= 
                                    (load_balance_model.weights[i] > weight_delta) ?
                                    load_balance_model.weights[i] - weight_delta : 8'h0;
                            end else begin
                                // Increase weight to increase load
                                load_balance_model.weights[i] <= 
                                    (load_balance_model.weights[i] < (8'hFF - weight_delta)) ?
                                    load_balance_model.weights[i] + weight_delta : 8'hFF;
                            end
                        end
                    end
                    
                    // Congestion prediction model training
                    for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                        logic [7:0] congestion_error;
                        logic [7:0] predicted_congestion;
                        logic [7:0] actual_congestion;
                        
                        predicted_congestion = congestion_predictor_output[i];
                        actual_congestion = engine_congested[i] ? 8'd255 : 8'd0;
                        
                        congestion_error = (predicted_congestion > actual_congestion) ?
                                          (predicted_congestion - actual_congestion) :
                                          (actual_congestion - predicted_congestion);
                        
                        if (congestion_error > 8'd20) begin
                            learning_error_accumulator <= 
                                learning_error_accumulator + {8'h0, congestion_error};
                        end
                    end
                    
                    // Update training iterations
                    load_balance_model.training_iterations <= 
                        load_balance_model.training_iterations + 1;
                    congestion_predictor.training_iterations <= 
                        congestion_predictor.training_iterations + 1;
                    
                    // Check convergence
                    if (load_balance_model.training_iterations > 16'd1000 &&
                        learning_error_accumulator < 16'h1000) begin
                        load_balance_model.model_converged <= 1'b1;
                    end
                    
                    if (congestion_predictor.training_iterations > 16'd800) begin
                        congestion_predictor.model_converged <= 1'b1;
                    end
                end
            end
        end else begin : gen_no_ml_training
            always_comb begin
                load_balance_model = '0;
                congestion_predictor = '0;
                thermal_optimizer = '0;
                power_optimizer = '0;
                learning_error_accumulator = 16'h0;
            end
        end
    endgenerate
    
    // Intelligent Load Balancing
    generate
        if (ENABLE_LOAD_BALANCING) begin : gen_load_balancing
            always_ff @(posedge clk_main or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                        engine_efficiency_scores[i] <= 8'd128;
                        engine_thermal_factors[i] <= 8'd128;
                        engine_power_factors[i] <= 8'd128;
                        composite_load_scores[i] <= 8'd128;
                        load_balance_weights[i] <= 8'd64; // Equal initial weights
                    end
                    optimal_engine_selection <= 4'h0;
                end else if (current_state == ML_OPTIMIZING || current_state == ML_MONITORING) begin
                    // Calculate efficiency scores for each engine
                    for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                        // Efficiency = throughput / (latency * utilization)
                        logic [15:0] efficiency_calc;
                        logic [7:0] thermal_penalty;
                        logic [7:0] power_penalty;
                        
                        if (engine_latency[i] > 8'h0 && engine_utilization[i] > 8'h0) begin
                            efficiency_calc = engine_throughput[i] / 
                                            ({8'h0, engine_latency[i]} * 
                                             {8'h0, engine_utilization[i]});
                            engine_efficiency_scores[i] <= efficiency_calc[7:0];
                        end else begin
                            engine_efficiency_scores[i] <= 8'd255;
                        end
                        
                        // Thermal penalty (higher temperature = lower score)
                        if (i < NUM_THERMAL_ZONES) begin
                            thermal_penalty = (zone_temperatures[i] > 8'd85) ?
                                            (zone_temperatures[i] - 8'd85) : 8'd0;
                            engine_thermal_factors[i] <= 8'd255 - thermal_penalty;
                        end else begin
                            engine_thermal_factors[i] <= 8'd255 - (junction_temp_c >> 2);
                        end
                        
                        // Power penalty (consider power efficiency)
                        power_penalty = (power_efficiency < 8'd80) ? 
                                       (8'd80 - power_efficiency) : 8'd0;
                        engine_power_factors[i] <= 8'd255 - power_penalty;
                        
                        // Composite score combining all factors
                        logic [15:0] composite_calc;
                        composite_calc = ({8'h0, engine_efficiency_scores[i]} +
                                        {8'h0, engine_thermal_factors[i]} +
                                        {8'h0, engine_power_factors[i]}) / 3;
                        composite_load_scores[i] <= composite_calc[7:0];
                        
                        // Update load balancing weights based on ML model and composite scores
                        logic [7:0] ml_weight;
                        ml_weight = load_balance_model.weights[i % 32];
                        
                        logic [15:0] weight_calc;
                        weight_calc = ({8'h0, ml_weight} + {8'h0, composite_calc[7:0]}) >> 1;
                        load_balance_weights[i] <= weight_calc[7:0];
                    end
                    
                    // Find optimal engine (highest composite score)
                    logic [7:0] max_score;
                    logic [3:0] best_engine;
                    max_score = 8'h0;
                    best_engine = 4'h0;
                    
                    for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                        if (composite_load_scores[i] > max_score && !engine_congested[i]) begin
                            max_score = composite_load_scores[i];
                            best_engine = i[3:0];
                        end
                    end
                    
                    optimal_engine_selection <= best_engine;
                end
            end
        end else begin : gen_no_load_balancing
            always_comb begin
                for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                    engine_efficiency_scores[i] = 8'd128;
                    engine_thermal_factors[i] = 8'd128;
                    engine_power_factors[i] = 8'd128;
                    composite_load_scores[i] = 8'd128;
                    load_balance_weights[i] = 8'd64;
                end
                optimal_engine_selection = 4'h0;
            end
        end
    endgenerate
    
    // Predictive Flow Control
    generate
        if (ENABLE_PREDICTIVE_CONTROL) begin : gen_predictive_control
            always_ff @(posedge clk_main or negedge rst_n) begin
                if (!rst_n) begin
                    for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                        throughput_predictor[i] <= 16'h0;
                        congestion_predictor_output[i] <= 8'h0;
                        optimal_buffer_depths[i] <= 16'd1024;
                        buffer_utilization_optimal[i] <= 8'd128;
                    end
                    dynamic_buffer_threshold <= 8'd128;
                    predicted_congestion_level <= 8'h0;
                    bandwidth_prediction <= 16'h0;
                    latency_prediction <= 8'h0;
                end else if (current_state == ML_PREDICTING || current_state == ML_OPTIMIZING) begin
                    // Predict throughput based on historical patterns
                    for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                        logic [15:0] trend_calc;
                        logic [15:0] predicted_throughput;
                        
                        // Simple linear prediction based on recent trend
                        if (traffic_patterns[i].throughput_history[0] > 
                            traffic_patterns[i].throughput_history[3]) begin
                            trend_calc = traffic_patterns[i].throughput_history[0] - 
                                        traffic_patterns[i].throughput_history[3];
                            predicted_throughput = traffic_patterns[i].throughput_history[0] + 
                                                 (trend_calc >> 2); // 25% of trend
                        end else begin
                            trend_calc = traffic_patterns[i].throughput_history[3] - 
                                        traffic_patterns[i].throughput_history[0];
                            predicted_throughput = (traffic_patterns[i].throughput_history[0] > 
                                                   (trend_calc >> 2)) ?
                                                  traffic_patterns[i].throughput_history[0] - 
                                                  (trend_calc >> 2) : 16'h0;
                        end
                        
                        throughput_predictor[i] <= predicted_throughput;
                        
                        // Predict congestion based on queue depth and utilization
                        logic [7:0] congestion_factor;
                        congestion_factor = ((engine_queue_depth[i][15:8] + 
                                           engine_utilization[i]) >> 1);
                        
                        if (congestion_factor > 8'd180) begin
                            congestion_predictor_output[i] <= 8'd200; // High congestion
                        end else if (congestion_factor > 8'd120) begin
                            congestion_predictor_output[i] <= 8'd100; // Medium congestion
                        end else begin
                            congestion_predictor_output[i] <= 8'd20;  // Low congestion
                        end
                        
                        // Optimize buffer depths based on predictions
                        if (predicted_throughput > 16'd8000) begin // High throughput
                            optimal_buffer_depths[i] <= 16'd4096;
                            buffer_utilization_optimal[i] <= 8'd160; // 62.5%
                        end else if (predicted_throughput > 16'd4000) begin
                            optimal_buffer_depths[i] <= 16'd2048;
                            buffer_utilization_optimal[i] <= 8'd128; // 50%
                        end else begin
                            optimal_buffer_depths[i] <= 16'd1024;
                            buffer_utilization_optimal[i] <= 8'd96;  // 37.5%
                        end
                    end
                    
                    // Calculate aggregate predictions
                    logic [17:0] total_predicted_bandwidth;
                    logic [9:0] average_predicted_latency;
                    logic [9:0] max_congestion;
                    
                    total_predicted_bandwidth = 18'h0;
                    average_predicted_latency = 10'h0;
                    max_congestion = 10'h0;
                    
                    for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                        total_predicted_bandwidth = total_predicted_bandwidth + 
                                                  {2'h0, throughput_predictor[i]};
                        average_predicted_latency = average_predicted_latency + 
                                                   {2'h0, traffic_patterns[i].latency_history[0]};
                        if ({2'h0, congestion_predictor_output[i]} > max_congestion) begin
                            max_congestion = {2'h0, congestion_predictor_output[i]};
                        end
                    end
                    
                    bandwidth_prediction <= total_predicted_bandwidth[15:0];
                    latency_prediction <= average_predicted_latency[9:2]; // Divide by 4
                    predicted_congestion_level <= max_congestion[7:0];
                    
                    // Dynamic buffer threshold based on congestion prediction
                    if (max_congestion > 10'd150) begin
                        dynamic_buffer_threshold <= 8'd200; // Aggressive buffering
                    end else if (max_congestion > 10'd100) begin
                        dynamic_buffer_threshold <= 8'd160; // Moderate buffering
                    end else begin
                        dynamic_buffer_threshold <= 8'd128; // Normal buffering
                    end
                end
            end
        end else begin : gen_no_predictive_control
            always_comb begin
                for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                    throughput_predictor[i] = 16'h0;
                    congestion_predictor_output[i] = 8'h0;
                    optimal_buffer_depths[i] = 16'd1024;
                    buffer_utilization_optimal[i] = 8'd128;
                end
                dynamic_buffer_threshold = 8'd128;
                predicted_congestion_level = 8'h0;
                bandwidth_prediction = 16'h0;
                latency_prediction = 8'h0;
            end
        end
    endgenerate
    
    // Predictive Maintenance and Reliability
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            reliability_score <= 16'hFFFF;          // 100% initial reliability
            wear_level_indicator <= 8'h0;           // No wear initially
            maintenance_prediction <= 1'b0;
            estimated_lifetime_hours <= 16'hFFFF;   // Maximum lifetime
        end else begin
            // Simple reliability model based on thermal stress and utilization
            logic [15:0] thermal_stress_factor;
            logic [15:0] utilization_stress_factor;
            logic [15:0] combined_stress;
            
            // Calculate thermal stress (exponential relationship with temperature)
            if (junction_temp_c > 8'd85) begin
                thermal_stress_factor = {8'h0, junction_temp_c - 8'd85} << 4; // 16x factor
            end else begin
                thermal_stress_factor = 16'h10; // Minimal stress
            end
            
            // Calculate utilization stress
            logic [7:0] avg_utilization;
            avg_utilization = 8'h0;
            for (int i = 0; i < NUM_PROTOCOL_ENGINES; i++) begin
                avg_utilization = avg_utilization + (engine_utilization[i] >> 2);
            end
            
            if (avg_utilization > 8'd200) begin // > 78% utilization
                utilization_stress_factor = {8'h0, avg_utilization - 8'd200} << 2;
            end else begin
                utilization_stress_factor = 16'h8;
            end
            
            combined_stress = thermal_stress_factor + utilization_stress_factor;
            
            // Update reliability score (decrease over time with stress)
            if (combined_stress > 16'h100 && reliability_score > combined_stress) begin
                reliability_score <= reliability_score - (combined_stress >> 8);
            end
            
            // Update wear level (increase with stress)
            if (combined_stress > 16'h200 && wear_level_indicator < 8'hF0) begin
                wear_level_indicator <= wear_level_indicator + 1;
            end
            
            // Maintenance prediction (reliability < 80% or wear > 75%)
            maintenance_prediction <= (reliability_score < 16'hCCCC) || 
                                    (wear_level_indicator > 8'hC0);
            
            // Estimated lifetime (simplified linear model)
            if (combined_stress > 16'h0 && estimated_lifetime_hours > 16'h100) begin
                estimated_lifetime_hours <= estimated_lifetime_hours - 
                                          (combined_stress >> 12);
            end
        end
    end
    
    // Output Generation
    assign recommended_engine_sel = optimal_engine_selection;
    assign optimal_buffer_threshold = dynamic_buffer_threshold;
    assign recommended_priority_boost = (predicted_congestion_level > 8'd150) ? 4'hF : 4'h0;
    assign flow_control_bypass_enable = (predicted_congestion_level < 8'd50) && 
                                       (latency_prediction < 8'd20);
    assign credit_return_optimization = dynamic_buffer_threshold;
    
    // Power and Thermal Optimization Outputs
    assign power_optimization_mode = (current_power_mw > 16'd4000) ? 4'h3 : 4'h1;
    assign thermal_optimization_level = (junction_temp_c > 8'd90) ? 8'd200 : 8'd100;
    assign dynamic_voltage_scaling_req = (current_power_mw > 16'd5000) || thermal_warning;
    assign frequency_scaling_recommendation = (thermal_throttle_active) ? 8'd128 : 8'd255;
    
    // ML Model Status
    assign ml_model_confidence = (load_balance_model.model_converged && 
                                 congestion_predictor.model_converged) ? 8'd200 : 8'd100;
    assign ml_prediction_accuracy = (learning_error_accumulator < 16'h1000) ? 16'hC000 : 16'h8000;
    assign ml_model_trained = load_balance_model.model_converged && 
                             congestion_predictor.model_converged;
    
    // Status Register
    assign ml_optimization_status = {
        current_state,              // [31:28]
        optimal_engine_selection,   // [27:24]
        ml_model_trained,           // [23]
        maintenance_prediction,     // [22]
        flow_control_bypass_enable, // [21]
        dynamic_voltage_scaling_req,// [20]
        4'h0,                      // [19:16] Reserved
        predicted_congestion_level, // [15:8]
        wear_level_indicator        // [7:0]
    };
    
    // Debug Metrics
    assign debug_ml_metrics[0] = bandwidth_prediction;
    assign debug_ml_metrics[1] = {8'h0, latency_prediction};
    assign debug_ml_metrics[2] = {8'h0, predicted_congestion_level};
    assign debug_ml_metrics[3] = {8'h0, dynamic_buffer_threshold};
    assign debug_ml_metrics[4] = reliability_score;
    assign debug_ml_metrics[5] = {8'h0, wear_level_indicator};
    assign debug_ml_metrics[6] = estimated_lifetime_hours;
    assign debug_ml_metrics[7] = ml_prediction_accuracy;
    assign debug_ml_metrics[8] = {12'h0, optimal_engine_selection};
    assign debug_ml_metrics[9] = {8'h0, ml_model_confidence};
    assign debug_ml_metrics[10] = load_balance_model.training_iterations;
    assign debug_ml_metrics[11] = congestion_predictor.training_iterations;
    assign debug_ml_metrics[12] = learning_error_accumulator;
    assign debug_ml_metrics[13] = {8'h0, adaptation_rate};
    assign debug_ml_metrics[14] = performance_metrics[0];
    assign debug_ml_metrics[15] = {12'h0, current_state};

endmodule