module ucie_multi_module_coordinator #(
    parameter NUM_MODULES = 4,              // Maximum 4 modules supported
    parameter MODULE_ID = 0,                // This module's ID (0-3)
    parameter COORDINATION_TIMEOUT = 1000,  // Coordination timeout cycles
    parameter ENABLE_BANDWIDTH_SHARING = 1, // Enable dynamic bandwidth sharing
    parameter ENABLE_POWER_COORDINATION = 1 // Enable coordinated power management
) (
    // Clock and Reset
    input  logic        clk,
    input  logic        rst_n,
    
    // Module Synchronization Clocks (from other modules)
    input  logic [NUM_MODULES-1:0] module_sync_clk,
    input  logic [NUM_MODULES-1:0] module_sync_reset_n,
    
    // Inter-Module Coordination Signals
    output logic                   coord_valid,
    output logic [31:0]           coord_data,
    input  logic [NUM_MODULES-1:0] coord_ready,
    
    input  logic [NUM_MODULES-1:0] coord_valid_in,
    input  logic [31:0]           coord_data_in [NUM_MODULES-1:0],
    output logic [NUM_MODULES-1:0] coord_ready_out,
    
    // Module Status Inputs
    input  ucie_pkg::link_state_t     link_state,
    input  ucie_pkg::power_state_t    power_state,
    input  ucie_pkg::training_state_t training_state,
    input  logic [7:0]                active_lanes,
    input  logic [15:0]               bandwidth_utilization,
    
    // Coordination Control
    output logic                   multi_module_active,
    output logic                   coordinator_role,
    output logic [1:0]            coordination_phase,
    output logic [NUM_MODULES-1:0] module_sync_valid,
    output logic [31:0]           module_sync_data [NUM_MODULES-1:0],
    
    // Power Coordination
    input  ucie_pkg::power_state_t    power_sync_req,
    output logic                      power_sync_ack,
    output ucie_pkg::power_state_t    coordinated_power_state,
    
    // Bandwidth Coordination
    output logic [7:0]            bandwidth_share [NUM_MODULES-1:0],
    output logic                  bandwidth_rebalance_req,
    input  logic                  bandwidth_rebalance_ack,
    
    // Performance Coordination
    input  logic [15:0]           performance_counters,
    output logic [15:0]           system_performance,
    output logic                  load_balance_active,
    
    // Error Coordination
    input  logic                  local_error,
    input  logic [3:0]           error_count,
    output logic                  system_error,
    output logic                  error_isolation_active,
    
    // Debug and Status
    output logic [31:0]           coordination_debug,
    output logic [15:0]           module_status_vector,
    output logic [7:0]            coordination_statistics
);

import ucie_pkg::*;

// ============================================================================
// Coordination State Machine Definition
// ============================================================================

typedef enum logic [3:0] {
    COORD_RESET         = 4'h0,
    COORD_DISCOVERY     = 4'h1,
    COORD_NEGOTIATION   = 4'h2,
    COORD_SYNC_INIT     = 4'h3,
    COORD_ACTIVE        = 4'h4,
    COORD_POWER_SYNC    = 4'h5,
    COORD_BANDWIDTH_SYNC = 4'h6,
    COORD_ERROR_HANDLE  = 4'h7,
    COORD_REBALANCE     = 4'h8,
    COORD_ISOLATION     = 4'h9,
    COORD_ERROR         = 4'hF
} coordination_state_t;

coordination_state_t coord_state, coord_state_next;

// ============================================================================
// Internal Signal Declarations
// ============================================================================

// Module Discovery and Status
logic [NUM_MODULES-1:0] modules_discovered;
logic [NUM_MODULES-1:0] modules_active;
logic [NUM_MODULES-1:0] modules_ready;
logic [NUM_MODULES-1:0] modules_error;

// Coordination Message Structure
typedef struct packed {
    logic [3:0]  msg_type;        // Message type
    logic [3:0]  source_id;       // Source module ID
    logic [7:0]  sequence;        // Sequence number
    logic [15:0] payload;         // Message payload
} coord_msg_t;

coord_msg_t tx_msg, rx_msg [NUM_MODULES-1:0];

