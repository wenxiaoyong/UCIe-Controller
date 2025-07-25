# UCIe Physical Layer Micro Architecture Specification (MAS)

## Document Information
- **Document**: Physical Layer MAS v1.0
- **Project**: UCIe Controller RTL Implementation
- **Layer**: Physical Layer (Layer 3 of 4)
- **Date**: 2025-07-25
- **Status**: Implementation Ready

---

## 1. Executive Summary

The Physical Layer MAS defines the detailed micro-architecture for the UCIe controller's physical interface subsystem. This layer manages the critical hardware interface functions including link training, lane management, sideband communication, clock management, and analog front-end coordination.

### Key Capabilities
- **Link Training Engine**: Complete 23-state training sequence with multi-module coordination
- **Lane Management**: Repair, reversal, width degradation, and module coordination
- **Sideband Protocol**: 800MHz always-on auxiliary domain communication
- **Multi-Package Support**: Standard, Advanced, and UCIe-3D package implementations
- **Clock Management**: Multi-domain clock generation, distribution, and power management
- **AFE Interface**: Comprehensive analog front-end control and monitoring

---

## 2. Module Hierarchy and Architecture

### 2.1 Top-Level Module Structure

```systemverilog
module ucie_physical_layer #(
    parameter int PACKAGE_TYPE      = 2,        // 0=Std, 1=Adv, 2=3D
    parameter int MODULE_WIDTH      = 64,       // x8, x16, x32, x64
    parameter int NUM_MODULES       = 1,        // 1-4 modules
    parameter int MAX_SPEED_GT_S    = 128,      // Maximum speed in GT/s
    parameter int SIDEBAND_FREQ_MHZ = 800,      // Sideband frequency
    parameter int NUM_LANES         = 64,       // Total number of lanes
    parameter int REPAIR_LANES      = 8        // Number of repair lanes
) (
    // Clock and Reset
    input  logic                    clk_mainband,      // Mainband clock (variable)
    input  logic                    clk_aux,           // Auxiliary clock (800MHz)
    input  logic                    clk_ref,           // Reference clock (100MHz)
    input  logic                    rst_n,             // Active-low reset
    
    // D2D Adapter Interface
    ucie_d2d_phy_if.physical       d2d_tx,            // D2D to Physical TX
    ucie_d2d_phy_if.physical       d2d_rx,            // D2D to Physical RX
    
    // Analog Front-End Interface
    ucie_afe_if.controller         afe_ctrl,          // AFE control interface
    
    // Sideband Interface (Off-package)
    output logic                   sb_clk_out,        // Sideband clock output
    input  logic                   sb_clk_in,         // Sideband clock input
    output logic [1:0]             sb_data_out,       // Sideband data output
    input  logic [1:0]             sb_data_in,        // Sideband data input
    
    // Mainband Lanes (High-speed differential)
    output logic [NUM_LANES-1:0]   mb_tx_p,           // Mainband TX positive
    output logic [NUM_LANES-1:0]   mb_tx_n,           // Mainband TX negative
    input  logic [NUM_LANES-1:0]   mb_rx_p,           // Mainband RX positive
    input  logic [NUM_LANES-1:0]   mb_rx_n,           // Mainband RX negative
    
    // Training and Control
    input  logic                   training_enable,   // Training enable
    output logic [4:0]             training_state,    // Current training state
    output logic                   training_complete, // Training completion
    output logic [7:0]             active_lanes,      // Number of active lanes
    output logic [7:0]             active_speed,      // Active speed (GT/s)
    
    // Lane Management
    input  logic                   lane_repair_enable,// Lane repair enable
    output logic [NUM_LANES-1:0]   lane_status,       // Per-lane status
    output logic [NUM_LANES-1:0]   lane_map,          // Lane mapping
    output logic                   width_degraded,    // Width degradation occurred
    
    // Power Management
    input  logic [1:0]             power_state_req,   // Power state request
    output logic [1:0]             power_state_ack,   // Power state acknowledgment
    input  logic                   clock_gate_enable, // Clock gating enable
    output logic                   pll_locked,        // PLL lock status
    
    // Debug and Test
    input  logic [3:0]             test_mode,         // Test mode selection
    input  logic                   debug_enable,      // Debug mode enable
    output logic [63:0]            debug_data,        // Debug information
    output logic [31:0]            ber_counters,      // Bit error rate counters
    
    // Configuration and Status
    input  logic [31:0]            phy_config,        // Physical layer config
    output logic [31:0]            phy_status,        // Physical layer status
    output logic [31:0]            training_counters  // Training statistics
);
```

