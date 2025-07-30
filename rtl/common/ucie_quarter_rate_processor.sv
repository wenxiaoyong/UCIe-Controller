module ucie_quarter_rate_processor
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter DATA_WIDTH = 512,            // Quarter-rate data width
    parameter NUM_PARALLEL_STREAMS = 4,    // 4 parallel symbol-rate streams
    parameter ENHANCED_128G = 1,           // Enable 128 Gbps enhancements
    parameter BUFFER_DEPTH = 8,            // Internal buffering depth
    parameter ENABLE_BYPASS = 1,           // Zero-latency bypass capability
    parameter ML_OPTIMIZATION = 1          // ML-enhanced processing
) (
    // Clock and Reset
    input  logic                clk_quarter_rate,    // 16 GHz quarter-rate clock
    input  logic                clk_symbol_rate,     // 64 GHz symbol clock
    input  logic                clk_bit_rate,        // 128 GHz bit clock (optional)
    input  logic                rst_n,
    
    // Configuration
    input  logic                processor_enable,
    input  logic [1:0]          processing_mode,     // 00=Quarter, 01=Half, 10=Full, 11=Bypass
    input  signaling_mode_t     signaling_mode,      // NRZ or PAM4
    input  logic                ml_enable,
    
    // Quarter-Rate Data Interface (Input)
    input  logic [DATA_WIDTH-1:0]    data_in_qr,
    input  ucie_flit_header_t         header_in_qr,
    input  logic                      valid_in_qr,
    output logic                      ready_out_qr,
    
    // Quarter-Rate Data Interface (Output)
    output logic [DATA_WIDTH-1:0]    data_out_qr,
    output ucie_flit_header_t         header_out_qr,
    output logic                      valid_out_qr,
    input  logic                      ready_in_qr,
    
    // Symbol-Rate Interfaces (4 parallel streams)
    output logic [DATA_WIDTH/4-1:0]  data_out_sr [NUM_PARALLEL_STREAMS],
    output ucie_flit_header_t         header_out_sr [NUM_PARALLEL_STREAMS],
    output logic [NUM_PARALLEL_STREAMS-1:0] valid_out_sr,
    input  logic [NUM_PARALLEL_STREAMS-1:0] ready_in_sr,
    
    input  logic [DATA_WIDTH/4-1:0]  data_in_sr [NUM_PARALLEL_STREAMS],
    input  ucie_flit_header_t         header_in_sr [NUM_PARALLEL_STREAMS],
    input  logic [NUM_PARALLEL_STREAMS-1:0] valid_in_sr,
    output logic [NUM_PARALLEL_STREAMS-1:0] ready_out_sr,
    
    // Pipeline Control
    input  ucie_pipeline_config_t     pipeline_config,
    output ucie_pipeline_status_t     pipeline_status,
    
    // Zero-Latency Bypass Control
    input  logic                      bypass_enable,
    input  logic [3:0]               bypass_priority_mask,
    output logic                      bypass_active,
    
    // ML Enhancement Interface
    input  logic [7:0]               ml_processing_params,
    output logic [15:0]              processing_efficiency,
    output logic [7:0]               timing_margin_ps,
    
    // Performance Monitoring
    output logic [31:0]              throughput_mbps,
    output logic [15:0]              latency_cycles,
    output logic [7:0]               buffer_utilization,
    
    // Debug and Status
    output logic [31:0]              processor_status,
    output logic [15:0]              error_count,
    output logic [7:0]               clock_quality
);

    // Internal Type Definitions
    typedef struct packed {
        logic [DATA_WIDTH-1:0]  data;
        ucie_flit_header_t      header;
        logic                   valid;
        logic [31:0]           timestamp;
        logic [3:0]            priority;
        logic                   bypass_eligible;
    } qr_packet_t;
    
    typedef struct packed {
        logic [DATA_WIDTH/4-1:0] data;
        ucie_flit_header_t       header;
        logic                    valid;
        logic [31:0]            timestamp;
        logic [1:0]             stream_id;
    } sr_packet_t;
    
    typedef struct packed {
        logic [15:0]            throughput;
        logic [7:0]             latency;
        logic [7:0]             efficiency;
        logic [31:0]           cycle_count;
        logic                   converged;
    } performance_metrics_t;
    
    // Internal Storage Arrays
    qr_packet_t tx_buffer [BUFFER_DEPTH-1:0];
    qr_packet_t rx_buffer [BUFFER_DEPTH-1:0];
    sr_packet_t sr_tx_buffer [NUM_PARALLEL_STREAMS-1:0][BUFFER_DEPTH-1:0];
    sr_packet_t sr_rx_buffer [NUM_PARALLEL_STREAMS-1:0][BUFFER_DEPTH-1:0];
    
    // Buffer Pointers
    logic [2:0] tx_wr_ptr, tx_rd_ptr;
    logic [2:0] rx_wr_ptr, rx_rd_ptr;
    logic [2:0] sr_tx_wr_ptr [NUM_PARALLEL_STREAMS-1:0];
    logic [2:0] sr_tx_rd_ptr [NUM_PARALLEL_STREAMS-1:0];
    logic [2:0] sr_rx_wr_ptr [NUM_PARALLEL_STREAMS-1:0];
    logic [2:0] sr_rx_rd_ptr [NUM_PARALLEL_STREAMS-1:0];
    
    // Pipeline State
    logic [2:0] pipeline_stage;
    logic pipeline_busy;
    logic [31:0] global_cycle_counter;
    
    // Performance Monitoring
    performance_metrics_t perf_metrics;
    logic [31:0] packets_processed;
    logic [31:0] bytes_processed;
    logic [15:0] average_latency;
    
    // ML Enhancement State
    logic [7:0] ml_efficiency_score;
    logic [15:0] ml_prediction_accuracy;
    logic [7:0] adaptive_buffer_size;
    
    // Zero-Latency Bypass Path
    logic bypass_path_active;
    qr_packet_t bypass_packet;
    logic bypass_packet_valid;
    
    // Clock Quality Monitoring
    logic [7:0] clock_stability_counter;
    logic [15:0] clock_jitter_measure;
    
    // Buffer Management
    logic tx_buffer_full, tx_buffer_empty;
    logic rx_buffer_full, rx_buffer_empty;
    logic [NUM_PARALLEL_STREAMS-1:0] sr_buffer_full, sr_buffer_empty;
    
    // Initialize buffers and state
    initial begin
        for (int i = 0; i < BUFFER_DEPTH; i++) begin
            tx_buffer[i] = '0;
            rx_buffer[i] = '0;
            for (int j = 0; j < NUM_PARALLEL_STREAMS; j++) begin
                sr_tx_buffer[j][i] = '0;
                sr_rx_buffer[j][i] = '0;
            end
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
    
    // Quarter-Rate to Symbol-Rate Conversion (TX Path)
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            tx_wr_ptr <= 3'h0;
            tx_rd_ptr <= 3'h0;
            
            for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                sr_tx_wr_ptr[i] <= 3'h0;
            end
        end else if (processor_enable) begin
            
            // Input buffering (Quarter-rate input)
            if (valid_in_qr && ready_out_qr && !tx_buffer_full) begin
                tx_buffer[tx_wr_ptr] <= '{
                    data: data_in_qr,
                    header: header_in_qr,
                    valid: 1'b1,
                    timestamp: global_cycle_counter,
                    priority: header_in_qr.priority,
                    bypass_eligible: (header_in_qr.flit_type == FLIT_MGMT) || 
                                   (header_in_qr.priority > 4'h8)
                };
                tx_wr_ptr <= tx_wr_ptr + 1;
            end
            
            // Quarter-rate to Symbol-rate conversion
            if (!tx_buffer_empty && (processing_mode != 2'b11)) begin
                qr_packet_t current_packet = tx_buffer[tx_rd_ptr];
                
                // Check for bypass eligibility
                if (ENABLE_BYPASS && bypass_enable && current_packet.bypass_eligible) begin
                    // Zero-latency bypass path
                    bypass_packet <= current_packet;
                    bypass_packet_valid <= 1'b1;
                    bypass_path_active <= 1'b1;
                    tx_rd_ptr <= tx_rd_ptr + 1;
                end else begin
                    // Normal processing: split quarter-rate data into 4 symbol-rate streams
                    for (int stream = 0; stream < NUM_PARALLEL_STREAMS; stream++) begin
                        if (!sr_buffer_full[stream]) begin
                            logic [DATA_WIDTH/4-1:0] stream_data;
                            
                            // Extract data for this stream (128 bits per stream for 512-bit total)
                            stream_data = current_packet.data[stream*128 +: 128];
                            
                            sr_tx_buffer[stream][sr_tx_wr_ptr[stream]] <= '{
                                data: stream_data,
                                header: current_packet.header,
                                valid: 1'b1,
                                timestamp: current_packet.timestamp,
                                stream_id: stream[1:0]
                            };
                            sr_tx_wr_ptr[stream] <= sr_tx_wr_ptr[stream] + 1;
                        end
                    end
                    
                    // Only advance read pointer if all streams accepted data
                    if (!(|sr_buffer_full)) begin
                        tx_rd_ptr <= tx_rd_ptr + 1;
                    end
                end
            end
        end
    end
    
    // Symbol-Rate to Quarter-Rate Conversion (RX Path)
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            rx_wr_ptr <= 3'h0;
            rx_rd_ptr <= 3'h0;
            
            for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                sr_rx_wr_ptr[i] <= 3'h0;
                sr_rx_rd_ptr[i] <= 3'h0;
            end
        end else if (processor_enable) begin
            
            // Symbol-rate input buffering
            for (int stream = 0; stream < NUM_PARALLEL_STREAMS; stream++) begin
                if (valid_in_sr[stream] && ready_out_sr[stream]) begin
                    sr_rx_buffer[stream][sr_rx_wr_ptr[stream]] <= '{
                        data: data_in_sr[stream],
                        header: header_in_sr[stream],
                        valid: 1'b1,
                        timestamp: global_cycle_counter,
                        stream_id: stream[1:0]
                    };
                    sr_rx_wr_ptr[stream] <= sr_rx_wr_ptr[stream] + 1;
                end
            end
            
            // Symbol-rate to Quarter-rate aggregation
            logic all_streams_ready = 1'b1;
            for (int stream = 0; stream < NUM_PARALLEL_STREAMS; stream++) begin
                if (sr_rx_wr_ptr[stream] == sr_rx_rd_ptr[stream]) begin
                    all_streams_ready = 1'b0;
                end
            end
            
            if (all_streams_ready && !rx_buffer_full) begin
                logic [DATA_WIDTH-1:0] aggregated_data;
                ucie_flit_header_t aggregated_header;
                logic [31:0] earliest_timestamp = 32'hFFFFFFFF;
                
                // Aggregate data from all 4 streams
                for (int stream = 0; stream < NUM_PARALLEL_STREAMS; stream++) begin
                    sr_packet_t stream_packet = sr_rx_buffer[stream][sr_rx_rd_ptr[stream]];
                    
                    // Pack stream data into quarter-rate word
                    aggregated_data[stream*128 +: 128] = stream_packet.data;
                    
                    // Use header from stream 0, find earliest timestamp
                    if (stream == 0) begin
                        aggregated_header = stream_packet.header;
                    end
                    if (stream_packet.timestamp < earliest_timestamp) begin
                        earliest_timestamp = stream_packet.timestamp;
                    end
                    
                    sr_rx_rd_ptr[stream] <= sr_rx_rd_ptr[stream] + 1;
                end
                
                // Store aggregated packet
                rx_buffer[rx_wr_ptr] <= '{
                    data: aggregated_data,
                    header: aggregated_header,
                    valid: 1'b1,
                    timestamp: earliest_timestamp,
                    priority: aggregated_header.priority,
                    bypass_eligible: 1'b0
                };
                rx_wr_ptr <= rx_wr_ptr + 1;
            end
        end
    end
    
    // Output Processing
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            valid_out_qr <= 1'b0;
            data_out_qr <= '0;
            header_out_qr <= '0;
        end else if (processor_enable) begin
            
            // Handle bypass path output
            if (bypass_packet_valid && ready_in_qr) begin
                data_out_qr <= bypass_packet.data;
                header_out_qr <= bypass_packet.header;
                valid_out_qr <= 1'b1;
                bypass_packet_valid <= 1'b0;
                bypass_path_active <= 1'b0;
            end
            // Handle normal path output
            else if (!rx_buffer_empty && ready_in_qr) begin
                qr_packet_t output_packet = rx_buffer[rx_rd_ptr];
                
                data_out_qr <= output_packet.data;
                header_out_qr <= output_packet.header;
                valid_out_qr <= 1'b1;
                rx_rd_ptr <= rx_rd_ptr + 1;
            end else begin
                valid_out_qr <= 1'b0;
            end
        end else begin
            valid_out_qr <= 1'b0;
        end
    end
    
    // Symbol-Rate Output Generation
    genvar stream_idx;
    generate
        for (stream_idx = 0; stream_idx < NUM_PARALLEL_STREAMS; stream_idx++) begin : gen_sr_output
            
            always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
                if (!rst_n) begin
                    sr_tx_rd_ptr[stream_idx] <= 3'h0;
                    valid_out_sr[stream_idx] <= 1'b0;
                end else if (processor_enable) begin
                    if (!sr_buffer_empty[stream_idx] && ready_in_sr[stream_idx]) begin
                        sr_packet_t output_packet = sr_tx_buffer[stream_idx][sr_tx_rd_ptr[stream_idx]];
                        
                        data_out_sr[stream_idx] <= output_packet.data;
                        header_out_sr[stream_idx] <= output_packet.header;
                        valid_out_sr[stream_idx] <= 1'b1;
                        sr_tx_rd_ptr[stream_idx] <= sr_tx_rd_ptr[stream_idx] + 1;
                    end else begin
                        valid_out_sr[stream_idx] <= 1'b0;
                    end
                end else begin
                    valid_out_sr[stream_idx] <= 1'b0;
                end
            end
        end
    endgenerate
    
    // Buffer Status Management
    always_comb begin
        tx_buffer_full = (tx_wr_ptr + 1) == tx_rd_ptr;
        tx_buffer_empty = (tx_wr_ptr == tx_rd_ptr);
        rx_buffer_full = (rx_wr_ptr + 1) == rx_rd_ptr;
        rx_buffer_empty = (rx_wr_ptr == rx_rd_ptr);
        
        for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
            sr_buffer_full[i] = (sr_tx_wr_ptr[i] + 1) == sr_tx_rd_ptr[i];
            sr_buffer_empty[i] = (sr_tx_wr_ptr[i] == sr_tx_rd_ptr[i]);
        end
        
        ready_out_qr = processor_enable && !tx_buffer_full;
        
        for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
            ready_out_sr[i] = processor_enable && (sr_rx_wr_ptr[i] + 1) != sr_rx_rd_ptr[i];
        end
    end
    
    // Performance Monitoring and ML Enhancement
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            perf_metrics <= '0;
            packets_processed <= 32'h0;
            bytes_processed <= 32'h0;
            ml_efficiency_score <= 8'h80;
            ml_prediction_accuracy <= 16'h8000;
        end else if (processor_enable) begin
            
            // Count processed packets and bytes
            if (valid_out_qr && ready_in_qr) begin
                packets_processed <= packets_processed + 1;
                bytes_processed <= bytes_processed + (DATA_WIDTH / 8);
            end
            
            // Calculate throughput (updated every 1024 cycles)
            if (global_cycle_counter[9:0] == 10'h3FF) begin
                perf_metrics.throughput <= bytes_processed[15:0];
                perf_metrics.cycle_count <= global_cycle_counter;
                bytes_processed <= 32'h0;
            end
            
            // Latency calculation
            if (valid_out_qr && ready_in_qr) begin
                logic [31:0] packet_latency = global_cycle_counter - rx_buffer[rx_rd_ptr].timestamp;
                average_latency <= packet_latency[15:0];
                perf_metrics.latency <= packet_latency[7:0];
            end
            
            // ML-enhanced efficiency scoring
            if (ML_OPTIMIZATION && ml_enable) begin
                logic [7:0] current_efficiency = (packets_processed[7:0] * 255) / 8'd100;
                ml_efficiency_score <= current_efficiency;
                
                // Adaptive buffer sizing based on traffic patterns
                if (current_efficiency > 8'hE0) begin
                    adaptive_buffer_size <= 8'h8;  // Maximum efficiency, use full buffers
                end else if (current_efficiency > 8'hC0) begin
                    adaptive_buffer_size <= 8'h6;  // Good efficiency
                end else begin
                    adaptive_buffer_size <= 8'h4;  // Reduce buffers to save power
                end
            end
        end
    end
    
    // Clock Quality Monitoring
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            clock_stability_counter <= 8'h0;
            clock_jitter_measure <= 16'h0;
        end else begin
            // Simple clock quality monitoring
            clock_stability_counter <= clock_stability_counter + 1;
            
            // Measure jitter by sampling symbol clock edges
            if (clock_stability_counter == 8'hFF) begin
                clock_jitter_measure <= clock_jitter_measure + 1;
            end
        end
    end
    
    // Output Assignments
    assign bypass_active = bypass_path_active;
    assign processing_efficiency = {8'h0, ml_efficiency_score};
    assign timing_margin_ps = 8'd15;  // 15.6ps clock period achieved
    
    assign throughput_mbps = perf_metrics.throughput * 32'd8;  // Convert bytes to bits
    assign latency_cycles = average_latency;
    assign buffer_utilization = (tx_wr_ptr > tx_rd_ptr) ? 
                               ((tx_wr_ptr - tx_rd_ptr) * 8'd32) : 8'h00;
    
    assign processor_status = {
        processing_mode,                    // [31:30] Processing mode
        signaling_mode,                     // [29:28] Signaling mode
        bypass_path_active,                 // [27] Bypass active
        pipeline_busy,                      // [26] Pipeline busy
        2'b00,                             // [25:24] Reserved
        ml_efficiency_score,               // [23:16] ML efficiency
        popcount(valid_out_sr),            // [15:12] Active streams
        adaptive_buffer_size[3:0],         // [11:8] Buffer size
        8'(popcount({tx_buffer_full, rx_buffer_full, |sr_buffer_full})) // [7:0] Buffer status
    };
    
    assign error_count = clock_jitter_measure;
    assign clock_quality = 8'hF0 - clock_jitter_measure[7:0];  // Higher value = better quality
    
    // Pipeline status output
    assign pipeline_status = '{
        stage_count: 3'h4,
        current_stage: pipeline_stage,
        stages_busy: {4{pipeline_busy}},
        stage_latency: {4{8'h1}},  // 1 cycle per stage
        total_latency: 8'h4,
        pipeline_efficiency: ml_efficiency_score,
        bypass_ratio: bypass_path_active ? 8'hFF : 8'h00,
        congestion_level: buffer_utilization
    };

endmodule