# UCIe Protocol Layer Micro Architecture Specification (MAS)

## Document Information
- **Document**: Protocol Layer MAS v1.0
- **Project**: UCIe Controller RTL Implementation
- **Layer**: Protocol Layer (Layer 1 of 4)
- **Date**: 2025-07-25
- **Status**: Implementation Ready

---

## 1. Executive Summary

The Protocol Layer MAS defines the detailed micro-architecture for the UCIe controller's protocol processing subsystem. This layer handles multi-protocol packet processing, flit format conversion, flow control, and arbitration for PCIe, CXL, Streaming, and Management Transport protocols.

### Key Capabilities
- **Multi-Protocol Support**: Concurrent PCIe, CXL (I/O + Cache/Mem), Streaming, Management Transport
- **Flit Processing**: Raw, 68B, 256B standard/latency-optimized format support
- **Flow Control**: Credit-based backpressure with virtual channel management
- **Performance**: 3-stage pipeline with single-cycle flit processing capability
- **Scalability**: Up to 128 Gbps per lane with quarter-rate processing

---

## 2. Module Hierarchy and Architecture

### 2.1 Top-Level Module Structure

```systemverilog
module ucie_protocol_layer #(
    parameter int PROTOCOL_MASK    = 4'b1111,  // PCIe|CXL|Stream|Mgmt
    parameter int MAX_SPEED_GT_S   = 128,       // Maximum speed in GT/s
    parameter int MODULE_WIDTH     = 64,        // x8, x16, x32, x64
    parameter int PACKAGE_TYPE     = 2,         // 0=Std, 1=Adv, 2=3D
    parameter int NUM_VIRTUAL_CH   = 8,         // Virtual channels
    parameter int FLIT_BUFFER_DEPTH = 16       // Per-protocol buffer depth
) (
    // Clock and Reset
    input  logic                    clk_protocol,      // Protocol domain clock
    input  logic                    clk_aux,           // Auxiliary clock (800MHz)
    input  logic                    rst_n,             // Active-low reset
    
    // FDI Interface (to D2D Adapter)
    ucie_fdi_if.protocol           fdi_tx,            // FDI transmit
    ucie_fdi_if.protocol           fdi_rx,            // FDI receive
    
    // RDI Interface (to D2D Adapter)  
    ucie_rdi_if.protocol           rdi_tx,            // RDI transmit
    ucie_rdi_if.protocol           rdi_rx,            // RDI receive
    
    // Protocol-Specific Interfaces
    ucie_pcie_if.device            pcie_if,           // PCIe interface
    ucie_cxl_if.device             cxl_if,            // CXL interface
    ucie_streaming_if.device       stream_if,         // Streaming interface
    ucie_mgmt_if.device            mgmt_if,           // Management interface
    
    // Configuration and Control
    input  logic [31:0]            protocol_config,   // Protocol configuration
    input  logic [7:0]             flow_control_cfg,  // Flow control settings
    output logic [31:0]            protocol_status,   // Protocol status
    output logic [15:0]            performance_counters, // Performance metrics
    
    // Debug and Test
    input  logic                   debug_enable,      // Debug mode enable
    output logic [63:0]            debug_data,        // Debug information
    input  logic [3:0]             test_mode          // Test mode selection
);
```

### 2.2 Sublayer Module Breakdown

#### 2.2.1 Protocol Engines (ucie_protocol_engines.sv)
```systemverilog
module ucie_protocol_engines #(
    parameter int PROTOCOL_MASK = 4'b1111,
    parameter int MODULE_WIDTH  = 64
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Individual Protocol Interfaces
    ucie_pcie_if.engine        pcie_if,
    ucie_cxl_if.engine         cxl_if, 
    ucie_streaming_if.engine   stream_if,
    ucie_mgmt_if.engine        mgmt_if,
    
    // Internal Flit Processing
    output flit_packet_t       tx_flit_out,
    output logic               tx_flit_valid,
    input  logic               tx_flit_ready,
    
    input  flit_packet_t       rx_flit_in,
    input  logic               rx_flit_valid,
    output logic               rx_flit_ready,
    
    // Engine Status
    output logic [3:0]         engine_active,
    output logic [3:0]         engine_error
);
```

