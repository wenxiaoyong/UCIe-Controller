module ucie_signal_integrity_monitor
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter NUM_LANES = 64,               // Number of monitored lanes
    parameter NUM_MONITOR_POINTS = 16,      // Monitor points per lane
    parameter ENHANCED_128G = 1,            // Enable 128 Gbps optimizations
    parameter EYE_SAMPLE_DEPTH = 1024,      // Eye diagram sample depth
    parameter ML_ANALYSIS = 1,              // Enable ML-based analysis
    parameter REAL_TIME_ANALYSIS = 1        // Enable real-time analysis
) (
    // Clock and Reset
    input  logic                clk_symbol_rate,     // 64 GHz symbol clock
    input  logic                clk_quarter_rate,    // 16 GHz quarter-rate
    input  logic                clk_management,      // 200 MHz management
    input  logic                rst_n,
    
    // Configuration
    input  logic                monitor_enable,
    input  logic [7:0]          monitor_mode,        // Monitoring configuration
    input  signaling_mode_t     signaling_mode,      // NRZ or PAM4
    input  logic                ml_enable,
    
    // Per-Lane Signal Inputs
    input  logic [1:0]          pam4_signal [NUM_LANES],      // Raw PAM4 signals
    input  logic [1:0]          pam4_recovered [NUM_LANES],   // Recovered data
    input  logic [NUM_LANES-1:0] signal_valid,
    input  logic [NUM_LANES-1:0] clock_recovered,
    
    // Real-time Eye Diagram Monitoring
    output logic [7:0]          eye_height_mv [NUM_LANES],
    output logic [7:0]          eye_width_ps [NUM_LANES],
    output logic [15:0]         eye_opening_area [NUM_LANES],
    output logic [NUM_LANES-1:0] eye_quality_good,
    output logic [7:0]          eye_closure_rate [NUM_LANES],
    
    // Jitter Analysis
    output logic [15:0]         rj_rms_ps [NUM_LANES],        // Random jitter RMS
    output logic [15:0]         dj_pp_ps [NUM_LANES],         // Deterministic jitter P-P
    output logic [15:0]         tj_pp_ps [NUM_LANES],         // Total jitter P-P
    output logic [15:0]         jitter_spectrum [NUM_LANES][8], // Frequency components
    
    // Crosstalk Analysis
    output logic [15:0]         near_end_xtalk_db [NUM_LANES],
    output logic [15:0]         far_end_xtalk_db [NUM_LANES],
    output logic [7:0]          crosstalk_victims [NUM_LANES], // Affected lanes count
    output logic [NUM_LANES-1:0] crosstalk_critical,
    
    // Channel Response Analysis
    output logic [15:0]         channel_loss_db [NUM_LANES],
    output logic [7:0]          reflection_coeff [NUM_LANES],
    output logic [15:0]         impedance_ohm [NUM_LANES],
    output logic [7:0]          group_delay_ps [NUM_LANES],
    
    // Signal Quality Metrics
    output logic [15:0]         signal_power_dbm [NUM_LANES],
    output logic [15:0]         noise_power_dbm [NUM_LANES],
    output logic [15:0]         snr_db [NUM_LANES],
    output logic [15:0]         signal_integrity_score [NUM_LANES],
    
    // ML-Enhanced Analysis
    input  logic [15:0]         ml_channel_prediction [NUM_LANES],
    input  logic [7:0]          ml_noise_prediction [NUM_LANES],
    output logic [7:0]          ml_si_optimization [NUM_LANES],
    output logic [15:0]         ml_prediction_accuracy [NUM_LANES],
    
    // Real-time Adaptation Interface
    output logic [7:0]          recommended_eq_settings [NUM_LANES][8],
    output logic [15:0]         optimal_threshold_mv [NUM_LANES][4],
    output logic [7:0]          clock_phase_adjustment [NUM_LANES],
    output logic [NUM_LANES-1:0] adaptation_required,
    
    // Historical Analysis
    output logic [15:0]         si_trend_analysis [NUM_LANES][4], // 4 time periods
    output logic [7:0]          degradation_rate [NUM_LANES],
    output logic [31:0]         time_to_failure_hours [NUM_LANES],
    
    // Debug and Diagnostics
    input  logic [5:0]          debug_lane_select,
    input  logic [3:0]          debug_monitor_select,
    output logic [31:0]         debug_data_out,
    output logic [15:0]         debug_timestamp,
    
    // Status and Control
    output logic [31:0]         monitor_status,
    output logic [15:0]         error_count,
    output logic [7:0]          analysis_progress
);

    // Eye Diagram Monitoring Structure
    typedef struct packed {
        logic [7:0]  height_samples [EYE_SAMPLE_DEPTH-1:0];
        logic [7:0]  width_samples [EYE_SAMPLE_DEPTH-1:0];
        logic [15:0] sample_count;
        logic [7:0]  min_height;
        logic [7:0]  max_height;
        logic [7:0]  min_width;  
        logic [7:0]  max_width;
        logic [15:0] opening_area;
        logic [7:0]  closure_events;
        logic [31:0] measurement_timestamp;
    } eye_monitor_state_t;
    
    // Jitter Analysis Structure
    typedef struct packed {
        logic [15:0] edge_timestamps [256];  // Recent edge timestamps
        logic [7:0]  timestamp_ptr;
        logic [15:0] rj_accumulator;
        logic [15:0] dj_accumulator;
        logic [15:0] tj_measurement;
        logic [15:0] frequency_bins [8];     // Jitter spectrum
        logic [31:0] analysis_cycles;
    } jitter_analysis_state_t;
    
    // Crosstalk Analysis Structure
    typedef struct packed {
        logic [15:0] victim_amplitude [NUM_LANES];
        logic [15:0] aggressor_amplitude [NUM_LANES];
        logic [15:0] near_end_coupling;
        logic [15:0] far_end_coupling;
        logic [7:0]  victim_count;
        logic [31:0] coupling_matrix [4];   // Simplified coupling
        logic        critical_level;
    } crosstalk_state_t;
    
    // Channel Analysis Structure
    typedef struct packed {
        logic [15:0] insertion_loss;
        logic [15:0] return_loss;
        logic [15:0] characteristic_impedance;
        logic [7:0]  group_delay_variation;
        logic [15:0] frequency_response [8]; // 8 frequency points
        logic [31:0] measurement_timestamp;
    } channel_state_t;
    
    // ML Analysis Structure
    typedef struct packed {
        logic [15:0] prediction_history [8];
        logic [15:0] measurement_history [8];
        logic [7:0]  prediction_confidence;
        logic [15:0] model_accuracy;
        logic [7:0]  optimization_score;
        logic [31:0] learning_cycles;
    } ml_analysis_state_t;
    
    // Per-Lane State Arrays
    eye_monitor_state_t    eye_state [NUM_LANES];
    jitter_analysis_state_t jitter_state [NUM_LANES];
    crosstalk_state_t      crosstalk_state [NUM_LANES];
    channel_state_t        channel_state [NUM_LANES];
    ml_analysis_state_t    ml_analysis [NUM_LANES];
    
    // Global State
    logic [31:0] global_symbol_counter;
    logic [31:0] analysis_cycle_counter;
    logic [15:0] global_error_counter;
    logic [7:0] analysis_progress_counter;
    
    // Working Variables
    logic [15:0] instantaneous_measurements [NUM_LANES][4];
    logic [7:0] quality_scores [NUM_LANES];
    logic [31:0] degradation_tracking [NUM_LANES];
    
    // Global Symbol Counter
    always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
        if (!rst_n) begin
            global_symbol_counter <= 32'h0;
        end else begin
            global_symbol_counter <= global_symbol_counter + 1;
        end
    end
    
    // Analysis Cycle Counter
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            analysis_cycle_counter <= 32'h0;
            analysis_progress_counter <= 8'h0;
        end else if (monitor_enable) begin
            analysis_cycle_counter <= analysis_cycle_counter + 1;
            analysis_progress_counter <= analysis_progress_counter + 1;
        end
    end
    
    // Per-Lane Signal Integrity Monitoring
    genvar lane_idx;
    generate
        for (lane_idx = 0; lane_idx < NUM_LANES; lane_idx++) begin : gen_lane_monitoring
            
            // Real-time Eye Diagram Monitoring
            always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
                if (!rst_n) begin
                    eye_state[lane_idx].sample_count <= 16'h0;
                    eye_state[lane_idx].min_height <= 8'hFF;
                    eye_state[lane_idx].max_height <= 8'h00;
                    eye_state[lane_idx].min_width <= 8'hFF;
                    eye_state[lane_idx].max_width <= 8'h00;
                    eye_state[lane_idx].closure_events <= 8'h0;
                end else if (monitor_enable && signal_valid[lane_idx]) begin
                    
                    // Sample current signal levels for eye measurement
                    logic [1:0] current_signal = pam4_signal[lane_idx];
                    logic [1:0] recovered_data = pam4_recovered[lane_idx];
                    
                    // Calculate instantaneous eye metrics
                    logic [7:0] signal_amplitude;
                    case (current_signal)
                        2'b00: signal_amplitude = 8'd25;   // -3 level
                        2'b01: signal_amplitude = 8'd75;   // -1 level
                        2'b10: signal_amplitude = 8'd125;  // +1 level
                        2'b11: signal_amplitude = 8'd175;  // +3 level
                    endcase
                    
                    logic [7:0] expected_amplitude;
                    case (recovered_data)
                        2'b00: expected_amplitude = 8'd25;
                        2'b01: expected_amplitude = 8'd75;
                        2'b10: expected_amplitude = 8'd125;
                        2'b11: expected_amplitude = 8'd175;
                    endcase
                    
                    // Eye height measurement (voltage margin)
                    logic [7:0] voltage_margin = (signal_amplitude > expected_amplitude) ?
                        (signal_amplitude - expected_amplitude) : 
                        (expected_amplitude - signal_amplitude);
                    
                    // Update sample buffer (circular buffer)
                    logic [15:0] sample_idx = eye_state[lane_idx].sample_count % EYE_SAMPLE_DEPTH;
                    eye_state[lane_idx].height_samples[sample_idx] <= voltage_margin;
                    eye_state[lane_idx].width_samples[sample_idx] <= 8'd15; // Simplified timing margin
                    
                    eye_state[lane_idx].sample_count <= eye_state[lane_idx].sample_count + 1;
                    
                    // Track min/max values
                    if (voltage_margin < eye_state[lane_idx].min_height) begin
                        eye_state[lane_idx].min_height <= voltage_margin;
                    end
                    if (voltage_margin > eye_state[lane_idx].max_height) begin
                        eye_state[lane_idx].max_height <= voltage_margin;
                    end
                    
                    // Eye closure detection
                    if (voltage_margin < 8'd20) begin // <20mV margin
                        eye_state[lane_idx].closure_events <= 
                            eye_state[lane_idx].closure_events + 1;
                    end
                    
                    // Calculate opening area (simplified)
                    eye_state[lane_idx].opening_area <= 
                        {8'h0, eye_state[lane_idx].min_height} * 
                        {8'h0, eye_state[lane_idx].min_width};
                end
            end
            
            // Jitter Analysis Engine
            always_ff @(posedge clk_symbol_rate or negedge rst_n) begin
                if (!rst_n) begin
                    jitter_state[lane_idx].timestamp_ptr <= 8'h0;
                    jitter_state[lane_idx].rj_accumulator <= 16'h0;
                    jitter_state[lane_idx].dj_accumulator <= 16'h0;
                    jitter_state[lane_idx].analysis_cycles <= 32'h0;
                end else if (monitor_enable && clock_recovered[lane_idx]) begin
                    
                    // Capture edge timestamps for jitter analysis
                    logic clock_edge_detected = clock_recovered[lane_idx];
                    if (clock_edge_detected) begin
                        jitter_state[lane_idx].edge_timestamps[jitter_state[lane_idx].timestamp_ptr] 
                            <= global_symbol_counter[15:0];
                        jitter_state[lane_idx].timestamp_ptr <= 
                            jitter_state[lane_idx].timestamp_ptr + 1;
                    end
                    
                    jitter_state[lane_idx].analysis_cycles <= 
                        jitter_state[lane_idx].analysis_cycles + 1;
                    
                    // Jitter analysis every 256 samples
                    if (jitter_state[lane_idx].timestamp_ptr == 8'hFF) begin
                        // Calculate period variations for RJ/DJ separation
                        logic [15:0] period_variations [255];
                        logic [15:0] mean_period = 16'd64; // Nominal 64 symbol periods
                        logic [31:0] variance_sum = 32'h0;
                        
                        for (int i = 1; i < 256; i++) begin
                            period_variations[i-1] = 
                                jitter_state[lane_idx].edge_timestamps[i] - 
                                jitter_state[lane_idx].edge_timestamps[i-1];
                            
                            // Accumulate variance for RJ calculation
                            logic [15:0] deviation = (period_variations[i-1] > mean_period) ?
                                (period_variations[i-1] - mean_period) :
                                (mean_period - period_variations[i-1]);
                            variance_sum = variance_sum + (deviation * deviation);
                        end
                        
                        // RJ is proportional to standard deviation
                        jitter_state[lane_idx].rj_accumulator <= variance_sum[23:8];
                        
                        // DJ estimation (simplified - look for systematic patterns)
                        logic [15:0] systematic_error = 16'h0;
                        for (int i = 0; i < 8; i++) begin
                            systematic_error = systematic_error + 
                                period_variations[i * 32][7:0];
                        end
                        jitter_state[lane_idx].dj_accumulator <= systematic_error;
                        
                        // Total jitter combines RJ and DJ
                        jitter_state[lane_idx].tj_measurement <= 
                            jitter_state[lane_idx].rj_accumulator + 
                            jitter_state[lane_idx].dj_accumulator;
                        
                        // Reset for next analysis cycle
                        jitter_state[lane_idx].timestamp_ptr <= 8'h0;
                    end
                end
            end
            
            // Crosstalk Analysis
            always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
                if (!rst_n) begin
                    crosstalk_state[lane_idx].victim_count <= 8'h0;
                    crosstalk_state[lane_idx].near_end_coupling <= 16'h0;
                    crosstalk_state[lane_idx].far_end_coupling <= 16'h0;
                    crosstalk_state[lane_idx].critical_level <= 1'b0;
                end else if (monitor_enable) begin
                    
                    // Measure crosstalk by comparing adjacent lane signals
                    logic [15:0] victim_signal = {14'h0, pam4_signal[lane_idx]};
                    logic [15:0] total_aggressor_energy = 16'h0;
                    logic [7:0] active_aggressors = 8'h0;
                    
                    // Check adjacent lanes for crosstalk coupling
                    for (int adj = -2; adj <= 2; adj++) begin
                        int aggressor_lane = lane_idx + adj;
                        if (aggressor_lane >= 0 && aggressor_lane < NUM_LANES && 
                            aggressor_lane != lane_idx) begin
                            
                            logic [15:0] aggressor_signal = {14'h0, pam4_signal[aggressor_lane]};
                            logic [15:0] coupling_strength = 
                                (aggressor_signal > victim_signal) ?
                                (aggressor_signal - victim_signal) :
                                (victim_signal - aggressor_signal);
                            
                            total_aggressor_energy = total_aggressor_energy + coupling_strength;
                            if (coupling_strength > 16'd20) begin // Significant coupling
                                active_aggressors = active_aggressors + 1;
                            end
                        end
                    end
                    
                    crosstalk_state[lane_idx].victim_count <= active_aggressors;
                    
                    // Near-end crosstalk (NEXT) - immediate coupling
                    crosstalk_state[lane_idx].near_end_coupling <= total_aggressor_energy;
                    
                    // Far-end crosstalk (FEXT) - delayed coupling (simplified)
                    crosstalk_state[lane_idx].far_end_coupling <= 
                        total_aggressor_energy >> 1; // Assume 6dB less than NEXT
                    
                    // Critical crosstalk detection
                    crosstalk_state[lane_idx].critical_level <= 
                        (total_aggressor_energy > 16'd100) || (active_aggressors > 8'd2);
                end
            end
            
            // Channel Response Analysis
            always_ff @(posedge clk_management or negedge rst_n) begin
                if (!rst_n) begin
                    channel_state[lane_idx].insertion_loss <= 16'h0;
                    channel_state[lane_idx].return_loss <= 16'h0;
                    channel_state[lane_idx].characteristic_impedance <= 16'd50; // Default 50 ohm
                    channel_state[lane_idx].group_delay_variation <= 8'h0;
                end else if (monitor_enable && (analysis_cycle_counter[11:0] == 12'hFFF)) begin
                    
                    // Simplified channel analysis based on signal levels
                    logic [15:0] input_power = {14'h0, pam4_signal[lane_idx]};
                    logic [15:0] output_power = {14'h0, pam4_recovered[lane_idx]};
                    
                    // Insertion loss estimation
                    if (input_power > output_power && input_power > 16'h0) begin
                        logic [31:0] loss_ratio = (output_power * 32'd1000) / input_power;
                        channel_state[lane_idx].insertion_loss <= 
                            16'd1000 - loss_ratio[15:0]; // Convert to loss
                    end
                    
                    // Return loss (reflection coefficient estimation)
                    logic [15:0] reflected_estimate = 
                        (input_power > output_power) ? 
                        (input_power - output_power) : 16'h0;
                    channel_state[lane_idx].return_loss <= reflected_estimate;
                    
                    // Impedance variation detection (simplified)
                    logic [15:0] impedance_variation = reflected_estimate >> 2;
                    channel_state[lane_idx].characteristic_impedance <= 
                        16'd50 + impedance_variation - 16'd25; // 50 ± variation
                    
                    // Group delay estimation based on jitter characteristics
                    channel_state[lane_idx].group_delay_variation <= 
                        jitter_state[lane_idx].dj_accumulator[15:8];
                end
            end
            
            // ML-Enhanced Analysis
            always_ff @(posedge clk_management or negedge rst_n) begin
                if (!rst_n) begin
                    ml_analysis[lane_idx].prediction_confidence <= 8'h80;
                    ml_analysis[lane_idx].model_accuracy <= 16'h8000;
                    ml_analysis[lane_idx].optimization_score <= 8'h80;
                    ml_analysis[lane_idx].learning_cycles <= 32'h0;
                end else if (ML_ANALYSIS && ml_enable && monitor_enable) begin
                    ml_analysis[lane_idx].learning_cycles <= ml_analysis[lane_idx].learning_cycles + 1;
                    
                    // Update prediction and measurement history
                    if (analysis_cycle_counter[7:0] == 8'hFF) begin
                        // Shift history arrays
                        for (int i = 7; i > 0; i--) begin
                            ml_analysis[lane_idx].prediction_history[i] <= 
                                ml_analysis[lane_idx].prediction_history[i-1];
                            ml_analysis[lane_idx].measurement_history[i] <= 
                                ml_analysis[lane_idx].measurement_history[i-1];
                        end
                        
                        // Add new values
                        ml_analysis[lane_idx].prediction_history[0] <= 
                            ml_channel_prediction[lane_idx];
                        ml_analysis[lane_idx].measurement_history[0] <= 
                            channel_state[lane_idx].insertion_loss;
                    end
                    
                    // Calculate ML prediction accuracy
                    logic [15:0] prediction_error = 
                        (ml_channel_prediction[lane_idx] > channel_state[lane_idx].insertion_loss) ?
                        (ml_channel_prediction[lane_idx] - channel_state[lane_idx].insertion_loss) :
                        (channel_state[lane_idx].insertion_loss - ml_channel_prediction[lane_idx]);
                    
                    if (prediction_error < 16'd50) begin // Good prediction
                        ml_analysis[lane_idx].prediction_confidence <= 
                            (ml_analysis[lane_idx].prediction_confidence < 8'hF0) ?
                            ml_analysis[lane_idx].prediction_confidence + 1 : 8'hFF;
                    end else begin
                        ml_analysis[lane_idx].prediction_confidence <= 
                            (ml_analysis[lane_idx].prediction_confidence > 8'h20) ?
                            ml_analysis[lane_idx].prediction_confidence - 1 : 8'h10;
                    end
                    
                    // Model accuracy calculation
                    ml_analysis[lane_idx].model_accuracy <= 
                        16'd10000 - ((prediction_error * 16'd100) / 16'd1000);
                    
                    // Optimization score based on overall signal quality
                    logic [31:0] quality_sum = 
                        {16'h0, eye_state[lane_idx].opening_area} +
                        (16'd1000 - jitter_state[lane_idx].tj_measurement) +
                        (16'd500 - crosstalk_state[lane_idx].near_end_coupling);
                    ml_analysis[lane_idx].optimization_score <= quality_sum[15:8];
                end
            end
        end
    endgenerate
    
    // Global Analysis and Reporting
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            global_error_counter <= 16'h0;
        end else if (monitor_enable) begin
            
            // Count lanes with signal integrity issues
            logic [15:0] issue_count = 16'h0;
            for (int i = 0; i < NUM_LANES; i++) begin
                if (eye_state[i].closure_events > 8'd10 ||
                    jitter_state[i].tj_measurement > 16'd100 ||
                    crosstalk_state[i].critical_level) begin
                    issue_count = issue_count + 1;
                end
            end
            global_error_counter <= issue_count;
        end
    end
    
    // Debug Data Multiplexer
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            debug_data_out <= 32'h0;
            debug_timestamp <= 16'h0;
        end else if (debug_lane_select < NUM_LANES) begin
            debug_timestamp <= analysis_cycle_counter[15:0];
            
            case (debug_monitor_select)
                4'h0: debug_data_out <= {16'h0, eye_state[debug_lane_select].opening_area};
                4'h1: debug_data_out <= {16'h0, jitter_state[debug_lane_select].tj_measurement};
                4'h2: debug_data_out <= {16'h0, crosstalk_state[debug_lane_select].near_end_coupling};
                4'h3: debug_data_out <= {16'h0, channel_state[debug_lane_select].insertion_loss};
                4'h4: debug_data_out <= {16'h0, ml_analysis[debug_lane_select].model_accuracy};
                default: debug_data_out <= analysis_cycle_counter;
            endcase
        end
    end
    
    // Output Assignments
    for (genvar i = 0; i < NUM_LANES; i++) begin
        // Eye diagram outputs
        assign eye_height_mv[i] = eye_state[i].min_height;
        assign eye_width_ps[i] = eye_state[i].min_width;
        assign eye_opening_area[i] = eye_state[i].opening_area;
        assign eye_quality_good[i] = (eye_state[i].opening_area > 16'd200);
        assign eye_closure_rate[i] = eye_state[i].closure_events;
        
        // Jitter outputs
        assign rj_rms_ps[i] = jitter_state[i].rj_accumulator;
        assign dj_pp_ps[i] = jitter_state[i].dj_accumulator;
        assign tj_pp_ps[i] = jitter_state[i].tj_measurement;
        for (genvar j = 0; j < 8; j++) begin
            assign jitter_spectrum[i][j] = jitter_state[i].frequency_bins[j];
        end
        
        // Crosstalk outputs
        assign near_end_xtalk_db[i] = crosstalk_state[i].near_end_coupling;
        assign far_end_xtalk_db[i] = crosstalk_state[i].far_end_coupling;
        assign crosstalk_victims[i] = crosstalk_state[i].victim_count;
        assign crosstalk_critical[i] = crosstalk_state[i].critical_level;
        
        // Channel outputs
        assign channel_loss_db[i] = channel_state[i].insertion_loss;
        assign reflection_coeff[i] = channel_state[i].return_loss[15:8];
        assign impedance_ohm[i] = channel_state[i].characteristic_impedance;
        assign group_delay_ps[i] = channel_state[i].group_delay_variation;
        
        // Signal quality outputs
        assign signal_power_dbm[i] = {14'h0, pam4_signal[i]} * 16'd10; // Simplified
        assign noise_power_dbm[i] = eye_state[i].closure_events * 16'd5;
        assign snr_db[i] = signal_power_dbm[i] - noise_power_dbm[i];
        assign signal_integrity_score[i] = ml_analysis[i].optimization_score * 16'd100;
        
        // ML outputs
        assign ml_si_optimization[i] = ml_analysis[i].optimization_score;
        assign ml_prediction_accuracy[i] = ml_analysis[i].model_accuracy;
        
        // Adaptation recommendations (simplified)
        for (genvar j = 0; j < 8; j++) begin
            assign recommended_eq_settings[i][j] = 
                (eye_state[i].opening_area < 16'd100) ? 8'd200 : 8'd128;
        end
        for (genvar j = 0; j < 4; j++) begin
            assign optimal_threshold_mv[i][j] = 
                16'd50 + (j * 16'd50) + {8'h0, eye_state[i].min_height};
        end
        assign clock_phase_adjustment[i] = jitter_state[i].dj_accumulator[15:8];
        assign adaptation_required[i] = (eye_state[i].opening_area < 16'd150) ||
                                       (jitter_state[i].tj_measurement > 16'd80) ||
                                       crosstalk_state[i].critical_level;
        
        // Historical analysis (simplified)
        for (genvar j = 0; j < 4; j++) begin
            assign si_trend_analysis[i][j] = ml_analysis[i].measurement_history[j*2];
        end
        assign degradation_rate[i] = 8'd10; // Placeholder
        assign time_to_failure_hours[i] = 32'd8760; // 1 year placeholder
    end
    
    assign monitor_status = {
        monitor_enable,                       // [31] Monitor enabled
        ML_ANALYSIS && ml_enable,             // [30] ML enabled
        REAL_TIME_ANALYSIS,                   // [29] Real-time enabled
        signaling_mode,                       // [28:27] Signaling mode
        3'(popcount(eye_quality_good)),       // [26:24] Good eye count
        8'(global_error_counter[7:0]),        // [23:16] Error count
        analysis_progress_counter             // [15:8] Progress
    };
    
    assign error_count = global_error_counter;
    assign analysis_progress = analysis_progress_counter;

endmodule