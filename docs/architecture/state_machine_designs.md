# UCIe State Machine Designs

## Overview
This document provides detailed state machine designs for the UCIe controller, covering link training, power management, error recovery, and protocol-specific state machines. These are the core control logic elements that coordinate all UCIe operations.

## State Machine Hierarchy

```
┌─────────────────────────────────────────────────────────────────────┐
│                    UCIe State Machine Architecture                  │
│                                                                     │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │ Link Training   │    │ Power Management│    │ Error Recovery  │ │
│  │ State Machine   │◄──►│ State Machine   │◄──►│ State Machine   │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│           │                       │                       │        │
│           ▼                       ▼                       ▼        │
│  ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│  │ Protocol State  │    │ Lane Management │    │ Retry Logic     │ │
│  │ Machines        │    │ State Machine   │    │ State Machine   │ │
│  └─────────────────┘    └─────────────────┘    └─────────────────┘ │
└─────────────────────────────────────────────────────────────────────┘
```

## 1. Link Training State Machine

### 1.1 Main Link Training States

```systemverilog
typedef enum logic [4:0] {
    LT_RESET            = 5'h00,
    LT_SBINIT           = 5'h01,
    LT_MBINIT_PARAM     = 5'h02,
    LT_MBINIT_CAL       = 5'h03,
    LT_MBINIT_REPAIRCLK = 5'h04,
    LT_MBINIT_REPAIRVAL = 5'h05,
    LT_MBINIT_REVERSALMB = 5'h06,
    LT_MBINIT_REPAIRMB  = 5'h07,
    LT_MBTRAIN_VALVREF  = 5'h08,
    LT_MBTRAIN_DATAVREF = 5'h09,
    LT_MBTRAIN_SPEEDIDLE = 5'h0A,
    LT_MBTRAIN_TXSELFCAL = 5'h0B,
    LT_MBTRAIN_RXCLKCAL = 5'h0C,
    LT_MBTRAIN_VALTRAINCENTER = 5'h0D,
    LT_MBTRAIN_VALTRAINVREF = 5'h0E,
    LT_MBTRAIN_DATATRAINCENTER1 = 5'h0F,
    LT_MBTRAIN_DATATRAINVREF = 5'h10,
    LT_MBTRAIN_RXDESKEW = 5'h11,
    LT_MBTRAIN_DATATRAINCENTER2 = 5'h12,
    LT_MBTRAIN_LINKSPEED = 5'h13,
    LT_MBTRAIN_REPAIR   = 5'h14,
    LT_LINKINIT         = 5'h15,
    LT_ACTIVE           = 5'h16,
    LT_L1               = 5'h17,
    LT_L2               = 5'h18,
    LT_PHYRETRAIN       = 5'h19,
    LT_TRAINERROR       = 5'h1A,
    LT_DISABLED         = 5'h1F
} link_training_state_t;
```

### 1.2 Link Training State Machine Implementation

