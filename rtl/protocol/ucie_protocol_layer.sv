module ucie_protocol_layer
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int NUM_PROTOCOLS = 4,  // PCIe, CXL, Streaming, Management
    parameter int BUFFER_DEPTH = 32,
    parameter int NUM_VCS = 8         // Virtual Channels
) (
    input  logic                clk,
    input  logic                rst_n,
    
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
    
    // Arbitration Logic
    logic [NUM_PROTOCOLS-1:0] tx_request;
    logic [$clog2(NUM_PROTOCOLS)-1:0] selected_protocol;
    logic [$clog2(NUM_PROTOCOLS)-1:0] last_served_protocol;
    logic [7:0] protocol_weights [NUM_PROTOCOLS-1:0];
    
    // Virtual Channel Management
    logic [7:0] vc_credit_counters [NUM_PROTOCOLS-1:0][NUM_VCS-1:0];
    logic [7:0] vc_consumed_counters [NUM_PROTOCOLS-1:0][NUM_VCS-1:0];
    
    // Performance Counters
    logic [31:0] tx_flit_count [NUM_PROTOCOLS-1:0];
    logic [31:0] rx_flit_count [NUM_PROTOCOLS-1:0];
    logic [15:0] error_counters [NUM_PROTOCOLS-1:0];
    
    // Local variables for arbitration
    logic all_weights_zero;
    logic [7:0] highest_weight;
    logic selection_made;
    logic [$clog2(NUM_PROTOCOLS)-1:0] rr_start;
    logic [$clog2(NUM_PROTOCOLS)-1:0] idx;
    
    // State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= PL_RESET;
        end else begin
            current_state <= next_state;
        end
    end
    
    // Next State Logic
    always_comb begin
        next_state = current_state;
        
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
                logic any_buffer_full = 1'b0;
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
                logic buffers_available = 1'b1;
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
    
    // Weighted Round-Robin Arbitration
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_served_protocol <= '0;
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                protocol_weights[i] <= protocol_priority[i];
            end
        end else begin
            // Update weights based on priority
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                protocol_weights[i] <= protocol_priority[i];
            end
            
            // Update last served when a transmission completes
            if (d2d_tx_valid && d2d_tx_ready) begin
                last_served_protocol <= selected_protocol;
                
                // Decrement weight of served protocol
                if (protocol_weights[selected_protocol] > 0) begin
                    protocol_weights[selected_protocol] <= 
                        protocol_weights[selected_protocol] - 1;
                end
                
                // Restore weights when all reach zero
                all_weights_zero = 1'b1;
                for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                    if (protocol_weights[i] > 0) begin
                        all_weights_zero = 1'b0;
                    end
                end
                
                if (all_weights_zero) begin
                    for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                        protocol_weights[i] <= protocol_priority[i];
                    end
                end
            end
        end
    end
    
    // Protocol Selection Logic
    always_comb begin
        tx_request = '0;
        selected_protocol = '0;
        
        // Generate requests based on buffer status
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            tx_request[i] = protocol_enable[i] && 
                           tx_buffer_valid[i][tx_rd_ptr[i]] &&
                           (tx_buffer_count[i] > 0);
        end
        
        // Weighted priority selection
        highest_weight = 8'h0;
        selection_made = 1'b0;
        
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            if (tx_request[i] && protocol_weights[i] > highest_weight) begin
                highest_weight = protocol_weights[i];
                selected_protocol = i[$clog2(NUM_PROTOCOLS)-1:0];
                selection_made = 1'b1;
            end
        end
        
        // Round-robin among equal weights
        if (selection_made && highest_weight > 0) begin
            rr_start = last_served_protocol + $clog2(NUM_PROTOCOLS)'(1);
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                idx = $clog2(NUM_PROTOCOLS)'((32'(rr_start) + i) % NUM_PROTOCOLS);
                if (tx_request[idx] && protocol_weights[idx] == highest_weight) begin
                    selected_protocol = idx;
                    break;
                end
            end
        end
    end
    
    // Virtual Channel Credit Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                for (int j = 0; j < NUM_VCS; j++) begin
                    vc_credit_counters[i][j] <= vc_credits[i][j];
                    vc_consumed_counters[i][j] <= 8'h0;
                end
            end
        end else begin
            // Update credit counters
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                for (int j = 0; j < NUM_VCS; j++) begin
                    // Refresh credits
                    if (vc_credits[i][j] > vc_credit_counters[i][j]) begin
                        vc_credit_counters[i][j] <= vc_credits[i][j];
                    end
                    
                    // Consume credits on transmission
                    if (d2d_tx_valid && d2d_tx_ready && 
                        (selected_protocol == $clog2(NUM_PROTOCOLS)'(i)) && (d2d_tx_vc == 8'(j))) begin
                        if (vc_credit_counters[i][j] > 0) begin
                            vc_credit_counters[i][j] <= vc_credit_counters[i][j] - 1;
                            vc_consumed_counters[i][j] <= vc_consumed_counters[i][j] + 1;
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
            
            // Count buffer overflows and underflows
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                if ((tx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH)) ||
                    (rx_buffer_count[i] >= ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH))) begin
                    if (error_counters[i] < 16'hFFFF) begin
                        error_counters[i] <= error_counters[i] + 1;
                    end
                end
            end
        end
    end
    
    // Output Logic
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
        
        // TX Path
        if (current_state == PL_ACTIVE) begin
            // Ready signals for protocols
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                ul_tx_ready[i] = protocol_enable[i] && 
                                (tx_buffer_count[i] < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-1));
            end
            
            // Output selected protocol data
            if (|tx_request) begin
                d2d_tx_flit = tx_buffers[selected_protocol][tx_rd_ptr[selected_protocol]];
                d2d_tx_valid = tx_buffer_valid[selected_protocol][tx_rd_ptr[selected_protocol]];
                d2d_tx_protocol_id = {2'b0, selected_protocol};
                d2d_tx_vc = ul_tx_vc[selected_protocol];
            end
        end
        
        // RX Path
        if (current_state == PL_ACTIVE) begin
            d2d_rx_ready = (d2d_rx_protocol_id < 4'(NUM_PROTOCOLS)) && 
                          (rx_buffer_count[$clog2(NUM_PROTOCOLS)'(d2d_rx_protocol_id)] < ($clog2(BUFFER_DEPTH)+1)'(BUFFER_DEPTH-1));
            
            // Output to upper layers
            for (int i = 0; i < NUM_PROTOCOLS; i++) begin
                if (rx_buffer_valid[i][rx_rd_ptr[i]] && rx_buffer_count[i] > 0) begin
                    ul_rx_flit[i] = rx_buffers[i][rx_rd_ptr[i]];
                    ul_rx_valid[i] = 1'b1;
                    ul_rx_vc[i] = d2d_rx_vc; // Pass through VC from D2D
                end
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
    
    // Status and Debug Outputs
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
    
    logic [15:0] total_errors;
    always_comb begin
        total_errors = 16'h0;
        for (int i = 0; i < NUM_PROTOCOLS; i++) begin
            total_errors = total_errors + error_counters[i];
        end
    end
    
    assign layer_status = {current_state, 5'b0, selected_protocol, 
                          protocol_active, 2'b0, total_errors};
    assign error_count = total_errors;

endmodule
