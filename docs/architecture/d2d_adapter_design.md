# UCIe D2D Adapter Architecture

## Overview
The Die-to-Die (D2D) Adapter is the central coordination layer that bridges the Protocol Layer and Physical Layer. It handles link state management, CRC/retry mechanisms, power management, and protocol stack multiplexing while ensuring reliable data transfer across the UCIe link.

## D2D Adapter Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              D2D Adapter                                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      Protocol Interface                             │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │   │
│  │  │   Stack 0    │ │   Stack 1    │ │  Management  │                │   │
│  │  │ (PCIe/CXL)   │ │ (CXL/Stream) │ │  Transport   │                │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│  ┌─────────────────────────────────▼────────────────────────────────────┐   │
│  │                        Stack Multiplexer                            │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │   │
│  │  │ Protocol     │ │   Flit       │ │  Stack       │                │   │
│  │  │Arbitration   │ │ Validation   │ │ Coordination │                │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│  ┌─────────────────────────────────▼────────────────────────────────────┐   │
│  │                         Link Layer Engine                           │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │   │
│  │  │    Link      │ │     CRC      │ │    Retry     │                │   │
│  │  │    State     │ │  Generator/  │ │   Buffer     │                │   │
│  │  │   Machine    │ │   Checker    │ │  Manager     │                │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘                │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │   │
│  │  │   Power      │ │  Parameter   │ │   Timeout    │                │   │
│  │  │ Management   │ │  Exchange    │ │   Manager    │                │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                    │                                        │
│  ┌─────────────────────────────────▼────────────────────────────────────┐   │
│  │                      Physical Interface                             │   │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐                │   │
│  │  │   Mainband   │ │   Sideband   │ │   Control    │                │   │
│  │  │   Interface  │ │   Interface  │ │   Signals    │                │   │
│  │  └──────────────┘ └──────────────┘ └──────────────┘                │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Major Functional Blocks

### 1. Link State Machine (LSM)

```systemverilog
module ucie_link_state_machine (
    input  logic                clk,
    input  logic                resetn,
    
    // Physical Layer Interface
    input  ucie_phy_status_t    phy_status,
    output ucie_phy_control_t   phy_control,
    
    // Protocol Layer Interface
    input  ucie_proto_request_t proto_request,
    output ucie_proto_response_t proto_response,
    
    // State Machine Outputs
    output ucie_link_state_t    current_state,
    output logic                link_ready,
    output logic                retrain_request,
    
    // Configuration and Status
    input  ucie_lsm_config_t    config,
    output ucie_lsm_status_t    status
);
```

**State Machine Hierarchy:**
```
RESET
  │
  ▼
SBINIT (Sideband Initialization)
  │
  ▼
MBINIT (Mainband Initialization)
  ├── MBINIT.PARAM (Parameter Exchange)
  ├── MBINIT.CAL (Calibration)
  ├── MBINIT.REPAIRCLK (Clock Repair)
  ├── MBINIT.REPAIRVAL (Valid Repair)
  ├── MBINIT.REVERSALMB (Lane Reversal)
  └── MBINIT.REPAIRMB (Lane Repair)
  │
  ▼
MBTRAIN (Mainband Training)
  ├── MBTRAIN.VALVREF
  ├── MBTRAIN.DATAVREF
  ├── MBTRAIN.SPEEDIDLE
  ├── MBTRAIN.TXSELFCAL
  ├── MBTRAIN.RXCLKCAL
  ├── MBTRAIN.VALTRAINCENTER
  ├── MBTRAIN.VALTRAINVREF
  ├── MBTRAIN.DATATRAINCENTER1
  ├── MBTRAIN.DATATRAINVREF
  ├── MBTRAIN.RXDESKEW
  ├── MBTRAIN.DATATRAINCENTER2
  ├── MBTRAIN.LINKSPEED
  └── MBTRAIN.REPAIR
  │
  ▼
LINKINIT (Link Initialization)
  │
  ▼
ACTIVE (Normal Operation)
  │
  ├── L1 (Standby)
  ├── L2 (Sleep)
  ├── PHYRETRAIN
  └── TRAINERROR
```

### 2. CRC Generator and Checker

