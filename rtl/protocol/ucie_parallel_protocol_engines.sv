// Parallel Protocol Engines for 128 Gbps UCIe Controller
// 4x 32 Gbps parallel engines to achieve 128 Gbps total throughput
// Each engine handles a specific subset of protocols

module ucie_parallel_protocol_engines
    import ucie_pkg::*;
#(
    parameter NUM_ENGINES = 4,                    // 4 parallel engines
    parameter ENGINE_BANDWIDTH_GBPS = 32,        // 32 Gbps per engine
    parameter BUFFER_DEPTH = 4096,               // Deep buffering per engine
    parameter NUM_VCS = 8,                       // Virtual channels per engine
    parameter ENABLE_ML_OPTIMIZATION = 1          // ML-enhanced load balancing
) (
    // Clock and Reset
    input  logic                     clk_quarter_rate,    // 16 GHz quarter-rate
    input  logic                     clk_symbol_rate,     // 64 GHz symbol rate
    input  logic                     rst_n,
    
    // Configuration
    input  logic                     engines_enable,
    input  logic [3:0]               num_active_engines,  // 1-4 active engines
    input  logic [1:0]               load_balance_mode,   // 00=RR, 01=weighted, 10=ML
    
    // 128 Gbps Input Distribution Interface
    input  logic [511:0]             flit_data_128g,      // 512-bit wide for 128 Gbps
    input  flit_header_t             flit_header_128g,
    input  logic                     flit_valid_128g,
    output logic                     flit_ready_128g,
    input  logic [3:0]               flit_protocol_id,
    input  logic [7:0]               flit_vc,
    
    // Per-Engine Interfaces (to individual protocol processors)
    output logic [127:0]             engine_data [NUM_ENGINES],        // 128-bit per engine
    output flit_header_t             engine_header [NUM_ENGINES],
    output logic [NUM_ENGINES-1:0]   engine_valid,
    input  logic [NUM_ENGINES-1:0]   engine_ready,
    output logic [3:0]               engine_protocol_id [NUM_ENGINES],
    output logic [7:0]               engine_vc [NUM_ENGINES],
    
    // Aggregated Output from Engines
    input  logic [127:0]             engine_out_data [NUM_ENGINES],
    input  flit_header_t             engine_out_header [NUM_ENGINES],
    input  logic [NUM_ENGINES-1:0]   engine_out_valid,
    output logic [NUM_ENGINES-1:0]   engine_out_ready,
    input  logic [3:0]               engine_out_protocol_id [NUM_ENGINES],
    input  logic [7:0]               engine_out_vc [NUM_ENGINES],
    
    // Combined 128 Gbps Output
    output logic [511:0]             flit_out_data_128g,
    output flit_header_t             flit_out_header_128g,
    output logic                     flit_out_valid_128g,
    input  logic                     flit_out_ready_128g,
    output logic [3:0]               flit_out_protocol_id,
    output logic [7:0]               flit_out_vc,
    
    // Load Balancing Interface
    input  logic [7:0]               engine_weights [NUM_ENGINES],     // Static weights
    output logic [15:0]              engine_load [NUM_ENGINES],        // Current load
    output logic [15:0]              engine_throughput [NUM_ENGINES],  // Throughput per engine
    
    // ML-Enhanced Load Balancing
    input  logic                     ml_enable,
    input  logic [7:0]               ml_parameters [8],
    output logic [7:0]               ml_load_predictions [NUM_ENGINES],
    output logic [7:0]               ml_performance_metrics [4],
    
    // Flow Control and Congestion Management
    input  logic [7:0]               vc_credits [NUM_ENGINES][NUM_VCS],
    output logic [7:0]               vc_consumed [NUM_ENGINES][NUM_VCS],
    output logic [NUM_ENGINES-1:0]   engine_congested,
    
    // Performance Monitoring
    output logic [31:0]              total_throughput_mbps,
    output logic [15:0]              average_latency_cycles,
    output logic [7:0]               load_balance_efficiency,
    
    // Error Detection and Recovery
    output logic [NUM_ENGINES-1:0]   engine_errors,
    output logic                     load_balance_error,
    input  logic                     error_recovery_enable,
    
    // Status and Debug
    output logic [31:0]              engines_status,
    output logic [31:0]              load_balance_stats,
    output logic [15:0]              debug_counters [NUM_ENGINES]
);

    // Load Balancing State Machine
    typedef enum logic [2:0] {
        LB_RESET,
        LB_INIT,
        LB_ROUND_ROBIN,
        LB_WEIGHTED,
        LB_ML_ADAPTIVE,
        LB_CONGESTION_AVOID,
        LB_ERROR_RECOVERY
    } lb_state_t;
    
    lb_state_t current_state, next_state;
    
    // Engine Selection Logic
    logic [$clog2(NUM_ENGINES)-1:0] selected_engine_tx;
    logic [$clog2(NUM_ENGINES)-1:0] selected_engine_rx;
    logic [$clog2(NUM_ENGINES)-1:0] rr_counter;
    logic [NUM_ENGINES-1:0] engine_available;
    
    // Input Distribution Buffers
    logic [511:0] input_buffer [16];  // 16-deep input buffer
    logic [15:0] input_buffer_valid;
    logic [3:0] input_wr_ptr, input_rd_ptr;
    logic [4:0] input_buffer_count;
    
    // Output Aggregation Buffers
    logic [511:0] output_buffer [16];  // 16-deep output buffer
    logic [15:0] output_buffer_valid;
    logic [3:0] output_wr_ptr, output_rd_ptr;
    logic [4:0] output_buffer_count;
    
    // Load Balancing Metrics
    logic [31:0] engine_flit_count [NUM_ENGINES];
    logic [15:0] engine_buffer_occupancy [NUM_ENGINES];
    logic [7:0] engine_congestion_level [NUM_ENGINES];
    
    // ML-Enhanced Load Balancing
    logic [7:0] ml_congestion_predictor [NUM_ENGINES];
    logic [7:0] ml_throughput_predictor [NUM_ENGINES];
    logic [15:0] ml_adaptation_counter;
    logic [7:0] ml_learning_rate;
    
    // Performance Tracking
    logic [31:0] total_flits_processed;
    logic [31:0] load_balance_cycles;
    logic [15:0] congestion_events;
    
    // State Machine
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= LB_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
        case (current_state)
            LB_RESET: begin
                if (engines_enable) begin
                    next_state = LB_INIT;
                end
            end
            
            LB_INIT: begin
                case (load_balance_mode)
                    2'b00: next_state = LB_ROUND_ROBIN;
                    2'b01: next_state = LB_WEIGHTED;
                    2'b10: next_state = ml_enable ? LB_ML_ADAPTIVE : LB_WEIGHTED;
                    default: next_state = LB_ROUND_ROBIN;
                endcase
            end
            
            LB_ROUND_ROBIN: begin
                if (load_balance_mode != 2'b00) begin
                    next_state = LB_INIT;
                end else if (|engine_congested) begin
                    next_state = LB_CONGESTION_AVOID;
                end else if (load_balance_error) begin
                    next_state = LB_ERROR_RECOVERY;
                end
            end
            
            LB_WEIGHTED: begin
                if (load_balance_mode == 2'b00) begin
                    next_state = LB_ROUND_ROBIN;
                end else if (load_balance_mode == 2'b10 && ml_enable) begin
                    next_state = LB_ML_ADAPTIVE;
                end else if (|engine_congested) begin
                    next_state = LB_CONGESTION_AVOID;
                end else if (load_balance_error) begin
                    next_state = LB_ERROR_RECOVERY;
                end
            end
            
            LB_ML_ADAPTIVE: begin
                if (!ml_enable) begin
                    next_state = LB_WEIGHTED;
                end else if (load_balance_mode != 2'b10) begin
                    next_state = LB_INIT;
                end else if (|engine_congested) begin
                    next_state = LB_CONGESTION_AVOID;
                end else if (load_balance_error) begin
                    next_state = LB_ERROR_RECOVERY;
                end
            end
            
            LB_CONGESTION_AVOID: begin
                if (!|engine_congested) begin
                    next_state = LB_INIT;
                end else if (load_balance_error) begin
                    next_state = LB_ERROR_RECOVERY;
                end
            end
            
            LB_ERROR_RECOVERY: begin
                if (!load_balance_error && error_recovery_enable) begin
                    next_state = LB_INIT;
                end
            end
            
            default: begin
                next_state = LB_RESET;
            end
        endcase
    end
    
    // Input Distribution Logic
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            input_wr_ptr <= 4'h0;
            input_buffer_count <= 5'h0;
            input_buffer_valid <= 16'h0;
        end else if (flit_valid_128g && flit_ready_128g) begin
            // Store incoming 128 Gbps flit
            input_buffer[input_wr_ptr] <= flit_data_128g;
            input_buffer_valid[input_wr_ptr] <= 1'b1;
            
            // Update write pointer
            input_wr_ptr <= (input_wr_ptr == 4'd15) ? 4'h0 : input_wr_ptr + 1;
            
            // Update buffer count
            if (input_buffer_count < 5'd16) begin
                input_buffer_count <= input_buffer_count + 1;
            end
        end
    end
    
    // Engine Selection Logic
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            selected_engine_tx <= '0;
            rr_counter <= '0;
        end else if (input_buffer_valid[input_rd_ptr]) begin
            case (current_state)
                LB_ROUND_ROBIN: begin
                    // Simple round-robin selection
                    selected_engine_tx <= rr_counter;
                    rr_counter <= (rr_counter == ($clog2(NUM_ENGINES))'(num_active_engines-1)) ? 
                                 '0 : rr_counter + 1;
                end
                
                LB_WEIGHTED: begin
                    // Weighted selection based on engine weights and load
                    logic [$clog2(NUM_ENGINES)-1:0] best_engine;
                    logic [15:0] best_score;
                    
                    best_engine = '0;
                    best_score = 16'hFFFF;  // Lower is better
                    
                    for (int i = 0; i < NUM_ENGINES; i++) begin
                        if (i < num_active_engines && engine_ready[i]) begin
                            logic [15:0] engine_score;
                            // Score = load / weight ratio
                            engine_score = (engine_load[i] << 8) / (engine_weights[i] + 1);
                            
                            if (engine_score < best_score) begin
                                best_score = engine_score;
                                best_engine = i[$clog2(NUM_ENGINES)-1:0];
                            end
                        end
                    end
                    
                    selected_engine_tx <= best_engine;
                end
                
                LB_ML_ADAPTIVE: begin
                    // ML-enhanced selection
                    logic [$clog2(NUM_ENGINES)-1:0] ml_best_engine;
                    logic [15:0] ml_best_score;
                    
                    ml_best_engine = '0;
                    ml_best_score = 16'hFFFF;
                    
                    for (int i = 0; i < NUM_ENGINES; i++) begin
                        if (i < num_active_engines && engine_ready[i]) begin
                            logic [15:0] ml_score;
                            // ML score = predicted congestion + current load
                            ml_score = ml_congestion_predictor[i] + engine_load[i][7:0];
                            
                            if (ml_score < ml_best_score) begin
                                ml_best_score = ml_score;
                                ml_best_engine = i[$clog2(NUM_ENGINES)-1:0];
                            end
                        end
                    end
                    
                    selected_engine_tx <= ml_best_engine;
                end
                
                LB_CONGESTION_AVOID: begin
                    // Avoid congested engines
                    logic [$clog2(NUM_ENGINES)-1:0] non_congested_engine;
                    
                    non_congested_engine = '0;
                    for (int i = 0; i < NUM_ENGINES; i++) begin
                        if (i < num_active_engines && engine_ready[i] && !engine_congested[i]) begin
                            non_congested_engine = i[$clog2(NUM_ENGINES)-1:0];
                            break;
                        end
                    end
                    
                    selected_engine_tx <= non_congested_engine;
                end
                
                default: begin
                    selected_engine_tx <= '0;
                end
            endcase
        end
    end
    
    // Data Distribution to Engines
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            input_rd_ptr <= 4'h0;
            for (int i = 0; i < NUM_ENGINES; i++) begin
                engine_data[i] <= 128'h0;
                engine_header[i] <= '0;
                engine_valid[i] <= 1'b0;
                engine_protocol_id[i] <= 4'h0;
                engine_vc[i] <= 8'h0;
            end
        end else if (input_buffer_valid[input_rd_ptr] && engine_ready[selected_engine_tx]) begin
            // Distribute 512-bit data to 4x 128-bit engines
            case (selected_engine_tx)
                2'd0: engine_data[0] <= input_buffer[input_rd_ptr][127:0];
                2'd1: engine_data[1] <= input_buffer[input_rd_ptr][255:128];
                2'd2: engine_data[2] <= input_buffer[input_rd_ptr][383:256];
                2'd3: engine_data[3] <= input_buffer[input_rd_ptr][511:384];
            endcase
            
            engine_header[selected_engine_tx] <= flit_header_128g;
            engine_valid[selected_engine_tx] <= 1'b1;
            engine_protocol_id[selected_engine_tx] <= flit_protocol_id;
            engine_vc[selected_engine_tx] <= flit_vc;
            
            // Clear other engines
            for (int i = 0; i < NUM_ENGINES; i++) begin
                if (i != selected_engine_tx) begin
                    engine_valid[i] <= 1'b0;
                end
            end
            
            // Update read pointer
            input_buffer_valid[input_rd_ptr] <= 1'b0;
            input_rd_ptr <= (input_rd_ptr == 4'd15) ? 4'h0 : input_rd_ptr + 1;
            if (input_buffer_count > 0) begin
                input_buffer_count <= input_buffer_count - 1;
            end
        end
    end
    
    // Output Aggregation Logic
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            output_wr_ptr <= 4'h0;
            output_buffer_count <= 5'h0;
            output_buffer_valid <= 16'h0;
            selected_engine_rx <= '0;
        end else begin
            // Round-robin collection from engines
            logic engine_found;
            engine_found = 1'b0;
            
            for (int i = 0; i < NUM_ENGINES; i++) begin
                logic [$clog2(NUM_ENGINES)-1:0] engine_idx;
                engine_idx = ($clog2(NUM_ENGINES))'((selected_engine_rx + i) % NUM_ENGINES);
                
                if (!engine_found && engine_out_valid[engine_idx] && 
                    output_buffer_count < 5'd16) begin
                    
                    // Aggregate 128-bit from engine to 512-bit output
                    case (engine_idx)
                        2'd0: output_buffer[output_wr_ptr][127:0] <= engine_out_data[0];
                        2'd1: output_buffer[output_wr_ptr][255:128] <= engine_out_data[1];
                        2'd2: output_buffer[output_wr_ptr][383:256] <= engine_out_data[2];
                        2'd3: output_buffer[output_wr_ptr][511:384] <= engine_out_data[3];
                    endcase
                    
                    output_buffer_valid[output_wr_ptr] <= 1'b1;
                    
                    // Update write pointer
                    output_wr_ptr <= (output_wr_ptr == 4'd15) ? 4'h0 : output_wr_ptr + 1;
                    output_buffer_count <= output_buffer_count + 1;
                    
                    // Mark engine as ready for next data
                    engine_out_ready[engine_idx] <= 1'b1;
                    
                    // Update selection for next cycle
                    selected_engine_rx <= ($clog2(NUM_ENGINES))'((engine_idx + 1) % NUM_ENGINES);
                    engine_found = 1'b1;
                end else begin
                    engine_out_ready[engine_idx] <= 1'b0;
                end
            end
        end
    end
    
    // Output Generation
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            output_rd_ptr <= 4'h0;
            flit_out_data_128g <= 512'h0;
            flit_out_valid_128g <= 1'b0;
        end else if (output_buffer_valid[output_rd_ptr] && flit_out_ready_128g) begin
            flit_out_data_128g <= output_buffer[output_rd_ptr];
            flit_out_valid_128g <= 1'b1;
            
            // Update read pointer
            output_buffer_valid[output_rd_ptr] <= 1'b0;
            output_rd_ptr <= (output_rd_ptr == 4'd15) ? 4'h0 : output_rd_ptr + 1;
            if (output_buffer_count > 0) begin
                output_buffer_count <= output_buffer_count - 1;
            end
        end else begin
            flit_out_valid_128g <= 1'b0;
        end
    end
    
    // ML-Enhanced Load Balancing
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_ENGINES; i++) begin
                ml_congestion_predictor[i] <= 8'h40;  // 50% baseline
                ml_throughput_predictor[i] <= 8'h80;
            end
            ml_adaptation_counter <= 16'h0;
            ml_learning_rate <= 8'h04;  // 4/256 learning rate
        end else if (current_state == LB_ML_ADAPTIVE && ml_enable) begin
            ml_adaptation_counter <= ml_adaptation_counter + 1;
            
            // Adapt every 256 cycles
            if (ml_adaptation_counter[7:0] == 8'hFF) begin
                for (int i = 0; i < NUM_ENGINES; i++) begin
                    // Update congestion predictor based on actual congestion
                    if (engine_congested[i]) begin
                        if (ml_congestion_predictor[i] < 8'hF0) begin
                            ml_congestion_predictor[i] <= ml_congestion_predictor[i] + ml_learning_rate;
                        end
                    end else begin
                        if (ml_congestion_predictor[i] > ml_learning_rate) begin
                            ml_congestion_predictor[i] <= ml_congestion_predictor[i] - ml_learning_rate;
                        end
                    end
                    
                    // Update throughput predictor
                    logic [7:0] actual_throughput;
                    actual_throughput = engine_throughput[i][7:0];
                    
                    if (actual_throughput > ml_throughput_predictor[i]) begin
                        ml_throughput_predictor[i] <= ml_throughput_predictor[i] + (ml_learning_rate >> 1);
                    end else if (actual_throughput < ml_throughput_predictor[i]) begin
                        if (ml_throughput_predictor[i] > (ml_learning_rate >> 1)) begin
                            ml_throughput_predictor[i] <= ml_throughput_predictor[i] - (ml_learning_rate >> 1);
                        end
                    end
                end
            end
        end
    end
    
    // Engine Load and Performance Monitoring
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_ENGINES; i++) begin
                engine_flit_count[i] <= 32'h0;
                engine_buffer_occupancy[i] <= 16'h0;
                engine_congestion_level[i] <= 8'h0;
            end
            total_flits_processed <= 32'h0;
            load_balance_cycles <= 32'h0;
        end else begin
            load_balance_cycles <= load_balance_cycles + 1;
            
            // Monitor engine activity
            for (int i = 0; i < NUM_ENGINES; i++) begin
                if (engine_valid[i] && engine_ready[i]) begin
                    engine_flit_count[i] <= engine_flit_count[i] + 1;
                    total_flits_processed <= total_flits_processed + 1;
                end
                
                // Estimate buffer occupancy (simplified)
                if (engine_valid[i] && !engine_ready[i]) begin
                    if (engine_buffer_occupancy[i] < 16'hFFFF) begin
                        engine_buffer_occupancy[i] <= engine_buffer_occupancy[i] + 1;
                    end
                end else if (engine_buffer_occupancy[i] > 0) begin
                    engine_buffer_occupancy[i] <= engine_buffer_occupancy[i] - 1;
                end
                
                // Calculate congestion level
                engine_congestion_level[i] <= engine_buffer_occupancy[i][7:0];
            end
        end
    end
    
    // Output Assignments
    always_comb begin
        // Engine availability
        for (int i = 0; i < NUM_ENGINES; i++) begin
            engine_available[i] = (i < num_active_engines) && engine_ready[i] && !engine_congested[i];
        end
        
        // Load calculations
        for (int i = 0; i < NUM_ENGINES; i++) begin
            engine_load[i] = engine_buffer_occupancy[i];
            engine_throughput[i] = engine_flit_count[i][15:0];
            engine_congested[i] = (engine_congestion_level[i] > 8'hC0);  // 75% threshold
        end
        
        // ML predictions
        for (int i = 0; i < NUM_ENGINES; i++) begin
            ml_load_predictions[i] = ml_congestion_predictor[i];
        end
        
        // Flow control ready
        flit_ready_128g = (input_buffer_count < 5'd15) && engines_enable;
        
        // Performance metrics
        total_throughput_mbps = (total_flits_processed * 512) / (load_balance_cycles + 1);
        average_latency_cycles = (input_buffer_count + output_buffer_count) * 8;
        load_balance_efficiency = (total_flits_processed * 100) / (load_balance_cycles + 1);
        
        // Error detection
        load_balance_error = (input_buffer_count > 5'd15) || (output_buffer_count > 5'd15);
        for (int i = 0; i < NUM_ENGINES; i++) begin
            engine_errors[i] = engine_congestion_level[i] > 8'hF0;
        end
    end
    
    // ML Performance Metrics
    assign ml_performance_metrics[0] = ml_congestion_predictor[0];  // Engine 0 prediction
    assign ml_performance_metrics[1] = ml_throughput_predictor[0];  // Engine 0 throughput
    assign ml_performance_metrics[2] = ml_learning_rate;           // Learning rate
    assign ml_performance_metrics[3] = ml_adaptation_counter[7:0]; // Adaptation progress
    
    // Status Outputs
    assign engines_status = {
        current_state,                  // [31:29]
        load_balance_mode,              // [28:27]
        num_active_engines,             // [26:23]
        engine_available,               // [22:19]
        engine_congested,               // [18:15]
        load_balance_error,             // [14]
        ml_enable,                      // [13]
        engines_enable,                 // [12]
        input_buffer_count,             // [11:7]
        output_buffer_count,            // [6:2]
        selected_engine_tx              // [1:0]
    };
    
    assign load_balance_stats = {
        total_throughput_mbps[15:0],    // [31:16]
        average_latency_cycles          // [15:0]
    };
    
    // Debug Counters
    generate
        for (genvar i = 0; i < NUM_ENGINES; i++) begin : gen_debug_counters
            assign debug_counters[i] = engine_flit_count[i][15:0];
        end
    endgenerate

endmodule