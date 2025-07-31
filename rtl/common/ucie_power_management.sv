module ucie_power_management #(
    parameter NUM_DOMAINS            = 3,  // 0.6V, 0.8V, 1.0V
    parameter NUM_LANES              = 64,
    parameter ENABLE_AVFS            = 1,  // Adaptive Voltage/Frequency Scaling
    parameter ENABLE_ADAPTIVE_POWER  = 1,
    parameter POWER_MONITOR_WIDTH    = 16
) (
    // Clock and Reset
    input  logic        clk,
    input  logic        rst_n,
    
    // ========================================================================
    // Power Domain Control Interface
    // ========================================================================
    
    // Power Domain Enable/Disable
    output logic        domain_0v6_active,
    output logic        domain_0v8_active,
    output logic        domain_1v0_active,
    input  logic [2:0]  power_domain_status,
    
    // Power Domain Configuration
    input  logic        multi_domain_enable,
    input  logic [2:0]  power_domain_config,
    input  logic        avfs_enable,
    input  logic [7:0]  power_budget_limit,  // Power budget in 100mW units
    
    // ========================================================================
    // Lane Power Management Interface
    // ========================================================================
    
    // Per-Lane Power Control
    input  logic [NUM_LANES-1:0]    lane_active,
    output logic [NUM_LANES-1:0][1:0] lane_power_state,  // 00=Off, 01=Standby, 10=Active, 11=Boost
    input  logic [NUM_LANES-1:0][1:0] phy_lane_power_state,
    
    // Lane Power Monitoring
    output logic [NUM_LANES-1:0]    lane_power_good,
    output logic [NUM_LANES-1:0][7:0] lane_power_consumption,  // Power per lane in mW
    
    // ========================================================================
    // Adaptive Power Features Interface
    // ========================================================================
    
    // Adaptive Power Control
    output logic        adaptive_power_enable,
    input  logic [15:0] power_budget,           // Total power budget in mW
    output logic        adaptive_power_active,
    
    // AVFS (Adaptive Voltage/Frequency Scaling)
    output logic        avfs_active,
    output logic [7:0]  voltage_0v6_setting,   // Voltage setting for 0.6V domain
    output logic [7:0]  voltage_0v8_setting,   // Voltage setting for 0.8V domain  
    output logic [7:0]  voltage_1v0_setting,   // Voltage setting for 1.0V domain
    output logic [15:0] frequency_scaling,     // Frequency scaling factor
    
    // ========================================================================
    // Thermal Integration Interface
    // ========================================================================
    
    // Thermal Inputs
    input  logic [7:0]  die_temperature,       // Average die temperature
    input  logic        thermal_throttle,      // Thermal throttling request
    input  logic [1:0]  thermal_throttle_level, // Throttling level
    
    // Thermal-Driven Power Response
    output logic        thermal_power_reduction,
    output logic [7:0]  thermal_power_limit,   // Reduced power limit due to thermal
    
    // ========================================================================
    // Performance Integration Interface  
    // ========================================================================
    
    // Performance Monitoring
    input  logic [15:0] bandwidth_utilization, // Current bandwidth utilization
    input  logic [31:0] traffic_pattern,       // Traffic pattern indicator
    
    // Performance-Based Power Optimization
    output logic [7:0]  power_efficiency,      // Current power efficiency metric
    output logic        performance_power_mode, // Performance vs power optimization
    
    // ========================================================================
    // System-Level Power Interface
    // ========================================================================
    
    // Global Power Control
    output logic        global_power_good,     // All domains powered and stable
    output logic        power_state_change,    // Power state transition in progress
    input  logic        system_power_enable,   // System-level power enable
    
    // Power State Machine
    output logic [2:0]  current_power_state,   // Current system power state
    input  logic [2:0]  requested_power_state, // Requested power state
    output logic        power_transition_busy, // Power transition in progress
    
    // ========================================================================
    // Debug and Monitoring Interface
    // ========================================================================
    
    // Power Monitoring
    output logic [POWER_MONITOR_WIDTH-1:0] total_power_consumption,
    output logic [POWER_MONITOR_WIDTH-1:0] domain_0v6_power,
    output logic [POWER_MONITOR_WIDTH-1:0] domain_0v8_power,
    output logic [POWER_MONITOR_WIDTH-1:0] domain_1v0_power,
    
    // Debug Interface
    output logic [31:0] debug_power_status,
    input  logic [7:0]  debug_select
);

    import ucie_pkg::*;
    import ucie_common_pkg::*;

    // ========================================================================
    // Internal Signal Declarations
    // ========================================================================
    
    // Power State Machine
    power_state_t       next_power_state;
    power_state_t       power_state_reg;
    logic [15:0]        power_transition_timer;
    logic               transition_timeout;
    
    // Domain Power Control
    logic [2:0]         domain_enable_req;
    logic [2:0]         domain_enable_ack;
    logic [2:0]         domain_stable;
    logic [15:0]        domain_power_up_timer[2:0];
    
    // AVFS Control
    logic               avfs_enable_int;
    logic [7:0]         avfs_voltage_target[2:0];
    logic [15:0]        avfs_frequency_target;
    logic               avfs_adaptation_active;
    
    // Adaptive Power Control
    logic               adaptive_enable_int;
    logic [15:0]        current_power_budget;
    logic [15:0]        remaining_power_budget;
    logic [7:0]         power_allocation_factor;
    
    // Thermal Management
    logic               thermal_emergency;
    logic [7:0]         thermal_reduction_factor;
    logic [15:0]        thermal_adjusted_budget;
    
    // Performance Optimization
    logic [7:0]         utilization_factor;
    logic [7:0]         efficiency_metric;
    logic               low_power_mode_enable;
    
    // Lane Power Management
    logic [NUM_LANES-1:0][7:0] lane_power_estimates;
    logic [15:0]        total_lane_power;
    
    // Monitoring and Statistics
    logic [31:0]        power_event_counter;
    logic [31:0]        thermal_event_counter;
    logic [31:0]        avfs_event_counter;
    
    // ========================================================================
    // Power State Machine
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            power_state_reg <= POWER_L2;
            power_transition_timer <= 16'h0;
            power_event_counter <= 32'h0;
        end else begin
            power_state_reg <= next_power_state;
            
            // Power transition timer
            if (power_state_reg != next_power_state) begin
                power_transition_timer <= 16'h0;
                power_event_counter <= power_event_counter + 1;
            end else if (power_transition_timer != 16'hFFFF) begin
                power_transition_timer <= power_transition_timer + 1;
            end
        end
    end
    
    // Power state transition logic
    always_comb begin
        next_power_state = power_state_reg;
        transition_timeout = (power_transition_timer > 16'd1000);
        
        if (!system_power_enable) begin
            next_power_state = POWER_L2;
        end else begin
            case (power_state_reg)
                POWER_L2: begin // Deep sleep
                    if (requested_power_state != POWER_L2) begin
                        next_power_state = POWER_L1;
                    end
                end
                
                POWER_L1: begin // Standby
                    if (requested_power_state == POWER_L2) begin
                        next_power_state = POWER_L2;
                    end else if (requested_power_state == POWER_L0 && domain_stable == 3'b111) begin
                        next_power_state = POWER_L0;
                    end
                end
                
                POWER_L0: begin // Active
                    if (thermal_emergency) begin
                        next_power_state = POWER_L1;
                    end else if (requested_power_state != POWER_L0) begin
                        next_power_state = requested_power_state;
                    end
                end
                
                default: next_power_state = POWER_L2;
            endcase
        end
    end
    
    assign current_power_state = power_state_reg;
    assign power_transition_busy = (power_state_reg != next_power_state) && !transition_timeout;
    assign power_state_change = (power_state_reg != next_power_state);
    
    // ========================================================================
    // Multi-Domain Power Control
    // ========================================================================
    
    // Domain enable request generation
    always_comb begin
        domain_enable_req = 3'b000;
        
        case (power_state_reg)
            POWER_L0: begin
                if (multi_domain_enable) begin
                    domain_enable_req = power_domain_config;
                end else begin
                    domain_enable_req = 3'b111; // All domains active
                end
            end
            
            POWER_L1: begin
                domain_enable_req = 3'b001; // Only 1.0V domain
            end
            
            POWER_L2: begin
                domain_enable_req = 3'b000; // All domains off
            end
            
            default: domain_enable_req = 3'b000;
        endcase
    end
    
    // Domain power sequencing
    genvar domain_idx;
    generate
        for (domain_idx = 0; domain_idx < 3; domain_idx++) begin : gen_domain_control
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    domain_power_up_timer[domain_idx] <= 16'h0;
                    domain_stable[domain_idx] <= 1'b0;
                end else begin
                    if (domain_enable_req[domain_idx] && !domain_stable[domain_idx]) begin
                        if (domain_power_up_timer[domain_idx] < 16'd100) begin
                            domain_power_up_timer[domain_idx] <= domain_power_up_timer[domain_idx] + 1;
                        end else begin
                            domain_stable[domain_idx] <= 1'b1;
                        end
                    end else if (!domain_enable_req[domain_idx]) begin
                        domain_power_up_timer[domain_idx] <= 16'h0;
                        domain_stable[domain_idx] <= 1'b0;
                    end
                end
            end
        end
    endgenerate
    
    assign domain_0v6_active = domain_enable_req[0] && domain_stable[0];
    assign domain_0v8_active = domain_enable_req[1] && domain_stable[1];
    assign domain_1v0_active = domain_enable_req[2] && domain_stable[2];
    assign global_power_good = (domain_stable == power_domain_config) || !multi_domain_enable;
    
    // ========================================================================
    // Adaptive Voltage/Frequency Scaling (AVFS)
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            avfs_enable_int <= 1'b0;
            avfs_voltage_target[0] <= 8'd60;  // 0.6V default
            avfs_voltage_target[1] <= 8'd80;  // 0.8V default
            avfs_voltage_target[2] <= 8'd100; // 1.0V default
            avfs_frequency_target <= 16'd10000; // 1.0x scaling default
            avfs_adaptation_active <= 1'b0;
            avfs_event_counter <= 32'h0;
        end else begin
            avfs_enable_int <= avfs_enable && ENABLE_AVFS;
            
            if (avfs_enable_int && (power_state_reg == POWER_L0)) begin
                // Thermal-based voltage scaling
                if (thermal_throttle) begin
                    avfs_voltage_target[0] <= 8'd55;  // Reduce 0.6V domain
                    avfs_voltage_target[1] <= 8'd75;  // Reduce 0.8V domain
                    avfs_voltage_target[2] <= 8'd95;  // Reduce 1.0V domain
                    avfs_frequency_target <= 16'd8000; // 0.8x frequency scaling
                    avfs_adaptation_active <= 1'b1;
                    avfs_event_counter <= avfs_event_counter + 1;
                end else if (bandwidth_utilization < 16'd2000) begin // <20% utilization
                    avfs_voltage_target[0] <= 8'd58;  // Slightly reduce voltages
                    avfs_voltage_target[1] <= 8'd78;
                    avfs_voltage_target[2] <= 8'd98;
                    avfs_frequency_target <= 16'd9000; // 0.9x frequency scaling
                    avfs_adaptation_active <= 1'b1;
                end else begin
                    // Restore nominal values for high utilization
                    avfs_voltage_target[0] <= 8'd60;
                    avfs_voltage_target[1] <= 8'd80;
                    avfs_voltage_target[2] <= 8'd100;
                    avfs_frequency_target <= 16'd10000;
                    avfs_adaptation_active <= 1'b0;
                end
            end else begin
                avfs_adaptation_active <= 1'b0;
            end
        end
    end
    
    assign avfs_active = avfs_adaptation_active;
    assign voltage_0v6_setting = avfs_voltage_target[0];
    assign voltage_0v8_setting = avfs_voltage_target[1];
    assign voltage_1v0_setting = avfs_voltage_target[2];
    assign frequency_scaling = avfs_frequency_target;
    
    // ========================================================================
    // Adaptive Power Management
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adaptive_enable_int <= 1'b0;
            current_power_budget <= 16'd5000; // 5W default
            power_allocation_factor <= 8'd100;
            thermal_event_counter <= 32'h0;
        end else begin
            adaptive_enable_int <= ENABLE_ADAPTIVE_POWER;
            
            // Set power budget based on configuration
            if (power_budget_limit != 8'h0) begin
                current_power_budget <= {power_budget_limit, 8'h0}; // Convert to mW
            end else begin
                current_power_budget <= power_budget;
            end
            
            // Thermal-based power management
            if (thermal_throttle) begin
                thermal_emergency <= (thermal_throttle_level >= 2'b10);
                
                case (thermal_throttle_level)
                    2'b01: thermal_reduction_factor <= 8'd90;  // 10% reduction
                    2'b10: thermal_reduction_factor <= 8'd75;  // 25% reduction
                    2'b11: thermal_reduction_factor <= 8'd50;  // 50% reduction
                    default: thermal_reduction_factor <= 8'd100;
                endcase
                
                thermal_event_counter <= thermal_event_counter + 1;
            end else begin
                thermal_emergency <= 1'b0;
                thermal_reduction_factor <= 8'd100;
            end
            
            // Calculate thermal-adjusted power budget
            thermal_adjusted_budget <= (current_power_budget * thermal_reduction_factor) >> 8;
        end
    end
    
    assign adaptive_power_enable = adaptive_enable_int;
    assign adaptive_power_active = adaptive_enable_int && (power_state_reg == POWER_L0);
    assign thermal_power_reduction = (thermal_reduction_factor < 8'd100);
    assign thermal_power_limit = thermal_adjusted_budget[15:8];
    
    // ========================================================================
    // Lane Power Management
    // ========================================================================
    
    always_comb begin
        total_lane_power = 16'h0;
        
        // Calculate per-lane power consumption
        for (int lane = 0; lane < NUM_LANES; lane++) begin
            if (lane_active[lane]) begin
                case (power_state_reg)
                    POWER_L0: lane_power_estimates[lane] = 8'd53;  // 53mW per lane at 128 Gbps
                    POWER_L1: lane_power_estimates[lane] = 8'd10;  // 10mW standby
                    POWER_L2: lane_power_estimates[lane] = 8'd1;   // 1mW deep sleep
                    default:  lane_power_estimates[lane] = 8'd0;
                endcase
            end else begin
                lane_power_estimates[lane] = 8'd0;
            end
            
            total_lane_power = total_lane_power + lane_power_estimates[lane];
        end
    end
    
    // Lane power state assignment
    generate
        for (genvar lane_idx = 0; lane_idx < NUM_LANES; lane_idx++) begin : gen_lane_power
            always_comb begin
                if (!lane_active[lane_idx]) begin
                    lane_power_state[lane_idx] = 2'b00; // Off
                    lane_power_good[lane_idx] = 1'b0;
                end else begin
                    case (power_state_reg)
                        POWER_L0: begin
                            lane_power_state[lane_idx] = 2'b10; // Active
                            lane_power_good[lane_idx] = domain_stable[2]; // Depends on 1.0V domain
                        end
                        POWER_L1: begin
                            lane_power_state[lane_idx] = 2'b01; // Standby
                            lane_power_good[lane_idx] = domain_stable[2];
                        end
                        default: begin
                            lane_power_state[lane_idx] = 2'b00; // Off
                            lane_power_good[lane_idx] = 1'b0;
                        end
                    endcase
                end
                
                lane_power_consumption[lane_idx] = lane_power_estimates[lane_idx];
            end
        end
    endgenerate
    
    // ========================================================================
    // Performance Integration and Efficiency Calculation
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            utilization_factor <= 8'h0;
            efficiency_metric <= 8'h0;
            low_power_mode_enable <= 1'b0;
        end else begin
            utilization_factor <= bandwidth_utilization[15:8];
            
            // Calculate power efficiency (inverted - higher is better)
            if (total_lane_power > 16'h0 && bandwidth_utilization > 16'h0) begin
                efficiency_metric <= 8'd255 - ((total_lane_power * 8'd100) / bandwidth_utilization[15:8]);
            end else begin
                efficiency_metric <= 8'h0;
            end
            
            // Enable low power mode for low utilization
            low_power_mode_enable <= (bandwidth_utilization < 16'd1000); // <10% utilization
        end
    end
    
    assign power_efficiency = efficiency_metric;
    assign performance_power_mode = !low_power_mode_enable && (power_state_reg == POWER_L0);
    
    // ========================================================================
    // Power Monitoring and Calculation
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            domain_0v6_power <= 16'h0;
            domain_0v8_power <= 16'h0;
            domain_1v0_power <= 16'h0;
            total_power_consumption <= 16'h0;
        end else begin
            // Estimate power consumption per domain
            if (domain_0v6_active) begin
                domain_0v6_power <= (total_lane_power * 8'd20) >> 8; // ~20% of lane power
            end else begin
                domain_0v6_power <= 16'h0;
            end
            
            if (domain_0v8_active) begin
                domain_0v8_power <= (total_lane_power * 8'd30) >> 8; // ~30% of lane power
            end else begin
                domain_0v8_power <= 16'h0;
            end
            
            if (domain_1v0_active) begin
                domain_1v0_power <= (total_lane_power * 8'd50) >> 8; // ~50% of lane power
            end else begin
                domain_1v0_power <= 16'h0;
            end
            
            // Total power is sum of all domains
            total_power_consumption <= domain_0v6_power + domain_0v8_power + domain_1v0_power;
        end
    end
    
    // ========================================================================
    // Debug Interface
    // ========================================================================
    
    always_comb begin
        case (debug_select[7:4])
            4'h0: debug_power_status = {current_power_state, power_transition_busy, 
                                       domain_stable, global_power_good, 24'h0};
            4'h1: debug_power_status = {total_power_consumption, 16'h0};
            4'h2: debug_power_status = {domain_0v6_power[15:8], domain_0v8_power[15:8], 
                                       domain_1v0_power[15:8], 8'h0};
            4'h3: debug_power_status = {voltage_0v6_setting, voltage_0v8_setting, 
                                       voltage_1v0_setting, avfs_active, 7'h0};
            4'h4: debug_power_status = {thermal_reduction_factor, die_temperature, 
                                       thermal_throttle_level, thermal_emergency, 13'h0};
            4'h5: debug_power_status = {power_efficiency, utilization_factor, 
                                       performance_power_mode, low_power_mode_enable, 14'h0};
            4'h6: debug_power_status = power_event_counter;
            4'h7: debug_power_status = {thermal_event_counter[15:0], avfs_event_counter[15:0]};
            default: debug_power_status = 32'hDEADBEEF;
        endcase
    end

endmodule