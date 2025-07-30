module ucie_advanced_observability_framework
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter TRACE_BUFFER_DEPTH = 1048576,    // 1M samples trace buffer
    parameter NUM_TRIGGER_CONDITIONS = 64,     // Intelligent trigger conditions
    parameter NUM_PERFORMANCE_COUNTERS = 128,  // Performance monitoring counters
    parameter NUM_LANES = 64,                   // Number of monitored lanes
    parameter ENHANCED_128G = 1,                // Enable 128 Gbps optimizations
    parameter ANOMALY_DETECTION_DEPTH = 32,    // Statistical learning depth
    parameter EVENT_CATEGORIES = 16            // Event categorization depth
) (
    // Clock and Reset
    input  logic                clk_quarter_rate,    // 16 GHz quarter-rate
    input  logic                clk_management,      // 200 MHz management clock
    input  logic                rst_n,
    
    // Configuration
    input  logic                obs_global_enable,
    input  logic                trace_enable,
    input  logic                anomaly_detection_enable,
    input  logic                performance_monitoring_enable,
    input  logic                real_time_analytics_enable,
    input  logic [7:0]          trace_compression_level,    // 0=None, 255=Max
    
    // Data Capture Interfaces
    input  logic [255:0]        flit_data_capture,
    input  ucie_flit_header_t   flit_header_capture,
    input  logic                flit_valid_capture,
    input  logic [2:0]          flit_protocol_id,
    input  logic [NUM_LANES-1:0] lane_activity_capture,
    
    // System State Monitoring
    input  logic [31:0]         system_performance_metrics [16],
    input  logic [15:0]         power_consumption_mw [8],
    input  logic [11:0]         thermal_readings_c [16],
    input  logic [7:0]          error_counts [NUM_LANES],
    input  logic [NUM_LANES-1:0] link_training_status,
    
    // ML-Enhanced Analytics Interface
    input  logic                ml_enable,
    input  logic [15:0]         ml_prediction_confidence [8],
    input  logic [31:0]         ml_model_accuracy,
    output logic [15:0]         anomaly_probability [EVENT_CATEGORIES],
    output logic [7:0]          predictive_alert_level,
    
    // Intelligent Triggering
    input  logic [31:0]         trigger_conditions [NUM_TRIGGER_CONDITIONS],
    input  logic [NUM_TRIGGER_CONDITIONS-1:0] trigger_enable_mask,
    output logic [NUM_TRIGGER_CONDITIONS-1:0] trigger_activated,
    output logic                trace_triggered,
    output logic [31:0]         trigger_timestamp,
    
    // Trace Buffer Management
    output logic [19:0]         trace_write_pointer,
    output logic [19:0]         trace_read_pointer,
    output logic [31:0]         trace_sample_count,
    output logic                trace_buffer_full,
    output logic                trace_buffer_overflow,
    
    // Performance Analytics Dashboard
    output logic [31:0]         dashboard_metrics [32],
    output logic [15:0]         bandwidth_utilization_percent [NUM_LANES],
    output logic [15:0]         latency_distribution_ns [8],  // Histogram bins
    output logic [7:0]          protocol_efficiency_score [4],
    output logic [15:0]         system_load_average,
    
    // Anomaly Detection Results
    output logic [EVENT_CATEGORIES-1:0] anomaly_detected,
    output logic [7:0]          anomaly_severity [EVENT_CATEGORIES],
    output logic [31:0]         anomaly_timestamp [EVENT_CATEGORIES],
    output logic [255:0]        anomaly_signature [EVENT_CATEGORIES],
    output logic                regression_detected,
    
    // Real-time Issue Detection
    output logic                performance_degradation_alert,
    output logic                thermal_anomaly_alert,
    output logic                power_anomaly_alert,
    output logic                protocol_violation_alert,
    output logic [15:0]         issue_correlation_score,
    
    // Data Export Interface
    input  logic                export_request,
    input  logic [1:0]          export_format,       // 00=Raw, 01=CSV, 10=JSON, 11=Binary
    output logic [255:0]        export_data_stream,
    output logic                export_data_valid,
    output logic                export_complete,
    
    // Debug Access Interface
    input  logic [19:0]         debug_read_address,
    input  logic                debug_read_enable,
    output logic [255:0]        debug_read_data,
    output logic                debug_read_valid,
    
    // Configuration and Control
    input  logic [31:0]         observation_window_cycles,
    input  logic [7:0]          statistical_confidence_threshold,
    input  logic [15:0]         performance_baseline [16],
    
    // Status and Health
    output logic [31:0]         obs_status,
    output logic [15:0]         memory_utilization_percent,
    output logic [7:0]          processing_load_percent
);

    // Trace Buffer Entry Structure
    typedef struct packed {
        logic [255:0]           data_payload;
        ucie_flit_header_t      header;
        logic [31:0]            timestamp;
        logic [2:0]             protocol_id;
        logic [7:0]             event_type;
        logic [15:0]            associated_metrics;
        logic [NUM_LANES-1:0]   lane_snapshot;
        logic                   compressed;
    } trace_entry_t;
    
    // Performance Counter Structure
    typedef struct packed {
        logic [63:0]            counter_value;
        logic [31:0]            last_update_time;
        logic [15:0]            update_rate;
        logic [7:0]             counter_type;      // Event type being counted
        logic                   overflow_flag;
        logic                   enabled;
    } performance_counter_t;
    
    // Anomaly Detection State
    typedef struct packed {
        logic [31:0]            baseline_values [8];
        logic [31:0]            current_values [8];
        logic [15:0]            deviation_scores [8];
        logic [31:0]            detection_history [ANOMALY_DETECTION_DEPTH];
        logic [7:0]             confidence_level;
        logic [31:0]            learning_cycles;
        logic                   model_trained;
    } anomaly_detector_t;
    
    // Real-time Analytics State
    typedef struct packed {
        logic [31:0]            bandwidth_accumulator [NUM_LANES];
        logic [31:0]            latency_accumulator [8];
        logic [15:0]            latency_sample_counts [8];
        logic [31:0]            packet_counts [4];
        logic [31:0]            error_accumulator;
        logic [31:0]            measurement_window_start;
        logic                   analytics_valid;
    } analytics_state_t;
    
    // Event Classification Structure
    typedef struct packed {
        logic [7:0]             event_category;     // 0-15 categories
        logic [7:0]             severity_level;     // 0=Info, 255=Critical
        logic [31:0]            occurrence_count;
        logic [31:0]            first_occurrence;
        logic [31:0]            last_occurrence;
        logic [255:0]           pattern_signature;
        logic                   correlated_events;
    } event_classifier_t;
    
    // Main Storage Arrays
    trace_entry_t trace_buffer [TRACE_BUFFER_DEPTH];
    performance_counter_t perf_counters [NUM_PERFORMANCE_COUNTERS];
    anomaly_detector_t anomaly_detectors [EVENT_CATEGORIES];
    analytics_state_t realtime_analytics;
    event_classifier_t event_classifiers [EVENT_CATEGORIES];
    
    // Control and State Variables
    logic [19:0] trace_wr_ptr, trace_rd_ptr;
    logic [31:0] global_timestamp_counter;
    logic [31:0] trace_samples_captured;
    logic trace_buffer_full_flag;
    logic [NUM_TRIGGER_CONDITIONS-1:0] trigger_states;
    
    // Working Variables for Analytics
    logic [31:0] current_bandwidth [NUM_LANES];
    logic [15:0] current_latency_histogram [8];
    logic [7:0] system_health_score;
    logic [15:0] correlation_matrix [EVENT_CATEGORIES][EVENT_CATEGORIES];
    
    // ML and Statistical Learning
    logic [31:0] ml_feature_vector [16];
    logic [15:0] statistical_baselines [32];
    logic [7:0] anomaly_thresholds [EVENT_CATEGORIES];
    
    // Global Timestamp Counter
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            global_timestamp_counter <= 32'h0;
        end else begin
            global_timestamp_counter <= global_timestamp_counter + 1;
        end
    end
    
    // Intelligent Trigger Engine
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            trigger_states <= '0;
            trace_triggered <= 1'b0;
            trigger_timestamp <= 32'h0;
        end else if (obs_global_enable && trace_enable) begin
            
            // Evaluate all trigger conditions
            for (int i = 0; i < NUM_TRIGGER_CONDITIONS; i++) begin
                if (trigger_enable_mask[i]) begin
                    logic condition_met = 1'b0;
                    
                    // Decode trigger condition (simplified implementation)
                    logic [7:0] trigger_type = trigger_conditions[i][7:0];
                    logic [23:0] trigger_threshold = trigger_conditions[i][31:8];
                    
                    case (trigger_type)
                        8'h01: begin // Flit error threshold
                            condition_met = (error_counts[0] > trigger_threshold[7:0]);
                        end
                        8'h02: begin // Bandwidth threshold
                            condition_met = (current_bandwidth[0] > {8'h0, trigger_threshold});
                        end
                        8'h03: begin // Latency threshold
                            condition_met = (current_latency_histogram[0] > trigger_threshold[15:0]);
                        end
                        8'h04: begin // Thermal threshold
                            condition_met = (thermal_readings_c[0] > trigger_threshold[11:0]);
                        end
                        8'h05: begin // Power threshold
                            condition_met = (power_consumption_mw[0] > trigger_threshold[15:0]);
                        end
                        8'h06: begin // Protocol violation
                            condition_met = (flit_header_capture.error_detected);
                        end
                        8'h07: begin // Link training failure
                            condition_met = (!link_training_status[0]);
                        end
                        8'h08: begin // Anomaly detection trigger
                            condition_met = (|anomaly_detected);
                        end
                        8'h09: begin // Performance regression
                            condition_met = regression_detected;
                        end
                        8'h0A: begin // System overload
                            condition_met = (system_load_average > trigger_threshold[15:0]);
                        end
                        default: condition_met = 1'b0;
                    endcase
                    
                    trigger_states[i] <= condition_met;
                    
                    if (condition_met && !trigger_states[i]) begin // Rising edge
                        trace_triggered <= 1'b1;
                        trigger_timestamp <= global_timestamp_counter;
                    end
                end else begin
                    trigger_states[i] <= 1'b0;
                end
            end
        end
    end
    
    // High-Speed Trace Buffer Management
    always_ff @(posedge clk_quarter_rate or negedge rst_n) begin
        if (!rst_n) begin
            trace_wr_ptr <= 20'h0;
            trace_samples_captured <= 32'h0;
            trace_buffer_full_flag <= 1'b0;
        end else if (obs_global_enable && trace_enable) begin
            
            // Capture data when valid or triggered
            if (flit_valid_capture || trace_triggered || (|trigger_states)) begin
                
                // Prepare trace entry
                trace_entry_t new_entry;
                new_entry.data_payload = flit_data_capture;
                new_entry.header = flit_header_capture;
                new_entry.timestamp = global_timestamp_counter;
                new_entry.protocol_id = flit_protocol_id;
                new_entry.event_type = trace_triggered ? 8'hFF : 8'h01; // Special marking for triggered events
                new_entry.associated_metrics = {8'h0, error_counts[0]};
                new_entry.lane_snapshot = lane_activity_capture;
                new_entry.compressed = (trace_compression_level > 8'h80);
                
                // Apply compression if enabled
                if (trace_compression_level > 8'h00) begin
                    // Simplified compression - zero out less significant bits
                    logic [7:0] compress_shift = trace_compression_level >> 5; // /32
                    new_entry.data_payload <= new_entry.data_payload & (~((256'h1 << compress_shift) - 1));
                end
                
                // Store in circular buffer
                trace_buffer[trace_wr_ptr] <= new_entry;
                
                // Update write pointer with wrap-around
                if (trace_wr_ptr == (TRACE_BUFFER_DEPTH - 1)) begin
                    trace_wr_ptr <= 20'h0;
                    trace_buffer_full_flag <= 1'b1;
                end else begin
                    trace_wr_ptr <= trace_wr_ptr + 1;
                end
                
                trace_samples_captured <= trace_samples_captured + 1;
            end
        end
    end
    
    // Performance Counter Management
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PERFORMANCE_COUNTERS; i++) begin
                perf_counters[i] <= '0;
                perf_counters[i].enabled <= 1'b1; // Enable by default
            end
        end else if (obs_global_enable && performance_monitoring_enable) begin
            
            // Update predefined performance counters
            if (perf_counters[0].enabled) begin // Total flits processed
                if (flit_valid_capture) begin
                    perf_counters[0].counter_value <= perf_counters[0].counter_value + 1;
                    perf_counters[0].last_update_time <= global_timestamp_counter;
                end
            end
            
            if (perf_counters[1].enabled) begin // Error count accumulator
                logic [15:0] total_errors = 16'h0;
                for (int lane = 0; lane < NUM_LANES && lane < 16; lane++) begin
                    total_errors = total_errors + {8'h0, error_counts[lane]};
                end
                perf_counters[1].counter_value <= {48'h0, total_errors};
            end
            
            if (perf_counters[2].enabled) begin // Bandwidth utilization
                if (global_timestamp_counter[7:0] == 8'hFF) begin // Every 256 cycles
                    logic [31:0] bandwidth_sum = 32'h0;
                    for (int lane = 0; lane < NUM_LANES && lane < 16; lane++) begin
                        bandwidth_sum = bandwidth_sum + current_bandwidth[lane];
                    end
                    perf_counters[2].counter_value <= {32'h0, bandwidth_sum};
                end
            end
            
            if (perf_counters[3].enabled) begin // Power consumption tracking
                if (global_timestamp_counter[11:0] == 12'hFFF) begin // Every 4096 cycles
                    logic [31:0] power_sum = 32'h0;
                    for (int i = 0; i < 8; i++) begin
                        power_sum = power_sum + {16'h0, power_consumption_mw[i]};
                    end
                    perf_counters[3].counter_value <= {32'h0, power_sum};
                end
            end
            
            if (perf_counters[4].enabled) begin // Thermal monitoring
                if (global_timestamp_counter[11:0] == 12'h7FF) begin // Every 2048 cycles
                    logic [15:0] max_temp = 16'h0;
                    for (int i = 0; i < 16; i++) begin
                        if (thermal_readings_c[i] > max_temp[11:0]) begin
                            max_temp = {4'h0, thermal_readings_c[i]};
                        end
                    end
                    perf_counters[4].counter_value <= {48'h0, max_temp};
                end
            end
            
            // Check for counter overflows
            for (int i = 0; i < NUM_PERFORMANCE_COUNTERS; i++) begin
                if (perf_counters[i].counter_value == 64'hFFFFFFFFFFFFFFFF) begin
                    perf_counters[i].overflow_flag <= 1'b1;
                end
            end
        end
    end
    
    // Real-time Analytics Engine
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            realtime_analytics <= '0;
            system_health_score <= 8'hFF; // Perfect health initially
        end else if (obs_global_enable && real_time_analytics_enable) begin
            
            // Update measurement window
            if (global_timestamp_counter - realtime_analytics.measurement_window_start > observation_window_cycles) begin
                realtime_analytics.measurement_window_start <= global_timestamp_counter;
                
                // Calculate analytics for completed window
                for (int lane = 0; lane < NUM_LANES && lane < 16; lane++) begin
                    // Bandwidth calculation (simplified)
                    current_bandwidth[lane] <= realtime_analytics.bandwidth_accumulator[lane] / 
                                             (observation_window_cycles >> 10); // Normalize
                    realtime_analytics.bandwidth_accumulator[lane] <= 32'h0; // Reset
                end
                
                // Latency histogram update
                for (int bin = 0; bin < 8; bin++) begin
                    if (realtime_analytics.latency_sample_counts[bin] > 0) begin
                        current_latency_histogram[bin] <= 
                            realtime_analytics.latency_accumulator[bin] / realtime_analytics.latency_sample_counts[bin];
                    end
                    realtime_analytics.latency_accumulator[bin] <= 32'h0;
                    realtime_analytics.latency_sample_counts[bin] <= 16'h0;
                end
                
                realtime_analytics.analytics_valid <= 1'b1;
            end
            
            // Accumulate current window data
            if (flit_valid_capture) begin
                logic [5:0] lane_idx = flit_protocol_id[1:0] * 16; // Simplified lane mapping
                if (lane_idx < NUM_LANES) begin
                    realtime_analytics.bandwidth_accumulator[lane_idx] <= 
                        realtime_analytics.bandwidth_accumulator[lane_idx] + (FLIT_WIDTH / 8);
                end
                
                // Latency binning (simplified)
                logic [2:0] latency_bin = flit_header_capture.timestamp[2:0];
                realtime_analytics.latency_accumulator[latency_bin] <= 
                    realtime_analytics.latency_accumulator[latency_bin] + 
                    {16'h0, flit_header_capture.timestamp[15:0]};
                realtime_analytics.latency_sample_counts[latency_bin] <= 
                    realtime_analytics.latency_sample_counts[latency_bin] + 1;
            end
            
            // System health calculation
            logic [15:0] health_factors [4];
            health_factors[0] = (current_bandwidth[0] < {24'h0, performance_baseline[0]}) ? 16'hFFFF : 16'h8000;
            health_factors[1] = (current_latency_histogram[0] < performance_baseline[1]) ? 16'hFFFF : 16'h6000;
            health_factors[2] = (error_counts[0] == 8'h0) ? 16'hFFFF : 16'h4000;
            health_factors[3] = (thermal_readings_c[0] < 12'd85) ? 16'hFFFF : 16'h2000;
            
            logic [31:0] health_sum = {16'h0, health_factors[0]} + {16'h0, health_factors[1]} + 
                                     {16'h0, health_factors[2]} + {16'h0, health_factors[3]};
            system_health_score <= health_sum[19:12]; // Scale to 8-bit
        end
    end
    
    // ML-Enhanced Anomaly Detection
    genvar anom_idx;
    generate
        for (anom_idx = 0; anom_idx < EVENT_CATEGORIES; anom_idx++) begin : gen_anomaly_detectors
            
            always_ff @(posedge clk_management or negedge rst_n) begin
                if (!rst_n) begin
                    anomaly_detectors[anom_idx] <= '0;
                    anomaly_detectors[anom_idx].confidence_level <= 8'h80; // Medium confidence
                    
                    // Initialize baselines
                    for (int i = 0; i < 8; i++) begin
                        anomaly_detectors[anom_idx].baseline_values[i] <= performance_baseline[i % 16];
                    end
                end else if (obs_global_enable && anomaly_detection_enable && ml_enable) begin
                    
                    anomaly_detectors[anom_idx].learning_cycles <= 
                        anomaly_detectors[anom_idx].learning_cycles + 1;
                    
                    // Update current values based on category
                    case (anom_idx[3:0])
                        4'h0: begin // Performance anomalies
                            anomaly_detectors[anom_idx].current_values[0] <= current_bandwidth[0];
                            anomaly_detectors[anom_idx].current_values[1] <= {16'h0, current_latency_histogram[0]};
                            anomaly_detectors[anom_idx].current_values[2] <= perf_counters[0].counter_value[31:0];
                        end
                        4'h1: begin // Thermal anomalies
                            anomaly_detectors[anom_idx].current_values[0] <= {20'h0, thermal_readings_c[0]};
                            anomaly_detectors[anom_idx].current_values[1] <= {20'h0, thermal_readings_c[1]};
                        end
                        4'h2: begin // Power anomalies
                            anomaly_detectors[anom_idx].current_values[0] <= {16'h0, power_consumption_mw[0]};
                            anomaly_detectors[anom_idx].current_values[1] <= {16'h0, power_consumption_mw[1]};
                        end
                        4'h3: begin // Protocol anomalies
                            anomaly_detectors[anom_idx].current_values[0] <= {24'h0, error_counts[0]};
                            anomaly_detectors[anom_idx].current_values[1] <= flit_header_capture.timestamp;
                        end
                        default: begin
                            // Generic system metrics
                            anomaly_detectors[anom_idx].current_values[0] <= system_performance_metrics[anom_idx % 16];
                        end
                    endcase
                    
                    // Calculate deviation scores
                    for (int i = 0; i < 8; i++) begin
                        logic [31:0] deviation = (anomaly_detectors[anom_idx].current_values[i] > 
                                                anomaly_detectors[anom_idx].baseline_values[i]) ?
                            (anomaly_detectors[anom_idx].current_values[i] - anomaly_detectors[anom_idx].baseline_values[i]) :
                            (anomaly_detectors[anom_idx].baseline_values[i] - anomaly_detectors[anom_idx].current_values[i]);
                        
                        // Scale deviation as percentage of baseline
                        if (anomaly_detectors[anom_idx].baseline_values[i] > 0) begin
                            anomaly_detectors[anom_idx].deviation_scores[i] <= 
                                (deviation * 16'd100) / anomaly_detectors[anom_idx].baseline_values[i][15:0];
                        end else begin
                            anomaly_detectors[anom_idx].deviation_scores[i] <= deviation[15:0];
                        end
                    end
                    
                    // Anomaly detection logic
                    logic [7:0] significant_deviations = 8'h0;
                    for (int i = 0; i < 8; i++) begin
                        if (anomaly_detectors[anom_idx].deviation_scores[i] > 16'd50) begin // >50% deviation
                            significant_deviations = significant_deviations + 1;
                        end
                    end
                    
                    // Anomaly probability calculation
                    anomaly_probability[anom_idx] <= {8'h0, significant_deviations} * 16'd2000; // Scale up
                    
                    // Update detection history
                    for (int i = ANOMALY_DETECTION_DEPTH-1; i > 0; i--) begin
                        anomaly_detectors[anom_idx].detection_history[i] <= 
                            anomaly_detectors[anom_idx].detection_history[i-1];
                    end
                    anomaly_detectors[anom_idx].detection_history[0] <= 
                        {24'h0, significant_deviations};
                    
                    // Confidence level adjustment
                    if (significant_deviations > 3) begin
                        anomaly_detectors[anom_idx].confidence_level <= 
                            (anomaly_detectors[anom_idx].confidence_level < 8'hF0) ?
                            anomaly_detectors[anom_idx].confidence_level + 2 : 8'hFF;
                    end else if (significant_deviations == 0) begin
                        anomaly_detectors[anom_idx].confidence_level <= 
                            (anomaly_detectors[anom_idx].confidence_level > 8'h20) ?
                            anomaly_detectors[anom_idx].confidence_level - 1 : 8'h10;
                    end
                    
                    // Model training completion
                    anomaly_detectors[anom_idx].model_trained <= 
                        (anomaly_detectors[anom_idx].learning_cycles > 32'd10000) &&
                        (anomaly_detectors[anom_idx].confidence_level > statistical_confidence_threshold);
                end
            end
        end
    endgenerate
    
    // Data Export Engine
    logic [1:0] export_state;
    logic [19:0] export_address;
    logic [31:0] export_sample_count;
    
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            export_state <= 2'b00;
            export_address <= 20'h0;
            export_data_valid <= 1'b0;
            export_complete <= 1'b0;
            export_sample_count <= 32'h0;
        end else if (obs_global_enable) begin
            
            case (export_state)
                2'b00: begin // Idle
                    if (export_request) begin
                        export_state <= 2'b01;
                        export_address <= trace_rd_ptr;
                        export_sample_count <= 32'h0;
                        export_complete <= 1'b0;
                    end
                end
                
                2'b01: begin // Reading
                    if (export_address != trace_wr_ptr) begin
                        trace_entry_t export_entry = trace_buffer[export_address];
                        
                        // Format data based on export format
                        case (export_format)
                            2'b00: begin // Raw binary
                                export_data_stream <= export_entry.data_payload;
                            end
                            2'b01: begin // CSV format (simplified)
                                export_data_stream <= {
                                    export_entry.timestamp,            // Timestamp
                                    8'h2C,                             // Comma
                                    export_entry.protocol_id, 5'h0,   // Protocol
                                    8'h2C,                             // Comma  
                                    export_entry.event_type,           // Event type
                                    8'h0A,                             // Newline
                                    192'h0                             // Padding
                                };
                            end
                            2'b10: begin // JSON format (simplified)
                                export_data_stream <= {
                                    64'h7B2274223A22,                  // {"t":"
                                    export_entry.timestamp,            // Timestamp
                                    64'h222C2270223A22,                // ","p":"
                                    export_entry.protocol_id, 5'h0,   // Protocol
                                    32'h227D2C,                       // "},
                                    88'h0                              // Padding
                                };
                            end
                            2'b11: begin // Compressed binary
                                export_data_stream <= export_entry.data_payload & 256'hFFFFFFFFFFFF0000; // Simplified compression
                            end
                        endcase
                        
                        export_data_valid <= 1'b1;
                        export_address <= (export_address == (TRACE_BUFFER_DEPTH-1)) ? 20'h0 : export_address + 1;
                        export_sample_count <= export_sample_count + 1;
                        export_state <= 2'b10;
                    end else begin
                        export_state <= 2'b11; // Complete
                    end
                end
                
                2'b10: begin // Wait for acknowledgment
                    export_data_valid <= 1'b0;
                    export_state <= 2'b01; // Continue reading
                end
                
                2'b11: begin // Complete
                    export_complete <= 1'b1;
                    export_data_valid <= 1'b0;
                    export_state <= 2'b00;
                end
            endcase
        end
    end
    
    // Debug Read Interface
    always_ff @(posedge clk_management or negedge rst_n) begin
        if (!rst_n) begin
            debug_read_data <= 256'h0;
            debug_read_valid <= 1'b0;
        end else if (debug_read_enable && (debug_read_address < TRACE_BUFFER_DEPTH)) begin
            debug_read_data <= trace_buffer[debug_read_address].data_payload;
            debug_read_valid <= 1'b1;
        end else begin
            debug_read_valid <= 1'b0;
        end
    end
    
    // Output Assignments
    assign trigger_activated = trigger_states;
    assign trace_write_pointer = trace_wr_ptr;
    assign trace_read_pointer = trace_rd_ptr;
    assign trace_sample_count = trace_samples_captured;
    assign trace_buffer_full = trace_buffer_full_flag;
    assign trace_buffer_overflow = trace_buffer_full_flag && (trace_wr_ptr == trace_rd_ptr);
    
    // Dashboard metrics
    for (genvar i = 0; i < 32; i++) begin
        assign dashboard_metrics[i] = (i < 16) ? system_performance_metrics[i] : perf_counters[i-16].counter_value[31:0];
    end
    
    for (genvar i = 0; i < NUM_LANES && i < 16; i++) begin
        assign bandwidth_utilization_percent[i] = (current_bandwidth[i] * 16'd100) / {16'h0, performance_baseline[0]};
    end
    
    for (genvar i = 0; i < 8; i++) begin
        assign latency_distribution_ns[i] = current_latency_histogram[i];
        assign protocol_efficiency_score[i] = (current_bandwidth[i % 4] > 0) ?
            ({24'h0, performance_baseline[i]} * 8'd100) / current_bandwidth[i % 4][7:0] : 8'h0;
    end
    
    assign system_load_average = {8'h0, system_health_score};
    
    // Anomaly detection outputs
    for (genvar i = 0; i < EVENT_CATEGORIES; i++) begin
        assign anomaly_detected[i] = anomaly_probability[i] > 16'd5000; // 50% threshold
        assign anomaly_severity[i] = anomaly_probability[i][15:8];
        assign anomaly_timestamp[i] = anomaly_detectors[i].detection_history[0];
        assign anomaly_signature[i] = {
            anomaly_detectors[i].deviation_scores[0],
            anomaly_detectors[i].deviation_scores[1],
            anomaly_detectors[i].deviation_scores[2],
            anomaly_detectors[i].deviation_scores[3],
            anomaly_detectors[i].current_values[0][31:0],
            anomaly_detectors[i].current_values[1][31:0],
            anomaly_detectors[i].current_values[2][31:0],
            anomaly_detectors[i].current_values[3][31:0]
        };
    end
    
    assign regression_detected = (anomaly_probability[0] > 16'd7500) && // 75% confidence
                                (system_health_score < 8'h80);
    
    // Real-time alerts
    assign performance_degradation_alert = (system_health_score < 8'h60) || (|anomaly_detected[3:0]);
    assign thermal_anomaly_alert = anomaly_detected[1] && (anomaly_severity[1] > 8'hC0);
    assign power_anomaly_alert = anomaly_detected[2] && (anomaly_severity[2] > 8'hC0);
    assign protocol_violation_alert = anomaly_detected[3] || flit_header_capture.error_detected;
    
    // Calculate issue correlation score
    logic [7:0] correlation_count = 8'h0;
    for (int i = 0; i < EVENT_CATEGORIES; i++) begin
        if (anomaly_detected[i]) correlation_count = correlation_count + 1;
    end
    assign issue_correlation_score = {8'h0, correlation_count};
    
    assign predictive_alert_level = (|anomaly_detected) ? 8'hFF : 
                                   (system_health_score < 8'hA0) ? 8'h80 : 8'h00;
    
    assign obs_status = {
        obs_global_enable,              // [31] Global enable
        trace_enable,                   // [30] Trace enable
        anomaly_detection_enable,       // [29] Anomaly detection
        real_time_analytics_enable,     // [28] Real-time analytics
        ml_enable,                      // [27] ML enabled
        trace_buffer_full_flag,         // [26] Buffer full
        export_complete,                // [25] Export complete
        regression_detected,            // [24] Regression detected
        system_health_score,            // [23:16] Health score
        correlation_count               // [15:8] Active anomalies
    };
    
    assign memory_utilization_percent = (trace_wr_ptr * 16'd100) / TRACE_BUFFER_DEPTH[15:0];
    assign processing_load_percent = (|trigger_states) ? 8'hFF : 8'h40; // High when triggered

endmodule