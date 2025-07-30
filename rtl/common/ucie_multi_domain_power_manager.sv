module ucie_multi_domain_power_manager #(
    parameter NUM_DOMAINS = 3,              // 0.6V, 0.8V, 1.0V domains
    parameter ENABLE_AVFS = 1,              // Adaptive Voltage/Frequency Scaling
    parameter POWER_BUDGET_MW = 5400,       // Total power budget in mW
    parameter THERMAL_THRESHOLD_C = 85      // Thermal throttling threshold
) (
    // Primary Clock Domain
    input  logic        clk,
    input  logic        rst_n,
    
    // Domain Enable Controls
    input  logic        domain_0v6_en,      // 0.6V domain enable
    input  logic        domain_0v8_en,      // 0.8V domain enable
    input  logic        domain_1v0_en,      // 1.0V domain enable
    output logic [2:0]  domain_status,      // Domain active status
    
    // Power State Interface
    input  ucie_pkg::power_state_t      current_power_state,
    output ucie_pkg::micro_power_state_t micro_power_state,
    input  logic                        transition_req,
    output logic                        transition_ack,
    
    // Thermal Management
    input  logic [7:0]  die_temperature,   // Die temperature in Celsius
    output logic        thermal_throttle,   // Thermal throttling active
    output logic [7:0]  thermal_status,    // Thermal management status
    
    // Performance Feedback
    input  logic [15:0] performance_metrics,
    output logic [15:0] system_performance,
    
    // Domain Voltage/Frequency Controls (AVFS)
    output logic [7:0]  domain_0v6_voltage, // 0.6V domain voltage control
    output logic [7:0]  domain_0v8_voltage, // 0.8V domain voltage control  
    output logic [7:0]  domain_1v0_voltage, // 1.0V domain voltage control
    output logic [7:0]  domain_0v6_freq,    // 0.6V domain frequency control
    output logic [7:0]  domain_0v8_freq,    // 0.8V domain frequency control
    output logic [7:0]  domain_1v0_freq,    // 1.0V domain frequency control
    
    // Power Consumption Monitoring
    output logic [15:0] power_consumption_mw, // Current power consumption
    output logic        power_budget_alarm,   // Power budget exceeded
    
    // Debug Interface
    output logic [31:0] debug_power_state,
    output logic [31:0] debug_thermal_state
);

import ucie_pkg::*;

// ============================================================================
// Internal Signals
// ============================================================================

// Power State Machine
typedef enum logic [3:0] {
    PWR_MGR_RESET    = 4'h0,
    PWR_MGR_INIT     = 4'h1, 
    PWR_MGR_L0_ACTIVE = 4'h2,
    PWR_MGR_L0_STANDBY = 4'h3,
    PWR_MGR_L0_LOW_POWER = 4'h4,
    PWR_MGR_L0_THROTTLED = 4'h5,
    PWR_MGR_L0_ADAPTIVE = 4'h6,
    PWR_MGR_L0_ML_OPT = 4'h7,
    PWR_MGR_L1       = 4'h8,
    PWR_MGR_L2       = 4'h9,
    PWR_MGR_L3       = 4'hA,
    PWR_MGR_TRANSITION = 4'hB,
    PWR_MGR_ERROR    = 4'hF
} power_mgr_state_t;

power_mgr_state_t current_state, next_state;

// Domain Control Registers
logic [2:0] domain_enable_reg;
logic [2:0] domain_active_reg;
logic [2:0] domain_ready_reg;

// AVFS Control
logic [7:0] voltage_target [2:0];  // Target voltages for each domain
logic [7:0] frequency_target [2:0]; // Target frequencies for each domain
logic [7:0] voltage_current [2:0]; // Current voltages
logic [7:0] frequency_current [2:0]; // Current frequencies

// Thermal Management
logic thermal_alarm;
logic thermal_warning;
logic [7:0] thermal_history [7:0];  // 8-sample thermal history
logic [2:0] thermal_hist_ptr;

// Power Monitoring
logic [15:0] estimated_power_mw;
logic [15:0] power_history [7:0];   // 8-sample power history
logic [2:0] power_hist_ptr;
logic power_over_budget;

// Transition Control
logic transition_in_progress;
logic [3:0] transition_timer;
logic transition_timeout;

// Performance Monitoring
logic [15:0] performance_filtered;
logic [7:0] performance_trend;

// ============================================================================
// Power Management State Machine
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_state <= PWR_MGR_RESET;
    end else begin
        current_state <= next_state;
    end
end