#### 2.2.2 Flit Processor (ucie_flit_processor.sv)
```systemverilog
module ucie_flit_processor #(
    parameter int FLIT_WIDTH = 256,
    parameter int PIPELINE_STAGES = 3
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Raw Protocol Data Input
    input  protocol_packet_t    protocol_in,
    input  logic [3:0]          protocol_type,  // 0=PCIe, 1=CXL, 2=Stream, 3=Mgmt
    input  logic                protocol_valid,
    output logic                protocol_ready,
    
    // Formatted Flit Output
    output flit_packet_t        flit_out,
    output logic                flit_valid,
    input  logic                flit_ready,
    
    // Flit Format Control
    input  logic [1:0]          flit_format,    // 0=Raw, 1=68B, 2=256B std, 3=256B LO
    input  logic                latency_opt,    // Latency optimization enable
    
    // Pipeline Status
    output logic [2:0]          pipeline_occupancy,
    output logic                pipeline_stall
);
```

#### 2.2.3 Flow Control Manager (ucie_flow_control.sv)
```systemverilog
module ucie_flow_control #(
    parameter int NUM_VIRTUAL_CH = 8,
    parameter int CREDIT_WIDTH   = 8,
    parameter int MAX_CREDITS    = 255
) (
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Transmit Flow Control
    input  logic [NUM_VIRTUAL_CH-1:0]  tx_vc_request,
    input  logic [7:0]                  tx_vc_credits_needed,
    output logic [NUM_VIRTUAL_CH-1:0]  tx_vc_grant,
    output logic [7:0]                  tx_vc_credits_avail,
    
    // Receive Flow Control  
    input  logic [NUM_VIRTUAL_CH-1:0]  rx_vc_consumed,
    input  logic [7:0]                  rx_vc_credits_used,
    output logic [NUM_VIRTUAL_CH-1:0]  rx_vc_credit_update,
    output logic [7:0]                  rx_vc_credits_returned,
    
    // Credit Management Interface
    input  logic [NUM_VIRTUAL_CH-1:0]  credit_init,
    input  logic [7:0]                  initial_credits,
    output logic [NUM_VIRTUAL_CH-1:0]  credit_underflow,
    output logic [NUM_VIRTUAL_CH-1:0]  credit_overflow,
    
    // Configuration
    input  logic [7:0]                  vc_config [NUM_VIRTUAL_CH-1:0],
    output logic [15:0]                 fc_status
);
```

#### 2.2.4 Protocol Buffers (ucie_protocol_buffers.sv)
```systemverilog
module ucie_protocol_buffers #(
    parameter int BUFFER_DEPTH = 16,
    parameter int FLIT_WIDTH   = 256,
    parameter int NUM_PROTOCOLS = 4
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Input Buffer Interfaces (one per protocol)
    input  flit_packet_t        tx_flit_in [NUM_PROTOCOLS-1:0],
    input  logic [NUM_PROTOCOLS-1:0] tx_valid_in,
    output logic [NUM_PROTOCOLS-1:0] tx_ready_out,
    
    // Output to Arbitration
    output flit_packet_t        tx_flit_out [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] tx_valid_out,
    input  logic [NUM_PROTOCOLS-1:0] tx_ready_in,
    
    // Receive Buffer Interfaces  
    input  flit_packet_t        rx_flit_in,
    input  logic [3:0]          rx_protocol_id,
    input  logic                rx_valid_in,
    output logic                rx_ready_out,
    
    output flit_packet_t        rx_flit_out [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] rx_valid_out,
    input  logic [NUM_PROTOCOLS-1:0] rx_ready_in,
    
    // Buffer Status
    output logic [7:0]          buffer_occupancy [NUM_PROTOCOLS-1:0],
    output logic [NUM_PROTOCOLS-1:0] buffer_full,
    output logic [NUM_PROTOCOLS-1:0] buffer_empty,
    output logic [NUM_PROTOCOLS-1:0] buffer_almost_full
);
```

