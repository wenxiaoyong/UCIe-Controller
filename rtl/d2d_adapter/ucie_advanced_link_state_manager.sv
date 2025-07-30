module ucie_advanced_link_state_manager
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter NUM_LANES = 64,
    parameter ENHANCED_128G = 1,         // Enable 128 Gbps enhancements
    parameter ML_STATE_PREDICTION = 1,   // Enable ML-based state prediction
    parameter ADVANCED_POWER_MGMT = 1,   // Enable advanced power management
    parameter MULTI_MODULE_SUPPORT = 1   // Enable multi-module coordination
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // System Configuration
    input  logic                link_enable,
    input  logic [7:0]          target_data_rate,      // GT/s
    input  logic [7:0]          target_lanes,
    input  signaling_mode_t     signaling_mode,
    input  logic                retimer_mode,
    
    // Physical Layer Interface
    input  logic                phy_ready,
    input  logic [NUM_LANES-1:0] phy_lane_ready,
    input  logic [NUM_LANES-1:0] phy_lane_error,
    input  logic                phy_training_complete,
    input  logic [7:0]          phy_signal_quality,
    output logic                phy_enable,
    output logic                phy_training_enable,
    output logic [7:0]          phy_power_state,
    
    // D2D Adapter Interface
    input  logic                adapter_ready,
    input  logic                crc_error,
    input  logic [15:0]         retry_count,
    input  logic [7:0]          buffer_utilization,
    output logic                adapter_enable,
    output logic                link_reset_req,
    
    // Protocol Layer Interface
    input  logic                protocol_ready,
    input  logic [7:0]          protocol_errors,
    input  logic [15:0]         flow_control_credits,
    output logic                protocol_enable,
    output logic [3:0]          link_state_to_protocol,
    
    // Sideband Interface
    input  logic                sb_param_exchange_complete,
    input  logic                sb_link_up,
    input  logic [31:0]         sb_remote_capabilities,
    input  logic [7:0]          sb_remote_state,
    output logic [7:0]          sb_local_state,
    output logic                sb_state_change_req,
    
    // Power Management Interface
    input  micro_power_state_t  requested_power_state,
    input  logic                thermal_throttle_req,
    input  temperature_t        die_temperature,
    output micro_power_state_t  current_power_state,
    output logic                power_state_ack,
    
    // ML Enhancement Interface
    input  logic                ml_enable,
    input  logic [7:0]          ml_confidence_threshold,
    output logic [15:0]         ml_state_prediction,
    output logic [7:0]          ml_transition_confidence,
    output logic [7:0]          ml_performance_score,
    
    // Multi-Module Coordination (128 Gbps)
    input  logic [3:0]          module_count,
    input  logic [3:0]          module_id,
    input  logic [31:0]         inter_module_sync,
    output logic [31:0]         module_status,
    output logic                module_sync_req,
    
    // Advanced Features Interface
    input  logic                lane_repair_enable,
    input  logic [NUM_LANES-1:0] lane_repair_map,
    input  logic                lane_reversal_enable,
    output logic [NUM_LANES-1:0] active_lane_map,
    output logic                link_degraded,
    
    // Status and Debug
    output link_state_t         current_link_state,
    output logic [31:0]         state_machine_status,
    output logic [15:0]         state_transition_count,
    output logic [31:0]         link_uptime_cycles,
    output logic [7:0]          link_quality_score,
    
    // Error and Performance Monitoring
    output logic [15:0]         error_event_count,
    output logic [7:0]          performance_score,
    output logic                link_stability_alarm,
    output logic [15:0]         training_failure_count
);

    // Advanced State Machine Definition
    typedef enum logic [4:0] {
        // Basic UCIe States
        LINK_RESET        = 5'h00,
        LINK_DISABLED     = 5'h01,
        LINK_TRAINING     = 5'h02,
        LINK_ACTIVE       = 5'h03,
        LINK_RETRAIN      = 5'h04,
        
        // Enhanced 128 Gbps States
        LINK_PAM4_INIT    = 5'h08,
        LINK_PAM4_TRAIN   = 5'h09,
        LINK_PAM4_EQUALIZE = 5'h0A,
        LINK_PAM4_OPTIMIZE = 5'h0B,
        
        // Advanced Power States
        LINK_L0_ACTIVE    = 5'h10,
        LINK_L0_LOW_POWER = 5'h11,
        LINK_L0_THROTTLED = 5'h12,
        LINK_L1_STANDBY   = 5'h13,
        LINK_L2_POWERDOWN = 5'h14,
        
        // Error Recovery States
        LINK_ERROR_DETECT = 5'h18,
        LINK_ERROR_ISOLATE = 5'h19,
        LINK_ERROR_RECOVER = 5'h1A,
        LINK_LANE_REPAIR  = 5'h1B,
        
        // Multi-Module States
        LINK_MODULE_SYNC  = 5'h1C,
        LINK_MODULE_COORD = 5'h1D,
        LINK_MODULE_BALANCE = 5'h1E,
        
        // ML-Enhanced States
        LINK_ML_PREDICT   = 5'h1F
    } enhanced_link_state_t;
    
    // State Variables
    enhanced_link_state_t current_state, next_state;
    enhanced_link_state_t prev_state_history [7:0];
    logic [2:0] state_history_ptr;
    
    // Timing and Control
    logic [31:0] state_timer;
    logic [31:0] uptime_counter;
    logic [15:0] transition_counter;
    logic [15:0] training_failure_counter;
    logic [15:0] error_counter;
    
    // Power Management State
    micro_power_state_t power_state_reg;
    logic [7:0] power_transition_timer;
    logic power_state_stable;
    
    // Lane Management
    logic [NUM_LANES-1:0] active_lanes;
    logic [NUM_LANES-1:0] failed_lanes;
    logic [NUM_LANES-1:0] repaired_lanes;
    logic [7:0] lane_count_active;
    logic [7:0] lane_count_target;
    
    // Performance Monitoring
    logic [7:0] link_quality;
    logic [7:0] performance_metric;
    logic [31:0] error_accumulator;
    logic [31:0] performance_accumulator;
    
    // ML State Prediction Engine
    logic [15:0] ml_state_predictor;
    logic [7:0] ml_confidence;
    logic [7:0] ml_accuracy_score;
    logic [31:0] ml_prediction_history [7:0];
    logic [2:0] ml_history_ptr;
    
    // Multi-Module Coordination
    logic [31:0] module_sync_state;
    logic [3:0] synchronized_modules;
    logic [7:0] module_coordination_timer;
    
    // Advanced Feature Controls
    logic lane_repair_active;
    logic lane_reversal_active;
    logic thermal_management_active;
    logic [7:0] degradation_threshold;
    
    // State Transition Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= LINK_RESET;
            state_timer <= '0;
            uptime_counter <= '0;
            transition_counter <= '0;
            state_history_ptr <= '0;
            
            for (int i = 0; i < 8; i++) begin
                prev_state_history[i] <= LINK_RESET;
            end
        end else begin
            // State transition
            if (current_state != next_state) begin
                prev_state_history[state_history_ptr] <= current_state;
                state_history_ptr <= state_history_ptr + 1;
                current_state <= next_state;
                state_timer <= '0;
                transition_counter <= transition_counter + 1;
            end else begin
                state_timer <= state_timer + 1;
            end
            
            // Update uptime when in active states
            if (current_state == LINK_ACTIVE || 
                current_state == LINK_L0_ACTIVE ||
                current_state == LINK_PAM4_OPTIMIZE) begin
                uptime_counter <= uptime_counter + 1;
            end
        end
    end
    
    // Next State Determination Logic
    always_comb begin
        next_state = current_state; // Default: stay in current state
        
        case (current_state)
            LINK_RESET: begin
                if (link_enable && phy_ready) begin
                    if (ENHANCED_128G && signaling_mode == SIG_PAM4) begin
                        next_state = LINK_PAM4_INIT;
                    end else begin
                        next_state = LINK_TRAINING;
                    end
                end else if (!link_enable) begin
                    next_state = LINK_DISABLED;
                end
            end
            
            LINK_DISABLED: begin
                if (link_enable) begin
                    next_state = LINK_RESET;
                end
            end
            
            LINK_TRAINING: begin
                if (phy_training_complete && adapter_ready && protocol_ready) begin
                    if (MULTI_MODULE_SUPPORT && module_count > 1) begin
                        next_state = LINK_MODULE_SYNC;
                    end else begin
                        next_state = LINK_ACTIVE;
                    end
                end else if (state_timer > 32'd100000) begin // Training timeout
                    training_failure_counter <= training_failure_counter + 1;
                    next_state = LINK_ERROR_RECOVER;
                end else if (phy_lane_error != '0) begin
                    next_state = LINK_ERROR_DETECT;
                end
            end
            
            LINK_PAM4_INIT: begin
                if (phy_ready && sb_param_exchange_complete) begin
                    next_state = LINK_PAM4_TRAIN;
                end else if (state_timer > 32'd50000) begin
                    next_state = LINK_ERROR_RECOVER;
                end
            end
            
            LINK_PAM4_TRAIN: begin
                if (phy_training_complete) begin
                    next_state = LINK_PAM4_EQUALIZE;
                end else if (state_timer > 32'd200000) begin // Extended timeout for PAM4
                    training_failure_counter <= training_failure_counter + 1;
                    next_state = LINK_ERROR_RECOVER;
                end
            end
            
            LINK_PAM4_EQUALIZE: begin
                if (phy_signal_quality > 8'd200) begin // Good signal quality
                    next_state = LINK_PAM4_OPTIMIZE;
                end else if (state_timer > 32'd150000) begin
                    next_state = LINK_RETRAIN;
                end
            end
            
            LINK_PAM4_OPTIMIZE: begin
                if (adapter_ready && protocol_ready) begin
                    if (MULTI_MODULE_SUPPORT && module_count > 1) begin
                        next_state = LINK_MODULE_SYNC;
                    end else begin
                        next_state = LINK_L0_ACTIVE;
                    end
                end else if (phy_signal_quality < 8'd150) begin
                    next_state = LINK_PAM4_EQUALIZE;
                end
            end
            
            LINK_MODULE_SYNC: begin
                if (synchronized_modules == module_count) begin
                    next_state = LINK_MODULE_COORD;
                end else if (state_timer > 32'd75000) begin
                    next_state = LINK_ERROR_RECOVER;
                end
            end
            
            LINK_MODULE_COORD: begin
                if (inter_module_sync[0]) begin // Sync signal from other modules
                    next_state = LINK_L0_ACTIVE;
                end else if (state_timer > 32'd25000) begin
                    next_state = LINK_MODULE_SYNC;
                end
            end
            
            LINK_ACTIVE, LINK_L0_ACTIVE: begin
                // Transition based on power management requests
                if (thermal_throttle_req || die_temperature > TEMP_WARNING) begin
                    next_state = LINK_L0_THROTTLED;
                end else if (requested_power_state == L0_LOW_POWER) begin
                    next_state = LINK_L0_LOW_POWER;
                end else if (requested_power_state == L1_STANDBY) begin
                    next_state = LINK_L1_STANDBY;
                end else if (requested_power_state == L2_POWERDOWN) begin
                    next_state = LINK_L2_POWERDOWN;
                end else if (crc_error || protocol_errors > 8'd10) begin
                    next_state = LINK_ERROR_DETECT;
                end else if (lane_repair_enable && (popcount(phy_lane_error) > 2)) begin
                    next_state = LINK_LANE_REPAIR;
                end else if (ML_STATE_PREDICTION && ml_enable && 
                           (ml_state_predictor[3:0] != 4'(current_state[3:0])) &&
                           (ml_confidence > ml_confidence_threshold)) begin
                    next_state = LINK_ML_PREDICT;
                end
            end
            
            LINK_L0_LOW_POWER: begin
                if (requested_power_state == L0_ACTIVE || 
                    protocol_errors > 8'd5) begin
                    next_state = LINK_L0_ACTIVE;
                end else if (thermal_throttle_req) begin
                    next_state = LINK_L0_THROTTLED;
                end else if (requested_power_state == L1_STANDBY) begin
                    next_state = LINK_L1_STANDBY;
                end
            end
            
            LINK_L0_THROTTLED: begin
                if (!thermal_throttle_req && die_temperature < TEMP_NORMAL) begin
                    next_state = LINK_L0_ACTIVE;
                end else if (die_temperature > TEMP_CRITICAL) begin
                    next_state = LINK_L2_POWERDOWN;
                end
            end
            
            LINK_L1_STANDBY: begin
                if (requested_power_state == L0_ACTIVE || protocol_errors > 0) begin
                    next_state = LINK_L0_ACTIVE;
                end else if (requested_power_state == L2_POWERDOWN) begin
                    next_state = LINK_L2_POWERDOWN;
                end
            end
            
            LINK_L2_POWERDOWN: begin
                if (requested_power_state == L0_ACTIVE || link_enable) begin
                    next_state = LINK_RESET;
                end
            end
            
            LINK_ERROR_DETECT: begin
                if (popcount(phy_lane_error) > (NUM_LANES >> 2)) begin // >25% lanes failed
                    next_state = LINK_ERROR_ISOLATE;
                end else if (crc_error && retry_count > 16'd100) begin
                    next_state = LINK_ERROR_RECOVER;
                end else if (state_timer > 32'd10000) begin // Quick error assessment
                    if (phy_lane_error == '0 && !crc_error) begin
                        next_state = current_state == LINK_PAM4_OPTIMIZE ? LINK_L0_ACTIVE : LINK_ACTIVE;
                    end else begin
                        next_state = LINK_ERROR_RECOVER;
                    end
                end
            end
            
            LINK_ERROR_ISOLATE: begin
                if (lane_repair_enable) begin
                    next_state = LINK_LANE_REPAIR;
                end else begin
                    next_state = LINK_ERROR_RECOVER;
                end
            end
            
            LINK_ERROR_RECOVER: begin
                if (state_timer > 32'd50000) begin // Recovery timeout
                    next_state = LINK_RETRAIN;
                end
            end
            
            LINK_LANE_REPAIR: begin
                if (popcount(active_lanes) >= (target_lanes >> 1)) begin // At least 50% lanes active
                    next_state = LINK_RETRAIN;
                end else if (state_timer > 32'd75000) begin
                    next_state = LINK_ERROR_RECOVER;
                end
            end
            
            LINK_RETRAIN: begin
                if (ENHANCED_128G && signaling_mode == SIG_PAM4) begin
                    next_state = LINK_PAM4_INIT;
                end else begin
                    next_state = LINK_TRAINING;
                end
            end
            
            LINK_ML_PREDICT: begin
                // ML-guided state transition
                if (ml_confidence > 8'd200) begin // High confidence
                    case (ml_state_predictor[3:0])
                        4'h0: next_state = LINK_L0_ACTIVE;
                        4'h1: next_state = LINK_L0_LOW_POWER;
                        4'h2: next_state = LINK_L0_THROTTLED;
                        4'h3: next_state = LINK_RETRAIN;
                        default: next_state = LINK_L0_ACTIVE;
                    endcase
                end else begin
                    next_state = LINK_L0_ACTIVE; // Fall back to active
                end
            end
            
            default: next_state = LINK_RESET;
        endcase
    end
    
    // Lane Management Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_lanes <= '0;
            failed_lanes <= '0;
            repaired_lanes <= '0;
            lane_count_active <= '0;
            lane_repair_active <= 1'b0;
        end else begin
            // Update lane status
            failed_lanes <= phy_lane_error;
            
            if (current_state == LINK_LANE_REPAIR) begin
                lane_repair_active <= 1'b1;
                
                // Attempt to repair failed lanes
                for (int i = 0; i < NUM_LANES; i++) begin
                    if (failed_lanes[i] && lane_repair_map[i]) begin
                        // Simple repair logic - in reality would involve PHY recalibration
                        if (state_timer[7:0] == 8'hFF) begin // Periodic repair attempt
                            repaired_lanes[i] <= ~repaired_lanes[i];
                        end
                    end
                end
            end else begin
                lane_repair_active <= 1'b0;
            end
            
            // Update active lane map
            for (int i = 0; i < NUM_LANES; i++) begin
                active_lanes[i] <= phy_lane_ready[i] && !failed_lanes[i] && (i < target_lanes);
            end
            
            lane_count_active <= popcount(active_lanes);
        end
    end
    
    // Power Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power_state_reg <= L0_ACTIVE;
            power_transition_timer <= '0;
            power_state_stable <= 1'b0;
        end else begin
            case (current_state)
                LINK_L0_ACTIVE: power_state_reg <= L0_ACTIVE;
                LINK_L0_LOW_POWER: power_state_reg <= L0_LOW_POWER;
                LINK_L0_THROTTLED: power_state_reg <= L0_THROTTLED;
                LINK_L1_STANDBY: power_state_reg <= L1_STANDBY;
                LINK_L2_POWERDOWN: power_state_reg <= L2_POWERDOWN;
                default: power_state_reg <= L0_ACTIVE;
            endcase
            
            // Power state stability timer
            if (power_state_reg == requested_power_state) begin
                if (power_transition_timer < 8'hFF) begin
                    power_transition_timer <= power_transition_timer + 1;
                end
                power_state_stable <= (power_transition_timer > 8'h10);
            end else begin
                power_transition_timer <= '0;
                power_state_stable <= 1'b0;
            end
        end
    end
    
    // ML State Prediction Engine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ml_state_predictor <= '0;
            ml_confidence <= '0;
            ml_accuracy_score <= 8'h80;
            ml_history_ptr <= '0;
            
            for (int i = 0; i < 8; i++) begin
                ml_prediction_history[i] <= '0;
            end
        end else if (ML_STATE_PREDICTION && ml_enable) begin
            // Simple ML prediction based on error patterns and performance
            logic [7:0] error_trend = (error_counter[7:0] > prev_state_history[0][7:0]) ? 8'hFF : 8'h00;
            logic [7:0] performance_trend = performance_metric;
            logic [7:0] thermal_factor = (die_temperature > TEMP_WARNING) ? 8'hC0 : 8'h40;
            
            // Weighted prediction algorithm
            logic [15:0] prediction_input = {error_trend, performance_trend} + 
                                          {thermal_factor, buffer_utilization};
            
            // Store prediction history
            ml_prediction_history[ml_history_ptr] <= {16'h0, prediction_input};
            ml_history_ptr <= ml_history_ptr + 1;
            
            // Calculate prediction based on trends
            if (error_trend > 8'h80 || thermal_factor > 8'hA0) begin
                ml_state_predictor <= 16'h0002; // Predict throttled state
                ml_confidence <= 8'hE0;
            end else if (performance_trend > 8'hC0 && error_trend < 8'h20) begin
                ml_state_predictor <= 16'h0000; // Predict active state
                ml_confidence <= 8'hF0;
            end else if (performance_trend < 8'h40) begin
                ml_state_predictor <= 16'h0001; // Predict low power state
                ml_confidence <= 8'hB0;
            end else begin
                ml_confidence <= ml_confidence > 8'h10 ? ml_confidence - 8'h10 : 8'h00;
            end
            
            // Update accuracy score based on prediction success
            logic prediction_correct = (ml_state_predictor[3:0] == 4'(current_state[3:0]));
            if (prediction_correct) begin
                ml_accuracy_score <= (ml_accuracy_score < 8'hF0) ? ml_accuracy_score + 8'h08 : 8'hFF;
            end else begin
                ml_accuracy_score <= (ml_accuracy_score > 8'h08) ? ml_accuracy_score - 8'h04 : 8'h00;
            end
        end
    end
    
    // Performance and Quality Monitoring
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            link_quality <= 8'h80;
            performance_metric <= 8'h80;
            error_counter <= '0;
            error_accumulator <= '0;
            performance_accumulator <= '0;
        end else begin
            // Update error counters
            if (crc_error || (phy_lane_error != '0) || (protocol_errors > 0)) begin
                error_counter <= error_counter + 1;
                error_accumulator <= error_accumulator + 
                                   {24'h0, protocol_errors} + 
                                   {16'h0, popcount(phy_lane_error), 8'h0};
            end
            
            // Calculate link quality (0-255, higher is better)
            logic [7:0] lane_quality = 8'((lane_count_active * 255) / target_lanes);
            logic [7:0] signal_quality = phy_signal_quality;
            logic [7:0] error_quality = (error_counter < 16'h100) ? 
                                       8'(255 - (error_counter[7:0])) : 8'h00;
            
            link_quality <= (lane_quality + signal_quality + error_quality) / 3;
            
            // Calculate performance metric
            logic [7:0] uptime_factor = (uptime_counter > 32'h10000) ? 8'hFF : 
                                       8'(uptime_counter[15:8]);
            logic [7:0] stability_factor = (transition_counter < 16'h10) ? 8'hFF :
                                          8'(255 - transition_counter[7:0]);
            
            performance_metric <= (link_quality + uptime_factor + stability_factor) / 3;
            performance_accumulator <= performance_accumulator + {24'h0, performance_metric};
        end
    end
    
    // Multi-Module Coordination
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            module_sync_state <= '0;
            synchronized_modules <= '0;
            module_coordination_timer <= '0;
        end else if (MULTI_MODULE_SUPPORT && module_count > 1) begin
            case (current_state)
                LINK_MODULE_SYNC: begin
                    module_coordination_timer <= module_coordination_timer + 1;
                    
                    // Simple synchronization protocol
                    if (module_coordination_timer[7:0] == 8'hFF) begin
                        module_sync_state <= module_sync_state + 1;
                    end
                    
                    // Count synchronized modules (simplified)
                    synchronized_modules <= popcount(inter_module_sync[module_count-1:0]);
                end
                
                LINK_MODULE_COORD: begin
                    // Coordinate with other modules for balanced operation
                    module_sync_state <= {module_id, current_state, link_quality, lane_count_active};
                end
                
                default: begin
                    module_coordination_timer <= '0;
                end
            endcase
        end
    end
    
    // Output Assignments
    assign current_link_state = link_state_t'(current_state[2:0]); // Map to basic UCIe states
    
    assign phy_enable = (current_state != LINK_DISABLED) && (current_state != LINK_L2_POWERDOWN);
    assign phy_training_enable = (current_state == LINK_TRAINING) || 
                                (current_state == LINK_PAM4_TRAIN) ||
                                (current_state == LINK_PAM4_EQUALIZE);
    assign phy_power_state = {5'b0, power_state_reg};
    
    assign adapter_enable = (current_state == LINK_ACTIVE) || 
                           (current_state == LINK_L0_ACTIVE) ||
                           (current_state == LINK_L0_LOW_POWER);
    assign link_reset_req = (current_state == LINK_RESET) || (current_state == LINK_ERROR_RECOVER);
    
    assign protocol_enable = adapter_enable;
    assign link_state_to_protocol = current_state[3:0];
    
    assign sb_local_state = {3'b0, current_state};
    assign sb_state_change_req = (current_state != prev_state_history[0]);
    
    assign current_power_state = power_state_reg;
    assign power_state_ack = power_state_stable;
    
    assign ml_state_prediction = ml_state_predictor;
    assign ml_transition_confidence = ml_confidence;
    assign ml_performance_score = ml_accuracy_score;
    
    assign module_status = module_sync_state;
    assign module_sync_req = (current_state == LINK_MODULE_SYNC);
    
    assign active_lane_map = active_lanes;
    assign link_degraded = (lane_count_active < target_lanes) || (link_quality < 8'h80);
    
    assign state_machine_status = {
        current_state,              // [31:27] Current state
        power_state_stable,         // [26] Power state stable
        lane_repair_active,         // [25] Lane repair active
        ML_STATE_PREDICTION[0],     // [24] ML prediction enabled
        synchronized_modules,       // [23:20] Synchronized modules
        lane_count_active,          // [19:12] Active lane count
        popcount(failed_lanes)      // [11:4] Failed lane count
    };
    
    assign state_transition_count = transition_counter;
    assign link_uptime_cycles = uptime_counter;
    assign link_quality_score = link_quality;
    
    assign error_event_count = error_counter;
    assign performance_score = performance_metric;
    assign link_stability_alarm = (transition_counter > 16'd50) || (error_counter > 16'd100);
    assign training_failure_count = training_failure_counter;

endmodule