always_comb begin
    next_state = current_state;
    
    case (current_state)
        PWR_MGR_RESET: begin
            if (rst_n) begin
                next_state = PWR_MGR_INIT;
            end
        end
        
        PWR_MGR_INIT: begin
            if (domain_ready_reg == domain_enable_reg) begin
                next_state = PWR_MGR_L0_ACTIVE;
            end
        end
        
        PWR_MGR_L0_ACTIVE: begin
            if (transition_req) begin
                case (current_power_state)
                    PWR_L1: next_state = PWR_MGR_TRANSITION;
                    PWR_L2: next_state = PWR_MGR_TRANSITION;
                    PWR_L3: next_state = PWR_MGR_TRANSITION;
                    default: begin
                        // Micro-state transitions within L0
                        if (thermal_alarm) begin
                            next_state = PWR_MGR_L0_THROTTLED;
                        end else if (power_over_budget) begin
                            next_state = PWR_MGR_L0_LOW_POWER;
                        end else if (performance_trend < 50) begin
                            next_state = PWR_MGR_L0_STANDBY;
                        end else begin
                            next_state = PWR_MGR_L0_ADAPTIVE;
                        end
                    end
                endcase
            end else if (thermal_alarm) begin
                next_state = PWR_MGR_L0_THROTTLED;
            end else if (power_over_budget) begin
                next_state = PWR_MGR_L0_LOW_POWER;
            end
        end
        
        PWR_MGR_L0_STANDBY: begin
            if (performance_trend > 75) begin
                next_state = PWR_MGR_L0_ACTIVE;
            end else if (thermal_alarm) begin
                next_state = PWR_MGR_L0_THROTTLED;
            end else if (transition_req && current_power_state != PWR_L0) begin
                next_state = PWR_MGR_TRANSITION;
            end
        end
        
        PWR_MGR_L0_LOW_POWER: begin
            if (!power_over_budget && !thermal_alarm) begin
                next_state = PWR_MGR_L0_STANDBY;
            end else if (transition_req && current_power_state != PWR_L0) begin
                next_state = PWR_MGR_TRANSITION;
            end
        end
        
        PWR_MGR_L0_THROTTLED: begin
            if (!thermal_alarm) begin
                next_state = PWR_MGR_L0_STANDBY;
            end else if (die_temperature > (THERMAL_THRESHOLD_C + 10)) begin
                next_state = PWR_MGR_L1; // Emergency power reduction
            end
        end
        
        PWR_MGR_L0_ADAPTIVE: begin
            if (thermal_alarm) begin
                next_state = PWR_MGR_L0_THROTTLED;
            end else if (power_over_budget) begin
                next_state = PWR_MGR_L0_LOW_POWER;
            end else if (performance_trend < 25) begin
                next_state = PWR_MGR_L0_STANDBY;
            end else if (transition_req && current_power_state != PWR_L0) begin
                next_state = PWR_MGR_TRANSITION;
            end
        end
        
        PWR_MGR_L0_ML_OPT: begin
            // ML-optimized state with dynamic transitions
            if (thermal_alarm) begin
                next_state = PWR_MGR_L0_THROTTLED;
            end else if (transition_req && current_power_state != PWR_L0) begin
                next_state = PWR_MGR_TRANSITION;
            end
        end
        
        PWR_MGR_TRANSITION: begin
            if (transition_timeout) begin
                next_state = PWR_MGR_ERROR;
            end else if (!transition_in_progress) begin
                case (current_power_state)
                    PWR_L0: next_state = PWR_MGR_L0_ACTIVE;
                    PWR_L1: next_state = PWR_MGR_L1;
                    PWR_L2: next_state = PWR_MGR_L2;
                    PWR_L3: next_state = PWR_MGR_L3;
                    default: next_state = PWR_MGR_ERROR;
                endcase
            end
        end
        
        PWR_MGR_L1: begin
            if (transition_req && current_power_state != PWR_L1) begin
                next_state = PWR_MGR_TRANSITION;
            end
        end
        
        PWR_MGR_L2: begin
            if (transition_req && current_power_state != PWR_L2) begin
                next_state = PWR_MGR_TRANSITION;
            end
        end
        
        PWR_MGR_L3: begin
            if (transition_req && current_power_state != PWR_L3) begin
                next_state = PWR_MGR_TRANSITION;
            end
        end
        
        PWR_MGR_ERROR: begin
            if (!transition_req) begin
                next_state = PWR_MGR_INIT;
            end
        end
        
        default: next_state = PWR_MGR_ERROR;
    endcase
end