#### 2.2.5 Arbitration and Multiplexing (ucie_arb_mux.sv)
```systemverilog
module ucie_arb_mux #(
    parameter int NUM_INPUTS     = 4,
    parameter int FLIT_WIDTH     = 256,
    parameter int ARB_ALGORITHM  = 0  // 0=RR, 1=Priority, 2=Weighted
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Input Interfaces
    input  flit_packet_t        flit_in [NUM_INPUTS-1:0],
    input  logic [NUM_INPUTS-1:0] valid_in,
    output logic [NUM_INPUTS-1:0] ready_out,
    
    // Output Interface
    output flit_packet_t        flit_out,
    output logic                valid_out,
    input  logic                ready_in,
    
    // Arbitration Control
    input  logic [7:0]          priority [NUM_INPUTS-1:0],   // Priority weights
    input  logic [NUM_INPUTS-1:0] arb_enable,              // Per-input enable
    
    // Arbitration Status
    output logic [NUM_INPUTS-1:0] grant_vector,            // Current grants
    output logic [7:0]          arb_history,               // Grant history
    output logic                arb_conflict                // Arbitration conflict
);
```

---

## 3. Data Structures and Interfaces

### 3.1 Flit Packet Structure
```systemverilog
typedef struct packed {
    logic [7:0]     flit_type;      // Flit type identifier
    logic [3:0]     protocol_id;    // Protocol identifier  
    logic [3:0]     virtual_ch;     // Virtual channel
    logic [15:0]    length;         // Payload length
    logic [31:0]    header;         // Protocol header
    logic [255:0]   payload;        // Flit payload data
    logic [31:0]    crc;            // Flit CRC
    logic           sop;            // Start of packet
    logic           eop;            // End of packet
    logic [7:0]     reserved;       // Reserved fields
} flit_packet_t;
```

### 3.2 Protocol Packet Structure
```systemverilog
typedef struct packed {
    logic [3:0]     protocol_type;  // Protocol type
    logic [7:0]     packet_type;    // Packet type within protocol
    logic [15:0]    packet_length;  // Total packet length
    logic [63:0]    address;        // Address field (if applicable)
    logic [31:0]    control;        // Control information
    logic [511:0]   data;           // Protocol data payload
    logic           valid;          // Data valid
    logic [7:0]     byte_enable;    // Byte enable mask
} protocol_packet_t;
```

### 3.3 Flow Control Structure
```systemverilog
typedef struct packed {
    logic [7:0]     credits_avail;  // Available credits
    logic [7:0]     credits_used;   // Credits consumed
    logic           update_req;     // Credit update request
    logic           grant;          // Flow control grant
    logic [3:0]     vc_id;          // Virtual channel ID
} flow_control_t;
```

---

## 4. Functional Specifications

### 4.1 Protocol Processing Pipeline

#### Stage 1: Protocol Recognition and Parsing
- **Duration**: 1 clock cycle
- **Function**: Identify incoming protocol type and parse headers
- **Inputs**: Raw protocol packets from protocol interfaces
- **Outputs**: Parsed protocol information and payload data

#### Stage 2: Flit Format Conversion  
- **Duration**: 1 clock cycle
- **Function**: Convert protocol packets to UCIe flit format
- **Processing**: 
  - Header mapping according to protocol-specific rules
  - Payload segmentation for large packets
  - CRC calculation and insertion
  - Start/End of packet marking

#### Stage 3: Flow Control and Arbitration
- **Duration**: 1 clock cycle
- **Function**: Apply flow control and arbitrate between protocols
- **Processing**:
  - Credit availability checking
  - Virtual channel assignment
  - Protocol prioritization
  - Output scheduling

### 4.2 Protocol-Specific Processing