### 2.2 Sublayer Module Breakdown

#### 2.2.1 Link Training FSM (ucie_link_training_fsm.sv)
```systemverilog
module ucie_link_training_fsm #(
    parameter int NUM_MODULES = 1,
    parameter int NUM_LANES = 64
) (
    input  logic                clk,
    input  logic                clk_aux,
    input  logic                rst_n,
    
    // Training Control
    input  logic                training_start,
    output logic [4:0]          training_state,
    output logic                training_complete,
    output logic                training_error,
    
    // Physical Control Interface
    output logic                phy_reset_req,
    output logic [7:0]          phy_speed_req,
    output logic [7:0]          phy_width_req,
    input  logic                phy_ready,
    input  logic [7:0]          phy_speed_ack,
    input  logic [7:0]          phy_width_ack,
    
    // Sideband Parameter Interface
    output logic [31:0]         sb_param_tx,
    output logic                sb_param_tx_valid,
    input  logic                sb_param_tx_ready,
    input  logic [31:0]         sb_param_rx,
    input  logic                sb_param_rx_valid,
    output logic                sb_param_rx_ready,
    
    // Lane Management Interface
    output logic                lane_train_enable,
    input  logic [NUM_LANES-1:0] lane_train_done,
    input  logic [NUM_LANES-1:0] lane_train_error,
    output logic [NUM_LANES-1:0] lane_enable,
    
    // Training Pattern Interface
    output logic [7:0]          pattern_select,
    output logic                pattern_enable,
    input  logic                pattern_lock,
    input  logic [15:0]         pattern_errors,
    
    // Calibration Interface
    output logic                cal_start,
    input  logic                cal_done,
    input  logic                cal_error,
    
    // Multi-Module Coordination
    output logic                module_sync_req,
    input  logic                module_sync_ack,
    input  logic [NUM_MODULES-1:0] module_ready,
    
    // Status and Debug
    output logic [31:0]         training_timer,
    output logic [15:0]         error_counters,
    output logic [7:0]          training_attempts
);
```

#### 2.2.2 Lane Manager (ucie_lane_manager.sv)
```systemverilog
module ucie_lane_manager #(
    parameter int NUM_LANES = 64,
    parameter int REPAIR_LANES = 8,
    parameter int MIN_WIDTH = 8
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // Lane Control Interface
    input  logic                lane_mgmt_enable,
    output logic [NUM_LANES-1:0] lane_enable,
    output logic [NUM_LANES-1:0] lane_active,
    input  logic [NUM_LANES-1:0] lane_error,
    
    // Lane Mapping
    output logic [7:0]          lane_map [NUM_LANES-1:0], // Physical to logical mapping
    output logic [7:0]          reverse_map [NUM_LANES-1:0], // Logical to physical mapping
    input  logic                reversal_detected,
    output logic                reversal_corrected,
    
    // Width Management
    input  logic [7:0]          requested_width,
    output logic [7:0]          actual_width,
    output logic                width_degraded,
    input  logic [7:0]          min_width,
    
    // Repair Management
    input  logic                repair_enable,
    output logic                repair_active,
    output logic [NUM_LANES-1:0] repair_lanes,
    input  logic [15:0]         ber_threshold,
    input  logic [15:0]         lane_ber [NUM_LANES-1:0],
    
    // Module Coordination
    input  logic [3:0]          module_id,
    input  logic [3:0]          num_modules,
    output logic                module_coordinator_req,
    input  logic                module_coordinator_ack,
    
    // Lane Status
    output logic [NUM_LANES-1:0] lane_good,
    output logic [NUM_LANES-1:0] lane_marginal,
    output logic [NUM_LANES-1:0] lane_failed,
    output logic [7:0]          good_lane_count,
    
    // Configuration
    input  logic [31:0]         lane_config,
    output logic [31:0]         lane_status
);
```

