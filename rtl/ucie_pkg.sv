package ucie_pkg;

    // UCIe Specification Parameters
    parameter int UCIE_VERSION_MAJOR = 2;
    parameter int UCIE_VERSION_MINOR = 0;
    
    // Physical Layer Parameters
    parameter int MAX_LANES = 64;
    parameter int MIN_LANES = 8;
    parameter int MAX_MODULES = 4;
    parameter int SIDEBAND_FREQ_MHZ = 800;
    
    // Data Rate Parameters (GT/s) - Enhanced for 128 Gbps
    parameter int MIN_DATA_RATE = 4;
    parameter int MAX_DATA_RATE = 128;
    typedef enum logic [3:0] {
        DR_4GT   = 4'h0,  // 4 GT/s
        DR_8GT   = 4'h1,  // 8 GT/s
        DR_12GT  = 4'h2,  // 12 GT/s
        DR_16GT  = 4'h3,  // 16 GT/s
        DR_24GT  = 4'h4,  // 24 GT/s
        DR_32GT  = 4'h5,  // 32 GT/s
        DR_64GT  = 4'h6,  // 64 GT/s (NRZ limit)
        DR_128GT = 4'h7   // 128 GT/s (PAM4 required)
    } data_rate_t;
    
    // Signaling Mode Parameters
    typedef enum logic [1:0] {
        SIG_NRZ  = 2'b00,  // Non-Return-to-Zero (up to 64 GT/s)
        SIG_PAM4 = 2'b01,  // 4-level Pulse Amplitude Modulation (64+ GT/s)
        SIG_PAM8 = 2'b10   // 8-level PAM (future)
    } signaling_mode_t;
    
    // Signaling Mode Constants (for backward compatibility)
    parameter signaling_mode_t SIGNALING_NRZ  = SIG_NRZ;
    parameter signaling_mode_t SIGNALING_PAM4 = SIG_PAM4;
    parameter signaling_mode_t SIGNALING_PAM8 = SIG_PAM8;
    
    // Data Rate Constants (for backward compatibility)
    parameter data_rate_t DATA_RATE_4G   = DR_4GT;
    parameter data_rate_t DATA_RATE_8G   = DR_8GT;
    parameter data_rate_t DATA_RATE_16G  = DR_16GT;
    parameter data_rate_t DATA_RATE_32G  = DR_32GT;
    parameter data_rate_t DATA_RATE_64G  = DR_64GT;
    parameter data_rate_t DATA_RATE_128G = DR_128GT;
    
    // PAM4 Specific Parameters
    parameter int PAM4_SYMBOL_RATE_GSPS = 64;  // 64 Gsym/s for 128 Gbps
    parameter int PAM4_BITS_PER_SYMBOL = 2;    // 2 bits per PAM4 symbol
    parameter int PAM4_LANES_MAX = 64;
    parameter int PAM4_POWER_MW_PER_LANE = 53; // 72% power reduction target
    
    // Quarter-Rate Processing Parameters
    parameter int QUARTER_RATE_DIV = 4;
    parameter int QUARTER_RATE_PARALLEL_ENGINES = 4;
    parameter int QUARTER_RATE_BUFFER_MULT = 4;
    
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
    typedef enum logic [3:0] {
        LINK_RESET      = 4'h0,
        LINK_SBINIT     = 4'h1,
        LINK_PARAM      = 4'h2,
        LINK_MBINIT     = 4'h3,
        LINK_CAL        = 4'h4,
        LINK_MBTRAIN    = 4'h5,
        LINK_LINKINIT   = 4'h6,
        LINK_ACTIVE     = 4'h7,
        LINK_L1         = 4'h8,
        LINK_L2         = 4'h9,
        LINK_RETRAIN    = 4'hA,
        LINK_REPAIR     = 4'hB,
        LINK_ERROR      = 4'hF
    } link_state_t;
    
    // Training States
    typedef enum logic [4:0] {
        TRAIN_RESET         = 5'h00,
        TRAIN_SBINIT        = 5'h01,
        TRAIN_PARAM         = 5'h02,
        TRAIN_MBINIT        = 5'h03,
        TRAIN_CAL           = 5'h04,
        TRAIN_MBTRAIN       = 5'h05,
        TRAIN_LINKINIT      = 5'h06,
        TRAIN_ACTIVE        = 5'h07,
        TRAIN_L1            = 5'h08,
        TRAIN_L2            = 5'h09,
        TRAIN_RETRAIN       = 5'h0A,
        TRAIN_REPAIR        = 5'h0B,
        TRAIN_WIDTH_CHANGE  = 5'h0C,
        TRAIN_SPEED_CHANGE  = 5'h0D,
        TRAIN_ERROR         = 5'h0E,
        TRAIN_RETIMER       = 5'h0F,
        TRAIN_TEST          = 5'h10,
        TRAIN_COMPLIANCE    = 5'h11,
        TRAIN_LOOPBACK      = 5'h12,
        TRAIN_PATGEN        = 5'h13,
        TRAIN_MULTIMOD      = 5'h14
    } training_state_t;
    
    // Power States - Enhanced with Micro-States
    typedef enum logic [1:0] {
        PWR_L0  = 2'b00,  // Active
        PWR_L1  = 2'b01,  // Standby
        PWR_L2  = 2'b10,  // Sleep
        PWR_L3  = 2'b11   // Off
    } power_state_t;
    
    // Micro-Power States for L0 (Advanced Power Management)
    typedef enum logic [2:0] {
        L0_ACTIVE      = 3'b000,  // Full active
        L0_STANDBY     = 3'b001,  // Partial standby
        L0_LOW_POWER   = 3'b010,  // Low power active
        L0_THROTTLED   = 3'b011,  // Thermal throttling
        L0_ADAPTIVE    = 3'b100,  // Adaptive power
        L0_ML_OPTIMIZED = 3'b101  // ML-enhanced optimization
    } micro_power_state_t;
    
    // Advanced Power Management Parameters
    parameter int POWER_TRANSITION_TIME_NS = 100;  // 100ns transition time
    parameter int THERMAL_THRESHOLD_C = 85;        // 85°C thermal threshold
    parameter int POWER_BUDGET_MW_TOTAL = 5400;    // 5.4W total budget for 64 lanes
    parameter int POWER_BUDGET_MW_PER_LANE = 84;   // Average 84mW per lane (5400/64)
    
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
            DR_4GT:   return 4;
            DR_8GT:   return 8;
            DR_12GT:  return 12;
            DR_16GT:  return 16;
            DR_24GT:  return 24;
            DR_32GT:  return 32;
            DR_64GT:  return 64;
            DR_128GT: return 128;
            default:  return 4;
        endcase
    endfunction
    
    // Check if data rate requires PAM4 signaling
    function automatic logic requires_pam4(data_rate_t dr);
        return (dr == DR_128GT);
    endfunction
    
    // Calculate symbol rate for given data rate and signaling mode
    function automatic int get_symbol_rate_gsps(data_rate_t dr, signaling_mode_t sig);
        int data_rate = get_data_rate_value(dr);
        case (sig)
            SIG_NRZ:  return data_rate;  // 1 bit per symbol
            SIG_PAM4: return data_rate / 2;  // 2 bits per symbol
            SIG_PAM8: return data_rate / 3;  // 3 bits per symbol
            default:  return data_rate;
        endcase
    endfunction
    
    // Calculate power consumption per lane
    function automatic int get_power_per_lane_mw(data_rate_t dr, signaling_mode_t sig);
        int base_power;
        case (dr)
            DR_4GT:   base_power = 15;
            DR_8GT:   base_power = 25;
            DR_16GT:  base_power = 45;
            DR_32GT:  base_power = 85;
            DR_64GT:  base_power = (sig == SIG_NRZ) ? 160 : 95;
            DR_128GT: base_power = (sig == SIG_PAM4) ? 53 : 190;  // 72% reduction with PAM4
            default:  base_power = 15;
        endcase
        return base_power;
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
            LINK_SBINIT:   return "SBINIT";
            LINK_PARAM:    return "PARAM";
            LINK_MBINIT:   return "MBINIT";
            LINK_CAL:      return "CAL";
            LINK_MBTRAIN:  return "MBTRAIN";
            LINK_LINKINIT: return "LINKINIT";
            LINK_ACTIVE:   return "ACTIVE";
            LINK_L1:       return "L1";
            LINK_L2:       return "L2";
            LINK_RETRAIN:  return "RETRAIN";
            LINK_REPAIR:   return "REPAIR";
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