// Message Types
typedef enum logic [3:0] {
    MSG_DISCOVERY    = 4'h0,
    MSG_STATUS       = 4'h1,
    MSG_POWER_REQ    = 4'h2,
    MSG_POWER_ACK    = 4'h3,
    MSG_BW_REQUEST   = 4'h4,
    MSG_BW_GRANT     = 4'h5,
    MSG_ERROR_ALERT  = 4'h6,
    MSG_HEARTBEAT    = 4'hF
} coord_msg_type_t;

// Module State Tracking
typedef struct packed {
    link_state_t     link_state;
    power_state_t    power_state;
    training_state_t training_state;
    logic [7:0]      active_lanes;
    logic [15:0]     bandwidth_util;
    logic [7:0]      error_count;
    logic            responsive;
    logic [15:0]     last_heartbeat;
} module_status_t;

module_status_t module_status [NUM_MODULES-1:0];
module_status_t local_status;

// Coordinator Selection and Role Management
logic is_coordinator;
logic [1:0] coordinator_id;
logic coordinator_election_active;
logic [15:0] coordinator_priority;

// Synchronization Control
logic [15:0] sync_timer;
logic sync_timeout;
logic [7:0] sync_sequence;
logic sync_in_progress;

// Power Coordination State
power_state_t requested_power_states [NUM_MODULES-1:0];
power_state_t consensus_power_state;
logic power_coordination_active;
logic [NUM_MODULES-1:0] power_votes;

// Bandwidth Coordination State
logic [7:0] requested_bandwidth [NUM_MODULES-1:0];
logic [7:0] allocated_bandwidth [NUM_MODULES-1:0];
logic [15:0] total_system_bandwidth;
logic bandwidth_coordination_active;

// Error Coordination State
logic [NUM_MODULES-1:0] error_alerts;
logic [NUM_MODULES-1:0] isolated_modules;
logic system_error_active;
logic error_recovery_active;

// Performance Tracking
logic [15:0] system_perf_accumulator;
logic [7:0] coordination_cycles;
logic [7:0] successful_coordinations;
logic [7:0] failed_coordinations;

// ============================================================================
// Coordinator Election and Role Assignment
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        is_coordinator <= (MODULE_ID == 0); // Default: Module 0 is coordinator
        coordinator_id <= 2'h0;
        coordinator_election_active <= 1'b0;
        coordinator_priority <= 16'h0;
    end else begin
        // Coordinator election based on module capabilities and status
        if (coord_state == COORD_DISCOVERY || coordinator_election_active) begin
            coordinator_priority <= {8'h0, active_lanes} + {12'h0, ~MODULE_ID}; // Higher lanes + lower ID = higher priority
            
            // Check if we have the highest priority among discovered modules
            logic higher_priority_exists;
            higher_priority_exists = 1'b0;
            
            for (int i = 0; i < NUM_MODULES; i++) begin
                if (modules_discovered[i] && i != MODULE_ID) begin
                    logic [15:0] other_priority = {8'h0, module_status[i].active_lanes} + {12'h0, ~i[3:0]};
                    if (other_priority > coordinator_priority) begin
                        higher_priority_exists = 1'b1;
                    end
                end
            end
            
            is_coordinator <= !higher_priority_exists;
            
            if (!higher_priority_exists) begin
                coordinator_id <= MODULE_ID;
            end else begin
                // Find the module with highest priority
                for (int i = 0; i < NUM_MODULES; i++) begin
                    if (modules_discovered[i]) begin
                        logic [15:0] check_priority = {8'h0, module_status[i].active_lanes} + {12'h0, ~i[3:0]};
                        if (check_priority > coordinator_priority) begin
                            coordinator_id <= i[1:0];
                        end
                    end
                end
            end
        end
        
        coordinator_election_active <= (coord_state == COORD_DISCOVERY);
    end
end

// ============================================================================
// Main Coordination State Machine
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coord_state <= COORD_RESET;
    end else begin
        coord_state <= coord_state_next;
    end
end