#### 2.2.3 Sideband Engine (ucie_sideband_engine.sv)
```systemverilog
module ucie_sideband_engine #(
    parameter int SB_FREQ_MHZ = 800,
    parameter int PACKET_WIDTH = 64,
    parameter int CRC_WIDTH = 8
) (
    input  logic                clk_aux,              // 800MHz auxiliary clock
    input  logic                rst_n,
    
    // External Sideband Interface
    output logic                sb_clk_out,
    input  logic                sb_clk_in,
    output logic [1:0]          sb_data_out,
    input  logic [1:0]          sb_data_in,
    
    // Internal Packet Interface
    input  logic [PACKET_WIDTH-1:0] tx_packet,
    input  logic                tx_packet_valid,
    output logic                tx_packet_ready,
    
    output logic [PACKET_WIDTH-1:0] rx_packet,
    output logic                rx_packet_valid,
    input  logic                rx_packet_ready,
    
    // Control and Status
    input  logic                sb_enable,
    output logic                sb_link_up,
    output logic                sb_error,
    input  logic [7:0]          sb_config,
    
    // CRC and Error Detection
    output logic                crc_error,
    output logic [15:0]         error_counters,
    input  logic                error_clear,
    
    // Power Management
    input  logic                sb_power_down,
    output logic                sb_wake_detected,
    input  logic                sb_wake_request,
    
    // Debug Interface
    output logic [31:0]         sb_debug_data,
    input  logic                sb_debug_enable
);
```

#### 2.2.4 Clock Manager (ucie_clock_manager.sv)
```systemverilog
module ucie_clock_manager #(
    parameter int MAX_SPEED_GT_S = 128,
    parameter int REF_FREQ_MHZ = 100
) (
    input  logic                clk_ref,              // Reference clock input
    input  logic                rst_n,
    
    // Generated Clocks
    output logic                clk_mainband,         // Mainband clock (variable)
    output logic                clk_aux,              // Auxiliary clock (800MHz)
    output logic                clk_sideband,         // Sideband clock (800MHz)
    output logic                clk_protocol,         // Protocol clock
    
    // PLL Control
    input  logic [7:0]          speed_select,         // Speed selection (GT/s)
    output logic                pll_locked,           // PLL lock status
    output logic                pll_error,            // PLL error status
    input  logic                pll_reset,            // PLL reset request
    
    // Clock Gating Control
    input  logic                clock_gate_enable,
    input  logic [15:0]         clock_gate_mask,     // Per-domain gating
    output logic [15:0]         clock_active,        // Active clock indicators
    
    // Power Management
    input  logic [1:0]          power_state,
    output logic                clocks_stable,
    input  logic                wake_request,
    output logic                clock_wake_ready,
    
    // Frequency Monitoring
    output logic [31:0]         freq_counter,
    output logic                freq_valid,
    input  logic                freq_measure_enable,
    
    // Debug and Test
    input  logic [3:0]          test_mode,
    output logic [31:0]         clock_debug_data
);
```

