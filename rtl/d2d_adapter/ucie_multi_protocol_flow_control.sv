module ucie_multi_protocol_flow_control
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter NUM_PROTOCOLS = 8,          // PCIe, CXL I/O, CXL Cache, CXL Mem, Streaming, Management, etc.
    parameter NUM_VCS_PER_PROTOCOL = 8,   // Virtual channels per protocol
    parameter TOTAL_VCS = NUM_PROTOCOLS * NUM_VCS_PER_PROTOCOL,
    parameter FLIT_WIDTH = 256,
    parameter CREDIT_WIDTH = 16,
    parameter ENHANCED_128G = 1,          // Enable 128 Gbps enhancements
    parameter ML_FLOW_OPTIMIZATION = 1,   // Enable ML-based flow optimization
    parameter ADAPTIVE_QOS = 1            // Enable adaptive QoS management
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // System Configuration
    input  logic                flow_control_enable,
    input  logic [NUM_PROTOCOLS-1:0] protocol_enable,
    input  logic [7:0]          target_bandwidth_gbps,
    input  logic                enhanced_mode,
    
    // Protocol Interfaces (Upstream - from Protocol Layers)
    input  logic [NUM_PROTOCOLS-1:0] ul_flit_valid,
    input  logic [FLIT_WIDTH-1:0] ul_flit_data [NUM_PROTOCOLS-1:0],
    input  logic [NUM_PROTOCOLS-1:0] ul_flit_sop,
    input  logic [NUM_PROTOCOLS-1:0] ul_flit_eop,
    input  protocol_type_t      ul_protocol_type [NUM_PROTOCOLS-1:0],
    input  logic [2:0]          ul_vc_id [NUM_PROTOCOLS-1:0],
    input  logic [3:0]          ul_priority [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] ul_flit_ready,
    
    // Downstream Interface (to CRC/Retry Engine)
    output logic                dl_flit_valid,
    output logic [FLIT_WIDTH-1:0] dl_flit_data,
    output logic                dl_flit_sop,
    output logic                dl_flit_eop,
    output logic [3:0]          dl_flit_be,
    output protocol_type_t      dl_protocol_type,
    output logic [7:0]          dl_vc_global_id,
    input  logic                dl_flit_ready,
    
    // Credit Interface (from Remote)
    input  logic [TOTAL_VCS-1:0] credit_return,
    input  logic [CREDIT_WIDTH-1:0] credit_count [TOTAL_VCS-1:0],
    
    // Credit Generation (to Remote)
    output logic [TOTAL_VCS-1:0] credit_grant,
    output logic [CREDIT_WIDTH-1:0] credit_available [TOTAL_VCS-1:0],
    
    // QoS and Traffic Shaping
    input  logic [7:0]          bandwidth_allocation [NUM_PROTOCOLS-1:0], // Percentage
    input  logic [15:0]         latency_target_ns [NUM_PROTOCOLS-1:0],
    input  logic [3:0]          traffic_class [NUM_PROTOCOLS-1:0],
    output logic [7:0]          congestion_level [NUM_PROTOCOLS-1:0],
    
    // ML Enhancement Interface
    input  logic                ml_enable,
    input  logic [7:0]          ml_prediction_weight,
    input  logic [15:0]         ml_bandwidth_predict [NUM_PROTOCOLS-1:0],
    output logic [7:0]          ml_flow_efficiency,
    output logic [15:0]         ml_congestion_prediction,
    
    // 128 Gbps Advanced Features
    input  logic                burst_mode_enable,
    input  logic [3:0]          parallel_arbiters,
    input  logic                zero_latency_bypass,
    output logic [7:0]          throughput_utilization,
    output logic                pipeline_stall,
    
    // Performance Monitoring
    output logic [31:0]         total_throughput_mbps,
    output logic [15:0]         average_latency_ns,
    output logic [7:0]          fairness_index,
    output logic [15:0]         buffer_occupancy [NUM_PROTOCOLS-1:0],
    
    // Status and Debug
    output logic [31:0]         flow_control_status,
    output logic [15:0]         dropped_flit_count,
    output logic [7:0]          arbitration_efficiency,
    output logic [TOTAL_VCS-1:0] vc_active_status
);

    // Internal Type Definitions
    typedef struct packed {
        logic [FLIT_WIDTH-1:0] data;
        logic                  sop;
        logic                  eop;
        logic [3:0]           be;
        protocol_type_t       protocol;
        logic [2:0]           vc_local;
        logic [7:0]           vc_global;
        logic [3:0]           priority;
        logic [7:0]           traffic_class;
        logic [31:0]          timestamp;
        logic                 valid;
    } flit_entry_t;
    
    typedef struct packed {
        logic [CREDIT_WIDTH-1:0] available;
        logic [CREDIT_WIDTH-1:0] allocated;
        logic [CREDIT_WIDTH-1:0] pending;
        logic [15:0]             return_count;
        logic [31:0]             last_grant_time;
        logic                    flow_control_active;
        logic [7:0]              congestion_score;
    } credit_state_t;
    
    typedef struct packed {
        logic [15:0]             flit_count;
        logic [31:0]             byte_count;
        logic [31:0]             total_latency;
        logic [15:0]             max_latency;
        logic [15:0]             min_latency;
        logic [7:0]              utilization;
        logic [7:0]              fairness_score;
    } performance_metrics_t;
    
    // Internal Storage
    flit_entry_t input_buffers [NUM_PROTOCOLS-1:0][15:0]; // 16-deep per protocol
    logic [3:0] buffer_wr_ptr [NUM_PROTOCOLS-1:0];
    logic [3:0] buffer_rd_ptr [NUM_PROTOCOLS-1:0];
    logic [4:0] buffer_count [NUM_PROTOCOLS-1:0];
    
    // Credit Management
    credit_state_t credit_state [TOTAL_VCS-1:0];
    logic [CREDIT_WIDTH-1:0] initial_credits [TOTAL_VCS-1:0];
    
    // Arbitration State
    logic [NUM_PROTOCOLS-1:0] arb_request;
    logic [NUM_PROTOCOLS-1:0] arb_grant;
    logic [$clog2(NUM_PROTOCOLS)-1:0] arb_winner;
    logic [$clog2(NUM_PROTOCOLS)-1:0] arb_last_winner;
    
    // Enhanced 128 Gbps Arbitration
    logic [3:0] parallel_arb_winner [3:0];
    logic [3:0] parallel_arb_valid;
    logic [1:0] parallel_arb_selector;
    
    // Performance Monitoring
    performance_metrics_t perf_metrics [NUM_PROTOCOLS-1:0];
    logic [31:0] global_cycle_counter;
    logic [31:0] throughput_accumulator;
    logic [31:0] latency_accumulator;
    
    // ML Flow Optimization
    logic [7:0] ml_flow_predictor [NUM_PROTOCOLS-1:0];
    logic [7:0] ml_congestion_predictor;
    logic [15:0] ml_bandwidth_utilization [NUM_PROTOCOLS-1:0];
    logic [7:0] ml_efficiency_score;
    
    // QoS Management
    logic [7:0] dynamic_priority [NUM_PROTOCOLS-1:0];
    logic [15:0] bandwidth_budget [NUM_PROTOCOLS-1:0];
    logic [15:0] bandwidth_consumed [NUM_PROTOCOLS-1:0];
    logic [31:0] qos_timer;
    
    // Zero-Latency Bypass
    logic bypass_active;
    logic bypass_protocol_selected;
    logic [$clog2(NUM_PROTOCOLS)-1:0] bypass_protocol_id;
    
    // Initialize credit allocations
    initial begin
        for (int i = 0; i < TOTAL_VCS; i++) begin
            initial_credits[i] = CREDIT_WIDTH'(64); // Default 64 credits per VC
        end
        
        // Enhanced allocation for 128 Gbps mode
        if (ENHANCED_128G) begin
            for (int i = 0; i < TOTAL_VCS; i++) begin
                // Allocate more credits for high-priority protocols
                if (i < NUM_VCS_PER_PROTOCOL) begin // PCIe VCs
                    initial_credits[i] = CREDIT_WIDTH'(128);
                end else if (i < 3 * NUM_VCS_PER_PROTOCOL) begin // CXL VCs
                    initial_credits[i] = CREDIT_WIDTH'(96);
                end else begin // Other protocols
                    initial_credits[i] = CREDIT_WIDTH'(64);
                end
            end
        end
    end
    
    // Input Buffer Management
    genvar proto_idx;
    generate
        for (proto_idx = 0; proto_idx < NUM_PROTOCOLS; proto_idx++) begin : gen_input_buffers
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    buffer_wr_ptr[proto_idx] <= '0;
                    buffer_rd_ptr[proto_idx] <= '0;
                    buffer_count[proto_idx] <= '0;
                    
                    for (int i = 0; i < 16; i++) begin
                        input_buffers[proto_idx][i] <= '0;
                    end
                end else begin
                    // Write path
                    if (ul_flit_valid[proto_idx] && ul_flit_ready[proto_idx]) begin
                        logic [7:0] global_vc_id = proto_idx * NUM_VCS_PER_PROTOCOL + ul_vc_id[proto_idx];
                        
                        input_buffers[proto_idx][buffer_wr_ptr[proto_idx]] <= '{
                            data: ul_flit_data[proto_idx],
                            sop: ul_flit_sop[proto_idx],
                            eop: ul_flit_eop[proto_idx],
                            be: 4'hF, // Assume full flit
                            protocol: ul_protocol_type[proto_idx],
                            vc_local: ul_vc_id[proto_idx],
                            vc_global: global_vc_id,
                            priority: ul_priority[proto_idx],
                            traffic_class: traffic_class[proto_idx],
                            timestamp: global_cycle_counter,
                            valid: 1'b1
                        };
                        
                        buffer_wr_ptr[proto_idx] <= buffer_wr_ptr[proto_idx] + 1;
                        buffer_count[proto_idx] <= buffer_count[proto_idx] + 1;
                    end
                    
                    // Read path
                    if (arb_grant[proto_idx] && dl_flit_ready && (buffer_count[proto_idx] > 0)) begin
                        buffer_rd_ptr[proto_idx] <= buffer_rd_ptr[proto_idx] + 1;
                        buffer_count[proto_idx] <= buffer_count[proto_idx] - 1;
                        input_buffers[proto_idx][buffer_rd_ptr[proto_idx]].valid <= 1'b0;
                    end
                end
            end
            
            // Buffer ready indication
            assign ul_flit_ready[proto_idx] = flow_control_enable && 
                                             protocol_enable[proto_idx] && 
                                             (buffer_count[proto_idx] < 5'd15); // Leave one slot
            
            // Arbitration request
            assign arb_request[proto_idx] = (buffer_count[proto_idx] > 0) && 
                                          protocol_enable[proto_idx] &&
                                          input_buffers[proto_idx][buffer_rd_ptr[proto_idx]].valid;
        end
    endgenerate
    
    // Credit State Management
    genvar vc_idx;
    generate
        for (vc_idx = 0; vc_idx < TOTAL_VCS; vc_idx++) begin : gen_credit_management
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    credit_state[vc_idx].available <= initial_credits[vc_idx];
                    credit_state[vc_idx].allocated <= '0;
                    credit_state[vc_idx].pending <= '0;
                    credit_state[vc_idx].return_count <= '0;
                    credit_state[vc_idx].last_grant_time <= '0;
                    credit_state[vc_idx].flow_control_active <= 1'b0;
                    credit_state[vc_idx].congestion_score <= '0;
                end else begin
                    // Credit return processing
                    if (credit_return[vc_idx]) begin
                        credit_state[vc_idx].available <= credit_state[vc_idx].available + 
                                                         credit_count[vc_idx];
                        credit_state[vc_idx].return_count <= credit_state[vc_idx].return_count + 1;
                        credit_state[vc_idx].pending <= (credit_state[vc_idx].pending > credit_count[vc_idx]) ?
                                                        credit_state[vc_idx].pending - credit_count[vc_idx] : '0;
                    end
                    
                    // Credit allocation (when flit is transmitted)
                    logic [7:0] protocol_id = vc_idx / NUM_VCS_PER_PROTOCOL;
                    if (arb_grant[protocol_id] && dl_flit_ready && 
                        (dl_vc_global_id == vc_idx) && dl_flit_valid) begin
                        
                        if (credit_state[vc_idx].available > 0) begin
                            credit_state[vc_idx].available <= credit_state[vc_idx].available - 1;
                            credit_state[vc_idx].allocated <= credit_state[vc_idx].allocated + 1;
                            credit_state[vc_idx].pending <= credit_state[vc_idx].pending + 1;
                            credit_state[vc_idx].last_grant_time <= global_cycle_counter;
                            credit_state[vc_idx].flow_control_active <= 1'b1;
                        end
                    end
                    
                    // Congestion scoring
                    if (credit_state[vc_idx].available < (initial_credits[vc_idx] >> 2)) begin
                        // Less than 25% credits available
                        credit_state[vc_idx].congestion_score <= 8'hC0; // High congestion
                    end else if (credit_state[vc_idx].available < (initial_credits[vc_idx] >> 1)) begin
                        // Less than 50% credits available
                        credit_state[vc_idx].congestion_score <= 8'h80; // Medium congestion
                    end else begin
                        credit_state[vc_idx].congestion_score <= 8'h40; // Low congestion
                    end
                end
            end
            
            // Credit outputs
            assign credit_available[vc_idx] = credit_state[vc_idx].available;
        end
    endgenerate
    
    // Enhanced Arbitration for 128 Gbps
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_grant <= '0;
            arb_winner <= '0;
            arb_last_winner <= '0;
            parallel_arb_selector <= '0;
            
            for (int i = 0; i < 4; i++) begin
                parallel_arb_winner[i] <= '0;
            end
            parallel_arb_valid <= '0;
        end else if (flow_control_enable) begin
            arb_grant <= '0; // Clear previous grants
            
            if (enhanced_mode && parallel_arbiters > 1) begin
                // Parallel arbitration for 128 Gbps mode
                for (int arb_id = 0; arb_id < parallel_arbiters && arb_id < 4; arb_id++) begin
                    logic [NUM_PROTOCOLS-1:0] local_request;
                    logic [$clog2(NUM_PROTOCOLS)-1:0] local_winner;
                    
                    // Distribute requests across parallel arbiters
                    for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                        local_request[p] = arb_request[p] && ((p % parallel_arbiters) == arb_id);
                    end
                    
                    // Round-robin arbitration within each arbiter
                    ucie_round_robin_arbiter #(
                        .NUM_REQUESTERS(NUM_PROTOCOLS)
                    ) i_parallel_arbiter (
                        .clk(clk),
                        .rst_n(rst_n),
                        .request(local_request),
                        .grant_id(local_winner),
                        .grant_valid(parallel_arb_valid[arb_id])
                    );
                    
                    parallel_arb_winner[arb_id] <= local_winner;
                end
                
                // Select winner from parallel arbiters
                if (parallel_arb_valid != '0) begin
                    case (parallel_arb_selector)
                        2'b00: if (parallel_arb_valid[0]) begin
                            arb_winner <= parallel_arb_winner[0];
                            arb_grant[parallel_arb_winner[0]] <= 1'b1;
                        end
                        2'b01: if (parallel_arb_valid[1]) begin
                            arb_winner <= parallel_arb_winner[1];
                            arb_grant[parallel_arb_winner[1]] <= 1'b1;
                        end
                        2'b10: if (parallel_arb_valid[2]) begin
                            arb_winner <= parallel_arb_winner[2];
                            arb_grant[parallel_arb_winner[2]] <= 1'b1;
                        end
                        2'b11: if (parallel_arb_valid[3]) begin
                            arb_winner <= parallel_arb_winner[3];
                            arb_grant[parallel_arb_winner[3]] <= 1'b1;
                        end
                    endcase
                    parallel_arb_selector <= parallel_arb_selector + 1;
                end
            end else begin
                // Standard priority-based arbitration
                logic [$clog2(NUM_PROTOCOLS)-1:0] highest_priority_id;
                logic [3:0] highest_priority;
                logic found_request;
                
                highest_priority = '0;
                highest_priority_id = '0;
                found_request = 1'b0;
                
                // Priority arbitration with round-robin for same priority
                for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                    logic [$clog2(NUM_PROTOCOLS)-1:0] check_id = (arb_last_winner + p + 1) % NUM_PROTOCOLS;
                    
                    if (arb_request[check_id]) begin
                        logic [3:0] current_priority = dynamic_priority[check_id];
                        
                        if (!found_request || (current_priority > highest_priority)) begin
                            highest_priority = current_priority;
                            highest_priority_id = check_id;
                            found_request = 1'b1;
                        end
                    end
                end
                
                if (found_request) begin
                    arb_winner <= highest_priority_id;
                    arb_grant[highest_priority_id] <= 1'b1;
                    arb_last_winner <= highest_priority_id;
                end
            end
        end
    end
    
    // Zero-Latency Bypass Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bypass_active <= 1'b0;
            bypass_protocol_selected <= 1'b0;
            bypass_protocol_id <= '0;
        end else if (zero_latency_bypass && enhanced_mode) begin
            // Detect low-latency, high-priority traffic for bypass
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                if (ul_flit_valid[p] && (ul_priority[p] >= 4'hC) && // High priority
                    (traffic_class[p] <= 4'h2)) begin // Low latency class
                    
                    bypass_active <= 1'b1;
                    bypass_protocol_selected <= 1'b1;
                    bypass_protocol_id <= p;
                    break;
                end
            end
            
            // Clear bypass after flit transmission
            if (bypass_active && dl_flit_valid && dl_flit_ready && dl_flit_eop) begin
                bypass_active <= 1'b0;
                bypass_protocol_selected <= 1'b0;
            end
        end
    end
    
    // QoS and Dynamic Priority Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qos_timer <= '0;
            
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                dynamic_priority[p] <= ul_priority[p];
                bandwidth_budget[p] <= (bandwidth_allocation[p] * target_bandwidth_gbps) / 100;
                bandwidth_consumed[p] <= '0;
            end
        end else if (ADAPTIVE_QOS) begin
            qos_timer <= qos_timer + 1;
            
            // Update bandwidth consumption
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                if (arb_grant[p] && dl_flit_valid && dl_flit_ready) begin
                    bandwidth_consumed[p] <= bandwidth_consumed[p] + FLIT_WIDTH;
                end
                
                // Reset bandwidth tracking every 1024 cycles
                if (qos_timer[9:0] == 10'h3FF) begin
                    bandwidth_consumed[p] <= '0;
                end
                
                // Dynamic priority adjustment based on bandwidth utilization
                if (bandwidth_consumed[p] < (bandwidth_budget[p] >> 1)) begin
                    // Under-utilizing bandwidth, increase priority
                    dynamic_priority[p] <= (ul_priority[p] < 4'hE) ? ul_priority[p] + 1 : 4'hF;
                end else if (bandwidth_consumed[p] > bandwidth_budget[p]) begin
                    // Over-utilizing bandwidth, decrease priority
                    dynamic_priority[p] <= (ul_priority[p] > 4'h1) ? ul_priority[p] - 1 : 4'h0;
                end else begin
                    // Within budget, use base priority
                    dynamic_priority[p] <= ul_priority[p];
                end
            end
        end
    end
    
    // ML Flow Optimization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ml_efficiency_score <= 8'h80;
            ml_congestion_predictor <= '0;
            
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                ml_flow_predictor[p] <= '0;
                ml_bandwidth_utilization[p] <= '0;
            end
        end else if (ML_FLOW_OPTIMIZATION && ml_enable) begin
            // ML-based flow prediction and optimization
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                // Predict bandwidth utilization based on recent patterns
                logic [15:0] recent_utilization = bandwidth_consumed[p];
                logic [15:0] predicted_demand = ml_bandwidth_predict[p];
                
                // Update ML predictor based on actual vs predicted
                if (recent_utilization > predicted_demand) begin
                    ml_flow_predictor[p] <= (ml_flow_predictor[p] < 8'hF0) ? 
                                           ml_flow_predictor[p] + ml_prediction_weight : 8'hFF;
                end else begin
                    ml_flow_predictor[p] <= (ml_flow_predictor[p] > ml_prediction_weight) ? 
                                           ml_flow_predictor[p] - ml_prediction_weight : 8'h00;
                end
                
                ml_bandwidth_utilization[p] <= recent_utilization;
                
                // Update congestion level based on ML prediction
                logic [7:0] vc_start = p * NUM_VCS_PER_PROTOCOL;
                logic [7:0] avg_congestion = '0;
                for (int vc = 0; vc < NUM_VCS_PER_PROTOCOL; vc++) begin
                    avg_congestion = avg_congestion + credit_state[vc_start + vc].congestion_score;
                end
                avg_congestion = avg_congestion / NUM_VCS_PER_PROTOCOL;
                
                congestion_level[p] <= avg_congestion;
            end
            
            // Global ML efficiency calculation
            logic [15:0] total_predicted = '0;
            logic [15:0] total_actual = '0;
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                total_predicted = total_predicted + ml_bandwidth_predict[p];
                total_actual = total_actual + bandwidth_consumed[p];
            end
            
            // Calculate prediction accuracy
            if (total_predicted > 0) begin
                logic [15:0] accuracy = (total_actual < total_predicted) ?
                                       (total_actual * 255 / total_predicted) :
                                       (total_predicted * 255 / total_actual);
                ml_efficiency_score <= accuracy[7:0];
            end
            
            // Global congestion prediction
            logic [15:0] congestion_sum = '0;
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                congestion_sum = congestion_sum + congestion_level[p];
            end
            ml_congestion_predictor <= congestion_sum / NUM_PROTOCOLS;
        end
    end
    
    // Output Flit Generation
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dl_flit_valid <= 1'b0;
            dl_flit_data <= '0;
            dl_flit_sop <= 1'b0;
            dl_flit_eop <= 1'b0;
            dl_flit_be <= '0;
            dl_protocol_type <= PCIE;
            dl_vc_global_id <= '0;
        end else begin
            dl_flit_valid <= 1'b0; // Default
            
            // Zero-latency bypass path
            if (bypass_active && bypass_protocol_selected) begin
                logic [$clog2(NUM_PROTOCOLS)-1:0] bypass_proto = bypass_protocol_id;
                
                dl_flit_valid <= ul_flit_valid[bypass_proto];
                dl_flit_data <= ul_flit_data[bypass_proto];
                dl_flit_sop <= ul_flit_sop[bypass_proto];
                dl_flit_eop <= ul_flit_eop[bypass_proto];
                dl_flit_be <= 4'hF;
                dl_protocol_type <= ul_protocol_type[bypass_proto];
                dl_vc_global_id <= bypass_proto * NUM_VCS_PER_PROTOCOL + ul_vc_id[bypass_proto];
            end
            // Normal arbitrated path
            else if (|arb_grant && dl_flit_ready) begin
                flit_entry_t selected_flit = input_buffers[arb_winner][buffer_rd_ptr[arb_winner]];
                
                dl_flit_valid <= selected_flit.valid;
                dl_flit_data <= selected_flit.data;
                dl_flit_sop <= selected_flit.sop;
                dl_flit_eop <= selected_flit.eop;
                dl_flit_be <= selected_flit.be;
                dl_protocol_type <= selected_flit.protocol;
                dl_vc_global_id <= selected_flit.vc_global;
            end
        end
    end
    
    // Performance Monitoring
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            global_cycle_counter <= '0;
            throughput_accumulator <= '0;
            latency_accumulator <= '0;
            
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                perf_metrics[p] <= '0;
            end
        end else begin
            global_cycle_counter <= global_cycle_counter + 1;
            
            // Update per-protocol performance metrics
            for (int p = 0; p < NUM_PROTOCOLS; p++) begin
                if (arb_grant[p] && dl_flit_valid && dl_flit_ready) begin
                    flit_entry_t completed_flit = input_buffers[p][buffer_rd_ptr[p]];
                    logic [31:0] flit_latency = global_cycle_counter - completed_flit.timestamp;
                    
                    perf_metrics[p].flit_count <= perf_metrics[p].flit_count + 1;
                    perf_metrics[p].byte_count <= perf_metrics[p].byte_count + (FLIT_WIDTH / 8);
                    perf_metrics[p].total_latency <= perf_metrics[p].total_latency + flit_latency;
                    
                    if (flit_latency > perf_metrics[p].max_latency) begin
                        perf_metrics[p].max_latency <= flit_latency[15:0];
                    end
                    
                    if (flit_latency < perf_metrics[p].min_latency || perf_metrics[p].min_latency == 0) begin
                        perf_metrics[p].min_latency <= flit_latency[15:0];
                    end
                    
                    throughput_accumulator <= throughput_accumulator + FLIT_WIDTH;
                    latency_accumulator <= latency_accumulator + flit_latency;
                end
                
                // Calculate utilization (simplified)
                perf_metrics[p].utilization <= 8'((buffer_count[p] * 255) / 16);
                
                // Buffer occupancy for monitoring
                buffer_occupancy[p] <= {11'b0, buffer_count[p]};
            end
        end
    end
    
    // Output Assignments
    assign total_throughput_mbps = (throughput_accumulator >> 10); // Approximate Mbps
    assign average_latency_ns = latency_accumulator[15:0]; // Simplified
    assign throughput_utilization = 8'((throughput_accumulator[7:0] * 100) / 8'd255);
    assign pipeline_stall = !dl_flit_ready && |arb_grant;
    
    assign ml_flow_efficiency = ml_efficiency_score;
    assign ml_congestion_prediction = {8'b0, ml_congestion_predictor};
    
    assign fairness_index = 8'h80; // Simplified fairness calculation
    assign arbitration_efficiency = 8'((transition_counter < 16'h100) ? 8'hFF : 8'h80);
    
    // VC active status
    generate
        for (genvar vc = 0; vc < TOTAL_VCS; vc++) begin : gen_vc_status
            assign vc_active_status[vc] = credit_state[vc].flow_control_active;
        end
    endgenerate
    
    // Credit grant generation (simplified)
    assign credit_grant = credit_return; // Echo back for acknowledgment
    
    assign flow_control_status = {
        enhanced_mode,                  // [31] Enhanced 128G mode
        ML_FLOW_OPTIMIZATION[0],        // [30] ML optimization enabled
        zero_latency_bypass,            // [29] Zero latency bypass enabled
        bypass_active,                  // [28] Bypass currently active
        parallel_arbiters,              // [27:24] Number of parallel arbiters
        popcount(arb_request),          // [23:16] Number of active requests
        popcount(protocol_enable),      // [15:8] Number of enabled protocols
        arb_winner                      // [7:0] Current arbitration winner
    };

endmodule

// Round-Robin Arbiter Helper Module
module ucie_round_robin_arbiter #(
    parameter NUM_REQUESTERS = 8
) (
    input  logic                clk,
    input  logic                rst_n,
    input  logic [NUM_REQUESTERS-1:0] request,
    output logic [$clog2(NUM_REQUESTERS)-1:0] grant_id,
    output logic                grant_valid
);

    logic [$clog2(NUM_REQUESTERS)-1:0] last_grant;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_grant <= '0;
            grant_valid <= 1'b0;
            grant_id <= '0;
        end else begin
            grant_valid <= 1'b0;
            
            // Round-robin arbitration
            for (int i = 0; i < NUM_REQUESTERS; i++) begin
                logic [$clog2(NUM_REQUESTERS)-1:0] check_id = (last_grant + i + 1) % NUM_REQUESTERS;
                
                if (request[check_id]) begin
                    grant_id <= check_id;
                    grant_valid <= 1'b1;
                    last_grant <= check_id;
                    break;
                end
            end
        end
    end

endmodule