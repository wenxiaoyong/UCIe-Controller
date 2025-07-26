module ucie_stack_multiplexer
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    parameter int NUM_STACKS = 4,      // Max concurrent protocol stacks
    parameter int STACK_ID_WIDTH = 4
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Protocol Layer Interfaces (Multiple Stacks)
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] proto_tx_flit [NUM_STACKS-1:0],
    input  logic [NUM_STACKS-1:0] proto_tx_valid,
    output logic [NUM_STACKS-1:0] proto_tx_ready,
    input  logic [STACK_ID_WIDTH-1:0] proto_tx_stack_id [NUM_STACKS-1:0],
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] proto_rx_flit [NUM_STACKS-1:0],
    output logic [NUM_STACKS-1:0] proto_rx_valid,
    input  logic [NUM_STACKS-1:0] proto_rx_ready,
    
    // D2D Layer Interface (Single Stream)
    output logic [ucie_pkg::FLIT_WIDTH-1:0] d2d_tx_flit,
    output logic                d2d_tx_valid,
    input  logic                d2d_tx_ready,
    output logic [STACK_ID_WIDTH-1:0] d2d_tx_stack_id,
    
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] d2d_rx_flit,
    input  logic                d2d_rx_valid,
    output logic                d2d_rx_ready,
    input  logic [STACK_ID_WIDTH-1:0] d2d_rx_stack_id,
    
    // Stack Management
    input  logic [NUM_STACKS-1:0] stack_enable,
    input  logic [7:0]          stack_priority [NUM_STACKS-1:0],
    output logic [NUM_STACKS-1:0] stack_active,
    
    // Flow Control
    input  logic [7:0]          fc_credits [NUM_STACKS-1:0],
    output logic [7:0]          fc_consumed [NUM_STACKS-1:0],
    
    // Status
    output logic [15:0]         mux_status,
    output logic [7:0]          active_stack_count
);

    // Internal State
    logic [NUM_STACKS-1:0] stack_tx_pending;
    logic [NUM_STACKS-1:0] stack_has_credit;
    logic [$clog2(NUM_STACKS)-1:0] selected_stack;
    logic [$clog2(NUM_STACKS)-1:0] current_tx_stack;
    logic [$clog2(NUM_STACKS)-1:0] last_served_stack;
    
    // Arbitration State
    typedef enum logic [1:0] {
        ARB_IDLE,
        ARB_SERVING,
        ARB_WAIT_READY,
        ARB_ERROR
    } arb_state_t;
    
    arb_state_t arb_state, arb_next_state;
    
    // Flow Control Tracking
    logic [7:0] credit_counters [NUM_STACKS-1:0];
    logic [7:0] consumed_counters [NUM_STACKS-1:0];
    
    // Local variables for arbitration
    logic [7:0] highest_priority;
    logic [$clog2(NUM_STACKS)-1:0] priority_winner;
    logic priority_found;
    logic [$clog2(NUM_STACKS)-1:0] rr_start;
    logic rr_found;
    logic [$clog2(NUM_STACKS)-1:0] idx;
    
    // Round-Robin Arbitration Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_served_stack <= '0;
        end else if (d2d_tx_valid && d2d_tx_ready) begin
            last_served_stack <= current_tx_stack;
        end
    end
    
    // Priority-based Stack Selection with Round-Robin
    always_comb begin
        selected_stack = '0;
        stack_tx_pending = proto_tx_valid & stack_enable;
        
        // Check which stacks have credits
        for (int i = 0; i < NUM_STACKS; i++) begin
            stack_has_credit[i] = (credit_counters[i] > 0) && stack_enable[i];
        end
        
        // Priority-based selection
        highest_priority = 8'h0;
        priority_winner = '0;
        priority_found = 1'b0;
        
        for (int i = 0; i < NUM_STACKS; i++) begin
            if (stack_tx_pending[i] && stack_has_credit[i] && 
                stack_priority[i] > highest_priority) begin
                highest_priority = stack_priority[i];
                priority_winner = i[$clog2(NUM_STACKS)-1:0];
                priority_found = 1'b1;
            end
        end
        
        // Round-robin among equal priority
        if (priority_found) begin
            rr_start = ($clog2(NUM_STACKS))'(2'(last_served_stack) + 1);
            rr_found = 1'b0;
            
            // Search from last_served + 1 to NUM_STACKS-1
            for (int i = 0; i < NUM_STACKS; i++) begin
                idx = ($clog2(NUM_STACKS))'((32'(rr_start) + i) % NUM_STACKS);
                if (!rr_found && stack_tx_pending[idx] && stack_has_credit[idx] && 
                    stack_priority[idx] == highest_priority) begin
                    selected_stack = idx;
                    rr_found = 1'b1;
                end
            end
            
            if (!rr_found) begin
                selected_stack = priority_winner;
            end
        end
    end
    
    // Arbitration State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            arb_state <= ARB_IDLE;
        end else begin
            arb_state <= arb_next_state;
        end
    end
    
    always_comb begin
        arb_next_state = arb_state;
        
        case (arb_state)
            ARB_IDLE: begin
                if (|stack_tx_pending && |stack_has_credit) begin
                    arb_next_state = ARB_SERVING;
                end
            end
            
            ARB_SERVING: begin
                if (d2d_tx_valid && d2d_tx_ready) begin
                    if (|stack_tx_pending && |stack_has_credit) begin
                        arb_next_state = ARB_SERVING; // Continue serving
                    end else begin
                        arb_next_state = ARB_IDLE;
                    end
                end else if (!d2d_tx_ready) begin
                    arb_next_state = ARB_WAIT_READY;
                end
            end
            
            ARB_WAIT_READY: begin
                if (d2d_tx_ready) begin
                    arb_next_state = ARB_SERVING;
                end
            end
            
            ARB_ERROR: begin
                // Error recovery state
                arb_next_state = ARB_IDLE;
            end
            
            default: begin
                arb_next_state = ARB_IDLE;
            end
        endcase
    end
    
    // Current serving stack tracking
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_tx_stack <= '0;
        end else if ((arb_state == ARB_IDLE && arb_next_state == ARB_SERVING) ||
                     (arb_state == ARB_SERVING && (|stack_tx_pending && |stack_has_credit))) begin
            current_tx_stack <= selected_stack;
        end
    end
    
    // Flow Control Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_STACKS; i++) begin
                credit_counters[i] <= fc_credits[i];
                consumed_counters[i] <= 8'h0;
            end
        end else begin
            // Update credits and consumption
            for (int i = 0; i < NUM_STACKS; i++) begin
                // Refresh credits periodically or when new credits arrive
                if (fc_credits[i] > credit_counters[i]) begin
                    credit_counters[i] <= fc_credits[i];
                end
                
                // Consume credits when transmitting
                if (d2d_tx_valid && d2d_tx_ready && (current_tx_stack == $clog2(NUM_STACKS)'(i))) begin
                    if (credit_counters[i] > 0) begin
                        credit_counters[i] <= credit_counters[i] - 1;
                        consumed_counters[i] <= consumed_counters[i] + 1;
                    end
                end
            end
        end
    end
    
    // TX Path Output Logic
    always_comb begin
        // Default outputs
        d2d_tx_flit = '0;
        d2d_tx_valid = 1'b0;
        d2d_tx_stack_id = '0;
        proto_tx_ready = '0;
        
        if (arb_state == ARB_SERVING || arb_state == ARB_WAIT_READY) begin
            // Output selected stack's data
            d2d_tx_flit = proto_tx_flit[current_tx_stack];
            d2d_tx_valid = proto_tx_valid[current_tx_stack] && 
                          stack_has_credit[current_tx_stack];
            d2d_tx_stack_id = proto_tx_stack_id[current_tx_stack];
            
            // Ready signal to selected stack
            proto_tx_ready[current_tx_stack] = d2d_tx_ready && 
                                               stack_has_credit[current_tx_stack];
        end
    end
    
    // RX Path Demultiplexing
    always_comb begin
        // Default outputs
        for (int i = 0; i < NUM_STACKS; i++) begin
            proto_rx_flit[i] = d2d_rx_flit;
            proto_rx_valid[i] = 1'b0;
        end
        d2d_rx_ready = 1'b0;
        
        // Route based on stack ID
        if (d2d_rx_valid && (d2d_rx_stack_id < 4'(NUM_STACKS))) begin
            proto_rx_valid[d2d_rx_stack_id[1:0]] = 1'b1;
            d2d_rx_ready = proto_rx_ready[d2d_rx_stack_id[1:0]];
        end
    end
    
    // Stack Activity Tracking
    logic [NUM_STACKS-1:0] stack_tx_activity, stack_rx_activity;
    logic [7:0] activity_counters [NUM_STACKS-1:0];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stack_tx_activity <= '0;
            stack_rx_activity <= '0;
            for (int i = 0; i < NUM_STACKS; i++) begin
                activity_counters[i] <= 8'h0;
            end
        end else begin
            // Track TX activity
            for (int i = 0; i < NUM_STACKS; i++) begin
                stack_tx_activity[i] <= proto_tx_valid[i] && proto_tx_ready[i];
                stack_rx_activity[i] <= proto_rx_valid[i] && proto_rx_ready[i];
                
                if (stack_tx_activity[i] || stack_rx_activity[i]) begin
                    if (activity_counters[i] < 8'hFF) begin
                        activity_counters[i] <= activity_counters[i] + 1;
                    end
                end else if (activity_counters[i] > 0) begin
                    activity_counters[i] <= activity_counters[i] - 1;
                end
            end
        end
    end
    
    // Status Generation
    always_comb begin
        stack_active = '0;
        active_stack_count = 8'h0;
        
        for (int i = 0; i < NUM_STACKS; i++) begin
            stack_active[i] = stack_enable[i] && (activity_counters[i] > 0);
            if (stack_active[i]) begin
                active_stack_count = active_stack_count + 1;
            end
        end
        
        mux_status = {arb_state, 2'b0, active_stack_count, 4'b0};
        
        // Output consumed credits
        for (int i = 0; i < NUM_STACKS; i++) begin
            fc_consumed[i] = consumed_counters[i];
        end
    end

endmodule
