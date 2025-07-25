# UCIe Interface Specifications

## Overview
This document defines the detailed signal-level interfaces for all components in the UCIe controller architecture, including RDI, FDI, Sideband, and internal interfaces between layers.

## Interface Hierarchy

```
┌─────────────────────────────────────────────────────────────────────┐
│                     UCIe Interface Architecture                     │
│                                                                     │
│  Application ◄──► RDI/FDI ◄──► Protocol ◄──► D2D ◄──► Physical     │
│    Layer             Interface    Layer       Adapter    Layer      │
│                                                                     │
│                              │                    │                 │
│                              ▼                    ▼                 │
│                      Internal Interfaces  Sideband Interface       │
│                                                   │                 │
│                                                   ▼                 │
│                                            Physical Bumps           │
└─────────────────────────────────────────────────────────────────────┘
```

## 1. Raw Die-to-Die Interface (RDI)

### 1.1 RDI Interface Definition

```systemverilog
interface ucie_rdi_if #(
    parameter DATA_WIDTH = 512,
    parameter USER_WIDTH = 16
) (
    input logic clk,
    input logic resetn
);
    
    // Transmit Interface
    logic                   tx_valid;
    logic [DATA_WIDTH-1:0]  tx_data;
    logic [USER_WIDTH-1:0]  tx_user;
    logic                   tx_sop;
    logic                   tx_eop;
    logic [5:0]            tx_empty;
    logic                   tx_ready;
    
    // Receive Interface
    logic                   rx_valid;
    logic [DATA_WIDTH-1:0]  rx_data;
    logic [USER_WIDTH-1:0]  rx_user;
    logic                   rx_sop;
    logic                   rx_eop;
    logic [5:0]            rx_empty;
    logic                   rx_ready;
    
    // State and Control
    logic                   link_up;
    logic                   link_error;
    logic [7:0]            link_status;
    
    // Power Management
    logic                   lp_wake_req;
    logic                   pl_wake_ack;
    logic                   pl_clk_req;
    logic                   lp_clk_ack;
    
    // Stallreq/Ack Mechanism
    logic                   lp_stallreq;
    logic                   pl_stallack;
    logic                   pl_stallreq;
    logic                   lp_stallack;
    
    // State Request/Status
    logic [3:0]            lp_state_req;
    logic [3:0]            pl_state_sts;
    logic [3:0]            pl_state_req;
    logic [3:0]            lp_state_sts;
    
    modport device (
        input  clk, resetn,
        output tx_valid, tx_data, tx_user, tx_sop, tx_eop, tx_empty,
               lp_wake_req, lp_clk_ack, lp_stallreq, lp_stallack,
               lp_state_req, lp_state_sts, rx_ready,
        input  tx_ready, rx_valid, rx_data, rx_user, rx_sop, rx_eop, rx_empty,
               pl_wake_ack, pl_clk_req, pl_stallreq, pl_stallack,
               pl_state_req, pl_state_sts, link_up, link_error, link_status
    );
    
    modport controller (
        input  clk, resetn, tx_valid, tx_data, tx_user, tx_sop, tx_eop, tx_empty,
               lp_wake_req, lp_clk_ack, lp_stallreq, lp_stallack,
               lp_state_req, lp_state_sts, rx_ready,
        output tx_ready, rx_valid, rx_data, rx_user, rx_sop, rx_eop, rx_empty,
               pl_wake_ack, pl_clk_req, pl_stallreq, pl_stallack,
               pl_state_req, pl_state_sts, link_up, link_error, link_status
    );
endinterface
```

### 1.2 RDI Timing Specifications

```systemverilog
// Timing parameters for RDI interface
parameter RDI_SETUP_TIME    = 100;  // ps
parameter RDI_HOLD_TIME     = 50;   // ps
parameter RDI_CLK_TO_Q      = 200;  // ps
parameter RDI_MAX_SKEW      = 50;   // ps
```

### 1.3 RDI State Machine

```systemverilog
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
```

## 2. Flit-Aware Die-to-Die Interface (FDI)

### 2.1 FDI Interface Definition