// ============================================================================
// Domain Control Logic
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        domain_enable_reg <= 3'b000;
        domain_active_reg <= 3'b000;
        domain_ready_reg <= 3'b000;
    end else begin
        domain_enable_reg <= {domain_1v0_en, domain_0v8_en, domain_0v6_en};
        
        // Domain activation logic
        for (int i = 0; i < 3; i++) begin
            if (domain_enable_reg[i] && !domain_active_reg[i]) begin
                domain_active_reg[i] <= 1'b1;
                domain_ready_reg[i] <= 1'b1; // Simplified - would include PLL lock, etc.
            end else if (!domain_enable_reg[i]) begin
                domain_active_reg[i] <= 1'b0;
                domain_ready_reg[i] <= 1'b0;
            end
        end
    end
end

assign domain_status = domain_active_reg;

// ============================================================================
// AVFS (Adaptive Voltage/Frequency Scaling) Control
// ============================================================================

generate
if (ENABLE_AVFS) begin : gen_avfs

    // Voltage/Frequency Target Calculation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            voltage_target[0] <= 8'h60;  // 0.6V nominal (96 = 0.6V * 160)
            voltage_target[1] <= 8'h80;  // 0.8V nominal (128 = 0.8V * 160)  
            voltage_target[2] <= 8'h100; // 1.0V nominal (160 = 1.0V * 160)
            frequency_target[0] <= 8'h40; // 25% frequency (64/256)
            frequency_target[1] <= 8'h80; // 50% frequency (128/256)
            frequency_target[2] <= 8'hFF; // 100% frequency (255/256)
        end else begin
            case (current_state)
                PWR_MGR_L0_ACTIVE: begin
                    voltage_target[0] <= 8'h60;  // Nominal voltages
                    voltage_target[1] <= 8'h80;
                    voltage_target[2] <= 8'h100;
                    frequency_target[0] <= 8'h80; // Higher frequency
                    frequency_target[1] <= 8'hC0;
                    frequency_target[2] <= 8'hFF;
                end
                
                PWR_MGR_L0_STANDBY: begin
                    voltage_target[0] <= 8'h58;  // Reduced voltages
                    voltage_target[1] <= 8'h78;
                    voltage_target[2] <= 8'hF0;
                    frequency_target[0] <= 8'h60; // Reduced frequency
                    frequency_target[1] <= 8'h80;
                    frequency_target[2] <= 8'hC0;
                end
                
                PWR_MGR_L0_LOW_POWER: begin
                    voltage_target[0] <= 8'h50;  // Low voltages
                    voltage_target[1] <= 8'h70;
                    voltage_target[2] <= 8'hE0;
                    frequency_target[0] <= 8'h40; // Low frequency
                    frequency_target[1] <= 8'h60;
                    frequency_target[2] <= 8'h80;
                end
                
                PWR_MGR_L0_THROTTLED: begin
                    voltage_target[0] <= 8'h48;  // Minimum safe voltages
                    voltage_target[1] <= 8'h68;
                    voltage_target[2] <= 8'hD0;
                    frequency_target[0] <= 8'h30; // Minimum frequency
                    frequency_target[1] <= 8'h50;
                    frequency_target[2] <= 8'h70;
                end
                
                PWR_MGR_L0_ADAPTIVE: begin
                    // Dynamic adjustment based on performance and thermal
                    if (thermal_warning) begin
                        voltage_target[0] <= voltage_target[0] - 1;
                        voltage_target[1] <= voltage_target[1] - 1;
                        voltage_target[2] <= voltage_target[2] - 1;
                    end else if (performance_trend > 90) begin
                        voltage_target[0] <= voltage_target[0] + 1;
                        voltage_target[1] <= voltage_target[1] + 1;
                        voltage_target[2] <= voltage_target[2] + 1;
                    end
                end
                
                default: begin
                    // Maintain current targets
                end
            endcase
        end
    end
    
    // Voltage/Frequency Tracking (simplified model)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            voltage_current <= '{8'h60, 8'h80, 8'h100};
            frequency_current <= '{8'h40, 8'h80, 8'hFF};
        end else begin
            for (int i = 0; i < 3; i++) begin
                // Slew rate limited tracking
                if (voltage_current[i] < voltage_target[i]) begin
                    voltage_current[i] <= voltage_current[i] + 1;
                end else if (voltage_current[i] > voltage_target[i]) begin
                    voltage_current[i] <= voltage_current[i] - 1;
                end
                
                if (frequency_current[i] < frequency_target[i]) begin
                    frequency_current[i] <= frequency_current[i] + 1;
                end else if (frequency_current[i] > frequency_target[i]) begin
                    frequency_current[i] <= frequency_current[i] - 1;
                end
            end
        end
    end
    
    // Output assignments
    assign domain_0v6_voltage = voltage_current[0];
    assign domain_0v8_voltage = voltage_current[1];
    assign domain_1v0_voltage = voltage_current[2];
    assign domain_0v6_freq = frequency_current[0];
    assign domain_0v8_freq = frequency_current[1];
    assign domain_1v0_freq = frequency_current[2];