```systemverilog
module ucie_link_training_fsm #(
    parameter NUM_MODULES = 1,
    parameter MODULE_WIDTH = 64
) (
    input  logic                    clk,
    input  logic                    resetn,
    input  logic                    cold_reset,
    
    // Control Inputs
    input  logic                    start_training,
    input  logic                    force_retrain,
    input  logic                    remote_retrain_req,
    
    // Physical Layer Status
    input  logic                    phy_ready,
    input  logic [NUM_MODULES-1:0]  module_ready,
    input  logic                    sideband_ready,
    input  logic                    mainband_ready,
    
    // Training Results
    input  logic                    param_exchange_done,
    input  logic                    param_exchange_error,
    input  logic                    calibration_done,
    input  logic                    calibration_error,
    input  logic                    repair_done,
    input  logic                    repair_error,
    input  logic                    training_done,
    input  logic                    training_error,
    
    // State Machine Outputs
    output link_training_state_t    current_state,
    output logic                    training_complete,
    output logic                    training_failed,
    output logic                    link_active,
    
    // Training Control Outputs
    output logic                    start_param_exchange,
    output logic                    start_calibration,
    output logic                    start_repair,
    output logic                    start_phy_training,
    output logic                    enable_mainband,
    
    // Timeout Configuration
    input  logic [31:0]             timeout_cycles [32],
    
    // Status and Debug
    output logic [31:0]             state_time_counter,
    output logic [15:0]             retrain_count,
    output logic [7:0]              last_error_code
);

// Internal signals
link_training_state_t next_state;
logic [31:0] timeout_counter;
logic timeout_expired;
logic state_change;

// State register
always_ff @(posedge clk or negedge resetn) begin
    if (!resetn || cold_reset) begin
        current_state <= LT_RESET;
        timeout_counter <= 0;
        state_time_counter <= 0;
        retrain_count <= 0;
    end else begin
        if (state_change) begin
            current_state <= next_state;
            timeout_counter <= 0;
            state_time_counter <= 0;
        end else begin
            timeout_counter <= timeout_counter + 1;
            state_time_counter <= state_time_counter + 1;
        end
        
        if (current_state == LT_PHYRETRAIN) begin
            retrain_count <= retrain_count + 1;
        end
    end
end

// Timeout detection
always_comb begin
    timeout_expired = (timeout_counter >= timeout_cycles[current_state]);
end

// State transition logic
always_comb begin
    next_state = current_state;
    state_change = 1'b0;
    
    case (current_state)
        LT_RESET: begin
            if (phy_ready && start_training) begin
                next_state = LT_SBINIT;
                state_change = 1'b1;
            end
        end
        
        LT_SBINIT: begin
            if (sideband_ready) begin
                next_state = LT_MBINIT_PARAM;
                state_change = 1'b1;
            end else if (timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBINIT_PARAM: begin
            if (param_exchange_done) begin
                next_state = LT_MBINIT_CAL;
                state_change = 1'b1;
            end else if (param_exchange_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBINIT_CAL: begin
            if (calibration_done) begin
                next_state = LT_MBINIT_REPAIRCLK;
                state_change = 1'b1;
            end else if (calibration_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBINIT_REPAIRCLK: begin
            if (repair_done) begin
                next_state = LT_MBINIT_REPAIRVAL;
                state_change = 1'b1;
            end else if (repair_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBINIT_REPAIRVAL: begin
            if (repair_done) begin
                next_state = LT_MBINIT_REVERSALMB;
                state_change = 1'b1;
            end else if (repair_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBINIT_REVERSALMB: begin
            if (repair_done) begin
                next_state = LT_MBINIT_REPAIRMB;
                state_change = 1'b1;
            end else if (repair_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBINIT_REPAIRMB: begin
            if (repair_done) begin
                next_state = LT_MBTRAIN_VALVREF;
                state_change = 1'b1;
            end else if (repair_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_VALVREF: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_DATAVREF;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_DATAVREF: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_SPEEDIDLE;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_SPEEDIDLE: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_TXSELFCAL;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_TXSELFCAL: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_RXCLKCAL;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_RXCLKCAL: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_VALTRAINCENTER;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_VALTRAINCENTER: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_VALTRAINVREF;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_VALTRAINVREF: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_DATATRAINCENTER1;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_DATATRAINCENTER1: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_DATATRAINVREF;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_DATATRAINVREF: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_RXDESKEW;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_RXDESKEW: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_DATATRAINCENTER2;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_DATATRAINCENTER2: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_LINKSPEED;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_LINKSPEED: begin
            if (training_done) begin
                next_state = LT_MBTRAIN_REPAIR;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_MBTRAIN_REPAIR: begin
            if (repair_done) begin
                next_state = LT_LINKINIT;
                state_change = 1'b1;
            end else if (repair_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_LINKINIT: begin
            if (mainband_ready && (&module_ready)) begin
                next_state = LT_ACTIVE;
                state_change = 1'b1;
            end else if (timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_ACTIVE: begin
            if (force_retrain || remote_retrain_req) begin
                next_state = LT_PHYRETRAIN;
                state_change = 1'b1;
            end
        end
        
        LT_PHYRETRAIN: begin
            if (training_done) begin
                next_state = LT_ACTIVE;
                state_change = 1'b1;
            end else if (training_error || timeout_expired) begin
                next_state = LT_TRAINERROR;
                state_change = 1'b1;
            end
        end
        
        LT_TRAINERROR: begin
            // Stay in error state until reset
            if (cold_reset) begin
                next_state = LT_RESET;
                state_change = 1'b1;
            end
        end
        
        default: begin
            next_state = LT_RESET;
            state_change = 1'b1;
        end
    endcase
end

// Output assignments
assign training_complete = (current_state == LT_ACTIVE);
assign training_failed = (current_state == LT_TRAINERROR);
assign link_active = (current_state == LT_ACTIVE);

assign start_param_exchange = (current_state == LT_MBINIT_PARAM);
assign start_calibration = (current_state == LT_MBINIT_CAL);
assign start_repair = (current_state == LT_MBINIT_REPAIRCLK) ||
                     (current_state == LT_MBINIT_REPAIRVAL) ||
                     (current_state == LT_MBINIT_REVERSALMB) ||
                     (current_state == LT_MBINIT_REPAIRMB) ||
                     (current_state == LT_MBTRAIN_REPAIR);

assign start_phy_training = (current_state >= LT_MBTRAIN_VALVREF) &&
                           (current_state <= LT_MBTRAIN_LINKSPEED);

assign enable_mainband = (current_state >= LT_MBINIT_CAL);

endmodule
```

