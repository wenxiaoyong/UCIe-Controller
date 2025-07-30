module ucie_advanced_link_state_manager
    import ucie_pkg::*;
#(
    parameter NUM_LANES = 64,
    parameter ENABLE_MULTI_MODULE = 0,
    parameter NUM_MODULES = 1,
    parameter MODULE_ID = 0,
    parameter ENABLE_ADVANCED_REPAIR = 1,
    parameter MAX_REPAIR_LANES = 8
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    input  logic                clk_sideband,
    input  logic                rst_sideband_n,
    
    // Configuration Interface
    input  data_rate_t          target_data_rate,
    input  logic [7:0]          target_lanes,
    input  package_type_t       package_type,
    input  signaling_mode_t     signaling_mode,
    
    // Physical Layer Interface
    output link_state_t         current_link_state,
    output training_state_t     current_training_state,
    input  logic                phy_ready,
    input  logic [NUM_LANES-1:0] lane_status,
    input  logic [NUM_LANES-1:0] lane_trained,
    
    // Sideband Protocol Interface
    output logic                sb_msg_valid,
    output sb_msg_type_t        sb_msg_type,
    output logic [255:0]        sb_msg_data,
    input  logic                sb_msg_ready,
    
    input  logic                sb_rx_valid,
    input  sb_msg_type_t        sb_rx_type,
    input  logic [255:0]        sb_rx_data,
    output logic                sb_rx_ready,
    
    // Power Management Interface
    input  power_state_t        power_state,
    input  micro_power_state_t  micro_power_state,
    output logic                power_state_change_req,
    input  logic                power_state_change_ack,
    
    // Multi-Module Coordination
    input  logic [NUM_MODULES-1:0] module_sync_req,
    output logic                multi_module_sync_ack,
    input  logic [NUM_MODULES-1:0] module_ready,
    output logic                module_coordinator_active,
    
    // Lane Management and Repair
    output logic [NUM_LANES-1:0] lane_enable,
    output logic [NUM_LANES-1:0] lane_repair_req,
    input  logic [NUM_LANES-1:0] lane_repair_complete,
    output logic [7:0]          active_lane_count,
    
    // Advanced Features
    input  logic                thermal_throttle,
    input  logic [7:0]          die_temperature,
    output logic                adaptive_training_enable,
    output logic [3:0]          training_optimization_level,
    
    // Status and Debug
    output logic                link_up,
    output logic [7:0]          link_status,
    output logic [15:0]         state_machine_debug,
    output logic [31:0]         training_statistics,
    
    // Error Detection and Recovery
    input  logic                crc_error,
    input  logic                sequence_error,
    input  logic                timeout_error,
    output logic                error_recovery_active,
    output logic [3:0]          error_recovery_count
);

// ============================================================================
// State Machine Definitions and Signals
// ============================================================================

link_state_t link_state_reg, link_state_next;
training_state_t training_state_reg, training_state_next;

// Training Phase Control
logic [15:0] training_timer;
logic training_timeout;
logic training_success;
logic training_retry_req;
logic [3:0] training_retry_count;

// Parameter Exchange State
typedef struct packed {
    data_rate_t     negotiated_speed;
    logic [7:0]     negotiated_width;
    signaling_mode_t negotiated_signaling;
    package_type_t  negotiated_package;
    logic           param_exchange_complete;
    logic           param_mismatch;
} param_exchange_t;

param_exchange_t param_state, param_state_next;

// Lane Management State
typedef struct packed {
    logic [NUM_LANES-1:0] lanes_available;
    logic [NUM_LANES-1:0] lanes_active;
    logic [NUM_LANES-1:0] lanes_failed;
    logic [NUM_LANES-1:0] lanes_repair_pending;
    logic [7:0]          good_lane_count;
    logic [7:0]          repair_attempts;
    logic                repair_in_progress;
} lane_mgmt_t;

lane_mgmt_t lane_state, lane_state_next;

// Multi-Module Coordination State
typedef struct packed {
    logic [NUM_MODULES-1:0] module_states_synced;
    logic [NUM_MODULES-1:0] module_training_complete;
    logic                   coordinator_role;
    logic [3:0]            sync_phase;
    logic                   all_modules_ready;
} multi_module_t;

multi_module_t mm_state, mm_state_next;

// Power Management Integration
logic power_transition_pending;
logic power_save_training_state;
link_state_t saved_link_state;
training_state_t saved_training_state;

