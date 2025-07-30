interface ucie_phy_if #(
    parameter NUM_LANES = 64,
    parameter ENABLE_PAM4 = 1,
    parameter SIGNALING_MODE = "PAM4"
) (
    input logic clk,
    input logic resetn,
    input logic clk_symbol,        // Symbol rate clock
    input logic clk_quarter_rate   // Quarter-rate clock
);

    // Physical Lane Signals
    logic [NUM_LANES-1:0]       lane_tx_data;
    logic [NUM_LANES-1:0]       lane_rx_data;
    logic [NUM_LANES-1:0]       lane_tx_valid;
    logic [NUM_LANES-1:0]       lane_rx_valid;
    
    // PAM4 Symbol Interface (when enabled)
    logic [1:0]                 pam4_tx_symbols [NUM_LANES-1:0];
    logic [1:0]                 pam4_rx_symbols [NUM_LANES-1:0];
    logic [NUM_LANES-1:0]       pam4_tx_symbol_valid;
    logic [NUM_LANES-1:0]       pam4_rx_symbol_valid;
    
    // Physical Differential Signals
    logic [NUM_LANES-1:0]       phy_tx_p;
    logic [NUM_LANES-1:0]       phy_tx_n;
    logic [NUM_LANES-1:0]       phy_rx_p;
    logic [NUM_LANES-1:0]       phy_rx_n;
    
    // Lane Status and Control
    logic [NUM_LANES-1:0]       lane_enable;
    logic [NUM_LANES-1:0]       lane_status;
    logic [NUM_LANES-1:0]       lane_trained;
    logic [NUM_LANES-1:0]       lane_failed;
    
    // Equalization Control
    logic [5:0]                 dfe_tap_weights [NUM_LANES-1:0][31:0];
    logic [4:0]                 ffe_tap_weights [NUM_LANES-1:0][15:0];
    logic [NUM_LANES-1:0]       eq_adaptation_enable;
    logic [NUM_LANES-1:0]       eq_converged;
    
    // Thermal Management
    logic [7:0]                 die_temperature;
    logic [NUM_LANES-1:0]       thermal_throttle_req;
    logic [15:0]                power_consumption [NUM_LANES-1:0];
    logic [NUM_LANES-1:0]       thermal_alarm;
    
    // Link Training Control
    logic                       training_enable;
    logic [3:0]                 training_mode;
    logic                       training_complete;
    logic [7:0]                 training_status;
    
    // Sideband Interface
    logic                       sb_clk;
    logic [7:0]                 sb_data_tx;
    logic [7:0]                 sb_data_rx;
    logic                       sb_valid_tx;
    logic                       sb_valid_rx;
    logic                       sb_ready_tx;
    logic                       sb_ready_rx;

    modport controller (
        input  clk, resetn, clk_symbol, clk_quarter_rate,
        output lane_tx_data, lane_tx_valid, pam4_tx_symbols, pam4_tx_symbol_valid,
               phy_tx_p, phy_tx_n, lane_enable, dfe_tap_weights, ffe_tap_weights,
               eq_adaptation_enable, training_enable, training_mode,
               sb_clk, sb_data_tx, sb_valid_tx, sb_ready_rx,
        input  lane_rx_data, lane_rx_valid, pam4_rx_symbols, pam4_rx_symbol_valid,
               phy_rx_p, phy_rx_n, lane_status, lane_trained, lane_failed,
               eq_converged, die_temperature, thermal_alarm, power_consumption,
               training_complete, training_status, sb_data_rx, sb_valid_rx, sb_ready_tx
    );
    
    modport phy (
        input  clk, resetn, clk_symbol, clk_quarter_rate,
               lane_tx_data, lane_tx_valid, pam4_tx_symbols, pam4_tx_symbol_valid,
               lane_enable, dfe_tap_weights, ffe_tap_weights, eq_adaptation_enable,
               training_enable, training_mode, sb_clk, sb_data_tx, sb_valid_tx, sb_ready_rx,
        output phy_tx_p, phy_tx_n, lane_rx_data, lane_rx_valid, pam4_rx_symbols,
               pam4_rx_symbol_valid, phy_rx_p, phy_rx_n, lane_status, lane_trained,
               lane_failed, eq_converged, die_temperature, thermal_alarm,
               power_consumption, training_complete, training_status,
               sb_data_rx, sb_valid_rx, sb_ready_tx
    );

endinterface