```systemverilog
interface ucie_fdi_if #(
    parameter FLIT_WIDTH = 256,
    parameter NUM_VCS = 8
) (
    input logic clk,
    input logic resetn
);
    
    // Transmit Flit Interface
    logic                   pl_flit_valid;
    logic [FLIT_WIDTH-1:0]  pl_flit_data;
    logic                   pl_flit_sop;
    logic                   pl_flit_eop;
    logic [3:0]            pl_flit_be;
    logic                   lp_flit_ready;
    
    // Receive Flit Interface  
    logic                   lp_flit_valid;
    logic [FLIT_WIDTH-1:0]  lp_flit_data;
    logic                   lp_flit_sop;
    logic                   lp_flit_eop;
    logic [3:0]            lp_flit_be;
    logic                   pl_flit_ready;
    
    // Flit Cancel (256B mode only)
    logic                   pl_flit_cancel;
    
    // Credit Interface
    logic [NUM_VCS-1:0]     pl_credit_return;
    logic [NUM_VCS-1:0]     lp_credit_return;
    
    // State and Control (same as RDI)
    logic                   link_up;
    logic                   link_error;
    logic [7:0]            link_status;
    
    // Power Management (same as RDI)
    logic                   lp_wake_req;
    logic                   pl_wake_ack;
    logic                   pl_clk_req;
    logic                   lp_clk_ack;
    
    // Rx Active Request/Status
    logic                   lp_rx_active_req;
    logic                   pl_rx_active_sts;
    
    modport device (
        input  clk, resetn,
        output pl_flit_valid, pl_flit_data, pl_flit_sop, pl_flit_eop, pl_flit_be,
               pl_flit_cancel, pl_credit_return, lp_wake_req, lp_clk_ack,
               lp_rx_active_req, lp_flit_ready,
        input  lp_flit_ready, lp_flit_valid, lp_flit_data, lp_flit_sop, lp_flit_eop,
               lp_flit_be, lp_credit_return, pl_wake_ack, pl_clk_req,
               pl_rx_active_sts, link_up, link_error, link_status, pl_flit_ready
    );
endinterface
```

### 2.2 FDI Flit Formats

```systemverilog
// Flit Format Types
typedef enum logic [2:0] {
    FLIT_RAW            = 3'h0,
    FLIT_68B            = 3'h1,
    FLIT_256B_STD_END   = 3'h2,
    FLIT_256B_STD_START = 3'h3,
    FLIT_256B_LAT_OPT   = 3'h4
} flit_format_t;

// 68B Flit Structure
typedef struct packed {
    logic [7:0]   format_encoding;  // 8 bits
    logic [15:0]  length;          // 16 bits  
    logic [7:0]   msg_class;       // 8 bits
    logic [7:0]   vc_id;           // 8 bits
    logic [31:0]  crc;             // 32 bits
    logic [479:0] payload;         // 480 bits (60 bytes)
} flit_68b_t;

// 256B Standard Flit Structure  
typedef struct packed {
    logic [7:0]   format_encoding;  // 8 bits
    logic [15:0]  length;          // 16 bits
    logic [7:0]   msg_class;       // 8 bits
    logic [7:0]   vc_id;           // 8 bits
    logic [31:0]  protocol_header; // 32 bits
    logic [31:0]  crc;             // 32 bits
    logic [1919:0] payload;        // 1920 bits (240 bytes)
} flit_256b_std_t;

// Latency-Optimized 256B Flit Structure
typedef struct packed {
    logic [7:0]   format_encoding;  // 8 bits
    logic [7:0]   msg_class;       // 8 bits
    logic [7:0]   vc_id;           // 8 bits
    logic [7:0]   reserved;        // 8 bits
    logic [31:0]  crc;             // 32 bits
    logic [1983:0] payload;        // 1984 bits (248 bytes)
} flit_256b_lat_t;
```

### 2.3 FDI Flow Control

```systemverilog
// Credit-based Flow Control
typedef struct packed {
    logic [7:0]   initial_credits[8];  // Per-VC initial credits
    logic [7:0]   credit_limit[8];     // Per-VC credit limits
    logic [15:0]  timeout_value;       // Credit timeout
    logic         credit_return_mode;  // Periodic vs. immediate
} fdi_flow_control_t;
```

## 3. Sideband Interface

### 3.1 Sideband Physical Interface

