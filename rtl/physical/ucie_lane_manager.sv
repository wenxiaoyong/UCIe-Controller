module ucie_lane_manager
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int NUM_LANES = 64,
    parameter int REPAIR_LANES = 8,
    parameter int MIN_WIDTH = 8
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Lane Control Interface
    input  logic                lane_mgmt_enable,
    output logic [NUM_LANES-1:0] lane_enable,
    output logic [NUM_LANES-1:0] lane_active,
    input  logic [NUM_LANES-1:0] lane_error,
    
    // Lane Mapping
    output logic [7:0]          lane_map [NUM_LANES-1:0], // Physical to logical mapping
    output logic [7:0]          reverse_map [NUM_LANES-1:0], // Logical to physical mapping
    input  logic                reversal_detected,
    output logic                reversal_corrected,
    
    // Width Management
    input  logic [7:0]          requested_width,
    output logic [7:0]          actual_width,
    output logic                width_degraded,
    input  logic [7:0]          min_width,
    
    // Repair Management
    input  logic                repair_enable,
    output logic                repair_active,
    output logic [NUM_LANES-1:0] repair_lanes,
    input  logic [15:0]         ber_threshold,
    input  logic [15:0]         lane_ber [NUM_LANES-1:0],
    
    // Module Coordination
    input  logic [3:0]          module_id,
    input  logic [3:0]          num_modules,
    output logic                module_coordinator_req,
    input  logic                module_coordinator_ack,
    
    // Lane Status
    output logic [NUM_LANES-1:0] lane_good,
    output logic [NUM_LANES-1:0] lane_marginal,
    output logic [NUM_LANES-1:0] lane_failed,
    output logic [7:0]          good_lane_count,
    
    // Configuration
    input  logic [31:0]         lane_config,
    output logic [31:0]         lane_status
);

    // Lane Management State Machine
    typedef enum logic [3:0] {
        LANE_INIT,
        LANE_MAPPING,
        LANE_TRAINING,
        LANE_ACTIVE,
        LANE_MONITORING,
        LANE_REPAIR_REQUEST,
        LANE_REPAIR_ACTIVE,
        LANE_DEGRADE,
        LANE_ERROR
    } lane_mgmt_state_t;
    
    lane_mgmt_state_t current_state, next_state;
    
    // Lane Status Arrays
    logic [NUM_LANES-1:0] lane_enabled_reg;
    logic [NUM_LANES-1:0] lane_active_reg;
    logic [NUM_LANES-1:0] lane_good_reg;
    logic [NUM_LANES-1:0] lane_marginal_reg;
    logic [NUM_LANES-1:0] lane_failed_reg;
    logic [NUM_LANES-1:0] lane_repair_reg;
    
    // Lane Mapping Tables
    logic [7:0] physical_to_logical [NUM_LANES-1:0];
    logic [7:0] logical_to_physical [NUM_LANES-1:0];
    logic [NUM_LANES-1:0] spare_lanes;
    logic mapping_reversed;
    
    // Width Management
    logic [7:0] current_width;
    logic [7:0] target_width;
    logic [7:0] available_lanes;
    logic width_degradation_needed;
    
    // Repair Management
    logic [NUM_LANES-1:0] lanes_needing_repair;
    logic [NUM_LANES-1:0] lanes_under_repair;
    logic [3:0] repair_count;
    logic [3:0] failed_count;
    logic repair_possible;
    
    // BER Monitoring
    logic [NUM_LANES-1:0] ber_alarm;
    logic [NUM_LANES-1:0] ber_warning;
    logic [15:0] ber_alarm_threshold;
    logic [15:0] ber_warning_threshold;
    
    // Timers
    logic [31:0] state_timer;
    logic [31:0] repair_timer;
    logic [31:0] monitoring_timer;
    
    // Initialize thresholds
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ber_alarm_threshold <= ber_threshold;
            ber_warning_threshold <= ber_threshold >> 1; // Half of alarm threshold
        end else begin
            ber_alarm_threshold <= ber_threshold;
            ber_warning_threshold <= ber_threshold >> 1;
        end
    end
    
    // BER Monitoring Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ber_alarm <= '0;
            ber_warning <= '0;
        end else begin
            for (int i = 0; i < NUM_LANES; i++) begin
                ber_alarm[i] <= (lane_ber[i] > ber_alarm_threshold);
                ber_warning[i] <= (lane_ber[i] > ber_warning_threshold) && 
                                 (lane_ber[i] <= ber_alarm_threshold);
            end
        end
    end
    
    // Lane Quality Assessment
    always_comb begin
        lanes_needing_repair = '0;
        repair_count = 4'h0;
        failed_count = 4'h0;
        
        for (int i = 0; i < NUM_LANES; i++) begin
            // Determine if lane needs repair
            if (ber_alarm[i] || lane_error[i]) begin
                lanes_needing_repair[i] = 1'b1;
                if (repair_count < 4'hF) repair_count = repair_count + 1;
            end
            
            // Count failed lanes
            if (lane_failed_reg[i]) begin
                if (failed_count < 4'hF) failed_count = failed_count + 1;
            end
        end
        
        // Check if repair is possible
        repair_possible = (32'(repair_count) <= REPAIR_LANES) && 
                         ((current_width - 8'(repair_count)) >= min_width);
    end
    
    // State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= LANE_INIT;
        end else begin
            current_state <= next_state;
        end
    end
    
    // State Timer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_timer <= 32'h0;
            repair_timer <= 32'h0;
            monitoring_timer <= 32'h0;
        end else begin
            state_timer <= state_timer + 1;
            
            if (current_state == LANE_REPAIR_ACTIVE) begin
                repair_timer <= repair_timer + 1;
            end else begin
                repair_timer <= 32'h0;
            end
            
            if (current_state == LANE_MONITORING) begin
                monitoring_timer <= monitoring_timer + 1;
            end else begin
                monitoring_timer <= 32'h0;
            end
            
            if (current_state != next_state) begin
                state_timer <= 32'h0;
            end
        end
    end
    
    // Lane Mapping Initialization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize direct mapping
            for (int i = 0; i < NUM_LANES; i++) begin
                physical_to_logical[i] <= i[7:0];
                logical_to_physical[i] <= i[7:0];
            end
            spare_lanes <= '0;
            mapping_reversed <= 1'b0;
        end else if (current_state == LANE_MAPPING) begin
            // Handle lane reversal
            if (reversal_detected && !mapping_reversed) begin
                for (int i = 0; i < NUM_LANES; i++) begin
                    physical_to_logical[i] <= 8'(NUM_LANES-1-i);
                    logical_to_physical[NUM_LANES-1-i] <= 8'(i);
                end
                mapping_reversed <= 1'b1;
            end
            
            // Identify spare lanes (beyond requested width)
            for (int i = 0; i < NUM_LANES; i++) begin
                spare_lanes[i] <= (i >= requested_width);
            end
        end
    end
    
    // Lane Repair Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lanes_under_repair <= '0;
            lane_repair_reg <= '0;
        end else if (current_state == LANE_REPAIR_ACTIVE) begin
            // Implement repair by remapping to spare lanes
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lanes_needing_repair[i] && !lanes_under_repair[i]) begin
                    // Find a spare lane
                    for (int j = 0; j < NUM_LANES; j++) begin
                        if (spare_lanes[j] && !lane_repair_reg[j]) begin
                            // Remap failed lane to spare lane
                            logical_to_physical[i] <= j[7:0];
                            physical_to_logical[j] <= i[7:0];
                            lane_repair_reg[j] <= 1'b1;
                            lanes_under_repair[i] <= 1'b1;
                            break;
                        end
                    end
                end
            end
        end else if (current_state == LANE_ACTIVE) begin
            // Clear repair status when back to active
            lanes_under_repair <= '0;
        end
    end
    
    // Width Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_width <= 8'h0;
            target_width <= 8'h0;
            width_degradation_needed <= 1'b0;
        end else begin
            // Count available good lanes
            available_lanes = 8'h0;
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_good_reg[i] || lane_marginal_reg[i]) begin
                    available_lanes = available_lanes + 1;
                end
            end
            
            // Determine target width
            if (available_lanes >= requested_width) begin
                target_width <= requested_width;
                width_degradation_needed <= 1'b0;
            end else if (available_lanes >= min_width) begin
                target_width <= available_lanes;
                width_degradation_needed <= 1'b1;
            end else begin
                target_width <= min_width;
                width_degradation_needed <= 1'b1;
            end
            
            // Update current width based on state
            if (current_state == LANE_ACTIVE || current_state == LANE_MONITORING) begin
                current_width <= target_width;
            end
        end
    end
    
    // Lane Status Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lane_enabled_reg <= '0;
            lane_active_reg <= '0;
            lane_good_reg <= '0;
            lane_marginal_reg <= '0;
            lane_failed_reg <= '0;
        end else begin
            case (current_state)
                LANE_INIT: begin
                    lane_enabled_reg <= '0;
                    lane_active_reg <= '0;
                    lane_good_reg <= '0;
                    lane_marginal_reg <= '0;
                    lane_failed_reg <= '0;
                end
                
                LANE_TRAINING: begin
                    // Enable lanes up to target width
                    for (int i = 0; i < NUM_LANES; i++) begin
                        lane_enabled_reg[i] <= (i < target_width);
                    end
                end
                
                LANE_ACTIVE, LANE_MONITORING: begin
                    // Update lane status based on BER and errors
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (i < current_width) begin
                            lane_active_reg[i] <= !lane_error[i] && !ber_alarm[i];
                            
                            if (lane_error[i] || ber_alarm[i]) begin
                                lane_failed_reg[i] <= 1'b1;
                                lane_good_reg[i] <= 1'b0;
                                lane_marginal_reg[i] <= 1'b0;
                            end else if (ber_warning[i]) begin
                                lane_marginal_reg[i] <= 1'b1;
                                lane_good_reg[i] <= 1'b0;
                                lane_failed_reg[i] <= 1'b0;
                            end else begin
                                lane_good_reg[i] <= 1'b1;
                                lane_marginal_reg[i] <= 1'b0;
                                lane_failed_reg[i] <= 1'b0;
                            end
                        end else begin
                            lane_active_reg[i] <= 1'b0;
                            lane_enabled_reg[i] <= 1'b0;
                        end
                    end
                end
                
                default: begin
                    // Keep current status
                end
            endcase
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            LANE_INIT: begin
                if (lane_mgmt_enable) begin
                    next_state = LANE_MAPPING;
                end
            end
            
            LANE_MAPPING: begin
                if (state_timer > 32'd1000) begin // 1us mapping time
                    next_state = LANE_TRAINING;
                end
            end
            
            LANE_TRAINING: begin
                if (state_timer > 32'd1000000) begin // 1ms training timeout
                    next_state = LANE_ERROR;
                end else if (target_width > 0) begin
                    next_state = LANE_ACTIVE;
                end
            end
            
            LANE_ACTIVE: begin
                if (|lanes_needing_repair) begin
                    if (repair_enable && repair_possible) begin
                        next_state = LANE_REPAIR_REQUEST;
                    end else if (width_degradation_needed) begin
                        next_state = LANE_DEGRADE;
                    end else begin
                        next_state = LANE_ERROR;
                    end
                end else begin
                    next_state = LANE_MONITORING;
                end
            end
            
            LANE_MONITORING: begin
                if (|lanes_needing_repair) begin
                    next_state = LANE_ACTIVE; // Return to active for repair decision
                end else if (monitoring_timer > 32'd100000) begin // 100us monitoring cycle
                    next_state = LANE_ACTIVE;
                end
            end
            
            LANE_REPAIR_REQUEST: begin
                if (module_coordinator_ack) begin
                    next_state = LANE_REPAIR_ACTIVE;
                end else if (state_timer > 32'd10000) begin // 10us timeout
                    next_state = LANE_DEGRADE;
                end
            end
            
            LANE_REPAIR_ACTIVE: begin
                if (repair_timer > 32'd20000000) begin // 20ms repair timeout
                    next_state = LANE_ERROR;
                end else if (!|lanes_needing_repair) begin
                    next_state = LANE_ACTIVE;
                end
            end
            
            LANE_DEGRADE: begin
                if (target_width >= min_width) begin
                    next_state = LANE_ACTIVE;
                end else begin
                    next_state = LANE_ERROR;
                end
            end
            
            LANE_ERROR: begin
                // Stay in error state until reset or external intervention
                if (lane_mgmt_enable && (state_timer > 32'd100000000)) begin // 100ms
                    next_state = LANE_INIT;
                end
            end
            
            default: begin
                next_state = LANE_INIT;
            end
        endcase
    end
    
    // Output Logic
    always_comb begin
        module_coordinator_req = (current_state == LANE_REPAIR_REQUEST);
        repair_active = (current_state == LANE_REPAIR_ACTIVE);
        reversal_corrected = mapping_reversed;
        
        // Count good lanes
        good_lane_count = 8'h0;
        for (int i = 0; i < NUM_LANES; i++) begin
            if (lane_good_reg[i]) begin
                good_lane_count = good_lane_count + 1;
            end
        end
    end
    
    // Output Assignments
    assign lane_enable = lane_enabled_reg;
    assign lane_active = lane_active_reg;
    assign lane_good = lane_good_reg;
    assign lane_marginal = lane_marginal_reg;
    assign lane_failed = lane_failed_reg;
    assign repair_lanes = lane_repair_reg;
    assign actual_width = current_width;
    assign width_degraded = (current_width < requested_width);
    
    // Lane mapping outputs
    assign lane_map = physical_to_logical;
    assign reverse_map = logical_to_physical;
    
    // Status register
    assign lane_status = {current_state, 4'b0, repair_count, failed_count, 
                         current_width, good_lane_count};

endmodule
