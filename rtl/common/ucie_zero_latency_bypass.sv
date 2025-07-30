module ucie_zero_latency_bypass
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter DATA_WIDTH = 512,             // Bypass data width
    parameter NUM_BYPASS_LANES = 16,        // Dedicated bypass lanes
    parameter NUM_PRIORITY_LEVELS = 8,      // Priority classification levels
    parameter ENHANCED_128G = 1,            // Enable 128 Gbps optimizations
    parameter ML_PREDICTION = 1,            // Enable ML-based bypass prediction
    parameter BYPASS_BUFFER_DEPTH = 4       // Minimal buffering for bypass path
) (
    // Clock and Reset
    input  logic                clk_symbol_rate,     // 64 GHz symbol clock
    input  logic                clk_quarter_rate,    // 16 GHz quarter-rate
    input  logic                rst_n,
    
    // Configuration
    input  logic                bypass_global_enable,
    input  logic [7:0]          latency_threshold_ns, // Packets below this get bypass
    input  logic [7:0]          bypass_utilization_limit, // Max bypass utilization %
    input  logic                ml_enable,
    
    // Normal Path Interface (Input)
    input  logic [DATA_WIDTH-1:0]    normal_data_in,
    input  ucie_flit_header_t         normal_header_in,
    input  logic                      normal_valid_in,
    output logic                      normal_ready_out,
    
    // Normal Path Interface (Output)
    output logic [DATA_WIDTH-1:0]    normal_data_out,
    output ucie_flit_header_t         normal_header_out,
    output logic                      normal_valid_out,
    input  logic                      normal_ready_in,
    
    // Bypass Path Interface (Input)
    input  logic [DATA_WIDTH-1:0]    bypass_data_in,
    input  ucie_flit_header_t         bypass_header_in,
    input  logic                      bypass_valid_in,
    output logic                      bypass_ready_out,
    
    // Bypass Path Interface (Output)
    output logic [DATA_WIDTH-1:0]    bypass_data_out,
    output ucie_flit_header_t         bypass_header_out,
    output logic                      bypass_valid_out,
    input  logic                      bypass_ready_in,
    
    // Multiplexed Output (Combined normal + bypass)
    output logic [DATA_WIDTH-1:0]    mux_data_out,
    output ucie_flit_header_t         mux_header_out,
    output logic                      mux_valid_out,
    input  logic                      mux_ready_in,
    
    // Priority Classification Interface
    input  logic [2:0]          priority_class [NUM_PRIORITY_LEVELS],
    input  logic [7:0]          bypass_enable_mask,  // Per-protocol bypass enable
    output logic [2:0]          active_priority_level,
    
    // ML Enhancement Interface
    input  logic [15:0]         ml_traffic_prediction,
    input  logic [7:0]          ml_latency_prediction,
    output logic [7:0]          bypass_efficiency_score,
    output logic [15:0]         ml_bypass_optimization,
    
    // Latency Measurement and Optimization
    output logic [15:0]         measured_latency_cycles,
    output logic [15:0]         bypass_latency_cycles,
    output logic [7:0]          latency_reduction_percent,
    
    // Performance Monitoring
    output logic [31:0]         bypass_packets_count,
    output logic [31:0]         normal_packets_count,
    output logic [31:0]         total_bytes_bypassed,
    output logic [7:0]          bypass_utilization_percent,
    
    // Real-time Analytics
    output logic [15:0]         average_bypass_latency_ns,
    output logic [15:0]         average_normal_latency_ns,
    output logic [7:0]          bypass_hit_ratio_percent,
    
    // Debug and Status
    output logic [31:0]         bypass_status,
    output logic [15:0]         error_count,
    output logic [7:0]          congestion_level
);

    // Bypass Decision Engine
    typedef struct packed {
        logic [DATA_WIDTH-1:0]  data;
        ucie_flit_header_t      header;
        logic [31:0]           timestamp;
        logic [15:0]           predicted_latency;
        logic [2:0]            priority_level;
        logic                  bypass_eligible;
        logic                  ml_predicted;
        logic                  valid;
    } bypass_packet_t;
    
    typedef struct packed {
        logic [7:0]            utilization;
        logic [15:0]           queue_depth;
        logic [7:0]            congestion;
        logic [31:0]           throughput;
        logic                  overload;
    } bypass_metrics_t;
    
    // Minimal Bypass Buffers (Ultra-low latency)
    bypass_packet_t bypass_buffer [BYPASS_BUFFER_DEPTH-1:0];
    bypass_packet_t normal_buffer [BYPASS_BUFFER_DEPTH-1:0];
    
    // Buffer Pointers
    logic [1:0] bypass_wr_ptr, bypass_rd_ptr;
    logic [1:0] normal_wr_ptr, normal_rd_ptr;
    
    // Performance Counters
    logic [31:0] global_cycle_counter;
    logic [31:0] bypass_packet_counter;
    logic [31:0] normal_packet_counter;
    logic [31:0] bypass_byte_counter;
    logic [31:0] latency_accumulator_bypass;
    logic [31:0] latency_accumulator_normal;
    
    // ML Enhancement State
    logic [7:0] ml_bypass_prediction_accuracy;
    logic [15:0] ml_traffic_pattern_history [8];
    logic [7:0] ml_learning_coefficient;
    logic [31:0] ml_learning_cycles;
    
    // Bypass Decision Logic
    logic [7:0] current_bypass_utilization;
    logic bypass_path_congested;
    logic normal_path_congested;
    logic [2:0] packet_priority_classification;
    
    // Real-time Latency Tracking
    logic [15:0] instant_bypass_latency;
    logic [15:0] instant_normal_latency;
    logic [7:0] latency_improvement_ratio;
    
    // Buffer Status
    logic bypass_buffer_full, bypass_buffer_empty;
    logic normal_buffer_full, normal_buffer_empty;
    
    // Initialize buffers
    initial begin
        for (int i = 0; i < BYPASS_BUFFER_DEPTH; i++) begin
            bypass_buffer[i] = '0;
            normal_buffer[i] = '0;
        end
    end
    
    // Global Cycle Counter
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            global_cycle_counter <= 32'h0;
        end else begin
            global_cycle_counter <= global_cycle_counter + 1;
        end
    end
    
    // Bypass Eligibility Decision Engine
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            packet_priority_classification <= 3'h0;
        end else if (bypass_global_enable) begin
            
            // Priority-based classification
            if (bypass_valid_in) begin
                ucie_flit_header_t current_header = bypass_header_in;
                
                // High priority classification
                case (current_header.flit_type)
                    FLIT_MGMT: packet_priority_classification <= 3'h7;      // Highest: Management
                    FLIT_CTRL: packet_priority_classification <= 3'h6;      // High: Control
                    FLIT_PROTOCOL: begin
                        case (current_header.protocol_id)
                            PROTOCOL_CXL: packet_priority_classification <= 3'h5;  // High: CXL
                            PROTOCOL_PCIE: packet_priority_classification <= 3'h4; // Medium: PCIe
                            default: packet_priority_classification <= 3'h3;       // Medium: Others
                        endcase
                    end
                    FLIT_DATA: packet_priority_classification <= 3'h2;      // Low: Data
                    default: packet_priority_classification <= 3'h1;        // Lowest: Unknown
                endcase
                
                // ML-enhanced priority adjustment
                if (ML_PREDICTION && ml_enable) begin
                    if (ml_latency_prediction < latency_threshold_ns) begin
                        packet_priority_classification <= packet_priority_classification + 1;
                    end
                end
            end
        end
    end
    
    // Bypass Path Processing (Ultra-low latency)
    always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
        if (!rst_n) begin
            bypass_wr_ptr <= 2'h0;
            bypass_ready_out <= 1'b0;
        end else if (bypass_global_enable && !bypass_buffer_full) begin
            bypass_ready_out <= 1'b1;
            
            if (bypass_valid_in && bypass_ready_out) begin
                
                // Determine bypass eligibility
                logic bypass_eligible = 1'b0;
                
                // Priority-based bypass decision
                if (packet_priority_classification >= 3'h5) begin
                    bypass_eligible = 1'b1;
                end
                
                // Latency-based bypass decision
                if (ML_PREDICTION && ml_enable && 
                    ml_latency_prediction < latency_threshold_ns) begin
                    bypass_eligible = 1'b1;
                end
                
                // Utilization-based throttling
                if (current_bypass_utilization > bypass_utilization_limit) begin
                    bypass_eligible = 1'b0;
                end
                
                // Store in minimal buffer
                bypass_buffer[bypass_wr_ptr] <= '{
                    data: bypass_data_in,
                    header: bypass_header_in,
                    timestamp: global_cycle_counter,
                    predicted_latency: ml_latency_prediction,
                    priority_level: packet_priority_classification,
                    bypass_eligible: bypass_eligible,
                    ml_predicted: ML_PREDICTION && ml_enable,
                    valid: 1'b1
                };
                bypass_wr_ptr <= bypass_wr_ptr + 1;
            end
        end else begin
            bypass_ready_out <= 1'b0;
        end
    end
    
    // Normal Path Processing
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            normal_wr_ptr <= 2'h0;
            normal_ready_out <= 1'b0;
        end else if (bypass_global_enable && !normal_buffer_full) begin
            normal_ready_out <= 1'b1;
            
            if (normal_valid_in && normal_ready_out) begin
                normal_buffer[normal_wr_ptr] <= '{
                    data: normal_data_in,
                    header: normal_header_in,
                    timestamp: global_cycle_counter,
                    predicted_latency: 16'h0,  // Normal path doesn't predict
                    priority_level: 3'h0,      // Default priority
                    bypass_eligible: 1'b0,     // Normal path
                    ml_predicted: 1'b0,
                    valid: 1'b1
                };
                normal_wr_ptr <= normal_wr_ptr + 1;
            end
        end else begin
            normal_ready_out <= 1'b0;
        end
    end
    
    // Output Arbitration and Multiplexing
    always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
        if (!rst_n) begin
            bypass_rd_ptr <= 2'h0;
            normal_rd_ptr <= 2'h0;
            bypass_valid_out <= 1'b0;
            normal_valid_out <= 1'b0;
            mux_valid_out <= 1'b0;
        end else if (bypass_global_enable) begin
            
            // Bypass path has highest priority
            if (!bypass_buffer_empty && bypass_ready_in) begin
                bypass_packet_t bypass_pkt = bypass_buffer[bypass_rd_ptr];
                
                if (bypass_pkt.valid && bypass_pkt.bypass_eligible) begin
                    // Direct bypass output (zero additional latency)
                    bypass_data_out <= bypass_pkt.data;
                    bypass_header_out <= bypass_pkt.header;
                    bypass_valid_out <= 1'b1;
                    
                    // Also send to mux output
                    mux_data_out <= bypass_pkt.data;
                    mux_header_out <= bypass_pkt.header;
                    mux_valid_out <= 1'b1;
                    
                    bypass_rd_ptr <= bypass_rd_ptr + 1;
                    bypass_packet_counter <= bypass_packet_counter + 1;
                    bypass_byte_counter <= bypass_byte_counter + (DATA_WIDTH / 8);
                    
                    // Calculate latency for this packet
                    instant_bypass_latency <= global_cycle_counter - bypass_pkt.timestamp;
                    latency_accumulator_bypass <= latency_accumulator_bypass + 
                                                (global_cycle_counter - bypass_pkt.timestamp);
                end
            end
            // Normal path when bypass not active
            else if (!normal_buffer_empty && normal_ready_in) begin
                bypass_packet_t normal_pkt = normal_buffer[normal_rd_ptr];
                
                if (normal_pkt.valid) begin
                    normal_data_out <= normal_pkt.data;
                    normal_header_out <= normal_pkt.header;
                    normal_valid_out <= 1'b1;
                    
                    // Send to mux output if bypass not active
                    if (bypass_buffer_empty) begin
                        mux_data_out <= normal_pkt.data;
                        mux_header_out <= normal_pkt.header;
                        mux_valid_out <= 1'b1;
                    end
                    
                    normal_rd_ptr <= normal_rd_ptr + 1;
                    normal_packet_counter <= normal_packet_counter + 1;
                    
                    // Calculate latency for this packet  
                    instant_normal_latency <= global_cycle_counter - normal_pkt.timestamp;
                    latency_accumulator_normal <= latency_accumulator_normal + 
                                                (global_cycle_counter - normal_pkt.timestamp);
                end
            end else begin
                bypass_valid_out <= 1'b0;
                normal_valid_out <= 1'b0;
                mux_valid_out <= 1'b0;
            end
        end
    end
    
    // ML-Enhanced Bypass Optimization
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            ml_bypass_prediction_accuracy <= 8'h80;
            ml_learning_coefficient <= 8'h10;
            ml_learning_cycles <= 32'h0;
            for (int i = 0; i < 8; i++) begin
                ml_traffic_pattern_history[i] <= 16'h0;
            end
        end else if (ML_PREDICTION && ml_enable && bypass_global_enable) begin
            ml_learning_cycles <= ml_learning_cycles + 1;
            
            // Update traffic pattern history
            if (global_cycle_counter[11:0] == 12'hFFF) begin
                for (int i = 7; i > 0; i--) begin
                    ml_traffic_pattern_history[i] <= ml_traffic_pattern_history[i-1];
                end
                ml_traffic_pattern_history[0] <= bypass_packet_counter[15:0];
            end
            
            // Calculate bypass prediction accuracy
            if (bypass_valid_out && bypass_ready_in) begin
                bypass_packet_t current_pkt = bypass_buffer[bypass_rd_ptr];
                if (current_pkt.ml_predicted) begin
                    // Compare predicted vs actual latency
                    logic [15:0] latency_error = (instant_bypass_latency > current_pkt.predicted_latency) ?
                                               (instant_bypass_latency - current_pkt.predicted_latency) :
                                               (current_pkt.predicted_latency - instant_bypass_latency);
                    
                    if (latency_error < 16'd10) begin // Within 10 cycles
                        ml_bypass_prediction_accuracy <= (ml_bypass_prediction_accuracy < 8'hF0) ?
                                                       ml_bypass_prediction_accuracy + 1 : 8'hFF;
                    end else begin
                        ml_bypass_prediction_accuracy <= (ml_bypass_prediction_accuracy > 8'h10) ?
                                                       ml_bypass_prediction_accuracy - 1 : 8'h00;
                    end
                end
            end
            
            // Adaptive learning coefficient
            if (ml_bypass_prediction_accuracy > 8'hE0) begin
                ml_learning_coefficient <= 8'h05; // Slow learning when accurate
            end else if (ml_bypass_prediction_accuracy < 8'h60) begin
                ml_learning_coefficient <= 8'h20; // Fast learning when inaccurate
            end
        end
    end
    
    // Real-time Performance Analytics
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            current_bypass_utilization <= 8'h0;
            latency_improvement_ratio <= 8'h0;
        end else if (bypass_global_enable) begin
            
            // Calculate bypass utilization (updated every 256 cycles)
            if (global_cycle_counter[7:0] == 8'hFF) begin
                logic [31:0] total_packets = bypass_packet_counter + normal_packet_counter;
                if (total_packets > 0) begin
                    current_bypass_utilization <= (bypass_packet_counter * 8'd100) / total_packets[7:0];
                end
            end
            
            // Calculate latency improvement
            if (instant_normal_latency > 0 && instant_bypass_latency > 0) begin
                if (instant_normal_latency > instant_bypass_latency) begin
                    logic [15:0] improvement = instant_normal_latency - instant_bypass_latency;
                    latency_improvement_ratio <= (improvement * 8'd100) / instant_normal_latency[7:0];
                end
            end
        end
    end
    
    // Buffer Status Logic
    always_comb begin
        bypass_buffer_full = (bypass_wr_ptr + 1) == bypass_rd_ptr;
        bypass_buffer_empty = (bypass_wr_ptr == bypass_rd_ptr);
        normal_buffer_full = (normal_wr_ptr + 1) == normal_rd_ptr;
        normal_buffer_empty = (normal_wr_ptr == normal_rd_ptr);
    end
    
    // Output Assignments
    assign active_priority_level = packet_priority_classification;
    assign bypass_efficiency_score = ml_bypass_prediction_accuracy;
    assign ml_bypass_optimization = {8'h0, ml_learning_coefficient};
    
    assign measured_latency_cycles = instant_normal_latency;
    assign bypass_latency_cycles = instant_bypass_latency;
    assign latency_reduction_percent = latency_improvement_ratio;
    
    assign bypass_packets_count = bypass_packet_counter;
    assign normal_packets_count = normal_packet_counter;
    assign total_bytes_bypassed = bypass_byte_counter;
    assign bypass_utilization_percent = current_bypass_utilization;
    
    assign average_bypass_latency_ns = (bypass_packet_counter > 0) ?
                                     (latency_accumulator_bypass[15:0] / bypass_packet_counter[15:0]) : 16'h0;
    assign average_normal_latency_ns = (normal_packet_counter > 0) ?
                                     (latency_accumulator_normal[15:0] / normal_packet_counter[15:0]) : 16'h0;
    assign bypass_hit_ratio_percent = current_bypass_utilization;
    
    assign bypass_status = {
        bypass_global_enable,              // [31] Global enable
        ML_PREDICTION && ml_enable,        // [30] ML enabled
        bypass_path_congested,             // [29] Bypass congested
        normal_path_congested,             // [28] Normal congested
        packet_priority_classification,    // [27:25] Current priority
        current_bypass_utilization,        // [24:17] Utilization
        ml_bypass_prediction_accuracy[7:0] // [16:9] ML accuracy
    };
    
    assign error_count = {8'h0, ml_learning_coefficient};
    assign congestion_level = current_bypass_utilization;

endmodule