#### 2.2.5 AFE Interface (ucie_afe_interface.sv)
```systemverilog
module ucie_afe_interface #(
    parameter int NUM_LANES = 64,
    parameter int AFE_CONFIG_WIDTH = 32
) (
    input  logic                clk,
    input  logic                rst_n,
    
    // AFE Control Interface
    output logic [AFE_CONFIG_WIDTH-1:0] afe_config [NUM_LANES-1:0],
    input  logic [AFE_CONFIG_WIDTH-1:0] afe_status [NUM_LANES-1:0],
    output logic                afe_config_valid,
    input  logic                afe_config_ack,
    
    // Per-Lane Control
    output logic [NUM_LANES-1:0] lane_tx_enable,
    output logic [NUM_LANES-1:0] lane_rx_enable,
    input  logic [NUM_LANES-1:0] lane_tx_ready,
    input  logic [NUM_LANES-1:0] lane_rx_ready,
    
    // Calibration Interface
    output logic                cal_request,
    input  logic                cal_complete,
    input  logic                cal_error,
    output logic [7:0]          cal_type,             // Calibration type
    
    // Voltage and Current Control
    output logic [7:0]          tx_voltage [NUM_LANES-1:0],
    output logic [7:0]          rx_voltage [NUM_LANES-1:0],
    input  logic [7:0]          tx_current [NUM_LANES-1:0],
    input  logic [7:0]          rx_current [NUM_LANES-1:0],
    
    // Impedance Control
    output logic [7:0]          tx_impedance [NUM_LANES-1:0],
    output logic [7:0]          rx_impedance [NUM_LANES-1:0],
    input  logic                impedance_cal_done,
    output logic                impedance_cal_start,
    
    // Signal Quality Monitoring
    input  logic [7:0]          signal_quality [NUM_LANES-1:0],
    input  logic [15:0]         eye_height [NUM_LANES-1:0],
    input  logic [15:0]         eye_width [NUM_LANES-1:0],
    output logic [15:0]         quality_threshold,
    
    // Power Management
    input  logic [1:0]          afe_power_state,
    output logic                afe_power_ready,
    input  logic                afe_power_down,
    
    // Test and Debug
    input  logic [3:0]          afe_test_mode,
    output logic [31:0]         afe_debug_data,
    input  logic                afe_loopback_enable
);
```

---

## 3. Training State Machine and Sequences

### 3.1 Training State Definitions

```systemverilog
typedef enum logic [4:0] {
    // Basic States
    TRAIN_RESET         = 5'h00,  // Reset and initialization
    TRAIN_SBINIT        = 5'h01,  // Sideband initialization
    TRAIN_PARAM         = 5'h02,  // Parameter exchange
    TRAIN_MBINIT        = 5'h03,  // Mainband initialization
    TRAIN_CAL           = 5'h04,  // Calibration
    TRAIN_MBTRAIN       = 5'h05,  // Mainband training
    TRAIN_LINKINIT      = 5'h06,  // Link initialization
    TRAIN_ACTIVE        = 5'h07,  // Active operation
    
    // Power States
    TRAIN_L1            = 5'h08,  // L1 power state
    TRAIN_L2            = 5'h09,  // L2 power state
    
    // Error and Recovery States
    TRAIN_PHYRETRAIN    = 5'h0A,  // Physical layer retrain
    TRAIN_REPAIR        = 5'h0B,  // Lane repair
    TRAIN_DEGRADE       = 5'h0C,  // Width degradation
    TRAIN_ERROR         = 5'h0D,  // Training error
    
    // Advanced States  
    TRAIN_MULTIMOD      = 5'h0E,  // Multi-module coordination
    TRAIN_RETIMER       = 5'h0F,  // Retimer training
    
    // Test States
    TRAIN_TEST          = 5'h10,  // Test mode
    TRAIN_COMPLIANCE    = 5'h11,  // Compliance testing
    TRAIN_LOOPBACK      = 5'h12,  // Loopback mode
    TRAIN_PATGEN        = 5'h13   // Pattern generation
} training_state_t;
```

