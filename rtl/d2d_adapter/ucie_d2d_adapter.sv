module ucie_d2d_adapter_enhanced #(
    parameter FLIT_WIDTH            = 256,
    parameter NUM_VCS               = 8,
    parameter RETRY_BUFFER_DEPTH    = 128,
    parameter ENABLE_ADVANCED_CRC   = 1,
    parameter ENABLE_LANE_REPAIR    = 1,
    parameter ENABLE_MULTI_MODULE   = 0,
    parameter NUM_PROTOCOLS         = 4,
    parameter MODULE_WIDTH          = 64,
    parameter MAX_SPEED_GBPS        = 128
) (
    // Clock and Reset
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clk_sideband,
    input  logic        rst_sideband_n,
    
    // ========================================================================
    // Protocol Layer Interface (Enhanced for 128 Gbps)
    // ========================================================================
    
    // Protocol to D2D (TX)
    input  logic [FLIT_WIDTH-1:0]   protocol_tx_flit,
    input  logic                     protocol_tx_valid,
    output logic                     protocol_tx_ready,
    input  logic [3:0]              protocol_tx_protocol_id,
    input  logic [7:0]              protocol_tx_vc,
    
    // D2D to Protocol (RX)
    output logic [FLIT_WIDTH-1:0]   protocol_rx_flit,
    output logic                     protocol_rx_valid,
    input  logic                     protocol_rx_ready,
    output logic [3:0]              protocol_rx_protocol_id,
    output logic [7:0]              protocol_rx_vc,
    
    // ========================================================================
    // Physical Layer Interface (Enhanced for 128 Gbps)
    // ========================================================================
    
    // D2D to Physical (TX)
    output logic [FLIT_WIDTH-1:0]   phy_tx_flit,
    output logic                     phy_tx_valid,
    input  logic                     phy_tx_ready,
    
    // Physical to D2D (RX)
    input  logic [FLIT_WIDTH-1:0]   phy_rx_flit,
    input  logic                     phy_rx_valid,
    output logic                     phy_rx_ready,
    
    // ========================================================================
    // Link Status and Control
    // ========================================================================
    
    // Link State Management
    output logic                     link_up,
    output logic [7:0]              link_status,
    input  logic                     link_trained,
    input  logic [MODULE_WIDTH-1:0] lanes_active,
    
    // Training and Parameter Exchange
    input  logic                     training_complete,
    input  logic [63:0]             local_parameters,
    input  logic [63:0]             remote_parameters,
    
    // ========================================================================
    // Multi-Module Coordination (Enhanced)
    // ========================================================================
    
    input  logic [1:0]              module_id,
    input  logic [3:0]              num_modules,
    output logic                     module_coord_valid,
    output logic [31:0]             module_coord_data,
    input  logic [3:0]              module_coord_ready,
    
    // ========================================================================
    // Power Management Interface (128 Gbps Multi-Domain)
    // ========================================================================
    
    input  logic [2:0]              power_state,           // Current power state
    output logic                     power_transition_req,  // Request power transition
    input  logic                     power_transition_ack,  // Power transition acknowledged
    
    // Advanced Power Features
    input  logic                     power_domain_0v6_en,   // 0.6V domain enable
    input  logic                     power_domain_0v8_en,   // 0.8V domain enable
    input  logic                     power_domain_1v0_en,   // 1.0V domain enable
    
    // ========================================================================
    // Advanced Features and Configuration
    // ========================================================================
    
    // ML Enhancement Interface
    input  logic                     ml_optimization_enable,
    input  logic [7:0]              ml_bandwidth_prediction,
    input  logic                     ml_prediction_valid,
    
    // Thermal Management
    input  logic [7:0]              die_temperature,
    output logic                     thermal_throttle_req,
    
    // Error Injection and Testing
    input  logic                     error_injection_enable,
    input  logic [3:0]              error_injection_type,
    
    // Debug Interface
    output logic [31:0]             debug_status,
    output logic [15:0]             performance_counters,
    input  logic [7:0]              debug_select
);

    import ucie_pkg::*;
    import ucie_common_pkg::*;

    // ========================================================================
    // Internal Signal Declarations
    // ========================================================================
    
    // Link State Management Signals
    link_state_t                    current_link_state;
    training_state_t               current_training_state;
    logic                          link_state_change;
    logic [15:0]                   link_uptime_counter;
    
    // CRC and Retry Signals
    logic [FLIT_WIDTH-1:0]         crc_tx_flit;
    logic                          crc_tx_valid;
    logic                          crc_tx_ready;
    logic [31:0]                   crc_tx_value;
    
    logic [FLIT_WIDTH-1:0]         crc_rx_flit;
    logic                          crc_rx_valid;
    logic                          crc_rx_ready;
    logic [31:0]                   crc_rx_value;
    logic                          crc_error;
    
    // Retry Buffer Signals
    logic [FLIT_WIDTH-1:0]         retry_buffer_data;
    logic                          retry_buffer_valid;
    logic                          retry_buffer_ready;
    logic                          retry_request;
    logic                          retry_ack;
    logic [7:0]                    retry_sequence_num;
    
    // Flow Control Signals
    logic [NUM_VCS-1:0][15:0]      tx_credits;
    logic [NUM_VCS-1:0][15:0]      rx_credits;
    logic [NUM_VCS-1:0]            credit_return;
    logic [NUM_VCS-1:0]            flow_control_stop;
    
    // Multi-Protocol Signals
    logic [NUM_PROTOCOLS-1:0]      protocol_enable;
    logic [NUM_PROTOCOLS-1:0][7:0] protocol_priority;
    logic [NUM_PROTOCOLS-1:0]      protocol_active;
    
    // Advanced Feature Signals
    logic                          zero_latency_bypass_active;
    logic                          ml_traffic_shaping_active;
    logic [7:0]                    adaptive_buffer_threshold;
    
    // Power Management Signals
    power_state_t                  requested_power_state;
    micro_power_state_t            current_micro_state;
    logic                          power_optimization_active;
    
    // Performance Monitoring
    logic [31:0]                   tx_flit_count;
    logic [31:0]                   rx_flit_count;
    logic [31:0]                   error_count;
    logic [31:0]                   retry_count;
    logic [15:0]                   bandwidth_utilization;
    logic [15:0]                   buffer_occupancy;
    
    // ========================================================================
    // Enhanced Link State Manager (128 Gbps Capable)
    // ========================================================================
    
    ucie_advanced_link_state_manager #(
        .ENABLE_FAST_TRAINING      (MAX_SPEED_GBPS >= 64),
        .ENABLE_PARALLEL_TRAINING  (MAX_SPEED_GBPS >= 128),
        .ENABLE_ML_PREDICTION      (1),
        .TRAINING_TIMEOUT_CYCLES   (100000)
    ) u_link_state_manager (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .clk_sideband           (clk_sideband),
        .rst_sideband_n         (rst_sideband_n),
        
        // Physical Layer Interface
        .phy_link_trained       (link_trained),
        .phy_lanes_active       (lanes_active),
        .training_complete      (training_complete),
        
        // Parameter Exchange
        .local_parameters       (local_parameters),
        .remote_parameters      (remote_parameters),
        
        // Link State Outputs
        .link_state             (current_link_state),
        .training_state         (current_training_state),
        .link_up                (link_up),
        .link_status            (link_status),
        .link_state_change      (link_state_change),
        
        // Power Management
        .power_state            (power_state),
        .power_transition_req   (power_transition_req),
        .power_transition_ack   (power_transition_ack),
        
        // ML Enhancement
        .ml_optimization_enable (ml_optimization_enable),
        .ml_prediction_valid    (ml_prediction_valid),
        .ml_bandwidth_pred      (ml_bandwidth_prediction),
        
        // Thermal Management
        .die_temperature        (die_temperature),
        .thermal_throttle       (thermal_throttle_req),
        
        // Debug
        .debug_select           (debug_select[3:0]),
        .debug_info             (debug_status[15:0])
    );
    
    // ========================================================================
    // Enhanced CRC and Retry Engine (4x Parallel for 128 Gbps)
    // ========================================================================
    
    ucie_enhanced_crc_retry #(
        .FLIT_WIDTH             (FLIT_WIDTH),
        .RETRY_BUFFER_DEPTH     (RETRY_BUFFER_DEPTH),
        .NUM_CRC_ENGINES        (ENABLE_ADVANCED_CRC ? 4 : 1),
        .ENABLE_PARALLEL_CRC    (MAX_SPEED_GBPS >= 128),
        .CRC_POLYNOMIAL         (32'h04C11DB7),  // CRC-32 IEEE 802.3
        .MAX_RETRY_COUNT        (16)
    ) u_crc_retry_engine (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // TX Path
        .tx_flit_in             (protocol_tx_flit),
        .tx_valid_in            (protocol_tx_valid & protocol_tx_ready),
        .tx_protocol_id         (protocol_tx_protocol_id),
        .tx_vc                  (protocol_tx_vc),
        
        .tx_flit_out            (crc_tx_flit),
        .tx_valid_out           (crc_tx_valid),
        .tx_ready_out           (crc_tx_ready),
        .tx_crc_value           (crc_tx_value),
        
        // RX Path
        .rx_flit_in             (phy_rx_flit),
        .rx_valid_in            (phy_rx_valid),
        .rx_ready_in            (phy_rx_ready),
        
        .rx_flit_out            (crc_rx_flit),
        .rx_valid_out           (crc_rx_valid),
        .rx_ready_out           (crc_rx_ready),
        .rx_crc_value           (crc_rx_value),
        .crc_error              (crc_error),
        
        // Retry Control
        .retry_request          (retry_request),
        .retry_ack              (retry_ack),
        .retry_sequence_num     (retry_sequence_num),
        
        // Buffer Management
        .buffer_data            (retry_buffer_data),
        .buffer_valid           (retry_buffer_valid),
        .buffer_ready           (retry_buffer_ready),
        
        // Statistics
        .retry_count            (retry_count),
        .error_count            (error_count),
        
        // Configuration
        .error_injection_enable (error_injection_enable),
        .error_injection_type   (error_injection_type)
    );
    
    // ========================================================================
    // Multi-Protocol Flow Control Manager (Enhanced for 128 Gbps)
    // ========================================================================
    
    ucie_multi_protocol_flow_control #(
        .NUM_PROTOCOLS          (NUM_PROTOCOLS),
        .NUM_VCS                (NUM_VCS),
        .CREDIT_WIDTH           (16),
        .ENABLE_ADAPTIVE_FLOW   (1),
        .ENABLE_ML_SHAPING      (1)
    ) u_flow_control (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Protocol Interface
        .protocol_active        (protocol_active),
        .protocol_priority      (protocol_priority),
        
        // TX Flow Control
        .tx_flit                (crc_tx_flit),
        .tx_valid               (crc_tx_valid),
        .tx_ready               (crc_tx_ready),
        .tx_protocol_id         (protocol_tx_protocol_id),
        .tx_vc                  (protocol_tx_vc),
        .tx_credits             (tx_credits),
        
        // RX Flow Control
        .rx_flit                (crc_rx_flit),
        .rx_valid               (crc_rx_valid),
        .rx_ready               (crc_rx_ready),
        .rx_protocol_id         (protocol_rx_protocol_id),
        .rx_vc                  (protocol_rx_vc),
        .rx_credits             (rx_credits),
        
        // Flow Control Status
        .credit_return          (credit_return),
        .flow_control_stop      (flow_control_stop),
        
        // Advanced Features
        .zero_latency_bypass    (zero_latency_bypass_active),
        .ml_traffic_shaping     (ml_traffic_shaping_active),
        .adaptive_threshold     (adaptive_buffer_threshold),
        
        // ML Enhancement
        .ml_optimization_enable (ml_optimization_enable),
        .ml_bandwidth_pred      (ml_bandwidth_prediction),
        .ml_prediction_valid    (ml_prediction_valid),
        
        // Performance Monitoring
        .bandwidth_utilization  (bandwidth_utilization),
        .buffer_occupancy       (buffer_occupancy)
    );
    
    // ========================================================================
    // Stack Multiplexer with Enhanced Arbitration
    // ========================================================================
    
    ucie_stack_multiplexer #(
        .FLIT_WIDTH             (FLIT_WIDTH),
        .NUM_PROTOCOLS          (NUM_PROTOCOLS),
        .NUM_VCS                (NUM_VCS),
        .ENABLE_WEIGHTED_ARB    (1),
        .ENABLE_ML_ARBITRATION  (1)
    ) u_stack_mux (
        .clk                    (clk),
        .rst_n                  (rst_n),
        
        // Protocol Layer Interface (Post Flow Control)
        .protocol_tx_flit       (crc_tx_flit),
        .protocol_tx_valid      (crc_tx_valid & ~|flow_control_stop),
        .protocol_tx_ready      (protocol_tx_ready),
        .protocol_tx_protocol_id(protocol_tx_protocol_id),
        .protocol_tx_vc         (protocol_tx_vc),
        
        .protocol_rx_flit       (protocol_rx_flit),
        .protocol_rx_valid      (protocol_rx_valid),
        .protocol_rx_ready      (protocol_rx_ready),  
        .protocol_rx_protocol_id(protocol_rx_protocol_id),
        .protocol_rx_vc         (protocol_rx_vc),
        
        // Physical Layer Interface
        .phy_tx_flit            (phy_tx_flit),
        .phy_tx_valid           (phy_tx_valid),
        .phy_tx_ready           (phy_tx_ready),
        
        .phy_rx_flit            (crc_rx_flit),
        .phy_rx_valid           (crc_rx_valid),
        .phy_rx_ready           (phy_rx_ready),
        
        // Configuration
        .protocol_enable        (protocol_enable),
        .protocol_priority      (protocol_priority),
        .protocol_active        (protocol_active),
        
        // Advanced Features
        .zero_latency_bypass    (zero_latency_bypass_active),
        .ml_arbitration_enable  (ml_optimization_enable),
        .ml_bandwidth_pred      (ml_bandwidth_prediction),
        
        // Link State
        .link_up                (link_up),
        .link_state             (current_link_state)
    );
    
    // ========================================================================
    // Multi-Module Coordination (Enhanced)
    // ========================================================================
    
    generate
    if (ENABLE_MULTI_MODULE) begin : gen_multi_module
        
        ucie_multi_module_coordinator #(
            .NUM_MODULES        (4),
            .COORDINATION_WIDTH (32),
            .ENABLE_LOAD_BALANCE(1)
        ) u_multi_module_coord (
            .clk                    (clk),
            .rst_n                  (rst_n),
            
            // Module Identification
            .module_id              (module_id),
            .num_modules            (num_modules),
            
            // Coordination Interface
            .coord_valid            (module_coord_valid),
            .coord_data             (module_coord_data),
            .coord_ready            (module_coord_ready),
            
            // Link State Synchronization
            .link_state             (current_link_state),
            .link_up                (link_up),
            
            // Power Coordination
            .power_state            (power_state),
            .power_transition_req   (power_transition_req),
            
            // Performance Coordination
            .bandwidth_utilization  (bandwidth_utilization),
            .load_balance_active    (ml_traffic_shaping_active)
        );
        
    end else begin : gen_single_module
        assign module_coord_valid = 1'b0;
        assign module_coord_data = 32'h0;
    end
    endgenerate
    
    // ========================================================================
    // Advanced Power Management
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            requested_power_state <= POWER_L0;
            current_micro_state <= MICRO_POWER_FULL;
            power_optimization_active <= 1'b0;
        end else begin
            // Power state management based on link state and thermal conditions
            case (current_link_state)
                LINK_RESET, LINK_DISABLED: begin
                    requested_power_state <= POWER_L2;
                    current_micro_state <= MICRO_POWER_SLEEP;
                end
                
                LINK_ACTIVE: begin
                    if (thermal_throttle_req) begin
                        requested_power_state <= POWER_L1;
                        current_micro_state <= MICRO_POWER_ECO;
                    end else if (bandwidth_utilization < 16'd1000) begin  // <10% util
                        requested_power_state <= POWER_L0;
                        current_micro_state <= MICRO_POWER_IDLE;
                    end else begin
                        requested_power_state <= POWER_L0;
                        current_micro_state <= MICRO_POWER_FULL;
                    end
                end
                
                default: begin
                    requested_power_state <= POWER_L1;
                    current_micro_state <= MICRO_POWER_IDLE;
                end
            endcase
            
            // Power optimization based on ML predictions and efficiency
            power_optimization_active <= ml_optimization_enable && 
                                        (bandwidth_utilization < 16'd5000); // <50% util
        end
    end
    
    // ========================================================================
    // Performance Monitoring and Statistics
    // ========================================================================
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_flit_count <= 32'h0;
            rx_flit_count <= 32'h0;
            link_uptime_counter <= 16'h0;
        end else begin
            // Count transmitted flits
            if (phy_tx_valid && phy_tx_ready) begin
                tx_flit_count <= tx_flit_count + 1;
            end
            
            // Count received flits  
            if (phy_rx_valid && phy_rx_ready) begin
                rx_flit_count <= rx_flit_count + 1;
            end
            
            // Link uptime counter
            if (link_up && (link_uptime_counter != 16'hFFFF)) begin
                link_uptime_counter <= link_uptime_counter + 1;
            end else if (!link_up) begin
                link_uptime_counter <= 16'h0;
            end
        end
    end
    
    // ========================================================================
    // Debug and Performance Counter Outputs
    // ========================================================================
    
    always_comb begin
        performance_counters = bandwidth_utilization;
        
        case (debug_select[7:4])
            4'h0: debug_status = {link_status, current_link_state, current_training_state, 8'h0};
            4'h1: debug_status = tx_flit_count;
            4'h2: debug_status = rx_flit_count;
            4'h3: debug_status = {16'h0, error_count[15:0]};
            4'h4: debug_status = {16'h0, retry_count[15:0]};
            4'h5: debug_status = {bandwidth_utilization, buffer_occupancy};
            4'h6: debug_status = {power_state, current_micro_state, die_temperature, 16'h0};
            4'h7: debug_status = {link_uptime_counter, 16'h0};
            default: debug_status = 32'hDEADBEEF;
        endcase
    end
    
    // ========================================================================
    // Configuration and Control Logic
    // ========================================================================
    
    always_comb begin
        // Protocol configuration based on link state
        protocol_enable = (link_up && (current_link_state == LINK_ACTIVE)) ? 
                         4'b1111 : 4'b0000;
        
        // Dynamic protocol priority based on ML predictions and thermal state
        if (ml_optimization_enable && ml_prediction_valid) begin
            // ML-enhanced priority assignment
            protocol_priority[0] = 8'd100;  // Management Transport (highest)
            protocol_priority[1] = thermal_throttle_req ? 8'd60 : 8'd80;  // CXL
            protocol_priority[2] = thermal_throttle_req ? 8'd40 : 8'd60;  // PCIe  
            protocol_priority[3] = 8'd20;   // Streaming (lowest)
        end else begin
            // Default priority assignment
            protocol_priority[0] = 8'd100;  // Management Transport
            protocol_priority[1] = 8'd80;   // CXL
            protocol_priority[2] = 8'd60;   // PCIe
            protocol_priority[3] = 8'd40;   // Streaming
        end
        
        // Zero-latency bypass for critical traffic
        zero_latency_bypass_active = ml_optimization_enable && 
                                   (protocol_tx_protocol_id == 4'h0) && // Management
                                   (current_micro_state == MICRO_POWER_FULL);
        
        // Adaptive buffer threshold based on utilization
        adaptive_buffer_threshold = (bandwidth_utilization > 16'd8000) ? 8'd200 : 8'd100;
    end

endmodule