```systemverilog
module ucie_crc_engine #(
    parameter FLIT_WIDTH = 256,
    parameter CRC_WIDTH = 32,
    parameter POLYNOMIAL = 32'h04C11DB7  // CRC-32
) (
    input  logic                clk,
    input  logic                resetn,
    
    // Transmit Path
    input  logic                tx_flit_valid,
    input  logic [FLIT_WIDTH-1:0] tx_flit_data,
    output logic [CRC_WIDTH-1:0]  tx_crc,
    output logic                tx_crc_valid,
    
    // Receive Path
    input  logic                rx_flit_valid,
    input  logic [FLIT_WIDTH-1:0] rx_flit_data,
    input  logic [CRC_WIDTH-1:0]  rx_crc,
    output logic                rx_crc_error,
    output logic                rx_crc_valid,
    
    // Configuration
    input  logic                crc_enable,
    input  logic [CRC_WIDTH-1:0] crc_init_value
);
```

**CRC Implementation Features:**
- **Parallel CRC**: Single-cycle CRC calculation for full flit width
- **Configurable Polynomial**: Support for different CRC types
- **Pipeline Stages**: Optimized for high-speed operation
- **Error Injection**: Built-in test capability

### 3. Retry Buffer Manager

```systemverilog
module ucie_retry_manager #(
    parameter BUFFER_DEPTH = 16,
    parameter FLIT_WIDTH = 256,
    parameter TIMEOUT_CYCLES = 1000
) (
    input  logic                clk,
    input  logic                resetn,
    
    // Transmit Interface
    input  logic                tx_flit_valid,
    input  logic [FLIT_WIDTH-1:0] tx_flit_data,
    input  logic [15:0]         tx_sequence_num,
    output logic                tx_flit_ready,
    
    // Acknowledgment Interface
    input  logic                ack_valid,
    input  logic [15:0]         ack_sequence_num,
    input  logic                nak_valid,
    input  logic [15:0]         nak_sequence_num,
    
    // Retry Interface
    output logic                retry_valid,
    output logic [FLIT_WIDTH-1:0] retry_flit_data,
    output logic [15:0]         retry_sequence_num,
    input  logic                retry_ready,
    
    // Status and Control
    output logic                buffer_full,
    output logic                retry_timeout,
    input  ucie_retry_config_t  config,
    output ucie_retry_status_t  status
);
```

**Retry Mechanism Features:**
- **Circular Buffer**: Efficient storage with wraparound
- **Sequence Tracking**: Automatic sequence number management
- **Timeout Detection**: Configurable retry timeouts
- **Flow Control**: Backpressure when buffer full

### 4. Stack Multiplexer

```systemverilog
module ucie_stack_multiplexer #(
    parameter NUM_STACKS = 2,
    parameter FLIT_WIDTH = 256
) (
    input  logic                clk,
    input  logic                resetn,
    
    // Stack 0 Interface (e.g., PCIe/CXL.io)
    input  logic                stack0_tx_valid,
    input  logic [FLIT_WIDTH-1:0] stack0_tx_data,
    input  ucie_flit_header_t   stack0_tx_header,
    output logic                stack0_tx_ready,
    
    output logic                stack0_rx_valid,
    output logic [FLIT_WIDTH-1:0] stack0_rx_data,
    output ucie_flit_header_t   stack0_rx_header,
    input  logic                stack0_rx_ready,
    
    // Stack 1 Interface (e.g., CXL.cache/mem, Streaming)
    input  logic                stack1_tx_valid,
    input  logic [FLIT_WIDTH-1:0] stack1_tx_data,
    input  ucie_flit_header_t   stack1_tx_header,
    output logic                stack1_tx_ready,
    
    output logic                stack1_rx_valid,
    output logic [FLIT_WIDTH-1:0] stack1_rx_data,
    output ucie_flit_header_t   stack1_rx_header,
    input  logic                stack1_rx_ready,
    
    // Unified Output to Link Layer
    output logic                link_tx_valid,
    output logic [FLIT_WIDTH-1:0] link_tx_data,
    output ucie_flit_header_t   link_tx_header,
    input  logic                link_tx_ready,
    
    // Unified Input from Link Layer
    input  logic                link_rx_valid,
    input  logic [FLIT_WIDTH-1:0] link_rx_data,
    input  ucie_flit_header_t   link_rx_header,
    output logic                link_rx_ready,
    
    // Configuration
    input  ucie_mux_config_t    config,
    output ucie_mux_status_t    status
);
```

