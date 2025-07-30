module ucie_cxl_protocol_engine
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter FLIT_WIDTH = 256,             // CXL flit width (68B/256B)
    parameter MAX_OUTSTANDING_REQS = 64,    // Maximum outstanding requests
    parameter ENHANCED_128G = 1,            // Enable 128 Gbps optimizations
    parameter CXL_VERSION = 2,              // CXL Version (1.1, 2.0, 3.0)
    parameter ML_OPTIMIZATION = 1           // Enable ML-based optimizations
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // Configuration
    input  logic                engine_enable,
    input  logic [7:0]          link_width,         // x8, x16, x32, x64
    input  cxl_mode_t           cxl_mode,           // I/O, Cache, Memory, All
    input  logic                ml_enable,
    
    // FDI Interface (Flit-Aware Die-to-Die)
    input  logic [FLIT_WIDTH-1:0] fdi_rx_data,
    input  ucie_flit_header_t      fdi_rx_header,
    input  logic                   fdi_rx_valid,
    output logic                   fdi_rx_ready,
    
    output logic [FLIT_WIDTH-1:0] fdi_tx_data,
    output ucie_flit_header_t      fdi_tx_header,
    output logic                   fdi_tx_valid,
    input  logic                   fdi_tx_ready,
    
    // CXL.io Interface (PCIe-compatible)
    input  logic [255:0]        cxl_io_rx_tlp,
    input  cxl_io_header_t      cxl_io_rx_header,
    input  logic                cxl_io_rx_valid,
    output logic                cxl_io_rx_ready,
    
    output logic [255:0]        cxl_io_tx_tlp,
    output cxl_io_header_t      cxl_io_tx_header,
    output logic                cxl_io_tx_valid,
    input  logic                cxl_io_tx_ready,
    
    // CXL.cache Interface
    input  logic [511:0]        cxl_cache_rx_data,
    input  cxl_cache_header_t   cxl_cache_rx_header,
    input  logic                cxl_cache_rx_valid,
    output logic                cxl_cache_rx_ready,
    
    output logic [511:0]        cxl_cache_tx_data,
    output cxl_cache_header_t   cxl_cache_tx_header,
    output logic                cxl_cache_tx_valid,
    input  logic                cxl_cache_tx_ready,
    
    // CXL.mem Interface
    input  logic [511:0]        cxl_mem_rx_data,
    input  cxl_mem_header_t     cxl_mem_rx_header,
    input  logic                cxl_mem_rx_valid,
    output logic                cxl_mem_rx_ready,
    
    output logic [511:0]        cxl_mem_tx_data,
    output cxl_mem_header_t     cxl_mem_tx_header,
    output logic                cxl_mem_tx_valid,
    input  logic                cxl_mem_tx_ready,
    
    // Multi-Protocol Arbitration
    input  logic [3:0]          io_priority_weight,
    input  logic [3:0]          cache_priority_weight,
    input  logic [3:0]          mem_priority_weight,
    output logic [1:0]          active_protocol,      // 00=I/O, 01=Cache, 10=Mem, 11=Mixed
    
    // Coherency and Memory Management
    input  logic [63:0]         coherency_domain_mask,
    input  logic                coherency_enable,
    output logic [15:0]         cache_coherency_state,
    output logic                memory_order_violation,
    
    // ML Enhancement Interface
    input  logic [7:0]          ml_cache_predictor,
    input  logic [15:0]         ml_bandwidth_allocation,
    output logic [7:0]          ml_coherency_efficiency,
    output logic [15:0]         ml_protocol_balance,
    
    // Error Handling
    output logic [15:0]         error_count,
    output logic                protocol_error,
    output logic                coherency_error,
    
    // Performance Monitoring
    output logic [31:0]         io_transactions,
    output logic [31:0]         cache_transactions,
    output logic [31:0]         mem_transactions,
    output logic [31:0]         total_bytes_transferred,
    output logic [15:0]         average_latency_cycles,
    output logic [7:0]          protocol_efficiency,
    
    // Debug and Status
    output logic [31:0]         engine_status,
    output logic [31:0]         coherency_debug
);

    // CXL Message Types
    typedef enum logic [5:0] {
        // CXL.io Messages (PCIe-compatible)
        CXL_IO_MEM_READ    = 6'b000000,
        CXL_IO_MEM_WRITE   = 6'b000001,
        CXL_IO_CFG_READ    = 6'b000010,
        CXL_IO_CFG_WRITE   = 6'b000011,
        CXL_IO_COMPLETION  = 6'b000100,
        
        // CXL.cache Messages
        CXL_CACHE_SNOOP    = 6'b010000,
        CXL_CACHE_GO       = 6'b010001,
        CXL_CACHE_GO_ERR   = 6'b010010,
        CXL_CACHE_RSP_I    = 6'b010011,
        CXL_CACHE_RSP_S    = 6'b010100,
        CXL_CACHE_RSP_E    = 6'b010101,
        CXL_CACHE_RSP_M    = 6'b010110,
        CXL_CACHE_DATA     = 6'b010111,
        CXL_CACHE_DATA_E   = 6'b011000,
        CXL_CACHE_WRITEBACK= 6'b011001,
        
        // CXL.mem Messages
        CXL_MEM_READ       = 6'b100000,
        CXL_MEM_WRITE      = 6'b100001,
        CXL_MEM_PARTIAL_WR = 6'b100010,
        CXL_MEM_BI_READ    = 6'b100011,
        CXL_MEM_BI_WRITE   = 6'b100100,
        CXL_MEM_DATA       = 6'b100101,
        CXL_MEM_DATA_RESP  = 6'b100110,
        CXL_MEM_COMP       = 6'b100111
    } cxl_message_type_t;
    
    typedef struct packed {
        logic [511:0]           data;
        logic [31:0]           timestamp;
        logic [15:0]           tag;
        logic [63:0]           address;
        logic [7:0]            length;
        cxl_message_type_t     msg_type;
        logic [2:0]            priority;
        logic                  valid;
        logic [1:0]            protocol;    // 00=I/O, 01=Cache, 10=Mem
    } cxl_transaction_t;
    
    typedef struct packed {
        logic [FLIT_WIDTH-1:0] data;
        ucie_flit_header_t     header;
        logic [31:0]          timestamp;
        logic [3:0]           priority;
        logic                 valid;
        flit_format_t         format;
        logic [1:0]           cxl_protocol;
    } cxl_flit_packet_t;
    
    // Outstanding Transaction Tracking
    typedef struct packed {
        logic [15:0]        tag;
        logic [63:0]        address;
        logic [31:0]        timestamp;
        logic [7:0]         length;
        cxl_message_type_t  msg_type;
        logic [1:0]         protocol;
        logic               valid;
        logic [2:0]         coherency_state; // I, S, E, M states
    } outstanding_req_t;
    
    outstanding_req_t outstanding_reqs [MAX_OUTSTANDING_REQS-1:0];
    logic [5:0] outstanding_count;
    logic [5:0] outstanding_wr_ptr, outstanding_rd_ptr;
    
    // Protocol-Specific Buffers
    cxl_transaction_t io_rx_buffer [8];
    cxl_transaction_t io_tx_buffer [8];
    cxl_transaction_t cache_rx_buffer [8];
    cxl_transaction_t cache_tx_buffer [8];
    cxl_transaction_t mem_rx_buffer [8];
    cxl_transaction_t mem_tx_buffer [8];
    cxl_flit_packet_t flit_rx_buffer [16];
    cxl_flit_packet_t flit_tx_buffer [16];
    
    // Buffer Pointers
    logic [2:0] io_rx_wr_ptr, io_rx_rd_ptr;
    logic [2:0] io_tx_wr_ptr, io_tx_rd_ptr;
    logic [2:0] cache_rx_wr_ptr, cache_rx_rd_ptr;
    logic [2:0] cache_tx_wr_ptr, cache_tx_rd_ptr;
    logic [2:0] mem_rx_wr_ptr, mem_rx_rd_ptr;
    logic [2:0] mem_tx_wr_ptr, mem_tx_rd_ptr;
    logic [3:0] flit_rx_wr_ptr, flit_rx_rd_ptr;
    logic [3:0] flit_tx_wr_ptr, flit_tx_rd_ptr;
    
    // Performance Counters
    logic [31:0] cycle_counter;
    logic [31:0] io_counter, cache_counter, mem_counter;
    logic [31:0] byte_counter;
    logic [31:0] latency_accumulator;
    logic [15:0] error_counter;
    
    // Protocol Arbitration State
    logic [1:0] current_protocol;
    logic [7:0] arbitration_round_robin;
    logic [15:0] protocol_bandwidth_usage [3];
    
    // Coherency Management
    logic [15:0] coherency_state_tracking;
    logic [63:0] coherent_address_range;
    logic coherency_violation_detected;
    
    // ML Enhancement State
    logic [7:0] ml_cache_efficiency;
    logic [15:0] ml_protocol_optimization;
    logic [7:0] ml_coherency_prediction;
    
    // Buffer Status Flags
    logic io_rx_full, io_rx_empty, io_tx_full, io_tx_empty;
    logic cache_rx_full, cache_rx_empty, cache_tx_full, cache_tx_empty;
    logic mem_rx_full, mem_rx_empty, mem_tx_full, mem_tx_empty;
    logic flit_rx_full, flit_rx_empty, flit_tx_full, flit_tx_empty;
    
    // Initialize buffers
    initial begin
        for (int i = 0; i < 8; i++) begin
            io_rx_buffer[i] = '0;
            io_tx_buffer[i] = '0;
            cache_rx_buffer[i] = '0;
            cache_tx_buffer[i] = '0;
            mem_rx_buffer[i] = '0;
            mem_tx_buffer[i] = '0;
        end
        
        for (int i = 0; i < 16; i++) begin
            flit_rx_buffer[i] = '0;
            flit_tx_buffer[i] = '0;
        end
        
        for (int i = 0; i < MAX_OUTSTANDING_REQS; i++) begin
            outstanding_reqs[i] = '0;
        end
    end
    
    // Global Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cycle_counter <= 32'h0;
        end else begin
            cycle_counter <= cycle_counter + 1;
        end
    end
    
    // CXL.io Reception and Processing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            io_rx_wr_ptr <= 3'h0;
            cxl_io_rx_ready <= 1'b0;
        end else if (engine_enable && (cxl_mode == CXL_IO_ONLY || cxl_mode == CXL_ALL)) begin
            cxl_io_rx_ready <= !io_rx_full;
            
            if (cxl_io_rx_valid && cxl_io_rx_ready) begin
                io_rx_buffer[io_rx_wr_ptr] <= '{
                    data: {256'h0, cxl_io_rx_tlp},
                    timestamp: cycle_counter,
                    tag: cxl_io_rx_header.tag,
                    address: cxl_io_rx_header.address,
                    length: cxl_io_rx_header.length,
                    msg_type: cxl_message_type_t'(cxl_io_rx_header.msg_type),
                    priority: cxl_io_rx_header.tc,
                    valid: 1'b1,
                    protocol: 2'b00  // I/O protocol
                };
                io_rx_wr_ptr <= io_rx_wr_ptr + 1;
                io_counter <= io_counter + 1;
            end
        end else begin
            cxl_io_rx_ready <= 1'b0;
        end
    end
    
    // CXL.cache Reception and Processing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cache_rx_wr_ptr <= 3'h0;
            cxl_cache_rx_ready <= 1'b0;
        end else if (engine_enable && (cxl_mode == CXL_CACHE_ONLY || cxl_mode == CXL_ALL)) begin
            cxl_cache_rx_ready <= !cache_rx_full;
            
            if (cxl_cache_rx_valid && cxl_cache_rx_ready) begin
                cache_rx_buffer[cache_rx_wr_ptr] <= '{
                    data: cxl_cache_rx_data,
                    timestamp: cycle_counter,
                    tag: cxl_cache_rx_header.tag,
                    address: cxl_cache_rx_header.address,
                    length: cxl_cache_rx_header.length,
                    msg_type: cxl_message_type_t'(cxl_cache_rx_header.msg_type),
                    priority: cxl_cache_rx_header.priority,
                    valid: 1'b1,
                    protocol: 2'b01  // Cache protocol
                };
                cache_rx_wr_ptr <= cache_rx_wr_ptr + 1;
                cache_counter <= cache_counter + 1;
            end
        end else begin
            cxl_cache_rx_ready <= 1'b0;
        end
    end
    
    // CXL.mem Reception and Processing
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_rx_wr_ptr <= 3'h0;
            cxl_mem_rx_ready <= 1'b0;
        end else if (engine_enable && (cxl_mode == CXL_MEM_ONLY || cxl_mode == CXL_ALL)) begin
            cxl_mem_rx_ready <= !mem_rx_full;
            
            if (cxl_mem_rx_valid && cxl_mem_rx_ready) begin
                mem_rx_buffer[mem_rx_wr_ptr] <= '{
                    data: cxl_mem_rx_data,
                    timestamp: cycle_counter,
                    tag: cxl_mem_rx_header.tag,
                    address: cxl_mem_rx_header.address,
                    length: cxl_mem_rx_header.length,
                    msg_type: cxl_message_type_t'(cxl_mem_rx_header.msg_type),
                    priority: cxl_mem_rx_header.priority,
                    valid: 1'b1,
                    protocol: 2'b10  // Memory protocol
                };
                mem_rx_wr_ptr <= mem_rx_wr_ptr + 1;
                mem_counter <= mem_counter + 1;
            end
        end else begin
            cxl_mem_rx_ready <= 1'b0;
        end
    end
    
    // Multi-Protocol Arbitration
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_protocol <= 2'b00;
            arbitration_round_robin <= 8'h0;
        end else if (engine_enable) begin
            arbitration_round_robin <= arbitration_round_robin + 1;
            
            // Priority-based arbitration with round-robin fairness
            case (arbitration_round_robin[1:0])
                2'b00: begin // I/O priority
                    if (!io_rx_empty && (io_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b00;
                    end else if (!cache_rx_empty && (cache_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b01;
                    end else if (!mem_rx_empty && (mem_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b10;
                    end
                end
                2'b01: begin // Cache priority
                    if (!cache_rx_empty && (cache_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b01;
                    end else if (!mem_rx_empty && (mem_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b10;
                    end else if (!io_rx_empty && (io_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b00;
                    end
                end
                2'b10: begin // Memory priority
                    if (!mem_rx_empty && (mem_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b10;
                    end else if (!io_rx_empty && (io_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b00;
                    end else if (!cache_rx_empty && (cache_priority_weight > 4'h0)) begin
                        current_protocol <= 2'b01;
                    end
                end
                default: begin
                    // Weighted priority based on ML prediction
                    if (ML_OPTIMIZATION && ml_enable) begin
                        logic [7:0] io_weight = io_priority_weight * ml_bandwidth_allocation[3:0];
                        logic [7:0] cache_weight = cache_priority_weight * ml_bandwidth_allocation[7:4];
                        logic [7:0] mem_weight = mem_priority_weight * ml_bandwidth_allocation[11:8];
                        
                        if (io_weight >= cache_weight && io_weight >= mem_weight) begin
                            current_protocol <= 2'b00;
                        end else if (cache_weight >= mem_weight) begin
                            current_protocol <= 2'b01;
                        end else begin
                            current_protocol <= 2'b10;
                        end
                    end
                end
            endcase
        end
    end
    
    // CXL Transaction to UCIe Flit Conversion
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            io_rx_rd_ptr <= 3'h0;
            cache_rx_rd_ptr <= 3'h0;
            mem_rx_rd_ptr <= 3'h0;
            flit_tx_wr_ptr <= 4'h0;
        end else if (engine_enable && !flit_tx_full) begin
            
            case (current_protocol)
                2'b00: begin // Process I/O transactions
                    if (!io_rx_empty) begin
                        cxl_transaction_t current_txn = io_rx_buffer[io_rx_rd_ptr];
                        
                        if (current_txn.valid) begin
                            cxl_flit_packet_t converted_flit;
                            
                            // Map CXL.io to UCIe flit
                            converted_flit.header.flit_type <= FLIT_PROTOCOL;
                            converted_flit.header.flit_format <= FLIT_68B_STD;
                            converted_flit.header.protocol_id <= PROTOCOL_CXL;
                            converted_flit.header.priority <= current_txn.priority[3:0];
                            converted_flit.data <= current_txn.data[FLIT_WIDTH-1:0];
                            converted_flit.timestamp <= current_txn.timestamp;
                            converted_flit.priority <= current_txn.priority[3:0];
                            converted_flit.valid <= 1'b1;
                            converted_flit.format <= FLIT_68B_STD;
                            converted_flit.cxl_protocol <= 2'b00;
                            
                            flit_tx_buffer[flit_tx_wr_ptr] <= converted_flit;
                            flit_tx_wr_ptr <= flit_tx_wr_ptr + 1;
                            io_rx_rd_ptr <= io_rx_rd_ptr + 1;
                        end
                    end
                end
                
                2'b01: begin // Process Cache transactions
                    if (!cache_rx_empty) begin
                        cxl_transaction_t current_txn = cache_rx_buffer[cache_rx_rd_ptr];
                        
                        if (current_txn.valid) begin
                            cxl_flit_packet_t converted_flit;
                            
                            // Map CXL.cache to UCIe flit
                            converted_flit.header.flit_type <= FLIT_PROTOCOL;
                            converted_flit.header.flit_format <= FLIT_256B_STD;
                            converted_flit.header.protocol_id <= PROTOCOL_CXL;
                            converted_flit.header.priority <= current_txn.priority[3:0];
                            converted_flit.data <= current_txn.data[FLIT_WIDTH-1:0];
                            converted_flit.timestamp <= current_txn.timestamp;
                            converted_flit.priority <= current_txn.priority[3:0];
                            converted_flit.valid <= 1'b1;
                            converted_flit.format <= FLIT_256B_STD;
                            converted_flit.cxl_protocol <= 2'b01;
                            
                            flit_tx_buffer[flit_tx_wr_ptr] <= converted_flit;
                            flit_tx_wr_ptr <= flit_tx_wr_ptr + 1;
                            cache_rx_rd_ptr <= cache_rx_rd_ptr + 1;
                            
                            // Track coherency state
                            if (coherency_enable) begin
                                case (current_txn.msg_type)
                                    CXL_CACHE_RSP_I: coherency_state_tracking[3:0] <= 4'b0001;
                                    CXL_CACHE_RSP_S: coherency_state_tracking[7:4] <= 4'b0010;
                                    CXL_CACHE_RSP_E: coherency_state_tracking[11:8] <= 4'b0100;
                                    CXL_CACHE_RSP_M: coherency_state_tracking[15:12] <= 4'b1000;
                                    default: coherency_state_tracking <= coherency_state_tracking;
                                endcase
                            end
                        end
                    end
                end
                
                2'b10: begin // Process Memory transactions
                    if (!mem_rx_empty) begin
                        cxl_transaction_t current_txn = mem_rx_buffer[mem_rx_rd_ptr];
                        
                        if (current_txn.valid) begin
                            cxl_flit_packet_t converted_flit;
                            
                            // Map CXL.mem to UCIe flit
                            converted_flit.header.flit_type <= FLIT_PROTOCOL;
                            converted_flit.header.flit_format <= FLIT_256B_STD;
                            converted_flit.header.protocol_id <= PROTOCOL_CXL;
                            converted_flit.header.priority <= current_txn.priority[3:0];
                            converted_flit.data <= current_txn.data[FLIT_WIDTH-1:0];
                            converted_flit.timestamp <= current_txn.timestamp;
                            converted_flit.priority <= current_txn.priority[3:0];
                            converted_flit.valid <= 1'b1;
                            converted_flit.format <= FLIT_256B_STD;
                            converted_flit.cxl_protocol <= 2'b10;
                            
                            flit_tx_buffer[flit_tx_wr_ptr] <= converted_flit;
                            flit_tx_wr_ptr <= flit_tx_wr_ptr + 1;
                            mem_rx_rd_ptr <= mem_rx_rd_ptr + 1;
                        end
                    end
                end
            endcase
        end
    end
    
    // FDI Transmission
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_tx_rd_ptr <= 4'h0;
            fdi_tx_valid <= 1'b0;
        end else if (engine_enable) begin
            
            if (!flit_tx_empty && fdi_tx_ready) begin
                cxl_flit_packet_t tx_flit = flit_tx_buffer[flit_tx_rd_ptr];
                
                fdi_tx_data <= tx_flit.data;
                fdi_tx_header <= tx_flit.header;
                fdi_tx_valid <= 1'b1;
                flit_tx_rd_ptr <= flit_tx_rd_ptr + 1;
                
                // Update performance counters
                byte_counter <= byte_counter + (FLIT_WIDTH / 8);
            end else begin
                fdi_tx_valid <= 1'b0;
            end
        end else begin
            fdi_tx_valid <= 1'b0;
        end
    end
    
    // ML-Enhanced Performance Optimization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ml_cache_efficiency <= 8'h80;
            ml_protocol_optimization <= 16'h8000;
            ml_coherency_prediction <= 8'h80;
        end else if (ML_OPTIMIZATION && ml_enable && engine_enable) begin
            
            // Calculate cache efficiency
            if (cache_counter > 0) begin
                logic [15:0] cache_hit_rate = (coherency_state_tracking[7:4] + 
                                             coherency_state_tracking[11:8] + 
                                             coherency_state_tracking[15:12]) * 16'd256 / cache_counter[15:0];
                ml_cache_efficiency <= cache_hit_rate[7:0];
            end
            
            // Protocol balance optimization
            logic [31:0] total_transactions = io_counter + cache_counter + mem_counter;
            if (total_transactions > 0) begin
                logic [15:0] io_ratio = (io_counter * 16'd256) / total_transactions[15:0];
                logic [15:0] cache_ratio = (cache_counter * 16'd256) / total_transactions[15:0];
                logic [15:0] mem_ratio = (mem_counter * 16'd256) / total_transactions[15:0];
                
                ml_protocol_optimization <= {io_ratio[7:4], cache_ratio[7:4], mem_ratio[7:4], 4'h0};
            end
            
            // Coherency prediction based on access patterns
            if (coherency_enable) begin
                logic [7:0] coherency_violations = coherency_violation_detected ? 8'hFF : 8'h00;
                ml_coherency_prediction <= (ml_coherency_prediction + coherency_violations) >> 1;
            end
        end
    end
    
    // Coherency Management and Violation Detection
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            coherency_violation_detected <= 1'b0;
            coherent_address_range <= 64'h0;
        end else if (coherency_enable && engine_enable) begin
            
            // Simple coherency violation detection
            if (cache_rx_wr_ptr != cache_rx_rd_ptr && mem_rx_wr_ptr != mem_rx_rd_ptr) begin
                cxl_transaction_t cache_txn = cache_rx_buffer[cache_rx_rd_ptr];
                cxl_transaction_t mem_txn = mem_rx_buffer[mem_rx_rd_ptr];
                
                // Check for address conflicts
                if ((cache_txn.address & coherency_domain_mask) == 
                    (mem_txn.address & coherency_domain_mask)) begin
                    coherency_violation_detected <= 1'b1;
                    error_counter <= error_counter + 1;
                end else begin
                    coherency_violation_detected <= 1'b0;
                end
            end
        end
    end
    
    // Buffer Status Logic
    always_comb begin
        io_rx_full = (io_rx_wr_ptr + 1) == io_rx_rd_ptr;
        io_rx_empty = (io_rx_wr_ptr == io_rx_rd_ptr);
        io_tx_full = (io_tx_wr_ptr + 1) == io_tx_rd_ptr;
        io_tx_empty = (io_tx_wr_ptr == io_tx_rd_ptr);
        
        cache_rx_full = (cache_rx_wr_ptr + 1) == cache_rx_rd_ptr;
        cache_rx_empty = (cache_rx_wr_ptr == cache_rx_rd_ptr);
        cache_tx_full = (cache_tx_wr_ptr + 1) == cache_tx_rd_ptr;
        cache_tx_empty = (cache_tx_wr_ptr == cache_tx_rd_ptr);
        
        mem_rx_full = (mem_rx_wr_ptr + 1) == mem_rx_rd_ptr;
        mem_rx_empty = (mem_rx_wr_ptr == mem_rx_rd_ptr);
        mem_tx_full = (mem_tx_wr_ptr + 1) == mem_tx_rd_ptr;
        mem_tx_empty = (mem_tx_wr_ptr == mem_tx_rd_ptr);
        
        flit_rx_full = (flit_rx_wr_ptr + 1) == flit_rx_rd_ptr;
        flit_rx_empty = (flit_rx_wr_ptr == flit_rx_rd_ptr);
        flit_tx_full = (flit_tx_wr_ptr + 1) == flit_tx_rd_ptr;
        flit_tx_empty = (flit_tx_wr_ptr == flit_tx_rd_ptr);
    end
    
    // Output Assignments
    assign active_protocol = current_protocol;
    assign cache_coherency_state = coherency_state_tracking;
    assign memory_order_violation = coherency_violation_detected;
    
    assign ml_coherency_efficiency = ml_cache_efficiency;
    assign ml_protocol_balance = ml_protocol_optimization;
    
    assign error_count = error_counter;
    assign protocol_error = |{io_rx_full, cache_rx_full, mem_rx_full};
    assign coherency_error = coherency_violation_detected;
    
    assign io_transactions = io_counter;
    assign cache_transactions = cache_counter;
    assign mem_transactions = mem_counter;
    assign total_bytes_transferred = byte_counter;
    assign average_latency_cycles = (outstanding_count > 0) ? 
                                  (latency_accumulator[15:0] / outstanding_count) : 16'h0;
    assign protocol_efficiency = ml_cache_efficiency;
    
    assign engine_status = {
        engine_enable,                  // [31] Engine enabled
        cxl_mode,                      // [30:28] CXL mode
        current_protocol,              // [27:26] Current protocol
        coherency_enable,              // [25] Coherency enabled
        outstanding_count,             // [24:19] Outstanding requests
        link_width[5:0],               // [18:13] Link width
        ml_cache_efficiency[4:0],      // [12:8] Cache efficiency
        arbitration_round_robin       // [7:0] Arbitration state
    };
    
    assign coherency_debug = {
        coherency_state_tracking,      // [31:16] Coherency state
        coherent_address_range[15:0]   // [15:0] Address range
    };

endmodule