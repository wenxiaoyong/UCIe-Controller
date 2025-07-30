module ucie_protocol_layer
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int NUM_PROTOCOLS = 4,  // PCIe, CXL, Streaming, Management
    parameter int BUFFER_DEPTH = 16384,        // 4x deeper for 128 Gbps
    parameter int NUM_VCS = 8         // Virtual Channels
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Quarter-Rate Processing Support (128 Gbps enhancement)
    input  logic                clk_quarter_rate,   // 16 GHz quarter-rate clock
    input  logic                clk_symbol_rate,    // 64 GHz symbol rate clock
    input  logic                quarter_rate_enable,
    
    // Upper Layer Interface (per protocol)
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] ul_tx_flit [NUM_PROTOCOLS-1:0],
    input  logic [NUM_PROTOCOLS-1:0] ul_tx_valid,
    output logic [NUM_PROTOCOLS-1:0] ul_tx_ready,
    input  logic [7:0]          ul_tx_vc [NUM_PROTOCOLS-1:0],
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] ul_rx_flit [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] ul_rx_valid,
    input  logic [NUM_PROTOCOLS-1:0] ul_rx_ready,
    output logic [7:0]          ul_rx_vc [NUM_PROTOCOLS-1:0],
    
    // D2D Adapter Interface
    output logic [ucie_pkg::FLIT_WIDTH-1:0] d2d_tx_flit,
    output logic                d2d_tx_valid,
    input  logic                d2d_tx_ready,
    output logic [3:0]          d2d_tx_protocol_id,
    output logic [7:0]          d2d_tx_vc,
    
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] d2d_rx_flit,
    input  logic                d2d_rx_valid,
    output logic                d2d_rx_ready,
    input  logic [3:0]          d2d_rx_protocol_id,
    input  logic [7:0]          d2d_rx_vc,
    
    // Protocol Configuration
    input  logic [NUM_PROTOCOLS-1:0] protocol_enable,
    input  logic [7:0]          protocol_priority [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] protocol_active,
    
    // Virtual Channel Flow Control
    input  logic [7:0]          vc_credits [NUM_PROTOCOLS-1:0][NUM_VCS-1:0],
    output logic [7:0]          vc_consumed [NUM_PROTOCOLS-1:0][NUM_VCS-1:0],
    
    // Protocol-Specific Features
    input  logic                pcie_mode,          // PCIe specific mode
    input  logic [1:0]          cxl_mode,           // CXL.io, CXL.cache, CXL.mem
    input  logic [7:0]          streaming_channels, // Number of streaming channels
    input  logic                mgmt_enable,        // Management protocol enable
    
    // Performance Monitoring
    output logic [31:0]         protocol_stats [NUM_PROTOCOLS-1:0],
    output logic [15:0]         buffer_occupancy [NUM_PROTOCOLS-1:0],
    
    // Status and Debug
    output logic [31:0]         layer_status,
    output logic [15:0]         error_count
);

    // Use protocol types from package
    
    // Protocol Layer State Machine
    typedef enum logic [2:0] {
        PL_RESET,
        PL_INIT,
        PL_ACTIVE,
        PL_FLOW_CONTROL,
        PL_ERROR,
        PL_RECOVERY
    } pl_state_t;
    
    pl_state_t current_state, next_state;
    
    // Internal Buffers and Arbitration
    logic [ucie_pkg::FLIT_WIDTH-1:0] tx_buffers [NUM_PROTOCOLS-1:0][BUFFER_DEPTH-1:0];
    logic [BUFFER_DEPTH-1:0] tx_buffer_valid [NUM_PROTOCOLS-1:0];
    logic [$clog2(BUFFER_DEPTH)-1:0] tx_wr_ptr [NUM_PROTOCOLS-1:0];
    logic [$clog2(BUFFER_DEPTH)-1:0] tx_rd_ptr [NUM_PROTOCOLS-1:0];
    logic [$clog2(BUFFER_DEPTH):0] tx_buffer_count [NUM_PROTOCOLS-1:0];
    
    logic [ucie_pkg::FLIT_WIDTH-1:0] rx_buffers [NUM_PROTOCOLS-1:0][BUFFER_DEPTH-1:0];
    logic [BUFFER_DEPTH-1:0] rx_buffer_valid [NUM_PROTOCOLS-1:0];
    logic [$clog2(BUFFER_DEPTH)-1:0] rx_wr_ptr [NUM_PROTOCOLS-1:0];
    logic [$clog2(BUFFER_DEPTH)-1:0] rx_rd_ptr [NUM_PROTOCOLS-1:0];
    logic [$clog2(BUFFER_DEPTH):0] rx_buffer_count [NUM_PROTOCOLS-1:0];
    
    // Enhanced Arbitration Logic with Priority Inheritance
    logic [NUM_PROTOCOLS-1:0] tx_request;
    logic [NUM_PROTOCOLS-1:0] tx_credit_available;
    logic [NUM_PROTOCOLS-1:0] tx_ready_qualified;
    logic [$clog2(NUM_PROTOCOLS)-1:0] selected_protocol;
    logic [$clog2(NUM_PROTOCOLS)-1:0] last_served_protocol;
    logic [7:0] protocol_weights [NUM_PROTOCOLS-1:0];
    logic [7:0] base_weights [NUM_PROTOCOLS-1:0];
    logic [7:0] dynamic_weights [NUM_PROTOCOLS-1:0];
    
    // Priority Enhancement System
    logic [15:0] protocol_wait_time [NUM_PROTOCOLS-1:0];  // Track waiting time
    logic [7:0]  priority_boost [NUM_PROTOCOLS-1:0];     // Dynamic priority boost
    logic [7:0]  aging_factor [NUM_PROTOCOLS-1:0];       // Priority aging
    logic [NUM_PROTOCOLS-1:0] high_priority_mask;        // Emergency high priority
    logic [NUM_PROTOCOLS-1:0] starvation_prevention;     // Starvation detection
    
    // Virtual Channel Management with Credit Enforcement
    logic [7:0] vc_credit_counters [NUM_PROTOCOLS-1:0][NUM_VCS-1:0];
    logic [7:0] vc_consumed_counters [NUM_PROTOCOLS-1:0][NUM_VCS-1:0];
    logic [NUM_VCS-1:0] vc_available [NUM_PROTOCOLS-1:0];
    logic [NUM_PROTOCOLS-1:0] any_vc_available;
    
    // Quarter-Rate Processing Support (128 Gbps)
    logic [3:0] parallel_selection [3:0];    // 4 parallel arbiters
    logic [3:0] parallel_valid;              // Parallel valid signals
    logic [1:0] quarter_rate_phase;          // Current phase (0-3)
    logic       quarter_rate_arbitration;     // Quarter-rate mode active
    
    // Performance Counters with Enhanced Metrics
    logic [31:0] tx_flit_count [NUM_PROTOCOLS-1:0];
    logic [31:0] rx_flit_count [NUM_PROTOCOLS-1:0];
    logic [15:0] error_counters [NUM_PROTOCOLS-1:0];
    logic [31:0] arbitration_cycles [NUM_PROTOCOLS-1:0];
    logic [15:0] starvation_counter [NUM_PROTOCOLS-1:0];
    logic [15:0] priority_inversions [NUM_PROTOCOLS-1:0];
    
    // Advanced Arbitration State
    typedef enum logic [2:0] {
        ARB_IDLE,
        ARB_PRIORITY_SCAN,
        ARB_CREDIT_CHECK,
        ARB_SELECTION,
        ARB_GRANT,
        ARB_BACKPRESSURE,
        ARB_RECOVERY
    } arb_state_t;
    
    arb_state_t arb_state, arb_next_state;
    
    // Local variables for enhanced arbitration
    logic all_weights_zero;
    logic [7:0] highest_priority;
    logic [7:0] effective_priority [NUM_PROTOCOLS-1:0];
    logic selection_made;
    logic [$clog2(NUM_PROTOCOLS)-1:0] rr_start;
    logic [$clog2(NUM_PROTOCOLS)-1:0] idx;
    logic [31:0] starvation_threshold;        // Cycles before starvation declared
    logic backpressure_detected;
    
    // State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= PL_RESET;
            arb_state <= ARB_IDLE;
        end else begin
            current_state <= next_state;
            arb_state <= arb_next_state;
        end
    end
    
    // Enhanced Arbitration Initialization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize arbitration parameters
            starvation_threshold <= 32'd10000;  // 10,000 cycles starvation threshold
            quarter_rate_arbitration <= quarter_rate_enable;
            quarter_rate_phase <= 2'b00;
            backpressure_detected <= 1'b0;
            
            // Initialize priority management
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                base_weights[i] <= protocol_priority[i];
                dynamic_weights[i] <= protocol_priority[i];
                protocol_wait_time[i] <= 16'h0;
                priority_boost[i] <= 8'h0;
                aging_factor[i] <= 8'h1;
                starvation_counter[i] <= 16'h0;
                priority_inversions[i] <= 16'h0;
                arbitration_cycles[i] <= 32'h0;
            end
            
            high_priority_mask <= {NUM_PROTOCOLS{1'b0}};
            starvation_prevention <= {NUM_PROTOCOLS{1'b0}};
            
            // Initialize quarter-rate processing
            parallel_valid <= 4'b0000;
            for (int i = 0; i < 4; i++) begin
                parallel_selection[i] <= 4'h0;
            end
        end else begin
            // Update quarter-rate phase
            if (quarter_rate_arbitration) begin
                quarter_rate_phase <= quarter_rate_phase + 1;
            end
            
            // Update priority management
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                // Base weight tracking
                base_weights[i] <= protocol_priority[i];
                
                // Track waiting time for starvation prevention
                if (tx_request[i] && !ul_tx_ready[i]) begin
                    protocol_wait_time[i] <= protocol_wait_time[i] + 1;
                    arbitration_cycles[i] <= arbitration_cycles[i] + 1;
                    
                    // Starvation detection
                    if (protocol_wait_time[i] > starvation_threshold[15:0]) begin
                        starvation_prevention[i] <= 1'b1;
                        starvation_counter[i] <= starvation_counter[i] + 1;
                    end
                end else if (d2d_tx_valid && d2d_tx_ready && (selected_protocol == i)) begin
                    // Reset wait time when protocol is served
                    protocol_wait_time[i] <= 16'h0;
                    starvation_prevention[i] <= 1'b0;
                end
                
                // Priority aging - increase priority for waiting protocols
                if (protocol_wait_time[i] > 16'd1000) begin  // 1000 cycles
                    aging_factor[i] <= (aging_factor[i] < 8'h8) ? aging_factor[i] + 1 : 8'h8;
                end else begin
                    aging_factor[i] <= 8'h1;
                end
                
                // Dynamic priority boost calculation
                priority_boost[i] <= starvation_prevention[i] ? 8'hFF :  // Max boost for starvation
                                   (aging_factor[i] > 8'h4) ? 8'h20 :    // Moderate boost for aging
                                   8'h0;                                 // No boost
                
                // Calculate effective priority
                dynamic_weights[i] <= (base_weights[i] + priority_boost[i] > 8'hFF) ? 
                                    8'hFF : base_weights[i] + priority_boost[i];
                
                // High priority emergency escalation
                high_priority_mask[i] <= starvation_prevention[i] || 
                                       (protocol_priority[i] > 8'hC0); // Emergency threshold
            end
        end
    end
    
    // Local variables for state logic
    logic any_buffer_full;
    logic buffers_available;
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        any_buffer_full = 1'b0;
        buffers_available = 1'b1;
        
        case (current_state)
            PL_RESET: begin
                next_state = PL_INIT;
            end
            
            PL_INIT: begin
                if (|protocol_enable) begin
                    next_state = PL_ACTIVE;
                end
            end
            
            PL_ACTIVE: begin
                // Check for flow control or error conditions
                for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                    if (tx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH) || 
                        rx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH)) begin
                        any_buffer_full = 1'b1;
                    end
                end
                
                if (any_buffer_full) begin
                    next_state = PL_FLOW_CONTROL;
                end
            end
            
            PL_FLOW_CONTROL: begin
                // Return to active when buffers have space
                for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                    if (tx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-4) || 
                        rx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-4)) begin
                        buffers_available = 1'b0;
                    end
                end
                
                if (buffers_available) begin
                    next_state = PL_ACTIVE;
                end
            end
            
            PL_ERROR: begin
                next_state = PL_RECOVERY;
            end
            
            PL_RECOVERY: begin
                next_state = PL_INIT;
            end
            
            default: begin
                next_state = PL_RESET;
            end
        endcase
    end
    
    // TX Buffer Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                tx_wr_ptr[i] <= '0;
                tx_rd_ptr[i] <= '0;
                tx_buffer_count[i] <= '0;
                tx_buffer_valid[i] <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                // Write to buffer
                if (ul_tx_valid[i] && ul_tx_ready[i] && protocol_enable[i]) begin
                    tx_buffers[i][tx_wr_ptr[i]] <= ul_tx_flit[i];
                    tx_buffer_valid[i][tx_wr_ptr[i]] <= 1'b1;
                    
                    if (tx_wr_ptr[i] == $clog2(BUFFER_DEPTH)'(BUFFER_DEPTH-1)) begin
                        tx_wr_ptr[i] <= '0;
                    end else begin
                        tx_wr_ptr[i] <= tx_wr_ptr[i] + 1;
                    end
                    
                    if (tx_buffer_count[i] < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH)) begin
                        tx_buffer_count[i] <= tx_buffer_count[i] + 1;
                    end
                end
                
                // Read from buffer
                if (d2d_tx_valid && d2d_tx_ready && (selected_protocol == $clog2(NUM_PROTOCOLS)'(i))) begin
                    tx_buffer_valid[i][tx_rd_ptr[i]] <= 1'b0;
                    
                    if (tx_rd_ptr[i] == $clog2(BUFFER_DEPTH)'(BUFFER_DEPTH-1)) begin
                        tx_rd_ptr[i] <= '0;
                    end else begin
                        tx_rd_ptr[i] <= tx_rd_ptr[i] + 1;
                    end
                    
                    if (tx_buffer_count[i] > 0) begin
                        tx_buffer_count[i] <= tx_buffer_count[i] - 1;
                    end
                end
            end
        end
    end
    
    // RX Buffer Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                rx_wr_ptr[i] <= '0;
                rx_rd_ptr[i] <= '0;
                rx_buffer_count[i] <= '0;
                rx_buffer_valid[i] <= '0;
            end
        end else begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                // Write to buffer
                if (d2d_rx_valid && d2d_rx_ready && (d2d_rx_protocol_id == 4'(i))) begin
                    rx_buffers[i][rx_wr_ptr[i]] <= d2d_rx_flit;
                    rx_buffer_valid[i][rx_wr_ptr[i]] <= 1'b1;
                    
                    if (rx_wr_ptr[i] == $clog2(BUFFER_DEPTH)'(BUFFER_DEPTH-1)) begin
                        rx_wr_ptr[i] <= '0;
                    end else begin
                        rx_wr_ptr[i] <= rx_wr_ptr[i] + 1;
                    end
                    
                    if (rx_buffer_count[i] < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH)) begin
                        rx_buffer_count[i] <= rx_buffer_count[i] + 1;
                    end
                end
                
                // Read from buffer
                if (ul_rx_valid[i] && ul_rx_ready[i]) begin
                    rx_buffer_valid[i][rx_rd_ptr[i]] <= 1'b0;
                    
                    if (rx_rd_ptr[i] == $clog2(BUFFER_DEPTH)'(BUFFER_DEPTH-1)) begin
                        rx_rd_ptr[i] <= '0;
                    end else begin
                        rx_rd_ptr[i] <= rx_rd_ptr[i] + 1;
                    end
                    
                    if (rx_buffer_count[i] > 0) begin
                        rx_buffer_count[i] <= rx_buffer_count[i] - 1;
                    end
                end
            end
        end
    end
    
    // Enhanced Arbitration State Machine
    always_comb begin
        arb_next_state = arb_state;
        
        case (arb_state)
            ARB_IDLE: begin
                if (|tx_request) begin
                    arb_next_state = ARB_PRIORITY_SCAN;
                end
            end
            
            ARB_PRIORITY_SCAN: begin
                arb_next_state = ARB_CREDIT_CHECK;
            end
            
            ARB_CREDIT_CHECK: begin
                if (|tx_credit_available) begin
                    arb_next_state = ARB_SELECTION;
                end else begin
                    arb_next_state = ARB_BACKPRESSURE;
                end
            end
            
            ARB_SELECTION: begin
                if (selection_made) begin
                    arb_next_state = ARB_GRANT;
                end else begin
                    arb_next_state = ARB_RECOVERY;
                end
            end
            
            ARB_GRANT: begin
                if (d2d_tx_ready) begin
                    arb_next_state = ARB_IDLE;
                end
            end
            
            ARB_BACKPRESSURE: begin
                if (|tx_credit_available) begin
                    arb_next_state = ARB_SELECTION;
                end else begin
                    arb_next_state = ARB_IDLE;
                end
            end
            
            ARB_RECOVERY: begin
                arb_next_state = ARB_IDLE;
            end
            
            default: arb_next_state = ARB_IDLE;
        endcase
    end
    
    // Enhanced Weighted Round-Robin with Priority Inheritance
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_served_protocol <= '0;
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                protocol_weights[i] <= protocol_priority[i];
            end
        end else begin
            // Update weights with dynamic priorities
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                protocol_weights[i] <= dynamic_weights[i];
            end
            
            // Update last served when a transmission completes
            if (d2d_tx_valid && d2d_tx_ready) begin
                last_served_protocol <= selected_protocol;
                
                // Decrement weight of served protocol (unless high priority)
                if (protocol_weights[selected_protocol] > 0 && 
                    !high_priority_mask[selected_protocol]) begin
                    protocol_weights[selected_protocol] <= 
                        protocol_weights[selected_protocol] - 1;
                end
                
                // Restore weights when all reach zero
                all_weights_zero <= 1'b1;
                for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                    if (protocol_weights[i] > 0) begin
                        all_weights_zero <= 1'b0;
                    end
                end
                
                if (all_weights_zero) begin
                    for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                        protocol_weights[i] <= dynamic_weights[i];
                    end
                end
            end
        end
    end
    
    // Enhanced Protocol Selection Logic with Credit Enforcement
    always_comb begin
        // Initialize selection variables
        tx_request = '0;
        tx_credit_available = '0;
        tx_ready_qualified = '0;
        selected_protocol = '0;
        rr_start = '0;
        idx = '0;
        
        // Virtual Channel availability check
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            vc_available[i] = '0;
            any_vc_available[i] = 1'b0;
            
            for (int j = 0; j < NUM_VCS; j++) begin
                vc_available[i][j] = (vc_credit_counters[i][j] > 0);
                if (vc_available[i][j]) begin
                    any_vc_available[i] = 1'b1;
                end
            end
        end
        
        // Generate qualified requests based on buffer status AND credit availability
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            tx_request[i] = protocol_enable[i] && 
                           tx_buffer_valid[i][tx_rd_ptr[i]] &&
                           (tx_buffer_count[i] > 0);
            
            tx_credit_available[i] = tx_request[i] && any_vc_available[i];
            
            tx_ready_qualified[i] = tx_credit_available[i] && 
                                   (arb_state == ARB_GRANT || arb_state == ARB_SELECTION);
        end
        
        // Enhanced priority-based selection with starvation prevention
        highest_priority = 8'h0;
        selection_made = 1'b0;
        
        // Calculate effective priorities including boosts
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            if (high_priority_mask[i]) begin
                effective_priority[i] = 8'hFF;  // Emergency priority
            end else if (starvation_prevention[i]) begin
                effective_priority[i] = (protocol_weights[i] + 8'h80 > 8'hFF) ? 
                                      8'hFF : protocol_weights[i] + 8'h80;
            end else begin
                effective_priority[i] = protocol_weights[i];
            end
        end
        
        // First pass: Look for emergency high priority protocols
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            if (tx_ready_qualified[i] && high_priority_mask[i]) begin
                selected_protocol = i[$clog2(NUM_PROTOCOLS)-1:0];
                selection_made = 1'b1;
                break;  // Emergency protocols get immediate service
            end
        end
        
        // Second pass: Regular priority-based selection if no emergency
        if (!selection_made) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                if (tx_ready_qualified[i] && effective_priority[i] > highest_priority) begin
                    highest_priority = effective_priority[i];
                    selected_protocol = i[$clog2(NUM_PROTOCOLS)-1:0];
                    selection_made = 1'b1;
                end
            end
            
            // Round-robin among equal priorities
            if (selection_made && highest_priority > 0) begin
                rr_start = last_served_protocol + $clog2(NUM_PROTOCOLS)'(1);
                for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                    idx = $clog2(NUM_PROTOCOLS)'((32'(rr_start) + i) % NUM_PROTOCOLS);
                    if (tx_ready_qualified[idx] && effective_priority[idx] == highest_priority) begin
                        selected_protocol = idx;
                        break;
                    end
                end
            end
        end
        
        // Quarter-rate processing support for 128 Gbps
        if (quarter_rate_arbitration && selection_made) begin
            parallel_valid[quarter_rate_phase] = 1'b1;
            parallel_selection[quarter_rate_phase] = {2'b0, selected_protocol};
        end else if (!quarter_rate_arbitration) begin
            parallel_valid = 4'b0001;  // Only use first lane in non-quarter-rate mode
            parallel_selection[0] = {2'b0, selected_protocol};
        end
        
        // Backpressure detection
        backpressure_detected = |tx_request && !|tx_credit_available;
    end
    
    // Enhanced Virtual Channel Credit Management with Flow Control
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                for (int j = 0; j < NUM_VCS; j++) begin
                    vc_credit_counters[i][j] <= vc_credits[i][j];
                    vc_consumed_counters[i][j] <= 8'h0;
                end
            end
        end else begin
            // Update credit counters with enhanced flow control
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                for (int j = 0; j < NUM_VCS; j++) begin
                    // Credit refresh and return handling
                    if (vc_credits[i][j] > vc_credit_counters[i][j]) begin
                        // Credits returned from downstream - restore them
                        vc_credit_counters[i][j] <= vc_credits[i][j];
                        
                        // Reduce consumed counter proportionally
                        if (vc_consumed_counters[i][j] > (vc_credits[i][j] - vc_credit_counters[i][j])) begin
                            vc_consumed_counters[i][j] <= vc_consumed_counters[i][j] - 
                                                        (vc_credits[i][j] - vc_credit_counters[i][j]);
                        end else begin
                            vc_consumed_counters[i][j] <= 8'h0;
                        end
                    end
                    
                    // Credit consumption with backpressure enforcement
                    if (d2d_tx_valid && d2d_tx_ready && 
                        (selected_protocol == $clog2(NUM_PROTOCOLS)'(i)) && 
                        (d2d_tx_vc == 8'(j))) begin
                        
                        // Only consume if credits are available
                        if (vc_credit_counters[i][j] > 0) begin
                            vc_credit_counters[i][j] <= vc_credit_counters[i][j] - 1;
                            vc_consumed_counters[i][j] <= vc_consumed_counters[i][j] + 1;
                        end else begin
                            // Credit violation - should not happen with proper arbitration
                            // This is a safety check and error condition
                            if (error_counters[i] < 16'hFFFF) begin
                                // Track credit violations as errors - will be handled in next section
                            end
                        end
                    end
                    
                    // Emergency credit refresh to prevent deadlock
                    // If no credits available for extended period, force refresh
                    if (protocol_wait_time[i] > starvation_threshold[15:0] && 
                        vc_credit_counters[i][j] == 0 && 
                        vc_credits[i][j] > 0) begin
                        // Emergency credit restoration
                        vc_credit_counters[i][j] <= 8'h1;  // Give at least one credit
                    end
                    
                    // Quarter-rate processing credit management
                    if (quarter_rate_arbitration) begin
                        // In quarter-rate mode, consume credits for parallel processing
                        for (int k = 0; k < 4; k++) begin
                            if (parallel_valid[k] && 
                                (parallel_selection[k][$clog2(NUM_PROTOCOLS)-1:0] == i) &&
                                (k != quarter_rate_phase)) begin  // Don't double-count current phase
                                if (vc_credit_counters[i][j] > 0) begin
                                    vc_credit_counters[i][j] <= vc_credit_counters[i][j] - 1;
                                    vc_consumed_counters[i][j] <= vc_consumed_counters[i][j] + 1;
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    // Performance Monitoring
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                tx_flit_count[i] <= 32'h0;
                rx_flit_count[i] <= 32'h0;
                error_counters[i] <= 16'h0;
            end
        end else begin
            // Count transmitted flits
            if (d2d_tx_valid && d2d_tx_ready) begin
                if (tx_flit_count[selected_protocol] < 32'hFFFFFFFF) begin
                    tx_flit_count[selected_protocol] <= 
                        tx_flit_count[selected_protocol] + 1;
                end
            end
            
            // Count received flits
            if (d2d_rx_valid && d2d_rx_ready) begin
                if (d2d_rx_protocol_id < 4'(NUM_PROTOCOLS) &&
                    rx_flit_count[$clog2(NUM_PROTOCOLS)'(d2d_rx_protocol_id)] < 32'hFFFFFFFF) begin
                    rx_flit_count[$clog2(NUM_PROTOCOLS)'(d2d_rx_protocol_id)] <= 
                        rx_flit_count[$clog2(NUM_PROTOCOLS)'(d2d_rx_protocol_id)] + 1;
                end
            end
            
            // Enhanced error tracking including credit violations
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                // Buffer overflow/underflow errors
                if ((tx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH)) ||
                    (rx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH))) begin
                    if (error_counters[i] < 16'hFFFF) begin
                        error_counters[i] <= error_counters[i] + 1;
                    end
                end
                
                // Credit violation errors
                if (d2d_tx_valid && d2d_tx_ready && (selected_protocol == i)) begin
                    logic [7:0] target_vc = d2d_tx_vc;
                    if (target_vc < 8'(NUM_VCS) && vc_credit_counters[i][target_vc] == 0) begin
                        // Credit violation detected
                        if (error_counters[i] < 16'hFFFF) begin
                            error_counters[i] <= error_counters[i] + 1;
                        end
                    end
                end
                
                // Priority inversion tracking
                logic higher_priority_waiting = 1'b0;
                for (int j = 0; j < NUM_PROTOCOLS; j++) begin
                    if (j != i && protocol_priority[j] > protocol_priority[i] && 
                        tx_request[j] && !tx_ready_qualified[j]) begin
                        higher_priority_waiting = 1'b1;
                    end
                end
                
                if (higher_priority_waiting && d2d_tx_valid && d2d_tx_ready && 
                    (selected_protocol == i)) begin
                    if (priority_inversions[i] < 16'hFFFF) begin
                        priority_inversions[i] <= priority_inversions[i] + 1;
                    end
                end
            end
        end
    end
    
    // Enhanced Output Logic with Credit-Aware Flow Control
    always_comb begin
        // Default outputs
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            ul_tx_ready[i] = 1'b0;
            ul_rx_flit[i] = '0;
            ul_rx_valid[i] = 1'b0;
            ul_rx_vc[i] = '0;
        end
        
        d2d_tx_flit = '0;
        d2d_tx_valid = 1'b0;
        d2d_tx_protocol_id = '0;
        d2d_tx_vc = '0;
        d2d_rx_ready = 1'b0;
        
        // TX Path with Credit-Aware Ready Signaling
        if (current_state == PL_ACTIVE && arb_state != ARB_BACKPRESSURE) begin
            // Enhanced ready signals considering buffer space AND credit availability
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                logic buffer_has_space = (tx_buffer_count[i] < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-1));
                logic has_vc_credits = any_vc_available[i];
                logic not_starving_others = !starvation_prevention[i] || 
                                          (protocol_priority[i] >= 8'hC0);  // High priority exempt
                
                ul_tx_ready[i] = protocol_enable[i] && 
                                buffer_has_space && 
                                has_vc_credits &&
                                not_starving_others;
            end
            
            // Output selected protocol data with arbitration state check
            if (|tx_ready_qualified && (arb_state == ARB_GRANT)) begin
                d2d_tx_flit = tx_buffers[selected_protocol][tx_rd_ptr[selected_protocol]];
                d2d_tx_valid = tx_buffer_valid[selected_protocol][tx_rd_ptr[selected_protocol]] &&
                              tx_credit_available[selected_protocol];
                d2d_tx_protocol_id = {2'b0, selected_protocol};
                d2d_tx_vc = ul_tx_vc[selected_protocol];
            end
            
            // Quarter-rate processing output
            if (quarter_rate_arbitration && (arb_state == ARB_GRANT)) begin
                // Use parallel selection for current phase
                logic [1:0] current_selection = parallel_selection[quarter_rate_phase][$clog2(NUM_PROTOCOLS)-1:0];
                if (parallel_valid[quarter_rate_phase] && 
                    current_selection < NUM_PROTOCOLS) begin
                    d2d_tx_flit = tx_buffers[current_selection][tx_rd_ptr[current_selection]];
                    d2d_tx_valid = tx_buffer_valid[current_selection][tx_rd_ptr[current_selection]] &&
                                  tx_credit_available[current_selection];
                    d2d_tx_protocol_id = {2'b0, current_selection};
                    d2d_tx_vc = ul_tx_vc[current_selection];
                end
            end
        end
        
        // RX Path with Enhanced Flow Control
        if (current_state == PL_ACTIVE) begin
            // Enhanced RX ready with protocol validation
            logic protocol_valid = (d2d_rx_protocol_id < 4'(NUM_PROTOCOLS));
            logic buffer_has_space = protocol_valid && 
                (rx_buffer_count[$clog2(NUM_PROTOCOLS)'(d2d_rx_protocol_id)] < 
                 ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-1));
            logic protocol_enabled = protocol_valid && 
                protocol_enable[$clog2(NUM_PROTOCOLS)'(d2d_rx_protocol_id)];
            
            d2d_rx_ready = protocol_valid && buffer_has_space && protocol_enabled;
            
            // Output to upper layers with enhanced VC handling
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                if (rx_buffer_valid[i][rx_rd_ptr[i]] && rx_buffer_count[i] > 0 && 
                    protocol_enable[i]) begin
                    ul_rx_flit[i] = rx_buffers[i][rx_rd_ptr[i]];
                    ul_rx_valid[i] = 1'b1;
                    
                    // Enhanced VC assignment - extract from flit header if available
                    logic [7:0] extracted_vc = rx_buffers[i][rx_rd_ptr[i]][15:8];  // Assume VC in bits [15:8]
                    ul_rx_vc[i] = (extracted_vc < 8'(NUM_VCS)) ? extracted_vc : d2d_rx_vc;
                end
            end
        end
        
        // Backpressure handling
        if (arb_state == ARB_BACKPRESSURE || backpressure_detected) begin
            // Reduce ready signals to apply backpressure
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                ul_tx_ready[i] = ul_tx_ready[i] && !starvation_prevention[i];
            end
        end
    end
    
    // Protocol Activity Tracking
    always_comb begin
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            protocol_active[i] = protocol_enable[i] && 
                                ((tx_buffer_count[i] > 0) || (rx_buffer_count[i] > 0));
        end
    end
    
    // Enhanced Status and Debug Outputs with Credit Management
    assign protocol_stats[0] = tx_flit_count[0];
    assign protocol_stats[1] = tx_flit_count[1];
    assign protocol_stats[2] = tx_flit_count[2];
    assign protocol_stats[3] = tx_flit_count[3];
    
    assign buffer_occupancy[0] = {{(16-$clog2(BUFFER_DEPTH)-1){1'b0}}, tx_buffer_count[0]};
    assign buffer_occupancy[1] = {{(16-$clog2(BUFFER_DEPTH)-1){1'b0}}, tx_buffer_count[1]};
    assign buffer_occupancy[2] = {{(16-$clog2(BUFFER_DEPTH)-1){1'b0}}, tx_buffer_count[2]};
    assign buffer_occupancy[3] = {{(16-$clog2(BUFFER_DEPTH)-1){1'b0}}, tx_buffer_count[3]};
    
    assign vc_consumed[0] = vc_consumed_counters[0];
    assign vc_consumed[1] = vc_consumed_counters[1];
    assign vc_consumed[2] = vc_consumed_counters[2];
    assign vc_consumed[3] = vc_consumed_counters[3];
    
    // Enhanced error and performance metrics
    logic [15:0] total_errors;
    logic [15:0] total_starvation_events;
    logic [15:0] total_priority_inversions;
    logic [31:0] total_arbitration_cycles;
    
    always_comb begin
        total_errors = 16'h0;
        total_starvation_events = 16'h0;
        total_priority_inversions = 16'h0;
        total_arbitration_cycles = 32'h0;
        
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            total_errors = total_errors + error_counters[i];
            total_starvation_events = total_starvation_events + starvation_counter[i];
            total_priority_inversions = total_priority_inversions + priority_inversions[i];
            total_arbitration_cycles = total_arbitration_cycles + arbitration_cycles[i];
        end
    end
    
    // Enhanced layer status with arbitration and credit state
    assign layer_status = {
        current_state,                    // [31:29] Protocol layer state
        arb_state,                       // [28:26] Arbitration state  
        quarter_rate_arbitration,        // [25]    Quarter-rate mode
        backpressure_detected,           // [24]    Backpressure condition
        selected_protocol,               // [23:22] Currently selected protocol
        protocol_active,                 // [21:18] Active protocols
        starvation_prevention,           // [17:14] Starvation prevention active
        high_priority_mask[3:0],         // [13:10] Emergency high priority
        parallel_valid,                  // [9:6]   Quarter-rate parallel valid
        1'b0,                           // [5]     Reserved
        total_errors[4:0]               // [4:0]   Error count (truncated)
    };
    
    assign error_count = total_errors;

endmodule
