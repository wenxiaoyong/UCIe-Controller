module ucie_link_manager
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int NUM_MODULES = 1,
    parameter int MODULE_WIDTH = 64
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Link State Management Interface
    input  logic                link_train_start,
    output logic [3:0]          link_state,
    output logic                link_active,
    output logic                training_complete,
    
    // Physical Layer Interface
    output logic                phy_reset_req,
    input  logic                phy_reset_ack,
    output logic [7:0]          phy_train_cmd,
    input  logic [7:0]          phy_train_status,
    
    // Sideband Parameter Exchange
    output logic [31:0]         param_tx_data,
    output logic                param_tx_valid,
    input  logic                param_tx_ready,
    input  logic [31:0]         param_rx_data,
    input  logic                param_rx_valid,
    output logic                param_rx_ready,
    
    // Error Recovery Interface
    input  logic [7:0]          error_vector,
    output logic [2:0]          recovery_action,
    output logic                error_recovery_active,
    
    // Link Configuration
    input  logic [7:0]          max_link_width,
    input  logic [7:0]          max_link_speed,
    output logic [7:0]          negotiated_width,
    output logic [7:0]          negotiated_speed,
    
    // Status and Debug
    output logic [15:0]         fsm_state_vector,
    output logic [31:0]         training_counters
);

    // State Variables
    link_state_t current_state, next_state;
    
    // Configuration Registers
    logic [7:0] local_max_width, local_max_speed;
    logic [7:0] remote_max_width, remote_max_speed;
    logic [7:0] final_width, final_speed;
    
    // Control and Status
    logic [31:0] state_timer;
    logic [31:0] total_training_time;
    logic param_negotiation_done;
    logic phy_training_done;
    logic error_detected;
    logic recovery_in_progress;
    
    // Error Recovery
    logic [2:0] error_recovery_count;
    logic [7:0] last_error_vector;
    
    // Initialize local capabilities
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            local_max_width <= max_link_width;
            local_max_speed <= max_link_speed;
        end
    end
    
    // Main State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= LINK_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // State Timer
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_timer <= 32'h0;
            total_training_time <= 32'h0;
        end else if (current_state != next_state) begin
            state_timer <= 32'h0;
            if (next_state != LINK_RESET) begin
                total_training_time <= total_training_time + state_timer;
            end else begin
                total_training_time <= 32'h0;
            end
        end else begin
            state_timer <= state_timer + 1;
        end
    end
    
    // Parameter Negotiation Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            remote_max_width <= 8'h0;
            remote_max_speed <= 8'h0;
            final_width <= 8'h0;
            final_speed <= 8'h0;
            param_negotiation_done <= 1'b0;
        end else if (current_state == LINK_PARAM && param_rx_valid) begin
            // Extract remote capabilities from received parameter
            remote_max_width <= param_rx_data[31:24];
            remote_max_speed <= param_rx_data[23:16];
            
            // Negotiate final parameters (minimum of both sides)
            final_width <= (local_max_width < remote_max_width) ? 
                          local_max_width : remote_max_width;
            final_speed <= (local_max_speed < remote_max_speed) ? 
                          local_max_speed : remote_max_speed;
            
            param_negotiation_done <= 1'b1;
        end else if (current_state == LINK_RESET) begin
            param_negotiation_done <= 1'b0;
        end
    end
    
    // Error Detection and Recovery
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_detected <= 1'b0;
            recovery_in_progress <= 1'b0;
            error_recovery_count <= 3'h0;
            last_error_vector <= 8'h0;
        end else begin
            // Error detection
            if (|error_vector) begin
                error_detected <= 1'b1;
                last_error_vector <= error_vector;
            end
            
            // Recovery state management
            if (current_state == LINK_REPAIR || current_state == LINK_RETRAIN) begin
                recovery_in_progress <= 1'b1;
                if (current_state != next_state) begin
                    error_recovery_count <= error_recovery_count + 1;
                end
            end else if (current_state == LINK_ACTIVE) begin
                recovery_in_progress <= 1'b0;
                error_detected <= 1'b0;
                if (next_state != LINK_ACTIVE) begin
                    error_recovery_count <= 3'h0;
                end
            end
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            LINK_RESET: begin
                if (link_train_start) begin
                    next_state = LINK_SBINIT;
                end
            end
            
            LINK_SBINIT: begin
                if (state_timer > 32'd100000) begin // 100us timeout
                    next_state = LINK_ERROR;
                end else if (phy_reset_ack) begin
                    next_state = LINK_PARAM;
                end
            end
            
            LINK_PARAM: begin
                if (state_timer > 32'd1000000) begin // 1ms timeout
                    next_state = LINK_ERROR;
                end else if (param_negotiation_done) begin
                    next_state = LINK_MBINIT;
                end
            end
            
            LINK_MBINIT: begin
                if (state_timer > 32'd500000) begin // 500us timeout
                    next_state = LINK_ERROR;
                end else if (phy_train_status[0]) begin // PHY ready
                    next_state = LINK_CAL;
                end
            end
            
            LINK_CAL: begin
                if (state_timer > 32'd2000000) begin // 2ms timeout
                    next_state = LINK_ERROR;
                end else if (phy_train_status[1]) begin // Calibration done
                    next_state = LINK_MBTRAIN;
                end
            end
            
            LINK_MBTRAIN: begin
                if (state_timer > 32'd5000000) begin // 5ms timeout
                    next_state = LINK_ERROR;
                end else if (phy_train_status[2]) begin // Training done
                    next_state = LINK_LINKINIT;
                end
            end
            
            LINK_LINKINIT: begin
                if (state_timer > 32'd1000000) begin // 1ms timeout  
                    next_state = LINK_ERROR;
                end else if (phy_train_status[3]) begin // Link ready
                    next_state = LINK_ACTIVE;
                end
            end
            
            LINK_ACTIVE: begin
                if (error_detected) begin
                    // Determine recovery action based on error type
                    if (error_vector[0]) begin // CRC error
                        if (error_recovery_count < 3) begin
                            next_state = LINK_RETRAIN;
                        end else begin
                            next_state = LINK_ERROR;
                        end
                    end else if (error_vector[1]) begin // Lane error
                        next_state = LINK_REPAIR;
                    end else begin
                        next_state = LINK_ERROR;
                    end
                end
            end
            
            LINK_REPAIR: begin
                if (state_timer > 32'd20000000) begin // 20ms timeout
                    next_state = LINK_ERROR;
                end else if (phy_train_status[4]) begin // Repair done
                    next_state = LINK_ACTIVE;
                end
            end
            
            LINK_RETRAIN: begin
                if (state_timer > 32'd10000000) begin // 10ms timeout
                    next_state = LINK_ERROR;
                end else if (phy_train_status[2]) begin // Retrain done
                    next_state = LINK_ACTIVE;
                end
            end
            
            LINK_L1: begin
                // Power management states would be handled here
                // For now, simple logic to return to active
                if (link_train_start) begin
                    next_state = LINK_ACTIVE;
                end
            end
            
            LINK_L2: begin
                // Deep sleep state
                if (link_train_start) begin
                    next_state = LINK_SBINIT; // May need sideband re-init
                end
            end
            
            LINK_ERROR: begin
                // Error state - could implement recovery logic
                if (link_train_start && (error_recovery_count < 3)) begin
                    next_state = LINK_RESET;
                end
            end
            
            default: begin
                next_state = LINK_RESET;
            end
        endcase
    end
    
    // Output Logic
    always_comb begin
        // Default outputs
        phy_reset_req = 1'b0;
        phy_train_cmd = 8'h0;
        param_tx_data = 32'h0;
        param_tx_valid = 1'b0;
        param_rx_ready = 1'b0;
        recovery_action = 3'h0;
        
        case (current_state)
            LINK_RESET: begin
                phy_reset_req = 1'b1;
            end
            
            LINK_SBINIT: begin
                phy_train_cmd = 8'h01; // Sideband init command
            end
            
            LINK_PARAM: begin
                // Send local capabilities
                param_tx_data = {local_max_width, local_max_speed, 16'hFFFF};
                param_tx_valid = 1'b1;
                param_rx_ready = 1'b1;
            end
            
            LINK_MBINIT: begin
                phy_train_cmd = 8'h02; // Mainband init command
            end
            
            LINK_CAL: begin
                phy_train_cmd = 8'h03; // Calibration command
            end
            
            LINK_MBTRAIN: begin
                phy_train_cmd = 8'h04; // Training command
            end
            
            LINK_LINKINIT: begin
                phy_train_cmd = 8'h05; // Link init command
            end
            
            LINK_REPAIR: begin
                phy_train_cmd = 8'h06; // Repair command
                recovery_action = 3'h1; // Lane repair
            end
            
            LINK_RETRAIN: begin
                phy_train_cmd = 8'h04; // Retrain command
                recovery_action = 3'h2; // Link retrain
            end
            
            default: begin
                // Default case handled above
            end
        endcase
    end
    
    // Status Outputs
    assign link_state = current_state;
    assign link_active = (current_state == LINK_ACTIVE);
    assign training_complete = link_active;
    assign negotiated_width = final_width;
    assign negotiated_speed = final_speed;
    assign error_recovery_active = recovery_in_progress;
    assign fsm_state_vector = {current_state, next_state, error_recovery_count, 
                              error_detected, recovery_in_progress, param_negotiation_done, 2'b0};
    assign training_counters = total_training_time;

endmodule