## 2. Power Management State Machine

### 2.1 Power Management States

```systemverilog
typedef enum logic [2:0] {
    PM_L0           = 3'h0,  // Active
    PM_L1_ENTRY     = 3'h1,  // Entering L1
    PM_L1           = 3'h2,  // L1 Standby
    PM_L1_EXIT      = 3'h3,  // Exiting L1
    PM_L2_ENTRY     = 3'h4,  // Entering L2
    PM_L2           = 3'h5,  // L2 Sleep
    PM_L2_EXIT      = 3'h6,  // Exiting L2
    PM_DISABLED     = 3'h7   // Disabled
} power_mgmt_state_t;
```

### 2.2 Power Management State Machine

```systemverilog
module ucie_power_mgmt_fsm (
    input  logic                clk,
    input  logic                aux_clk,
    input  logic                resetn,
    
    // Power Management Requests
    input  logic                l1_entry_req,
    input  logic                l2_entry_req,
    input  logic                l0_wake_req,
    input  logic                remote_pm_req,
    input  logic [2:0]          remote_pm_state,
    
    // Protocol Layer Status
    input  logic                proto_idle,
    input  logic                proto_active,
    input  logic                outstanding_requests,
    
    // Physical Layer Interface
    output logic                phy_l1_enable,
    output logic                phy_l2_enable,
    output logic                phy_wake_enable,
    input  logic                phy_l1_ready,
    input  logic                phy_l2_ready,
    input  logic                phy_wake_detected,
    
    // Clock and Power Control
    output logic                main_clock_gate,
    output logic                aux_power_only,
    output logic                pll_power_down,
    
    // State Machine Outputs
    output power_mgmt_state_t   current_state,
    output logic                pm_ack,
    output logic                pm_error,
    
    // Configuration
    input  logic [31:0]         l1_idle_timeout,
    input  logic [31:0]         l2_idle_timeout,
    input  logic [31:0]         wake_timeout,
    input  logic                auto_l1_enable,
    input  logic                auto_l2_enable
);

// Internal signals
power_mgmt_state_t next_state;
logic [31:0] idle_counter;
logic [31:0] timeout_counter;
logic state_change;
logic idle_timeout_l1;
logic idle_timeout_l2;
logic wake_timeout_expired;

// State register
always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        current_state <= PM_L0;
        idle_counter <= 0;
        timeout_counter <= 0;
    end else begin
        if (state_change) begin
            current_state <= next_state;
            timeout_counter <= 0;
        end else begin
            timeout_counter <= timeout_counter + 1;
        end
        
        // Idle counter for automatic power management
        if (proto_idle && !outstanding_requests) begin
            idle_counter <= idle_counter + 1;
        end else begin
            idle_counter <= 0;
        end
    end
end

// Timeout detection
assign idle_timeout_l1 = (idle_counter >= l1_idle_timeout) && auto_l1_enable;
assign idle_timeout_l2 = (idle_counter >= l2_idle_timeout) && auto_l2_enable;
assign wake_timeout_expired = (timeout_counter >= wake_timeout);

// State transition logic
always_comb begin
    next_state = current_state;
    state_change = 1'b0;
    
    case (current_state)
        PM_L0: begin
            if (l1_entry_req || idle_timeout_l1) begin
                next_state = PM_L1_ENTRY;
                state_change = 1'b1;
            end else if (l2_entry_req || idle_timeout_l2) begin
                next_state = PM_L2_ENTRY;
                state_change = 1'b1;
            end
        end
        
        PM_L1_ENTRY: begin
            if (phy_l1_ready) begin
                next_state = PM_L1;
                state_change = 1'b1;
            end else if (proto_active || l0_wake_req) begin
                next_state = PM_L0;
                state_change = 1'b1;
            end
        end
        
        PM_L1: begin
            if (proto_active || l0_wake_req || phy_wake_detected) begin
                next_state = PM_L1_EXIT;
                state_change = 1'b1;
            end else if (l2_entry_req || idle_timeout_l2) begin
                next_state = PM_L2_ENTRY;
                state_change = 1'b1;
            end
        end
        
        PM_L1_EXIT: begin
            if (!phy_l1_ready) begin
                next_state = PM_L0;
                state_change = 1'b1;
            end else if (wake_timeout_expired) begin
                next_state = PM_L0;  // Force exit on timeout
                state_change = 1'b1;
            end
        end
        
        PM_L2_ENTRY: begin
            if (phy_l2_ready) begin
                next_state = PM_L2;
                state_change = 1'b1;
            end else if (proto_active || l0_wake_req) begin
                next_state = PM_L0;
                state_change = 1'b1;
            end
        end
        
        PM_L2: begin
            if (l0_wake_req || phy_wake_detected) begin
                next_state = PM_L2_EXIT;
                state_change = 1'b1;
            end
        end
        
        PM_L2_EXIT: begin
            if (!phy_l2_ready) begin
                next_state = PM_L0;
                state_change = 1'b1;
            end else if (wake_timeout_expired) begin
                next_state = PM_L0;  // Force exit on timeout
                state_change = 1'b1;
            end
        end
        
        default: begin
            next_state = PM_L0;
            state_change = 1'b1;
        end
    endcase
end

// Output assignments
assign phy_l1_enable = (current_state == PM_L1_ENTRY) || (current_state == PM_L1);
assign phy_l2_enable = (current_state == PM_L2_ENTRY) || (current_state == PM_L2);
assign phy_wake_enable = (current_state == PM_L1_EXIT) || (current_state == PM_L2_EXIT);

assign main_clock_gate = (current_state == PM_L1) || (current_state == PM_L2);
assign aux_power_only = (current_state == PM_L2);
assign pll_power_down = (current_state == PM_L2);

assign pm_ack = state_change;
assign pm_error = wake_timeout_expired;

endmodule
```