### 5. Parameter Exchange Engine

```systemverilog
module ucie_parameter_exchange (
    input  logic                clk,
    input  logic                resetn,
    
    // Sideband Interface
    ucie_sideband_if.master     sideband,
    
    // Local Capabilities
    input  ucie_adapter_cap_t   local_adapter_cap,
    input  ucie_cxl_cap_t       local_cxl_cap,
    input  ucie_multiproto_cap_t local_mp_cap,
    
    // Negotiated Parameters
    output ucie_adapter_cap_t   final_adapter_cap,
    output ucie_cxl_cap_t       final_cxl_cap,
    output ucie_multiproto_cap_t final_mp_cap,
    
    // Control and Status
    input  logic                start_exchange,
    output logic                exchange_complete,
    output logic                exchange_error,
    
    // Configuration
    input  ucie_param_config_t  config,
    output ucie_param_status_t  status
);
```

### 6. Power Management Controller

```systemverilog
module ucie_power_manager (
    input  logic                clk,
    input  logic                resetn,
    
    // Link State Interface
    input  ucie_link_state_t    link_state,
    output ucie_pm_request_t    pm_request,
    input  ucie_pm_response_t   pm_response,
    
    // Protocol Layer Interface
    input  logic                proto_idle,
    input  logic                proto_active,
    output logic                pm_block_new_requests,
    
    // Physical Layer Interface
    output logic                phy_l1_entry_req,
    output logic                phy_l2_entry_req,
    input  logic                phy_l1_entry_ack,
    input  logic                phy_l2_entry_ack,
    input  logic                phy_wake_detected,
    
    // Power States
    output ucie_power_state_t   current_power_state,
    output logic                low_power_mode,
    
    // Configuration
    input  ucie_pm_config_t     config,
    output ucie_pm_status_t     status
);
```

## Data Structure Definitions

### 1. Link State Enumeration

```systemverilog
typedef enum logic [4:0] {
    LINK_RESET           = 5'h00,
    LINK_SBINIT          = 5'h01,
    LINK_MBINIT_PARAM    = 5'h02,
    LINK_MBINIT_CAL      = 5'h03,
    LINK_MBINIT_REPAIR   = 5'h04,
    LINK_MBTRAIN_START   = 5'h08,
    LINK_MBTRAIN_ACTIVE  = 5'h09,
    LINK_LINKINIT        = 5'h10,
    LINK_ACTIVE          = 5'h11,
    LINK_L1              = 5'h12,
    LINK_L2              = 5'h13,
    LINK_PHYRETRAIN      = 5'h14,
    LINK_TRAINERROR      = 5'h15,
    LINK_DISABLED        = 5'h1F
} ucie_link_state_t;
```

### 2. Capability Structures

```systemverilog
typedef struct packed {
    logic [7:0]   adapter_version;
    logic [15:0]  supported_speeds;      // Bitmask: [32,24,16,12,8,4]GT/s
    logic [7:0]   supported_widths;      // Bitmask: [64,32,16,8]
    logic         cxl_256b_flit_mode;
    logic         cxl_68b_flit_mode;
    logic         streaming_protocol;
    logic         management_transport;
    logic         raw_mode;
    logic [7:0]   max_modules;
    logic [15:0]  retry_buffer_depth;
} ucie_adapter_cap_t;

typedef struct packed {
    logic         cxl_io_supported;
    logic         cxl_cache_supported;
    logic         cxl_mem_supported;
    logic [7:0]   cxl_version;
    logic [15:0]  cache_size_kb;
    logic [7:0]   num_cxl_ports;
    logic [31:0]  mem_size_mb;
} ucie_cxl_cap_t;
```

### 3. Flit Header Structure

