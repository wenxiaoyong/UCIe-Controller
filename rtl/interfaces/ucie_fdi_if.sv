interface ucie_fdi_if #(
    parameter FLIT_WIDTH = 256,
    parameter NUM_VCS = 8,
    parameter ENHANCED_128G = 1,      // Always enable 128 Gbps enhancements (per architecture)
    parameter ENABLE_ML_FLOW = 1,     // Always enable ML-enhanced flow control (per architecture)
    parameter ENABLE_PAM4 = 1         // Always enable PAM4 support (per architecture)
) (
    input logic clk,
    input logic resetn,
    // Enhanced clocking for 128 Gbps (always present per architecture)
    input logic clk_quarter_rate,     // Quarter-rate clock for PAM4
    input logic clk_symbol,           // Symbol rate clock  
    input logic resetn_sync           // Synchronized reset
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
    
    // Flit Cancel (256B mode only) - Enhanced Implementation
    logic                   pl_flit_cancel;
    logic                   pl_flit_cancel_ack;
    logic [7:0]             cancel_reason;
    logic [15:0]            cancel_sequence;
    
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
    
    // Quarter-Rate Processing Support (128 Gbps enhancement)
    logic                   quarter_rate_mode;
    logic [1:0]             quarter_rate_phase;
    logic [3:0]             parallel_lane_sel;
    
    // Zero-Latency Bypass Signals
    logic                   bypass_enable;
    logic                   bypass_valid;
    logic [FLIT_WIDTH-1:0]  bypass_data;
    logic                   bypass_ready;
    
    // Enhanced 128 Gbps signals (always present per architecture)
    // Multi-domain clock coordination
    logic                clk_domain_sync;
    logic [1:0]          clk_domain_sel;
    
    // Thermal throttling interface
    logic                thermal_throttle;
    logic [7:0]          temperature_status;
    
    // Advanced flow control with deeper buffers
    logic [15:0]         advanced_credits;
    logic [7:0]          burst_length;
    logic [3:0]          buffer_level_percent;
    
    // Power domain coordination
    logic [3:0]          power_domain_active;
    logic                low_power_mode;
    
    // ML-enhanced flow control (always present per architecture)
    logic                ml_flow_predict;
    logic [7:0]          ml_congestion_level;
    logic [3:0]          ml_priority_boost;
    logic [7:0]          ml_bandwidth_predict;
    logic [3:0]          ml_latency_class;
    
    // PAM4 specific signals (always present per architecture)
    logic [1:0]          pam4_symbol_align;
    logic                pam4_training_mode;
    logic [3:0]          pam4_eq_status;
    logic [7:0]          pam4_error_count;
    
    modport device (
        input  clk, resetn, clk_quarter_rate, clk_symbol, resetn_sync,
        output pl_flit_valid, pl_flit_data, pl_flit_sop, pl_flit_eop, pl_flit_be,
               pl_flit_cancel, pl_credit_return, lp_wake_req, lp_clk_ack,
               lp_rx_active_req, lp_flit_ready, quarter_rate_mode, quarter_rate_phase,
               parallel_lane_sel, bypass_enable, bypass_valid, bypass_data,
               cancel_reason, cancel_sequence, clk_domain_sync, clk_domain_sel,
               thermal_throttle, temperature_status, advanced_credits, burst_length,
               buffer_level_percent, power_domain_active, low_power_mode,
               ml_flow_predict, ml_congestion_level, ml_priority_boost,
               ml_bandwidth_predict, ml_latency_class, pam4_symbol_align,
               pam4_training_mode, pam4_eq_status, pam4_error_count,
        input  lp_flit_ready, lp_flit_valid, lp_flit_data, lp_flit_sop, lp_flit_eop,
               lp_flit_be, lp_credit_return, pl_wake_ack, pl_clk_req,
               pl_rx_active_sts, link_up, link_error, link_status, pl_flit_ready,
               bypass_ready, pl_flit_cancel_ack
    );
    
    modport controller (
        input  clk, resetn, clk_quarter_rate, clk_symbol, resetn_sync,
               pl_flit_valid, pl_flit_data, pl_flit_sop, pl_flit_eop, pl_flit_be,
               pl_flit_cancel, pl_credit_return, lp_wake_req, lp_clk_ack,
               lp_rx_active_req, lp_flit_ready, quarter_rate_mode, quarter_rate_phase,
               parallel_lane_sel, bypass_enable, bypass_valid, bypass_data,
               cancel_reason, cancel_sequence, clk_domain_sync, clk_domain_sel,
               thermal_throttle, temperature_status, advanced_credits, burst_length,
               buffer_level_percent, power_domain_active, low_power_mode,
               ml_flow_predict, ml_congestion_level, ml_priority_boost,
               ml_bandwidth_predict, ml_latency_class, pam4_symbol_align,
               pam4_training_mode, pam4_eq_status, pam4_error_count,
        output lp_flit_ready, lp_flit_valid, lp_flit_data, lp_flit_sop, lp_flit_eop,
               lp_flit_be, lp_credit_return, pl_wake_ack, pl_clk_req,
               pl_rx_active_sts, link_up, link_error, link_status, pl_flit_ready,
               bypass_ready, pl_flit_cancel_ack
    );
endinterface
