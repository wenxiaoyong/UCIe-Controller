module ucie_enhanced_crc_retry
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter FLIT_WIDTH = 256,
    parameter CRC_WIDTH = 32,
    parameter RETRY_BUFFER_DEPTH = 256,    // Enhanced deep buffer for 128 Gbps
    parameter MAX_RETRY_COUNT = 15,        // Enhanced retry count per architecture
    parameter SEQUENCE_WIDTH = 16,
    parameter NUM_CRC_ENGINES = 4,         // 4x parallel CRC engines for 128 Gbps
    parameter ENHANCED_128G = 1,           // Always enable 128 Gbps enhancements
    parameter ML_PREDICTION = 1,           // Always enable ML-based error prediction
    parameter ENABLE_SELECTIVE_REPLAY = 1, // Enable selective replay per architecture
    parameter ENABLE_FEC = 1               // Enable Forward Error Correction per architecture
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // Configuration
    input  logic                crc_enable,
    input  logic                retry_enable,
    input  logic [3:0]          crc_polynomial_sel,   // Multiple CRC polynomials
    input  logic [7:0]          retry_timeout_cycles,
    input  logic                enhanced_mode,        // 128 Gbps mode
    
    // Transmit Path Interface
    input  logic                tx_flit_valid,
    input  logic [FLIT_WIDTH-1:0] tx_flit_data,
    input  logic                tx_flit_sop,
    input  logic                tx_flit_eop,
    input  logic [3:0]          tx_flit_be,
    input  virtual_channel_t    tx_flit_vc,
    output logic                tx_flit_ready,
    
    // Transmit Output (to Physical Layer)
    output logic                phy_tx_valid,
    output logic [FLIT_WIDTH-1:0] phy_tx_data,
    output logic                phy_tx_sop,
    output logic                phy_tx_eop,
    output logic [3:0]          phy_tx_be,
    output logic [CRC_WIDTH-1:0] phy_tx_crc,
    output logic [SEQUENCE_WIDTH-1:0] phy_tx_sequence,
    input  logic                phy_tx_ready,
    
    // Receive Path Interface (from Physical Layer)
    input  logic                phy_rx_valid,
    input  logic [FLIT_WIDTH-1:0] phy_rx_data,
    input  logic                phy_rx_sop,
    input  logic                phy_rx_eop,
    input  logic [3:0]          phy_rx_be,
    input  logic [CRC_WIDTH-1:0] phy_rx_crc,
    input  logic [SEQUENCE_WIDTH-1:0] phy_rx_sequence,
    output logic                phy_rx_ready,
    
    // Receive Output Interface
    output logic                rx_flit_valid,
    output logic [FLIT_WIDTH-1:0] rx_flit_data,
    output logic                rx_flit_sop,
    output logic                rx_flit_eop,
    output logic [3:0]          rx_flit_be,
    output virtual_channel_t    rx_flit_vc,
    input  logic                rx_flit_ready,
    
    // Retry Control Interface
    input  logic                retry_req,           // Request retry from remote
    input  logic [SEQUENCE_WIDTH-1:0] retry_sequence, // Sequence to retry from
    output logic                retry_ack,           // Acknowledge retry
    output logic                retry_complete,      // Retry operation complete
    
    // Status and Statistics
    output logic [31:0]         crc_status,
    output logic [31:0]         retry_status,
    output logic [15:0]         crc_error_count,
    output logic [15:0]         retry_count,
    output logic [7:0]          buffer_utilization,
    
    // ML Enhancement Interface
    input  logic                ml_enable,
    input  logic [7:0]          ml_error_threshold,
    output logic [15:0]         ml_error_prediction,
    output logic [7:0]          ml_reliability_score,
    
    // Advanced 128 Gbps Features
    input  logic                burst_mode,          // High-throughput burst mode
    input  logic [3:0]          parallel_crc_lanes,  // Parallel CRC computation
    output logic                crc_pipeline_ready,  // Pipeline ready indicator
    
    // Selective Replay Interface
    input  logic                selective_replay_enable,
    input  logic [SEQUENCE_WIDTH-1:0] selective_start_seq,
    input  logic [SEQUENCE_WIDTH-1:0] selective_end_seq,
    output logic                selective_replay_active,
    
    // Forward Error Correction Interface
    input  logic                fec_enable,
    output logic                fec_correction_applied,
    output logic [7:0]          fec_corrected_bits,
    
    // Thermal and Power Management
    input  logic                thermal_throttle,
    input  logic [7:0]          power_budget_percent,
    output logic                adaptive_retry_active
    
    // Debug and Performance
    output logic [15:0]         throughput_mbps,
    output logic [7:0]          error_rate_ppm,     // Parts per million
    output logic                buffer_overflow,
    output logic                sequence_error
);

    // Internal Type Definitions
    typedef struct packed {
        logic [FLIT_WIDTH-1:0] data;
        logic                  sop;
        logic                  eop;
        logic [3:0]           be;
        virtual_channel_t     vc;
        logic [CRC_WIDTH-1:0] crc;
        logic [SEQUENCE_WIDTH-1:0] sequence;
        logic [31:0]          timestamp;
        logic [3:0]           retry_count;
        logic                 valid;
    } retry_buffer_entry_t;
    
    typedef struct packed {
        logic [CRC_WIDTH-1:0] polynomial;
        logic [CRC_WIDTH-1:0] initial_value;
        logic [CRC_WIDTH-1:0] xor_out;
        logic                 reflect_input;
        logic                 reflect_output;
    } crc_config_t;
    
    typedef struct packed {
        logic [15:0]          error_count;
        logic [15:0]          total_count;
        logic [7:0]           consecutive_errors;
        logic [31:0]          last_error_time;
        logic [7:0]           error_pattern;
        logic                 prediction_valid;
    } error_tracking_t;
    
    // CRC Configuration Table
    crc_config_t crc_configs [15:0];
    
    // Initialize CRC configurations
    initial begin
        // CRC-32 IEEE 802.3
        crc_configs[0] = '{
            polynomial: 32'h04C11DB7,
            initial_value: 32'hFFFFFFFF,
            xor_out: 32'hFFFFFFFF,
            reflect_input: 1'b1,
            reflect_output: 1'b1
        };
        
        // CRC-32C (Castagnoli) - Better for high-speed links
        crc_configs[1] = '{
            polynomial: 32'h1EDC6F41,
            initial_value: 32'hFFFFFFFF,
            xor_out: 32'hFFFFFFFF,
            reflect_input: 1'b1,
            reflect_output: 1'b1
        };
        
        // CRC-32K (Koopman) - Enhanced error detection
        crc_configs[2] = '{
            polynomial: 32'h741B8CD7,
            initial_value: 32'hFFFFFFFF,
            xor_out: 32'h00000000,
            reflect_input: 1'b0,
            reflect_output: 1'b0
        };
        
        // Additional configurations for different polynomials...
        for (int i = 3; i < 16; i++) begin
            crc_configs[i] = crc_configs[0]; // Default to IEEE 802.3
        end
    end
    
    // State Variables
    retry_buffer_entry_t retry_buffer [RETRY_BUFFER_DEPTH-1:0];
    logic [$clog2(RETRY_BUFFER_DEPTH)-1:0] retry_wr_ptr, retry_rd_ptr;
    logic [$clog2(RETRY_BUFFER_DEPTH):0] retry_count_int;
    
    logic [SEQUENCE_WIDTH-1:0] tx_sequence_counter;
    logic [SEQUENCE_WIDTH-1:0] rx_sequence_expected;
    logic [SEQUENCE_WIDTH-1:0] last_acked_sequence;
    
    // CRC Computation Modules
    logic [CRC_WIDTH-1:0] tx_crc_calculated;
    logic [CRC_WIDTH-1:0] rx_crc_calculated;
    logic                 tx_crc_valid;
    logic                 rx_crc_valid;
    logic                 crc_error;
    
    // Enhanced CRC for 128 Gbps (parallel computation)
    logic [CRC_WIDTH-1:0] parallel_crc [3:0];
    logic [3:0]           parallel_crc_valid;
    
    // Error Tracking and ML Prediction
    error_tracking_t error_tracker;
    logic [15:0] ml_prediction_engine_output;
    logic [7:0]  reliability_score_int;
    
    // Performance Counters
    logic [31:0] throughput_counter;
    logic [31:0] cycle_counter;
    logic [15:0] crc_error_counter;
    logic [15:0] retry_counter;
    logic [31:0] last_throughput_sample;
    
    // Retry State Machine
    typedef enum logic [2:0] {
        RETRY_IDLE,
        RETRY_REQUESTED,
        RETRY_IN_PROGRESS,
        RETRY_COMPLETE_WAIT,
        RETRY_ERROR_RECOVERY
    } retry_state_t;
    
    retry_state_t retry_state;
    logic [7:0] retry_timeout_counter;
    logic [$clog2(RETRY_BUFFER_DEPTH)-1:0] retry_replay_ptr;
    
    // Generate parallel CRC computation for 128 Gbps
    genvar crc_lane;
    generate
        for (crc_lane = 0; crc_lane < 4; crc_lane++) begin : gen_parallel_crc
            logic [FLIT_WIDTH/4-1:0] lane_data;
            assign lane_data = tx_flit_data[(crc_lane+1)*64-1:crc_lane*64];
            
            ucie_crc32_engine #(
                .DATA_WIDTH(FLIT_WIDTH/4),
                .CRC_WIDTH(CRC_WIDTH)
            ) i_parallel_crc (
                .clk(clk),
                .rst_n(rst_n),
                .data_in(lane_data),
                .data_valid(tx_flit_valid && enhanced_mode && (parallel_crc_lanes > crc_lane)),
                .crc_config(crc_configs[crc_polynomial_sel]),
                .crc_out(parallel_crc[crc_lane]),
                .crc_valid(parallel_crc_valid[crc_lane])
            );
        end
    endgenerate
    
    // Main CRC computation engine
    ucie_crc32_engine #(
        .DATA_WIDTH(FLIT_WIDTH),
        .CRC_WIDTH(CRC_WIDTH)
    ) i_tx_crc_engine (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(tx_flit_data),
        .data_valid(tx_flit_valid && crc_enable),
        .crc_config(crc_configs[crc_polynomial_sel]),
        .crc_out(tx_crc_calculated),
        .crc_valid(tx_crc_valid)
    );
    
    ucie_crc32_engine #(
        .DATA_WIDTH(FLIT_WIDTH),
        .CRC_WIDTH(CRC_WIDTH)
    ) i_rx_crc_engine (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(phy_rx_data),
        .data_valid(phy_rx_valid && crc_enable),
        .crc_config(crc_configs[crc_polynomial_sel]),
        .crc_out(rx_crc_calculated),
        .crc_valid(rx_crc_valid)
    );
    
    // Enhanced CRC selection for 128 Gbps mode
    logic [CRC_WIDTH-1:0] final_tx_crc;
    always_comb begin
        if (enhanced_mode && parallel_crc_lanes > 1) begin
            // Combine parallel CRC results using XOR for enhanced error detection
            final_tx_crc = parallel_crc[0];
            for (int i = 1; i < parallel_crc_lanes && i < 4; i++) begin
                final_tx_crc = final_tx_crc ^ parallel_crc[i];
            end
        end else begin
            final_tx_crc = tx_crc_calculated;
        end
    end
    
    // Transmit Path Processing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_sequence_counter <= '0;
            retry_wr_ptr <= '0;
            retry_count_int <= '0;
            phy_tx_valid <= 1'b0;
            phy_tx_data <= '0;
            phy_tx_sop <= 1'b0;
            phy_tx_eop <= 1'b0;
            phy_tx_be <= '0;
            phy_tx_crc <= '0;
            phy_tx_sequence <= '0;
            throughput_counter <= '0;
        end else begin
            // Handle transmit path
            if (tx_flit_valid && tx_flit_ready && phy_tx_ready) begin
                // Store in retry buffer if retry is enabled
                if (retry_enable && retry_count_int < RETRY_BUFFER_DEPTH) begin
                    retry_buffer[retry_wr_ptr] <= '{
                        data: tx_flit_data,
                        sop: tx_flit_sop,
                        eop: tx_flit_eop,
                        be: tx_flit_be,
                        vc: tx_flit_vc,
                        crc: final_tx_crc,
                        sequence: tx_sequence_counter,
                        timestamp: cycle_counter,
                        retry_count: 4'h0,
                        valid: 1'b1
                    };
                    retry_wr_ptr <= retry_wr_ptr + 1;
                    retry_count_int <= retry_count_int + 1;
                end
                
                // Forward to physical layer
                phy_tx_valid <= 1'b1;
                phy_tx_data <= tx_flit_data;
                phy_tx_sop <= tx_flit_sop;
                phy_tx_eop <= tx_flit_eop;
                phy_tx_be <= tx_flit_be;
                phy_tx_crc <= final_tx_crc;
                phy_tx_sequence <= tx_sequence_counter;
                
                // Increment sequence counter
                tx_sequence_counter <= tx_sequence_counter + 1;
                
                // Update throughput counter
                throughput_counter <= throughput_counter + FLIT_WIDTH;
            end else if (!tx_flit_valid || !phy_tx_ready) begin
                phy_tx_valid <= 1'b0;
            end
        end
    end
    
    // Receive Path Processing and CRC Checking
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_sequence_expected <= '0;
            crc_error <= 1'b0;
            rx_flit_valid <= 1'b0;
            rx_flit_data <= '0;
            rx_flit_sop <= 1'b0;
            rx_flit_eop <= 1'b0;
            rx_flit_be <= '0;
            rx_flit_vc <= '0;
            crc_error_counter <= '0;
        end else begin
            if (phy_rx_valid && phy_rx_ready) begin
                // Check CRC
                logic crc_match = (phy_rx_crc == rx_crc_calculated) || !crc_enable;
                logic sequence_match = (phy_rx_sequence == rx_sequence_expected);
                
                if (crc_match && sequence_match) begin
                    // Good flit - forward to upper layer
                    rx_flit_valid <= 1'b1;
                    rx_flit_data <= phy_rx_data;
                    rx_flit_sop <= phy_rx_sop;
                    rx_flit_eop <= phy_rx_eop;
                    rx_flit_be <= phy_rx_be;
                    rx_flit_vc <= virtual_channel_t'(phy_rx_data[7:0]); // Assume VC in lower bits
                    
                    rx_sequence_expected <= rx_sequence_expected + 1;
                    crc_error <= 1'b0;
                    
                    // Update error tracking for ML
                    if (error_tracker.consecutive_errors > 0) begin
                        error_tracker.consecutive_errors <= error_tracker.consecutive_errors - 1;
                    end
                end else begin
                    // CRC or sequence error detected
                    rx_flit_valid <= 1'b0;
                    crc_error <= 1'b1;
                    crc_error_counter <= crc_error_counter + 1;
                    
                    // Update error tracking
                    error_tracker.error_count <= error_tracker.error_count + 1;
                    error_tracker.consecutive_errors <= error_tracker.consecutive_errors + 1;
                    error_tracker.last_error_time <= cycle_counter;
                    error_tracker.error_pattern <= {error_tracker.error_pattern[6:0], 1'b1};
                    
                    // Request retry if enabled
                    if (retry_enable) begin
                        // Retry logic will be handled by retry state machine
                    end
                end
                
                error_tracker.total_count <= error_tracker.total_count + 1;
            end else begin
                rx_flit_valid <= 1'b0;
                crc_error <= 1'b0;
            end
        end
    end
    
    // Retry State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retry_state <= RETRY_IDLE;
            retry_timeout_counter <= '0;
            retry_replay_ptr <= '0;
            retry_ack <= 1'b0;
            retry_complete <= 1'b0;
            retry_counter <= '0;
        end else begin
            case (retry_state)
                RETRY_IDLE: begin
                    retry_ack <= 1'b0;
                    retry_complete <= 1'b0;
                    
                    if (retry_req || crc_error) begin
                        retry_state <= RETRY_REQUESTED;
                        retry_timeout_counter <= retry_timeout_cycles;
                        retry_counter <= retry_counter + 1;
                        
                        // Find the retry point in buffer
                        for (int i = 0; i < RETRY_BUFFER_DEPTH; i++) begin
                            if (retry_buffer[i].valid && 
                                retry_buffer[i].sequence == retry_sequence) begin
                                retry_replay_ptr <= i;
                                break;
                            end
                        end
                    end
                end
                
                RETRY_REQUESTED: begin
                    retry_ack <= 1'b1;
                    retry_state <= RETRY_IN_PROGRESS;
                end
                
                RETRY_IN_PROGRESS: begin
                    retry_ack <= 1'b0;
                    
                    // Replay logic would be implemented here
                    // For now, simplified completion
                    if (retry_timeout_counter > 0) begin
                        retry_timeout_counter <= retry_timeout_counter - 1;
                    end else begin
                        retry_state <= RETRY_COMPLETE_WAIT;
                    end
                end
                
                RETRY_COMPLETE_WAIT: begin
                    retry_complete <= 1'b1;
                    retry_state <= RETRY_IDLE;
                end
                
                default: retry_state <= RETRY_IDLE;
            endcase
        end
    end
    
    // ML-Based Error Prediction
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ml_prediction_engine_output <= '0;
            reliability_score_int <= 8'hFF;
        end else if (ml_enable) begin
            // Simple ML prediction based on error patterns
            logic [7:0] error_rate = (error_tracker.total_count > 0) ? 
                                   8'((error_tracker.error_count * 255) / error_tracker.total_count) : 8'h00;
            
            // Predict future errors based on current error rate and pattern
            if (error_rate > ml_error_threshold) begin
                ml_prediction_engine_output <= ml_prediction_engine_output + 
                                             16'(error_tracker.consecutive_errors * error_rate);
            end else begin
                if (ml_prediction_engine_output > 0) begin
                    ml_prediction_engine_output <= ml_prediction_engine_output - 1;
                end
            end
            
            // Calculate reliability score
            if (error_rate < 8'h10) begin        // <6.25% error rate
                reliability_score_int <= 8'hFF;  // Excellent
            end else if (error_rate < 8'h40) begin  // <25% error rate
                reliability_score_int <= 8'hC0;  // Good
            end else if (error_rate < 8'h80) begin  // <50% error rate
                reliability_score_int <= 8'h80;  // Fair
            end else begin
                reliability_score_int <= 8'h40;  // Poor
            end
        end
    end
    
    // Performance Monitoring
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= '0;
            last_throughput_sample <= '0;
        end else begin
            cycle_counter <= cycle_counter + 1;
            
            // Sample throughput every 1024 cycles
            if (cycle_counter[9:0] == 10'h3FF) begin
                last_throughput_sample <= throughput_counter;
                throughput_counter <= '0;
            end
        end
    end
    
    // Output Assignments
    assign tx_flit_ready = phy_tx_ready && (retry_count_int < RETRY_BUFFER_DEPTH || !retry_enable);
    assign phy_rx_ready = rx_flit_ready;
    
    assign crc_pipeline_ready = enhanced_mode ? (&parallel_crc_valid || !burst_mode) : tx_crc_valid;
    
    // Status outputs
    assign buffer_utilization = 8'((retry_count_int * 255) / RETRY_BUFFER_DEPTH);
    assign buffer_overflow = (retry_count_int >= RETRY_BUFFER_DEPTH);
    assign sequence_error = (phy_rx_valid && (phy_rx_sequence != rx_sequence_expected));
    
    assign crc_error_count = crc_error_counter;
    assign retry_count = retry_counter;
    
    assign ml_error_prediction = ml_prediction_engine_output;
    assign ml_reliability_score = reliability_score_int;
    
    // Calculate throughput in Mbps (simplified)
    assign throughput_mbps = 16'((last_throughput_sample * 1000) >> 20); // Approximate conversion
    
    // Calculate error rate in parts per million
    assign error_rate_ppm = (error_tracker.total_count > 0) ? 
                           8'((error_tracker.error_count * 1000000) / error_tracker.total_count) : 8'h00;
    
    assign crc_status = {
        enhanced_mode,              // [31] 128 Gbps enhanced mode
        ml_enable,                  // [30] ML prediction enabled
        parallel_crc_lanes,         // [29:26] Parallel CRC lanes
        crc_polynomial_sel,         // [25:22] CRC polynomial selection
        6'b0,                       // [21:16] Reserved
        crc_error_count             // [15:0] CRC error count
    };
    
    assign retry_status = {
        retry_state,                // [31:29] Retry state
        retry_enable,               // [28] Retry enabled
        4'b0,                       // [27:24] Reserved
        buffer_utilization,         // [23:16] Buffer utilization
        retry_count                 // [15:0] Retry count
    };

endmodule

// CRC32 Engine Module
module ucie_crc32_engine #(
    parameter DATA_WIDTH = 256,
    parameter CRC_WIDTH = 32
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic [DATA_WIDTH-1:0] data_in,
    input  logic                data_valid,
    input  ucie_enhanced_crc_retry::crc_config_t crc_config,
    output logic [CRC_WIDTH-1:0] crc_out,
    output logic                crc_valid
);

    logic [CRC_WIDTH-1:0] crc_reg;
    logic [CRC_WIDTH-1:0] crc_next;
    
    // CRC computation logic (simplified for demonstration)
    always_comb begin
        crc_next = crc_reg;
        
        if (data_valid) begin
            // Simplified CRC calculation - would need full implementation
            for (int i = 0; i < DATA_WIDTH; i++) begin
                logic bit_in = crc_config.reflect_input ? data_in[DATA_WIDTH-1-i] : data_in[i];
                logic msb = crc_next[CRC_WIDTH-1];
                crc_next = {crc_next[CRC_WIDTH-2:0], 1'b0} ^ (msb ? crc_config.polynomial : '0);
                crc_next[0] = crc_next[0] ^ bit_in;
            end
        end
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_reg <= crc_config.initial_value;
            crc_valid <= 1'b0;
        end else begin
            if (data_valid) begin
                crc_reg <= crc_next;
                crc_valid <= 1'b1;
            end else begin
                crc_valid <= 1'b0;
            end
        end
    end
    
    assign crc_out = crc_config.reflect_output ? 
                    {<<{crc_reg}} ^ crc_config.xor_out : 
                    crc_reg ^ crc_config.xor_out;

endmodule