```systemverilog
interface ucie_sideband_if (
    input logic aux_clk,      // Auxiliary clock (always-on)
    input logic aux_resetn    // Auxiliary reset
);
    
    // Physical Sideband Signals
    logic       sb_clk_out;    // 800 MHz sideband clock output
    logic       sb_data_out;   // Sideband data output
    logic       sb_data_in;    // Sideband data input
    
    // Redundant Sideband (Advanced Package only)
    logic       sb_clk_out_red;
    logic       sb_data_out_red;
    logic       sb_data_in_red;
    
    // Sideband Packet Interface
    logic               tx_packet_valid;
    logic [63:0]        tx_packet_data;
    logic [7:0]         tx_packet_length;
    logic [3:0]         tx_packet_type;
    logic               tx_packet_ready;
    
    logic               rx_packet_valid;
    logic [63:0]        rx_packet_data;
    logic [7:0]         rx_packet_length;
    logic [3:0]         rx_packet_type;
    logic               rx_packet_ready;
    
    // Status and Control
    logic               sideband_active;
    logic               sideband_error;
    logic [7:0]         sideband_status;
    
    modport master (
        input  aux_clk, aux_resetn, sb_data_in, sb_data_in_red,
               tx_packet_ready, rx_packet_valid, rx_packet_data,
               rx_packet_length, rx_packet_type,
        output sb_clk_out, sb_data_out, sb_clk_out_red, sb_data_out_red,
               tx_packet_valid, tx_packet_data, tx_packet_length,
               tx_packet_type, rx_packet_ready, sideband_active,
               sideband_error, sideband_status
    );
endinterface
```

### 3.2 Sideband Packet Types

```systemverilog
typedef enum logic [3:0] {
    SB_REG_ACCESS       = 4'h0,
    SB_MSG_NO_DATA      = 4'h1,
    SB_MSG_WITH_DATA    = 4'h2,
    SB_MPM_WITH_DATA    = 4'h3,
    SB_MPM_NO_DATA      = 4'h4,
    SB_CREDIT_RETURN    = 4'h5,
    SB_INIT_DONE        = 4'h6,
    SB_PM_MESSAGE       = 4'h7,
    SB_VENDOR_DEFINED   = 4'hF
} sideband_packet_type_t;
```

### 3.3 Management Port Message (MPM) Structure

```systemverilog
typedef struct packed {
    logic [7:0]   packet_type;     // MPM packet type
    logic [7:0]   length;          // Payload length
    logic [15:0]  target_id;       // Destination ID
    logic [15:0]  source_id;       // Source ID
    logic [7:0]   msg_tag;         // Message tag
    logic [7:0]   msg_code;        // Message code
    logic [511:0] payload;         // Variable payload
    logic [31:0]  crc;             // CRC32
} mpm_packet_t;
```

## 4. Internal Layer Interfaces

### 4.1 Protocol to D2D Adapter Interface

```systemverilog
interface ucie_proto_d2d_if #(
    parameter FLIT_WIDTH = 256,
    parameter NUM_STACKS = 2
) (
    input logic clk,
    input logic resetn
);
    
    // Per-Stack Flit Interface
    logic [NUM_STACKS-1:0]          stack_tx_valid;
    logic [FLIT_WIDTH-1:0]          stack_tx_data [NUM_STACKS-1:0];
    ucie_flit_header_t              stack_tx_header [NUM_STACKS-1:0];
    logic [NUM_STACKS-1:0]          stack_tx_ready;
    
    logic [NUM_STACKS-1:0]          stack_rx_valid;
    logic [FLIT_WIDTH-1:0]          stack_rx_data [NUM_STACKS-1:0];
    ucie_flit_header_t              stack_rx_header [NUM_STACKS-1:0];
    logic [NUM_STACKS-1:0]          stack_rx_ready;
    
    // Flow Control
    logic [NUM_STACKS-1:0]          stack_credit_update;
    logic [7:0]                     stack_credit_count [NUM_STACKS-1:0];
    
    // Protocol Configuration
    logic [NUM_STACKS-1:0]          stack_enable;
    ucie_protocol_type_t            stack_protocol [NUM_STACKS-1:0];
    
    // Error Reporting
    logic [NUM_STACKS-1:0]          stack_error;
    ucie_error_info_t               stack_error_info [NUM_STACKS-1:0];
    
    modport protocol (
        input  clk, resetn, stack_tx_ready, stack_rx_valid, stack_rx_data,
               stack_rx_header, stack_credit_count, stack_enable, stack_protocol,
        output stack_tx_valid, stack_tx_data, stack_tx_header, stack_rx_ready,
               stack_credit_update, stack_error, stack_error_info
    );
endinterface
```

### 4.2 D2D Adapter to Physical Layer Interface

