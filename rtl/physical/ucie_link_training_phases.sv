// Link Training Phase A/B Controller for 128 Gbps UCIe
// Implements comprehensive multi-phase link training with ML-enhanced optimization
// Supports PAM4 signaling, lane management, and adaptive parameter negotiation

module ucie_link_training_phases
    import ucie_pkg::*;
#(
    parameter NUM_LANES = 16,            // Number of data lanes
    parameter ENABLE_PHASE_AB = 1,       // Enable Phase A/B training
    parameter ENABLE_ML_OPTIMIZATION = 1, // ML-enhanced training
    parameter ENABLE_ADAPTIVE_EQ = 1     // Adaptive equalization during training
) (
    // Clock and Reset
    input  logic                clk_main,          // 800 MHz main clock
    input  logic                clk_symbol_rate,   // 64 GHz symbol rate clock
    input  logic                clk_quarter_rate,  // 16 GHz quarter-rate clock
    input  logic                rst_n,
    
    // Training Control Interface
    input  logic                training_enable,
    input  logic                training_restart,
    input  link_mode_t          target_link_mode,   // Target link configuration
    input  data_rate_t          target_data_rate,   // Target data rate
    input  signaling_mode_t     signaling_mode,     // NRZ/PAM4
    
    // Lane Interface (per lane)
    output logic [NUM_LANES-1:0] lane_tx_enable,
    output logic [NUM_LANES-1:0] lane_rx_enable,
    input  logic [NUM_LANES-1:0] lane_signal_detect,
    input  logic [NUM_LANES-1:0] lane_cdr_lock,
    input  logic [NUM_LANES-1:0] lane_ready,
    
    // Pattern Generation and Detection
    output logic [1:0]          training_pattern [NUM_LANES], // PAM4 training patterns
    output logic [NUM_LANES-1:0] pattern_enable,
    input  logic [NUM_LANES-1:0] pattern_lock,
    input  logic [7:0]          pattern_error_count [NUM_LANES],
    
    // Equalization Control Interface
    output logic                eq_training_enable,
    output logic [7:0]          eq_training_mode,   // Training mode for EQ
    input  logic                eq_adaptation_done,
    input  logic [15:0]         eq_quality_metric,
    
    // Phase A/B Specific Controls
    output logic                phase_a_active,
    output logic                phase_b_active,
    output logic [7:0]          phase_a_duration,   // Phase A duration in ms
    output logic [7:0]          phase_b_duration,   // Phase B duration in ms
    
    // Parameter Negotiation Interface
    output logic [31:0]         local_parameters,   // Parameters to send
    input  logic [31:0]         remote_parameters,  // Parameters received
    output logic                param_valid,
    input  logic                param_ack,
    
    // Lane Management Interface
    output logic [NUM_LANES-1:0] lane_enable_mask,  // Enabled lanes
    output logic [NUM_LANES-1:0] lane_polarity_flip, // Polarity control
    output logic [3:0]          active_lane_count,  // Number of active lanes
    input  logic [NUM_LANES-1:0] lane_fault_status, // Lane fault indicators
    
    // ML-Enhanced Training Interface
    input  logic                ml_enable,
    input  logic [7:0]          ml_parameters [8],
    output logic [7:0]          ml_training_metrics [6],
    input  logic [15:0]         ml_optimization_target,
    
    // Performance Monitoring
    output logic [31:0]         training_time_us,   // Total training time
    output logic [15:0]         training_iterations,
    output logic [7:0]          training_quality,   // 0-255 quality score
    output logic [15:0]         bit_error_rate,     // BER during training
    
    // Status and Control
    output logic                training_complete,
    output logic                training_failed,
    output logic [7:0]          failure_reason,
    output logic [31:0]         training_status,
    output logic [15:0]         debug_training_metrics [8]
);

    // Use training_state_t from ucie_pkg
    // Local phase-specific state machine
    typedef enum logic [4:0] {
        PHASE_RESET,
        PHASE_INIT,
        PHASE_A_START,
        PHASE_A_PATTERN,
        PHASE_A_LOCK,
        PHASE_A_EQ,
        PHASE_A_VERIFY,
        PHASE_B_START,
        PHASE_B_PATTERN,
        PHASE_B_LOCK,
        PHASE_B_EQ,
        PHASE_B_VERIFY,
        PHASE_PARAM_EXCHANGE,
        PHASE_FINAL_VERIFY,
        PHASE_COMPLETE,
        PHASE_FAILED,
        PHASE_ERROR_RECOVERY
    } phase_state_t;
    
    phase_state_t current_phase, next_phase;
    training_state_t current_training_state, next_training_state;
    
    // Phase A/B Training Patterns
    typedef enum logic [3:0] {
        PATTERN_PRBS7,
        PATTERN_PRBS15,
        PATTERN_PRBS23,
        PATTERN_PRBS31,
        PATTERN_CLOCK,
        PATTERN_SQUARE_WAVE,
        PATTERN_PAM4_LEVELS,
        PATTERN_JITTER_TEST,
        PATTERN_CUSTOM
    } training_pattern_t;
    
    training_pattern_t current_pattern_type;
    logic [1:0] pattern_data [9]; // Pre-computed pattern data
    
    // Training Phase Control
    logic [31:0] phase_timer;              // Current phase timer
    logic [15:0] phase_a_cycles;           // Phase A duration in cycles
    logic [15:0] phase_b_cycles;           // Phase B duration in cycles
    logic [7:0]  training_retry_count;     // Number of training retries
    logic [7:0]  max_training_retries;     // Maximum allowed retries
    
    // Lane Status Tracking
    logic [NUM_LANES-1:0] lane_phase_a_complete;
    logic [NUM_LANES-1:0] lane_phase_b_complete;
    logic [NUM_LANES-1:0] lane_training_active;
    logic [NUM_LANES-1:0] lane_equalization_done;
    logic [7:0] lane_quality_score [NUM_LANES];
    
    // Pattern Generation and Management
    logic [31:0] prbs7_state [NUM_LANES];
    logic [31:0] prbs15_state [NUM_LANES];
    logic [31:0] prbs23_state [NUM_LANES];
    logic [31:0] prbs31_state [NUM_LANES];
    logic [7:0]  pattern_cycle_counter;
    
    // Equalization Integration
    logic        eq_phase_a_enable;
    logic        eq_phase_b_enable;
    logic [7:0]  eq_adaptation_timeout;
    logic [15:0] eq_quality_threshold;
    logic [15:0] current_eq_quality [NUM_LANES];
    
    // ML-Enhanced Training Optimization
    logic [7:0]  ml_phase_predictor;
    logic [7:0]  ml_pattern_optimizer;
    logic [7:0]  ml_timing_optimizer;
    logic [7:0]  ml_quality_predictor;
    logic [15:0] ml_training_efficiency;
    logic [7:0]  ml_adaptation_rate;
    
    // Performance Monitoring
    logic [31:0] training_start_time;
    logic [31:0] phase_a_time;
    logic [31:0] phase_b_time;
    logic [15:0] total_iterations;
    logic [15:0] error_accumulator;
    logic [7:0]  overall_quality;
    
    // Parameter Negotiation
    typedef struct packed {
        logic [3:0] supported_data_rates;  // Bitmask of supported rates
        logic [1:0] preferred_signaling;   // NRZ/PAM4 preference
        logic [3:0] max_lane_count;        // Maximum supported lanes
        logic [7:0] eq_capabilities;       // Equalization capabilities
        logic [7:0] training_options;      // Training mode options
        logic [7:0] reserved;              // Reserved for future use
    } parameter_struct_t;
    
    parameter_struct_t local_param_struct, remote_param_struct;
    logic parameter_negotiation_complete;
    logic parameter_mismatch;
    
    // Main State Machine
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= LT_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            LT_RESET: begin
                if (training_enable) begin
                    next_state = LT_INIT;
                end
            end
            
            LT_INIT: begin
                if (training_restart) begin
                    next_state = LT_RESET;
                end else if (ENABLE_PHASE_AB) begin
                    next_state = LT_PHASE_A_START;
                end else begin
                    next_state = LT_PARAMETER_EXCHANGE; // Skip phases if disabled
                end
            end
            
            LT_PHASE_A_START: begin
                next_state = LT_PHASE_A_PATTERN;
            end
            
            LT_PHASE_A_PATTERN: begin
                if (phase_timer > {16'h0, phase_a_cycles}) begin
                    next_state = LT_PHASE_A_LOCK;
                end else if (training_retry_count > max_training_retries) begin
                    next_state = LT_TRAINING_FAILED;
                end
            end
            
            LT_PHASE_A_LOCK: begin
                if (&pattern_lock) begin // All lanes locked
                    next_state = LT_PHASE_A_EQ;
                end else if (phase_timer > {16'h0, phase_a_cycles} + 32'd10000) begin
                    next_state = LT_ERROR_RECOVERY;
                end
            end
            
            LT_PHASE_A_EQ: begin
                if (ENABLE_ADAPTIVE_EQ) begin
                    if (eq_adaptation_done) begin
                        next_state = LT_PHASE_A_VERIFY;
                    end else if (phase_timer > 32'd50000) begin // EQ timeout
                        next_state = LT_ERROR_RECOVERY;
                    end
                end else begin
                    next_state = LT_PHASE_A_VERIFY;
                end
            end
            
            LT_PHASE_A_VERIFY: begin
                if (&lane_phase_a_complete) begin
                    next_state = LT_PHASE_B_START;
                end else if (phase_timer > 32'd100000) begin
                    next_state = LT_ERROR_RECOVERY;
                end
            end
            
            LT_PHASE_B_START: begin
                next_state = LT_PHASE_B_PATTERN;
            end
            
            LT_PHASE_B_PATTERN: begin
                if (phase_timer > {16'h0, phase_b_cycles}) begin
                    next_state = LT_PHASE_B_LOCK;
                end else if (training_retry_count > max_training_retries) begin
                    next_state = LT_TRAINING_FAILED;
                end
            end
            
            LT_PHASE_B_LOCK: begin
                if (&pattern_lock) begin
                    next_state = LT_PHASE_B_EQ;
                end else if (phase_timer > {16'h0, phase_b_cycles} + 32'd10000) begin
                    next_state = LT_ERROR_RECOVERY;
                end
            end
            
            LT_PHASE_B_EQ: begin
                if (ENABLE_ADAPTIVE_EQ) begin
                    if (eq_adaptation_done) begin
                        next_state = LT_PHASE_B_VERIFY;
                    end else if (phase_timer > 32'd50000) begin
                        next_state = LT_ERROR_RECOVERY;
                    end
                end else begin
                    next_state = LT_PHASE_B_VERIFY;
                end
            end
            
            LT_PHASE_B_VERIFY: begin
                if (&lane_phase_b_complete) begin
                    next_state = LT_PARAMETER_EXCHANGE;
                end else if (phase_timer > 32'd100000) begin
                    next_state = LT_ERROR_RECOVERY;
                end
            end
            
            LT_PARAMETER_EXCHANGE: begin
                if (parameter_negotiation_complete && !parameter_mismatch) begin
                    next_state = LT_FINAL_VERIFICATION;
                end else if (parameter_mismatch) begin
                    next_state = LT_TRAINING_FAILED;
                end else if (phase_timer > 32'd200000) begin // Parameter timeout
                    next_state = LT_ERROR_RECOVERY;
                end
            end
            
            LT_FINAL_VERIFICATION: begin
                if (overall_quality > 8'd200 && bit_error_rate < 16'd100) begin
                    next_state = LT_TRAINING_COMPLETE;
                end else if (phase_timer > 32'd50000) begin
                    next_state = LT_ERROR_RECOVERY;
                end
            end
            
            LT_TRAINING_COMPLETE: begin
                if (training_restart) begin
                    next_state = LT_RESET;
                end
                // Stay in complete state
            end
            
            LT_TRAINING_FAILED: begin
                if (training_restart) begin
                    next_state = LT_RESET;
                end
                // Stay in failed state until restart
            end
            
            LT_ERROR_RECOVERY: begin
                if (training_retry_count < max_training_retries) begin
                    next_state = LT_INIT; // Retry training
                end else begin
                    next_state = LT_TRAINING_FAILED;
                end
            end
            
            default: begin
                next_state = LT_RESET;
            end
        endcase
    end
    
    // Phase Timer and Control
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            phase_timer <= 32'h0;
            phase_a_cycles <= 16'd5000;    // 5ms default Phase A
            phase_b_cycles <= 16'd10000;   // 10ms default Phase B
            training_retry_count <= 8'h0;
            max_training_retries <= 8'd3;
            training_start_time <= 32'h0;
            phase_a_time <= 32'h0;
            phase_b_time <= 32'h0;
        end else begin
            case (current_state)
                LT_RESET, LT_INIT: begin
                    phase_timer <= 32'h0;
                    training_retry_count <= 8'h0;
                    training_start_time <= phase_timer;
                end
                
                LT_PHASE_A_START: begin
                    phase_timer <= 32'h0;
                    // Adjust Phase A duration based on data rate
                    case (target_data_rate)
                        DATA_RATE_128G: phase_a_cycles <= 16'd8000;  // Longer for high speed
                        DATA_RATE_64G:  phase_a_cycles <= 16'd6000;
                        DATA_RATE_32G:  phase_a_cycles <= 16'd4000;
                        default:        phase_a_cycles <= 16'd5000;
                    endcase
                end
                
                LT_PHASE_B_START: begin
                    phase_a_time <= phase_timer;
                    phase_timer <= 32'h0;
                    // Adjust Phase B duration based on signaling mode
                    if (signaling_mode == SIGNALING_PAM4) begin
                        phase_b_cycles <= 16'd15000; // Longer for PAM4
                    end else begin
                        phase_b_cycles <= 16'd10000;
                    end
                end
                
                LT_PARAMETER_EXCHANGE: begin
                    phase_b_time <= phase_timer;
                    phase_timer <= 32'h0;
                end
                
                LT_ERROR_RECOVERY: begin
                    training_retry_count <= training_retry_count + 1;
                    phase_timer <= 32'h0;
                end
                
                default: begin
                    if (phase_timer < 32'hFFFFFFF0) begin
                        phase_timer <= phase_timer + 1;
                    end
                end
            endcase
        end
    end
    
    // Training Pattern Generation
    always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_LANES; i++) begin
                prbs7_state[i] <= 32'h1;
                prbs15_state[i] <= 32'h1;
                prbs23_state[i] <= 32'h1;
                prbs31_state[i] <= 32'h1;
                training_pattern[i] <= 2'b00;
            end
            pattern_cycle_counter <= 8'h0;
            current_pattern_type <= PATTERN_PRBS7;
        end else if (pattern_enable != '0) begin
            pattern_cycle_counter <= pattern_cycle_counter + 1;
            
            // Select pattern type based on training phase
            case (current_state)
                LT_PHASE_A_PATTERN, LT_PHASE_A_LOCK: begin
                    current_pattern_type <= PATTERN_PRBS7;  // Simple pattern for Phase A
                end
                LT_PHASE_B_PATTERN, LT_PHASE_B_LOCK: begin
                    if (signaling_mode == SIGNALING_PAM4) begin
                        current_pattern_type <= PATTERN_PAM4_LEVELS; // PAM4 specific
                    end else begin
                        current_pattern_type <= PATTERN_PRBS15;
                    end
                end
                default: begin
                    current_pattern_type <= PATTERN_PRBS7;
                end
            endcase
            
            // Generate patterns for each lane
            for (int i = 0; i < NUM_LANES; i++) begin
                if (pattern_enable[i]) begin
                    case (current_pattern_type)
                        PATTERN_PRBS7: begin
                            // PRBS7: x^7 + x^6 + 1
                            logic new_bit;
                            new_bit = prbs7_state[i][6] ^ prbs7_state[i][5];
                            prbs7_state[i] <= {prbs7_state[i][30:0], new_bit};
                            training_pattern[i] <= {prbs7_state[i][1], prbs7_state[i][0]};
                        end
                        
                        PATTERN_PRBS15: begin
                            // PRBS15: x^15 + x^14 + 1
                            logic new_bit;
                            new_bit = prbs15_state[i][14] ^ prbs15_state[i][13];
                            prbs15_state[i] <= {prbs15_state[i][30:0], new_bit};
                            training_pattern[i] <= {prbs15_state[i][1], prbs15_state[i][0]};
                        end
                        
                        PATTERN_PAM4_LEVELS: begin
                            // Cycle through PAM4 levels: 00, 01, 10, 11
                            case (pattern_cycle_counter[1:0])
                                2'b00: training_pattern[i] <= 2'b00; // -3 level
                                2'b01: training_pattern[i] <= 2'b01; // -1 level
                                2'b10: training_pattern[i] <= 2'b10; // +1 level
                                2'b11: training_pattern[i] <= 2'b11; // +3 level
                            endcase
                        end
                        
                        PATTERN_CLOCK: begin
                            // Simple clock pattern
                            training_pattern[i] <= {pattern_cycle_counter[0], ~pattern_cycle_counter[0]};
                        end
                        
                        PATTERN_SQUARE_WAVE: begin
                            // Square wave pattern
                            training_pattern[i] <= {pattern_cycle_counter[2], pattern_cycle_counter[2]};
                        end
                        
                        default: begin
                            training_pattern[i] <= 2'b00;
                        end
                    endcase
                end
            end
        end
    end
    
    // Lane Status Management
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            lane_phase_a_complete <= '0;
            lane_phase_b_complete <= '0;
            lane_training_active <= '0;
            lane_equalization_done <= '0;
            for (int i = 0; i < NUM_LANES; i++) begin
                lane_quality_score[i] <= 8'h0;
                current_eq_quality[i] <= 16'h0;
            end
        end else begin
            case (current_state)
                LT_RESET, LT_INIT: begin
                    lane_phase_a_complete <= '0;
                    lane_phase_b_complete <= '0;
                    lane_training_active <= '0;
                    lane_equalization_done <= '0;
                end
                
                LT_PHASE_A_START: begin
                    lane_training_active <= lane_enable_mask;
                end
                
                LT_PHASE_A_VERIFY: begin
                    // Check Phase A completion criteria for each lane
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (lane_enable_mask[i] && pattern_lock[i] && 
                            pattern_error_count[i] < 8'd10) begin
                            lane_phase_a_complete[i] <= 1'b1;
                            lane_quality_score[i] <= 8'd200 - pattern_error_count[i];
                        end
                    end
                end
                
                LT_PHASE_B_VERIFY: begin
                    // Check Phase B completion criteria for each lane
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (lane_enable_mask[i] && pattern_lock[i] && 
                            pattern_error_count[i] < 8'd5 && lane_phase_a_complete[i]) begin
                            lane_phase_b_complete[i] <= 1'b1;
                            lane_quality_score[i] <= lane_quality_score[i] + 8'd50 - pattern_error_count[i];
                        end
                    end
                end
                
                default: begin
                    // Update lane quality based on error counts
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (pattern_error_count[i] > 8'd50) begin
                            if (lane_quality_score[i] > 8'd10) begin
                                lane_quality_score[i] <= lane_quality_score[i] - 8'd10;
                            end
                        end
                    end
                end
            endcase
        end
    end
    
    // Equalization Control Integration
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            eq_phase_a_enable <= 1'b0;
            eq_phase_b_enable <= 1'b0;
            eq_adaptation_timeout <= 8'd100;
            eq_quality_threshold <= 16'd8000;
        end else begin
            case (current_state)
                LT_PHASE_A_EQ: begin
                    eq_phase_a_enable <= ENABLE_ADAPTIVE_EQ;
                    eq_phase_b_enable <= 1'b0;
                end
                
                LT_PHASE_B_EQ: begin
                    eq_phase_a_enable <= 1'b0;
                    eq_phase_b_enable <= ENABLE_ADAPTIVE_EQ;
                end
                
                default: begin
                    eq_phase_a_enable <= 1'b0;
                    eq_phase_b_enable <= 1'b0;
                end
            endcase
            
            // Update EQ quality metrics
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_enable_mask[i]) begin
                    current_eq_quality[i] <= eq_quality_metric;
                end
            end
        end
    end
    
    // Parameter Negotiation Logic
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            local_param_struct <= '0;
            remote_param_struct <= '0;
            parameter_negotiation_complete <= 1'b0;
            parameter_mismatch <= 1'b0;
        end else begin
            case (current_state)
                LT_INIT: begin
                    // Set up local parameters
                    local_param_struct.supported_data_rates <= 4'b1111; // All rates
                    local_param_struct.preferred_signaling <= 2'(signaling_mode);
                    local_param_struct.max_lane_count <= 4'(NUM_LANES);
                    local_param_struct.eq_capabilities <= 8'hFF; // All EQ modes
                    local_param_struct.training_options <= 8'h0F; // Phase A/B support
                    parameter_negotiation_complete <= 1'b0;
                    parameter_mismatch <= 1'b0;
                end
                
                LT_PARAMETER_EXCHANGE: begin
                    if (param_ack) begin
                        remote_param_struct <= remote_parameters;
                        
                        // Check for compatibility
                        logic data_rate_compatible;
                        logic signaling_compatible;
                        logic lane_count_compatible;
                        
                        data_rate_compatible = |(local_param_struct.supported_data_rates & 
                                               remote_param_struct.supported_data_rates);
                        signaling_compatible = (local_param_struct.preferred_signaling == 
                                              remote_param_struct.preferred_signaling);
                        lane_count_compatible = (remote_param_struct.max_lane_count >= 4'd8);
                        
                        if (data_rate_compatible && signaling_compatible && lane_count_compatible) begin
                            parameter_negotiation_complete <= 1'b1;
                            parameter_mismatch <= 1'b0;
                        end else begin
                            parameter_negotiation_complete <= 1'b0;
                            parameter_mismatch <= 1'b1;
                        end
                    end
                end
                
                default: begin
                    // Maintain current state
                end
            endcase
        end
    end
    
    // ML-Enhanced Training Optimization
    generate
        if (ENABLE_ML_OPTIMIZATION) begin : gen_ml_training
            always_ff @(posedge clk_main or negedge rst_n) begin
                if (!rst_n) begin
                    ml_phase_predictor <= 8'h80;       // 50% baseline
                    ml_pattern_optimizer <= 8'h80;
                    ml_timing_optimizer <= 8'h80;
                    ml_quality_predictor <= 8'h80;
                    ml_training_efficiency <= 16'h8000;
                    ml_adaptation_rate <= 8'd4;
                end else if (ml_enable) begin
                    // ML-based phase duration optimization
                    if (current_state == LT_PHASE_A_VERIFY) begin
                        if (&lane_phase_a_complete && phase_timer < {16'h0, phase_a_cycles}) begin
                            // Phase A completed early - reduce future duration
                            ml_phase_predictor <= ml_phase_predictor > 8'd10 ? 
                                                 ml_phase_predictor - 8'd5 : 8'd10;
                        end else if (!(&lane_phase_a_complete) && phase_timer >= {16'h0, phase_a_cycles}) begin
                            // Phase A took too long - increase future duration
                            ml_phase_predictor <= ml_phase_predictor < 8'd240 ? 
                                                 ml_phase_predictor + 8'd10 : 8'd240;
                        end
                    end
                    
                    // ML-based pattern optimization
                    logic [7:0] avg_error_count;
                    avg_error_count = 8'h0;
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (lane_enable_mask[i]) begin
                            avg_error_count = avg_error_count + pattern_error_count[i];
                        end
                    end
                    avg_error_count = avg_error_count >> 2; // Divide by 4 (approximate)
                    
                    if (avg_error_count < 8'd5) begin
                        // Good pattern performance
                        ml_pattern_optimizer <= ml_pattern_optimizer < 8'd250 ? 
                                               ml_pattern_optimizer + 8'd2 : 8'd250;
                    end else if (avg_error_count > 8'd20) begin
                        // Poor pattern performance
                        ml_pattern_optimizer <= ml_pattern_optimizer > 8'd20 ? 
                                               ml_pattern_optimizer - 8'd5 : 8'd20;
                    end
                    
                    // ML-based timing optimization
                    logic [7:0] timing_score;
                    timing_score = (phase_timer[15:8] < 8'd100) ? 
                                  (8'd100 - phase_timer[15:8]) : 8'd0;
                    
                    if (timing_score > ml_timing_optimizer) begin
                        ml_timing_optimizer <= ml_timing_optimizer + ml_adaptation_rate;
                    end else if (ml_timing_optimizer > timing_score) begin
                        ml_timing_optimizer <= ml_timing_optimizer - ml_adaptation_rate;
                    end
                    
                    // ML-based quality prediction
                    logic [7:0] avg_quality;
                    avg_quality = (lane_quality_score[0] + lane_quality_score[1] + 
                                  lane_quality_score[2] + lane_quality_score[3]) >> 2;
                    
                    ml_quality_predictor <= avg_quality;
                    
                    // Update training efficiency
                    if (current_state == LT_TRAINING_COMPLETE) begin
                        logic [15:0] efficiency_metric;
                        efficiency_metric = (16'd10000 * overall_quality) / 
                                          (training_time_us[15:0] + 1);
                        ml_training_efficiency <= efficiency_metric;
                    end
                end
            end
        end else begin : gen_no_ml_training
            assign ml_phase_predictor = 8'h80;
            assign ml_pattern_optimizer = 8'h80;
            assign ml_timing_optimizer = 8'h80;
            assign ml_quality_predictor = 8'h80;
            assign ml_training_efficiency = 16'h8000;
        end
    endgenerate
    
    // Performance Monitoring and Quality Assessment
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            total_iterations <= 16'h0;
            error_accumulator <= 16'h0;
            overall_quality <= 8'h0;
        end else begin
            case (current_state)
                LT_RESET, LT_INIT: begin
                    total_iterations <= 16'h0;
                    error_accumulator <= 16'h0;
                    overall_quality <= 8'h0;
                end
                
                LT_PHASE_A_PATTERN, LT_PHASE_B_PATTERN: begin
                    if (total_iterations < 16'hFFFF) begin
                        total_iterations <= total_iterations + 1;
                    end
                end
                
                LT_FINAL_VERIFICATION, LT_TRAINING_COMPLETE: begin
                    // Calculate overall quality
                    logic [11:0] quality_sum;
                    logic [3:0] active_lanes;
                    
                    quality_sum = 12'h0;
                    active_lanes = 4'h0;
                    
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (lane_enable_mask[i]) begin
                            quality_sum = quality_sum + {4'h0, lane_quality_score[i]};
                            active_lanes = active_lanes + 1;
                        end
                    end
                    
                    if (active_lanes > 0) begin
                        overall_quality <= quality_sum / {8'h0, active_lanes};
                    end
                end
                
                default: begin
                    // Accumulate errors during training
                    logic [15:0] current_errors;
                    current_errors = 16'h0;
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (lane_enable_mask[i]) begin
                            current_errors = current_errors + {8'h0, pattern_error_count[i]};
                        end
                    end
                    
                    if (error_accumulator < (16'hFFFF - current_errors)) begin
                        error_accumulator <= error_accumulator + current_errors;
                    end
                end
            endcase
        end
    end
    
    // Output Logic
    always_comb begin
        // Lane control outputs
        lane_tx_enable = lane_enable_mask & {NUM_LANES{training_enable}};
        lane_rx_enable = lane_enable_mask & {NUM_LANES{training_enable}};
        
        // Pattern control
        pattern_enable = '0;
        case (current_state)
            LT_PHASE_A_PATTERN, LT_PHASE_A_LOCK, LT_PHASE_A_EQ: begin
                pattern_enable = lane_enable_mask;
            end
            LT_PHASE_B_PATTERN, LT_PHASE_B_LOCK, LT_PHASE_B_EQ: begin
                pattern_enable = lane_enable_mask;
            end
            default: begin
                pattern_enable = '0;
            end
        endcase
        
        // Equalization control
        eq_training_enable = eq_phase_a_enable || eq_phase_b_enable;
        eq_training_mode = {4'h0, eq_phase_b_enable, eq_phase_a_enable, 2'b00};
        
        // Phase status
        phase_a_active = (current_state >= LT_PHASE_A_START) && 
                        (current_state <= LT_PHASE_A_VERIFY);
        phase_b_active = (current_state >= LT_PHASE_B_START) && 
                        (current_state <= LT_PHASE_B_VERIFY);
        
        // Lane management
        lane_enable_mask = {NUM_LANES{1'b1}}; // Enable all lanes for now
        lane_polarity_flip = '0; // No polarity flipping
        active_lane_count = NUM_LANES[3:0];
        
        // Parameter negotiation
        local_parameters = local_param_struct;
        param_valid = (current_state == LT_PARAMETER_EXCHANGE);
        
        // Status outputs
        training_complete = (current_state == LT_TRAINING_COMPLETE);
        training_failed = (current_state == LT_TRAINING_FAILED);
        
        // Failure reason encoding
        case (current_state)
            LT_TRAINING_FAILED: begin
                if (parameter_mismatch) begin
                    failure_reason = 8'h01; // Parameter mismatch
                end else if (training_retry_count > max_training_retries) begin
                    failure_reason = 8'h02; // Too many retries
                end else if (!(&pattern_lock)) begin
                    failure_reason = 8'h03; // Pattern lock failure
                end else if (!eq_adaptation_done) begin
                    failure_reason = 8'h04; // Equalization failure
                end else begin
                    failure_reason = 8'hFF; // Unknown failure
                end
            end
            default: begin
                failure_reason = 8'h00; // No failure
            end
        endcase
    end
    
    // Output Assignments
    assign phase_a_duration = phase_a_cycles[15:8];
    assign phase_b_duration = phase_b_cycles[15:8];
    
    assign training_time_us = (training_start_time > 0) ? 
                             (phase_timer - training_start_time) : 32'h0;
    assign training_iterations = total_iterations;
    assign training_quality = overall_quality;
    assign bit_error_rate = error_accumulator;
    
    // ML metrics
    assign ml_training_metrics[0] = ml_phase_predictor;
    assign ml_training_metrics[1] = ml_pattern_optimizer;
    assign ml_training_metrics[2] = ml_timing_optimizer;
    assign ml_training_metrics[3] = ml_quality_predictor;
    assign ml_training_metrics[4] = ml_training_efficiency[15:8];
    assign ml_training_metrics[5] = ml_adaptation_rate;
    
    // Status register
    assign training_status = {
        current_state,                  // [31:27]
        training_complete,              // [26]
        training_failed,                // [25]
        phase_a_active,                 // [24]
        phase_b_active,                 // [23]
        parameter_negotiation_complete, // [22]
        eq_training_enable,             // [21]
        1'b0,                          // [20] Reserved
        active_lane_count,              // [19:16]
        overall_quality,                // [15:8]
        failure_reason                  // [7:0]
    };
    
    // Debug metrics
    assign debug_training_metrics[0] = {8'h0, overall_quality};
    assign debug_training_metrics[1] = total_iterations;
    assign debug_training_metrics[2] = error_accumulator;
    assign debug_training_metrics[3] = training_time_us[15:0];
    assign debug_training_metrics[4] = {8'h0, training_retry_count};
    assign debug_training_metrics[5] = phase_a_cycles;
    assign debug_training_metrics[6] = phase_b_cycles;
    assign debug_training_metrics[7] = ml_training_efficiency;

endmodule