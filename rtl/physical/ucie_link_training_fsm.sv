module ucie_link_training_fsm
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
    import ucie_common_pkg::*; // For thermal management types
#(
    parameter int NUM_MODULES = 1,
    parameter int NUM_LANES = 64,
    parameter int ENHANCED_128G = 1, // Always enable 128 Gbps enhancements
    parameter int THERMAL_MANAGEMENT = 1, // Always enable thermal management
    parameter int ADAPTIVE_TRAINING = 1  // Enable adaptive training parameters
) (
    input  logic                clk,
    input  logic                clk_aux,
    input  logic                rst_n,
    
    // Training Control
    input  logic                training_start,
    output logic [4:0]          training_state,
    output logic                training_complete,
    output logic                training_error,
    
    // Physical Control Interface
    output logic                phy_reset_req,
    output logic [7:0]          phy_speed_req,
    output logic [7:0]          phy_width_req,
    input  logic                phy_ready,
    input  logic [7:0]          phy_speed_ack,
    input  logic [7:0]          phy_width_ack,
    
    // Sideband Parameter Interface
    output logic [31:0]         sb_param_tx,
    output logic                sb_param_tx_valid,
    input  logic                sb_param_tx_ready,
    input  logic [31:0]         sb_param_rx,
    input  logic                sb_param_rx_valid,
    output logic                sb_param_rx_ready,
    
    // Lane Management Interface
    output logic                lane_train_enable,
    input  logic [NUM_LANES-1:0] lane_train_done,
    input  logic [NUM_LANES-1:0] lane_train_error,
    output logic [NUM_LANES-1:0] lane_enable,
    
    // Training Pattern Interface
    output logic [7:0]          pattern_select,
    output logic                pattern_enable,
    input  logic                pattern_lock,
    input  logic [15:0]         pattern_errors,
    
    // Calibration Interface
    output logic                cal_start,
    input  logic                cal_done,
    input  logic                cal_error,
    
    // Multi-Module Coordination
    output logic                module_sync_req,
    input  logic                module_sync_ack,
    input  logic [NUM_MODULES-1:0] module_ready,
    
    // Status and Debug
    output logic [31:0]         training_timer,
    output logic [15:0]         error_counters,
    output logic [7:0]          training_attempts,
    
    // Thermal Management Integration
    input  logic [7:0]          die_temperature,          // Die temperature in Celsius
    input  logic [7:0]          ambient_temperature,      // Ambient temperature
    input  logic [15:0]         power_consumption_mw,     // Current power consumption
    input  logic                thermal_emergency,        // Emergency thermal shutdown
    input  logic                thermal_warning,          // Thermal warning threshold
    output logic                thermal_training_active,  // Training with thermal consideration
    output logic                thermal_throttle_req,     // Request thermal throttling
    output logic [7:0]          thermal_safe_speed,       // Thermally safe speed recommendation
    
    // Adaptive Training Parameters
    input  logic                adaptive_enable,          // Enable adaptive training
    output logic [7:0]          adaptive_pattern_time,    // Adaptive pattern training time
    output logic [7:0]          adaptive_cal_time,       // Adaptive calibration time
    output logic [3:0]          adaptive_retry_count,     // Adaptive retry count
    output logic                training_mode_aggressive, // Aggressive training mode
    
    // Enhanced 128 Gbps Training Support
    input  logic                pam4_mode_requested,      // PAM4 mode requested
    output logic                pam4_training_active,     // PAM4 training in progress
    output logic [7:0]          equalization_level,       // Equalization training level
    output logic                advanced_training_req     // Advanced training required
);

    // State Variables
    training_state_t current_state, next_state;
    
    // Timer and Counter Registers
    logic [31:0] timer_count;
    logic [15:0] error_count;
    logic [7:0]  attempt_count;
    logic [31:0] timeout_values [13:0];
    
    // Control Signals
    logic timer_expired;
    logic all_lanes_trained;
    logic param_exchange_done;
    logic calibration_complete;
    logic pattern_locked;
    logic modules_synchronized;
    
    // Thermal Management Variables
    logic thermal_training_active_reg;
    logic thermal_throttle_req_reg;
    logic [7:0] thermal_safe_speed_reg;
    logic thermal_emergency_last;
    logic thermal_cooldown_needed;
    logic [31:0] thermal_cooldown_timer;
    logic [7:0] thermal_history [7:0]; // 8-sample thermal history
    logic [2:0] thermal_history_ptr;
    
    // Adaptive Training Parameters
    logic [7:0] adaptive_pattern_time_reg;
    logic [7:0] adaptive_cal_time_reg;
    logic [3:0] adaptive_retry_count_reg;
    logic training_mode_aggressive_reg;
    logic [31:0] adaptive_learning_timer;
    logic [7:0] training_success_rate;
    logic [7:0] training_failure_rate;
    
    // Enhanced Training Support
    logic pam4_training_active_reg;
    logic [7:0] equalization_level_reg;
    logic advanced_training_req_reg;
    logic [15:0] advanced_training_attempts;
    
    // Thermal Decision Matrix - Speed vs Temperature
    logic [7:0] thermal_speed_matrix [15:0]; // Speed limits for different temperatures
    
    // Thermal Management and Adaptive Training Initialization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize thermal speed matrix - temperature (°C) to max speed mapping
            thermal_speed_matrix[0]  <= 8'd128; // <40°C: 128 GT/s (full speed)
            thermal_speed_matrix[1]  <= 8'd128; // 40-45°C: 128 GT/s
            thermal_speed_matrix[2]  <= 8'd64;  // 45-50°C: 64 GT/s
            thermal_speed_matrix[3]  <= 8'd64;  // 50-55°C: 64 GT/s
            thermal_speed_matrix[4]  <= 8'd32;  // 55-60°C: 32 GT/s
            thermal_speed_matrix[5]  <= 8'd32;  // 60-65°C: 32 GT/s
            thermal_speed_matrix[6]  <= 8'd24;  // 65-70°C: 24 GT/s
            thermal_speed_matrix[7]  <= 8'd16;  // 70-75°C: 16 GT/s
            thermal_speed_matrix[8]  <= 8'd16;  // 75-80°C: 16 GT/s
            thermal_speed_matrix[9]  <= 8'd12;  // 80-85°C: 12 GT/s
            thermal_speed_matrix[10] <= 8'd8;   // 85-90°C: 8 GT/s
            thermal_speed_matrix[11] <= 8'd8;   // 90-95°C: 8 GT/s
            thermal_speed_matrix[12] <= 8'd4;   // 95-100°C: 4 GT/s
            thermal_speed_matrix[13] <= 8'd4;   // 100-105°C: 4 GT/s
            thermal_speed_matrix[14] <= 8'd4;   // 105-110°C: 4 GT/s
            thermal_speed_matrix[15] <= 8'd0;   // >110°C: Emergency shutdown
            
            // Initialize thermal management
            thermal_training_active_reg <= 1'b0;
            thermal_throttle_req_reg <= 1'b0;
            thermal_safe_speed_reg <= 8'd128; // Start optimistic
            thermal_emergency_last <= 1'b0;
            thermal_cooldown_needed <= 1'b0;
            thermal_cooldown_timer <= 32'h0;
            thermal_history_ptr <= 3'h0;
            
            // Initialize thermal history with safe values
            for (int i = 0; i < 8; i++) begin
                thermal_history[i] <= 8'd25; // Room temperature
            end
            
            // Initialize adaptive training parameters
            adaptive_pattern_time_reg <= 8'd100;  // 100us default pattern time  
            adaptive_cal_time_reg <= 8'd200;      // 200us default calibration time
            adaptive_retry_count_reg <= 4'd3;     // 3 retries default
            training_mode_aggressive_reg <= 1'b0;
            adaptive_learning_timer <= 32'h0;
            training_success_rate <= 8'hC0;       // Start with 75% assumed success rate
            training_failure_rate <= 8'h40;       // Start with 25% assumed failure rate
            
            // Initialize enhanced training support
            pam4_training_active_reg <= 1'b0;
            equalization_level_reg <= 8'd0;
            advanced_training_req_reg <= 1'b0;
            advanced_training_attempts <= 16'h0;
            
        end
    end
    
    // State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= TRAIN_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Timer Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_count <= 32'h0;
        end else if (current_state != next_state) begin
            timer_count <= 32'h0;  // Reset timer on state change
        end else begin
            timer_count <= timer_count + 1;
        end
    end
    
    // Timeout Detection
    always_comb begin
        case (current_state)
            TRAIN_RESET:     timer_expired = (timer_count > timeout_values[0]);
            TRAIN_SBINIT:    timer_expired = (timer_count > timeout_values[1]);
            TRAIN_PARAM:     timer_expired = (timer_count > timeout_values[2]);
            TRAIN_MBINIT:    timer_expired = (timer_count > timeout_values[3]);
            TRAIN_CAL:       timer_expired = (timer_count > timeout_values[4]);
            TRAIN_MBTRAIN:   timer_expired = (timer_count > timeout_values[5]);
            TRAIN_LINKINIT:  timer_expired = (timer_count > timeout_values[6]);
            default:         timer_expired = 1'b0;
        endcase
    end
    
    // Initialize timeout values (example values in clock cycles)
    initial begin
        timeout_values[0]  = 32'd1000;    // RESET: 1us @ 1GHz
        timeout_values[1]  = 32'd100000;  // SBINIT: 100us
        timeout_values[2]  = 32'd1000000; // PARAM: 1ms
        timeout_values[3]  = 32'd500000;  // MBINIT: 500us
        timeout_values[4]  = 32'd2000000; // CAL: 2ms
        timeout_values[5]  = 32'd5000000; // MBTRAIN: 5ms
        timeout_values[6]  = 32'd1000000; // LINKINIT: 1ms
    end
    
    // Status Signal Generation
    always_comb begin
        all_lanes_trained = &lane_train_done;
        param_exchange_done = sb_param_rx_valid && sb_param_tx_ready;
        calibration_complete = cal_done && !cal_error;
        pattern_locked = pattern_lock && (pattern_errors < 16'd10);
        modules_synchronized = &module_ready || (NUM_MODULES == 1);
    end
    
    // Thermal Management and Adaptive Training Engine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset thermal management registers (already handled in initialization)
        end else begin
            // Update thermal history every 10000 cycles (10us @ 1GHz)
            if (timer_count[13:0] == 14'h0) begin
                thermal_history[thermal_history_ptr] <= die_temperature;
                thermal_history_ptr <= thermal_history_ptr + 1;
            end
            
            // Thermal management logic
            if (THERMAL_MANAGEMENT) begin
                // Emergency thermal handling
                if (thermal_emergency && !thermal_emergency_last) begin
                    thermal_throttle_req_reg <= 1'b1;
                    thermal_cooldown_needed <= 1'b1;
                    thermal_cooldown_timer <= 32'd10000000; // 10ms cooldown
                    thermal_safe_speed_reg <= 8'd4; // Emergency speed
                end
                thermal_emergency_last <= thermal_emergency;
                
                // Thermal cooldown management
                if (thermal_cooldown_needed) begin
                    if (thermal_cooldown_timer > 32'h0) begin
                        thermal_cooldown_timer <= thermal_cooldown_timer - 1;
                    end else if (die_temperature < 8'd70) begin // 70°C safe threshold
                        thermal_cooldown_needed <= 1'b0;
                        thermal_throttle_req_reg <= 1'b0;
                    end
                end
                
                // Calculate thermally safe speed based on current temperature
                logic [3:0] temp_index = (die_temperature > 8'd40) ? 
                                        4'((die_temperature - 8'd40) / 8'd5) : 4'h0;
                if (temp_index > 4'd15) temp_index = 4'd15;
                thermal_safe_speed_reg <= thermal_speed_matrix[temp_index];
                
                // Activate thermal training mode if temperature is concerning
                thermal_training_active_reg <= (die_temperature > 8'd65) || thermal_warning;
            end
            
            // Adaptive training parameter learning
            if (ADAPTIVE_TRAINING && adaptive_enable) begin
                adaptive_learning_timer <= adaptive_learning_timer + 1;
                
                // Update adaptive parameters every 100000 cycles (100us @ 1GHz)
                if (adaptive_learning_timer >= 32'd100000) begin
                    adaptive_learning_timer <= 32'h0;
                    
                    // Learn from training outcomes
                    if (current_state == TRAIN_ACTIVE && training_complete) begin
                        // Training succeeded - can be more aggressive
                        if (training_success_rate < 8'hF0) begin
                            training_success_rate <= training_success_rate + 8'h08;
                        end
                        if (training_failure_rate > 8'h08) begin
                            training_failure_rate <= training_failure_rate - 8'h04;
                        end
                        
                        // Reduce training times slightly on success
                        if (adaptive_pattern_time_reg > 8'd50) begin
                            adaptive_pattern_time_reg <= adaptive_pattern_time_reg - 8'd5;
                        end
                        if (adaptive_cal_time_reg > 8'd100) begin
                            adaptive_cal_time_reg <= adaptive_cal_time_reg - 8'd10;
                        end
                        
                    end else if (current_state == TRAIN_ERROR || training_error) begin
                        // Training failed - be more conservative
                        if (training_failure_rate < 8'hF0) begin
                            training_failure_rate <= training_failure_rate + 8'h08;
                        end
                        if (training_success_rate > 8'h08) begin
                            training_success_rate <= training_success_rate - 8'h04;
                        end
                        
                        // Increase training times on failure
                        if (adaptive_pattern_time_reg < 8'd200) begin
                            adaptive_pattern_time_reg <= adaptive_pattern_time_reg + 8'd10;
                        end
                        if (adaptive_cal_time_reg < 8'd400) begin
                            adaptive_cal_time_reg <= adaptive_cal_time_reg + 8'd20;
                        end
                        
                        // Increase retry count on frequent failures
                        if (training_failure_rate > 8'h80 && adaptive_retry_count_reg < 4'd7) begin
                            adaptive_retry_count_reg <= adaptive_retry_count_reg + 1;
                        end
                    end
                    
                    // Determine training mode based on thermal and success rate
                    if (thermal_training_active_reg) begin
                        training_mode_aggressive_reg <= 1'b0; // Conservative in thermal stress
                    end else if (training_success_rate > 8'hC0 && training_failure_rate < 8'h40) begin
                        training_mode_aggressive_reg <= 1'b1; // Aggressive when successful
                    end else begin
                        training_mode_aggressive_reg <= 1'b0; // Conservative otherwise
                    end
                end
            end
            
            // Enhanced 128 Gbps training management
            if (ENHANCED_128G) begin
                // PAM4 training activation
                pam4_training_active_reg <= pam4_mode_requested && 
                                           (thermal_safe_speed_reg >= 8'd64) &&
                                           !thermal_emergency;
                
                // Advanced training requirements
                advanced_training_req_reg <= pam4_mode_requested || 
                                           (thermal_safe_speed_reg >= 8'd32);
                
                // Equalization level based on thermal and speed requirements
                if (pam4_training_active_reg) begin
                    if (thermal_training_active_reg) begin
                        equalization_level_reg <= 8'd4; // Conservative EQ for thermal stress
                    end else begin
                        equalization_level_reg <= 8'd8; // Full EQ for optimal performance
                    end
                end else begin
                    equalization_level_reg <= 8'd2; // Basic EQ for lower speeds
                end
                
                // Track advanced training attempts
                if (advanced_training_req_reg && 
                    (current_state == TRAIN_MBTRAIN || current_state == TRAIN_CAL)) begin
                    advanced_training_attempts <= advanced_training_attempts + 1;
                end
            end
        end
    end
    
    // Main State Machine Logic with Thermal Management Integration
    always_comb begin
        // Default outputs
        next_state = current_state;
        phy_reset_req = 1'b0;
        phy_speed_req = thermal_safe_speed_reg;  // Use thermally safe speed
        phy_width_req = 8'd64;  // Default x64
        sb_param_tx = 32'h0;
        sb_param_tx_valid = 1'b0;
        sb_param_rx_ready = 1'b0;
        lane_train_enable = 1'b0;
        lane_enable = {NUM_LANES{1'b0}};
        pattern_select = 8'h0;
        pattern_enable = 1'b0;
        cal_start = 1'b0;
        module_sync_req = 1'b0;
        training_complete = 1'b0;
        training_error = 1'b0;
        
        // Thermal emergency override - force safe state
        if (thermal_emergency && THERMAL_MANAGEMENT) begin
            next_state = TRAIN_ERROR;
            training_error = 1'b1;
            phy_speed_req = 8'd4;  // Emergency speed
            lane_enable = {NUM_LANES{1'b0}};
        end else begin
            case (current_state)
                TRAIN_RESET: begin
                    phy_reset_req = 1'b1;
                    if (training_start && phy_ready && !thermal_cooldown_needed) begin
                        next_state = TRAIN_SBINIT;
                    end else if (timer_expired) begin
                        next_state = TRAIN_ERROR;
                    end
                end
                
                TRAIN_SBINIT: begin
                    // Initialize sideband communication with thermal awareness
                    if (timer_expired || thermal_warning) begin
                        next_state = TRAIN_ERROR;
                    end else if (phy_ready) begin
                        next_state = TRAIN_PARAM;
                    end
                end
                
                TRAIN_PARAM: begin
                    // Parameter exchange with thermal-aware speed negotiation
                    logic [7:0] negotiated_speed = thermal_training_active_reg ? 
                                                  thermal_safe_speed_reg : 8'd128;
                    sb_param_tx = {8'd64, negotiated_speed, 16'hFFFF}; // width, thermal-safe speed, protocols
                    sb_param_tx_valid = 1'b1;
                    sb_param_rx_ready = 1'b1;
                    
                    if (timer_expired) begin
                        next_state = TRAIN_ERROR;
                    end else if (param_exchange_done) begin
                        next_state = TRAIN_MBINIT;
                    end
                end
                
                TRAIN_MBINIT: begin
                    // Mainband initialization with thermal constraints
                    logic [7:0] init_speed = thermal_training_active_reg ? 
                                           thermal_safe_speed_reg : 8'd128;
                    phy_speed_req = init_speed;
                    phy_width_req = 8'd64;   // Request negotiated width
                    
                    if (timer_expired || (thermal_training_active_reg && thermal_warning)) begin
                        next_state = TRAIN_ERROR;
                    end else if (phy_ready && (phy_speed_ack != 8'h0)) begin
                        next_state = TRAIN_CAL;
                    end
                end
                
                TRAIN_CAL: begin
                    // Calibration phase with thermal monitoring
                    cal_start = 1'b1;
                    
                    // Use adaptive calibration time based on thermal conditions
                    logic extended_cal = thermal_training_active_reg || training_mode_aggressive_reg;
                    
                    if (timer_expired || cal_error || thermal_warning) begin
                        next_state = TRAIN_ERROR;
                    end else if (calibration_complete) begin
                        next_state = TRAIN_MBTRAIN;
                    end
                end
                
                TRAIN_MBTRAIN: begin
                    // Mainband training with thermal and adaptive management
                    lane_train_enable = 1'b1;
                    
                    // Adaptive lane enabling based on thermal conditions
                    if (thermal_training_active_reg) begin
                        // Enable fewer lanes under thermal stress to reduce power
                        lane_enable = {NUM_LANES/2{1'b1}, NUM_LANES/2{1'b0}};
                    end else begin
                        lane_enable = {NUM_LANES{1'b1}};
                    end
                    
                    // Adaptive pattern selection
                    if (training_mode_aggressive_reg && !thermal_training_active_reg) begin
                        pattern_select = 8'h1F;  // PRBS31 for aggressive training
                    end else if (thermal_training_active_reg) begin
                        pattern_select = 8'h07;  // PRBS7 for thermal-conservative training
                    end else begin
                        pattern_select = 8'h0F;  // PRBS15 for balanced training
                    end
                    pattern_enable = 1'b1;
                    
                    if (timer_expired || (|lane_train_error) || thermal_warning) begin
                        next_state = TRAIN_ERROR;
                    end else if (all_lanes_trained && pattern_locked) begin
                        if (NUM_MODULES > 1) begin
                            next_state = TRAIN_MULTIMOD;
                        end else begin
                            next_state = TRAIN_LINKINIT;
                        end
                    end
                end
                
                TRAIN_MULTIMOD: begin
                    // Multi-module coordination with thermal coordination
                    module_sync_req = 1'b1;
                    
                    if (timer_expired || thermal_warning) begin
                        next_state = TRAIN_ERROR;
                    end else if (modules_synchronized && module_sync_ack) begin
                        next_state = TRAIN_LINKINIT;
                    end
                end
                
                TRAIN_LINKINIT: begin
                    // Link initialization with final thermal check
                    if (thermal_training_active_reg) begin
                        // Conservative lane enabling for thermal management
                        lane_enable = {NUM_LANES/2{1'b1}, NUM_LANES/2{1'b0}};
                    end else begin
                        lane_enable = {NUM_LANES{1'b1}};
                    end
                    
                    if (timer_expired || thermal_warning) begin
                        next_state = TRAIN_ERROR;
                    end else if (all_lanes_trained) begin
                        next_state = TRAIN_ACTIVE;
                    end
                end
                
                TRAIN_ACTIVE: begin
                    // Active operation with continuous thermal monitoring
                    training_complete = 1'b1;
                    
                    // Dynamic lane management based on thermal state
                    if (thermal_training_active_reg) begin
                        lane_enable = {NUM_LANES/2{1'b1}, NUM_LANES/2{1'b0}};
                    end else begin
                        lane_enable = {NUM_LANES{1'b1}};
                    end
                    
                    // Thermal-triggered retraining
                    if (thermal_warning && die_temperature > 8'd80) begin
                        next_state = TRAIN_RESET; // Retrain at lower speed
                    end
                    // Stay in this state until external request for state change
                end
                
                TRAIN_ERROR: begin
                    // Error state with thermal-aware retry logic
                    training_error = 1'b1;
                    
                    // Thermal cooldown logic
                    if (thermal_cooldown_needed) begin
                        // Wait for thermal cooldown before retry
                        if (!thermal_cooldown_needed && training_start && (attempt_count < adaptive_retry_count_reg)) begin
                            next_state = TRAIN_RESET;
                        end
                    end else if (training_start && (attempt_count < adaptive_retry_count_reg)) begin
                        next_state = TRAIN_RESET;
                    end
                end
                
                default: begin
                    next_state = TRAIN_RESET;
                end
            endcase
        end
    end
    
    // Counter Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_count <= 16'h0;
            attempt_count <= 8'h0;
        end else begin
            if (current_state == TRAIN_ERROR) begin
                if (next_state == TRAIN_RESET) begin
                    attempt_count <= attempt_count + 1;
                end
                error_count <= error_count + 1;
            end else if (current_state == TRAIN_ACTIVE) begin
                // Reset counters on successful training
                error_count <= 16'h0;
                attempt_count <= 8'h0;
            end
        end
    end
    
    // Output Assignments
    assign training_state = current_state;
    assign training_timer = timer_count;
    assign error_counters = error_count;
    assign training_attempts = attempt_count;
    
    // Thermal Management Outputs
    assign thermal_training_active = thermal_training_active_reg;
    assign thermal_throttle_req = thermal_throttle_req_reg;
    assign thermal_safe_speed = thermal_safe_speed_reg;
    
    // Adaptive Training Outputs
    assign adaptive_pattern_time = adaptive_pattern_time_reg;
    assign adaptive_cal_time = adaptive_cal_time_reg;
    assign adaptive_retry_count = adaptive_retry_count_reg;
    assign training_mode_aggressive = training_mode_aggressive_reg;
    
    // Enhanced 128 Gbps Training Outputs
    assign pam4_training_active = pam4_training_active_reg;
    assign equalization_level = equalization_level_reg;
    assign advanced_training_req = advanced_training_req_reg;

endmodule
