package ucie_pkg;

    // RDI State Types
    typedef enum logic [3:0] {
        RDI_RESET       = 4'h0,
        RDI_ACTIVE      = 4'h1,
        RDI_PM_ENTRY    = 4'h2,
        RDI_PM_L1       = 4'h3,
        RDI_PM_L2       = 4'h4,
        RDI_PM_EXIT     = 4'h5,
        RDI_RETRAIN     = 4'h6,
        RDI_LINKRESET   = 4'h7,
        RDI_DISABLED    = 4'h8,
        RDI_LINKERROR   = 4'h9
    } rdi_state_t;

    // Flit Format Types
    typedef enum logic [2:0] {
        FLIT_RAW            = 3'h0,
        FLIT_68B            = 3'h1,
        FLIT_256B_STD_END   = 3'h2,
        FLIT_256B_STD_START = 3'h3,
        FLIT_256B_LAT_OPT   = 3'h4
    } flit_format_t;

    // Protocol Types
    typedef enum logic [3:0] {
        PROTOCOL_RAW        = 4'h0,
        PROTOCOL_PCIE       = 4'h1,
        PROTOCOL_CXL_IO     = 4'h2,
        PROTOCOL_CXL_CACHE  = 4'h3,
        PROTOCOL_CXL_MEM    = 4'h4,
        PROTOCOL_STREAMING  = 4'h8,
        PROTOCOL_MGMT       = 4'hF
    } protocol_type_t;

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
        TRAIN_PHYRETRAIN    = 5'h0A,
        TRAIN_REPAIR        = 5'h0B,
        TRAIN_DEGRADE       = 5'h0C,
        TRAIN_ERROR         = 5'h0D,
        TRAIN_MULTIMOD      = 5'h0E,
        TRAIN_RETIMER       = 5'h0F,
        TRAIN_TEST          = 5'h10,
        TRAIN_COMPLIANCE    = 5'h11,
        TRAIN_LOOPBACK      = 5'h12,
        TRAIN_PATGEN        = 5'h13
    } training_state_t;

    // Error Types
    typedef enum logic [7:0] {
        ERR_NONE            = 8'h00,
        ERR_CRC             = 8'h01,
        ERR_SEQUENCE        = 8'h02,
        ERR_FORMAT          = 8'h03,
        ERR_TIMEOUT         = 8'h04,
        ERR_LANE_FAILURE    = 8'h05,
        ERR_CLOCK_FAILURE   = 8'h06,
        ERR_VALID_FAILURE   = 8'h07,
        ERR_TRAINING_FAIL   = 8'h08,
        ERR_POWER_MGMT      = 8'h09,
        ERR_PROTOCOL        = 8'h0A,
        ERR_OVERFLOW        = 8'h0B,
        ERR_UNDERFLOW       = 8'h0C,
        ERR_SIDEBAND        = 8'h0D,
        ERR_CONFIG          = 8'h0E,
        ERR_VENDOR_DEFINED  = 8'hFF
    } ucie_error_type_t;

    // Common Structures
    typedef struct packed {
        logic [7:0]   format_encoding;
        logic [15:0]  length;
        logic [7:0]   msg_class;
        logic [7:0]   vc_id;
        logic [31:0]  crc;
        logic [479:0] payload;
    } flit_68b_t;

    typedef struct packed {
        logic [7:0]   format_encoding;
        logic [15:0]  length;
        logic [7:0]   msg_class;
        logic [7:0]   vc_id;
        logic [31:0]  protocol_header;
        logic [31:0]  crc;
        logic [1919:0] payload;
    } flit_256b_std_t;

    typedef struct packed {
        ucie_error_type_t   error_type;
        logic [7:0]         severity;
        logic [15:0]        error_code;
        logic [31:0]        error_data;
        logic [31:0]        timestamp;
        logic [7:0]         source_id;
    } ucie_error_info_t;

    // CRC Calculation Function
    function automatic logic [31:0] calc_crc32(
        input logic [31:0] crc_init,
        input logic [255:0] data,
        input logic [7:0] data_length
    );
        logic [31:0] crc_temp = crc_init;
        for (int i = 0; i < data_length; i++) begin
            if (crc_temp[31] ^ data[i]) begin
                crc_temp = (crc_temp << 1) ^ 32'h04C11DB7;
            end else begin
                crc_temp = crc_temp << 1;
            end
        end
        return crc_temp;
    endfunction

endpackage