```systemverilog
interface ucie_d2d_phy_if #(
    parameter FLIT_WIDTH = 256
) (
    input logic clk,
    input logic resetn
);
    
    // Mainband Data Interface
    logic                   mb_tx_valid;
    logic [FLIT_WIDTH-1:0]  mb_tx_data;
    ucie_flit_header_t      mb_tx_header;
    logic                   mb_tx_ready;
    
    logic                   mb_rx_valid;
    logic [FLIT_WIDTH-1:0]  mb_rx_data;
    ucie_flit_header_t      mb_rx_header;
    logic                   mb_rx_ready;
    
    // Sideband Interface
    ucie_sideband_if        sideband;
    
    // Link State Interface
    ucie_link_state_t       current_link_state;
    logic                   link_training_req;
    logic                   link_training_done;
    logic                   link_error;
    
    // Parameter Exchange
    ucie_adapter_cap_t      local_adapter_cap;
    ucie_adapter_cap_t      remote_adapter_cap;
    logic                   param_exchange_done;
    
    // Power Management
    logic                   pm_l1_req;
    logic                   pm_l2_req;
    logic                   pm_l0_req;
    logic                   pm_ack;
    
    modport d2d (
        input  clk, resetn, mb_tx_ready, mb_rx_valid, mb_rx_data, mb_rx_header,
               current_link_state, link_training_done, remote_adapter_cap,
               param_exchange_done, pm_ack,
        output mb_tx_valid, mb_tx_data, mb_tx_header, mb_rx_ready,
               link_training_req, local_adapter_cap, pm_l1_req, pm_l2_req, pm_l0_req
    );
endinterface
```

## 5. Configuration Interfaces

### 5.1 Configuration Register Interface

```systemverilog
interface ucie_config_if (
    input logic clk,
    input logic resetn
);
    
    // Register Access Interface
    logic               reg_valid;
    logic               reg_write;
    logic [31:0]        reg_addr;
    logic [31:0]        reg_wdata;
    logic [31:0]        reg_rdata;
    logic               reg_ready;
    logic               reg_error;
    
    // DVSEC Configuration
    logic [15:0]        vendor_id;
    logic [15:0]        device_id;
    logic [31:0]        capability_ptr;
    
    // Link Configuration
    ucie_link_config_t  link_config;
    ucie_phy_config_t   phy_config;
    ucie_proto_config_t proto_config;
    
    // Status Reporting
    ucie_link_status_t  link_status;
    ucie_phy_status_t   phy_status;
    ucie_proto_status_t proto_status;
    
    modport device (
        input  clk, resetn, reg_valid, reg_write, reg_addr, reg_wdata,
               vendor_id, device_id, capability_ptr, link_config,
               phy_config, proto_config,
        output reg_rdata, reg_ready, reg_error, link_status,
               phy_status, proto_status
    );
endinterface
```

### 5.2 Debug Interface

```systemverilog
interface ucie_debug_if (
    input logic clk,
    input logic resetn
);
    
    // Debug Register Access
    logic               dbg_valid;
    logic               dbg_write;
    logic [31:0]        dbg_addr;
    logic [31:0]        dbg_wdata;
    logic [31:0]        dbg_rdata;
    logic               dbg_ready;
    
    // Test Pattern Control
    logic               test_pattern_enable;
    logic [63:0]        test_pattern;
    logic [63:0]        received_pattern;
    logic               pattern_error;
    
    // Compliance Mode
    logic               compliance_enable;
    logic [7:0]         compliance_pattern;
    
    // Error Injection
    logic               error_inject_enable;
    logic [3:0]         error_inject_type;
    logic [63:0]        error_inject_mask;
    
    // Performance Monitoring
    logic [31:0]        perf_counter_select;
    logic [63:0]        perf_counter_value;
    
    modport device (
        input  clk, resetn, dbg_valid, dbg_write, dbg_addr, dbg_wdata,
               test_pattern_enable, test_pattern, compliance_enable,
               compliance_pattern, error_inject_enable, error_inject_type,
               error_inject_mask, perf_counter_select,
        output dbg_rdata, dbg_ready, received_pattern, pattern_error,
               perf_counter_value
    );
endinterface
```

## 6. Physical Bump Interface

### 6.1 Standard Package Bump Map

```systemverilog
// x16 Standard Package Module
typedef struct packed {
    logic [15:0]    data_lane;      // D0-D15
    logic           clock_p;        // CLKP
    logic           clock_n;        // CLKN  
    logic           valid;          // VALID
    logic           track;          // TRACK
    logic           sb_clk;         // Sideband clock
    logic           sb_data;        // Sideband data
    logic           vss[4];         // Ground pins
    logic           vdd[4];         // Power pins
} std_pkg_x16_bumps_t;

// x8 Standard Package Module (degraded)
typedef struct packed {
    logic [7:0]     data_lane;      // D0-D7
    logic           clock_p;        // CLKP
    logic           clock_n;        // CLKN
    logic           valid;          // VALID
    logic           track;          // TRACK
    logic           sb_clk;         // Sideband clock
    logic           sb_data;        // Sideband data
    logic           vss[2];         // Ground pins
    logic           vdd[2];         // Power pins
} std_pkg_x8_bumps_t;
```

