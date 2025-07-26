module ucie_sideband_engine
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int SB_FREQ_MHZ = 800,  // Sideband frequency in MHz
    parameter int NUM_LANES = 64,
    parameter int PARAM_WIDTH = 32,
    parameter int TIMEOUT_CYCLES = 800000  // 1ms @ 800MHz
) (
    input  logic                clk_sb,    // 800MHz sideband clock
    input  logic                clk_main,  // Main system clock
    input  logic                rst_n,
    
    // Sideband Physical Interface
    output logic                sb_clk,
    output logic [7:0]          sb_data,
    output logic                sb_valid,
    input  logic                sb_ready,
    
    input  logic                sb_clk_in,
    input  logic [7:0]          sb_data_in,
    input  logic                sb_valid_in,
    output logic                sb_ready_out,
    
    // Parameter Exchange Interface
    output logic [31:0]         param_tx_data,
    output logic                param_tx_valid,
    input  logic                param_tx_ready,
    
    input  logic [31:0]         param_rx_data,
    input  logic                param_rx_valid,
    output logic                param_rx_ready,
    
    // Link Training Interface
    input  logic                training_enable,
    output logic                training_complete,
    output logic                training_error,
    input  logic [15:0]         training_pattern,
    output logic [15:0]         received_pattern,
    
    // Power Management Interface
    input  logic [1:0]          power_state_req,   // L0, L1, L2, L3
    output logic [1:0]          power_state_ack,
    input  logic                wake_request,
    output logic                sleep_ready,
    
    // Lane Management Interface
    input  logic [NUM_LANES-1:0] lane_enable_req,
    output logic [NUM_LANES-1:0] lane_enable_ack,
    input  logic [7:0]          width_req,
    output logic [7:0]          width_ack,
    
    // Configuration Interface
    input  logic [31:0]         sb_config,
    output logic [31:0]         sb_status,
    
    // Error and Debug
    output logic [15:0]         sb_error_count,
    output logic [31:0]         sb_debug_info
);

    // Sideband Protocol State Machine
    typedef enum logic [3:0] {
        SB_RESET,
        SB_INIT,
        SB_PARAM_EXCHANGE,
        SB_TRAINING,
        SB_ACTIVE,
        SB_POWER_MGMT,
        SB_ERROR,
        SB_RECOVERY,
        SB_L1_ENTRY,
        SB_L1_EXIT,
        SB_L2_ENTRY,
        SB_L2_EXIT
    } sb_state_t;
    
    sb_state_t current_state, next_state;
    
    // Use sideband message types from package
    
    // Message Buffer and Parsing
    logic [7:0] tx_msg_buffer [15:0]; // 16-byte message buffer
    logic [7:0] rx_msg_buffer [15:0];
    logic [3:0] tx_msg_len, rx_msg_len;
    logic [3:0] tx_byte_idx, rx_byte_idx;
    logic msg_tx_busy, msg_rx_busy;
    
    // Protocol Timing
    logic [31:0] state_timer;
    logic [31:0] heartbeat_timer;
    logic [31:0] timeout_timer;
    logic timeout_expired, heartbeat_needed;
    
    // Cross-Clock Domain Synchronization
    logic [2:0] main_to_sb_sync, sb_to_main_sync;
    logic training_enable_sb, power_req_sb;
    logic [1:0] power_state_req_sb;
    
    // Synchronize control signals from main clock to sideband clock
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            main_to_sb_sync <= 3'b0;
            training_enable_sb <= 1'b0;
            power_state_req_sb <= 2'b0;
        end else begin
            main_to_sb_sync <= {main_to_sb_sync[1:0], training_enable};
            training_enable_sb <= main_to_sb_sync[2] && !main_to_sb_sync[1];
            power_state_req_sb <= power_state_req;
        end
    end
    
    // Synchronize status signals from sideband clock to main clock
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            sb_to_main_sync <= 3'b0;
        end else begin
            sb_to_main_sync <= {sb_to_main_sync[1:0], (current_state == SB_ACTIVE)};
        end
    end
    
    // State Machine
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= SB_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Timing Management
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            state_timer <= 32'h0;
            heartbeat_timer <= 32'h0;
            timeout_timer <= 32'h0;
        end else begin
            if (current_state != next_state) begin
                state_timer <= 32'h0;
            end else begin
                state_timer <= state_timer + 1;
            end
            
            heartbeat_timer <= heartbeat_timer + 1;
            
            if (msg_tx_busy || msg_rx_busy) begin
                timeout_timer <= timeout_timer + 1;
            end else begin
                timeout_timer <= 32'h0;
            end
        end
    end
    
    assign timeout_expired = (timeout_timer > TIMEOUT_CYCLES);
    assign heartbeat_needed = (heartbeat_timer > 32'd80000); // 100us @ 800MHz
    
    // Message Transmission State Machine
    typedef enum logic [2:0] {
        TX_IDLE,
        TX_HEADER,
        TX_PAYLOAD,
        TX_CRC,
        TX_WAIT_ACK,
        TX_ERROR
    } tx_state_t;
    
    tx_state_t tx_state, tx_next_state;
    logic [7:0] tx_crc;
    logic tx_complete;
    
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            tx_state <= TX_IDLE;
            tx_byte_idx <= 4'h0;
        end else begin
            tx_state <= tx_next_state;
            
            case (tx_state)
                TX_HEADER, TX_PAYLOAD: begin
                    if (sb_valid && sb_ready) begin
                        if (tx_byte_idx < tx_msg_len-1) begin
                            tx_byte_idx <= tx_byte_idx + 1;
                        end else begin
                            tx_byte_idx <= 4'h0;
                        end
                    end
                end
                
                TX_IDLE: begin
                    tx_byte_idx <= 4'h0;
                end
                
                default: begin
                    // Keep current index
                end
            endcase
        end
    end
    
    // TX State Logic
    always_comb begin
        tx_next_state = tx_state;
        
        case (tx_state)
            TX_IDLE: begin
                if (msg_tx_busy) begin
                    tx_next_state = TX_HEADER;
                end
            end
            
            TX_HEADER: begin
                if (sb_valid && sb_ready) begin
                    if (tx_byte_idx >= 3) begin // 4-byte header
                        if (tx_msg_len > 4) begin
                            tx_next_state = TX_PAYLOAD;
                        end else begin
                            tx_next_state = TX_CRC;
                        end
                    end
                end else if (timeout_expired) begin
                    tx_next_state = TX_ERROR;
                end
            end
            
            TX_PAYLOAD: begin
                if (sb_valid && sb_ready) begin
                    if (tx_byte_idx >= tx_msg_len-1) begin
                        tx_next_state = TX_CRC;
                    end
                end else if (timeout_expired) begin
                    tx_next_state = TX_ERROR;
                end
            end
            
            TX_CRC: begin
                if (sb_valid && sb_ready) begin
                    tx_next_state = TX_WAIT_ACK;
                end
            end
            
            TX_WAIT_ACK: begin
                if (tx_complete) begin
                    tx_next_state = TX_IDLE;
                end else if (timeout_expired) begin
                    tx_next_state = TX_ERROR;
                end
            end
            
            TX_ERROR: begin
                tx_next_state = TX_IDLE;
            end
            
            default: begin
                tx_next_state = TX_IDLE;
            end
        endcase
    end
    
    // Message Reception State Machine
    typedef enum logic [2:0] {
        RX_IDLE,
        RX_HEADER,
        RX_PAYLOAD,
        RX_CRC_CHECK,
        RX_PROCESS,
        RX_ERROR
    } rx_state_t;
    
    rx_state_t rx_state, rx_next_state;
    logic [7:0] rx_crc_calc, rx_crc_recv;
    logic rx_crc_valid;
    
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= RX_IDLE;
            rx_byte_idx <= 4'h0;
        end else begin
            rx_state <= rx_next_state;
            
            case (rx_state)
                RX_HEADER, RX_PAYLOAD: begin
                    if (sb_valid_in && sb_ready_out) begin
                        rx_msg_buffer[rx_byte_idx] <= sb_data_in;
                        if (rx_byte_idx < 15) begin
                            rx_byte_idx <= rx_byte_idx + 1;
                        end
                    end
                end
                
                RX_IDLE: begin
                    rx_byte_idx <= 4'h0;
                end
                
                default: begin
                    // Keep current index
                end
            endcase
        end
    end
    
    // Message Processing Logic
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            param_tx_valid <= 1'b0;
            training_complete <= 1'b0;
            training_error <= 1'b0;
            power_state_ack <= 2'b11; // L3 (reset state)
            lane_enable_ack <= '0;
            width_ack <= 8'h0;
        end else if (rx_state == RX_PROCESS && rx_crc_valid) begin
            case (rx_msg_buffer[0]) // Message type
                ucie_pkg::MSG_PARAM_REQ: begin
                    // Extract parameter request
                    param_tx_data <= {rx_msg_buffer[4], rx_msg_buffer[3], 
                                     rx_msg_buffer[2], rx_msg_buffer[1]};
                    param_tx_valid <= 1'b1;
                end
                
                ucie_pkg::MSG_TRAIN_REQ: begin
                    // Process training request
                    received_pattern <= {rx_msg_buffer[2], rx_msg_buffer[1]};
                    if (rx_msg_buffer[3] == 8'h01) begin // Training complete
                        training_complete <= 1'b1;
                    end
                end
                
                ucie_pkg::MSG_POWER_REQ: begin
                    // Acknowledge power state change
                    power_state_ack <= rx_msg_buffer[1][1:0];
                end
                
                ucie_pkg::MSG_LANE_REQ: begin
                    // Acknowledge lane configuration
                    width_ack <= rx_msg_buffer[1];
                    for (int i = 0; i < NUM_LANES; i++) begin
                        if (i < rx_msg_buffer[1]) begin
                            lane_enable_ack[i] <= 1'b1;
                        end else begin
                            lane_enable_ack[i] <= 1'b0;
                        end
                    end
                end
                
                default: begin
                    // Unknown message type
                end
            endcase
        end else begin
            // Clear single-cycle signals
            param_tx_valid <= 1'b0;
            training_complete <= 1'b0;
            training_error <= 1'b0;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            SB_RESET: begin
                if (state_timer > 32'd8000) begin // 10us @ 800MHz
                    next_state = SB_INIT;
                end
            end
            
            SB_INIT: begin
                if (state_timer > 32'd80000) begin // 100us initialization
                    next_state = SB_PARAM_EXCHANGE;
                end
            end
            
            SB_PARAM_EXCHANGE: begin
                if (param_tx_valid && param_tx_ready) begin
                    next_state = SB_TRAINING;
                end else if (timeout_expired) begin
                    next_state = SB_ERROR;
                end
            end
            
            SB_TRAINING: begin
                if (training_complete) begin
                    next_state = SB_ACTIVE;
                end else if (training_error || timeout_expired) begin
                    next_state = SB_ERROR;
                end
            end
            
            SB_ACTIVE: begin
                if (power_state_req_sb == 2'b01) begin // L1 request
                    next_state = SB_L1_ENTRY;
                end else if (power_state_req_sb == 2'b10) begin // L2 request
                    next_state = SB_L2_ENTRY;
                end else if (timeout_expired) begin
                    next_state = SB_ERROR;
                end
            end
            
            SB_L1_ENTRY: begin
                if (state_timer > 32'd800) begin // 1us
                    next_state = SB_POWER_MGMT;
                end
            end
            
            SB_L1_EXIT: begin
                if (wake_request) begin
                    next_state = SB_ACTIVE;
                end
            end
            
            SB_L2_ENTRY: begin
                if (state_timer > 32'd8000) begin // 10us
                    next_state = SB_POWER_MGMT;
                end
            end
            
            SB_L2_EXIT: begin
                if (wake_request) begin
                    next_state = SB_TRAINING; // Re-train after L2 exit
                end
            end
            
            SB_POWER_MGMT: begin
                if (wake_request) begin
                    if (power_state_ack == 2'b01) begin
                        next_state = SB_L1_EXIT;
                    end else if (power_state_ack == 2'b10) begin
                        next_state = SB_L2_EXIT;
                    end
                end
            end
            
            SB_ERROR: begin
                if (state_timer > 32'd800000) begin // 1ms recovery time
                    next_state = SB_RECOVERY;
                end
            end
            
            SB_RECOVERY: begin
                next_state = SB_INIT;
            end
            
            default: begin
                next_state = SB_RESET;
            end
        endcase
    end
    
    // Output Logic
    always_comb begin
        // Sideband clock output (always running)
        sb_clk = clk_sb;
        
        // Default outputs
        sb_data = 8'h0;
        sb_valid = 1'b0;
        sb_ready_out = 1'b0;
        msg_tx_busy = 1'b0;
        
        case (tx_state)
            TX_HEADER: begin
                sb_data = tx_msg_buffer[tx_byte_idx];
                sb_valid = 1'b1;
                msg_tx_busy = 1'b1;
            end
            
            TX_PAYLOAD: begin
                sb_data = tx_msg_buffer[tx_byte_idx];
                sb_valid = 1'b1;
                msg_tx_busy = 1'b1;
            end
            
            TX_CRC: begin
                sb_data = tx_crc;
                sb_valid = 1'b1;
                msg_tx_busy = 1'b1;
            end
            
            default: begin
                // Default values already set
            end
        endcase
        
        // Receive ready when in appropriate states
        sb_ready_out = (rx_state == RX_HEADER) || (rx_state == RX_PAYLOAD);
        
        // Parameter interface ready
        param_rx_ready = (current_state == SB_PARAM_EXCHANGE);
        
        // Power management outputs
        sleep_ready = (current_state == SB_POWER_MGMT);
    end
    
    // Error Counter
    logic [15:0] error_counter;
    
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            error_counter <= 16'h0;
        end else if (current_state == SB_ERROR || timeout_expired || !rx_crc_valid) begin
            if (error_counter < 16'hFFFF) begin
                error_counter <= error_counter + 1;
            end
        end
    end
    
    // CRC Calculation (simplified 8-bit CRC)
    function automatic logic [7:0] calc_crc8(logic [7:0] data_in, logic [7:0] crc_in);
        logic [7:0] crc_poly = 8'h07; // CRC-8 polynomial
        logic [7:0] crc_temp = crc_in ^ data_in;
        for (int i = 0; i < 8; i++) begin
            if (crc_temp[7]) begin
                crc_temp = (crc_temp << 1) ^ crc_poly;
            end else begin
                crc_temp = crc_temp << 1;
            end
        end
        return crc_temp;
    endfunction
    
    // CRC Calculation for messages
    always_ff @(posedge clk_sb or negedge rst_n) begin
        if (!rst_n) begin
            tx_crc <= 8'h0;
            rx_crc_calc <= 8'h0;
            rx_crc_valid <= 1'b0;
        end else begin
            // Calculate TX CRC
            if (tx_state == TX_HEADER || tx_state == TX_PAYLOAD) begin
                if (sb_valid && sb_ready) begin
                    tx_crc <= calc_crc8(sb_data, tx_crc);
                end
            end else if (tx_state == TX_IDLE) begin
                tx_crc <= 8'h0;
            end
            
            // Calculate RX CRC
            if (rx_state == RX_HEADER || rx_state == RX_PAYLOAD) begin
                if (sb_valid_in && sb_ready_out) begin
                    rx_crc_calc <= calc_crc8(sb_data_in, rx_crc_calc);
                end
            end else if (rx_state == RX_CRC_CHECK) begin
                rx_crc_recv <= sb_data_in;
                rx_crc_valid <= (rx_crc_calc == sb_data_in);
            end else if (rx_state == RX_IDLE) begin
                rx_crc_calc <= 8'h0;
                rx_crc_valid <= 1'b0;
            end
        end
    end
    
    // Status Outputs
    assign sb_error_count = error_counter;
    assign sb_status = {current_state, tx_state, rx_state, 12'h0, 
                       power_state_ack, width_ack};
    assign sb_debug_info = {state_timer[15:0], heartbeat_timer[15:0]};

endmodule