always_comb begin
    coord_state_next = coord_state;
    
    case (coord_state)
        COORD_RESET: begin
            if (rst_n && module_sync_reset_n != '0) begin
                coord_state_next = COORD_DISCOVERY;
            end
        end
        
        COORD_DISCOVERY: begin
            if ($countones(modules_discovered) >= 2) begin // At least 2 modules
                coord_state_next = COORD_NEGOTIATION;
            end else if (sync_timeout) begin
                coord_state_next = COORD_ERROR; // Single module or discovery timeout
            end
        end
        
        COORD_NEGOTIATION: begin
            if (is_coordinator && ($countones(modules_ready) == $countones(modules_discovered))) begin
                coord_state_next = COORD_SYNC_INIT;
            end else if (!is_coordinator && modules_ready[coordinator_id]) begin
                coord_state_next = COORD_SYNC_INIT;
            end else if (sync_timeout) begin
                coord_state_next = COORD_ERROR;
            end
        end
        
        COORD_SYNC_INIT: begin
            if (sync_in_progress && !sync_timeout) begin
                coord_state_next = COORD_ACTIVE;
            end else if (sync_timeout) begin
                coord_state_next = COORD_ERROR;
            end
        end
        
        COORD_ACTIVE: begin
            if (power_coordination_active) begin
                coord_state_next = COORD_POWER_SYNC;
            end else if (bandwidth_coordination_active) begin
                coord_state_next = COORD_BANDWIDTH_SYNC;
            end else if (system_error_active) begin
                coord_state_next = COORD_ERROR_HANDLE;
            end else if (|error_alerts) begin
                coord_state_next = COORD_ERROR_HANDLE;
            end
        end
        
        COORD_POWER_SYNC: begin
            if (!power_coordination_active) begin
                coord_state_next = COORD_ACTIVE;
            end else if (sync_timeout) begin
                coord_state_next = COORD_ERROR;
            end
        end
        
        COORD_BANDWIDTH_SYNC: begin
            if (!bandwidth_coordination_active) begin
                coord_state_next = COORD_ACTIVE;
            end else if (bandwidth_rebalance_req) begin
                coord_state_next = COORD_REBALANCE;
            end else if (sync_timeout) begin
                coord_state_next = COORD_ERROR;
            end
        end
        
        COORD_REBALANCE: begin
            if (bandwidth_rebalance_ack) begin
                coord_state_next = COORD_ACTIVE;
            end else if (sync_timeout) begin
                coord_state_next = COORD_ERROR;
            end
        end
        
        COORD_ERROR_HANDLE: begin
            if (!system_error_active && error_alerts == '0) begin
                coord_state_next = COORD_ACTIVE;
            end else if (|isolated_modules) begin
                coord_state_next = COORD_ISOLATION;
            end
        end
        
        COORD_ISOLATION: begin
            if (error_recovery_active) begin
                coord_state_next = COORD_ACTIVE;
            end
        end
        
        COORD_ERROR: begin
            if (!sync_timeout && modules_discovered != '0) begin
                coord_state_next = COORD_DISCOVERY;
            end
        end
        
        default: coord_state_next = COORD_ERROR;
    endcase
end

// ============================================================================
// Module Discovery and Status Tracking
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        modules_discovered <= '0;
        modules_active <= '0;
        modules_ready <= '0;
        modules_error <= '0;
        module_status <= '{default: '0};
        local_status <= '0;
    end else begin
        // Update local status
        local_status.link_state <= link_state;
        local_status.power_state <= power_state;
        local_status.training_state <= training_state;
        local_status.active_lanes <= active_lanes;
        local_status.bandwidth_util <= bandwidth_utilization;
        local_status.error_count <= error_count;
        local_status.responsive <= 1'b1;
        local_status.last_heartbeat <= sync_timer;
        
        // Process incoming coordination messages
        for (int i = 0; i < NUM_MODULES; i++) begin
            if (i != MODULE_ID && coord_valid_in[i]) begin
                rx_msg[i] = coord_msg_t'(coord_data_in[i]);
                
                case (rx_msg[i].msg_type)
                    MSG_DISCOVERY: begin
                        modules_discovered[i] <= 1'b1;
                        module_status[i].responsive <= 1'b1;
                    end
                    
                    MSG_STATUS: begin
                        modules_active[i] <= 1'b1;
                        module_status[i].link_state <= link_state_t'(rx_msg[i].payload[3:0]);
                        module_status[i].power_state <= power_state_t'(rx_msg[i].payload[5:4]);
                        module_status[i].active_lanes <= rx_msg[i].payload[13:6];
                        module_status[i].responsive <= 1'b1;
                        module_status[i].last_heartbeat <= sync_timer;
                    end
                    
                    MSG_POWER_REQ: begin
                        requested_power_states[i] <= power_state_t'(rx_msg[i].payload[1:0]);
                        power_coordination_active <= 1'b1;
                    end
                    
                    MSG_BW_REQUEST: begin
                        requested_bandwidth[i] <= rx_msg[i].payload[7:0];
                        bandwidth_coordination_active <= 1'b1;
                    end
                    
                    MSG_ERROR_ALERT: begin
                        error_alerts[i] <= 1'b1;
                        module_status[i].error_count <= rx_msg[i].payload[7:0];
                        system_error_active <= 1'b1;
                    end
                    
                    MSG_HEARTBEAT: begin
                        module_status[i].responsive <= 1'b1;
                        module_status[i].last_heartbeat <= sync_timer;
                    end
                    
                    default: begin
                        // Unknown message type
                    end
                endcase
            end
            
            // Check for unresponsive modules
            if (modules_discovered[i] && (sync_timer - module_status[i].last_heartbeat) > 16'd1000) begin
                module_status[i].responsive <= 1'b0;
                modules_error[i] <= 1'b1;
            end
        end
        
        // Update ready status based on module states
        for (int i = 0; i < NUM_MODULES; i++) begin
            if (modules_discovered[i]) begin
                modules_ready[i] <= (module_status[i].link_state == LINK_ACTIVE) && 
                                   module_status[i].responsive;
            end
        end
    end
end

// ============================================================================
// Message Transmission Logic
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        coord_valid <= 1'b0;
        coord_data <= 32'h0;
        tx_msg <= '0;
        sync_sequence <= 8'h0;
    end else begin
        case (coord_state)
            COORD_DISCOVERY: begin
                if (!coord_valid || coord_ready[MODULE_ID]) begin
                    coord_valid <= 1'b1;
                    tx_msg.msg_type <= MSG_DISCOVERY;
                    tx_msg.source_id <= MODULE_ID;
                    tx_msg.sequence <= sync_sequence;
                    tx_msg.payload <= {8'h0, active_lanes};
                    coord_data <= tx_msg;
                    sync_sequence <= sync_sequence + 1;
                end
            end
            
            COORD_ACTIVE: begin
                if (!coord_valid || coord_ready[MODULE_ID]) begin
                    coord_valid <= 1'b1;
                    tx_msg.msg_type <= MSG_STATUS;
                    tx_msg.source_id <= MODULE_ID;
                    tx_msg.sequence <= sync_sequence;
                    tx_msg.payload <= {2'h0, active_lanes, power_state, link_state};
                    coord_data <= tx_msg;
                    sync_sequence <= sync_sequence + 1;
                end
            end
            
            COORD_POWER_SYNC: begin
                if (is_coordinator && (!coord_valid || coord_ready[MODULE_ID])) begin
                    coord_valid <= 1'b1;
                    tx_msg.msg_type <= MSG_POWER_ACK;
                    tx_msg.source_id <= MODULE_ID;
                    tx_msg.sequence <= sync_sequence;
                    tx_msg.payload <= {14'h0, consensus_power_state};
                    coord_data <= tx_msg;
                    sync_sequence <= sync_sequence + 1;
                end
            end
            
            COORD_BANDWIDTH_SYNC: begin
                if (is_coordinator && (!coord_valid || coord_ready[MODULE_ID])) begin
                    coord_valid <= 1'b1;
                    tx_msg.msg_type <= MSG_BW_GRANT;
                    tx_msg.source_id <= MODULE_ID;
                    tx_msg.sequence <= sync_sequence;
                    tx_msg.payload <= {8'h0, allocated_bandwidth[MODULE_ID]};
                    coord_data <= tx_msg;
                    sync_sequence <= sync_sequence + 1;
                end
            end
            
            default: begin
                if (coord_ready[MODULE_ID]) begin
                    coord_valid <= 1'b0;
                end
            end
        endcase
    end
end

// ============================================================================
// Power Coordination Logic
// ============================================================================

generate
if (ENABLE_POWER_COORDINATION) begin : gen_power_coord

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        consensus_power_state <= PWR_L0;
        power_votes <= '0;
        power_coordination_active <= 1'b0;
        requested_power_states <= '{default: PWR_L0};
    end else begin
        if (coord_state == COORD_POWER_SYNC && is_coordinator) begin
            // Coordinator determines consensus power state
            logic [1:0] l0_votes, l1_votes, l2_votes, l3_votes;
            l0_votes = 2'h0; l1_votes = 2'h0; l2_votes = 2'h0; l3_votes = 2'h0;
            
            for (int i = 0; i < NUM_MODULES; i++) begin
                if (modules_discovered[i]) begin
                    case (requested_power_states[i])
                        PWR_L0: l0_votes = l0_votes + 1;
                        PWR_L1: l1_votes = l1_votes + 1;
                        PWR_L2: l2_votes = l2_votes + 1;
                        PWR_L3: l3_votes = l3_votes + 1;
                    endcase
                end
            end
            
            // Consensus: choose the most restrictive state with majority
            if (l3_votes > ($countones(modules_discovered) >> 1)) begin
                consensus_power_state <= PWR_L3;
            end else if (l2_votes > ($countones(modules_discovered) >> 1)) begin
                consensus_power_state <= PWR_L2;
            end else if (l1_votes > ($countones(modules_discovered) >> 1)) begin
                consensus_power_state <= PWR_L1;
            end else begin
                consensus_power_state <= PWR_L0;
            end
            
            power_coordination_active <= 1'b0;
        end else if (power_sync_req != power_state) begin
            power_coordination_active <= 1'b1;
            requested_power_states[MODULE_ID] <= power_sync_req;
        end
    end
end

assign coordinated_power_state = consensus_power_state;
assign power_sync_ack = !power_coordination_active && (coord_state == COORD_ACTIVE);

end else begin : gen_no_power_coord
    assign coordinated_power_state = power_state;
    assign power_sync_ack = 1'b1;
    always_comb power_coordination_active = 1'b0;
end
endgenerate

// ============================================================================
// Bandwidth Coordination Logic
// ============================================================================

generate
if (ENABLE_BANDWIDTH_SHARING) begin : gen_bandwidth_coord

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        allocated_bandwidth <= '{default: 8'h40}; // Default 25% each for 4 modules
        total_system_bandwidth <= 16'd1024; // 1024 Gbps total (example)
        bandwidth_coordination_active <= 1'b0;
    end else begin
        if (coord_state == COORD_BANDWIDTH_SYNC && is_coordinator) begin
            // Dynamic bandwidth allocation algorithm
            logic [15:0] total_requested;
            total_requested = 16'h0;
            
            // Calculate total requested bandwidth
            for (int i = 0; i < NUM_MODULES; i++) begin
                if (modules_discovered[i]) begin
                    total_requested = total_requested + requested_bandwidth[i];
                end
            end
            
            // Allocate bandwidth proportionally
            for (int i = 0; i < NUM_MODULES; i++) begin
                if (modules_discovered[i]) begin
                    if (total_requested > 0) begin
                        allocated_bandwidth[i] <= 
                            (requested_bandwidth[i] * 8'd255) / total_requested[7:0];
                    end else begin
                        allocated_bandwidth[i] <= 8'd64; // Equal share
                    end
                end else begin
                    allocated_bandwidth[i] <= 8'h0;
                end
            end
            
            bandwidth_coordination_active <= 1'b0;
        end else if (bandwidth_utilization > 8'd200) begin // High utilization threshold
            bandwidth_coordination_active <= 1'b1;
            requested_bandwidth[MODULE_ID] <= bandwidth_utilization;
        end
    end
end

// Bandwidth sharing output
always_comb begin
    for (int i = 0; i < NUM_MODULES; i++) begin
        bandwidth_share[i] = allocated_bandwidth[i];
    end
end

assign bandwidth_rebalance_req = bandwidth_coordination_active && is_coordinator;
assign load_balance_active = bandwidth_coordination_active;

end else begin : gen_no_bandwidth_coord
    always_comb begin
        for (int i = 0; i < NUM_MODULES; i++) begin
            bandwidth_share[i] = 8'h40; // Fixed 25% each
        end
    end
    assign bandwidth_rebalance_req = 1'b0;
    assign load_balance_active = 1'b0;
    always_comb bandwidth_coordination_active = 1'b0;
end
endgenerate

// ============================================================================
// Error Coordination and Isolation
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        error_alerts <= '0;
        isolated_modules <= '0;
        system_error_active <= 1'b0;
        error_recovery_active <= 1'b0;
    end else begin
        // Local error detection
        if (local_error) begin
            error_alerts[MODULE_ID] <= 1'b1;
            system_error_active <= 1'b1;
        end
        
        // System error handling
        if (coord_state == COORD_ERROR_HANDLE && is_coordinator) begin
            // Isolate modules with persistent errors
            for (int i = 0; i < NUM_MODULES; i++) begin
                if (error_alerts[i] && module_status[i].error_count > 4'd8) begin
                    isolated_modules[i] <= 1'b1;
                end
            end
            
            // Clear alerts for isolated modules
            error_alerts <= error_alerts & ~isolated_modules;
            
            if (error_alerts == '0) begin
                system_error_active <= 1'b0;
                error_recovery_active <= 1'b1;
            end
        end
        
        // Recovery completion
        if (coord_state == COORD_ACTIVE && error_recovery_active) begin
            error_recovery_active <= 1'b0;
        end
    end
end

// ============================================================================
// Synchronization Timer and Timeout Management
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        sync_timer <= 16'h0;
        sync_timeout <= 1'b0;
        sync_in_progress <= 1'b0;
        coordination_cycles <= 8'h0;
        successful_coordinations <= 8'h0;
        failed_coordinations <= 8'h0;
    end else begin
        sync_timer <= sync_timer + 1;
        
        // State-specific timeout detection
        case (coord_state)
            COORD_DISCOVERY: begin
                sync_timeout <= (sync_timer > COORDINATION_TIMEOUT);
                sync_in_progress <= 1'b0;
            end
            
            COORD_NEGOTIATION: begin
                sync_timeout <= (sync_timer > COORDINATION_TIMEOUT);
                sync_in_progress <= 1'b0;
            end
            
            COORD_SYNC_INIT: begin
                sync_timeout <= (sync_timer > (COORDINATION_TIMEOUT >> 1));
                sync_in_progress <= 1'b1;
            end
            
            COORD_ACTIVE: begin
                sync_timeout <= 1'b0;
                sync_in_progress <= 1'b0;
                if (coord_state != coord_state_next) begin
                    coordination_cycles <= coordination_cycles + 1;
                end
            end
            
            default: begin
                sync_timeout <= (sync_timer > (COORDINATION_TIMEOUT << 1));
                sync_in_progress <= 1'b0;
            end
        endcase
        
        // Reset timer on state changes
        if (coord_state != coord_state_next) begin
            sync_timer <= 16'h0;
            if (coord_state_next == COORD_ACTIVE) begin
                successful_coordinations <= successful_coordinations + 1;
            end else if (coord_state_next == COORD_ERROR) begin
                failed_coordinations <= failed_coordinations + 1;
            end
        end
    end
end

// ============================================================================
// Performance Monitoring
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        system_perf_accumulator <= 16'h0;
    end else begin
        // Accumulate performance across all active modules
        system_perf_accumulator <= performance_counters;
        for (int i = 0; i < NUM_MODULES; i++) begin
            if (modules_active[i]) begin
                system_perf_accumulator <= system_perf_accumulator + module_status[i].bandwidth_util;
            end
        end
    end
end

// ============================================================================
// Output Assignments
// ============================================================================

assign multi_module_active = (coord_state == COORD_ACTIVE) && ($countones(modules_discovered) > 1);
assign coordinator_role = is_coordinator;
assign coordination_phase = coord_state[1:0];

// Module sync outputs
always_comb begin
    for (int i = 0; i < NUM_MODULES; i++) begin
        if (i == MODULE_ID) begin
            module_sync_valid[i] = coord_valid;
            module_sync_data[i] = coord_data;
        end else begin
            module_sync_valid[i] = coord_valid_in[i];
            module_sync_data[i] = coord_data_in[i];
        end
        coord_ready_out[i] = (coord_state == COORD_ACTIVE) || (coord_state == COORD_RESET);
    end
end

assign system_performance = system_perf_accumulator;
assign system_error = system_error_active;
assign error_isolation_active = |isolated_modules;

// Debug outputs
assign coordination_debug = {
    coord_state,
    4'h0,
    is_coordinator,
    coordinator_election_active,
    power_coordination_active,
    bandwidth_coordination_active,
    system_error_active,
    error_recovery_active,
    sync_in_progress,
    sync_timeout,
    modules_discovered,
    modules_active
};

assign module_status_vector = {
    modules_discovered,
    modules_active,
    modules_error,
    sync_in_progress
};

assign coordination_statistics = {
    successful_coordinations,
    failed_coordinations
};

endmodule