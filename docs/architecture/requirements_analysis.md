# UCIe Controller Requirements Analysis

## Overview
Based on UCIe Specification v2.0, this document outlines the key requirements for implementing a UCIe controller.

## High-Level Requirements

### 1. Protocol Support
- **PCIe**: Full Base Specification support with flit mapping
- **CXL**: I/O, cache, and memory protocols (excluding RCD/RCH/eRCD/eRCH)
- **Streaming**: Generic protocol support for user-defined protocols
- **Management Transport**: UCIe-specific management and debug protocols
- **Raw Format**: Protocol-agnostic mode for custom implementations

### 2. Physical Layer Requirements

#### Package Support
| Package Type | Reach | Bump Pitch | Data Rates | BER |
|--------------|-------|------------|------------|-----|
| Standard | 10-25mm | 100-130μm | 4-32 GT/s | 1e-27 (≤8GT/s), 1e-15 (≥12GT/s) |
| Advanced | <2mm | 25-55μm | 4-32 GT/s | 1e-27 (≤12GT/s), 1e-15 (≥16GT/s) |
| UCIe-3D | 3D vertical | <10μm (opt), 10-25μm (func) | ≤4 GT/s | 1e-27 |

#### Module Configurations
- **Standard Package**: x8, x16 modules
- **Advanced Package**: x32, x64 modules
- **Multi-module**: Up to 4 modules per link

### 3. Interface Requirements

#### Raw Die-to-Die Interface (RDI)
- Protocol-agnostic raw data transfer
- Clock domain management
- Power management hooks
- Reset and initialization sequences

#### Flit-Aware Die-to-Die Interface (FDI)
- Flit-based protocol processing
- Multiple flit formats (68B, 256B standard/latency-optimized)
- Flow control and credit management
- Protocol multiplexing support

#### Sideband Interface
- Fixed 800 MHz clock (independent of mainband rate)
- Always-on auxiliary power domain
- Parameter exchange and negotiation
- Register access for debug/compliance
- Management packet transport

### 4. Link Training Requirements

#### Initialization Stages
1. **RESET**: Basic reset and power-on sequence
2. **SBINIT**: Sideband initialization and basic connectivity
3. **MBINIT**: Mainband initialization with parameter exchange
4. **MBTRAIN**: Physical layer training and calibration
5. **LINKINIT**: Link-level initialization
6. **ACTIVE**: Operational data transfer state

#### Training Features
- Parameter negotiation (speed, width, protocols)
- Lane repair and mapping
- Lane reversal support
- Multi-module coordination
- Retimer integration

### 5. Error Handling & Reliability

#### CRC and Retry
- Link-level CRC calculation and checking
- Automatic retry mechanism for corrupted packets
- Buffer management for retry scenarios
- Timeout handling and error escalation

#### Lane Management
- Runtime lane failure detection
- Dynamic lane remapping and repair
- Width degradation handling
- Module disable capability

### 6. Power Management

#### Link States
- **L0**: Active state
- **L1**: Standby with fast recovery
- **L2**: Sleep state with longer recovery
- Coordinated entry/exit with link partner

#### Clock Management
- Dynamic clock gating
- Free-running clock mode
- Wake/sleep handshake protocols

### 7. Management and Debug

#### UCIe Manageability Architecture
- Management network topology
- Access control and security
- Configuration discovery
- Runtime monitoring

#### Debug Infrastructure (UDA)
- DFx Management Hub (DMH)
- DFx Management Spoke (DMS)
- Test and compliance interfaces
- Sort/pre-bond testing support

## Implementation Priorities

### Critical Path Items
1. **Link Training State Machine**: Core to all functionality
2. **Protocol Flit Processing**: Determines performance characteristics
3. **Error Detection/Correction**: Required for reliability
4. **Power Management**: Essential for system integration

### Performance Critical
1. **Data Path Optimization**: Minimize latency in flit processing
2. **Clock Domain Crossing**: Efficient sideband/mainband coordination
3. **Buffer Management**: Optimize for throughput and area

### Compliance Critical
1. **Parameter Negotiation**: Ensure interoperability
2. **Test Modes**: Support compliance testing
3. **Register Interface**: Debug and configuration access
4. **Timing Margins**: Meet specification requirements

## Design Constraints

### Timing
- All timeout values: -0%, +50% tolerance
- Must meet setup/hold requirements across all speed grades
- Clock domain crossing synchronization

### Power
- Sideband must operate on auxiliary power
- Support for clock gating and power state transitions
- Thermal management considerations

### Area
- Minimize mainband datapath logic
- Optimize for target package type and module configuration
- Consider multi-module scaling

### Interoperability
- Must work with any compliant UCIe device
- Support mixed-speed and mixed-width scenarios
- Handle different package types and retimer configurations

## Next Steps

1. **Architecture Definition**: Define block-level partitioning
2. **Interface Specification**: Detail RDI/FDI signal definitions
3. **State Machine Design**: Implement link training flow
4. **Protocol Mapping**: Design flit processing engines
5. **Verification Strategy**: Plan testbench and compliance testing