#### 4.2.1 PCIe Protocol Engine
```systemverilog
// PCIe TLP Processing
typedef struct packed {
    logic [2:0]     fmt;            // Format field
    logic [4:0]     type_field;     // Type field  
    logic           tc;             // Traffic class
    logic [9:0]     length;         // Length in DW
    logic [15:0]    requester_id;   // Requester ID
    logic [7:0]     tag;            // Transaction tag
    logic [63:0]    address;        // Memory address
    logic [31:0]    data [];        // Payload data
} pcie_tlp_t;

// Processing Steps:
// 1. TLP header parsing and validation
// 2. Address translation (if required)
// 3. Flow control credit management
// 4. Flit format conversion (TLP → UCIe flit)
// 5. Error checking and reporting
```

#### 4.2.2 CXL Protocol Engine
```systemverilog
// CXL Multi-Stack Support
typedef enum logic [1:0] {
    CXL_IO    = 2'b00,  // CXL.io (PCIe-based)
    CXL_CACHE = 2'b01,  // CXL.cache 
    CXL_MEM   = 2'b10   // CXL.mem
} cxl_stack_t;

typedef struct packed {
    cxl_stack_t     stack;          // CXL stack type
    logic [2:0]     opcode;         // CXL opcode
    logic [47:0]    address;        // Physical address
    logic [5:0]     cache_id;       // Cache ID (for .cache)
    logic [511:0]   data;           // Data payload
    logic [7:0]     meta;           // Metadata
} cxl_packet_t;

// Processing Features:
// - Concurrent I/O + Cache/Memory operation
// - Coherency protocol handling
// - Memory semantic preservation  
// - Cache line management
```

#### 4.2.3 Streaming Protocol Engine
```systemverilog
// User-Defined Streaming Protocol
typedef struct packed {
    logic [15:0]    stream_id;      // Stream identifier
    logic [7:0]     stream_type;    // User-defined type
    logic [31:0]    sequence_num;   // Sequence number
    logic [15:0]    payload_len;    // Payload length
    logic [1023:0]  payload_data;   // Variable payload
    logic           flow_control;   // Flow control enable
} streaming_packet_t;

// Configurable Features:
// - User-defined packet formats
// - Configurable flow control
// - Stream multiplexing
// - Quality of service support
```

#### 4.2.4 Management Transport Engine
```systemverilog
// UCIe Management Protocol
typedef struct packed {
    logic [7:0]     mgmt_type;      // Management packet type
    logic [15:0]    target_id;      // Target device ID
    logic [31:0]    register_addr;  // Register address
    logic [31:0]    data;           // Register data
    logic           read_write;     // 0=read, 1=write
    logic [7:0]     byte_enable;    // Byte enable
} mgmt_packet_t;

// Management Functions:
// - Register access and configuration
// - Error reporting and handling
// - Performance monitoring
// - Debug and test support
```

### 4.3 Flow Control Mechanisms

#### 4.3.1 Credit-Based Flow Control
- **Credit Pool**: 256 credits per virtual channel
- **Credit Granularity**: Per-flit credit consumption
- **Update Frequency**: Every 4 clock cycles or on threshold
- **Backpressure**: Automatic when credits < threshold

#### 4.3.2 Virtual Channel Management
- **Number of VCs**: 8 virtual channels (configurable)
- **VC Assignment**: Based on protocol type and QoS
- **VC Arbitration**: Weighted fair queuing algorithm
- **VC Status**: Individual occupancy and credit tracking

---

## 5. Performance Specifications

### 5.1 Timing Requirements

| Parameter | Specification | Notes |
|-----------|---------------|-------|
| Clock Frequency | Up to 2 GHz | Protocol domain clock |
| Pipeline Latency | 3 clock cycles | Parse → Process → Format |
| Flit Processing Rate | 1 flit/cycle | Maximum throughput |
| Credit Update Latency | 2 clock cycles | From consumption to update |
| Protocol Switch Time | 1 clock cycle | Between different protocols |

### 5.2 Throughput Specifications

| Configuration | Max Throughput | Efficiency |
|---------------|----------------|------------|
| x64 @ 128 GT/s | 8.192 Tbps | >95% |
| x32 @ 64 GT/s | 2.048 Tbps | >95% |
| x16 @ 32 GT/s | 512 Gbps | >90% |
| x8 @ 16 GT/s | 128 Gbps | >85% |

### 5.3 Buffer Requirements