### 3.2 Training Sequence Specifications

#### Sequence 1: SBINIT (Sideband Initialization)
- **Duration**: 100μs typical, 1ms maximum
- **Function**: Establish sideband link
- **Activities**:
  - Sideband clock and data recovery
  - Basic connectivity test
  - Initial handshake protocol
  - Link partner identification

#### Sequence 2: PARAM (Parameter Exchange)
- **Duration**: 1ms typical, 10ms maximum  
- **Function**: Negotiate capabilities
- **Parameters**:
  - Speed capabilities (4-128 GT/s)
  - Width capabilities (x8-x64)
  - Protocol support mask
  - Feature enables (CRC, retry, etc.)
  - Package type identification

#### Sequence 3: MBINIT (Mainband Initialization)
- **Duration**: 500μs typical, 5ms maximum
- **Function**: Initialize mainband
- **Activities**:
  - PLL initialization and lock
  - Clock distribution setup
  - Lane assignment and mapping
  - Initial electrical setup

#### Sequence 4: CAL (Calibration)
- **Duration**: 2ms typical, 20ms maximum
- **Function**: Electrical calibration
- **Calibrations**:
  - Impedance calibration (50Ω target)
  - Voltage level optimization
  - Timing calibration and skew adjustment
  - Signal integrity validation

#### Sequence 5: MBTRAIN (Mainband Training)
- **Duration**: 5ms typical, 50ms maximum
- **Function**: High-speed training
- **Training Patterns**:
  - PRBS7/15/23/31 sequences
  - Custom UCIe training patterns
  - Lane-to-lane skew training
  - Receiver adaptation

#### Sequence 6: LINKINIT (Link Initialization)
- **Duration**: 1ms typical, 10ms maximum
- **Function**: Final link setup
- **Activities**:
  - Protocol layer activation
  - Flow control initialization
  - Buffer setup and validation
  - Link quality verification

### 3.3 Package-Specific Training

#### Standard Package Training
- **Reach**: 10-25mm organic substrate
- **Challenges**: Signal integrity over distance
- **Special Requirements**:
  - Extended calibration time
  - Enhanced signal conditioning
  - Crosstalk mitigation
  - Lower speed operation (<= 32 GT/s)

#### Advanced Package Training  
- **Reach**: <2mm silicon bridge/interposer
- **Challenges**: High-speed signaling
- **Special Requirements**:
  - Precise timing control
  - Advanced equalization
  - High-frequency optimization
  - Full speed operation (up to 128 GT/s)

#### UCIe-3D Package Training
- **Reach**: Vertical 3D stacking
- **Challenges**: Thermal and mechanical constraints
- **Special Requirements**:
  - Conservative speed limits (<= 4 GT/s)
  - Thermal monitoring integration
  - Mechanical stress consideration
  - Power delivery optimization

---

## 4. Lane Management and Repair

### 4.1 Lane Quality Assessment

#### Bit Error Rate (BER) Monitoring
```systemverilog
typedef struct packed {
    logic [31:0]    error_count;       // Total errors detected
    logic [31:0]    total_bits;        // Total bits transmitted
    logic [15:0]    ber_value;         // Calculated BER (log scale)
    logic           ber_valid;         // BER calculation valid
    logic           ber_alarm;         // BER exceeds threshold
} ber_status_t;
```

#### Signal Quality Metrics
- **Eye Height**: Minimum 200mV for good lane
- **Eye Width**: Minimum 0.3 UI for good lane  
- **Jitter**: RMS jitter < 0.1 UI
- **Crosstalk**: < -30dB isolation between lanes

### 4.2 Lane Repair Mechanisms

#### Repair Strategy 1: Lane Remapping
- **Trigger**: Single lane BER > 1e-12
- **Action**: Map logical lane to spare physical lane
- **Duration**: ~1ms (no retraining required)
- **Success Rate**: >95% with available spare lanes

