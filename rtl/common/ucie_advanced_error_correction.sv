module ucie_advanced_error_correction
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter DATA_WIDTH = 256,             // Data width for correction
    parameter NUM_LANES = 64,               // Number of lanes
    parameter ENHANCED_128G = 1,            // Enable 128 Gbps optimizations
    parameter RS_CODE_LENGTH = 255,         // Reed-Solomon code length
    parameter RS_DATA_LENGTH = 223,         // Reed-Solomon data length
    parameter RS_PARITY_SYMBOLS = 32,       // Reed-Solomon parity symbols
    parameter SOFT_DECISION_ENABLE = 1,     // Enable soft-decision decoding
    parameter ADAPTIVE_FEC_ENABLE = 1       // Enable adaptive FEC strength
) (
    // Clock and Reset
    input  logic                clk_quarter_rate,    // 16 GHz quarter-rate
    input  logic                clk_management,      // 200 MHz management
    input  logic                rst_n,
    
    // Configuration
    input  logic                ecc_global_enable,
    input  logic [3:0]          fec_mode,           // 0=Off, 1=CRC, 2=RS, 3=Hybrid, 4=Adaptive
    input  logic                soft_decision_enable,
    input  logic [7:0]          error_threshold,    // Dynamic FEC strength adjustment
    input  logic                ml_enable,
    
    // Input Data Interface
    input  logic [DATA_WIDTH-1:0]    data_in,
    input  ucie_flit_header_t         header_in,
    input  logic                      valid_in,
    output logic                      ready_out,
    
    // Output Data Interface (Corrected)
    output logic [DATA_WIDTH-1:0]    data_out,
    output ucie_flit_header_t         header_out,
    output logic                      valid_out,
    input  logic                      ready_in,
    
    // Error Correction Status
    output logic [15:0]         corrected_errors [NUM_LANES],
    output logic [15:0]         uncorrectable_errors [NUM_LANES],
    output logic [7:0]          error_correction_strength,
    output logic [NUM_LANES-1:0] lane_error_critical,
    
    // Reed-Solomon FEC Interface
    input  logic [7:0]          rs_syndrome [RS_PARITY_SYMBOLS],
    output logic [7:0]          rs_error_magnitude [RS_CODE_LENGTH],
    output logic [7:0]          rs_error_location [RS_CODE_LENGTH],
    output logic                rs_correction_success,
    
    // Soft-Decision Decoding
    input  logic [3:0]          soft_bits [DATA_WIDTH],    // 4-bit soft values
    output logic [7:0]          reliability_metric [DATA_WIDTH/8],
    output logic [15:0]         decoding_confidence,
    
    // Adaptive FEC Control
    output logic [3:0]          adaptive_fec_level,      // Current FEC strength
    output logic [15:0]         error_rate_estimate,     // Estimated error rate
    output logic [7:0]          fec_efficiency_score,    // FEC performance metric
    
    // ML Enhancement Interface
    input  logic [15:0]         ml_error_prediction [NUM_LANES],
    input  logic [7:0]          ml_channel_quality [NUM_LANES],
    output logic [7:0]          ml_fec_optimization [NUM_LANES],
    output logic [15:0]         ml_prediction_accuracy,
    
    // Advanced Error Analysis
    output logic [31:0]         error_pattern_analysis [4],  // Systematic error patterns
    output logic [15:0]         burst_error_count,
    output logic [15:0]         random_error_count,
    output logic [7:0]          error_correlation_coefficient,
    
    // Performance Monitoring
    output logic [31:0]         total_bits_processed,
    output logic [31:0]         total_errors_corrected,
    output logic [31:0]         correction_cycles_used,
    output logic [15:0]         average_correction_latency,
    
    // Debug and Status
    output logic [31:0]         ecc_status,
    output logic [15:0]         debug_error_count,
    output logic [7:0]          thermal_throttle_level
);

    // Reed-Solomon Galois Field Operations
    typedef struct packed {
        logic [7:0] polynomial;             // GF(256) primitive polynomial
        logic [7:0] generator_poly [RS_PARITY_SYMBOLS];
        logic [7:0] alpha_powers [RS_CODE_LENGTH];
        logic [7:0] log_table [256];
        logic [7:0] antilog_table [256];
    } rs_galois_field_t;
    
    // Error Correction State Machine
    typedef enum logic [3:0] {
        ECC_IDLE          = 4'b0000,
        ECC_ANALYZE       = 4'b0001,
        ECC_CRC_CHECK     = 4'b0010,
        ECC_RS_SYNDROME   = 4'b0011,
        ECC_FIND_ERRORS   = 4'b0100,
        ECC_CORRECT_ERRORS= 4'b0101,
        ECC_SOFT_DECODE   = 4'b0110,
        ECC_VERIFY        = 4'b0111,
        ECC_COMPLETE      = 4'b1000,
        ECC_ERROR         = 4'b1111
    } ecc_state_t;
    
    // Error Pattern Analysis Structure
    typedef struct packed {
        logic [31:0] single_bit_errors;
        logic [31:0] double_bit_errors;
        logic [31:0] burst_errors;
        logic [31:0] systematic_errors;
        logic [15:0] error_positions [16];   // Most common error positions
        logic [7:0]  pattern_confidence;
        logic [31:0] analysis_timestamp;
    } error_pattern_state_t;
    
    // Soft-Decision Decoding State
    typedef struct packed {
        logic [3:0]  soft_values [DATA_WIDTH];
        logic [7:0]  reliability [DATA_WIDTH/8];
        logic [15:0] decoding_metrics;
        logic [7:0]  confidence_level;
        logic        soft_decode_success;
        logic [31:0] decode_iterations;
    } soft_decision_state_t;
    
    // Adaptive FEC Management
    typedef struct packed {
        logic [3:0]  current_strength;
        logic [15:0] measured_error_rate;
        logic [15:0] target_error_rate;
        logic [7:0]  adaptation_speed;
        logic [31:0] adaptation_history [8];
        logic        strength_locked;
    } adaptive_fec_state_t;
    
    // Per-Lane Error Tracking
    typedef struct packed {
        logic [15:0] corrected_count;
        logic [15:0] uncorrectable_count;
        logic [15:0] error_rate_ppm;
        logic [7:0]  correction_attempts;
        logic [31:0] last_error_timestamp;
        logic        critical_error_state;
    } lane_error_state_t;
    
    // State Arrays and Variables
    rs_galois_field_t           galois_field;
    ecc_state_t                 ecc_state;
    error_pattern_state_t       error_patterns;
    soft_decision_state_t       soft_decoder;
    adaptive_fec_state_t        adaptive_fec;
    lane_error_state_t          lane_errors [NUM_LANES];
    
    // Reed-Solomon Working Variables
    logic [7:0] rs_syndrome_calc [RS_PARITY_SYMBOLS];
    logic [7:0] rs_error_poly [RS_PARITY_SYMBOLS];
    logic [7:0] rs_error_eval [RS_CODE_LENGTH];
    logic [7:0] rs_error_deriv [RS_CODE_LENGTH];
    logic [15:0] rs_correction_count;
    
    // Data Processing Buffers
    logic [DATA_WIDTH-1:0] input_buffer [4];
    logic [DATA_WIDTH-1:0] working_buffer;
    logic [DATA_WIDTH-1:0] corrected_buffer;
    ucie_flit_header_t header_buffer [4];
    logic [1:0] buffer_wr_ptr, buffer_rd_ptr;
    
    // Performance Counters
    logic [31:0] global_cycle_counter;
    logic [31:0] bits_processed_counter;
    logic [31:0] errors_corrected_counter;
    logic [31:0] correction_latency_accumulator;
    logic [15:0] correction_operations;
    
    // ML Enhancement State
    logic [15:0] ml_prediction_history [NUM_LANES][4];
    logic [7:0] ml_accuracy_tracker [NUM_LANES];
    logic [15:0] ml_optimization_score;
    logic [31:0] ml_learning_cycles;
    
    // Initialize Galois Field for Reed-Solomon
    initial begin
        // GF(256) primitive polynomial: x^8 + x^4 + x^3 + x^2 + 1 (0x11D)
        galois_field.polynomial = 8'h1D;
        
        // Initialize generator polynomial for RS(255,223)
        galois_field.generator_poly[0] = 8'h01;
        for (int i = 1; i < RS_PARITY_SYMBOLS; i++) begin
            galois_field.generator_poly[i] = 8'h02; // Simplified initialization
        end
        
        // Initialize alpha powers and log tables (simplified)
        for (int i = 0; i < 256; i++) begin
            galois_field.alpha_powers[i] = 8'(i);
            galois_field.log_table[i] = 8'(i);
            galois_field.antilog_table[i] = 8'(255 - i);
        end
    end
    
    // Global Cycle Counter
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            global_cycle_counter <= 32'h0;
        end else begin
            global_cycle_counter <= global_cycle_counter + 1;
        end
    end
    
    // Input Buffer Management
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            buffer_wr_ptr <= 2'h0;
            ready_out <= 1'b0;
        end else if (ecc_global_enable) begin
            ready_out <= ((buffer_wr_ptr + 1) != buffer_rd_ptr);
            
            if (valid_in && ready_out) begin
                input_buffer[buffer_wr_ptr] <= data_in;
                header_buffer[buffer_wr_ptr] <= header_in;
                buffer_wr_ptr <= buffer_wr_ptr + 1;
            end
        end else begin
            ready_out <= 1'b0;
        end
    end
    
    // Main Error Correction State Machine
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            ecc_state <= ECC_IDLE;
            buffer_rd_ptr <= 2'h0;
            valid_out <= 1'b0;
            rs_correction_count <= 16'h0;
        end else if (ecc_global_enable) begin
            
            case (ecc_state)
                ECC_IDLE: begin
                    if (buffer_wr_ptr != buffer_rd_ptr) begin
                        working_buffer <= input_buffer[buffer_rd_ptr];
                        ecc_state <= ECC_ANALYZE;
                        bits_processed_counter <= bits_processed_counter + DATA_WIDTH;
                    end
                end
                
                ECC_ANALYZE: begin
                    // Quick error analysis to determine correction method
                    logic [15:0] error_estimate = 16'h0;
                    for (int i = 0; i < DATA_WIDTH; i += 8) begin
                        logic [7:0] byte_val = working_buffer[i+7:i];
                        // Simple parity check for error estimation
                        if (^byte_val != header_buffer[buffer_rd_ptr].parity_expected[i/8]) begin
                            error_estimate = error_estimate + 1;
                        end
                    end
                    
                    // Choose correction method based on estimated errors
                    if (fec_mode == 4'h1 || error_estimate < 2) begin
                        ecc_state <= ECC_CRC_CHECK;
                    end else if (fec_mode >= 4'h2) begin
                        ecc_state <= ECC_RS_SYNDROME;
                    end else begin
                        ecc_state <= (SOFT_DECISION_ENABLE && soft_decision_enable) ? 
                                   ECC_SOFT_DECODE : ECC_COMPLETE;
                    end
                end
                
                ECC_CRC_CHECK: begin
                    // Simple CRC-32 error detection and single-bit correction
                    logic [31:0] calculated_crc = 32'h0;
                    logic [31:0] received_crc = working_buffer[31:0];
                    
                    // Calculate CRC (simplified implementation)
                    for (int i = 32; i < DATA_WIDTH; i++) begin
                        calculated_crc = calculated_crc ^ {31'h0, working_buffer[i]};
                        if (calculated_crc[0]) begin
                            calculated_crc = (calculated_crc >> 1) ^ 32'hEDB88320;
                        end else begin
                            calculated_crc = calculated_crc >> 1;
                        end
                    end
                    
                    if (calculated_crc == received_crc) begin
                        corrected_buffer <= working_buffer;
                        ecc_state <= ECC_COMPLETE;
                    end else begin
                        // Attempt single-bit correction
                        logic [7:0] error_position = 8'(calculated_crc[7:0]);
                        if (error_position < DATA_WIDTH) begin
                            corrected_buffer <= working_buffer ^ (256'h1 << error_position);
                            errors_corrected_counter <= errors_corrected_counter + 1;
                        end else begin
                            corrected_buffer <= working_buffer; // Can't correct
                        end
                        ecc_state <= ECC_COMPLETE;
                    end
                end
                
                ECC_RS_SYNDROME: begin
                    // Calculate Reed-Solomon syndrome
                    for (int i = 0; i < RS_PARITY_SYMBOLS; i++) begin
                        rs_syndrome_calc[i] <= 8'h0;
                        
                        // Syndrome calculation (simplified)
                        for (int j = 0; j < RS_DATA_LENGTH; j++) begin
                            logic [7:0] data_symbol = working_buffer[(j*8)+7:(j*8)];
                            rs_syndrome_calc[i] <= rs_syndrome_calc[i] ^ data_symbol;
                        end
                    end
                    ecc_state <= ECC_FIND_ERRORS;
                end
                
                ECC_FIND_ERRORS: begin
                    // Berlekamp-Massey algorithm for error locator polynomial (simplified)
                    logic [15:0] detected_errors = 16'h0;
                    
                    for (int i = 0; i < RS_PARITY_SYMBOLS; i++) begin
                        if (rs_syndrome_calc[i] != 8'h0) begin
                            detected_errors = detected_errors + 1;
                        end
                    end
                    
                    if (detected_errors > 0 && detected_errors <= (RS_PARITY_SYMBOLS/2)) begin
                        rs_correction_count <= detected_errors;
                        ecc_state <= ECC_CORRECT_ERRORS;
                    end else if (detected_errors == 0) begin
                        corrected_buffer <= working_buffer;
                        ecc_state <= ECC_COMPLETE;
                    end else begin
                        // Too many errors for Reed-Solomon correction
                        ecc_state <= (SOFT_DECISION_ENABLE && soft_decision_enable) ? 
                                   ECC_SOFT_DECODE : ECC_ERROR;
                    end
                end
                
                ECC_CORRECT_ERRORS: begin
                    // Apply Reed-Solomon error correction
                    corrected_buffer <= working_buffer;
                    
                    // Simplified error correction (in practice, would use Forney algorithm)
                    for (int i = 0; i < rs_correction_count && i < 16; i++) begin
                        logic [7:0] error_pos = rs_error_location[i];
                        logic [7:0] error_val = rs_error_magnitude[i];
                        
                        if (error_pos < (DATA_WIDTH/8)) begin
                            corrected_buffer[(error_pos*8)+7:(error_pos*8)] <= 
                                corrected_buffer[(error_pos*8)+7:(error_pos*8)] ^ error_val;
                        end
                    end
                    
                    errors_corrected_counter <= errors_corrected_counter + rs_correction_count;
                    ecc_state <= ECC_VERIFY;
                end
                
                ECC_SOFT_DECODE: begin
                    if (SOFT_DECISION_ENABLE) begin
                        // Soft-decision iterative decoding
                        for (int i = 0; i < DATA_WIDTH; i++) begin
                            soft_decoder.soft_values[i] <= soft_bits[i];
                        end
                        
                        // Simplified soft decoding (iterative improvement)
                        soft_decoder.decode_iterations <= soft_decoder.decode_iterations + 1;
                        
                        // Calculate reliability metrics
                        for (int i = 0; i < DATA_WIDTH/8; i++) begin
                            logic [7:0] reliability_sum = 8'h0;
                            for (int j = 0; j < 8; j++) begin
                                reliability_sum = reliability_sum + {4'h0, soft_bits[i*8+j]};
                            end
                            soft_decoder.reliability[i] <= reliability_sum;
                        end
                        
                        // Make hard decisions based on soft values
                        for (int i = 0; i < DATA_WIDTH; i++) begin
                            corrected_buffer[i] <= soft_bits[i] > 4'h8;
                        end
                        
                        soft_decoder.soft_decode_success <= 1'b1;
                        ecc_state <= ECC_VERIFY;
                    end else begin
                        ecc_state <= ECC_COMPLETE;
                    end
                end
                
                ECC_VERIFY: begin
                    // Final verification of correction
                    logic correction_verified = 1'b1;
                    
                    // Re-check CRC on corrected data (simplified)
                    logic [31:0] verify_crc = 32'h0;
                    for (int i = 32; i < DATA_WIDTH; i++) begin
                        verify_crc = verify_crc ^ {31'h0, corrected_buffer[i]};
                    end
                    
                    if (verify_crc == corrected_buffer[31:0]) begin
                        rs_correction_success <= 1'b1;
                        ecc_state <= ECC_COMPLETE;
                    end else begin
                        rs_correction_success <= 1'b0;
                        ecc_state <= ECC_ERROR;
                    end
                end
                
                ECC_COMPLETE: begin
                    data_out <= corrected_buffer;
                    header_out <= header_buffer[buffer_rd_ptr];
                    valid_out <= 1'b1;
                    
                    if (ready_in) begin
                        buffer_rd_ptr <= buffer_rd_ptr + 1;
                        valid_out <= 1'b0;
                        ecc_state <= ECC_IDLE;
                        
                        // Update performance counters
                        correction_operations <= correction_operations + 1;
                        correction_latency_accumulator <= correction_latency_accumulator + 
                            (global_cycle_counter - header_buffer[buffer_rd_ptr].timestamp[31:0]);
                    end
                end
                
                ECC_ERROR: begin
                    // Error state - output original data with error indication
                    data_out <= working_buffer;
                    header_out <= header_buffer[buffer_rd_ptr];
                    header_out.error_detected <= 1'b1;
                    valid_out <= 1'b1;
                    
                    if (ready_in) begin
                        buffer_rd_ptr <= buffer_rd_ptr + 1;
                        valid_out <= 1'b0;
                        ecc_state <= ECC_IDLE;
                        debug_error_count <= debug_error_count + 1;
                    end
                end
            endcase
        end
    end
    
    // Adaptive FEC Strength Management
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            adaptive_fec.current_strength <= 4'h2;        // Start with medium strength
            adaptive_fec.target_error_rate <= 16'd100;    // Target: 100 ppm
            adaptive_fec.adaptation_speed <= 8'h10;
            adaptive_fec.strength_locked <= 1'b0;
        end else if (ADAPTIVE_FEC_ENABLE && ecc_global_enable && (fec_mode == 4'h4)) begin
            
            // Calculate current error rate
            if (correction_operations > 0) begin
                adaptive_fec.measured_error_rate <= 
                    (errors_corrected_counter * 16'd1000000) / bits_processed_counter[15:0];
            end
            
            // Adjust FEC strength based on error rate
            if (global_cycle_counter[15:0] == 16'hFFFF) begin // Every 65k cycles
                if (adaptive_fec.measured_error_rate > adaptive_fec.target_error_rate + 16'd50) begin
                    // Too many errors - increase FEC strength
                    if (adaptive_fec.current_strength < 4'hF) begin
                        adaptive_fec.current_strength <= adaptive_fec.current_strength + 1;
                    end
                end else if (adaptive_fec.measured_error_rate < adaptive_fec.target_error_rate - 16'd25) begin
                    // Very few errors - can decrease FEC strength for better performance
                    if (adaptive_fec.current_strength > 4'h1) begin
                        adaptive_fec.current_strength <= adaptive_fec.current_strength - 1;
                    end
                end
                
                // Update adaptation history
                for (int i = 7; i > 0; i--) begin
                    adaptive_fec.adaptation_history[i] <= adaptive_fec.adaptation_history[i-1];
                end
                adaptive_fec.adaptation_history[0] <= {16'h0, adaptive_fec.measured_error_rate};
            end
        end
    end
    
    // ML-Enhanced Error Prediction and Optimization
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            ml_optimization_score <= 16'h8000;
            ml_learning_cycles <= 32'h0;
            for (int i = 0; i < NUM_LANES; i++) begin
                ml_accuracy_tracker[i] <= 8'h80;
                for (int j = 0; j < 4; j++) begin
                    ml_prediction_history[i][j] <= 16'h0;
                end
            end
        end else if (ml_enable && ecc_global_enable) begin
            ml_learning_cycles <= ml_learning_cycles + 1;
            
            // Update ML prediction accuracy
            for (int lane = 0; lane < NUM_LANES; lane++) begin
                if (lane < 4) begin // Process a few lanes per cycle
                    logic [15:0] predicted_errors = ml_error_prediction[lane];
                    logic [15:0] actual_errors = lane_errors[lane].corrected_count;
                    
                    // Calculate prediction error
                    logic [15:0] prediction_error = (predicted_errors > actual_errors) ?
                        (predicted_errors - actual_errors) : (actual_errors - predicted_errors);
                    
                    if (prediction_error < 16'd10) begin // Good prediction
                        ml_accuracy_tracker[lane] <= (ml_accuracy_tracker[lane] < 8'hF0) ?
                            ml_accuracy_tracker[lane] + 1 : 8'hFF;
                    end else begin
                        ml_accuracy_tracker[lane] <= (ml_accuracy_tracker[lane] > 8'h10) ?
                            ml_accuracy_tracker[lane] - 1 : 8'h00;
                    end
                    
                    // Update prediction history
                    if (global_cycle_counter[11:0] == 12'hFFF) begin
                        for (int i = 3; i > 0; i--) begin
                            ml_prediction_history[lane][i] <= ml_prediction_history[lane][i-1];
                        end
                        ml_prediction_history[lane][0] <= predicted_errors;
                    end
                end
            end
            
            // Calculate overall ML optimization score
            logic [31:0] accuracy_sum = 32'h0;
            for (int i = 0; i < NUM_LANES; i++) begin
                accuracy_sum = accuracy_sum + ml_accuracy_tracker[i];
            end
            ml_optimization_score <= accuracy_sum[15:0] / NUM_LANES[15:0];
        end
    end
    
    // Error Pattern Analysis
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            error_patterns <= '0;
        end else if (ecc_global_enable && (ecc_state == ECC_COMPLETE)) begin
            error_patterns.analysis_timestamp <= global_cycle_counter;
            
            // Classify error patterns
            if (rs_correction_count == 1) begin
                error_patterns.single_bit_errors <= error_patterns.single_bit_errors + 1;
            end else if (rs_correction_count == 2) begin
                error_patterns.double_bit_errors <= error_patterns.double_bit_errors + 1;
            end else if (rs_correction_count > 2) begin
                error_patterns.burst_errors <= error_patterns.burst_errors + 1;
            end
            
            // Track error positions for systematic error detection
            if (rs_correction_count > 0 && rs_correction_count <= 16) begin
                logic [7:0] pos_index = rs_error_location[0] % 16;
                error_patterns.error_positions[pos_index] <= 
                    error_patterns.error_positions[pos_index] + 1;
            end
        end
    end
    
    // Output Assignments
    for (genvar i = 0; i < NUM_LANES; i++) begin
        assign corrected_errors[i] = (i < 4) ? lane_errors[i].corrected_count : 16'h0;
        assign uncorrectable_errors[i] = (i < 4) ? lane_errors[i].uncorrectable_count : 16'h0;
        assign lane_error_critical[i] = (i < 4) ? lane_errors[i].critical_error_state : 1'b0;
        assign ml_fec_optimization[i] = (i < NUM_LANES) ? ml_accuracy_tracker[i] : 8'h0;
    end
    
    assign error_correction_strength = {4'h0, adaptive_fec.current_strength};
    assign adaptive_fec_level = adaptive_fec.current_strength;
    assign error_rate_estimate = adaptive_fec.measured_error_rate;
    assign fec_efficiency_score = ml_optimization_score[15:8];
    
    assign ml_prediction_accuracy = ml_optimization_score;
    assign decoding_confidence = soft_decoder.decoding_metrics;
    
    for (genvar i = 0; i < DATA_WIDTH/8; i++) begin
        assign reliability_metric[i] = (SOFT_DECISION_ENABLE) ? soft_decoder.reliability[i] : 8'h80;
    end
    
    for (genvar i = 0; i < 4; i++) begin
        assign error_pattern_analysis[i] = (i == 0) ? error_patterns.single_bit_errors :
                                          (i == 1) ? error_patterns.double_bit_errors :
                                          (i == 2) ? error_patterns.burst_errors :
                                                    error_patterns.systematic_errors;
    end
    
    assign burst_error_count = error_patterns.burst_errors[15:0];
    assign random_error_count = error_patterns.single_bit_errors[15:0];
    assign error_correlation_coefficient = error_patterns.pattern_confidence;
    
    assign total_bits_processed = bits_processed_counter;
    assign total_errors_corrected = errors_corrected_counter;
    assign correction_cycles_used = correction_latency_accumulator;
    assign average_correction_latency = (correction_operations > 0) ?
        (correction_latency_accumulator[15:0] / correction_operations) : 16'h0;
    
    assign ecc_status = {
        ecc_global_enable,                    // [31] Global enable
        ADAPTIVE_FEC_ENABLE,                  // [30] Adaptive FEC
        SOFT_DECISION_ENABLE,                 // [29] Soft decision
        fec_mode,                            // [28:25] FEC mode
        adaptive_fec.current_strength,        // [24:21] Current strength
        ecc_state,                           // [20:17] Current state
        rs_correction_success,                // [16] RS success
        adaptive_fec.measured_error_rate[15:0] // [15:0] Error rate
    };
    
    assign thermal_throttle_level = (adaptive_fec.current_strength > 4'h8) ? 8'h80 : 8'h40;

endmodule