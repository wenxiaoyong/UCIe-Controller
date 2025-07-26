module ucie_crc_retry_engine
    import ucie_pkg::*;  // Import inside module to avoid global namespace pollution
#(
    // Use package parameters for standard values
    parameter int CUSTOM_BUFFER_DEPTH = ucie_pkg::RETRY_BUFFER_DEPTH,
    parameter int CUSTOM_MAX_RETRY = ucie_pkg::MAX_RETRY_COUNT
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Transmit Path
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] tx_flit_in,
    input  logic                tx_flit_valid,
    output logic                tx_flit_ready,
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] tx_flit_out,
    output logic                tx_flit_valid_out,
    input  logic                tx_flit_ready_in,
    
    // Receive Path
    input  logic [ucie_pkg::FLIT_WIDTH-1:0] rx_flit_in,
    input  logic                rx_flit_valid,
    output logic                rx_flit_ready,
    
    output logic [ucie_pkg::FLIT_WIDTH-1:0] rx_flit_out,
    output logic                rx_flit_valid_out,
    input  logic                rx_flit_ready_in,
    
    // CRC Interface
    output logic [ucie_pkg::CRC_WIDTH-1:0] tx_crc,
    input  logic [ucie_pkg::CRC_WIDTH-1:0] rx_crc,
    output logic                crc_error,
    
    // Retry Control
    input  logic                retry_request,
    output logic [7:0]          retry_sequence_num,
    output logic                retry_in_progress,
    output logic                retry_buffer_full,
    
    // Status and Counters
    output logic [15:0]         crc_error_count,
    output logic [15:0]         retry_count,
    output logic [7:0]          buffer_occupancy
);

    // Retry Buffer Management
    logic [ucie_pkg::FLIT_WIDTH-1:0] retry_buffer [CUSTOM_BUFFER_DEPTH-1:0];
    logic [7:0] retry_seq_nums [CUSTOM_BUFFER_DEPTH-1:0];
    logic [31:0] retry_timestamps [CUSTOM_BUFFER_DEPTH-1:0];
    logic [CUSTOM_BUFFER_DEPTH-1:0] buffer_valid;
    
    // Buffer Pointers
    logic [$clog2(CUSTOM_BUFFER_DEPTH)-1:0] wr_ptr, rd_ptr;
    logic [$clog2(CUSTOM_BUFFER_DEPTH):0] buffer_count;
    
    // Sequence Numbers
    logic [7:0] tx_seq_num, rx_seq_num_expected;
    logic [7:0] last_acked_seq_num;
    
    // CRC Calculation
    logic [ucie_pkg::CRC_WIDTH-1:0] calculated_tx_crc, calculated_rx_crc;
    logic crc_calc_valid;
    
    // Retry State Management
    typedef enum logic [2:0] {
        RETRY_IDLE,
        RETRY_REQUESTED,
        RETRY_IN_PROGRESS,
        RETRY_COMPLETE,
        RETRY_TIMEOUT,
        RETRY_ERROR
    } retry_state_t;
    
    retry_state_t retry_state, retry_next_state;
    logic [3:0] current_retry_count;
    logic [31:0] retry_timer;
    logic retry_timeout;
    
    // Error Counters
    logic [15:0] crc_err_counter, retry_counter;
    
    // Buffer Management Logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
            buffer_count <= '0;
            buffer_valid <= '0;
        end else begin
            // Write to buffer when transmitting
            if (tx_flit_valid && tx_flit_ready && tx_flit_ready_in) begin
                retry_buffer[wr_ptr] <= tx_flit_in;
                retry_seq_nums[wr_ptr] <= tx_seq_num;
                retry_timestamps[wr_ptr] <= retry_timer;
                buffer_valid[wr_ptr] <= 1'b1;
                
                if (wr_ptr == $clog2(CUSTOM_BUFFER_DEPTH)'(CUSTOM_BUFFER_DEPTH-1)) begin
                    wr_ptr <= '0;
                end else begin
                    wr_ptr <= wr_ptr + 1;
                end
                
                if (buffer_count < ($clog2(CUSTOM_BUFFER_DEPTH)+1)'(CUSTOM_BUFFER_DEPTH)) begin
                    buffer_count <= buffer_count + 1;
                end
            end
            
            // Remove from buffer when acknowledged
            if (last_acked_seq_num != rx_seq_num_expected) begin
                // Find and invalidate acknowledged entries
                for (int i = 0; i < CUSTOM_BUFFER_DEPTH; i++) begin
                    if (buffer_valid[i] && 
                        (retry_seq_nums[i] <= last_acked_seq_num)) begin
                        buffer_valid[i] <= 1'b0;
                        if (buffer_count > 0) begin
                            buffer_count <= buffer_count - 1;
                        end
                    end
                end
            end
        end
    end
    
    // Sequence Number Management  
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_seq_num <= 8'h0;
            rx_seq_num_expected <= 8'h0;
            last_acked_seq_num <= 8'hFF; // Initialize to max to avoid false matches
        end else begin
            // Increment TX sequence number for each transmitted flit
            if (tx_flit_valid && tx_flit_ready && tx_flit_ready_in) begin
                tx_seq_num <= tx_seq_num + 1;
            end
            
            // Update expected RX sequence number
            if (rx_flit_valid && rx_flit_ready && !crc_error) begin
                rx_seq_num_expected <= rx_seq_num_expected + 1;
            end
            
            // Update last acknowledged sequence number (simplified - would come from remote)
            if (rx_flit_valid && rx_flit_ready) begin
                // Extract ACK info from received flit (implementation dependent)
                last_acked_seq_num <= rx_flit_in[15:8]; // Assume ACK in header
            end
        end
    end
    
    // CRC Calculation for Transmit Path
    always_comb begin
        calculated_tx_crc = calc_crc32(32'hFFFFFFFF, tx_flit_in, 8'd32); // 256 bits = 32 bytes
    end
    
    // CRC Calculation for Receive Path
    always_comb begin
        calculated_rx_crc = calc_crc32(32'hFFFFFFFF, rx_flit_in, 8'd32);
    end
    
    // CRC Error Detection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_error <= 1'b0;
            crc_err_counter <= 16'h0;
        end else begin
            if (rx_flit_valid && rx_flit_ready) begin
                crc_error <= (calculated_rx_crc != rx_crc);
                if (calculated_rx_crc != rx_crc) begin
                    crc_err_counter <= crc_err_counter + 1;
                end
            end else begin
                crc_error <= 1'b0;
            end
        end
    end
    
    // Retry State Machine
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            retry_state <= RETRY_IDLE;
            retry_timer <= 32'h0;
        end else begin
            retry_state <= retry_next_state;
            retry_timer <= retry_timer + 1;
        end
    end
    
    // Retry State Logic
    always_comb begin
        retry_next_state = retry_state;
        retry_timeout = (retry_timer > 32'd10000); // 10us timeout at 1GHz
        
        case (retry_state)
            RETRY_IDLE: begin
                if (retry_request || crc_error) begin
                    retry_next_state = RETRY_REQUESTED;
                end
            end
            
            RETRY_REQUESTED: begin
                if (current_retry_count >= 4'(CUSTOM_MAX_RETRY)) begin
                    retry_next_state = RETRY_ERROR;
                end else begin
                    retry_next_state = RETRY_IN_PROGRESS;
                end
            end
            
            RETRY_IN_PROGRESS: begin
                if (retry_timeout) begin
                    retry_next_state = RETRY_TIMEOUT;
                end else if (tx_flit_valid_out && tx_flit_ready_in) begin
                    retry_next_state = RETRY_COMPLETE;
                end
            end
            
            RETRY_COMPLETE: begin
                retry_next_state = RETRY_IDLE;
            end
            
            RETRY_TIMEOUT: begin
                if (current_retry_count >= 4'(CUSTOM_MAX_RETRY)) begin
                    retry_next_state = RETRY_ERROR;
                end else begin
                    retry_next_state = RETRY_REQUESTED;
                end
            end
            
            RETRY_ERROR: begin
                // Stay in error state until reset or external intervention
                if (retry_request) begin
                    retry_next_state = RETRY_IDLE;
                end
            end
            
            default: begin
                retry_next_state = RETRY_IDLE;
            end
        endcase
    end
    
    // Retry Counter Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_retry_count <= 4'h0;
            retry_counter <= 16'h0;
        end else begin
            case (retry_state)
                RETRY_IDLE: begin
                    if (retry_next_state == RETRY_REQUESTED) begin
                        current_retry_count <= 4'h0;
                    end
                end
                
                RETRY_REQUESTED: begin
                    if (retry_next_state == RETRY_IN_PROGRESS) begin
                        current_retry_count <= current_retry_count + 1;
                        retry_counter <= retry_counter + 1;
                    end
                end
                
                RETRY_COMPLETE: begin
                    current_retry_count <= 4'h0;
                end
                
                RETRY_ERROR: begin
                    current_retry_count <= 4'h0;
                end
                
                default: begin
                    // No change
                end
            endcase
        end
    end
    
    // Output Logic for Transmit Path
    always_comb begin
        // Default pass-through
        tx_flit_out = tx_flit_in;
        tx_flit_valid_out = tx_flit_valid;
        tx_flit_ready = tx_flit_ready_in;
        
        // During retry, output from buffer instead
        if (retry_state == RETRY_IN_PROGRESS) begin
            // Find the flit to retry based on sequence number
            tx_flit_out = retry_buffer[rd_ptr];
            tx_flit_valid_out = buffer_valid[rd_ptr];
            tx_flit_ready = 1'b0; // Don't accept new flits during retry
        end
        
        // Block transmission if buffer is full
        if (buffer_count >= ($clog2(CUSTOM_BUFFER_DEPTH)+1)'(CUSTOM_BUFFER_DEPTH)) begin
            tx_flit_ready = 1'b0;
        end
    end
    
    // Output Logic for Receive Path
    always_comb begin
        // Pass through receive path with CRC checking
        rx_flit_out = rx_flit_in;
        rx_flit_valid_out = rx_flit_valid && !crc_error;
        rx_flit_ready = rx_flit_ready_in;
    end
    
    // Status Outputs
    assign tx_crc = calculated_tx_crc;
    assign retry_sequence_num = tx_seq_num;
    assign retry_in_progress = (retry_state != RETRY_IDLE);
    assign retry_buffer_full = (buffer_count >= ($clog2(CUSTOM_BUFFER_DEPTH)+1)'(CUSTOM_BUFFER_DEPTH));
    assign crc_error_count = crc_err_counter;
    assign retry_count = retry_counter;
    assign buffer_occupancy = {{(8-$clog2(CUSTOM_BUFFER_DEPTH)-1){1'b0}}, buffer_count};

endmodule