#### Repair Strategy 2: Width Degradation
- **Trigger**: Multiple lane failures exceed spare capacity
- **Action**: Reduce active width, disable failed lanes
- **Duration**: ~10ms (partial retraining required)
- **Success Rate**: >90% down to minimum width

#### Repair Strategy 3: Speed Reduction
- **Trigger**: Signal integrity issues at high speed
- **Action**: Negotiate lower speed operation
- **Duration**: ~20ms (full retraining required)
- **Success Rate**: >95% for marginal signal quality

### 4.3 Lane Reversal Detection

#### Detection Algorithm
```systemverilog
// Lane reversal detection using training patterns
function automatic logic detect_lane_reversal(
    input logic [63:0] received_pattern,
    input logic [63:0] expected_pattern
);
    logic [63:0] reversed_pattern;
    logic normal_match, reversed_match;
    
    // Generate bit-reversed pattern
    for (int i = 0; i < 64; i++) begin
        reversed_pattern[i] = expected_pattern[63-i];
    end
    
    // Check for matches
    normal_match = (received_pattern == expected_pattern);
    reversed_match = (received_pattern == reversed_pattern);
    
    return reversed_match && !normal_match;
endfunction
```

#### Reversal Correction
- **Detection**: During training pattern phase
- **Correction**: Update lane mapping tables
- **Transparency**: Hidden from upper layers
- **Latency**: <100μs additional training time

---

## 5. Sideband Protocol Implementation

### 5.1 Sideband Packet Format

```systemverilog
typedef struct packed {
    logic [7:0]     packet_type;       // Packet type identifier
    logic [7:0]     sequence_num;      // Sequence number
    logic [15:0]    packet_length;     // Payload length in bytes
    logic [31:0]    destination_id;    // Target device ID
    logic [31:0]    source_id;         // Source device ID
    logic [255:0]   payload;           // Packet payload
    logic [7:0]     crc;               // CRC-8 checksum
    logic           eop;               // End of packet
} sideband_packet_t;
```

### 5.2 Sideband Message Types

#### Management Messages
- **PARAM_REQ**: Parameter request
- **PARAM_RSP**: Parameter response
- **CONFIG_WR**: Configuration write
- **CONFIG_RD**: Configuration read
- **STATUS_REQ**: Status request
- **STATUS_RSP**: Status response

#### Control Messages
- **TRAIN_START**: Training start command
- **TRAIN_STOP**: Training stop command
- **POWER_REQ**: Power state request
- **POWER_ACK**: Power state acknowledgment
- **ERROR_REPORT**: Error notification
- **RESET_REQ**: Reset request

#### Debug Messages
- **DEBUG_REG_RD**: Debug register read
- **DEBUG_REG_WR**: Debug register write
- **TRACE_DATA**: Trace data capture
- **TEST_MODE**: Test mode control

### 5.3 Sideband Error Handling

#### Error Detection
- **CRC-8 Protection**: Polynomial 0x07 (x^8 + x^2 + x + 1)
- **Sequence Number**: Duplicate detection
- **Timeout Protection**: 1ms packet timeout
- **Framing Validation**: Start/end delimiter checking

#### Error Recovery
- **Automatic Retry**: Up to 3 retries per packet
- **Error Reporting**: Status messages for persistent errors
- **Link Reset**: Sideband link restart for critical errors
- **Fallback Mode**: Reduced functionality mode

---

## 6. Performance Specifications

### 6.1 Timing Requirements

| Parameter | Specification | Notes |
|-----------|---------------|-------|
| Complete Training | <10ms | RESET to ACTIVE |
| Lane Repair | <1ms | Single lane remapping |
| Width Degradation | <10ms | Partial retraining |
| Speed Negotiation | <20ms | Full retraining |
| Power State Transition | <100μs | L0 ↔ L2 worst case |
| Clock Lock Time | <100μs | PLL lock establishment |
| Sideband Latency | <10μs | Packet transmission |