## 3. Error Recovery State Machine

### 3.1 Error Recovery States

```systemverilog
typedef enum logic [3:0] {
    ERR_IDLE            = 4'h0,
    ERR_DETECTED        = 4'h1,
    ERR_ANALYSIS        = 4'h2,
    ERR_RETRY           = 4'h3,
    ERR_LANE_REPAIR     = 4'h4,
    ERR_SPEED_DEGRADE   = 4'h5,
    ERR_WIDTH_DEGRADE   = 4'h6,
    ERR_LINK_RETRAIN    = 4'h7,
    ERR_LINK_RESET      = 4'h8,
    ERR_RECOVERY_DONE   = 4'h9,
    ERR_UNRECOVERABLE   = 4'hF
} error_recovery_state_t;
```

### 3.2 Error Recovery State Machine

```systemverilog
module ucie_error_recovery_fsm (
    input  logic                    clk,
    input  logic                    resetn,
    
    // Error Inputs
    input  logic                    crc_error,
    input  logic                    timeout_error,
    input  logic                    lane_error,
    input  logic                    protocol_error,
    input  logic [7:0]              error_count,
    input  logic [7:0]              error_severity,
    
    // Recovery Capabilities
    input  logic                    retry_capable,
    input  logic                    repair_capable,
    input  logic                    degrade_capable,
    input  logic                    retrain_capable,
    
    // Recovery Results
    input  logic                    retry_success,
    input  logic                    repair_success,
    input  logic                    degrade_success,
    input  logic                    retrain_success,
    
    // Recovery Actions
    output logic                    start_retry,
    output logic                    start_repair,
    output logic                    start_degrade,
    output logic                    start_retrain,
    output logic                    start_reset,
    
    // State Machine Status
    output error_recovery_state_t   current_state,
    output logic                    recovery_active,
    output logic                    recovery_success,
    output logic                    recovery_failed,
    
    // Configuration
    input  logic [7:0]              max_retry_count,
    input  logic [7:0]              error_threshold,
    input  logic [31:0]             recovery_timeout
);

// Internal signals
error_recovery_state_t next_state;
logic [7:0] retry_count;
logic [31:0] recovery_timer;
logic state_change;
logic recovery_timeout_expired;
logic error_threshold_exceeded;

// State register
always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        current_state <= ERR_IDLE;
        retry_count <= 0;
        recovery_timer <= 0;
    end else begin
        if (state_change) begin
            current_state <= next_state;
            recovery_timer <= 0;
            if (current_state == ERR_IDLE) begin
                retry_count <= 0;
            end
        end else begin
            recovery_timer <= recovery_timer + 1;
        end
        
        if (current_state == ERR_RETRY) begin
            retry_count <= retry_count + 1;
        end
    end
end

// Error analysis
assign error_threshold_exceeded = (error_count >= error_threshold);
assign recovery_timeout_expired = (recovery_timer >= recovery_timeout);

// State transition logic
always_comb begin
    next_state = current_state;
    state_change = 1'b0;
    
    case (current_state)
        ERR_IDLE: begin
            if (crc_error || timeout_error || lane_error || protocol_error) begin
                next_state = ERR_DETECTED;
                state_change = 1'b1;
            end
        end
        
        ERR_DETECTED: begin
            next_state = ERR_ANALYSIS;
            state_change = 1'b1;
        end
        
        ERR_ANALYSIS: begin
            if (error_severity <= 2 && retry_capable && retry_count < max_retry_count) begin
                next_state = ERR_RETRY;
                state_change = 1'b1;
            end else if (lane_error && repair_capable) begin
                next_state = ERR_LANE_REPAIR;
                state_change = 1'b1;
            end else if (error_threshold_exceeded && degrade_capable) begin
                if (timeout_error || error_severity >= 6) begin
                    next_state = ERR_SPEED_DEGRADE;
                    state_change = 1'b1;
                end else begin
                    next_state = ERR_WIDTH_DEGRADE;
                    state_change = 1'b1;
                end
            end else if (retrain_capable) begin
                next_state = ERR_LINK_RETRAIN;
                state_change = 1'b1;
            end else begin
                next_state = ERR_LINK_RESET;
                state_change = 1'b1;
            end
        end
        
        ERR_RETRY: begin
            if (retry_success) begin
                next_state = ERR_RECOVERY_DONE;
                state_change = 1'b1;
            end else if (recovery_timeout_expired || retry_count >= max_retry_count) begin
                next_state = ERR_ANALYSIS;
                state_change = 1'b1;
            end
        end
        
        ERR_LANE_REPAIR: begin
            if (repair_success) begin
                next_state = ERR_RECOVERY_DONE;
                state_change = 1'b1;
            end else if (recovery_timeout_expired) begin
                next_state = ERR_ANALYSIS;
                state_change = 1'b1;
            end
        end
        
        ERR_SPEED_DEGRADE: begin
            if (degrade_success) begin
                next_state = ERR_RECOVERY_DONE;
                state_change = 1'b1;
            end else if (recovery_timeout_expired) begin
                next_state = ERR_ANALYSIS;
                state_change = 1'b1;
            end
        end
        
        ERR_WIDTH_DEGRADE: begin
            if (degrade_success) begin
                next_state = ERR_RECOVERY_DONE;
                state_change = 1'b1;
            end else if (recovery_timeout_expired) begin
                next_state = ERR_ANALYSIS;
                state_change = 1'b1;
            end
        end
        
        ERR_LINK_RETRAIN: begin
            if (retrain_success) begin
                next_state = ERR_RECOVERY_DONE;
                state_change = 1'b1;
            end else if (recovery_timeout_expired) begin
                next_state = ERR_LINK_RESET;
                state_change = 1'b1;
            end
        end
        
        ERR_LINK_RESET: begin
            next_state = ERR_UNRECOVERABLE;
            state_change = 1'b1;
        end
        
        ERR_RECOVERY_DONE: begin
            next_state = ERR_IDLE;
            state_change = 1'b1;
        end
        
        ERR_UNRECOVERABLE: begin
            // Stay in unrecoverable state until system reset
        end
        
        default: begin
            next_state = ERR_IDLE;
            state_change = 1'b1;
        end
    endcase
end

// Output assignments
assign start_retry = (current_state == ERR_RETRY);
assign start_repair = (current_state == ERR_LANE_REPAIR);
assign start_degrade = (current_state == ERR_SPEED_DEGRADE) || 
                      (current_state == ERR_WIDTH_DEGRADE);
assign start_retrain = (current_state == ERR_LINK_RETRAIN);
assign start_reset = (current_state == ERR_LINK_RESET);

assign recovery_active = (current_state != ERR_IDLE) && 
                        (current_state != ERR_RECOVERY_DONE) &&
                        (current_state != ERR_UNRECOVERABLE);
assign recovery_success = (current_state == ERR_RECOVERY_DONE);
assign recovery_failed = (current_state == ERR_UNRECOVERABLE);

endmodule
```

