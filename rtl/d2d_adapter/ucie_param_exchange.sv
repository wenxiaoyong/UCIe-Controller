module ucie_param_exchange
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int PARAM_WIDTH = 32,
    parameter int TIMEOUT_CYCLES = 1000000, // 1ms @ 1GHz
    parameter int NUM_PARAM_REGS = 16
) (
    input  logic                clk,
    input  logic                clk_aux,      // Auxiliary clock for sideband
    input  logic                rst_n,
    
    // Sideband Interface
    output logic [31:0]         sb_tx_data,
    output logic                sb_tx_valid,
    input  logic                sb_tx_ready,
    
    input  logic [31:0]         sb_rx_data,
    input  logic                sb_rx_valid,
    output logic                sb_rx_ready,
    
    // Parameter Configuration Interface
    input  logic [31:0]         local_params [NUM_PARAM_REGS-1:0],
    output logic [31:0]         remote_params [NUM_PARAM_REGS-1:0],
    
    // Control Interface
    input  logic                param_exchange_start,
    output logic                param_exchange_complete,
    output logic                param_exchange_error,
    output logic                param_mismatch,
    
    // Power Management Integration
    input  logic [1:0]          power_state,
    output logic                power_param_valid,
    input  logic                wake_param_request,
    output logic                sleep_param_ready,
    
    // Negotiated Parameters
    output logic [7:0]          negotiated_speed,
    output logic [7:0]          negotiated_width,
    output logic [3:0]          negotiated_protocols,
    output logic [7:0]          negotiated_features,
    
    // Status and Debug
    output logic [15:0]         exchange_status,
    output logic [31:0]         timeout_counter
);

    // Parameter Exchange State Machine
    typedef enum logic [3:0] {
        PARAM_IDLE,
        PARAM_SEND_LOCAL,
        PARAM_WAIT_REMOTE,
        PARAM_NEGOTIATE,
        PARAM_VALIDATE,
        PARAM_COMPLETE,
        PARAM_ERROR,
        PARAM_TIMEOUT,
        PARAM_POWER_SAVE,
        PARAM_WAKE_UP
    } param_state_t;
    
    param_state_t current_state, next_state;
    
    // Parameter Storage
    logic [31:0] local_param_regs [NUM_PARAM_REGS-1:0];
    logic [31:0] remote_param_regs [NUM_PARAM_REGS-1:0];
    logic [31:0] negotiated_param_regs [NUM_PARAM_REGS-1:0];
    
    // Exchange Control
    logic [3:0] param_index;
    logic [3:0] tx_param_index, rx_param_index;
    logic [31:0] timer_count;
    logic timeout_expired;
    logic all_params_sent, all_params_received;
    
    // Parameter Validation
    logic [NUM_PARAM_REGS-1:0] param_valid_mask;
    logic [NUM_PARAM_REGS-1:0] param_mismatch_mask;
    logic negotiation_success;
    
    // Cross-clock domain signals for auxiliary clock interface
    logic sb_tx_valid_aux, sb_rx_ready_aux;
    logic [31:0] sb_tx_data_aux;
    logic param_start_sync, param_complete_sync;
    
    // Clock Domain Crossing for Control Signals
    logic [2:0] start_sync_ff, complete_sync_ff;
    
    always_ff @(posedge clk_aux or negedge rst_n) begin
        if (!rst_n) begin
            start_sync_ff <= 3'b0;
        end else begin
            start_sync_ff <= {start_sync_ff[1:0], param_exchange_start};
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            complete_sync_ff <= 3'b0;
        end else begin
            complete_sync_ff <= {complete_sync_ff[1:0], param_complete_sync};
        end
    end
    
    assign param_start_sync = start_sync_ff[2] && !start_sync_ff[1];
    assign param_exchange_complete = complete_sync_ff[2] && !complete_sync_ff[1];
    
    // Initialize Local Parameters
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PARAM_REGS; i++) begin
                local_param_regs[i] <= local_params[i];
            end
        end else begin
            // Update local parameters dynamically if needed
            for (int i = 0; i < NUM_PARAM_REGS; i++) begin
                if (current_state == PARAM_IDLE) begin
                    local_param_regs[i] <= local_params[i];
                end
            end
        end
    end
    
    // State Machine (Main Clock Domain)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= PARAM_IDLE;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Timer Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            timer_count <= 32'h0;
        end else if (current_state != next_state) begin
            timer_count <= 32'h0; // Reset on state change
        end else begin
            timer_count <= timer_count + 1;
        end
    end
    
    assign timeout_expired = (timer_count > TIMEOUT_CYCLES);
    
    // Parameter Index Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_param_index <= 4'h0;
            rx_param_index <= 4'h0;
        end else begin
            case (current_state)
                PARAM_SEND_LOCAL: begin
                    if (sb_tx_valid && sb_tx_ready) begin
                        if (tx_param_index < 4'(NUM_PARAM_REGS-1)) begin
                            tx_param_index <= tx_param_index + 1;
                        end
                    end
                end
                
                PARAM_WAIT_REMOTE: begin
                    if (sb_rx_valid && sb_rx_ready) begin
                        if (rx_param_index < 4'(NUM_PARAM_REGS-1)) begin
                            rx_param_index <= rx_param_index + 1;
                        end
                    end
                end
                
                PARAM_IDLE: begin
                    tx_param_index <= 4'h0;
                    rx_param_index <= 4'h0;
                end
                
                default: begin
                    // Keep current values
                end
            endcase
        end
    end
    
    // Completion Flags
    assign all_params_sent = (tx_param_index >= 4'(NUM_PARAM_REGS-1));
    assign all_params_received = (rx_param_index >= 4'(NUM_PARAM_REGS-1));
    
    // Remote Parameter Reception
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PARAM_REGS; i++) begin
                remote_param_regs[i] <= 32'h0;
            end
        end else if (current_state == PARAM_WAIT_REMOTE && sb_rx_valid && sb_rx_ready) begin
            remote_param_regs[rx_param_index] <= sb_rx_data;
        end
    end
    
    // Parameter Negotiation Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PARAM_REGS; i++) begin
                negotiated_param_regs[i] <= 32'h0;
            end
            param_valid_mask <= '0;
            param_mismatch_mask <= '0;
            negotiation_success <= 1'b0;
        end else if (current_state == PARAM_NEGOTIATE) begin
            // Negotiate parameters based on compatibility
            for (int i = 0; i < NUM_PARAM_REGS; i++) begin
                case (i)
                    0: begin // Speed capability
                        negotiated_param_regs[i] <= (local_param_regs[i] < remote_param_regs[i]) ? 
                                                   local_param_regs[i] : remote_param_regs[i];
                        param_valid_mask[i] <= 1'b1;
                    end
                    
                    1: begin // Width capability
                        negotiated_param_regs[i] <= (local_param_regs[i] < remote_param_regs[i]) ? 
                                                   local_param_regs[i] : remote_param_regs[i];
                        param_valid_mask[i] <= 1'b1;
                    end
                    
                    2: begin // Protocol support (bitwise AND)
                        negotiated_param_regs[i] <= local_param_regs[i] & remote_param_regs[i];
                        param_valid_mask[i] <= |negotiated_param_regs[i];
                        param_mismatch_mask[i] <= ~param_valid_mask[i];
                    end
                    
                    3: begin // Features (bitwise AND)
                        negotiated_param_regs[i] <= local_param_regs[i] & remote_param_regs[i];
                        param_valid_mask[i] <= 1'b1;
                    end
                    
                    default: begin // Other parameters - exact match required
                        negotiated_param_regs[i] <= local_param_regs[i];
                        param_valid_mask[i] <= (local_param_regs[i] == remote_param_regs[i]);
                        param_mismatch_mask[i] <= ~param_valid_mask[i];
                    end
                endcase
            end
            
            negotiation_success <= &param_valid_mask;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            PARAM_IDLE: begin
                if (param_exchange_start) begin
                    if (power_state == 2'b00) begin // L0 state
                        next_state = PARAM_SEND_LOCAL;
                    end else begin
                        next_state = PARAM_POWER_SAVE;
                    end
                end else if (wake_param_request) begin
                    next_state = PARAM_WAKE_UP;
                end
            end
            
            PARAM_SEND_LOCAL: begin
                if (timeout_expired) begin
                    next_state = PARAM_TIMEOUT;
                end else if (all_params_sent) begin
                    next_state = PARAM_WAIT_REMOTE;
                end
            end
            
            PARAM_WAIT_REMOTE: begin
                if (timeout_expired) begin
                    next_state = PARAM_TIMEOUT;
                end else if (all_params_received) begin
                    next_state = PARAM_NEGOTIATE;
                end
            end
            
            PARAM_NEGOTIATE: begin
                if (negotiation_success) begin
                    next_state = PARAM_VALIDATE;
                end else begin
                    next_state = PARAM_ERROR;
                end
            end
            
            PARAM_VALIDATE: begin
                // Additional validation could be performed here
                next_state = PARAM_COMPLETE;
            end
            
            PARAM_COMPLETE: begin
                // Stay in complete state until reset or new exchange
                if (param_exchange_start) begin
                    next_state = PARAM_SEND_LOCAL;
                end
            end
            
            PARAM_ERROR: begin
                // Stay in error state until reset
                if (param_exchange_start) begin
                    next_state = PARAM_IDLE;
                end
            end
            
            PARAM_TIMEOUT: begin
                // Timeout recovery
                next_state = PARAM_ERROR;
            end
            
            PARAM_POWER_SAVE: begin
                if (power_state == 2'b00) begin
                    next_state = PARAM_IDLE;
                end
            end
            
            PARAM_WAKE_UP: begin
                if (power_state == 2'b00) begin
                    next_state = PARAM_SEND_LOCAL;
                end
            end
            
            default: begin
                next_state = PARAM_IDLE;
            end
        endcase
    end
    
    // Output Logic
    always_comb begin
        // Default outputs
        sb_tx_data = 32'h0;
        sb_tx_valid = 1'b0;
        sb_rx_ready = 1'b0;
        param_complete_sync = 1'b0;
        power_param_valid = 1'b0;
        sleep_param_ready = 1'b0;
        
        case (current_state)
            PARAM_SEND_LOCAL: begin
                sb_tx_data = local_param_regs[tx_param_index];
                sb_tx_valid = 1'b1;
            end
            
            PARAM_WAIT_REMOTE: begin
                sb_rx_ready = 1'b1;
            end
            
            PARAM_COMPLETE: begin
                param_complete_sync = 1'b1;
                power_param_valid = 1'b1;
            end
            
            PARAM_POWER_SAVE: begin
                sleep_param_ready = 1'b1;
            end
            
            default: begin
                // Default values already set
            end
        endcase
    end
    
    // Status and Output Assignment
    assign remote_params = remote_param_regs;
    assign param_exchange_error = (current_state == PARAM_ERROR) || (current_state == PARAM_TIMEOUT);
    assign param_mismatch = |param_mismatch_mask;
    assign timeout_counter = timer_count;
    
    // Negotiated Parameter Outputs
    assign negotiated_speed = negotiated_param_regs[0][7:0];
    assign negotiated_width = negotiated_param_regs[1][7:0];
    assign negotiated_protocols = negotiated_param_regs[2][3:0];
    assign negotiated_features = negotiated_param_regs[3][7:0];
    
    // Status Register
    assign exchange_status = {current_state, tx_param_index, rx_param_index, 
                             negotiation_success, param_mismatch, 2'b0};

endmodule