### 6.2 Signal Integrity Specifications

| Package Type | Max Speed | BER Target | Eye Specs |
|--------------|-----------|------------|-----------|
| Standard | 32 GT/s | 1e-15 | >200mV, >0.3UI |
| Advanced | 128 GT/s | 1e-15 | >150mV, >0.25UI |
| UCIe-3D | 4 GT/s | 1e-27 | >300mV, >0.4UI |

### 6.3 Power Specifications

| Component | Active Power | Standby Power | Sleep Power |
|-----------|--------------|---------------|-------------|
| Training Engine | 50mW | 10mW | 1mW |
| Lane Manager | 30mW | 5mW | 0.5mW |
| Sideband Engine | 20mW | 20mW | 10mW |
| Clock Manager | 100mW | 20mW | 5mW |
| AFE Interface | 25mW | 5mW | 1mW |

---

## 7. Debug and Test Infrastructure

### 7.1 Built-in Self-Test (BIST)

#### Training BIST
- **Pattern Generation**: PRBS7/15/23/31 generators
- **Pattern Checking**: Real-time error detection
- **Eye Diagram**: Built-in eye measurement
- **BER Testing**: Accelerated BER characterization

#### Lane BIST
- **Loopback Testing**: Near-end and far-end loopback
- **Crosstalk Measurement**: Inter-lane interference
- **Jitter Analysis**: RJ and DJ separation
- **Impedance Testing**: TDR-based impedance check

#### Sideband BIST
- **Packet Testing**: End-to-end packet integrity
- **Clock Testing**: Frequency and jitter measurement
- **CRC Testing**: Error injection and detection
- **Timeout Testing**: Timeout mechanism validation

### 7.2 Debug Interfaces

#### Training Debug
- **State Visibility**: Real-time training state
- **Timer Monitoring**: Training sequence timing
- **Error Logging**: Detailed error event capture
- **Pattern Analysis**: Training pattern statistics

#### Signal Integrity Debug
- **Eye Monitoring**: Continuous eye measurement
- **BER Tracking**: Real-time BER calculation
- **Signal Quality**: Comprehensive SI metrics
- **Margin Analysis**: Operating margin assessment

#### Performance Debug
- **Throughput Monitoring**: Real-time bandwidth
- **Latency Measurement**: End-to-end delay
- **Efficiency Calculation**: Link utilization
- **Error Statistics**: Comprehensive error tracking

---

## 8. Configuration and Control

### 8.1 Configuration Registers

#### Physical Configuration (Offset 0x000)
```
Bits [31:28] - Package type selection
Bits [27:24] - Maximum speed capability
Bits [23:16] - Maximum width capability  
Bits [15:8]  - Training timeout values
Bits [7:0]   - Lane repair configuration
```

#### Clock Configuration (Offset 0x004)
```
Bits [31:24] - PLL configuration
Bits [23:16] - Clock gating control
Bits [15:8]  - Frequency selection
Bits [7:0]   - Power management settings
```

#### Sideband Configuration (Offset 0x008)
```
Bits [31:24] - Packet timeout values
Bits [23:16] - CRC configuration
Bits [15:8]  - Error handling settings
Bits [7:0]   - Debug control
```

### 8.2 Status Registers

#### Physical Status (Offset 0x010)
```
Bits [31:28] - Current training state
Bits [27:24] - Active speed
Bits [23:16] - Active width
Bits [15:8]  - Lane status summary
Bits [7:0]   - Power state
```

#### Error Status (Offset 0x014)
```
Bits [31:24] - Training error count
Bits [23:16] - Lane repair count
Bits [15:8]  - BER alarm status
Bits [7:0]   - Sideband error status
```

---

## 9. Implementation Guidelines

### 9.1 Clock Domain Management