## 4. Protocol-Specific State Machines

### 4.1 CXL Protocol State Machine

```systemverilog
typedef enum logic [3:0] {
    CXL_RESET           = 4'h0,
    CXL_INIT            = 4'h1,
    CXL_READY           = 4'h2,
    CXL_ACTIVE          = 4'h3,
    CXL_IO_ACTIVE       = 4'h4,
    CXL_CACHE_ACTIVE    = 4'h5,
    CXL_MEM_ACTIVE      = 4'h6,
    CXL_ERROR           = 4'h7,
    CXL_DISABLED        = 4'hF
} cxl_protocol_state_t;

module ucie_cxl_protocol_fsm (
    input  logic                clk,
    input  logic                resetn,
    
    // Link Status
    input  logic                link_active,
    input  logic                link_error,
    
    // CXL Configuration
    input  logic                cxl_io_enable,
    input  logic                cxl_cache_enable,
    input  logic                cxl_mem_enable,
    
    // Protocol Status
    input  logic                io_ready,
    input  logic                cache_ready,
    input  logic                mem_ready,
    
    // Traffic Activity
    input  logic                io_traffic,
    input  logic                cache_traffic,
    input  logic                mem_traffic,
    
    // State Machine Outputs
    output cxl_protocol_state_t current_state,
    output logic                cxl_active,
    output logic                io_stack_enable,
    output logic                cache_stack_enable,
    output logic                mem_stack_enable
);

// State machine implementation
cxl_protocol_state_t next_state;
logic state_change;

always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        current_state <= CXL_RESET;
    end else if (state_change) begin
        current_state <= next_state;
    end
end

always_comb begin
    next_state = current_state;
    state_change = 1'b0;
    
    case (current_state)
        CXL_RESET: begin
            if (link_active) begin
                next_state = CXL_INIT;
                state_change = 1'b1;
            end
        end
        
        CXL_INIT: begin
            if (cxl_io_enable && io_ready) begin
                next_state = CXL_READY;
                state_change = 1'b1;
            end else if (link_error) begin
                next_state = CXL_ERROR;
                state_change = 1'b1;
            end
        end
        
        CXL_READY: begin
            if (io_traffic || cache_traffic || mem_traffic) begin
                next_state = CXL_ACTIVE;
                state_change = 1'b1;
            end else if (link_error) begin
                next_state = CXL_ERROR;
                state_change = 1'b1;
            end
        end
        
        CXL_ACTIVE: begin
            if (io_traffic && !cache_traffic && !mem_traffic) begin
                next_state = CXL_IO_ACTIVE;
                state_change = 1'b1;
            end else if (!io_traffic && cache_traffic && !mem_traffic) begin
                next_state = CXL_CACHE_ACTIVE;
                state_change = 1'b1;
            end else if (!io_traffic && !cache_traffic && mem_traffic) begin
                next_state = CXL_MEM_ACTIVE;
                state_change = 1'b1;
            end else if (link_error) begin
                next_state = CXL_ERROR;
                state_change = 1'b1;
            end
        end
        
        CXL_IO_ACTIVE,
        CXL_CACHE_ACTIVE,
        CXL_MEM_ACTIVE: begin
            if (!io_traffic && !cache_traffic && !mem_traffic) begin
                next_state = CXL_READY;
                state_change = 1'b1;
            end else if (io_traffic || cache_traffic || mem_traffic) begin
                next_state = CXL_ACTIVE;
                state_change = 1'b1;
            end else if (link_error) begin
                next_state = CXL_ERROR;
                state_change = 1'b1;
            end
        end
        
        CXL_ERROR: begin
            if (!link_error) begin
                next_state = CXL_INIT;
                state_change = 1'b1;
            end
        end
        
        default: begin
            next_state = CXL_RESET;
            state_change = 1'b1;
        end
    endcase
end

// Output assignments
assign cxl_active = (current_state >= CXL_READY) && (current_state <= CXL_MEM_ACTIVE);
assign io_stack_enable = cxl_io_enable && cxl_active;
assign cache_stack_enable = cxl_cache_enable && cxl_active;
assign mem_stack_enable = cxl_mem_enable && cxl_active;

endmodule
```

