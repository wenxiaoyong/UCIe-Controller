package ucie_pkg;

    // UCIe Specification Parameters
    parameter int UCIE_VERSION_MAJOR = 2;
    parameter int UCIE_VERSION_MINOR = 0;
    
    // Physical Layer Parameters
    parameter int MAX_LANES = 64;
    parameter int MIN_LANES = 8;
    parameter int MAX_MODULES = 4;
    parameter int SIDEBAND_FREQ_MHZ = 800;
    
    // Data Rate Parameters (GT/s)
    parameter int MIN_DATA_RATE = 4;
    parameter int MAX_DATA_RATE = 32;
    typedef enum logic [3:0] {
        DR_4GT   = 4'h0,  // 4 GT/s
        DR_8GT   = 4'h1,  // 8 GT/s
        DR_12GT  = 4'h2,  // 12 GT/s
        DR_16GT  = 4'h3,  // 16 GT/s
        DR_24GT  = 4'h4,  // 24 GT/s
        DR_32GT  = 4'h5   // 32 GT/s
    } data_rate_t;
    
    // Flit Formats
    parameter int FLIT_WIDTH = 256;
    parameter int FLIT_HEADER_WIDTH = 32;
    parameter int FLIT_PAYLOAD_WIDTH = 224;
    parameter int CRC_WIDTH = 32;
    
    // Protocol Types
    typedef enum logic [3:0] {
        PROTO_PCIE        = 4'h0,
        PROTO_CXL_IO      = 4'h1,
        PROTO_CXL_CACHE   = 4'h2,
        PROTO_CXL_MEM     = 4'h3,
        PROTO_STREAMING   = 4'h4,
        PROTO_MGMT        = 4'hF
    } protocol_type_t;
    
    // Package Types
    typedef enum logic [1:0] {
        PKG_STANDARD    = 2'b00,  // Standard Package
        PKG_ADVANCED    = 2'b01,  // Advanced Package  
        PKG_UCIE_3D     = 2'b10   // UCIe-3D Package
    } package_type_t;
    
    // Link States
    typedef enum logic [2:0] {
        LINK_RESET      = 3'b000,
        LINK_INIT       = 3'b001,
        LINK_TRAINING   = 3'b010,
        LINK_ACTIVE     = 3'b011,
        LINK_L1         = 3'b100,
        LINK_L2         = 3'b101,
        LINK_ERROR      = 3'b111
    } link_state_t;
    
    // Power States
    typedef enum logic [1:0] {
        PWR_L0  = 2'b00,  // Active
        PWR_L1  = 2'b01,  // Standby
        PWR_L2  = 2'b10,  // Sleep
        PWR_L3  = 2'b11   // Off
    } power_state_t;
    
    // Virtual Channel Parameters
    parameter int MAX_VCS = 8;
    parameter int DEFAULT_VC_CREDITS = 16;
    
    // Buffer Parameters
    parameter int DEFAULT_BUFFER_DEPTH = 32;
    parameter int MAX_BUFFER_DEPTH = 128;
    parameter int MIN_BUFFER_DEPTH = 8;
    
    // Retry Parameters
    parameter int MAX_RETRY_COUNT = 7;
    parameter int RETRY_BUFFER_DEPTH = 64;
    parameter int RETRY_TIMEOUT_US = 10;
    
    // CRC Polynomial (CRC-32)
    parameter logic [31:0] CRC32_POLYNOMIAL = 32'h04C11DB7;
    parameter logic [31:0] CRC32_INIT = 32'hFFFFFFFF;
    
    // BER Thresholds
    parameter int BER_ALARM_THRESHOLD = 32'h00001000;
    parameter int BER_WARNING_THRESHOLD = 32'h00000800;
    
    // Timing Parameters (in clock cycles @ 1GHz)
    parameter int PARAM_EXCHANGE_TIMEOUT = 1000000;  // 1ms
    parameter int TRAINING_TIMEOUT = 10000000;       // 10ms
    parameter int SIDEBAND_MSG_TIMEOUT = 800000;     // 1ms @ 800MHz
    parameter int HEARTBEAT_INTERVAL = 80000;        // 100us @ 800MHz
    
    // Lane Management
    parameter int MAX_REPAIR_LANES = 8;
    parameter int LANE_REPAIR_TIMEOUT = 20000000;    // 20ms
    parameter int LANE_MONITORING_CYCLE = 100000;    // 100us
    
    // Flit Header Format
    typedef struct packed {
        logic [3:0]  protocol_id;
        logic [7:0]  virtual_channel;
        logic [7:0]  sequence_number;
        logic [3:0]  flit_type;
        logic [7:0]  reserved;
    } flit_header_t;
    
    // Flit Types
    typedef enum logic [3:0] {
        FLIT_HEADER     = 4'h0,
        FLIT_DATA       = 4'h1,
        FLIT_TAIL       = 4'h2,
        FLIT_SINGLE     = 4'h3,
        FLIT_CONTROL    = 4'hF
    } flit_type_t;
    
    // Message Types for Sideband
    typedef enum logic [7:0] {
        MSG_PARAM_REQ    = 8'h10,
        MSG_PARAM_RSP    = 8'h11,
        MSG_TRAIN_REQ    = 8'h20,
        MSG_TRAIN_RSP    = 8'h21,
        MSG_POWER_REQ    = 8'h30,
        MSG_POWER_ACK    = 8'h31,
        MSG_LANE_REQ     = 8'h40,
        MSG_LANE_ACK     = 8'h41,
        MSG_ERROR        = 8'hF0,
        MSG_HEARTBEAT    = 8'hFF
    } sb_msg_type_t;
    
    // Configuration Register Map
    typedef enum logic [15:0] {
        CFG_CONTROLLER_ID    = 16'h0000,
        CFG_PROTOCOL_ENABLE  = 16'h0001,
        CFG_PROTOCOL_PRIORITY = 16'h0002,
        CFG_WIDTH_CONFIG     = 16'h0003,
        CFG_SPEED_CONFIG     = 16'h0004,
        CFG_VC_CREDITS_BASE  = 16'h0010,  // 0x0010-0x001F
        CFG_LANE_CONFIG      = 16'h0020,
        CFG_POWER_CONFIG     = 16'h0030,
        CFG_SB_CONFIG        = 16'h0040,
        CFG_STATUS_BASE      = 16'h0100,  // 0x0100-0x01FF
        CFG_PERF_BASE        = 16'h0200   // 0x0200-0x02FF
    } config_addr_t;
    
    // Error Types
    typedef enum logic [3:0] {
        ERR_NONE         = 4'h0,
        ERR_CRC          = 4'h1,
        ERR_SEQUENCE     = 4'h2,
        ERR_PROTOCOL     = 4'h3,
        ERR_BUFFER_OVERFLOW = 4'h4,
        ERR_TIMEOUT      = 4'h5,
        ERR_LANE_FAILURE = 4'h6,
        ERR_PARAM_MISMATCH = 4'h7,
        ERR_TRAINING     = 4'h8,
        ERR_POWER        = 4'h9,
        ERR_SIDEBAND     = 4'hA,
        ERR_UNKNOWN      = 4'hF
    } error_type_t;
    
    // Utility Functions
    function automatic logic [31:0] calc_crc32(
        logic [31:0] crc_in,
        logic [255:0] data_in,
        logic [7:0] data_bytes
    );
        logic [31:0] crc_temp = crc_in;
        logic [7:0] data_byte;
        
        for (int i = 0; i < data_bytes; i++) begin
            data_byte = data_in[i*8 +: 8];
            crc_temp = crc_temp ^ {24'h0, data_byte};
            
            for (int j = 0; j < 8; j++) begin
                if (crc_temp[31]) begin
                    crc_temp = (crc_temp << 1) ^ CRC32_POLYNOMIAL;
                end else begin
                    crc_temp = crc_temp << 1;
                end
            end
        end
        
        return crc_temp;
    endfunction
    
    // Helper function to extract flit header
    function automatic flit_header_t extract_flit_header(
        logic [FLIT_WIDTH-1:0] flit_data
    );
        flit_header_t header;
        header = flit_data[FLIT_WIDTH-1:FLIT_WIDTH-32];
        return header;
    endfunction
    
    // Helper function to create flit header
    function automatic logic [31:0] create_flit_header(
        protocol_type_t protocol,
        logic [7:0] vc,
        logic [7:0] seq_num,
        flit_type_t ftype
    );
        flit_header_t header;
        header.protocol_id = protocol;
        header.virtual_channel = vc;
        header.sequence_number = seq_num;
        header.flit_type = ftype;
        header.reserved = 8'h0;
        return header;
    endfunction
    
    // Lane mapping utilities
    function automatic logic [7:0] get_logical_lane(
        logic [7:0] physical_lane,
        logic [7:0] lane_map [MAX_LANES-1:0]
    );
        if (8'(physical_lane) < 8'(MAX_LANES)) begin
            return lane_map[physical_lane[5:0]];
        end else begin
            return 8'hFF; // Invalid
        end
    endfunction
    
    // Priority encoder for arbitration
    function automatic logic [$clog2(MAX_LANES)-1:0] priority_encode(
        logic [MAX_LANES-1:0] requests
    );
        for (int i = 0; i < MAX_LANES; i++) begin
            if (requests[i]) begin
                return i[$clog2(MAX_LANES)-1:0];
            end
        end
        return '0;
    endfunction
    
    // Convert data rate enum to actual rate
    function automatic int get_data_rate_value(data_rate_t dr);
        case (dr)
            DR_4GT:  return 4;
            DR_8GT:  return 8;
            DR_12GT: return 12;
            DR_16GT: return 16;
            DR_24GT: return 24;
            DR_32GT: return 32;
            default: return 4;
        endcase
    endfunction
    
    // Convert power state to string for debug
    function automatic string power_state_to_string(power_state_t state);
        case (state)
            PWR_L0: return "L0_ACTIVE";
            PWR_L1: return "L1_STANDBY";
            PWR_L2: return "L2_SLEEP";
            PWR_L3: return "L3_OFF";
            default: return "UNKNOWN";
        endcase
    endfunction
    
    // Convert link state to string for debug
    function automatic string link_state_to_string(link_state_t state);
        case (state)
            LINK_RESET:    return "RESET";
            LINK_INIT:     return "INIT";
            LINK_TRAINING: return "TRAINING";
            LINK_ACTIVE:   return "ACTIVE";
            LINK_L1:       return "L1";
            LINK_L2:       return "L2";
            LINK_ERROR:    return "ERROR";
            default:       return "UNKNOWN";
        endcase
    endfunction
    
    // Debugging and Monitoring Structures
    typedef struct packed {
        logic [31:0] tx_flit_count;
        logic [31:0] rx_flit_count;
        logic [15:0] error_count;
        logic [15:0] buffer_peak_occupancy;
    } protocol_stats_t;
    
    typedef struct packed {
        logic [15:0] crc_errors;
        logic [15:0] retry_count;
        logic [15:0] timeout_count;
        logic [15:0] sequence_errors;
    } link_stats_t;
    
    typedef struct packed {
        logic [7:0]  good_lanes;
        logic [7:0]  marginal_lanes;
        logic [7:0]  failed_lanes;
        logic [7:0]  repair_lanes;
        logic [15:0] ber_violations;
        logic [15:0] lane_changes;
    } lane_stats_t;
    
    // Constants for common values
    parameter logic [FLIT_WIDTH-1:0] IDLE_FLIT = '0;
    parameter logic [31:0] NULL_CRC = 32'h0;
    parameter logic [7:0] BROADCAST_VC = 8'hFF;
    parameter logic [7:0] MGMT_VC = 8'h00;
    
    // Assertion helper macros (for verification)
    `define ASSERT_CLK(cond, msg) \
        assert property (@(posedge clk) disable iff (!rst_n) (cond)) \
        else $error("ASSERTION FAILED: %s", msg);
    
    `define ASSERT_NEVER(cond, msg) \
        assert property (@(posedge clk) disable iff (!rst_n) !(cond)) \
        else $error("ASSERTION FAILED: %s", msg);

endpackage