#### Clock Architecture
- **clk_ref**: 100MHz reference (always on)
- **clk_aux**: 800MHz auxiliary (sideband domain)
- **clk_mainband**: Variable speed mainband clock
- **clk_protocol**: Protocol interface clock

#### CDC Implementation
- **Synchronizer Chains**: 2-FF for control, 3-FF for critical
- **Async FIFOs**: Gray code pointers for data crossing
- **Handshake Protocols**: For critical control sequences
- **Reset Synchronization**: Proper reset domain management

### 9.2 Power Management Integration

#### Dynamic Power Control
- **Clock Gating**: Fine-grained per-functional-block
- **Power Gating**: Complete subsystem shutdown
- **Voltage Scaling**: Speed-dependent voltage adjustment
- **Activity Monitoring**: Usage-based optimization

#### Static Power Optimization
- **High-Vt Cells**: Non-critical path optimization
- **Memory Optimization**: Low-leakage memory selection
- **Power Domains**: Isolated power island design
- **Retention Registers**: State preservation during power down

---

## 10. Verification Strategy

### 10.1 Unit-Level Verification

#### Training FSM Verification
- **State Coverage**: All state transitions covered
- **Timeout Testing**: All timeout scenarios
- **Error Injection**: Training failure modes
- **Multi-Module**: Coordinated training scenarios

#### Lane Management Verification
- **Repair Scenarios**: All repair mechanisms
- **BER Testing**: Error rate threshold testing
- **Mapping Verification**: Lane mapping correctness
- **Degradation Testing**: Width reduction scenarios

#### Sideband Verification
- **Packet Testing**: All packet types and scenarios
- **Error Handling**: CRC errors, timeouts, retries
- **Performance**: Throughput and latency validation
- **Power Management**: Wake/sleep coordination

### 10.2 Integration Verification

#### System-Level Testing
- **End-to-End**: Complete training sequences
- **Multi-Package**: All package type variations
- **Performance**: Full speed and width validation
- **Stress Testing**: Extended operation under load

#### Compliance Testing
- **UCIe Specification**: Complete spec compliance
- **Interoperability**: Cross-vendor compatibility
- **Electrical**: Signal integrity validation
- **Timing**: Setup/hold margin verification

---

## 11. Implementation Timeline

### 11.1 Development Phases

#### Phase 1: Core Infrastructure (Weeks 1-4)
- Basic module structure and interfaces
- Training FSM framework
- Clock management basics
- Sideband protocol foundation

#### Phase 2: Training Implementation (Weeks 5-8)
- Complete training sequence implementation
- Parameter exchange mechanism
- Lane management and repair
- Multi-module coordination

#### Phase 3: Advanced Features (Weeks 9-12)
- Signal integrity monitoring
- Advanced calibration algorithms
- Power management integration
- Debug and test infrastructure

#### Phase 4: Integration and Validation (Weeks 13-16)
- Complete system integration
- Comprehensive verification
- Performance optimization
- Documentation and delivery

---

## 12. Deliverables

### 12.1 RTL Deliverables
- Complete SystemVerilog implementation
- Synthesis constraints and scripts
- Physical implementation guidelines
- Power management integration

### 12.2 Verification Deliverables
- UVM testbench environment
- Complete verification test suite
- Coverage analysis and reports
- Compliance verification results

### 12.3 Documentation Deliverables
- Detailed implementation specification
- Configuration and user guide
- Debug and troubleshooting manual
- Performance characterization report

---

## Conclusion

The Physical Layer MAS provides comprehensive implementation guidance for the critical hardware interface layer of the UCIe controller. This specification ensures robust link establishment, reliable lane management, and optimal signal integrity while supporting all UCIe package types and operating conditions.

**Implementation Status**: Ready for RTL development
**Verification Readiness**: Complete verification strategy defined
**Performance Target**: <10ms training, >95% lane repair success rate
**Signal Integrity Target**: Meeting all UCIe v2.0 electrical specifications