## 5. Retry Logic State Machine

### 5.1 Retry States

```systemverilog
typedef enum logic [2:0] {
    RETRY_IDLE          = 3'h0,
    RETRY_WAIT_ACK      = 3'h1,
    RETRY_TIMEOUT       = 3'h2,
    RETRY_RETRANSMIT    = 3'h3,
    RETRY_ERROR         = 3'h4
} retry_state_t;
```

### 5.2 Retry Logic State Machine

```systemverilog
module ucie_retry_fsm #(
    parameter FLIT_WIDTH = 256,
    parameter SEQ_NUM_WIDTH = 16
) (
    input  logic                    clk,
    input  logic                    resetn,
    
    // Transmit Interface
    input  logic                    tx_flit_valid,
    input  logic [FLIT_WIDTH-1:0]  tx_flit_data,
    input  logic [SEQ_NUM_WIDTH-1:0] tx_seq_num,
    output logic                    tx_flit_ready,
    
    // ACK/NAK Interface
    input  logic                    ack_valid,
    input  logic [SEQ_NUM_WIDTH-1:0] ack_seq_num,
    input  logic                    nak_valid,
    input  logic [SEQ_NUM_WIDTH-1:0] nak_seq_num,
    
    // Retry Interface
    output logic                    retry_flit_valid,
    output logic [FLIT_WIDTH-1:0]  retry_flit_data,
    output logic [SEQ_NUM_WIDTH-1:0] retry_seq_num,
    
    // State Machine Status
    output retry_state_t            current_state,
    output logic                    retry_active,
    output logic                    retry_error,
    
    // Configuration
    input  logic [31:0]             retry_timeout_cycles,
    input  logic [7:0]              max_retry_count
);

// Internal signals
retry_state_t next_state;
logic [31:0] timeout_counter;
logic [7:0] retry_count;
logic [SEQ_NUM_WIDTH-1:0] expected_ack_seq;
logic state_change;
logic timeout_expired;
logic max_retries_exceeded;

// State register
always_ff @(posedge clk or negedge resetn) begin
    if (!resetn) begin
        current_state <= RETRY_IDLE;
        timeout_counter <= 0;
        retry_count <= 0;
        expected_ack_seq <= 0;
    end else begin
        if (state_change) begin
            current_state <= next_state;
            timeout_counter <= 0;
            if (current_state == RETRY_IDLE && tx_flit_valid) begin
                expected_ack_seq <= tx_seq_num;
            end
        end else begin
            timeout_counter <= timeout_counter + 1;
        end
        
        if (current_state == RETRY_RETRANSMIT) begin
            retry_count <= retry_count + 1;
        end else if (current_state == RETRY_IDLE) begin
            retry_count <= 0;
        end
    end
end

// Timeout and retry limit detection
assign timeout_expired = (timeout_counter >= retry_timeout_cycles);
assign max_retries_exceeded = (retry_count >= max_retry_count);

// State transition logic
always_comb begin
    next_state = current_state;
    state_change = 1'b0;
    
    case (current_state)
        RETRY_IDLE: begin
            if (tx_flit_valid) begin
                next_state = RETRY_WAIT_ACK;
                state_change = 1'b1;
            end
        end
        
        RETRY_WAIT_ACK: begin
            if (ack_valid && (ack_seq_num == expected_ack_seq)) begin
                next_state = RETRY_IDLE;
                state_change = 1'b1;
            end else if (nak_valid && (nak_seq_num == expected_ack_seq)) begin
                next_state = RETRY_RETRANSMIT;
                state_change = 1'b1;
            end else if (timeout_expired) begin
                next_state = RETRY_TIMEOUT;
                state_change = 1'b1;
            end
        end
        
        RETRY_TIMEOUT: begin
            if (!max_retries_exceeded) begin
                next_state = RETRY_RETRANSMIT;
                state_change = 1'b1;
            end else begin
                next_state = RETRY_ERROR;
                state_change = 1'b1;
            end
        end
        
        RETRY_RETRANSMIT: begin
            next_state = RETRY_WAIT_ACK;
            state_change = 1'b1;
        end
        
        RETRY_ERROR: begin
            // Stay in error state until reset or manual intervention
            next_state = RETRY_IDLE;
            state_change = 1'b1;
        end
        
        default: begin
            next_state = RETRY_IDLE;
            state_change = 1'b1;
        end
    endcase
end

// Output assignments
assign tx_flit_ready = (current_state == RETRY_IDLE);
assign retry_flit_valid = (current_state == RETRY_RETRANSMIT);
assign retry_flit_data = tx_flit_data;  // From retry buffer
assign retry_seq_num = expected_ack_seq;

assign retry_active = (current_state != RETRY_IDLE);
assign retry_error = (current_state == RETRY_ERROR);

endmodule
```