| Buffer Type | Depth | Width | Total Memory |
|-------------|-------|-------|--------------|
| TX Protocol Buffers | 16 entries | 256 bits | 16 KB |
| RX Protocol Buffers | 16 entries | 256 bits | 16 KB |
| Flow Control Tables | 8 VCs | 32 bits | 256 B |
| Arbitration State | 4 protocols | 64 bits | 32 B |

---

## 6. Error Handling and Recovery

### 6.1 Error Detection Mechanisms

#### Protocol-Level Errors
- **Header Validation**: Format and field checking
- **CRC Verification**: Payload integrity checking  
- **Sequence Validation**: Packet ordering verification
- **Flow Control Violations**: Credit overflow/underflow detection

#### System-Level Errors
- **Buffer Overflow**: Input buffer saturation
- **Pipeline Stalls**: Excessive backpressure detection
- **Clock Domain Crossing**: Metastability detection
- **Configuration Errors**: Invalid parameter detection

### 6.2 Error Recovery Strategies

#### Automatic Recovery
1. **Retry Mechanism**: Automatic retransmission for CRC errors
2. **Flow Control Reset**: Credit resynchronization
3. **Buffer Flush**: Clear corrupted data from buffers
4. **Protocol Restart**: Reinitialize specific protocol engines

#### Manual Recovery
1. **Software Intervention**: Register-based error clearing
2. **Configuration Update**: Runtime parameter adjustment
3. **Debug Mode**: Detailed error analysis and logging
4. **Test Mode**: Built-in self-test execution

---

## 7. Configuration and Control

### 7.1 Configuration Registers

#### Protocol Configuration (Offset 0x000)
```
Bits [31:28] - Protocol Enable Mask (PCIe|CXL|Stream|Mgmt)
Bits [27:24] - Flit Format Selection
Bits [23:16] - Virtual Channel Configuration
Bits [15:8]  - Flow Control Thresholds
Bits [7:0]   - Debug and Test Mode
```

#### Performance Configuration (Offset 0x004)
```
Bits [31:24] - Pipeline Configuration
Bits [23:16] - Arbitration Algorithm Selection
Bits [15:8]  - Credit Pool Size
Bits [7:0]   - Buffer Configuration
```

### 7.2 Status Registers

#### Protocol Status (Offset 0x010)
```
Bits [31:28] - Protocol Active Status
Bits [27:24] - Protocol Error Status  
Bits [23:16] - Pipeline Occupancy
Bits [15:8]  - Buffer Occupancy Status
Bits [7:0]   - Flow Control Status
```

#### Performance Counters (Offset 0x014)
```
Bits [31:24] - Packets Processed Counter
Bits [23:16] - CRC Error Counter
Bits [15:8]  - Flow Control Stall Counter
Bits [7:0]   - Buffer Overflow Counter
```

---

## 8. Debug and Test Features

### 8.1 Built-in Self-Test (BIST)

#### Protocol Engine Tests
- **Pattern Generation**: Known data pattern injection
- **Loopback Testing**: Internal data path verification
- **CRC Testing**: Error injection and detection verification
- **Flow Control Testing**: Credit mechanism validation

#### Performance Testing
- **Throughput Measurement**: Maximum data rate testing
- **Latency Measurement**: End-to-end delay testing
- **Buffer Testing**: Memory integrity verification
- **Arbitration Testing**: Fairness and priority verification

### 8.2 Debug Infrastructure

#### Trace Capture
- **Flit Tracing**: Complete flit capture and analysis
- **State Machine Tracing**: Protocol engine state tracking
- **Performance Tracing**: Throughput and latency measurements
- **Error Tracing**: Detailed error event logging

#### Debug Interfaces
- **Register Access**: Runtime configuration and status access
- **Signal Probing**: Internal signal observation
- **Event Triggering**: Conditional debug activation
- **Data Injection**: Test data insertion for verification

---

## 9. Physical Implementation Considerations

### 9.1 Synthesis Guidelines

#### Critical Path Optimization
- **Pipeline Balancing**: Equal delay across pipeline stages
- **Logic Optimization**: Minimize combinational logic depth
- **Clock Gating**: Aggressive power optimization
- **Register Placement**: Strategic register insertion

