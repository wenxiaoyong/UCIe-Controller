# UCIe Protocol Layer Architecture

## Overview
The Protocol Layer provides multi-protocol support for PCIe, CXL, Streaming, and Management Transport protocols. It handles protocol-specific packet processing, flit formatting, and flow control while presenting unified interfaces to the D2D Adapter.

## Protocol Layer Block Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              Protocol Layer                                 │
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────────────┐ │
│  │    PCIe     │  │     CXL     │  │  Streaming  │  │     Management      │ │
│  │   Engine    │  │   Engine    │  │   Engine    │  │   Transport Engine  │ │
│  │             │  │             │  │             │  │                     │ │
│  └─────────────┘  └─────────────┘  └─────────────┘  └─────────────────────┘ │
│         │                 │                 │                     │          │
│         └─────────────────┼─────────────────┼─────────────────────┘          │
│                           │                 │                                │
│  ┌─────────────────────────▼─────────────────▼──────────────────────────────┐ │
│  │                  Protocol Arbiter & Multiplexer                         │ │
│  │  ┌──────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐│ │
│  │  │   Protocol   │ │    Flit      │ │    Flow      │ │     Credit       ││ │
│  │  │ Negotiation  │ │  Formatter   │ │   Control    │ │   Management     ││ │
│  │  └──────────────┘ └──────────────┘ └──────────────┘ └──────────────────┘│ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
│                                       │                                       │
│                                       ▼                                       │
│  ┌───────────────────────────────────────────────────────────────────────────┐ │
│  │                      Common Flit Interface                               │ │
│  │                 (to/from D2D Adapter)                                    │ │
│  └───────────────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Protocol Engine Designs

### 1. PCIe Protocol Engine (128 Gbps Enhanced)

```systemverilog
module ucie_pcie_engine #(
    parameter DATA_WIDTH = 512,
    parameter FLIT_WIDTH = 256,
    parameter MAX_SPEED_GBPS = 128,    // Enhanced to support 128 Gbps
    parameter NUM_PARALLEL_ENGINES = 4  // 4x parallel for 128 Gbps
) (
    input  logic                clk,
    input  logic                clk_quarter_rate,  // 16 GHz for 128 Gbps
    input  logic                resetn,
    
    // PCIe TLP Interface (Enhanced bandwidth)
    input  logic [NUM_PARALLEL_ENGINES-1:0] pcie_tx_valid,
    input  logic [DATA_WIDTH-1:0] pcie_tx_data [NUM_PARALLEL_ENGINES-1:0],
    input  logic [3:0]          pcie_tx_keep [NUM_PARALLEL_ENGINES-1:0],
    output logic [NUM_PARALLEL_ENGINES-1:0] pcie_tx_ready,
    
    output logic [NUM_PARALLEL_ENGINES-1:0] pcie_rx_valid,
    output logic [DATA_WIDTH-1:0] pcie_rx_data [NUM_PARALLEL_ENGINES-1:0],
    output logic [3:0]          pcie_rx_keep [NUM_PARALLEL_ENGINES-1:0],
    input  logic [NUM_PARALLEL_ENGINES-1:0] pcie_rx_ready,
    
    // Enhanced Flit Interface for 128 Gbps
    output logic                flit_tx_valid,
    output logic [FLIT_WIDTH*4-1:0] flit_tx_data,  // 4x width for 128 Gbps
    output ucie_flit_header_t   flit_tx_header,
    input  logic                flit_tx_ready,
    
    input  logic                flit_rx_valid,
    input  logic [FLIT_WIDTH*4-1:0] flit_rx_data,  // 4x width for 128 Gbps
    input  ucie_flit_header_t   flit_rx_header,
    output logic                flit_rx_ready,
    
    // Enhanced Control and Status
    input  ucie_pcie_config_t   config,
    output ucie_pcie_status_t   status,
    
    // 128 Gbps Performance Monitoring
    output logic [31:0]         bandwidth_utilization_percent,
    output logic [15:0]         latency_cycles,
    output logic [31:0]         throughput_mbps
);
```

**Key Features:**
- **TLP to Flit Conversion**: Maps PCIe TLPs to UCIe flit formats
- **Multiple Flit Formats**: 68B, 256B standard, and latency-optimized
- **Header Processing**: PCIe header mapping to UCIe flit headers
- **Flow Control**: Credit-based backpressure management
- **128 Gbps Enhancements**:
  - **4x Parallel Engines**: Concurrent processing for 128 Gbps throughput
  - **Quarter-Rate Processing**: 16 GHz internal clock for power efficiency
  - **Enhanced Buffering**: QDR SRAM with 4x scaling for latency targets
  - **Bandwidth Monitoring**: Real-time throughput and utilization tracking

### 2. CXL Protocol Engine (128 Gbps Enhanced)

