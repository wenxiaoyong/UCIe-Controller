module ucie_controller_top_enhanced
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    // System Configuration
    parameter NUM_LANES = 64,
    parameter NUM_MODULES = 4,
    parameter NUM_PROTOCOLS = 8,
    parameter FLIT_WIDTH = 256,
    
    // 128 Gbps Enhancement Parameters
    parameter ENHANCED_128G = 1,
    parameter PAM4_SIGNALING = 1,
    parameter ADVANCED_EQUALIZATION = 1,
    parameter POWER_OPTIMIZATION = 1,
    
    // ML Enhancement Parameters
    parameter ML_ENHANCED = 1,
    parameter ML_THERMAL_MGMT = 1,
    parameter ML_LANE_OPTIMIZATION = 1,
    parameter ML_FLOW_CONTROL = 1,
    
    // Advanced Feature Parameters
    parameter MULTI_MODULE_SUPPORT = 1,
    parameter ADVANCED_CRC_RETRY = 1,
    parameter ENHANCED_PARAMETER_EXCHANGE = 1,
    parameter COMPREHENSIVE_THERMAL_MGMT = 1
) (
    // Primary System Clocks and Reset
    input  logic                sys_clk,           // Main system clock
    input  logic                sys_rst_n,         // System reset (active low)
    input  logic                ref_clk,           // Reference clock for PLLs
    input  logic                sideband_clk,      // 800 MHz sideband clock
    
    // High-Speed Differential Clocks (128 Gbps)
    input  logic                hs_clk_p,          // High-speed clock positive
    input  logic                hs_clk_n,          // High-speed clock negative
    output logic                hs_clk_out_p,      // Forwarded clock positive
    output logic                hs_clk_out_n,      // Forwarded clock negative
    
    // Configuration and Control
    input  logic [3:0]          module_id,
    input  logic [3:0]          total_modules,
    input  logic                controller_enable,
    input  logic [7:0]          target_data_rate,  // GT/s
    input  logic [7:0]          target_lanes,
    input  signaling_mode_t     signaling_mode,
    input  package_type_t       package_type,
    
    // High-Speed Differential Data Lanes
    input  logic [NUM_LANES-1:0] rx_data_p,
    input  logic [NUM_LANES-1:0] rx_data_n,
    output logic [NUM_LANES-1:0] tx_data_p,
    output logic [NUM_LANES-1:0] tx_data_n,
    
    // Sideband Interface (800 MHz always-on)
    input  logic                sb_rx_data,
    input  logic                sb_rx_valid,
    output logic                sb_rx_ready,
    output logic                sb_tx_data,
    output logic                sb_tx_valid,
    input  logic                sb_tx_ready,
    
    // Protocol Layer Interfaces
    // PCIe Interface
    input  logic                pcie_clk,
    input  logic                pcie_rst_n,
    input  logic [FLIT_WIDTH-1:0] pcie_tx_data,
    input  logic                pcie_tx_valid,
    input  logic                pcie_tx_sop,
    input  logic                pcie_tx_eop,
    output logic                pcie_tx_ready,
    output logic [FLIT_WIDTH-1:0] pcie_rx_data,
    output logic                pcie_rx_valid,
    output logic                pcie_rx_sop,
    output logic                pcie_rx_eop,
    input  logic                pcie_rx_ready,
    
    // CXL Interface (I/O, Cache, Memory)
    input  logic                cxl_clk,
    input  logic                cxl_rst_n,
    input  logic [FLIT_WIDTH-1:0] cxl_tx_data [2:0], // I/O, Cache, Memory
    input  logic [2:0]          cxl_tx_valid,
    input  logic [2:0]          cxl_tx_sop,
    input  logic [2:0]          cxl_tx_eop,
    output logic [2:0]          cxl_tx_ready,
    output logic [FLIT_WIDTH-1:0] cxl_rx_data [2:0],
    output logic [2:0]          cxl_rx_valid,
    output logic [2:0]          cxl_rx_sop,
    output logic [2:0]          cxl_rx_eop,
    input  logic [2:0]          cxl_rx_ready,
    
    // Streaming Protocol Interface
    input  logic                stream_clk,
    input  logic                stream_rst_n,
    input  logic [FLIT_WIDTH-1:0] stream_tx_data,
    input  logic                stream_tx_valid,
    input  logic                stream_tx_sop,
    input  logic                stream_tx_eop,
    output logic                stream_tx_ready,
    output logic [FLIT_WIDTH-1:0] stream_rx_data,
    output logic                stream_rx_valid,
    output logic                stream_rx_sop,
    output logic                stream_rx_eop,
    input  logic                stream_rx_ready,
    
    // Management Interface
    input  logic                mgmt_clk,
    input  logic                mgmt_rst_n,
    input  logic [31:0]         mgmt_addr,
    input  logic [31:0]         mgmt_wdata,
    input  logic                mgmt_write,
    input  logic                mgmt_read,
    output logic [31:0]         mgmt_rdata,
    output logic                mgmt_ready,
    output logic                mgmt_error,
    
    // Power Management Interface
    input  micro_power_state_t  requested_power_state,
    input  logic                thermal_throttle_req,
    input  temperature_t        ambient_temperature,
    output micro_power_state_t  current_power_state,
    output logic                power_state_ack,
    output logic [15:0]         total_power_consumption,
    
    // ML Enhancement Interface
    input  logic                ml_enable,
    input  logic [7:0]          ml_optimization_weight,
    input  logic [7:0]          ml_thermal_weight,
    output logic [15:0]         ml_performance_score,
    output logic [7:0]          ml_thermal_score,
    output logic [7:0]          ml_efficiency_score,
    
    // Advanced Monitoring and Debug
    output logic [31:0]         controller_status,
    output logic [15:0]         link_quality_score,
    output logic [15:0]         system_throughput_gbps,
    output logic [NUM_LANES-1:0] lane_status,
    output logic [15:0]         error_count,
    output logic [7:0]          retry_count,
    
    // Multi-Module Coordination
    input  logic [31:0]         inter_module_sync,
    output logic [31:0]         module_status_out,
    output logic                module_ready,
    output logic                global_link_up,
    
    // Emergency and Safety
    output logic                emergency_shutdown,
    output logic                link_degradation_alarm,
    output logic                thermal_emergency,
    
    // Test and Debug Interface
    input  logic                test_mode,
    input  logic [7:0]          test_pattern,
    output logic [31:0]         debug_bus
);

    // Internal Clock Generation and Management
    logic core_clk;              // Core logic clock
    logic phy_clk;               // High-speed PHY clock
    logic quarter_rate_clk;      // Quarter-rate clock for 128 Gbps
    logic pll_locked;
    logic clk_domains_ready;
    
    // Internal Reset Management
    logic core_rst_n;
    logic phy_rst_n;
    logic thermal_rst_n;
    logic [7:0] reset_sync_chain;
    
    // Inter-Module Communication Buses
    // Protocol Layer to D2D Adapter
    logic [NUM_PROTOCOLS-1:0]    ul_flit_valid;
    logic [FLIT_WIDTH-1:0]       ul_flit_data [NUM_PROTOCOLS-1:0];
    logic [NUM_PROTOCOLS-1:0]    ul_flit_sop;
    logic [NUM_PROTOCOLS-1:0]    ul_flit_eop;
    protocol_type_t              ul_protocol_type [NUM_PROTOCOLS-1:0];
    logic [2:0]                  ul_vc_id [NUM_PROTOCOLS-1:0];
    logic [3:0]                  ul_priority [NUM_PROTOCOLS-1:0];
    logic [NUM_PROTOCOLS-1:0]    ul_flit_ready;
    
    // D2D Adapter to Physical Layer
    logic                        dl_flit_valid;
    logic [FLIT_WIDTH-1:0]       dl_flit_data;
    logic                        dl_flit_sop;
    logic                        dl_flit_eop;
    logic [3:0]                  dl_flit_be;
    protocol_type_t              dl_protocol_type;
    logic [7:0]                  dl_vc_global_id;
    logic                        dl_flit_ready;
    
    // Physical Layer Connections
    logic                        phy_tx_valid;
    logic [FLIT_WIDTH-1:0]       phy_tx_data;
    logic                        phy_tx_sop;
    logic                        phy_tx_eop;
    logic [31:0]                 phy_tx_crc;
    logic [15:0]                 phy_tx_sequence;
    logic                        phy_tx_ready;
    
    logic                        phy_rx_valid;
    logic [FLIT_WIDTH-1:0]       phy_rx_data;
    logic                        phy_rx_sop;
    logic                        phy_rx_eop;
    logic [31:0]                 phy_rx_crc;
    logic [15:0]                 phy_rx_sequence;
    logic                        phy_rx_ready;
    
    // Lane Management Signals
    logic [NUM_LANES-1:0]        phy_lane_ready;
    logic [NUM_LANES-1:0]        phy_lane_error;
    logic [NUM_LANES-1:0]        phy_lane_trained;
    logic [7:0]                  phy_signal_quality [NUM_LANES-1:0];
    logic [15:0]                 phy_error_count [NUM_LANES-1:0];
    logic [NUM_LANES-1:0]        phy_lane_enable;
    logic [NUM_LANES-1:0]        phy_lane_reset;
    
    // Thermal Management Signals
    temperature_t                lane_temperature [NUM_LANES-1:0];
    power_mw_t                   lane_power [NUM_LANES-1:0];
    logic [NUM_LANES-1:0]        thermal_throttle_lanes;
    logic [NUM_LANES-1:0]        thermal_alarm_lanes;
    logic [7:0]                  power_scale_factor [NUM_LANES-1:0];
    logic [3:0]                  voltage_scale [NUM_LANES-1:0];
    logic [3:0]                  frequency_scale [NUM_LANES-1:0];
    
    // Link State Management
    link_state_t                 current_link_state;
    logic [31:0]                 link_state_status;
    logic [15:0]                 state_transition_count;
    logic [31:0]                 link_uptime_cycles;
    
    // Flow Control and Credit Management
    logic [63:0]                 credit_return;
    logic [15:0]                 credit_count [63:0];
    logic [63:0]                 credit_grant;
    logic [15:0]                 credit_available [63:0];
    
    // Parameter Exchange Signals
    ucie_capability_t            local_capabilities;
    ucie_capability_t            remote_capabilities [NUM_MODULES-1:0];
    logic [7:0]                  negotiated_data_rate;
    logic [7:0]                  negotiated_lane_count;
    signaling_mode_t             negotiated_signaling;
    logic [NUM_MODULES-1:0]      module_compatibility;
    logic                        param_exchange_complete;
    
    // ML Enhancement Signals
    logic [15:0]                 ml_lane_prediction [NUM_LANES-1:0];
    logic [15:0]                 ml_thermal_prediction [NUM_LANES-1:0];
    logic [15:0]                 ml_bandwidth_predict [NUM_PROTOCOLS-1:0];
    logic [7:0]                  ml_lane_optimization_score;
    logic [7:0]                  ml_thermal_optimization_score;
    logic [7:0]                  ml_flow_optimization_score;
    logic [15:0]                 ml_negotiation_score;
    
    // Error and Performance Monitoring
    logic [15:0]                 crc_error_count;
    logic [15:0]                 retry_count_int;
    logic [15:0]                 training_failure_count;
    logic [31:0]                 total_throughput_mbps;
    logic [15:0]                 average_latency_ns;
    logic [7:0]                  arbitration_efficiency;
    
    // Advanced Feature Status
    logic                        lane_repair_active;
    logic                        parameter_exchange_active;
    logic                        thermal_management_active;
    logic                        ml_optimization_active;
    
    // ================================================
    // Clock and Reset Management
    // ================================================
    
    // Multi-domain clock generation for 128 Gbps operation
    ucie_clock_manager #(
        .ENHANCED_128G(ENHANCED_128G),
        .PAM4_SIGNALING(PAM4_SIGNALING)
    ) i_clock_manager (
        .ref_clk(ref_clk),
        .hs_clk_p(hs_clk_p),
        .hs_clk_n(hs_clk_n),
        .rst_n(sys_rst_n),
        .core_clk(core_clk),
        .phy_clk(phy_clk),
        .quarter_rate_clk(quarter_rate_clk),
        .hs_clk_out_p(hs_clk_out_p),
        .hs_clk_out_n(hs_clk_out_n),
        .pll_locked(pll_locked),
        .clk_ready(clk_domains_ready)
    );
    
    // Synchronized reset generation
    always_ff @(posedge core_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            reset_sync_chain <= 8'h00;
            core_rst_n <= 1'b0;
            phy_rst_n <= 1'b0;
            thermal_rst_n <= 1'b0;
        end else begin
            reset_sync_chain <= {reset_sync_chain[6:0], (pll_locked && clk_domains_ready)};
            core_rst_n <= reset_sync_chain[7];
            phy_rst_n <= reset_sync_chain[6];
            thermal_rst_n <= reset_sync_chain[5];
        end
    end
    
    // ================================================
    // Enhanced Physical Layer (128 Gbps PAM4)
    // ================================================
    
    ucie_physical_layer_enhanced #(
        .NUM_LANES(NUM_LANES),
        .ENHANCED_128G(ENHANCED_128G),
        .PAM4_SIGNALING(PAM4_SIGNALING),
        .ADVANCED_EQUALIZATION(ADVANCED_EQUALIZATION),
        .ML_LANE_OPTIMIZATION(ML_LANE_OPTIMIZATION)
    ) i_physical_layer (
        .clk(phy_clk),
        .rst_n(phy_rst_n),
        .quarter_rate_clk(quarter_rate_clk),
        
        // Configuration
        .phy_enable(controller_enable),
        .signaling_mode(negotiated_signaling),
        .data_rate(negotiated_data_rate),
        .lane_count(negotiated_lane_count),
        
        // High-speed differential lanes
        .rx_data_p(rx_data_p),
        .rx_data_n(rx_data_n),
        .tx_data_p(tx_data_p),
        .tx_data_n(tx_data_n),
        
        // Data interface to D2D adapter
        .tx_flit_valid(phy_tx_valid),
        .tx_flit_data(phy_tx_data),
        .tx_flit_sop(phy_tx_sop),
        .tx_flit_eop(phy_tx_eop),
        .tx_flit_crc(phy_tx_crc),
        .tx_flit_sequence(phy_tx_sequence),
        .tx_flit_ready(phy_tx_ready),
        
        .rx_flit_valid(phy_rx_valid),
        .rx_flit_data(phy_rx_data),
        .rx_flit_sop(phy_rx_sop),
        .rx_flit_eop(phy_rx_eop),
        .rx_flit_crc(phy_rx_crc),
        .rx_flit_sequence(phy_rx_sequence),
        .rx_flit_ready(phy_rx_ready),
        
        // Lane management
        .lane_ready(phy_lane_ready),
        .lane_error(phy_lane_error),
        .lane_trained(phy_lane_trained),
        .signal_quality(phy_signal_quality),
        .error_count(phy_error_count),
        .lane_enable(phy_lane_enable),
        .lane_reset(phy_lane_reset),
        
        // Power and thermal
        .lane_power(lane_power),
        .lane_temperature(lane_temperature),
        .thermal_throttle(thermal_throttle_lanes),
        .power_scale_factor(power_scale_factor),
        .voltage_scale(voltage_scale),
        .frequency_scale(frequency_scale),
        
        // ML enhancement
        .ml_enable(ml_enable),
        .ml_lane_prediction(ml_lane_prediction),
        .ml_optimization_score(ml_lane_optimization_score)
    );
    
    // ================================================
    // Comprehensive Thermal Management
    // ================================================
    
    if (COMPREHENSIVE_THERMAL_MGMT) begin : gen_thermal_manager
        ucie_thermal_manager #(
            .NUM_LANES(NUM_LANES),
            .POWER_OPTIMIZATION(POWER_OPTIMIZATION),
            .PROCESS_COMPENSATION(1)
        ) i_thermal_manager (
            .clk(core_clk),
            .rst_n(thermal_rst_n),
            
            .thermal_enable(controller_enable),
            .ambient_temperature(ambient_temperature),
            .process_corner(8'h40), // TT corner
            
            .lane_power(lane_power),
            .lane_enable(phy_lane_enable),
            .lane_temperature(lane_temperature),
            .thermal_throttle_req(thermal_throttle_lanes),
            .thermal_alarm(thermal_alarm_lanes),
            
            .power_scale_factor(power_scale_factor),
            .voltage_scale(voltage_scale),
            .frequency_scale(frequency_scale),
            
            .global_throttle_enable(thermal_throttle_req),
            .throttle_threshold_temp(8'd85), // 85°C
            .throttle_release_temp(8'd75),   // 75°C
            .emergency_shutdown_req(thermal_emergency),
            
            .ml_thermal_enable(ML_THERMAL_MGMT && ml_enable),
            .ml_prediction_weight(ml_thermal_weight),
            .thermal_prediction(ml_thermal_prediction),
            .ml_thermal_score(ml_thermal_optimization_score),
            
            .total_power_consumption(total_power_consumption)
        );
        
        assign thermal_management_active = |thermal_throttle_lanes;
    end else begin
        assign thermal_throttle_lanes = '0;
        assign thermal_alarm_lanes = '0;
        assign power_scale_factor = '{default: 8'hFF};
        assign voltage_scale = '{default: 4'h8};
        assign frequency_scale = '{default: 4'h1};
        assign thermal_emergency = 1'b0;
        assign total_power_consumption = 16'h0;
        assign ml_thermal_optimization_score = 8'h80;
        assign thermal_management_active = 1'b0;
    end
    
    // ================================================
    // Advanced Lane Management System
    // ================================================
    
    ucie_advanced_lane_manager #(
        .NUM_LANES(NUM_LANES),
        .ENHANCED_128G(ENHANCED_128G),
        .ML_LANE_OPTIMIZATION(ML_LANE_OPTIMIZATION),
        .DYNAMIC_REMAPPING(1),
        .REDUNDANCY_SUPPORT(1)
    ) i_lane_manager (
        .clk(core_clk),
        .rst_n(core_rst_n),
        
        .lane_mgmt_enable(controller_enable),
        .target_lane_count(target_lanes),
        .min_lane_count(target_lanes >> 1), // 50% minimum
        .signaling_mode(negotiated_signaling),
        .data_rate(negotiated_data_rate),
        
        .phy_lane_ready(phy_lane_ready),
        .phy_lane_error(phy_lane_error),
        .phy_lane_trained(phy_lane_trained),
        .phy_signal_quality(phy_signal_quality),
        .phy_error_count(phy_error_count),
        .phy_lane_enable(phy_lane_enable),
        .phy_lane_reset(phy_lane_reset),
        
        .lane_reversal_enable(1'b0),
        .lane_polarity_invert('0),
        
        .repair_enable(1'b1),
        .repair_threshold_errors(8'd20),
        .repair_timeout_cycles(16'd1000),
        .lane_repair_active(lane_status),
        
        .redundant_lane_available('0),
        .redundancy_ratio(8'd10), // 10% redundancy
        
        .ber_threshold(16'd100),
        .quality_threshold(8'd150),
        
        .ml_enable(ML_LANE_OPTIMIZATION && ml_enable),
        .ml_prediction_confidence(8'hC0),
        .ml_lane_prediction(ml_lane_prediction),
        .ml_optimization_score(ml_lane_optimization_score),
        
        .pam4_mode(negotiated_signaling == SIG_PAM4),
        .parallel_lane_groups(4'h4),
        .adaptive_equalization(ADVANCED_EQUALIZATION),
        
        .lane_temperature(lane_temperature),
        .thermal_throttle(thermal_throttle_lanes),
        
        .link_degradation_alarm(link_degradation_alarm)
    );
    
    assign lane_repair_active = |lane_status;
    
    // ================================================
    // Enhanced D2D Adapter with Advanced Features
    // ================================================
    
    // Advanced Link State Manager
    ucie_advanced_link_state_manager #(
        .NUM_LANES(NUM_LANES),
        .ENHANCED_128G(ENHANCED_128G),
        .ML_STATE_PREDICTION(ML_ENHANCED),
        .ADVANCED_POWER_MGMT(1),
        .MULTI_MODULE_SUPPORT(MULTI_MODULE_SUPPORT)
    ) i_link_state_manager (
        .clk(core_clk),
        .rst_n(core_rst_n),
        
        .link_enable(controller_enable),
        .target_data_rate(negotiated_data_rate),
        .target_lanes(negotiated_lane_count),
        .signaling_mode(negotiated_signaling),
        .retimer_mode(1'b0),
        
        .phy_ready(pll_locked),
        .phy_lane_ready(phy_lane_ready),
        .phy_lane_error(phy_lane_error),
        .phy_training_complete(&phy_lane_trained),
        .phy_signal_quality(phy_signal_quality[0]),
        
        .adapter_ready(1'b1),
        .crc_error(|phy_error_count[0]),
        .retry_count(retry_count_int),
        
        .protocol_ready(1'b1),
        .protocol_errors(8'h0),
        
        .sb_param_exchange_complete(param_exchange_complete),
        .sb_link_up(current_link_state == LINK_ACTIVE),
        
        .requested_power_state(requested_power_state),
        .thermal_throttle_req(thermal_throttle_req),
        .die_temperature(lane_temperature[0]),
        .current_power_state(current_power_state),
        .power_state_ack(power_state_ack),
        
        .ml_enable(ML_ENHANCED && ml_enable),
        .ml_confidence_threshold(8'hC0),
        
        .module_count(total_modules),
        .module_id(module_id),
        .inter_module_sync(inter_module_sync),
        .module_status(module_status_out),
        .module_ready(module_ready),
        
        .current_link_state(current_link_state),
        .state_machine_status(link_state_status),
        .state_transition_count(state_transition_count),
        .link_uptime_cycles(link_uptime_cycles),
        .training_failure_count(training_failure_count)
    );
    
    // Enhanced CRC/Retry Engine
    if (ADVANCED_CRC_RETRY) begin : gen_enhanced_crc_retry
        ucie_enhanced_crc_retry #(
            .FLIT_WIDTH(FLIT_WIDTH),
            .ENHANCED_128G(ENHANCED_128G),
            .ML_PREDICTION(ML_ENHANCED)
        ) i_crc_retry_engine (
            .clk(core_clk),
            .rst_n(core_rst_n),
            
            .crc_enable(1'b1),
            .retry_enable(1'b1),
            .crc_polynomial_sel(4'h1), // CRC-32C
            .enhanced_mode(ENHANCED_128G),
            
            .tx_flit_valid(dl_flit_valid),
            .tx_flit_data(dl_flit_data),
            .tx_flit_sop(dl_flit_sop),
            .tx_flit_eop(dl_flit_eop),
            .tx_flit_be(dl_flit_be),
            .tx_flit_ready(dl_flit_ready),
            
            .phy_tx_valid(phy_tx_valid),
            .phy_tx_data(phy_tx_data),
            .phy_tx_sop(phy_tx_sop),
            .phy_tx_eop(phy_tx_eop),
            .phy_tx_crc(phy_tx_crc),
            .phy_tx_sequence(phy_tx_sequence),
            .phy_tx_ready(phy_tx_ready),
            
            .phy_rx_valid(phy_rx_valid),
            .phy_rx_data(phy_rx_data),
            .phy_rx_sop(phy_rx_sop),
            .phy_rx_eop(phy_rx_eop),
            .phy_rx_crc(phy_rx_crc),
            .phy_rx_sequence(phy_rx_sequence),
            .phy_rx_ready(phy_rx_ready),
            
            .rx_flit_valid(phy_rx_valid),
            .rx_flit_data(phy_rx_data),
            .rx_flit_sop(phy_rx_sop),
            .rx_flit_eop(phy_rx_eop),
            .rx_flit_ready(phy_rx_ready),
            
            .ml_enable(ML_ENHANCED && ml_enable),
            .ml_error_threshold(8'h20),
            
            .burst_mode(ENHANCED_128G),
            .parallel_crc_lanes(4'h4),
            
            .crc_error_count(crc_error_count),
            .retry_count(retry_count_int),
            .throughput_mbps(total_throughput_mbps[15:0])
        );
    end else begin
        // Simple pass-through for basic operation
        assign phy_tx_valid = dl_flit_valid;
        assign phy_tx_data = dl_flit_data;
        assign phy_tx_sop = dl_flit_sop;
        assign phy_tx_eop = dl_flit_eop;
        assign phy_tx_crc = 32'h0;
        assign phy_tx_sequence = 16'h0;
        assign dl_flit_ready = phy_tx_ready;
        assign crc_error_count = 16'h0;
        assign retry_count_int = 16'h0;
        assign total_throughput_mbps = 32'h0;
    end
    
    // Multi-Protocol Flow Control
    if (ML_FLOW_CONTROL) begin : gen_ml_flow_control
        ucie_multi_protocol_flow_control #(
            .NUM_PROTOCOLS(NUM_PROTOCOLS),
            .FLIT_WIDTH(FLIT_WIDTH),
            .ENHANCED_128G(ENHANCED_128G),
            .ML_FLOW_OPTIMIZATION(ML_FLOW_CONTROL),
            .ADAPTIVE_QOS(1)
        ) i_flow_control (
            .clk(core_clk),
            .rst_n(core_rst_n),
            
            .flow_control_enable(controller_enable),
            .protocol_enable({NUM_PROTOCOLS{1'b1}}),
            .target_bandwidth_gbps(8'd128),
            .enhanced_mode(ENHANCED_128G),
            
            .ul_flit_valid(ul_flit_valid),
            .ul_flit_data(ul_flit_data),
            .ul_flit_sop(ul_flit_sop),
            .ul_flit_eop(ul_flit_eop),
            .ul_protocol_type(ul_protocol_type),
            .ul_vc_id(ul_vc_id),
            .ul_priority(ul_priority),
            .ul_flit_ready(ul_flit_ready),
            
            .dl_flit_valid(dl_flit_valid),
            .dl_flit_data(dl_flit_data),
            .dl_flit_sop(dl_flit_sop),
            .dl_flit_eop(dl_flit_eop),
            .dl_flit_be(dl_flit_be),
            .dl_protocol_type(dl_protocol_type),
            .dl_vc_global_id(dl_vc_global_id),
            .dl_flit_ready(dl_flit_ready),
            
            .credit_return(credit_return),
            .credit_count(credit_count),
            .credit_grant(credit_grant),
            .credit_available(credit_available),
            
            .bandwidth_allocation('{default: 8'd12}), // ~12% per protocol
            .latency_target_ns('{default: 16'd1000}), // 1μs target
            .traffic_class('{default: 4'h4}),
            
            .ml_enable(ML_FLOW_CONTROL && ml_enable),
            .ml_prediction_weight(ml_optimization_weight),
            .ml_bandwidth_predict(ml_bandwidth_predict),
            .ml_flow_efficiency(ml_flow_optimization_score),
            
            .burst_mode_enable(ENHANCED_128G),
            .parallel_arbiters(4'h4),
            .zero_latency_bypass(1'b1),
            
            .total_throughput_mbps(total_throughput_mbps),
            .average_latency_ns(average_latency_ns),
            .arbitration_efficiency(arbitration_efficiency)
        );
    end else begin
        // Simple direct connection for basic operation
        assign dl_flit_valid = ul_flit_valid[0];
        assign dl_flit_data = ul_flit_data[0];
        assign dl_flit_sop = ul_flit_sop[0];
        assign dl_flit_eop = ul_flit_eop[0];
        assign dl_flit_be = 4'hF;
        assign dl_protocol_type = ul_protocol_type[0];
        assign dl_vc_global_id = {5'h0, ul_vc_id[0]};
        assign ul_flit_ready[0] = dl_flit_ready;
        assign ul_flit_ready[NUM_PROTOCOLS-1:1] = '0;
        assign total_throughput_mbps = 32'h0;
        assign average_latency_ns = 16'h0;
        assign arbitration_efficiency = 8'h80;
        assign ml_flow_optimization_score = 8'h80;
    end
    
    // ================================================
    // Enhanced Parameter Exchange
    // ================================================
    
    if (ENHANCED_PARAMETER_EXCHANGE) begin : gen_parameter_exchange
        ucie_enhanced_parameter_exchange #(
            .NUM_MODULES(NUM_MODULES),
            .ENHANCED_128G(ENHANCED_128G),
            .ML_NEGOTIATION(ML_ENHANCED),
            .ADVANCED_CAPABILITIES(1)
        ) i_parameter_exchange (
            .clk(core_clk),
            .rst_n(core_rst_n),
            
            .param_exchange_enable(controller_enable),
            .module_id(module_id),
            .total_modules(total_modules),
            .master_module(module_id == 4'h0),
            
            .sb_clk(sideband_clk),
            .sb_rst_n(core_rst_n),
            .sb_valid(sb_rx_valid),
            .sb_data({24'h0, sb_rx_data}),
            .sb_command(4'h1),
            .sb_ready(sb_rx_ready),
            .sb_response_valid(sb_tx_valid),
            .sb_response_data(),
            .sb_response_status(),
            
            .local_capabilities(local_capabilities),
            .supported_data_rates('{default: target_data_rate}),
            .supported_lane_counts('{default: target_lanes}),
            .supported_signaling('{default: signaling_mode}),
            .package_type(package_type),
            .vendor_id(16'hABCD),
            .device_id(16'h1234),
            
            .remote_capabilities(remote_capabilities),
            .negotiated_data_rate(negotiated_data_rate),
            .negotiated_lane_count(negotiated_lane_count),
            .negotiated_signaling(negotiated_signaling),
            .module_compatibility(module_compatibility),
            
            .pam4_supported(PAM4_SIGNALING),
            .equalization_taps(4'h8),
            .power_budget_mw(8'd200),
            .thermal_budget(16'd1000),
            
            .ml_enable(ML_ENHANCED && ml_enable),
            .ml_optimization_weight(ml_optimization_weight),
            .performance_targets('{default: 16'd1000}),
            .ml_negotiation_score(ml_negotiation_score),
            
            .extended_capabilities(32'hDEADBEEF),
            .protocol_versions('{default: 16'h0200}),
            .feature_flags(32'hCAFEBABE),
            
            .inter_module_sync(inter_module_sync),
            .global_negotiation_complete(param_exchange_complete)
        );
        
        assign parameter_exchange_active = !param_exchange_complete;
    end else begin
        // Default negotiated parameters
        assign negotiated_data_rate = target_data_rate;
        assign negotiated_lane_count = target_lanes;
        assign negotiated_signaling = signaling_mode;
        assign param_exchange_complete = 1'b1;
        assign parameter_exchange_active = 1'b0;
        assign ml_negotiation_score = 16'h8000;
    end
    
    // ================================================
    // Protocol Layer Interfaces
    // ================================================
    
    // PCIe Protocol Interface
    assign ul_flit_valid[0] = pcie_tx_valid;
    assign ul_flit_data[0] = pcie_tx_data;
    assign ul_flit_sop[0] = pcie_tx_sop;
    assign ul_flit_eop[0] = pcie_tx_eop;
    assign ul_protocol_type[0] = PCIE;
    assign ul_vc_id[0] = 3'h0;
    assign ul_priority[0] = 4'h8;
    assign pcie_tx_ready = ul_flit_ready[0];
    
    assign pcie_rx_data = phy_rx_data;
    assign pcie_rx_valid = phy_rx_valid && (dl_protocol_type == PCIE);
    assign pcie_rx_sop = phy_rx_sop;
    assign pcie_rx_eop = phy_rx_eop;
    
    // CXL Protocol Interfaces (I/O, Cache, Memory)
    genvar cxl_idx;
    generate
        for (cxl_idx = 0; cxl_idx < 3; cxl_idx++) begin : gen_cxl_interfaces
            assign ul_flit_valid[1 + cxl_idx] = cxl_tx_valid[cxl_idx];
            assign ul_flit_data[1 + cxl_idx] = cxl_tx_data[cxl_idx];
            assign ul_flit_sop[1 + cxl_idx] = cxl_tx_sop[cxl_idx];
            assign ul_flit_eop[1 + cxl_idx] = cxl_tx_eop[cxl_idx];
            assign ul_protocol_type[1 + cxl_idx] = (cxl_idx == 0) ? CXL_IO : 
                                                   (cxl_idx == 1) ? CXL_CACHE : CXL_MEM;
            assign ul_vc_id[1 + cxl_idx] = cxl_idx[2:0];
            assign ul_priority[1 + cxl_idx] = 4'h6 + cxl_idx[3:0];
            assign cxl_tx_ready[cxl_idx] = ul_flit_ready[1 + cxl_idx];
            
            assign cxl_rx_data[cxl_idx] = phy_rx_data;
            assign cxl_rx_valid[cxl_idx] = phy_rx_valid && 
                                         ((dl_protocol_type == CXL_IO && cxl_idx == 0) ||
                                          (dl_protocol_type == CXL_CACHE && cxl_idx == 1) ||
                                          (dl_protocol_type == CXL_MEM && cxl_idx == 2));
            assign cxl_rx_sop[cxl_idx] = phy_rx_sop;
            assign cxl_rx_eop[cxl_idx] = phy_rx_eop;
        end
    endgenerate
    
    // Streaming Protocol Interface
    assign ul_flit_valid[4] = stream_tx_valid;
    assign ul_flit_data[4] = stream_tx_data;
    assign ul_flit_sop[4] = stream_tx_sop;
    assign ul_flit_eop[4] = stream_tx_eop;
    assign ul_protocol_type[4] = STREAMING;
    assign ul_vc_id[4] = 3'h0;
    assign ul_priority[4] = 4'h4;
    assign stream_tx_ready = ul_flit_ready[4];
    
    assign stream_rx_data = phy_rx_data;
    assign stream_rx_valid = phy_rx_valid && (dl_protocol_type == STREAMING);
    assign stream_rx_sop = phy_rx_sop;
    assign stream_rx_eop = phy_rx_eop;
    
    // Management Protocol Interface
    assign ul_flit_valid[5] = 1'b0; // Handled through sideband
    assign ul_flit_data[5] = '0;
    assign ul_flit_sop[5] = 1'b0;
    assign ul_flit_eop[5] = 1'b0;
    assign ul_protocol_type[5] = MANAGEMENT;
    assign ul_vc_id[5] = 3'h0;
    assign ul_priority[5] = 4'hF; // Highest priority
    
    // Unused protocol interfaces
    assign ul_flit_valid[NUM_PROTOCOLS-1:6] = '0;
    assign ul_flit_data[NUM_PROTOCOLS-1:6] = '{default: '0};
    assign ul_flit_sop[NUM_PROTOCOLS-1:6] = '0;
    assign ul_flit_eop[NUM_PROTOCOLS-1:6] = '0;
    assign ul_protocol_type[NUM_PROTOCOLS-1:6] = '{default: STREAMING};
    assign ul_vc_id[NUM_PROTOCOLS-1:6] = '{default: 3'h0};
    assign ul_priority[NUM_PROTOCOLS-1:6] = '{default: 4'h0};
    
    // ================================================
    // Management Interface
    // ================================================
    
    ucie_management_interface #(
        .NUM_LANES(NUM_LANES)
    ) i_management (
        .clk(mgmt_clk),
        .rst_n(mgmt_rst_n),
        
        .mgmt_addr(mgmt_addr),
        .mgmt_wdata(mgmt_wdata),
        .mgmt_write(mgmt_write),
        .mgmt_read(mgmt_read),
        .mgmt_rdata(mgmt_rdata),
        .mgmt_ready(mgmt_ready),
        .mgmt_error(mgmt_error),
        
        // Status inputs from various modules
        .controller_enable(controller_enable),
        .link_state(current_link_state),
        .negotiated_data_rate(negotiated_data_rate),
        .negotiated_lane_count(negotiated_lane_count),
        .lane_status(lane_status),
        .error_count(crc_error_count),
        .retry_count(retry_count_int),
        .power_consumption(total_power_consumption),
        .thermal_status(thermal_alarm_lanes)
    );
    
    // ================================================
    // Output Assignments and Status Generation
    // ================================================
    
    // System-level status and control
    assign global_link_up = (current_link_state == LINK_ACTIVE) && param_exchange_complete;
    assign emergency_shutdown = thermal_emergency || (|training_failure_count > 16'd100);
    
    // ML performance scoring
    assign ml_performance_score = (ml_lane_optimization_score + 
                                  ml_thermal_optimization_score + 
                                  ml_flow_optimization_score) / 3;
    assign ml_thermal_score = ml_thermal_optimization_score;
    assign ml_efficiency_score = ml_flow_optimization_score;
    
    // Performance and monitoring outputs
    assign link_quality_score = {8'h0, phy_signal_quality[0]};
    assign system_throughput_gbps = total_throughput_mbps >> 10; // Convert Mbps to Gbps (approx)
    assign error_count = crc_error_count;
    assign retry_count = retry_count_int[7:0];
    
    // ML optimization activity
    assign ml_optimization_active = ML_ENHANCED && ml_enable && 
                                   (ml_lane_optimization_score > 8'h80 ||
                                    ml_thermal_optimization_score > 8'h80 ||
                                    ml_flow_optimization_score > 8'h80);
    
    // Comprehensive controller status
    assign controller_status = {
        global_link_up,                    // [31] Link fully operational
        emergency_shutdown,                // [30] Emergency shutdown active
        thermal_emergency,                 // [29] Thermal emergency
        link_degradation_alarm,            // [28] Link degradation detected
        parameter_exchange_active,         // [27] Parameter exchange active
        thermal_management_active,         // [26] Thermal management active
        lane_repair_active,                // [25] Lane repair active
        ml_optimization_active,            // [24] ML optimization active
        current_link_state,                // [23:20] Link state
        negotiated_signaling,              // [19:18] Negotiated signaling mode
        2'b0,                              // [17:16] Reserved
        system_throughput_gbps             // [15:0] System throughput in Gbps
    };
    
    // Debug bus for advanced debugging
    assign debug_bus = test_mode ? 
                      {test_pattern, link_state_status[23:0]} : 
                      {current_link_state, 4'h0, negotiated_data_rate, 
                       negotiated_lane_count, popcount(phy_lane_ready)};
    
    // Initialize local capabilities
    assign local_capabilities = '{
        supported_data_rates: (1 << 5) | (1 << 4) | (1 << 3), // 32, 16, 8 GT/s
        supported_lane_counts: (1 << 6) | (1 << 5) | (1 << 4), // 64, 32, 16 lanes
        pam4_signaling: PAM4_SIGNALING,
        advanced_equalization: ADVANCED_EQUALIZATION,
        power_management: 1'b1,
        thermal_management: COMPREHENSIVE_THERMAL_MGMT,
        ml_enhanced: ML_ENHANCED,
        multi_module: MULTI_MODULE_SUPPORT,
        package_support: package_type,
        crc_retry: ADVANCED_CRC_RETRY,
        reserved: 16'h0
    };

endmodule

// Clock Manager Helper Module
module ucie_clock_manager #(
    parameter ENHANCED_128G = 1,
    parameter PAM4_SIGNALING = 1
) (
    input  logic ref_clk,
    input  logic hs_clk_p,
    input  logic hs_clk_n,
    input  logic rst_n,
    output logic core_clk,
    output logic phy_clk,
    output logic quarter_rate_clk,
    output logic hs_clk_out_p,
    output logic hs_clk_out_n,
    output logic pll_locked,
    output logic clk_ready
);

    // Simplified clock management for simulation
    // In real implementation, this would contain PLLs, clock dividers, etc.
    
    logic [3:0] pll_lock_counter;
    
    always_ff @(posedge ref_clk or negedge rst_n) begin
        if (!rst_n) begin
            pll_lock_counter <= 4'h0;
            pll_locked <= 1'b0;
        end else begin
            if (pll_lock_counter < 4'hF) begin
                pll_lock_counter <= pll_lock_counter + 1;
            end else begin
                pll_locked <= 1'b1;
            end
        end
    end
    
    // Clock assignments (simplified for demonstration)
    assign core_clk = ref_clk;
    assign phy_clk = ref_clk;
    assign quarter_rate_clk = ref_clk; // Should be ref_clk/4 in real implementation
    assign hs_clk_out_p = hs_clk_p;
    assign hs_clk_out_n = hs_clk_n;
    assign clk_ready = pll_locked;

endmodule

// Management Interface Helper Module  
module ucie_management_interface #(
    parameter NUM_LANES = 64
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] mgmt_addr,
    input  logic [31:0] mgmt_wdata,
    input  logic        mgmt_write,
    input  logic        mgmt_read,
    output logic [31:0] mgmt_rdata,
    output logic        mgmt_ready,
    output logic        mgmt_error,
    
    // Status inputs
    input  logic        controller_enable,
    input  link_state_t link_state,
    input  logic [7:0]  negotiated_data_rate,
    input  logic [7:0]  negotiated_lane_count,
    input  logic [NUM_LANES-1:0] lane_status,
    input  logic [15:0] error_count,
    input  logic [15:0] retry_count,
    input  logic [15:0] power_consumption,
    input  logic [NUM_LANES-1:0] thermal_status
);

    // Simple register-based management interface
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mgmt_rdata <= 32'h0;
            mgmt_ready <= 1'b0;
            mgmt_error <= 1'b0;
        end else begin
            mgmt_ready <= mgmt_read || mgmt_write;
            mgmt_error <= 1'b0;
            
            if (mgmt_read) begin
                case (mgmt_addr[7:0])
                    8'h00: mgmt_rdata <= {24'h0, link_state};
                    8'h04: mgmt_rdata <= {negotiated_data_rate, negotiated_lane_count, 16'h0};
                    8'h08: mgmt_rdata <= {error_count, retry_count};
                    8'h0C: mgmt_rdata <= {power_consumption, 16'h0};
                    8'h10: mgmt_rdata <= lane_status[31:0];
                    8'h14: mgmt_rdata <= {thermal_status[31:0]};
                    default: mgmt_rdata <= 32'hDEADBEEF;
                endcase
            end
        end
    end

endmodule