import ucie_pkg::*;

module ucie_link_training_fsm #(
    parameter int NUM_MODULES = 1,
    parameter int NUM_LANES = 64
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
    output logic [7:0]          training_attempts
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
    
    // Main State Machine Logic
    always_comb begin
        // Default outputs
        next_state = current_state;
        phy_reset_req = 1'b0;
        phy_speed_req = 8'd32;  // Default 32 GT/s
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
        
        case (current_state)
            TRAIN_RESET: begin
                phy_reset_req = 1'b1;
                if (training_start && phy_ready) begin
                    next_state = TRAIN_SBINIT;
                end else if (timer_expired) begin
                    next_state = TRAIN_ERROR;
                end
            end
            
            TRAIN_SBINIT: begin
                // Initialize sideband communication
                if (timer_expired) begin
                    next_state = TRAIN_ERROR;
                end else if (phy_ready) begin
                    next_state = TRAIN_PARAM;
                end
            end
            
            TRAIN_PARAM: begin
                // Parameter exchange
                sb_param_tx = {8'd64, 8'd128, 16'hFFFF}; // width, speed, protocols
                sb_param_tx_valid = 1'b1;
                sb_param_rx_ready = 1'b1;
                
                if (timer_expired) begin
                    next_state = TRAIN_ERROR;
                end else if (param_exchange_done) begin
                    next_state = TRAIN_MBINIT;
                end
            end
            
            TRAIN_MBINIT: begin
                // Mainband initialization
                phy_speed_req = 8'd128;  // Request negotiated speed
                phy_width_req = 8'd64;   // Request negotiated width
                
                if (timer_expired) begin
                    next_state = TRAIN_ERROR;
                end else if (phy_ready && (phy_speed_ack != 8'h0)) begin
                    next_state = TRAIN_CAL;
                end
            end
            
            TRAIN_CAL: begin
                // Calibration phase
                cal_start = 1'b1;
                
                if (timer_expired || cal_error) begin
                    next_state = TRAIN_ERROR;
                end else if (calibration_complete) begin
                    next_state = TRAIN_MBTRAIN;
                end
            end
            
            TRAIN_MBTRAIN: begin
                // Mainband training
                lane_train_enable = 1'b1;
                lane_enable = {NUM_LANES{1'b1}};
                pattern_select = 8'h1F;  // PRBS31
                pattern_enable = 1'b1;
                
                if (timer_expired || (|lane_train_error)) begin
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
                // Multi-module coordination
                module_sync_req = 1'b1;
                
                if (timer_expired) begin
                    next_state = TRAIN_ERROR;
                end else if (modules_synchronized && module_sync_ack) begin
                    next_state = TRAIN_LINKINIT;
                end
            end
            
            TRAIN_LINKINIT: begin
                // Link initialization
                lane_enable = {NUM_LANES{1'b1}};
                
                if (timer_expired) begin
                    next_state = TRAIN_ERROR;
                end else if (all_lanes_trained) begin
                    next_state = TRAIN_ACTIVE;
                end
            end
            
            TRAIN_ACTIVE: begin
                // Active operation
                training_complete = 1'b1;
                lane_enable = {NUM_LANES{1'b1}};
                // Stay in this state until external request for state change
            end
            
            TRAIN_ERROR: begin
                // Error state
                training_error = 1'b1;
                // Could implement retry logic here
                if (training_start && (attempt_count < 8'd3)) begin
                    next_state = TRAIN_RESET;
                end
            end
            
            default: begin
                next_state = TRAIN_RESET;
            end
        endcase
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

endmodule