### 6.2 Advanced Package Bump Map

```systemverilog
// x64 Advanced Package Module
typedef struct packed {
    logic [63:0]    data_lane;      // D0-D63
    logic [3:0]     spare_data;     // Spare data lanes
    logic           clock_p;        // CLKP
    logic           clock_n;        // CLKN
    logic           clock_p_spare;  // Spare CLKP
    logic           clock_n_spare;  // Spare CLKN
    logic           valid;          // VALID
    logic           valid_spare;    // Spare VALID
    logic           track;          // TRACK
    logic           sb_clk;         // Sideband clock
    logic           sb_data;        // Sideband data
    logic           sb_clk_red;     // Redundant sideband clock
    logic           sb_data_red;    // Redundant sideband data
    logic           vss[8];         // Ground pins
    logic           vdd[8];         // Power pins
} adv_pkg_x64_bumps_t;

// x32 Advanced Package Module
typedef struct packed {
    logic [31:0]    data_lane;      // D0-D31
    logic [3:0]     spare_data;     // Spare data lanes
    logic           clock_p;        // CLKP
    logic           clock_n;        // CLKN
    logic           clock_p_spare;  // Spare CLKP
    logic           clock_n_spare;  // Spare CLKN
    logic           valid;          // VALID
    logic           valid_spare;    // Spare VALID
    logic           track;          // TRACK
    logic           sb_clk;         // Sideband clock
    logic           sb_data;        // Sideband data
    logic           sb_clk_red;     // Redundant sideband clock
    logic           sb_data_red;    // Redundant sideband data
    logic           vss[4];         // Ground pins
    logic           vdd[4];         // Power pins
} adv_pkg_x32_bumps_t;
```

## 7. Timing and Electrical Specifications

### 7.1 Timing Parameters

```systemverilog
// Timing specifications for different speeds
typedef struct packed {
    logic [15:0]    setup_time_ps;      // Setup time
    logic [15:0]    hold_time_ps;       // Hold time
    logic [15:0]    clk_to_q_ps;        // Clock to output
    logic [15:0]    max_skew_ps;        // Maximum skew
    logic [15:0]    jitter_rms_ps;      // RMS jitter
    logic [15:0]    jitter_pk2pk_ps;    // Peak-to-peak jitter
} timing_spec_t;

parameter timing_spec_t TIMING_4GT  = '{200, 100, 300, 100, 10, 50};
parameter timing_spec_t TIMING_8GT  = '{150, 75,  250, 75,  8,  40};
parameter timing_spec_t TIMING_16GT = '{100, 50,  200, 50,  6,  30};
parameter timing_spec_t TIMING_32GT = '{75,  40,  150, 40,  5,  25};
```

### 7.2 Electrical Parameters

```systemverilog
// Electrical specifications
typedef struct packed {
    logic [15:0]    vdd_mv;             // Supply voltage (mV)
    logic [15:0]    vol_max_mv;         // Output low max (mV)
    logic [15:0]    voh_min_mv;         // Output high min (mV)
    logic [15:0]    vil_max_mv;         // Input low max (mV)
    logic [15:0]    vih_min_mv;         // Input high min (mV)
    logic [15:0]    differential_swing_mv; // Differential swing
} electrical_spec_t;

parameter electrical_spec_t STD_PKG_ELEC = '{800, 100, 700, 150, 650, 400};
parameter electrical_spec_t ADV_PKG_ELEC = '{800, 80,  720, 120, 680, 500};
```

## 8. Error Conditions and Reporting

### 8.1 Error Types

```systemverilog
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
```

### 8.2 Error Information Structure

```systemverilog
typedef struct packed {
    ucie_error_type_t   error_type;
    logic [7:0]         severity;      // 0=Info, 1=Warning, 2=Error, 3=Fatal
    logic [15:0]        error_code;
    logic [31:0]        error_data;
    logic [31:0]        timestamp;
    logic [7:0]         source_id;
} ucie_error_info_t;
```

## Next Steps

1. **Signal-level Verification**: Validate all interface signals and timing
2. **Testbench Development**: Create interface-specific verification components
3. **Synthesis Constraints**: Define timing constraints for implementation
4. **Package Integration**: Map interfaces to physical bump locations
5. **Compliance Testing**: Validate against UCIe specification requirements