```systemverilog
module ucie_cxl_engine #(
    parameter SUPPORT_IO = 1,
    parameter SUPPORT_CACHE = 1,
    parameter SUPPORT_MEM = 1,
    parameter MAX_SPEED_GBPS = 128,        // Enhanced to 128 Gbps
    parameter NUM_PARALLEL_STACKS = 4      // 4x parallel stacks for bandwidth
) (
    input  logic                clk,
    input  logic                clk_quarter_rate,  // 16 GHz for 128 Gbps
    input  logic                resetn,
    
    // CXL.io Interface (Enhanced)
    cxl_io_if.device            cxl_io [NUM_PARALLEL_STACKS-1:0],
    
    // CXL.cache Interface (Enhanced)
    cxl_cache_if.device         cxl_cache [NUM_PARALLEL_STACKS-1:0],
    
    // CXL.mem Interface (Enhanced)
    cxl_mem_if.device           cxl_mem [NUM_PARALLEL_STACKS-1:0],
    
    // Enhanced Multi-Stack Flit Interface for 128 Gbps
    output logic [NUM_PARALLEL_STACKS-1:0] stack_tx_valid,
    output ucie_flit_t [NUM_PARALLEL_STACKS-1:0] stack_tx_flit,
    input  logic [NUM_PARALLEL_STACKS-1:0] stack_tx_ready,
    
    input  logic [NUM_PARALLEL_STACKS-1:0] stack_rx_valid,
    input  ucie_flit_t [NUM_PARALLEL_STACKS-1:0] stack_rx_flit,
    output logic [NUM_PARALLEL_STACKS-1:0] stack_rx_ready,
    
    // Enhanced Configuration and Status
    input  ucie_cxl_config_t    config,
    output ucie_cxl_status_t    status,
    
    // 128 Gbps Performance Monitoring
    output logic [31:0]         cache_hit_rate_percent,
    output logic [31:0]         memory_bandwidth_mbps,
    output logic [15:0]         coherency_latency_ns
);
```

**Key Features:**
- **Multi-Stack Support**: Independent I/O and cache/memory stacks
- **68B and 256B Modes**: Optimized flit formats for different use cases
- **Protocol Multiplexing**: ARB/MUX between CXL sub-protocols
- **Coherency Support**: Cache protocol state management
- **128 Gbps Enhancements**:
  - **4x Parallel Stacks**: Concurrent CXL.io + CXL.cache/mem processing
  - **Enhanced Coherency**: Ultra-low latency cache coherency for 128 Gbps
  - **Memory Bandwidth Scaling**: 4x memory interface bandwidth
  - **Advanced Monitoring**: Cache hit rates and coherency latency tracking

### 3. Streaming Protocol Engine

```systemverilog
module ucie_streaming_engine #(
    parameter DATA_WIDTH = 512,
    parameter MAX_PACKET_SIZE = 4096
) (
    input  logic                clk,
    input  logic                resetn,
    
    // Generic Streaming Interface
    input  logic                stream_tx_valid,
    input  logic [DATA_WIDTH-1:0] stream_tx_data,
    input  logic                stream_tx_sop,
    input  logic                stream_tx_eop,
    input  logic [5:0]          stream_tx_empty,
    output logic                stream_tx_ready,
    
    output logic                stream_rx_valid,
    output logic [DATA_WIDTH-1:0] stream_rx_data,
    output logic                stream_rx_sop,
    output logic                stream_rx_eop,
    output logic [5:0]          stream_rx_empty,
    input  logic                stream_rx_ready,
    
    // Flit Interface
    output logic                flit_tx_valid,
    output ucie_flit_t          flit_tx_data,
    input  logic                flit_tx_ready,
    
    input  logic                flit_rx_valid,
    input  ucie_flit_t          flit_rx_data,
    output logic                flit_rx_ready,
    
    // Configuration
    input  ucie_streaming_config_t config,
    output ucie_streaming_status_t status
);
```

**Key Features:**
- **Generic Packet Interface**: Support for any streaming protocol
- **Packetization**: Automatic segmentation into UCIe flits
- **Flow Control**: Stream-level and flit-level flow control
- **Latency Optimization**: Direct packet-to-flit mapping

## Flit Format Processing

### 1. Flit Formatter

```systemverilog
module ucie_flit_formatter (
    input  logic                clk,
    input  logic                resetn,
    
    // Protocol Input
    input  logic                proto_valid,
    input  ucie_proto_packet_t  proto_packet,
    input  ucie_protocol_type_t proto_type,
    output logic                proto_ready,
    
    // Flit Output
    output logic                flit_valid,
    output ucie_flit_t          flit_data,
    input  logic                flit_ready,
    
    // Configuration
    input  ucie_flit_config_t   config
);
```