end else begin : gen_no_avfs
    // Fixed voltage/frequency when AVFS disabled
    assign domain_0v6_voltage = 8'h60;
    assign domain_0v8_voltage = 8'h80;
    assign domain_1v0_voltage = 8'h100;
    assign domain_0v6_freq = 8'h80;
    assign domain_0v8_freq = 8'hC0;
    assign domain_1v0_freq = 8'hFF;
end
endgenerate

// ============================================================================
// Thermal Management
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        thermal_history <= '{default: 8'h0};
        thermal_hist_ptr <= 3'b000;
        thermal_alarm <= 1'b0;
        thermal_warning <= 1'b0;
    end else begin
        // Update thermal history
        thermal_history[thermal_hist_ptr] <= die_temperature;
        thermal_hist_ptr <= thermal_hist_ptr + 1;
        
        // Thermal threshold checking
        thermal_alarm <= (die_temperature > THERMAL_THRESHOLD_C);
        thermal_warning <= (die_temperature > (THERMAL_THRESHOLD_C - 10));
    end
end

assign thermal_throttle = thermal_alarm;
assign thermal_status = {thermal_alarm, thermal_warning, 2'b00, thermal_hist_ptr, 1'b0};

// ============================================================================
// Power Monitoring and Budget Management
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        power_history <= '{default: 16'h0};
        power_hist_ptr <= 3'b000;
        estimated_power_mw <= 16'h0;
        power_over_budget <= 1'b0;
    end else begin
        // Estimate power based on voltage, frequency, and activity
        estimated_power_mw <= 
            (voltage_current[0] * frequency_current[0] >> 6) +  // 0.6V domain
            (voltage_current[1] * frequency_current[1] >> 5) +  // 0.8V domain  
            (voltage_current[2] * frequency_current[2] >> 4);   // 1.0V domain
        
        // Update power history
        power_history[power_hist_ptr] <= estimated_power_mw;
        power_hist_ptr <= power_hist_ptr + 1;
        
        // Power budget checking
        power_over_budget <= (estimated_power_mw > POWER_BUDGET_MW);
    end
end

assign power_consumption_mw = estimated_power_mw;
assign power_budget_alarm = power_over_budget;

// ============================================================================
// Micro Power State Output
// ============================================================================

always_comb begin
    case (current_state)
        PWR_MGR_L0_ACTIVE:     micro_power_state = L0_ACTIVE;
        PWR_MGR_L0_STANDBY:    micro_power_state = L0_STANDBY;
        PWR_MGR_L0_LOW_POWER:  micro_power_state = L0_LOW_POWER;
        PWR_MGR_L0_THROTTLED:  micro_power_state = L0_THROTTLED;
        PWR_MGR_L0_ADAPTIVE:   micro_power_state = L0_ADAPTIVE;
        PWR_MGR_L0_ML_OPT:     micro_power_state = L0_ML_OPTIMIZED;
        default:               micro_power_state = L0_ACTIVE;
    endcase
end

// ============================================================================
// Transition Control
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        transition_in_progress <= 1'b0;
        transition_timer <= 4'h0;
        transition_timeout <= 1'b0;
    end else begin
        if (current_state == PWR_MGR_TRANSITION) begin
            transition_in_progress <= 1'b1;
            if (transition_timer == 4'hF) begin
                transition_timeout <= 1'b1;
            end else begin
                transition_timer <= transition_timer + 1;
            end
        end else begin
            transition_in_progress <= 1'b0;
            transition_timer <= 4'h0;
            transition_timeout <= 1'b0;
        end
    end
end

assign transition_ack = !transition_in_progress && (current_state != PWR_MGR_TRANSITION);

// ============================================================================
// Performance Monitoring and Trend Analysis
// ============================================================================

always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        performance_filtered <= 16'h0;
        performance_trend <= 8'h0;
    end else begin
        // Simple IIR filter for performance metrics
        performance_filtered <= (performance_filtered * 3 + performance_metrics) >> 2;
        
        // Calculate trend (simplified)
        performance_trend <= performance_filtered[15:8];
    end
end

assign system_performance = performance_filtered;

// ============================================================================
// Debug Outputs
// ============================================================================

assign debug_power_state = {
    4'h0, current_state,
    8'h0, micro_power_state,
    4'h0, transition_timer,
    3'b000, transition_in_progress, transition_timeout, thermal_alarm, thermal_warning, power_over_budget
};

assign debug_thermal_state = {
    die_temperature,
    thermal_status,
    estimated_power_mw
};

endmodule