```systemverilog
typedef struct packed {
    logic [2:0]   format_type;
    logic [4:0]   protocol_id;
    logic [7:0]   length;
    logic [3:0]   vc_id;
    logic [15:0]  sequence_num;
    logic [7:0]   msg_class;
    logic [7:0]   msg_route;
    logic [31:0]  reserved;
} ucie_flit_header_t;
```

## Error Handling and Recovery

### 1. Error Detection Hierarchy

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   CRC Errors    │    │  Timeout Errors │    │ Protocol Errors │
│   - Corrupted   │───►│  - Retry timeout│───►│ - Invalid flit  │
│     flits       │    │  - Ack timeout  │    │ - Sequence err  │
│   - Bad CRC     │    │  - Training TO  │    │ - Format error  │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         └───────────────────────┼───────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │   Error Response        │
                    │   - Retry request       │
                    │   - Link retrain        │
                    │   - Error reporting     │
                    │   - Recovery action     │
                    └─────────────────────────┘
```

### 2. Recovery State Machine

```systemverilog
typedef enum logic [2:0] {
    RECOVERY_IDLE        = 3'h0,
    RECOVERY_RETRY       = 3'h1,
    RECOVERY_RETRAIN     = 3'h2,
    RECOVERY_RESET       = 3'h3,
    RECOVERY_DISABLED    = 3'h4
} ucie_recovery_state_t;
```

## Performance Features

### 1. Pipelining Architecture
- **3-Stage Pipeline**: Receive → Process → Transmit
- **Parallel CRC**: CRC calculation concurrent with data processing
- **Look-ahead Processing**: Predict next flit requirements

### 2. Buffer Optimization
- **Adaptive Sizing**: Dynamic buffer allocation based on link characteristics
- **Multi-Priority**: Separate buffers for different traffic classes
- **Credit Management**: Precise flow control to prevent overflow

### 3. Low-Latency Optimizations
- **Cut-through Forwarding**: Start transmission before complete packet received
- **Zero-Copy Retry**: In-place retry without additional copying
- **Fast State Transitions**: Optimized state machine timing

## Configuration Interfaces

### 1. Runtime Configuration

```systemverilog
typedef struct packed {
    logic [15:0]  max_retry_count;
    logic [31:0]  retry_timeout_cycles;
    logic [7:0]   pm_idle_threshold;
    logic [7:0]   pm_l1_timeout;
    logic [15:0]  pm_l2_timeout;
    logic         auto_retry_enable;
    logic         pm_enable;
    logic [3:0]   error_threshold;
} ucie_d2d_config_t;
```

### 2. Debug and Monitoring

```systemverilog
typedef struct packed {
    logic [31:0]  flits_transmitted;
    logic [31:0]  flits_received;
    logic [31:0]  crc_errors;
    logic [31:0]  retry_count;
    logic [31:0]  timeouts;
    logic [15:0]  current_retry_buffer_usage;
    logic [7:0]   link_utilization_percent;
    logic [31:0]  power_state_time[4];  // Time in each power state
} ucie_d2d_status_t;
```

## Integration Points

### 1. Protocol Layer Interface
- **Flit-based Communication**: Standardized flit format exchange
- **Flow Control**: Credit-based backpressure
- **Error Reporting**: Protocol-specific error indication

### 2. Physical Layer Interface
- **State Coordination**: Link training and power management
- **Parameter Exchange**: Capability negotiation
- **Error Detection**: Physical layer error reporting

## Verification Considerations

### 1. Test Scenarios
- **Normal Operation**: Standard flit transmission and reception
- **Error Injection**: CRC errors, timeouts, protocol violations
- **Power Management**: L1/L2 entry/exit sequences
- **Link Training**: Complete initialization flow

### 2. Coverage Metrics
- **State Machine Coverage**: All states and transitions
- **Error Path Coverage**: All error conditions and recovery
- **Protocol Coverage**: All supported protocol combinations
- **Performance Coverage**: Bandwidth and latency targets

## Next Steps

1. **State Machine Implementation**: Complete link training flow
2. **CRC Engine Development**: Optimized parallel CRC calculation
3. **Retry Logic**: Robust buffer management and timeout handling
4. **Power Management**: Full L0/L1/L2 state support
5. **Integration Testing**: End-to-end protocol flow validation