**Supported Flit Formats:**
1. **Raw Format**: Protocol-agnostic passthrough
2. **68B Flit Format**: Compact format for low-latency
3. **Standard 256B**: Full-featured format with all fields
4. **Latency-Optimized 256B**: Reduced header overhead

### 2. Flit Parser

```systemverilog
module ucie_flit_parser (
    input  logic                clk,
    input  logic                resetn,
    
    // Flit Input
    input  logic                flit_valid,
    input  ucie_flit_t          flit_data,
    output logic                flit_ready,
    
    // Protocol Output
    output logic                proto_valid,
    output ucie_proto_packet_t  proto_packet,
    output ucie_protocol_type_t proto_type,
    input  logic                proto_ready,
    
    // Status
    output ucie_parse_status_t  status
);
```

## Protocol Arbitration and Multiplexing

### 1. Stack Multiplexer

```systemverilog
module ucie_stack_mux #(
    parameter NUM_STACKS = 2,
    parameter NUM_PROTOCOLS = 4
) (
    input  logic                    clk,
    input  logic                    resetn,
    
    // Protocol Inputs
    input  logic [NUM_PROTOCOLS-1:0]     proto_tx_valid,
    input  ucie_flit_t [NUM_PROTOCOLS-1:0] proto_tx_flit,
    input  logic [1:0] [NUM_PROTOCOLS-1:0] proto_stack_sel,
    output logic [NUM_PROTOCOLS-1:0]     proto_tx_ready,
    
    // Stack Outputs
    output logic [NUM_STACKS-1:0]        stack_tx_valid,
    output ucie_flit_t [NUM_STACKS-1:0]  stack_tx_flit,
    input  logic [NUM_STACKS-1:0]        stack_tx_ready,
    
    // Arbitration Configuration
    input  ucie_arb_config_t             arb_config
);
```

**Arbitration Schemes:**
- **Round Robin**: Fair scheduling between protocols
- **Priority Based**: Protocol-specific priority levels
- **Weighted Fair**: Bandwidth allocation per protocol
- **Dynamic**: Runtime adjustable based on traffic

### 2. Flow Control Manager

```systemverilog
module ucie_flow_control #(
    parameter NUM_VCS = 8,
    parameter CREDIT_WIDTH = 8
) (
    input  logic                clk,
    input  logic                resetn,
    
    // Credit Interface
    output logic [NUM_VCS-1:0]  credit_request,
    input  logic [NUM_VCS-1:0]  credit_grant,
    input  logic [CREDIT_WIDTH-1:0] credit_count [NUM_VCS-1:0],
    
    // Flow Control to Protocols
    output logic [NUM_VCS-1:0]  fc_ready,
    input  logic [NUM_VCS-1:0]  fc_consume,
    
    // Remote Credit Updates
    input  logic                remote_credit_valid,
    input  ucie_credit_update_t remote_credit_update,
    
    // Configuration
    input  ucie_fc_config_t     config,
    output ucie_fc_status_t     status
);
```

## Data Type Definitions

### 1. Flit Structure

```systemverilog
typedef struct packed {
    logic [7:0]   format_type;
    logic [15:0]  length;
    logic [7:0]   protocol_id;
    logic [7:0]   vc_id;
    logic [15:0]  sequence_num;
    logic [31:0]  crc;
    logic [2047:0] payload;  // Variable based on format
} ucie_flit_t;

typedef enum logic [2:0] {
    RAW_FORMAT        = 3'b000,
    FLIT_68B         = 3'b001,
    FLIT_256B_STD    = 3'b010,
    FLIT_256B_LAT_OPT = 3'b011
} ucie_flit_format_t;
```

### 2. Protocol Types

```systemverilog
typedef enum logic [3:0] {
    PROTOCOL_PCIE    = 4'h0,
    PROTOCOL_CXL_IO  = 4'h1,
    PROTOCOL_CXL_CACHE = 4'h2,
    PROTOCOL_CXL_MEM = 4'h3,
    PROTOCOL_STREAMING = 4'h4,
    PROTOCOL_MGMT    = 4'h5,
    PROTOCOL_RAW     = 4'hF
} ucie_protocol_type_t;
```

## 128 Gbps Protocol Layer Architecture

### 1. Parallel Protocol Processing Framework

