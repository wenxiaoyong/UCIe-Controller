module ucie_controller_top
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int NUM_LANES = 64,
    parameter int NUM_PROTOCOLS = 4,
    parameter int NUM_VCS = 8,
    parameter int BUFFER_DEPTH = 32,
    parameter int SB_FREQ_MHZ = 800
) (
    // System Clocks and Reset
    input  logic                clk_main,      // Main system clock
    input  logic                clk_sb,        // 800MHz sideband clock
    input  logic                rst_n,
    
    // UCIe Physical Interface
    // Mainband Interface
    output logic                mb_clk_fwd,    // Forwarded clock
    output logic [NUM_LANES-1:0] mb_data,     // Data lanes
    output logic                mb_valid,      // Valid signal
    input  logic                mb_ready,      // Ready signal
    
    input  logic                mb_clk_fwd_in,
    input  logic [NUM_LANES-1:0] mb_data_in,
    input  logic                mb_valid_in,
    output logic                mb_ready_out,
    
    // Sideband Interface  
    output logic                sb_clk,
    output logic [7:0]          sb_data,
    output logic                sb_valid,
    input  logic                sb_ready,
    
    input  logic                sb_clk_in,
    input  logic [7:0]          sb_data_in,
    input  logic                sb_valid_in,
    output logic                sb_ready_out,
    
    // Upper Layer Protocol Interfaces
    // PCIe Interface
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] pcie_tx_flit,
    input  logic                pcie_tx_valid,
    output logic                pcie_tx_ready,
    input  logic [7:0]          pcie_tx_vc,
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] pcie_rx_flit,
    output logic                pcie_rx_valid,
    input  logic                pcie_rx_ready,
    output logic [7:0]          pcie_rx_vc,
    
    // CXL Interface
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] cxl_tx_flit,
    input  logic                cxl_tx_valid,
    output logic                cxl_tx_ready,
    input  logic [7:0]          cxl_tx_vc,
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] cxl_rx_flit,
    output logic                cxl_rx_valid,
    input  logic                cxl_rx_ready,
    output logic [7:0]          cxl_rx_vc,
    
    // Streaming Interface
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] stream_tx_flit,
    input  logic                stream_tx_valid,
    output logic                stream_tx_ready,
    input  logic [7:0]          stream_tx_vc,
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] stream_rx_flit,
    output logic                stream_rx_valid,
    input  logic                stream_rx_ready,
    output logic [7:0]          stream_rx_vc,
    
    // Management Interface
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] mgmt_tx_flit,
    input  logic                mgmt_tx_valid,
    output logic                mgmt_tx_ready,
    input  logic [7:0]          mgmt_tx_vc,
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] mgmt_rx_flit,
    output logic                mgmt_rx_valid,
    input  logic                mgmt_rx_ready,
    output logic [7:0]          mgmt_rx_vc,
    
    // Configuration Interface
    input  logic [31:0]         config_data,
    input  logic [15:0]         config_addr,
    input  logic                config_write,
    input  logic                config_read,
    output logic [31:0]         config_rdata,
    output logic                config_ready,
    
    // Power Management
    input  logic [1:0]          power_state_req,
    output logic [1:0]          power_state_ack,
    input  logic                wake_request,
    output logic                sleep_ready,
    
    // Link Training and Management
    input  logic                link_training_enable,
    output logic                link_training_complete,
    output logic                link_active,
    output logic                link_error,
    
    // Lane Management
    input  logic [7:0]          requested_width,
    output logic [7:0]          actual_width,
    output logic                width_degraded,
    input  logic [7:0]          min_width,
    
    // Status and Debug
    output logic [31:0]         controller_status,
    output logic [31:0]         link_status,
    output logic [31:0]         error_status,
    output logic [63:0]         performance_counters [3:0]
);

    // Internal Interfaces
    // Protocol Layer to D2D Adapter
    logic [ucie_pkg::FLIT_WIDTH-1:0] d2d_tx_flit;
    logic                  d2d_tx_valid;
    logic                  d2d_tx_ready;
    logic [3:0]            d2d_tx_protocol_id;
    logic [7:0]            d2d_tx_vc;
    
    logic [ucie_pkg::FLIT_WIDTH-1:0] d2d_rx_flit;
    logic                  d2d_rx_valid;
    logic                  d2d_rx_ready;
    logic [3:0]            d2d_rx_protocol_id;
    logic [7:0]            d2d_rx_vc;
    
    // D2D Adapter to Physical Layer
    logic [ucie_pkg::FLIT_WIDTH-1:0] phy_tx_flit;
    logic                  phy_tx_valid;
    logic                  phy_tx_ready;
    logic [31:0]           phy_tx_crc;
    
    logic [ucie_pkg::FLIT_WIDTH-1:0] phy_rx_flit;
    logic                  phy_rx_valid;
    logic                  phy_rx_ready;
    logic [31:0]           phy_rx_crc;
    
    // Sideband Interfaces
    logic [31:0]           param_tx_data;
    logic                  param_tx_valid;
    logic                  param_tx_ready;
    
    logic [31:0]           param_rx_data;
    logic                  param_rx_valid;
    logic                  param_rx_ready;
    
    // Parameter Exchange to Sideband Engine interface (PE outputs → SB inputs)
    logic [31:0]           pe_to_sb_tx_data;
    logic                  pe_to_sb_tx_valid;
    logic                  pe_to_sb_tx_ready;
    
    // Sideband Engine to Parameter Exchange interface (SB outputs → PE inputs)
    logic [31:0]           sb_to_pe_rx_data;
    logic                  sb_to_pe_rx_valid;
    logic                  sb_to_pe_rx_ready;
    
    // Lane Management Interfaces
    logic [NUM_LANES-1:0]  lane_enable;
    logic [NUM_LANES-1:0]  lane_active;
    logic [NUM_LANES-1:0]  lane_error;
    logic [NUM_LANES-1:0]  lane_good;
    logic [NUM_LANES-1:0]  lane_marginal;
    logic [NUM_LANES-1:0]  lane_failed;
    
    // Configuration Registers
    logic [31:0] config_regs [63:0];
    logic        config_protocol_enable [NUM_PROTOCOLS-1:0];
    logic [7:0]  config_protocol_priority [NUM_PROTOCOLS-1:0];
    logic [7:0]  config_vc_credits [NUM_PROTOCOLS-1:0][NUM_VCS-1:0];
    
    // Status Collection
    logic [31:0] protocol_stats [NUM_PROTOCOLS-1:0];
    logic [15:0] buffer_occupancy [NUM_PROTOCOLS-1:0];
    logic [31:0] layer_status;
    logic [15:0] protocol_error_count;
    
    // Additional status signals
    logic [NUM_PROTOCOLS-1:0] protocol_active;
    logic [7:0] vc_consumed [NUM_PROTOCOLS-1:0][NUM_VCS-1:0];
    logic crc_error;
    logic param_mismatch;
    logic power_param_valid;
    logic [7:0] negotiated_features;
    logic [15:0] exchange_status;
    logic [31:0] timeout_counter;
    logic [7:0] lane_map [NUM_LANES-1:0];
    logic [7:0] reverse_map [NUM_LANES-1:0];
    logic module_coordinator_req;
    logic [31:0] lane_status;
    logic [31:0] sb_status;
    logic [15:0] sb_error_count;
    logic [31:0] sb_debug_info;
    
    // Upper Layer Protocol Arrays
    logic [ucie_pkg::FLIT_WIDTH-1:0] ul_tx_flits [NUM_PROTOCOLS-1:0];
    logic [NUM_PROTOCOLS-1:0] ul_tx_valid;
    logic [NUM_PROTOCOLS-1:0] ul_tx_ready;
    logic [7:0] ul_tx_vcs [NUM_PROTOCOLS-1:0];
    
    logic [ucie_pkg::FLIT_WIDTH-1:0] ul_rx_flits [NUM_PROTOCOLS-1:0];
    logic [NUM_PROTOCOLS-1:0] ul_rx_valid;
    logic [NUM_PROTOCOLS-1:0] ul_rx_ready;
    logic [7:0] ul_rx_vcs [NUM_PROTOCOLS-1:0];
    
    // Map protocol interfaces to arrays
    assign ul_tx_flits[0] = pcie_tx_flit;
    assign ul_tx_flits[1] = cxl_tx_flit;
    assign ul_tx_flits[2] = stream_tx_flit;
    assign ul_tx_flits[3] = mgmt_tx_flit;
    
    assign ul_tx_valid[0] = pcie_tx_valid;
    assign ul_tx_valid[1] = cxl_tx_valid;
    assign ul_tx_valid[2] = stream_tx_valid;
    assign ul_tx_valid[3] = mgmt_tx_valid;
    
    assign pcie_tx_ready = ul_tx_ready[0];
    assign cxl_tx_ready = ul_tx_ready[1];
    assign stream_tx_ready = ul_tx_ready[2];
    assign mgmt_tx_ready = ul_tx_ready[3];
    
    assign ul_tx_vcs[0] = pcie_tx_vc;
    assign ul_tx_vcs[1] = cxl_tx_vc;
    assign ul_tx_vcs[2] = stream_tx_vc;
    assign ul_tx_vcs[3] = mgmt_tx_vc;
    
    assign pcie_rx_flit = ul_rx_flits[0];
    assign cxl_rx_flit = ul_rx_flits[1];
    assign stream_rx_flit = ul_rx_flits[2];
    assign mgmt_rx_flit = ul_rx_flits[3];
    
    assign pcie_rx_valid = ul_rx_valid[0];
    assign cxl_rx_valid = ul_rx_valid[1];
    assign stream_rx_valid = ul_rx_valid[2];
    assign mgmt_rx_valid = ul_rx_valid[3];
    
    assign ul_rx_ready[0] = pcie_rx_ready;
    assign ul_rx_ready[1] = cxl_rx_ready;
    assign ul_rx_ready[2] = stream_rx_ready;
    assign ul_rx_ready[3] = mgmt_rx_ready;
    
    assign pcie_rx_vc = ul_rx_vcs[0];
    assign cxl_rx_vc = ul_rx_vcs[1];
    assign stream_rx_vc = ul_rx_vcs[2];
    assign mgmt_rx_vc = ul_rx_vcs[3];
    
    // Configuration Register Management
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < 64; i++) begin
                config_regs[i] <= 32'h0;
            end
            
            // Default configuration
            config_regs[0] <= 32'h00000001; // Controller enable
            config_regs[1] <= 32'h0000000F; // All protocols enabled
            config_regs[2] <= 32'h03020100; // Protocol priorities
            config_regs[3] <= {8'd64, 8'd32, 8'd0, requested_width}; // Width config
        end else if (config_write && config_ready) begin
            if (config_addr < 64) begin
                config_regs[config_addr[5:0]] <= config_data;
            end
        end
    end
    
    // Extract configuration
    always_comb begin
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            config_protocol_enable[i] = config_regs[1][i];
            config_protocol_priority[i] = config_regs[2][i*8 +: 8];
        end
        
        // Default VC credits
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            for (int j = 0; j < NUM_VCS; j++) begin
                config_vc_credits[i][j] = 8'd16; // Default 16 credits per VC
            end
        end
    end
    
    // Configuration read logic
    always_comb begin
        config_ready = 1'b1;
        if (config_read && config_addr < 64) begin
            config_rdata = config_regs[config_addr[5:0]];
        end else begin
            config_rdata = 32'h0;
        end
    end
    
    // Protocol Layer Instance
    ucie_protocol_layer #(
        .NUM_PROTOCOLS(NUM_PROTOCOLS),
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .NUM_VCS(NUM_VCS)
    ) protocol_layer_inst (
        .clk(clk_main),
        .rst_n(rst_n),
        
        // Upper Layer Interface
        .ul_tx_flit(ul_tx_flits),
        .ul_tx_valid(ul_tx_valid),
        .ul_tx_ready(ul_tx_ready),
        .ul_tx_vc(ul_tx_vcs),
        
        .ul_rx_flit(ul_rx_flits),
        .ul_rx_valid(ul_rx_valid),
        .ul_rx_ready(ul_rx_ready),
        .ul_rx_vc(ul_rx_vcs),
        
        // D2D Adapter Interface
        .d2d_tx_flit(d2d_tx_flit),
        .d2d_tx_valid(d2d_tx_valid),
        .d2d_tx_ready(d2d_tx_ready),
        .d2d_tx_protocol_id(d2d_tx_protocol_id),
        .d2d_tx_vc(d2d_tx_vc),
        
        .d2d_rx_flit(d2d_rx_flit),
        .d2d_rx_valid(d2d_rx_valid),
        .d2d_rx_ready(d2d_rx_ready),
        .d2d_rx_protocol_id(d2d_rx_protocol_id),
        .d2d_rx_vc(d2d_rx_vc),
        
        // Configuration
        .protocol_enable({config_protocol_enable[3], config_protocol_enable[2], 
                          config_protocol_enable[1], config_protocol_enable[0]}),
        .protocol_priority(config_protocol_priority),
        .protocol_active(protocol_active),
        
        // Virtual Channel Flow Control
        .vc_credits(config_vc_credits),
        .vc_consumed(vc_consumed),
        
        // Protocol-Specific Features
        .pcie_mode(1'b1),
        .cxl_mode(2'b01),
        .streaming_channels(8'd8),
        .mgmt_enable(1'b1),
        
        // Performance Monitoring
        .protocol_stats(protocol_stats),
        .buffer_occupancy(buffer_occupancy),
        
        // Status
        .layer_status(layer_status),
        .error_count(protocol_error_count)
    );
    
    // D2D Adapter Instances
    // CRC/Retry Engine
    logic retry_request, retry_in_progress, retry_buffer_full;
    logic [7:0] retry_sequence_num;
    logic [15:0] crc_error_count, retry_count;
    logic [7:0] buffer_occupancy_crc;
    
    ucie_crc_retry_engine #(
        .CUSTOM_BUFFER_DEPTH(64),
        .CUSTOM_MAX_RETRY(7)
    ) crc_retry_inst (
        .clk(clk_main),
        .rst_n(rst_n),
        
        // Transmit Path
        .tx_flit_in(d2d_tx_flit),
        .tx_flit_valid(d2d_tx_valid),
        .tx_flit_ready(d2d_tx_ready),
        
        .tx_flit_out(phy_tx_flit),
        .tx_flit_valid_out(phy_tx_valid),
        .tx_flit_ready_in(phy_tx_ready),
        
        // Receive Path
        .rx_flit_in(phy_rx_flit),
        .rx_flit_valid(phy_rx_valid),
        .rx_flit_ready(phy_rx_ready),
        
        .rx_flit_out(d2d_rx_flit),
        .rx_flit_valid_out(d2d_rx_valid),
        .rx_flit_ready_in(d2d_rx_ready),
        
        // CRC Interface
        .tx_crc(phy_tx_crc),
        .rx_crc(phy_rx_crc),
        .crc_error(crc_error),
        
        // Retry Control
        .retry_request(retry_request),
        .retry_sequence_num(retry_sequence_num),
        .retry_in_progress(retry_in_progress),
        .retry_buffer_full(retry_buffer_full),
        
        // Status
        .crc_error_count(crc_error_count),
        .retry_count(retry_count),
        .buffer_occupancy(buffer_occupancy_crc)
    );
    
    // Parameter Exchange
    logic param_exchange_start, param_exchange_complete, param_exchange_error;
    logic [7:0] negotiated_speed, negotiated_width;
    logic [3:0] negotiated_protocols;
    logic [31:0] local_params [15:0];
    logic [31:0] remote_params [15:0];
    
    // Initialize local parameters
    always_comb begin
        local_params[0] = 32'h00000020; // Max speed: 32 GT/s
        local_params[1] = {24'h0, requested_width}; // Requested width
        local_params[2] = 32'h0000000F; // Protocol support
        local_params[3] = 32'h000000FF; // Feature support
        for (int i = 4; i < 16; i++) begin
            local_params[i] = 32'h0;
        end
    end
    
    ucie_param_exchange #(
        .PARAM_WIDTH(32),
        .TIMEOUT_CYCLES(1000000),
        .NUM_PARAM_REGS(16)
    ) param_exchange_inst (
        .clk(clk_main),
        .clk_aux(clk_sb),
        .rst_n(rst_n),
        
        // Sideband Interface (param_exchange outputs to sideband_engine inputs)
        .sb_tx_data(pe_to_sb_tx_data),     // param_exchange → sideband_engine
        .sb_tx_valid(pe_to_sb_tx_valid),   // param_exchange → sideband_engine
        .sb_tx_ready(pe_to_sb_tx_ready),   // sideband_engine → param_exchange
        
        // Sideband Interface (sideband_engine outputs to param_exchange inputs)  
        .sb_rx_data(sb_to_pe_rx_data),     // sideband_engine → param_exchange
        .sb_rx_valid(sb_to_pe_rx_valid),   // sideband_engine → param_exchange
        .sb_rx_ready(sb_to_pe_rx_ready),   // param_exchange → sideband_engine
        
        // Parameter Configuration
        .local_params(local_params),
        .remote_params(remote_params),
        
        // Control Interface
        .param_exchange_start(param_exchange_start),
        .param_exchange_complete(param_exchange_complete),
        .param_exchange_error(param_exchange_error),
        .param_mismatch(param_mismatch),
        
        // Power Management Integration
        .power_state(power_state_req),
        .power_param_valid(power_param_valid),
        .wake_param_request(wake_request),
        .sleep_param_ready(sleep_ready),
        
        // Negotiated Parameters
        .negotiated_speed(negotiated_speed),
        .negotiated_width(negotiated_width),
        .negotiated_protocols(negotiated_protocols),
        .negotiated_features(negotiated_features),
        
        // Status
        .exchange_status(exchange_status),
        .timeout_counter(timeout_counter)
    );
    
    // Lane Manager
    logic lane_mgmt_enable, reversal_detected, reversal_corrected;
    logic repair_enable, repair_active, width_degraded_lane;
    logic [NUM_LANES-1:0] repair_lanes;
    logic [7:0] good_lane_count;
    logic [15:0] lane_ber [NUM_LANES-1:0];
    
    // Initialize BER values (would come from PHY in real implementation)
    always_comb begin
        for (int i = 0; i < NUM_LANES; i++) begin
            lane_ber[i] = 16'h0100; // Low BER value
        end
    end
    
    ucie_lane_manager #(
        .NUM_LANES(NUM_LANES),
        .REPAIR_LANES(8),
        .MIN_WIDTH(8)
    ) lane_manager_inst (
        .clk(clk_main),
        .rst_n(rst_n),
        
        // Lane Control Interface
        .lane_mgmt_enable(lane_mgmt_enable),
        .lane_enable(lane_enable),
        .lane_active(lane_active),
        .lane_error(lane_error),
        
        // Lane Mapping
        .lane_map(lane_map),
        .reverse_map(reverse_map),
        .reversal_detected(reversal_detected),
        .reversal_corrected(reversal_corrected),
        
        // Width Management
        .requested_width(requested_width),
        .actual_width(actual_width),
        .width_degraded(width_degraded),
        .min_width(min_width),
        
        // Repair Management
        .repair_enable(repair_enable),
        .repair_active(repair_active),
        .repair_lanes(repair_lanes),
        .ber_threshold(16'h1000),
        .lane_ber(lane_ber),
        
        // Module Coordination
        .module_id(4'h0),
        .num_modules(4'h1),
        .module_coordinator_req(module_coordinator_req),
        .module_coordinator_ack(1'b1),
        
        // Lane Status
        .lane_good(lane_good),
        .lane_marginal(lane_marginal),
        .lane_failed(lane_failed),
        .good_lane_count(good_lane_count),
        
        // Configuration
        .lane_config(config_regs[16]),
        .lane_status(lane_status)
    );
    
    // Sideband Engine
    logic training_enable, training_complete, training_error;
    logic [15:0] training_pattern, received_pattern;
    logic [NUM_LANES-1:0] lane_enable_req, lane_enable_ack;
    logic [7:0] width_req, width_ack;
    
    ucie_sideband_engine #(
        .SB_FREQ_MHZ(SB_FREQ_MHZ),
        .NUM_LANES(NUM_LANES),
        .PARAM_WIDTH(32),
        .TIMEOUT_CYCLES(800000)
    ) sideband_engine_inst (
        .clk_sb(clk_sb),
        .clk_main(clk_main),
        .rst_n(rst_n),
        
        // Sideband Physical Interface
        .sb_clk(sb_clk),
        .sb_data(sb_data),
        .sb_valid(sb_valid),
        .sb_ready(sb_ready),
        
        .sb_clk_in(sb_clk_in),
        .sb_data_in(sb_data_in),
        .sb_valid_in(sb_valid_in),
        .sb_ready_out(sb_ready_out),
        
        // Parameter Exchange Interface (sideband_engine outputs to param_exchange inputs)
        .param_tx_data(sb_to_pe_rx_data),    // sideband_engine → param_exchange
        .param_tx_valid(sb_to_pe_rx_valid),  // sideband_engine → param_exchange
        .param_tx_ready(sb_to_pe_rx_ready),  // param_exchange → sideband_engine
        
        // Parameter Exchange Interface (param_exchange outputs to sideband_engine inputs)
        .param_rx_data(pe_to_sb_tx_data),    // param_exchange → sideband_engine
        .param_rx_valid(pe_to_sb_tx_valid),  // param_exchange → sideband_engine
        .param_rx_ready(pe_to_sb_tx_ready),  // sideband_engine → param_exchange
        
        // Link Training Interface
        .training_enable(training_enable),
        .training_complete(training_complete),
        .training_error(training_error),
        .training_pattern(training_pattern),
        .received_pattern(received_pattern),
        
        // Power Management Interface
        .power_state_req(power_state_req),
        .power_state_ack(power_state_ack),
        .wake_request(wake_request),
        .sleep_ready(sleep_ready),
        
        // Lane Management Interface
        .lane_enable_req(lane_enable_req),
        .lane_enable_ack(lane_enable_ack),
        .width_req(width_req),
        .width_ack(width_ack),
        
        // Configuration
        .sb_config(config_regs[32]),
        .sb_status(sb_status),
        
        // Error and Debug
        .sb_error_count(sb_error_count),
        .sb_debug_info(sb_debug_info)
    );
    
    // Control Logic
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            param_exchange_start <= 1'b0;
            lane_mgmt_enable <= 1'b0;
            training_enable <= 1'b0;
            repair_enable <= 1'b0;
            retry_request <= 1'b0;
        end else begin
            // Start parameter exchange on reset deassertion
            if (config_regs[0][0]) begin // Controller enable
                param_exchange_start <= 1'b1;
                lane_mgmt_enable <= 1'b1;
                training_enable <= link_training_enable;
                repair_enable <= 1'b1;
            end
            
            // Request retry on CRC errors
            retry_request <= (crc_error_count > 0) && !retry_in_progress;
        end
    end
    
    // Physical Interface (simplified - would connect to actual PHY)
    assign mb_clk_fwd = clk_main;
    assign mb_data = phy_tx_flit[NUM_LANES-1:0]; // Map flit to lanes
    assign mb_valid = phy_tx_valid;
    assign phy_tx_ready = mb_ready;
    
    assign phy_rx_flit = {{(FLIT_WIDTH-NUM_LANES){1'b0}}, mb_data_in};
    assign phy_rx_valid = mb_valid_in;
    assign mb_ready_out = phy_rx_ready;
    assign phy_rx_crc = 32'h0; // Simplified - would come from PHY
    
    // Status and Monitoring
    assign link_training_complete = training_complete;
    assign link_active = (actual_width > 0) && !training_error;
    assign link_error = training_error || param_exchange_error;
    
    assign controller_status = {
        8'h0,                    // Reserved
        4'h0,                    // Reserved  
        negotiated_protocols,    // Negotiated protocols
        actual_width,            // Current width
        negotiated_speed         // Current speed
    };
    
    assign link_status = {
        17'h0,                   // Reserved
        width_degraded,          // Width degraded
        repair_active,           // Repair active
        retry_in_progress,       // Retry in progress
        reversal_corrected,      // Reversal corrected
        training_complete,       // Training complete
        param_exchange_complete, // Param exchange complete
        link_active,             // Link active
        good_lane_count          // Good lane count
    };
    
    assign error_status = {
        protocol_error_count,    // Protocol layer errors
        crc_error_count          // CRC errors
    };
    
    assign performance_counters[0] = {32'h0, protocol_stats[0]};  // PCIe stats
    assign performance_counters[1] = {32'h0, protocol_stats[1]};  // CXL stats
    assign performance_counters[2] = {32'h0, protocol_stats[2]};  // Streaming stats
    assign performance_counters[3] = {32'h0, protocol_stats[3]};  // Management stats

endmodule
