interface ucie_phy_if #(
    parameter NUM_LANES = 64,
    parameter MAX_SPEED_GBPS = 128,
    parameter SIGNALING_MODE = "PAM4"  // NRZ, PAM4
) (
    input logic clk_app,
    input logic clk_symbol,    // High-speed symbol clock (64 GHz for 128 Gbps PAM4)
    input logic clk_quarter,   // Quarter-rate clock (16 GHz)
    input logic clk_sideband,  // 800 MHz sideband clock
    input logic rst_n
);

    // ========================================================================
    // Physical Lane Signals (Enhanced for 128 Gbps PAM4)
    // ========================================================================
    
    // TX Differential Pairs
    logic [NUM_LANES-1:0]       tx_data_p;
    logic [NUM_LANES-1:0]       tx_data_n;
    
    // RX Differential Pairs  
    logic [NUM_LANES-1:0]       rx_data_p;
    logic [NUM_LANES-1:0]       rx_data_n;
    
    // PAM4 Enhanced Signals (for >64 Gbps)
    logic [NUM_LANES-1:0][1:0]  tx_pam4_level;    // PAM4 level control per lane
    logic [NUM_LANES-1:0][1:0]  rx_pam4_level;    // Received PAM4 level
    logic [NUM_LANES-1:0]       pam4_mode_en;     // Enable PAM4 mode per lane
    
    // ========================================================================
    // Advanced Equalization (128 Gbps Enhancement)
    // ========================================================================
    
    // DFE (Decision Feedback Equalizer) - 32 taps
    logic [NUM_LANES-1:0][31:0][7:0] dfe_coefficients;    // 32-tap DFE per lane
    logic [NUM_LANES-1:0]            dfe_enable;
    logic [NUM_LANES-1:0]            dfe_adapt_enable;
    
    // FFE (Feed Forward Equalizer) - 16 taps  
    logic [NUM_LANES-1:0][15:0][7:0] ffe_coefficients;    // 16-tap FFE per lane
    logic [NUM_LANES-1:0]            ffe_enable;
    logic [NUM_LANES-1:0]            ffe_adapt_enable;
    
    // CTLE (Continuous Time Linear Equalizer)
    logic [NUM_LANES-1:0][3:0]       ctle_gain;           // CTLE gain per lane
    logic [NUM_LANES-1:0][2:0]       ctle_peak_freq;      // Peak frequency setting
    
    // ========================================================================
    // Lane Management and Status
    // ========================================================================
    
    // Lane Enable/Disable
    logic [NUM_LANES-1:0]       lane_enable;
    logic [NUM_LANES-1:0]       lane_active;
    logic [NUM_LANES-1:0]       lane_trained;
    logic [NUM_LANES-1:0]       lane_error;
    
    // Lane Repair and Mapping
    logic [NUM_LANES-1:0]       lane_repair_disable;
    logic [NUM_LANES-1:0][7:0]  lane_mapping;           // Logical to physical mapping
    logic                       lane_reversal_enable;
    
    // Lane Quality Metrics
    logic [NUM_LANES-1:0][15:0] lane_ber_count;         // Bit error rate counter
    logic [NUM_LANES-1:0][7:0]  lane_eye_height;        // Eye diagram height
    logic [NUM_LANES-1:0][7:0]  lane_eye_width;         // Eye diagram width
    
    // ========================================================================
    // Thermal Management (128 Gbps Enhancement) 
    // ========================================================================
    
    // Temperature Sensors (64 sensors for fine-grained monitoring)
    logic [63:0][7:0]          thermal_sensor_data;
    logic [63:0]               thermal_sensor_valid;
    logic [7:0]                die_temperature_avg;
    
    // Thermal Control
    logic                      thermal_throttle_active;
    logic [1:0]                thermal_throttle_level;  // 0=None, 1=Light, 2=Medium, 3=Heavy
    logic [7:0]                thermal_zone_status;     // 8 thermal zones
    
    // ========================================================================
    // Link Training and State Machine
    // ========================================================================
    
    // Training State Control
    logic                       training_enable;
    logic [3:0]                 training_state;         // Current training state
    logic                       training_complete;
    logic                       training_error;
    
    // Training Pattern Control
    logic [1:0]                 training_pattern;       // Pattern selection
    logic                       pattern_lock;
    logic [NUM_LANES-1:0]       pattern_error;
    
    // Parameter Exchange
    logic [63:0]                local_parameters;
    logic [63:0]                remote_parameters;
    logic                       param_exchange_complete;
    
    // ========================================================================
    // Clock and Data Recovery (CDR)
    // ========================================================================
    
    logic [NUM_LANES-1:0]       cdr_lock;
    logic [NUM_LANES-1:0][7:0]  cdr_phase_offset;
    logic [NUM_LANES-1:0]       cdr_adapt_enable;
    
    // ========================================================================
    // Power Management (Multi-Domain Support)
    // ========================================================================
    
    // Power Domain Controls (128 Gbps Enhancement)
    logic                       power_domain_0v6_active; // High-speed domain
    logic                       power_domain_0v8_active; // Digital domain  
    logic                       power_domain_1v0_active; // Auxiliary domain
    
    // Lane Power States
    logic [NUM_LANES-1:0][1:0]  lane_power_state;       // Per-lane power state
    logic                       global_power_good;
    
    // Power Optimization
    logic                       adaptive_power_enable;
    logic [7:0]                 power_budget;           // Current power budget
    
    // ========================================================================
    // Advanced Features and ML Support
    // ========================================================================
    
    // ML-Enhanced Prediction Interface
    logic                      ml_prediction_enable;
    logic [7:0]                ml_signal_quality_pred;  // Predicted signal quality
    logic [7:0]                ml_lane_failure_prob;    // Lane failure probability
    logic                      ml_adaptation_request;
    
    // Signal Integrity Monitoring
    logic [NUM_LANES-1:0][15:0] signal_integrity_metric;
    logic [NUM_LANES-1:0]       signal_quality_alarm;
    
    // Crosstalk Cancellation
    logic [NUM_LANES-1:0]       xtalk_cancel_enable;
    logic [NUM_LANES-1:0][7:0]  xtalk_coefficients;
    
    // ========================================================================
    // Debug and Test Interface
    // ========================================================================
    
    // Test Pattern Generation
    logic                      test_pattern_enable;
    logic [2:0]                test_pattern_type;      // PRBS7, PRBS15, PRBS31, etc.
    logic [NUM_LANES-1:0]      test_pattern_error;
    
    // Loopback Modes
    logic                      near_end_loopback;
    logic                      far_end_loopback;
    logic [NUM_LANES-1:0]      lane_loopback_enable;
    
    // Debug Observability
    logic [31:0]               debug_bus;
    logic [7:0]                debug_select;

    // ========================================================================
    // Modport Definitions
    // ========================================================================
    
    modport controller (
        input  clk_app, clk_symbol, clk_quarter, clk_sideband, rst_n,
               rx_data_p, rx_data_n, rx_pam4_level,
               cdr_lock, cdr_phase_offset,
               remote_parameters, param_exchange_complete,
               thermal_sensor_data, thermal_sensor_valid,
               signal_integrity_metric, signal_quality_alarm,
               test_pattern_error, pattern_error,
               
        output tx_data_p, tx_data_n, tx_pam4_level, pam4_mode_en,
               dfe_coefficients, dfe_enable, dfe_adapt_enable,
               ffe_coefficients, ffe_enable, ffe_adapt_enable,
               ctle_gain, ctle_peak_freq,
               lane_enable, lane_repair_disable, lane_mapping,
               lane_reversal_enable,
               training_enable, training_pattern,
               local_parameters,
               power_domain_0v6_active, power_domain_0v8_active, power_domain_1v0_active,
               lane_power_state, adaptive_power_enable, power_budget,
               thermal_throttle_active, thermal_throttle_level,
               ml_prediction_enable, ml_adaptation_request,
               xtalk_cancel_enable, xtalk_coefficients,
               test_pattern_enable, test_pattern_type,
               near_end_loopback, far_end_loopback, lane_loopback_enable,
               debug_select,
               
        inout  lane_active, lane_trained, lane_error, lane_ber_count,
               lane_eye_height, lane_eye_width,
               training_state, training_complete, training_error,
               pattern_lock, cdr_adapt_enable,
               global_power_good, die_temperature_avg,
               thermal_zone_status, ml_signal_quality_pred,
               ml_lane_failure_prob, debug_bus
    );
    
    modport phy (
        input  clk_app, clk_symbol, clk_quarter, clk_sideband, rst_n,
               tx_data_p, tx_data_n, tx_pam4_level, pam4_mode_en,
               dfe_coefficients, dfe_enable, dfe_adapt_enable,
               ffe_coefficients, ffe_enable, ffe_adapt_enable,
               ctle_gain, ctle_peak_freq,
               lane_enable, lane_repair_disable, lane_mapping,
               lane_reversal_enable,
               training_enable, training_pattern,
               local_parameters,
               power_domain_0v6_active, power_domain_0v8_active, power_domain_1v0_active,
               lane_power_state, adaptive_power_enable, power_budget,
               thermal_throttle_active, thermal_throttle_level,
               ml_prediction_enable, ml_adaptation_request,
               xtalk_cancel_enable, xtalk_coefficients,
               test_pattern_enable, test_pattern_type,
               near_end_loopback, far_end_loopback, lane_loopback_enable,
               debug_select,
               
        output rx_data_p, rx_data_n, rx_pam4_level,
               lane_active, lane_trained, lane_error,
               lane_ber_count, lane_eye_height, lane_eye_width,
               cdr_lock, cdr_phase_offset, cdr_adapt_enable,
               training_state, training_complete, training_error,
               pattern_lock, pattern_error,
               remote_parameters, param_exchange_complete,
               global_power_good, die_temperature_avg,
               thermal_zone_status,
               thermal_sensor_data, thermal_sensor_valid,
               ml_signal_quality_pred, ml_lane_failure_prob,
               signal_integrity_metric, signal_quality_alarm,
               test_pattern_error, debug_bus
    );
    
    modport testbench (
        input  clk_app, clk_symbol, clk_quarter, clk_sideband, rst_n,
        inout  tx_data_p, tx_data_n, rx_data_p, rx_data_n,
               tx_pam4_level, rx_pam4_level, pam4_mode_en,
               dfe_coefficients, ffe_coefficients, ctle_gain,
               lane_enable, lane_active, lane_trained,
               training_enable, training_complete,
               power_domain_0v6_active, power_domain_0v8_active, power_domain_1v0_active,
               thermal_throttle_active, ml_prediction_enable,
               test_pattern_enable, near_end_loopback, far_end_loopback,
               debug_bus, debug_select
    );
    
    // ========================================================================
    // Interface Validation and Assertions
    // ========================================================================
    
    // Parameter validation
    initial begin
        assert (NUM_LANES inside {8, 16, 32, 64}) else
            $error("Invalid NUM_LANES: %0d. Must be 8, 16, 32, or 64", NUM_LANES);
        assert (MAX_SPEED_GBPS inside {4, 8, 12, 16, 24, 32, 64, 128}) else
            $error("Invalid MAX_SPEED_GBPS: %0d", MAX_SPEED_GBPS);
        assert (SIGNALING_MODE inside {"NRZ", "PAM4"}) else
            $error("Invalid SIGNALING_MODE: %s. Must be NRZ or PAM4", SIGNALING_MODE);
        
        // PAM4 required for >64 Gbps
        if (MAX_SPEED_GBPS > 64) begin
            assert (SIGNALING_MODE == "PAM4") else
                $error("PAM4 signaling required for speeds >64 Gbps");
        end
    end
    
    // Runtime assertions
    always @(posedge clk_app) begin
        if (rst_n) begin
            // Power domain consistency
            assert (!(power_domain_0v6_active && !power_domain_0v8_active)) else
                $error("0.6V domain cannot be active without 0.8V domain");
            
            // Thermal protection
            assert (!(die_temperature_avg > 8'd100 && !thermal_throttle_active)) else
                $warning("High temperature detected but thermal throttling not active");
                
            // Training consistency  
            assert (!(training_complete && training_error)) else
                $error("Training cannot be both complete and in error state");
        end
    end

endinterface
