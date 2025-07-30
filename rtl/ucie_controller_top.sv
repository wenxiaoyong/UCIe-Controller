module ucie_controller_top
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int NUM_LANES = 64,
    parameter int NUM_PROTOCOLS = 4,
    parameter int NUM_VCS = 8,
    parameter int BUFFER_DEPTH = 16384,     // 4x deeper for 128 Gbps
    parameter int SB_FREQ_MHZ = 800,
    // 128 Gbps Enhancement Parameters
    parameter int ENABLE_128GBPS = 1,
    parameter int ENABLE_PAM4 = 1,
    parameter int ENABLE_QUARTER_RATE = 1,
    parameter int ENABLE_PARALLEL_ENGINES = 1,
    parameter int SYMBOL_RATE_GSPS = 64,    // 64 Gsym/s
    parameter int QUARTER_RATE_DIV = 4,
    // Multi-Module Coordination Parameters
    parameter int NUM_MODULES = 1,          // Number of coordinated modules (1-4)
    parameter int MODULE_ID = 0,            // This module's ID (0-3)
    parameter int ENABLE_MULTI_MODULE = 0   // Enable multi-module coordination
) (
    // System Clocks and Reset
    input  logic                clk_main,      // Main system clock
    input  logic                clk_sb,        // 800MHz sideband clock
    input  logic                rst_n,
    
    // 128 Gbps Clock Domains (when ENABLE_128GBPS=1)
    input  logic                clk_symbol_rate,    // 64 GHz symbol clock
    input  logic                clk_quarter_rate,   // 16 GHz quarter-rate clock
    input  logic                clk_bit_rate,       // 128 GHz bit clock
    
    // UCIe Physical Interface
    // Mainband Interface - Enhanced for PAM4
    output logic                mb_clk_fwd,    // Forwarded clock
    output logic [NUM_LANES-1:0] mb_data,     // Data lanes (NRZ mode)
    output logic                mb_valid,      // Valid signal
    input  logic                mb_ready,      // Ready signal
    
    input  logic                mb_clk_fwd_in,
    input  logic [NUM_LANES-1:0] mb_data_in,
    input  logic                mb_valid_in,
    output logic                mb_ready_out,
    
    // PAM4 Physical Interface (when ENABLE_PAM4=1)
    output logic [NUM_LANES-1:0] pam4_tx_p,    // PAM4 TX positive
    output logic [NUM_LANES-1:0] pam4_tx_n,    // PAM4 TX negative
    input  logic [NUM_LANES-1:0] pam4_rx_p,    // PAM4 RX positive
    input  logic [NUM_LANES-1:0] pam4_rx_n,    // PAM4 RX negative
    
    // PAM4 Symbol Interface
    output logic [1:0]          pam4_tx_symbols [NUM_LANES-1:0],
    input  logic [1:0]          pam4_rx_symbols [NUM_LANES-1:0],
    output logic [NUM_LANES-1:0] pam4_tx_symbol_valid,
    input  logic [NUM_LANES-1:0] pam4_rx_symbol_valid,
    
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
    
    // Package-Specific Configuration
    input  package_type_t       package_type,          // Standard/Advanced/UCIe-3D
    input  logic [7:0]          package_capability,    // Package capability mask
    input  logic [7:0]          package_max_lanes,     // Max lanes for package
    input  logic [3:0]          package_max_speed,     // Max speed for package
    output logic [31:0]         package_status,        // Package configuration status
    
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
    output logic [63:0]         performance_counters [3:0],
    
    // 128 Gbps Enhancement Status
    output logic [31:0]         gbps_128_status,
    output logic [15:0]         quarter_rate_metrics [4],
    output logic [15:0]         parallel_engine_stats [4],
    
    // Multi-Module Coordination Interface
    input  logic [3:0]          multi_module_enable,     // Bitmask of active modules
    input  logic [1:0]          coordination_mode,       // 00=independent, 01=master-slave, 10=distributed, 11=load-balanced
    output logic [1:0]          module_role,             // 00=standalone, 01=master, 10=slave, 11=peer
    
    // Inter-Module Communication Bus
    input  logic [31:0]         inter_module_data_in [3:0],  // Data from other modules
    input  logic [3:0]          inter_module_valid_in,       // Valid signals from other modules
    output logic [31:0]         inter_module_data_out,       // Data to other modules
    output logic                inter_module_valid_out,      // Valid signal to other modules
    
    // Multi-Module Status and Control
    input  logic [7:0]          global_width_request,        // Global width coordination
    input  logic [3:0]          global_speed_request,        // Global speed coordination
    output logic [7:0]          module_width_contribution,   // This module's width contribution
    output logic [3:0]          module_speed_capability,     // This module's speed capability
    
    // Synchronized Control Signals
    input  logic                global_training_enable,      // Coordinated training start
    input  logic                global_power_transition,     // Coordinated power state change
    output logic                module_training_ready,       // This module ready for training
    output logic                module_power_ready           // This module ready for power transition
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
    
    // Package-Specific Configuration
    logic [7:0]  package_effective_lanes;      // Effective lanes after package constraints
    logic [3:0]  package_effective_speed;      // Effective speed after package constraints
    logic [7:0]  package_feature_mask;         // Available features for this package
    logic        package_128g_capable;         // Package supports 128 Gbps
    logic        package_pam4_capable;         // Package supports PAM4
    logic        package_retimer_capable;      // Package supports retimer
    logic [31:0] package_config_reg;           // Package configuration register
    
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
    
    // 128 Gbps Enhancement Internal Signals
    
    // Quarter-Rate Processor Interfaces
    logic [1:0] pam4_symbol_data_rx [4];        // 4 parallel streams from PAM4 PHY
    logic [3:0] pam4_symbol_valid_rx;
    logic [3:0] pam4_symbol_ready_rx;
    logic [511:0] quarter_rate_data_rx;         // 512-bit quarter-rate data
    logic quarter_rate_valid_rx;
    logic quarter_rate_ready_rx;
    
    logic [511:0] quarter_rate_data_tx;         // 512-bit quarter-rate data
    logic quarter_rate_valid_tx;
    logic quarter_rate_ready_tx;
    logic [1:0] pam4_symbol_data_tx [4];        // 4 parallel streams to PAM4 PHY
    logic [3:0] pam4_symbol_valid_tx;
    logic [3:0] pam4_symbol_ready_tx;
    
    // Parallel Protocol Engines Interfaces
    logic [127:0] engine_data_in [4];           // 128-bit per engine input
    flit_header_t engine_header_in [4];
    logic [3:0] engine_valid_in;
    logic [3:0] engine_ready_in;
    logic [3:0] engine_protocol_id_in [4];
    logic [7:0] engine_vc_in [4];
    
    logic [127:0] engine_data_out [4];          // 128-bit per engine output
    flit_header_t engine_header_out [4];
    logic [3:0] engine_valid_out;
    logic [3:0] engine_ready_out;
    logic [3:0] engine_protocol_id_out [4];
    logic [7:0] engine_vc_out [4];
    
    // Enhanced Protocol Layer Interface
    logic [511:0] protocol_tx_flit_128g;        // Enhanced protocol layer interface
    logic protocol_tx_valid_128g;
    logic protocol_tx_ready_128g;
    logic [3:0] protocol_tx_protocol_id_128g;
    logic [7:0] protocol_tx_vc_128g;
    
    logic [511:0] protocol_rx_flit_128g;
    logic protocol_rx_valid_128g;
    logic protocol_rx_ready_128g;
    logic [3:0] protocol_rx_protocol_id_128g;
    logic [7:0] protocol_rx_vc_128g;
    flit_header_t protocol_rx_header_128g;
    
    // Status and Performance Monitoring
    logic [31:0] quarter_rate_status;
    logic [15:0] quarter_rate_debug [4];
    logic [31:0] parallel_engines_status;
    logic [15:0] engine_debug [4];
    logic [7:0] ml_performance_metrics [4];
    logic [15:0] buffer_occupancy_128g [2];
    
    // ML-Enhanced Features - Unified Interface
    logic ml_global_enable;
    logic [7:0] ml_global_learning_rate;
    logic [7:0] ml_global_error_threshold;
    
    // Per-module ML interfaces
    logic [7:0] ml_protocol_parameters [8];          // For parallel protocol engines
    logic [7:0] ml_phy_parameters [NUM_LANES-1:0];   // Per-lane PHY parameters
    logic [7:0] ml_lane_parameters [4];              // For lane manager
    logic [15:0] ml_crc_error_prediction;            // For CRC/retry engine
    logic [7:0] ml_crc_reliability_score;            // CRC reliability score
    
    // ML status aggregation
    logic [7:0] ml_engine_load_predictions [4];
    logic [7:0] ml_phy_performance_metrics [NUM_LANES-1:0];
    logic [NUM_LANES-1:0] ml_lane_predictions;
    logic [7:0] ml_lane_optimization_metrics [4];
    
    // Multi-Module Coordination State
    typedef enum logic [2:0] {
        MM_STANDALONE,        // Single module operation
        MM_DISCOVERY,         // Discovering other modules
        MM_NEGOTIATION,       // Negotiating roles and parameters
        MM_SYNCHRONIZED,      // Synchronized multi-module operation
        MM_COORDINATED,       // Active coordination with load balancing
        MM_ERROR              // Coordination error state
    } multi_module_state_t;
    
    multi_module_state_t mm_state, mm_next_state;
    
    // Multi-Module Coordination Signals
    logic [3:0] detected_modules;           // Modules detected on the bus
    logic [7:0] mm_coordination_timer;      // Timer for coordination timeouts
    logic mm_master_elected;               // Master election complete
    logic mm_sync_training;                // Synchronized training mode
    logic mm_sync_power;                   // Synchronized power management
    logic [7:0] mm_total_width;            // Total width across all modules
    logic [3:0] mm_negotiated_speed;       // Negotiated speed across modules
    logic [31:0] mm_status_word;           // Multi-module status aggregation
    
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
    
    // Package-Specific Configuration Logic
    always_comb begin
        case (package_type)
            ucie_pkg::PKG_STANDARD: begin
                // Standard Package: 10-25mm reach, up to 32 GT/s, max 32 lanes
                package_effective_lanes = (package_max_lanes > 8'd32) ? 8'd32 : package_max_lanes;
                package_effective_speed = (package_max_speed > 4'd5) ? 4'd5 : package_max_speed; // Max DR_32GT
                package_128g_capable = 1'b0;        // No 128 Gbps support
                package_pam4_capable = 1'b0;        // No PAM4 support
                package_retimer_capable = 1'b1;     // Retimer support available
                package_feature_mask = 8'b00111111; // Basic features
            end
            
            ucie_pkg::PKG_ADVANCED: begin
                // Advanced Package: <2mm reach, up to 32 GT/s, max 64 lanes
                package_effective_lanes = (package_max_lanes > NUM_LANES) ? NUM_LANES : package_max_lanes;
                package_effective_speed = (package_max_speed > 4'd7) ? 4'd7 : package_max_speed; // Max DR_128GT
                package_128g_capable = (package_max_speed >= 4'd7) ? 1'b1 : 1'b0; // 128 Gbps if speed allows
                package_pam4_capable = (package_max_speed >= 4'd7) ? 1'b1 : 1'b0; // PAM4 for 128 Gbps
                package_retimer_capable = 1'b1;     // Retimer support available
                package_feature_mask = 8'b11111111; // All features available
            end
            
            ucie_pkg::PKG_UCIE_3D: begin
                // UCIe-3D Package: <10μm pitch, up to 4 GT/s, optimized for 3D stacking
                package_effective_lanes = NUM_LANES; // Full lane support for 3D
                package_effective_speed = 4'd0;      // Max DR_4GT for 3D
                package_128g_capable = 1'b0;        // No 128 Gbps support
                package_pam4_capable = 1'b0;        // No PAM4 support  
                package_retimer_capable = 1'b0;     // No retimer support
                package_feature_mask = 8'b00001111; // Basic 3D features
            end
            
            default: begin
                // Default to Standard Package behavior
                package_effective_lanes = 8'd32;
                package_effective_speed = 4'd5;
                package_128g_capable = 1'b0;
                package_pam4_capable = 1'b0;
                package_retimer_capable = 1'b1;
                package_feature_mask = 8'b00111111;
            end
        endcase
    end
    
    // ML Global Configuration Initialization
    always_comb begin
        ml_global_enable = 1'b1;                    // Enable ML features by default
        ml_global_learning_rate = 8'h10;            // Default learning rate (16/256)
        ml_global_error_threshold = 8'h20;          // Default error threshold (32/256)
        
        // Initialize per-module ML parameters
        for (int i = 0; i < 8; i++) begin
            ml_protocol_parameters[i] = ml_global_learning_rate;
        end
        
        for (int i = 0; i < NUM_LANES; i++) begin
            ml_phy_parameters[i] = ml_global_learning_rate;
        end
        
        for (int i = 0; i < 4; i++) begin
            ml_lane_parameters[i] = ml_global_learning_rate;
        end
    end
    
    // Multi-Module Coordination State Machine
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            mm_state <= MM_STANDALONE;
            detected_modules <= 4'h0;
            mm_coordination_timer <= 8'h0;
            mm_master_elected <= 1'b0;
            mm_sync_training <= 1'b0;
            mm_sync_power <= 1'b0;
            mm_total_width <= 8'h0;
            mm_negotiated_speed <= 4'h0;
        end else begin
            mm_state <= mm_next_state;
            
            case (mm_state)
                MM_STANDALONE: begin
                    if (ENABLE_MULTI_MODULE && NUM_MODULES > 1) begin
                        // Detect other active modules
                        detected_modules <= multi_module_enable;
                        mm_coordination_timer <= 8'hFF; // Start timeout
                    end
                end
                
                MM_DISCOVERY: begin
                    mm_coordination_timer <= mm_coordination_timer - 1;
                    
                    // Count detected modules
                    logic [2:0] module_count;
                    module_count = 3'h0;
                    for (int i = 0; i < 4; i++) begin
                        if (detected_modules[i]) module_count = module_count + 1;
                    end
                    
                    // Update detected modules based on valid signals
                    detected_modules <= detected_modules | inter_module_valid_in;
                end
                
                MM_NEGOTIATION: begin
                    mm_coordination_timer <= mm_coordination_timer - 1;
                    
                    // Master election: lowest MODULE_ID becomes master
                    logic [1:0] master_id;
                    master_id = 2'h3; // Start with highest ID
                    for (int i = 0; i < 4; i++) begin
                        if (detected_modules[i] && (i < master_id)) begin
                            master_id = i[1:0];
                        end
                    end
                    
                    mm_master_elected <= (master_id == MODULE_ID[1:0]);
                    
                    // Aggregate width and speed capabilities
                    if (inter_module_valid_in[0]) mm_total_width <= mm_total_width + inter_module_data_in[0][7:0];
                    if (inter_module_valid_in[1]) mm_total_width <= mm_total_width + inter_module_data_in[1][7:0];
                    if (inter_module_valid_in[2]) mm_total_width <= mm_total_width + inter_module_data_in[2][7:0];
                    if (inter_module_valid_in[3]) mm_total_width <= mm_total_width + inter_module_data_in[3][7:0];
                end
                
                MM_SYNCHRONIZED: begin
                    // Synchronize training and power management
                    mm_sync_training <= global_training_enable;
                    mm_sync_power <= global_power_transition;
                    
                    // Monitor for coordination mode changes
                    if (coordination_mode == 2'b11) begin // Load-balanced mode
                        // Enter coordinated operation
                    end
                end
                
                MM_COORDINATED: begin
                    // Active load balancing and coordination
                    // Distribute traffic based on module capabilities
                    
                    // Monitor for errors or disconnections
                    if (|inter_module_valid_in == 1'b0 && NUM_MODULES > 1) begin
                        // Lost connection to other modules
                    end
                end
                
                MM_ERROR: begin
                    // Error recovery: return to standalone mode
                    mm_coordination_timer <= mm_coordination_timer - 1;
                    if (mm_coordination_timer == 8'h0) begin
                        detected_modules <= 4'h0;
                        mm_master_elected <= 1'b0;
                    end
                end
            endcase
        end
    end
    
    // Multi-Module State Transition Logic
    always_comb begin
        mm_next_state = mm_state;
        
        case (mm_state)
            MM_STANDALONE: begin
                if (ENABLE_MULTI_MODULE && NUM_MODULES > 1 && |multi_module_enable) begin
                    mm_next_state = MM_DISCOVERY;
                end
            end
            
            MM_DISCOVERY: begin
                if (mm_coordination_timer == 8'h0) begin
                    mm_next_state = MM_ERROR; // Discovery timeout
                end else if (|detected_modules) begin
                    mm_next_state = MM_NEGOTIATION;
                end
            end
            
            MM_NEGOTIATION: begin
                if (mm_coordination_timer == 8'h0) begin
                    mm_next_state = MM_ERROR; // Negotiation timeout
                end else if (mm_master_elected || MODULE_ID == 0) begin
                    mm_next_state = MM_SYNCHRONIZED;
                end
            end
            
            MM_SYNCHRONIZED: begin
                if (coordination_mode == 2'b11) begin // Load-balanced
                    mm_next_state = MM_COORDINATED;
                end else if (!|detected_modules && NUM_MODULES > 1) begin
                    mm_next_state = MM_ERROR;
                end
            end
            
            MM_COORDINATED: begin
                if (coordination_mode != 2'b11) begin
                    mm_next_state = MM_SYNCHRONIZED;
                end else if (!|detected_modules && NUM_MODULES > 1) begin
                    mm_next_state = MM_ERROR;
                end
            end
            
            MM_ERROR: begin
                if (mm_coordination_timer == 8'h0) begin
                    mm_next_state = MM_STANDALONE;
                end
            end
        endcase
    end
    
    // Multi-Module Coordination Output Assignments
    logic multi_module_ready;
    
    always_comb begin
        // Default assignments
        module_role = 2'b00;  // Standalone
        inter_module_data_out = 32'h0;
        inter_module_valid_out = 1'b0;
        module_width_contribution = 8'h0;
        module_speed_capability = 4'h0;
        module_training_ready = 1'b0;
        module_power_ready = 1'b0;
        
        case (mm_state)
            MM_STANDALONE: begin
                module_role = 2'b00;
                // No inter-module communication
            end
            
            MM_DISCOVERY, MM_NEGOTIATION: begin
                module_role = 2'b11;  // Peer during negotiation
                inter_module_data_out = {24'h0, 8'(MODULE_ID)};
                inter_module_valid_out = 1'b1;
            end
            
            MM_SYNCHRONIZED, MM_COORDINATED: begin
                if (is_master) begin
                    module_role = 2'b01;  // Master
                    // Broadcast coordination data
                    inter_module_data_out = {
                        8'h0,
                        actual_width,
                        4'(negotiated_speed),
                        4'b0,
                        training_fsm_state,
                        2'b0,
                        training_complete
                    };
                    inter_module_valid_out = 1'b1;
                end else begin
                    module_role = 2'b10;  // Slave
                    // Acknowledge coordination
                    inter_module_data_out = {28'h0, 4'(MODULE_ID)};
                    inter_module_valid_out = multi_module_ready;
                end
                
                // Contribute to system capabilities
                module_width_contribution = actual_width;
                module_speed_capability = 4'(negotiated_speed);
                module_training_ready = training_complete;
                module_power_ready = (link_power_state == ucie_pkg::PWR_L0);
            end
            
            MM_ERROR: begin
                module_role = 2'b00;  // Revert to standalone
            end
        endcase
    end
    
    // Multi-Module Coordination Integration with Existing Systems
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            multi_module_ready <= 1'b0;
        end else if (ENABLE_MULTI_MODULE) begin
            // Multi-module system is ready when all subsystems are operational
            multi_module_ready <= training_complete && 
                                 (link_power_state == ucie_pkg::PWR_L0) &&
                                 protocol_layer_ready &&
                                 phy_ready &&
                                 !mm_coordination_timeout;
        end else begin
            multi_module_ready <= 1'b1;  // Always ready in standalone mode
        end
    end
    
    // Comprehensive Parameter Validation
    logic [31:0] validation_errors;
    logic parameter_validation_complete;
    logic [7:0] validation_warnings;
    
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            validation_errors <= 32'h0;
            parameter_validation_complete <= 1'b0;
            validation_warnings <= 8'h0;
        end else begin
            // Reset validation status
            validation_errors <= 32'h0;
            validation_warnings <= 8'h0;
            parameter_validation_complete <= 1'b0;
            
            // Validate NUM_LANES parameter
            if (NUM_LANES < ucie_pkg::MIN_LANES || NUM_LANES > ucie_pkg::MAX_LANES) begin
                validation_errors[0] <= 1'b1;  // Invalid lane count
            end
            if (NUM_LANES % 8 != 0) begin
                validation_warnings[0] <= 1'b1;  // Non-optimal lane count (not multiple of 8)
            end
            
            // Validate ENABLE_128GBPS compatibility
            if (ENABLE_128GBPS && !ENABLE_PAM4) begin
                validation_errors[1] <= 1'b1;  // 128 Gbps requires PAM4
            end
            if (ENABLE_128GBPS && !ENABLE_QUARTER_RATE) begin
                validation_errors[2] <= 1'b1;  // 128 Gbps requires quarter-rate processing
            end
            if (ENABLE_128GBPS && !ENABLE_PARALLEL_ENGINES) begin
                validation_warnings[1] <= 1'b1;  // 128 Gbps recommended with parallel engines
            end
            
            // Validate package compatibility
            case (PKG_TYPE)
                ucie_pkg::PKG_STANDARD: begin
                    if (NUM_LANES > 32) begin
                        validation_errors[3] <= 1'b1;  // Standard package limited to 32 lanes
                    end
                    if (ENABLE_128GBPS) begin
                        validation_errors[4] <= 1'b1;  // Standard package doesn't support 128 Gbps
                    end
                end
                ucie_pkg::PKG_ADVANCED: begin
                    if (NUM_LANES > 64) begin
                        validation_errors[5] <= 1'b1;  // Advanced package limited to 64 lanes
                    end
                end
                ucie_pkg::PKG_UCIE_3D: begin
                    if (ENABLE_128GBPS) begin
                        validation_errors[6] <= 1'b1;  // UCIe-3D limited to 4 GT/s
                    end
                    if (NUM_LANES > 32) begin
                        validation_warnings[2] <= 1'b1;  // UCIe-3D optimized for narrower widths
                    end
                end
                default: begin
                    validation_errors[7] <= 1'b1;  // Invalid package type
                end
            endcase
            
            // Validate NUM_PROTOCOLS compatibility
            if (NUM_PROTOCOLS < 1 || NUM_PROTOCOLS > 8) begin
                validation_errors[8] <= 1'b1;  // Invalid protocol count
            end
            
            // Validate buffer depth parameters
            if (BUFFER_DEPTH < ucie_pkg::MIN_BUFFER_DEPTH || BUFFER_DEPTH > ucie_pkg::MAX_BUFFER_DEPTH) begin
                validation_errors[9] <= 1'b1;  // Invalid buffer depth
            end
            if (BUFFER_DEPTH < 64 && ENABLE_128GBPS) begin
                validation_warnings[3] <= 1'b1;  // Small buffer for 128 Gbps
            end
            
            // Validate multi-module parameters
            if (ENABLE_MULTI_MODULE) begin
                if (NUM_MODULES < 1 || NUM_MODULES > ucie_pkg::MAX_MODULES) begin
                    validation_errors[10] <= 1'b1;  // Invalid module count
                end
                if (MODULE_ID >= NUM_MODULES) begin
                    validation_errors[11] <= 1'b1;  // Invalid module ID
                end
                if (NUM_MODULES > 1 && !ENABLE_PARALLEL_ENGINES) begin
                    validation_warnings[4] <= 1'b1;  // Multi-module recommended with parallel engines
                end
            end
            
            // Validate ML configuration
            if (ENABLE_ML_OPTIMIZATION) begin
                if (!ENABLE_ADVANCED_FEATURES) begin
                    validation_warnings[5] <= 1'b1;  // ML optimization recommended with advanced features
                end
            end
            
            // Validate timing parameters
            if (SYMBOL_RATE_GSPS > 64 && !ENABLE_PAM4) begin
                validation_errors[12] <= 1'b1;  // High symbol rates require PAM4
            end
            if (SYMBOL_RATE_GSPS == 0) begin
                validation_errors[13] <= 1'b1;  // Invalid symbol rate
            end
            
            // Validate NUM_VCS parameter
            if (NUM_VCS < 1 || NUM_VCS > ucie_pkg::MAX_VCS) begin
                validation_errors[14] <= 1'b1;  // Invalid virtual channel count
            end
            
            // Validate advanced features compatibility
            if (ENABLE_RETIMER_SUPPORT && PKG_TYPE == ucie_pkg::PKG_UCIE_3D) begin
                validation_warnings[6] <= 1'b1;  // Retimer not typically used with 3D packages
            end
            
            // Validate power optimization parameters
            if (POWER_OPTIMIZATION_LEVEL > 3) begin
                validation_errors[15] <= 1'b1;  // Invalid power optimization level
            end
            
            // Check for critical parameter combinations
            if (ENABLE_128GBPS && NUM_LANES < 32) begin
                validation_warnings[7] <= 1'b1;  // 128 Gbps recommended with wider configurations
            end
            
            // Parameter validation is complete (takes 1 cycle)
            parameter_validation_complete <= 1'b1;
        end
    end
    
    // Parameter validation status output
    logic [31:0] parameter_validation_status;
    assign parameter_validation_status = {
        parameter_validation_complete,   // [31] Validation complete
        7'h0,                           // [30:24] Reserved
        validation_warnings,            // [23:16] Warning flags
        validation_errors[15:0]         // [15:0] Error flags
    };
    
    // Comprehensive Error Recovery Mechanisms
    typedef enum logic [3:0] {
        ERR_RECOVERY_IDLE,
        ERR_RECOVERY_DETECT,
        ERR_RECOVERY_CLASSIFY,
        ERR_RECOVERY_ISOLATE,
        ERR_RECOVERY_RETRY,
        ERR_RECOVERY_RETRAIN,
        ERR_RECOVERY_LANE_MAP,
        ERR_RECOVERY_PROTOCOL_RESET,
        ERR_RECOVERY_SYSTEM_RESET,
        ERR_RECOVERY_COMPLETE,
        ERR_RECOVERY_FAILED
    } error_recovery_state_t;
    
    error_recovery_state_t err_recovery_state, err_recovery_next_state;
    logic [31:0] error_mask, error_status_reg;
    logic [15:0] recovery_attempt_count;
    logic [7:0] error_recovery_timer;
    logic [3:0] current_error_type;
    logic error_recovery_active;
    
    // Error classification and severity assessment
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            error_status_reg <= 32'h0;
            error_mask <= 32'hFFFFFFFF;  // All errors enabled by default
            current_error_type <= 4'h0;
        end else begin
            // Collect errors from all modules
            error_status_reg <= {
                16'h0,                          // [31:16] Reserved
                validation_errors[15],          // [15] Parameter validation error
                |validation_errors[14:0],       // [14] General validation errors
                training_error,                 // [13] Training error
                param_exchange_error,           // [12] Parameter exchange error
                crc_error_count > 16'd100,      // [11] Excessive CRC errors
                protocol_error_count > 16'd50,  // [10] Excessive protocol errors
                mm_coordination_timeout,        // [9] Multi-module coordination timeout
                |engine_errors,                 // [8] Engine errors (from parallel engines)
                phy_rx_crc_error,              // [7] PHY CRC error
                buffer_overflow,               // [6] Buffer overflow
                lane_error_detected,           // [5] Lane error
                thermal_alarm_active,          // [4] Thermal alarm
                power_error_detected,          // [3] Power error
                sideband_error,                // [2] Sideband error
                retry_limit_exceeded,          // [1] Retry limit exceeded
                link_timeout                   // [0] Link timeout
            };
            
            // Classify most critical error
            if (error_status_reg & error_mask) begin
                // Priority encoding for error types (highest priority first)
                if (error_status_reg[15]) begin
                    current_error_type <= ucie_pkg::ERR_PARAM_MISMATCH;
                end else if (error_status_reg[13]) begin
                    current_error_type <= ucie_pkg::ERR_TRAINING;
                end else if (error_status_reg[11] || error_status_reg[7]) begin
                    current_error_type <= ucie_pkg::ERR_CRC;
                end else if (error_status_reg[5]) begin
                    current_error_type <= ucie_pkg::ERR_LANE_FAILURE;
                end else if (error_status_reg[6]) begin
                    current_error_type <= ucie_pkg::ERR_BUFFER_OVERFLOW;
                end else if (error_status_reg[0]) begin
                    current_error_type <= ucie_pkg::ERR_TIMEOUT;
                end else begin
                    current_error_type <= ucie_pkg::ERR_UNKNOWN;
                end
            end else begin
                current_error_type <= ucie_pkg::ERR_NONE;
            end
        end
    end
    
    // Error Recovery State Machine
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            err_recovery_state <= ERR_RECOVERY_IDLE;
            recovery_attempt_count <= 16'h0;
            error_recovery_timer <= 8'h0;
            error_recovery_active <= 1'b0;
        end else begin
            err_recovery_state <= err_recovery_next_state;
            
            case (err_recovery_state)
                ERR_RECOVERY_IDLE: begin
                    error_recovery_active <= 1'b0;
                    if (current_error_type != ucie_pkg::ERR_NONE) begin
                        error_recovery_active <= 1'b1;
                        error_recovery_timer <= 8'd100;  // 100 cycle timeout
                    end
                end
                
                ERR_RECOVERY_DETECT: begin
                    error_recovery_timer <= error_recovery_timer - 1;
                end
                
                ERR_RECOVERY_CLASSIFY: begin
                    // Classification done in combinational logic above
                    error_recovery_timer <= 8'd50;
                end
                
                ERR_RECOVERY_ISOLATE: begin
                    error_recovery_timer <= error_recovery_timer - 1;
                    // Isolate error source based on error type
                end
                
                ERR_RECOVERY_RETRY: begin
                    if (recovery_attempt_count < 16'd5) begin
                        recovery_attempt_count <= recovery_attempt_count + 1;
                        error_recovery_timer <= 8'd200;  // Longer timeout for retry
                    end
                end
                
                ERR_RECOVERY_RETRAIN: begin
                    error_recovery_timer <= error_recovery_timer - 1;
                    if (recovery_attempt_count < 16'd3) begin
                        recovery_attempt_count <= recovery_attempt_count + 1;
                    end
                end
                
                ERR_RECOVERY_LANE_MAP: begin
                    error_recovery_timer <= error_recovery_timer - 1;
                    recovery_attempt_count <= recovery_attempt_count + 1;
                end
                
                ERR_RECOVERY_PROTOCOL_RESET: begin
                    error_recovery_timer <= error_recovery_timer - 1;
                    recovery_attempt_count <= recovery_attempt_count + 1;
                end
                
                ERR_RECOVERY_SYSTEM_RESET: begin
                    error_recovery_timer <= error_recovery_timer - 1;
                    recovery_attempt_count <= recovery_attempt_count + 1;
                end
                
                ERR_RECOVERY_COMPLETE: begin
                    recovery_attempt_count <= 16'h0;
                    error_recovery_active <= 1'b0;
                end
                
                ERR_RECOVERY_FAILED: begin
                    error_recovery_active <= 1'b0;
                    // Error recovery has failed - system needs external intervention
                end
            endcase
        end
    end
    
    // Error Recovery State Transition Logic
    always_comb begin
        err_recovery_next_state = err_recovery_state;
        
        case (err_recovery_state)
            ERR_RECOVERY_IDLE: begin
                if (current_error_type != ucie_pkg::ERR_NONE) begin
                    err_recovery_next_state = ERR_RECOVERY_DETECT;
                end
            end
            
            ERR_RECOVERY_DETECT: begin
                if (error_recovery_timer == 8'h0) begin
                    err_recovery_next_state = ERR_RECOVERY_CLASSIFY;
                end
            end
            
            ERR_RECOVERY_CLASSIFY: begin
                case (current_error_type)
                    ucie_pkg::ERR_CRC, ucie_pkg::ERR_SEQUENCE: begin
                        err_recovery_next_state = ERR_RECOVERY_RETRY;
                    end
                    ucie_pkg::ERR_LANE_FAILURE: begin
                        err_recovery_next_state = ERR_RECOVERY_LANE_MAP;
                    end
                    ucie_pkg::ERR_TRAINING, ucie_pkg::ERR_PARAM_MISMATCH: begin
                        err_recovery_next_state = ERR_RECOVERY_RETRAIN;
                    end
                    ucie_pkg::ERR_PROTOCOL, ucie_pkg::ERR_BUFFER_OVERFLOW: begin
                        err_recovery_next_state = ERR_RECOVERY_PROTOCOL_RESET;
                    end
                    ucie_pkg::ERR_TIMEOUT, ucie_pkg::ERR_POWER, ucie_pkg::ERR_SIDEBAND: begin
                        err_recovery_next_state = ERR_RECOVERY_SYSTEM_RESET;
                    end
                    default: begin
                        err_recovery_next_state = ERR_RECOVERY_ISOLATE;
                    end
                endcase
            end
            
            ERR_RECOVERY_ISOLATE: begin
                if (error_recovery_timer == 8'h0) begin
                    err_recovery_next_state = ERR_RECOVERY_RETRY;
                end
            end
            
            ERR_RECOVERY_RETRY: begin
                if (current_error_type == ucie_pkg::ERR_NONE) begin
                    err_recovery_next_state = ERR_RECOVERY_COMPLETE;
                end else if (recovery_attempt_count >= 16'd5) begin
                    err_recovery_next_state = ERR_RECOVERY_RETRAIN;
                end else if (error_recovery_timer == 8'h0) begin
                    err_recovery_next_state = ERR_RECOVERY_RETRY;  // Retry again
                end
            end
            
            ERR_RECOVERY_RETRAIN: begin
                if (training_complete && current_error_type == ucie_pkg::ERR_NONE) begin
                    err_recovery_next_state = ERR_RECOVERY_COMPLETE;
                end else if (recovery_attempt_count >= 16'd3) begin
                    err_recovery_next_state = ERR_RECOVERY_PROTOCOL_RESET;
                end else if (error_recovery_timer == 8'h0) begin
                    err_recovery_next_state = ERR_RECOVERY_RETRAIN;  // Retry retrain
                end
            end
            
            ERR_RECOVERY_LANE_MAP: begin
                if (current_error_type == ucie_pkg::ERR_NONE) begin
                    err_recovery_next_state = ERR_RECOVERY_COMPLETE;
                end else if (error_recovery_timer == 8'h0) begin
                    err_recovery_next_state = ERR_RECOVERY_RETRAIN;
                end
            end
            
            ERR_RECOVERY_PROTOCOL_RESET: begin
                if (current_error_type == ucie_pkg::ERR_NONE) begin
                    err_recovery_next_state = ERR_RECOVERY_COMPLETE;
                end else if (error_recovery_timer == 8'h0) begin
                    err_recovery_next_state = ERR_RECOVERY_SYSTEM_RESET;
                end
            end
            
            ERR_RECOVERY_SYSTEM_RESET: begin
                if (current_error_type == ucie_pkg::ERR_NONE) begin
                    err_recovery_next_state = ERR_RECOVERY_COMPLETE;
                end else if (error_recovery_timer == 8'h0) begin
                    err_recovery_next_state = ERR_RECOVERY_FAILED;
                end
            end
            
            ERR_RECOVERY_COMPLETE: begin
                err_recovery_next_state = ERR_RECOVERY_IDLE;
            end
            
            ERR_RECOVERY_FAILED: begin
                // Stay in failed state until external reset
                if (current_error_type == ucie_pkg::ERR_NONE) begin
                    err_recovery_next_state = ERR_RECOVERY_IDLE;
                end
            end
        endcase
    end
    
    // Error Recovery Actions (outputs to control other modules)
    logic trigger_crc_retry, trigger_link_retrain, trigger_lane_remap;
    logic trigger_protocol_reset, trigger_system_reset;
    logic error_isolation_active;
    
    always_comb begin
        // Default assignments
        trigger_crc_retry = 1'b0;
        trigger_link_retrain = 1'b0;
        trigger_lane_remap = 1'b0;
        trigger_protocol_reset = 1'b0;
        trigger_system_reset = 1'b0;
        error_isolation_active = 1'b0;
        
        case (err_recovery_state)
            ERR_RECOVERY_ISOLATE: begin
                error_isolation_active = 1'b1;
            end
            ERR_RECOVERY_RETRY: begin
                trigger_crc_retry = 1'b1;
            end
            ERR_RECOVERY_RETRAIN: begin
                trigger_link_retrain = 1'b1;
            end
            ERR_RECOVERY_LANE_MAP: begin
                trigger_lane_remap = 1'b1;
            end
            ERR_RECOVERY_PROTOCOL_RESET: begin
                trigger_protocol_reset = 1'b1;
            end
            ERR_RECOVERY_SYSTEM_RESET: begin
                trigger_system_reset = 1'b1;
            end
        endcase
    end
    
    // Error Recovery Status Output
    logic [31:0] error_recovery_status;
    assign error_recovery_status = {
        error_recovery_active,          // [31] Recovery active
        3'(err_recovery_state),         // [30:28] Recovery state
        current_error_type,             // [27:24] Current error type
        error_recovery_timer,           // [23:16] Recovery timer
        recovery_attempt_count          // [15:0] Attempt count
    };
    
    // Comprehensive Performance Monitoring Infrastructure
    typedef struct packed {
        logic [31:0] total_flits_tx;
        logic [31:0] total_flits_rx;
        logic [31:0] total_bytes_tx;
        logic [31:0] total_bytes_rx;
        logic [15:0] avg_latency_cycles;
        logic [15:0] peak_latency_cycles;
        logic [7:0]  utilization_percent;
        logic [7:0]  efficiency_percent;
    } performance_metrics_t;
    
    performance_metrics_t perf_metrics;
    logic [31:0] perf_sample_counter;
    logic [15:0] perf_sample_period;  // Configurable sample period
    logic [31:0] perf_timestamp;
    
    // Per-Protocol Performance Tracking
    logic [31:0] protocol_tx_count [NUM_PROTOCOLS];
    logic [31:0] protocol_rx_count [NUM_PROTOCOLS];
    logic [31:0] protocol_error_count [NUM_PROTOCOLS];
    logic [15:0] protocol_avg_latency [NUM_PROTOCOLS];
    
    // Per-Lane Performance Tracking
    logic [31:0] lane_bit_count [NUM_LANES];
    logic [15:0] lane_ber_estimate [NUM_LANES];
    logic [7:0]  lane_utilization [NUM_LANES];
    logic [NUM_LANES-1:0] lane_active_mask;
    
    // Real-time Performance Counters
    logic [31:0] instantaneous_throughput_mbps;
    logic [15:0] instantaneous_latency_cycles;
    logic [7:0]  link_utilization_percent;
    logic [7:0]  buffer_utilization_percent;
    
    // Historical Performance Tracking (Moving averages)
    logic [31:0] throughput_history [16];  // 16-sample history
    logic [15:0] latency_history [16];
    logic [3:0]  history_write_ptr;
    logic [31:0] throughput_sum;
    logic [31:0] latency_sum;
    
    // Performance Event Counters
    logic [31:0] training_event_count;
    logic [31:0] error_recovery_count;
    logic [31:0] lane_repair_count;
    logic [31:0] power_state_change_count;
    logic [31:0] congestion_event_count;
    
    // Advanced Performance Metrics
    logic [15:0] peak_sustainable_rate_gbps;
    logic [7:0]  power_efficiency_score;  // Gbps per Watt * 10
    logic [7:0]  thermal_efficiency_score;
    logic [15:0] qos_compliance_percent;
    
    // Performance Monitoring State Machine
    typedef enum logic [2:0] {
        PERF_IDLE,
        PERF_COLLECT,
        PERF_ANALYZE,
        PERF_UPDATE,
        PERF_REPORT
    } perf_monitor_state_t;
    
    perf_monitor_state_t perf_state;
    logic [7:0] perf_monitor_timer;
    logic performance_monitoring_active;
    
    // Performance data collection
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            perf_metrics <= '0;
            perf_sample_counter <= 32'h0;
            perf_sample_period <= 16'd1000;  // Default 1000 cycles
            perf_timestamp <= 32'h0;
            
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                protocol_tx_count[i] <= 32'h0;
                protocol_rx_count[i] <= 32'h0;
                protocol_error_count[i] <= 32'h0;
                protocol_avg_latency[i] <= 16'h0;
            end
            
            for (int i = 0; i < NUM_LANES; i++) begin
                lane_bit_count[i] <= 32'h0;
                lane_ber_estimate[i] <= 16'h0;
                lane_utilization[i] <= 8'h0;
            end
            
            for (int i = 0; i < 16; i++) begin
                throughput_history[i] <= 32'h0;
                latency_history[i] <= 16'h0;
            end
            
            history_write_ptr <= 4'h0;
            throughput_sum <= 32'h0;
            latency_sum <= 32'h0;
            
            training_event_count <= 32'h0;
            error_recovery_count <= 32'h0;
            lane_repair_count <= 32'h0;
            power_state_change_count <= 32'h0;
            congestion_event_count <= 32'h0;
            
            performance_monitoring_active <= 1'b1;
        end else begin
            perf_timestamp <= perf_timestamp + 1;
            
            // Collect per-protocol statistics
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                if (protocol_tx_valid[i] && protocol_tx_ready[i]) begin
                    protocol_tx_count[i] <= protocol_tx_count[i] + 1;
                    perf_metrics.total_flits_tx <= perf_metrics.total_flits_tx + 1;
                    perf_metrics.total_bytes_tx <= perf_metrics.total_bytes_tx + (FLIT_WIDTH / 8);
                end
                
                if (protocol_rx_valid[i] && protocol_rx_ready[i]) begin
                    protocol_rx_count[i] <= protocol_rx_count[i] + 1;
                    perf_metrics.total_flits_rx <= perf_metrics.total_flits_rx + 1;
                    perf_metrics.total_bytes_rx <= perf_metrics.total_bytes_rx + (FLIT_WIDTH / 8);
                end
                
                if (protocol_error[i]) begin
                    protocol_error_count[i] <= protocol_error_count[i] + 1;
                end
            end
            
            // Collect per-lane statistics
            for (int i = 0; i < NUM_LANES; i++) begin
                if (lane_active_mask[i]) begin
                    if (ENABLE_PAM4) begin
                        lane_bit_count[i] <= lane_bit_count[i] + 2;  // 2 bits per PAM4 symbol
                    end else begin
                        lane_bit_count[i] <= lane_bit_count[i] + 1;  // 1 bit per NRZ symbol
                    end
                    
                    // Calculate lane utilization (simplified)
                    if (mb_valid && i < actual_width) begin
                        lane_utilization[i] <= (lane_utilization[i] < 8'hFE) ? 
                                              lane_utilization[i] + 1 : 8'hFF;
                    end else if (lane_utilization[i] > 0) begin
                        lane_utilization[i] <= lane_utilization[i] - 1;
                    end
                end
            end
            
            // Event counting
            if (training_complete && !training_complete) begin  // Rising edge detection
                training_event_count <= training_event_count + 1;
            end
            
            if (error_recovery_active && !error_recovery_active) begin  // Rising edge
                error_recovery_count <= error_recovery_count + 1;
            end
            
            if (repair_active && !repair_active) begin  // Rising edge
                lane_repair_count <= lane_repair_count + 1;
            end
            
            // Sample period processing
            if (perf_sample_counter >= perf_sample_period) begin
                perf_sample_counter <= 32'h0;
                
                // Update moving averages
                throughput_sum <= throughput_sum - throughput_history[history_write_ptr] + instantaneous_throughput_mbps;
                latency_sum <= latency_sum - latency_history[history_write_ptr] + instantaneous_latency_cycles;
                
                throughput_history[history_write_ptr] <= instantaneous_throughput_mbps;
                latency_history[history_write_ptr] <= instantaneous_latency_cycles;
                
                history_write_ptr <= (history_write_ptr == 4'd15) ? 4'h0 : history_write_ptr + 1;
                
                // Update averaged metrics
                perf_metrics.avg_latency_cycles <= latency_sum >> 4;  // Divide by 16
                perf_metrics.utilization_percent <= link_utilization_percent;
                
            end else begin
                perf_sample_counter <= perf_sample_counter + 1;
            end
        end
    end
    
    // Real-time performance calculations
    always_comb begin
        // Calculate instantaneous throughput (Mbps)
        instantaneous_throughput_mbps = (perf_metrics.total_bytes_tx + perf_metrics.total_bytes_rx) * 8 / 
                                       ((perf_timestamp >> 10) + 1);  // Approximate division by time
        
        // Calculate instantaneous latency (simplified estimation)
        instantaneous_latency_cycles = (protocol_tx_flit_count + protocol_rx_flit_count > 0) ?
                                      16'd10 : 16'd0;  // Simplified latency model
        
        // Calculate link utilization
        logic [15:0] active_lanes_count = 0;
        for (int i = 0; i < NUM_LANES; i++) begin
            if (lane_active_mask[i]) active_lanes_count = active_lanes_count + 1;
        end
        
        link_utilization_percent = (active_lanes_count * 100) / NUM_LANES;
        
        // Calculate buffer utilization (aggregate across all buffers)
        logic [15:0] total_buffer_occupancy = 0;
        logic [15:0] total_buffer_capacity = 0;
        
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            total_buffer_occupancy = total_buffer_occupancy + protocol_buffer_occupancy[i];
            total_buffer_capacity = total_buffer_capacity + BUFFER_DEPTH;
        end
        
        buffer_utilization_percent = (total_buffer_capacity > 0) ? 
                                   8'((total_buffer_occupancy * 100) / total_buffer_capacity) : 8'h0;
        
        // Update lane active mask
        for (int i = 0; i < NUM_LANES; i++) begin
            lane_active_mask[i] = (i < actual_width) && training_complete && !lane_error[i];
        end
    end
    
    // Advanced performance metrics calculation
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            peak_sustainable_rate_gbps <= 16'h0;
            power_efficiency_score <= 8'h0;
            thermal_efficiency_score <= 8'h0;
            qos_compliance_percent <= 16'h0;
        end else if (performance_monitoring_active) begin
            // Calculate peak sustainable rate
            logic [31:0] theoretical_max_gbps;
            theoretical_max_gbps = actual_width * get_data_rate_value(negotiated_speed);
            
            if (instantaneous_throughput_mbps > (peak_sustainable_rate_gbps * 1000)) begin
                peak_sustainable_rate_gbps <= instantaneous_throughput_mbps / 1000;
            end
            
            // Calculate power efficiency (Gbps per Watt * 10)
            if (total_power_consumption_mw > 0) begin
                power_efficiency_score <= 8'((instantaneous_throughput_mbps / 1000 * 10000) / 
                                           total_power_consumption_mw);
            end
            
            // Calculate thermal efficiency score (performance vs temperature)
            if (die_temperature > 0) begin
                thermal_efficiency_score <= 8'((instantaneous_throughput_mbps / 1000 * 100) / 
                                              die_temperature);
            end
            
            // Calculate QoS compliance (simplified metric)
            logic [15:0] total_violations = 0;
            logic [15:0] total_transactions = 0;
            
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                total_violations = total_violations + protocol_error_count[i][15:0];
                total_transactions = total_transactions + protocol_tx_count[i][15:0];
            end
            
            if (total_transactions > 0) begin
                qos_compliance_percent <= 16'd10000 - 16'((total_violations * 10000) / total_transactions);
            end
        end
    end
    
    // Performance monitoring state machine
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            perf_state <= PERF_IDLE;
            perf_monitor_timer <= 8'h0;
        end else begin
            case (perf_state)
                PERF_IDLE: begin
                    if (performance_monitoring_active) begin
                        perf_state <= PERF_COLLECT;
                        perf_monitor_timer <= 8'd10;
                    end
                end
                
                PERF_COLLECT: begin
                    if (perf_monitor_timer > 0) begin
                        perf_monitor_timer <= perf_monitor_timer - 1;
                    end else begin
                        perf_state <= PERF_ANALYZE;
                        perf_monitor_timer <= 8'd5;
                    end
                end
                
                PERF_ANALYZE: begin
                    if (perf_monitor_timer > 0) begin
                        perf_monitor_timer <= perf_monitor_timer - 1;
                    end else begin
                        perf_state <= PERF_UPDATE;
                    end
                end
                
                PERF_UPDATE: begin
                    // Update efficiency calculations
                    perf_metrics.efficiency_percent <= 8'((instantaneous_throughput_mbps * 100) / 
                                                        ((actual_width * get_data_rate_value(negotiated_speed) * 1000) + 1));
                    perf_state <= PERF_REPORT;
                end
                
                PERF_REPORT: begin
                    perf_state <= PERF_IDLE;
                end
            endcase
        end
    end
    
    // Performance monitoring outputs
    logic [31:0] performance_summary_0, performance_summary_1;
    logic [31:0] performance_summary_2, performance_summary_3;
    
    assign performance_summary_0 = {
        perf_metrics.utilization_percent,    // [31:24] Link utilization
        perf_metrics.efficiency_percent,     // [23:16] Efficiency
        instantaneous_throughput_mbps[15:0]  // [15:0] Current throughput
    };
    
    assign performance_summary_1 = {
        perf_metrics.avg_latency_cycles,     // [31:16] Average latency
        perf_metrics.peak_latency_cycles     // [15:0] Peak latency
    };
    
    assign performance_summary_2 = {
        peak_sustainable_rate_gbps,          // [31:16] Peak rate
        qos_compliance_percent               // [15:0] QoS compliance
    };
    
    assign performance_summary_3 = {
        power_efficiency_score,              // [31:24] Power efficiency
        thermal_efficiency_score,            // [23:16] Thermal efficiency
        buffer_utilization_percent,          // [15:8] Buffer utilization
        link_utilization_percent            // [7:0] Link utilization
    };
    
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
            
            // Package-specific configuration register
            package_config_reg <= 32'h0;
        end else if (config_write && config_ready) begin
            if (config_addr < 64) begin
                config_regs[config_addr[5:0]] <= config_data;
            end
            
            // Handle package configuration register (address 4)
            if (config_addr == 16'h0004) begin
                package_config_reg <= config_data;
            end
        end else begin
            // Update package configuration register based on detected package type
            package_config_reg <= {
                8'h0,                           // [31:24] Reserved
                package_feature_mask,           // [23:16] Feature mask
                package_effective_lanes,        // [15:8]  Effective lanes
                2'b0,                          // [7:6]   Reserved
                package_type,                   // [5:4]   Package type
                package_effective_speed         // [3:0]   Effective speed
            };
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
        config_ready = config_read ? 1'b1 : 1'b0;
        if (config_read) begin
            case (config_addr)
                16'h0004: config_rdata = package_config_reg;  // Package configuration
                default: begin
                    if (config_addr < 64) begin
                        config_rdata = config_regs[config_addr[5:0]];
                    end else begin
                        config_rdata = 32'h0;
                    end
                end
            endcase
        end else begin
            config_rdata = 32'h0;
        end
    end
    
    // Package Status Output
    assign package_status = {
        8'h0,                           // [31:24] Reserved
        package_capability,             // [23:16] Input capability
        package_effective_lanes,        // [15:8]  Effective lanes
        2'b0,                          // [7:6]   Reserved
        package_type,                   // [5:4]   Package type
        package_effective_speed         // [3:0]   Effective speed
    };
    
    // Extract protocol info from D2D receive flit header
    flit_header_t d2d_rx_header;
    always_comb begin
        d2d_rx_header = extract_flit_header(d2d_rx_flit);
        d2d_rx_protocol_id = d2d_rx_header.protocol_id;
        d2d_rx_vc = d2d_rx_header.virtual_channel;
    end
    
    // Protocol Layer Instance
    ucie_protocol_layer #(
        .NUM_PROTOCOLS(NUM_PROTOCOLS),
        .BUFFER_DEPTH(BUFFER_DEPTH),
        .NUM_VCS(NUM_VCS)
    ) protocol_layer_inst (
        .clk(clk_main),
        .rst_n(rst_n),
        
        // Quarter-Rate Processing Support (128 Gbps enhancement)
        .clk_quarter_rate(clk_quarter_rate),
        .clk_symbol_rate(clk_symbol_rate),
        .quarter_rate_enable(ENABLE_QUARTER_RATE),
        
        // Upper Layer Interface
        .ul_tx_flit(ul_tx_flits),
        .ul_tx_valid(ul_tx_valid),
        .ul_tx_ready(ul_tx_ready),
        .ul_tx_vc(ul_tx_vcs),
        
        .ul_rx_flit(ul_rx_flits),
        .ul_rx_valid(ul_rx_valid),
        .ul_rx_ready(ul_rx_ready),
        .ul_rx_vc(ul_rx_vcs),
        
        // D2D Adapter Interface (Standard Path)
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
        
        // Enhanced 128 Gbps Interface (when parallel engines enabled)
        .enhanced_tx_flit_128g(protocol_tx_flit_128g),
        .enhanced_tx_valid_128g(protocol_tx_valid_128g),
        .enhanced_tx_ready_128g(protocol_tx_ready_128g),
        .enhanced_tx_protocol_id_128g(protocol_tx_protocol_id_128g),
        .enhanced_tx_vc_128g(protocol_tx_vc_128g),
        
        .enhanced_rx_flit_128g(protocol_rx_flit_128g),
        .enhanced_rx_valid_128g(protocol_rx_valid_128g),
        .enhanced_rx_ready_128g(protocol_rx_ready_128g),
        .enhanced_rx_protocol_id_128g(protocol_rx_protocol_id_128g),
        .enhanced_rx_vc_128g(protocol_rx_vc_128g),
        
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
    
    // Quarter-Rate Processor Instance (128 Gbps Enhancement)
    generate
        if (ENABLE_128GBPS && ENABLE_QUARTER_RATE) begin : gen_quarter_rate_processor
            ucie_quarter_rate_processor #(
                .DATA_WIDTH(512),              // 4x wider for quarter-rate
                .NUM_PARALLEL_STREAMS(4),      // 4 parallel streams
                .BUFFER_DEPTH(64),            // Deeper buffering for rate conversion
                .ENABLE_ML_OPTIMIZATION(1)     // ML-enhanced processing
            ) quarter_rate_processor_inst (
                // Clock Domains
                .clk_symbol_rate(clk_symbol_rate),
                .clk_quarter_rate(clk_quarter_rate),
                .clk_bit_rate(clk_bit_rate),
                .rst_n(rst_n),
                
                // Configuration
                .processor_enable(ENABLE_QUARTER_RATE),
                .processing_mode(2'b01),       // Quarter-rate mode
                .signaling_mode(ucie_pkg::SIGNALING_PAM4),
                .data_rate(ucie_pkg::DATA_RATE_128G),
                
                // Symbol-Rate Input Interface (from PAM4 PHY)
                .symbol_data_in(pam4_symbol_data_rx),
                .symbol_valid_in(pam4_symbol_valid_rx),
                .symbol_ready_out(pam4_symbol_ready_rx),
                
                // Quarter-Rate Output Interface (to Protocol Layer)
                .quarter_data_out(quarter_rate_data_rx),
                .quarter_valid_out(quarter_rate_valid_rx),
                .quarter_ready_in(quarter_rate_ready_rx),
                
                // Quarter-Rate Input Interface (from Protocol Layer)
                .quarter_data_in(quarter_rate_data_tx),
                .quarter_valid_in(quarter_rate_valid_tx),
                .quarter_ready_out(quarter_rate_ready_tx),
                
                // Symbol-Rate Output Interface (to PAM4 PHY)
                .symbol_data_out(pam4_symbol_data_tx),
                .symbol_valid_out(pam4_symbol_valid_tx),
                .symbol_ready_in(pam4_symbol_ready_tx),
                
                // Pipeline Control
                .pipeline_bypass(1'b0),        // No bypass for 128 Gbps
                .pipeline_stages(4'd4),        // 4-stage pipeline
                .pipeline_occupancy(),
                
                // ML-Enhanced Processing Interface
                .ml_enable(ml_global_enable),
                .ml_parameters(ml_protocol_parameters), // Use unified parameters
                .ml_performance_metrics(ml_performance_metrics),
                .ml_adaptation_rate({8'h0, ml_global_learning_rate}), // Use global learning rate
                
                // Rate Conversion Status
                .rate_conversion_active(),
                .conversion_statistics(),
                .buffer_occupancy(buffer_occupancy_128g),
                
                // Error Detection and Correction
                .rate_conversion_error(),
                .error_syndrome(),
                .error_correction_enable(1'b1),
                
                // Performance Monitoring
                .throughput_mbps(),
                .latency_cycles(),
                .efficiency_percent(),
                
                // Debug and Status
                .processor_status(quarter_rate_status),
                .debug_counters(quarter_rate_debug)
            );
        end else begin : gen_no_quarter_rate
            // Bypass mode when quarter-rate processing is disabled
            assign quarter_rate_data_rx = '0;
            assign quarter_rate_valid_rx = 1'b0;
            assign quarter_rate_ready_tx = 1'b1;
            assign pam4_symbol_data_tx = '0;
            assign pam4_symbol_valid_tx = '0;
            assign pam4_symbol_ready_rx = '1;
            assign quarter_rate_status = 32'h0;
            assign quarter_rate_debug = '0;
            assign ml_performance_metrics = '0;
            assign buffer_occupancy_128g = '0;
        end
    endgenerate
    
    // Parallel Protocol Engines Instance (128 Gbps Enhancement)
    generate
        if (ENABLE_128GBPS && ENABLE_PARALLEL_ENGINES) begin : gen_parallel_engines
            ucie_parallel_protocol_engines #(
                .NUM_ENGINES(4),                    // 4 parallel engines
                .ENGINE_BANDWIDTH_GBPS(32),        // 32 Gbps per engine
                .BUFFER_DEPTH(4096),               // Deep buffering per engine
                .NUM_VCS(NUM_VCS),                 // Virtual channels per engine
                .ENABLE_ML_OPTIMIZATION(1)          // ML-enhanced load balancing
            ) parallel_engines_inst (
                // Clock and Reset
                .clk_quarter_rate(clk_quarter_rate),
                .clk_symbol_rate(clk_symbol_rate),
                .rst_n(rst_n),
                
                // Configuration
                .engines_enable(ENABLE_PARALLEL_ENGINES),
                .num_active_engines(4'd4),          // All 4 engines active
                .load_balance_mode(2'b10),          // ML-enhanced mode
                
                // 128 Gbps Input Distribution Interface
                .flit_data_128g(protocol_tx_flit_128g),
                .flit_header_128g(ucie_pkg::extract_flit_header(protocol_tx_flit_128g)),
                .flit_valid_128g(protocol_tx_valid_128g),
                .flit_ready_128g(protocol_tx_ready_128g),
                .flit_protocol_id(protocol_tx_protocol_id_128g),
                .flit_vc(protocol_tx_vc_128g),
                
                // Per-Engine Interfaces (to individual protocol processors)
                .engine_data(engine_data_in),
                .engine_header(engine_header_in),
                .engine_valid(engine_valid_in),
                .engine_ready(engine_ready_in),
                .engine_protocol_id(engine_protocol_id_in),
                .engine_vc(engine_vc_in),
                
                // Aggregated Output from Engines
                .engine_out_data(engine_data_out),
                .engine_out_header(engine_header_out),
                .engine_out_valid(engine_valid_out),
                .engine_out_ready(engine_ready_out),
                .engine_out_protocol_id(engine_protocol_id_out),
                .engine_out_vc(engine_vc_out),
                
                // Combined 128 Gbps Output
                .flit_out_data_128g(protocol_rx_flit_128g),
                .flit_out_header_128g(protocol_rx_header_128g),
                .flit_out_valid_128g(protocol_rx_valid_128g),
                .flit_out_ready_128g(protocol_rx_ready_128g),
                .flit_out_protocol_id(protocol_rx_protocol_id_128g),
                .flit_out_vc(protocol_rx_vc_128g),
                
                // Load Balancing Interface
                .engine_weights('0),                // Default weights
                .engine_load(),
                .engine_throughput(),
                
                // ML-Enhanced Load Balancing
                .ml_enable(ml_global_enable),
                .ml_parameters(ml_protocol_parameters),  // Use unified parameters
                .ml_load_predictions(ml_engine_load_predictions),
                .ml_performance_metrics(ml_performance_metrics),
                
                // Flow Control and Congestion Management
                .vc_credits(config_vc_credits),
                .vc_consumed(),
                .engine_congested(),
                
                // Performance Monitoring
                .total_throughput_mbps(),
                .average_latency_cycles(),
                .load_balance_efficiency(),
                
                // Error Detection and Recovery
                .engine_errors(),
                .load_balance_error(),
                .error_recovery_enable(1'b1),
                
                // Status and Debug
                .engines_status(parallel_engines_status),
                .load_balance_stats(),
                .debug_counters(engine_debug)
            );
        end else begin : gen_no_parallel_engines
            // Bypass mode when parallel engines are disabled
            assign protocol_tx_flit_128g = '0;
            assign protocol_tx_valid_128g = 1'b0;
            assign protocol_tx_ready_128g = 1'b1;
            assign protocol_rx_flit_128g = '0;
            assign protocol_rx_valid_128g = 1'b0;
            assign protocol_rx_ready_128g = 1'b1;
            assign parallel_engines_status = 32'h0;
            assign engine_debug = '0;
        end
    endgenerate
    
    // D2D Adapter Instances
    // Enhanced CRC/Retry Engine (128 Gbps capable)
    logic retry_request, retry_in_progress, retry_buffer_full;
    logic [7:0] retry_sequence_num;
    logic [15:0] crc_error_count, retry_count;
    logic [7:0] buffer_occupancy_crc;
    logic [31:0] enhanced_retry_stats;
    logic ml_error_prediction_valid;
    logic [7:0] predicted_error_rate;
    
    ucie_enhanced_crc_retry #(
        .FLIT_WIDTH(ucie_pkg::FLIT_WIDTH),
        .RETRY_BUFFER_DEPTH(128),       // Deeper buffer for 128 Gbps
        .MAX_RETRY_COUNT(8),
        .ENHANCED_128G(ENABLE_128GBPS),
        .ML_PREDICTION(1)
    ) enhanced_crc_retry_inst (
        .clk(clk_main),
        .rst_n(rst_n),
        
        // Configuration
        .crc_enable(1'b1),
        .retry_enable(1'b1),
        .crc_polynomial_sel(4'h0),      // Default CRC-32
        .retry_timeout_cycles(8'd100),
        .enhanced_mode(ENABLE_128GBPS),
        
        // Transmit Path Interface
        .tx_flit_valid(d2d_tx_valid),
        .tx_flit_data(d2d_tx_flit),
        .tx_flit_sop(1'b1),             // Simplified for now
        .tx_flit_eop(1'b1),
        .tx_flit_be(4'hF),
        .tx_flit_vc(8'h0),              // Default VC
        .tx_flit_ready(d2d_tx_ready),
        
        // Transmit Output (to Physical Layer)
        .phy_tx_valid(phy_tx_valid),
        .phy_tx_data(phy_tx_flit),
        .phy_tx_sop(),                  // Not connected for now
        .phy_tx_eop(),
        .phy_tx_be(),
        .phy_tx_crc(phy_tx_crc),
        .phy_tx_sequence(),
        .phy_tx_ready(phy_tx_ready),
        
        // Receive Path Interface (from Physical Layer)
        .phy_rx_valid(phy_rx_valid),
        .phy_rx_data(phy_rx_flit),
        .phy_rx_sop(1'b1),
        .phy_rx_eop(1'b1),
        .phy_rx_be(4'hF),
        .phy_rx_crc(phy_rx_crc),
        .phy_rx_sequence(16'h0),
        .phy_rx_ready(phy_rx_ready),
        
        // Receive Output Interface
        .rx_flit_valid(d2d_rx_valid),
        .rx_flit_data(d2d_rx_flit),
        .rx_flit_sop(),
        .rx_flit_eop(),
        .rx_flit_be(),
        .rx_flit_vc(),
        .rx_flit_ready(d2d_rx_ready),
        
        // Retry Control Interface
        .retry_req(1'b0),               // No external retry request
        .retry_sequence(16'h0),
        .retry_ack(),
        .retry_complete(),
        
        // Status and Statistics
        .crc_status(),
        .retry_status(),
        .crc_error_count(crc_error_count),
        .retry_count(retry_count),
        .buffer_utilization(),
        
        // ML Enhancement Interface
        .ml_enable(ml_global_enable),
        .ml_error_threshold(ml_global_error_threshold),
        .ml_error_prediction(ml_crc_error_prediction),
        .ml_reliability_score(ml_crc_reliability_score),
        
        // Advanced 128 Gbps Features
        .burst_mode(ENABLE_128GBPS),
        .parallel_crc_lanes(4'd4),
        .crc_pipeline_ready(),
        
        // Debug and Performance
        .throughput_mbps(),
        .error_rate_ppm(),
        .buffer_overflow(),
        .sequence_error()
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
    
    // Advanced Lane Manager (128 Gbps capable with ML optimization)
    logic lane_mgmt_enable, reversal_detected, reversal_corrected;
    logic repair_enable, repair_active, width_degraded_lane;
    logic [NUM_LANES-1:0] repair_lanes;
    logic [7:0] good_lane_count;
    logic [15:0] lane_ber [NUM_LANES-1:0];
    logic [NUM_LANES-1:0] phy_lane_ready, phy_lane_trained;
    logic [7:0] phy_signal_quality [NUM_LANES-1:0];
    logic [15:0] phy_error_count [NUM_LANES-1:0];
    logic [7:0] active_lane_map [NUM_LANES-1:0];
    logic [7:0] logical_to_physical_map [NUM_LANES-1:0];
    logic [NUM_LANES-1:0] lane_group_boundaries;
    logic [7:0] lane_group_config [8-1:0];
    logic [NUM_LANES-1:0] ml_lane_predictions;
    logic [7:0] ml_optimization_metrics [4];
    
    // Initialize enhanced lane management signals  
    always_comb begin
        // Lane management read-only signals
        reversal_detected = 1'b0; // No lane reversal detected initially
        width_degraded_lane = 1'b0; // No width degradation initially
        
        // Initialize BER values (would come from PHY in real implementation)
        for (int i = 0; i < NUM_LANES; i++) begin
            lane_ber[i] = 16'h0100; // Low BER value
            phy_signal_quality[i] = 8'hF0; // Good signal quality
            phy_error_count[i] = 16'h0010;  // Low error count
        end
        
        // Initialize lane status
        phy_lane_ready = lane_enable;
        phy_lane_trained = lane_active;
        lane_error = '0; // No lane errors initially
        
        // Initialize lane group configuration
        for (int i = 0; i < 8; i++) begin
            lane_group_config[i] = 8'h8; // 8 lanes per group
        end
    end
    
    ucie_advanced_lane_manager #(
        .NUM_LANES(NUM_LANES),
        .MAX_LANE_GROUPS(8),
        .ENHANCED_128G(ENABLE_128GBPS),
        .ML_LANE_OPTIMIZATION(1),
        .DYNAMIC_REMAPPING(1),
        .REDUNDANCY_SUPPORT(1)
    ) advanced_lane_manager_inst (
        .clk(clk_main),
        .rst_n(rst_n),
        
        // System Configuration
        .lane_mgmt_enable(lane_mgmt_enable),
        .target_lane_count(requested_width),
        .min_lane_count(min_width),
        .signaling_mode(ENABLE_PAM4 ? ucie_pkg::SIGNALING_PAM4 : ucie_pkg::SIGNALING_NRZ),
        .data_rate(ENABLE_128GBPS ? ucie_pkg::DATA_RATE_128G : ucie_pkg::DATA_RATE_32G),
        
        // Physical Lane Interface
        .phy_lane_ready(phy_lane_ready),
        .phy_lane_error(lane_error),
        .phy_lane_trained(phy_lane_trained),
        .phy_signal_quality(phy_signal_quality),
        .phy_error_count(phy_error_count),
        .phy_lane_enable(lane_enable),
        .phy_lane_reset(),                  // Not connected for now
        
        // Lane Mapping and Configuration
        .lane_reversal_enable(1'b1),        // Enable lane reversal detection
        .lane_polarity_invert('0),          // No polarity inversion by default
        .lane_group_config(lane_group_config),
        .active_lane_map(active_lane_map),
        .logical_to_physical_map(logical_to_physical_map),
        .lane_group_boundaries(lane_group_boundaries),
        
        // Lane Repair and Recovery
        .repair_enable(repair_enable),
        .repair_trigger_threshold(16'h1000), // BER threshold
        .emergency_repair_enable(1'b1),
        .repair_status(repair_active),
        .repair_lanes_available(),
        .repair_in_progress(),
        
        // Width Management
        .width_negotiation_enable(1'b1),
        .current_width(actual_width),
        .width_degraded(width_degraded),
        .width_change_request(),
        
        // ML-Enhanced Lane Optimization
        .ml_optimization_enable(ml_global_enable),
        .ml_lane_predictions(ml_lane_predictions),
        .ml_optimization_metrics(ml_lane_optimization_metrics),
        .ml_learning_rate(ml_global_learning_rate),
        .ml_prediction_horizon(16'h1000),
        
        // Dynamic Lane Management
        .dynamic_remapping_enable(1'b1),
        .lane_performance_thresholds('0),   // Default thresholds
        .adaptive_repair_enable(1'b1),
        
        // Advanced Status
        .lane_quality_metrics(),
        .lane_utilization_stats(),
        .predictive_maintenance_alerts(),
        
        // Legacy compatibility outputs
        .lane_good(lane_good),
        .lane_marginal(lane_marginal),
        .lane_failed(lane_failed),
        .good_lane_count(good_lane_count)
    );
    
    // Sideband Engine
    logic training_enable, training_complete, training_error;
    logic [15:0] training_pattern, received_pattern;
    logic [NUM_LANES-1:0] lane_enable_req, lane_enable_ack;
    logic [7:0] width_req, width_ack;
    
    // Initialize read-only training and configuration signals
    always_comb begin
        training_pattern = 16'hA55A;      // Standard training pattern
        lane_enable_req = '1;             // Request all lanes enabled initially
        width_req = NUM_LANES[7:0];       // Request full width
    end
    
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
    
    // PAM4 PHY Instance for 128 Gbps Operation
    logic [NUM_LANES-1:0] pam4_phy_ready;
    logic [5:0] dfe_tap_weights [NUM_LANES-1:0][31:0];  // 32-tap DFE per lane
    logic [4:0] ffe_tap_weights [NUM_LANES-1:0][15:0];  // 16-tap FFE per lane
    logic [NUM_LANES-1:0] eq_converged;
    logic [NUM_LANES-1:0] thermal_alarm;
    logic [15:0] power_consumption [NUM_LANES-1:0];  // Power per lane in mW
    
    generate
        if (ENABLE_PAM4) begin : gen_pam4_phy_instance
            ucie_pam4_phy #(
                .SYMBOL_RATE_GSPS(SYMBOL_RATE_GSPS),
                .NUM_LANES(NUM_LANES),
                .POWER_OPTIMIZATION(1),        // Enable 72% power reduction
                .ADVANCED_EQUALIZATION(1),     // Enable 32-tap DFE + 16-tap FFE
                .THERMAL_MANAGEMENT(1)         // Enable thermal management
            ) pam4_phy_inst (
                // Clock and Reset
                .clk_symbol(clk_symbol_rate),
                .clk_quarter(clk_quarter_rate),
                .clk_bit(clk_bit_rate),
                .rst_n(rst_n),
                
                // Configuration Interface
                .phy_enable(ENABLE_PAM4),
                .target_lanes(actual_width),
                .signaling_mode(ucie_pkg::SIGNALING_PAM4),
                .data_rate(ucie_pkg::DATA_RATE_128G),
                .phy_ready(pam4_phy_ready),
                
                // Lane Data Interface (PAM4 Symbols)
                .tx_symbols(pam4_tx_symbols),
                .tx_symbol_valid(pam4_tx_symbol_valid),
                .tx_symbol_ready(),  // Not used for now
                
                .rx_symbols(pam4_rx_symbols),
                .rx_symbol_valid(pam4_rx_symbol_valid),
                .rx_symbol_ready('1),  // Always ready
                
                // Physical Pins (to/from package)  
                .phy_tx_p(pam4_tx_p),
                .phy_tx_n(pam4_tx_n),
                .phy_rx_p(pam4_rx_p),
                .phy_rx_n(pam4_rx_n),
                
                // Advanced Equalization Control
                .dfe_tap_weights(dfe_tap_weights),
                .ffe_tap_weights(ffe_tap_weights),
                .eq_adaptation_enable(1'b1),    // Enable adaptive equalization
                .eq_converged(eq_converged),
                
                // Thermal Management Interface  
                .die_temperature(8'd45),        // 45°C nominal operating temperature
                .thermal_throttle_req('0),      // No throttling by default
                .power_consumption(power_consumption),
                .thermal_alarm(thermal_alarm),
                
                // ML Enhancement Interface
                .ml_optimization_enable(ml_global_enable),
                .ml_eq_parameters(ml_phy_parameters),
                .ml_performance_metrics(ml_phy_performance_metrics),
                
                // Status and Debug
                .phy_status(),
                .signal_integrity_metrics(),
                .error_injection_enable(1'b0),
                .debug_bus()
            );
            
            // Connect PAM4 symbols to quarter-rate processor
            always_comb begin
                for (int i = 0; i < 4; i++) begin
                    pam4_symbol_data_rx[i] = pam4_rx_symbols[i*16];  // Subsample lanes
                    pam4_symbol_valid_rx[i] = pam4_rx_symbol_valid[i*16];
                    pam4_tx_symbols[i*16] = pam4_symbol_data_tx[i];
                    pam4_tx_symbol_valid[i*16] = pam4_symbol_valid_tx[i];
                end
            end
            
            // PAM4 Clock forwarding
            assign mb_clk_fwd = clk_symbol_rate;
            
        end else begin : gen_nrz_interface
            // NRZ Legacy Interface
            assign mb_clk_fwd = clk_main;
            assign mb_data = phy_tx_flit[NUM_LANES-1:0]; // Map flit to lanes
            assign mb_valid = phy_tx_valid;
            assign phy_tx_ready = mb_ready;
            
            assign phy_rx_flit = {{(FLIT_WIDTH-NUM_LANES){1'b0}}, mb_data_in};
            assign phy_rx_valid = mb_valid_in;
            assign mb_ready_out = phy_rx_ready;
            
            // Tie off PAM4 interfaces when not used
            assign pam4_tx_p = '0;
            assign pam4_tx_n = '0;
            assign pam4_rx_symbols = '0;
            assign pam4_tx_symbols = '0;
            assign pam4_tx_symbol_valid = '0;
        end
    endgenerate
    
    assign phy_rx_crc = 32'h0; // Simplified - would come from PHY
    
    // Status and Monitoring
    assign link_training_complete = training_complete;
    assign link_active = (actual_width > 0) && !training_error;
    assign link_error = training_error || param_exchange_error;
    
    // Controller status base (lower 16 bits)
    logic [15:0] controller_status_base;
    assign controller_status_base = {
        4'h0,                    // Reserved  
        negotiated_protocols,    // Negotiated protocols
        actual_width,            // Current width
        negotiated_speed         // Current speed
    };
    
    // Upper bits will be driven by ML logic separately
    logic [15:0] controller_status_upper;
    
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
    
    // 128 Gbps Enhancement Status Outputs
    assign gbps_128_status = {
        ENABLE_128GBPS,              // [31] - 128 Gbps mode enabled
        ENABLE_PAM4,                 // [30] - PAM4 signaling enabled  
        ENABLE_QUARTER_RATE,         // [29] - Quarter-rate processing enabled
        ENABLE_PARALLEL_ENGINES,     // [28] - Parallel engines enabled
        4'h0,                        // [27:24] - Reserved
        SYMBOL_RATE_GSPS[7:0],       // [23:16] - Symbol rate in Gsym/s
        actual_width,                // [15:8] - Current lane width
        negotiated_speed             // [7:0] - Current speed
    };
    
    // Quarter-Rate Processing Metrics
    generate
        if (ENABLE_128GBPS && ENABLE_QUARTER_RATE) begin : gen_quarter_rate_metrics
            assign quarter_rate_metrics[0] = quarter_rate_debug[0];  // Symbols processed
            assign quarter_rate_metrics[1] = quarter_rate_debug[1];  // Quarter words processed
            assign quarter_rate_metrics[2] = buffer_occupancy_128g[0]; // RX buffer occupancy
            assign quarter_rate_metrics[3] = buffer_occupancy_128g[1]; // TX buffer occupancy
        end else begin : gen_no_quarter_rate_metrics
            assign quarter_rate_metrics = '0;
        end
    endgenerate
    
    // Parallel Engine Statistics
    generate
        if (ENABLE_128GBPS && ENABLE_PARALLEL_ENGINES) begin : gen_parallel_engine_metrics
            assign parallel_engine_stats[0] = engine_debug[0];  // Engine 0 flit count
            assign parallel_engine_stats[1] = engine_debug[1];  // Engine 1 flit count
            assign parallel_engine_stats[2] = engine_debug[2];  // Engine 2 flit count
            assign parallel_engine_stats[3] = engine_debug[3];  // Engine 3 flit count
        end else begin : gen_no_parallel_engine_metrics
            assign parallel_engine_stats = '0;
        end
    endgenerate
    
    // ML System Aggregation and Monitoring
    logic [7:0] ml_global_performance_score;
    logic [15:0] ml_total_predictions;
    logic [7:0] ml_adaptation_success_rate;
    
    always_ff @(posedge clk_main or negedge rst_n) begin
        if (!rst_n) begin
            ml_global_performance_score <= 8'h80;  // Default score (50%)
            ml_total_predictions <= 16'h0;
            ml_adaptation_success_rate <= 8'h80;   // Default success rate (50%)
        end else if (ml_global_enable) begin
            // Aggregate ML performance across all modules
            logic [15:0] total_score;
            logic [7:0] module_count;
            
            total_score = 16'h0;
            module_count = 8'h0;
            
            // Aggregate protocol engine ML metrics
            for (int i = 0; i < 4; i++) begin
                if (ml_performance_metrics[i] > 0) begin
                    total_score = total_score + ml_performance_metrics[i];
                    module_count = module_count + 1;
                end
            end
            
            // Aggregate lane manager ML metrics
            for (int i = 0; i < 4; i++) begin
                if (ml_lane_optimization_metrics[i] > 0) begin
                    total_score = total_score + ml_lane_optimization_metrics[i];
                    module_count = module_count + 1;
                end
            end
            
            // Aggregate PHY ML metrics (sample first few lanes)
            for (int i = 0; i < 8 && i < NUM_LANES; i++) begin
                if (ml_phy_performance_metrics[i] > 0) begin
                    total_score = total_score + ml_phy_performance_metrics[i];
                    module_count = module_count + 1;
                end  
            end
            
            // Add CRC reliability score
            if (ml_crc_reliability_score > 0) begin
                total_score = total_score + ml_crc_reliability_score;
                module_count = module_count + 1;
            end
            
            // Calculate global performance score
            if (module_count > 0) begin
                ml_global_performance_score <= 8'(total_score / module_count);
            end
            
            // Count total predictions made
            ml_total_predictions <= ml_total_predictions + 1;
            
            // Calculate adaptation success rate based on error reduction
            if (crc_error_count == 0 && protocol_error_count == 0) begin
                if (ml_adaptation_success_rate < 8'hFE) begin
                    ml_adaptation_success_rate <= ml_adaptation_success_rate + 1;
                end
            end else begin
                if (ml_adaptation_success_rate > 8'h01) begin
                    ml_adaptation_success_rate <= ml_adaptation_success_rate - 1;
                end
            end
        end
    end
    
    // ML Status Output - combine with base status
    always_comb begin
        // Set upper 16 bits with ML status
        controller_status_upper = {
            8'h0,                       // [31:24] Reserved
            ml_global_enable,           // [23] ML globally enabled
            2'b0,                       // [22:21] Reserved
            ml_global_performance_score[7:3], // [20:16] Performance score (top 5 bits)
        };
    end
    
    // Final controller status assignment
    assign controller_status = {controller_status_upper, controller_status_base};

    // ================================================
    // VERIFICATION FRAMEWORK
    // ================================================
    
    // Verification Enable Control
    logic verification_enable;
    assign verification_enable = 1'b1; // Can be controlled via configuration
    
    // ================================================
    // SVA ASSERTIONS
    // ================================================
    
    // Clock Domain Assertions
    property clk_stable;
        @(posedge clk) $stable(clk);
    endproperty
    
    assert_clk_stable: assert property (clk_stable)
        else $error("[ASSERTION] Clock stability violation detected");
    
    // Reset Sequence Assertions
    property reset_sequence;
        @(posedge clk) !rst_n |-> ##[1:10] (current_link_state == LINK_RESET);
    endproperty
    
    assert_reset_sequence: assert property (disable iff (!verification_enable) reset_sequence)
        else $error("[ASSERTION] Reset sequence violation - link state not RESET after reset deassertion");
    
    // Link State Progression Assertions
    property link_state_progression;
        @(posedge clk) disable iff (!rst_n || !verification_enable)
        (current_link_state == LINK_RESET) |-> 
        ##[1:1000] (current_link_state == LINK_SBINIT);
    endproperty
    
    assert_link_progression: assert property (link_state_progression)
        else $error("[ASSERTION] Link state progression violation - RESET to SBINIT timeout");
    
    // 128 Gbps PAM4 Configuration Assertions
    property pam4_128g_config;
        @(posedge clk) disable iff (!rst_n || !verification_enable)
        (config_data_rate == DATA_RATE_128G) |-> (config_signaling_mode == SIGNALING_PAM4);
    endproperty
    
    assert_pam4_128g: assert property (pam4_128g_config)
        else $error("[ASSERTION] 128 Gbps requires PAM4 signaling mode");
    
    // Power Management Assertions
    property power_transition_valid;
        @(posedge clk) disable iff (!rst_n || !verification_enable)
        $changed(config_power_state) |-> 
        ##[1:100] (current_power_state == config_power_state);
    endproperty
    
    assert_power_transition: assert property (power_transition_valid)
        else $error("[ASSERTION] Power state transition timeout or invalid");
    
    // Protocol Layer Ready Assertions
    property protocol_ready_sequence;
        @(posedge clk) disable iff (!rst_n || !verification_enable)
        (current_link_state == LINK_ACTIVE) |-> protocol_layer_ready;
    endproperty
    
    assert_protocol_ready: assert property (protocol_ready_sequence)
        else $error("[ASSERTION] Protocol layer not ready when link is active");
    
    // Multi-Module Coordination Assertions
    property multi_module_sync;
        @(posedge clk) disable iff (!rst_n || !verification_enable || !ENABLE_MULTI_MODULE)
        (mm_state == MM_SYNCHRONIZED) |-> 
        (mm_master_ready && mm_sync_achieved);
    endproperty
    
    assert_multi_module: assert property (multi_module_sync)
        else $error("[ASSERTION] Multi-module synchronization violation");
    
    // Parameter Validation Assertions
    property valid_lane_config;
        @(posedge clk) disable iff (!rst_n || !verification_enable)
        (config_num_lanes >= MIN_LANES) && (config_num_lanes <= MAX_LANES);
    endproperty
    
    assert_lane_config: assert property (valid_lane_config)
        else $error("[ASSERTION] Invalid lane configuration: %d", config_num_lanes);
    
    // Performance Monitoring Assertions
    property throughput_bounds;
        @(posedge clk) disable iff (!rst_n || !verification_enable)
        (current_link_state == LINK_ACTIVE) |-> 
        (perf_throughput_mbps <= perf_max_throughput_mbps);
    endproperty
    
    assert_throughput_bounds: assert property (throughput_bounds)
        else $error("[ASSERTION] Throughput exceeds maximum: %d > %d", 
                   perf_throughput_mbps, perf_max_throughput_mbps);
    
    // Error Recovery Assertions
    property error_recovery_timeout;
        @(posedge clk) disable iff (!rst_n || !verification_enable)
        (error_recovery_state == ERR_RECOVERY_ACTIVE) |-> 
        ##[1:10000] (error_recovery_state == ERR_RECOVERY_COMPLETE);
    endproperty
    
    assert_error_recovery: assert property (error_recovery_timeout)
        else $error("[ASSERTION] Error recovery timeout - stuck in recovery state");
    
    // ================================================
    // FUNCTIONAL COVERAGE
    // ================================================
    
    // Coverage Groups
    covergroup cg_link_states @(posedge clk);
        option.per_instance = 1;
        option.name = "link_states_coverage";
        
        link_state_cp: coverpoint current_link_state {
            bins reset_state = {LINK_RESET};
            bins init_states = {LINK_SBINIT, LINK_PARAM, LINK_MBINIT};
            bins training_states = {LINK_CAL, LINK_MBTRAIN, LINK_LINKINIT};
            bins active_state = {LINK_ACTIVE};
            bins power_states = {LINK_L1, LINK_L2};
            bins recovery_states = {LINK_RETRAIN, LINK_REPAIR};
            bins error_state = {LINK_ERROR};
            
            // State transition coverage
            bins reset_to_init = (LINK_RESET => LINK_SBINIT);
            bins init_to_active = (LINK_SBINIT => LINK_PARAM => LINK_MBINIT => 
                                 LINK_CAL => LINK_MBTRAIN => LINK_LINKINIT => LINK_ACTIVE);
            bins active_to_power = (LINK_ACTIVE => LINK_L1), (LINK_ACTIVE => LINK_L2);
            bins power_to_active = (LINK_L1 => LINK_ACTIVE), (LINK_L2 => LINK_ACTIVE);
            bins error_recovery = (LINK_ERROR => LINK_RETRAIN => LINK_ACTIVE);
        }
        
        training_state_cp: coverpoint current_training_state {
            bins training_sequence = {TRAIN_RESET, TRAIN_SBINIT, TRAIN_PARAM, 
                                    TRAIN_MBINIT, TRAIN_CAL, TRAIN_MBTRAIN, 
                                    TRAIN_LINKINIT, TRAIN_ACTIVE};
            bins special_modes = {TRAIN_RETIMER, TRAIN_TEST, TRAIN_COMPLIANCE, 
                                TRAIN_LOOPBACK, TRAIN_PATGEN};
            bins multi_module = {TRAIN_MULTIMOD};
            bins error_states = {TRAIN_ERROR, TRAIN_RETRAIN, TRAIN_REPAIR};
        }
        
        power_state_cp: coverpoint current_power_state {
            bins active_power = {PWR_L0};
            bins low_power = {PWR_L1, PWR_L2};
            bins power_off = {PWR_L3};
        }
    endgroup
    
    covergroup cg_128g_features @(posedge clk);
        option.per_instance = 1;
        option.name = "128gbps_features_coverage";
        
        data_rate_cp: coverpoint config_data_rate {
            bins low_speed = {DR_4GT, DR_8GT, DR_12GT, DR_16GT};
            bins mid_speed = {DR_24GT, DR_32GT};
            bins high_speed = {DR_64GT};
            bins ultra_speed = {DR_128GT};
        }
        
        signaling_mode_cp: coverpoint config_signaling_mode {
            bins nrz_mode = {SIG_NRZ};
            bins pam4_mode = {SIG_PAM4};
            bins future_mode = {SIG_PAM8};
        }
        
        package_type_cp: coverpoint config_package_type {
            bins standard_pkg = {PKG_STANDARD};
            bins advanced_pkg = {PKG_ADVANCED};
            bins ucie_3d_pkg = {PKG_UCIE_3D};
        }
        
        // Cross coverage for 128 Gbps configurations
        cross_128g: cross data_rate_cp, signaling_mode_cp, package_type_cp {
            bins valid_128g = cross_128g with (data_rate_cp == DR_128GT && 
                                             signaling_mode_cp == SIG_PAM4);
            bins invalid_128g_nrz = cross_128g with (data_rate_cp == DR_128GT && 
                                                   signaling_mode_cp == SIG_NRZ);
        }
    endgroup
    
    covergroup cg_protocol_coverage @(posedge clk);
        option.per_instance = 1;
        option.name = "protocol_coverage";
        
        protocol_cp: coverpoint config_protocol_enable {
            bins pcie_only = {4'b0001};
            bins cxl_only = {4'b1110};
            bins streaming_only = {4'b0100};
            bins mgmt_only = {4'b1000};
            bins multi_protocol = {[4'b0011:4'b1111]};
        }
        
        vc_usage_cp: coverpoint rx_flit_vc {
            bins mgmt_vc = {8'h00};
            bins low_priority = {[8'h01:8'h3F]};
            bins high_priority = {[8'h40:8'h7F]};
            bins broadcast = {8'hFF};
        }
    endgroup
    
    covergroup cg_error_scenarios @(posedge clk);
        option.per_instance = 1;
        option.name = "error_scenarios_coverage";
        
        error_type_cp: coverpoint error_type {
            bins no_error = {ERR_NONE};
            bins data_errors = {ERR_CRC, ERR_SEQUENCE};
            bins protocol_errors = {ERR_PROTOCOL, ERR_BUFFER_OVERFLOW};
            bins timing_errors = {ERR_TIMEOUT, ERR_PARAM_MISMATCH};
            bins hardware_errors = {ERR_LANE_FAILURE, ERR_TRAINING};
            bins system_errors = {ERR_POWER, ERR_SIDEBAND};
            bins unknown_error = {ERR_UNKNOWN};
        }
        
        recovery_state_cp: coverpoint error_recovery_state {
            bins idle = {ERR_RECOVERY_IDLE};
            bins detecting = {ERR_RECOVERY_DETECT};
            bins isolating = {ERR_RECOVERY_ISOLATE};
            bins correcting = {ERR_RECOVERY_CORRECT};
            bins complete = {ERR_RECOVERY_COMPLETE};
            bins failed = {ERR_RECOVERY_FAILED};
        }
        
        // Cross coverage of error types and recovery
        cross_error_recovery: cross error_type_cp, recovery_state_cp;
    endgroup
    
    covergroup cg_performance_metrics @(posedge clk);
        option.per_instance = 1;
        option.name = "performance_metrics_coverage";
        
        throughput_cp: coverpoint perf_throughput_mbps {
            bins low_throughput = {[0:1000]};
            bins med_throughput = {[1001:10000]};
            bins high_throughput = {[10001:50000]};
            bins ultra_throughput = {[50001:128000]};
        }
        
        latency_cp: coverpoint perf_avg_latency_cycles {
            bins low_latency = {[0:10]};
            bins med_latency = {[11:50]};
            bins high_latency = {[51:100]};
            bins very_high_latency = {[101:1000]};
        }
        
        utilization_cp: coverpoint perf_link_utilization {
            bins low_util = {[0:25]};
            bins med_util = {[26:50]};
            bins high_util = {[51:85]};
            bins max_util = {[86:100]};
        }
    endgroup
    
    // Instantiate Coverage Groups
    cg_link_states link_states_cov;
    cg_128g_features features_128g_cov;
    cg_protocol_coverage protocol_cov;
    cg_error_scenarios error_cov;
    cg_performance_metrics perf_cov;
    
    initial begin
        if (verification_enable) begin
            link_states_cov = new();
            features_128g_cov = new();
            protocol_cov = new();
            error_cov = new();
            perf_cov = new();
            
            $display("[VERIFICATION] Coverage groups initialized");
        end
    end
    
    // ================================================
    // TESTBENCH HELPER FUNCTIONS
    // ================================================
    
    // Function to check if current configuration is valid for 128 Gbps
    function automatic logic is_valid_128g_config();
        return (config_data_rate == DATA_RATE_128G) && 
               (config_signaling_mode == SIGNALING_PAM4) &&
               (config_num_lanes >= 8) && 
               (config_num_lanes <= 64);
    endfunction
    
    // Function to calculate expected throughput
    function automatic logic [31:0] calc_expected_throughput_mbps();
        logic [31:0] lane_rate_mbps;
        
        case (config_data_rate)
            DR_4GT:   lane_rate_mbps = 4000;
            DR_8GT:   lane_rate_mbps = 8000;
            DR_12GT:  lane_rate_mbps = 12000;
            DR_16GT:  lane_rate_mbps = 16000;
            DR_24GT:  lane_rate_mbps = 24000;
            DR_32GT:  lane_rate_mbps = 32000;
            DR_64GT:  lane_rate_mbps = 64000;
            DR_128GT: lane_rate_mbps = 128000;
            default:  lane_rate_mbps = 4000;
        endcase
        
        return lane_rate_mbps * config_num_lanes;
    endfunction
    
    // Function to validate power consumption
    function automatic logic is_power_within_budget();
        logic [31:0] expected_power_mw;
        expected_power_mw = get_power_per_lane_mw(config_data_rate, config_signaling_mode) * config_num_lanes;
        return (perf_power_consumption_mw <= (expected_power_mw + (expected_power_mw >> 3))); // 12.5% tolerance
    endfunction
    
    // ================================================
    // VERIFICATION MONITORS
    // ================================================
    
    // Performance Monitor
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset monitoring
        end else if (verification_enable && current_link_state == LINK_ACTIVE) begin
            // Check throughput bounds
            if (perf_throughput_mbps > calc_expected_throughput_mbps()) begin
                $warning("[MONITOR] Throughput %d exceeds expected %d", 
                        perf_throughput_mbps, calc_expected_throughput_mbps());
            end
            
            // Check power consumption
            if (!is_power_within_budget()) begin
                $warning("[MONITOR] Power consumption %d mW exceeds budget", 
                        perf_power_consumption_mw);
            end
            
            // Check 128 Gbps specific metrics
            if (config_data_rate == DATA_RATE_128G) begin
                if (perf_power_efficiency_pj_per_bit > 1000) begin // 1 pJ/bit target
                    $warning("[MONITOR] 128G power efficiency %d pJ/bit exceeds target", 
                            perf_power_efficiency_pj_per_bit);
                end
            end
        end
    end
    
    // Error Monitor
    always_ff @(posedge clk) begin
        if (verification_enable && error_condition) begin
            $info("[MONITOR] Error detected: Type=%s, Recovery=%s", 
                  error_type.name(), error_recovery_state.name());
        end
    end
    
    // Link State Monitor
    always_ff @(posedge clk) begin
        if (verification_enable && $changed(current_link_state)) begin
            $info("[MONITOR] Link state transition: %s -> %s", 
                  $past(current_link_state).name(), current_link_state.name());
        end
    end
    
    // ================================================
    // VERIFICATION SUMMARY GENERATION
    // ================================================
    
    // Coverage summary task
    task automatic print_coverage_summary();
        real link_cov, feature_cov, protocol_cov_val, error_cov_val, perf_cov_val;
        
        if (verification_enable) begin
            link_cov = link_states_cov.get_inst_coverage();
            feature_cov = features_128g_cov.get_inst_coverage();
            protocol_cov_val = protocol_cov.get_inst_coverage();
            error_cov_val = error_cov.get_inst_coverage();
            perf_cov_val = perf_cov.get_inst_coverage();
            
            $display("==========================================");
            $display("UCIE CONTROLLER VERIFICATION SUMMARY");
            $display("==========================================");
            $display("Link States Coverage:     %0.2f%%", link_cov);
            $display("128G Features Coverage:   %0.2f%%", feature_cov);
            $display("Protocol Coverage:        %0.2f%%", protocol_cov_val);
            $display("Error Scenarios Coverage: %0.2f%%", error_cov_val);
            $display("Performance Coverage:     %0.2f%%", perf_cov_val);
            $display("==========================================");
            $display("Overall Coverage:         %0.2f%%", 
                    (link_cov + feature_cov + protocol_cov_val + error_cov_val + perf_cov_val) / 5.0);
            $display("==========================================");
        end
    endtask
    
    // Final verification report
    final begin
        if (verification_enable) begin
            print_coverage_summary();
            $display("[VERIFICATION] UCIe Controller verification framework completed");
        end
    end

endmodule