```systemverilog
module ucie_128g_protocol_layer #(
    parameter NUM_PARALLEL_ENGINES = 4,
    parameter ENGINE_BANDWIDTH_GBPS = 32
) (
    input  logic                     clk_quarter_rate,  // 16 GHz
    input  logic                     clk_symbol_rate,   // 64 GHz
    input  logic                     resetn,
    
    // 128 Gbps Aggregate Interface
    input  logic [1023:0]            protocol_data_128g,
    input  ucie_protocol_header_t    protocol_header_128g,
    input  logic                     protocol_valid_128g,
    output logic                     protocol_ready_128g,
    
    // Per-Engine Distribution
    output logic [255:0]             engine_data [NUM_PARALLEL_ENGINES-1:0],
    output ucie_protocol_header_t    engine_header [NUM_PARALLEL_ENGINES-1:0],
    output logic [NUM_PARALLEL_ENGINES-1:0] engine_valid,
    input  logic [NUM_PARALLEL_ENGINES-1:0] engine_ready,
    
    // Enhanced Flow Control for 128 Gbps
    input  ucie_128g_flow_control_t  flow_control_config,
    output ucie_128g_flow_status_t   flow_control_status
);
```

### 2. Enhanced Buffer Architecture for 128 Gbps

```systemverilog
module ucie_128g_protocol_buffers #(
    parameter BUFFER_DEPTH_RATIO = 4,    // 4x deeper for same latency
    parameter QDR_FREQ_MHZ = 500         // 500 MHz QDR SRAM
) (
    input  logic                     clk_qdr,
    input  logic                     resetn,
    
    // 128 Gbps Buffer Interface
    input  logic [1023:0]            wr_data_128g,
    input  logic                     wr_valid_128g,
    output logic                     wr_ready_128g,
    
    output logic [1023:0]            rd_data_128g,
    output logic                     rd_valid_128g,
    input  logic                     rd_ready_128g,
    
    // Hierarchical Buffer Management
    input  ucie_buffer_config_t      buffer_config,
    output ucie_buffer_status_t      buffer_status,
    
    // Performance Monitoring
    output logic [31:0]              buffer_utilization_percent,
    output logic [15:0]              average_latency_cycles
);
```

## Performance Optimizations

### 1. Enhanced Pipeline Architecture (128 Gbps)
- **8-Stage Ultra-High Speed Pipeline**: Optimized for 128 Gbps throughput
- **Quarter-Rate Processing**: 16 GHz internal operation for power efficiency
- **Parallel Processing**: 4x concurrent protocol engines
- **Zero-Latency Bypass**: Direct routing for management and urgent CXL.cache

### 2. Advanced Buffer Management (128 Gbps)
- **QDR SRAM Buffers**: 500 MHz quad-data-rate for high bandwidth
- **Hierarchical Buffering**: L1 (fast), L2 (medium), L3 (large) buffer tiers
- **Predictive Prefetching**: 10-20 cycle lookahead for reduced latency
- **4x Buffer Scaling**: Maintains latency targets at 4x bandwidth

### 3. Ultra-Low-Latency Features (128 Gbps)
- **Single-Cycle Cut-Through**: Immediate transmission at 128 Gbps
- **ML-Enhanced Header Prediction**: AI-driven traffic pattern analysis
- **Zero-Latency Bypass Paths**: Direct routes with 1-cycle latency
- **Advanced Look-Ahead**: Multi-cycle protocol processing prediction

## Configuration and Control

### 1. Protocol Negotiation
- **Capability Advertisement**: Supported protocols and formats
- **Parameter Exchange**: Speed, width, protocol selection
- **Runtime Reconfiguration**: Dynamic protocol switching

### 2. Debug and Monitoring
- **Protocol Counters**: Per-protocol traffic statistics
- **Error Detection**: Format validation and reporting
- **Trace Capture**: Protocol transaction logging

## Integration with D2D Adapter

### 1. Interface Signals
```systemverilog
interface ucie_protocol_if #(
    parameter FLIT_WIDTH = 256
);
    logic                   flit_tx_valid;
    logic [FLIT_WIDTH-1:0]  flit_tx_data;
    logic                   flit_tx_ready;
    logic                   flit_rx_valid;
    logic [FLIT_WIDTH-1:0]  flit_rx_data;
    logic                   flit_rx_ready;
    
    logic                   credit_update_valid;
    ucie_credit_update_t    credit_update;
    
    logic                   error_detected;
    ucie_error_info_t       error_info;
    
    modport protocol (
        output flit_tx_valid, flit_tx_data,
        input  flit_tx_ready,
        input  flit_rx_valid, flit_rx_data,
        output flit_rx_ready,
        output credit_update_valid, credit_update,
        output error_detected, error_info
    );
endinterface
```

### 2. Control Interface
- **Protocol Enable/Disable**: Runtime protocol control
- **Error Reporting**: Protocol-specific error conditions
- **Performance Monitoring**: Bandwidth and latency metrics

## Next Steps

1. **Detailed Protocol Mappings**: Complete flit format implementations
2. **Flow Control Design**: Credit-based backpressure mechanisms
3. **Arbitration Logic**: Fair and efficient protocol scheduling
4. **Verification Plan**: Protocol-specific test scenarios