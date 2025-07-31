interface ucie_rdi_if #(
    parameter DATA_WIDTH = 512,
    parameter USER_WIDTH = 16,
    parameter ENHANCED_128G = 1,  // Always enable 128 Gbps enhancements (per architecture)
    parameter PAM4_SUPPORT = 1    // Always enable PAM4 specific signals (per architecture)
) (
    input logic clk,
    input logic resetn,
    // Enhanced clocking for 128 Gbps (always present per architecture)
    input logic clk_quarter_rate,  // Quarter-rate clock for PAM4
    input logic clk_symbol,        // Symbol rate clock
    input logic resetn_sync        // Synchronized reset
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
    
    // Enhanced 128 Gbps signals (always present per architecture)
    // Multi-domain clock coordination
    logic                clk_domain_sync;
    logic [1:0]          clk_domain_sel;
    
    // Thermal throttling
    logic                thermal_throttle;
    logic [7:0]          temperature_status;
    
    // Advanced flow control
    logic [15:0]         advanced_credits;
    logic [7:0]          burst_length;
    
    // PAM4 specific signals (always present per architecture)
    logic [1:0]          pam4_symbol_align;
    logic                pam4_training_mode;
    logic [3:0]          pam4_eq_status;
    logic [7:0]          pam4_error_count;
    
    // ML-enhanced flow control (always present per architecture)
    logic                ml_prediction_valid;
    logic [7:0]          ml_bandwidth_predict;
    logic [3:0]          ml_latency_class;
    
    modport device (
        input  clk, resetn, clk_quarter_rate, clk_symbol, resetn_sync,
        output tx_valid, tx_data, tx_user, tx_sop, tx_eop, tx_empty,
               lp_wake_req, lp_clk_ack, lp_stallreq, lp_stallack,
               lp_state_req, lp_state_sts, rx_ready,
               clk_domain_sync, clk_domain_sel, thermal_throttle, temperature_status,
               advanced_credits, burst_length, pam4_symbol_align, pam4_training_mode,
               pam4_eq_status, pam4_error_count, ml_prediction_valid,
               ml_bandwidth_predict, ml_latency_class,
        input  tx_ready, rx_valid, rx_data, rx_user, rx_sop, rx_eop, rx_empty,
               pl_wake_ack, pl_clk_req, pl_stallreq, pl_stallack,
               pl_state_req, pl_state_sts, link_up, link_error, link_status
    );
    
    modport controller (
        input  clk, resetn, clk_quarter_rate, clk_symbol, resetn_sync,
               tx_valid, tx_data, tx_user, tx_sop, tx_eop, tx_empty,
               lp_wake_req, lp_clk_ack, lp_stallreq, lp_stallack,
               lp_state_req, lp_state_sts, rx_ready,
               clk_domain_sync, clk_domain_sel, thermal_throttle, temperature_status,
               advanced_credits, burst_length, pam4_symbol_align, pam4_training_mode,
               pam4_eq_status, pam4_error_count, ml_prediction_valid,
               ml_bandwidth_predict, ml_latency_class,
        output tx_ready, rx_valid, rx_data, rx_user, rx_sop, rx_eop, rx_empty,
               pl_wake_ack, pl_clk_req, pl_stallreq, pl_stallack,
               pl_state_req, pl_state_sts, link_up, link_error, link_status
    );
endinterface