## 6. State Machine Integration

### 6.1 Top-Level State Coordinator

```systemverilog
module ucie_state_coordinator (
    input  logic                    clk,
    input  logic                    resetn,
    
    // Individual State Machine Interfaces
    ucie_link_training_fsm_if       link_training,
    ucie_power_mgmt_fsm_if          power_mgmt,
    ucie_error_recovery_fsm_if      error_recovery,
    ucie_protocol_fsm_if            protocol_fsm,
    
    // Coordination Logic
    output logic                    global_error,
    output logic                    system_ready,
    output logic                    coordination_active,
    
    // Priority and Arbitration
    input  logic [3:0]              state_priority [4],
    output logic [3:0]              active_state_machine
);

// State machine coordination logic
always_comb begin
    // Priority-based coordination
    if (error_recovery.recovery_active) begin
        active_state_machine = 4'h2;  // Error recovery has highest priority
    end else if (link_training.training_active) begin
        active_state_machine = 4'h0;  // Link training second priority
    end else if (power_mgmt.pm_active) begin
        active_state_machine = 4'h1;  // Power management third priority
    end else begin
        active_state_machine = 4'h3;  // Protocol state machines
    end
end

// Global status
assign global_error = error_recovery.recovery_failed || 
                     link_training.training_failed;
assign system_ready = link_training.training_complete && 
                     !error_recovery.recovery_active;
assign coordination_active = |{link_training.training_active,
                              power_mgmt.pm_active,
                              error_recovery.recovery_active};

endmodule
```

## Next Steps

1. **State Machine Verification**: Create comprehensive testbenches for each FSM
2. **Timing Analysis**: Validate state transition timing requirements
3. **Integration Testing**: Test state machine interactions and coordination
4. **Coverage Analysis**: Ensure all states and transitions are exercised
5. **Performance Optimization**: Optimize critical path timing in state machines