// Error Recovery State
typedef struct packed {
    logic [3:0] crc_error_count;
    logic [3:0] seq_error_count;
    logic [3:0] timeout_error_count;
    logic [3:0] total_error_count;
    logic       error_threshold_exceeded;
    logic       recovery_active;
} error_recovery_t;

error_recovery_t error_state, error_state_next;

// Sideband Message State
logic sb_tx_pending;
sb_msg_type_t sb_tx_type_reg;
logic [255:0] sb_tx_data_reg;
logic sb_rx_processed;

// Performance Tracking
logic [31:0] training_start_time;
logic [31:0] training_end_time;
logic [15:0] successful_trainings;
logic [15:0] failed_trainings;

// ============================================================================
// Main Link State Machine
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        link_state_reg <= LINK_RESET;
        training_state_reg <= TRAIN_RESET;
        param_state <= '0;
        lane_state <= '0;
        mm_state <= '0;
        error_state <= '0;
    end else begin
        link_state_reg <= link_state_next;
        training_state_reg <= training_state_next;
        param_state <= param_state_next;
        lane_state <= lane_state_next;
        mm_state <= mm_state_next;
        error_state <= error_state_next;
    end
end

// Link State Transition Logic
always_comb begin
    link_state_next = link_state_reg;
    
    case (link_state_reg)
        LINK_RESET: begin
            if (phy_ready && !thermal_throttle) begin
                link_state_next = LINK_SBINIT;
            end
        end
        
        LINK_SBINIT: begin
            if (training_state_reg == TRAIN_SBINIT && sb_rx_processed) begin
                link_state_next = LINK_PARAM;
            end else if (error_state.error_threshold_exceeded) begin
                link_state_next = LINK_ERROR;
            end
        end
        
        LINK_PARAM: begin
            if (param_state.param_exchange_complete && !param_state.param_mismatch) begin
                if (ENABLE_MULTI_MODULE && NUM_MODULES > 1) begin
                    if (mm_state.all_modules_ready) begin
                        link_state_next = LINK_MBINIT;
                    end
                end else begin
                    link_state_next = LINK_MBINIT;
                end
            end else if (param_state.param_mismatch) begin
                link_state_next = LINK_ERROR;
            end
        end
        
        LINK_MBINIT: begin
            if (training_state_reg == TRAIN_MBINIT && lane_state.good_lane_count >= target_lanes) begin
                link_state_next = LINK_CAL;
            end else if (training_timeout) begin
                link_state_next = LINK_RETRAIN;
            end
        end
        
        LINK_CAL: begin
            if (training_state_reg == TRAIN_CAL && training_success) begin
                link_state_next = LINK_MBTRAIN;
            end else if (training_timeout) begin
                link_state_next = LINK_RETRAIN;
            end
        end
        
        LINK_MBTRAIN: begin
            if (training_state_reg == TRAIN_MBTRAIN && training_success) begin
                link_state_next = LINK_LINKINIT;
            end else if (training_timeout || error_state.error_threshold_exceeded) begin
                link_state_next = LINK_RETRAIN;
            end
        end
        
        LINK_LINKINIT: begin
            if (training_state_reg == TRAIN_LINKINIT && training_success) begin
                link_state_next = LINK_ACTIVE;
            end else if (training_timeout) begin
                link_state_next = LINK_RETRAIN;
            end
        end
        
        LINK_ACTIVE: begin
            if (power_state == PWR_L1) begin
                link_state_next = LINK_L1;
            end else if (power_state == PWR_L2) begin
                link_state_next = LINK_L2;
            end else if (error_state.error_threshold_exceeded) begin
                link_state_next = LINK_REPAIR;
            end else if (lane_state.repair_in_progress) begin
                link_state_next = LINK_REPAIR;
            end else if (thermal_throttle && die_temperature > (THERMAL_THRESHOLD_C + 5)) begin
                link_state_next = LINK_L1; // Thermal protection
            end
        end
        
        LINK_L1: begin
            if (power_state == PWR_L0 && !thermal_throttle) begin
                link_state_next = LINK_ACTIVE;
            end else if (power_state == PWR_L2) begin
                link_state_next = LINK_L2;
            end
        end
        
        LINK_L2: begin
            if (power_state == PWR_L0) begin
                link_state_next = LINK_RETRAIN; // Need to retrain after L2
            end else if (power_state == PWR_L1) begin
                link_state_next = LINK_L1;
            end
        end
        
        LINK_RETRAIN: begin
            if (training_state_reg == TRAIN_ACTIVE) begin
                link_state_next = LINK_ACTIVE;
            end else if (training_retry_count >= 3) begin
                link_state_next = LINK_ERROR;
            end
        end
        
        LINK_REPAIR: begin
            if (lane_state.repair_in_progress == 1'b0 && lane_state.good_lane_count >= target_lanes) begin
                link_state_next = LINK_ACTIVE;
            end else if (lane_state.repair_attempts >= MAX_REPAIR_LANES) begin
                link_state_next = LINK_ERROR;
            end
        end
        
        LINK_ERROR: begin
            if (!error_state.error_threshold_exceeded && phy_ready) begin
                link_state_next = LINK_RESET;
            end
        end
        
        default: link_state_next = LINK_ERROR;
    endcase
end

// ============================================================================
// Training State Machine
// ============================================================================

always_comb begin
    training_state_next = training_state_reg;
    
    case (training_state_reg)
        TRAIN_RESET: begin
            if (link_state_reg == LINK_SBINIT) begin
                training_state_next = TRAIN_SBINIT;
            end
        end
        
        TRAIN_SBINIT: begin
            if (sb_rx_valid && sb_rx_type == MSG_PARAM_REQ) begin
                training_state_next = TRAIN_PARAM;
            end else if (training_timeout) begin
                training_state_next = TRAIN_ERROR;
            end
        end
        
        TRAIN_PARAM: begin
            if (param_state.param_exchange_complete && !param_state.param_mismatch) begin
                training_state_next = TRAIN_MBINIT;
            end else if (param_state.param_mismatch || training_timeout) begin
                training_state_next = TRAIN_ERROR;
            end
        end
        
        TRAIN_MBINIT: begin
            if (lane_state.good_lane_count >= target_lanes) begin
                training_state_next = TRAIN_CAL;
            end else if (training_timeout) begin
                training_state_next = TRAIN_ERROR;
            end
        end
        
        TRAIN_CAL: begin
            if (training_success) begin
                training_state_next = TRAIN_MBTRAIN;
            end else if (training_timeout) begin
                training_state_next = TRAIN_ERROR;
            end
        end
        
        TRAIN_MBTRAIN: begin
            if (training_success) begin
                training_state_next = TRAIN_LINKINIT;
            end else if (training_timeout) begin
                training_state_next = TRAIN_ERROR;
            end
        end
        
        TRAIN_LINKINIT: begin
            if (training_success) begin
                training_state_next = TRAIN_ACTIVE;
            end else if (training_timeout) begin
                training_state_next = TRAIN_ERROR;
            end
        end
        
        TRAIN_ACTIVE: begin
            if (link_state_reg != LINK_ACTIVE) begin
                case (link_state_reg)
                    LINK_L1: training_state_next = TRAIN_L1;
                    LINK_L2: training_state_next = TRAIN_L2;
                    LINK_RETRAIN: training_state_next = TRAIN_RETRAIN;
                    LINK_REPAIR: training_state_next = TRAIN_REPAIR;
                    default: training_state_next = TRAIN_ERROR;
                endcase
            end
        end
        
        TRAIN_L1: begin
            if (link_state_reg == LINK_ACTIVE) begin
                training_state_next = TRAIN_ACTIVE;
            end else if (link_state_reg == LINK_L2) begin
                training_state_next = TRAIN_L2;
            end
        end
        
        TRAIN_L2: begin
            if (link_state_reg == LINK_RETRAIN) begin
                training_state_next = TRAIN_RETRAIN;
            end else if (link_state_reg == LINK_L1) begin
                training_state_next = TRAIN_L1;
            end
        end
        
        TRAIN_RETRAIN: begin
            if (training_success) begin
                training_state_next = TRAIN_ACTIVE;
            end else if (training_retry_count >= 3) begin
                training_state_next = TRAIN_ERROR;
            end else begin
                training_state_next = TRAIN_MBINIT; // Restart training
            end
        end
        
        TRAIN_REPAIR: begin
            if (!lane_state.repair_in_progress) begin
                training_state_next = TRAIN_ACTIVE;
            end else if (lane_state.repair_attempts >= MAX_REPAIR_LANES) begin
                training_state_next = TRAIN_ERROR;
            end
        end
        
        TRAIN_ERROR: begin
            if (link_state_reg == LINK_RESET) begin
                training_state_next = TRAIN_RESET;
            end
        end
        
        default: training_state_next = TRAIN_ERROR;
    endcase
end

// ============================================================================
// Parameter Exchange Logic
// ============================================================================

always_comb begin
    param_state_next = param_state;
    
    if (training_state_reg == TRAIN_PARAM) begin
        if (sb_rx_valid && sb_rx_type == MSG_PARAM_REQ) begin
            // Process received parameters and negotiate
            param_state_next.negotiated_speed = 
                (sb_rx_data[7:0] <= target_data_rate) ? data_rate_t'(sb_rx_data[7:0]) : target_data_rate;
            param_state_next.negotiated_width = 
                (sb_rx_data[15:8] <= target_lanes) ? sb_rx_data[15:8] : target_lanes;
            param_state_next.negotiated_signaling = 
                (param_state_next.negotiated_speed > DR_64GT) ? SIG_PAM4 : signaling_mode;
            param_state_next.negotiated_package = package_type;
            
            // Check for parameter mismatches
            param_state_next.param_mismatch = 
                (sb_rx_data[23:16] != package_type) || 
                (param_state_next.negotiated_speed < DR_4GT);
            
            param_state_next.param_exchange_complete = !param_state_next.param_mismatch;
        end
    end else if (link_state_reg == LINK_RESET) begin
        param_state_next = '0;
    end
end

// ============================================================================
// Lane Management Logic
// ============================================================================

generate
if (ENABLE_ADVANCED_REPAIR) begin : gen_advanced_repair

always_comb begin
    lane_state_next = lane_state;
    
    case (training_state_reg)
        TRAIN_MBINIT: begin
            // Initialize lane detection
            lane_state_next.lanes_available = lane_status;
            lane_state_next.lanes_active = lane_trained;
            lane_state_next.lanes_failed = ~lane_trained & lane_status;
            lane_state_next.good_lane_count = $countones(lane_trained);
        end
        
        TRAIN_CAL, TRAIN_MBTRAIN: begin
            // Update lane status during training
            lane_state_next.lanes_active = lane_trained;
            lane_state_next.lanes_failed = ~lane_trained & lane_state.lanes_available;
            lane_state_next.good_lane_count = $countones(lane_trained);
        end
        
        TRAIN_REPAIR: begin
            // Advanced lane repair algorithm
            if (!lane_state.repair_in_progress) begin
                lane_state_next.repair_in_progress = 1'b1;
                lane_state_next.lanes_repair_pending = lane_state.lanes_failed;
            end else if (lane_repair_complete != '0) begin
                // Update repaired lanes
                lane_state_next.lanes_repair_pending &= ~lane_repair_complete;
                lane_state_next.lanes_active |= lane_repair_complete;
                lane_state_next.lanes_failed &= ~lane_repair_complete;
                lane_state_next.good_lane_count = $countones(lane_state_next.lanes_active);
                
                if (lane_state_next.lanes_repair_pending == '0) begin
                    lane_state_next.repair_in_progress = 1'b0;
                end
            end
            
            if (lane_state.repair_attempts < 8'hFF) begin
                lane_state_next.repair_attempts = lane_state.repair_attempts + 1;
            end
        end
        
        TRAIN_RESET: begin
            lane_state_next = '0;
        end
        
        default: begin
            // Runtime lane monitoring in ACTIVE state
            if (training_state_reg == TRAIN_ACTIVE) begin
                lane_state_next.lanes_active = lane_trained;
                lane_state_next.good_lane_count = $countones(lane_trained);
                
                // Detect new lane failures
                if ($countones(lane_trained) < lane_state.good_lane_count) begin
                    lane_state_next.lanes_failed |= (lane_state.lanes_active & ~lane_trained);
                    if ($countones(lane_state_next.lanes_failed) > 0) begin
                        lane_state_next.repair_in_progress = 1'b1;
                    end
                end
            end
        end
    endcase
end

end else begin : gen_basic_repair
    // Basic lane management without advanced repair
    always_comb begin
        lane_state_next.lanes_available = lane_status;
        lane_state_next.lanes_active = lane_trained;
        lane_state_next.lanes_failed = ~lane_trained & lane_status;
        lane_state_next.good_lane_count = $countones(lane_trained);
        lane_state_next.repair_in_progress = 1'b0;
        lane_state_next.lanes_repair_pending = '0;
        lane_state_next.repair_attempts = '0;
    end
end
endgenerate

// ============================================================================
// Multi-Module Coordination
// ============================================================================

generate
if (ENABLE_MULTI_MODULE && NUM_MODULES > 1) begin : gen_multi_module

always_comb begin
    mm_state_next = mm_state;
    
    // Determine coordinator role (lowest MODULE_ID becomes coordinator)
    mm_state_next.coordinator_role = (MODULE_ID == 0);
    
    case (link_state_reg)
        LINK_PARAM: begin
            if (mm_state.coordinator_role) begin
                // Coordinator waits for all modules to complete parameter exchange
                mm_state_next.module_states_synced = module_ready;
                mm_state_next.all_modules_ready = (&module_ready);
            end else begin
                // Non-coordinator modules signal readiness
                mm_state_next.module_states_synced[MODULE_ID] = param_state.param_exchange_complete;
            end
        end
        
        TRAIN_ACTIVE: begin
            mm_state_next.module_training_complete[MODULE_ID] = 1'b1;
            mm_state_next.all_modules_ready = (&mm_state.module_training_complete);
        end
        
        LINK_RESET: begin
            mm_state_next = '0;
            mm_state_next.coordinator_role = (MODULE_ID == 0);
        end
        
        default: begin
            // Maintain current state
        end
    endcase
end

assign module_coordinator_active = mm_state.coordinator_role;
assign multi_module_sync_ack = mm_state.all_modules_ready;

end else begin : gen_single_module
    assign module_coordinator_active = 1'b0;
    assign multi_module_sync_ack = 1'b1;
    always_comb mm_state_next = '0;
end
endgenerate

// ============================================================================
// Error Recovery Logic
// ============================================================================

always_comb begin
    error_state_next = error_state;
    
    // Error counting
    if (crc_error && error_state.crc_error_count < 4'hF) begin
        error_state_next.crc_error_count = error_state.crc_error_count + 1;
    end
    
    if (sequence_error && error_state.seq_error_count < 4'hF) begin
        error_state_next.seq_error_count = error_state.seq_error_count + 1;
    end
    
    if (timeout_error && error_state.timeout_error_count < 4'hF) begin
        error_state_next.timeout_error_count = error_state.timeout_error_count + 1;
    end
    
    error_state_next.total_error_count = 
        error_state_next.crc_error_count + 
        error_state_next.seq_error_count + 
        error_state_next.timeout_error_count;
    
    // Error threshold checking
    error_state_next.error_threshold_exceeded = (error_state_next.total_error_count > 4'h8);
    
    // Recovery activation
    error_state_next.recovery_active = 
        error_state_next.error_threshold_exceeded || 
        (link_state_reg == LINK_REPAIR) ||
        (training_state_reg == TRAIN_REPAIR);
    
    // Reset error counts on successful training completion
    if (training_state_reg == TRAIN_ACTIVE && link_state_reg == LINK_ACTIVE) begin
        error_state_next.crc_error_count = '0;
        error_state_next.seq_error_count = '0;
        error_state_next.timeout_error_count = '0;
        error_state_next.total_error_count = '0;
        error_state_next.error_threshold_exceeded = 1'b0;
    end
end

// ============================================================================
// Sideband Message Handling
// ============================================================================

always_ff @(posedge clk_sideband or negedge rst_sideband_n) begin
    if (!rst_sideband_n) begin
        sb_tx_pending <= 1'b0;
        sb_tx_type_reg <= MSG_HEARTBEAT;
        sb_tx_data_reg <= '0;
        sb_rx_processed <= 1'b0;
    end else begin
        // Transmit message generation
        case (training_state_reg)
            TRAIN_PARAM: begin
                if (!sb_tx_pending) begin
                    sb_tx_pending <= 1'b1;
                    sb_tx_type_reg <= MSG_PARAM_RSP;
                    sb_tx_data_reg[7:0] <= target_data_rate;
                    sb_tx_data_reg[15:8] <= target_lanes;
                    sb_tx_data_reg[23:16] <= package_type;
                    sb_tx_data_reg[31:24] <= signaling_mode;
                end
            end
            
            TRAIN_ACTIVE: begin
                if (!sb_tx_pending) begin
                    sb_tx_pending <= 1'b1;
                    sb_tx_type_reg <= MSG_HEARTBEAT;
                    sb_tx_data_reg[7:0] <= lane_state.good_lane_count;
                    sb_tx_data_reg[15:8] <= error_state.total_error_count;
                end
            end
            
            default: begin
                if (sb_msg_ready && sb_tx_pending) begin
                    sb_tx_pending <= 1'b0;
                end
            end
        endcase
        
        // Receive message processing
        if (sb_rx_valid && !sb_rx_processed) begin
            sb_rx_processed <= 1'b1;
        end else if (!sb_rx_valid) begin
            sb_rx_processed <= 1'b0;
        end
    end
end

// ============================================================================
// Timer and Timeout Management
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        training_timer <= 16'h0;
        training_timeout <= 1'b0;
        training_retry_count <= 4'h0;
        training_start_time <= 32'h0;
        training_end_time <= 32'h0;
        successful_trainings <= 16'h0;
        failed_trainings <= 16'h0;
    end else begin
        // Training timer
        if (training_state_reg != training_state_next) begin
            training_timer <= 16'h0;
            training_timeout <= 1'b0;
            if (training_state_next != TRAIN_RESET && training_state_next != TRAIN_ERROR) begin
                training_start_time <= training_start_time + 1; // Simple counter
            end
        end else if (training_timer < 16'hFFFF) begin
            training_timer <= training_timer + 1;
        end
        
        // Timeout detection (state-specific timeouts)
        case (training_state_reg)
            TRAIN_SBINIT: training_timeout <= (training_timer > PARAM_EXCHANGE_TIMEOUT[15:0]);
            TRAIN_PARAM: training_timeout <= (training_timer > PARAM_EXCHANGE_TIMEOUT[15:0]);
            TRAIN_MBINIT, TRAIN_CAL, TRAIN_MBTRAIN, TRAIN_LINKINIT: 
                training_timeout <= (training_timer > TRAINING_TIMEOUT[15:0]);
            TRAIN_REPAIR: training_timeout <= (training_timer > LANE_REPAIR_TIMEOUT[15:0]);
            default: training_timeout <= 1'b0;
        endcase
        
        // Retry counting
        if (link_state_reg == LINK_RETRAIN && link_state_next != LINK_RETRAIN) begin
            if (link_state_next == LINK_ACTIVE) begin
                training_retry_count <= 4'h0; // Reset on success
                successful_trainings <= successful_trainings + 1;
                training_end_time <= training_start_time;
            end else if (training_retry_count < 4'hF) begin
                training_retry_count <= training_retry_count + 1;
                if (training_retry_count == 4'h2) begin // Max retries reached
                    failed_trainings <= failed_trainings + 1;
                end
            end
        end
    end
end

// Training success detection
assign training_success = (lane_state.good_lane_count >= target_lanes) && 
                         (param_state.param_exchange_complete) &&
                         (!error_state.error_threshold_exceeded);

// ============================================================================
// Output Assignments
// ============================================================================

assign current_link_state = link_state_reg;
assign current_training_state = training_state_reg;

assign sb_msg_valid = sb_tx_pending;
assign sb_msg_type = sb_tx_type_reg;
assign sb_msg_data = sb_tx_data_reg;
assign sb_rx_ready = !sb_rx_processed;

assign power_state_change_req = (power_state != PWR_L0) && (link_state_reg == LINK_ACTIVE);

assign lane_enable = lane_state.lanes_active;
assign lane_repair_req = lane_state.lanes_repair_pending;
assign active_lane_count = lane_state.good_lane_count;

assign adaptive_training_enable = (micro_power_state == L0_ADAPTIVE) || (micro_power_state == L0_ML_OPTIMIZED);
assign training_optimization_level = 
    (micro_power_state == L0_ML_OPTIMIZED) ? 4'h3 :
    (micro_power_state == L0_ADAPTIVE) ? 4'h2 :
    (micro_power_state == L0_ACTIVE) ? 4'h1 : 4'h0;

assign link_up = (link_state_reg == LINK_ACTIVE);
assign link_status = {
    link_state_reg,
    training_state_reg[3:0]
};

assign state_machine_debug = {
    link_state_reg,
    training_state_reg[3:0],
    param_state.param_exchange_complete,
    lane_state.repair_in_progress,
    error_state.recovery_active,
    thermal_throttle,
    mm_state.coordinator_role,
    training_timeout
};

assign training_statistics = {
    successful_trainings,
    failed_trainings
};

assign error_recovery_active = error_state.recovery_active;
assign error_recovery_count = error_state.total_error_count;

endmodule