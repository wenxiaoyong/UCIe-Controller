// Multi-Domain Clocking System for 128 Gbps UCIe Controller
// Manages multiple clock domains with voltage scaling and power optimization
// Supports 128 GHz bit rate, 64 GHz symbol rate, and 16 GHz quarter-rate clocks

module ucie_multi_domain_clocking
    import ucie_pkg::*;
#(
    parameter ENABLE_VOLTAGE_SCALING = 1,    // Enable adaptive voltage scaling
    parameter ENABLE_CLOCK_GATING = 1,       // Enable fine-grain clock gating
    parameter NUM_POWER_DOMAINS = 4,         // Number of power domains
    parameter PLL_REF_FREQ_MHZ = 100        // Reference clock frequency
) (
    // Reference Clock and Reset
    input  logic                ref_clk,           // 100 MHz reference clock
    input  logic                por_rst_n,        // Power-on reset
    
    // Configuration and Control
    input  logic                clocking_enable,
    input  data_rate_t          target_data_rate,  // Target data rate
    input  signaling_mode_t     signaling_mode,    // NRZ/PAM4
    input  logic [1:0]          power_mode,        // 00=full, 01=low, 10=sleep
    input  logic                thermal_throttle,  // Thermal throttling request
    
    // Generated Clock Outputs
    output logic                clk_bit_rate,      // 128 GHz for PAM4 bit processing
    output logic                clk_symbol_rate,   // 64 GHz for PAM4 symbols
    output logic                clk_quarter_rate,  // 16 GHz for quarter-rate processing
    output logic                clk_main,          // Main system clock (800 MHz)
    output logic                clk_sideband,      // 800 MHz sideband clock
    
    // Clock Domain Reset Outputs
    output logic                rst_bit_rate_n,
    output logic                rst_symbol_rate_n,
    output logic                rst_quarter_rate_n,
    output logic                rst_main_n,
    output logic                rst_sideband_n,
    
    // Voltage Scaling Interface
    output logic [7:0]          vdd_core_mv,       // Core voltage in mV
    output logic [7:0]          vdd_phy_mv,        // PHY voltage in mV
    output logic [7:0]          vdd_pll_mv,        // PLL voltage in mV
    input  logic [3:0]          voltage_ready,     // Voltage regulator ready
    
    // Power Domain Control
    output logic [NUM_POWER_DOMAINS-1:0] domain_enable,
    output logic [NUM_POWER_DOMAINS-1:0] domain_isolate,
    input  logic [NUM_POWER_DOMAINS-1:0] domain_ack,
    
    // Clock Gating Controls
    output logic                gate_bit_rate,     // Gate high-speed clocks when idle
    output logic                gate_symbol_rate,
    output logic                gate_quarter_rate,
    input  logic                protocol_active,   // Protocol layer activity
    input  logic                phy_active,        // PHY activity
    
    // Performance and Monitoring
    output logic [31:0]         pll_lock_time_us,  // PLL lock time in microseconds
    output logic [15:0]         power_consumption_mw, // Estimated power consumption
    output logic [7:0]          thermal_margin_c,  // Thermal margin in Celsius
    
    // Status and Debug
    output logic                all_clocks_stable,
    output logic                voltage_scaling_active,
    output logic [31:0]         clocking_status,
    output logic [15:0]         debug_counters [4]
);

    // PLL Configuration State Machine
    typedef enum logic [3:0] {
        CLK_RESET,
        CLK_POWER_UP,
        CLK_VOLTAGE_SCALE,
        CLK_PLL_CONFIG,
        CLK_PLL_LOCK_WAIT,
        CLK_CLOCK_ENABLE,
        CLK_ACTIVE,
        CLK_POWER_SAVE,
        CLK_THERMAL_LIMIT,
        CLK_ERROR_RECOVERY
    } clocking_state_t;
    
    clocking_state_t current_state, next_state;
    
    // PLL Control Registers
    logic [15:0] pll_main_multiplier;      // Main PLL multiplier
    logic [15:0] pll_high_speed_multiplier; // High-speed PLL multiplier
    logic [7:0]  pll_main_divider;         // Main PLL output divider
    logic [7:0]  pll_high_speed_divider;   // High-speed PLL divider
    logic [3:0]  pll_main_phase;          // Phase control
    logic [3:0]  pll_high_speed_phase;
    
    // Clock Enable Controls
    logic pll_main_enable, pll_high_speed_enable;
    logic pll_main_locked, pll_high_speed_locked;
    logic pll_main_reset_n, pll_high_speed_reset_n;
    
    // Voltage Scaling Control
    logic [7:0] target_vdd_core, target_vdd_phy, target_vdd_pll;
    logic [7:0] current_vdd_core, current_vdd_phy, current_vdd_pll;
    logic voltage_transition_active;
    logic [15:0] voltage_settle_counter;
    
    // Clock Gating Logic  
    logic [15:0] activity_counter;
    logic [7:0]  idle_threshold;
    logic        clocks_gated;
    
    // Performance Monitoring
    logic [31:0] pll_lock_counter;
    logic [15:0] power_estimation;
    logic [7:0]  temperature_estimate;
    
    // Reset Synchronizers
    logic [3:0] bit_rate_reset_sync;
    logic [3:0] symbol_rate_reset_sync;
    logic [3:0] quarter_rate_reset_sync;  
    logic [3:0] main_reset_sync;
    logic [3:0] sideband_reset_sync;
    
    // State Machine
    always_ff @(posedge ref_clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            current_state <= CLK_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            CLK_RESET: begin
                if (clocking_enable) begin
                    next_state = CLK_POWER_UP;
                end
            end
            
            CLK_POWER_UP: begin
                if (&domain_ack) begin // All power domains ready
                    next_state = CLK_VOLTAGE_SCALE;
                end
            end
            
            CLK_VOLTAGE_SCALE: begin
                if (ENABLE_VOLTAGE_SCALING) begin
                    if (&voltage_ready && !voltage_transition_active) begin
                        next_state = CLK_PLL_CONFIG;
                    end
                end else begin
                    next_state = CLK_PLL_CONFIG;
                end
            end
            
            CLK_PLL_CONFIG: begin
                next_state = CLK_PLL_LOCK_WAIT;
            end
            
            CLK_PLL_LOCK_WAIT: begin
                if (pll_main_locked && pll_high_speed_locked) begin
                    next_state = CLK_CLOCK_ENABLE;
                end else if (pll_lock_counter > 32'd100000) begin // Timeout
                    next_state = CLK_ERROR_RECOVERY;
                end
            end
            
            CLK_CLOCK_ENABLE: begin
                next_state = CLK_ACTIVE;
            end
            
            CLK_ACTIVE: begin
                if (thermal_throttle) begin
                    next_state = CLK_THERMAL_LIMIT;
                end else if (power_mode == 2'b01) begin
                    next_state = CLK_POWER_SAVE;
                end else if (power_mode == 2'b10) begin
                    next_state = CLK_POWER_UP; // Transition to sleep
                end
            end
            
            CLK_POWER_SAVE: begin
                if (power_mode == 2'b00) begin
                    next_state = CLK_ACTIVE;
                end else if (thermal_throttle) begin
                    next_state = CLK_THERMAL_LIMIT;
                end
            end
            
            CLK_THERMAL_LIMIT: begin
                if (!thermal_throttle) begin
                    next_state = CLK_ACTIVE;
                end
            end
            
            CLK_ERROR_RECOVERY: begin
                next_state = CLK_RESET;
            end
            
            default: begin
                next_state = CLK_RESET;
            end
        endcase
    end
    
    // PLL Configuration Logic
    always_ff @(posedge ref_clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            pll_main_multiplier <= 16'd8;        // 100 MHz * 8 = 800 MHz
            pll_high_speed_multiplier <= 16'd640; // 100 MHz * 640 = 64 GHz
            pll_main_divider <= 8'd1;
            pll_high_speed_divider <= 8'd1;
            pll_main_phase <= 4'h0;
            pll_high_speed_phase <= 4'h0;
            pll_main_enable <= 1'b0;
            pll_high_speed_enable <= 1'b0;
            pll_lock_counter <= 32'h0;
        end else begin
            case (current_state)
                CLK_PLL_CONFIG: begin
                    // Configure PLLs based on target data rate
                    case (target_data_rate)
                        DATA_RATE_128G: begin
                            if (signaling_mode == SIGNALING_PAM4) begin
                                pll_high_speed_multiplier <= 16'd640; // 64 GHz symbols
                            end else begin
                                pll_high_speed_multiplier <= 16'd1280; // 128 GHz NRZ
                            end
                        end
                        DATA_RATE_64G: begin
                            pll_high_speed_multiplier <= 16'd320;  // 32 GHz
                        end
                        DATA_RATE_32G: begin
                            pll_high_speed_multiplier <= 16'd160;  // 16 GHz
                        end
                        default: begin
                            pll_high_speed_multiplier <= 16'd160;  // Default 16 GHz
                        end
                    endcase
                    
                    // Enable PLLs
                    pll_main_enable <= 1'b1;
                    pll_high_speed_enable <= 1'b1;
                    pll_lock_counter <= 32'h0;
                end
                
                CLK_PLL_LOCK_WAIT: begin
                    pll_lock_counter <= pll_lock_counter + 1;
                end
                
                CLK_RESET, CLK_ERROR_RECOVERY: begin
                    pll_main_enable <= 1'b0;
                    pll_high_speed_enable <= 1'b0;
                    pll_lock_counter <= 32'h0;
                end
                
                default: begin
                    // Maintain current settings
                end
            endcase
        end
    end
    
    // Voltage Scaling Logic
    generate
        if (ENABLE_VOLTAGE_SCALING) begin : gen_voltage_scaling
            always_ff @(posedge ref_clk or negedge por_rst_n) begin
                if (!por_rst_n) begin
                    target_vdd_core <= 8'd900;    // 900mV default
                    target_vdd_phy <= 8'd1000;    // 1000mV default
                    target_vdd_pll <= 8'd1100;    // 1100mV default
                    current_vdd_core <= 8'd0;
                    current_vdd_phy <= 8'd0;
                    current_vdd_pll <= 8'd0;
                    voltage_transition_active <= 1'b0;
                    voltage_settle_counter <= 16'h0;
                end else begin
                    case (current_state)
                        CLK_VOLTAGE_SCALE: begin
                            // Set target voltages based on data rate and power mode
                            case ({target_data_rate, power_mode})
                                {DATA_RATE_128G, 2'b00}: begin // Full power 128G
                                    target_vdd_core <= 8'd1000;
                                    target_vdd_phy <= 8'd1200;
                                    target_vdd_pll <= 8'd1300;
                                end
                                {DATA_RATE_128G, 2'b01}: begin // Low power 128G
                                    target_vdd_core <= 8'd950;
                                    target_vdd_phy <= 8'd1100;
                                    target_vdd_pll <= 8'd1200;
                                end
                                {DATA_RATE_64G, 2'b00}: begin // Full power 64G
                                    target_vdd_core <= 8'd950;
                                    target_vdd_phy <= 8'd1100;
                                    target_vdd_pll <= 8'd1200;
                                end
                                {DATA_RATE_32G, 2'b00}: begin // Full power 32G
                                    target_vdd_core <= 8'd900;
                                    target_vdd_phy <= 8'd1000;
                                    target_vdd_pll <= 8'd1100;
                                end
                                default: begin // Low power default
                                    target_vdd_core <= 8'd850;
                                    target_vdd_phy <= 8'd950;
                                    target_vdd_pll <= 8'd1000;
                                end
                            endcase
                            
                            voltage_transition_active <= 1'b1;
                            voltage_settle_counter <= 16'h0;
                        end
                        
                        CLK_THERMAL_LIMIT: begin
                            // Reduce voltages for thermal throttling
                            target_vdd_core <= target_vdd_core - 8'd50;  // -50mV
                            target_vdd_phy <= target_vdd_phy - 8'd50;
                            target_vdd_pll <= target_vdd_pll - 8'd50;
                        end
                        
                        default: begin
                            if (voltage_transition_active) begin
                                voltage_settle_counter <= voltage_settle_counter + 1;
                                if (voltage_settle_counter > 16'd1000) begin // 10us settle time
                                    voltage_transition_active <= 1'b0;
                                    current_vdd_core <= target_vdd_core;
                                    current_vdd_phy <= target_vdd_phy;
                                    current_vdd_pll <= target_vdd_pll;
                                end
                            end
                        end
                    endcase
                end
            end
        end else begin : gen_no_voltage_scaling
            assign target_vdd_core = 8'd1000;  // Fixed 1V
            assign target_vdd_phy = 8'd1200;   // Fixed 1.2V
            assign target_vdd_pll = 8'd1300;   // Fixed 1.3V
            assign current_vdd_core = target_vdd_core;
            assign current_vdd_phy = target_vdd_phy;
            assign current_vdd_pll = target_vdd_pll;
            assign voltage_transition_active = 1'b0;
        end
    endgenerate
    
    // Clock Gating Logic
    generate
        if (ENABLE_CLOCK_GATING) begin : gen_clock_gating
            always_ff @(posedge ref_clk or negedge por_rst_n) begin
                if (!por_rst_n) begin
                    activity_counter <= 16'h0;
                    idle_threshold <= 8'd100;  // 100 cycles idle threshold
                    clocks_gated <= 1'b0;
                end else begin
                    // Monitor activity
                    if (protocol_active || phy_active) begin
                        activity_counter <= 16'h0;
                        clocks_gated <= 1'b0;
                    end else begin
                        if (activity_counter < idle_threshold) begin
                            activity_counter <= activity_counter + 1;
                        end else begin
                            clocks_gated <= (power_mode != 2'b00); // Gate in low power modes
                        end
                    end
                end
            end
        end else begin : gen_no_clock_gating
            assign activity_counter = 16'h0;
            assign clocks_gated = 1'b0;
        end
    endgenerate
    
    // Power Domain Control
    always_ff @(posedge ref_clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            domain_enable <= '0;
            domain_isolate <= '1;  // Start isolated
        end else begin
            case (current_state)
                CLK_POWER_UP: begin
                    domain_enable <= '1;      // Enable all domains
                    domain_isolate <= '0;     // Remove isolation
                end
                
                CLK_RESET: begin
                    domain_enable <= '0;      // Disable all domains
                    domain_isolate <= '1;     // Isolate all domains
                end
                
                default: begin
                    // Maintain current state
                end
            endcase
        end
    end
    
    // Clock Generation (Simplified - would use actual PLLs in real implementation)
    logic clk_main_int, clk_symbol_rate_int, clk_quarter_rate_int, clk_bit_rate_int;
    
    // Main clock generation (800 MHz)
    always_ff @(posedge ref_clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            clk_main_int <= 1'b0;
        end else if (pll_main_enable && pll_main_locked) begin
            clk_main_int <= ~clk_main_int; // Toggle for simplified clock
        end
    end
    
    // High-speed clock generation (symbol rate)
    logic [7:0] high_speed_counter;
    always_ff @(posedge ref_clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            clk_symbol_rate_int <= 1'b0;
            clk_quarter_rate_int <= 1'b0;
            clk_bit_rate_int <= 1'b0;
            high_speed_counter <= 8'h0;
        end else if (pll_high_speed_enable && pll_high_speed_locked) begin
            high_speed_counter <= high_speed_counter + 1;
            
            // Generate clocks based on counter
            clk_symbol_rate_int <= high_speed_counter[0];      // /2
            clk_quarter_rate_int <= &high_speed_counter[1:0];  // /4
            clk_bit_rate_int <= ~clk_symbol_rate_int;          // 2x symbol rate
        end
    end
    
    // Clock Output Assignment with Gating
    assign clk_main = clk_main_int && !gate_quarter_rate;
    assign clk_sideband = clk_main_int;  // Same as main clock
    assign clk_symbol_rate = clk_symbol_rate_int && !gate_symbol_rate;
    assign clk_quarter_rate = clk_quarter_rate_int && !gate_quarter_rate;
    assign clk_bit_rate = clk_bit_rate_int && !gate_bit_rate;
    
    // Reset Synchronization
    always_ff @(posedge clk_main_int or negedge por_rst_n) begin
        if (!por_rst_n) begin
            main_reset_sync <= 4'h0;
            sideband_reset_sync <= 4'h0;
        end else begin
            main_reset_sync <= {main_reset_sync[2:0], 1'b1};
            sideband_reset_sync <= {sideband_reset_sync[2:0], 1'b1};
        end
    end
    
    always_ff @(posedge clk_quarter_rate_int or negedge por_rst_n) begin
        if (!por_rst_n) begin
            quarter_rate_reset_sync <= 4'h0;
        end else begin
            quarter_rate_reset_sync <= {quarter_rate_reset_sync[2:0], 1'b1};
        end
    end
    
    always_ff @(posedge clk_symbol_rate_int or negedge por_rst_n) begin
        if (!por_rst_n) begin
            symbol_rate_reset_sync <= 4'h0;
        end else begin
            symbol_rate_reset_sync <= {symbol_rate_reset_sync[2:0], 1'b1};
        end
    end
    
    always_ff @(posedge clk_bit_rate_int or negedge por_rst_n) begin
        if (!por_rst_n) begin
            bit_rate_reset_sync <= 4'h0;
        end else begin
            bit_rate_reset_sync <= {bit_rate_reset_sync[2:0], 1'b1};
        end
    end
    
    // Performance Estimation
    always_ff @(posedge ref_clk or negedge por_rst_n) begin
        if (!por_rst_n) begin
            power_estimation <= 16'h0;
            temperature_estimate <= 8'd25; // 25°C ambient
        end else begin
            // Simple power estimation based on voltage and frequency
            logic [15:0] core_power, phy_power, pll_power;
            
            // Power = CV²f (simplified)
            core_power = (current_vdd_core * current_vdd_core) >> 8;
            phy_power = (current_vdd_phy * current_vdd_phy) >> 6;  // Higher activity
            pll_power = (current_vdd_pll * current_vdd_pll) >> 10; // Lower activity
            
            power_estimation <= core_power + phy_power + pll_power;
            
            // Simple temperature estimation
            if (power_estimation > 16'd500) begin
                temperature_estimate <= 8'd85; // High power = high temp
            end else if (power_estimation > 16'd250) begin
                temperature_estimate <= 8'd55; // Medium power
            end else begin
                temperature_estimate <= 8'd35; // Low power
            end
        end
    end
    
    // Output Assignments
    assign rst_main_n = main_reset_sync[3];
    assign rst_sideband_n = sideband_reset_sync[3];
    assign rst_quarter_rate_n = quarter_rate_reset_sync[3];
    assign rst_symbol_rate_n = symbol_rate_reset_sync[3];
    assign rst_bit_rate_n = bit_rate_reset_sync[3];
    
    assign vdd_core_mv = current_vdd_core;
    assign vdd_phy_mv = current_vdd_phy;
    assign vdd_pll_mv = current_vdd_pll;
    
    assign gate_bit_rate = clocks_gated || (current_state != CLK_ACTIVE);
    assign gate_symbol_rate = clocks_gated || (current_state != CLK_ACTIVE);
    assign gate_quarter_rate = clocks_gated || (current_state != CLK_ACTIVE);
    
    assign all_clocks_stable = pll_main_locked && pll_high_speed_locked && 
                              (current_state == CLK_ACTIVE);
    assign voltage_scaling_active = voltage_transition_active;
    
    assign pll_lock_time_us = pll_lock_counter[31:8]; // Convert to microseconds
    assign power_consumption_mw = power_estimation;
    assign thermal_margin_c = (8'd125 > temperature_estimate) ? 
                             (8'd125 - temperature_estimate) : 8'd0;
    
    // Status Register
    assign clocking_status = {
        current_state,                  // [31:28]
        power_mode,                     // [27:26]
        signaling_mode,                 // [25:24]
        target_data_rate,               // [23:20]
        pll_main_locked,                // [19]
        pll_high_speed_locked,          // [18]
        voltage_transition_active,      // [17]
        clocks_gated,                   // [16]
        thermal_throttle,               // [15]
        3'b0,                          // [14:12] Reserved
        &domain_ack,                   // [11]
        &voltage_ready,                // [10]
        2'b0,                          // [9:8] Reserved
        temperature_estimate           // [7:0]
    };
    
    // Debug Counters
    assign debug_counters[0] = pll_lock_counter[15:0];
    assign debug_counters[1] = voltage_settle_counter;
    assign debug_counters[2] = activity_counter;
    assign debug_counters[3] = power_estimation;
    
    // Simplified PLL Lock Generation (would be from actual PLLs)
    assign pll_main_locked = pll_main_enable && (pll_lock_counter > 32'd1000);
    assign pll_high_speed_locked = pll_high_speed_enable && (pll_lock_counter > 32'd2000);

endmodule