#### Area Optimization
- **Memory Inference**: Efficient RAM/FIFO implementation
- **Logic Sharing**: Common subexpression elimination
- **Resource Multiplexing**: Time-shared functional units
- **Configuration-Based Sizing**: Runtime parameter optimization

### 9.2 Power Management

#### Dynamic Power Reduction
- **Clock Gating**: Protocol-specific clock disabling
- **Power Gating**: Unused engine power shutdown
- **Voltage Scaling**: Performance-based voltage adjustment
- **Activity Monitoring**: Usage-based power optimization

#### Static Power Reduction  
- **Low-Power Design**: High-Vt cell usage in non-critical paths
- **Memory Optimization**: Compiler-optimized memory layout
- **Leakage Reduction**: Power switch insertion
- **Thermal Management**: Temperature-based throttling

---

## 10. Verification Strategy

### 10.1 Unit-Level Verification

#### Module-Specific Tests
- **Protocol Engine Tests**: Individual engine functionality
- **Flit Processor Tests**: Format conversion verification
- **Flow Control Tests**: Credit mechanism validation
- **Buffer Tests**: Memory and arbitration verification

#### Coverage Metrics
- **Functional Coverage**: Protocol scenario coverage
- **Code Coverage**: Line and branch coverage (>95%)
- **Toggle Coverage**: Signal activity verification
- **FSM Coverage**: State machine transition coverage

### 10.2 Integration-Level Verification

#### System-Level Tests
- **Multi-Protocol Tests**: Concurrent protocol operation
- **Performance Tests**: Throughput and latency validation
- **Stress Tests**: Maximum load and error injection
- **Compliance Tests**: UCIe specification conformance

#### Verification Environment
- **UVM Framework**: Constrained random verification
- **Protocol Monitors**: Specification compliance checking
- **Scoreboards**: End-to-end data integrity verification
- **Coverage Collectors**: Comprehensive coverage analysis

---

## 11. Implementation Timeline

### 11.1 Development Phases

#### Phase 1: Core Infrastructure (Weeks 1-4)
- Basic module structure and interfaces
- Protocol packet definitions and types
- Basic flit processing pipeline
- Simple flow control mechanism

#### Phase 2: Protocol Engines (Weeks 5-8)
- PCIe protocol engine implementation
- CXL multi-stack protocol engine
- Streaming protocol engine
- Management protocol engine

#### Phase 3: Advanced Features (Weeks 9-12)
- Advanced flow control and virtual channels
- Arbitration and performance optimization
- Error handling and recovery mechanisms
- Debug and test infrastructure

#### Phase 4: Integration and Verification (Weeks 13-16)
- Full system integration
- Comprehensive verification and testing
- Performance optimization and tuning
- Documentation and delivery

### 11.2 Verification Timeline

#### Unit Verification (Weeks 5-12)
- Individual module verification
- Coverage analysis and closure
- Bug fixing and optimization

#### Integration Verification (Weeks 13-20)
- System-level verification
- Protocol compliance testing
- Performance validation
- Final verification closure

---

## 12. Deliverables

### 12.1 RTL Deliverables
- Complete SystemVerilog source code
- Synthesis scripts and constraints
- Implementation guidelines
- Configuration files

### 12.2 Verification Deliverables
- UVM testbench environment
- Test cases and scenarios
- Coverage reports and analysis
- Verification closure report

### 12.3 Documentation Deliverables
- Detailed design documentation
- User guide and configuration manual
- Performance analysis report
- Compliance verification report

---

## Conclusion

The Protocol Layer MAS provides comprehensive implementation guidance for the UCIe controller's protocol processing subsystem. This specification ensures high-performance, reliable, and scalable protocol handling for all supported UCIe protocols while maintaining compliance with UCIe v2.0 specifications.

**Implementation Status**: Ready for RTL development
**Verification Readiness**: Complete verification strategy defined
**Performance Target**: 8.192 Tbps aggregate throughput capability
**Power Efficiency**: <0.66 pJ/bit at maximum performance