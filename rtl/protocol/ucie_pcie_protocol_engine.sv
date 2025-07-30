module ucie_pcie_protocol_engine
    import ucie_pkg::*;
    import ucie_common_pkg::*;
#(
    parameter FLIT_WIDTH = 256,             // PCIe flit width (68B/256B)
    parameter MAX_OUTSTANDING_TLPS = 64,    // Maximum outstanding TLPs
    parameter ENHANCED_128G = 1,            // Enable 128 Gbps optimizations
    parameter PCIE_GEN = 5,                 // PCIe Generation (4 or 5)
    parameter ML_OPTIMIZATION = 1           // Enable ML-based optimizations
) (
    // Clock and Reset
    input  logic                clk,
    input  logic                rst_n,
    
    // Configuration
    input  logic                engine_enable,
    input  logic [7:0]          link_width,         // x8, x16, x32, x64
    input  pcie_speed_t         pcie_speed,         // PCIe speed configuration
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
    
    // PCIe TLP Interface (to/from PCIe Root Complex/Endpoint)
    input  logic [255:0]        pcie_rx_tlp,
    input  pcie_tlp_header_t    pcie_rx_tlp_header,
    input  logic                pcie_rx_tlp_valid,
    output logic                pcie_rx_tlp_ready,
    
    output logic [255:0]        pcie_tx_tlp,
    output pcie_tlp_header_t    pcie_tx_tlp_header,
    output logic                pcie_tx_tlp_valid,
    input  logic                pcie_tx_tlp_ready,
    
    // Flow Control Interface
    input  logic [11:0]         fc_posted_header_credits,
    input  logic [15:0]         fc_posted_data_credits,
    input  logic [11:0]         fc_nonposted_header_credits,
    input  logic [15:0]         fc_nonposted_data_credits,
    input  logic [11:0]         fc_completion_header_credits,
    input  logic [15:0]         fc_completion_data_credits,
    
    output logic [11:0]         fc_posted_header_consumed,
    output logic [15:0]         fc_posted_data_consumed,
    output logic [11:0]         fc_nonposted_header_consumed,
    output logic [15:0]         fc_nonposted_data_consumed,
    output logic [11:0]         fc_completion_header_consumed,
    output logic [15:0]         fc_completion_data_consumed,
    
    // ML Enhancement Interface
    input  logic [7:0]          ml_latency_target,
    input  logic [15:0]         ml_bandwidth_prediction,
    output logic [7:0]          ml_performance_score,
    output logic [15:0]         ml_optimization_metrics,
    
    // Error Handling
    output logic [15:0]         error_count,
    output logic                tlp_error,
    output logic                flow_control_error,
    
    // Performance Monitoring
    output logic [31:0]         tlps_processed,
    output logic [31:0]         bytes_transferred,
    output logic [15:0]         average_latency_cycles,
    output logic [7:0]          bandwidth_utilization,
    
    // Debug and Status
    output logic [31:0]         engine_status,
    output logic [15:0]         debug_info
);

    // PCIe TLP Type Definitions
    typedef enum logic [4:0] {
        TLP_MEM_READ32     = 5'b00000,
        TLP_MEM_READ64     = 5'b00001,
        TLP_MEM_WRITE32    = 5'b00010,
        TLP_MEM_WRITE64    = 5'b00011,
        TLP_IO_READ        = 5'b00100,
        TLP_IO_WRITE       = 5'b00101,
        TLP_CONFIG_READ0   = 5'b00110,
        TLP_CONFIG_WRITE0  = 5'b00111,
        TLP_CONFIG_READ1   = 5'b01000,
        TLP_CONFIG_WRITE1  = 5'b01001,
        TLP_COMPLETION     = 5'b01010,
        TLP_COMPLETION_D   = 5'b01011,
        TLP_MESSAGE        = 5'b01100,
        TLP_VENDOR_TYPE0   = 5'b01101,
        TLP_VENDOR_TYPE1   = 5'b01110
    } pcie_tlp_type_t;
    
    typedef struct packed {
        logic [255:0]       data;
        pcie_tlp_header_t   header;
        logic [31:0]        timestamp;
        logic [15:0]        tag;
        logic [2:0]         traffic_class;
        logic               valid;
        pcie_tlp_type_t     tlp_type;
    } pcie_tlp_packet_t;
    
    typedef struct packed {
        logic [FLIT_WIDTH-1:0] data;
        ucie_flit_header_t     header;
        logic [31:0]          timestamp;
        logic [3:0]           priority;
        logic                 valid;
        flit_format_t         format;
    } ucie_flit_packet_t;
    
    // Outstanding TLP Tracking
    typedef struct packed {
        logic [15:0]        tag;
        logic [15:0]        requester_id;
        logic [31:0]        timestamp;
        logic [7:0]         length;
        logic               valid;
        pcie_tlp_type_t     tlp_type;
    } outstanding_tlp_t;
    
    outstanding_tlp_t outstanding_tlps [MAX_OUTSTANDING_TLPS-1:0];
    logic [5:0] outstanding_count;
    logic [5:0] outstanding_wr_ptr, outstanding_rd_ptr;
    
    // Internal Buffers
    pcie_tlp_packet_t rx_tlp_buffer [8];
    pcie_tlp_packet_t tx_tlp_buffer [8];
    ucie_flit_packet_t rx_flit_buffer [8];
    ucie_flit_packet_t tx_flit_buffer [8];
    
    // Buffer Pointers
    logic [2:0] rx_tlp_wr_ptr, rx_tlp_rd_ptr;
    logic [2:0] tx_tlp_wr_ptr, tx_tlp_rd_ptr;
    logic [2:0] rx_flit_wr_ptr, rx_flit_rd_ptr;
    logic [2:0] tx_flit_wr_ptr, tx_flit_rd_ptr;
    
    // Flow Control State
    logic [11:0] fc_ph_available, fc_nph_available, fc_cplh_available;
    logic [15:0] fc_pd_available, fc_npd_available, fc_cpld_available;
    
    // Performance Counters
    logic [31:0] cycle_counter;
    logic [31:0] tlp_counter;
    logic [31:0] byte_counter;
    logic [31:0] latency_accumulator;
    logic [15:0] error_counter;
    
    // ML Enhancement State
    logic [7:0] ml_performance_metric;
    logic [15:0] ml_bandwidth_efficiency;
    logic [7:0] ml_congestion_level;
    
    // Buffer Status
    logic rx_tlp_buffer_full, rx_tlp_buffer_empty;
    logic tx_tlp_buffer_full, tx_tlp_buffer_empty;
    logic rx_flit_buffer_full, rx_flit_buffer_empty;
    logic tx_flit_buffer_full, tx_flit_buffer_empty;
    
    // Initialize buffers
    initial begin
        for (int i = 0; i < 8; i++) begin
            rx_tlp_buffer[i] = '0;
            tx_tlp_buffer[i] = '0;
            rx_flit_buffer[i] = '0;
            tx_flit_buffer[i] = '0;
        end
        
        for (int i = 0; i < MAX_OUTSTANDING_TLPS; i++) begin
            outstanding_tlps[i] = '0;
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
    
    // PCIe TLP Reception and Buffering
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_tlp_wr_ptr <= 3'h0;
            pcie_rx_tlp_ready <= 1'b0;
        end else if (engine_enable) begin
            pcie_rx_tlp_ready <= !rx_tlp_buffer_full;
            
            if (pcie_rx_tlp_valid && pcie_rx_tlp_ready) begin
                rx_tlp_buffer[rx_tlp_wr_ptr] <= '{
                    data: pcie_rx_tlp,
                    header: pcie_rx_tlp_header,
                    timestamp: cycle_counter,
                    tag: pcie_rx_tlp_header.tag,
                    traffic_class: pcie_rx_tlp_header.tc,
                    valid: 1'b1,
                    tlp_type: pcie_tlp_type_t'(pcie_rx_tlp_header.tlp_type)
                };
                rx_tlp_wr_ptr <= rx_tlp_wr_ptr + 1;
            end
        end else begin
            pcie_rx_tlp_ready <= 1'b0;
        end
    end
    
    // FDI Reception and Buffering
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_flit_wr_ptr <= 3'h0;
            fdi_rx_ready <= 1'b0;
        end else if (engine_enable) begin
            fdi_rx_ready <= !rx_flit_buffer_full;
            
            if (fdi_rx_valid && fdi_rx_ready) begin
                rx_flit_buffer[rx_flit_wr_ptr] <= '{
                    data: fdi_rx_data,
                    header: fdi_rx_header,
                    timestamp: cycle_counter,
                    priority: fdi_rx_header.priority,
                    valid: 1'b1,
                    format: fdi_rx_header.flit_format
                };
                rx_flit_wr_ptr <= rx_flit_wr_ptr + 1;
            end
        end else begin
            fdi_rx_ready <= 1'b0;
        end
    end
    
    // PCIe TLP to UCIe Flit Conversion
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_tlp_rd_ptr <= 3'h0;
            tx_flit_wr_ptr <= 3'h0;
        end else if (engine_enable && !rx_tlp_buffer_empty && !tx_flit_buffer_full) begin
            
            pcie_tlp_packet_t current_tlp = rx_tlp_buffer[rx_tlp_rd_ptr];
            
            if (current_tlp.valid) begin
                // Convert PCIe TLP to UCIe Flit
                ucie_flit_packet_t converted_flit;
                
                // Map PCIe TLP to UCIe flit format
                case (current_tlp.tlp_type)
                    TLP_MEM_READ32, TLP_MEM_READ64: begin
                        converted_flit.header.flit_type <= FLIT_PROTOCOL;
                        converted_flit.header.flit_format <= FLIT_68B_STD;
                        converted_flit.header.protocol_id <= PROTOCOL_PCIE;
                        converted_flit.header.priority <= current_tlp.traffic_class[3:0];
                    end
                    TLP_MEM_WRITE32, TLP_MEM_WRITE64: begin
                        converted_flit.header.flit_type <= FLIT_PROTOCOL;
                        converted_flit.header.flit_format <= FLIT_256B_STD;
                        converted_flit.header.protocol_id <= PROTOCOL_PCIE;
                        converted_flit.header.priority <= current_tlp.traffic_class[3:0];
                    end
                    TLP_COMPLETION, TLP_COMPLETION_D: begin
                        converted_flit.header.flit_type <= FLIT_PROTOCOL;
                        converted_flit.header.flit_format <= FLIT_68B_STD;
                        converted_flit.header.protocol_id <= PROTOCOL_PCIE;
                        converted_flit.header.priority <= current_tlp.traffic_class[3:0];
                    end
                    default: begin
                        converted_flit.header.flit_type <= FLIT_PROTOCOL;
                        converted_flit.header.flit_format <= FLIT_68B_STD;
                        converted_flit.header.protocol_id <= PROTOCOL_PCIE;
                        converted_flit.header.priority <= 4'h4; // Default priority
                    end
                endcase
                
                // Pack TLP data into flit
                converted_flit.data <= {current_tlp.data[FLIT_WIDTH-1:0]};
                converted_flit.timestamp <= current_tlp.timestamp;
                converted_flit.priority <= current_tlp.traffic_class[3:0];
                converted_flit.valid <= 1'b1;
                converted_flit.format <= converted_flit.header.flit_format;
                
                // Store converted flit
                tx_flit_buffer[tx_flit_wr_ptr] <= converted_flit;
                tx_flit_wr_ptr <= tx_flit_wr_ptr + 1;
                rx_tlp_rd_ptr <= rx_tlp_rd_ptr + 1;
                
                // Track outstanding TLPs for non-posted requests
                if (current_tlp.tlp_type == TLP_MEM_READ32 || 
                    current_tlp.tlp_type == TLP_MEM_READ64) begin
                    
                    if (outstanding_count < MAX_OUTSTANDING_TLPS[5:0]) begin
                        outstanding_tlps[outstanding_wr_ptr] <= '{
                            tag: current_tlp.tag,
                            requester_id: current_tlp.header.requester_id,
                            timestamp: current_tlp.timestamp,
                            length: current_tlp.header.length,
                            valid: 1'b1,
                            tlp_type: current_tlp.tlp_type
                        };
                        outstanding_wr_ptr <= outstanding_wr_ptr + 1;
                        outstanding_count <= outstanding_count + 1;
                    end
                end
            end
        end
    end
    
    // UCIe Flit to PCIe TLP Conversion
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_flit_rd_ptr <= 3'h0;
            tx_tlp_wr_ptr <= 3'h0;
        end else if (engine_enable && !rx_flit_buffer_empty && !tx_tlp_buffer_full) begin
            
            ucie_flit_packet_t current_flit = rx_flit_buffer[rx_flit_rd_ptr];
            
            if (current_flit.valid && 
                current_flit.header.protocol_id == PROTOCOL_PCIE) begin
                
                // Convert UCIe Flit to PCIe TLP
                pcie_tlp_packet_t converted_tlp;
                
                // Extract TLP from flit data
                converted_tlp.data <= current_flit.data[255:0];
                converted_tlp.timestamp <= current_flit.timestamp;
                converted_tlp.traffic_class <= current_flit.priority[2:0];
                converted_tlp.valid <= 1'b1;
                
                // Reconstruct TLP header from flit
                converted_tlp.header.requester_id <= current_flit.data[127:112];
                converted_tlp.header.tag <= current_flit.data[111:96];
                converted_tlp.header.length <= current_flit.data[95:88];
                converted_tlp.header.tc <= current_flit.priority[2:0];
                converted_tlp.header.tlp_type <= current_flit.data[87:83];
                
                // Determine TLP type from flit content
                converted_tlp.tlp_type <= pcie_tlp_type_t'(current_flit.data[87:83]);
                
                // Store converted TLP
                tx_tlp_buffer[tx_tlp_wr_ptr] <= converted_tlp;
                tx_tlp_wr_ptr <= tx_tlp_wr_ptr + 1;
                rx_flit_rd_ptr <= rx_flit_rd_ptr + 1;
                
                // Handle completion matching for outstanding TLPs
                if (converted_tlp.tlp_type == TLP_COMPLETION || 
                    converted_tlp.tlp_type == TLP_COMPLETION_D) begin
                    
                    // Find and retire matching outstanding TLP
                    for (int i = 0; i < MAX_OUTSTANDING_TLPS; i++) begin
                        if (outstanding_tlps[i].valid && 
                            outstanding_tlps[i].tag == converted_tlp.tag) begin
                            
                            outstanding_tlps[i].valid <= 1'b0;
                            outstanding_count <= outstanding_count - 1;
                            
                            // Calculate latency for performance monitoring
                            logic [31:0] tlp_latency = cycle_counter - outstanding_tlps[i].timestamp;
                            latency_accumulator <= latency_accumulator + tlp_latency;
                        end
                    end
                end
            end
        end
    end
    
    // FDI Transmission
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_flit_rd_ptr <= 3'h0;
            fdi_tx_valid <= 1'b0;
        end else if (engine_enable) begin
            
            if (!tx_flit_buffer_empty && fdi_tx_ready) begin
                ucie_flit_packet_t tx_flit = tx_flit_buffer[tx_flit_rd_ptr];
                
                fdi_tx_data <= tx_flit.data;
                fdi_tx_header <= tx_flit.header;
                fdi_tx_valid <= 1'b1;
                tx_flit_rd_ptr <= tx_flit_rd_ptr + 1;
            end else begin
                fdi_tx_valid <= 1'b0;
            end
        end else begin
            fdi_tx_valid <= 1'b0;
        end
    end
    
    // PCIe TLP Transmission
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_tlp_rd_ptr <= 3'h0;
            pcie_tx_tlp_valid <= 1'b0;
        end else if (engine_enable) begin
            
            if (!tx_tlp_buffer_empty && pcie_tx_tlp_ready) begin
                pcie_tlp_packet_t tx_tlp = tx_tlp_buffer[tx_tlp_rd_ptr];
                
                pcie_tx_tlp <= tx_tlp.data;
                pcie_tx_tlp_header <= tx_tlp.header;
                pcie_tx_tlp_valid <= 1'b1;
                tx_tlp_rd_ptr <= tx_tlp_rd_ptr + 1;
                
                // Update counters
                tlp_counter <= tlp_counter + 1;
                byte_counter <= byte_counter + (tx_tlp.header.length * 32'd4); // Length in DWORDs
            end else begin
                pcie_tx_tlp_valid <= 1'b0;
            end
        end else begin
            pcie_tx_tlp_valid <= 1'b0;
        end
    end
    
    // Flow Control Management
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fc_ph_available <= 12'h0;
            fc_nph_available <= 12'h0;
            fc_cplh_available <= 12'h0;
            fc_pd_available <= 16'h0;
            fc_npd_available <= 16'h0;
            fc_cpld_available <= 16'h0;
        end else if (engine_enable) begin
            
            // Update available credits
            fc_ph_available <= fc_posted_header_credits - fc_posted_header_consumed;
            fc_pd_available <= fc_posted_data_credits - fc_posted_data_consumed;
            fc_nph_available <= fc_nonposted_header_credits - fc_nonposted_header_consumed;
            fc_npd_available <= fc_nonposted_data_credits - fc_nonposted_data_consumed;
            fc_cplh_available <= fc_completion_header_credits - fc_completion_header_consumed;
            fc_cpld_available <= fc_completion_data_credits - fc_completion_data_consumed;
        end
    end
    
    // ML-Enhanced Performance Optimization
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ml_performance_metric <= 8'h80;
            ml_bandwidth_efficiency <= 16'h8000;
            ml_congestion_level <= 8'h40;
        end else if (ML_OPTIMIZATION && ml_enable && engine_enable) begin
            
            // Calculate bandwidth utilization
            if (cycle_counter[11:0] == 12'hFFF) begin // Update every 4096 cycles
                logic [31:0] actual_bandwidth = byte_counter;
                logic [31:0] theoretical_bandwidth = 32'd4096 * (link_width * 32'd128); // Simplified
                
                if (theoretical_bandwidth > 0) begin
                    ml_bandwidth_efficiency <= (actual_bandwidth * 16'd65535) / theoretical_bandwidth;
                end
                
                byte_counter <= 32'h0;
            end
            
            // Calculate performance score based on latency and utilization
            logic [15:0] avg_latency = (outstanding_count > 0) ? 
                                     (latency_accumulator[15:0] / outstanding_count) : 16'h0;
            
            if (avg_latency < ml_latency_target * 16'd256) begin
                ml_performance_metric <= (ml_performance_metric < 8'hF0) ? 
                                       ml_performance_metric + 1 : 8'hFF;
            end else begin
                ml_performance_metric <= (ml_performance_metric > 8'h10) ? 
                                       ml_performance_metric - 1 : 8'h00;
            end
            
            // Congestion level based on buffer fullness
            logic [3:0] buffer_fullness = {rx_tlp_buffer_full, tx_tlp_buffer_full, 
                                         rx_flit_buffer_full, tx_flit_buffer_full};
            ml_congestion_level <= {4'h0, buffer_fullness} * 8'd16;
        end
    end
    
    // Error Detection and Handling
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            error_counter <= 16'h0;
            tlp_error <= 1'b0;
            flow_control_error <= 1'b0;
        end else if (engine_enable) begin
            
            // TLP format errors
            if (pcie_rx_tlp_valid && pcie_rx_tlp_ready) begin
                if (pcie_rx_tlp_header.length == 8'h0) begin
                    tlp_error <= 1'b1;
                    error_counter <= error_counter + 1;
                end else begin
                    tlp_error <= 1'b0;
                end
            end
            
            // Flow control errors
            if ((fc_ph_available == 12'h0 && pcie_tx_tlp_valid) ||
                (fc_nph_available == 12'h0 && pcie_tx_tlp_valid) ||
                (fc_cplh_available == 12'h0 && pcie_tx_tlp_valid)) begin
                flow_control_error <= 1'b1;
                error_counter <= error_counter + 1;
            end else begin
                flow_control_error <= 1'b0;
            end
        end
    end
    
    // Buffer Status Logic
    always_comb begin
        rx_tlp_buffer_full = (rx_tlp_wr_ptr + 1) == rx_tlp_rd_ptr;
        rx_tlp_buffer_empty = (rx_tlp_wr_ptr == rx_tlp_rd_ptr);
        tx_tlp_buffer_full = (tx_tlp_wr_ptr + 1) == tx_tlp_rd_ptr;
        tx_tlp_buffer_empty = (tx_tlp_wr_ptr == tx_tlp_rd_ptr);
        rx_flit_buffer_full = (rx_flit_wr_ptr + 1) == rx_flit_rd_ptr;
        rx_flit_buffer_empty = (rx_flit_wr_ptr == rx_flit_rd_ptr);
        tx_flit_buffer_full = (tx_flit_wr_ptr + 1) == tx_flit_rd_ptr;
        tx_flit_buffer_empty = (tx_flit_wr_ptr == tx_flit_rd_ptr);
    end
    
    // Output Assignments
    assign fc_posted_header_consumed = rx_tlp_buffer_full ? 12'h0 : 12'h1;
    assign fc_posted_data_consumed = byte_counter[27:12];
    assign fc_nonposted_header_consumed = 12'h0; // Simplified
    assign fc_nonposted_data_consumed = 16'h0;
    assign fc_completion_header_consumed = 12'h0;
    assign fc_completion_data_consumed = 16'h0;
    
    assign ml_performance_score = ml_performance_metric;
    assign ml_optimization_metrics = ml_bandwidth_efficiency;
    
    assign error_count = error_counter;
    assign tlps_processed = tlp_counter;
    assign bytes_transferred = byte_counter;
    assign average_latency_cycles = (outstanding_count > 0) ? 
                                  (latency_accumulator[15:0] / outstanding_count) : 16'h0;
    assign bandwidth_utilization = ml_bandwidth_efficiency[15:8];
    
    assign engine_status = {
        engine_enable,                  // [31] Engine enabled
        pcie_speed,                     // [30:28] PCIe speed
        link_width[5:0],               // [27:22] Link width
        outstanding_count,              // [21:16] Outstanding TLPs
        ml_performance_metric,          // [15:8] ML performance
        ml_congestion_level            // [7:0] Congestion level
    };
    
    assign debug_info = {
        rx_tlp_buffer_full,            // [15] RX TLP buffer full
        tx_tlp_buffer_full,            // [14] TX TLP buffer full
        rx_flit_buffer_full,           // [13] RX flit buffer full
        tx_flit_buffer_full,           // [12] TX flit buffer full
        tlp_error,                     // [11] TLP error
        flow_control_error,            // [10] Flow control error
        2'b00,                         // [9:8] Reserved
        error_counter[7:0]             // [7:0] Error count
    };

endmodule