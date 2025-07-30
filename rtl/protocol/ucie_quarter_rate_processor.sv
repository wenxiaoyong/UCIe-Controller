// Quarter-Rate Processor for 128 Gbps UCIe Controller
// Enables timing closure at 128 Gbps by processing data at quarter symbol rate
// 64 Gsym/s → 16 GHz processing with 4x parallel data streams

module ucie_quarter_rate_processor
    import ucie_pkg::*;
#(
    parameter DATA_WIDTH = 512,              // 4x wider for quarter-rate
    parameter NUM_PARALLEL_STREAMS = 4,      // 4 parallel streams
    parameter BUFFER_DEPTH = 64,            // Deeper buffering for rate conversion
    parameter ENABLE_ML_OPTIMIZATION = 1     // ML-enhanced processing
) (
    // Clock Domains
    input  logic                     clk_symbol_rate,    // 64 GHz symbol clock
    input  logic                     clk_quarter_rate,   // 16 GHz quarter-rate clock
    input  logic                     clk_bit_rate,       // 128 GHz bit clock
    input  logic                     rst_n,
    
    // Configuration
    input  logic                     processor_enable,
    input  logic [1:0]               processing_mode,    // 00=bypass, 01=quarter, 10=adaptive
    input  signaling_mode_t          signaling_mode,
    input  data_rate_t               data_rate,
    
    // Symbol-Rate Input Interface (from PAM4 PHY)
    input  logic [1:0]               symbol_data_in [NUM_PARALLEL_STREAMS],
    input  logic [NUM_PARALLEL_STREAMS-1:0] symbol_valid_in,
    output logic [NUM_PARALLEL_STREAMS-1:0] symbol_ready_out,
    
    // Quarter-Rate Output Interface (to Protocol Layer)
    output logic [DATA_WIDTH-1:0]    quarter_data_out,
    output logic                     quarter_valid_out,
    input  logic                     quarter_ready_in,
    
    // Quarter-Rate Input Interface (from Protocol Layer)
    input  logic [DATA_WIDTH-1:0]    quarter_data_in,
    input  logic                     quarter_valid_in,
    output logic                     quarter_ready_out,
    
    // Symbol-Rate Output Interface (to PAM4 PHY)
    output logic [1:0]               symbol_data_out [NUM_PARALLEL_STREAMS],
    output logic [NUM_PARALLEL_STREAMS-1:0] symbol_valid_out,
    input  logic [NUM_PARALLEL_STREAMS-1:0] symbol_ready_in,
    
    // Pipeline Control
    input  logic                     pipeline_bypass,    // Bypass for low latency
    input  logic [3:0]               pipeline_stages,    // Configurable pipeline depth
    output logic [7:0]               pipeline_occupancy,
    
    // ML-Enhanced Processing Interface
    input  logic                     ml_enable,
    input  logic [7:0]               ml_parameters [8],
    output logic [7:0]               ml_performance_metrics [4],
    input  logic [15:0]              ml_adaptation_rate,
    
    // Rate Conversion Status
    output logic                     rate_conversion_active,
    output logic [31:0]              conversion_statistics,
    output logic [15:0]              buffer_occupancy [2],  // RX/TX buffers
    
    // Error Detection and Correction
    output logic                     rate_conversion_error,
    output logic [7:0]               error_syndrome,
    input  logic                     error_correction_enable,
    
    // Performance Monitoring
    output logic [31:0]              throughput_mbps,
    output logic [15:0]              latency_cycles,
    output logic [7:0]               efficiency_percent,
    
    // Debug and Status
    output logic [31:0]              processor_status,
    output logic [15:0]              debug_counters [4]
);

    // Internal State Machine
    typedef enum logic [3:0] {
        QR_RESET,
        QR_INIT,
        QR_BYPASS,
        QR_RATE_CONVERT,
        QR_ML_ADAPT,
        QR_ERROR_RECOVERY,
        QR_THERMAL_THROTTLE
    } qr_state_t;
    
    qr_state_t current_state, next_state;
    
    // Rate Conversion Buffers
    logic [1:0] rx_symbol_buffer [NUM_PARALLEL_STREAMS][BUFFER_DEPTH];
    logic [BUFFER_DEPTH-1:0] rx_buffer_valid [NUM_PARALLEL_STREAMS];
    logic [$clog2(BUFFER_DEPTH)-1:0] rx_wr_ptr [NUM_PARALLEL_STREAMS];
    logic [$clog2(BUFFER_DEPTH)-1:0] rx_rd_ptr [NUM_PARALLEL_STREAMS];
    logic [$clog2(BUFFER_DEPTH):0] rx_buffer_count [NUM_PARALLEL_STREAMS];
    
    logic [DATA_WIDTH-1:0] tx_quarter_buffer [BUFFER_DEPTH];
    logic [BUFFER_DEPTH-1:0] tx_buffer_valid;
    logic [$clog2(BUFFER_DEPTH)-1:0] tx_wr_ptr, tx_rd_ptr;
    logic [$clog2(BUFFER_DEPTH):0] tx_buffer_count;
    
    // Rate Conversion Logic
    logic [8:0] symbol_accumulator [NUM_PARALLEL_STREAMS];  // 9 bits for symbol accumulation
    logic [3:0] symbol_count [NUM_PARALLEL_STREAMS];
    logic quarter_rate_ready;
    logic [DATA_WIDTH-1:0] assembled_quarter_word;
    
    // ML-Enhanced Processing
    logic [7:0] ml_congestion_predictor;
    logic [7:0] ml_throughput_optimizer;
    logic [7:0] ml_latency_predictor;
    logic [7:0] ml_error_predictor;
    
    // Performance Counters
    logic [31:0] symbols_processed;
    logic [31:0] quarter_words_processed;
    logic [31:0] bypass_cycles;
    logic [31:0] conversion_cycles;
    
    // Pipeline Registers for High-Speed Operation
    logic [1:0] symbol_pipe [NUM_PARALLEL_STREAMS][8];  // 8-stage pipeline
    logic [NUM_PARALLEL_STREAMS-1:0] symbol_valid_pipe [8];
    logic [DATA_WIDTH-1:0] quarter_pipe [4];            // 4-stage quarter-rate pipeline
    logic [3:0] quarter_valid_pipe;
    
    // State Machine
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= QR_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            QR_RESET: begin
                if (processor_enable) begin
                    next_state = QR_INIT;
                end
            end
            
            QR_INIT: begin
                if (processing_mode == 2'b00) begin
                    next_state = QR_BYPASS;
                end else if (processing_mode == 2'b01) begin
                    next_state = QR_RATE_CONVERT;
                end else if (processing_mode == 2'b10 && ml_enable) begin
                    next_state = QR_ML_ADAPT;
                end
            end
            
            QR_BYPASS: begin
                if (processing_mode != 2'b00) begin
                    next_state = QR_INIT;
                end else if (rate_conversion_error) begin
                    next_state = QR_ERROR_RECOVERY;
                end
            end
            
            QR_RATE_CONVERT: begin
                if (processing_mode == 2'b00) begin
                    next_state = QR_BYPASS;
                end else if (ml_enable && processing_mode == 2'b10) begin
                    next_state = QR_ML_ADAPT;
                end else if (rate_conversion_error) begin
                    next_state = QR_ERROR_RECOVERY;
                end
            end
            
            QR_ML_ADAPT: begin
                if (!ml_enable) begin
                    next_state = QR_RATE_CONVERT;
                end else if (processing_mode == 2'b00) begin
                    next_state = QR_BYPASS;
                end else if (rate_conversion_error) begin
                    next_state = QR_ERROR_RECOVERY;
                end
            end
            
            QR_ERROR_RECOVERY: begin
                if (!rate_conversion_error) begin
                    next_state = QR_INIT;
                end
            end
            
            default: begin
                next_state = QR_RESET;
            end
        endcase
    end
    
    // Symbol Rate to Quarter Rate Conversion (RX Path)
    always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                rx_wr_ptr[i] <= '0;
                rx_buffer_count[i] <= '0;
                rx_buffer_valid[i] <= '0;
                symbol_accumulator[i] <= 9'h0;
                symbol_count[i] <= 4'h0;
            end
        end else if (current_state == QR_RATE_CONVERT || current_state == QR_ML_ADAPT) begin
            for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                if (symbol_valid_in[i] && symbol_ready_out[i]) begin
                    // Store symbol in buffer
                    rx_symbol_buffer[i][rx_wr_ptr[i]] <= symbol_data_in[i];
                    rx_buffer_valid[i][rx_wr_ptr[i]] <= 1'b1;
                    
                    // Update write pointer
                    if (rx_wr_ptr[i] == ($clog2(BUFFER_DEPTH))'(BUFFER_DEPTH-1)) begin
                        rx_wr_ptr[i] <= '0;
                    end else begin
                        rx_wr_ptr[i] <= rx_wr_ptr[i] + 1;
                    end
                    
                    // Update buffer count
                    if (rx_buffer_count[i] < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH)) begin
                        rx_buffer_count[i] <= rx_buffer_count[i] + 1;
                    end
                    
                    // Accumulate symbols for quarter-rate assembly
                    symbol_accumulator[i] <= {symbol_accumulator[i][6:0], symbol_data_in[i]};
                    symbol_count[i] <= symbol_count[i] + 1;
                end
            end
        end
    end
    
    // Quarter Rate Assembly Logic
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            assembled_quarter_word <= '0;
            quarter_rate_ready <= 1'b0;
        end else if (current_state == QR_RATE_CONVERT || current_state == QR_ML_ADAPT) begin
            // Check if we have enough symbols from all streams
            logic all_streams_ready;
            all_streams_ready = 1'b1;
            for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                if (symbol_count[i] < 4'h4) begin  // Need 4 symbols per stream
                    all_streams_ready = 1'b0;
                end
            end
            
            if (all_streams_ready) begin
                // Assemble quarter-rate word from accumulated symbols
                for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                    assembled_quarter_word[i*128 +: 128] <= {
                        symbol_accumulator[i][7:6],   // Symbol 3
                        symbol_accumulator[i][5:4],   // Symbol 2
                        symbol_accumulator[i][3:2],   // Symbol 1
                        symbol_accumulator[i][1:0],   // Symbol 0
                        120'h0                        // Padding
                    };
                    symbol_count[i] <= '0;  // Reset count
                end
                quarter_rate_ready <= 1'b1;
            end else begin
                quarter_rate_ready <= 1'b0;
            end
        end
    end
    
    // Quarter Rate to Symbol Rate Conversion (TX Path)
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            tx_wr_ptr <= '0;
            tx_buffer_count <= '0;
            tx_buffer_valid <= '0;
        end else if (current_state == QR_RATE_CONVERT || current_state == QR_ML_ADAPT) begin
            if (quarter_valid_in && quarter_ready_out) begin
                // Store quarter-rate word in buffer
                tx_quarter_buffer[tx_wr_ptr] <= quarter_data_in;
                tx_buffer_valid[tx_wr_ptr] <= 1'b1;
                
                // Update write pointer
                if (tx_wr_ptr == ($clog2(BUFFER_DEPTH))'(BUFFER_DEPTH-1)) begin
                    tx_wr_ptr <= '0;
                end else begin
                    tx_wr_ptr <= tx_wr_ptr + 1;
                end
                
                // Update buffer count
                if (tx_buffer_count < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH)) begin
                    tx_buffer_count <= tx_buffer_count + 1;
                end
            end
        end
    end
    
    // Symbol Rate Output Generation
    logic [1:0] tx_symbol_counter;
    logic [DATA_WIDTH-1:0] current_tx_word;
    
    always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
        if (!rst_n) begin
            tx_rd_ptr <= '0;
            tx_symbol_counter <= 2'h0;
            current_tx_word <= '0;
            for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                symbol_data_out[i] <= 2'b00;
                symbol_valid_out[i] <= 1'b0;
            end
        end else if (current_state == QR_RATE_CONVERT || current_state == QR_ML_ADAPT) begin
            if (tx_buffer_valid[tx_rd_ptr] && |symbol_ready_in) begin
                // Load new quarter-rate word when starting new conversion
                if (tx_symbol_counter == 2'h0) begin
                    current_tx_word <= tx_quarter_buffer[tx_rd_ptr];
                end
                
                // Extract symbols for each stream
                for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                    if (symbol_ready_in[i]) begin
                        case (tx_symbol_counter)
                            2'h0: symbol_data_out[i] <= current_tx_word[i*128 + 1:i*128];
                            2'h1: symbol_data_out[i] <= current_tx_word[i*128 + 3:i*128 + 2];
                            2'h2: symbol_data_out[i] <= current_tx_word[i*128 + 5:i*128 + 4];
                            2'h3: symbol_data_out[i] <= current_tx_word[i*128 + 7:i*128 + 6];
                        endcase
                        symbol_valid_out[i] <= 1'b1;
                    end
                end
                
                // Update symbol counter
                tx_symbol_counter <= tx_symbol_counter + 1;
                
                // Move to next quarter-rate word when done
                if (tx_symbol_counter == 2'h3) begin
                    tx_buffer_valid[tx_rd_ptr] <= 1'b0;
                    if (tx_rd_ptr == ($clog2(BUFFER_DEPTH))'(BUFFER_DEPTH-1)) begin
                        tx_rd_ptr <= '0;
                    end else begin
                        tx_rd_ptr <= tx_rd_ptr + 1;
                    end
                    if (tx_buffer_count > 0) begin
                        tx_buffer_count <= tx_buffer_count - 1;
                    end
                end
            end
        end
    end
    
    // ML-Enhanced Processing
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            ml_congestion_predictor <= 8'h0;
            ml_throughput_optimizer <= 8'h80;  // 50% baseline
            ml_latency_predictor <= 8'h10;
            ml_error_predictor <= 8'h0;
        end else if (current_state == QR_ML_ADAPT && ml_enable) begin
            // ML-based congestion prediction
            logic [7:0] avg_buffer_occupancy;
            avg_buffer_occupancy = (rx_buffer_count[0] + rx_buffer_count[1] + 
                                   rx_buffer_count[2] + rx_buffer_count[3]) >> 2;
            
            if (avg_buffer_occupancy > (BUFFER_DEPTH * 3/4)) begin
                ml_congestion_predictor <= ml_congestion_predictor + ml_adaptation_rate[7:0];
            end else if (avg_buffer_occupancy < (BUFFER_DEPTH * 1/4)) begin
                if (ml_congestion_predictor > ml_adaptation_rate[7:0]) begin
                    ml_congestion_predictor <= ml_congestion_predictor - ml_adaptation_rate[7:0];
                end
            end
            
            // ML-based throughput optimization
            if (quarter_rate_ready && quarter_ready_in) begin
                ml_throughput_optimizer <= ml_throughput_optimizer + 1;
            end else if (ml_throughput_optimizer > 0) begin
                ml_throughput_optimizer <= ml_throughput_optimizer - 1;
            end
            
            // ML-based latency prediction
            ml_latency_predictor <= avg_buffer_occupancy + tx_buffer_count[7:0];
            
            // ML-based error prediction
            if (rate_conversion_error) begin
                ml_error_predictor <= ml_error_predictor + 4;
            end else if (ml_error_predictor > 0) begin
                ml_error_predictor <= ml_error_predictor - 1;
            end
        end
    end
    
    // Performance Monitoring
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            symbols_processed <= 32'h0;
            quarter_words_processed <= 32'h0;
            bypass_cycles <= 32'h0;
            conversion_cycles <= 32'h0;
        end else begin
            // Count symbols processed
            for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                if (symbol_valid_in[i] && symbol_ready_out[i] && 
                    symbols_processed < 32'hFFFFFFFF) begin
                    symbols_processed <= symbols_processed + 1;
                end
            end
            
            // Count quarter words processed
            if (quarter_valid_out && quarter_ready_in && 
                quarter_words_processed < 32'hFFFFFFFF) begin
                quarter_words_processed <= quarter_words_processed + 1;
            end
            
            // Count bypass cycles
            if (current_state == QR_BYPASS && bypass_cycles < 32'hFFFFFFFF) begin
                bypass_cycles <= bypass_cycles + 1;
            end
            
            // Count conversion cycles
            if ((current_state == QR_RATE_CONVERT || current_state == QR_ML_ADAPT) && 
                conversion_cycles < 32'hFFFFFFFF) begin
                conversion_cycles <= conversion_cycles + 1;
            end
        end
    end
    
    // Output Logic
    always_comb begin
        // Default outputs
        symbol_ready_out = '0;
        quarter_data_out = '0;
        quarter_valid_out = 1'b0;
        quarter_ready_out = 1'b0;
        
        case (current_state)
            QR_BYPASS: begin
                // Direct bypass mode - not implemented for 128 Gbps
                symbol_ready_out = symbol_ready_in;
                quarter_data_out = quarter_data_in;
                quarter_valid_out = quarter_valid_in;
                quarter_ready_out = quarter_ready_in;
            end
            
            QR_RATE_CONVERT, QR_ML_ADAPT: begin
                // Rate conversion mode
                for (int i = 0; i < NUM_PARALLEL_STREAMS; i++) begin
                    symbol_ready_out[i] = (rx_buffer_count[i] < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-1));
                end
                
                quarter_data_out = assembled_quarter_word;
                quarter_valid_out = quarter_rate_ready;
                quarter_ready_out = (tx_buffer_count < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-1));
            end
            
            default: begin
                // Reset/error states - no outputs
            end
        endcase
    end
    
    // Status and Debug Outputs
    assign rate_conversion_active = (current_state == QR_RATE_CONVERT || current_state == QR_ML_ADAPT);
    assign conversion_statistics = {symbols_processed[15:0], quarter_words_processed[15:0]};
    assign buffer_occupancy[0] = (rx_buffer_count[0] + rx_buffer_count[1] + 
                                 rx_buffer_count[2] + rx_buffer_count[3]) >> 2;
    assign buffer_occupancy[1] = tx_buffer_count[15:0];
    
    // ML Performance Metrics
    assign ml_performance_metrics[0] = ml_congestion_predictor;
    assign ml_performance_metrics[1] = ml_throughput_optimizer;
    assign ml_performance_metrics[2] = ml_latency_predictor;
    assign ml_performance_metrics[3] = ml_error_predictor;
    
    // Performance Calculations
    assign throughput_mbps = (quarter_words_processed * DATA_WIDTH * 1000) / (conversion_cycles + 1);
    assign latency_cycles = buffer_occupancy[0] + buffer_occupancy[1];
    assign efficiency_percent = (conversion_cycles * 100) / (conversion_cycles + bypass_cycles + 1);
    
    // Error Detection
    assign rate_conversion_error = (|rx_buffer_count > BUFFER_DEPTH) || 
                                  (tx_buffer_count > BUFFER_DEPTH) ||
                                  (ml_error_predictor > 8'h80);
    assign error_syndrome = {4'h0, current_state};
    
    // Status Register
    assign processor_status = {
        current_state,              // [31:28]
        processing_mode,            // [27:26]
        signaling_mode,             // [25:24]
        data_rate,                  // [23:20]
        ml_enable,                  // [19]
        rate_conversion_active,     // [18]
        rate_conversion_error,      // [17]
        quarter_rate_ready,         // [16]
        efficiency_percent,         // [15:8]
        pipeline_occupancy          // [7:0]
    };
    
    // Debug Counters
    assign debug_counters[0] = symbols_processed[15:0];
    assign debug_counters[1] = quarter_words_processed[15:0];
    assign debug_counters[2] = bypass_cycles[15:0];
    assign debug_counters[3] = conversion_cycles[15:0];
    
    assign pipeline_occupancy = (buffer_occupancy[0] + buffer_occupancy[1]) >> 1;

endmodule